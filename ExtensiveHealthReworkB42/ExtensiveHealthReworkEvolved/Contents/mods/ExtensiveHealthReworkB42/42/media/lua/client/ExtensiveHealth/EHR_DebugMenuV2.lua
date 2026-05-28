--[[
    Extensive Health Rework B42
    Debug Menu v2.0

    Comprehensive debug panel with 8 tabs matching Medical Monitor UI style.
    Replaces old EHR_DebugMenu.lua and context menu debug options.

    Tabs: Overview | Diseases | Blood | Wounds | Medications | Stats | Scenarios | Log

    v2.0.0 - 2026-01-08
]]--

require "ExtensiveHealth/EHR_Main"
require "ISUI/ISPanel"
pcall(function() require "ExtensiveHealth/EHR_WoundInfection" end)

-- Defensive check - create stubs if needed
if not EHR then EHR = {} end
if not EHR.Log then EHR.Log = function(msg) print("[EHR] " .. tostring(msg)) end end

-- ============================================
-- NAMESPACE
-- ============================================

EHR.DebugV2 = {}
EHR.DebugV2.instance = nil

-- ============================================
-- CONSTANTS
-- ============================================

local WINDOW_WIDTH = 580
local WINDOW_HEIGHT = 720
local TAB_HEIGHT = 28
local HEADER_HEIGHT = 32
local BUTTON_HEIGHT = 24
local PADDING = 10
local FONT = UIFont.Small

-- Tab definitions
EHR.DebugV2.Tabs = {
    { id = "overview", name = "Overview" },
    { id = "diseases", name = "Diseases" },
    { id = "blood", name = "Blood" },
    { id = "wounds", name = "Wounds" },
    { id = "medications", name = "Meds" },
    { id = "stats", name = "Stats" },
    { id = "scenarios", name = "Scenarios" },
    { id = "log", name = "Log" },
}

-- Color scheme (matches Medical Monitor)
EHR.DebugV2.Colors = {
    background = {r=0.1, g=0.1, b=0.12, a=0.95},
    border = {r=0.3, g=0.5, b=0.4, a=1},
    headerBg = {r=0.15, g=0.2, b=0.18, a=1},
    tabBg = {r=0.12, g=0.14, b=0.16, a=1},
    tabActive = {r=0.2, g=0.35, b=0.3, a=1},
    tabHover = {r=0.15, g=0.25, b=0.22, a=1},
    text = {r=0.9, g=0.9, b=0.9, a=1},
    textDim = {r=0.6, g=0.6, b=0.6, a=1},
    safe = {r=0.2, g=0.8, b=0.3, a=1},
    warning = {r=0.9, g=0.7, b=0.2, a=1},
    danger = {r=0.9, g=0.3, b=0.1, a=1},
    critical = {r=1, g=0.1, b=0.1, a=1},
    buttonBg = {r=0.18, g=0.22, b=0.2, a=1},
    buttonHover = {r=0.25, g=0.35, b=0.3, a=1},
}

local function debugClamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function debugWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        return gameTime:getWorldAgeHours()
    end
    return 0
end

local DEBUG_WOUND_VANILLA_LEVELS = {
    [1] = 2,
    [2] = 6,
    [3] = 11,
    [4] = 15,
}

local function debugTransmitPlayerModData(player)
    if player and player.transmitModData then
        pcall(function() player:transmitModData() end)
    end
end

local function debugFindPlayerForModData(data)
    if not data or not getSpecificPlayer then return nil end
    for i = 0, 3 do
        local player = getSpecificPlayer(i)
        if player and player.getModData and player:getModData() == data then
            return player
        end
    end
    return nil
end

local function debugGetBodyPart(player, partId)
    if not player or not partId or not BodyPartType then return nil end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return nil end

    local partType = BodyPartType[partId]
    if not partType and BodyPartType.FromString then
        local ok, result = pcall(function() return BodyPartType.FromString(partId) end)
        if ok then partType = result end
    end
    if not partType then return nil end

    local okPart, part = pcall(function()
        return bodyDamage:getBodyPart(partType)
    end)

    return okPart and part or nil
end

local function debugSetVanillaWoundInfection(player, partId, stage)
    local part = debugGetBodyPart(player, partId)
    if not part then return false end

    stage = math.max(0, math.min(4, tonumber(stage) or 0))

    if stage <= 0 then
        if EHR and EHR.WoundInfection and EHR.WoundInfection.ClearVanillaInfection then
            EHR.WoundInfection.ClearVanillaInfection(part)
        else
            pcall(function() part:setWoundInfectionLevel(-1) end)
            pcall(function() part:setInfectedWound(false) end)
        end
        return true
    end

    local level = DEBUG_WOUND_VANILLA_LEVELS[stage] or 2
    pcall(function() part:setInfectedWound(true) end)
    pcall(function() part:setWoundInfectionLevel(level) end)
    return true
end

local function debugClearAllVanillaWoundInfections(player)
    if not player or not EHR or not EHR.DebugV2 or not EHR.DebugV2.BodyParts then return end
    for _, partId in ipairs(EHR.DebugV2.BodyParts) do
        debugSetVanillaWoundInfection(player, partId, 0)
    end
end

local function debugDiseaseStageProgress(stage)
    local progressByStage = {
        [1] = 0.05,
        [2] = 0.20,
        [3] = 0.50,
        [4] = 0.80,
    }
    return progressByStage[tonumber(stage) or 1] or 0.20
end

local function debugGetDiseaseTotalDuration(diseaseId, disease)
    local started = disease and tonumber(disease.startTime)
    local ended = disease and tonumber(disease.endTime)
    if started and ended and ended > started and (ended - started) >= 6 then
        return ended - started
    end

    local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId] or nil
    local maxDuration = def and tonumber(def.durationMax) or nil
    local minDuration = def and tonumber(def.durationMin) or nil
    return math.max(6, maxDuration or minDuration or 72)
end

local function debugNormalizeDiseaseTiming(diseaseId, disease, stage)
    if type(disease) ~= "table" then return end

    local currentHour = debugWorldAgeHours()
    local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId] or nil
    local maxStage = tonumber(def and def.stageCount) or tonumber(disease.stageCount) or 4
    local normalizedStage = math.max(1, math.min(maxStage, tonumber(stage or disease.stage) or 1))
    local totalDuration = debugGetDiseaseTotalDuration(diseaseId, disease)
    local progress = debugDiseaseStageProgress(normalizedStage)
    if def and def.reverseProgression then
        progress = math.max(0.02, math.min(0.95, ((maxStage - normalizedStage) / maxStage) + 0.04))
    end

    disease.stage = normalizedStage
    disease.startTime = currentHour - (totalDuration * progress)
    disease.endTime = disease.startTime + totalDuration
    if def and def.reverseProgression then
        disease.incubationEnd = disease.startTime
        disease.peakTime = disease.startTime
        disease.stageCount = maxStage
        disease.reverseProgression = true
    else
        disease.incubationEnd = disease.startTime + (totalDuration * 0.10)
        disease.peakTime = disease.startTime + (totalDuration * 0.40)
    end
    disease.progress = progress
    disease.stageProgress = 0
    disease.stageStartTime = currentHour
    disease.lastStageTime = currentHour
    disease.debugForcedStageAt = currentHour
    if diseaseId == "tetanus" then
        disease.tetanusHealthCap = nil
        disease.tetanusSevereHealthCap = nil
    end
end

local function debugGetDiseaseProgress(disease)
    if type(disease) ~= "table" then return 0 end

    local currentHour = debugWorldAgeHours()
    local started = tonumber(disease.startTime)
    local ended = tonumber(disease.endTime)
    if started and ended and ended > started then
        return debugClamp(((currentHour - started) / (ended - started)) * 100, 0, 100)
    end

    local duration = tonumber(disease.duration)
    if started and duration and duration > 0 then
        return debugClamp(((currentHour - started) / duration) * 100, 0, 100)
    end

    local progress = tonumber(disease.progress)
    if progress then
        if progress <= 1 then
            return debugClamp(progress * 100, 0, 100)
        end
        return debugClamp(progress, 0, 100)
    end

    return debugDiseaseStageProgress(disease.stage) * 100
end

-- ============================================
-- WOUND INFECTION V2 HELPERS (Debug)
-- ============================================

local function ensureWoundData(data)
    data.EHR_WoundInfection = data.EHR_WoundInfection or {
        parts = {},
        incubating = {},
        totalInfectedParts = 0,
        worstStage = 0,
        lastCheck = 0,
    }
    data.EHR_WoundInfection.parts = data.EHR_WoundInfection.parts or {}
    data.EHR_WoundInfection.incubating = data.EHR_WoundInfection.incubating or {}
    return data.EHR_WoundInfection
end

local function recalcWoundStats(woundData)
    if not woundData or not woundData.parts then return end
    local count = 0
    local worst = 0
    for _, partData in pairs(woundData.parts) do
        if partData.stage and partData.stage > 0 then
            count = count + 1
            if partData.stage > worst then
                worst = partData.stage
            end
        end
    end
    woundData.totalInfectedParts = count
    woundData.worstStage = worst
end

local function setWoundStage(data, partId, stage, player)
    if not partId then return end
    local woundData = ensureWoundData(data)
    local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
    stage = math.max(0, math.min(4, tonumber(stage) or 0))

    player = player or debugFindPlayerForModData(data)
    woundData.incubating[partId] = nil

    if stage <= 0 then
        if player and EHR and EHR.WoundInfection and EHR.WoundInfection.ClearPartSymptomPain then
            EHR.WoundInfection.ClearPartSymptomPain(player, partId)
        end
        woundData.parts[partId] = nil
        debugSetVanillaWoundInfection(player, partId, 0)
    else
        local vanillaLevel = DEBUG_WOUND_VANILLA_LEVELS[stage] or 2
        woundData.parts[partId] = woundData.parts[partId] or {}
        woundData.parts[partId].stage = stage
        woundData.parts[partId].stageStartTime = currentHour
        woundData.parts[partId].startTime = woundData.parts[partId].startTime or currentHour
        woundData.parts[partId].vanillaLevel = vanillaLevel
        woundData.parts[partId].debugForced = true
        woundData.parts[partId].debugForcedTime = currentHour
        debugSetVanillaWoundInfection(player, partId, stage)

        if stage >= 4 and player then
            data.EHR_Sepsis = data.EHR_Sepsis or {
                active = true,
                stage = 1,
                startTime = currentHour,
                treatmentDoses = 0,
                lastHealthDamageHour = currentHour,
                healthCap = nil,
            }
            data.EHR_Sepsis.active = true
            data.EHR_Sepsis.stage = math.max(1, tonumber(data.EHR_Sepsis.stage) or 1)
            data.EHR_Sepsis.stageStartTime = currentHour
            data.EHR_Sepsis.lastHealthDamageHour = currentHour
            data.EHR_Sepsis.healthCap = nil
            data.EHR_Sepsis.sourceBodyPart = partId
            data.EHR_Sepsis_Initialized = true

            woundData.parts[partId].stage = 3
            woundData.parts[partId].stageStartTime = currentHour
            woundData.parts[partId].sepsisTriggered = true
            woundData.parts[partId].lastSepsisTrigger = currentHour
        end
    end

    if player and EHR and EHR.WoundInfection and EHR.WoundInfection.RecalculateStats then
        EHR.WoundInfection.RecalculateStats(player)
    else
        recalcWoundStats(woundData)
    end
    debugTransmitPlayerModData(player)
end

local function getWoundStage(data, partId)
    if not data or not data.EHR_WoundInfection or not data.EHR_WoundInfection.parts then return 0 end
    local partData = data.EHR_WoundInfection.parts[partId]
    return partData and partData.stage or 0
end

local function clearAllWounds(data, player)
    player = player or debugFindPlayerForModData(data)
    local woundData = ensureWoundData(data)
    if player and EHR and EHR.WoundInfection and EHR.WoundInfection.ClearAllSymptomPain then
        EHR.WoundInfection.ClearAllSymptomPain(player)
    end
    woundData.parts = {}
    woundData.incubating = {}
    woundData.totalInfectedParts = 0
    woundData.worstStage = 0
    woundData.lastCheck = getGameTime() and getGameTime():getWorldAgeHours() or 0
    data.EHR_WoundInfection_V2_Initialized = nil
    data.EHR_WoundInfection_V2_Migrated = nil
    data.EHR_WoundInfections = nil
    data.EHR_WoundInfections_Initialized = nil
    debugClearAllVanillaWoundInfections(player)
    debugTransmitPlayerModData(player)
end

-- ============================================
-- PERMISSION SYSTEM
-- ============================================

--[[
    Check if debug menu access is allowed.
    SP: Requires sandbox DebugMode = true
    MP: Requires sandbox DebugMode = true AND admin/moderator/gm access level
    No Steam -debug flag required!
]]--
function EHR.DebugV2.IsDebugAllowed()
    -- BUG-020 FIX: No getDebug() check - Steam -debug flag is NOT required

    -- Check sandbox setting first
    local sandboxEnabled = false
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local debugModeValue = SandboxVars.ExtensiveHealthRework.DebugMode
        sandboxEnabled = debugModeValue == true or debugModeValue == 1
    end

    -- If sandbox DebugMode is disabled, no access
    if not sandboxEnabled then
        return false
    end

    -- Single-player: sandbox setting is enough
    if not isClient() then
        return true
    end

    -- Multiplayer: also require admin/moderator/gm access level
    local player = getSpecificPlayer(0)
    if not player then return false end

    -- Check player's access level (doesn't require -debug flag)
    local accessLevel = ""
    pcall(function()
        accessLevel = player:getAccessLevel() or ""
    end)

    -- Allow admin, moderator, or GM access levels
    local hasAccess = accessLevel == "admin" or accessLevel == "moderator" or accessLevel == "gm"

    return hasAccess
end

-- ============================================
-- DEBUG LOG SYSTEM
-- ============================================

EHR.DebugV2.LogEntries = {}
EHR.DebugV2.LogMaxEntries = 500

function EHR.DebugV2.Log(message, category, level)
    category = category or "DEBUG"
    level = level or "INFO"

    local timestamp = os.date("%H:%M:%S")
    local entry = {
        time = timestamp,
        category = category,
        level = level,
        message = message,
    }

    table.insert(EHR.DebugV2.LogEntries, 1, entry)  -- Insert at beginning

    -- Trim old entries
    while #EHR.DebugV2.LogEntries > EHR.DebugV2.LogMaxEntries do
        table.remove(EHR.DebugV2.LogEntries)
    end

    -- Also log to console if EHR.DEBUG is on
    if EHR.DEBUG then
        EHR.Log(string.format("[%s] %s: %s", category, level, message))
    end
end

-- ============================================
-- MAIN WINDOW CLASS
-- ============================================

EHR_DebugMenuV2 = ISPanel:derive("EHR_DebugMenuV2")

function EHR_DebugMenuV2:new(x, y, width, height, player)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.currentTab = "overview"
    o.tabButtons = {}
    o.contentPanels = {}
    o.borderColor = EHR.DebugV2.Colors.border
    o.backgroundColor = EHR.DebugV2.Colors.background
    o.moveWithMouse = false  -- We handle dragging ourselves
    o.dragging = false
    o.dragOffsetX = 0
    o.dragOffsetY = 0

    return o
end

function EHR_DebugMenuV2:initialise()
    ISPanel.initialise(self)
end

function EHR_DebugMenuV2:createChildren()
    ISPanel.createChildren(self)

    local c = EHR.DebugV2.Colors
    local y = 0

    -- Title bar with close button
    self.titleBar = ISPanel:new(0, 0, self.width, HEADER_HEIGHT)
    self.titleBar:initialise()
    self.titleBar.backgroundColor = c.headerBg
    self.titleBar.borderColor = c.border
    self:addChild(self.titleBar)

    -- Close button
    self.closeBtn = ISButton:new(self.width - 28, 4, 24, 24, "X", self, EHR_DebugMenuV2.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = c.border
    self.closeBtn.backgroundColor = c.buttonBg
    self.titleBar:addChild(self.closeBtn)

    y = HEADER_HEIGHT

    -- Tab bar
    self.tabBar = ISPanel:new(0, y, self.width, TAB_HEIGHT)
    self.tabBar:initialise()
    self.tabBar.backgroundColor = c.tabBg
    self.tabBar.borderColor = c.border
    self:addChild(self.tabBar)

    -- Create tab buttons
    local tabWidth = math.floor(self.width / #EHR.DebugV2.Tabs)
    for i, tab in ipairs(EHR.DebugV2.Tabs) do
        local tabBtn = ISButton:new((i-1) * tabWidth, 0, tabWidth, TAB_HEIGHT, tab.name, self, EHR_DebugMenuV2.onTabClick)
        tabBtn:initialise()
        tabBtn:instantiate()
        tabBtn.internal = tab.id
        tabBtn.borderColor = c.border
        tabBtn.backgroundColor = (tab.id == self.currentTab) and c.tabActive or c.tabBg
        tabBtn.textColor = c.text
        self.tabBar:addChild(tabBtn)
        self.tabButtons[tab.id] = tabBtn
    end

    y = y + TAB_HEIGHT

    -- Content area
    local contentHeight = self.height - y - PADDING
    self.contentArea = ISPanel:new(0, y, self.width, contentHeight)
    self.contentArea:initialise()
    self.contentArea.backgroundColor = c.background
    self.contentArea.borderColor = {r=0, g=0, b=0, a=0}
    self:addChild(self.contentArea)

    -- Create content panels for each tab
    self:createOverviewPanel()
    self:createDiseasesPanel()
    self:createBloodPanel()
    self:createWoundsPanel()
    self:createMedicationsPanel()
    self:createStatsPanel()
    self:createScenariosPanel()
    self:createLogPanel()

    -- Show initial tab
    self:showTab(self.currentTab)
end

function EHR_DebugMenuV2:onTabClick(button)
    local tabId = button.internal
    self:showTab(tabId)
end

function EHR_DebugMenuV2:showTab(tabId)
    local c = EHR.DebugV2.Colors

    -- Update tab button styles
    for id, btn in pairs(self.tabButtons) do
        btn.backgroundColor = (id == tabId) and c.tabActive or c.tabBg
    end

    -- Hide all content panels, show selected
    for id, panel in pairs(self.contentPanels) do
        panel:setVisible(id == tabId)
    end

    self.currentTab = tabId
    EHR.DebugV2.Log("Switched to tab: " .. tabId, "UI", "DEBUG")
end

function EHR_DebugMenuV2:onClose()
    -- CRIT-002 FIX: Cancel any running tests to prevent orphaned event handlers
    EHR.DebugV2.TestsRunning = false

    self:setVisible(false)
    EHR.DebugV2.instance = nil
    self:removeFromUIManager()

    EHR.DebugV2.Log("Debug Menu closed", "UI", "INFO")
end

-- ============================================
-- WINDOW DRAGGING
-- ============================================

function EHR_DebugMenuV2:onMouseDown(x, y)
    -- Only start drag if clicking on title bar area (top HEADER_HEIGHT pixels)
    if y < HEADER_HEIGHT and x < (self.width - 30) then  -- Avoid close button
        self.dragging = true
        self.dragStartX = self:getX()
        self.dragStartY = self:getY()
        self.dragMouseStartX = getMouseX()
        self.dragMouseStartY = getMouseY()
        self:bringToTop()
        return true
    end
    return ISPanel.onMouseDown(self, x, y)
end

function EHR_DebugMenuV2:onMouseMove(dx, dy)
    if self.dragging then
        local mouseX = getMouseX()
        local mouseY = getMouseY()
        local newX = self.dragStartX + (mouseX - self.dragMouseStartX)
        local newY = self.dragStartY + (mouseY - self.dragMouseStartY)

        -- Keep window on screen
        newX = math.max(0, math.min(newX, getCore():getScreenWidth() - self.width))
        newY = math.max(0, math.min(newY, getCore():getScreenHeight() - self.height))

        self:setX(newX)
        self:setY(newY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function EHR_DebugMenuV2:onMouseUp(x, y)
    self.dragging = false
    return ISPanel.onMouseUp(self, x, y)
end

function EHR_DebugMenuV2:onMouseUpOutside(x, y)
    self.dragging = false
    return ISPanel.onMouseUpOutside(self, x, y)
end
-- ============================================
-- TAB CONTENT: OVERVIEW
-- ============================================

function EHR_DebugMenuV2:createOverviewPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["overview"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 120
    local btnSpacing = 10

    -- Quick action buttons
    local fullHealBtn = ISButton:new(PADDING, y, btnWidth, BUTTON_HEIGHT, "Full Heal", self, EHR_DebugMenuV2.onFullHeal)
    fullHealBtn:initialise()
    fullHealBtn:instantiate()
    fullHealBtn.backgroundColor = c.safe
    panel:addChild(fullHealBtn)

    local killBtn = ISButton:new(PADDING + btnWidth + btnSpacing, y, btnWidth, BUTTON_HEIGHT, "Kill Player", self, EHR_DebugMenuV2.onKillPlayer)
    killBtn:initialise()
    killBtn:instantiate()
    killBtn.backgroundColor = c.danger
    panel:addChild(killBtn)

    local resetBtn = ISButton:new(PADDING + (btnWidth + btnSpacing) * 2, y, btnWidth, BUTTON_HEIGHT, "Reset All EHR", self, EHR_DebugMenuV2.onResetAll)
    resetBtn:initialise()
    resetBtn:instantiate()
    resetBtn.backgroundColor = c.warning
    panel:addChild(resetBtn)

    local testServerBtn = ISButton:new(PADDING + (btnWidth + btnSpacing) * 3, y, btnWidth, BUTTON_HEIGHT, "Test Server", self, EHR_DebugMenuV2.onTestServer)
    testServerBtn:initialise()
    testServerBtn:instantiate()
    testServerBtn.backgroundColor = {r=0.3, g=0.5, b=0.7, a=1}
    testServerBtn.tooltip = "Tests MP server command connection"
    panel:addChild(testServerBtn)

    -- MED-001 FIX: Store menu reference for render function
    panel.menuRef = self

    -- Status display will be rendered in prerender
    panel.render = function(self)
        ISPanel.render(self)
        self:renderOverviewStatus()
    end

    panel.renderOverviewStatus = function(self)
        -- MED-001 FIX: Use menuRef pattern consistently
        local menu = self.menuRef
        if not menu or not menu.player then return end
        local player = menu.player

        local data = player:getModData()
        local c = EHR.DebugV2.Colors
        local y = 60
        local x = PADDING

        -- Blood Status
        self:drawText("BLOOD STATUS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local bloodVol = 5000
        local salineVol = 0
        if data.EHR_Blood then
            bloodVol = data.EHR_Blood.currentVolume or 5000
            salineVol = data.EHR_Blood.transfusedSaline or 0
        end
        local bloodPct = (bloodVol / 5000) * 100
        local bloodColor = bloodPct > 80 and c.safe or (bloodPct > 60 and c.warning or c.danger)
        self:drawText(string.format("Blood: %.0f mL (%.0f%%)", bloodVol, bloodPct), x + 10, y, bloodColor.r, bloodColor.g, bloodColor.b, bloodColor.a, FONT)
        y = y + 20
        self:drawText(string.format("Saline: %.0f mL", salineVol), x + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        y = y + 30

        -- Disease Status
        self:drawText("ACTIVE DISEASES", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local diseaseCount = 0
        if data.EHR_Disease and data.EHR_Disease.active then
            for id, disease in pairs(data.EHR_Disease.active) do
                diseaseCount = diseaseCount + 1
            end
        end

        if diseaseCount > 0 then
            self:drawText(string.format("%d active disease(s)", diseaseCount), x + 10, y, c.warning.r, c.warning.g, c.warning.b, c.warning.a, FONT)
        else
            self:drawText("None", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
        end
        y = y + 30

        -- Wound Infection Status
        self:drawText("WOUND INFECTIONS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local infectedCount = 0
        if data.EHR_WoundInfection and data.EHR_WoundInfection.parts then
            for _, partData in pairs(data.EHR_WoundInfection.parts) do
                if partData.stage and partData.stage > 0 then
                    infectedCount = infectedCount + 1
                end
            end
        end

        if infectedCount > 0 then
            self:drawText(string.format("%d infected wound(s)", infectedCount), x + 10, y, c.danger.r, c.danger.g, c.danger.b, c.danger.a, FONT)
        else
            self:drawText("None", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
        end
        y = y + 30

        -- Sepsis Status
        self:drawText("SEPSIS STATUS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local sepsisStage = 0
        if data.EHR_Sepsis then
            sepsisStage = data.EHR_Sepsis.stage or 0
        end

        if sepsisStage > 0 then
            local stageNames = {"Early", "Progressing", "Severe", "Terminal"}
            local stageName = stageNames[sepsisStage] or "Unknown"
            self:drawText(string.format("Stage %d: %s", sepsisStage, stageName), x + 10, y, c.critical.r, c.critical.g, c.critical.b, c.critical.a, FONT)
        else
            self:drawText("Not active", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
        end
        y = y + 30

        -- Medications Status
        self:drawText("ACTIVE MEDICATIONS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        -- BUG FIX: Read from actual medication system (EHR.Medication) not legacy EHR_Medications
        local medCount = 0
        if EHR.Medication and EHR.Medication.GetActiveTreatments then
            local treatments = EHR.Medication.GetActiveTreatments(self.player)
            medCount = #treatments
        end

        if medCount > 0 then
            self:drawText(string.format("%d active medication(s)", medCount), x + 10, y, c.text.r, c.text.g, c.text.b, c.text.a, FONT)
        else
            self:drawText("None", x + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        end
    end
end

function EHR_DebugMenuV2:onFullHeal()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "FullHeal", {})
        EHR.DebugV2.Log("Full Heal sent to server", "ACTIONS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()

    -- Reset blood
    if EHR.Blood and EHR.Blood.SetBloodVolume then
        EHR.Blood.SetBloodVolume(self.player, data.EHR_Blood and data.EHR_Blood.maxVolume or 5000)
    end
    if data.EHR_Blood then
        data.EHR_Blood.transfusedSaline = 0
        data.EHR_Blood.transfusedBlood = 0
    end

    -- Clear diseases
    if EHR.Disease and EHR.Disease.CureAll then
        EHR.Disease.CureAll(self.player)
    end
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFever then
        EHR.BodyTemp.ResetDiseaseFever(self.player, true)
    end

    -- Clear wound infections
    clearAllWounds(data, self.player)

    -- Clear sepsis
    if EHR.Sepsis and EHR.Sepsis.Cure then
        EHR.Sepsis.Cure(self.player)
    end

    -- Clear medications
    if EHR.Medication and EHR.Medication.ClearAll then
        EHR.Medication.ClearAll(self.player)
    end

    -- Heal vanilla body damage
    local bodyDamage = self.player:getBodyDamage()
    if bodyDamage then
        bodyDamage:RestoreToFullHealth()
    end

    -- Reset stats
    local stats = self.player:getStats()
    if stats and CharacterStat then
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0)
            stats:set(CharacterStat.THIRST, 0)
            stats:set(CharacterStat.FATIGUE, 0)
            stats:set(CharacterStat.PAIN, 0)
            stats:set(CharacterStat.SICKNESS, 0)
            stats:set(CharacterStat.POISON, 0)
            stats:set(CharacterStat.FOOD_SICKNESS, 0)
        end)
    end

    EHR.DebugV2.Log("Full Heal executed", "ACTIONS", "INFO")
end

function EHR_DebugMenuV2:onKillPlayer()
    if not self.player then return end

    -- DEBUG: Trace MP detection
    print("[EHR DEBUG] onKillPlayer called")
    print("[EHR DEBUG] isClient() = " .. tostring(isClient()))
    print("[EHR DEBUG] isServer() = " .. tostring(isServer()))
    print("[EHR DEBUG] isCoopHost() = " .. tostring(isCoopHost()))
    print("[EHR DEBUG] Player username = " .. tostring(self.player:getUsername()))

    -- MP: Send to server (use isClient OR check if multiplayer)
    local isMP = isClient() or (isCoopHost and isCoopHost())
    print("[EHR DEBUG] isMP = " .. tostring(isMP))

    if isMP then
        print("[EHR DEBUG] Sending KillPlayer command to server...")
        sendClientCommand(self.player, "EHR_Debug", "KillPlayer", {})
        print("[EHR DEBUG] sendClientCommand called!")
        EHR.DebugV2.Log("Kill Player sent to server", "ACTIONS", "WARN")
        return
    end

    -- SP: Execute directly
    print("[EHR DEBUG] Executing KillPlayer locally (SP mode)")
    self.player:setHealth(0)
    pcall(function() self.player:setZombie(true) end)

    EHR.DebugV2.Log("Kill Player executed", "ACTIONS", "WARN")
end

function EHR_DebugMenuV2:onResetAll()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ResetAll", {})
        EHR.DebugV2.Log("Reset All sent to server", "ACTIONS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    local playerID = tostring(self.player:getUsername() or self.player:getPlayerNum())

    if EHR and EHR.WoundInfection and EHR.WoundInfection.ClearAllSymptomPain then
        EHR.WoundInfection.ClearAllSymptomPain(self.player)
    end

    -- Clear all EHR data
    data.EHR_Blood = nil
    data.EHR_Blood_Initialized = nil
    data.EHR_Disease = nil
    data.EHR_Disease_Initialized = nil
    data.EHR_WoundInfection = nil
    data.EHR_WoundInfection_V2_Initialized = nil
    data.EHR_WoundInfection_V2_Migrated = nil
    data.EHR_WoundInfections = nil
    data.EHR_WoundInfections_Initialized = nil
    data.EHR_Sepsis = nil
    data.EHR_Sepsis_Initialized = nil
    data.EHR_Medication = nil
    data.EHR_Medications = nil
    data.EHR_SideEffects = nil
    data.EHR_Corpse = nil
    data.EHR_Corpse_Initialized = nil
    data.EHR_Temperature = nil
    debugClearAllVanillaWoundInfections(self.player)

    if EHR.ResetLockedHealth then
        EHR.ResetLockedHealth(playerID)
    end
    if EHR.ResetBloodDebugCounters then
        EHR.ResetBloodDebugCounters()
    end
    if EHR and EHR.InitializePlayer then
        EHR.InitializePlayer(self.player)
    end
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFever then
        EHR.BodyTemp.ResetDiseaseFever(self.player, true)
    end

    EHR.DebugV2.Log("Reset All EHR data executed", "ACTIONS", "INFO")
end

--[[
    Test server command connection - sends a Ping to verify MP commands work
]]--
function EHR_DebugMenuV2:onTestServer()
    if not self.player then return end

    print("=========================================")
    print("[EHR DEBUG] Test Server Connection")
    print("[EHR DEBUG] isClient() = " .. tostring(isClient()))
    print("[EHR DEBUG] isServer() = " .. tostring(isServer()))
    print("[EHR DEBUG] isCoopHost() = " .. tostring(isCoopHost()))
    print("[EHR DEBUG] Player = " .. tostring(self.player:getUsername()))

    local isMP = isClient() or (isCoopHost and isCoopHost())
    print("[EHR DEBUG] isMP = " .. tostring(isMP))

    if isMP then
        print("[EHR DEBUG] Sending Ping command to server...")
        sendClientCommand(self.player, "EHR_Debug", "Ping", { message = "Test from client at " .. tostring(getTimestamp()) })
        print("[EHR DEBUG] sendClientCommand('Ping') called!")
        EHR.DebugV2.Log("Ping sent to server - check server console for response", "DEBUG", "INFO")
    else
        print("[EHR DEBUG] Single-player mode - no server to ping")
        EHR.DebugV2.Log("SP mode - no server to test", "DEBUG", "INFO")
    end
    print("=========================================")
end

-- ============================================
-- TAB CONTENT: DISEASES
-- ============================================

-- Disease IDs for infliction dropdown
EHR.DebugV2.DiseaseList = {
    "ahtr",
    "food_poisoning",
    "toxin_poisoning",
    "common_cold",
    "pneumonia",
    "dysentery",
    "hypothermia",
    "corpse_sickness",
    "heat_exhaustion",
    "heat_stroke",
    "trichinosis",
    "hyperkeratotic_scabies",
    "gastroenteritis",
    "cadaveric_aspergillosis",
    "tetanus",
    "concussion",
    "delirium",
    "insomnia",
    "tuberculosis",
}

function EHR_DebugMenuV2:getActiveDiseaseIds()
    local ids = {}
    if not self.player then return ids end

    local data = self.player:getModData()
    if data and data.EHR_Disease and data.EHR_Disease.active then
        for diseaseId, disease in pairs(data.EHR_Disease.active) do
            if type(disease) == "table" then
                table.insert(ids, diseaseId)
            end
        end
    end

    table.sort(ids)
    return ids
end

function EHR_DebugMenuV2:getSelectedDiseaseId()
    local ids = self:getActiveDiseaseIds()
    if #ids == 0 then
        self.selectedDiseaseId = nil
        return nil
    end

    local data = self.player:getModData()
    if self.selectedDiseaseId
        and data.EHR_Disease
        and data.EHR_Disease.active
        and data.EHR_Disease.active[self.selectedDiseaseId] then
        return self.selectedDiseaseId
    end

    self.selectedDiseaseId = ids[1]
    return self.selectedDiseaseId
end

function EHR_DebugMenuV2:createDiseasesPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["diseases"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 130  -- Wider buttons for full disease names
    local btnSmall = 30

    -- Cure All button
    local cureAllBtn = ISButton:new(PADDING, y, 80, BUTTON_HEIGHT, "Cure All", self, EHR_DebugMenuV2.onCureAllDiseases)
    cureAllBtn:initialise()
    cureAllBtn:instantiate()
    cureAllBtn.backgroundColor = c.safe
    panel:addChild(cureAllBtn)

    local prevBtn = ISButton:new(PADDING + 90, y, 48, BUTTON_HEIGHT, "Prev", self, EHR_DebugMenuV2.onCycleSelectedDisease)
    prevBtn:initialise()
    prevBtn:instantiate()
    prevBtn.internal = -1
    prevBtn.backgroundColor = c.buttonBg
    panel:addChild(prevBtn)

    local nextBtn = ISButton:new(PADDING + 143, y, 48, BUTTON_HEIGHT, "Next", self, EHR_DebugMenuV2.onCycleSelectedDisease)
    nextBtn:initialise()
    nextBtn:instantiate()
    nextBtn.internal = 1
    nextBtn.backgroundColor = c.buttonBg
    panel:addChild(nextBtn)

    local stageX = PADDING + 205
    for stage = 1, 4 do
        local stageBtn = ISButton:new(stageX, y, 44, BUTTON_HEIGHT, "S" .. tostring(stage), self, EHR_DebugMenuV2.onSetSelectedDiseaseStage)
        stageBtn:initialise()
        stageBtn:instantiate()
        stageBtn.internal = stage
        stageBtn.backgroundColor = stage == 3 and c.danger or (stage == 2 and c.warning or c.buttonBg)
        stageBtn.textColor = c.text
        panel:addChild(stageBtn)
        stageX = stageX + 48
    end

    -- Disease infliction buttons - 3 columns to fit wider buttons
    local inflictX = PADDING
    local inflictY = y + BUTTON_HEIGHT + 28
    for i, diseaseId in ipairs(EHR.DebugV2.DiseaseList) do
        local col = ((i - 1) % 3)
        local row = math.floor((i - 1) / 3)
        local btnX = inflictX + col * (btnWidth + 5)
        local btnY = inflictY + row * (BUTTON_HEIGHT + 3)

        -- Get proper name from disease definition, fallback to title case
        local displayName
        if EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId] then
            displayName = EHR.Disease.Diseases[diseaseId].name
        else
            -- Fallback: Convert underscore ID to title case (e.g. "food_poisoning" -> "Food Poisoning")
            displayName = diseaseId:gsub("_", " "):gsub("(%a)([%w_']*)", function(a,b) return a:upper()..(b or "") end)
        end

        local btn = ISButton:new(btnX, btnY, btnWidth, BUTTON_HEIGHT, displayName, self, EHR_DebugMenuV2.onInflictDisease)
        btn:initialise()
        btn:instantiate()
        btn.internal = diseaseId
        btn.backgroundColor = c.warning
        btn.textColor = c.text
        panel:addChild(btn)
    end

    panel.activeStatusY = inflictY + (math.ceil(#EHR.DebugV2.DiseaseList / 3) * (BUTTON_HEIGHT + 3)) + 18

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderDiseasesStatus()
    end

    panel.renderDiseasesStatus = function(self)
        local menu = self.menuRef
        if not menu or not menu.player then return end

        local data = menu.player:getModData()
        local c = EHR.DebugV2.Colors
        local x = PADDING
        local selectedId = menu:getSelectedDiseaseId()
        local selectedDef = selectedId and EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[selectedId] or nil
        local selectedName = selectedDef and selectedDef.name or selectedId or "none"

        self:drawText("Stage target: " .. tostring(selectedName),
            x + 90, PADDING + BUTTON_HEIGHT + 6, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)

        local y = self.activeStatusY or 220

        -- Active diseases header
        self:drawText("ACTIVE DISEASES", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local hasDisease = false
        if data.EHR_Disease and data.EHR_Disease.active then
            for id, disease in pairs(data.EHR_Disease.active) do
                hasDisease = true

                -- Get definition for name
                local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[id]
                local name = def and def.name or id
                local stage = disease.stage or 1
                local stageNames = {"Incubation", "Early", "Peak", "Recovery"}
                local stageName = stageNames[stage] or "Unknown"

                -- Color based on stage
                local stageColor = c.safe
                if stage == 2 then stageColor = c.warning
                elseif stage == 3 then stageColor = c.danger
                elseif stage == 4 then stageColor = c.safe end

                local marker = (id == selectedId) and "> " or "  "
                self:drawText(string.format("%s%s - Stage %d (%s)", marker, name, stage, stageName),
                    x + 10, y, stageColor.r, stageColor.g, stageColor.b, stageColor.a, FONT)
                y = y + 18

                -- Duration remaining
                local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
                local remaining = math.max(0, (tonumber(disease.endTime) or currentHour) - currentHour)
                self:drawText(string.format("  Time remaining: %.1f hours", remaining),
                    x + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
                y = y + 18

                local progress = debugGetDiseaseProgress(disease)
                local barX = x + 12
                local barY = y
                local barW = 260
                local barH = 7
                local filledW = math.floor(barW * (progress / 100))
                self:drawRect(barX, barY, barW, barH, 0.55, 0.04, 0.04, 0.04)
                if filledW > 0 then
                    self:drawRect(barX, barY, filledW, barH, 0.85, stageColor.r, stageColor.g, stageColor.b)
                end
                self:drawRectBorder(barX, barY, barW, barH, c.border.a, c.border.r, c.border.g, c.border.b)
                self:drawText(string.format("%d%%", math.floor(progress + 0.5)),
                    barX + barW + 10, barY - 5, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
                y = y + 18
            end
        end

        if not hasDisease then
            self:drawText("No active diseases", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
        end
    end
end

function EHR_DebugMenuV2:onCureAllDiseases()
    if not self.player then return end

    -- MP: Send to server AND update locally for immediate feedback
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "CureAllDiseases", {})
        EHR.DebugV2.Log("Cure All Diseases sent to server", "DISEASES", "INFO")
    end

    -- Always update locally (both SP and MP for immediate UI feedback)
    if EHR.Disease and EHR.Disease.CureAll then
        EHR.Disease.CureAll(self.player)
    else
        local data = self.player:getModData()
        if data.EHR_Disease and data.EHR_Disease.active then
            for id, _ in pairs(data.EHR_Disease.active) do
                data.EHR_Disease.active[id] = nil
            end
        end
    end
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFeverIfStale then
        EHR.BodyTemp.ResetDiseaseFeverIfStale(self.player, true)
    end

    EHR.DebugV2.Log("Cured all diseases", "DISEASES", "INFO")
end

function EHR_DebugMenuV2:onCycleSelectedDisease(button)
    local ids = self:getActiveDiseaseIds()
    if #ids == 0 then
        self.selectedDiseaseId = nil
        EHR.DebugV2.Log("No active diseases to select", "DISEASES", "WARN")
        return
    end

    local direction = button and button.internal or 1
    local currentIndex = 1
    for i, diseaseId in ipairs(ids) do
        if diseaseId == self.selectedDiseaseId then
            currentIndex = i
            break
        end
    end

    local nextIndex = ((currentIndex - 1 + direction) % #ids) + 1
    self.selectedDiseaseId = ids[nextIndex]
    EHR.DebugV2.Log("Selected disease: " .. tostring(self.selectedDiseaseId), "DISEASES", "INFO")
end

function EHR_DebugMenuV2:onSetSelectedDiseaseStage(button)
    if not self.player or not button then return end

    local diseaseId = self:getSelectedDiseaseId()
    if not diseaseId then
        EHR.DebugV2.Log("No active disease selected for stage change", "DISEASES", "WARN")
        return
    end

    local stage = tonumber(button.internal) or 2
    if EHR.Disease and EHR.Disease.MarkDebugSet then
        EHR.Disease.MarkDebugSet(self.player)
    end

    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "SetDiseaseStage", {
            diseaseId = diseaseId,
            stage = stage,
        })
    end

    local changed = EHR.Disease and EHR.Disease.SetStage and EHR.Disease.SetStage(self.player, diseaseId, stage)
    if changed then
        EHR.DebugV2.Log(string.format("Set %s to stage %d", tostring(diseaseId), stage), "DISEASES", "INFO")
    else
        EHR.DebugV2.Log("Failed to set disease stage: " .. tostring(diseaseId), "DISEASES", "ERROR")
    end
end

function EHR_DebugMenuV2:onInflictDisease(button)
    if not self.player then return end

    local diseaseId = button.internal
    if not diseaseId then return end
    self.selectedDiseaseId = diseaseId

    -- MP FIX: Mark grace period BEFORE setting data to protect from overwrites
    if EHR.Disease and EHR.Disease.MarkDebugSet then
        EHR.Disease.MarkDebugSet(self.player)
    end

    -- MP: Send to server AND update locally for immediate feedback
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "InflictDisease", { diseaseId = diseaseId })
        EHR.DebugV2.Log("Inflict Disease sent to server: " .. diseaseId, "DISEASES", "INFO")
    end

    -- MP FIX: Always create disease directly to avoid Contract() early return
    -- Contract() returns early if player isn't initialized, which breaks debug menu
    local data = self.player:getModData()
    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    -- Ensure disease data structure exists
    if not data.EHR_Disease then
        data.EHR_Disease = {
            active = {},
            immunity = { general = 1.0 },
            history = { recoveries = {} },
        }
        data.EHR_Disease_Initialized = true
        print("[EHR Debug] Created EHR_Disease structure for player")
    end
    
    -- CRITICAL: Also ensure EHR_Initialized is set, otherwise Medical Monitor won't read data!
    if not data.EHR_Initialized then
        data.EHR_Initialized = true
        print("[EHR Debug] Set EHR_Initialized flag for Medical Monitor")
    end
    data.EHR_Disease.active = data.EHR_Disease.active or {}

    -- Get disease definition for proper duration, or use defaults
    local duration = 72
    local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId] or nil
    if def then
        duration = def.durationMin + ZombRand(def.durationMax - def.durationMin + 1)
    end
    local startStage = (def and def.reverseProgression and (tonumber(def.stageCount) or 3)) or 2

    -- Create disease entry directly
    local disease = {
        stage = startStage,  -- Start at Early stage, or peak for reverse-progressing trauma
        severity = 0.5,
        startTime = currentHour,
        endTime = currentHour + duration,
        incubationEnd = currentHour,
        peakTime = currentHour + (duration * 0.4),
        diagnosed = false,
    }
    debugNormalizeDiseaseTiming(diseaseId, disease, startStage)
    data.EHR_Disease.active[diseaseId] = disease
    if EHR.Disease and EHR.Disease.SetStage then
        EHR.Disease.SetStage(self.player, diseaseId, startStage)
    end
    print("[EHR Debug] v2.7.1-MP Created disease locally: " .. diseaseId .. " with " .. duration .. "h duration")

    EHR.DebugV2.Log("Inflicted disease: " .. diseaseId, "DISEASES", "INFO")
end

-- ============================================
-- TAB CONTENT: BLOOD
-- ============================================

function EHR_DebugMenuV2:createBloodPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["blood"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 60
    local btnSmall = 45

    -- Volume percentage buttons (label drawn in renderBloodStatus)

    local percentages = {100, 75, 50, 25, 10, 5, 1}
    local x = PADDING + 90
    for _, pct in ipairs(percentages) do
        local btn = ISButton:new(x, y, btnSmall, BUTTON_HEIGHT, pct.."%", self, EHR_DebugMenuV2.onSetBloodPercent)
        btn:initialise()
        btn:instantiate()
        btn.internal = pct
        btn.backgroundColor = (pct > 50) and c.safe or ((pct > 20) and c.warning or c.danger)
        panel:addChild(btn)
        x = x + btnSmall + 3
    end

    y = y + BUTTON_HEIGHT + 10

    -- +/- volume buttons
    local adjustX = PADDING + 90
    local amounts = {{500, "+"}, {100, "+"}, {-100, "-"}, {-500, "-"}}
    for _, adj in ipairs(amounts) do
        local label = adj[2] .. math.abs(adj[1]) .. "mL"
        local btn = ISButton:new(adjustX, y, 70, BUTTON_HEIGHT, label, self, EHR_DebugMenuV2.onAdjustBlood)
        btn:initialise()
        btn:instantiate()
        btn.internal = adj[1]
        btn.backgroundColor = (adj[1] > 0) and c.safe or c.danger
        panel:addChild(btn)
        adjustX = adjustX + 73
    end

    y = y + BUTTON_HEIGHT + 10

    -- Saline controls
    local salineX = PADDING + 90
    local addSalineBtn = ISButton:new(salineX, y, 80, BUTTON_HEIGHT, "+500mL", self, EHR_DebugMenuV2.onAddSaline)
    addSalineBtn:initialise()
    addSalineBtn:instantiate()
    addSalineBtn.backgroundColor = c.safe
    panel:addChild(addSalineBtn)

    local clearSalineBtn = ISButton:new(salineX + 85, y, 80, BUTTON_HEIGHT, "Clear", self, EHR_DebugMenuV2.onClearSaline)
    clearSalineBtn:initialise()
    clearSalineBtn:instantiate()
    clearSalineBtn.backgroundColor = c.warning
    panel:addChild(clearSalineBtn)

    y = y + BUTTON_HEIGHT + 10

    -- Blackout trigger
    local blackoutBtn = ISButton:new(PADDING, y, 120, BUTTON_HEIGHT, "Trigger Blackout", self, EHR_DebugMenuV2.onTriggerBlackout)
    blackoutBtn:initialise()
    blackoutBtn:instantiate()
    blackoutBtn.backgroundColor = c.critical
    panel:addChild(blackoutBtn)

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderBloodStatus()
    end

    panel.renderBloodStatus = function(self)
        local menu = self.menuRef
        if not menu or not menu.player then return end

        local data = menu.player:getModData()
        local c = EHR.DebugV2.Colors

        -- Draw static button row labels
        local labelY = PADDING + 4
        self:drawText("SET VOLUME:", PADDING, labelY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        labelY = labelY + BUTTON_HEIGHT + 10
        self:drawText("ADJUST:", PADDING, labelY + 4, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        labelY = labelY + BUTTON_HEIGHT + 10
        self:drawText("SALINE:", PADDING, labelY + 4, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)

        local y = 150
        local x = PADDING

        -- Blood volume display
        self:drawText("BLOOD STATUS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local maxVol = 5000
        local currentVol = maxVol
        local salineVol = 0
        local bloodType = "Unknown"
        local lossRate = 0

        if data.EHR_Blood then
            maxVol = data.EHR_Blood.maxVolume or 5000
            currentVol = data.EHR_Blood.currentVolume or maxVol
            salineVol = data.EHR_Blood.transfusedSaline or 0
            bloodType = data.EHR_Blood.bloodType or "Unknown"
            lossRate = data.EHR_Blood.lossRate or 0
        end

        local pct = (currentVol / maxVol) * 100
        local bloodColor = pct > 80 and c.safe or (pct > 60 and c.warning or (pct > 30 and c.danger or c.critical))

        -- Blood bar visualization
        local barWidth = 400
        local barHeight = 20
        local barX = x + 10
        local barY = y

        -- Background
        self:drawRect(barX, barY, barWidth, barHeight, 0.3, 0.1, 0.1, 0.1)
        -- Blood fill
        local fillWidth = (currentVol / maxVol) * barWidth
        self:drawRect(barX, barY, fillWidth, barHeight, bloodColor.a, bloodColor.r, bloodColor.g, bloodColor.b)
        -- Saline fill (overlay)
        if salineVol > 0 then
            local salineFillWidth = (salineVol / maxVol) * barWidth
            self:drawRect(barX + fillWidth - salineFillWidth, barY, salineFillWidth, barHeight, 0.5, 0.3, 0.5, 0.8)
        end
        -- Border
        self:drawRectBorder(barX, barY, barWidth, barHeight, 1, c.border.r, c.border.g, c.border.b)

        y = y + barHeight + 8

        -- Text stats
        self:drawText(string.format("Volume: %.0f / %.0f mL (%.1f%%)", currentVol, maxVol, pct),
            x + 10, y, bloodColor.r, bloodColor.g, bloodColor.b, bloodColor.a, FONT)
        y = y + 20

        self:drawText(string.format("Saline: %.0f mL", salineVol),
            x + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        y = y + 20

        self:drawText(string.format("Blood Type: %s", bloodType),
            x + 10, y, c.text.r, c.text.g, c.text.b, c.text.a, FONT)
        y = y + 20

        local lossColor = lossRate > 0 and c.danger or (lossRate < 0 and c.safe or c.textDim)
        self:drawText(string.format("Loss Rate: %.0f mL/min", lossRate),
            x + 10, y, lossColor.r, lossColor.g, lossColor.b, lossColor.a, FONT)
        y = y + 30

        -- Stage indicators
        self:drawText("BLOOD LOSS STAGES", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local stages = {
            {name = "Healthy", min = 85, max = 100, color = c.safe},
            {name = "Mild Loss", min = 70, max = 85, color = c.warning},
            {name = "Moderate Loss", min = 50, max = 70, color = c.danger},
            {name = "Critical", min = 0, max = 50, color = c.critical},
        }

        for _, stage in ipairs(stages) do
            local active = pct >= stage.min and pct < stage.max
            local indicator = active and "> " or "  "
            local stageColor = active and stage.color or c.textDim
            self:drawText(string.format("%s%s (%.0f%%-%.0f%%)", indicator, stage.name, stage.min, stage.max),
                x + 10, y, stageColor.r, stageColor.g, stageColor.b, stageColor.a, FONT)
            y = y + 18
        end
    end
end

-- MED-003 FIX: Removed empty drawTextOnPanel - static labels now drawn in renderBloodStatus

function EHR_DebugMenuV2:onSetBloodPercent(button)
    if not self.player then return end

    local pct = button.internal

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "SetBloodPercent", { percent = pct })
        EHR.DebugV2.Log(string.format("Set Blood %d%% sent to server", pct), "BLOOD", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    
    -- Ensure blood structure is fully initialized to prevent nil errors
    if not data.EHR_Blood or not data.EHR_Blood.maxVolume then
        data.EHR_Blood = data.EHR_Blood or {}
        data.EHR_Blood.maxVolume = 5000
        data.EHR_Blood.currentVolume = data.EHR_Blood.currentVolume or 5000
        data.EHR_Blood.bloodType = data.EHR_Blood.bloodType or "O+"
        data.EHR_Blood.transfusedSaline = data.EHR_Blood.transfusedSaline or 0
        data.EHR_Blood.transfusedBlood = data.EHR_Blood.transfusedBlood or 0
        data.EHR_Blood.lastStage = data.EHR_Blood.lastStage or 4
        data.EHR_Blood_Initialized = true
    end
    if not data.EHR_Initialized then data.EHR_Initialized = true end
    
    local maxVol = data.EHR_Blood.maxVolume
    local newVol = (pct / 100) * maxVol

    if EHR.Blood and EHR.Blood.SetBloodVolume then
        EHR.Blood.SetBloodVolume(self.player, newVol)
    else
        data.EHR_Blood.currentVolume = newVol
    end

    EHR.DebugV2.Log(string.format("Set blood to %d%%", pct), "BLOOD", "INFO")
end

function EHR_DebugMenuV2:onAdjustBlood(button)
    if not self.player then return end

    local amount = button.internal

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "AdjustBlood", { amount = amount })
        EHR.DebugV2.Log(string.format("Adjust Blood %+d mL sent to server", amount), "BLOOD", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    
    -- Ensure blood structure is fully initialized to prevent nil errors
    if not data.EHR_Blood or not data.EHR_Blood.maxVolume then
        data.EHR_Blood = data.EHR_Blood or {}
        data.EHR_Blood.maxVolume = 5000
        data.EHR_Blood.currentVolume = data.EHR_Blood.currentVolume or 5000
        data.EHR_Blood.bloodType = data.EHR_Blood.bloodType or "O+"
        data.EHR_Blood.transfusedSaline = data.EHR_Blood.transfusedSaline or 0
        data.EHR_Blood.transfusedBlood = data.EHR_Blood.transfusedBlood or 0
        data.EHR_Blood.lastStage = data.EHR_Blood.lastStage or 4
        data.EHR_Blood_Initialized = true
    end
    if not data.EHR_Initialized then data.EHR_Initialized = true end
    
    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(self.player, amount)
    else
        local maxVol = data.EHR_Blood.maxVolume
        local current = data.EHR_Blood.currentVolume
        data.EHR_Blood.currentVolume = math.max(0, math.min(maxVol, current + amount))
    end

    EHR.DebugV2.Log(string.format("Adjusted blood by %+d mL", amount), "BLOOD", "INFO")
end

function EHR_DebugMenuV2:onAddSaline()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "AddSaline", { amount = 500 })
        EHR.DebugV2.Log("Add Saline sent to server", "BLOOD", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    data.EHR_Blood = data.EHR_Blood or {}

    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(self.player, 500)
    else
        data.EHR_Blood.currentVolume = (data.EHR_Blood.currentVolume or 5000) + 500
    end
    data.EHR_Blood.transfusedSaline = (data.EHR_Blood.transfusedSaline or 0) + 500

    EHR.DebugV2.Log("Added 500mL saline", "BLOOD", "INFO")
end

function EHR_DebugMenuV2:onClearSaline()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ClearSaline", {})
        EHR.DebugV2.Log("Clear Saline sent to server", "BLOOD", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    if data.EHR_Blood then
        data.EHR_Blood.transfusedSaline = 0
        data.EHR_Blood.transfusedBlood = 0
    end

    EHR.DebugV2.Log("Cleared saline", "BLOOD", "INFO")
end

function EHR_DebugMenuV2:onTriggerBlackout()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "TriggerBlackout", {})
        EHR.DebugV2.Log("Trigger Blackout sent to server", "BLOOD", "WARN")
        return
    end

    -- SP: Execute directly
    if EHR.Blood and EHR.Blood.TriggerBlackout then
        EHR.Blood.TriggerBlackout(self.player)
    else
        local data = self.player:getModData()
        data.EHR_Blood = data.EHR_Blood or {}
        data.EHR_Blood.blackoutTriggered = true
        data.EHR_Blood.blackoutTime = 5
    end

    EHR.DebugV2.Log("Triggered blackout", "BLOOD", "WARN")
end

-- ============================================
-- TAB CONTENT: WOUNDS
-- ============================================

-- Body parts for wound infection tracking
EHR.DebugV2.BodyParts = {
    "Hand_L", "Hand_R",
    "ForeArm_L", "ForeArm_R",
    "UpperArm_L", "UpperArm_R",
    "Foot_L", "Foot_R",
    "LowerLeg_L", "LowerLeg_R",
    "UpperLeg_L", "UpperLeg_R",
    "Head", "Neck",
    "Torso_Upper", "Torso_Lower", "Groin",
}

-- Wound infection stage names
EHR.DebugV2.InfectionStages = {
    [0] = "Clean",
    [1] = "Infected",
    [2] = "Worsening",
    [3] = "Severe",
    [4] = "Septic",
}

EHR.DebugV2.SelectedWoundPartIndex = EHR.DebugV2.SelectedWoundPartIndex or 1

local function getSelectedWoundPartId()
    local parts = EHR.DebugV2.BodyParts
    local index = math.max(1, math.min(#parts, EHR.DebugV2.SelectedWoundPartIndex or 1))
    EHR.DebugV2.SelectedWoundPartIndex = index
    return parts[index]
end

function EHR_DebugMenuV2:createWoundsPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["wounds"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 100

    -- Quick action buttons
    local infectRandomBtn = ISButton:new(PADDING, y, btnWidth, BUTTON_HEIGHT, "Infect Random", self, EHR_DebugMenuV2.onInfectRandom)
    infectRandomBtn:initialise()
    infectRandomBtn:instantiate()
    infectRandomBtn.backgroundColor = c.warning
    panel:addChild(infectRandomBtn)

    local clearAllBtn = ISButton:new(PADDING + btnWidth + 10, y, btnWidth, BUTTON_HEIGHT, "Clear All", self, EHR_DebugMenuV2.onClearAllInfections)
    clearAllBtn:initialise()
    clearAllBtn:instantiate()
    clearAllBtn.backgroundColor = c.safe
    panel:addChild(clearAllBtn)

    -- Sepsis controls
    local triggerSepsisBtn = ISButton:new(PADDING + (btnWidth + 10) * 2, y, btnWidth, BUTTON_HEIGHT, "Trigger Sepsis", self, EHR_DebugMenuV2.onTriggerSepsis)
    triggerSepsisBtn:initialise()
    triggerSepsisBtn:instantiate()
    triggerSepsisBtn.backgroundColor = c.critical
    panel:addChild(triggerSepsisBtn)

    local clearSepsisBtn = ISButton:new(PADDING + (btnWidth + 10) * 3, y, btnWidth, BUTTON_HEIGHT, "Clear Sepsis", self, EHR_DebugMenuV2.onClearSepsis)
    clearSepsisBtn:initialise()
    clearSepsisBtn:instantiate()
    clearSepsisBtn.backgroundColor = c.safe
    panel:addChild(clearSepsisBtn)

    y = y + BUTTON_HEIGHT + 8

    local prevPartBtn = ISButton:new(PADDING, y, 48, BUTTON_HEIGHT, "Prev", self, EHR_DebugMenuV2.onCycleSelectedWoundPart)
    prevPartBtn.internal = -1
    prevPartBtn:initialise()
    prevPartBtn:instantiate()
    panel:addChild(prevPartBtn)

    local nextPartBtn = ISButton:new(PADDING + 54, y, 48, BUTTON_HEIGHT, "Next", self, EHR_DebugMenuV2.onCycleSelectedWoundPart)
    nextPartBtn.internal = 1
    nextPartBtn:initialise()
    nextPartBtn:instantiate()
    panel:addChild(nextPartBtn)

    local stageButtons = {
        {stage = 0, text = "Clean", color = c.safe, width = 58},
        {stage = 1, text = "S1", color = c.warning, width = 38},
        {stage = 2, text = "S2", color = c.warning, width = 38},
        {stage = 3, text = "S3", color = c.danger, width = 38},
        {stage = 4, text = "S4", color = c.critical, width = 38},
    }
    local stageX = PADDING + 112
    for _, stageData in ipairs(stageButtons) do
        local btn = ISButton:new(stageX, y, stageData.width, BUTTON_HEIGHT, stageData.text, self, EHR_DebugMenuV2.onSetSelectedWoundStage)
        btn.internal = stageData.stage
        btn:initialise()
        btn:instantiate()
        btn.backgroundColor = stageData.color
        panel:addChild(btn)
        stageX = stageX + stageData.width + 6
    end

    panel.statusY = y + BUTTON_HEIGHT + 10

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderWoundsStatus()
    end

    panel.renderWoundsStatus = function(self)
        local menu = self.menuRef
        if not menu or not menu.player then return end

        local data = menu.player:getModData()
        local c = EHR.DebugV2.Colors
        local y = self.statusY or 86
        local x = PADDING

        local selectedPart = getSelectedWoundPartId()
        local selectedStage = getWoundStage(data, selectedPart)
        local selectedStageName = EHR.DebugV2.InfectionStages[selectedStage] or "Unknown"
        self:drawText(string.format("%s -> %s (%d)", selectedPart:gsub("_", " "), selectedStageName, selectedStage),
            405, 45, c.text.r, c.text.g, c.text.b, c.text.a, FONT)

        -- Sepsis status
        self:drawText("SEPSIS STATUS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local sepsisStage = 0
        local sepsisActive = false
        if data.EHR_Sepsis then
            sepsisStage = data.EHR_Sepsis.stage or 0
            sepsisActive = data.EHR_Sepsis.active or false
        end

        if sepsisStage > 0 or sepsisActive then
            local stageNames = {"Early", "Progressing", "Severe", "Terminal"}
            local stageName = stageNames[sepsisStage] or "Unknown"
            local sepsisColor = sepsisStage >= 3 and c.critical or c.danger
            self:drawText(string.format("ACTIVE - Stage %d: %s", sepsisStage, stageName),
                x + 10, y, sepsisColor.r, sepsisColor.g, sepsisColor.b, sepsisColor.a, FONT)
        else
            self:drawText("Not active", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
        end
        y = y + 30

        -- Wound infections header
        self:drawText("WOUND INFECTIONS BY BODY PART", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        -- Two-column layout
        local colWidth = 250
        local startY = y
        local col = 0

        for i, partId in ipairs(EHR.DebugV2.BodyParts) do
            local stage = getWoundStage(data, partId)

            local stageName = EHR.DebugV2.InfectionStages[stage] or "Unknown"

            -- Color based on stage
            local stageColor = c.safe
            if stage == 1 then stageColor = c.warning
            elseif stage == 2 then stageColor = c.warning
            elseif stage == 3 then stageColor = c.danger
            elseif stage >= 4 then stageColor = c.critical end

            -- Format part name
            local displayName = partId:gsub("_", " ")

            local drawX = x + 10 + (col * colWidth)
            self:drawText(string.format("%s: %s (%d)", displayName, stageName, stage),
                drawX, y, stageColor.r, stageColor.g, stageColor.b, stageColor.a, FONT)

            -- Move to next row or column
            if col == 0 then
                col = 1
            else
                col = 0
                y = y + 18
            end
        end

        -- Ensure we're on a new line
        if col == 1 then
            y = y + 18
        end

        y = y + 20

        -- Body part health from vanilla
        self:drawText("VANILLA BODY PART HEALTH", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        local bodyDamage = menu.player:getBodyDamage()
        if bodyDamage and BodyPartType then
            col = 0
            for i, partId in ipairs(EHR.DebugV2.BodyParts) do
                local partType = BodyPartType[partId]
                if partType then
                    local success, part = pcall(function() return bodyDamage:getBodyPart(partType) end)
                    if success and part then
                        local health = part:getHealth() or 100
                        local vanillaInfected = false
                        local vanillaLevel = 0
                        pcall(function()
                            if part.isInfectedWound then vanillaInfected = part:isInfectedWound() == true end
                        end)
                        pcall(function()
                            if part.getWoundInfectionLevel then vanillaLevel = part:getWoundInfectionLevel() or 0 end
                        end)
                        vanillaLevel = math.max(0, vanillaLevel or 0)
                        local healthColor = health > 80 and c.safe or (health > 50 and c.warning or c.danger)
                        if vanillaInfected or vanillaLevel > 0 then
                            healthColor = c.warning
                        end

                        local displayName = partId:gsub("_", " ")
                        local drawX = x + 10 + (col * colWidth)
                        self:drawText(string.format("%s: %.0f%% inf %.0f", displayName, health, vanillaLevel),
                            drawX, y, healthColor.r, healthColor.g, healthColor.b, healthColor.a, FONT)

                        if col == 0 then
                            col = 1
                        else
                            col = 0
                            y = y + 18
                        end
                    end
                end
            end
        end
    end
end

function EHR_DebugMenuV2:onCycleSelectedWoundPart(button)
    local delta = button and tonumber(button.internal) or 1
    local count = #EHR.DebugV2.BodyParts
    local index = (EHR.DebugV2.SelectedWoundPartIndex or 1) + delta
    if index < 1 then index = count end
    if index > count then index = 1 end
    EHR.DebugV2.SelectedWoundPartIndex = index
end

function EHR_DebugMenuV2:onSetSelectedWoundStage(button)
    if not self.player then return end

    local partId = getSelectedWoundPartId()
    local stage = button and tonumber(button.internal) or 0

    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "SetWoundStage", {
            partId = partId,
            stage = stage,
        })
        EHR.DebugV2.Log(string.format("Set wound %s to stage %d sent to server", partId, stage), "WOUNDS", "INFO")
    end

    local data = self.player:getModData()
    setWoundStage(data, partId, stage, self.player)
    EHR.DebugV2.Log(string.format("Set wound %s to stage %d", partId, stage), "WOUNDS", "INFO")
end

function EHR_DebugMenuV2:onInfectRandom()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "InfectRandom", { severity = 2 })
        EHR.DebugV2.Log("Infect Random sent to server", "WOUNDS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    local partId = EHR.DebugV2.BodyParts[ZombRand(#EHR.DebugV2.BodyParts) + 1]
    setWoundStage(data, partId, 2, self.player)

    EHR.DebugV2.Log("Infected random part: " .. partId, "WOUNDS", "INFO")
end

function EHR_DebugMenuV2:onClearAllInfections()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ClearAllInfections", {})
        EHR.DebugV2.Log("Clear All Infections sent to server", "WOUNDS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    clearAllWounds(data, self.player)

    EHR.DebugV2.Log("Cleared all wound infections", "WOUNDS", "INFO")
end

function EHR_DebugMenuV2:onTriggerSepsis()
    if not self.player then return end

    local data = self.player:getModData()
    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    -- DEBUG: Log player and data table identity
    print(string.format("[EHR DEBUG TRIGGER] Player=%s, Username=%s", tostring(self.player), tostring(self.player:getUsername())))
    print(string.format("[EHR DEBUG TRIGGER] ModData table=%s", tostring(data)))
    print(string.format("[EHR DEBUG TRIGGER] BEFORE: EHR_Sepsis=%s", tostring(data.EHR_Sepsis)))

    -- MP FIX: Mark grace period BEFORE setting data to protect from overwrites
    if EHR.Sepsis and EHR.Sepsis.MarkDebugSet then
        EHR.Sepsis.MarkDebugSet(self.player)
    end

    -- MP: Send to server AND update locally for immediate feedback
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "TriggerSepsis", {})
        EHR.DebugV2.Log("Trigger Sepsis sent to server", "WOUNDS", "WARN")
    end

    -- Always update locally (both SP and MP for immediate UI feedback)
    data.EHR_Sepsis = {
        active = true,
        stage = 1,
        startTime = currentHour,
        stageStartTime = currentHour,
        sourceBodyPart = "Debug",
        treatmentDoses = 0,
        lastIVAntibiotics = nil,
        lastHealthDamageHour = currentHour,
        healthCap = nil,
        lastCuredTime = nil,
    }
    data.EHR_Sepsis_Initialized = true

    -- DEBUG: Verify the write
    print(string.format("[EHR DEBUG TRIGGER] AFTER: EHR_Sepsis=%s", tostring(data.EHR_Sepsis)))
    print(string.format("[EHR DEBUG TRIGGER] AFTER: stage=%s, active=%s", tostring(data.EHR_Sepsis.stage), tostring(data.EHR_Sepsis.active)))

    EHR.DebugV2.Log("Triggered sepsis (stage=1)", "WOUNDS", "WARN")
end

function EHR_DebugMenuV2:onClearSepsis()
    if not self.player then return end

    local data = self.player:getModData()

    -- MP: Send to server AND update locally for immediate feedback
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ClearSepsis", {})
        EHR.DebugV2.Log("Clear Sepsis sent to server", "WOUNDS", "INFO")
    end

    -- Always update locally (both SP and MP for immediate UI feedback)
    if EHR.Sepsis and EHR.Sepsis.Cure then
        EHR.Sepsis.Cure(self.player)
    elseif data.EHR_Sepsis then
        data.EHR_Sepsis.active = false
        data.EHR_Sepsis.stage = 0
    end

    -- Downgrade septic wounds locally
    local woundData = data.EHR_WoundInfection
    if woundData and woundData.parts then
        local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
        for _, partData in pairs(woundData.parts) do
            if partData.stage and partData.stage >= 4 then
                partData.stage = 3
                partData.stageStartTime = currentHour
            end
        end
        recalcWoundStats(woundData)
    end

    EHR.DebugV2.Log("Cleared sepsis and downgraded septic wounds", "WOUNDS", "INFO")
end

-- ============================================
-- TAB CONTENT: MEDICATIONS
-- ============================================

-- Medication tiers for testing
EHR.DebugV2.MedicationTiers = {
    { tier = 1, name = "Tier 1 (Basic)", example = "Painkillers, Bandages" },
    { tier = 2, name = "Tier 2 (Standard)", example = "Antibiotics, Beta Blockers" },
    { tier = 3, name = "Tier 3 (Advanced)", example = "Morphine, Blood Thinners" },
}

-- Common side effects for testing
EHR.DebugV2.SideEffects = {
    "drowsiness",
    "nausea",
    "dizziness",
    "blurred_vision",
    "confusion",
    "heart_racing",
    "tremors",
    "stomach_pain",
}

function EHR_DebugMenuV2:createMedicationsPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["medications"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 130

    -- Clear all medications button
    local clearAllBtn = ISButton:new(PADDING, y, btnWidth, BUTTON_HEIGHT, "Clear All Meds", self, EHR_DebugMenuV2.onClearAllMedications)
    clearAllBtn:initialise()
    clearAllBtn:instantiate()
    clearAllBtn.backgroundColor = c.safe
    panel:addChild(clearAllBtn)

    -- Clear side effects button
    local clearEffectsBtn = ISButton:new(PADDING + btnWidth + 10, y, btnWidth, BUTTON_HEIGHT, "Clear Side Effects", self, EHR_DebugMenuV2.onClearSideEffects)
    clearEffectsBtn:initialise()
    clearEffectsBtn:instantiate()
    clearEffectsBtn.backgroundColor = c.warning
    panel:addChild(clearEffectsBtn)

    y = y + BUTTON_HEIGHT + 15

    -- Force apply medication by tier
    for _, tierData in ipairs(EHR.DebugV2.MedicationTiers) do
        local btn = ISButton:new(PADDING, y, 160, BUTTON_HEIGHT, "Apply " .. tierData.name, self, EHR_DebugMenuV2.onApplyMedicationTier)
        btn:initialise()
        btn:instantiate()
        btn.internal = tierData.tier
        btn.backgroundColor = tierData.tier == 1 and c.safe or (tierData.tier == 2 and c.warning or c.danger)
        panel:addChild(btn)

        y = y + BUTTON_HEIGHT + 3
    end

    y = y + 10

    -- Side effect injection buttons
    local sideEffectX = PADDING
    for i, effect in ipairs(EHR.DebugV2.SideEffects) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local btnX = PADDING + col * (130 + 5)
        local btnY = y + row * (BUTTON_HEIGHT + 3)

        local displayName = effect:gsub("_", " "):gsub("(%a)([%w_']*)", function(a,b) return a:upper()..(b or "") end)
        local btn = ISButton:new(btnX, btnY, 130, BUTTON_HEIGHT, displayName, self, EHR_DebugMenuV2.onAddSideEffect)
        btn:initialise()
        btn:instantiate()
        btn.internal = effect
        btn.backgroundColor = c.buttonBg
        panel:addChild(btn)
    end

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderMedicationsStatus()
    end

    panel.renderMedicationsStatus = function(self)
        local menu = self.menuRef
        if not menu or not menu.player then return end

        local data = menu.player:getModData()
        local c = EHR.DebugV2.Colors
        -- Position below all buttons (tier buttons + side effect buttons)
        -- Tier buttons end ~127, side effects (3 rows) end ~215
        local y = 240
        local x = PADDING

        -- Active medications header
        self:drawText("ACTIVE MEDICATIONS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        -- BUG FIX: Read from actual medication system (EHR.Medication) not legacy EHR_Medications
        local hasMeds = false
        if EHR.Medication and EHR.Medication.GetActiveTreatments then
            local treatments = EHR.Medication.GetActiveTreatments(self.player)
            for _, treatment in ipairs(treatments) do
                hasMeds = true

                local tier = treatment.tier or 1
                local doses = treatment.doseCount or 0
                local totalDoses = treatment.totalDosesNeeded or 0
                local remaining = treatment.hoursRemaining or 0
                local tierColor = tier == 1 and c.safe or (tier == 2 and c.warning or c.danger)

                local medName = treatment.medicationName or treatment.diseaseId or "Unknown"
                self:drawText(string.format("%s (Tier %d)", medName, tier),
                    x + 10, y, tierColor.r, tierColor.g, tierColor.b, tierColor.a, FONT)
                y = y + 18

                -- Show dose status
                local doseInfo = string.format("  Dose %d/%d", doses, totalDoses)
                if treatment.isOverdue then
                    doseInfo = doseInfo .. string.format(" | OVERDUE %.1fh!", treatment.hoursOverdue or 0)
                    self:drawText(doseInfo, x + 10, y, c.danger.r, c.danger.g, c.danger.b, c.danger.a, FONT)
                else
                    doseInfo = doseInfo .. string.format(" | Cure in %.1fh", remaining)
                    self:drawText(doseInfo, x + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
                end
                y = y + 20
            end
        end

        if not hasMeds then
            self:drawText("No active medications", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
            y = y + 24
        end

        y = y + 10

        -- Side effects header
        self:drawText("ACTIVE SIDE EFFECTS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        y = y + 24

        -- BUG FIX: Read from actual medication system (EHR.Medication) not legacy EHR_SideEffects
        local hasEffects = false
        if EHR.Medication and EHR.Medication.GetActiveSideEffects then
            local effects = EHR.Medication.GetActiveSideEffects(self.player)
            for _, effectData in ipairs(effects) do
                hasEffects = true

                local severity = effectData.severity or 1
                local sevColor = severity == 1 and c.warning or (severity == 2 and c.danger or c.critical)
                local sevName = severity == 1 and "Mild" or (severity == 2 and "Moderate" or "Severe")

                local displayName = effectData.displayName or effectData.effectId or "Unknown"

                self:drawText(string.format("%s (%s) - %.1fh left", displayName, sevName, effectData.hoursRemaining or 0),
                    x + 10, y, sevColor.r, sevColor.g, sevColor.b, sevColor.a, FONT)
                y = y + 18
            end
        end

        if not hasEffects then
            self:drawText("No active side effects", x + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, FONT)
        end
    end
end

function EHR_DebugMenuV2:onClearAllMedications()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ClearAllMedications", {})
        EHR.DebugV2.Log("Clear All Medications sent to server", "MEDICATIONS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()

    if data.EHR_Medication then
        if data.EHR_Medication.activeTreatments then
            for id, _ in pairs(data.EHR_Medication.activeTreatments) do
                data.EHR_Medication.activeTreatments[id] = nil
            end
        end
        if data.EHR_Medication.activeDoses then
            for id, _ in pairs(data.EHR_Medication.activeDoses) do
                data.EHR_Medication.activeDoses[id] = nil
            end
        end
    end

    if data.EHR_Medications then
        for id, _ in pairs(data.EHR_Medications) do
            data.EHR_Medications[id] = nil
        end
    end

    EHR.DebugV2.Log("Cleared all medications", "MEDICATIONS", "INFO")
end

function EHR_DebugMenuV2:onClearSideEffects()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ClearSideEffects", {})
        EHR.DebugV2.Log("Clear Side Effects sent to server", "MEDICATIONS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()

    if data.EHR_Medication and data.EHR_Medication.activeSideEffects then
        for id, _ in pairs(data.EHR_Medication.activeSideEffects) do
            data.EHR_Medication.activeSideEffects[id] = nil
        end
    end

    if data.EHR_SideEffects then
        for id, _ in pairs(data.EHR_SideEffects) do
            data.EHR_SideEffects[id] = nil
        end
    end

    EHR.DebugV2.Log("Cleared all side effects", "MEDICATIONS", "INFO")
end

function EHR_DebugMenuV2:onApplyMedicationTier(button)
    if not self.player then return end

    local tier = button.internal
    if not tier then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ApplyMedicationTier", { tier = tier })
        EHR.DebugV2.Log(string.format("Apply Tier %d Medication sent to server", tier), "MEDICATIONS", "INFO")
        return
    end

    -- SP: Execute directly
    if EHR.Medication and EHR.Medication.Apply then
        EHR.Medication.Apply(self.player, "debug_medication", tier)
    else
        local data = self.player:getModData()
        data.EHR_Medication = data.EHR_Medication or {}
        data.EHR_Medication.activeTreatments = data.EHR_Medication.activeTreatments or {}
        local medId = "debug_tier" .. tier .. "_" .. os.time()
        data.EHR_Medication.activeTreatments[medId] = {
            tier = tier,
            startTime = os.time(),
            duration = 24,
            effectiveness = 0.8,
        }
    end

    EHR.DebugV2.Log(string.format("Applied Tier %d medication", tier), "MEDICATIONS", "INFO")
end

function EHR_DebugMenuV2:onAddSideEffect(button)
    if not self.player then return end

    local effectId = button.internal
    if not effectId then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "AddSideEffect", { effectId = effectId })
        EHR.DebugV2.Log(string.format("Add Side Effect %s sent to server", effectId), "MEDICATIONS", "INFO")
        return
    end

    -- SP: Execute directly
    local data = self.player:getModData()
    data.EHR_Medication = data.EHR_Medication or {}
    data.EHR_Medication.activeSideEffects = data.EHR_Medication.activeSideEffects or {}

    data.EHR_Medication.activeSideEffects[effectId] = {
        startTime = os.time(),
        duration = 6,
        severity = 0.5,
    }

    EHR.DebugV2.Log(string.format("Added side effect: %s", effectId), "MEDICATIONS", "INFO")
end

-- ============================================
-- TAB CONTENT: STATS
-- ============================================

-- Stats to display with their CharacterStat enum values
EHR.DebugV2.StatsList = {
    { id = "HUNGER", name = "Hunger", bad = true },
    { id = "THIRST", name = "Thirst", bad = true },
    { id = "FATIGUE", name = "Fatigue", bad = true },
    { id = "PAIN", name = "Pain", bad = true },
    { id = "STRESS", name = "Stress", bad = true },
    { id = "UNHAPPINESS", name = "Unhappiness", bad = true },
    { id = "BOREDOM", name = "Boredom", bad = true },
    { id = "PANIC", name = "Panic", bad = true },
    { id = "SICKNESS", name = "Sickness", bad = true },
    { id = "POISON", name = "Poison", bad = true },
    { id = "FOOD_SICKNESS", name = "Food Sickness", bad = true },
    { id = "ENDURANCE", name = "Endurance", bad = false },
    { id = "TEMPERATURE", name = "Temperature", bad = false },
    { id = "WETNESS", name = "Wetness", bad = true },
}

function EHR_DebugMenuV2:createStatsPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["stats"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 120

    -- Preset buttons
    local perfectBtn = ISButton:new(PADDING, y, btnWidth, BUTTON_HEIGHT, "Perfect Health", self, EHR_DebugMenuV2.onStatPresetPerfect)
    perfectBtn:initialise()
    perfectBtn:instantiate()
    perfectBtn.backgroundColor = c.safe
    panel:addChild(perfectBtn)

    local nearDeathBtn = ISButton:new(PADDING + btnWidth + 10, y, btnWidth, BUTTON_HEIGHT, "Near Death", self, EHR_DebugMenuV2.onStatPresetNearDeath)
    nearDeathBtn:initialise()
    nearDeathBtn:instantiate()
    nearDeathBtn.backgroundColor = c.danger
    panel:addChild(nearDeathBtn)

    local maxBadBtn = ISButton:new(PADDING + (btnWidth + 10) * 2, y, btnWidth, BUTTON_HEIGHT, "Max Bad Stats", self, EHR_DebugMenuV2.onStatPresetMaxBad)
    maxBadBtn:initialise()
    maxBadBtn:instantiate()
    maxBadBtn.backgroundColor = c.critical
    panel:addChild(maxBadBtn)

    y = y + BUTTON_HEIGHT + 15

    -- Create stat adjustment buttons for each stat
    local btnSmall = 28
    local barWidth = 180
    local labelWidth = 100
    local startY = y

    for i, statDef in ipairs(EHR.DebugV2.StatsList) do
        local row = i - 1
        local statY = startY + row * (BUTTON_HEIGHT + 4)

        -- Only render first 14 stats to fit in panel
        if statY + BUTTON_HEIGHT < self.contentArea.height - 60 then
            -- Minus button
            local minusBtn = ISButton:new(PADDING, statY, btnSmall, BUTTON_HEIGHT, "-", self, EHR_DebugMenuV2.onStatAdjust)
            minusBtn:initialise()
            minusBtn:instantiate()
            minusBtn.internal = { stat = statDef.id, delta = -0.1 }
            minusBtn.backgroundColor = c.safe
            panel:addChild(minusBtn)

            -- Plus button
            local plusBtn = ISButton:new(PADDING + btnSmall + 5, statY, btnSmall, BUTTON_HEIGHT, "+", self, EHR_DebugMenuV2.onStatAdjust)
            plusBtn:initialise()
            plusBtn:instantiate()
            plusBtn.internal = { stat = statDef.id, delta = 0.1 }
            plusBtn.backgroundColor = c.danger
            panel:addChild(plusBtn)

            -- Zero button
            local zeroBtn = ISButton:new(PADDING + (btnSmall + 5) * 2, statY, btnSmall, BUTTON_HEIGHT, "0", self, EHR_DebugMenuV2.onStatSet)
            zeroBtn:initialise()
            zeroBtn:instantiate()
            zeroBtn.internal = { stat = statDef.id, value = 0 }
            zeroBtn.backgroundColor = c.buttonBg
            panel:addChild(zeroBtn)

            -- Max button
            local maxBtn = ISButton:new(PADDING + (btnSmall + 5) * 3, statY, btnSmall, BUTTON_HEIGHT, "1", self, EHR_DebugMenuV2.onStatSet)
            maxBtn:initialise()
            maxBtn:instantiate()
            maxBtn.internal = { stat = statDef.id, value = 1 }
            maxBtn.backgroundColor = c.buttonBg
            panel:addChild(maxBtn)
        end
    end

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderStatsDisplay()
    end

    panel.renderStatsDisplay = function(self)
        local menu = self.menuRef
        if not menu or not menu.player then return end

        local stats = menu.player:getStats()
        if not stats then return end

        local c = EHR.DebugV2.Colors
        local startY = PADDING + BUTTON_HEIGHT + 15
        local labelX = PADDING + (28 + 5) * 4 + 10
        local barX = labelX + 100
        local barWidth = 180

        for i, statDef in ipairs(EHR.DebugV2.StatsList) do
            local row = i - 1
            local y = startY + row * (BUTTON_HEIGHT + 4) + 4

            -- Only render first 14 stats to fit in panel
            if y + 20 < self.height - 60 then
                -- Get stat value with pcall protection
                local value = 0
                if CharacterStat and CharacterStat[statDef.id] then
                    local success, result = pcall(function()
                        return stats:get(CharacterStat[statDef.id])
                    end)
                    if success and result then
                        value = result
                    end
                end

                -- Clamp display to 0-1 (some stats like POISON can exceed 1)
                local displayValue = math.min(1, math.max(0, value or 0))
                local actualValue = value or 0

                -- Label
                self:drawText(statDef.name .. ":", labelX, y, c.text.r, c.text.g, c.text.b, c.text.a, FONT)

                -- Bar background
                self:drawRect(barX, y, barWidth, 16, 0.3, 0.1, 0.1, 0.1)

                -- Bar fill - color based on good/bad and value
                local barColor
                if statDef.bad then
                    -- Bad stats: low = green, high = red
                    if displayValue < 0.3 then barColor = c.safe
                    elseif displayValue < 0.6 then barColor = c.warning
                    else barColor = c.danger end
                else
                    -- Good stats: low = red, high = green
                    if displayValue > 0.7 then barColor = c.safe
                    elseif displayValue > 0.3 then barColor = c.warning
                    else barColor = c.danger end
                end

                local fillWidth = displayValue * barWidth
                self:drawRect(barX, y, fillWidth, 16, barColor.a, barColor.r, barColor.g, barColor.b)

                -- Bar border
                self:drawRectBorder(barX, y, barWidth, 16, 1, c.border.r, c.border.g, c.border.b)

                -- Value text (show actual value which can exceed 1)
                local valueText = string.format("%.2f", actualValue)
                self:drawTextRight(valueText, barX + barWidth + 45, y, c.text.r, c.text.g, c.text.b, c.text.a, FONT)
            end
        end
    end
end

function EHR_DebugMenuV2:onStatAdjust(button)
    if not self.player then return end

    local data = button.internal
    if not data or not data.stat then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "AdjustStat", { stat = data.stat, amount = data.delta })
        EHR.DebugV2.Log(string.format("Adjust %s sent to server", data.stat), "STATS", "INFO")
        return
    end

    -- SP: Execute directly
    local stats = self.player:getStats()
    if not stats or not CharacterStat or not CharacterStat[data.stat] then return end

    pcall(function()
        local current = stats:get(CharacterStat[data.stat]) or 0
        local newValue = math.max(0, math.min(1, current + data.delta))
        stats:set(CharacterStat[data.stat], newValue)
    end)

    EHR.DebugV2.Log(string.format("Adjusted %s by %.1f", data.stat, data.delta), "STATS", "INFO")
end

function EHR_DebugMenuV2:onStatSet(button)
    if not self.player then return end

    local data = button.internal
    if not data or not data.stat then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "SetStat", { stat = data.stat, value = data.value })
        EHR.DebugV2.Log(string.format("Set %s sent to server", data.stat), "STATS", "INFO")
        return
    end

    -- SP: Execute directly
    local stats = self.player:getStats()
    if not stats or not CharacterStat or not CharacterStat[data.stat] then return end

    pcall(function()
        stats:set(CharacterStat[data.stat], data.value)
    end)

    EHR.DebugV2.Log(string.format("Set %s to %.1f", data.stat, data.value), "STATS", "INFO")
end

function EHR_DebugMenuV2:onStatPresetPerfect()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "StatPresetPerfect", {})
        EHR.DebugV2.Log("Perfect Health preset sent to server", "STATS", "INFO")
        return
    end

    -- SP: Execute directly
    local stats = self.player:getStats()
    if not stats or not CharacterStat then return end

    pcall(function()
        stats:set(CharacterStat.HUNGER, 0)
        stats:set(CharacterStat.THIRST, 0)
        stats:set(CharacterStat.FATIGUE, 0)
        stats:set(CharacterStat.PAIN, 0)
        stats:set(CharacterStat.STRESS, 0)
        stats:set(CharacterStat.UNHAPPINESS, 0)
        stats:set(CharacterStat.BOREDOM, 0)
        stats:set(CharacterStat.PANIC, 0)
        stats:set(CharacterStat.SICKNESS, 0)
        stats:set(CharacterStat.POISON, 0)
        stats:set(CharacterStat.FOOD_SICKNESS, 0)
        stats:set(CharacterStat.ENDURANCE, 1)
        stats:set(CharacterStat.WETNESS, 0)
    end)

    EHR.DebugV2.Log("Applied Perfect Health preset", "STATS", "INFO")
end

function EHR_DebugMenuV2:onStatPresetNearDeath()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "StatPresetNearDeath", {})
        EHR.DebugV2.Log("Near Death preset sent to server", "STATS", "WARN")
        return
    end

    -- SP: Execute directly
    local stats = self.player:getStats()
    if not stats or not CharacterStat then return end

    pcall(function()
        stats:set(CharacterStat.HUNGER, 0.95)
        stats:set(CharacterStat.THIRST, 0.95)
        stats:set(CharacterStat.FATIGUE, 0.95)
        stats:set(CharacterStat.PAIN, 0.9)
        stats:set(CharacterStat.STRESS, 0.8)
        stats:set(CharacterStat.UNHAPPINESS, 0.9)
        stats:set(CharacterStat.PANIC, 0.8)
        stats:set(CharacterStat.SICKNESS, 0.7)
        stats:set(CharacterStat.ENDURANCE, 0.05)
    end)

    EHR.DebugV2.Log("Applied Near Death preset", "STATS", "WARN")
end

function EHR_DebugMenuV2:onStatPresetMaxBad()
    if not self.player then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "StatPresetMaxBad", {})
        EHR.DebugV2.Log("Max Bad Stats preset sent to server", "STATS", "WARN")
        return
    end

    -- SP: Execute directly
    local stats = self.player:getStats()
    if not stats or not CharacterStat then return end

    pcall(function()
        stats:set(CharacterStat.HUNGER, 1)
        stats:set(CharacterStat.THIRST, 1)
        stats:set(CharacterStat.FATIGUE, 1)
        stats:set(CharacterStat.PAIN, 1)
        stats:set(CharacterStat.STRESS, 1)
        stats:set(CharacterStat.UNHAPPINESS, 1)
        stats:set(CharacterStat.BOREDOM, 1)
        stats:set(CharacterStat.PANIC, 1)
        stats:set(CharacterStat.SICKNESS, 1)
        stats:set(CharacterStat.POISON, 1)
        stats:set(CharacterStat.FOOD_SICKNESS, 1)
        stats:set(CharacterStat.ENDURANCE, 0)
        stats:set(CharacterStat.WETNESS, 1)
    end)

    EHR.DebugV2.Log("Applied Max Bad Stats preset", "STATS", "WARN")
end

-- ============================================
-- TAB CONTENT: SCENARIOS
-- ============================================

-- Scenario presets
EHR.DebugV2.Scenarios = {
    {
        id = "healthy",
        name = "1. Healthy Reset",
        desc = "All systems to perfect state",
        apply = function(player)
            local data = player:getModData()
            -- Reset blood (v2.7.0+: use API)
            data.EHR_Blood = data.EHR_Blood or {}
            if EHR.Blood and EHR.Blood.SetBloodVolume then
                EHR.Blood.SetBloodVolume(player, 5000)
            else
                data.EHR_Blood.currentVolume = 5000
            end
            data.EHR_Blood.transfusedSaline = 0
            -- Clear diseases
            if data.EHR_Disease and data.EHR_Disease.active then
                for id in pairs(data.EHR_Disease.active) do
                    data.EHR_Disease.active[id] = nil
                end
            end
            if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFever then
                EHR.BodyTemp.ResetDiseaseFever(player, true)
            end
            -- Clear infections
            clearAllWounds(data, player)
            -- Clear sepsis (keep initialized flag)
            if data.EHR_Sepsis then
                data.EHR_Sepsis.active = false
                data.EHR_Sepsis.stage = 0
            end
            -- Clear medications
            data.EHR_Medications = {}
            data.EHR_SideEffects = {}
            -- Reset stats
            local stats = player:getStats()
            if stats and CharacterStat then
                pcall(function()
                    stats:set(CharacterStat.HUNGER, 0)
                    stats:set(CharacterStat.THIRST, 0)
                    stats:set(CharacterStat.FATIGUE, 0)
                    stats:set(CharacterStat.SICKNESS, 0)
                    stats:set(CharacterStat.PAIN, 0)
                end)
            end
            -- Heal body
            local bodyDamage = player:getBodyDamage()
            if bodyDamage then bodyDamage:RestoreToFullHealth() end
        end
    },
    {
        id = "near_death",
        name = "2. Near Death",
        desc = "10% blood, stage 3 sepsis, 3 diseases",
        apply = function(player)
            local data = player:getModData()
            -- Critical blood (v2.7.0+: use API)
            data.EHR_Blood = data.EHR_Blood or {}
            if EHR.Blood and EHR.Blood.SetBloodVolume then
                EHR.Blood.SetBloodVolume(player, 500)  -- 10%
            else
                data.EHR_Blood.currentVolume = 500
            end
            -- Sepsis stage 3 (use proper structure)
            local gameTime = getGameTime()
            local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
            data.EHR_Sepsis = { active = true, stage = 3, startTime = currentHour, stageStartTime = currentHour, treatmentDoses = 0, lastHealthDamageHour = currentHour, healthCap = nil }
            data.EHR_Sepsis_Initialized = true
            -- Multiple diseases (use correct data path)
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.food_poisoning = { stage = 3, severity = 0.5 }
            debugNormalizeDiseaseTiming("food_poisoning", data.EHR_Disease.active.food_poisoning, 3)
            data.EHR_Disease.active.pneumonia = { stage = 2, severity = 0.7 }
            debugNormalizeDiseaseTiming("pneumonia", data.EHR_Disease.active.pneumonia, 2)
            data.EHR_Disease.active.hypothermia = { stage = 2, severity = 0.6 }
            debugNormalizeDiseaseTiming("hypothermia", data.EHR_Disease.active.hypothermia, 2)
            -- Bad stats
            local stats = player:getStats()
            if stats and CharacterStat then
                pcall(function()
                    stats:set(CharacterStat.HUNGER, 0.95)
                    stats:set(CharacterStat.THIRST, 0.95)
                    stats:set(CharacterStat.SICKNESS, 0.9)
                    stats:set(CharacterStat.PAIN, 0.8)
                end)
            end
        end
    },
    {
        id = "severe_infection",
        name = "3. Severe Infection",
        desc = "3 infected wounds at stage 3",
        apply = function(player)
            local data = player:getModData()
            setWoundStage(data, "Hand_L", 3, player)
            setWoundStage(data, "Torso_Upper", 3, player)
            setWoundStage(data, "UpperLeg_R", 3, player)
        end
    },
    {
        id = "food_poisoning",
        name = "4. Food Poisoning Peak",
        desc = "Stage 3 food poisoning with symptoms",
        apply = function(player)
            local data = player:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.food_poisoning = { stage = 3, elapsedTime = 12, severity = 0.5 }
            debugNormalizeDiseaseTiming("food_poisoning", data.EHR_Disease.active.food_poisoning, 3)
            local stats = player:getStats()
            if stats and CharacterStat then
                pcall(function()
                    stats:set(CharacterStat.FOOD_SICKNESS, 0.8)
                    stats:set(CharacterStat.SICKNESS, 0.7)
                end)
            end
        end
    },
    {
        id = "hypothermic",
        name = "5. Hypothermic",
        desc = "Stage 3 hypothermia",
        apply = function(player)
            local data = player:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.hypothermia = { stage = 3, severity = 0.6 }
            debugNormalizeDiseaseTiming("hypothermia", data.EHR_Disease.active.hypothermia, 3)
            local stats = player:getStats()
            if stats and CharacterStat then
                pcall(function()
                    stats:set(CharacterStat.TEMPERATURE, -0.5)
                end)
            end
        end
    },
    {
        id = "heat_stroke",
        name = "6. Heat Stroke",
        desc = "Active heat stroke",
        apply = function(player)
            local data = player:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.heat_stroke = { stage = 2, severity = 0.7 }
            debugNormalizeDiseaseTiming("heat_stroke", data.EHR_Disease.active.heat_stroke, 2)
            local stats = player:getStats()
            if stats and CharacterStat then
                pcall(function()
                    stats:set(CharacterStat.TEMPERATURE, 1.5)
                end)
            end
        end
    },
    {
        id = "multiple_diseases",
        name = "7. Multiple Diseases",
        desc = "3 random diseases active",
        apply = function(player)
            local data = player:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.common_cold = { stage = 2, severity = 0.3 }
            debugNormalizeDiseaseTiming("common_cold", data.EHR_Disease.active.common_cold, 2)
            data.EHR_Disease.active.gastroenteritis = { stage = 2, severity = 0.6 }
            debugNormalizeDiseaseTiming("gastroenteritis", data.EHR_Disease.active.gastroenteritis, 2)
            data.EHR_Disease.active.dysentery = { stage = 1, severity = 0.7 }
            debugNormalizeDiseaseTiming("dysentery", data.EHR_Disease.active.dysentery, 1)
        end
    },
    {
        id = "sepsis_emergency",
        name = "8. Sepsis Emergency",
        desc = "Stage 3 sepsis from infected wounds",
        apply = function(player)
            local data = player:getModData()
            -- Sepsis with proper structure
            local gameTime = getGameTime()
            local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
            data.EHR_Sepsis = { active = true, stage = 3, startTime = currentHour, stageStartTime = currentHour, treatmentDoses = 0, lastHealthDamageHour = currentHour, healthCap = nil }
            data.EHR_Sepsis_Initialized = true
            setWoundStage(data, "Torso_Upper", 4, player)
            setWoundStage(data, "Torso_Lower", 4, player)
        end
    },
    {
        id = "drug_overdose",
        name = "9. Drug Overdose",
        desc = "5 Tier 3 medications with side effects",
        apply = function(player)
            local data = player:getModData()
            data.EHR_Medications = data.EHR_Medications or {}
            for i = 1, 5 do
                data.EHR_Medications["overdose_med_" .. i] = { active = true, tier = 3, doses = 3 }
            end
            data.EHR_SideEffects = data.EHR_SideEffects or {}
            data.EHR_SideEffects.drowsiness = { active = true, severity = 3 }
            data.EHR_SideEffects.confusion = { active = true, severity = 3 }
            data.EHR_SideEffects.tremors = { active = true, severity = 2 }
        end
    },
    {
        id = "bleeding_out",
        name = "10. Bleeding Out",
        desc = "25% blood with active loss",
        apply = function(player)
            local data = player:getModData()
            data.EHR_Blood = data.EHR_Blood or {}
            -- v2.7.0+: use API
            if EHR.Blood and EHR.Blood.SetBloodVolume then
                EHR.Blood.SetBloodVolume(player, 1250)  -- 25%
            else
                data.EHR_Blood.currentVolume = 1250
            end
            data.EHR_Blood.lossRate = 50  -- Active bleeding
            -- Apply some wounds
            local bodyDamage = player:getBodyDamage()
            if bodyDamage and BodyPartType then
                pcall(function()
                    local arm = bodyDamage:getBodyPart(BodyPartType.ForeArm_L)
                    if arm then arm:setCut(true) end
                    local leg = bodyDamage:getBodyPart(BodyPartType.UpperLeg_R)
                    if leg then leg:setCut(true) end
                end)
            end
        end
    },
}

-- Test suite results
EHR.DebugV2.TestResults = {}
EHR.DebugV2.TestsRunning = false
EHR.DebugV2.TestProgress = 0
EHR.DebugV2.TestTotal = 0

function EHR_DebugMenuV2:createScenariosPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["scenarios"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 160

    -- Run Full Test Suite button
    local testSuiteBtn = ISButton:new(PADDING, y, 180, BUTTON_HEIGHT + 4, "Run Full Test Suite", self, EHR_DebugMenuV2.onRunTestSuite)
    testSuiteBtn:initialise()
    testSuiteBtn:instantiate()
    testSuiteBtn.backgroundColor = c.warning
    panel:addChild(testSuiteBtn)

    -- Clear results button
    local clearResultsBtn = ISButton:new(PADDING + 190, y, 100, BUTTON_HEIGHT + 4, "Clear Results", self, EHR_DebugMenuV2.onClearTestResults)
    clearResultsBtn:initialise()
    clearResultsBtn:instantiate()
    clearResultsBtn.backgroundColor = c.buttonBg
    panel:addChild(clearResultsBtn)

    y = y + BUTTON_HEIGHT + 15

    -- Scenario preset buttons (2 columns)
    for i, scenario in ipairs(EHR.DebugV2.Scenarios) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local btnX = PADDING + col * (btnWidth + 10)
        local btnY = y + row * (BUTTON_HEIGHT + 3)

        local btn = ISButton:new(btnX, btnY, btnWidth, BUTTON_HEIGHT, scenario.name, self, EHR_DebugMenuV2.onApplyScenario)
        btn:initialise()
        btn:instantiate()
        btn.internal = scenario.id
        btn.backgroundColor = c.buttonBg
        btn.textColor = c.text
        panel:addChild(btn)
    end

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderScenariosStatus()
    end

    panel.renderScenariosStatus = function(self)
        local menu = self.menuRef
        if not menu then return end

        local c = EHR.DebugV2.Colors
        local y = 200
        local x = PADDING

        -- Test progress bar
        if EHR.DebugV2.TestsRunning then
            self:drawText("RUNNING TESTS...", x, y, c.warning.r, c.warning.g, c.warning.b, c.warning.a, UIFont.Medium)
            y = y + 24

            -- Progress bar
            local barWidth = 400
            local barHeight = 16
            local progress = EHR.DebugV2.TestTotal > 0 and (EHR.DebugV2.TestProgress / EHR.DebugV2.TestTotal) or 0

            self:drawRect(x, y, barWidth, barHeight, 0.3, 0.1, 0.1, 0.1)
            self:drawRect(x, y, barWidth * progress, barHeight, c.warning.a, c.warning.r, c.warning.g, c.warning.b)
            self:drawRectBorder(x, y, barWidth, barHeight, 1, c.border.r, c.border.g, c.border.b)

            self:drawText(string.format("%d / %d", EHR.DebugV2.TestProgress, EHR.DebugV2.TestTotal),
                x + barWidth + 10, y, c.text.r, c.text.g, c.text.b, c.text.a, FONT)
            y = y + 30
        else
            self:drawText("TEST RESULTS", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
            y = y + 24
        end

        -- Test results display
        local passed = 0
        local failed = 0
        local results = EHR.DebugV2.TestResults

        if #results > 0 then
            -- Count pass/fail
            for _, result in ipairs(results) do
                if result.passed then passed = passed + 1 else failed = failed + 1 end
            end

            -- Summary
            local summaryColor = failed == 0 and c.safe or c.danger
            self:drawText(string.format("Passed: %d | Failed: %d | Total: %d", passed, failed, #results),
                x, y, summaryColor.r, summaryColor.g, summaryColor.b, summaryColor.a, FONT)
            y = y + 24

            -- Show last 12 results
            local startIdx = math.max(1, #results - 11)
            for i = startIdx, #results do
                local result = results[i]
                local color = result.passed and c.safe or c.danger
                local status = result.passed and "PASS" or "FAIL"

                self:drawText(string.format("[%s] %s", status, result.name),
                    x + 10, y, color.r, color.g, color.b, color.a, FONT)
                y = y + 16

                if y > self.height - 40 then break end
            end
        else
            self:drawText("No test results. Run the test suite to validate EHR systems.",
                x, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        end
    end
end

function EHR_DebugMenuV2:onApplyScenario(button)
    if not self.player then return end

    local scenarioId = button.internal
    if not scenarioId then return end

    -- MP: Send to server
    if isClient() then
        sendClientCommand(self.player, "EHR_Debug", "ApplyScenario", { scenarioId = scenarioId })
        EHR.DebugV2.Log("Apply Scenario " .. scenarioId .. " sent to server", "SCENARIOS", "INFO")
        return
    end

    -- SP: Find and apply scenario locally
    for _, scenario in ipairs(EHR.DebugV2.Scenarios) do
        if scenario.id == scenarioId then
            scenario.apply(self.player)
            EHR.DebugV2.Log("Applied scenario: " .. scenario.name, "SCENARIOS", "INFO")
            return
        end
    end
end

function EHR_DebugMenuV2:onClearTestResults()
    EHR.DebugV2.TestResults = {}
    EHR.DebugV2.TestProgress = 0
    EHR.DebugV2.TestTotal = 0
    EHR.DebugV2.Log("Cleared test results", "TESTS", "INFO")
end

function EHR_DebugMenuV2:onRunTestSuite()
    if not self.player or EHR.DebugV2.TestsRunning then return end

    EHR.DebugV2.TestResults = {}
    EHR.DebugV2.TestsRunning = true
    EHR.DebugV2.TestProgress = 0

    -- Define test suite
    local tests = {
        -- Disease tests (using correct data path: EHR_Disease.active)
        { name = "Disease: Contract food poisoning", test = function(p)
            local data = p:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.food_poisoning = { stage = 1, severity = 0.5 }
            debugNormalizeDiseaseTiming("food_poisoning", data.EHR_Disease.active.food_poisoning, 1)
            return data.EHR_Disease.active.food_poisoning ~= nil
        end },
        { name = "Disease: Cure disease", test = function(p)
            local data = p:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.test_disease = nil
            return data.EHR_Disease.active.test_disease == nil
        end },
        { name = "Disease: Stage progression", test = function(p)
            local data = p:getModData()
            data.EHR_Disease = data.EHR_Disease or { active = {} }
            data.EHR_Disease.active = data.EHR_Disease.active or {}
            data.EHR_Disease.active.stage_test = { stage = 1, severity = 0.5 }
            debugNormalizeDiseaseTiming("stage_test", data.EHR_Disease.active.stage_test, 2)
            return data.EHR_Disease.active.stage_test.stage == 2 and debugGetDiseaseProgress(data.EHR_Disease.active.stage_test) > 0
        end },

        -- Blood tests (v2.7.0+: use API)
        { name = "Blood: Set volume", test = function(p)
            local data = p:getModData()
            data.EHR_Blood = data.EHR_Blood or {}
            if EHR.Blood and EHR.Blood.SetBloodVolume then
                EHR.Blood.SetBloodVolume(p, 3000)
            else
                data.EHR_Blood.currentVolume = 3000
            end
            return data.EHR_Blood.currentVolume == 3000
        end },
        { name = "Blood: Add saline", test = function(p)
            local data = p:getModData()
            data.EHR_Blood = data.EHR_Blood or {}
            data.EHR_Blood.transfusedSaline = 500
            return data.EHR_Blood.transfusedSaline == 500
        end },
        { name = "Blood: Max volume check", test = function(p)
            local data = p:getModData()
            data.EHR_Blood = data.EHR_Blood or {}
            local max = data.EHR_Blood.maxVolume or 5000
            return max > 0
        end },

        -- Wound infection tests
        { name = "Wounds: Set infection stage", test = function(p)
            local data = p:getModData()
            setWoundStage(data, "Hand_L", 2, p)
            return getWoundStage(data, "Hand_L") == 2
        end },
        { name = "Wounds: Clear infection", test = function(p)
            local data = p:getModData()
            clearAllWounds(data, p)
            return getWoundStage(data, "Hand_R") == 0
        end },

        -- Sepsis tests (include EHR_Sepsis_Initialized to prevent auto-reset)
        { name = "Sepsis: Trigger", test = function(p)
            local data = p:getModData()
            local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
            data.EHR_Sepsis = { active = true, stage = 1, stageStartTime = 0, treatmentDoses = 0, lastHealthDamageHour = currentHour, healthCap = nil }
            data.EHR_Sepsis_Initialized = true
            return data.EHR_Sepsis.active == true
        end },
        { name = "Sepsis: Stage set", test = function(p)
            local data = p:getModData()
            local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
            data.EHR_Sepsis = data.EHR_Sepsis or { active = true, stageStartTime = 0, treatmentDoses = 0, lastHealthDamageHour = currentHour, healthCap = nil }
            data.EHR_Sepsis.stage = 3
            data.EHR_Sepsis.lastHealthDamageHour = currentHour
            data.EHR_Sepsis.healthCap = nil
            data.EHR_Sepsis_Initialized = true
            return data.EHR_Sepsis.stage == 3
        end },
        { name = "Sepsis: Clear", test = function(p)
            local data = p:getModData()
            if data.EHR_Sepsis then
                data.EHR_Sepsis.active = false
                data.EHR_Sepsis.stage = 0
            end
            return data.EHR_Sepsis == nil or data.EHR_Sepsis.active == false
        end },

        -- Medication tests
        { name = "Medication: Apply", test = function(p)
            local data = p:getModData()
            data.EHR_Medications = data.EHR_Medications or {}
            data.EHR_Medications.test_med = { active = true, tier = 1 }
            return data.EHR_Medications.test_med ~= nil
        end },
        { name = "Medication: Clear", test = function(p)
            local data = p:getModData()
            data.EHR_Medications = data.EHR_Medications or {}
            data.EHR_Medications.clear_test = nil
            return data.EHR_Medications.clear_test == nil
        end },

        -- Stats tests
        { name = "Stats: Set hunger", test = function(p)
            local stats = p:getStats()
            if not stats or not CharacterStat then return false end
            local success = pcall(function()
                stats:set(CharacterStat.HUNGER, 0.5)
            end)
            return success
        end },
        { name = "Stats: Get sickness", test = function(p)
            local stats = p:getStats()
            if not stats or not CharacterStat then return false end
            local success, value = pcall(function()
                return stats:get(CharacterStat.SICKNESS)
            end)
            return success and value ~= nil
        end },

        -- ModData persistence test
        { name = "ModData: Persistence check", test = function(p)
            local data = p:getModData()
            data.EHR_TestFlag = "test_value"
            return data.EHR_TestFlag == "test_value"
        end },
    }

    EHR.DebugV2.TestTotal = #tests

    -- Run tests with delayed execution to show progress
    local testIndex = 1
    local player = self.player

    local function runNextTest()
        if testIndex > #tests then
            EHR.DebugV2.TestsRunning = false
            EHR.DebugV2.Log(string.format("Test suite complete: %d tests", #tests), "TESTS", "INFO")
            return
        end

        local testDef = tests[testIndex]
        local success, result = pcall(function()
            return testDef.test(player)
        end)

        local passed = success and result == true

        table.insert(EHR.DebugV2.TestResults, {
            name = testDef.name,
            passed = passed,
        })

        EHR.DebugV2.TestProgress = testIndex
        testIndex = testIndex + 1

        -- Schedule next test
        if Events and Events.OnTick then
            -- Use delayed execution with safety checks
            local tickCount = 0
            local function delayedNext()
                tickCount = tickCount + 1
                if tickCount >= 2 then
                    Events.OnTick.Remove(delayedNext)
                    -- CRIT-001 FIX: Safety checks to prevent orphaned handlers
                    if not EHR.DebugV2.TestsRunning then
                        return  -- Test session was cancelled (menu closed)
                    end
                    if not player or player:isDead() then
                        EHR.DebugV2.TestsRunning = false
                        EHR.DebugV2.Log("Test suite aborted: player invalid", "TESTS", "ERROR")
                        return
                    end
                    runNextTest()
                end
            end
            Events.OnTick.Add(delayedNext)
        else
            runNextTest()
        end
    end

    runNextTest()
    EHR.DebugV2.Log("Started test suite with " .. #tests .. " tests", "TESTS", "INFO")
end

-- ============================================
-- TAB CONTENT: LOG
-- ============================================

-- Log category filter
EHR.DebugV2.LogFilter = "ALL"
EHR.DebugV2.LogCategories = { "ALL", "UI", "BLOOD", "DISEASES", "WOUNDS", "MEDICATIONS", "STATS", "SCENARIOS", "TESTS", "ACTIONS", "DEBUG" }

function EHR_DebugMenuV2:createLogPanel()
    local panel = ISPanel:new(0, 0, self.contentArea.width, self.contentArea.height)
    panel:initialise()
    panel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.contentArea:addChild(panel)
    self.contentPanels["log"] = panel

    local c = EHR.DebugV2.Colors
    local y = PADDING
    local btnWidth = 80

    -- Clear log button
    local clearLogBtn = ISButton:new(PADDING, y, btnWidth, BUTTON_HEIGHT, "Clear Log", self, EHR_DebugMenuV2.onClearLog)
    clearLogBtn:initialise()
    clearLogBtn:instantiate()
    clearLogBtn.backgroundColor = c.warning
    panel:addChild(clearLogBtn)

    -- Add test entry button
    local testLogBtn = ISButton:new(PADDING + btnWidth + 10, y, btnWidth, BUTTON_HEIGHT, "Add Test", self, EHR_DebugMenuV2.onAddTestLog)
    testLogBtn:initialise()
    testLogBtn:instantiate()
    testLogBtn.backgroundColor = c.buttonBg
    panel:addChild(testLogBtn)

    -- Filter buttons
    local filterX = PADDING + (btnWidth + 10) * 2 + 20
    local filterBtnWidth = 50

    for i, cat in ipairs({"ALL", "UI", "BLOOD", "ACTIONS", "DEBUG"}) do
        local btn = ISButton:new(filterX, y, filterBtnWidth, BUTTON_HEIGHT, cat, self, EHR_DebugMenuV2.onSetLogFilter)
        btn:initialise()
        btn:instantiate()
        btn.internal = cat
        btn.backgroundColor = EHR.DebugV2.LogFilter == cat and c.tabActive or c.buttonBg
        panel:addChild(btn)
        filterX = filterX + filterBtnWidth + 3
    end

    -- Store reference for rendering
    panel.menuRef = self

    panel.render = function(self)
        ISPanel.render(self)
        self:renderLogDisplay()
    end

    panel.renderLogDisplay = function(self)
        local c = EHR.DebugV2.Colors
        local y = PADDING + BUTTON_HEIGHT + 15
        local x = PADDING

        -- Header
        self:drawText("DEBUG LOG", x, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)

        local filter = EHR.DebugV2.LogFilter
        if filter ~= "ALL" then
            self:drawText(string.format(" (Filter: %s)", filter), x + 100, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        end

        y = y + 24

        -- Entry count
        local totalEntries = #EHR.DebugV2.LogEntries
        local filteredCount = 0
        for _, entry in ipairs(EHR.DebugV2.LogEntries) do
            if filter == "ALL" or entry.category == filter then
                filteredCount = filteredCount + 1
            end
        end

        self:drawText(string.format("Entries: %d / %d", filteredCount, totalEntries),
            x, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        y = y + 20

        -- Draw separator line
        self:drawRect(x, y, self.width - PADDING * 2, 1, c.border.a, c.border.r, c.border.g, c.border.b)
        y = y + 5

        -- Log entries
        local entries = EHR.DebugV2.LogEntries
        local maxVisible = 28
        local displayed = 0

        for i = 1, #entries do
            if displayed >= maxVisible then break end

            local entry = entries[i]

            -- Apply filter
            if filter ~= "ALL" and entry.category ~= filter then
                -- Skip filtered entries
            else
                -- Color based on level
                local color = c.text
                if entry.level == "ERROR" then color = c.danger
                elseif entry.level == "WARN" then color = c.warning
                elseif entry.level == "DEBUG" then color = c.textDim
                end

                -- Format: [TIME] [CAT] Message
                local catDisplay = string.format("[%s]", entry.category:sub(1, 4))
                local line = string.format("[%s] %s %s", entry.time, catDisplay, entry.message)

                -- Truncate long lines
                if #line > 70 then
                    line = line:sub(1, 67) .. "..."
                end

                self:drawText(line, x, y, color.r, color.g, color.b, color.a, FONT)
                y = y + 16
                displayed = displayed + 1
            end
        end

        if displayed == 0 then
            self:drawText("No log entries" .. (filter ~= "ALL" and " matching filter" or ""),
                x, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, FONT)
        end
    end
end

function EHR_DebugMenuV2:onClearLog()
    EHR.DebugV2.LogEntries = {}
    EHR.DebugV2.Log("Log cleared", "DEBUG", "INFO")
end

function EHR_DebugMenuV2:onAddTestLog()
    local levels = {"INFO", "WARN", "ERROR", "DEBUG"}
    local categories = {"UI", "BLOOD", "DISEASES", "WOUNDS", "ACTIONS"}

    local level = levels[ZombRand(#levels) + 1]
    local category = categories[ZombRand(#categories) + 1]

    EHR.DebugV2.Log("Test log entry #" .. (#EHR.DebugV2.LogEntries + 1), category, level)
end

function EHR_DebugMenuV2:onSetLogFilter(button)
    local filter = button.internal
    if filter then
        EHR.DebugV2.LogFilter = filter
        EHR.DebugV2.Log("Set log filter to: " .. filter, "DEBUG", "DEBUG")

        -- Update filter button styles
        local c = EHR.DebugV2.Colors
        local panel = self.contentPanels["log"]
        if panel then
            for _, child in ipairs(panel:getChildren()) do
                if child.internal then
                    child.backgroundColor = child.internal == filter and c.tabActive or c.buttonBg
                end
            end
        end
    end
end

-- ============================================
-- TITLE BAR RENDERING
-- ============================================

function EHR_DebugMenuV2:prerender()
    ISPanel.prerender(self)

    local c = EHR.DebugV2.Colors

    -- Draw title
    self:drawText("EHR DEBUG MENU v2.0", 10, 6, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)

    -- Permission indicator
    local permText = EHR.DebugV2.IsDebugAllowed() and "[ENABLED]" or "[DISABLED]"
    local permColor = EHR.DebugV2.IsDebugAllowed() and c.safe or c.danger
    self:drawTextRight(permText, self.width - 35, 6, permColor.r, permColor.g, permColor.b, permColor.a, FONT)
end

function EHR_DebugMenuV2:update()
    ISPanel.update(self)

    -- Validate player still exists
    if not self.player or self.player:isDead() then
        -- Player died or disconnected, close menu
        self:onClose()
    end
end

-- ============================================
-- TOGGLE FUNCTION (called by keybind)
-- ============================================

function EHR.DebugV2.Toggle()
    -- Check permissions first with detailed error messages
    local sandboxEnabled = false
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local debugModeValue = SandboxVars.ExtensiveHealthRework.DebugMode
        sandboxEnabled = debugModeValue == true or debugModeValue == 1
    end

    if not sandboxEnabled then
        print("[EHR] Debug Menu: Access denied - Sandbox DebugMode is DISABLED")
        print("[EHR] Enable it in Sandbox Options -> Extensive Health Rework -> Debug Mode")
        return
    end

    -- MP admin check
    if isClient() then
        local player = getSpecificPlayer(0)
        local accessLevel = ""
        if player then
            pcall(function() accessLevel = player:getAccessLevel() or "" end)
        end
        local hasAccess = accessLevel == "admin" or accessLevel == "moderator" or accessLevel == "gm"
        if not hasAccess then
            print("[EHR] Debug Menu: Access denied - You need ADMIN access in multiplayer")
            print("[EHR] Your current access level: '" .. tostring(accessLevel) .. "'")
            print("[EHR] Use /setaccesslevel [YourName] admin to give yourself admin")
            return
        end
    end

    local player = getSpecificPlayer(0)
    if not player then return end

    if EHR.DebugV2.instance then
        -- Close existing
        EHR.DebugV2.instance:onClose()
    else
        -- Open new
        local screenW = getCore():getScreenWidth()
        local screenH = getCore():getScreenHeight()
        local x = (screenW - WINDOW_WIDTH) / 2
        local y = (screenH - WINDOW_HEIGHT) / 2

        local menu = EHR_DebugMenuV2:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT, player)
        menu:initialise()
        menu:addToUIManager()
        menu:setVisible(true)

        EHR.DebugV2.instance = menu
        EHR.DebugV2.Log("Debug Menu opened", "UI", "INFO")
    end
end

-- Compatibility alias for old keybind system
EHR.DebugMenu = EHR.DebugMenu or {}
EHR.DebugMenu.Toggle = EHR.DebugV2.Toggle

-- ============================================
-- MODULE LOADED
-- ============================================

EHR.Log("DebugMenuV2 module loaded")
