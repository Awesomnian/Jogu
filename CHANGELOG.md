# Jogu Knows

## [v1.1.1](https://github.com/Awesomnian/Jogu/tree/v1.1.1) (2026-06-06)
[Full Changelog](https://github.com/Awesomnian/Jogu/compare/v1.1.0...v1.1.1)

Updated boss-kill detection to work in real time and not require a reload. A world boss kill now registers the moment the boss dies, via the encounter-end event, so the weekly lockout icon flips live in the open window, matching how Ironpaw, harvesting and profession cooldowns already update. The roster repaints only when a kill flag actually changes, and the zone and login rescans stay as a fallback. Also added an icon for the addon menu (IconTexture in the TOC) so Jogu Knows shows its own icon instead of the default question mark. The login prediction now stays quiet for a character that has already farmed that day, since at that point the planting is effectively done.

## [v1.1.0](https://github.com/Awesomnian/Jogu/tree/v1.1.0) (2026-05-28)
[Full Changelog](https://github.com/Awesomnian/Jogu/compare/v1.0.0...v1.1.0)

Major UI rewrite and architectural fixes. Combined single window replaces the previous two-window layout. Profession cooldown tracking added. Calibration storage moved from per-realm to per-region with a version stamp so future Blizzard cycle shifts can be handled with a single source-line bump. Roster gate added so a character only joins the list after a qualifying farm action. Live updates throughout for world boss kills, profession cooldowns, harvesting, and Ironpaw.

See PATCH_NOTES_1.1.md for the detailed list.

## [v1.0.0](https://github.com/Awesomnian/Jogu/tree/v1.0.0) (2026-03-23)
[Full Changelog](https://github.com/Awesomnian/Jogu/commits/v1.0.0) [Previous Releases](https://github.com/Awesomnian/Jogu/releases)

- Fix release workflow: remove incorrect -g flag, add fetch-depth  
    The -g flag was passing the tag name as game version instead of game flavor.  
    BigWigs Packager auto-detects MoP Classic from Interface: 50400 in the TOC.  
    Added fetch-depth: 0 for changelog generation from git history.  
- Add X-Curse-Project-ID to TOC for CurseForge integration  
- Add X-Wago-ID to TOC for Wago Addons integration  
- Update README for v1.0 release, replace screenshots  
    - Rewritten Purpose section with Jogu's rehab storyline  
    - Added auto-calibration and world boss tracking to TL;DR  
    - Added world boss login detection to Current Functionality  
    - Updated Technical Details with region-aware timing, new data storage, auto-calibration logic  
    - Removed Development History, What Didn't Work, Current State, and Future sections  
    - Replaced v0.7 screenshots with v1.0 screenshots  
- v1.0 - Jogu Knows: World boss tracking, region-aware resets, auto-calibration  
    Rename addon from "Jogu" to "Jogu Knows" (folder/slash command unchanged).  
    Version bump to 1.0.  
    Features:  
    - World boss lockout tracking (Sha/Gal/Nal/Oon/Ord) via "Jogu Knows More" panel  
    - Region-aware daily/weekly reset times (NA/OCE, EU, KR, TW, CN)  
    - Auto-calibration from bonus crop harvests (qty 7 or 10)  
    - Truffle Shuffle easter egg with TomTom waypoint support  
    - Multi-realm character suffix detection  
    - Integrated dual-panel layout (crop predictions + Alt Farm Report)  
    Release infrastructure:  
    - .pkgmeta for BigWigs Packager  
    - GitHub Actions workflow for automated releases  
    - RELEASE\_GUIDE.md with full publishing walkthrough  
- Improve clarity of farming activities tracking  
    Clarified the smart tracking feature description for alts performing farming activities.  
- Update addon installation instructions in README  
    Clarify instructions for saving TOC and LUA files.  
- Update README with installation instructions and plans  
    Clarified installation instructions and future plans for addon managers.  
- Revise README for Jogu addon clarity and details  
    Updated the README to clarify the purpose and functionality of the Jogu addon, including its lightweight nature and features.  
- Added screenshots of interface and login message  
- Add Jogu.zip for easy download  
- Initial commit - Jogu v0.7 - Sunsong Ranch crop predictor with alt tracking  
