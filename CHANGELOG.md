# Changelog

## 0.4.1
- The arrows are twice the size.

## 0.4.0
- **Arrows:** each row of the list gets an arrow just outside its right edge, in the downed teammate's class colour, pointing at them. It hides once you're within 4 yd. `/asb arrow` or the new tickbox turns them off.
- The game gives addons no facing, so the arrow takes it from the minimap's player arrow if this client lets an addon read it, and otherwise from the way you last moved. On movement it's right while you run forward, wrong while you strafe or backpedal, and holds while you stand still.
- With more than one teammate down, only the latest ping can be read live. The others' distances used to stay where they were until their next ping (every 3 s); they now follow how you've moved since.
- `/asb status` shows where facing comes from.

## 0.3.1
- `/asb debug`: shows each step in chat. On the downed player's side: going down (and why), each ping and each message sent. On everyone else's: each minimap ping (with what the game reports) and each message heard.
- A ping whose sender the game doesn't name is now taken as the downed teammate's, when exactly one teammate's SurvivorBeacon says they're down.
- The list says which link is missing instead of "position unknown": "nothing from their addon" (no message from their SurvivorBeacon) or "no ping yet" (its message arrived, its ping didn't).

## 0.3.0
- **Positions from minimap pings.** While you're down, SurvivorBeacon pings your own spot on the minimap every 3 s. The game keeps a ping fixed in the world and reports where it is from each teammate, so their list distance and minimap pin follow that spot as they move. This works in instances, which have no map coordinates. Map coordinates are still used where there's no ping.
- With two people down at once only the latest ping can be read live; the other's distance updates each time they ping (every 3 s).
- **Unlock list** button in the settings, in place of the lock tickbox.
- `/asb test` now puts the pretend teammate where you stand, placed by a ping, for 30 s. Walk away to check it stays put. The ping shows on your party's minimaps too.
- `/asb status` shows the raw ping position and who pinged last.

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
