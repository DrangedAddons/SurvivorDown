# SurvivorBeacon

An [Azeroth Survivors](https://discord.gg/azerothsurvivors) addon. When someone in your party goes down, it marks where, so you can get there and revive them.

## What you see when a teammate goes down
- **Call-out:** "Name is down!" in their class colour in the middle of the screen, with the raid warning sound. "Name is back up" when they're revived.
- **Minimap pin:** a pulsing skull on the minimap where they went down. Out of minimap range it sits on the rim, pointing their way.
- **Beam:** a skull, a light beam and a pulsing ring on the ground under their nameplate. Friendly nameplates are turned on while someone's down (and off again after) so there's a plate to hang it on.
- **Skull icon:** the skull raid icon on whoever is down.
- **List:** who's down, how far and which way ("48 yd NE"). While you're reviving someone it shows how far along you are. Click a name to target them.

The game has no way for an addon to draw at a spot in the world, so the beam needs the teammate's nameplate to be on screen. The minimap pin and the list work at any distance.

## Positions
The game gives addons no world position for players, and instances have no map coordinates. So while you're down, SurvivorBeacon pings your own spot on the minimap every 3 s. The game keeps a ping fixed in the world and tells each teammate where it is from them, which gives the list's distance and the minimap pin. Everyone in the party needs SurvivorBeacon for this.

Without a ping (a teammate without the addon), it falls back to map coordinates, which only exist outside instances. The beam hangs off the nameplate, so it moves when the game moves the plate; the distance and pin don't use the nameplate.

## Settings
Click the minimap button or type `/asb` to open the settings. Each part above has a tickbox there, and every change shows at once. **Test** and **Status** run `/asb test` and `/asb status`.

## Commands
- `/asb`: open or close the settings
- `/asb help`: list the commands and which parts are on
- `/asb alert`, `sound`, `minimap`, `plate`, `friendplates`, `skull`, `list`, `button`: turn that part on or off
- `/asb unlock` / `/asb lock`: move the list (or the Unlock list button in the settings)
- `/asb test`: a pretend teammate down where you stand for 30 s, placed by a ping. Walk away to check it stays put. With a target, it uses the target's name, so the beam shows on the target's plate.
- `/asb status`: what the addon can see: your party, positions, the zone's size, the game's revive line
- `/asb debug`: show every down, ping and message in chat, to find where a position gets lost
- `/asb reset`: settings back to defaults

Settings are per character.

## Requirements
Your coop partners need to be in your WoW party. Check with `/asb status`.
