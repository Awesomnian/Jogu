# 🐟 Jogu

**Author:** Awesomnia  
**GitHub:** https://github.com/awesomnian  
**Version:** 0.7  
**Addon location:**
```
C:\Program Files (x86)\World of Warcraft\_classic_\Interface\AddOns\Jogu
```

---

## Purpose

Jogu the Drunk is an NPC in World of Warcraft who would tell you what to plant today for bonus crops tomorrow. His predictions have not worked for most of Mists of Pandaria Classic and he has recently been disabled. This addon gives you that prediction ability and a few other useful bits of info. 

Type /jogu to open interface. 

It’s lightweight, at around 100kb as of v0.7.

---

## TL;DR

- A message on login telling you what the bonus for tomorrow is - default to off.
- Where in the cycle your current server is and ability to manually update this if it’s not correct, this will be remembered and predictions will be accurate from then on.
- ”Did I do my farm today on X?” - smart tracking for any alts that perform farming activities, notably harvesting crops or doing the Ironpaw Token daily quest from Halfhill Market which is given by a different Master each day if they have the Addon enabled.
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
- Default calculation is calibrated for Arugal (AU)
- "?" button (left side near prediction text) allows users on other servers to calibrate
- Clicking enters calibration mode: UI fades except crop wheel and prompt
- User clicks whichever crop was TODAY's bonus on their server
- Calibration saved per-realm in SavedVariables
- All characters on that realm will use the calibrated cycle going forward

### Optional Login Message
- Configurable checkbox to toggle login notifications (default off)
- When enabled, displays mouseable/clickable item link on login: `[Jogu] Plant [Scallions] today for bonus crops tomorrow!`

### Cooking School Bell / Nomi Integration
- Detects if character has Cooking School Bell (item 86425) in inventory
- If present, shows whether Nomi's daily quest (A Token of Appreciation, quest 31337) has been completed that day
- Bell icon is clickable to summon Nomi directly from the Jogu window
- Green text if quest completed: "You have received Nomi's gift today."
- Red text if quest not done: "You have not received your gift from Nomi today."
- Section hidden entirely if character doesn't have the bell

### Alt Tracking (v0.7 - Expanded Content Panel)
- "Expanded Content >" button (bottom-right) reveals side panel with character tracking
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
- "Expanded Content >" button aligned with checkbox at bottom-right

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
- Reset time: 15:00 UTC daily (2:00 AM Sydney/Melbourne AEDT)
- Reference epoch: January 4, 2026 15:00 UTC = Start of Witchberries (Day 1) farming window
- User verified: Jan 10, 2026 Sydney = Scallions (Day 6) - consistent with epoch
- Algorithm uses `GetServerTime()` for reliable UTC time

### Frame Creation:
- Frame created at PLAYER_LOGIN (hidden) to ensure UI panel system fully registers it
- Prevents first `/jogu` command from failing
- Takes approximately 30kb of RAM (v0.6 baseline)

### Data Storage:
- Realm calibration: `JoguDB.realmCalibration[realmName]` (epoch day and crop index)
- Character tracking: `JoguDB.characters["RealmName-CharacterName"]` (harvest/quest epochs, level, class)
- Login message preference: `JoguDB.showLoginMessage` (boolean)

### Alt Tracking Detection Logic:
**CHAT_MSG_LOOT Event** (level 86+):
- Constraint 1: Must be at Sunsong Ranch (`GetSubZoneText()`)
- Constraint 2: Core crops must be quantity 5-10 (exact bonus harvest amounts)
- Constraint 3: Edge seeds can be any quantity (Motes 89112, Ores 72092-72094, Lotus 72096, Leather 72120, Cloth 72988)

**QUEST_TURNED_IN Event** (level 90 only):
- Quest IDs: 30328-30332 (Master Token dailies only)
- Nomi quest (31337) remains separate and doesn't affect tracking

---

## Development History & Key Fixes

### v0.6 Issues
**Files not appearing on Windows filesystem:** Previous Claude session used container tools - fixed by using Desktop Commander MCP tool with actual Windows filesystem access

**Wrong crop prediction:** Incorrect epoch date/timezone handling - fixed by user verification of Jan 10 = Scallions (Day 6)

**Seed icons instead of crop icons:** Fixed by updating to crop item IDs (74840-74850)

**Text overlapping icons:** Fixed by increasing circle radius to 115px with proper spacing

**First `/jogu` command fails:** `ShowUIPanel()` fails when frame created and shown in same execution - fixed by creating frame at PLAYER_LOGIN (hidden)

**Memory leak (2-3kb/sec):** `OnUpdate` script with string concatenation - fixed by removing all OnUpdate scripts

**Gold highlight appearing inside icon:** `UI-ActionButton-Border` glows inward - fixed by using BackdropTemplate with WHITE8x8 edge file (2px gold border, 3px outside)

**UpdateJoguUI nil error:** Function declared after being called - fixed with forward declaration

**"Correct Crop" button misalignment:** Fixed by anchoring to checkbox for vertical alignment

### v0.7 Issues

**Column alignment in Expanded Content:** Icons appeared right-aligned instead of centered - fixed by calculating equal column widths (93px each) and centering icons/headers at column centers (140px and 233px from left edge)

**Button overlap:** Calibration button and Expanded Content button overlapping - fixed by moving calibration "?" to left side near prediction text, Expanded Content button to bottom-right aligned with checkbox

**Sorting logic:** Characters with level <90 need special handling for quest completion - treated as questDone=true for sorting purposes (can't complete quests, should appear in "all done" section)

---

## What Didn't Work

- `ShowUIPanel()` on frame creation in same execution - fails silently
- Creating new function references in `OnShow` handler - memory leak
- String concatenation in `OnUpdate` (even minimal) - memory leak from Lua GC
- `[target=mouseover]` macro syntax (from macro generator project) - invalid in WoW Classic
- `UI-ActionButton-Border` texture for highlight border - glows inward instead of outward
- Initial column alignment attempts using right-aligned positioning - fixed by using equal-width columns with centered positioning

---

## Current State (v0.7 Complete)

✅ Fully functional crop prediction
✅ Correct 10-day cycle calculation
✅ Proper timezone handling (15:00 UTC reset)
✅ Professional UI with profession-like window behavior
✅ Clickable Cooking School Bell integration
✅ No memory leaks
✅ `/jogu` works reliably on first use
✅ Login message with clickable item link
✅ Realm calibration for different server cycles
✅ Gold outer border highlight (not inner glow)
✅ Calibration mode fade effect for clarity
✅ **Alt tracking system with automatic detection**
✅ **Expanded Content panel with character management**
✅ **Manual completion toggles**
✅ **Priority-based sorting**
✅ **Class-colored character names**

---

## Potential Future Functionality (v0.8 Preparation)

### Console Command Status (`/jogu status`)
Print character farming status to chat console with:
- Aligned columns (Character, Farmed, Daily Token)
- Green/red colored YES/NO text
- Same sorting as Expanded Content panel
- Useful for quick status check without opening UI

### Server Detection and Cycle Positioning Automation
Current evidence shows calculation is accurate for Arugal (AU), but uncertainty remains:
- Does Pagle megaserver have different cycle position?
- Do servers bundled with Pagle share its cycle or have independent cycles?
- Automatic detection would eliminate need for manual calibration

### Release Preparation for Wago.io/WowUp Distribution
**Phase 1: Metadata & TOC Hardening**
- Update Interface version for current MoP Classic build
- Add/verify required headers (Title, Notes, Author, Version, Category)
- Insert X-Wago-ID placeholder

**Phase 2: Project Structure & Packager Config**
- Create `.pkgmeta` file for BigWigs Packager
- Create `.github/workflows/release.yml` for automated releases
- Configure GitHub topics for WowUp discovery

**Phase 3: Final Integration**
- Update TOC with real X-Wago-ID
- Configure GitHub Action with WAGO_API_TOKEN
- Test automated release workflow

**Note:** Check if v0.8 is solid enough to be v1.0 release during this phase.

---

*Version: 0.7 - January 10, 2026*
