-- Jogu Knows: Crop Prediction Addon for MoP Classic
-- Predicts tomorrow's bonus crop for Sunsong Ranch
-- Interface: 50400 (MoP Classic)
-- Version: 1.1-beta - single combined window: crop wheel + Nomi on the left, and a per-character
--                     roster (profession cooldowns, Farm, Ironpaw, world bosses) on the right.
--                     Adds: Characters-align-top toggle, Hide-world-bosses (narrows the window),
--                     and a "Specific crops" login message filter with a calibration-style picker.

local CROPS = {
    {id = 74846, name = "Witchberries"},
    {id = 74847, name = "Jade Squash"},
    {id = 74848, name = "Striped Melon"},
    {id = 74840, name = "Green Cabbage"},
    {id = 74841, name = "Juicycrunch Carrot"},
    {id = 74843, name = "Scallions"},
    {id = 74842, name = "Mogu Pumpkin"},
    {id = 74844, name = "Red Blossom Leek"},
    {id = 74849, name = "Pink Turnip"},
    {id = 74850, name = "White Turnip"},
}

-- Edge seed items that can drop from Sunsong Ranch edge plots
local EDGE_SEEDS = {
    [89112] = true, -- Mote of Harmony
    [72092] = true, -- Ghost Iron Ore
    [72093] = true, -- Black Trillium Ore
    [72094] = true, -- White Trillium Ore
    [72096] = true, -- Golden Lotus
    [72120] = true, -- Exotic Leather
    [72988] = true, -- Windwool Cloth
}

-- Master Token daily quest IDs (level 90 only)
local MASTER_TOKEN_QUESTS = {
    [30330] = true,
    [30331] = true,
    [30332] = true,
    [30328] = true,
    [30329] = true,
}

local COOKING_SCHOOL_BELL_ID = 86425
local NOMI_DAILY_QUEST_ID = 31337
-- Completing ANY of these Nomi / Cooking School daily quests counts as "spoken to Nomi today"
local NOMI_QUEST_IDS = {
    [31820] = true, [31337] = true, [31332] = true, [31333] = true,
    [31334] = true, [31335] = true, [31336] = true,
}
local TRUFFLE_SHUFFLE_QUEST_ID = 30330

-- Bonus-crop cycle anchor + version stamp.
--
-- DESIGN: predictions are anchored REGIONALLY for STORAGE of calibrations (so two realms in
-- the same region can't disagree), but every region starts from the same default baseline.
-- The Arugal/Pagle NA cycle is the verified ground truth; we have no evidence yet that EU,
-- KR, TW or CN run on a different cycle. If they do, that region's user calibration (manual
-- or auto on first bonus harvest) overrides the default for that region only.
--
-- CYCLE_VERSION is bumped whenever Blizzard shifts the cycle starting position. Calibrations
-- stored before a shift carry their save-time cycleVersion; on load, a mismatch causes the
-- stored calibration to be discarded and the default baseline takes over again. One-line
-- bump in source is the entire "fix a Blizzard shift" workflow.
local CYCLE_VERSION = 2

-- Verified 2026-05-27 (UTC after 15:00 reset, farming day = 20600) via auto-cal agreement on
-- Pagle and Arugal: today's bonus crop was Green Cabbage (index 4). Used by every region as
-- the default unless that region has an active calibration override.
local DEFAULT_CYCLE_ANCHOR = { epochDay = 20600, cropIndex = 4 }

-- Region-specific reset configuration (all times fixed UTC, no DST adjustment)
-- GetCurrentRegion(): 1=US/OCE, 2=Korea, 3=Europe, 4=Taiwan, 5=China
local REGION_RESET_CONFIG = {
    [1] = { dailyResetHour = 15, weeklyRefEpochDay = 20460 },  -- NA/OCE: 15:00 UTC, Wed Jan 7 2026
    [2] = { dailyResetHour = 0,  weeklyRefEpochDay = 20461 },  -- Korea:  00:00 UTC, Thu Jan 8 2026
    [3] = { dailyResetHour = 7,  weeklyRefEpochDay = 20460 },  -- Europe: 07:00 UTC, Wed Jan 7 2026
    [4] = { dailyResetHour = 0,  weeklyRefEpochDay = 20461 },  -- Taiwan: 00:00 UTC, Thu Jan 8 2026
    [5] = { dailyResetHour = 0,  weeklyRefEpochDay = 20461 },  -- China:  00:00 UTC, Thu Jan 8 2026
}

local function GetRegionResetConfig()
    local region = GetCurrentRegion and GetCurrentRegion() or 1
    return REGION_RESET_CONFIG[region] or REGION_RESET_CONFIG[1]
end

-- World Boss weekly lockout quest IDs (hidden quests flagged on kill)
-- Sha of Anger (32099) and Galleon (32098) were removed in v1.1: not relevant for current content.
local WORLD_BOSSES = {
    {name = "Nal", fullName = "Nalak", questID = 32518},
    {name = "Oon", fullName = "Oondasta", questID = 32519},
    {name = "CC", fullName = "Celestial Court", questID = 33117, futureContent = true},  -- one weekly lockout for all 4 Celestials (Chi-Ji/Yu'lon/Niuzao/Xuen)
    {name = "Ord", fullName = "Ordos", questID = 33118, futureContent = true},
}

local JoguFrame = nil
local calibrationMode = false
local cropPickerMode = false  -- when true, clicking a crop toggles JoguDB.selectedCrops[i]
local UpdateJoguUI  -- Forward declaration
local UpdateExpandedPanel  -- Forward declaration
local ApplyWorldBossVisibility  -- Forward declaration (resizes frame + hides boss headers/icons)
local ApplyMessageFilterEnabled  -- Forward declaration (cascades enabled state to filter controls)
local GetCurrentEpochDay  -- Forward declaration
local GetCurrentWeekEpoch  -- Forward declaration
local UpdateProfessions  -- Forward declaration (so MarkHarvested/MarkMasterToken can refresh)
local UpdateWorldBossStatus  -- Forward declaration (so MarkHarvested/MarkMasterToken can refresh)

-- Apply or remove calibration mode fade effect
local function SetCalibrationFade(enabled)
    if not JoguFrame then return end
    local alpha = enabled and 0.3 or 1.0
    local gray = enabled and 0.4 or 1.0
    
    -- Fade title
    if enabled then
        JoguFrame.title:SetTextColor(0.4, 0.33, 0)
    else
        JoguFrame.title:SetTextColor(1, 0.82, 0)
    end
    
    -- Fade flavor text
    if enabled then
        JoguFrame.flavorText:SetTextColor(0.35, 0.35, 0.35)
    else
        JoguFrame.flavorText:SetTextColor(0.9, 0.9, 0.9)
    end
    
    -- Fade timer text
    if enabled then
        JoguFrame.timerText:SetTextColor(0.3, 0.3, 0.3)
    else
        JoguFrame.timerText:SetTextColor(0.8, 0.8, 0.8)
    end
    
    -- Fade checkbox and label
    JoguFrame.checkbox:SetAlpha(alpha)
    if enabled then
        JoguFrame.checkboxLabel:SetTextColor(0.35, 0.35, 0.35)
    else
        JoguFrame.checkboxLabel:SetTextColor(0.9, 0.9, 0.9)
    end

    -- Fade Nomi section if visible
    if JoguFrame.nomiSection:IsShown() then
        JoguFrame.bellButton:SetAlpha(alpha)
        if enabled then
            JoguFrame.nomiText:SetTextColor(0.3, 0.3, 0.3)
        else
            -- Will be reset by UpdateJoguUI based on quest status
        end
        JoguFrame.separator:SetAlpha(alpha)
    end

    -- Fade the other checkboxes added in v1.1 (alignTop, onlyMessage/Specific crops, hideBosses).
    -- The calibrate button and picker "?" are intentionally NOT faded -- in either mode they are
    -- the active close button (X / tick) and must remain interactive.
    local function fadeBox(box, label)
        if box then box:SetAlpha(alpha) end
        if label then
            if enabled then label:SetTextColor(0.35, 0.35, 0.35)
            else label:SetTextColor(0.9, 0.9, 0.9) end
        end
    end
    fadeBox(JoguFrame.alignTopCheckbox, JoguFrame.alignTopLabel)
    fadeBox(JoguFrame.onlyMessageCheckbox, JoguFrame.onlyMessageLabel)
    fadeBox(JoguFrame.hideBossesCheckbox, JoguFrame.hideBossesLabel)
end

local FLAVOR_TEXT = "Whilst our friend Jogu is in rehab, largely due to your enablement, here's a handy guide to show you what to plant today to receive bonus crops tomorrow.\n\nStandard crops produce 5 items, a 'plump' proc gives +3 and bonus crops give +2. These stack."

local FRAME_HEIGHT = 600
-- Narrower right column when "Hide world bosses" is ticked; the window cropping point sits at
-- the (invisible) roster divider with the Remove button placed ~17px right of Ironpaw, matching
-- the Ord→Remove gap of the wide layout.
local FRAME_RIGHT_WIDTH_NARROW = 395
-- Declared here (before UpdateExpandedPanel) so both the roster renderer and CreateJoguFrame
-- can see them; Lua locals are only visible below their declaration.
local FRAME_LEFT_WIDTH = 380   -- Left column: crop wheel, flavor, Nomi, controls
local FRAME_RIGHT_WIDTH = 660  -- Right column: combined roster (cooldowns/farmed/token/bosses)
local FRAME_TOTAL_WIDTH = FRAME_LEFT_WIDTH + FRAME_RIGHT_WIDTH

function Jogu_OnLoad()
    if not JoguDB then
        JoguDB = {
            showLoginMessage = false,
            regionCalibration = {},
            characters = {}  -- Alt tracking data
        }
    end
    if not JoguDB.regionCalibration then
        JoguDB.regionCalibration = {}
    end
    if not JoguDB.characters then
        JoguDB.characters = {}
    end
    -- Per-boss "ever killed on any character" flags, keyed by weekly-lockout quest ID.
    -- Gates the reveal of future-content bosses (Celestial Court, Ordos) until first kill.
    if not JoguDB.bossEverKilled then
        JoguDB.bossEverKilled = {}
    end
    -- Set of selected crop indices (1-10) for the "Specific crops" message filter.
    if not JoguDB.selectedCrops then
        JoguDB.selectedCrops = {}
    end

    -- Drop the obsolete per-realm calibration store silently. Users on NA fall through to the
    -- default anchor and see no change; nothing visible happens.
    JoguDB.realmCalibration = nil
end

local function GetUTCTime()
    local utcTime = GetServerTime()
    local utcDate = date("!*t", utcTime)
    return utcTime, utcDate
end

-- Get current epoch day (region-aware daily reset)
GetCurrentEpochDay = function()
    local utcTime, utcDate = GetUTCTime()
    local resetHour = GetRegionResetConfig().dailyResetHour
    local farmingDayOffset = (utcDate.hour < resetHour) and -1 or 0
    return math.floor(utcTime / 86400) + farmingDayOffset
end

-- Get epoch day of the current weekly reset (region-aware reset day)
GetCurrentWeekEpoch = function()
    local currentEpochDay = GetCurrentEpochDay()
    local refDay = GetRegionResetConfig().weeklyRefEpochDay
    local daysSinceReset = (currentEpochDay - refDay) % 7
    return currentEpochDay - daysSinceReset
end

-- Register or update character in tracking database.
--
-- Tracking rule: a character must EARN their spot on the Jogu roster by performing a farm
-- action (harvest crops or complete the Ironpaw daily). Just logging in is not enough. So:
--   * Pass createIfMissing=true ONLY from the qualifying farm actions (MarkHarvested,
--     MarkMasterToken). Those create the entry on first call and trigger an immediate prof +
--     world-boss scan so the new roster row populates without needing a /reload.
--   * Pass createIfMissing=false (or omit) from everything else (PLAYER_LOGIN, MarkNomi, the
--     scanners themselves, spellcast hooks). If the character isn't tracked yet, this returns
--     nil and the caller no-ops. Once tracked, it refreshes level/class on every call.
local function RegisterCharacter(createIfMissing)
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    local key = realmName .. "-" .. playerName
    local level = UnitLevel("player")
    local _, class = UnitClass("player")

    if not JoguDB.characters[key] then
        if not createIfMissing then
            return nil
        end
        JoguDB.characters[key] = {
            lastHarvestEpoch = 0,
            lastMasterTokenEpoch = 0,
            level = level,
            class = class,
        }
    else
        -- Update level and class in case they changed
        JoguDB.characters[key].level = level
        JoguDB.characters[key].class = class
    end

    -- NOTE: roster-row data (professions, world-boss kills) is refreshed by the calling Mark
    -- function, not here. Doing it inline relied on a forward-declared local being populated
    -- and on UpdateProfessions/UpdateWorldBossStatus reading the WoW API cleanly during
    -- whatever event the parent call was triggered from. That worked for harvest but proved
    -- flaky for Ironpaw turn-ins. The explicit calls in MarkHarvested / MarkMasterToken give
    -- both paths visibly identical behaviour.

    return key
end

-- Mark character as having harvested today. Qualifying farm action -- creates the roster entry
-- if this is the character's first ever crop pick, then refreshes prof + world-boss data so
-- the new row populates fully (or an existing row picks up any changes since last scan).
local function MarkHarvested()
    local key = RegisterCharacter(true)
    JoguDB.characters[key].lastHarvestEpoch = GetCurrentEpochDay()
    UpdateProfessions()
    UpdateWorldBossStatus()
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Mark character as having completed Master Token (Ironpaw) quest today. Qualifying farm action
-- -- creates the roster entry if this is the character's first ever Ironpaw completion, then
-- refreshes prof + world-boss data the same way as MarkHarvested so both paths are consistent.
local function MarkMasterToken()
    local key = RegisterCharacter(true)
    JoguDB.characters[key].lastMasterTokenEpoch = GetCurrentEpochDay()
    UpdateProfessions()
    UpdateWorldBossStatus()
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Mark this character as having spoken to Nomi (completed a Nomi cooking daily) today. NOT a
-- qualifying farm action under the tracking rule, so this only updates an already-tracked
-- character; if the character isn't on the Jogu list yet, the Nomi event is silently ignored.
local function MarkNomi()
    local key = RegisterCharacter(false)
    if not key then return end
    JoguDB.characters[key].lastNomiEpoch = GetCurrentEpochDay()
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateJoguUI()
    end
end

-- Daily profession cooldown spells, keyed by profession skill-line ID.
-- [skillLineID] = daily-cooldown spellID. Use the COOLDOWN craft, not the no-CD bypass.
local PROFESSION_COOLDOWNS = {
    [171] = 114780,  -- Alchemy:       Transmute: Living Steel (per-character daily cooldown)
    [197] = 125557,  -- Tailoring:     Imperial Silk (the no-CD bypass is Song of Harmony 130325)
    [773] = 112996,  -- Inscription:   Scroll of Wisdom
    [164] = 143255,  -- Blacksmithing: Balanced Trillium Ingot
    [202] = 139176,  -- Engineering:   Jard's Peculiar Energy Source
    [165] = 142976,  -- Leatherworking: Hardened Magnificent Hide
}

-- Reverse lookup (spellID -> true) of the crafts above, so casting one can trigger a live
-- refresh of the current character's cooldown state (see UNIT_SPELLCAST_SUCCEEDED handler).
local TRACKED_COOLDOWN_SPELLS = {}
for _, spellID in pairs(PROFESSION_COOLDOWNS) do
    TRACKED_COOLDOWN_SPELLS[spellID] = true
end

local function GetProfessionCooldownSpell(skillLine)
    return PROFESSION_COOLDOWNS[skillLine]
end

-- Detect this character's two primary professions and their daily-cooldown state; store per char.
-- Cooldown state can only be read for the logged-in character, so each alt's icons reflect the
-- last time it ran this (on login / addon open). Assigned to the forward-declared local so
-- RegisterCharacter can call this when a char is added/re-added.
UpdateProfessions = function()
    local key = RegisterCharacter(false)
    if not key then return end  -- character not on the Jogu list yet; nothing to update
    local data = JoguDB.characters[key]
    local prevProfs = data.professions or {}
    local newProfs = {}
    local prof1, prof2 = GetProfessions()
    local indices = { prof1, prof2 }
    for slot = 1, 2 do
        local idx = indices[slot]
        if idx then
            local name, icon, _, _, _, _, skillLine = GetProfessionInfo(idx)
            local cdSpell = GetProfessionCooldownSpell(skillLine)
            -- Read the live cooldown for THIS character. start>0 with a long duration means the
            -- daily cooldown is ticking (it's been used). Convert the remaining time to an
            -- absolute server timestamp so alts (and future sessions) can tell, WITHOUT needing
            -- to know the exact daily reset time -- the icon greys out the instant the real
            -- cooldown ends. Default (off cooldown / spell unknown) = 0 = available/grey.
            local cdExpiry = (prevProfs[slot] and prevProfs[slot].skillLine == skillLine
                and prevProfs[slot].cdExpiry) or 0
            if cdSpell then
                local start, duration = GetSpellCooldown(cdSpell)
                if start and start > 0 and duration and duration > 60 then
                    cdExpiry = GetServerTime() + (start + duration - GetTime())
                else
                    cdExpiry = 0
                end
            end
            newProfs[slot] = {
                name = name, icon = icon, skillLine = skillLine,
                hasCD = (cdSpell ~= nil), cdSpell = cdSpell,
                cdExpiry = cdExpiry,
            }
        end
    end
    data.professions = newProfs
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Check and store world boss kill status for current character. Assigned to the forward-declared
-- local so RegisterCharacter can call this when a char is added/re-added.
UpdateWorldBossStatus = function()
    local key = RegisterCharacter(false)
    if not key then return end  -- character not on the Jogu list yet; nothing to update
    local data = JoguDB.characters[key]
    if not data.worldBosses then
        data.worldBosses = {}
    end
    local currentWeek = GetCurrentWeekEpoch()
    for _, boss in ipairs(WORLD_BOSSES) do
        if C_QuestLog.IsQuestFlaggedCompleted(boss.questID) then
            data.worldBosses[boss.questID] = currentWeek
            -- Reveal future-content bosses once killed on any character
            if boss.futureContent and not JoguDB.bossEverKilled[boss.questID] then
                JoguDB.bossEverKilled[boss.questID] = true
            end
        end
    end
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Return (tomorrowDay, currentDay) cycle indices. Always returns valid values -- every region
-- starts from DEFAULT_CYCLE_ANCHOR, with an optional regional calibration override that takes
-- precedence when its cycleVersion matches the current CYCLE_VERSION.
local function GetTomorrowBonusDay()
    local utcTime, utcDate = GetUTCTime()
    local resetHour = GetRegionResetConfig().dailyResetHour
    local farmingDayOffset = (utcDate.hour < resetHour) and -1 or 0
    local currentEpochDay = math.floor(utcTime / 86400) + farmingDayOffset

    local region = GetCurrentRegion and GetCurrentRegion() or 1
    local stored = JoguDB and JoguDB.regionCalibration and JoguDB.regionCalibration[region]
    local anchor = (stored and stored.cycleVersion == CYCLE_VERSION) and stored or DEFAULT_CYCLE_ANCHOR

    local daysSinceAnchor = currentEpochDay - anchor.epochDay
    local currentDay = ((anchor.cropIndex - 1 + daysSinceAnchor) % 10 + 10) % 10 + 1
    local tomorrowDay = (currentDay % 10) + 1
    return tomorrowDay, currentDay
end

local function GetSecondsUntilReset()
    local utcTime, utcDate = GetUTCTime()
    local secondsSinceMidnight = utcDate.hour * 3600 + utcDate.min * 60 + utcDate.sec
    local targetSeconds = GetRegionResetConfig().dailyResetHour * 3600
    if secondsSinceMidnight < targetSeconds then
        return targetSeconds - secondsSinceMidnight
    else
        return (86400 - secondsSinceMidnight) + targetSeconds
    end
end

local function FormatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%dh %dm", hours, mins)
end

local function HasCookingSchoolBell()
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID == COOKING_SCHOOL_BELL_ID then return true end
        end
    end
    return false
end

local function IsNomiQuestCompletedToday()
    -- Per-character, per-day: true only if THIS character turned in a tracked Nomi daily
    -- today (recorded by MarkNomi on QUEST_TURNED_IN). We use our own stored data instead of
    -- C_QuestLog flags because some of those quest flags are account-wide / one-time and would
    -- wrongly report "done" on characters that haven't completed today's daily.
    local key = GetRealmName() .. "-" .. UnitName("player")
    local data = JoguDB and JoguDB.characters and JoguDB.characters[key]
    return data ~= nil and data.lastNomiEpoch == GetCurrentEpochDay()
end

-- Get display name for a character, adding realm suffix only when multiple realms exist
-- Returns formatted name and a table mapping key -> displayName for all characters
local function GetCharacterDisplayNames()
    if not JoguDB or not JoguDB.characters then return {} end

    -- Count characters per realm
    local realmCounts = {}
    local totalChars = 0
    for key, _ in pairs(JoguDB.characters) do
        local realm = key:match("^(.+)%-")
        realmCounts[realm] = (realmCounts[realm] or 0) + 1
        totalChars = totalChars + 1
    end

    -- Find how many distinct realms
    local numRealms = 0
    for _ in pairs(realmCounts) do
        numRealms = numRealms + 1
    end

    -- If only one realm, no suffixes needed
    if numRealms <= 1 then
        local names = {}
        for key, _ in pairs(JoguDB.characters) do
            local name = key:match("^.+%-(.+)$")
            names[key] = name
        end
        return names
    end

    -- Find the majority realm (most characters)
    local majorityRealm = nil
    local majorityCount = 0
    for realm, count in pairs(realmCounts) do
        if count > majorityCount then
            majorityRealm = realm
            majorityCount = count
        end
    end

    -- Check if it's a tie (multiple realms share the max count)
    local isTied = false
    for realm, count in pairs(realmCounts) do
        if count == majorityCount and realm ~= majorityRealm then
            isTied = true
            break
        end
    end

    -- Build display names
    local names = {}
    for key, _ in pairs(JoguDB.characters) do
        local realm = key:match("^(.+)%-")
        local name = key:match("^.+%-(.+)$")

        -- Suffix if not on majority realm, or if tied suffix everyone
        if isTied or realm ~= majorityRealm then
            -- Strip parenthetical like "(AU)" from realm before abbreviating
            local cleanRealm = realm:match("^(%S+)") or realm
            local suffix = string.upper(string.sub(cleanRealm, 1, 2))
            names[key] = name .. "-" .. suffix
        else
            names[key] = name
        end
    end
    return names
end

-- Render the combined roster (right column): one row per character with class-colour gradient
-- background, profession cooldown icons, Farmed + Farm Token toggles, the six weekly world-boss
-- kill icons, and a Remove-character button. Replaces the old Daily Report + Jogu Knows More.
UpdateExpandedPanel = function()
    if not JoguFrame or not JoguFrame.altScrollChild then return end

    local scrollChild = JoguFrame.altScrollChild
    local scrollFrame = JoguFrame.altScrollFrame

    -- Re-colour boss column headers: a future-content boss (CC, Ordos) reveals in gold once it
    -- has been killed on any character; until then it stays greyed.
    if JoguFrame.bossHeaders then
        for i, boss in ipairs(WORLD_BOSSES) do
            local h = JoguFrame.bossHeaders[i]
            if h then
                if boss.futureContent and not (JoguDB.bossEverKilled and JoguDB.bossEverKilled[boss.questID]) then
                    h:SetTextColor(0.4, 0.4, 0.4)
                else
                    h:SetTextColor(1, 0.82, 0)
                end
            end
        end
    end

    -- Clear existing rows
    if scrollChild.rows then
        for _, row in ipairs(scrollChild.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    scrollChild.rows = {}

    local currentEpoch = GetCurrentEpochDay()
    local currentWeek = GetCurrentWeekEpoch()
    local displayNames = GetCharacterDisplayNames()

    -- Gather characters, alphabetical by display name
    local chars = {}
    for key, data in pairs(JoguDB.characters) do
        local name = displayNames[key] or key:match("^.+%-(.+)$")
        table.insert(chars, { key = key, name = name, data = data })
    end
    table.sort(chars, function(a, b) return a.name < b.name end)

    -- Row-local column x (icons are LEFT-anchored). Scroll area begins at FRAME_LEFT_WIDTH+10,
    -- so absolute frameX = 390 + these; the headers in CreateJoguFrame are centred to match.
    -- Sizes: cooldown icons 24px, all tick/cross status icons 20px, row text 14px.
    local CD = 32            -- icon size for cooldowns, Farmed, Ironpaw, world bosses (~2px row margin)
    local SI = 20            -- Remove-character button size
    local FONT = "Fonts\\FRIZQT__.TTF"
    local FSIZE = 14         -- uniform row text size (name + dashes)
    -- Daily columns left of the roster divider (abs x744); world bosses to its right. The two
    -- cooldown icons sit 30 apart (6px gap for 24px icons); cd2, Farmed, Ironpaw and the divider
    -- are evenly spaced 68 apart.
    -- Daily columns shifted right (and slightly compressed, 54 apart) to free room for a wider
    -- name column so suffixed names like "Awesomnia-AR" don't wrap. Divider/bosses unchanged.
    local COOLDOWN_X = { 138, 176 }   -- 32px, centres 154 / 192 (6px gap) -> "Cooldowns" header 563
    local FARMED_X = 230              -- 32px, centre 246 -> abs 636 -> "Farmed" header 636
    local TOKEN_X = 284               -- 32px, centre 300 -> abs 690 -> "Ironpaw" header 690
    local BOSS_X = { 361, 424, 486, 549 }  -- 4 bosses 32px, centres 377/440/502/565 -> headers 767/830/892/955
    -- "Hide world bosses" narrows the right column so the row ends just past Ironpaw, matching
    -- the prior Ord -> Remove gap. Boss icons are skipped below when hideWB is true.
    local hideWB = JoguDB and JoguDB.hideWorldBosses
    local effectiveRightW = hideWB and FRAME_RIGHT_WIDTH_NARROW or FRAME_RIGHT_WIDTH
    local ROW_W = effectiveRightW - 40

    -- Roster vertical alignment. Default (alignTop true / checkbox ticked) lists rows from the top
    -- of the scroll area, headers at -16. When unticked, the block of rows is centred on the
    -- crop-wheel centre line (frame depth 272; the scroll area starts at depth 42, so that line is
    -- 230px down inside the scroll) and the column headers move down to just above the first row.
    local STRIDE = 42
    local alignTop = (not JoguDB) or (JoguDB.alignTop ~= false)
    local n = #chars
    local blockHeight = (n > 0) and ((n - 1) * STRIDE + 36) or 0
    local startOffset = 0
    if not alignTop then
        startOffset = -(230 - blockHeight / 2)
        if startOffset > 0 then startOffset = 0 end  -- block too tall to centre -> fall back to top
    end
    -- Reposition the column headers to match the chosen alignment.
    if JoguFrame.colHeaders then
        local hy = -16
        if not alignTop and startOffset < 0 then
            hy = -((42 - startOffset) - 26)  -- 26px above the first row's top
        end
        for _, ch in ipairs(JoguFrame.colHeaders) do
            ch.h:ClearAllPoints()
            ch.h:SetPoint("TOP", JoguFrame, "TOPLEFT", ch.x, hy)
        end
    end

    local yOffset = startOffset
    for _, char in ipairs(chars) do
        local data = char.data
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetSize(ROW_W, 36)
        row:SetPoint("TOPLEFT", 0, yOffset)

        -- Class-colour gradient background: strong on the left, fading to transparent on the right
        local cc = RAID_CLASS_COLORS[data.class]
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        if cc then
            bg:SetGradient("HORIZONTAL", CreateColor(cc.r, cc.g, cc.b, 0.50), CreateColor(cc.r, cc.g, cc.b, 0.0))
        else
            bg:SetGradient("HORIZONTAL", CreateColor(0.4, 0.4, 0.4, 0.35), CreateColor(0.4, 0.4, 0.4, 0.0))
        end

        -- Character name (class-coloured; append level if < 90). Vertically centred (y0).
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetFont(FONT, FSIZE)
        nameText:SetPoint("LEFT", 8, 0)
        nameText:SetWidth(128)
        nameText:SetJustifyH("LEFT")
        if data.level and data.level < 90 then
            nameText:SetText(char.name .. " (" .. data.level .. ")")
        else
            nameText:SetText(char.name)
        end
        if cc then nameText:SetTextColor(cc.r, cc.g, cc.b) end

        -- Cooldowns: one slot per primary profession. Dash if no profession / no tracked daily
        -- cooldown; greyed+transparent icon while the daily CD is available; full colour once used.
        local profData = data.professions
        for slot = 1, 2 do
            local p = profData and profData[slot]
            if p and p.hasCD then
                local profName = p.name
                local used = (p.cdExpiry or 0) > GetServerTime()
                local profBtn = CreateFrame("Button", nil, row)
                profBtn:SetSize(CD, CD)
                profBtn:SetPoint("LEFT", row, "LEFT", COOLDOWN_X[slot], 0)

                local profIcon = profBtn:CreateTexture(nil, "ARTWORK")
                profIcon:SetAllPoints()
                profIcon:SetTexture(p.icon)
                if used then
                    profIcon:SetDesaturated(false)
                    profIcon:SetVertexColor(1, 1, 1, 1)
                else
                    profIcon:SetDesaturated(true)
                    profIcon:SetVertexColor(0.5, 0.5, 0.5, 0.5)
                end

                profBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(profName, 1, 0.82, 0)
                    if used then
                        GameTooltip:AddLine("Daily cooldown used today", 0.5, 0.5, 0.5)
                    else
                        GameTooltip:AddLine("Daily cooldown available", 0.1, 1, 0.1)
                    end
                    GameTooltip:Show()
                end)
                profBtn:SetScript("OnLeave", GameTooltip_Hide)
            else
                local dash = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dash:SetFont(FONT, FSIZE)
                dash:SetPoint("CENTER", row, "LEFT", COOLDOWN_X[slot] + CD / 2, 0)
                dash:SetText("—")
                dash:SetTextColor(0.4, 0.4, 0.4)
            end
        end

        -- Farmed (harvest) toggle
        local harvestBtn = CreateFrame("Button", nil, row)
        harvestBtn:SetSize(CD, CD)
        harvestBtn:SetPoint("LEFT", row, "LEFT", FARMED_X, 0)
        local harvestIcon = harvestBtn:CreateTexture(nil, "ARTWORK")
        harvestIcon:SetAllPoints()
        harvestIcon:SetTexture(134190)
        if data.lastHarvestEpoch == currentEpoch then
            harvestIcon:SetDesaturated(false)
            harvestIcon:SetVertexColor(1, 1, 1, 1)            -- farmed today: full colour
        else
            harvestIcon:SetDesaturated(true)
            harvestIcon:SetVertexColor(0.5, 0.5, 0.5, 0.5)    -- not farmed: greyed + dimmed
        end
        harvestBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Harvest Status", 1, 0.82, 0)
            if data.lastHarvestEpoch == currentEpoch then
                GameTooltip:AddLine("Crops harvested", 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine("Crops harvestable", 0.1, 1, 0.1)
            end
            GameTooltip:Show()
        end)
        harvestBtn:SetScript("OnLeave", GameTooltip_Hide)

        -- Farm Token toggle (level 90 only; dash otherwise)
        local tokenBtn = CreateFrame("Button", nil, row)
        tokenBtn:SetSize(CD, CD)
        tokenBtn:SetPoint("LEFT", row, "LEFT", TOKEN_X, 0)
        if data.level == 90 then
            local tokenIcon = tokenBtn:CreateTexture(nil, "ARTWORK")
            tokenIcon:SetAllPoints()
            tokenIcon:SetTexture(134912)
            if data.lastMasterTokenEpoch == currentEpoch then
                tokenIcon:SetDesaturated(false)
                tokenIcon:SetVertexColor(1, 1, 1, 1)            -- done today: full colour
            else
                tokenIcon:SetDesaturated(true)
                tokenIcon:SetVertexColor(0.5, 0.5, 0.5, 0.5)    -- not done: greyed + dimmed
            end
            tokenBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Master Chef quest", 1, 0.82, 0)
                if data.lastMasterTokenEpoch == currentEpoch then
                    GameTooltip:AddLine("Token received", 0.5, 0.5, 0.5)
                else
                    GameTooltip:AddLine("Token available", 0.1, 1, 0.1)
                end
                GameTooltip:Show()
            end)
            tokenBtn:SetScript("OnLeave", GameTooltip_Hide)
        else
            local dash = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            dash:SetFont(FONT, FSIZE)
            dash:SetPoint("CENTER", tokenBtn, "CENTER", 0, 0)
            dash:SetText("—")
            dash:SetTextColor(0.5, 0.5, 0.5)
            tokenBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Quests available at level 90")
                GameTooltip:Show()
            end)
            tokenBtn:SetScript("OnLeave", GameTooltip_Hide)
        end

        -- World boss kill icons (skipped entirely when the user has hidden world bosses).
        -- Future-content bosses show a greyed dash until revealed.
        local bosses = data.worldBosses or {}
        if not hideWB then for i, boss in ipairs(WORLD_BOSSES) do
            if boss.futureContent and not (JoguDB.bossEverKilled and JoguDB.bossEverKilled[boss.questID]) then
                local dash = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dash:SetFont(FONT, FSIZE)
                dash:SetPoint("CENTER", row, "LEFT", BOSS_X[i] + CD / 2, 0)
                dash:SetText("—")
                dash:SetTextColor(0.4, 0.4, 0.4)
            else
                local killed = bosses[boss.questID] and bosses[boss.questID] == currentWeek
                local bossBtn = CreateFrame("Button", nil, row)
                bossBtn:SetSize(CD, CD)
                bossBtn:SetPoint("LEFT", row, "LEFT", BOSS_X[i], 0)
                local icon = bossBtn:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                icon:SetTexture(237281)
                if killed then
                    icon:SetDesaturated(false)
                    icon:SetVertexColor(1, 1, 1, 1)            -- looted this week: full colour
                else
                    icon:SetDesaturated(true)
                    icon:SetVertexColor(0.5, 0.5, 0.5, 0.5)    -- not looted: greyed + dimmed
                end
                bossBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if killed then
                        GameTooltip:SetText("Looted", 1, 0.82, 0)
                    else
                        GameTooltip:SetText("Not looted", 1, 0.82, 0)
                    end
                    GameTooltip:Show()
                end)
                bossBtn:SetScript("OnLeave", GameTooltip_Hide)
            end
        end end  -- closes the for-WORLD_BOSSES and the `if not hideWB`

        -- Remove-character button (far right)
        local deleteBtn = CreateFrame("Button", nil, row)
        deleteBtn:SetSize(SI, SI)
        deleteBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        deleteBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove Character")
            GameTooltip:Show()
        end)
        deleteBtn:SetScript("OnLeave", GameTooltip_Hide)
        deleteBtn:SetScript("OnClick", function()
            JoguDB.characters[char.key] = nil
            UpdateExpandedPanel()
        end)

        table.insert(scrollChild.rows, row)
        yOffset = yOffset - STRIDE
    end

    -- Scroll child must cover the rows in both modes (central pushes them down by -startOffset).
    local contentH = (-startOffset) + n * STRIDE
    scrollChild:SetHeight(math.max(1, contentH))

    -- Show the scrollbar whenever content overflows the viewport, in either alignment mode.
    local frameHeight = scrollFrame:GetHeight()
    if contentH > frameHeight then
        scrollFrame.ScrollBar:Show()
    else
        scrollFrame.ScrollBar:Hide()
    end
end

-- (v1.1: the separate "Jogu Knows More" world boss panel was removed. World boss tracking is
-- now part of the single combined window, rendered per character by UpdateExpandedPanel above.
-- The FRAME_*_WIDTH constants are declared near the top of the file so UpdateExpandedPanel,
-- which runs before this point, can see them too.)

-- Resize the frame and hide the world-boss column for the "Hide world bosses" toggle.
ApplyWorldBossVisibility = function()
    if not JoguFrame then return end
    local hidden = JoguDB and JoguDB.hideWorldBosses
    local rightW = hidden and FRAME_RIGHT_WIDTH_NARROW or FRAME_RIGHT_WIDTH
    JoguFrame:SetWidth(FRAME_LEFT_WIDTH + rightW)
    if JoguFrame.altScrollChild then
        JoguFrame.altScrollChild:SetWidth(rightW - 40)
    end
    if JoguFrame.bossHeaders then
        for _, h in ipairs(JoguFrame.bossHeaders) do
            if hidden then h:Hide() else h:Show() end
        end
    end
    if UpdateExpandedPanel then UpdateExpandedPanel() end
end

-- Cascade the enabled state of the message-filter controls:
-- "Show prediction on login" gates "Only message for specific crops", which gates the picker "?".
ApplyMessageFilterEnabled = function()
    if not JoguFrame then return end
    local showOn = JoguFrame.checkbox and JoguFrame.checkbox:GetChecked()
    if JoguFrame.onlyMessageCheckbox then
        if showOn then
            JoguFrame.onlyMessageCheckbox:Enable()
            JoguFrame.onlyMessageCheckbox:SetAlpha(1)
            JoguFrame.onlyMessageLabel:SetTextColor(0.9, 0.9, 0.9)
        else
            JoguFrame.onlyMessageCheckbox:Disable()
            JoguFrame.onlyMessageCheckbox:SetAlpha(0.5)
            JoguFrame.onlyMessageLabel:SetTextColor(0.4, 0.4, 0.4)
        end
    end
    local pickerOn = showOn and JoguFrame.onlyMessageCheckbox and JoguFrame.onlyMessageCheckbox:GetChecked()
    if JoguFrame.pickerBtn then
        -- Keep the button mouse-enabled so its tooltip still appears on hover when greyed; the
        -- pickerBtn:OnClick has the actual click gate.
        JoguFrame.pickerBtn:SetAlpha(pickerOn and 1 or 0.5)
        if not pickerOn and cropPickerMode then
            -- Picker was active and we're disabling -- exit picker mode cleanly.
            cropPickerMode = false
            JoguFrame.pickerBtn:SetText("?")
            if JoguFrame.calibrateBtn then JoguFrame.calibrateBtn:SetText("?") end
            SetCalibrationFade(false)
            if UpdateJoguUI then UpdateJoguUI() end
        end
    end
end

local function CreateJoguFrame()
    local frame = CreateFrame("Frame", "JoguMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_TOTAL_WIDTH, FRAME_HEIGHT)

    -- UIPanelLayout for profession-like window management
    frame:SetAttribute("UIPanelLayout-defined", true)
    frame:SetAttribute("UIPanelLayout-enabled", true)
    frame:SetAttribute("UIPanelLayout-area", "left")
    frame:SetAttribute("UIPanelLayout-pushable", 5)
    frame:SetAttribute("UIPanelLayout-whileDead", true)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Closing the window while in crop-picker mode saves the current selection (selections are
    -- toggled live anyway) and exits picker mode, so reopening /jogu always shows the normal UI.
    frame:SetScript("OnHide", function()
        if cropPickerMode then
            cropPickerMode = false
            if frame.pickerBtn then frame.pickerBtn:SetText("?") end
            if frame.calibrateBtn then frame.calibrateBtn:SetText("?") end
            SetCalibrationFade(false)
            ApplyMessageFilterEnabled()
        end
    end)

    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    tinsert(UISpecialFrames, "JoguMainFrame")

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- ===== LEFT COLUMN: crop prediction =====

    -- Title "Jogu Knows" centred over the left column (no separate title bar)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOPLEFT", 190, -16)
    frame.title:SetText("Jogu Knows")
    frame.title:SetTextColor(1, 0.82, 0)

    -- Close button (top-right corner)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        HideUIPanel(frame)
    end)

    -- Flavor text, centred over the left column under the title
    frame.flavorText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.flavorText:SetPoint("TOP", frame, "TOPLEFT", 190, -42)
    frame.flavorText:SetWidth(350)
    frame.flavorText:SetJustifyH("CENTER")
    frame.flavorText:SetText(FLAVOR_TEXT)
    frame.flavorText:SetTextColor(0.9, 0.9, 0.9)

    -- Crop wheel (square item icons, labels below; today's bonus crop gets the gold glow)
    frame.cropButtons = {}
    frame.cropLabels = {}
    local centerX, centerY = 190, 272
    local radius = 116

    -- Soft golden glow for tomorrow's bonus crop, using Blizzard's own action-button glow
    -- texture (UI-ActionButton-Border, additive). Drawn BEHIND the icon and sized well larger
    -- than it (our icon fills its whole 36px button, unlike Blizzard's smaller-icon buttons),
    -- so the glow's bright ring clears the icon edge and shows only as an outward halo.
    -- GLOW_SIZE tunes how far the halo spreads (bigger = reaches further out).
    local GLOW_SIZE = 74

    for i = 1, 10 do
        local angle = (i - 1) * (2 * math.pi / 10) - (math.pi / 2)
        local x = centerX + radius * math.cos(angle)
        local y = centerY + radius * math.sin(angle)
        
        local btn = CreateFrame("Button", "JoguCropButton"..i, frame)
        btn:SetSize(40, 40)
        btn:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
        
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        btn.icon = icon
        btn.itemID = CROPS[i].id
        
        -- Golden glow: Blizzard's soft action-button glow texture (additive), gold-tinted,
        -- sized larger than the icon and centred. Drawn BEHIND the icon (BACKGROUND layer) so
        -- the icon covers the inner part and only the halo spilling PAST the icon edge shows --
        -- i.e. it radiates outward, not inward. Shown only for tomorrow's bonus crop.
        btn.glow = btn:CreateTexture(nil, "BACKGROUND")
        btn.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        btn.glow:SetBlendMode("ADD")
        btn.glow:SetVertexColor(1, 0.82, 0)
        btn.glow:SetSize(GLOW_SIZE, GLOW_SIZE)
        btn.glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.glow:Hide()

        -- Crop label - ALWAYS below icon, centered
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
        label:SetWidth(80)
        label:SetJustifyH("CENTER")
        label:SetText(CROPS[i].name)
        label:SetTextColor(1, 1, 1)
        frame.cropLabels[i] = label
        
        btn.cropIndex = i
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(CROPS[self.cropIndex].id)
            if calibrationMode then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to set as today's bonus crop", 0, 1, 0)
            elseif cropPickerMode then
                GameTooltip:AddLine(" ")
                if JoguDB.selectedCrops and JoguDB.selectedCrops[self.cropIndex] then
                    GameTooltip:AddLine("Click to remove from message filter", 1, 0.6, 0.6)
                else
                    GameTooltip:AddLine("Click to add to message filter", 0.6, 1, 0.6)
                end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        btn:SetScript("OnClick", function(self)
            if calibrationMode then
                -- Save calibration for this region (NOT this realm). Every realm in the same
                -- region shares the same cycle, so the region-keyed entry covers all of them
                -- and makes per-realm drift impossible.
                local region = GetCurrentRegion and GetCurrentRegion() or 1
                JoguDB.regionCalibration = JoguDB.regionCalibration or {}
                JoguDB.regionCalibration[region] = {
                    cropIndex = self.cropIndex,
                    epochDay = GetCurrentEpochDay(),
                    cycleVersion = CYCLE_VERSION,
                }

                -- Exit calibration mode
                calibrationMode = false
                JoguFrame.calibrateBtn:SetText("?")
                SetCalibrationFade(false)
                UpdateJoguUI()

                print("|cFF00FF00[Jogu Knows]|r Calibrated for your region: today's bonus crop is " .. CROPS[self.cropIndex].name)
            elseif cropPickerMode then
                -- Multi-select toggle for the "Only message for specific crops" filter.
                JoguDB.selectedCrops = JoguDB.selectedCrops or {}
                if JoguDB.selectedCrops[self.cropIndex] then
                    JoguDB.selectedCrops[self.cropIndex] = nil
                else
                    JoguDB.selectedCrops[self.cropIndex] = true
                end
                UpdateJoguUI()
            end
        end)
        
        frame.cropButtons[i] = btn
    end

    -- "Plant today" text, centred below the wheel (original layout). The "?" hugs its left edge.
    frame.plantText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.plantText:SetPoint("TOP", frame, "TOPLEFT", 190, -432)
    frame.plantText:SetTextColor(1, 0.82, 0)

    -- Calibration "?" button, sitting just left of the plant text (as before). The bell and the
    -- login checkbox below anchor to THIS button's left edge, so all three line up vertically.
    frame.calibrateBtn = CreateFrame("Button", "JoguCalibrateButton", frame, "UIPanelButtonTemplate")
    frame.calibrateBtn:SetPoint("RIGHT", frame.plantText, "LEFT", -10, 0)
    frame.calibrateBtn:SetSize(30, 22)
    frame.calibrateBtn:SetText("?")
    frame.calibrateBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Manually calibrate crop", 1, 0.82, 0)
        GameTooltip:AddLine("Select the bonus crop on your server for TODAY to synch the cycle to your server if it is incorrect. You only need to do this once.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.calibrateBtn:SetScript("OnLeave", GameTooltip_Hide)
    frame.calibrateBtn:SetScript("OnClick", function()
        -- During crop-picker mode this button shows a tick; clicking it exits the picker.
        if cropPickerMode then
            cropPickerMode = false
            frame.pickerBtn:SetText("?")
            frame.calibrateBtn:SetText("?")
            SetCalibrationFade(false)
            ApplyMessageFilterEnabled()
            UpdateJoguUI()
            return
        end
        calibrationMode = not calibrationMode
        if calibrationMode then
            frame.calibrateBtn:SetText("X")
            frame.plantText:SetText("What was today's bonus crop?")
            frame.plantText:SetTextColor(0.5, 0.8, 1)
            SetCalibrationFade(true)
        else
            frame.calibrateBtn:SetText("?")
            SetCalibrationFade(false)
            ApplyMessageFilterEnabled()
            UpdateJoguUI()
        end
    end)

    -- Timer text, centred under the plant line
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.timerText:SetPoint("TOP", frame, "TOPLEFT", 190, -456)
    frame.timerText:SetTextColor(0.8, 0.8, 0.8)

    -- Separator line. Always shown; its Y is set in UpdateJoguUI: with the Nomi bell present it
    -- sits above the bell (-488); with no bell it is centred between the timer and the checkboxes
    -- (-514).
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOP", frame, "TOPLEFT", 190, -488)
    separator:SetSize(320, 1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    frame.separator = separator

    -- Nomi section (shown only when the Cooking School Bell is in bags). 50px tall with the bell
    -- centred, so TOP at -491 puts the bell centre at -516.
    frame.nomiSection = CreateFrame("Frame", nil, frame)
    frame.nomiSection:SetPoint("TOP", frame, "TOPLEFT", 190, -491)
    frame.nomiSection:SetSize(340, 50)
    frame.nomiSection:Hide()

    -- Clickable bell button (SecureActionButton) to summon Nomi
    frame.bellButton = CreateFrame("Button", "JoguBellButton", frame.nomiSection, "SecureActionButtonTemplate")
    -- Bell anchored to its parent nomiSection's LEFT edge (parent = ancestor, secure-safe).
    -- nomiSection is TOP-anchored to the column centre at x=190, so when UpdateJoguUI sizes the
    -- section to "bell + gap + text width", the whole bell+nomi-text group auto-centres in the
    -- left column. Y offset +12 puts the bell centre at y=-504 (the section's centre is -516).
    frame.bellButton:SetPoint("LEFT", frame.nomiSection, "LEFT", 0, 12)
    frame.bellButton:SetSize(32, 32)
    frame.bellButton:SetAttribute("type", "item")
    frame.bellButton:SetAttribute("item", "Cooking School Bell")

    local bellIcon = frame.bellButton:CreateTexture(nil, "ARTWORK")
    bellIcon:SetAllPoints()
    bellIcon:SetTexture(GetItemIcon(COOKING_SCHOOL_BELL_ID))
    frame.bellButton.icon = bellIcon

    frame.bellButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    frame.bellButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(COOKING_SCHOOL_BELL_ID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to summon Nomi", 0, 1, 0)
        GameTooltip:Show()
    end)
    frame.bellButton:SetScript("OnLeave", GameTooltip_Hide)

    -- Nomi status text
    frame.nomiText = frame.nomiSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.nomiText:SetPoint("LEFT", frame.bellButton, "RIGHT", 10, 0)
    frame.nomiText:SetWidth(250)
    frame.nomiText:SetJustifyH("LEFT")

    -- ===== RIGHT COLUMN: combined roster =====

    -- Vertical divider between the two columns
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOP", frame, "TOPLEFT", FRAME_LEFT_WIDTH, -12)
    divider:SetPoint("BOTTOM", frame, "BOTTOMLEFT", FRAME_LEFT_WIDTH, 12)
    divider:SetWidth(1)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    -- Light divider inside the roster (abs x744): daily columns (Cooldowns/Farmed/Ironpaw) to its
    -- left, weekly world bosses to its right. A thin frame above the rows keeps it visible.
    local rosterDivider = CreateFrame("Frame", nil, frame)
    rosterDivider:SetPoint("TOP", frame, "TOPLEFT", 744, -12)
    rosterDivider:SetPoint("BOTTOM", frame, "BOTTOMLEFT", 744, 12)
    rosterDivider:SetWidth(1)
    rosterDivider:SetFrameLevel(frame:GetFrameLevel() + 5)
    local rosterDividerTex = rosterDivider:CreateTexture(nil, "OVERLAY")
    rosterDividerTex:SetAllPoints()
    rosterDividerTex:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    -- Hidden for now per Paul: the divider line isn't shown, but the frame is kept as an
    -- alignment anchor between the daily and world-boss sub-sections. Re-show with :Show() (or
    -- comment out this line) when refining the spacing between the two sides.
    rosterDividerTex:Hide()

    -- Column headers. Same font/size as the "Jogu Knows" title (GameFontNormalLarge) and on the
    -- same baseline (headerY = the title's y) so the title and every header sit on one line.
    -- frameX values are absolute (scroll area begins at FRAME_LEFT_WIDTH + 10 = 390); each header
    -- is centred over its row-local column (see the *_X tables in UpdateExpandedPanel).
    -- Column headers (GameFontNormalLarge). Stored in frame.colHeaders {h=fontstring, x=frameX} so
    -- UpdateExpandedPanel can move them: at the top (-16) in top-aligned mode, or down just above
    -- the first row in central mode.
    frame.colHeaders = {}
    local function MakeHeader(frameX, text)
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        h:SetPoint("TOP", frame, "TOPLEFT", frameX, -16)
        h:SetText(text)
        h:SetTextColor(1, 0.82, 0)
        table.insert(frame.colHeaders, { h = h, x = frameX })
        return h
    end
    -- Daily columns (evenly spaced) on the left of the roster divider; no "Character" header.
    MakeHeader(563, "Cooldowns")
    MakeHeader(636, "Farm")
    MakeHeader(690, "Ironpaw")

    -- World boss column headers (abbreviations) on the right of the roster divider. Ord stays at
    -- 955, Nal at 767, Oon/CC evenly between. Future-content bosses (CC, Ordos) stay greyed until
    -- their first kill; UpdateExpandedPanel re-colours these.
    frame.bossHeaders = {}
    local bossHeaderX = { 767, 830, 892, 955 }
    for i, boss in ipairs(WORLD_BOSSES) do
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        h:SetPoint("TOP", frame, "TOPLEFT", bossHeaderX[i], -16)
        h:SetWidth(40)
        h:SetJustifyH("CENTER")
        h:SetText(boss.name)
        if boss.futureContent and not (JoguDB.bossEverKilled and JoguDB.bossEverKilled[boss.questID]) then
            h:SetTextColor(0.4, 0.4, 0.4)
        else
            h:SetTextColor(1, 0.82, 0)
        end
        frame.bossHeaders[i] = h
        table.insert(frame.colHeaders, { h = h, x = bossHeaderX[i] })
    end

    -- Scroll frame for the roster (right column)
    local altScrollFrame = CreateFrame("ScrollFrame", "JoguAltScrollFrame", frame, "UIPanelScrollFrameTemplate")
    -- Top at -42 so the first row's colour bar lines up with the top of the flavour text (-42)
    altScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_LEFT_WIDTH + 10, -42)
    altScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 18)
    frame.altScrollFrame = altScrollFrame

    local altScrollChild = CreateFrame("Frame", nil, altScrollFrame)
    altScrollChild:SetSize(FRAME_RIGHT_WIDTH - 40, 1)
    altScrollFrame:SetScrollChild(altScrollChild)
    frame.altScrollChild = altScrollChild

    -- Bottom-left controls: 2 columns x 2 rows of 24x24 checkboxes, vertically aligned.
    --   Left column (x=25):   Row 1 "Show prediction on login"  / Row 2 "Specific crops" + "?"
    --   Right column (x=215): Row 1 "Characters align top"      / Row 2 "Hide world bosses"

    -- Row 1 left -- Show prediction on login
    frame.checkbox = CreateFrame("CheckButton", "JoguLoginCheckbox", frame, "UICheckButtonTemplate")
    frame.checkbox:SetSize(24, 24)
    frame.checkbox:SetPoint("BOTTOMLEFT", 25, 46)
    frame.checkbox:SetChecked(JoguDB and JoguDB.showLoginMessage or false)
    frame.checkbox:SetScript("OnClick", function(self)
        JoguDB.showLoginMessage = self:GetChecked() and true or false
        ApplyMessageFilterEnabled()
    end)

    frame.checkboxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.checkboxLabel:SetPoint("LEFT", frame.checkbox, "RIGHT", 5, 0)
    frame.checkboxLabel:SetText("Show prediction on login")
    frame.checkboxLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Row 1 right -- Characters align top (vertically above Hide world bosses)
    frame.alignTopCheckbox = CreateFrame("CheckButton", "JoguAlignTopCheckbox", frame, "UICheckButtonTemplate")
    frame.alignTopCheckbox:SetSize(24, 24)
    frame.alignTopCheckbox:SetPoint("BOTTOMLEFT", 215, 46)
    frame.alignTopCheckbox:SetChecked(not JoguDB or JoguDB.alignTop ~= false)
    frame.alignTopCheckbox:SetScript("OnClick", function(self)
        JoguDB.alignTop = self:GetChecked() and true or false
        UpdateExpandedPanel()
    end)

    frame.alignTopLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.alignTopLabel:SetPoint("LEFT", frame.alignTopCheckbox, "RIGHT", 5, 0)
    frame.alignTopLabel:SetText("Characters align top")
    frame.alignTopLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Row 2 left -- Specific crops (+ picker "?"). Anchored right-to-left: the picker "?" right
    -- edge aligns with the end of "Show prediction on login" above (indicating dependency), then
    -- the "Specific crops" label and its checkbox chain leftward from it.
    frame.pickerBtn = CreateFrame("Button", "JoguCropPickerButton", frame, "UIPanelButtonTemplate")
    frame.pickerBtn:SetPoint("RIGHT", frame.checkboxLabel, "RIGHT", 0, -32)
    frame.pickerBtn:SetSize(22, 22)
    frame.pickerBtn:SetText("?")
    frame.pickerBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Only show login message for selected crops", 1, 0.82, 0)
        GameTooltip:AddLine("Click to enter picker mode, then click crops in the wheel to toggle their selection. Click the tick on either this button or the cycle-calibration button to save and exit.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.pickerBtn:SetScript("OnLeave", GameTooltip_Hide)
    frame.pickerBtn:SetScript("OnClick", function(self)
        -- Greyed when prerequisites aren't met; the button stays mouse-enabled so the tooltip
        -- still shows on hover, but the click is gated here.
        if not (JoguDB and JoguDB.showLoginMessage and JoguDB.onlySelectedCrops) then return end
        if calibrationMode then  -- exit calibration if it was active
            calibrationMode = false
            JoguFrame.calibrateBtn:SetText("?")
            SetCalibrationFade(false)
        end
        cropPickerMode = not cropPickerMode
        if cropPickerMode then
            -- Enter picker: tick on both buttons, grey the rest of the UI. UpdateJoguUI applies
            -- the green prompt text and the wheel label colours (green > gold inside picker), so
            -- already-selected crops show green from the moment picker mode opens.
            self:SetText([[|TInterface\RaidFrame\ReadyCheck-Ready:0|t]])
            JoguFrame.calibrateBtn:SetText([[|TInterface\RaidFrame\ReadyCheck-Ready:0|t]])
            SetCalibrationFade(true)
            UpdateJoguUI()
        else
            -- Exit picker: restore buttons, plant text, normal alpha.
            self:SetText("?")
            JoguFrame.calibrateBtn:SetText("?")
            SetCalibrationFade(false)
            ApplyMessageFilterEnabled()
            UpdateJoguUI()
        end
    end)

    -- "Specific crops" label, right-anchored to the picker "?" (chain reverses for indent).
    frame.onlyMessageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.onlyMessageLabel:SetPoint("RIGHT", frame.pickerBtn, "LEFT", -6, 0)
    frame.onlyMessageLabel:SetText("Specific crops")
    frame.onlyMessageLabel:SetTextColor(0.9, 0.9, 0.9)

    -- "Specific crops" checkbox, right-anchored to the label so the whole "[box] Specific crops [?]"
    -- group ends at the same x as "Show prediction on login" above.
    frame.onlyMessageCheckbox = CreateFrame("CheckButton", "JoguOnlyMessageCheckbox", frame, "UICheckButtonTemplate")
    frame.onlyMessageCheckbox:SetSize(24, 24)
    frame.onlyMessageCheckbox:SetPoint("RIGHT", frame.onlyMessageLabel, "LEFT", -5, 0)
    frame.onlyMessageCheckbox:SetChecked(JoguDB and JoguDB.onlySelectedCrops or false)
    frame.onlyMessageCheckbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        JoguDB.onlySelectedCrops = checked
        if not checked then
            -- Filter turned off -> clear the selection and restore default wheel label colours.
            JoguDB.selectedCrops = {}
            if UpdateJoguUI then UpdateJoguUI() end
        end
        ApplyMessageFilterEnabled()
    end)

    -- Row 2 right -- Hide world bosses (vertically aligned with Characters align top)
    frame.hideBossesCheckbox = CreateFrame("CheckButton", "JoguHideBossesCheckbox", frame, "UICheckButtonTemplate")
    frame.hideBossesCheckbox:SetSize(24, 24)
    frame.hideBossesCheckbox:SetPoint("BOTTOMLEFT", 215, 15)
    frame.hideBossesCheckbox:SetChecked(JoguDB and JoguDB.hideWorldBosses or false)
    frame.hideBossesCheckbox:SetScript("OnClick", function(self)
        JoguDB.hideWorldBosses = self:GetChecked() and true or false
        ApplyWorldBossVisibility()
    end)

    frame.hideBossesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.hideBossesLabel:SetPoint("LEFT", frame.hideBossesCheckbox, "RIGHT", 5, 0)
    frame.hideBossesLabel:SetText("Hide world bosses")
    frame.hideBossesLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Apply initial cascade state for the message-filter checkboxes.
    ApplyMessageFilterEnabled()

    return frame
end

local function LoadItemIcons()
    if not JoguFrame then return end
    for i = 1, 10 do
        local btn = JoguFrame.cropButtons[i]
        local itemID = CROPS[i].id
        local icon = GetItemIcon(itemID)
        if icon then
            btn.icon:SetTexture(icon)
        else
            local item = Item:CreateFromItemID(itemID)
            item:ContinueOnItemLoad(function()
                btn.icon:SetTexture(GetItemIcon(itemID))
            end)
        end
    end
end

-- Full UI update - called only when panel opens
UpdateJoguUI = function()
    if not JoguFrame then return end

    local tomorrowDay = GetTomorrowBonusDay()

    -- Wheel highlights + label colours. The gold glow on today's bonus crop is independent of
    -- label colour (it always shows). Label colour rules:
    --   * Outside crop-picker mode: today's bonus = gold (overrides green); selected = green; rest white.
    --   * Inside crop-picker mode:  selected = green (overrides today's gold); today (if not selected) = gold; rest white.
    for i = 1, 10 do
        local isToday = (i == tomorrowDay)
        local isSelected = JoguDB.selectedCrops and JoguDB.selectedCrops[i]
        if isToday then
            JoguFrame.cropButtons[i].glow:Show()
        else
            JoguFrame.cropButtons[i].glow:Hide()
        end
        if cropPickerMode and isSelected then
            JoguFrame.cropLabels[i]:SetTextColor(0.3, 1, 0.3)
            JoguFrame.cropLabels[i]:SetFont("Fonts\\FRIZQT__.TTF", 9)
        elseif isToday then
            JoguFrame.cropLabels[i]:SetTextColor(1, 0.82, 0)
            JoguFrame.cropLabels[i]:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        elseif isSelected then
            JoguFrame.cropLabels[i]:SetTextColor(0.3, 1, 0.3)
            JoguFrame.cropLabels[i]:SetFont("Fonts\\FRIZQT__.TTF", 9)
        else
            JoguFrame.cropLabels[i]:SetTextColor(1, 1, 1)
            JoguFrame.cropLabels[i]:SetFont("Fonts\\FRIZQT__.TTF", 9)
        end
    end

    -- Plant text. In picker mode we always show the green prompt (so it doesn't revert to
    -- "Plant X today!" when the user toggles a crop, which retriggers UpdateJoguUI). In
    -- calibration mode the calibrate button's OnClick has already set the prompt ("What was
    -- today's bonus crop?") so leave it alone here. Otherwise show the normal prediction.
    if calibrationMode then
        -- left as-is
    elseif cropPickerMode then
        JoguFrame.plantText:SetText("Select crops for alerts")
        JoguFrame.plantText:SetTextColor(0.3, 1, 0.3)
    else
        JoguFrame.plantText:SetText("Plant " .. CROPS[tomorrowDay].name .. " today!")
        JoguFrame.plantText:SetTextColor(1, 0.82, 0)
    end

    -- Nomi section + separator (fixed frame height). With the Cooking School Bell present, the
    -- bell/Nomi line shows and the separator sits above it (-488). With no bell, the bell/Nomi
    -- line is hidden and the separator is centred between the timer and the checkboxes (-514).
    -- Separator + Nomi line. Two checkbox rows below (FRAME_HEIGHT 600); upper-row top at y=-530.
    -- With the bell: separator above it (-478), bell centred at -504 with ~10px gaps to both.
    -- Without the bell: separator centred between the timer and the upper checkbox row (-500).
    JoguFrame.separator:ClearAllPoints()
    if HasCookingSchoolBell() then
        JoguFrame.separator:SetPoint("TOP", JoguFrame, "TOPLEFT", 190, -478)
        JoguFrame.nomiSection:Show()
        if IsNomiQuestCompletedToday() then
            JoguFrame.nomiText:SetText("You have spoken to Nomi today.")
            JoguFrame.nomiText:SetTextColor(0.5, 1, 0.5)
        else
            JoguFrame.nomiText:SetText("You haven't spoken to Nomi today.")
            JoguFrame.nomiText:SetTextColor(1, 0.5, 0.5)
        end
        -- Centre the bell + Nomi text horizontally in the left column. nomiSection is TOP-anchored
        -- at the column's centre (x=190), so resizing its width re-centres it; the bell anchors to
        -- nomiSection's LEFT and the text follows the bell (LEFT to bell RIGHT, gap 10), so the
        -- visible group width is bell(32) + gap(10) + textWidth. Setting the section to that width
        -- puts the bell's left edge at (190 - W/2) and the text's right edge at (190 + W/2).
        local textWidth = JoguFrame.nomiText:GetStringWidth()
        JoguFrame.nomiSection:SetWidth(32 + 10 + textWidth)
    else
        JoguFrame.separator:SetPoint("TOP", JoguFrame, "TOPLEFT", 190, -500)
        JoguFrame.nomiSection:Hide()
    end

    -- Set initial timer
    -- Timer line. Picker mode replaces the countdown with a white "save" hint; otherwise the
    -- normal countdown is shown (its colour comes from SetCalibrationFade / default).
    if cropPickerMode then
        JoguFrame.timerText:SetText("Click the tick to save selection")
        JoguFrame.timerText:SetTextColor(1, 1, 1)
    else
        JoguFrame.timerText:SetText("Crops ripe in: " .. FormatTime(GetSecondsUntilReset()))
    end
end

local function ToggleJoguFrame()
    if not JoguFrame then return end

    if JoguFrame:IsVisible() then
        HideUIPanel(JoguFrame)
    else
        ShowUIPanel(JoguFrame)
        ApplyWorldBossVisibility()  -- applies saved hide state and renders the roster
        UpdateJoguUI()
    end
end

SLASH_JOGU1 = "/jogu"
SlashCmdList["JOGU"] = ToggleJoguFrame

-- Same-frame crop-loot aggregation (see CHAT_MSG_LOOT). A harvested plant's yield can
-- arrive as several loot lines in ONE frame when it splits across inventory stacks
-- (e.g. 8 -> 1 + 7). We sum per crop and evaluate the TOTAL once, on the next frame,
-- so a split is read as the real 8 (normal plump) and never mistaken for a bonus-day 7.
local pendingCropLoot = {}
local pendingCropFlush = false
local function FlushCropLoot()
    pendingCropFlush = false
    local harvested = false
    local calibratedCrop = nil
    for cropIndex, qty in pairs(pendingCropLoot) do
        pendingCropLoot[cropIndex] = nil
        -- A real single-plant harvest totals 5..10. Ignore partials/sums outside that range.
        if qty >= 5 and qty <= 10 then
            harvested = true
            -- Auto-calibration: a total of 7 or 10 means this crop IS today's bonus crop.
            -- Save it region-keyed (NOT per-realm) so every realm in the user's region
            -- benefits from this character's correction. Also fires when predictedToday is nil
            -- (no anchor known for this region yet) -- the harvest IS the anchor in that case.
            if qty == 7 or qty == 10 then
                local _, predictedToday = GetTomorrowBonusDay()
                if predictedToday ~= cropIndex then
                    local region = GetCurrentRegion and GetCurrentRegion() or 1
                    JoguDB.regionCalibration = JoguDB.regionCalibration or {}
                    JoguDB.regionCalibration[region] = {
                        cropIndex = cropIndex,
                        epochDay = GetCurrentEpochDay(),
                        cycleVersion = CYCLE_VERSION,
                    }
                    calibratedCrop = CROPS[cropIndex].name
                end
            end
        end
    end
    if harvested then
        MarkHarvested()
    end
    if calibratedCrop then
        print("|cFF00FF00[Jogu Knows]|r Auto-calibrated! Detected " .. calibratedCrop .. " as today's bonus crop.")
    end
    if (harvested or calibratedCrop) and JoguFrame and JoguFrame:IsVisible() then
        UpdateJoguUI()
        UpdateExpandedPanel()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "Jogu" then
        Jogu_OnLoad()
        
    elseif event == "PLAYER_LOGIN" then
        -- Create frame at login (hidden) so it's ready when /jogu is used
        JoguFrame = CreateJoguFrame()
        JoguFrame:Hide()
        LoadItemIcons()

        -- Refresh world boss + profession data for this character if they're already on the
        -- Jogu roster. We do NOT create the entry here -- a character only earns their spot
        -- on the list by performing a qualifying farm action (harvest crops or Ironpaw daily).
        -- The scanners call RegisterCharacter(false) internally and no-op if not tracked.
        local level = UnitLevel("player")
        if level >= 86 then
            UpdateWorldBossStatus()
            UpdateProfessions()
        end
        
        if JoguDB and JoguDB.showLoginMessage then
            local tomorrowDay = GetTomorrowBonusDay()
            -- "Only message for specific crops" filter: suppress unless tomorrow's crop is selected.
            local pass = true
            if JoguDB.onlySelectedCrops and not (JoguDB.selectedCrops and JoguDB.selectedCrops[tomorrowDay]) then
                pass = false
            end
            if pass then
                local cropData = CROPS[tomorrowDay]
                local itemLink = select(2, GetItemInfo(cropData.id))
                if itemLink then
                    print("|cFF00FF00[Jogu Knows]|r Plant " .. itemLink .. " today for bonus crops tomorrow!")
                else
                    local item = Item:CreateFromItemID(cropData.id)
                    item:ContinueOnItemLoad(function()
                        local link = select(2, GetItemInfo(cropData.id))
                        print("|cFF00FF00[Jogu Knows]|r Plant " .. (link or cropData.name) .. " today for bonus crops tomorrow!")
                    end)
                end
            end
        end
        
    elseif event == "QUEST_TURNED_IN" then
        local questID = arg1
        -- Track Master Token daily quest completion (level 90 only)
        if MASTER_TOKEN_QUESTS[questID] and UnitLevel("player") == 90 then
            MarkMasterToken()
        end
        -- Record per-character Nomi daily completion when any tracked Nomi quest is turned in
        if NOMI_QUEST_IDS[questID] then
            MarkNomi()
        end
        -- World-boss weekly credit. The kill auto-turns-in a hidden weekly quest (e.g. 32518
        -- for Nalak). When that questID flows through here we re-scan the roster's boss flags
        -- live, so the icon flips full-colour straight away instead of waiting for the next
        -- /reload. UpdateWorldBossStatus calls RegisterCharacter(false) and no-ops if this
        -- character isn't on the Jogu list yet, which preserves the farm-action-only gate.
        for _, boss in ipairs(WORLD_BOSSES) do
            if questID == boss.questID then
                UpdateWorldBossStatus()
                break
            end
        end

    elseif event == "QUEST_ACCEPTED" then
        -- arg1 is questID on modern clients, or questLogIndex on legacy (with questID as arg2)
        local questID = (arg1 and arg1 > 10000) and arg1 or select(1, ...)
        -- Easter egg: Truffle Shuffle pickup (chat message only -- the MoP Classic map UI
        -- predates the native user-waypoint pin system, so no map pin is placed).
        if questID == TRUFFLE_SHUFFLE_QUEST_ID then
            print("|cFF00FF00[Jogu Knows]|r Planting and picking, share the mushrooms, please do - set your spores down at 32, 32!")
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Refresh the current character's cooldown icons the instant a tracked daily craft is
        -- cast, so it goes full-colour without waiting for the next login. Payload (MoP Classic
        -- 5.5.3): arg1 = unitTarget, then castGUID, spellID.
        if arg1 == "player" then
            local spellID = select(2, ...)
            if spellID and TRACKED_COOLDOWN_SPELLS[spellID] then
                -- The cooldown can register a frame after the cast succeeds; re-read shortly after.
                C_Timer.After(0.5, UpdateProfessions)
            end
        end

    elseif event == "CHAT_MSG_LOOT" then
        -- Track Sunsong Ranch harvests (level 86+)
        local level = UnitLevel("player")
        if level < 86 then return end
        
        -- Constraint 1: Must be at Sunsong Ranch
        local subzone = GetSubZoneText()
        if subzone ~= "Sunsong Ranch" then return end
        
        local lootMessage = arg1
        -- Parse "You receive loot: |cXX|Hitem:ITEMID:...|h[Name]|h|rxQTY" or without xQTY
        local itemID = lootMessage:match("|Hitem:(%d+):")
        local quantity = lootMessage:match("x(%d+)")
        
        if not itemID then return end
        itemID = tonumber(itemID)
        local qty = tonumber(quantity) or 1
        
        -- Core crops: accumulate this frame's loot per crop, then evaluate the TOTAL in
        -- FlushCropLoot (next frame). A single plant's yield can split across inventory
        -- stacks into multiple same-frame loot lines (e.g. 8 -> 1 + 7); summing the total
        -- stops the 7-fragment being mistaken for a bonus-day harvest and auto-calibrating.
        for cropIndex, crop in ipairs(CROPS) do
            if crop.id == itemID then
                pendingCropLoot[cropIndex] = (pendingCropLoot[cropIndex] or 0) + qty
                if not pendingCropFlush then
                    pendingCropFlush = true
                    C_Timer.After(0, FlushCropLoot)
                end
                return
            end
        end
        
        -- Constraint 3: Edge seeds mark as harvested regardless of quantity
        if EDGE_SEEDS[itemID] then
            MarkHarvested()
            return
        end
    end
end)
