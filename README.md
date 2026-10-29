# SurvivorDown

An [Azeroth Survivors](https://discord.gg/azerothsurvivors) addon. When someone in your party goes down, it marks them and points you to them, so you can get there and revive them.

## What you see when a teammate goes down
- **Skull:** the skull raid icon over them, drawn by the game in the world.
- **Call-out:** "Name is down!" in their class colour in the middle of the screen, with the raid warning sound. "Name is back up" when they're revived.
- **List:** who's down and how far, in yards. While you're reviving someone it shows how far along you are. Click a name to target them. Room for a full party.
- **Arrows:** at the end of each row of the list, a gold arrow pointing at them. It hides once you're on top of them. With arrows off, or before the addon knows which way you face, the row says "25 yd NE" instead.
- **Minimap pin:** a pulsing skull on the minimap where they went down. Out of minimap range it sits on the rim, pointing their way.

## Positions
The game gives addons no world position for players, and instances have no map coordinates. So while you're down, SurvivorDown pings your own spot on the minimap every 3 s. The game keeps a ping fixed in the world and tells each teammate where it is from them, which gives the distance, the arrow and the minimap pin. Everyone in the party needs SurvivorDown for this. Without a ping (a teammate without the addon), it falls back to map coordinates, which only exist outside instances.

The game doesn't tell addons which way you're facing either. The arrows use the minimap's player arrow if this client lets an addon read it, and otherwise the way you last moved: right while you run toward something, wrong while you strafe or backpedal, and unchanged while you stand still.

## Settings
Click the minimap button or type `/asd` to open the settings. Each part above has a tickbox there, and every change shows at once. **Test** and **Status** run `/asd test` and `/asd status`. Settings are per character.

## Commands
- `/asd`: open or close the settings
- `/asd help`: list the commands and which parts are on
- `/asd alert`, `sound`, `minimap`, `skull`, `list`, `arrow`, `button`: turn that part on or off
- `/asd unlock` / `/asd lock`: move the list (or the Unlock list button in the settings)
- `/asd test`: a pretend teammate down where you stand for 30 s. Walk away and the arrow should keep pointing back. `/asd test 2` to `/asd test 5` adds more at fixed spots around it, to see a full party in the list.
- `/asd status`: what the addon can see: your party, positions, the zone's size, facing, the game's revive line
- `/asd debug`: show every down, ping and message in chat, to find where a position gets lost
- `/asd reset`: settings back to defaults

## Requirements
Your coop partners need to be in your WoW party. Check with `/asd status`.
