# Changelog

## 0.2.0
- **Settings window:** `/asb` or the new minimap button opens it. A tickbox for each part (call-out, sound, minimap pin, beam, friendly nameplates, skull, list, list lock, minimap button), plus Test and Status buttons.
- **Minimap button:** the skull icon. Click opens the settings; drag moves it around the minimap. `/asb button` shows or hides it.
- `/asb help` lists the commands (bare `/asb` now opens the settings).

## 0.1.1
- Fixed an error every 0.2 s while someone was down: the game has no `nameplateShowFriends` CVar. Friendly nameplates are still turned on while someone's down, and off after, since there's no way to tell if you had them on.
- `/asb status` shows more: whether each party member's nameplate is found, the raw map position, and the game's run, zone, lair and chest lines, to look for another source of positions.

## 0.1.0
- First version. When a party member goes down: a call-out with sound, a pulsing skull on the minimap where they went down, a beam and ground ring under their nameplate, the skull raid icon on them, and a list with distance and direction.
- The downed player's SurvivorBeacon sends its map position to the party; without it, the game's party position is used.
- Zone size for distances is measured from the run's lairs and chests.
- `/asb test` and `/asb status` for checking it in game.
