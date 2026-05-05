--[[
    Extensive Health Rework - Medical Monitor UI

    A comprehensive health monitoring panel that displays:
    - Blood composition with saline visualization
    - Active diseases with severity and effects
    - Active medications with duration and retake timers
    - Drug interactions and warnings
    - Side effects
    - Healing status

    Author: ExtensiveHealthRework Team
    Version: 1.0
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISRichTextPanel"
require "ExtensiveHealth/EHR_WoundInfection"
require "ExtensiveHealth/EHR_LifestyleCompat"
require "ExtensiveHealth/EHR_SubstanceScanner"
require "ExtensiveHealth/EHR_DiseaseFlyers"

EHR = EHR or {}
EHR.UI = EHR.UI or {}

local function ehrSafeText(key, fallback)
    if not getText then return fallback end
    local value = getText(key)
    if not value or value == key then
        return fallback
    end
    return value
end

local function ehrFormatText(key, fallback, ...)
    local template = ehrSafeText(key, fallback)
    if not template then return fallback end
    template = template:gsub("%%%%([sd])", "%%%1")
    local ok, result = pcall(string.format, template, ...)
    if ok and result then
        return result
    end
    ok, result = pcall(string.format, fallback, ...)
    if ok and result then
        return result
    end
    return fallback
end
-- ============================================
-- MEDICAL MONITOR PANEL CLASS
-- ============================================

EHR_MedicalMonitorUI = ISPanel:derive("EHR_MedicalMonitorUI")

-- Colors
EHR_MedicalMonitorUI.Colors = {
    background = {r=0.1, g=0.1, b=0.12, a=0.95},
    border = {r=0.3, g=0.5, b=0.4, a=1},
    headerBg = {r=0.15, g=0.2, b=0.18, a=1},
    text = {r=0.9, g=0.9, b=0.9, a=1},
    textDim = {r=0.6, g=0.6, b=0.6, a=1},

    -- Blood bar colors
    blood = {r=0.8, g=0.1, b=0.1, a=1},
    salineSafe = {r=0.2, g=0.7, b=0.9, a=1},
    salineWarning = {r=0.9, g=0.7, b=0.2, a=1},
    salineDanger = {r=0.9, g=0.4, b=0.1, a=1},
    salineLethal = {r=0.9, g=0.1, b=0.1, a=1},
    empty = {r=0.2, g=0.2, b=0.2, a=1},

    -- Status colors
    safe = {r=0.2, g=0.8, b=0.3, a=1},
    warning = {r=0.9, g=0.7, b=0.2, a=1},
    danger = {r=0.9, g=0.3, b=0.1, a=1},
    critical = {r=1, g=0.1, b=0.1, a=1},

    -- Severity colors
    severity1 = {r=0.5, g=0.8, b=0.5, a=1},
    severity2 = {r=0.7, g=0.7, b=0.3, a=1},
    severity3 = {r=0.9, g=0.6, b=0.2, a=1},
    severity4 = {r=0.9, g=0.3, b=0.2, a=1},
    severity5 = {r=1, g=0.1, b=0.1, a=1},

    -- Section colors
    sectionBg = {r=0.08, g=0.08, b=0.1, a=0.8},
    sectionBorder = {r=0.25, g=0.35, b=0.3, a=1},

    -- Interaction colors
    interactionSafe = {r=0.3, g=0.7, b=0.3, a=1},
    interactionWarning = {r=0.9, g=0.6, b=0.2, a=1},
    interactionDanger = {r=0.9, g=0.2, b=0.2, a=1},

    -- N6C Narcotics colors
    stimulant = {r=1.0, g=0.4, b=0.2, a=1},      -- Orange for stimulants (coke, meth, mdma)
    opioid = {r=0.6, g=0.3, b=0.8, a=1},         -- Purple for opioids
    depressant = {r=0.3, g=0.5, b=0.9, a=1},     -- Blue for depressants (benzos)
    cannabis = {r=0.4, g=0.8, b=0.3, a=1},       -- Green for cannabis
    withdrawal = {r=0.7, g=0.2, b=0.2, a=1},     -- Dark red for withdrawal

    -- Disease trend arrow colors
    trendImproving = {r=0.2, g=0.9, b=0.3, a=1},   -- Green for improving
    trendWorsening = {r=0.9, g=0.2, b=0.2, a=1},   -- Red for worsening
    trendStable = {r=0.8, g=0.8, b=0.3, a=1},      -- Yellow for stable
}

-- Panel dimensions
EHR_MedicalMonitorUI.EXPANDED_WIDTH = 800
EHR_MedicalMonitorUI.EXPANDED_HEIGHT = 800
EHR_MedicalMonitorUI.COMPACT_WIDTH = 550
EHR_MedicalMonitorUI.COMPACT_HEIGHT = 260
EHR_MedicalMonitorUI.LINE_HEIGHT = 26
EHR_MedicalMonitorUI.SMALL_LINE_HEIGHT = 20
EHR_MedicalMonitorUI.CONTENT_TOP = 40
EHR_MedicalMonitorUI.FOOTER_HEIGHT = 44
EHR_MedicalMonitorUI.EXPANDED_MIN_HEIGHT = 360
EHR_MedicalMonitorUI.EXPANDED_SCREEN_MARGIN = 20
EHR_MedicalMonitorUI.SECTION_HEADER_HEIGHT = 30
EHR_MedicalMonitorUI.SCROLL_STEP = 52

function EHR_MedicalMonitorUI:getTextWidth(text, font)
    text = tostring(text or "")
    font = font or UIFont.Small

    if getTextManager then
        local ok, width = pcall(function()
            return getTextManager():MeasureStringX(font, text)
        end)
        if ok and width then
            return width
        end
    end

    return #text * 7
end

function EHR_MedicalMonitorUI:trimLastCharacter(text)
    local len = #text
    if len <= 1 then return "" end

    local cut = len
    while cut > 1 do
        local byte = string.byte(text, cut)
        if not byte or byte < 128 or byte >= 192 then
            break
        end
        cut = cut - 1
    end

    return text:sub(1, cut - 1)
end

function EHR_MedicalMonitorUI:truncateText(text, maxWidth, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if not maxWidth or maxWidth <= 0 then return "" end
    if self:getTextWidth(text, font) <= maxWidth then return text end

    local suffix = "..."
    local trimmed = text
    while #trimmed > 0 and self:getTextWidth(trimmed .. suffix, font) > maxWidth do
        trimmed = self:trimLastCharacter(trimmed)
    end

    return trimmed .. suffix
end

function EHR_MedicalMonitorUI:drawRightTextFit(text, rightX, y, r, g, b, a, font, minX)
    text = tostring(text or "")
    font = font or UIFont.Small

    if minX then
        text = self:truncateText(text, rightX - minX, font)
    end

    local x = rightX - self:getTextWidth(text, font)
    if minX and x < minX then
        x = minX
    end

    self:drawText(text, x, y, r, g, b, a, font)
end

function EHR_MedicalMonitorUI:getExpandedMaxHeight()
    local screenHeight = EHR_MedicalMonitorUI.EXPANDED_HEIGHT
    if getCore then
        local ok, height = pcall(function()
            return getCore():getScreenHeight()
        end)
        if ok and height then
            screenHeight = height
        end
    end

    local top = self:getY() or 0
    local maxHeight = screenHeight - top - self.EXPANDED_SCREEN_MARGIN
    maxHeight = math.max(self.EXPANDED_MIN_HEIGHT, maxHeight)
    return math.min(maxHeight, screenHeight - self.EXPANDED_SCREEN_MARGIN)
end

function EHR_MedicalMonitorUI:getContentClipHeight()
    return math.max(24, self.height - self.CONTENT_TOP - self.FOOTER_HEIGHT)
end

function EHR_MedicalMonitorUI:getMaxContentScroll()
    if not self.isExpanded then return 0 end
    return math.max(0, (self.contentHeight or 0) - self:getContentClipHeight())
end

function EHR_MedicalMonitorUI:clampContentScroll()
    local maxScroll = self:getMaxContentScroll()
    self.contentScrollY = math.max(0, math.min(self.contentScrollY or 0, maxScroll))
    return maxScroll
end

function EHR_MedicalMonitorUI:repositionControls()
    if self.toggleBtn then
        self.toggleBtn:setX(self.width - 25)
    end
    if self.closeBtn then
        self.closeBtn:setX(self.width - 50)
    end

    if self.examineBtn then
        local btnWidth = 120
        local btnHeight = 20
        self.examineBtn:setX(self.width - btnWidth - 20)
        self.examineBtn:setY(self.height - btnHeight - 8)
    end
end

function EHR_MedicalMonitorUI:keepOnScreen()
    if not getCore then return end

    local screenW = nil
    local screenH = nil
    local okW, width = pcall(function()
        return getCore():getScreenWidth()
    end)
    if okW and width then screenW = width end

    local okH, height = pcall(function()
        return getCore():getScreenHeight()
    end)
    if okH and height then screenH = height end

    local margin = self.EXPANDED_SCREEN_MARGIN or 20
    if screenW then
        local maxX = math.max(margin, screenW - self.width - margin)
        local x = self:getX() or 0
        if x > maxX then
            self:setX(maxX)
        elseif x < margin then
            self:setX(margin)
        end
    end

    if screenH then
        local maxY = math.max(margin, screenH - self.height - margin)
        local y = self:getY() or 0
        if y > maxY then
            self:setY(maxY)
        elseif y < margin then
            self:setY(margin)
        end
    end
end

function EHR_MedicalMonitorUI:updateAdaptiveHeight()
    if not self.isExpanded then
        if self.height ~= self.COMPACT_HEIGHT then
            self:setHeight(self.COMPACT_HEIGHT)
            self:repositionControls()
        end
        self.contentScrollY = 0
        return
    end

    local contentHeight = self.contentHeight or 0
    local wantedHeight = math.max(self.EXPANDED_HEIGHT, self.CONTENT_TOP + self.FOOTER_HEIGHT + contentHeight)
    wantedHeight = math.min(wantedHeight, self:getExpandedMaxHeight())
    wantedHeight = math.max(self.EXPANDED_MIN_HEIGHT, wantedHeight)

    if math.abs((self.height or 0) - wantedHeight) > 1 then
        self:setHeight(wantedHeight)
        self:keepOnScreen()
        self:repositionControls()
    end

    self:clampContentScroll()
end

function EHR_MedicalMonitorUI:renderScrollBar()
    local maxScroll = self:getMaxContentScroll()
    if maxScroll <= 0 then return end

    local top = self.CONTENT_TOP
    local height = self:getContentClipHeight()
    local trackX = self.width - 7
    local thumbHeight = math.max(24, height * (height / (height + maxScroll)))
    local thumbY = top
    if maxScroll > 0 then
        thumbY = top + ((self.contentScrollY or 0) / maxScroll) * (height - thumbHeight)
    end

    self:drawRect(trackX, top, 3, height, 0.25, 0.2, 0.35, 0.28)
    self:drawRect(trackX - 1, thumbY, 5, thumbHeight, 0.85, self.Colors.border.r, self.Colors.border.g, self.Colors.border.b)
end

function EHR_MedicalMonitorUI:onMouseWheel(del)
    if not self.isExpanded then return false end

    local maxScroll = self:getMaxContentScroll()
    if maxScroll <= 0 then return false end

    self.contentScrollY = (self.contentScrollY or 0) + (del * self.SCROLL_STEP)
    self:clampContentScroll()
    return true
end
function EHR_MedicalMonitorUI:new(x, y, player)
    local o = ISPanel:new(x, y, EHR_MedicalMonitorUI.COMPACT_WIDTH, EHR_MedicalMonitorUI.COMPACT_HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.playerNum = player:getPlayerNum()
    o.isExpanded = false
    o.anchorLeft = true
    o.anchorRight = false
    o.anchorTop = true
    o.anchorBottom = false
    o.moveWithMouse = true

    -- Animation
    o.pulsePhase = 0
    o.flashPhase = 0

    -- Cache for performance
    o.lastUpdate = 0
    o.updateInterval = 500 -- ms
    o.cachedData = {}
    o.contentScrollY = 0
    o.contentHeight = 0

    return o
end
function EHR_MedicalMonitorUI:initialise()
    ISPanel.initialise(self)
end

function EHR_MedicalMonitorUI:createChildren()
    ISPanel.createChildren(self)

    -- Toggle expand/collapse button
    self.toggleBtn = ISButton:new(
        self.width - 25, 5, 20, 20,
        "+", self, EHR_MedicalMonitorUI.onToggleExpand
    )
    self.toggleBtn:initialise()
    self.toggleBtn:instantiate()
    self.toggleBtn.borderColor = self.Colors.border
    self:addChild(self.toggleBtn)

    -- Close button
    self.closeBtn = ISButton:new(
        self.width - 50, 5, 20, 20,
        "X", self, EHR_MedicalMonitorUI.onClose
    )
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = self.Colors.border
    self:addChild(self.closeBtn)

    -- Examine Self button (at bottom-right of panel)
    local btnWidth = 120
    local btnHeight = 20
    self.examineBtn = ISButton:new(
        self.width - btnWidth - 20,  -- Right-aligned with breathing room
        self.height - btnHeight - 8,
        btnWidth, btnHeight,
        getText("UI_EHR_ExamineButton") or "Examine Self",
        self, EHR_MedicalMonitorUI.onExamineSelf
    )
    self.examineBtn:initialise()
    self.examineBtn:instantiate()
    self.examineBtn.borderColor = self.Colors.border
    self.examineBtn.backgroundColor = {r=0.15, g=0.25, b=0.2, a=0.9}
    self.examineBtn:setTooltip(getText("UI_EHR_ExamineButton_tt") or "Examine your current health condition")
    self:addChild(self.examineBtn)
end

function EHR_MedicalMonitorUI:onToggleExpand()
    self.isExpanded = not self.isExpanded
    self.contentScrollY = 0

    if self.isExpanded then
        self:setWidth(EHR_MedicalMonitorUI.EXPANDED_WIDTH)
        self:setHeight(EHR_MedicalMonitorUI.EXPANDED_HEIGHT)
        self.toggleBtn:setTitle("-")
    else
        self:setWidth(EHR_MedicalMonitorUI.COMPACT_WIDTH)
        self:setHeight(EHR_MedicalMonitorUI.COMPACT_HEIGHT)
        self.toggleBtn:setTitle("+")
    end

    self:keepOnScreen()
    self:repositionControls()
    self:updateAdaptiveHeight()
    self:keepOnScreen()
end
function EHR_MedicalMonitorUI:onClose()
    self:setVisible(false)
    EHR.UI.MonitorVisible = false
end

-- ============================================
-- SELF-EXAMINATION FEATURE
-- ============================================

function EHR_MedicalMonitorUI:onExamineSelf()
    if not self.player then return end

    -- Prevent spam - cooldown of 2 seconds
    local now = getTimestampMs()
    if self.lastExamineTime and (now - self.lastExamineTime) < 2000 then
        return
    end
    self.lastExamineTime = now

    -- Get medical skill tier (true = ignore debug bypass for dialogue immersion)
    local skillTier, skillLevel = self:getMedicalSkillTier(true)

    -- Collect current health information
    local blood = self.cachedData.blood or {}
    local diseases = self.cachedData.diseases or {}

    -- Count active issues
    local diseaseCount = 0
    local severeDisease = nil
    local highestSeverity = 0
    for diseaseId, diseaseData in pairs(diseases) do
        diseaseCount = diseaseCount + 1
        if (diseaseData.severity or 1) > highestSeverity then
            highestSeverity = diseaseData.severity or 1
            severeDisease = {id = diseaseId, data = diseaseData}
        end
    end

    -- Check blood levels
    local currentVolume = blood.currentVolume or 5000
    local maxVolume = blood.maxVolume or 5000
    local bloodPercent = (currentVolume / maxVolume) * 100

    -- Check for sepsis specifically
    local hasSepsis = diseases["Sepsis"] ~= nil
    local sepsisStage = hasSepsis and diseases["Sepsis"].stage or 0

    -- Check for wound infections (if available)
    local hasWoundInfection = false
    if self.isRemoteExamination and self.remoteExamData then
        -- Check server-provided wound data for remote examination
        local woundData = self.remoteExamData.EHR_WoundInfection
        hasWoundInfection = woundData and woundData.worstStage and woundData.worstStage > 0
    elseif EHR.WoundInfection and EHR.WoundInfection.HasAnyInfection then
        hasWoundInfection = EHR.WoundInfection.HasAnyInfection(self.player)
    end

    -- Generate dialogue based on skill tier and conditions
    local dialogue = self:generateExamineDialogue(skillTier, skillLevel, {
        bloodPercent = bloodPercent,
        diseaseCount = diseaseCount,
        severeDisease = severeDisease,
        hasSepsis = hasSepsis,
        sepsisStage = sepsisStage,
        hasWoundInfection = hasWoundInfection,
        highestSeverity = highestSeverity,
    })

    -- Make the character say the dialogue
    if dialogue and self.player.Say then
        self.player:Say(dialogue)
    end

    -- Record examination to medical journal
    self:recordExamination(skillTier, dialogue, {
        bloodPercent = bloodPercent,
        diseaseCount = diseaseCount,
        hasSepsis = hasSepsis,
        sepsisStage = sepsisStage,
    })

    -- Award First Aid XP for self-examination
    local foundIssues = diseaseCount > 0 or bloodPercent < 90 or hasWoundInfection
    if EHR.SkillXP and EHR.SkillXP.OnSelfExamination then
        EHR.SkillXP.OnSelfExamination(self.player, skillTier, foundIssues)
    end
end

--[[
    Generate examination dialogue based on skill tier and current conditions.

    @param skillTier (number) - Player's medical skill tier (0-4)
    @param skillLevel (number) - Raw First Aid skill level
    @param conditions (table) - Current health conditions
    @return string - Dialogue for the character to say
]]--
function EHR_MedicalMonitorUI:generateExamineDialogue(skillTier, skillLevel, conditions)
    local dialogue = ""

    -- No issues detected
    if conditions.diseaseCount == 0 and conditions.bloodPercent >= 90 and not conditions.hasWoundInfection then
        if skillTier >= 3 then
            -- Expert/Master: detailed healthy status
            dialogue = getText("UI_EHR_Examine_HealthyDetailed") or "All vitals look good. Blood levels normal, no infections detected."
        else
            -- Lower skill: simple response
            dialogue = getText("UI_EHR_Examine_Healthy") or "I feel fine. Nothing seems wrong."
        end
        return dialogue
    end

    -- Blood loss detection
    if conditions.bloodPercent < 50 then
        if skillTier >= 2 then
            local status = conditions.bloodPercent < 30 and "Need a transfusion urgently!" or "Moderate blood loss."
            dialogue = string.format(getText("UI_EHR_Examine_BloodDetailed") or "Blood volume at approximately %d%%. %s", math.floor(conditions.bloodPercent), status)
        elseif skillTier >= 1 then
            dialogue = conditions.bloodPercent < 30 and (getText("UI_EHR_Examine_BloodCritical") or "I've lost too much blood! I need a transfusion!") or (getText("UI_EHR_Examine_BloodLow") or "I've lost blood... I feel weak.")
        else
            dialogue = getText("UI_EHR_Dialogue_Blood_Lightheaded") or "I feel lightheaded..."
        end
        return dialogue
    end

    -- Sepsis detection (high priority)
    if conditions.hasSepsis then
        if skillTier >= 3 then
            -- Expert: Full diagnosis
            dialogue = string.format(getText("UI_EHR_Examine_SepsisDetailed") or "Sepsis confirmed, Stage %d. Need IV antibiotics immediately!", conditions.sepsisStage)
        elseif skillTier >= 1 then
            -- Novice: Can identify sepsis
            dialogue = getText("UI_EHR_Examine_SepsisIdentified") or "I think I have blood poisoning... sepsis!"
        else
            -- Clueless: Vague symptoms
            dialogue = getText("UI_EHR_Examine_SepsisVague") or "I feel feverish and weak all over..."
        end
        return dialogue
    end

    -- Wound infection detection
    if conditions.hasWoundInfection then
        if skillTier >= 1 then
            dialogue = getText("UI_EHR_Examine_WoundInfection") or "One of my wounds looks infected..."
        else
            dialogue = getText("UI_EHR_Examine_SomethingWrong") or "Something doesn't feel right..."
        end
        return dialogue
    end

    -- Disease detection
    if conditions.diseaseCount > 0 then
        local disease = conditions.severeDisease

        if conditions.diseaseCount > 1 then
            -- Multiple issues
            if skillTier >= 2 then
                dialogue = getText("UI_EHR_Examine_MultipleIssues") or "I have multiple health issues to deal with."
            else
                dialogue = getText("UI_EHR_Examine_FeelSick") or "I feel sick... but I can't tell what's wrong."
            end
        elseif disease then
            -- Single disease
            if skillTier >= 3 and disease.data then
                -- Expert: Full details
                local diseaseDef = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[disease.id]
                local displayName = diseaseDef and diseaseDef.name or disease.id
                local stage = disease.data.stage or 1
                local severity = disease.data.severity or 1
                dialogue = ehrFormatText("UI_EHR_Examine_DiseaseDetailed", "Diagnosis: %s, Stage %d. Severity: %d/5.", displayName, stage, severity)
            elseif skillTier >= 1 then
                -- Novice: Can identify disease
                local diseaseDef = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[disease.id]
                local displayName = diseaseDef and diseaseDef.name or disease.id
                dialogue = ehrFormatText("UI_EHR_Examine_DiseaseIdentified", "I believe I have %s.", displayName)
            else
                -- Clueless: Vague
                dialogue = getText("UI_EHR_Examine_DiseaseVague") or "I think I might be sick with something..."
            end
        end
        return dialogue
    end

    -- Fallback: something wrong but can't identify
    dialogue = getText("UI_EHR_Examine_SomethingWrong") or "Something doesn't feel right..."
    return dialogue
end

--[[
    Record the examination results to the medical journal.

    @param skillTier (number)
    @param dialogue (string)
    @param conditions (table)
]]--
function EHR_MedicalMonitorUI:recordExamination(skillTier, dialogue, conditions)
    if not EHR.MedicalJournal then return end

    local journal = EHR.MedicalJournal.GetJournal(self.player)
    if not journal then return end

    -- Create examination entry
    local entry = {
        timestamp = getGameTime():getWorldAgeHours(),
        gameDay = getGameTime():getNightsSurvived() + 1,
        entryType = "examination",
        skillTier = skillTier,
        dialogue = dialogue,
        bloodPercent = conditions.bloodPercent,
        diseaseCount = conditions.diseaseCount,
        hasSepsis = conditions.hasSepsis,
        sepsisStage = conditions.sepsisStage,
    }

    -- Add to entries
    if not journal.entries then
        journal.entries = {}
    end
    table.insert(journal.entries, 1, entry)

    -- Trim old entries if over limit
    while #journal.entries > EHR.MedicalJournal.MAX_ENTRIES do
        table.remove(journal.entries)
    end

    -- Update timestamp
    journal.lastUpdated = getGameTime():getWorldAgeHours()

    if EHR.DEBUG then
        EHR.Log("Journal: Recorded self-examination")
    end
end

function EHR_MedicalMonitorUI:update()
    ISPanel.update(self)

    -- Update animations
    self.pulsePhase = (self.pulsePhase + 0.05) % (math.pi * 2)
    self.flashPhase = (self.flashPhase + 0.1) % (math.pi * 2)

    -- Update cached data periodically
    local now = getTimestampMs()
    if now - self.lastUpdate > self.updateInterval then
        self:updateCachedData()
        self.lastUpdate = now
    end

    self:updateAdaptiveHeight()
end
function EHR_MedicalMonitorUI:updateCachedData()
    if not self.player then return end

    -- SAFETY: Check if player is still valid and alive
    -- If player died, the monitor should be destroyed - this is a fallback
    if not self.player:isAlive() then
        EHR.Log("Medical Monitor: Player is dead, skipping update")
        return
    end

    -- For remote examination, skip the local player check
    -- Remote examinations use server-provided data
    if not self.isRemoteExamination then
        -- SAFETY: Verify this is the current player (handles respawn edge cases)
        local currentPlayer = getSpecificPlayer(self.playerNum)
        if currentPlayer ~= self.player then
            EHR.Log("Medical Monitor: Player reference mismatch, invalidating monitor")
            self.player = nil
            return
        end
    end

    -- Get data source: remote exam data from server OR local player data
    local data
    if self.isRemoteExamination and self.remoteExamData then
        -- Use server-provided data for remote examination
        data = self.remoteExamData
    else
        -- Use local player data
        data = EHR.GetPlayerData(self.player)
    end

    if not data then return end

    -- Preserve trend history across cache updates
    local previousTrends = self.cachedData.diseaseTrends or {}

    self.cachedData = {
        blood = data.EHR_Blood or {},
        diseases = {},
        medications = {},
        sideEffects = {},
        doseStatuses = {},
        narcotics = {},        -- N6C active substances
        withdrawal = nil,      -- N6C withdrawal status
        diseaseTrends = previousTrends,  -- Preserve trend tracking
    }

    -- Build a quick lookup of diseases currently under treatment.
    local activeTreatmentMap = {}
    if self.isRemoteExamination and self.remoteExamData and self.remoteExamData.EHR_Medication then
        local activeTreatments = self.remoteExamData.EHR_Medication.activeTreatments or {}
        for diseaseId, _ in pairs(activeTreatments) do
            activeTreatmentMap[diseaseId] = true
        end
    elseif EHR.Medication and EHR.Medication.GetMedicationData then
        local medTracking = EHR.Medication.GetMedicationData(self.player)
        local activeTreatments = medTracking and medTracking.activeTreatments or {}
        for diseaseId, _ in pairs(activeTreatments) do
            activeTreatmentMap[diseaseId] = true
        end
    end
    -- Get disease data
    -- CRITICAL FIX: Make a COPY of the diseases, don't use a reference!
    -- Using a reference caused sepsis to be cleared when the disease module cleared its table
    local diseaseData
    if self.isRemoteExamination and self.remoteExamData then
        -- Use server-provided disease data for remote examination
        diseaseData = self.remoteExamData.EHR_Disease
    elseif EHR.Disease and EHR.Disease.GetDiseaseData then
        diseaseData = EHR.Disease.GetDiseaseData(self.player)
    end

    if diseaseData then
        
        -- DEBUG: Log what we found
        if not EHR.UI._diseaseLogTimer then EHR.UI._diseaseLogTimer = 0 end
        EHR.UI._diseaseLogTimer = EHR.UI._diseaseLogTimer + 1
        if EHR.UI._diseaseLogTimer >= 120 then  -- Log every ~2 seconds
            EHR.UI._diseaseLogTimer = 0
            if diseaseData then
                local count = 0
                if diseaseData.active then
                    for id, _ in pairs(diseaseData.active) do
                        count = count + 1
                    end
                end
                print("[EHR Monitor] Disease data found: " .. count .. " active diseases")
            else
                print("[EHR Monitor] No disease data found for player")
            end
        end
        
        if diseaseData and diseaseData.active then
            local currentHour = getGameTime():getWorldAgeHours()
            -- Copy each disease entry and calculate progress
            for diseaseId, diseaseInfo in pairs(diseaseData.active) do
                -- BUG-019 FIX: Calculate progress for UI display
                -- Progress = percentage of time elapsed from start to end
                local progress = 0
                if diseaseInfo.startTime and diseaseInfo.endTime then
                    local totalDuration = diseaseInfo.endTime - diseaseInfo.startTime
                    local elapsed = currentHour - diseaseInfo.startTime
                    if totalDuration > 0 then
                        progress = math.max(0, math.min(1, elapsed / totalDuration))
                    end
                end

                -- Create copy with calculated progress
                self.cachedData.diseases[diseaseId] = {
                    startTime = diseaseInfo.startTime,
                    incubationEnd = diseaseInfo.incubationEnd,
                    endTime = diseaseInfo.endTime,
                    stage = diseaseInfo.stage,
                    severity = diseaseInfo.severity,
                    diagnosed = diseaseInfo.diagnosed,
                    peakTime = diseaseInfo.peakTime,
                    warmthBlocked = diseaseInfo.warmthBlocked,
                    progress = progress,  -- Calculated progress for UI
                    treating = activeTreatmentMap[diseaseId] == true,
                }
            end
        end
    end

    -- BUG-002 FIX: Also check for sepsis (stored in separate data structure)
    -- STABILITY FIX: Use stage > 0 as source of truth (not active flag)
    local sepsisData
    if self.isRemoteExamination and self.remoteExamData then
        -- Use server-provided sepsis data for remote examination
        sepsisData = self.remoteExamData.EHR_Sepsis
    elseif EHR.Sepsis and EHR.Sepsis.GetData then
        sepsisData = EHR.Sepsis.GetData(self.player)
    end

    if sepsisData and sepsisData.stage and sepsisData.stage > 0 then
        -- Calculate progress based on stage (stages 1-4)
        local sepsisStage = sepsisData.stage or 1
        local sepsisProgress = sepsisStage / 4  -- 25%, 50%, 75%, 100%

        -- Add sepsis to the diseases table for unified display
        self.cachedData.diseases["Sepsis"] = {
            severity = sepsisStage,
            progress = sepsisProgress,
            treating = (sepsisData.treatmentDoses or 0) > 0,
            stage = sepsisStage,
            isSepsis = true,
            sourceBodyPart = sepsisData.sourceBodyPart,
        }
    end

    -- Knox Infection Integration (vanilla zombie infection)
    if EHR.KnoxCure and EHR.KnoxCure.IsInfected then
        local isInfected = EHR.KnoxCure.IsInfected(self.player)

        if isInfected then
            -- Get infection progress (0-1 scale)
            local infectionProgress = 0
            if EHR.KnoxCure.GetInfectionProgress then
                infectionProgress = EHR.KnoxCure.GetInfectionProgress(self.player) or 0
            end

            -- Add Knox to diseases display
            self.cachedData.diseases["Knox_Infection"] = {
                severity = math.max(1, math.ceil(infectionProgress * 5)),
                progress = infectionProgress,
                stage = math.max(1, math.ceil(infectionProgress * 4)),
                isKnox = true,
                diagnosed = true,
            }
        end
    end

    -- Wound Infection Integration
    local woundData
    if self.isRemoteExamination and self.remoteExamData then
        -- Use server-provided wound infection data for remote examination
        woundData = self.remoteExamData.EHR_WoundInfection
    elseif EHR.WoundInfection and EHR.WoundInfection.GetData then
        woundData = EHR.WoundInfection.GetData(self.player)
    end

    if woundData and woundData.worstStage and woundData.worstStage > 0 then
        -- Add wound infection to diseases display
        self.cachedData.diseases["Wound_Infection"] = {
            severity = woundData.worstStage,
            progress = (woundData.worstStage or 1) / 4,  -- Stages 1-4
            stage = woundData.worstStage,
            isWoundInfection = true,
            diagnosed = true,
            infectedCount = woundData.infectedCount or 1,
            worstPart = woundData.worstPart,
        }
    end

    -- Update disease trends (track improving/worsening)
    self:updateDiseaseTrends()

    -- Get body temperature warnings (pre-disease states)
    self.cachedData.temperatureWarnings = {}
    local tempData
    if self.isRemoteExamination and self.remoteExamData then
        -- Use server-provided temperature data for remote examination
        tempData = self.remoteExamData.EHR_Temperature
    elseif EHR.BodyTemp and EHR.BodyTemp.GetTemperatureData and self.player then
        tempData = EHR.BodyTemp.GetTemperatureData(self.player)
    end

    if tempData then
        local coldStage = tempData.coldStage or 0
        local hotStage = tempData.hotStage or 0
        local bodyTemp = tempData.bodyTemp or 37.0

        if coldStage > 0 then
            local coldWarnings = {
                [1] = {name = getText("UI_EHR_Temp_Chilly") or "Chilly", severity = 1, desc = getText("UI_EHR_Temp_ChillyDesc") or "Feeling cold"},
                [2] = {name = getText("UI_EHR_Temp_Cold") or "Cold", severity = 2, desc = getText("UI_EHR_Temp_ColdDesc") or "Getting cold, find warmth"},
                [3] = {name = getText("UI_EHR_Temp_VeryCold") or "Very Cold", severity = 3, desc = getText("UI_EHR_Temp_VeryColdDesc") or "Dangerously cold!"},
                [4] = {name = getText("UI_EHR_Temp_HypoRisk") or "Hypothermia Risk", severity = 4, desc = getText("UI_EHR_Temp_HypoRiskDesc") or "CRITICAL: Get warm immediately!"},
            }
            local warning = coldWarnings[coldStage]
            if warning then
                table.insert(self.cachedData.temperatureWarnings, {
                    type = "cold",
                    stage = coldStage,
                    name = warning.name,
                    severity = warning.severity,
                    description = warning.desc,
                    bodyTemp = bodyTemp,
                    dangerTime = tempData.timeAtDangerousTemp or 0,
                })
            end
        end

        if hotStage > 0 then
            local hotWarnings = {
                [1] = {name = getText("UI_EHR_Temp_Warm") or "Warm", severity = 1, desc = getText("UI_EHR_Temp_WarmDesc") or "Feeling warm"},
                [2] = {name = getText("UI_EHR_Temp_Hot") or "Hot", severity = 2, desc = getText("UI_EHR_Temp_HotDesc") or "Getting hot, find shade"},
                [3] = {name = getText("UI_EHR_Temp_VeryHot") or "Very Hot", severity = 3, desc = getText("UI_EHR_Temp_VeryHotDesc") or "Dangerously hot!"},
                [4] = {name = getText("UI_EHR_Temp_HeatRisk") or "Heat Exhaustion Risk", severity = 4, desc = getText("UI_EHR_Temp_HeatRiskDesc") or "CRITICAL: Cool down immediately!"},
            }
            local warning = hotWarnings[hotStage]
            if warning then
                table.insert(self.cachedData.temperatureWarnings, {
                    type = "hot",
                    stage = hotStage,
                    name = warning.name,
                    severity = warning.severity,
                    description = warning.desc,
                    bodyTemp = bodyTemp,
                })
            end
        end
    end

    -- Get medication data
    if self.isRemoteExamination and self.remoteExamData and self.remoteExamData.EHR_Medication then
        -- Use server-provided medication data for remote examination
        local medData = self.remoteExamData.EHR_Medication
        self.cachedData.medications = medData.activeTreatments or {}
        self.cachedData.sideEffects = medData.activeSideEffects or {}
        self.cachedData.doseStatuses = medData.activeDoses or {}
    elseif EHR.Medication then
        if EHR.Medication.GetActiveTreatments then
            self.cachedData.medications = EHR.Medication.GetActiveTreatments(self.player)
        end
        if EHR.Medication.GetActiveSideEffects then
            self.cachedData.sideEffects = EHR.Medication.GetActiveSideEffects(self.player)
        end
        if EHR.Medication.GetAllDoseStatuses then
            self.cachedData.doseStatuses = EHR.Medication.GetAllDoseStatuses(self.player)
        end
    end

    -- Get N6C Narcotics data (if mod is loaded)
    if EHR.Narcotics then
        if EHR.Narcotics.GetActiveSubstances then
            self.cachedData.narcotics = EHR.Narcotics.GetActiveSubstances(self.player)
        end
        if EHR.Narcotics.GetWithdrawalStatus then
            self.cachedData.withdrawal = EHR.Narcotics.GetWithdrawalStatus(self.player)
        end
    end

    -- Universal Substance Scanner - detects substances from other mods (v2.8.0)
    self.cachedData.otherSubstances = {}
    if EHR.SubstanceScanner then
        local scannedSubstances = EHR.SubstanceScanner.Scan(self.player)
        -- Filter out NnC substances (already handled by N6C compat)
        for _, substance in ipairs(scannedSubstances) do
            if substance.prefix ~= "NnC" then
                table.insert(self.cachedData.otherSubstances, substance)
            end
        end
    end
end

-- ============================================
-- DISEASE TREND TRACKING (v2.8.0)
-- Tracks whether diseases are improving/worsening
-- ============================================

-- Trend constants (ASCII for font compatibility)
-- Text will be fetched from translation at runtime
EHR_MedicalMonitorUI.TrendArrows = {
    improving = { symbol = "[^]", textKey = "UI_EHR_Trend_Improving", fallback = "Improving" },
    worsening = { symbol = "[v]", textKey = "UI_EHR_Trend_Worsening", fallback = "Worsening" },
    stable = { symbol = "[-]", textKey = "UI_EHR_Trend_Stable", fallback = "Stable" },
}

-- Hysteresis settings to prevent flicker
EHR_MedicalMonitorUI.TREND_SAMPLES_REQUIRED = 2  -- Need 2 consecutive samples in same direction
EHR_MedicalMonitorUI.TREND_SEVERITY_THRESHOLD = 0.02  -- Minimum severity change to count

--[[
    Update disease trends based on severity/stage changes.
    Uses hysteresis to prevent rapid flickering between states.
]]--
function EHR_MedicalMonitorUI:updateDiseaseTrends()
    local diseases = self.cachedData.diseases or {}
    local trends = self.cachedData.diseaseTrends or {}

    for diseaseId, diseaseData in pairs(diseases) do
        local currentSeverity = diseaseData.severity or 0
        local currentStage = diseaseData.stage or 1
        local stageCount = diseaseData.stageCount or 4
        local prevData = trends[diseaseId]

        if prevData then
            -- Calculate deltas
            local severityDelta = currentSeverity - (prevData.lastSeverity or currentSeverity)
            local stageDelta = currentStage - (prevData.lastStage or currentStage)

            -- Determine direction from this sample
            local sampleDirection = "stable"

            -- Active treatment means the disease is being handled even if the stage has not dropped yet.
            if diseaseData.treating then
                sampleDirection = "improving"
            -- First check: active stage changes take priority
            elseif stageDelta > 0 then
                sampleDirection = "worsening"  -- Stage increased
            elseif stageDelta < 0 then
                sampleDirection = "improving"  -- Stage decreased
            elseif severityDelta > self.TREND_SEVERITY_THRESHOLD then
                sampleDirection = "worsening"  -- Severity rising
            elseif severityDelta < -self.TREND_SEVERITY_THRESHOLD then
                sampleDirection = "improving"  -- Severity dropping
            else
                -- No active change - use stage position to determine trend
                -- All diseases: stages 1-3 = worsening (progressing toward peak)
                -- Stage 4 (final stage) = recovery/improving
                -- This applies to all disease types:
                --   Food-borne: building up toxins -> peak symptoms -> recovery
                --   Environmental: infection/condition progressing -> recovery
                --   Wound-related: infection spreading -> treatment working
                local recoveryStage = stageCount  -- Last stage is always recovery
                if currentStage >= recoveryStage then
                    sampleDirection = "improving"  -- In recovery phase
                else
                    sampleDirection = "worsening"  -- Disease is progressing (incubation through peak)
                end
            end

            -- Hysteresis: count consecutive samples in same direction
            if sampleDirection == prevData.pendingTrend then
                prevData.sampleCount = (prevData.sampleCount or 0) + 1
            else
                prevData.pendingTrend = sampleDirection
                prevData.sampleCount = 1
            end

            -- Only change displayed trend after enough samples
            if prevData.sampleCount >= self.TREND_SAMPLES_REQUIRED then
                prevData.trend = sampleDirection
            end

            -- Update last values
            prevData.lastSeverity = currentSeverity
            prevData.lastStage = currentStage
        else
            -- First observation - determine initial trend from stage position
            -- Stages 1-3 = worsening (disease progressing), Stage 4 = improving (recovery)
            local stageCount = diseaseData.stageCount or 4
            local initialTrend = "worsening"  -- Default: disease is progressing
            if diseaseData.treating then
                initialTrend = "improving"
            elseif currentStage >= stageCount then
                initialTrend = "improving"  -- Already in recovery
            end

            trends[diseaseId] = {
                trend = initialTrend,
                pendingTrend = initialTrend,
                sampleCount = 0,
                lastSeverity = currentSeverity,
                lastStage = currentStage,
            }
        end
    end

    -- Clean up trends for diseases that no longer exist
    for diseaseId, _ in pairs(trends) do
        if not diseases[diseaseId] then
            trends[diseaseId] = nil
        end
    end

    self.cachedData.diseaseTrends = trends
end

--[[
    Get trend display info for a disease.
    @param diseaseId (string) - The disease ID
    @return table { symbol, text, color } or nil
]]--
function EHR_MedicalMonitorUI:getTrendDisplay(diseaseId)
    local trends = self.cachedData.diseaseTrends or {}
    local trendData = trends[diseaseId]
    if not trendData then return nil end

    local trend = trendData.trend or "stable"
    local arrow = self.TrendArrows[trend] or self.TrendArrows.stable
    local c = self.Colors

    local color
    if trend == "improving" then
        color = c.trendImproving
    elseif trend == "worsening" then
        color = c.trendWorsening
    else
        color = c.trendStable
    end

    -- Get translated text, fallback to English
    local text = getText(arrow.textKey) or arrow.fallback

    return {
        symbol = arrow.symbol,
        text = text,
        color = color,
    }
end

-- ============================================
-- BUG-012 FIX: Reset monitor state on death
-- ============================================

function EHR_MedicalMonitorUI:resetMonitor()
    -- Clear all cached data to prevent stale display
    self.cachedData = {
        blood = {},
        diseases = {},
        medications = {},
        sideEffects = {},
        doseStatuses = {},
        narcotics = {},
        withdrawal = nil,
        diseaseTrends = {},  -- Reset trend tracking on death
    }

    -- Reset animation phases to stop visual artifacts
    self.pulsePhase = 0
    self.flashPhase = 0

    -- Reset update timer
    self.lastUpdate = 0

    -- Hide the monitor immediately
    self:setVisible(false)

    EHR.Log("Medical Monitor: State reset (player death)")
end

function EHR_MedicalMonitorUI:prerender()
    ISPanel.prerender(self)

    local c = self.Colors

    -- Background
    self:drawRect(0, 0, self.width, self.height, c.background.a, c.background.r, c.background.g, c.background.b)

    -- Border
    self:drawRectBorder(0, 0, self.width, self.height, c.border.a, c.border.r, c.border.g, c.border.b)

    -- Header
    self:drawRect(0, 0, self.width, 30, c.headerBg.a, c.headerBg.r, c.headerBg.g, c.headerBg.b)
    self:drawRectBorder(0, 0, self.width, 30, c.border.a, c.border.r, c.border.g, c.border.b)

    -- Title (show examined player name if remote examination)
    local bloodType = "?"
    if self.cachedData.blood and self.cachedData.blood.bloodType then
        bloodType = self.cachedData.blood.bloodType
    end

    local titleText = getText("UI_EHR_MonitorTitle")
    if self.isRemoteExamination and self.targetPlayerName then
        titleText = string.format(getText("UI_EHR_Examining"), self.targetPlayerName)
    end

    local bloodTypeRight = self.width - 85
    local bloodTypeMinX = self.width - 145
    local titleMaxWidth = bloodTypeMinX - 18
    self:drawText(self:truncateText(titleText, titleMaxWidth, UIFont.Small), 10, 8, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    self:drawRightTextFit("[" .. bloodType .. "]", bloodTypeRight, 8, c.safe.r, c.safe.g, c.safe.b, c.safe.a, UIFont.Small, bloodTypeMinX)
end

function EHR_MedicalMonitorUI:render()
    ISPanel.render(self)

    if self.isExpanded then
        self:clampContentScroll()
        local clipTop = self.CONTENT_TOP
        local clipHeight = self:getContentClipHeight()
        local scrollY = self.contentScrollY or 0
        local y = clipTop - scrollY
        local contentStartY = y

        self:setStencilRect(0, clipTop, self.width, clipHeight)

        -- Full blood section is only for expanded view; compact has its own condensed block.
        y = self:renderBloodSection(y)

        -- Dose Alerts Section (urgent retakes shown first)
        y = self:renderDoseAlertsSection(y)

        -- N6C Narcotics Section (if any substances active)
        y = self:renderNarcoticsSection(y)

        -- Other Detected Substances Section (from universal scanner)
        y = self:renderOtherSubstancesSection(y)

        -- Diseases Section
        y = self:renderDiseasesSection(y)

        -- Medications Section
        y = self:renderMedicationsSection(y)

        -- Drug Interactions Section
        y = self:renderInteractionsSection(y)

        -- Side Effects Section
        y = self:renderSideEffectsSection(y)

        -- Healing Status Section
        y = self:renderHealingSection(y)

        -- Lifestyle Healing Bonuses Section (only shows if bonuses active)
        y = self:renderLifestyleBonusesSection(y)

        self.contentHeight = math.max(0, y - contentStartY)
        self:clearStencilRect()
        self:renderScrollBar()
        self:clampContentScroll()
    else
        -- Compact view
        self.contentScrollY = 0
        self.contentHeight = 0
        self:renderCompactView(self.CONTENT_TOP)
    end
end

-- ============================================
-- DOSE ALERTS SECTION (Expanded View)
-- ============================================

function EHR_MedicalMonitorUI:renderDoseAlertsSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    local doseStatuses = self.cachedData.doseStatuses or {}

    -- Filter for urgent alerts (overdue or due within 30 minutes)
    local urgentAlerts = {}
    for _, status in ipairs(doseStatuses) do
        if (status.isOverdue and not status.treatmentComplete)
            or (status.hoursUntilNextDose < 0.5 and not status.treatmentComplete) then
            table.insert(urgentAlerts, status)
        end
    end

    if #urgentAlerts == 0 then
        return y -- No alerts to show
    end

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_DoseAlerts"), padding, y + 2, c.warning.r, c.warning.g, c.warning.b, c.warning.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    for _, status in ipairs(urgentAlerts) do
        local alertColor = c.warning
        local alertText = ""
        local icon = "!"

        if status.isOverdue then
            alertColor = c.danger
            icon = "X"
            if status.hoursOverdue < 1 then
                alertText = string.format("%s - OVERDUE %.0fm!", status.medicationName, status.hoursOverdue * 60)
            else
                alertText = string.format("%s - OVERDUE %.1fh!", status.medicationName, status.hoursOverdue)
            end
            -- Flash effect
            local flash = (math.sin(self.flashPhase * 2) + 1) / 2
            alertColor = {
                r = c.danger.r * flash + c.warning.r * (1 - flash),
                g = c.danger.g * flash + c.warning.g * (1 - flash),
                b = c.danger.b * flash + c.warning.b * (1 - flash),
                a = 1
            }
        else
            alertText = string.format("%s - Due in %.0fm", status.medicationName, status.hoursUntilNextDose * 60)
        end

        local rightColumnX = self.width - 95
        local alertMaxWidth = rightColumnX - (padding + 10)
        self:drawText(icon .. " " .. self:truncateText(alertText, alertMaxWidth, UIFont.Small), padding + 5, y, alertColor.r, alertColor.g, alertColor.b, alertColor.a, UIFont.Small)

        -- Dose progress on right
        local doseProgress = string.format("[%d/%d]", status.doseCount, status.totalDosesNeeded)
        self:drawRightTextFit(doseProgress, self.width - padding, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, rightColumnX)

        y = y + self.LINE_HEIGHT
    end

    return y + 5
end

-- ============================================
-- BLOOD SECTION RENDERING
-- ============================================

function EHR_MedicalMonitorUI:renderBloodSection(startY)
    local c = self.Colors
    local y = startY
    local padding = 10
    local barHeight = 20
    local barWidth = self.width - (padding * 2)

    -- Section background
    self:drawRect(5, y, self.width - 10, 126, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)

    -- Section title
    self:drawText(getText("UI_EHR_BloodComposition"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + 32

    -- Get blood data (use stored values from EHR_Blood system)
    local blood = self.cachedData.blood or {}
    local currentVolume = blood.currentVolume or 5000
    local maxVolume = blood.maxVolume or 5000
    local transfusedBlood = blood.transfusedBlood or 0
    local transfusedSaline = blood.transfusedSaline or 0
    local salineRatio = blood.salineRatio or 0  -- Already calculated by EHR_Blood

    -- Calculate bar segments properly
    -- Total volume as percentage of max
    local totalPercent = math.min(1, currentVolume / maxVolume)

    -- Blood portion = current volume minus saline
    local actualBloodVolume = currentVolume - transfusedSaline
    local bloodBarPercent = math.max(0, actualBloodVolume / maxVolume)

    -- Saline portion
    local salineBarPercent = math.min(totalPercent - bloodBarPercent, transfusedSaline / maxVolume)

    -- Draw blood bar background (empty/missing blood)
    self:drawRect(padding, y, barWidth, barHeight, c.empty.a, c.empty.r, c.empty.g, c.empty.b)

    -- Draw blood portion (red)
    local bloodWidth = barWidth * bloodBarPercent
    if bloodWidth > 0 then
        self:drawRect(padding, y, bloodWidth, barHeight, c.blood.a, c.blood.r, c.blood.g, c.blood.b)
    end

    -- Draw saline portion (color based on ratio)
    if salineBarPercent > 0 then
        local salineColor = self:getSalineColor(salineRatio)
        local salineWidth = barWidth * salineBarPercent
        self:drawRect(padding + bloodWidth, y, salineWidth, barHeight,
            salineColor.a, salineColor.r, salineColor.g, salineColor.b)
    end

    -- Bar border
    self:drawRectBorder(padding, y, barWidth, barHeight, c.border.a, c.border.r, c.border.g, c.border.b)

    -- Pulse line effect (EKG style) - shows at the edge of current blood level
    local pulseY = y + barHeight / 2
    local pulseOffset = math.sin(self.pulsePhase) * 3
    local pulseX = padding + (barWidth * totalPercent) - 2
    if pulseX > padding and pulseX < padding + barWidth - 4 then
        self:drawRect(pulseX, pulseY + pulseOffset - 1, 4, 2, 1, 0.2, 1, 0.2)
    end

    y = y + barHeight + 8

    -- Blood stats text
    local bloodPercent = (actualBloodVolume / maxVolume) * 100
    local bloodText = string.format("Blood: %dmL (%.0f%%)", math.floor(actualBloodVolume), bloodPercent)
    local salinePercentDisplay = salineRatio * 100
    local salineText = string.format("Saline: %dmL (%.0f%%)", math.floor(transfusedSaline), salinePercentDisplay)

    self:drawText(self:truncateText(bloodText, self.width - padding * 2 - 90, UIFont.Small), padding, y, c.blood.r, c.blood.g, c.blood.b, c.blood.a, UIFont.Small)

    -- Saline status indicator
    local statusText, statusColor = self:getSalineStatus(salineRatio)
    self:drawRightTextFit(statusText, self.width - padding, y, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Small, padding + 240)
    y = y + self.LINE_HEIGHT

    local salineColor = self:getSalineColor(salineRatio)
    self:drawText(self:truncateText(salineText, self.width - padding * 2, UIFont.Small), padding, y, salineColor.r, salineColor.g, salineColor.b, salineColor.a, UIFont.Small)

    return y + 28
end

function EHR_MedicalMonitorUI:getSalineColor(ratio)
    local c = self.Colors
    if ratio >= 0.60 then
        -- Flashing effect for lethal
        local flash = (math.sin(self.flashPhase) + 1) / 2
        return {
            r = c.salineLethal.r * flash + 0.3 * (1 - flash),
            g = c.salineLethal.g * flash,
            b = c.salineLethal.b * flash,
            a = 1
        }
    elseif ratio >= 0.50 then
        return c.salineDanger
    elseif ratio >= 0.40 then
        return c.salineWarning
    else
        return c.salineSafe
    end
end

function EHR_MedicalMonitorUI:getSalineStatus(ratio)
    local c = self.Colors
    if ratio >= 0.60 then
        return getText("UI_EHR_SalineStatus_Lethal"), c.critical
    elseif ratio >= 0.50 then
        return getText("UI_EHR_SalineStatus_Danger"), c.danger
    elseif ratio >= 0.40 then
        return getText("UI_EHR_SalineStatus_Warning"), c.warning
    else
        return getText("UI_EHR_SalineStatus_Safe"), c.safe
    end
end

-- ============================================
-- N&C NARCOTICS SECTION RENDERING
-- ============================================

function EHR_MedicalMonitorUI:renderNarcoticsSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    local substances = self.cachedData.narcotics or {}
    local withdrawal = self.cachedData.withdrawal

    -- Skip section if no active substances and no withdrawal
    if #substances == 0 and not withdrawal then
        return y - 5 -- Return early, no section to render
    end

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_ActiveSubstances"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    -- Render withdrawal warning first if present
    if withdrawal then
        local wdColor = c.withdrawal
        -- Flash effect for withdrawal
        local flash = (math.sin(self.flashPhase) + 1) / 2
        wdColor = {
            r = c.withdrawal.r * flash + 0.4 * (1 - flash),
            g = c.withdrawal.g * flash + 0.1 * (1 - flash),
            b = c.withdrawal.b * flash + 0.1 * (1 - flash),
            a = 1
        }
        local wdText = "! WITHDRAWAL: " .. withdrawal.drugName
        local wdMaxWidth = self.width - padding * 2
        if withdrawal.blocksHealing then
            wdMaxWidth = wdMaxWidth - 125
        end
        self:drawText(self:truncateText(wdText, wdMaxWidth, UIFont.Small), padding + 5, y, wdColor.r, wdColor.g, wdColor.b, wdColor.a, UIFont.Small)
        if withdrawal.blocksHealing then
            self:drawRightTextFit("[Blocks Healing]", self.width - padding, y, c.danger.r, c.danger.g, c.danger.b, c.danger.a, UIFont.Small, self.width - 130)
        end
        y = y + self.LINE_HEIGHT
    end

    -- Render each active substance
    for _, substance in ipairs(substances) do
        y = self:renderSubstanceEntry(y, substance)
        if not self.isExpanded and y > self.height - 100 then break end -- Prevent overflow
    end

    return y + 5
end

-- ============================================
-- OTHER DETECTED SUBSTANCES SECTION (v2.8.0)
-- Shows substances from mods other than N6C
-- ============================================

function EHR_MedicalMonitorUI:renderOtherSubstancesSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    local substances = self.cachedData.otherSubstances or {}

    -- Skip section if no substances detected
    if #substances == 0 then
        return y - 5
    end

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_OtherSubstances") or "OTHER DETECTED SUBSTANCES", padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    -- Render each detected substance
    for _, substance in ipairs(substances) do
        -- Get color based on category
        local substanceColor = c.textDim  -- default gray
        if substance.category == "stimulant" then
            substanceColor = c.stimulant
        elseif substance.category == "opioid" then
            substanceColor = c.opioid
        elseif substance.category == "depressant" then
            substanceColor = c.depressant
        elseif substance.category == "cannabis" then
            substanceColor = c.cannabis
        end

        -- Substance name
        local displayText = substance.displayName
        local valueText = EHR.SubstanceScanner.FormatValue(substance)
        local valueColumnX = self.width - 110
        self:drawText(self:truncateText(displayText, valueColumnX - (padding + 10), UIFont.Small), padding + 5, y, substanceColor.r, substanceColor.g, substanceColor.b, substanceColor.a, UIFont.Small)

        -- Value on right
        self:drawRightTextFit(valueText, self.width - padding, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small, valueColumnX)

        y = y + self.LINE_HEIGHT
        if not self.isExpanded and y > self.height - 100 then break end -- Prevent overflow
    end

    return y + 5
end

function EHR_MedicalMonitorUI:renderSubstanceEntry(startY, substance)
    local c = self.Colors
    local y = startY
    local padding = 15

    -- Get color based on substance category
    local substanceColor = c.stimulant -- default
    if substance.color == "critical" then
        substanceColor = c.critical
    elseif substance.color == "stimulant" then
        substanceColor = c.stimulant
    elseif substance.color == "opioid" then
        substanceColor = c.opioid
    elseif substance.color == "depressant" then
        substanceColor = c.depressant
    elseif substance.color == "cannabis" then
        substanceColor = c.cannabis
    end

    -- Flash effect for overdose
    if substance.isOverdose then
        local flash = (math.sin(self.flashPhase * 2) + 1) / 2
        substanceColor = {
            r = c.critical.r * flash + substanceColor.r * (1 - flash),
            g = c.critical.g * flash + substanceColor.g * (1 - flash),
            b = c.critical.b * flash + substanceColor.b * (1 - flash),
            a = 1
        }
    end

    -- Substance name
    local statusColumnX = self.width - 115
    self:drawText(self:truncateText(substance.name, statusColumnX - padding - 5, UIFont.Small), padding, y, substanceColor.r, substanceColor.g, substanceColor.b, substanceColor.a, UIFont.Small)

    -- Status on right
    local statusColor = substanceColor
    if substance.isOverdose then
        statusColor = c.critical
    end
    self:drawRightTextFit(substance.status, self.width - padding, y, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Small, statusColumnX)
    y = y + self.LINE_HEIGHT
    -- Intensity bar
    local barWidth = 120
    local barHeight = 6
    self:drawRect(padding + 5, y, barWidth, barHeight, c.empty.a, c.empty.r, c.empty.g, c.empty.b)
    self:drawRect(padding + 5, y, barWidth * substance.intensity, barHeight,
        substanceColor.a, substanceColor.r, substanceColor.g, substanceColor.b)
    self:drawRectBorder(padding + 5, y, barWidth, barHeight, c.border.a, c.border.r, c.border.g, c.border.b)

    -- Effect level text
    local effectText = string.format("%.0f", substance.effectLevel)
    self:drawText(effectText, padding + barWidth + 15, y - 2, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)

    return y + 12
end

-- ============================================
-- DISEASES SECTION RENDERING
-- ============================================

function EHR_MedicalMonitorUI:renderDiseasesSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    local diseases = self.cachedData.diseases or {}
    local diseaseCount = 0
    for _ in pairs(diseases) do diseaseCount = diseaseCount + 1 end

    -- Count temperature warnings
    local tempWarnings = self.cachedData.temperatureWarnings or {}
    local tempWarningCount = #tempWarnings
    local corpseExposureLevel = nil
    if EHR.CorpseSickness and EHR.CorpseSickness.GetExposureDisplay then
        corpseExposureLevel = EHR.CorpseSickness.GetExposureDisplay(self.player)
        if corpseExposureLevel == "None" then
            corpseExposureLevel = nil
        end
    end

    local totalConditions = diseaseCount + tempWarningCount + (corpseExposureLevel and 1 or 0)

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_ActiveConditions"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    self:drawRightTextFit("[" .. totalConditions .. " Active]", self.width - padding, y + 2, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, self.width - 120)
    y = y + self.SECTION_HEADER_HEIGHT

    -- Render temperature warnings FIRST (they're urgent)
    for _, warning in ipairs(tempWarnings) do
        y = self:renderTemperatureWarning(y, warning)
        if not self.isExpanded and y > self.height - 100 then break end
    end

    if corpseExposureLevel then
        y = self:renderCorpseExposureSection(y, corpseExposureLevel)
    end

    if diseaseCount == 0 and tempWarningCount == 0 and not corpseExposureLevel then
        self:drawText(getText("UI_EHR_NoConditions"), padding + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, UIFont.Small)
        return y + 20
    end

    -- Render each disease
    for diseaseId, diseaseData in pairs(diseases) do
        y = self:renderDiseaseEntry(y, diseaseId, diseaseData)
        if not self.isExpanded and y > self.height - 100 then break end -- Prevent overflow
    end

    return y + 5
end

function EHR_MedicalMonitorUI:renderCorpseExposureSection(startY, level)
    if not level or level == "None" then return startY end

    local y = startY
    local c = self.Colors
    local padding = 10
    local label = (getText and getText("UI_EHR_CorpseExposure")) or "Corpse Exposure"
    local color = {1, 1, 1}
    if EHR.CorpseSickness and EHR.CorpseSickness.GetExposureColor then
        color = EHR.CorpseSickness.GetExposureColor(level) or color
    end

    self:drawText(label .. ":", padding, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + 16
    self:drawText("  " .. level, padding + 10, y, color[1], color[2], color[3], 1, UIFont.Small)
    y = y + 18

    return y
end

--[[
    Get player's medical skill tier for disease identification
    Returns: tier (0-4), skillLevel (0-10)

    Tiers:
    0 = Clueless (Level 0-1): "Unknown Condition"
    1 = Novice (Level 2-3): Disease name + severity
    2 = Intermediate (Level 4-5): + Symptoms
    3 = Expert (Level 6-7): + Progress + treatment status
    4 = Master (Level 8+): Full details + future treatment hints
]]--
function EHR_MedicalMonitorUI:getMedicalSkillTier(ignoreDebugBypass)
    -- Debug mode bypasses skill checks - show everything in UI panels
    -- But NOT for dialogue (ignoreDebugBypass = true) to maintain immersion
    if not ignoreDebugBypass and EHR.IsDebugMode and EHR.IsDebugMode() then
        return 4, 10  -- Master tier
    end

    local skillLevel = 0
    if self.player and Perks and Perks.Doctor then
        skillLevel = self.player:getPerkLevel(Perks.Doctor) or 0
    end

    local tier = 0
    if skillLevel >= 8 then
        tier = 4  -- Master
    elseif skillLevel >= 6 then
        tier = 3  -- Expert
    elseif skillLevel >= 4 then
        tier = 2  -- Intermediate
    elseif skillLevel >= 2 then
        tier = 1  -- Novice (Doctors/Nurses start here)
    else
        tier = 0  -- Clueless
    end

    return tier, skillLevel
end

function EHR_MedicalMonitorUI:renderDiseaseEntry(startY, diseaseId, diseaseData)
    local c = self.Colors
    local y = startY
    local padding = 15

    -- Get disease definition
    local diseaseDef = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId]
    local severity = diseaseData.severity or 1
    local progress = diseaseData.progress or 0

    -- Special handling for non-standard conditions (Sepsis, Knox, Wound Infection)
    -- Note: getText() returns the key itself if not found, so we check for that
    if diseaseData.isWoundInfection then
        local partCount = diseaseData.infectedCount or 1
        local partText = partCount > 1 and (" (" .. partCount .. " wounds)") or ""
        local woundName = getText("UI_EHR_WoundInfection")
        if not woundName or woundName == "UI_EHR_WoundInfection" then woundName = "Wound Infection" end
        diseaseDef = {
            name = woundName .. partText,
            symptoms = {"Pain", "Swelling", "Redness", "Fever"},
        }
    elseif diseaseData.isSepsis then
        local sepsisName = getText("UI_EHR_Sepsis")
        if not sepsisName or sepsisName == "UI_EHR_Sepsis" then sepsisName = "Sepsis" end
        diseaseDef = {
            name = sepsisName,
            symptoms = {"Fever", "Rapid heartbeat", "Confusion", "Extreme pain"},
        }
    elseif diseaseData.isKnox then
        local knoxName = getText("UI_EHR_KnoxInfection")
        if not knoxName or knoxName == "UI_EHR_KnoxInfection" then knoxName = "Knox Infection" end
        diseaseDef = {
            name = knoxName,
            symptoms = {"Fever", "Nausea", "Weakness", "Pale skin"},
        }
    end

    -- Get player's medical skill tier (bypass debug mode for proper skill checks)
    local skillTier, skillLevel = self:getMedicalSkillTier(true)

    -- Determine what to display based on skill tier and flyer knowledge
    local displayName
    local showSeverity = false
    local showSymptoms = false
    local showProgress = false
    local showTreatmentStatus = false
    local canIdentify = true
    local unknownInfo = nil

    if skillTier >= 4 then
        canIdentify = true
    elseif EHR.DiseaseFlyers and EHR.DiseaseFlyers.CanIdentifyDisease then
        canIdentify = EHR.DiseaseFlyers.CanIdentifyDisease(self.player, diseaseId)
        if not canIdentify and EHR.DiseaseFlyers.GetUnknownDiseaseDisplay then
            unknownInfo = EHR.DiseaseFlyers.GetUnknownDiseaseDisplay(diseaseId)
        end
    end

    if not canIdentify then
        displayName = (unknownInfo and unknownInfo.displayName) or (getText("UI_EHR_DiseaseUnknown") or "Unknown Illness")
    else
        displayName = diseaseDef and diseaseDef.name or diseaseId
        if skillTier >= 1 then
            showSeverity = true
        end
        if skillTier >= 2 then
            showSymptoms = true
        end
        if skillTier >= 3 then
            showProgress = true
            showTreatmentStatus = true
        end
    end

    -- Disease name first, details below it. This avoids overlap with long condition names.
    local severityColor = self:getSeverityColor(severity)
    local severityBar = self:getSeverityBar(severity)

    self:drawText(self:truncateText(displayName, self.width - padding * 2, UIFont.Small), padding, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.LINE_HEIGHT

    if showSeverity then
        self:drawText(getText("UI_EHR_Severity") .. severityBar .. " " .. severity .. "/5", padding + 5, y,
            severityColor.r, severityColor.g, severityColor.b, severityColor.a, UIFont.Small)
    else
        -- Show vague indicator for clueless players
        self:drawText(getText("UI_EHR_UnknownSeverity") or "Severity: ???", padding + 5, y,
            c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    end
    y = y + self.LINE_HEIGHT
    -- TREND ARROW: Always visible, even at Tier 0 skill (v2.8.0)
    -- Allows players to tell if they're getting better or worse
    local trendDisplay = self:getTrendDisplay(diseaseId)
    if trendDisplay then
        local trendText = trendDisplay.symbol .. " " .. trendDisplay.text
        self:drawText(trendText, padding + 5, y,
            trendDisplay.color.r, trendDisplay.color.g, trendDisplay.color.b, trendDisplay.color.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end

    -- Unknown disease description (flyer-gated)
    if not canIdentify then
        local descText = unknownInfo and unknownInfo.description or (getText("UI_EHR_SomethingWrong") or "Something feels wrong...")
        self:drawText(descText, padding + 5, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
        local requiresText = getText("UI_EHR_DiseaseRequiresFlyer") or "(Read the disease flyer to identify)"
        self:drawText(requiresText, padding + 5, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end

    -- Symptoms (visible only when identified and disease has symptoms defined)
    if showSymptoms and diseaseDef and diseaseDef.symptoms then
        local symptomText = getText("UI_EHR_Symptoms") or "Symptoms: "
        symptomText = symptomText .. table.concat(diseaseDef.symptoms, ", ")
        -- Word-wrap symptoms across multiple lines
        local maxWidth = self.width - padding - 25
        local charsPerLine = math.floor(maxWidth / 6)

        -- Draw first part with label
        if #symptomText <= charsPerLine then
            self:drawText(symptomText, padding + 5, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
            y = y + self.LINE_HEIGHT
        else
            -- Split into lines at commas
            local remaining = symptomText
            local isFirstLine = true
            while #remaining > 0 do
                local line = remaining:sub(1, charsPerLine)
                if #remaining > charsPerLine then
                    local lastComma = line:match(".*,")
                    if lastComma then line = lastComma end
                end
                local xPos = isFirstLine and (padding + 5) or (padding + 10)
                self:drawText(line, xPos, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
                y = y + self.LINE_HEIGHT
                remaining = remaining:sub(#line + 1):gsub("^%s+", "")
                isFirstLine = false
            end
        end
    end

    -- Progress (Tier 3+ ONLY - Expert medical skill required)
    if showProgress then
        local statusColumnX = self.width - 170
        local progressText = string.format("%.0f%%", progress * 100)
        self:drawText(progressText, padding + 5, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)

        -- Treatment status (Tier 3+)
        if showTreatmentStatus then
            local treatmentStatus = diseaseData.treating and "TREATING" or "UNTREATED"
            local statusColor = diseaseData.treating and c.safe or c.danger
            self:drawRightTextFit(treatmentStatus, self.width - padding, y, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Small, statusColumnX)
        end
        y = y + self.LINE_HEIGHT

        local barWidth = self.width - padding * 2 - 10
        local barHeight = 7
        self:drawRect(padding + 5, y + 2, barWidth, barHeight, c.empty.a, c.empty.r, c.empty.g, c.empty.b)
        self:drawRect(padding + 5, y + 2, barWidth * progress, barHeight,
            severityColor.a, severityColor.r, severityColor.g, severityColor.b)
        self:drawRectBorder(padding + 5, y + 2, barWidth, barHeight, c.border.a, c.border.r, c.border.g, c.border.b)
        y = y + 16
    end
    return y + 8
end

--[[
    Render a temperature warning entry
]]--
function EHR_MedicalMonitorUI:renderTemperatureWarning(startY, warning)
    local c = self.Colors
    local y = startY
    local padding = 15

    -- Severity colors
    local severityColors = {
        [1] = c.severity1,  -- Green-ish
        [2] = c.severity2,  -- Yellow
        [3] = c.severity3,  -- Orange
        [4] = c.severity4,  -- Red
    }
    local sevColor = severityColors[warning.severity] or c.text

    -- Icon based on type (ASCII for font compatibility)
    local icon = warning.type == "cold" and "[COLD]" or "[HOT]"

    -- Draw warning name with icon
    local displayText = icon .. " " .. warning.name
    local tempColumnX = self.width - 95
    self:drawText(self:truncateText(displayText, tempColumnX - padding - 5, UIFont.Small), padding, y, sevColor.r, sevColor.g, sevColor.b, sevColor.a, UIFont.Small)

    -- Draw body temperature on the right
    local tempText = string.format("%.1f C", warning.bodyTemp)
    self:drawRightTextFit(tempText, self.width - padding, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, tempColumnX)
    y = y + self.LINE_HEIGHT

    -- Draw description
    self:drawText(self:truncateText("  " .. warning.description, self.width - padding * 2, UIFont.Small), padding, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    y = y + self.LINE_HEIGHT
    -- If at danger stage (4), show time in danger zone
    if warning.stage >= 4 and warning.dangerTime and warning.dangerTime > 0 then
        local dangerText = string.format("  In danger zone: %.1f min", warning.dangerTime * 60)
        self:drawText(dangerText, padding, y, c.critical.r, c.critical.g, c.critical.b, c.critical.a, UIFont.Small)
        y = y + 16
    end

    return y + 2
end

function EHR_MedicalMonitorUI:getSeverityColor(severity)
    local c = self.Colors
    if severity >= 5 then return c.severity5
    elseif severity >= 4 then return c.severity4
    elseif severity >= 3 then return c.severity3
    elseif severity >= 2 then return c.severity2
    else return c.severity1 end
end

function EHR_MedicalMonitorUI:getSeverityBar(severity)
    -- Use ASCII characters for font compatibility (Unicode block chars show as "?")
    local filled = string.rep("#", severity)
    local empty = string.rep("-", 5 - severity)
    return filled .. empty
end

-- ============================================
-- MEDICATIONS SECTION RENDERING
-- ============================================

function EHR_MedicalMonitorUI:renderMedicationsSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    -- Get treatments (disease-based) and dose statuses (all active meds)
    local treatments = self.cachedData.medications or {}
    local doseStatuses = self.cachedData.doseStatuses or {}

    -- Build combined medication list
    -- First, add all treatments (disease-based)
    local displayedMeds = {}
    local seenMedKeys = {}

    for _, treatment in ipairs(treatments) do
        table.insert(displayedMeds, {
            medicationName = treatment.medicationName,
            medKey = treatment.medKey,
            tier = treatment.tier,
            hoursRemaining = treatment.hoursRemaining,
            progress = treatment.progress,
            doseCount = treatment.doseCount,
            totalDosesNeeded = treatment.totalDosesNeeded,
            hoursUntilNextDose = treatment.hoursUntilNextDose,
            isDoseActive = treatment.isDoseActive,
            hoursActiveRemaining = treatment.hoursActiveRemaining,
            isOverdue = treatment.isOverdue,
            hoursOverdue = treatment.hoursOverdue,
            isTreatingDisease = true,
        })
        seenMedKeys[treatment.medicationName] = true
    end

    -- Then add dose-only entries (meds taken without disease)
    for _, doseStatus in ipairs(doseStatuses) do
        if not seenMedKeys[doseStatus.medicationName] and (doseStatus.isDoseActive or not doseStatus.treatmentComplete) then
            table.insert(displayedMeds, {
                medicationName = doseStatus.medicationName,
                medKey = doseStatus.medKey,
                tier = doseStatus.tier,
                hoursRemaining = 0, -- No cure timer for symptom relief
                progress = doseStatus.doseCount / doseStatus.totalDosesNeeded,
                doseCount = doseStatus.doseCount,
                totalDosesNeeded = doseStatus.totalDosesNeeded,
                hoursUntilNextDose = doseStatus.hoursUntilNextDose,
                isDoseActive = doseStatus.isDoseActive,
                hoursActiveRemaining = doseStatus.hoursActiveRemaining,
                isOverdue = doseStatus.isOverdue,
                hoursOverdue = doseStatus.hoursOverdue,
                isTreatingDisease = false, -- Symptom relief only
            })
            seenMedKeys[doseStatus.medicationName] = true
        end
    end

    local medCount = #displayedMeds

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_ActiveMedications"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    self:drawRightTextFit("[" .. medCount .. " Active]", self.width - padding, y + 2, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, self.width - 120)
    y = y + self.SECTION_HEADER_HEIGHT

    if medCount == 0 then
        self:drawText(getText("UI_EHR_NoMedications"), padding + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        return y + 20
    end

    -- Render each medication
    for _, medData in ipairs(displayedMeds) do
        y = self:renderMedicationEntry(y, medData)
        if not self.isExpanded and y > self.height - 80 then break end
    end

    return y + 5
end

function EHR_MedicalMonitorUI:renderMedicationEntry(startY, medData)
    local c = self.Colors
    local y = startY
    local padding = 15

    -- Get translated medication name
    local displayName = medData.medicationName or "Unknown"
    if EHR.Medication and EHR.Medication.GetDisplayName and medData.medKey then
        displayName = EHR.Medication.GetDisplayName(medData.medKey)
    elseif getText then
        -- Try to find translation by converting displayName to key
        local keyName = displayName:gsub("[%s%-%&%(%)]", ""):gsub("%.", "")
        local autoKey = "UI_EHR_Med_" .. keyName
        local translated = getText(autoKey)
        if translated and translated ~= autoKey then
            displayName = translated
        end
    end
    local tier = medData.tier or 0
    local hoursRemaining = medData.hoursRemaining or 0
    local progress = medData.progress or 0
    local isTreatingDisease = medData.isTreatingDisease

    -- Dose tracking info
    local doseCount = medData.doseCount or 0
    local totalDoses = medData.totalDosesNeeded or 0
    local hoursUntilNextDose = medData.hoursUntilNextDose or 0
    local isDoseActive = medData.isDoseActive or false
    local hoursActiveRemaining = medData.hoursActiveRemaining or 0
    local isOverdue = medData.isOverdue or false
    local hoursOverdue = medData.hoursOverdue or 0

    -- Medication name and tier
    local tierName = self:getTierName(tier)
    local titleText = displayName .. " (" .. tierName .. ")"
    local titleMaxWidth = self.width - padding * 2
    if totalDoses > 0 then
        titleMaxWidth = titleMaxWidth - 95
    end
    self:drawText(self:truncateText(titleText, titleMaxWidth, UIFont.Small), padding, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)

    -- Dose count on right side
    if totalDoses > 0 then
        local doseText = string.format("Dose %d/%d", doseCount, totalDoses)
        local doseMinX = self.width - 110
        local doseMaxWidth = (self.width - padding) - doseMinX
        if self:getTextWidth(doseText, UIFont.Small) > doseMaxWidth then
            doseText = string.format("%d/%d", doseCount, totalDoses)
        end
        self:drawRightTextFit(doseText, self.width - padding, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, doseMinX)
    end
    y = y + self.LINE_HEIGHT
    -- Treatment progress (only for disease treatment, not symptom relief)
    if isTreatingDisease and hoursRemaining > 0 then
        local timeText = string.format("%.1fh left", hoursRemaining)
        self:drawText(timeText, padding + 5, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
        y = y + self.SMALL_LINE_HEIGHT

        local barWidth = self.width - padding * 2 - 10
        local barHeight = 7
        self:drawRect(padding + 5, y + 2, barWidth, barHeight, c.empty.a, c.empty.r, c.empty.g, c.empty.b)
        self:drawRect(padding + 5, y + 2, barWidth * progress, barHeight, c.safe.a, c.safe.r, c.safe.g, c.safe.b)
        self:drawRectBorder(padding + 5, y + 2, barWidth, barHeight, c.border.a, c.border.r, c.border.g, c.border.b)
        y = y + 16
    else
        -- Symptom relief only - show status text
        local reliefText = getText("UI_EHR_SymptomRelief")
        if isDoseActive and hoursActiveRemaining > 0 then
            reliefText = string.format("Symptom relief: %.1fh left", hoursActiveRemaining)
        end
        self:drawText(reliefText, padding + 5, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end
    -- Next dose timer / Retake indicator
    if totalDoses > 0 and doseCount < totalDoses then
        local retakeColor = c.safe
        local retakeText = ""

        if isOverdue then
            -- Overdue - show warning
            retakeColor = c.danger
            if hoursOverdue < 1 then
                retakeText = string.format("RETAKE NOW! (%.0fm overdue)", hoursOverdue * 60)
            else
                retakeText = string.format("RETAKE NOW! (%.1fh overdue)", hoursOverdue)
            end
            -- Flash effect for urgency
            local flash = (math.sin(self.flashPhase * 2) + 1) / 2
            retakeColor = {
                r = c.danger.r * flash + c.warning.r * (1 - flash),
                g = c.danger.g * flash + c.warning.g * (1 - flash),
                b = c.danger.b * flash + c.warning.b * (1 - flash),
                a = 1
            }
        elseif hoursUntilNextDose < 0.5 then
            -- Almost time
            retakeColor = c.warning
            retakeText = string.format("Retake in %.0fm", hoursUntilNextDose * 60)
        else
            -- On schedule
            retakeText = string.format("Next dose in %.1fh", hoursUntilNextDose)
        end

        self:drawText(retakeText, padding + 10, y, retakeColor.r, retakeColor.g, retakeColor.b, retakeColor.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end

    return y + 4
end

function EHR_MedicalMonitorUI:getTierName(tier)
    if tier == 0 then return "Basic"
    elseif tier == 1 then return "OTC"
    elseif tier == 2 then return "Rx"
    elseif tier == 3 then return "Clinical"
    else return "Unknown" end
end

-- ============================================
-- DRUG INTERACTIONS SECTION
-- ============================================

function EHR_MedicalMonitorUI:renderInteractionsSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    -- Get interactions
    local interactions = self:checkDrugInteractions()

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_DrugInteractions"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    if #interactions == 0 then
        self:drawText(getText("UI_EHR_NoInteractions"), padding + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, UIFont.Small)
        return y + 20
    end

    for _, interaction in ipairs(interactions) do
        local icon = interaction.severity == "danger" and "X" or "!"
        local color = interaction.severity == "danger" and c.danger or c.warning

        self:drawText(icon .. " " .. interaction.message, padding + 5, y, color.r, color.g, color.b, color.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end

    return y + 5
end

function EHR_MedicalMonitorUI:checkDrugInteractions()
    -- Use the medication system's drug interaction checker
    if EHR.Medication and EHR.Medication.CheckDrugInteractions then
        return EHR.Medication.CheckDrugInteractions(self.player)
    end

    -- Fallback to basic check if system not loaded
    local interactions = {}
    local medications = self.cachedData.medications or {}

    local hasTier3Count = 0
    for _, med in ipairs(medications) do
        if med.tier == 3 then hasTier3Count = hasTier3Count + 1 end
    end

    if hasTier3Count >= 2 then
        table.insert(interactions, {
            severity = "warning",
            message = "Multiple Tier 3 meds: Side effects may stack"
        })
    end

    return interactions
end

-- ============================================
-- SIDE EFFECTS SECTION
-- ============================================

function EHR_MedicalMonitorUI:renderSideEffectsSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    local sideEffects = self.cachedData.sideEffects or {}

    if #sideEffects == 0 then
        return y -- Don't render section if no side effects
    end

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_SideEffects"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    for _, effect in ipairs(sideEffects) do
        -- Get translated side effect name
        local displayName = effect.displayName or effect.effectId
        if EHR.Medication and EHR.Medication.GetSideEffectDisplayName and effect.effectId then
            displayName = EHR.Medication.GetSideEffectDisplayName(effect.effectId)
        elseif getText and effect.effectId then
            -- Try the side effect translation key (UI_SideEffect_Nausea, etc.)
            local key = "UI_SideEffect_" .. effect.effectId:gsub("^%l", string.upper):gsub("_(%l)", function(c) return c:upper() end)
            local translated = getText(key)
            if translated and translated ~= key then
                displayName = translated
            end
        end
        local hoursLeft = effect.hoursRemaining or 0

        self:drawText(self:truncateText(displayName, self.width - padding * 2 - 70, UIFont.Small), padding + 10, y, c.warning.r, c.warning.g, c.warning.b, c.warning.a, UIFont.Small)
        self:drawRightTextFit(string.format("%.1fh", hoursLeft), self.width - padding, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, self.width - 80)
        y = y + self.LINE_HEIGHT
    end

    return y + 5
end

-- ============================================
-- HEALING STATUS SECTION
-- ============================================

function EHR_MedicalMonitorUI:renderHealingSection(startY)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    -- Section header
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_HealingStatus"), padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    local blood = self.cachedData.blood or {}
    local canHeal = blood.canHeal
    local blockReason = blood.healBlockReason or "unknown"

    if canHeal then
        self:drawText(getText("UI_EHR_HealingActive"), padding + 10, y, c.safe.r, c.safe.g, c.safe.b, c.safe.a, UIFont.Small)
    else
        self:drawText(getText("UI_EHR_HealingBlocked"), padding + 10, y, c.danger.r, c.danger.g, c.danger.b, c.danger.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
        self:drawText(getText("UI_EHR_Reason") .. blockReason, padding + 15, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    end

    return y + 20
end

-- ============================================
-- LIFESTYLE HEALING BONUSES SECTION (v2.8.0)
-- ============================================

function EHR_MedicalMonitorUI:renderLifestyleBonusesSection(startY)
    -- Only render if Lifestyle mod is loaded
    if not EHR.LifestyleCompat or not EHR.LifestyleCompat.IsModLoaded() then
        return startY
    end

    local bonusDetails = EHR.LifestyleCompat.GetBonusDetails(self.player)
    local c = self.Colors
    local y = startY + 5
    local padding = 10

    -- Section header - always show when Lifestyle is detected
    self:drawRect(5, y, self.width - 10, self.SECTION_HEADER_HEIGHT, c.sectionBg.a, c.sectionBg.r, c.sectionBg.g, c.sectionBg.b)
    self:drawText(getText("UI_EHR_HealingBonuses") or "LIFESTYLE BONUSES", padding, y + 2, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    y = y + self.SECTION_HEADER_HEIGHT

    -- If no bonuses active, show hint
    if not bonusDetails.isActive then
        local hintText = getText("UI_EHR_NoBonuses") or "Take a bath or rest comfortably for healing bonuses"
        self:drawText(hintText, padding + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        return y + 20
    end

    -- Show all individual bonuses from details array
    for _, detail in ipairs(bonusDetails.details) do
        local bonusColor = detail.bonus >= 0 and c.trendImproving or c.danger
        local sign = detail.bonus >= 0 and "+" or ""
        local bonusText = string.format("%s: %s%d%%", detail.name, sign, math.floor(detail.bonus * 100))

        -- Add time remaining for bath bonus
        if detail.name == "Recent Bath" and bonusDetails.bathTimeLeft > 0 then
            bonusText = bonusText .. string.format(" (%.1fh)", bonusDetails.bathTimeLeft)
        end

        self:drawText(bonusText, padding + 10, y, bonusColor.r, bonusColor.g, bonusColor.b, bonusColor.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end

    -- Total bonus/penalty
    local totalColor = bonusDetails.totalBonus >= 0 and c.safe or c.danger
    local totalSign = bonusDetails.totalBonus >= 0 and "+" or ""
    local totalText = string.format("%s %s%d%%", getText("UI_EHR_TotalBonus") or "Total:", totalSign, math.floor(bonusDetails.totalBonus * 100))
    self:drawText(totalText, padding + 10, y, totalColor.r, totalColor.g, totalColor.b, totalColor.a, UIFont.Small)
    y = y + self.LINE_HEIGHT

    -- Note about supported diseases
    local noteText = getText("UI_EHR_BonusNote") or "(Affects disease recovery speed)"
    self:drawText(noteText, padding + 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)

    return y + 20
end

-- ============================================
-- COMPACT VIEW
-- ============================================

function EHR_MedicalMonitorUI:renderCompactView(startY)
    local c = self.Colors
    local y = startY
    local padding = 10
    local contentRight = self.width - padding

    -- Compact blood bar
    local barWidth = self.width - padding * 2
    local barHeight = 14

    local blood = self.cachedData.blood or {}
    local currentVolume = blood.currentVolume or 5000
    local maxVolume = blood.maxVolume or 5000
    local transfusedSaline = blood.transfusedSaline or 0
    local salineRatio = blood.salineRatio or 0
    local safeMaxVolume = maxVolume > 0 and maxVolume or 5000

    local bloodPercent = math.max(0, math.min(1, (currentVolume - transfusedSaline) / safeMaxVolume))
    local salinePercent = math.max(0, math.min(1 - bloodPercent, transfusedSaline / safeMaxVolume))

    -- Draw bar
    self:drawRect(padding, y, barWidth, barHeight, c.empty.a, c.empty.r, c.empty.g, c.empty.b)
    if bloodPercent > 0 then
        self:drawRect(padding, y, barWidth * bloodPercent, barHeight, c.blood.a, c.blood.r, c.blood.g, c.blood.b)
    end

    if salinePercent > 0 then
        local salineColor = self:getSalineColor(salineRatio)
        self:drawRect(padding + barWidth * bloodPercent, y, barWidth * salinePercent, barHeight,
            salineColor.a, salineColor.r, salineColor.g, salineColor.b)
    end

    self:drawRectBorder(padding, y, barWidth, barHeight, c.border.a, c.border.r, c.border.g, c.border.b)
    y = y + barHeight + 8

    -- Quick blood stats
    local bloodText = string.format("%.0f%% Blood", bloodPercent * 100)
    local salineText = string.format("%.0f%% Saline", salineRatio * 100)
    self:drawText(bloodText, padding, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    self:drawRightTextFit(salineText, contentRight, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, padding + 150)
    y = y + self.LINE_HEIGHT

    -- Condition and medication counts
    local diseaseCount = 0
    for _ in pairs(self.cachedData.diseases or {}) do diseaseCount = diseaseCount + 1 end

    local treatments = self.cachedData.medications or {}
    local doseStatuses = self.cachedData.doseStatuses or {}
    local seenMeds = {}
    local medCount = 0
    for _, t in ipairs(treatments) do
        if t.medicationName then seenMeds[t.medicationName] = true end
        medCount = medCount + 1
    end
    for _, d in ipairs(doseStatuses) do
        if d.medicationName and not seenMeds[d.medicationName] and (d.isDoseActive or not d.treatmentComplete) then
            medCount = medCount + 1
        end
    end

    self:drawText(diseaseCount .. " Conditions", padding, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    self:drawRightTextFit(medCount .. " Meds", contentRight, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small, padding + 150)
    y = y + self.LINE_HEIGHT

    -- One compact warning line, only if something needs attention.
    local warningText = nil
    local warningColor = c.warning
    local overdueCount = 0
    local firstOverdue = nil
    for _, status in ipairs(doseStatuses) do
        if status.isOverdue and not status.treatmentComplete then
            overdueCount = overdueCount + 1
            if not firstOverdue then firstOverdue = status end
        end
    end

    if overdueCount > 0 then
        warningColor = c.danger
        if overdueCount == 1 then
            warningText = "X " .. self:truncateText(firstOverdue.medicationName or "?", 140, UIFont.Small) .. " OVERDUE!"
        else
            warningText = "X " .. overdueCount .. " meds OVERDUE!"
        end
    else
        local interactions = self:checkDrugInteractions()
        if #interactions > 0 then
            warningText = string.format("! %d Drug Interactions", #interactions)
        else
            local narcotics = self.cachedData.narcotics or {}
            local withdrawal = self.cachedData.withdrawal
            if withdrawal then
                warningColor = c.withdrawal
                warningText = "! Withdrawal: " .. (withdrawal.drugName or "?")
            elseif #narcotics > 0 then
                warningColor = c.stimulant
                warningText = #narcotics .. " Substance(s) Active"
            end
        end
    end

    if warningText then
        self:drawText(self:truncateText(warningText, self.width - padding * 2, UIFont.Small), padding, y, warningColor.r, warningColor.g, warningColor.b, warningColor.a, UIFont.Small)
        y = y + self.LINE_HEIGHT
    end

    -- Healing status
    local bloodData = self.cachedData.blood or {}
    local healText
    if bloodData.canHeal then
        healText = getText("UI_EHR_Compact_HealingActive") or "Healing: Active"
    else
        local reason = bloodData.healBlockReason or "?"
        healText = string.format(getText("UI_EHR_Compact_HealingSlowed") or "Healing: Slowed (%s)", reason)
    end
    local healColor = bloodData.canHeal and c.safe or c.danger
    self:drawText(self:truncateText(healText, self.width - padding * 2, UIFont.Small), padding, y, healColor.r, healColor.g, healColor.b, healColor.a, UIFont.Small)

    -- Expand hint stays above the button instead of flowing into it.
    local hintText = getText("UI_EHR_Compact_ClickExpand") or "[Click + to expand]"
    local hintWidth = self:getTextWidth(hintText, UIFont.Small)
    local hintX = math.max(padding, math.floor((self.width - hintWidth) / 2))
    local hintY = self.height - 58
    self:drawText(hintText, hintX, hintY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)

    return hintY + self.LINE_HEIGHT
end

-- ============================================
-- GLOBAL FUNCTIONS
-- ============================================

-- Initialize UI namespace (don't overwrite if exists)
EHR.UI = EHR.UI or {}
EHR.UI.MonitorInstance = nil
EHR.UI.MonitorVisible = false
EHR.UI.AttachSide = "right"
EHR.UI.AttachGap = 5

-- ============================================
-- FIND HEALTH PANEL (ISCharacterInfoWindow)
-- ============================================

local function findCharacterInfoWindow()
    -- In B42, health panel is inside ISCharacterInfoWindow
    if ISCharacterInfoWindow and ISCharacterInfoWindow.instance then
        return ISCharacterInfoWindow.instance
    end
    return nil
end

-- ============================================
-- CREATE / SHOW / HIDE MONITOR
-- ============================================

local function createMonitor(player)
    if not player then return nil end

    local screenW = getCore():getScreenWidth()

    local monitor = EHR_MedicalMonitorUI:new(screenW - EHR_MedicalMonitorUI.COMPACT_WIDTH - 20, 100, player)
    monitor:initialise()
    monitor:instantiate()
    monitor:addToUIManager()
    monitor:setVisible(false)

    return monitor
end

local function updateMonitorPosition()
    local monitor = EHR.UI.MonitorInstance
    if not monitor then return end

    local charWindow = findCharacterInfoWindow()
    if not charWindow then return end

    local screenW = getCore():getScreenWidth()
    local gap = EHR.UI.AttachGap

    -- Get character window position and size
    local cwX = charWindow:getX()
    local cwY = charWindow:getY()
    local cwW = charWindow:getWidth()

    -- Calculate position to the right of character window
    local rightX = cwX + cwW + gap
    local leftX = cwX - monitor.width - gap

    -- Check if right side fits on screen
    local fitsRight = (rightX + monitor.width) <= screenW
    local fitsLeft = leftX >= 0

    -- Default to right, flip to left if doesn't fit
    local targetX = rightX
    if not fitsRight and fitsLeft then
        targetX = leftX
    elseif not fitsRight then
        targetX = math.max(0, screenW - monitor.width)
    end

    monitor:setX(targetX)
    -- BUG-009 FIX: Add 35px offset to avoid overlap with Map button
    monitor:setY(cwY + 35)
end

function EHR.UI.ShowMonitor(player)
    if not player then
        player = getPlayer()
    end
    if not player then return end

    if not EHR.UI.MonitorInstance then
        EHR.UI.MonitorInstance = createMonitor(player)
    end

    if EHR.UI.MonitorInstance then
        EHR.UI.MonitorInstance:setVisible(true)
        EHR.UI.MonitorVisible = true
        EHR.UI.MonitorInstance:updateCachedData()
        updateMonitorPosition()
    end
end

function EHR.UI.HideMonitor()
    if EHR.UI.MonitorInstance then
        EHR.UI.MonitorInstance:setVisible(false)
    end
    EHR.UI.MonitorVisible = false
end

function EHR.UI.ToggleMonitor(player)
    if EHR.UI.MonitorVisible then
        EHR.UI.HideMonitor()
    else
        EHR.UI.ShowMonitor(player)
    end
end

-- ============================================
-- TICK HANDLER - Track character window
-- ============================================

local lastCharWindowVisible = false
local lastCharWindowX = 0
local lastCharWindowY = 0
local lastCharWindowW = 0
local tickCount = 0

local function onTickHandler()
    tickCount = tickCount + 1

    -- Only check every 5 ticks to reduce overhead
    if tickCount % 5 ~= 0 then return end

    local player = getPlayer()
    if not player then return end

    -- Find the character info window
    local charWindow = findCharacterInfoWindow()

    if charWindow then
        local isVisible = charWindow:isVisible()
        local cwX = charWindow:getX()
        local cwY = charWindow:getY()
        local cwW = charWindow:getWidth()

        -- Window just became visible
        if isVisible and not lastCharWindowVisible then
            EHR.UI.ShowMonitor(player)
        end

        -- Window just became hidden
        if not isVisible and lastCharWindowVisible then
            EHR.UI.HideMonitor()
        end

        -- Window moved - update our position
        if isVisible and EHR.UI.MonitorVisible then
            if cwX ~= lastCharWindowX or cwY ~= lastCharWindowY or cwW ~= lastCharWindowW then
                updateMonitorPosition()
            end
        end

        lastCharWindowVisible = isVisible
        lastCharWindowX = cwX
        lastCharWindowY = cwY
        lastCharWindowW = cwW
    else
        -- No character window found
        if EHR.UI.MonitorVisible then
            EHR.UI.HideMonitor()
        end
        lastCharWindowVisible = false
    end
end

Events.OnTick.Add(onTickHandler)

-- ============================================
-- KEY BINDING (handled by EHR_KeybindManager.lua)
-- Keybinds are customizable in Options  Mods  Extensive Health Rework
-- ============================================

-- Legacy backup: Only active if keybind manager fails to load
local function onKeyPressedHandler(key)
    -- Check if keybind manager is handling this
    if EHR.Keybinds and EHR.Keybinds.initialized then
        return  -- Keybind manager handles it
    end

    -- Fallback to hardcoded H key if manager not loaded
    if key == Keyboard.KEY_H then
        local player = getPlayer()
        if player then
            EHR.UI.ToggleMonitor(player)
        end
    end
end

Events.OnKeyPressed.Add(onKeyPressedHandler)

-- ============================================
-- BUG-012 FIX: PLAYER DEATH - Reset monitor state
-- ============================================

local function onPlayerDeathHandler(player)
    -- Defensive guard: ensure valid player object
    if not player then return end

    local monitor = EHR.UI.MonitorInstance
    if not monitor then return end

    -- Only reset if this monitor was tracking the dead player
    if monitor.player == player then
        EHR.Log("Medical Monitor: Tracked player died, resetting monitor state")
        monitor:resetMonitor()
        EHR.UI.MonitorInstance = nil
        EHR.UI.MonitorVisible = false
        -- BUG-021 FIX: Reset char window tracking so monitor shows again on respawn
        lastCharWindowVisible = false
    end
end

if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(onPlayerDeathHandler)
end

-- ============================================
-- PLAYER CREATION - Reset monitor for new character
-- ============================================

local function onCreatePlayerHandler(playerIndex, player)
    EHR.Log("Medical Monitor: OnCreatePlayer fired for index " .. tostring(playerIndex))

    -- Always destroy old monitor when a new player is created
    -- This ensures we get fresh data for the new character
    if EHR.UI.MonitorInstance then
        EHR.Log("Medical Monitor: Destroying old monitor for new character")
        EHR.UI.MonitorInstance:resetMonitor()
        EHR.UI.MonitorInstance:removeFromUIManager()
        EHR.UI.MonitorInstance = nil
    end

    EHR.UI.MonitorVisible = false
    lastCharWindowVisible = false

    -- Reset thermoregulator flag so it re-attempts on new character
    thermoregulatorDisabled = false
end

Events.OnCreatePlayer.Add(onCreatePlayerHandler)

-- ============================================
-- GAME START - Reset state
-- ============================================

local function onGameStartHandler()
    EHR.UI.MonitorInstance = nil
    EHR.UI.MonitorVisible = false
    lastCharWindowVisible = false
end

Events.OnGameStart.Add(onGameStartHandler)

-- ============================================
-- VANILLA TEMPERATURE SUPPRESSION (Client-side backup - Hybrid Approach)
-- Backup suppression in case shared code doesn't run
-- Uses same hybrid approach: disable thermoregulator + throttled safety checks
-- ============================================

local clientSuppression = {
    thermoregulatorDisabled = false,
    lastPlayer = nil,
    tickCounter = 0,
    SAFETY_CHECK_INTERVAL = 30,  -- Only check every 30 ticks (~1 second)
    NORMAL_BODY_TEMP = 37.0,
    TOLERANCE = 1.0,
    logCounter = 0,
}

local function suppressVanillaTemperatureClient()
    local player = getSpecificPlayer(0)
    if not player then return end
    if not player:isAlive() then return end

    -- Reset state if player changed
    if clientSuppression.lastPlayer ~= player then
        clientSuppression.thermoregulatorDisabled = false
        clientSuppression.lastPlayer = player
        clientSuppression.tickCounter = 0
    end

    -- PRIMARY: Try to disable thermoregulator once
    if not clientSuppression.thermoregulatorDisabled then
        pcall(function()
            local bodyDamage = player:getBodyDamage()
            if bodyDamage then
                local thermo = bodyDamage:getThermoregulator()
                if thermo and thermo.setSimulationMultiplier then
                    thermo:setSimulationMultiplier(0)
                    clientSuppression.thermoregulatorDisabled = true
                end
            end
        end)
    end

    -- SAFETY NET: Throttled check every N ticks
    clientSuppression.tickCounter = clientSuppression.tickCounter + 1
    if clientSuppression.tickCounter < clientSuppression.SAFETY_CHECK_INTERVAL then
        return  -- Skip this tick
    end
    clientSuppression.tickCounter = 0

    local stats = player:getStats()
    if not stats then return end

    if not CharacterStat or not CharacterStat.TEMPERATURE then return end

    local success, current = pcall(function()
        return stats:get(CharacterStat.TEMPERATURE)
    end)

    if success and current ~= nil then
        -- Only force if significantly off from normal
        if math.abs(current - clientSuppression.NORMAL_BODY_TEMP) > clientSuppression.TOLERANCE then
            pcall(function()
                stats:set(CharacterStat.TEMPERATURE, clientSuppression.NORMAL_BODY_TEMP)
            end)

            -- If we had to force, thermoregulator might have re-enabled
            clientSuppression.thermoregulatorDisabled = false

            -- Log when safety net triggers
            print("[EHR] Client safety net: " .. tostring(current) .. " -> " .. tostring(clientSuppression.NORMAL_BODY_TEMP))
        end
    end
end

Events.OnTick.Add(suppressVanillaTemperatureClient)

EHR.Log("EHR_MedicalMonitorUI.lua loaded - Medical Monitor attaches to Health Panel")
