--[[
    Extensive Health Rework - Tooltip System

    Handles tooltip registration and custom rendering for EHR items.
    This system provides rich, formatted tooltips with categories,
    effects, side effects, and more.

    Author: ExtensiveHealthRework Team
    Version: 1.0
]]

require "ISUI/ISToolTipInv"

-- Ensure TooltipData is loaded (should be loaded from shared already)
if not EHR or not EHR.Tooltips or not EHR.Tooltips.Data then
    -- Try to require it if not already loaded
    pcall(function() require "ExtensiveHealth/EHR_TooltipData" end)
end
pcall(function() require "ExtensiveHealth/EHR_Medication" end)
pcall(function() require "ExtensiveHealth/EHR_DiseaseFlyers" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
pcall(function() require "ExtensiveHealth/EHR_KnoxCure" end)
pcall(function() require "ExtensiveHealth/EHR_WatchBatteryCore" end)

EHR = EHR or {}
EHR.Tooltips = EHR.Tooltips or {}


local function tooltipItemName(itemFullType)
    itemFullType = tostring(itemFullType or "")
    return (itemFullType:match("%.(.+)$") or itemFullType):gsub("[^%w_]", "_")
end

local function tooltipText(itemFullType, suffix, fallback)
    local key = "Tooltip_EHR_" .. tooltipItemName(itemFullType) .. "_" .. tostring(suffix or "Text")
    return EHR.Locale.Text(key, fallback)
end

local function tooltipLabel(key, fallback)
    return EHR.Locale.Text("Tooltip_EHR_Label_" .. key, fallback)
end

local function tooltipFormat(key, fallback, ...)
    return EHR.Locale.Format("Tooltip_EHR_Label_" .. key, fallback, ...)
end

local function tooltipListValue(itemFullType, prefix, index, fallback)
    return tooltipText(itemFullType, prefix .. "_" .. tostring(index), fallback)
end

local function tooltipSuccessText(itemFullType, data)
    if tostring(itemFullType or "") == "ExtensiveHealth.GeneTherapyKit"
            and EHR.KnoxCure
            and EHR.KnoxCure.IsPatientZeroTraitEnabled
            and not EHR.KnoxCure.IsPatientZeroTraitEnabled() then
        return tooltipText(itemFullType, "SuccessText_PatientZeroDisabled", "SUCCESS: Current Knox infection cured")
    end
    return tooltipText(itemFullType, "SuccessText", data.successText)
end

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
        return tooltipLabel("ZeroHours", "0 hours")
    end

    if hours < 1 then
        local minutes = math.max(1, math.ceil(hours * 60))
        return tooltipFormat("Minutes", "%1 min", minutes)
    end

    local days = math.floor(hours / 24)
    local remainingHours = math.floor(hours % 24)

    if days > 0 then
        if remainingHours > 0 then
            return tooltipFormat("DaysHours", "%1 day(s) %2 hr(s)", days, remainingHours)
        else
            return tooltipFormat("Days", "%1 day(s)", days)
        end
    else
        return tooltipFormat("Hours", "%1 hour(s)", remainingHours)
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
            local tooltipText = EHR.Tooltips.BuildTooltipText(data, itemFullType)

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
function EHR.Tooltips.BuildTooltipText(data, itemFullType)
    local lines = {}
    itemFullType = itemFullType or ""

    -- Description
    if data.description then
        table.insert(lines, tooltipText(itemFullType, "Description", data.description))
    end

    -- Empty line separator
    table.insert(lines, " ")

    -- Effects
    if data.effects and #data.effects > 0 then
        for i, effect in ipairs(data.effects) do
            table.insert(lines, "<RGB:0.3,0.9,0.3> + " .. tooltipListValue(itemFullType, "Effect", i, effect))
        end
    end

    -- What it cures
    if data.cures and #data.cures > 0 then
        local localized = {}
        for i, cure in ipairs(data.cures) do table.insert(localized, tooltipListValue(itemFullType, "Cure", i, cure)) end
        local curesText = "<RGB:0.3,0.8,1.0> " .. tooltipLabel("Cures", "CURES:") .. " " .. table.concat(localized, ", ")
        table.insert(lines, curesText)
    end

    -- What it relieves (doesn't cure)
    if data.relieves and #data.relieves > 0 then
        local localized = {}
        for i, relief in ipairs(data.relieves) do table.insert(localized, tooltipListValue(itemFullType, "Relief", i, relief)) end
        local relievesText = "<RGB:0.9,0.9,0.3> " .. tooltipLabel("Relieves", "Relieves:") .. " " .. table.concat(localized, ", ")
        table.insert(lines, relievesText)
    end

    -- Treatment time
    if data.treatmentTime then
        table.insert(lines, "<RGB:0.7,0.7,0.7> " .. tooltipLabel("TreatmentTime", "Treatment time:") .. " " .. tooltipText(itemFullType, "TreatmentTime", data.treatmentTime))
    end

    -- Requirements
    if data.requirements and #data.requirements > 0 then
        local localized = {}
        for i, req in ipairs(data.requirements) do table.insert(localized, tooltipListValue(itemFullType, "Requirement", i, req)) end
        local reqText = "<RGB:0.9,0.6,0.2> " .. tooltipLabel("Requires", "Requires:") .. " " .. table.concat(localized, ", ")
        table.insert(lines, reqText)
    end

    -- Side effects (each on its own line)
    if data.sideEffects and #data.sideEffects > 0 then
        table.insert(lines, "<RGB:1.0,0.5,0.0> " .. tooltipLabel("SideEffects", "SIDE EFFECTS:"))
        for i, sideEffect in ipairs(data.sideEffects) do
            table.insert(lines, "<RGB:1.0,0.6,0.2>   - " .. tooltipListValue(itemFullType, "SideEffect", i, sideEffect))
        end
    end

    -- Warning
    if data.warning then
        table.insert(lines, "<RGB:1.0,0.3,0.3> ! " .. tooltipText(itemFullType, "Warning", data.warning))
    end

    -- Success/Failure text (for Gene Therapy etc)
    if data.successText then
        table.insert(lines, "<RGB:0.3,1.0,0.3> + " .. tooltipSuccessText(itemFullType, data))
    end
    if data.failureText then
        table.insert(lines, "<RGB:1.0,0.3,0.3> - " .. tooltipText(itemFullType, "FailureText", data.failureText))
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

local function watchBatteryText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_WatchBattery_" .. tostring(key), fallback)
    end
    return fallback
end

local function formatWatchTime(hour, minute)
    hour = math.floor(tonumber(hour) or 0) % 24
    minute = math.floor(tonumber(minute) or 0) % 60

    local use24Hour = true
    if getCore then
        local core = getCore()
        if core and core.getOptionClock24Hour then
            use24Hour = core:getOptionClock24Hour()
        end
    end

    if use24Hour then
        return string.format("%02d:%02d", hour, minute)
    end

    local suffix = hour >= 12 and "PM" or "AM"
    local displayHour = hour % 12
    if displayHour == 0 then displayHour = 12 end
    return string.format("%d:%02d %s", displayHour, minute, suffix)
end

local function getCurrentWatchTime()
    local gameTime = getGameTime and getGameTime() or nil
    local timeOfDay = gameTime and gameTime.getTimeOfDay and tonumber(gameTime:getTimeOfDay()) or 0
    local totalMinutes = math.floor((timeOfDay % 24) * 60 + 0.5) % (24 * 60)
    return math.floor(totalMinutes / 60), totalMinutes % 60
end

local function renderMedicalWatchTooltip(self, item)
    if not self or not item or not EHR.WatchBattery or not EHR.WatchBattery.IsMedicalWatch(item) then
        return false
    end
    if not getTextManager or not UIFont or not getCore then return false end

    local textManager = getTextManager()
    if not textManager then return false end

    local state = EHR.WatchBattery.GetState(item)
    local installed = state and state.installed == true
    local charge = installed and math.max(0, math.min(1, tonumber(state.charge) or 0)) or 0
    local powered = installed and charge > 0
    local percent = math.floor(charge * 100 + 0.5)
    local font = UIFont.Small
    local fontHeight = textManager:getFontHeight(font)
    local lineGap = 4
    local lineHeight = fontHeight + lineGap
    local padding = 10
    local barHeight = 10
    local lines = {}

    local displayName = item:getDisplayName() or item:getName() or "Medical Monitor Watch"
    table.insert(lines, { text = displayName, color = { r = 1.0, g = 1.0, b = 1.0 }, header = true })

    if powered then
        local hour, minute = getCurrentWatchTime()
        local timeText = watchBatteryText("Time", "Time") .. ": " .. formatWatchTime(hour, minute)
        table.insert(lines, { text = timeText, color = { r = 0.45, g = 0.90, b = 1.0 } })

        local alarmSet = false
        pcall(function() alarmSet = item:isAlarmSet() == true end)
        if alarmSet then
            local alarmHour = 0
            local alarmMinute = 0
            pcall(function()
                alarmHour = item:getHour()
                alarmMinute = item:getMinute()
            end)
            local alarmText = watchBatteryText("Alarm", "Alarm") .. ": " .. formatWatchTime(alarmHour, alarmMinute)
            table.insert(lines, { text = alarmText, color = { r = 0.90, g = 0.70, b = 0.25 } })
        end
    end

    local batteryValue = tostring(percent) .. "%"
    local batteryColor = { r = 0.20, g = 0.82, b = 0.36 }
    if not installed then
        batteryValue = watchBatteryText("NotInstalled", "Not installed")
        batteryColor = { r = 0.70, g = 0.70, b = 0.70 }
    elseif charge <= 0 then
        batteryValue = watchBatteryText("Depleted", "Depleted")
        batteryColor = { r = 0.95, g = 0.22, b = 0.14 }
    elseif charge <= 0.20 then
        batteryColor = { r = 0.95, g = 0.22, b = 0.14 }
    elseif charge <= 0.50 then
        batteryColor = { r = 0.95, g = 0.68, b = 0.12 }
    end
    table.insert(lines, {
        text = watchBatteryText("Battery", "Battery") .. ": " .. batteryValue,
        color = batteryColor,
        batteryBar = true,
    })

    local weight = item.getUnequippedWeight and tonumber(item:getUnequippedWeight()) or nil
    if weight then
        table.insert(lines, {
            text = tooltipFormat("Encumbrance", "Encumbrance: %1", string.format("%.1f", weight)),
            color = { r = 0.62, g = 0.62, b = 0.62 },
        })
    end

    local maxTextWidth = 210
    for _, line in ipairs(lines) do
        maxTextWidth = math.max(maxTextWidth, textManager:MeasureStringX(font, line.text))
    end
    local boxWidth = math.min(340, maxTextWidth + padding * 2)
    local boxHeight = padding * 2 + (#lines * lineHeight) + barHeight + 6

    local mx = getMouseX() + 24
    local my = getMouseY() + 24
    if self.followMouse == false then
        mx = self:getX()
        my = self:getY()
        if self.anchorBottomLeft then
            mx = self.anchorBottomLeft.x
            my = self.anchorBottomLeft.y - boxHeight
        end
    end

    local core = getCore()
    mx = math.max(5, math.min(mx, core:getScreenWidth() - boxWidth - 5))
    my = math.max(5, math.min(my, core:getScreenHeight() - boxHeight - 5))
    self:setX(mx)
    self:setY(my)
    self:setWidth(boxWidth)
    self:setHeight(boxHeight)

    local border = { r = 0.30, g = 0.62, b = 0.50 }
    self:drawRect(0, 0, boxWidth, boxHeight, 0.95, 0.08, 0.08, 0.10)
    self:drawRectBorder(0, 0, boxWidth, boxHeight, 1.0, border.r, border.g, border.b)
    self:drawRect(1, 1, boxWidth - 2, lineHeight + 2, 0.30, border.r, border.g, border.b)

    local y = padding
    for _, line in ipairs(lines) do
        local c = line.color
        self:drawText(line.text, padding, y, c.r, c.g, c.b, 1.0, font)
        y = y + lineHeight

        if line.batteryBar then
            local barWidth = boxWidth - padding * 2
            local innerWidth = math.max(0, barWidth - 2)
            local fillWidth = math.floor(innerWidth * charge + 0.5)
            self:drawRect(padding, y, barWidth, barHeight, 0.90, 0.02, 0.03, 0.03)
            if fillWidth > 0 then
                self:drawRect(padding + 1, y + 1, fillWidth, barHeight - 2, 0.95, batteryColor.r, batteryColor.g, batteryColor.b)
            end
            self:drawRectBorder(padding, y, barWidth, barHeight, 0.90, 0.34, 0.44, 0.40)
            y = y + barHeight + 6
        end
    end

    return true
end

-- Custom tooltip render with safety fallback
function ISToolTipInv:render()
    local useVanilla = true

    -- Try EHR custom tooltip first
    local item = self.item
    if item and EHR and EHR.WatchBattery and EHR.WatchBattery.IsMedicalWatch(item) then
        local success, rendered = pcall(function()
            return renderMedicalWatchTooltip(self, item)
        end)
        if success and rendered then
            useVanilla = false
        elseif not success then
            print("[EHR Tooltip] ERROR rendering Medical Monitor Watch: " .. tostring(rendered))
        end
    end

    if useVanilla and item and EHR and EHR.Tooltips and EHR.Tooltips.GetData then
        local itemFullType = item.getFullType and item:getFullType() or nil
        local ehrData = itemFullType and EHR.Tooltips.GetData(itemFullType) or nil

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
    local itemFullType = item and item.getFullType and item:getFullType() or ""

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
        local catText = tooltipText(itemFullType, "Category", data.category)
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
            addWrappedLines(tooltipFormat("Remaining", "Remaining: %1/%2", doseInfo.remainingDoses or 0, doseInfo.maxDoses), {r=0.45, g=0.9, b=1.0})
        end
    end

    -- Separator
    table.insert(lines, {text = "---", color = {r=0.4, g=0.4, b=0.4}})
    totalHeight = totalHeight + fontHeight + lineSpacing

    -- Description (with wrapping)
    if data.description then
        local descLines = wrapText(tooltipText(itemFullType, "Description", data.description), maxLineWidth, {r=0.9, g=0.9, b=0.9})
        for _, line in ipairs(descLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Effects (with wrapping)
    if data.effects and #data.effects > 0 then
        addSpacer()
        for i, effect in ipairs(data.effects) do
            local effectLines = wrapText("+ " .. tooltipListValue(itemFullType, "Effect", i, effect), maxLineWidth, {r=0.3, g=0.9, b=0.3})
            for _, line in ipairs(effectLines) do
                table.insert(lines, line)
                totalHeight = totalHeight + fontHeight + lineSpacing
            end
        end
    end

    if data.bloodCompatibility then
        local canReadCompatibility = EHR.Tooltips.HasBloodTypeKnowledge and EHR.Tooltips.HasBloodTypeKnowledge(self)
        if canReadCompatibility then
            addWrappedLines(tooltipText(itemFullType, "BloodCompatibility", data.bloodCompatibility), {r=0.3, g=0.8, b=1.0})
        else
            addWrappedLines(tooltipLabel("CompatibilityUnknown", "Compatibility: unknown (read Blood Types flyer or reach First Aid 8)"), {r=0.7, g=0.7, b=0.7})
        end
    end

    -- Cures (with wrapping)
    if data.cures and #data.cures > 0 then
        local localized = {}
        for i, cure in ipairs(data.cures) do table.insert(localized, tooltipListValue(itemFullType, "Cure", i, cure)) end
        local curesText = tooltipLabel("Cures", "CURES:") .. " " .. table.concat(localized, ", ")
        local curesLines = wrapText(curesText, maxLineWidth, {r=0.3, g=0.8, b=1.0})
        for _, line in ipairs(curesLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Relieves (with wrapping)
    if data.relieves and #data.relieves > 0 then
        local localized = {}
        for i, relief in ipairs(data.relieves) do table.insert(localized, tooltipListValue(itemFullType, "Relief", i, relief)) end
        local relievesText = tooltipLabel("Relieves", "Relieves:") .. " " .. table.concat(localized, ", ")
        local relievesLines = wrapText(relievesText, maxLineWidth, {r=0.9, g=0.9, b=0.3})
        for _, line in ipairs(relievesLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Treatment time
    if data.treatmentTime then
        addWrappedLines(tooltipLabel("TreatmentTime", "Treatment time:") .. " " .. tooltipText(itemFullType, "TreatmentTime", data.treatmentTime), {r=0.7, g=0.7, b=0.7})
    end

    -- Requirements (with wrapping)
    if data.requirements and #data.requirements > 0 then
        local localized = {}
        for i, req in ipairs(data.requirements) do table.insert(localized, tooltipListValue(itemFullType, "Requirement", i, req)) end
        local reqText = tooltipLabel("Requires", "Requires:") .. " " .. table.concat(localized, ", ")
        local reqLines = wrapText(reqText, maxLineWidth, {r=0.9, g=0.6, b=0.2})
        for _, line in ipairs(reqLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Side effects (with wrapping)
    if data.sideEffects and #data.sideEffects > 0 then
        addSpacer()
        table.insert(lines, {text = tooltipLabel("SideEffects", "SIDE EFFECTS:"), color = {r=1.0, g=0.5, b=0.0}})
        totalHeight = totalHeight + fontHeight + lineSpacing
        for i, sideEffect in ipairs(data.sideEffects) do
            local seLines = wrapText("  - " .. tooltipListValue(itemFullType, "SideEffect", i, sideEffect), maxLineWidth, {r=1.0, g=0.6, b=0.2})
            for _, line in ipairs(seLines) do
                table.insert(lines, line)
                totalHeight = totalHeight + fontHeight + lineSpacing
            end
        end
    end

    -- Warning (with wrapping)
    if data.warning then
        local warningLines = wrapText("! " .. tooltipText(itemFullType, "Warning", data.warning), maxLineWidth, {r=1.0, g=0.3, b=0.3})
        for _, line in ipairs(warningLines) do
            table.insert(lines, line)
            totalHeight = totalHeight + fontHeight + lineSpacing
        end
    end

    -- Success/Failure text (for Gene Therapy etc)
    if data.successText then
        addWrappedLines("+ " .. tooltipSuccessText(itemFullType, data), {r=0.3, g=1.0, b=0.3})
    end
    if data.failureText then
        addWrappedLines("- " .. tooltipText(itemFullType, "FailureText", data.failureText), {r=1.0, g=0.3, b=0.3})
    end

    -- Spoilage time for perishable items (blood bags, saline, etc.)
    if EHR.DEBUG then
        EHR.Log("[Tooltip DEBUG] data.perishable = " .. tostring(data.perishable))
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
            EHR.Log("[Tooltip DEBUG] Perishable item - age: " .. tostring(age) .. ", offAge: " .. tostring(offAge) .. ", offAgeMax: " .. tostring(offAgeMax))
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
                spoilText = tooltipLabel("FrozenSpoilage", "FROZEN - spoil timer paused")
                spoilColor = {r=0.4, g=0.8, b=1.0}
            elseif customSpoilage.state == "rotten" then
                spoilText = tooltipLabel("Spoiled", "SPOILED - Do not use!")
                spoilColor = {r=1.0, g=0.2, b=0.2}
            elseif customSpoilage.state == "stale" then
                local timeText = tostring(math.floor(customSpoilage.hoursUntilRotten or 0)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(customSpoilage.hoursUntilRotten or 0) end)
                end
                spoilText = tooltipLabel("StaleSpoilsIn", "STALE - Spoils in:") .. " " .. timeText
                spoilColor = {r=1.0, g=0.6, b=0.2}
            else
                local timeText = tostring(math.floor(customSpoilage.hoursUntilStale or 0)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(customSpoilage.hoursUntilStale or 0) end)
                end
                spoilText = tooltipLabel("FreshFor", "Fresh for:") .. " " .. timeText
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
                spoilText = tooltipLabel("Spoiled", "SPOILED - Do not use!")
                spoilColor = {r=1.0, g=0.2, b=0.2}
            elseif hoursUntilStale <= 0 then
                -- Stale but not rotten
                local timeText = tostring(math.floor(hoursUntilRotten)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(hoursUntilRotten) end)
                end
                spoilText = tooltipLabel("StaleSpoilsIn", "STALE - Spoils in:") .. " " .. timeText
                spoilColor = {r=1.0, g=0.6, b=0.2}
            else
                -- Still fresh
                local timeText = tostring(math.floor(hoursUntilStale)) .. " hours"
                if EHR.Tooltips.FormatTimeRemaining then
                    pcall(function() timeText = EHR.Tooltips.FormatTimeRemaining(hoursUntilStale) end)
                end
                spoilText = tooltipLabel("FreshFor", "Fresh for:") .. " " .. timeText
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
        table.insert(lines, {text = tooltipFormat("Encumbrance", "Encumbrance: %1", string.format("%.1f", weight)), color = {r=0.6, g=0.6, b=0.6}})
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
