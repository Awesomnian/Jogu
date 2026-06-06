# 🐟 Jogu Knows

Jogu Knows is a World of Warcraft addon for Mists of Pandaria Classic. It tells you which crop to plant today for a bonus harvest tomorrow at your Sunsong Ranch, and it tracks your daily status for profession cooldowns, farming activity, as well as weekly world-boss kills across all of your characters.

Available from your addon manager: [Wago](https://addons.wago.io/addons/jogu) or [CurseForge](https://www.curseforge.com/wow/addons/jogu-knows). Type `/jogu` in game to open the window.

## Purpose

Jogu the Drunk is an NPC who used to tell you what to plant today for bonus crops tomorrow. His predictions stopped working for most of Mists of Pandaria Classic, and he has been quietly forced into rehab. We are still able to get messages from him, and this addon shares them.

As his (surprisingly non-fatal) blood-alcohol level has dropped, his prescience has grown. He can now tell which of your characters have done their farming each day, which have completed their Ironpaw daily, which have used their daily profession craft, and which have defeated each weekly world boss.

## What it does

A single combined window shows the 10-day crop rotation as a wheel on the left and a per-character roster on the right. Today's bonus crop carries a soft golden glow, and the roster covers every character that has farmed at least once.

- Predicts tomorrow's bonus crop, with a countdown to the daily reset and an optional login message (off by default).
- Calibrates the cycle per region, by hand or automatically, for any region that ever sits at a different point in the rotation. NA and OCE share a verified default; other regions fall back to it unless calibrated.
- Tracks per character on the right of the window: daily profession cooldowns, crop harvesting, the Ironpaw Token daily, and weekly world boss lockouts (Nalak, Oondasta, Celestial Court, Ordos).
- Shows Nomi's Cooking School Bell status on the left of the window, with a clickable bell to summon them if your character has this in their inventory.
- Updates live as you play. Harvesting a crop, turning in the Ironpaw daily, killing a world boss, or casting a tracked profession daily refreshes the relevant icon immediately.
- Adds a character to the roster only when they perform a qualifying farm action (harvest crops or complete the Ironpaw daily). Logging in alone does not add an alt; this keeps the roster to characters who actually farm.
- Uses the real in-game item tooltip for each crop, so tooltip addons such as Auctionator and TradeSkillMaster enrich them as usual.

## How to install it

The simplest way is an addon manager. Search for "Jogu Knows" in the Wago app or the CurseForge app and install from there.

To install manually:

1. Download the packaged addon from the Releases page on GitHub, or from Wago or CurseForge.
2. Extract the archive. The folder inside must be named exactly `Jogu`. If you used GitHub's "Download ZIP" button, rename the extracted `Jogu-main` folder to `Jogu`.
3. Move the `Jogu` folder into `World of Warcraft\_classic_\Interface\AddOns\`.
4. Restart World of Warcraft, or type `/reload` if it is already running.

## How to use it

1. Type `/jogu` to open the window.
2. Plant the highlighted crop today to get the bonus tomorrow. The "Plant [Crop] today!" line names it.
3. If the highlighted crop is wrong for your server, click the `?` button and select the crop that was today's bonus. This calibration is saved per region and is used from then on; it also overrides the default for every other realm in that same region. The addon will check for bonus crops out-of-cycle and will automatically update the cycle if it is wrong, such as when Blizzard changed the cycle positioning in early May.
4. Optionally tick "Show prediction on login" to receive the prediction as a chat message at login.
5. Optionally also tick "Specific crops" and click the `?` next to it to pick only the crops you want a login message about. Useful if you only care about the high-value ones.
6. Optionally tick "Hide world bosses" to narrow the window to just the daily columns (cooldowns, harvesting, Ironpaw).
7. Optionally untick "Characters align top" to vertically centre the roster on the crop wheel instead of pinning it to the top.
8. If you have characters on other realms, they will be displayed with a -[XX] suffix, with the first 2 characters of that realm name. Characters on the majority realm will not have a suffix, if you have an even spread of characters across realms, all will have the suffi

All settings save across every character on your account.

## Crop yields

| Condition | Yield |
|---|---|
| Normal harvest | 5 crops |
| Bonus day | 7 crops (plus 2) |
| Plump proc | 8 crops (plus 3) |
| Bonus day and Plump | 10 crops (plus 5) |

A 7 or 10 stack of any crop is the signature of a bonus harvest. The addon uses this to auto-calibrate the cycle if its prediction was wrong.

## Caveats and limitations

Tracking for other characters reflects the last time each one logged in with the addon enabled. A character you have not played recently shows its last known state, not live data.

- Profession cooldown tracking covers Alchemy, Tailoring, Inscription, Blacksmithing, Engineering, and Leatherworking. The character must know the specific daily-cooldown recipe; if it does not, that slot stays greyed. Jewelcrafting has no tracked daily cooldown. Engineering get a daily cooldown with the release of Siege of Orgrimmar, [Jard's Peculiar Energy Source](https://www.wowhead.com/mop-classic/spell=139176/jards-peculiar-energy-source)
- Harvest, Farm Token, and Nomi status are recorded when the action happens while the addon is loaded. They persist across sessions, but something you did before the addon first loaded that day may not be detected until you do it again.
- A character only joins the roster after their first qualifying farm action (harvest or Ironpaw daily). If you remove a character from the roster, the next harvest or Ironpaw turn-in re-adds them with their professions and any world boss kills already on file.


## Requirements

- World of Warcraft: Mists of Pandaria Classic (interface 50400).
- No other addons are required. Auctionator or TradeSkillMaster are optional and only enrich the crop tooltips if you have them.



## Technical details

<details>

<summary>Rotation, timing, cycle anchor, storage, and detection</summary>

**10-day rotation, in order:** Witchberries (74846), Jade Squash (74847), Striped Melon (74848), Green Cabbage (74840), Juicycrunch Carrot (74841), Scallions (74843), Mogu Pumpkin (74842), Red Blossom Leek (74844), Pink Turnip (74849), White Turnip (74850).

**Timing:** Daily reset times are region-aware and fixed in UTC with no DST adjustment: NA and OCE at 15:00, Europe at 07:00, Korea, Taiwan, and China at 00:00. The region is detected via `GetCurrentRegion()`, and `GetServerTime()` provides UTC time.

**Cycle anchor:** Every region uses the same default starting point (`DEFAULT_CYCLE_ANCHOR`), set to the verified Arugal-AU and Pagle position. The crop order itself has never changed; only the position relative to the calendar shifts when Blizzard moves it (uncertain frequency, happened early May and was caught by server calibration logic). When a shift happens, the default anchor and a `CYCLE_VERSION` integer are bumped in source; any previously stored calibration whose `cycleVersion` no longer matches is discarded silently on load, so the new default takes over for everyone. A region's calibration only overrides the default for that one region.

**Data storage (SavedVariables `JoguDB`):** regional calibration overrides in `JoguDB.regionCalibration[regionID]`, each entry stamped with the `cycleVersion` it was saved under; per-character data in `JoguDB.characters["RealmName-CharacterName"]`, including harvest, Ironpaw, and Nomi epochs, level, class, weekly world boss kill weeks, and primary professions with daily cooldown expiry times; first-kill reveal flags for future-content bosses in `JoguDB.bossEverKilled[questID]`; the set of message-filter crop indices in `JoguDB.selectedCrops`; and the `showLoginMessage`, `onlySelectedCrops`, `alignTop`, and `hideWorldBosses` preferences.

**Detection:** At Sunsong Ranch, loot of 5 to 10 core crops (or any quantity of edge seeds) marks a harvest. Loot lines that arrive in the same frame are summed first, so a Plump harvest that splits across inventory stacks (for example 8 arriving as 1 then 7) is read as the real total and does not falsely trigger calibration. A genuine total of 7 or 10 still auto-corrects the cycle position if the current prediction is wrong, writing the override to the region's calibration entry so every realm in that region benefits. Master Token dailies (30328 to 30332) mark the Farm Token, and any tracked Nomi cooking daily (31820 and 31332 to 31337) marks Nomi for that character. World boss kills are read with `C_QuestLog.IsQuestFlaggedCompleted()` and refreshed both on login and live as each weekly-credit quest auto-turns-in (this is a backend thing, not an actual in-game quest handin), so the icon flips full-colour the instant the boss dies. Profession cooldowns are read with `GetProfessions()`, `GetProfessionInfo()`, and `GetSpellCooldown()`, refreshed on login and the moment a tracked daily craft succeeds.

</details>

Version 1.1.0, May 2026.
