# 🐟 Jogu Knows

**Author:** Awesomnia
**GitHub:** https://github.com/awesomnian
**Version:** 1.0
**Addon location:**
Either right-click and save-as the TOC and LUA files into the below folder (or wherever your MoP Classic folder lives) or right-click and save-as the .zip file and extract it to that folder.
```
C:\Program Files (x86)\World of Warcraft\_classic_\Interface\AddOns\Jogu
```
Once this is all working well and some final functionality is confirmed/completed, this will be available for addon managers.

---

## Purpose

Jogu the Drunk is an NPC in World of Warcraft who would tell you what to plant today for bonus crops tomorrow. His predictions have not worked for most of Mists of Pandaria Classic and he’s been recently forced into rehab. We’re still able to get messages from him which are shared via this addon.

As his surprisingly un-fatal blood-alcohol level has dropped, his prescience has grown exponentially and he can now tell which characters have defeated world bosses each week!

Type /jogu to open interface.

It’s lightweight, at around 100kb as of v1.0.

---

## TL;DR

- A message on login telling you what the bonus for tomorrow is - default to off.
- Where in the cycle your current server is and ability to manually update this if it’s not correct, this will be remembered and predictions will be accurate from then on.
- Added smart detection for servers that may be at a different part of the cycle, the addon will calibrate automatically if your cycle is of a different timing from NA servers whenever a bonus crop is harvested. If you know what today’s bonus crop is, you can manually update it if it’s incorrect. If you don’t, plant one of everything and it’ll detect and update the cycle the next day.
- “Did I do my farm today on X?” - smart tracking for any alts that perform farming activities if they have the Addon enabled. Specifically, harvesting crops or doing the Ironpaw Token daily quest from Halfhill Market which is given by a different Master each day.
- Uses in-game tooltip for each of the crops so any addons like TSM or Auctionator that enrich tooltips and show things like which alts have how many items will work.
- Nomi’s Cooking Bell status/different interface if a character has this in their bags.

---

## Current Functionality

### Visual Crop Cycle Display
- Shows all 10 crops in a circular arrangement
- Hovering over any crop shows the in-game item tooltip (enriched with Auctionator/TradeSkillMaster data if installed)
- Tomorrow's bonus crop is highlighted with a gold outer border and outline font

### Tomorrow's Bonus Prediction
- Highlights which crop to plant today for bonus yield tomorrow
- "Plant [Crop] today!" message displayed prominently
- Shows time remaining until crops ripen (15:00 UTC daily reset)

### Realm Calibration ("?" Button)
- Different servers may have different points in the 10-day cycle
- Default calculation is calibrated for the NA/OCE region (verified identical on Arugal and Pagle)
- "?" button (left side near prediction text) allows users in other regions to calibrate
- Clicking enters calibration mode: UI fades except crop wheel and prompt
- User clicks whichever crop was TODAY's bonus on their server
- Calibration saved per-realm in SavedVariables
- All characters on that realm will use the calibrated cycle going forward

### Optional Login Message
- Configurable checkbox to toggle login notifications (default off)
- When enabled, displays mouseable/clickable item link on login: `[Jogu Knows] Plant [Scallions] today for bonus crops tomorrow!`
- When an alt logs in with the Addon enabled, their current kill-status on world bosses will be updated and stored. This can be checked by clicking the "Jogu Knows More" button in the interface.
- When a new World Boss is killed for the first time they will be activated and the current kill-status will be shown for all of your alts.

### Cooking School Bell / Nomi Integration
- Detects if character has Cooking School Bell (item 86425) in inventory
- If present, shows whether Nomi's daily quest (A Token of Appreciation, quest 31337) has been completed that day
- Bell icon is clickable to summon Nomi directly from the Jogu window
- Green text if quest completed: "You have received Nomi's gift today."
- Red text if quest not done: "You have not received your gift from Nomi today."
- Section hidden entirely if character doesn't have the bell

### Alt Farm Report (integrated right panel)
- Alt tracking is displayed in the right half of the main window
- **Automatic Registration:** Characters auto-register when they harvest crops or complete Master Token dailies
- **Harvest Tracking:** Detects crop harvesting at Sunsong Ranch (5-10 core crops OR edge item seeds)
- **Master Token Dailies:** Tracks completion of 5 Master Token quests (level 90 only):
  - Truffle Shuffle (30330)
  - Mile High Grub (30331)
  - Fatty Goatsteak (30332)
  - Thousand Year Dumpling (30328)
  - Cindergut Peppers (30329)
- **Manual Toggles:** Click status icons (green check/red X) to manually mark completion
- **Smart Sorting:** Priority-based (both incomplete → farm incomplete → quest incomplete → both complete), then alphabetical
- **Character Management:** Delete button (X) removes characters from tracking
- **Class Coloring:** Character names use class colors for easy identification

### Window Behavior
- `/jogu` slash command toggles the prediction window
- Draggable window - can be repositioned anywhere on screen
- Uses UIPanelLayout for profession-like window management (aligns with Spellbook, Professions, etc.)
- Pressing ESC closes the window
- Dynamic height adjustment based on Cooking School Bell presence
- "?" calibration button aligned left with prediction text
- "Jogu Knows More >" button opens world boss lockout panel

---

## Crop Bonus System

| Condition | Yield |
|-----------|-------|
| Normal harvest | 5 crops |
| Bonus day | 7 crops (+2) |
| "Plump" proc | 8 crops (+3) |
| Bonus day + Plump | 10 crops (+5) |

---

## Technical Details

### 10-Day Rotation Cycle (in order):
1. Witchberries (74846)
2. Jade Squash (74847)
3. Striped Melon (74848)
4. Green Cabbage (74840)
5. Juicycrunch Carrot (74841)
6. Scallions (74843)
7. Mogu Pumpkin (74842)
8. Red Blossom Leek (74844)
9. Pink Turnip (74849)
10. White Turnip (74850)

### Timing:
- Region-aware daily reset times (fixed UTC, no DST adjustment):
  - NA/OCE: 15:00 UTC
  - Europe: 07:00 UTC
  - Korea/Taiwan/China: 00:00 UTC
- Region detected automatically via `GetCurrentRegion()`
- Weekly resets: NA/OCE and EU on Wednesday, KR/TW/CN on Thursday
- Algorithm uses `GetServerTime()` for reliable UTC time regardless of region
- Reference epoch: January 4, 2026 15:00 UTC = Start of Witchberries (Day 1) farming window

### Frame Creation:
- Frame created at PLAYER_LOGIN (hidden) to ensure UI panel system fully registers it
- Prevents first `/jogu` command from failing
- World boss kill status checked on each character login and stored in SavedVariables
- Takes approximately 100kb of RAM (v1.0)

### Data Storage:
- Realm calibration: `JoguDB.realmCalibration[realmName]` (epoch day and crop index)
- Character tracking: `JoguDB.characters["RealmName-CharacterName"]` (harvest/quest epochs, level, class, world boss kills)
- World boss weekly lockouts: stored per-character with weekly epoch, auto-reset on new week
- Login message preference: `JoguDB.showLoginMessage` (boolean)

### Alt Tracking Detection Logic:
**CHAT_MSG_LOOT Event** (level 86+):
- Constraint 1: Must be at Sunsong Ranch (`GetSubZoneText()`)
- Constraint 2: Core crops must be quantity 5-10 (exact bonus harvest amounts)
- Constraint 3: Edge seeds can be any quantity (Motes 89112, Ores 72092-72094, Lotus 72096, Leather 72120, Cloth 72988)
- **Auto-calibration:** If quantity is exactly 7 or 10 (bonus crop indicators), the addon detects which crop is today's bonus and auto-corrects the cycle position if the current prediction is wrong

**QUEST_TURNED_IN Event** (level 90 only):
- Quest IDs: 30328-30332 (Master Token dailies only)
- Nomi quest (31337) remains separate and doesn't affect tracking

**PLAYER_LOGIN Event:**
- World boss kill status checked via `C_QuestLog.IsQuestFlaggedCompleted()` for Sha, Galleon, Nalak, Oondasta, and Ordos

---

*Version: 1.0 - March 24, 2026*
