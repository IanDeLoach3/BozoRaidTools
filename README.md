# BozoRaidTools

A raid management addon for a single officer running raids for the guild **Bozo**, built for WoW Classic Era (1.15.x) and WoW Forever (interface 16001).

## Features

- **Attendance.** Start and end raid sessions, track who attended, and see per-player totals.
- **Group roster.** Lists your current party or raid with guild rank and notes from the guild roster, plus a gear inspect window showing each item's icon and level.
- **Loot log.** Logs loot from real loot and trade events while a raid session is active, with the Need/Greed/Pass breakdown for each item.
- **Targeted rolls.** Load an item, see which group members' classes can use it, announce the roll in raid chat, track the native `/roll` results, and declare the winner. It can open a trade with the winner when they are in range.
- **Prep check.** Pre-pull readiness check.
- **Post-raid summary.** A Discord-ready summary of the raid, attendance, and loot.
- **Export / import.** CSV export and import so records can be shared between officers.

## Commands

`/brt` opens the window. `/brt testloot` fills the loot log with real items from your bags for testing, and `/brt cleartestloot` clears it.

## Install

Copy the `BozoRaidTools` folder into your `Interface/AddOns/` directory.

## Notes

Saved data depends on SavedVariables, which currently have reliability bugs on the Forever beta. Use the export buttons to keep a copy of important records.

## License

Copyright (c) 2026 Ian DeLoach. All rights reserved. See `LICENSE.txt`.
