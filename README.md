# ImprovedRaidFrames

WoW 3.3.5a addon which replaces and improves upon both **Enhanced Raid Frames** and **Compact Raid Frames: Heal Extension** (CompactRaidFrame_HealEx).

Improved Raid Frames builds on the **Compact Raid Frames** backport of the retail raid frames. It adds configurable aura indicators, heal prediction and absorb shields, a right-click menu that no longer causes "action blocked" errors, Ctrl-click focus, and a set of performance improvements that matter most in 25 and 40-player raids.

> **Status:** early version (0.x). Tested against Compact Raid Frames 1.14 and !!!ClassicAPI 1.32.

## Requirements

- World of Warcraft 3.3.5a (Wrath of the Lich King) client
- [Compact Raid Frames](#credits) (`CompactRaidFrame`) by Tsoukie
- [!!!ClassicAPI](#credits) by Tsoukie
- Optional: the [mod-playerbot-heal-tracker](https://github.com/EvilTactician/mod-playerbot-heal-tracker) AzerothCore server module, to show the heals of playerbots (only for servers running mod-playerbots)

## Installation

1. Download the repository (green **Code** button → **Download ZIP**).
2. Extract it into `World of Warcraft\Interface\AddOns\`.
3. Rename the folder to exactly **`ImprovedRaidFrames`** (GitHub adds `-main` to the name). The folder name must match `ImprovedRaidFrames.toc`.
4. Make sure Compact Raid Frames and !!!ClassicAPI are installed and enabled.

### Moving over from Enhanced Raid Frames and Heal Extension

Improved Raid Frames uses the same settings layout as Enhanced Raid Frames, so your indicator setup carries over:

1. Install Improved Raid Frames and log in **with Enhanced Raid Frames still enabled**.
2. Improved Raid Frames offers to copy all your Enhanced Raid Frames profiles (including which character uses which profile and your dual-spec profile settings). Accept, and reload the UI when asked. You can also do this later with the **Copy Enhanced Raid Frames Settings** button on the Improved Raid Frames options page.
3. Disable **Enhanced Raid Frames** and **Compact Raid Frames: Heal Extension**, and reload.

Profile strings exported from Enhanced Raid Frames (Profile Import/Export) can also be imported directly.

While either of those addons is still enabled, Improved Raid Frames leaves their features to them so nothing runs twice, and tells you so at login.

Settings are saved per account in `WTF\Account\<ACCOUNT>\SavedVariables\ImprovedRaidFrames.lua`, not in the addon folder.

## Features

### Right-click menu and focus

Compact Raid Frames opened Blizzard's shared unit menu from addon code. That taints Blizzard's menu code, so after the raid frames had been shown, **Set Focus** could be blocked anywhere in the UI ("CompactRaidFrame has been blocked from an action only available to the Blizzard UI"). Improved Raid Frames gives the raid frames their own menu, built on !!!ClassicAPI's separate dropdown code, so Blizzard's menus are never touched.

- **Ctrl-left-click** a raid frame to set your focus to that unit, in or out of combat.
- The menu's **Set Focus** line works out of combat. In combat the game doesn't allow addons to show secure buttons, so the line is greyed out with a reminder to use Ctrl-click.
- **Main Tank** and **Main Assist** can be set from the menu (raids only, for the leader and assistants). Compact Raid Frames used Blizzard's raid member menu, which doesn't have them.
- The menu also has: whisper, inspect, achievements, trade, follow, raid target icons, promote to leader/assistant, demote, master looter, uninvite/remove from raid, and for yourself loot method, loot threshold, convert to raid/party and leave party.
- Raid frames are registered with **Clique** (`ClickCastFrames`) for players who use it.

### Aura indicators (from Enhanced Raid Frames)

All Enhanced Raid Frames features are kept: 9 indicator positions per frame, tracking by aura name, spell ID, debuff type (`magic`, `curse`, `poison`, `disease`) or the `dispel` wildcard; icon or colour display, countdown text, stack size, cooldown swipe, glow, colours by time remaining or debuff type, "mine only", "missing only", tooltips; target markers; stock buff/debuff/dispellable icon toggles; range fade with an optional custom range; background opacity; frame scale; profiles with dual-spec switching, and profile import/export.

Fixed compared to Enhanced Raid Frames:

- The **`dispel`** wildcard works again. It relied on LibDispel, which the 3.3.5a backport doesn't have, so it never matched. Improved Raid Frames checks your spellbook (and your Felhunter's) for dispel spells instead.
- **Mine only** for indicators had an operator precedence bug.
- A watched spell ID could match part of a longer ID (774 also matched 17740).
- Changing an indicator's aura list now shows straight away, instead of at the next buff change.
- Importing a profile no longer re-creates the settings database, which used to stop profile switching from refreshing the frames.

### Heal prediction (from Compact Raid Frames: Heal Extension)

- **Incoming heals** (LibHealComm-4.0), optionally including the next few seconds of heals over time.
- **Absorb shields** (SpecializedAbsorbs-1.0).
- **Heal absorbs** such as Necrotic Strike and Incinerate Flesh (new: the library tracked them, but nothing displayed them).
- Each of these can be turned on or off under **Heal Prediction** in the options. The Heal Extension had no options.
- Fixed: frames now refresh when a healing modifier changes (e.g. Mortal Strike) or a unit disappears.

Other players' heals only show if they run an addon that shares them through LibHealComm-4.0. Shield sizes from other players are estimates.

### Playerbot heals

Playerbots don't run addons, so their heals never show as incoming heals. With the [mod-playerbot-heal-tracker](https://github.com/EvilTactician/mod-playerbot-heal-tracker) server module installed, the server sends them on the bots' behalf, in the standard LibHealComm-4.0 format, so any addon using LibHealComm-4.0 shows them.

Turn on **Show Playerbot Heals** under **Heal Prediction**. The options page shows whether the server module was detected. The option only works on servers that run mod-playerbots together with that module; on any other server, leave it off.

### Performance

These improvements are always on.

- **Unit events go only to the frame that needs them.** Compact Raid Frames registered every unit event (health, power, auras, threat, ...) on every frame, and each frame then checked whether the event was for its own unit: in a 40-player raid with pets, up to 80 handler calls per event. Improved Raid Frames delivers each event only to the frame(s) showing that unit.
- **No more permanent per-frame OnUpdate.** Compact Raid Frames kept an OnUpdate script running on every frame on every rendered frame (to check range every 0.5 seconds, and because of a bug that never removed the script). One shared timer now does the range checks.
- **One range check instead of two.** Enhanced Raid Frames ran its range check after Compact Raid Frames' own.
- **No duplicate aura scanning.** Enhanced Raid Frames scanned every aura change separately from Compact Raid Frames and created new tables for every aura each time. Improved Raid Frames scans right after Compact Raid Frames, reuses its tables, and skips the scan entirely when no indicator watches anything.
- **Stock icons that are turned off aren't scanned at all.** Enhanced Raid Frames only hid them after Compact Raid Frames had scanned them.
- **One indicator timer** instead of a separate repeating timer for every active indicator.
- **One heal prediction dispatcher.** The Heal Extension registered 13 library callbacks on every frame, so every heal or shield update called up to 80 handlers. Improved Raid Frames registers them once and finds the frame by GUID.

## Options

Type **`/irf`**, or open **Interface → AddOns → Improved Raid Frames**. Sections: General, Indicator Options, Target Marker Options, Heal Prediction, Profiles, and Profile Import/Export. The **Open the Blizzard Raid Profiles Options** button opens Compact Raid Frames' own settings.

## Credits

Improved Raid Frames builds on the work of others, who deserve the credit:

- **Enhanced Raid Frames** by Britt W. Yazel (MIT licence), backported to 3.3.5a by Tsoukie. The aura indicators, target markers, options and much of the code come from it.
- **Compact Raid Frames** (Blizzard's raid frames, backported to 3.3.5a) and **!!!ClassicAPI** by Tsoukie.
- **Compact Raid Frames: Heal Extension** by Tsoukie, whose heal prediction this replaces.
- Libraries, each under its own licence: Ace3, LibSharedMedia-3.0, AceGUI-3.0-SharedMediaWidgets, LibDeflate, LibDualSpec-1.0, LibRangeCheck-3.0, LibHealComm-4.0 (Shadowed, xbeeps, Azilroka, Tsoukie) and SpecializedAbsorbs-1.0.

## Licence

MIT, see [LICENSE](LICENSE). The libraries in `Libs` are distributed under their own licences.
