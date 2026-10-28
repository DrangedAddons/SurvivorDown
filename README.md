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
The best position comes from the downed player's own SurvivorBeacon, which sends it to the party while they're down. So it works best when the whole party has it. Without it, SurvivorBeacon uses the game's party position for that player, if the game provides one.

Distances need the zone's size in yards. SurvivorBeacon measures it from the run's guardian lairs and chests and remembers it per zone. Until then it uses the 1.12 map size for a few starting zones, or shows only a direction.

## Settings
Click the minimap button or type `/asb` to open the settings. Each part above has a tickbox there, and every change shows at once. **Test** and **Status** run `/asb test` and `/asb status`.

## Commands
- `/asb`: open or close the settings
- `/asb help`: list the commands and which parts are on
- `/asb alert`, `sound`, `minimap`, `plate`, `friendplates`, `skull`, `list`, `button`: turn that part on or off
- `/asb unlock` / `/asb lock`: move the list
- `/asb test`: a pretend teammate down 40 yd north-east of you for 20 s. With a target, it uses the target's name, so the beam shows on the target's plate.
- `/asb status`: what the addon can see: your party, positions, the zone's size, the game's revive line
- `/asb reset`: settings back to defaults

Settings are per character.

## Requirements
Your coop partners need to be in your WoW party. Check with `/asb status`.
