-- Jogu: Crop Prediction Addon for MoP Classic
-- Predicts tomorrow's bonus crop for Sunsong Ranch
-- Interface: 50400 (MoP Classic)
-- Version: 0.7 - Alt Tracking

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
local REFERENCE_EPOCH_DAY = 20457

local JoguFrame = nil
local expandedPanel = nil
local calibrationMode = false
local UpdateJoguUI  -- Forward declaration
local UpdateExpandedPanel  -- Forward declaration
local GetCurrentEpochDay  -- Forward declaration

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
end

local function GetUTCTime()
    local utcTime = GetServerTime()
    local utcDate = date("!*t", utcTime)
    return utcTime, utcDate
end

-- Get current epoch day (15:00 UTC reset)
GetCurrentEpochDay = function()
    local utcTime, utcDate = GetUTCTime()
    local farmingDayOffset = (utcDate.hour < 15) and -1 or 0
    return math.floor(utcTime / 86400) + farmingDayOffset
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
    if expandedPanel and expandedPanel:IsVisible() then
        UpdateExpandedPanel()
    end
end

-- Mark character as having completed Master Token quest today
local function MarkMasterToken()
    local key = RegisterCharacter()
    JoguDB.characters[key].lastMasterTokenEpoch = GetCurrentEpochDay()
    if expandedPanel and expandedPanel:IsVisible() then
        UpdateExpandedPanel()
    end
end

local function GetTomorrowBonusDay()
    local utcTime, utcDate = GetUTCTime()
    local farmingDayOffset = (utcDate.hour < 15) and -1 or 0
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
        -- Default calculation (calibrated for Arugal)
        local daysSinceRef = currentEpochDay - REFERENCE_EPOCH_DAY
        currentDay = ((daysSinceRef % 10) + 10) % 10 + 1
    end
    
    local tomorrowDay = (currentDay % 10) + 1
    return tomorrowDay, currentDay
end

local function GetSecondsUntilReset()
    local utcTime, utcDate = GetUTCTime()
    local secondsSinceMidnight = utcDate.hour * 3600 + utcDate.min * 60 + utcDate.sec
    local targetSeconds = 15 * 3600
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

-- Create the expandable alt-tracking panel
local function CreateExpandedPanel()
    -- Match height with main Jogu frame
    local panelHeight = JoguFrame:GetHeight()
    
    local panel = CreateFrame("Frame", "JoguExpandedPanel", UIParent, "BackdropTemplate")
    panel:SetSize(350, panelHeight)
    panel:SetPoint("LEFT", JoguFrame, "RIGHT", 5, 0)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(101)
    
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", 0, -20)
    panel.title:SetText("Expanded Content")
    panel.title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
        if JoguFrame.expandBtn then
            JoguFrame.expandBtn:SetText("Expanded Content >")
        end
    end)
    
    -- Column headers - centered in their respective columns
    -- Columns are: Name (0-93px), Farmed (93-186px), Daily Token (186-280px)
    -- Headers positioned in panel coords (scroll starts at x=20, so add 20 to scrollChild coords)
    local farmedHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    farmedHeader:SetPoint("TOP", panel, "TOPLEFT", 160, -50)  -- 140 + 20 offset
    farmedHeader:SetText("Farmed")
    farmedHeader:SetTextColor(1, 0.82, 0)
    
    local tokenHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tokenHeader:SetPoint("TOP", panel, "TOPLEFT", 253, -50)  -- 233 + 20 offset
    tokenHeader:SetText("Daily Token")
    tokenHeader:SetTextColor(1, 0.82, 0)
    
    -- Scroll frame for character list
    local scrollFrame = CreateFrame("ScrollFrame", "JoguScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 20)
    panel.scrollFrame = scrollFrame
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(280, 1)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild
    
    panel:SetScript("OnShow", function()
        -- Update height to match main frame in case it changed (bell added/removed)
        panel:SetHeight(JoguFrame:GetHeight())
        UpdateExpandedPanel()
    end)
    
    panel:SetScript("OnHide", function()
        if JoguFrame.expandBtn then
            JoguFrame.expandBtn:SetText("Expanded Content >")
        end
    end)
    
    -- Register for ESC key closing
    tinsert(UISpecialFrames, "JoguExpandedPanel")
    
    panel:Hide()
    return panel
end

-- Update the expanded panel with current character data
UpdateExpandedPanel = function()
    if not expandedPanel or not expandedPanel.scrollChild then return end
    
    local scrollChild = expandedPanel.scrollChild
    local scrollFrame = expandedPanel.scrollFrame
    
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
    
    for key, data in pairs(JoguDB.characters) do
        local name = key:match("^.+%-(.+)$")
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
        row:SetSize(280, 30)
        row:SetPoint("TOPLEFT", 0, yOffset)
        
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = nil,
        })
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
        
        -- Character name - first column (0-93px)
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 5, 0)
        nameText:SetWidth(85)
        nameText:SetJustifyH("LEFT")
        nameText:SetText(char.name .. " (" .. char.data.level .. ")")
        
        local classColor = RAID_CLASS_COLORS[char.data.class]
        if classColor then
            nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
        end
        
        -- Harvest status button - centered in Farmed column (93-186px, center at 140)
        local harvestBtn = CreateFrame("Button", nil, row)
        harvestBtn:SetSize(20, 20)
        harvestBtn:SetPoint("LEFT", row, "LEFT", 130, 0)  -- 140 - 10 (half icon width)
        
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
        
        -- Master Token status button - centered in Daily Token column (186-280px, center at 233)
        local tokenBtn = CreateFrame("Button", nil, row)
        tokenBtn:SetSize(20, 20)
        tokenBtn:SetPoint("LEFT", row, "LEFT", 223, 0)  -- 233 - 10 (half icon width)
        
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
        
        -- Delete button
        local deleteBtn = CreateFrame("Button", nil, row)
        deleteBtn:SetSize(20, 20)
        deleteBtn:SetPoint("RIGHT", -5, 0)
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

local function CreateJoguFrame()
    local frame = CreateFrame("Frame", "JoguMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(380, FRAME_HEIGHT_NO_BELL)
    
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
    
    -- Close expanded panel when main panel closes
    frame:SetScript("OnHide", function()
        if expandedPanel and expandedPanel:IsVisible() then
            expandedPanel:Hide()
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
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -20)
    frame.title:SetText("Jogu's Crop Predictions")
    frame.title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        -- Close expanded panel if it's open
        if expandedPanel and expandedPanel:IsVisible() then
            expandedPanel:Hide()
        end
    end)
    
    -- Flavor text
    frame.flavorText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.flavorText:SetPoint("TOP", 0, -45)
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
                local utcTime, utcDate = GetUTCTime()
                local farmingDayOffset = (utcDate.hour < 15) and -1 or 0
                local currentEpochDay = math.floor(utcTime / 86400) + farmingDayOffset
                
                JoguDB.realmCalibration[realmName] = {
                    todayCropIndex = self.cropIndex,
                    epochDay = currentEpochDay
                }
                
                -- Exit calibration mode
                calibrationMode = false
                JoguFrame.calibrateBtn:SetText("?")
                SetCalibrationFade(false)
                UpdateJoguUI()
                
                print("|cFF00FF00[Jogu]|r Calibrated for " .. realmName .. ": Today's bonus crop is " .. CROPS[self.cropIndex].name)
            end
        end)
        
        frame.cropButtons[i] = btn
    end

    -- "Plant today" text - positioned below the circle
    frame.plantText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.plantText:SetPoint("TOP", 0, -420)
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
    
    -- Timer text
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.timerText:SetPoint("TOP", 0, -445)
    frame.timerText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Separator line (hidden by default)
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOP", 0, -470)
    separator:SetSize(320, 1)
    separator:SetColorTexture(0.5, 0.5, 0.5, 0.5)
    separator:Hide()
    frame.separator = separator
    
    -- Nomi section (hidden by default)
    frame.nomiSection = CreateFrame("Frame", nil, frame)
    frame.nomiSection:SetPoint("TOP", 0, -485)
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
    frame.expandBtn:SetText("Expanded Content >")
    frame.expandBtn:SetScript("OnClick", function(self)
        if not expandedPanel then
            expandedPanel = CreateExpandedPanel()
        end
        
        if expandedPanel:IsVisible() then
            expandedPanel:Hide()
            self:SetText("Expanded Content >")
        else
            expandedPanel:Show()
            self:SetText("< Hide Content")
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
    end
end

SLASH_JOGU1 = "/jogu"
SlashCmdList["JOGU"] = ToggleJoguFrame

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
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
        end
        
        if JoguDB and JoguDB.showLoginMessage then
            local tomorrowDay = GetTomorrowBonusDay()
            local cropData = CROPS[tomorrowDay]
            local itemLink = select(2, GetItemInfo(cropData.id))
            if itemLink then
                print("|cFF00FF00[Jogu]|r Plant " .. itemLink .. " today for bonus crops tomorrow!")
            else
                local item = Item:CreateFromItemID(cropData.id)
                item:ContinueOnItemLoad(function()
                    local link = select(2, GetItemInfo(cropData.id))
                    print("|cFF00FF00[Jogu]|r Plant " .. (link or cropData.name) .. " today for bonus crops tomorrow!")
                end)
            end
        end
        
    elseif event == "QUEST_TURNED_IN" then
        -- Track Master Token daily quest completion (level 90 only)
        local questID = arg1
        if MASTER_TOKEN_QUESTS[questID] and UnitLevel("player") == 90 then
            MarkMasterToken()
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
        for _, crop in ipairs(CROPS) do
            if crop.id == itemID and qty >= 5 and qty <= 10 then
                MarkHarvested()
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
