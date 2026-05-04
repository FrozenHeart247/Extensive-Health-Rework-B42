--[[
    Extensive Health Rework B42
    Medical Journal UI Module

    ISPanel-based UI for viewing diagnosis history and statistics.
    Features tab panel with Entries and Statistics views.

    Keybind: Configurable via EHR_KeybindManager (default: J)

    v1.0.0
]]--

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTabPanel"
require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_MedicalJournal"

-- ============================================
-- UI CLASS DEFINITION
-- ============================================

EHR_MedicalJournalUI = ISPanel:derive("EHR_MedicalJournalUI")

-- Static instance reference
EHR_MedicalJournalUI.instance = nil

-- ============================================
-- CONSTANTS
-- ============================================

local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 600
local PADDING = 10
local BUTTON_HEIGHT = 25
local HEADER_HEIGHT = 35
local TAB_HEIGHT = 30

-- Color scheme (matches Medical Monitor / Debug Menu)
local Colors = {
    background = {r=0.1, g=0.1, b=0.12, a=0.95},
    border = {r=0.3, g=0.5, b=0.4, a=1},
    headerBg = {r=0.15, g=0.2, b=0.18, a=1},
    text = {r=0.9, g=0.9, b=0.9, a=1},
    textDim = {r=0.6, g=0.6, b=0.6, a=1},
    safe = {r=0.2, g=0.8, b=0.3, a=1},
    warning = {r=0.9, g=0.7, b=0.2, a=1},
    danger = {r=0.9, g=0.3, b=0.1, a=1},
    listBg = {r=0.08, g=0.08, b=0.1, a=1},
    listAlt = {r=0.12, g=0.12, b=0.14, a=1},
    buttonBg = {r=0.18, g=0.22, b=0.2, a=1},
}

-- ============================================
-- CONSTRUCTOR
-- ============================================

function EHR_MedicalJournalUI:new(x, y, width, height, player)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.backgroundColor = Colors.background
    o.borderColor = Colors.border
    o.moveWithMouse = true
    o.currentFilter = nil  -- nil = all, {correct=true/false}

    return o
end

-- ============================================
-- INITIALIZATION
-- ============================================

function EHR_MedicalJournalUI:initialise()
    ISPanel.initialise(self)
end

function EHR_MedicalJournalUI:createChildren()
    ISPanel.createChildren(self)

    local y = PADDING

    -- Header / Title
    self.titleLabel = ISLabel:new(
        PADDING, y,
        HEADER_HEIGHT,
        getText("UI_EHR_MedicalJournal_Title") or "Medical Journal",
        1, 1, 1, 1,
        UIFont.Large, true
    )
    self.titleLabel:initialise()
    self:addChild(self.titleLabel)

    y = y + HEADER_HEIGHT + PADDING

    -- Close button (top right)
    local closeBtnWidth = 60
    self.closeBtn = ISButton:new(
        self.width - closeBtnWidth - PADDING,
        PADDING,
        closeBtnWidth,
        BUTTON_HEIGHT,
        getText("UI_EHR_Close") or "Close",
        self,
        EHR_MedicalJournalUI.onClose
    )
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.backgroundColor = Colors.buttonBg
    self:addChild(self.closeBtn)

    -- Tab panel
    local tabPanelHeight = self.height - y - PADDING - BUTTON_HEIGHT - PADDING
    self.tabPanel = ISTabPanel:new(
        PADDING,
        y,
        self.width - PADDING * 2,
        tabPanelHeight
    )
    self.tabPanel:initialise()
    self.tabPanel:setAnchorBottom(true)
    self.tabPanel:setAnchorRight(true)
    self:addChild(self.tabPanel)

    -- Create tab contents
    self:createEntriesTab()
    self:createStatisticsTab()

    -- Add tabs
    self.tabPanel:addView(
        getText("UI_EHR_Journal_Tab_Entries") or "Entries",
        self.entriesPanel
    )
    self.tabPanel:addView(
        getText("UI_EHR_Journal_Tab_Statistics") or "Statistics",
        self.statsPanel
    )

    -- Bottom buttons (filter buttons for entries)
    y = self.height - PADDING - BUTTON_HEIGHT

    local filterBtnWidth = 70
    local filterX = PADDING

    self.filterAllBtn = ISButton:new(
        filterX, y, filterBtnWidth, BUTTON_HEIGHT,
        getText("UI_EHR_Journal_Filter_All") or "All",
        self, EHR_MedicalJournalUI.onFilterAll
    )
    self.filterAllBtn:initialise()
    self.filterAllBtn:instantiate()
    self:addChild(self.filterAllBtn)
    filterX = filterX + filterBtnWidth + 5

    self.filterCorrectBtn = ISButton:new(
        filterX, y, filterBtnWidth + 10, BUTTON_HEIGHT,
        getText("UI_EHR_Journal_Filter_Correct") or "Correct",
        self, EHR_MedicalJournalUI.onFilterCorrect
    )
    self.filterCorrectBtn:initialise()
    self.filterCorrectBtn:instantiate()
    self:addChild(self.filterCorrectBtn)
    filterX = filterX + filterBtnWidth + 15

    self.filterWrongBtn = ISButton:new(
        filterX, y, filterBtnWidth + 10, BUTTON_HEIGHT,
        getText("UI_EHR_Journal_Filter_Wrong") or "Wrong",
        self, EHR_MedicalJournalUI.onFilterWrong
    )
    self.filterWrongBtn:initialise()
    self.filterWrongBtn:instantiate()
    self:addChild(self.filterWrongBtn)

    -- Refresh button (right side)
    self.refreshBtn = ISButton:new(
        self.width - 80 - PADDING,
        y,
        80,
        BUTTON_HEIGHT,
        getText("UI_EHR_Refresh") or "Refresh",
        self,
        EHR_MedicalJournalUI.onRefresh
    )
    self.refreshBtn:initialise()
    self.refreshBtn:instantiate()
    self:addChild(self.refreshBtn)

    -- Initial data load
    self:refreshEntries()
end

-- ============================================
-- TAB CREATION
-- ============================================

function EHR_MedicalJournalUI:createEntriesTab()
    local panelWidth = self.width - PADDING * 2
    local panelHeight = self.height - 150  -- Approximate tab content height

    self.entriesPanel = ISPanel:new(0, 0, panelWidth, panelHeight)
    self.entriesPanel:initialise()
    self.entriesPanel.backgroundColor = {r=0, g=0, b=0, a=0}

    -- Scrolling list for entries
    self.entriesList = ISScrollingListBox:new(
        5, 5,
        panelWidth - 10,
        panelHeight - 50
    )
    self.entriesList:initialise()
    self.entriesList:instantiate()
    self.entriesList.itemheight = 40
    self.entriesList.selected = 0
    self.entriesList.font = UIFont.Small
    self.entriesList.doDrawItem = self.drawEntryItem
    self.entriesList.drawBorder = true
    self.entriesList.parent = self
    self.entriesPanel:addChild(self.entriesList)

    -- Entry count label
    self.entryCountLabel = ISLabel:new(
        5, panelHeight - 40,
        20,
        "0 entries",
        Colors.textDim.r, Colors.textDim.g, Colors.textDim.b, 1,
        UIFont.Small, true
    )
    self.entryCountLabel:initialise()
    self.entriesPanel:addChild(self.entryCountLabel)
end

function EHR_MedicalJournalUI:createStatisticsTab()
    local panelWidth = self.width - PADDING * 2
    local panelHeight = self.height - 150

    self.statsPanel = ISPanel:new(0, 0, panelWidth, panelHeight)
    self.statsPanel:initialise()
    self.statsPanel.backgroundColor = {r=0, g=0, b=0, a=0}
    self.statsPanel.parent = self
    self.statsPanel.render = self.renderStatistics
end

-- ============================================
-- RENDERING
-- ============================================

function EHR_MedicalJournalUI:prerender()
    ISPanel.prerender(self)

    -- Draw header background
    self:drawRect(
        0, 0,
        self.width, HEADER_HEIGHT + PADDING,
        Colors.headerBg.a, Colors.headerBg.r, Colors.headerBg.g, Colors.headerBg.b
    )

    -- Draw border
    self:drawRectBorder(
        0, 0,
        self.width, self.height,
        Colors.border.a, Colors.border.r, Colors.border.g, Colors.border.b
    )
end

function EHR_MedicalJournalUI:render()
    ISPanel.render(self)
end

-- Custom render for statistics panel
function EHR_MedicalJournalUI.renderStatistics(self)
    ISPanel.render(self)

    local parent = self.parent
    if not parent or not parent.player then return end

    local summary = EHR.MedicalJournal.GetSummary(parent.player)
    local x = 15
    local y = 15
    local lineHeight = 25
    local c = Colors

    -- Title
    self:drawText(
        getText("UI_EHR_Journal_Stats_Title") or "Diagnosis Statistics",
        x, y,
        c.text.r, c.text.g, c.text.b, 1,
        UIFont.Medium
    )
    y = y + lineHeight + 10

    -- Total diagnoses
    self:drawText(
        string.format("%s: %d",
            getText("UI_EHR_Journal_Stat_Total") or "Total Diagnoses",
            summary.totalDiagnoses
        ),
        x, y,
        c.text.r, c.text.g, c.text.b, 1,
        UIFont.Small
    )
    y = y + lineHeight

    -- Correct diagnoses
    self:drawText(
        string.format("%s: %d",
            getText("UI_EHR_Journal_Stat_Correct") or "Correct",
            summary.correctDiagnoses
        ),
        x, y,
        c.safe.r, c.safe.g, c.safe.b, 1,
        UIFont.Small
    )
    y = y + lineHeight

    -- Wrong diagnoses
    self:drawText(
        string.format("%s: %d",
            getText("UI_EHR_Journal_Stat_Wrong") or "Wrong",
            summary.wrongDiagnoses
        ),
        x, y,
        c.danger.r, c.danger.g, c.danger.b, 1,
        UIFont.Small
    )
    y = y + lineHeight + 5

    -- Accuracy bar
    local barWidth = 200
    local barHeight = 20
    local accuracy = summary.accuracyPercent / 100

    -- Bar background
    self:drawRect(x, y, barWidth, barHeight, 0.5, 0.2, 0.2, 0.2)

    -- Bar fill
    local fillColor = accuracy > 0.7 and c.safe or (accuracy > 0.4 and c.warning or c.danger)
    self:drawRect(x, y, barWidth * accuracy, barHeight, 1, fillColor.r, fillColor.g, fillColor.b)

    -- Bar border
    self:drawRectBorder(x, y, barWidth, barHeight, 1, c.border.r, c.border.g, c.border.b)

    -- Accuracy text
    self:drawText(
        string.format("%s: %d%%",
            getText("UI_EHR_Journal_Stat_Accuracy") or "Accuracy",
            summary.accuracyPercent
        ),
        x + barWidth + 10, y + 2,
        c.text.r, c.text.g, c.text.b, 1,
        UIFont.Small
    )

    y = y + barHeight + 20

    -- Diseases section
    self:drawText(
        getText("UI_EHR_Journal_Stats_Diseases") or "Disease History",
        x, y,
        c.text.r, c.text.g, c.text.b, 1,
        UIFont.Medium
    )
    y = y + lineHeight

    self:drawText(
        string.format("%s: %d",
            getText("UI_EHR_Journal_Stat_Contracted") or "Contracted",
            summary.totalDiseases
        ),
        x + 10, y,
        c.textDim.r, c.textDim.g, c.textDim.b, 1,
        UIFont.Small
    )
    y = y + lineHeight

    self:drawText(
        string.format("%s: %d",
            getText("UI_EHR_Journal_Stat_Cured") or "Cured",
            summary.totalCures
        ),
        x + 10, y,
        c.safe.r, c.safe.g, c.safe.b, 1,
        UIFont.Small
    )
end

-- Custom draw function for entry list items
function EHR_MedicalJournalUI.drawEntryItem(self, y, item, alt)
    local parent = self.parent

    if not item or not item.item then return y + self.itemheight end

    local entry = item.item
    local x = 10
    local c = Colors

    -- Alternate row background
    if alt then
        self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.1, 0.1, 0.12)
    end

    -- Handle examination entries differently from diagnosis entries
    local isExamination = entry.entryType == "examination"

    -- Day number
    local dayText = string.format("Day %d", entry.gameDay or 0)
    self:drawText(dayText, x, y + 3, c.textDim.r, c.textDim.g, c.textDim.b, 1, UIFont.Small)

    if isExamination then
        -- EXAMINATION ENTRY RENDERING
        -- Indicator color: green if healthy (no diseases), yellow if issues found
        local isHealthy = (entry.diseaseCount or 0) == 0 and (entry.bloodPercent or 100) >= 90
        local indicatorColor = isHealthy and c.safe or c.warning
        self:drawRect(0, y, 4, self.itemheight, 1, indicatorColor.r, indicatorColor.g, indicatorColor.b)

        -- Show "Self-Examination" as the entry type
        local examText = getText("UI_EHR_Journal_Examination") or "Self-Examination"
        self:drawText(examText, x + 60, y + 3, c.text.r, c.text.g, c.text.b, 1, UIFont.Small)

        -- Show health status instead of stage
        local statusText
        local statusColor
        if isHealthy then
            statusText = getText("UI_EHR_Journal_Healthy") or "HEALTHY"
            statusColor = c.safe
        else
            local issues = {}
            if (entry.diseaseCount or 0) > 0 then
                table.insert(issues, (entry.diseaseCount or 0) .. " disease(s)")
            end
            if (entry.bloodPercent or 100) < 90 then
                table.insert(issues, "low blood")
            end
            statusText = table.concat(issues, ", ")
            statusColor = c.warning
        end
        self:drawText(statusText, x + 200, y + 3, statusColor.r, statusColor.g, statusColor.b, 1, UIFont.Small)

        -- Show skill tier instead of correct/wrong
        local tierNames = {"Clueless", "Novice", "Intermediate", "Expert", "Master"}
        local tierText = tierNames[(entry.skillTier or 0) + 1] or "Unknown"
        self:drawText(tierText, x + 350, y + 3, c.textDim.r, c.textDim.g, c.textDim.b, 1, UIFont.Small)
    else
        -- DIAGNOSIS ENTRY RENDERING
        -- Correct/incorrect indicator
        local indicatorColor = entry.isCorrect and c.safe or c.danger
        self:drawRect(0, y, 4, self.itemheight, 1, indicatorColor.r, indicatorColor.g, indicatorColor.b)

        -- Disease name - improved fallback handling
        local diagnosedId = entry.diagnosedAs or "Unknown"
        local diseaseName = getText("UI_EHR_Disease_" .. diagnosedId)
        -- Check if getText returned the raw key (means translation not found)
        if not diseaseName or diseaseName == "?" or diseaseName == "" or diseaseName:find("^UI_EHR_") then
            -- Use humanized version of the ID
            diseaseName = diagnosedId:gsub("_", " "):gsub("(%a)([%w_']*)", function(a,b) return a:upper()..(b or "") end)
        end
        self:drawText(diseaseName, x + 60, y + 3, c.text.r, c.text.g, c.text.b, 1, UIFont.Small)

        -- Stage
        local stageText = string.format("Stage %d", entry.stage or 1)
        self:drawText(stageText, x + 200, y + 3, c.textDim.r, c.textDim.g, c.textDim.b, 1, UIFont.Small)

        -- Correct/Wrong label
        local statusText = entry.isCorrect and
            (getText("UI_EHR_Journal_Correct") or "CORRECT") or
            (getText("UI_EHR_Journal_Wrong") or "WRONG")
        local statusColor = entry.isCorrect and c.safe or c.danger
        self:drawText(statusText, x + 280, y + 3, statusColor.r, statusColor.g, statusColor.b, 1, UIFont.Small)

        -- If wrong, show actual disease
        if not entry.isCorrect and entry.actualDisease then
            local actualName = getText("UI_EHR_Disease_" .. entry.actualDisease)
            if not actualName or actualName == "?" or actualName == "" or actualName:find("^UI_EHR_") then
                actualName = entry.actualDisease:gsub("_", " "):gsub("(%a)([%w_']*)", function(a,b) return a:upper()..(b or "") end)
            end
            local wasText = string.format("(was %s)", actualName)
            self:drawText(wasText, x + 60, y + 20, c.danger.r, c.danger.g, c.danger.b, 0.8, UIFont.Small)
        end

        -- Skill level at time
        local skillText = string.format("Skill: %d", entry.effectiveSkill or 0)
        self:drawText(skillText, x + 380, y + 3, c.textDim.r, c.textDim.g, c.textDim.b, 1, UIFont.Small)
    end

    return y + self.itemheight
end

-- ============================================
-- DATA REFRESH
-- ============================================

function EHR_MedicalJournalUI:refreshEntries()
    if not self.entriesList then return end

    self.entriesList:clear()

    local entries = EHR.MedicalJournal.GetEntries(self.player, self.currentFilter)

    for i, entry in ipairs(entries) do
        self.entriesList:addItem(entry.diagnosedAs or "Unknown", entry)
    end

    -- Update entry count label
    if self.entryCountLabel then
        local countText = string.format("%d %s",
            #entries,
            #entries == 1 and "entry" or "entries"
        )
        if self.currentFilter then
            if self.currentFilter.correct == true then
                countText = countText .. " (correct only)"
            elseif self.currentFilter.correct == false then
                countText = countText .. " (wrong only)"
            end
        end
        self.entryCountLabel:setName(countText)
    end
end

-- ============================================
-- BUTTON HANDLERS
-- ============================================

function EHR_MedicalJournalUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    EHR_MedicalJournalUI.instance = nil
end

function EHR_MedicalJournalUI:onRefresh()
    self:refreshEntries()
end

function EHR_MedicalJournalUI:onFilterAll()
    self.currentFilter = nil
    self:refreshEntries()
end

function EHR_MedicalJournalUI:onFilterCorrect()
    self.currentFilter = {correct = true}
    self:refreshEntries()
end

function EHR_MedicalJournalUI:onFilterWrong()
    self.currentFilter = {correct = false}
    self:refreshEntries()
end

-- ============================================
-- STATIC TOGGLE FUNCTION
-- ============================================

--[[
    Toggle the Medical Journal UI.
    @param player (IsoPlayer, optional) - Defaults to player 0
]]--
function EHR_MedicalJournalUI.Toggle(player)
    player = player or getSpecificPlayer(0)
    if not player then return end

    -- Close if already open
    if EHR_MedicalJournalUI.instance and EHR_MedicalJournalUI.instance:isVisible() then
        EHR_MedicalJournalUI.instance:onClose()
        return
    end

    -- Create new instance
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = (screenW - WINDOW_WIDTH) / 2
    local y = (screenH - WINDOW_HEIGHT) / 2

    EHR_MedicalJournalUI.instance = EHR_MedicalJournalUI:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT, player)
    EHR_MedicalJournalUI.instance:initialise()
    EHR_MedicalJournalUI.instance:instantiate()
    EHR_MedicalJournalUI.instance:addToUIManager()
    EHR_MedicalJournalUI.instance:setVisible(true)

    -- Bring to front
    EHR_MedicalJournalUI.instance:bringToTop()
end

--[[
    Check if journal UI is currently open.
    @return boolean
]]--
function EHR_MedicalJournalUI.IsOpen()
    return EHR_MedicalJournalUI.instance ~= nil and EHR_MedicalJournalUI.instance:isVisible()
end

-- ============================================
-- NAMESPACE EXPORT
-- ============================================

EHR = EHR or {}
EHR.UI = EHR.UI or {}
EHR.UI.ToggleJournal = EHR_MedicalJournalUI.Toggle

-- ============================================
-- INITIALIZATION
-- ============================================

if EHR and EHR.Log then
    EHR.Log("MedicalJournalUI module loaded")
end
