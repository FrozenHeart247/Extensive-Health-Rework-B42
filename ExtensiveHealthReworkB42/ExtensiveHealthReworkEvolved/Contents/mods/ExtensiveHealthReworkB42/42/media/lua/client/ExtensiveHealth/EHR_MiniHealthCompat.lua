--[[
    Extensive Health Rework B42
    MiniHealthPanel Compatibility Module

    Adds a companion status panel that docks next to MiniHealthPanel:
    - Blood volume percentage
    - Infected body parts count
    - Sepsis status
    - Disease status

    Requires: MiniHealthPanel mod

    v1.0.0 - Initial implementation
]]--

require "ISUI/ISPanel"

-- ============================================
-- COMPANION PANEL CLASS
-- ============================================

ISEHRCompanionPanel = ISPanel:derive("ISEHRCompanionPanel")

-- Panel dimensions
ISEHRCompanionPanel.PANEL_WIDTH = 90
ISEHRCompanionPanel.PANEL_HEIGHT = 100
ISEHRCompanionPanel.PADDING = 5
ISEHRCompanionPanel.LINE_HEIGHT = 18
ISEHRCompanionPanel.DOCK_GAP = 2

-- Colors
ISEHRCompanionPanel.COLORS = {
    -- Blood level colors
    bloodHealthy = {r=0.4, g=0.9, b=0.4},    -- Green >70%
    bloodMild = {r=0.9, g=0.9, b=0.3},       -- Yellow 50-70%
    bloodLow = {r=0.9, g=0.5, b=0.2},        -- Orange 30-50%
    bloodCritical = {r=0.9, g=0.2, b=0.2},   -- Red <30%

    -- Infection colors
    infectionNone = {r=0.5, g=0.5, b=0.5},   -- Gray
    infectionActive = {r=0.9, g=0.4, b=0.1}, -- Orange

    -- Sepsis colors
    sepsisNone = {r=0.5, g=0.5, b=0.5},      -- Gray
    sepsisActive = {r=0.9, g=0.1, b=0.1},    -- Red

    -- Disease colors
    diseaseNone = {r=0.5, g=0.5, b=0.5},     -- Gray
    diseaseActive = {r=0.7, g=0.9, b=0.3},   -- Yellow-green

    -- Text
    label = {r=0.7, g=0.7, b=0.7},
    value = {r=1.0, g=1.0, b=1.0},
    title = {r=0.9, g=0.9, b=0.9},
}

function ISEHRCompanionPanel:new(mhpHandle)
    local o = ISPanel:new(0, 0, self.PANEL_WIDTH, self.PANEL_HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.mhpHandle = mhpHandle
    o.player = mhpHandle.player
    o.playerIndex = mhpHandle.playerIndex

    o.backgroundColor = {r=0.0, g=0.0, b=0.0, a=0.6}
    o.borderColor = {r=0.4, g=0.4, b=0.4, a=1.0}

    -- Cached values
    o.bloodPercent = 100
    o.bloodColor = ISEHRCompanionPanel.COLORS.bloodHealthy
    o.infectedCount = 0
    o.sepsisStage = 0
    o.sepsisText = "--"
    o.diseaseStage = 0
    o.diseaseText = "--"

    -- Docking state
    o.dockedRight = true

    -- Update timer
    o.updateCounter = 0
    o.UPDATE_INTERVAL = 30  -- ~1 second

    return o
end

function ISEHRCompanionPanel:initialise()
    ISPanel.initialise(self)
end

function ISEHRCompanionPanel:createChildren()
    -- No child elements needed, we draw everything manually
end

-- ============================================
-- POSITIONING
-- ============================================

function ISEHRCompanionPanel:updatePosition()
    if not self.mhpHandle then return end

    local mhp = self.mhpHandle
    local screenWidth = getCore():getScreenWidth()

    local mhpRight = mhp:getX() + mhp:getWidth()
    local panelWidth = self:getWidth()

    -- Check if docking right would go off screen
    if (mhpRight + self.DOCK_GAP + panelWidth) > screenWidth then
        -- Dock to left
        self:setX(mhp:getX() - panelWidth - self.DOCK_GAP)
        self.dockedRight = false
    else
        -- Dock to right (default)
        self:setX(mhpRight + self.DOCK_GAP)
        self.dockedRight = true
    end

    -- Match Y position
    self:setY(mhp:getY())
end

-- ============================================
-- DATA UPDATES
-- ============================================

function ISEHRCompanionPanel:updateData()
    if not self.player then return end
    if not EHR then return end

    -- Get blood data
    if EHR.Blood and EHR.Blood.GetPercent then
        self.bloodPercent = EHR.Blood.GetPercent(self.player)
        self.bloodColor = self:getBloodColor(self.bloodPercent)
    end

    -- Get infection count
    if EHR.WoundInfection and EHR.WoundInfection.CountInfectedParts then
        self.infectedCount = EHR.WoundInfection.CountInfectedParts(self.player)
    end

    -- Get sepsis data
    if EHR.Sepsis and EHR.Sepsis.GetData then
        local sepsisData = EHR.Sepsis.GetData(self.player)
        if sepsisData and sepsisData.stage and sepsisData.stage > 0 then
            self.sepsisStage = sepsisData.stage
            self.sepsisText = self:getSepsisText(sepsisData.stage)
        else
            self.sepsisStage = 0
            self.sepsisText = "--"
        end
    end

    -- Get disease data
    if EHR.Disease and EHR.Disease.GetDiseaseData then
        local diseaseData = EHR.Disease.GetDiseaseData(self.player)
        if diseaseData and diseaseData.active then
            -- Find worst disease stage
            local worstStage = 0
            for _, disease in pairs(diseaseData.active) do
                if disease.stage and disease.stage > worstStage then
                    worstStage = disease.stage
                end
            end
            if worstStage > 0 then
                self.diseaseStage = worstStage
                self.diseaseText = self:getDiseaseText(worstStage)
            else
                self.diseaseStage = 0
                self.diseaseText = "--"
            end
        else
            self.diseaseStage = 0
            self.diseaseText = "--"
        end
    end
end

function ISEHRCompanionPanel:getBloodColor(percent)
    if percent > 70 then
        return self.COLORS.bloodHealthy
    elseif percent > 50 then
        return self.COLORS.bloodMild
    elseif percent > 30 then
        return self.COLORS.bloodLow
    else
        return self.COLORS.bloodCritical
    end
end

function ISEHRCompanionPanel:getSepsisText(stage)
    local stageNames = {
        [1] = "Early",
        [2] = "Moderate",
        [3] = "Severe",
        [4] = "Shock",
    }
    return stageNames[stage] or "Active"
end

function ISEHRCompanionPanel:getDiseaseText(stage)
    local stageNames = {
        [1] = "Mild",
        [2] = "Moderate",
        [3] = "Severe",
        [4] = "Critical",
    }
    return stageNames[stage] or "Active"
end

-- ============================================
-- RENDERING
-- ============================================

function ISEHRCompanionPanel:prerender()
    -- Background
    self:drawRect(0, 0, self.width, self.height,
        self.backgroundColor.a,
        self.backgroundColor.r,
        self.backgroundColor.g,
        self.backgroundColor.b)

    -- Border
    self:drawRectBorder(0, 0, self.width, self.height,
        self.borderColor.a,
        self.borderColor.r,
        self.borderColor.g,
        self.borderColor.b)
end

function ISEHRCompanionPanel:render()
    local x = self.PADDING
    local y = self.PADDING
    local lineH = self.LINE_HEIGHT

    -- Title
    local title = "EHR Status"
    local titleWidth = getTextManager():MeasureStringX(UIFont.Small, title)
    self:drawText(title, (self.width - titleWidth) / 2, y,
        self.COLORS.title.r, self.COLORS.title.g, self.COLORS.title.b, 1.0,
        UIFont.Small)
    y = y + lineH + 2

    -- Separator line
    self:drawRect(x, y, self.width - (x * 2), 1, 0.5, 0.4, 0.4, 0.4)
    y = y + 4

    -- Blood
    self:drawText("Blood:", x, y,
        self.COLORS.label.r, self.COLORS.label.g, self.COLORS.label.b, 1.0,
        UIFont.Small)
    local bloodText = string.format("%d%%", math.floor(self.bloodPercent))
    local bloodTextWidth = getTextManager():MeasureStringX(UIFont.Small, bloodText)
    self:drawText(bloodText, self.width - x - bloodTextWidth, y,
        self.bloodColor.r, self.bloodColor.g, self.bloodColor.b, 1.0,
        UIFont.Small)
    y = y + lineH

    -- Infected parts
    local infectColor = self.infectedCount > 0 and self.COLORS.infectionActive or self.COLORS.infectionNone
    self:drawText("Infect:", x, y,
        self.COLORS.label.r, self.COLORS.label.g, self.COLORS.label.b, 1.0,
        UIFont.Small)
    local infectText = tostring(self.infectedCount)
    local infectTextWidth = getTextManager():MeasureStringX(UIFont.Small, infectText)
    self:drawText(infectText, self.width - x - infectTextWidth, y,
        infectColor.r, infectColor.g, infectColor.b, 1.0,
        UIFont.Small)
    y = y + lineH

    -- Sepsis
    local sepsisColor = self.sepsisStage > 0 and self.COLORS.sepsisActive or self.COLORS.sepsisNone
    self:drawText("Sepsis:", x, y,
        self.COLORS.label.r, self.COLORS.label.g, self.COLORS.label.b, 1.0,
        UIFont.Small)
    local sepsisTextWidth = getTextManager():MeasureStringX(UIFont.Small, self.sepsisText)
    self:drawText(self.sepsisText, self.width - x - sepsisTextWidth, y,
        sepsisColor.r, sepsisColor.g, sepsisColor.b, 1.0,
        UIFont.Small)
    y = y + lineH

    -- Disease
    local diseaseColor = self.diseaseStage > 0 and self.COLORS.diseaseActive or self.COLORS.diseaseNone
    self:drawText("Disease:", x, y,
        self.COLORS.label.r, self.COLORS.label.g, self.COLORS.label.b, 1.0,
        UIFont.Small)
    local diseaseTextWidth = getTextManager():MeasureStringX(UIFont.Small, self.diseaseText)
    self:drawText(self.diseaseText, self.width - x - diseaseTextWidth, y,
        diseaseColor.r, diseaseColor.g, diseaseColor.b, 1.0,
        UIFont.Small)
end

function ISEHRCompanionPanel:update()
    -- Follow MHP visibility
    if self.mhpHandle then
        local mhpVisible = self.mhpHandle:isVisible()
        local mhpAlpha = self.mhpHandle.alpha or 1

        if not mhpVisible or mhpAlpha <= 0 then
            self:setVisible(false)
            return
        else
            self:setVisible(true)
        end

        -- Match MHP alpha for fade effect
        self.backgroundColor.a = 0.6 * mhpAlpha
        self.borderColor.a = 1.0 * mhpAlpha
    end

    -- Update position (in case MHP moved)
    self:updatePosition()

    -- Update data periodically
    self.updateCounter = self.updateCounter + 1
    if self.updateCounter >= self.UPDATE_INTERVAL then
        self.updateCounter = 0
        self:updateData()
    end
end

-- ============================================
-- COMPATIBILITY MODULE
-- ============================================

EHR = EHR or {}
EHR.MiniHealthCompat = {}

-- Store companion panels per player
EHR.MiniHealthCompat.panels = {}

--[[
    Check if MiniHealthPanel is loaded
]]--
function EHR.MiniHealthCompat.IsModLoaded()
    return ISMiniHealth ~= nil and mhpHandle ~= nil
end

--[[
    Create companion panel for MHP
]]--
function EHR.MiniHealthCompat.CreateCompanionPanel(mhpHandle)
    if not mhpHandle then return nil end

    local panel = ISEHRCompanionPanel:new(mhpHandle)
    panel:initialise()
    panel:instantiate()
    panel:addToUIManager()
    panel:setVisible(true)

    -- Initial position and data
    panel:updatePosition()
    panel:updateData()

    return panel
end

--[[
    Initialize compatibility
]]--
function EHR.MiniHealthCompat.Initialize()
    if not EHR.MiniHealthCompat.IsModLoaded() then
        if EHR and EHR.Log then
            EHR.Log("MiniHealthPanel not detected - companion panel inactive")
        end
        return
    end

    if EHR and EHR.Log then
        EHR.Log("MiniHealthPanel detected - creating companion panel")
    end

    -- Create companion panel for existing mhpHandle
    if mhpHandle then
        local panel = EHR.MiniHealthCompat.CreateCompanionPanel(mhpHandle)
        if panel then
            EHR.MiniHealthCompat.panels[0] = panel
            if EHR and EHR.Log then
                EHR.Log("EHR companion panel created")
            end
        end
    end
end

--[[
    Delayed initialization (wait for MHP to be ready)
]]--
function EHR.MiniHealthCompat.OnGameStart()
    -- Delay initialization to ensure MHP is fully loaded
    -- MHP creates mhpHandle in its OnGameStart, so we wait a bit
    if EHR and EHR.Log then
        EHR.Log("MiniHealthCompat: Scheduling delayed init...")
    end
end

-- Tick counter for delayed init
local initDelayCounter = 0
local initDone = false

-- Expose reset function for death/respawn handling
EHR.MiniHealthCompat = EHR.MiniHealthCompat or {}
EHR.MiniHealthCompat.Reset = function()
    initDelayCounter = 0
    initDone = false
    EHR.Log("MiniHealthCompat: Reset")
end

function EHR.MiniHealthCompat.OnTick()
    if initDone then return end

    initDelayCounter = initDelayCounter + 1

    -- Wait ~2 seconds for MHP to fully initialize
    if initDelayCounter >= 60 then
        initDone = true
        EHR.MiniHealthCompat.Initialize()
    end
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events then
    Events.OnGameStart.Add(EHR.MiniHealthCompat.OnGameStart)
    Events.OnTick.Add(EHR.MiniHealthCompat.OnTick)

    if EHR and EHR.Log then
        EHR.Log("MiniHealthPanel compatibility module events registered")
    else
        print("[EHR] MiniHealthPanel compatibility module events registered")
    end
end

-- ============================================
-- DEATH/RESPAWN RESET
-- ============================================

-- Register death handler
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(player)
        if EHR.MiniHealthCompat and EHR.MiniHealthCompat.Reset then
            EHR.MiniHealthCompat.Reset()
        end
    end)
end

print("[EHR] MiniHealthPanel compatibility module loaded v1.0.0")
