"""BLP2 DXT3 decode/encode, enough for UI-RaidTargetingIcons."""
import struct
import numpy as np


def rgb565(c):
    return np.array([((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31], dtype=np.float32)


def decode(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'BLP2'
    _, enc, adepth, atype, mips, w, h = struct.unpack('<IBBBBII', d[4:20])
    assert enc == 2 and atype == 1, (enc, atype)
    off, size = struct.unpack('<I', d[20:24])[0], struct.unpack('<I', d[84:88])[0]
    data = d[off:off + size]
    img = np.zeros((h, w, 4), dtype=np.uint8)
    k = 0
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            blk = data[k:k + 16]
            k += 16
            a = int.from_bytes(blk[:8], 'little')
            c0, c1, idx = struct.unpack('<HHI', blk[8:16])
            p0, p1 = rgb565(c0), rgb565(c1)
            pal = [p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3]
            for i in range(16):
                y, x = by + i // 4, bx + i % 4
                img[y, x, :3] = pal[(idx >> (2 * i)) & 3]
                img[y, x, 3] = ((a >> (4 * i)) & 15) * 17
    return img


def to565(c):
    r, g, b = [int(round(v)) for v in c]
    return ((r * 31 + 127) // 255 << 11) | ((g * 63 + 127) // 255 << 5) | ((b * 31 + 127) // 255)


def encode_block(px):
    """px: (16,4) uint8 RGBA -> 16 bytes DXT3."""
    a = 0
    for i in range(16):
        a |= (int(px[i, 3]) * 15 + 127) // 255 << (4 * i)
    rgb = px[:, :3].astype(np.float32)
    # weight colour fit by alpha so invisible texels don't pull endpoints
    w = px[:, 3].astype(np.float32) / 255 + 0.01
    mean = (rgb * w[:, None]).sum(0) / w.sum()
    cen = rgb - mean
    cov = (cen * w[:, None]).T @ cen
    axis = np.linalg.eigh(cov)[1][:, -1]
    t = cen @ axis
    lo, hi = mean + axis * t.min(), mean + axis * t.max()
    c0, c1 = to565(np.clip(hi, 0, 255)), to565(np.clip(lo, 0, 255))
    if c0 < c1:
        c0, c1 = c1, c0
    p0, p1 = rgb565(c0), rgb565(c1)
    pal = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3])
    if c0 == c1:
        idx = 0
    else:
        dist = ((rgb[:, None, :] - pal[None]) ** 2).sum(-1)
        sel = dist.argmin(1)
        idx = 0
        for i in range(16):
            idx |= int(sel[i]) << (2 * i)
    return a.to_bytes(8, 'little') + struct.pack('<HHI', c0, c1, idx)


def encode_level(img):
    h, w = img.shape[:2]
    if h < 4 or w < 4:
        pad = np.zeros((max(h, 4), max(w, 4), 4), dtype=np.uint8)
        pad[:h, :w] = img
        img = pad
        h, w = 4, 4
    out = bytearray()
    for by in range(0, h, 4):
        for bx in range(0, w, 4):
            out += encode_block(img[by:by + 4, bx:bx + 4].reshape(16, 4))
    return bytes(out)


def downsample(img):
    f = img.astype(np.float32)
    a = f[..., 3:4] / 255
    pm = np.concatenate([f[..., :3] * a, f[..., 3:4]], -1)
    h, w = img.shape[:2]
    pm = pm.reshape(h // 2, 2, w // 2, 2, 4).mean((1, 3))
    al = pm[..., 3:4]
    rgb = np.where(al > 0, pm[..., :3] / np.maximum(al / 255, 1e-6), 0)
    return np.clip(np.concatenate([rgb, al], -1) + 0.5, 0, 255).astype(np.uint8)


def write(path, img):
    h, w = img.shape[:2]
    levels = [img]
    while levels[-1].shape[0] > 1:
        levels.append(downsample(levels[-1]))
    blobs = [encode_level(l) for l in levels]
    offs, sizes = [0] * 16, [0] * 16
    pos = 148 + 1024
    for i, b in enumerate(blobs):
        offs[i], sizes[i] = pos, len(b)
        pos += len(b)
    hdr = b'BLP2' + struct.pack('<IBBBBII', 1, 2, 8, 1, 1, w, h)
    hdr += struct.pack('<16I', *offs) + struct.pack('<16I', *sizes) + bytes(1024)
    open(path, 'wb').write(hdr + b''.join(blobs))
