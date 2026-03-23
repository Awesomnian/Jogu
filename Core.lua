-- Jogu Knows: Crop Prediction Addon for MoP Classic
-- Predicts tomorrow's bonus crop for Sunsong Ranch
-- Interface: 50400 (MoP Classic)
-- Version: 1.0 - World Boss Tracking + UI Polish

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
local TRUFFLE_SHUFFLE_QUEST_ID = 30330
local VALLEY_OF_FOUR_WINDS_MAP_ID = 376
local REFERENCE_EPOCH_DAY = 20457

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
local WORLD_BOSSES = {
    {name = "Sha", fullName = "Sha of Anger", questID = 32099},
    {name = "Gal", fullName = "Galleon", questID = 32098},
    {name = "Nal", fullName = "Nalak", questID = 32518},
    {name = "Oon", fullName = "Oondasta", questID = 32519},
    {name = "Ord", fullName = "Ordos", questID = 33117, futureContent = true},
}

local JoguFrame = nil
local worldBossPanel = nil
local calibrationMode = false
local UpdateJoguUI  -- Forward declaration
local UpdateExpandedPanel  -- Forward declaration
local UpdateWorldBossPanel  -- Forward declaration
local GetCurrentEpochDay  -- Forward declaration
local GetCurrentWeekEpoch  -- Forward declaration

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
end

local FLAVOR_TEXT = "Whilst our friend Jogu is in rehab, largely due to your enablement, here's a handy guide to show you what to plant today to receive bonus crops tomorrow.\n\nStandard crops produce 5 items, a 'plump' proc gives +3 and bonus crops give +2. These stack."

local FRAME_HEIGHT_WITH_BELL = 580
local FRAME_HEIGHT_NO_BELL = 520

function Jogu_OnLoad()
    if not JoguDB then
        JoguDB = { 
            showLoginMessage = false, 
            realmCalibration = {},
            characters = {}  -- Alt tracking data
        }
    end
    if not JoguDB.realmCalibration then
        JoguDB.realmCalibration = {}
    end
    if not JoguDB.characters then
        JoguDB.characters = {}
    end
    -- ordosEverKilled defaults to nil/false, set true on first Ordos kill
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

-- Register or update character in tracking database
local function RegisterCharacter()
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    local key = realmName .. "-" .. playerName
    local level = UnitLevel("player")
    local _, class = UnitClass("player")
    
    if not JoguDB.characters[key] then
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
    
    return key
end

-- Mark character as having harvested today
local function MarkHarvested()
    local key = RegisterCharacter()
    JoguDB.characters[key].lastHarvestEpoch = GetCurrentEpochDay()
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Mark character as having completed Master Token quest today
local function MarkMasterToken()
    local key = RegisterCharacter()
    JoguDB.characters[key].lastMasterTokenEpoch = GetCurrentEpochDay()
    if JoguFrame and JoguFrame:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Check and store world boss kill status for current character
local function UpdateWorldBossStatus()
    local key = RegisterCharacter()
    local data = JoguDB.characters[key]
    if not data.worldBosses then
        data.worldBosses = {}
    end
    local currentWeek = GetCurrentWeekEpoch()
    for _, boss in ipairs(WORLD_BOSSES) do
        if C_QuestLog.IsQuestFlaggedCompleted(boss.questID) then
            data.worldBosses[boss.questID] = currentWeek
            -- Track Ordos ever-killed globally
            if boss.futureContent then
                if not JoguDB.ordosEverKilled then
                    JoguDB.ordosEverKilled = true
                end
            end
        end
    end
    if worldBossPanel and worldBossPanel:IsVisible() then
        UpdateWorldBossPanel()
    end
end

local function GetTomorrowBonusDay()
    local utcTime, utcDate = GetUTCTime()
    local resetHour = GetRegionResetConfig().dailyResetHour
    local farmingDayOffset = (utcDate.hour < resetHour) and -1 or 0
    local currentEpochDay = math.floor(utcTime / 86400) + farmingDayOffset
    
    -- Check for realm-specific calibration
    local realmName = GetRealmName()
    local calibration = JoguDB and JoguDB.realmCalibration and JoguDB.realmCalibration[realmName]
    
    local currentDay
    if calibration then
        -- Use calibration: advance from calibrated crop by days elapsed
        local daysSinceCalibration = currentEpochDay - calibration.epochDay
        currentDay = ((calibration.todayCropIndex - 1 + daysSinceCalibration) % 10) + 1
    else
        -- Default calculation (calibrated for NA/OCE region)
        local daysSinceRef = currentEpochDay - REFERENCE_EPOCH_DAY
        currentDay = ((daysSinceRef % 10) + 10) % 10 + 1
    end
    
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
    return C_QuestLog.IsQuestFlaggedCompleted(NOMI_DAILY_QUEST_ID)
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

-- Update the alt tracking section in the main frame
UpdateExpandedPanel = function()
    if not JoguFrame or not JoguFrame.altScrollChild then return end

    local scrollChild = JoguFrame.altScrollChild
    local scrollFrame = JoguFrame.altScrollFrame
    
    -- Clear existing rows
    if scrollChild.rows then
        for _, row in ipairs(scrollChild.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    scrollChild.rows = {}
    
    -- Get character list with status
    local chars = {}
    local currentEpoch = GetCurrentEpochDay()
    local displayNames = GetCharacterDisplayNames()

    for key, data in pairs(JoguDB.characters) do
        local name = displayNames[key] or key:match("^.+%-(.+)$")
        local harvested = data.lastHarvestEpoch == currentEpoch
        local questDone = data.lastMasterTokenEpoch == currentEpoch

        -- Characters <90 treated as "quest done" for sorting purposes
        if data.level < 90 then
            questDone = true
        end

        table.insert(chars, {
            key = key,
            name = name,
            data = data,
            harvested = harvested,
            questDone = questDone
        })
    end
    
    -- Sort by priority: Both NO → Farmed NO/Quest YES → Farmed YES/Quest NO → Both YES → alphabetically
    table.sort(chars, function(a, b)
        local aPriority = 0
        local bPriority = 0
        
        -- Determine priority (lower number = higher priority in list)
        if not a.harvested and not a.questDone then
            aPriority = 1  -- Both NO
        elseif not a.harvested and a.questDone then
            aPriority = 2  -- Farmed NO, Quest YES
        elseif a.harvested and not a.questDone then
            aPriority = 3  -- Farmed YES, Quest NO
        else
            aPriority = 4  -- Both YES
        end
        
        if not b.harvested and not b.questDone then
            bPriority = 1
        elseif not b.harvested and b.questDone then
            bPriority = 2
        elseif b.harvested and not b.questDone then
            bPriority = 3
        else
            bPriority = 4
        end
        
        -- If same priority, sort alphabetically
        if aPriority == bPriority then
            return a.name < b.name
        end
        return aPriority < bPriority
    end)
    
    -- Create rows
    local yOffset = 0
    
    for i, char in ipairs(chars) do
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetSize(310, 30)
        row:SetPoint("TOPLEFT", 0, yOffset)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = nil,
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)

        -- Character name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(85)
        nameText:SetJustifyH("LEFT")
        if char.data.level < 90 then
            nameText:SetText(char.name .. " (" .. char.data.level .. ")")
        else
            nameText:SetText(char.name)
        end

        local classColor = RAID_CLASS_COLORS[char.data.class]
        if classColor then
            nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
        end

        -- Harvest status button - centered under Farmed header (header at scroll x=150)
        local harvestBtn = CreateFrame("Button", nil, row)
        harvestBtn:SetSize(20, 20)
        harvestBtn:SetPoint("LEFT", row, "LEFT", 140, 0)
        
        local harvestIcon = harvestBtn:CreateTexture(nil, "ARTWORK")
        harvestIcon:SetAllPoints()
        harvestBtn.icon = harvestIcon
        
        if char.harvested then
            harvestIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        else
            harvestIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        end
        
        harvestBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Harvest Status")
            GameTooltip:AddLine("Click to toggle", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        harvestBtn:SetScript("OnLeave", GameTooltip_Hide)
        harvestBtn:SetScript("OnClick", function()
            -- Toggle harvest status
            if char.data.lastHarvestEpoch == currentEpoch then
                char.data.lastHarvestEpoch = 0
            else
                char.data.lastHarvestEpoch = currentEpoch
            end
            UpdateExpandedPanel()
        end)
        
        -- Master Token status button - centered under Daily Token header (header at scroll x=243)
        local tokenBtn = CreateFrame("Button", nil, row)
        tokenBtn:SetSize(20, 20)
        tokenBtn:SetPoint("LEFT", row, "LEFT", 233, 0)
        
        local tokenIcon = tokenBtn:CreateTexture(nil, "ARTWORK")
        tokenIcon:SetAllPoints()
        tokenBtn.icon = tokenIcon
        
        if char.data.level == 90 then
            local completed = char.data.lastMasterTokenEpoch == currentEpoch
            if completed then
                tokenIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            else
                tokenIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            end
            
            tokenBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Master Token Quest")
                GameTooltip:AddLine("Click to toggle", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            tokenBtn:SetScript("OnLeave", GameTooltip_Hide)
            tokenBtn:SetScript("OnClick", function()
                -- Toggle token status
                if char.data.lastMasterTokenEpoch == currentEpoch then
                    char.data.lastMasterTokenEpoch = 0
                else
                    char.data.lastMasterTokenEpoch = currentEpoch
                end
                UpdateExpandedPanel()
            end)
        else
            -- Not eligible - show dash
            local dash = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        
        -- Delete button - far right of row
        local deleteBtn = CreateFrame("Button", nil, row)
        deleteBtn:SetSize(20, 20)
        deleteBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
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
        yOffset = yOffset - 35
    end
    
    -- Set scroll child height
    local contentHeight = math.max(1, #chars * 35)
    scrollChild:SetHeight(contentHeight)
    
    -- Hide scrollbar if content fits in frame
    local frameHeight = scrollFrame:GetHeight()
    if contentHeight <= frameHeight then
        scrollFrame.ScrollBar:Hide()
    else
        scrollFrame.ScrollBar:Show()
    end
end

-- Create the world boss tracking panel
local function CreateWorldBossPanel()
    local panelHeight = JoguFrame:GetHeight()

    local panel = CreateFrame("Frame", "JoguWorldBossPanel", UIParent, "BackdropTemplate")
    panel:SetSize(350, panelHeight)
    panel:SetPoint("LEFT", JoguFrame, "RIGHT", 5, 0)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(102)

    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", 0, -20)
    panel.title:SetText("Jogu Knows More")
    panel.title:SetTextColor(1, 0.82, 0)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
        if JoguFrame.expandBtn then
            JoguFrame.expandBtn:SetText("Jogu Knows More >")
        end
    end)

    -- Subtitle
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.subtitle:SetPoint("TOP", 0, -45)
    panel.subtitle:SetText("World Boss Weekly Lockouts")
    panel.subtitle:SetTextColor(0.9, 0.9, 0.9)

    -- Build boss column headers - all 5 bosses always shown
    local headerY = -70

    panel.bossHeaders = {}
    local bossStartX = 120
    local bossSpacing = 45

    for i, boss in ipairs(WORLD_BOSSES) do
        local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local xPos = bossStartX + (i - 1) * bossSpacing
        header:SetPoint("TOP", panel, "TOPLEFT", xPos, headerY)
        header:SetText(boss.name)
        header:SetWidth(40)
        header:SetJustifyH("CENTER")
        -- Grey out Ordos header if not yet available
        if boss.futureContent and not JoguDB.ordosEverKilled then
            header:SetTextColor(0.4, 0.4, 0.4)
        else
            header:SetTextColor(1, 0.82, 0)
        end
        panel.bossHeaders[i] = header
    end

    -- Scroll frame for character list
    local scrollFrame = CreateFrame("ScrollFrame", "JoguWorldBossScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -90)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 20)
    panel.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(280, 1)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild

    panel:SetScript("OnShow", function()
        panel:SetHeight(JoguFrame:GetHeight())
        panel:SetPoint("LEFT", JoguFrame, "RIGHT", 5, 0)
        UpdateWorldBossPanel()
    end)

    panel:SetScript("OnHide", function()
        if JoguFrame.expandBtn then
            JoguFrame.expandBtn:SetText("Jogu Knows More >")
        end
    end)

    tinsert(UISpecialFrames, "JoguWorldBossPanel")

    panel:Hide()
    return panel
end

-- Update the world boss panel with current character data
UpdateWorldBossPanel = function()
    if not worldBossPanel or not worldBossPanel.scrollChild then return end

    local scrollChild = worldBossPanel.scrollChild
    local scrollFrame = worldBossPanel.scrollFrame

    -- Clear existing rows
    if scrollChild.rows then
        for _, row in ipairs(scrollChild.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    scrollChild.rows = {}

    local currentWeek = GetCurrentWeekEpoch()

    -- Gather characters
    local chars = {}
    local displayNames = GetCharacterDisplayNames()
    for key, data in pairs(JoguDB.characters) do
        local name = displayNames[key] or key:match("^.+%-(.+)$")
        table.insert(chars, {key = key, name = name, data = data})
    end
    table.sort(chars, function(a, b) return a.name < b.name end)

    local yOffset = 0
    local bossStartX = 100
    local bossSpacing = 45

    for _, char in ipairs(chars) do
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetSize(320, 30)
        row:SetPoint("TOPLEFT", 0, yOffset)

        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = nil,
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)

        -- Character name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(90)
        nameText:SetJustifyH("LEFT")
        nameText:SetText(char.name)

        local classColor = RAID_CLASS_COLORS[char.data.class]
        if classColor then
            nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
        end

        -- Boss kill status icons - all 5 bosses, centered under headers
        local bosses = char.data.worldBosses or {}
        for i, boss in ipairs(WORLD_BOSSES) do
            local xPos = bossStartX + (i - 1) * bossSpacing

            if boss.futureContent and not JoguDB.ordosEverKilled then
                -- Ordos not yet available - show greyed dash like sub-90 daily token
                local dash = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                dash:SetPoint("LEFT", row, "LEFT", xPos - 10, 0)
                dash:SetWidth(20)
                dash:SetJustifyH("CENTER")
                dash:SetText("—")
                dash:SetTextColor(0.4, 0.4, 0.4)
            else
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(20, 20)
                icon:SetPoint("LEFT", row, "LEFT", xPos - 10, 0)

                local killed = bosses[boss.questID] and bosses[boss.questID] == currentWeek
                if killed then
                    icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                else
                    icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                end
            end
        end

        table.insert(scrollChild.rows, row)
        yOffset = yOffset - 35
    end

    local contentHeight = math.max(1, #chars * 35)
    scrollChild:SetHeight(contentHeight)

    local frameHeight = scrollFrame:GetHeight()
    if contentHeight <= frameHeight then
        scrollFrame.ScrollBar:Hide()
    else
        scrollFrame.ScrollBar:Show()
    end
end

local FRAME_LEFT_WIDTH = 380  -- Left half for crop predictions
local FRAME_RIGHT_WIDTH = 350 -- Right half for alt tracking
local FRAME_TOTAL_WIDTH = FRAME_LEFT_WIDTH + FRAME_RIGHT_WIDTH

local function CreateJoguFrame()
    local frame = CreateFrame("Frame", "JoguMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_TOTAL_WIDTH, FRAME_HEIGHT_NO_BELL)
    
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
    
    -- Close world boss panel when main panel closes
    frame:SetScript("OnHide", function()
        if worldBossPanel and worldBossPanel:IsVisible() then
            worldBossPanel:Hide()
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
    
    -- Title (centered over left half)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", -175, -20)
    frame.title:SetText("Jogu Knows")
    frame.title:SetTextColor(1, 0.82, 0)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        HideUIPanel(frame)
    end)

    -- Flavor text (centered over left half)
    frame.flavorText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.flavorText:SetPoint("TOP", -175, -45)
    frame.flavorText:SetWidth(340)
    frame.flavorText:SetJustifyH("CENTER")
    frame.flavorText:SetText(FLAVOR_TEXT)
    frame.flavorText:SetTextColor(0.9, 0.9, 0.9)

    -- Crop icons in circle - ALL LABELS BELOW ICONS
    frame.cropButtons = {}
    frame.cropLabels = {}
    local centerX, centerY = 190, 265
    local radius = 115  -- Large radius for proper spacing
    
    for i = 1, 10 do
        local angle = (i - 1) * (2 * math.pi / 10) - (math.pi / 2)
        local x = centerX + radius * math.cos(angle)
        local y = centerY + radius * math.sin(angle)
        
        local btn = CreateFrame("Button", "JoguCropButton"..i, frame)
        btn:SetSize(36, 36)
        btn:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
        
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        btn.icon = icon
        btn.itemID = CROPS[i].id
        
        -- Gold border highlight - proper outer border frame
        btn.highlightFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        btn.highlightFrame:SetPoint("TOPLEFT", -3, 3)
        btn.highlightFrame:SetPoint("BOTTOMRIGHT", 3, -3)
        btn.highlightFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 2,
        })
        btn.highlightFrame:SetBackdropBorderColor(1, 0.82, 0, 1)
        btn.highlightFrame:Hide()
        
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
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", GameTooltip_Hide)
        btn:SetScript("OnClick", function(self)
            if calibrationMode then
                -- Save calibration for this realm
                local realmName = GetRealmName()
                local currentEpochDay = GetCurrentEpochDay()
                
                JoguDB.realmCalibration[realmName] = {
                    todayCropIndex = self.cropIndex,
                    epochDay = currentEpochDay
                }
                
                -- Exit calibration mode
                calibrationMode = false
                JoguFrame.calibrateBtn:SetText("?")
                SetCalibrationFade(false)
                UpdateJoguUI()
                
                print("|cFF00FF00[Jogu Knows]|r Calibrated for " .. realmName .. ": Today's bonus crop is " .. CROPS[self.cropIndex].name)
            end
        end)
        
        frame.cropButtons[i] = btn
    end

    -- "Plant today" text - positioned below the circle (left half)
    frame.plantText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.plantText:SetPoint("TOP", -175, -420)
    frame.plantText:SetTextColor(1, 0.82, 0)
    
    -- Calibration button - "?" button on same line as plant text, to the left
    frame.calibrateBtn = CreateFrame("Button", "JoguCalibrateButton", frame, "UIPanelButtonTemplate")
    frame.calibrateBtn:SetPoint("RIGHT", frame.plantText, "LEFT", -10, 0)
    frame.calibrateBtn:SetSize(30, 22)
    frame.calibrateBtn:SetText("?")
    frame.calibrateBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Cycle Calibration", 1, 0.82, 0)
        GameTooltip:AddLine("Select the bonus crop on your server for TODAY to synch cycle to your server if it is incorrect. You only need to do this once.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.calibrateBtn:SetScript("OnLeave", GameTooltip_Hide)
    frame.calibrateBtn:SetScript("OnClick", function()
        calibrationMode = not calibrationMode
        if calibrationMode then
            frame.calibrateBtn:SetText("X")
            frame.plantText:SetText("What was today's bonus crop?")
            frame.plantText:SetTextColor(0.5, 0.8, 1)
            SetCalibrationFade(true)
        else
            frame.calibrateBtn:SetText("?")
            SetCalibrationFade(false)
            UpdateJoguUI()
        end
    end)
    
    -- Timer text (left half)
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.timerText:SetPoint("TOP", -175, -445)
    frame.timerText:SetTextColor(0.8, 0.8, 0.8)

    -- Separator line (hidden by default, left half)
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOP", -175, -470)
    separator:SetSize(320, 1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    separator:Hide()
    frame.separator = separator

    -- Nomi section (hidden by default, left half)
    frame.nomiSection = CreateFrame("Frame", nil, frame)
    frame.nomiSection:SetPoint("TOP", -175, -485)
    frame.nomiSection:SetSize(340, 50)
    frame.nomiSection:Hide()
    
    -- Clickable bell button using SecureActionButton
    frame.bellButton = CreateFrame("Button", "JoguBellButton", frame.nomiSection, "SecureActionButtonTemplate")
    frame.bellButton:SetPoint("LEFT", frame.nomiSection, "LEFT", 30, 0)
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

    -- ==========================================
    -- RIGHT HALF: Alt Farm Report
    -- ==========================================

    -- Vertical divider between left and right halves
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOP", frame, "TOPLEFT", FRAME_LEFT_WIDTH, -15)
    divider:SetPoint("BOTTOM", frame, "BOTTOMLEFT", FRAME_LEFT_WIDTH, 15)
    divider:SetWidth(1)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    -- Alt Farm Report title
    frame.altTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.altTitle:SetPoint("TOP", frame, "TOPLEFT", FRAME_LEFT_WIDTH + FRAME_RIGHT_WIDTH / 2, -20)
    frame.altTitle:SetText("Alt Farm Report")
    frame.altTitle:SetTextColor(1, 0.82, 0)

    -- Subtitle
    frame.altSubtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.altSubtitle:SetPoint("TOP", frame, "TOPLEFT", FRAME_LEFT_WIDTH + FRAME_RIGHT_WIDTH / 2, -45)
    frame.altSubtitle:SetText("Ironpaw Token daily from Cooking Masters")
    frame.altSubtitle:SetTextColor(0.9, 0.9, 0.9)

    -- Column headers for alt tracking
    local rightCenterX = FRAME_LEFT_WIDTH + FRAME_RIGHT_WIDTH / 2
    local farmedHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    farmedHeader:SetPoint("TOP", frame, "TOPLEFT", FRAME_LEFT_WIDTH + 160, -70)
    farmedHeader:SetText("Farmed")
    farmedHeader:SetTextColor(1, 0.82, 0)

    local tokenHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tokenHeader:SetPoint("TOP", frame, "TOPLEFT", FRAME_LEFT_WIDTH + 253, -70)
    tokenHeader:SetText("Daily Token")
    tokenHeader:SetTextColor(1, 0.82, 0)

    -- Scroll frame for character list (right half)
    local altScrollFrame = CreateFrame("ScrollFrame", "JoguAltScrollFrame", frame, "UIPanelScrollFrameTemplate")
    altScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_LEFT_WIDTH + 10, -90)
    altScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 45)
    frame.altScrollFrame = altScrollFrame

    local altScrollChild = CreateFrame("Frame", nil, altScrollFrame)
    altScrollChild:SetSize(FRAME_RIGHT_WIDTH - 50, 1)
    altScrollFrame:SetScrollChild(altScrollChild)
    frame.altScrollChild = altScrollChild

    -- Checkbox at bottom left
    frame.checkbox = CreateFrame("CheckButton", "JoguLoginCheckbox", frame, "UICheckButtonTemplate")
    frame.checkbox:SetPoint("BOTTOMLEFT", 25, 15)
    frame.checkbox:SetChecked(JoguDB and JoguDB.showLoginMessage or false)
    frame.checkbox:SetScript("OnClick", function(self)
        JoguDB.showLoginMessage = self:GetChecked()
    end)
    
    frame.checkboxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.checkboxLabel:SetPoint("LEFT", frame.checkbox, "RIGHT", 5, 0)
    frame.checkboxLabel:SetText("Show message on login")
    frame.checkboxLabel:SetTextColor(0.9, 0.9, 0.9)
    
    -- Expand button for alt tracker (bottom right)
    frame.expandBtn = CreateFrame("Button", "JoguExpandButton", frame, "UIPanelButtonTemplate")
    frame.expandBtn:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    frame.expandBtn:SetPoint("TOP", frame.checkbox, "TOP", 0, 0)
    frame.expandBtn:SetPoint("BOTTOM", frame.checkbox, "BOTTOM", 0, 0)
    frame.expandBtn:SetWidth(150)
    frame.expandBtn:SetText("Jogu Knows More >")
    frame.expandBtn:SetScript("OnClick", function(self)
        if not worldBossPanel then
            worldBossPanel = CreateWorldBossPanel()
        end

        if worldBossPanel:IsVisible() then
            worldBossPanel:Hide()
            self:SetText("Jogu Knows More >")
        else
            worldBossPanel:Show()
            self:SetText("< Jogu Knows More")
        end
    end)
    
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
    
    -- Update highlights and label colors
    for i = 1, 10 do
        if i == tomorrowDay then
            JoguFrame.cropButtons[i].highlightFrame:Show()
            JoguFrame.cropLabels[i]:SetTextColor(1, 0.82, 0)
            JoguFrame.cropLabels[i]:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        else
            JoguFrame.cropButtons[i].highlightFrame:Hide()
            JoguFrame.cropLabels[i]:SetTextColor(1, 1, 1)
            JoguFrame.cropLabels[i]:SetFont("Fonts\\FRIZQT__.TTF", 9)
        end
    end
    
    -- Update plant text
    JoguFrame.plantText:SetText("Plant " .. CROPS[tomorrowDay].name .. " today!")
    JoguFrame.plantText:SetTextColor(1, 0.82, 0)
    
    -- Update Nomi section
    local hasBell = HasCookingSchoolBell()
    if hasBell then
        JoguFrame:SetHeight(FRAME_HEIGHT_WITH_BELL)
        JoguFrame.nomiSection:Show()
        JoguFrame.separator:Show()
        if IsNomiQuestCompletedToday() then
            JoguFrame.nomiText:SetText("You have received Nomi's gift today.")
            JoguFrame.nomiText:SetTextColor(0.5, 1, 0.5)
        else
            JoguFrame.nomiText:SetText("You have not received your gift from Nomi today.")
            JoguFrame.nomiText:SetTextColor(1, 0.5, 0.5)
        end
    else
        JoguFrame:SetHeight(FRAME_HEIGHT_NO_BELL)
        JoguFrame.nomiSection:Hide()
        JoguFrame.separator:Hide()
    end
    
    -- Set initial timer
    JoguFrame.timerText:SetText("Crops ripe in: " .. FormatTime(GetSecondsUntilReset()))
end

local function ToggleJoguFrame()
    if not JoguFrame then return end

    if JoguFrame:IsVisible() then
        HideUIPanel(JoguFrame)
    else
        ShowUIPanel(JoguFrame)
        UpdateJoguUI()
        UpdateExpandedPanel()
    end
end

SLASH_JOGU1 = "/jogu"
SlashCmdList["JOGU"] = ToggleJoguFrame

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == "Jogu" then
        Jogu_OnLoad()
        
    elseif event == "PLAYER_LOGIN" then
        -- Create frame at login (hidden) so it's ready when /jogu is used
        JoguFrame = CreateJoguFrame()
        JoguFrame:Hide()
        LoadItemIcons()
        
        -- Register current character if level 86+
        local level = UnitLevel("player")
        if level >= 86 then
            RegisterCharacter()
            -- Check world boss kill status for this character
            UpdateWorldBossStatus()
        end
        
        if JoguDB and JoguDB.showLoginMessage then
            local tomorrowDay = GetTomorrowBonusDay()
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
        
    elseif event == "QUEST_TURNED_IN" then
        local questID = arg1
        -- Track Master Token daily quest completion (level 90 only)
        if MASTER_TOKEN_QUESTS[questID] and UnitLevel("player") == 90 then
            MarkMasterToken()
        end
        -- Update Nomi status on main panel when Nomi daily is turned in
        if questID == NOMI_DAILY_QUEST_ID and JoguFrame and JoguFrame:IsVisible() then
            UpdateJoguUI()
        end

    elseif event == "QUEST_ACCEPTED" then
        -- arg1 is questID on modern clients, or questLogIndex on legacy (with questID as arg2)
        local questID = (arg1 and arg1 > 10000) and arg1 or select(1, ...)
        -- Easter egg: Truffle Shuffle pickup
        if questID == TRUFFLE_SHUFFLE_QUEST_ID then
            print("|cFF00FF00[Jogu Knows]|r Planting and picking, share the mushrooms, please do - set your spores down at 32, 32!")
            -- Place a map pin at 32, 32 in Valley of the Four Winds
            if SlashCmdList["WAY"] then
                -- TomTom installed: use /way with custom label
                SlashCmdList["WAY"]("32 32 There's so mushroom!")
            elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
                -- Fallback: native waypoint API (retail-only, may not exist in MoP Classic)
                local point = UiMapPoint.CreateFromCoordinates(VALLEY_OF_FOUR_WINDS_MAP_ID, 0.32, 0.32)
                C_Map.SetUserWaypoint(point)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end
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
        
        -- Constraint 2: Core crops must be 5-10 quantity
        for cropIndex, crop in ipairs(CROPS) do
            if crop.id == itemID and qty >= 5 and qty <= 10 then
                MarkHarvested()
                -- Auto-calibration: 7 or 10 = bonus crop day, meaning this crop IS today's bonus
                if qty == 7 or qty == 10 then
                    local _, predictedToday = GetTomorrowBonusDay()
                    if predictedToday ~= cropIndex then
                        -- Current prediction is wrong — auto-correct the cycle position
                        local realmName = GetRealmName()
                        JoguDB.realmCalibration[realmName] = {
                            todayCropIndex = cropIndex,
                            epochDay = GetCurrentEpochDay()
                        }
                        print("|cFF00FF00[Jogu Knows]|r Auto-calibrated! Detected " .. crop.name .. " as today's bonus crop.")
                        if JoguFrame and JoguFrame:IsVisible() then
                            UpdateJoguUI()
                            UpdateExpandedPanel()
                        end
                    end
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
