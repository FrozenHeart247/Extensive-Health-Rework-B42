--[[
    Extensive Health Rework - Tooltip System

    Handles tooltip registration and custom rendering for EHR items.
    This system provides rich, formatted tooltips with categories,
    effects, side effects, and more.

    Author: ExtensiveHealthRework Team
    Version: 1.0
]]

require "ISUI/ISToolTipInv"
require "ISUI/ISFoodToolTip"

-- Ensure TooltipData is loaded (should be loaded from shared already)
if not EHR or not EHR.Tooltips or not EHR.Tooltips.Data then
    -- Try to require it if not already loaded
    pcall(function() require "ExtensiveHealth/EHR_TooltipData" end)
end
pcall(function() require "ExtensiveHealth/EHR_Medication" end)
pcall(function() require "ExtensiveHealth/EHR_DiseaseFlyers" end)

EHR = EHR or {}
EHR.Tooltips = EHR.Tooltips or {}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

local function getTooltipCharacter(panel)
    local character = nil

    if panel then
        if panel.character then
            character = panel.character
        elseif panel.tooltip then
            if panel.tooltip.getCharacter then
                local ok, result = pcall(function()
                    return panel.tooltip:getCharacter()
                end)
                if ok then character = result end
            elseif panel.tooltip.character then
                character = panel.tooltip.character
            end
        end
    end

    if not character and getPlayer then
        local ok, result = pcall(getPlayer)
        if ok then character = result end
    end

    return character
end

function EHR.Tooltips.HasBloodTypeKnowledge(panelOrPlayer)
    local player = panelOrPlayer
    if not (player and player.getModData and player.getPerkLevel) then
        player = getTooltipCharacter(panelOrPlayer)
    end

    if not player then return false end

    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.HasMedicalKnowledge then
        return EHR.DiseaseFlyers.HasMedicalKnowledge(player, "blood_types", 8)
    end

    if Perks and Perks.Doctor and player.getPerkLevel then
        local ok, level = pcall(function()
            return player:getPerkLevel(Perks.Doctor)
        end)
        return ok and (tonumber(level) or 0) >= 8
    end

    return false
end

-- Format hours into human-readable time (e.g., "5 days", "12 hours", "2 days 6 hours")
function EHR.Tooltips.FormatTimeRemaining(hours)
    if hours <= 0 then
        return "0 hours"
    end

    if hours < 1 then
        local minutes = math.max(1, math.ceil(hours * 60))
        return string.format("%d min", minutes)
    end

    local days = math.floor(hours / 24)
    local remainingHours = math.floor(hours % 24)

    if days > 0 then
        if remainingHours > 0 then
            return string.format("%d day%s %d hr%s", days, days == 1 and "" or "s", remainingHours, remainingHours == 1 and "" or "s")
        else
            return string.format("%d day%s", days, days == 1 and "" or "s")
        end
    else
        return string.format("%d hour%s", remainingHours, remainingHours == 1 and "" or "s")
    end
end

-- ============================================
-- TOOLTIP REGISTRATION
-- Registers all tooltip translations at runtime
-- ============================================

function EHR.Tooltips.RegisterTranslations()
    -- Ensure Tooltip_EN exists
    if not Tooltip_EN then
        Tooltip_EN = {}
    end

    -- Register each tooltip from our data
    if EHR.Tooltips.Data then
        for itemFullType, data in pairs(EHR.Tooltips.Data) do
            -- Extract item name from full type (e.g., "ExtensiveHealth.BloodBagONeg" -> "BloodBagONeg")
            local itemName = itemFullType:match("%.(.+)$") or itemFullType

            -- Build tooltip key
            local tooltipKey = "Tooltip_" .. itemName

            -- Build tooltip text from data
            local tooltipText = EHR.Tooltips.BuildTooltipText(data)

            -- Register in global Tooltip_EN table
            Tooltip_EN[tooltipKey] = tooltipText
        end
        EHR.Log("Registered " .. EHR.Tooltips.CountData() .. " tooltip translations")
    end
end

-- Count tooltip entries
function EHR.Tooltips.CountData()
    local count = 0
    if EHR.Tooltips.Data then
        for _ in pairs(EHR.Tooltips.Data) do
            count = count + 1
        end
    end
    return count
end

-- Build tooltip text string from data
function EHR.Tooltips.BuildTooltipText(data)
    local lines = {}

    -- Description
    if data.description then
        table.insert(lines, data.description)
    end

    -- Empty line separator
    table.insert(lines, " ")

    -- Effects
    if data.effects and #data.effects > 0 then
        for _, effect in ipairs(data.effects) do
            table.insert(lines, "<RGB:0.3,0.9,0.3> + " .. effect)
        end
    end

    -- What it cures
    if data.cures and #data.cures > 0 then
        local curesText = "<RGB:0.3,0.8,1.0> CURES: " .. table.concat(data.cures, ", ")
        table.insert(lines, curesText)
    end

    -- What it relieves (doesn't cure)
    if data.relieves and #data.relieves > 0 then
        local relievesText = "<RGB:0.9,0.9,0.3> Relieves: " .. table.concat(data.relieves, ", ")
        table.insert(lines, relievesText)
    end

    -- Treatment time
    if data.treatmentTime then
        table.insert(lines, "<RGB:0.7,0.7,0.7> Treatment time: " .. data.treatmentTime)
    end

    -- Requirements
    if data.requirements and #data.requirements > 0 then
        local reqText = "<RGB:0.9,0.6,0.2> Requires: " .. table.concat(data.requirements, ", ")
        table.insert(lines, reqText)
    end

    -- Side effects (each on its own line)
    if data.sideEffects and #data.sideEffects > 0 then
        table.insert(lines, "<RGB:1.0,0.5,0.0> SIDE EFFECTS:")
        for _, sideEffect in ipairs(data.sideEffects) do
            table.insert(lines, "<RGB:1.0,0.6,0.2>   - " .. sideEffect)
        end
    end

    -- Warning
    if data.warning then
        table.insert(lines, "<RGB:1.0,0.3,0.3> ! " .. data.warning)
    end

    -- Success/Failure text (for Gene Therapy etc)
    if data.successText then
        table.insert(lines, "<RGB:0.3,1.0,0.3> + " .. data.successText)
    end
    if data.failureText then
        table.insert(lines, "<RGB:1.0,0.3,0.3> - " .. data.failureText)
    end

    return table.concat(lines, " <LINE> ")
end

-- ============================================
-- CUSTOM TOOLTIP RENDERING
-- Override vanilla tooltip for EHR items
-- ============================================

-- Store original render function (with safety check)
local originalDoTooltip = nil
if ISToolTipInv and ISToolTipInv.render then
    originalDoTooltip = ISToolTipInv.render
else
    -- ISToolTipInv.render not found - log warning
    if EHR and EHR.Log then
        EHR.Log("WARNING: ISToolTipInv.render not found - custom tooltips may not work")
    end
end

-- Custom tooltip render with safety fallback
function ISToolTipInv:render()
    local useVanilla = true

    -- Try EHR custom tooltip first
    local item = self.item
    if item and EHR and EHR.Tooltips and EHR.Tooltips.GetData then
        local itemFullType = item:getFullType()
        local ehrData = EHR.Tooltips.GetData(itemFullType)

        -- Debug: Log what we're checking (only once per item type)
        if not EHR.Tooltips._debuggedTypes then EHR.Tooltips._debuggedTypes = {} end
        if not EHR.Tooltips._debuggedTypes[itemFullType] then
            EHR.Tooltips._debuggedTypes[itemFullType] = true
            print("[EHR Tooltip] Checking item: " .. tostring(itemFullType) .. " | Has EHR data: " .. tostring(ehrData ~= nil))
        end

        if ehrData then
            -- Wrap in pcall to catch any rendering errors
            local success, err = pcall(function()
                self:renderEHRTooltip(ehrData, item)
            end)
            if success then
                useVanilla = false
            else
                print("[EHR Tooltip] ERROR rendering: " .. tostring(err))
                -- Print stack trace for debugging
                print(debug.traceback())
            end
        end
    end

    -- Fall back to vanilla tooltip if needed
    if useVanilla and originalDoTooltip then
        originalDoTooltip(self)
    end
end

-- ============================================
-- FOOD TOOLTIP OVERRIDE
-- Items with DaysFresh/DaysTotallyRotten use ISFoodToolTip
-- We need to hook this for perishable items like blood bags
-- ============================================

local originalFoodTooltip = nil

-- Only hook ISFoodToolTip if it exists (B42 compatibility)
if ISFoodToolTip and type(ISFoodToolTip) == "table" and ISFoodToolTip.render then
    originalFoodTooltip = ISFoodToolTip.render

    function ISFoodToolTip:render()
        local useVanilla = true

        -- Try EHR custom tooltip first
        local item = self.item
        if item and EHR and EHR.Tooltips and EHR.Tooltips.GetData then
            local itemFullType = item:getFullType()
            local ehrData = EHR.Tooltips.GetData(itemFullType)
            if ehrData then
                -- Wrap in pcall to catch any rendering errors
                local success, err = pcall(function()
                    self:renderEHRTooltip(ehrData, item)
                end)
                if success then
                    useVanilla = false
                else
                    print("[EHR FoodTooltip] ERROR rendering: " .. tostring(err))
                    print(debug.traceback())
                end
            end
        end

        -- Fall back to vanilla food tooltip if needed
        if useVanilla and originalFoodTooltip then
            originalFoodTooltip(self)
        end
    end
else
    if EHR and EHR.Log then
        EHR.Log("WARNING: ISFoodToolTip not found - perishable item tooltips may use vanilla display")
    end
end

-- Render custom EHR tooltip (shared implementation for both tooltip classes)
local function renderEHRTooltipImpl(self, data, item)
    -- BUG FIX: Safety check for UI availability (prevents nil errors with mod conflicts)
    if not getMouseX or not getMouseY or not getTextManager or not UIFont then
        return false
    end
    local textManager = getTextManager()
    if not textManager then
        return false
    end

    -- Positioning offset (matches vanilla ISToolTipInv)
    local offset = 24

    local mx = getMouseX() + offset
    local my = getMouseY() + offset
    local maxLineWidth = 320

    -- Get font metrics
    local font = UIFont.Small
    local fontHeight = textManager:getFontHeight(font)
    local lineSpacing = 4

    local function trimLastCharacter(text)
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

    local function fitText(text, maxWidth)
        text = tostring(text or "")
        if not maxWidth or maxWidth <= 0 then return "" end
        if textManager:MeasureStringX(font, text) <= maxWidth then return text end

        local suffix = "..."
        local trimmed = text
        while #trimmed > 0 and textManager:MeasureStringX(font, trimmed .. suffix) > maxWidth do
            trimmed = trimLastCharacter(trimmed)
        end

        if trimmed == "" then return "" end
        return trimmed .. suffix
    end

    -- Helper function to wrap text
    local function wrapText(text, maxWidth, color)
        local wrappedLines = {}
        local words = {}
        for word in text:gmatch("%S+") do
            table.insert(words, word)
        end

        local currentLine = ""
        for i, word in ipairs(words) do
            local testLine = currentLine == "" and word or (currentLine .. " " .. word)
            local testWidth = textManager:MeasureStringX(font, testLine)
            if testWidth > maxWidth and currentLine ~= "" then
                table.insert(wrappedLines, {text = fitText(currentLine, maxWidth), color = color})
                currentLine = word
            else
                currentLine = testLine
            end
        end
        if currentLine ~= "" then
            table.insert(wrappedLines, {text = fitText(currentLine, maxWidth), color = color})
        end
        return wrappedLines
    end

    -- Calculate content
    local lines = {}
    local totalHeight = 0
    local maxWidth = 200

    local function addWrappedLines(text, color)
        local wrapped = wrapText(tostring(text or ""), maxLineWidth, color)
        for _, line in ipairs(wrapped) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    local function addSpacer()
        table.insert(lines, {text = " ", color = {r=1, g=1, b=1}, spacer = true})
        totalHeight = totalHeight + fontHeight + lineSpacing
    end

    -- Item name (from item display name)
    local displayName = item:getDisplayName() or item:getName()
    table.insert(lines, {text = displayName, color = {r=1, g=1, b=1}, bold = true})
    totalHeight = totalHeight + fontHeight + lineSpacing

    -- Category and tier
    if data.category then
        local catColor = EHR.Tooltips.GetCategoryColor(data.category)
        local catText = data.category
        if data.tier then
            catText = catText .. " - " .. EHR.Tooltips.GetTierName(data.tier)
        end
        table.insert(lines, {text = catText, color = catColor})
        totalHeight = totalHeight + fontHeight + lineSpacing
    end

    if EHR and EHR.Medication and EHR.Medication.GetItemDoseInfo then
        local okDose, doseInfo = pcall(function()
            return EHR.Medication.GetItemDoseInfo(item)
        end)
        if okDose and doseInfo and doseInfo.maxDoses and doseInfo.maxDoses > 1 then
            addWrappedLines(string.format("Remaining: %d/%d", doseInfo.remainingDoses or 0, doseInfo.maxDoses), {r=0.45, g=0.9, b=1.0})
        end
    end

    -- Separator
    table.insert(lines, {text = "---", color = {r=0.4, g=0.4, b=0.4}})
    totalHeight = totalHeight + fontHeight + lineSpacing

    -- Description (with wrapping)
    if data.description then
        local descLines = wrapText(data.description, maxLineWidth, {r=0.9, g=0.9, b=0.9})
        for _, line in ipairs(descLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Effects (with wrapping)
    if data.effects and #data.effects > 0 then
        addSpacer()
        for _, effect in ipairs(data.effects) do
            local effectLines = wrapText("+ " .. effect, maxLineWidth, {r=0.3, g=0.9, b=0.3})
            for _, line in ipairs(effectLines) do
                table.insert(lines, line)
                totalHeight = totalHeight + fontHeight + lineSpacing
            end
        end
    end

    if data.bloodCompatibility then
        local canReadCompatibility = EHR.Tooltips.HasBloodTypeKnowledge and EHR.Tooltips.HasBloodTypeKnowledge(self)
        if canReadCompatibility then
            addWrappedLines(data.bloodCompatibility, {r=0.3, g=0.8, b=1.0})
        else
            addWrappedLines("Compatibility: unknown (read Blood Types flyer or reach First Aid 8)", {r=0.7, g=0.7, b=0.7})
        end
    end

    -- Cures (with wrapping)
    if data.cures and #data.cures > 0 then
        local curesText = "CURES: " .. table.concat(data.cures, ", ")
        local curesLines = wrapText(curesText, maxLineWidth, {r=0.3, g=0.8, b=1.0})
        for _, line in ipairs(curesLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Relieves (with wrapping)
    if data.relieves and #data.relieves > 0 then
        local relievesText = "Relieves: " .. table.concat(data.relieves, ", ")
        local relievesLines = wrapText(relievesText, maxLineWidth, {r=0.9, g=0.9, b=0.3})
        for _, line in ipairs(relievesLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Treatment time
    if data.treatmentTime then
        addWrappedLines("Treatment time: " .. data.treatmentTime, {r=0.7, g=0.7, b=0.7})
    end

    -- Requirements (with wrapping)
    if data.requirements and #data.requirements > 0 then
        local reqText = "Requires: " .. table.concat(data.requirements, ", ")
        local reqLines = wrapText(reqText, maxLineWidth, {r=0.9, g=0.6, b=0.2})
        for _, line in ipairs(reqLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Side effects (with wrapping)
    if data.sideEffects and #data.sideEffects > 0 then
        addSpacer()
        table.insert(lines, {text = "SIDE EFFECTS:", color = {r=1.0, g=0.5, b=0.0}})
        totalHeight = totalHeight + fontHeight + lineSpacing
        for _, sideEffect in ipairs(data.sideEffects) do
            local seLines = wrapText("  - " .. sideEffect, maxLineWidth, {r=1.0, g=0.6, b=0.2})
            for _, line in ipairs(seLines) do
                table.insert(lines, line)
                totalHeight = totalHeight + fontHeight + lineSpacing
            end
        end
    end

    -- Warning (with wrapping)
    if data.warning then
        local warningLines = wrapText("! " .. data.warning, maxLineWidth, {r=1.0, g=0.3, b=0.3})
        for _, line in ipairs(warningLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Success/Failure text (for Gene Therapy etc)
    if data.successText then
        addWrappedLines("+ " .. data.successText, {r=0.3, g=1.0, b=0.3})
    end
    if data.failureText then
        addWrappedLines("- " .. data.failureText, {r=1.0, g=0.3, b=0.3})
    end

    -- Spoilage time for perishable items (blood bags, saline, etc.)
    if EHR.DEBUG then
        print("[EHR Tooltip DEBUG] data.perishable = " .. tostring(data.perishable))
    end
    if data.perishable then
        local age = 0
        local offAgeMax = 0
        local offAge = 0

        -- Safely get age values - try multiple methods
        pcall(function()
            -- Method 1: Direct item methods (works for food items)
            if item.getAge then age = item:getAge() or 0 end
            if item.getOffAgeMax then offAgeMax = item:getOffAgeMax() or 0 end
            if item.getOffAge then offAge = item:getOffAge() or 0 end

            -- Method 2: If values are 0 or unreasonably high (default 1 billion = "never spoils"),
            -- try getting from script item (for non-food items like blood bags)
            local UNREASONABLE_AGE = 100000  -- ~11 years in hours, anything above this is "not set"
            if offAgeMax == 0 or offAge == 0 or offAgeMax >= UNREASONABLE_AGE or offAge >= UNREASONABLE_AGE then
                local scriptItem = item:getScriptItem()
                if scriptItem then
                    -- DaysFresh and DaysTotallyRotten are in days, convert to hours
                    if scriptItem.getDaysFresh then
                        local daysFresh = scriptItem:getDaysFresh() or 0
                        if daysFresh > 0 then
                            offAge = daysFresh * 24  -- Convert days to hours
                        end
                    end
                    if scriptItem.getDaysTotallyRotten then
                        local daysRotten = scriptItem:getDaysTotallyRotten() or 0
                        if daysRotten > 0 then
                            offAgeMax = daysRotten * 24  -- Convert days to hours
                        end
                    end
                end
            end
        end)

        -- DEBUG: Log the values we got (only in debug mode)
        if EHR.DEBUG then
            print("[EHR Tooltip DEBUG] Perishable item - age: " .. tostring(age) .. ", offAge: " .. tostring(offAge) .. ", offAgeMax: " .. tostring(offAgeMax))
            table.insert(lines, {text = "DEBUG: age=" .. tostring(age) .. " offAge=" .. tostring(offAge) .. " offAgeMax=" .. tostring(offAgeMax), color = {r=1, g=1, b=0}})
            totalHeight = totalHeight + fontHeight + lineSpacing
        end

        -- Blood bags use EHR's warm-time spoilage so old saves and newly filled bags behave consistently.
        local customSpoilage = nil
        pcall(function()
            if EHR.Transfusion and EHR.Transfusion.GetBloodBagSpoilageInfo then
                customSpoilage = EHR.Transfusion.GetBloodBagSpoilageInfo(item)
            end
        end)

        if customSpoilage then
            local spoilText = ""
            local spoilColor = {r=0.7, g=0.7, b=0.7}

            if customSpoilage.isFrozen then
                spoilText = "FROZEN - spoil timer paused"
                spoilColor = {r=0.4, g=0.8, b=1.0}
            elseif customSpoilage.state == "rotten" then
                spoilText = "SPOILED - Do not use!"
                spoilColor = {r=1.0, g=0.2, b=0.2}
            elseif customSpoilage.state == "stale" then
                local timeText = tostring(math.floor(customSpoilage.hoursUntilRotten or 0)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(customSpoilage.hoursUntilRotten or 0) end)
                end
                spoilText = "STALE - Spoils in: " .. timeText
                spoilColor = {r=1.0, g=0.6, b=0.2}
            else
                local timeText = tostring(math.floor(customSpoilage.hoursUntilStale or 0)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(customSpoilage.hoursUntilStale or 0) end)
                end
                spoilText = "Fresh for: " .. timeText
                spoilColor = {r=0.5, g=0.9, b=0.5}
            end

            table.insert(lines, {text = spoilText, color = spoilColor})
            totalHeight = totalHeight + fontHeight + lineSpacing
        elseif offAgeMax > 0 then
            local hoursUntilRotten = offAgeMax - age
            local hoursUntilStale = offAge - age

            local spoilText = ""
            local spoilColor = {r=0.7, g=0.7, b=0.7}

            if hoursUntilRotten <= 0 then
                -- Already rotten
                spoilText = "SPOILED - Do not use!"
                spoilColor = {r=1.0, g=0.2, b=0.2}
            elseif hoursUntilStale <= 0 then
                -- Stale but not rotten
                local timeText = tostring(math.floor(hoursUntilRotten)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(hoursUntilRotten) end)
                end
                spoilText = "STALE - Spoils in: " .. timeText
                spoilColor = {r=1.0, g=0.6, b=0.2}
            else
                -- Still fresh
                local timeText = tostring(math.floor(hoursUntilStale)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(hoursUntilStale) end)
                end
                spoilText = "Fresh for: " .. timeText
                spoilColor = {r=0.5, g=0.9, b=0.5}
            end

            table.insert(lines, {text = spoilText, color = spoilColor})
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Weight/Encumbrance
    local weight = item:getUnequippedWeight()
    if weight then
        addSpacer()
        table.insert(lines, {text = string.format("Encumbrance: %.1f", weight), color = {r=0.6, g=0.6, b=0.6}})
        totalHeight = totalHeight + fontHeight + lineSpacing
    end

    -- Calculate max width from text
    for _, line in ipairs(lines) do
        local lineWidth = getTextManager():MeasureStringX(font, line.text)
        if lineWidth > maxWidth then
            maxWidth = math.min(lineWidth, maxLineWidth)
        end
    end

    -- Add padding
    local padding = 10
    local boxWidth = maxWidth + (padding * 2)
    local boxHeight = totalHeight + (padding * 2)

    -- Keep tooltip on screen
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    if mx + boxWidth > screenW then
        mx = screenW - boxWidth - 5
    end
    if my + boxHeight > screenH then
        my = screenH - boxHeight - 5
    end
    mx = math.max(5, mx)
    my = math.max(5, my)

    -- Position and size the tooltip panel
    self:setX(mx)
    self:setY(my)
    self:setWidth(boxWidth)
    self:setHeight(boxHeight)

    -- Draw background (relative coords: 0,0 is top-left of tooltip)
    self:drawRect(0, 0, boxWidth, boxHeight, 0.95, 0.08, 0.08, 0.1)

    -- Draw border
    local borderColor = EHR.Tooltips.GetCategoryColor(data.category or "Medical Supply")
    self:drawRectBorder(0, 0, boxWidth, boxHeight, 1, borderColor.r, borderColor.g, borderColor.b)

    -- Draw header highlight
    self:drawRect(1, 1, boxWidth - 2, fontHeight + lineSpacing + 4, 0.3, borderColor.r, borderColor.g, borderColor.b)

    -- Draw lines (relative to tooltip top-left)
    local y = padding
    for i, line in ipairs(lines) do
        local c = line.color
        if line.text ~= " " then
            self:drawText(fitText(line.text, boxWidth - padding * 2), padding, y, c.r, c.g, c.b, 1, font)
        end
        y = y + fontHeight + lineSpacing
    end

    return true -- Signal successful render
end

-- Assign the shared implementation to both tooltip classes
function ISToolTipInv:renderEHRTooltip(data, item)
    return renderEHRTooltipImpl(self, data, item)
end

-- Only assign to ISFoodToolTip if it exists
if ISFoodToolTip and type(ISFoodToolTip) == "table" then
    function ISFoodToolTip:renderEHRTooltip(data, item)
        return renderEHRTooltipImpl(self, data, item)
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

local function OnGameStart()
    -- Register translations when game starts
    EHR.Tooltips.RegisterTranslations()
end

Events.OnGameStart.Add(OnGameStart)

-- Also register on load for clients joining MP
local function OnMainMenuEnter()
    EHR.Tooltips.RegisterTranslations()
end

Events.OnMainMenuEnter.Add(OnMainMenuEnter)

EHR.Log("EHR_TooltipSystem.lua loaded - Custom tooltip system active")
