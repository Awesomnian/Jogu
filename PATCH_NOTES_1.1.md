# Jogu Knows v1.1 patch notes

Mists of Pandaria Classic, Siege of Orgrimmar update.

## New

- Combined single-window layout. The crop wheel, Nomi section, and a per-character roster of professions, harvesting, Ironpaw, and weekly world bosses now sit in one window. The separate "Jogu Knows More" panel is gone.
- Profession cooldown tracking. Two icons per character on the roster show the daily-cooldown state for that character's primary professions. Greyed while the cooldown is available, full colour once used. Tracked per character, resets automatically when the daily cooldown ends. Covered professions: Alchemy (Transmute Living Steel), Tailoring (Imperial Silk), Inscription (Scroll of Wisdom), Blacksmithing (Balanced Trillium Ingot), Engineering (Jard's Peculiar Energy Source), and Leatherworking (Hardened Magnificent Hide).
- Celestial Court tracked as a weekly lockout. Counts if you have killed any of the Four Celestials (Chi-Ji, Yu'lon, Niuzao, Xuen). Stays greyed until your account's first kill, the same as Ordos.
- Roster centred-alignment toggle. The "Characters align top" checkbox, when unticked, vertically centres the roster on the crop-wheel line. Useful if you have one or two alts and want a more balanced look.
- "Hide world bosses" toggle. Narrows the window to just the daily columns (cooldowns, Farm, Ironpaw) for users who only care about dailies. This is account-wide.
- "Specific crops" message filter. Click the "?" next to the new "Specific crops" checkbox to pick which crops you want a login message about. The login chat message then only fires on days where tomorrow's bonus is one of your picks.
- Live updates throughout. World boss kills, profession cooldowns, crop harvesting, and Ironpaw turn-ins now flip their roster icon immediately. No more waiting for `/reload` or relogging.
- All settings persist across every character on the account.

## Changes

- Calibration is now regional, not per-realm. Every region uses the same verified default cycle position. A region's calibration (manual via "?" or automatic on a bonus harvest) overrides the default for that whole region, so two realms in the same region cannot drift out of sync with each other. The earlier per-realm calibration storage was the source of the recurring "Realm X says one crop, Realm Y says another" bug.
- Cycle position is now version-stamped. When Blizzard moves the cycle (roughly every 3-4 months it seems), the addon's `CYCLE_VERSION` is bumped; any calibration saved against an older version is discarded silently and everyone falls through to the updated default. No need for users to manually recalibrate after a shift.
- World boss list trimmed to Nalak, Oondasta, Celestial Court, and Ordos. Sha of Anger and Galleon were removed as no longer relevant for current content.
- Status icons replace the previous tick and cross marks. Harvest, Ironpaw, and world boss icons now use themed full-colour-when-done / greyed-out-when-not artwork. Cooldown icons match the same convention.
- Tomorrow's bonus crop now carries a soft golden glow rather than the old hard border.
- Roster gate. A character only joins the list after their first qualifying farm action (harvest or Ironpaw daily turn-in). Just logging in does not add an alt, which keeps the list focused on characters who actually farm. Removing a character and then harvesting on them re-adds them with their professions and any world boss kills already on file.
- Nomi status is now tracked per character. It previously read a shared flag and could appear done on alts that had not done it. Any of his daily cooking quests counts.
- "Alt Farm Report" is now "Daily Report", with a new sub-header. The "Daily Token" column is now "Farm Token", and the "Farmed" column is now "Farm".
- The login checkbox is now labelled "Show prediction on login".
- Class-coloured row backgrounds. Each character row carries a left-to-right gradient in their class colour so the roster is easier to scan at a glance.

## Fixes

- Fixed a false auto-calibration. A Plump harvest that split across inventory stacks (for example 8 items arriving as 1 then 7) could look like a bonus-day yield and wrongly shift the cycle. Same-frame loot is now totalled before the bonus check.
- Fixed cross-realm prediction divergence. Two characters in the same region on the same UTC day now always produce the same prediction; the new regional calibration model makes per-realm drift structurally impossible.
- World boss kill credit now refreshes the roster icon immediately rather than waiting for the next login.
- Adding or re-adding a character to the roster now populates their professions and existing world boss kills straight away, instead of leaving the row blank until `/reload`.
