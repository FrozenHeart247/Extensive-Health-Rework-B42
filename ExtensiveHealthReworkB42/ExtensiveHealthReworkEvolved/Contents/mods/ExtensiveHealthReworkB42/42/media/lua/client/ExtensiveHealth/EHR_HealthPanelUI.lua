--[[
    Extensive Health Rework - Health Panel UI prototype

    Replacement-style health overview opened from the EHR health hotkey.
    This is intentionally read-only: it presents EHR data without changing
    disease, medication, blood, or vanilla health mechanics.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/BodyParts/ISBodyPartPanel"
require "XpSystem/ISUI/ISHealthPanel"
require "XpSystem/ISUI/ISCharacterScreen"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISCharacterProtection"
require "XpSystem/ISUI/ISClothingInsPanel"
pcall(function() require "ISUI/ISEquippedItem" end)
pcall(function() require "TimedActions/ISBaseTimedAction" end)
pcall(function() require "TimedActions/ISInventoryTransferUtil" end)
pcall(function() require "TimedActions/ISApplyBandage" end)
pcall(function() require "TimedActions/ISCleanBurn" end)
pcall(function() require "TimedActions/ISComfreyCataplasm" end)
pcall(function() require "TimedActions/ISDisinfect" end)
pcall(function() require "TimedActions/ISGarlicCataplasm" end)
pcall(function() require "TimedActions/ISPlantainCataplasm" end)
pcall(function() require "TimedActions/ISRemoveBullet" end)
pcall(function() require "TimedActions/ISRemoveGlass" end)
pcall(function() require "TimedActions/ISSplint" end)
pcall(function() require "TimedActions/ISStitch" end)
require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_DiseaseFlyers"
pcall(function() require "ExtensiveHealth/EHR_WatchBatteryCore" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
pcall(function() require "ExtensiveHealth/EHR_BandagePack" end)
pcall(function() require "ExtensiveHealth/EHR_Immunity" end)

EHR = EHR or {}
EHR.UI = EHR.UI or {}

EHR_HealthPanelUI = ISPanel:derive("EHR_HealthPanelUI")
EHR_HealthBodyPartPanel = ISBodyPartPanel:derive("EHR_HealthBodyPartPanel")
EHR_RemoteMedicalAction = ISBaseTimedAction:derive("EHR_RemoteMedicalAction")

local antibodiesWindowModule = nil
local antibodiesWindowChecked = false

EHR_HealthPanelUI.EXPANDED_WIDTH = 990
EHR_HealthPanelUI.COLLAPSED_WIDTH = 500
EHR_HealthPanelUI.HEIGHT = 780
EHR_HealthPanelUI.MIN_WIDTH = 460
EHR_HealthPanelUI.MIN_HEIGHT = 700
EHR_HealthPanelUI.RESIZE_SIZE = 18
EHR_HealthPanelUI.HEADER_HEIGHT = 40
EHR_HealthPanelUI.TAB_HEIGHT = 72
EHR_HealthPanelUI.BLOOD_PANEL_HEIGHT = 122
EHR_HealthPanelUI.LEFT_WIDTH = 390
EHR_HealthPanelUI.SCROLL_STEP = 32
EHR_HealthPanelUI.TEXT_DOCK_Y_BIAS = -2
EHR_HealthPanelUI.REMOTE_EXAM_MAX_DISTANCE = 4.0
EHR_HealthPanelUI.REMOTE_EXAM_MOVE_TOLERANCE = 0.75

EHR_HealthPanelUI.Colors = {
    background = { r = 0.025, g = 0.025, b = 0.028, a = 0.97 },
    panel = { r = 0.055, g = 0.055, b = 0.06, a = 0.94 },
    panelSoft = { r = 0.09, g = 0.085, b = 0.085, a = 0.72 },
    header = { r = 0.035, g = 0.035, b = 0.038, a = 0.98 },
    border = { r = 0.48, g = 0.14, b = 0.12, a = 1.0 },
    borderDim = { r = 0.24, g = 0.10, b = 0.09, a = 1.0 },
    text = { r = 0.92, g = 0.91, b = 0.86, a = 1.0 },
    textDim = { r = 0.62, g = 0.62, b = 0.62, a = 1.0 },
    green = { r = 0.22, g = 0.88, b = 0.30, a = 1.0 },
    blue = { r = 0.20, g = 0.78, b = 1.0, a = 1.0 },
    yellow = { r = 0.95, g = 0.74, b = 0.18, a = 1.0 },
    orange = { r = 1.0, g = 0.36, b = 0.12, a = 1.0 },
    red = { r = 0.86, g = 0.05, b = 0.045, a = 1.0 },
    redDark = { r = 0.30, g = 0.015, b = 0.015, a = 1.0 },
    purple = { r = 0.58, g = 0.20, b = 0.72, a = 1.0 },
    body = { r = 0.30, g = 0.33, b = 0.31, a = 0.55 },
    bodyHot = { r = 0.64, g = 0.18, b = 0.12, a = 0.82 },
}

EHR_HealthPanelUI.DiseaseIconPaths = {
    unknown = "media/textures/EHR_Disease_Unknown.png",
    ahtr = "media/textures/EHR_Disease_AHTR.png",
    cadaveric_aspergillosis = "media/textures/EHR_Disease_CadavericAspergillosis.png",
    cellulitis = "media/textures/EHR_Disease_Cellulitis.png",
    common_cold = "media/textures/EHR_Disease_CommonCold.png",
    concussion = "media/textures/EHR_Disease_Concussion.png",
    corpse_exposure = "media/textures/EHR_Disease_CorpseSickness.png",
    corpse_sickness = "media/textures/EHR_Disease_CorpseSickness.png",
    delirium = "media/textures/EHR_Disease_Delirium.png",
    dysentery = "media/textures/EHR_Disease_Dysentery.png",
    food_poisoning = "media/textures/EHR_Disease_FoodPoisoning.png",
    gastroenteritis = "media/textures/EHR_Disease_Gastroenteritis.png",
    heat_exhaustion = "media/textures/EHR_Disease_HeatExhaustion.png",
    heat_stroke = "media/textures/EHR_Disease_HeatStroke.png",
    hyperkeratotic_scabies = "media/textures/EHR_Disease_hyperkeratoticScabies.png",
    hypothermia = "media/textures/EHR_Disease_Hypotermia.png",
    insomnia = "media/textures/EHR_Disease_Insomina.png",
    painkiller_addiction = "media/textures/EHR_Disease_PainkillerAddiction.png",
    knox_infection = "media/textures/EHR_Disease_KnoxInfection.png",
    pneumonia = "media/textures/EHR_Disease_Pneumonia.png",
    sepsis = "media/textures/EHR_Disease_Sepsis.png",
    tetanus = "media/textures/EHR_Disease_Tetanus.png",
    toxin_poisoning = "media/textures/EHR_Disease_ToxinPoisoning.png",
    trichinosis = "media/textures/EHR_Disease_Trichinosis.png",
    tuberculosis = "media/textures/EHR_Disease_Tuberculosis.png",
    wound_infection = "media/textures/EHR_Disease_Wound_Infection.png",
}

EHR_HealthPanelUI.PanelIconPaths = {
    overview = "media/textures/EHR_Overview.png",
    body_status = "media/textures/EHR_BodyStatus.png",
}

local MEDICAL_MONITOR_WATCH_ITEMS = {
    ["ExtensiveHealth.EHRMedicalWatch_Left"] = true,
    ["ExtensiveHealth.EHRMedicalWatch_Right"] = true,
    EHRMedicalWatch_Left = true,
    EHRMedicalWatch_Right = true,
}

local suppressVanillaTicks = 0

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function countTable(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
end

local function formatHours(hours)
    hours = tonumber(hours) or 0
    if hours >= 24 then
        return string.format("%.1fd", hours / 24)
    end
    return string.format("%.1fh", hours)
end

local function healthPanelDisinfectDebug(message)
    if not EHR or EHR.DISINFECT_DEBUG ~= true then return end
    print("[EHR][DisinfectDebug][HealthPanel] " .. tostring(message))
end

local function debugItemName(item)
    if not item then return "nil" end
    local name = nil
    pcall(function()
        if item.getFullType then name = item:getFullType() end
    end)
    if name and name ~= "" then return tostring(name) end
    pcall(function()
        if item.getType then name = item:getType() end
    end)
    return tostring(name or item)
end

local function debugPlayerName(player)
    if not player then return "nil" end
    local name = nil
    pcall(function()
        if player.getUsername then name = player:getUsername() end
    end)
    if name and name ~= "" then return tostring(name) end
    pcall(function()
        if player.getDescriptor and player:getDescriptor() and player:getDescriptor().getForename then
            name = player:getDescriptor():getForename()
        end
    end)
    return tostring(name or player)
end

local function formatShortHours(hours)
    hours = tonumber(hours) or 0
    if hours < 1 then
        return string.format("%.0fm", math.max(0, hours) * 60)
    end
    return formatHours(hours)
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime()
    if gameTime and gameTime.getWorldAgeHours then
        return gameTime:getWorldAgeHours()
    end
    return 0
end

local function getSepsisProgress(sepsisData)
    local stage = clamp(tonumber(sepsisData and sepsisData.stage) or 0, 0, 4)
    if stage <= 0 then
        return 0, 0
    end

    local now = getWorldAgeHours()
    local duration = EHR.Sepsis and EHR.Sepsis.StageDuration and tonumber(EHR.Sepsis.StageDuration[stage]) or nil
    local speedMult = 1.0
    if EHR.Sepsis and EHR.Sepsis.GetSpeedMultiplier then
        local ok, value = pcall(EHR.Sepsis.GetSpeedMultiplier)
        value = tonumber(value)
        if ok and value and value > 0 then
            speedMult = value
        end
    end

    local stageFraction = 0
    if stage >= 4 then
        stageFraction = 1
    elseif duration and duration > 0 then
        local started = tonumber(sepsisData.stageStartTime) or now
        stageFraction = clamp((now - started) / (duration / speedMult), 0, 1)
    end

    return clamp(((stage - 1) + stageFraction) / 4, 0, 1), stage
end

local function getWoundInfectionProgress(woundData)
    if type(woundData) ~= "table" or type(woundData.parts) ~= "table" then
        return 0, 0, nil
    end

    local now = getWorldAgeHours()
    local config = EHR.WoundInfection and EHR.WoundInfection.Config or nil
    local durations = config and config.STAGE_DURATION or nil
    local speedMult = 1.0
    if EHR.WoundInfection and EHR.WoundInfection.GetSpeedMultiplier then
        local ok, value = pcall(EHR.WoundInfection.GetSpeedMultiplier)
        value = tonumber(value)
        if ok and value and value > 0 then
            speedMult = value
        end
    end

    local bestStage = 0
    local bestProgress = 0
    local worstPart = nil

    for partName, partData in pairs(woundData.parts) do
        local stage = clamp(tonumber(partData and partData.stage) or 0, 0, 4)
        if stage > 0 then
            local stageFraction = 0
            local duration = durations and tonumber(durations[stage]) or nil
            if stage >= 4 then
                stageFraction = 1
            elseif duration and duration > 0 then
                local started = tonumber(partData.stageStartTime) or now
                stageFraction = clamp((now - started) / (duration / speedMult), 0, 1)
            end

            local progress = clamp(((stage - 1) + stageFraction) / 4, 0, 1)
            if stage > bestStage or (stage == bestStage and progress > bestProgress) then
                bestStage = stage
                bestProgress = progress
                worstPart = partName
            end
        end
    end

    return bestProgress, bestStage, worstPart
end

local function safeText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text(key, fallback)
    end
    local text = nil
    if getText then
        text = getText(key)
    end
    if not text or text == key or text == "?" then
        return fallback
    end
    return text
end

local function getAntibodiesWindowModule()
    if antibodiesWindowChecked then
        return antibodiesWindowModule
    end

    antibodiesWindowChecked = true

    if getActivatedMods then
        local ok, activeMods = pcall(getActivatedMods)
        if ok and activeMods and activeMods.contains and not activeMods:contains("lgd_antibodies") then
            return nil
        end
    end

    if require then
        local ok, module = pcall(require, "ui/antibodies_window")
        if ok and type(module) == "table" and type(module.show) == "function" then
            if not module.toString then
                function module:toString()
                    return "AntibodiesWindow"
                end
            end
            antibodiesWindowModule = module
        end
    end

    return antibodiesWindowModule
end

local function safeFormat(key, fallback, ...)
    if EHR and EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format(key, fallback, ...)
    end
    local ok, value = pcall(string.format, fallback, ...)
    return ok and value or fallback
end

local function callBodyPartMethod(bodyPart, methodName, fallback)
    if not bodyPart or not methodName then return fallback end
    local method = bodyPart[methodName]
    if not method then return fallback end
    local ok, result = pcall(function()
        return method(bodyPart)
    end)
    if ok then return result end
    return fallback
end

local function getBodyPartCacheKey(bodyPart)
    local partType = callBodyPartMethod(bodyPart, "getType", nil)
    if partType ~= nil then
        return tostring(partType)
    end
    return tostring(bodyPart)
end

local function getBodyPartTypeCacheKey(bodyPartType)
    if bodyPartType == nil then return nil end
    return tostring(bodyPartType)
end

local function bodyPartHasActionableStatus(bodyPart)
    if not bodyPart then return false end

    return callBodyPartMethod(bodyPart, "HasInjury", false) == true
            or callBodyPartMethod(bodyPart, "bandaged", false) == true
            or callBodyPartMethod(bodyPart, "stitched", false) == true
            or callBodyPartMethod(bodyPart, "bleeding", false) == true
            or callBodyPartMethod(bodyPart, "bitten", false) == true
            or callBodyPartMethod(bodyPart, "isCut", false) == true
            or callBodyPartMethod(bodyPart, "scratched", false) == true
            or callBodyPartMethod(bodyPart, "deepWounded", false) == true
            or callBodyPartMethod(bodyPart, "haveGlass", false) == true
            or callBodyPartMethod(bodyPart, "haveBullet", false) == true
            or callBodyPartMethod(bodyPart, "isNeedBurnWash", false) == true
            or (tonumber(callBodyPartMethod(bodyPart, "getBurnTime", 0)) or 0) > 0
            or (tonumber(callBodyPartMethod(bodyPart, "getFractureTime", 0)) or 0) > 0
            or (tonumber(callBodyPartMethod(bodyPart, "getSplintFactor", 0)) or 0) > 0
end

local function snapshotHasActionableStatus(snapshot)
    if type(snapshot) ~= "table" then return false end

    return snapshot.hasInjury == true
            or snapshot.bandaged == true
            or snapshot.stitched == true
            or snapshot.bleeding == true
            or snapshot.bitten == true
            or snapshot.cut == true
            or snapshot.scratched == true
            or snapshot.deepWounded == true
            or snapshot.haveGlass == true
            or snapshot.haveBullet == true
            or snapshot.needBurnWash == true
            or (tonumber(snapshot.burnTime) or 0) > 0
            or (tonumber(snapshot.fractureTime) or 0) > 0
            or (tonumber(snapshot.splintFactor) or 0) > 0
end

local function bodyPartMatchesSnapshot(bodyPart, snapshot)
    if not bodyPart or type(snapshot) ~= "table" then return true end

    local booleanChecks = {
        { "bandaged", "bandaged" },
        { "stitched", "stitched" },
        { "bleeding", "bleeding" },
        { "bitten", "bitten" },
        { "cut", "isCut" },
        { "scratched", "scratched" },
        { "deepWounded", "deepWounded" },
        { "haveGlass", "haveGlass" },
        { "haveBullet", "haveBullet" },
        { "needBurnWash", "isNeedBurnWash" },
    }

    for _, check in ipairs(booleanChecks) do
        local key = check[1]
        if snapshot[key] ~= nil and (callBodyPartMethod(bodyPart, check[2], false) == true) ~= (snapshot[key] == true) then
            return false
        end
    end

    local numericChecks = {
        { "burnTime", "getBurnTime" },
        { "fractureTime", "getFractureTime" },
        { "splintFactor", "getSplintFactor" },
    }

    for _, check in ipairs(numericChecks) do
        local key = check[1]
        if snapshot[key] ~= nil then
            local bodyHas = (tonumber(callBodyPartMethod(bodyPart, check[2], 0)) or 0) > 0
            local snapshotHas = (tonumber(snapshot[key]) or 0) > 0
            if bodyHas ~= snapshotHas then
                return false
            end
        end
    end

    return true
end

function EHR_RemoteMedicalAction:isValid()
    return self.character ~= nil and self.panel ~= nil and self.factory ~= nil
end

function EHR_RemoteMedicalAction:start()
end

function EHR_RemoteMedicalAction:update()
    self:forceComplete()
end

function EHR_RemoteMedicalAction:stop()
    ISBaseTimedAction.stop(self)
end

function EHR_RemoteMedicalAction:perform()
    healthPanelDisinfectDebug(string.format("RemoteMedicalAction.perform start doctor=%s panel=%s factory=%s",
        debugPlayerName(self.character), tostring(self.panel), tostring(self.factory)))
    if self.panel and self.factory then
        if self.panel.syncBodyPartPanelBodyParts then
            self.panel:syncBodyPartPanelBodyParts()
        end
        self.factory(self.panel, self)
    end
    healthPanelDisinfectDebug("RemoteMedicalAction.perform end")
    ISBaseTimedAction.perform(self)
end

function EHR_RemoteMedicalAction:new(character, panel, factory)
    local o = ISBaseTimedAction.new(self, character)
    o.stopOnWalk = false
    o.stopOnRun = true
    o.maxTime = -1
    o.panel = panel
    o.factory = factory
    return o
end

local function copyBodyPartStatuses(statuses)
    local copy = {}
    if type(statuses) ~= "table" then return copy end

    for i, status in ipairs(statuses) do
        copy[i] = {
            key = status.key,
            label = status.label,
            color = status.color,
            visualValue = status.visualValue,
            priority = status.priority,
        }
    end

    return copy
end

local function hideWindow(instance)
    if not instance then return end
    local ok = pcall(function()
        if instance.isVisible and instance:isVisible() then
            instance:setVisible(false)
        end
    end)
    return ok
end

local function hideVanillaHealthWindow()
    if ISCharacterInfoWindow and ISCharacterInfoWindow.instance then
        hideWindow(ISCharacterInfoWindow.instance)
    end
    if getPlayerInfoPanel then
        for playerNum = 0, 3 do
            hideWindow(getPlayerInfoPanel(playerNum))
        end
    end
    if ISHealthPanel and ISHealthPanel.instance then
        hideWindow(ISHealthPanel.instance)
    end
end

local function isVanillaHealthViewName(viewName)
    if not viewName then return false end
    if getText and viewName == getText("IGUI_XP_Health") then return true end
    if xpSystemText and viewName == xpSystemText.health then return true end
    return false
end

local function patchCharacterInfoWindowHealthToggle()
    if not ISCharacterInfoWindow or ISCharacterInfoWindow.ehrHealthToggleSuppressPatch then return end
    if not ISCharacterInfoWindow.toggleView then return end

    local originalToggleView = ISCharacterInfoWindow.toggleView
    ISCharacterInfoWindow.ehrHealthToggleSuppressPatch = true

    ISCharacterInfoWindow.toggleView = function(self, viewName)
        if suppressVanillaTicks > 0 and isVanillaHealthViewName(viewName) then
            hideWindow(self)
            return
        end
        return originalToggleView(self, viewName)
    end
end

local function onTickHideVanilla()
    if suppressVanillaTicks <= 0 then return end
    suppressVanillaTicks = suppressVanillaTicks - 1
    hideVanillaHealthWindow()
end

local function suppressLegacyHealthUI(ticks)
    ticks = ticks or 12
    suppressVanillaTicks = math.max(suppressVanillaTicks, ticks)
    EHR.UI.SuppressLegacyMonitorTicks = math.max(tonumber(EHR.UI.SuppressLegacyMonitorTicks) or 0, ticks)
    hideVanillaHealthWindow()
    if EHR.UI.HideMonitor then
        EHR.UI.HideMonitor()
    end
end

EHR.UI.SuppressLegacyHealthUI = suppressLegacyHealthUI

local function clearLegacyHealthSuppression()
    suppressVanillaTicks = 0
    EHR.UI.SuppressLegacyMonitorTicks = 0
end

EHR.UI.ClearLegacyHealthSuppression = clearLegacyHealthSuppression

function EHR.UI.HideHealthPanelOnly()
    if EHR.UI.HealthPanelInstance then
        EHR.UI.HealthPanelInstance:setVisible(false)
    end
    EHR.UI.HealthPanelVisible = false
end

function EHR.UI.IsEHRPrimaryHealthPanel()
    if EHR.Keybinds and EHR.Keybinds.IsEHRPrimaryHealthPanel then
        return EHR.Keybinds.IsEHRPrimaryHealthPanel()
    end
    return true
end

function EHR.UI.ShouldHeartButtonOpenEHR()
    if EHR.Keybinds and EHR.Keybinds.ShouldHeartButtonOpenEHR then
        return EHR.Keybinds.ShouldHeartButtonOpenEHR()
    end
    return false
end

function EHR.UI.ShouldOpenHealthPanelCompact()
    if EHR.Keybinds and EHR.Keybinds.ShouldOpenHealthPanelCompact then
        return EHR.Keybinds.ShouldOpenHealthPanelCompact()
    end
    return true
end

function EHR.UI.ToggleVanillaHealthPanel(player)
    player = player or (getSpecificPlayer and getSpecificPlayer(0)) or (getPlayer and getPlayer())
    if not player then return end

    clearLegacyHealthSuppression()
    EHR.UI.HideHealthPanelOnly()
    if EHR.UI.HideMonitor then
        EHR.UI.HideMonitor()
    end

    local playerNum = 0
    if player.getPlayerNum then
        playerNum = player:getPlayerNum()
    end

    if EHR.UI.OriginalEquippedItemHealthMouseDown and ISEquippedItem and ISEquippedItem.instance then
        local equipped = ISEquippedItem.instance
        if (not equipped.playerNum or equipped.playerNum == playerNum) and equipped.infopanel and equipped.healthBtn then
            EHR.UI.OriginalEquippedItemHealthMouseDown(equipped, equipped.healthBtn, 0, 0)
            return
        end
    end

    local infoPanel = getPlayerInfoPanel and getPlayerInfoPanel(playerNum) or nil
    if not infoPanel and getPlayerData then
        local data = getPlayerData(playerNum)
        infoPanel = data and data.characterInfo or nil
    end
    if not infoPanel and ISEquippedItem and ISEquippedItem.instance then
        local equipped = ISEquippedItem.instance
        if (not equipped.playerNum or equipped.playerNum == playerNum) and equipped.infopanel then
            infoPanel = equipped.infopanel
        end
    end
    if not infoPanel and ISCharacterInfoWindow and ISCharacterInfoWindow.instance then
        infoPanel = ISCharacterInfoWindow.instance
    end
    if not infoPanel or not infoPanel.toggleView then return end

    local healthViewName = getText("IGUI_XP_Health")
    if infoPanel.isActive and infoPanel:isActive(healthViewName) then
        if infoPanel.close then
            infoPanel:close()
        else
            infoPanel:toggleView(healthViewName)
        end
        return
    end

    if infoPanel.panel and infoPanel.panel.getView and infoPanel.panel:getView(healthViewName) then
        local wasVisible = infoPanel.getIsVisible and infoPanel:getIsVisible()
        infoPanel.panel:activateView(healthViewName)
        infoPanel:setVisible(true)
        if not wasVisible and infoPanel.addToUIManager then
            infoPanel:addToUIManager()
        end
    else
        infoPanel:toggleView(healthViewName)
    end

    if infoPanel.bringToTop and infoPanel.getIsVisible and infoPanel:getIsVisible() then
        infoPanel:bringToTop()
    end
end

local function tableValuesSortedByName(tbl, nameGetter)
    local values = {}
    if type(tbl) ~= "table" then return values end

    for key, value in pairs(tbl) do
        table.insert(values, { id = key, data = value, name = nameGetter(key, value) })
    end

    table.sort(values, function(a, b)
        return tostring(a.name or a.id) < tostring(b.name or b.id)
    end)

    return values
end

function EHR_HealthBodyPartPanel:onRightMouseUp(x, y)
    healthPanelDisinfectDebug(string.format("BodyPartPanel.onRightMouseUp x=%s y=%s parent=%s",
        tostring(x), tostring(y), tostring(self.parent)))
    if UIManager and UIManager.getSpeedControls and UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then
        if not getDebug() then return false end
    end

    local selected = self:getPartForCoordinate(x, y)
    healthPanelDisinfectDebug(string.format("BodyPartPanel selected=%s bodyPart=%s bodyPartType=%s",
        tostring(selected), tostring(selected and selected.bodyPart), tostring(selected and selected.bodyPartType)))
    if selected and selected.bodyPart then
        self:setSelected(x, y, true)
        if self.parent and self.parent.openBodyPartContextMenu then
            self.parent:openBodyPartContextMenu(selected.bodyPart, self:getX() + x, self:getY() + y, selected.bodyPartType)
            return true
        end
    end

    return ISBodyPartPanel.onRightMouseUp(self, x, y)
end

function EHR_HealthBodyPartPanel:onMouseUp(x, y)
    if self.selectedBp and ISMouseDrag and ISMouseDrag.dragging and ISInventoryPane and ISInventoryPane.getActualItems then
        local dragging = ISInventoryPane.getActualItems(ISMouseDrag.dragging)
        if dragging and #dragging > 0 and self.parent and self.parent.dropItemsOnBodyPart then
            self.parent:dropItemsOnBodyPart(self.selectedBp.bodyPart, dragging, self.selectedBp.bodyPartType)
            return true
        end
    end
    return ISBodyPartPanel.onMouseUp(self, x, y)
end

function EHR_HealthPanelUI:new(x, y, player)
    local o = ISPanel:new(x, y, EHR_HealthPanelUI.EXPANDED_WIDTH, EHR_HealthPanelUI.HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.playerNum = player and player:getPlayerNum() or 0
    o.rightExpanded = true
    o.activeTab = "ehr"
    o.selectedZone = "overview"
    o.dragging = false
    o.dragStartX = 0
    o.dragStartY = 0
    o.dragMouseStartX = 0
    o.dragMouseStartY = 0
    o.resizing = false
    o.resizeStartW = 0
    o.resizeStartH = 0
    o.resizeMouseStartX = 0
    o.resizeMouseStartY = 0
    o.contentScrollY = 0
    o.contentHeight = 0
    o.markerBounds = {}
    o.tabBounds = {}
    o.embeddedTabs = {}
    o.cachedData = {}
    o.progressSmoothing = {}
    o.vanillaHealthAdapter = nil
    o.isRemoteHealthPanel = false
    o.remoteDoctor = nil
    o.remotePatient = nil
    o.remotePatientOnlineID = nil
    o.remoteExamData = nil
    o.remoteBodyDamageRefreshTicks = 0
    o.remoteBodyDamageAccessTicks = 0
    o.remoteBodyPartStatusCache = {}
    o.remoteActionBodyPartCache = {}
    o.remoteExamRefreshBurst = nil
    o.lastRemoteExamDistanceCheckMs = 0
    o.remoteExamDoctorX = nil
    o.remoteExamDoctorY = nil
    o.remoteExamDoctorZ = nil
    o.remoteExamPatientX = nil
    o.remoteExamPatientY = nil
    o.remoteExamPatientZ = nil
    o.lastRemoteBodyDamageEnsureMs = 0
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    o.anchorLeft = true
    o.anchorTop = true
    o.anchorRight = false
    o.anchorBottom = false

    return o
end

function EHR_HealthPanelUI:initialise()
    ISPanel.initialise(self)
end

function EHR_HealthPanelUI:toString()
    return "EHR_HealthPanelUI"
end

function EHR_HealthBodyPartPanel:toString()
    return "EHR_HealthBodyPartPanel"
end

function EHR_HealthPanelUI:getPatientBodyDamage()
    if not self.player or not self.player.getBodyDamage then return nil end

    if self.isRemoteHealthPanel and isClient and isClient() and self.player.isLocalPlayer and not self.player:isLocalPlayer() and self.player.getBodyDamageRemote then
        -- B42 can initialize the vanilla remote BodyDamage stream as a full-health
        -- snapshot. Passive EHR rendering uses server snapshots instead; only
        -- touch the remote stream briefly while building an actual medical action.
        if (tonumber(self.remoteBodyDamageAccessTicks) or 0) > 0 then
            local ok, remoteBodyDamage = pcall(function()
                return self.player:getBodyDamageRemote()
            end)
            if ok and remoteBodyDamage then
                return remoteBodyDamage
            end
        end
    end

    return self.player:getBodyDamage()
end

function EHR_HealthPanelUI:getRemoteBodyPartSnapshotByType(bodyPartType)
    if not self.isRemoteHealthPanel or type(self.remoteExamData) ~= "table" then return nil end
    local bodyStatus = self.remoteExamData.EHR_BodyStatus
    local parts = bodyStatus and bodyStatus.parts
    if type(parts) ~= "table" then return nil end

    local partKey = getBodyPartTypeCacheKey(bodyPartType)
    if not partKey then return nil end
    return parts[partKey]
end

function EHR_HealthPanelUI:getRemoteBodyPartSnapshot(bodyPart)
    local partType = callBodyPartMethod(bodyPart, "getType", nil)
    return self:getRemoteBodyPartSnapshotByType(partType)
end

function EHR_HealthPanelUI:beginRemoteBodyDamageAccess(ticks)
    if not self.isRemoteHealthPanel or not self.remoteDoctor or not self.remotePatient then return end

    -- EHR remote panels are driven by server snapshots. B42's vanilla remote
    -- BodyDamage stream may initialize as a full-health/full-stats object, and
    -- starting it from EHR medical actions can heal/refill the patient. Vanilla
    -- timed actions can operate on patient:getBodyDamage() directly, so keep
    -- this as a no-op for EHR.
    self.remoteBodyDamageAccessTicks = 0
end

function EHR_HealthPanelUI:ensureRemoteBodyDamageUpdates(ticks)
    self:beginRemoteBodyDamageAccess(ticks)
end

function EHR_HealthPanelUI:markRemoteBodyDamageDirty(ticks)
    if not self.isRemoteHealthPanel then return end

    ticks = tonumber(ticks) or 8
    self.remoteBodyDamageRefreshTicks = math.max(tonumber(self.remoteBodyDamageRefreshTicks) or 0, ticks)
    if (tonumber(self.remoteBodyDamageAccessTicks) or 0) > 0 then
        self:syncBodyPartPanelBodyParts()
    end
end

function EHR_HealthPanelUI:processRemoteBodyDamageRefresh()
    if not self.isRemoteHealthPanel then return end

    local accessTicks = tonumber(self.remoteBodyDamageAccessTicks) or 0
    if accessTicks > 0 then
        self.remoteBodyDamageAccessTicks = accessTicks - 1
        if self.remoteBodyDamageAccessTicks <= 0 and self.remoteDoctor and self.remotePatient and self.remoteDoctor.stopReceivingBodyDamageUpdates then
            pcall(function()
                self.remoteDoctor:stopReceivingBodyDamageUpdates(self.remotePatient)
            end)
        end
    end

    if type(self.remoteExamRefreshBurst) == "table" and #self.remoteExamRefreshBurst > 0 then
        for i = #self.remoteExamRefreshBurst, 1, -1 do
            self.remoteExamRefreshBurst[i] = (tonumber(self.remoteExamRefreshBurst[i]) or 0) - 1
            if self.remoteExamRefreshBurst[i] <= 0 then
                table.remove(self.remoteExamRefreshBurst, i)
                if EHR.MPExamination and EHR.MPExamination.RequestExamData
                        and self.remoteDoctor and self.remotePatient
                        and isClient and isClient() then
                    EHR.MPExamination.RequestExamData(self.remoteDoctor, self.remotePatient, true, true)
                end
            end
        end
    end

    local ticks = tonumber(self.remoteBodyDamageRefreshTicks) or 0
    if ticks <= 0 then return end

    self.remoteBodyDamageRefreshTicks = ticks - 1
    if (tonumber(self.remoteBodyDamageAccessTicks) or 0) > 0 then
        self:syncBodyPartPanelBodyParts()
    end

    if self.remoteBodyDamageRefreshTicks <= 0
            and EHR.MPExamination and EHR.MPExamination.RequestExamData
            and isClient and isClient() then
        EHR.MPExamination.RequestExamData(self.remoteDoctor, self.remotePatient, true)
    end
end

function EHR_HealthPanelUI:queueRemoteExamRefreshBurst()
    if not self.isRemoteHealthPanel then return end

    self.remoteExamRefreshBurst = {
        8,
        24,
        55,
        110,
    }
    self:markRemoteBodyDamageDirty(180)
end

function EHR_HealthPanelUI:syncBodyPartPanelBodyParts()
    if not self.bodyPartPanel or not self.bodyPartPanel.bps then return end

    local bodyDamage = self:getPatientBodyDamage()
    if not bodyDamage or not bodyDamage.getBodyPart then return end

    for _, bp in ipairs(self.bodyPartPanel.bps) do
        if bp and bp.bodyPartType then
            local ok, bodyPart = pcall(function()
                return bodyDamage:getBodyPart(bp.bodyPartType)
            end)
            if ok and bodyPart then
                if self.isRemoteHealthPanel then
                    local partKey = getBodyPartTypeCacheKey(bp.bodyPartType)
                    local snapshot = self:getRemoteBodyPartSnapshotByType(bp.bodyPartType)
                    local snapshotActionable = snapshotHasActionableStatus(snapshot)
                    self.remoteActionBodyPartCache = self.remoteActionBodyPartCache or {}

                    if bodyPartHasActionableStatus(bodyPart) and bodyPartMatchesSnapshot(bodyPart, snapshot) then
                        self.remoteActionBodyPartCache[partKey] = bodyPart
                        bp.bodyPart = bodyPart
                    elseif snapshotActionable
                            and bodyPartHasActionableStatus(self.remoteActionBodyPartCache[partKey])
                            and bodyPartMatchesSnapshot(self.remoteActionBodyPartCache[partKey], snapshot) then
                        bp.bodyPart = self.remoteActionBodyPartCache[partKey]
                    else
                        if not snapshotActionable then
                            self.remoteActionBodyPartCache[partKey] = nil
                        end
                        bp.bodyPart = bodyPart
                    end
                else
                    bp.bodyPart = bodyPart
                end
            end
        end
    end
end

function EHR_HealthPanelUI:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = ISButton:new(self.width - 30, 6, 24, 22, "X", self, EHR_HealthPanelUI.onClose)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton.borderColor = { r = 0.72, g = 0.24, b = 0.20, a = 1 }
    self:addChild(self.closeButton)

    self.expandButton = ISButton:new(self.width - 60, 6, 24, 22, "-", self, EHR_HealthPanelUI.onToggleRight)
    self.expandButton:initialise()
    self.expandButton:instantiate()
    self.expandButton.borderColor = { r = 0.72, g = 0.24, b = 0.20, a = 1 }
    self:addChild(self.expandButton)

    self.antibodiesButton = ISButton:new(self.width - 90, 6, 24, 22, "", self, EHR_HealthPanelUI.onOpenAntibodiesPanel)
    self.antibodiesButton:initialise()
    self.antibodiesButton:instantiate()
    self.antibodiesButton.toString = function()
        return "EHR_AntibodiesButton"
    end
    self.antibodiesButton.borderColor = { r = 0.72, g = 0.24, b = 0.20, a = 1 }
    self.antibodiesButton.backgroundColor = { r = 0.045, g = 0.025, b = 0.025, a = 0.72 }
    self.antibodiesButton.backgroundColorMouseOver = { r = 0.20, g = 0.055, b = 0.045, a = 0.95 }
    self.antibodiesButton:setTooltip(safeText("UI_EHR_AntibodiesPanel", "Antibodies panel"))
    local antibodiesIcon = getTexture and getTexture("media/textures/Item_AntibodyCompTest.png") or nil
    if antibodiesIcon then
        self.antibodiesButton:setImage(antibodiesIcon)
        self.antibodiesButton:forceImageSize(18, 18)
    else
        self.antibodiesButton:setTitle("AB")
    end
    self.antibodiesButton:setVisible(false)
    self:addChild(self.antibodiesButton)

    self:ensureBodyPartPanel()
    self:createEmbeddedVanillaTabs()
    self:syncTabVisibility()
end

function EHR_HealthPanelUI:getAntibodiesPatient()
    local patient = self.remotePatient or self.player
    if patient and self.remotePatientOnlineID and getPlayerByOnlineID then
        local ok, refreshed = pcall(function()
            return getPlayerByOnlineID(self.remotePatientOnlineID)
        end)
        if ok and refreshed then
            patient = refreshed
        end
    end
    return patient
end

function EHR_HealthPanelUI:shouldShowAntibodiesButton()
    local doctor = self.remoteDoctor or self.player
    local patient = self:getAntibodiesPatient()
    if not doctor or not patient then return false end
    return getAntibodiesWindowModule() ~= nil
end

function EHR_HealthPanelUI:onOpenAntibodiesPanel()
    local antibodiesWindow = getAntibodiesWindowModule()
    if not antibodiesWindow or not antibodiesWindow.show then return end

    local doctor = self.remoteDoctor or self.player
    local patient = self:getAntibodiesPatient()
    if not doctor or not patient then return end

    pcall(function()
        antibodiesWindow.show(doctor, patient)
    end)
end

function EHR_HealthPanelUI:ensureBodyPartPanel()
    if self.bodyPartPanel and self.bodyPartPanel.player == self.player then
        return self.bodyPartPanel
    end

    if self.bodyPartPanel then
        self:removeChild(self.bodyPartPanel)
        self.bodyPartPanel = nil
    end

    if not self.player or not EHR_HealthBodyPartPanel then
        return nil
    end

    self.bodyPartPanel = EHR_HealthBodyPartPanel:new(self.player, 0, 0, self, nil)
    self.bodyPartPanel:initialise()
    self.bodyPartPanel:instantiate()
    self.bodyPartPanel:setAlphas(0.62, 1.0, 1.0, 0.38, 0.38)
    self.bodyPartPanel:setColorScheme({
        { val = 0.00, color = Color.new(0.76, 0.86, 0.80, 1) },
        { val = 0.20, color = Color.new(0.22, 0.88, 0.30, 1) },
        { val = 0.40, color = Color.new(0.95, 0.74, 0.18, 1) },
        { val = 0.60, color = Color.new(1.00, 0.36, 0.12, 1) },
        { val = 0.80, color = Color.new(0.58, 0.20, 0.72, 1) },
        { val = 1.00, color = Color.new(0.86, 0.05, 0.045, 1) },
    })
    self.bodyPartPanel:enableNodes("media/ui/BodyParts/bps_node_diamond", "media/ui/BodyParts/bps_node_diamond_outline")
    self:syncBodyPartPanelBodyParts()
    self:addChild(self.bodyPartPanel)

    return self.bodyPartPanel
end

function EHR_HealthPanelUI:destroyPlayerBoundViews()
    self:stopPointerInteraction()
    self:clearRemoteBodyContextRetry()

    if self.bodyPartPanel then
        pcall(function()
            self.bodyPartPanel:setVisible(false)
        end)
        pcall(function()
            self:removeChild(self.bodyPartPanel)
        end)
        self.bodyPartPanel = nil
    end

    if self.embeddedTabs then
        for _, view in pairs(self.embeddedTabs) do
            pcall(function()
                view:setVisible(false)
            end)
            pcall(function()
                self:removeChild(view)
            end)
        end
    end

    self.embeddedTabs = {}
    self.embeddedTabsCreated = false
    self.vanillaHealthAdapter = nil
    self.cachedData = {}
    self.remoteBodyPartStatusCache = {}
    self.remoteActionBodyPartCache = {}
    self.remoteBodyDamageAccessTicks = 0
    self.remoteExamRefreshBurst = nil
    self.markerBounds = {}
    self.contentScrollY = 0
    self.selectedZone = "overview"
end

function EHR_HealthPanelUI:bindPlayer(player, force)
    if not player then return false end

    self.isRemoteHealthPanel = false
    self.remoteDoctor = nil
    self.remotePatient = nil
    self.remotePatientOnlineID = nil
    self.remoteExamData = nil
    self.remoteBodyPartStatusCache = {}
    self.remoteActionBodyPartCache = {}
    self.remoteExamRefreshBurst = nil

    local playerNum = player.getPlayerNum and player:getPlayerNum() or 0
    if not force and self.player == player and self.playerNum == playerNum then
        return false
    end

    self.player = player
    self.playerNum = playerNum
    self:destroyPlayerBoundViews()
    self:ensureBodyPartPanel()
    self:createEmbeddedVanillaTabs()
    self:syncTabVisibility()

    if EHR.DEBUG then
        EHR.Log("HealthPanelUI: rebound to player " .. tostring(playerNum))
    end

    return true
end

function EHR_HealthPanelUI:bindRemotePatient(doctor, patient, force)
    if not doctor or not patient then return false end

    local playerNum = doctor.getPlayerNum and doctor:getPlayerNum() or 0
    if not force and self.isRemoteHealthPanel and self.remoteDoctor == doctor and self.player == patient and self.playerNum == playerNum then
        return false
    end

    self.isRemoteHealthPanel = true
    self.remoteDoctor = doctor
    self.remotePatient = patient
    self.remotePatientOnlineID = nil
    self.remoteBodyPartStatusCache = {}
    self.remoteActionBodyPartCache = {}
    self.remoteExamRefreshBurst = nil
    self.lastRemoteExamDistanceCheckMs = 0
    pcall(function()
        self.remoteExamDoctorX = doctor:getX()
        self.remoteExamDoctorY = doctor:getY()
        self.remoteExamDoctorZ = doctor:getZ()
        self.remoteExamPatientX = patient:getX()
        self.remoteExamPatientY = patient:getY()
        self.remoteExamPatientZ = patient:getZ()
    end)
    pcall(function()
        if patient.getOnlineID then
            self.remotePatientOnlineID = patient:getOnlineID()
        end
    end)
    self.player = patient
    self.playerNum = playerNum
    self:destroyPlayerBoundViews()
    self:ensureBodyPartPanel()
    self:createEmbeddedVanillaTabs()
    self:syncTabVisibility()

    if EHR.DEBUG then
        EHR.Log("HealthPanelUI: rebound to remote patient for doctor " .. tostring(playerNum))
    end

    return true
end

function EHR_HealthPanelUI:remoteExamShouldClose()
    if not self.isRemoteHealthPanel then return false end

    local doctor = self.remoteDoctor
    local patient = self.remotePatient or self.player
    if not doctor or not patient then return true end

    local okDead, isDead = pcall(function()
        return (doctor.isDead and doctor:isDead()) or (patient.isDead and patient:isDead())
    end)
    if okDead and isDead then return true end

    if ISHealthPanel and ISHealthPanel.IsCharactersInSameCar then
        local okSameCar, sameCar = pcall(function()
            return ISHealthPanel.IsCharactersInSameCar(doctor, patient)
        end)
        if okSameCar and sameCar then return false end
    end

    local okPos, doctorX, doctorY, doctorZ, patientX, patientY, patientZ = pcall(function()
        return doctor:getX() or 0,
                doctor:getY() or 0,
                doctor:getZ() or 0,
                patient:getX() or 0,
                patient:getY() or 0,
                patient:getZ() or 0
    end)
    if not okPos then return true end
    local dx = doctorX - patientX
    local dy = doctorY - patientY
    local dz = doctorZ - patientZ
    if math.abs(dz or 0) > 0.1 then return true end

    local moveTolerance = tonumber(EHR_HealthPanelUI.REMOTE_EXAM_MOVE_TOLERANCE) or 0.75
    if self.remoteExamDoctorX and self.remoteExamDoctorY and self.remoteExamDoctorZ
            and (math.abs(doctorX - self.remoteExamDoctorX) > moveTolerance
            or math.abs(doctorY - self.remoteExamDoctorY) > moveTolerance
            or math.abs(doctorZ - self.remoteExamDoctorZ) > 0.1) then
        return true
    end
    if self.remoteExamPatientX and self.remoteExamPatientY and self.remoteExamPatientZ
            and (math.abs(patientX - self.remoteExamPatientX) > moveTolerance
            or math.abs(patientY - self.remoteExamPatientY) > moveTolerance
            or math.abs(patientZ - self.remoteExamPatientZ) > 0.1) then
        return true
    end

    local maxDistance = tonumber(EHR_HealthPanelUI.REMOTE_EXAM_MAX_DISTANCE) or 4.0
    return (dx * dx + dy * dy) > (maxDistance * maxDistance)
end

function EHR_HealthPanelUI:closeRemoteExamIfOutOfRange()
    if not self.isRemoteHealthPanel then return false end

    local now = getTimestampMs and getTimestampMs() or 0
    if now > 0 and (now - (self.lastRemoteExamDistanceCheckMs or 0)) < 300 then
        return false
    end
    self.lastRemoteExamDistanceCheckMs = now

    if not self:remoteExamShouldClose() then return false end

    if EHR.UI and EHR.UI.DestroyRemoteHealthPanel then
        EHR.UI.DestroyRemoteHealthPanel(self.ehrRemoteKey or self.remotePatient or self.player)
    else
        self:setVisible(false)
    end
    return true
end

function EHR_HealthPanelUI:getTabDefinitions()
    local vanillaText = xpSystemText or {}
    if self.isRemoteHealthPanel then
        return {
            { id = "ehr", label = safeText("UI_EHR_Tab_EHR_Compact", "EHR") },
        }
    end
    if self.width < 560 then
        return {
            { id = "ehr", label = safeText("UI_EHR_Tab_EHR_Compact", "EHR") },
        }
    end

    local compact = self.width < 760
    return {
        { id = "ehr", label = compact and safeText("UI_EHR_Tab_EHR_Compact", "EHR") or safeText("UI_EHR_Tab_EHR", "EHR Monitor") },
        { id = "immunity", label = compact and safeText("UI_EHR_Tab_Immunity_Compact", "Immune System") or safeText("UI_EHR_Tab_Immunity", "Immune System") },
        { id = "info", label = vanillaText.info or safeText("UI_EHR_Tab_Info", "Info") },
        { id = "skills", label = vanillaText.skills or safeText("UI_EHR_Tab_Skills", "Skills") },
        { id = "health", label = vanillaText.health or safeText("UI_EHR_Tab_Health", "Health") },
        { id = "protection", label = compact and safeText("UI_EHR_Tab_Protection_Compact", "Protect") or (vanillaText.protection or safeText("UI_EHR_Tab_Protection", "Protection")) },
        { id = "temperature", label = compact and safeText("UI_EHR_Tab_Temperature_Compact", "Temp") or safeText("UI_EHR_Tab_Temperature", "Temperature") },
    }
end

function EHR_HealthPanelUI:getContentTop()
    return self.HEADER_HEIGHT + self.TAB_HEIGHT + 10
end

function EHR_HealthPanelUI:getTabContentBounds()
    local y = self:getContentTop()
    return {
        x = 12,
        y = y,
        w = math.max(120, self.width - 24),
        h = math.max(120, self.height - y - 12),
    }
end

function EHR_HealthPanelUI:getEHRContentTop()
    return self:getContentTop() + self.BLOOD_PANEL_HEIGHT + 10
end

function EHR_HealthPanelUI:getEHRLayout()
    local top = self:getEHRContentTop()
    local h = math.max(160, self.height - top - 12)
    local leftW = self.rightExpanded and math.min(self.LEFT_WIDTH, math.max(320, math.floor(self.width * 0.42))) or math.max(280, self.width - 24)
    local rightX = 12 + leftW + 10
    local rightW = math.max(220, self.width - rightX - 12)

    return {
        top = top,
        h = h,
        leftX = 12,
        leftY = top,
        leftW = leftW,
        leftH = h,
        rightX = rightX,
        rightY = top,
        rightW = rightW,
        rightH = h,
    }
end

function EHR_HealthPanelUI:prepareEmbeddedVanillaView(view)
    if not view then return end
    if view.ehrPrepared then return end
    view.ehrPrepared = true

    view.anchorLeft = true
    view.anchorTop = true
    view.anchorRight = true
    view.anchorBottom = true

    view.setWidthAndParentWidth = function(viewSelf, width)
        local parent = viewSelf.parent
        local bounds = parent and parent.getTabContentBounds and parent:getTabContentBounds() or nil
        local maxWidth = bounds and bounds.w or width
        ISPanel.setWidth(viewSelf, math.max(100, maxWidth or width or viewSelf.width or 100))
    end

    view.setHeightAndParentHeight = function(viewSelf, height)
        local parent = viewSelf.parent
        local bounds = parent and parent.getTabContentBounds and parent:getTabContentBounds() or nil
        local maxHeight = bounds and bounds.h or height
        ISPanel.setHeight(viewSelf, math.max(100, maxHeight or height or viewSelf.height or 100))
    end

    local originalPrerender = view.prerender
    local originalRender = view.render
    view.prerender = function(viewSelf, ...)
        viewSelf:setStencilRect(0, 0, viewSelf.width, viewSelf.height)
        if originalPrerender then
            originalPrerender(viewSelf, ...)
        end
    end
    view.render = function(viewSelf, ...)
        if originalRender then
            originalRender(viewSelf, ...)
        end
        viewSelf:clearStencilRect()
    end
end

function EHR_HealthPanelUI:prepareRemoteHealthView(view)
    if not self.isRemoteHealthPanel or not view or view.ehrRemotePrepared then return end
    if not ISHealthPanel then return end

    view.ehrRemotePrepared = true
    view.ehrOwnerPanel = self

    local originalUpdate = view.update
    view.update = function(viewSelf, ...)
        local owner = viewSelf and viewSelf.ehrOwnerPanel or nil
        if not owner or not owner.isRemoteHealthPanel then
            if originalUpdate then
                return originalUpdate(viewSelf, ...)
            end
            return
        end

        local doctor = owner.remoteDoctor or viewSelf.otherPlayer
        local patient = owner.remotePatient or owner.player or viewSelf.character
        if not doctor or not patient then return end

        if isClient and isClient() and patient.getOnlineID and getPlayerByOnlineID then
            local ok, refreshed = pcall(function()
                return getPlayerByOnlineID(patient:getOnlineID())
            end)
            if ok and refreshed and refreshed ~= patient then
                owner:bindRemotePatient(doctor, refreshed, true)
                return
            end
        end

        viewSelf.character = patient
        viewSelf.otherPlayer = doctor
        viewSelf.doctorLevel = doctor.getPerkLevel and doctor:getPerkLevel(Perks.Doctor) or viewSelf.doctorLevel

        -- The vanilla remote health panel clears BodyDamageRemote to "full health"
        -- when it thinks a patient is too far away. EHR owns distance handling,
        -- so a hidden embedded tab must never reset the body snapshot.
        if owner.activeTab ~= "health" then
            viewSelf.blockingMessage = nil
            viewSelf.blockingAlpha = 0
            return
        end

        local patientX, patientY = 0, 0
        local doctorX, doctorY = 0, 0
        pcall(function()
            patientX, patientY = patient:getX(), patient:getY()
            doctorX, doctorY = doctor:getX(), doctor:getY()
        end)

        viewSelf.characterX = patientX
        viewSelf.characterY = patientY
        viewSelf.otherPlayerX = doctorX
        viewSelf.otherPlayerY = doctorY

        local sameCar = false
        if ISHealthPanel.IsCharactersInSameCar then
            pcall(function()
                sameCar = ISHealthPanel.IsCharactersInSameCar(doctor, patient) == true
            end)
        end

        if not sameCar and not ISHealthPanel.cheat
                and (math.abs(patientX - doctorX) > 2 or math.abs(patientY - doctorY) > 2) then
            viewSelf.blockingMessage = getText("IGUI_TradingUI_TooFarAway", patient.getDisplayName and patient:getDisplayName() or "")
            viewSelf.blockingAlpha = math.min(1.0, (tonumber(viewSelf.blockingAlpha) or 0) + 0.05)
            return
        end

        viewSelf.blockingMessage = nil
        viewSelf.blockingAlpha = math.max(0.0, (tonumber(viewSelf.blockingAlpha) or 0) - 0.05)

        if originalUpdate then
            return originalUpdate(viewSelf, ...)
        end
    end
end

function EHR_HealthPanelUI:prepareInfoLiteratureButton(view)
    if not view or not view.literatureButton or view.ehrLiteratureButtonPrepared then return end
    view.ehrLiteratureButtonPrepared = true

    view.literatureButton.onclick = function(target, button, ...)
        ISCharacterScreen.onShowLiterature(target, button, ...)
        local ui = target and target.literatureUI or nil
        if not ui then return end

        if not ui.ehrOwnerCheckPatched then
            ui.ehrOwnerCheckPatched = true
            local originalPrerender = ui.prerender
            ui.prerender = function(uiSelf, ...)
                if ISCollapsableWindowJoypad and ISCollapsableWindowJoypad.prerender then
                    ISCollapsableWindowJoypad.prerender(uiSelf, ...)
                elseif originalPrerender then
                    local oldOwner = uiSelf.owner
                    local infoPanel = getPlayerInfoPanel and getPlayerInfoPanel(uiSelf.playerNum) or nil
                    if infoPanel and infoPanel.charScreen then
                        uiSelf.owner = infoPanel.charScreen
                    end
                    originalPrerender(uiSelf, ...)
                    uiSelf.owner = oldOwner
                end
            end
        end

        ui:setVisible(true)
        ui:addToUIManager()
        if ui.bringToTop then
            ui:bringToTop()
        end

        if Events and Events.OnTick then
            local reopened = false
            local function reopenLiterature()
                if reopened then
                    Events.OnTick.Remove(reopenLiterature)
                    return
                end
                reopened = true
                if target and target.literatureUI then
                    target.literatureUI:setVisible(true)
                    target.literatureUI:addToUIManager()
                    if target.literatureUI.bringToTop then
                        target.literatureUI:bringToTop()
                    end
                end
                Events.OnTick.Remove(reopenLiterature)
            end
            Events.OnTick.Add(reopenLiterature)
        end
    end
end

function EHR_HealthPanelUI:prepareInfoAvatarRefresh(view)
    if not view or view.ehrInfoAvatarRefreshPrepared then return end
    view.ehrInfoAvatarRefreshPrepared = true

    local originalPrerender = view.prerender
    view.prerender = function(viewSelf, ...)
        viewSelf.ehrAvatarRefreshTick = (tonumber(viewSelf.ehrAvatarRefreshTick) or 0) + 1
        if viewSelf.ehrVisible and (viewSelf.ehrAvatarRefreshTick == 1 or viewSelf.ehrAvatarRefreshTick % 15 == 0) then
            viewSelf.refreshNeeded = true
        end
        if originalPrerender then
            originalPrerender(viewSelf, ...)
        end
    end
end

function EHR_HealthPanelUI:prepareTemperatureView(view)
    if not view or view.ehrTemperaturePrepared then return end
    view.ehrTemperaturePrepared = true
    view.ehrOwnerPanel = self

    local function isLocalButtonRowHit(viewSelf, button, x, y)
        if not viewSelf or not button then return false end
        if button.getIsVisible and not button:getIsVisible() then return false end
        if button.isVisible and not button:isVisible() then return false end

        local bx = button.getX and button:getX() or button.x or 0
        local by = button.getY and button:getY() or button.y or 0
        local bw = button.getWidth and button:getWidth() or button.width or 0
        local bh = button.getHeight and button:getHeight() or button.height or 0
        local rowLeft = math.max(0, math.min(bx, tonumber(viewSelf.coreRectangleX) or bx) - 10)
        local rowRight = math.min(viewSelf.width or (bx + bw), math.max(bx + bw, (viewSelf.width or bx + bw) - 10))

        return x >= rowLeft and x <= rowRight and y >= by and y <= by + bh
    end

    local function normalizeButton(button)
        if not button then return end
        if button.setBackgroundColorMouseOverRGBA then
            button:setBackgroundColorMouseOverRGBA(0, 0, 0, 1)
        else
            button.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 1 }
        end
        button.pressed = false
        button.mouseOver = false
    end

    if view.viewButtons then
        for _, group in pairs(view.viewButtons) do
            for _, button in ipairs(group) do
                normalizeButton(button)
                button.onclick = function(target, btn)
                    if target and btn and btn.customData and btn.customData.index and target.setViewIndex then
                        target:setViewIndex(btn.customData.index)
                    end
                    if target and target.ehrOwnerPanel then
                        target.ehrOwnerPanel:resetTemperatureButtonState(target)
                    end
                end
            end
        end
    end
    normalizeButton(view.toggleAdvBtn)

    local function localizedText(key, fallback)
        if getText then
            local ok, value = pcall(getText, key)
            if ok and value and value ~= "" and value ~= key then
                return value
            end
        end
        return fallback
    end

    local originalPrerender = view.prerender
    view.prerender = function(viewSelf, ...)
        if originalPrerender then
            originalPrerender(viewSelf, ...)
        end

        local function clearIndoorClimateLabel()
            local debugEnabled = isDebugEnabled and isDebugEnabled() or false
            if viewSelf.ehrIndoorClimateLabelVisible and viewSelf.labelCoreTemp then
                if not debugEnabled then
                    viewSelf.labelCoreTemp:setName(
                        viewSelf.labelCoreTemp.prefixName or "Core temperature"
                    )
                end
            end
            if viewSelf.ehrMetabolicLabelVisible and viewSelf.labelCoreHeat and not debugEnabled then
                viewSelf.labelCoreHeat:setName(
                    viewSelf.labelCoreHeat.prefixName or "Body heat generation"
                )
            end
            viewSelf.ehrIndoorClimateLabelVisible = false
            viewSelf.ehrMetabolicLabelVisible = false
        end

        local icl = _G and _G.IndoorClimateLite or nil
        if not icl or type(icl.getTemperatureSample) ~= "function" then
            clearIndoorClimateLabel()
            return
        end

        viewSelf.ehrIndoorClimateUiTick = (tonumber(viewSelf.ehrIndoorClimateUiTick) or 0) + 1
        if not viewSelf.ehrIndoorClimateSample or viewSelf.ehrIndoorClimateUiTick % 15 == 0 then
            local okSample, freshSample = pcall(icl.getTemperatureSample, viewSelf.player)
            if okSample and type(freshSample) == "table" and freshSample.active ~= false then
                viewSelf.ehrIndoorClimateSample = freshSample
            else
                viewSelf.ehrIndoorClimateSample = nil
            end
        end

        local sample = viewSelf.ehrIndoorClimateSample
        local airTemp = sample and tonumber(sample.airC) or nil
        if not airTemp or not viewSelf.labelCoreTemp then
            clearIndoorClimateLabel()
            return
        end

        local coreTemp = nil
        local metabolicRate = nil
        pcall(function()
            local bodyDamage = viewSelf.player and viewSelf.player:getBodyDamage() or nil
            local thermoregulator = bodyDamage and bodyDamage:getThermoregulator() or nil
            coreTemp = thermoregulator and tonumber(thermoregulator:getCoreTemperature()) or nil
            metabolicRate = thermoregulator and tonumber(thermoregulator:getMetabolicRateReal()) or nil
        end)

        -- While ICL supplies ambient air, EHR's vanilla heat adapter owns the
        -- corrected core value. Use it for both the label and temperature bar.
        pcall(function()
            local ehr = _G and _G.EHR or nil
            local bodyTemp = ehr and ehr.BodyTemp or nil
            local tempData = bodyTemp
                and bodyTemp.GetTemperatureData
                and bodyTemp.GetTemperatureData(viewSelf.player)
                or nil
            local owner = tempData and tempData.environmentManagedBy or nil
            if owner == "IndoorClimateLite"
                    or owner == "VanillaHeatAdapter"
                    or owner == "ClientThermoregulator" then
                coreTemp = tonumber(tempData.bodyTemp) or coreTemp
                metabolicRate = tonumber(tempData.lastMetabolicRate) or metabolicRate
            end
        end)

        if coreTemp and viewSelf.coreTemperatureBar and viewSelf.coreTemperatureBar.setValue then
            local clampedCore = math.max(20, math.min(42, coreTemp))
            local coreUi = clampedCore < 37
                and (((clampedCore - 20) / 17) * 0.5)
                or (0.5 + (((clampedCore - 37) / 5) * 0.5))
            viewSelf.coreTemperatureBar:setValue(math.max(0, math.min(1, coreUi)))
        end

        local prefix = viewSelf.labelCoreTemp.prefixName or "Core temperature"
        local locationLabel = sample.indoors == true
            and localizedText("UI_ICL_IndoorAir", "Indoor air")
            or localizedText("UI_ICL_OutdoorAir", "Outdoor air")
        local label = coreTemp
            and string.format("%s (%.1f C) | %s: %.1f C", prefix, coreTemp, locationLabel, airTemp)
            or string.format("%s | %s: %.1f C", prefix, locationLabel, airTemp)

        local outdoorTemp = tonumber(sample.outdoorC)
        if sample.indoors == true and outdoorTemp then
            label = label .. string.format(
                " | %s: %.1f C",
                localizedText("UI_ICL_OutdoorAir", "Outdoor air"),
                outdoorTemp
            )
        end
        viewSelf.labelCoreTemp:setName(label)
        viewSelf.ehrIndoorClimateLabelVisible = true

        if metabolicRate and viewSelf.labelCoreHeat then
            local heatPrefix = viewSelf.labelCoreHeat.prefixName or "Body heat generation"
            viewSelf.labelCoreHeat:setName(string.format("%s (%.2f MET)", heatPrefix, metabolicRate))
            viewSelf.ehrMetabolicLabelVisible = true
        end
    end

    local originalOnMouseUp = view.onMouseUp
    view.onMouseUp = function(viewSelf, x, y)
        local buttons = viewSelf.viewButtons and viewSelf.currentViewID and viewSelf.viewButtons[viewSelf.currentViewID] or nil
        if buttons then
            for _, button in ipairs(buttons) do
                if isLocalButtonRowHit(viewSelf, button, x, y) then
                    if button.customData and button.customData.index and viewSelf.setViewIndex then
                        viewSelf:setViewIndex(button.customData.index)
                    end
                    if viewSelf.ehrOwnerPanel then
                        viewSelf.ehrOwnerPanel:resetTemperatureButtonState(viewSelf)
                    end
                    return true
                end
            end
        end

        if isLocalButtonRowHit(viewSelf, viewSelf.toggleAdvBtn, x, y) then
            if ISClothingInsPanel and ISClothingInsPanel.onToggleViewStyle then
                ISClothingInsPanel.onToggleViewStyle(viewSelf, viewSelf.toggleAdvBtn)
            elseif viewSelf.onToggleViewStyle then
                viewSelf:onToggleViewStyle(viewSelf.toggleAdvBtn)
            end
            if viewSelf.ehrOwnerPanel then
                viewSelf.ehrOwnerPanel:resetTemperatureButtonState(viewSelf)
            end
            return true
        end

        if originalOnMouseUp then
            return originalOnMouseUp(viewSelf, x, y)
        end
        return false
    end
end

function EHR_HealthPanelUI:createEmbeddedVanillaTabs()
    if self.embeddedTabsCreated then return end
    self.embeddedTabsCreated = true
    self.embeddedTabs = self.embeddedTabs or {}

    if not self.player then return end
    if self.isRemoteHealthPanel then return end

    local bounds = self:getTabContentBounds()
    local specs = {
        {
            id = "info",
            factory = function()
                return ISCharacterScreen:new(0, 0, bounds.w, bounds.h, self.playerNum)
            end,
        },
        {
            id = "skills",
            factory = function()
                return ISCharacterInfo:new(0, 0, bounds.w, bounds.h, self.playerNum)
            end,
        },
        {
            id = "health",
            factory = function()
                return ISHealthPanel:new(self.player, 0, 0, bounds.w, bounds.h)
            end,
        },
        {
            id = "protection",
            factory = function()
                return ISCharacterProtection:new(0, 0, bounds.w, bounds.h, self.playerNum)
            end,
        },
        {
            id = "temperature",
            factory = function()
                return ISClothingInsPanel:new(self.player, 0, 0, bounds.w, bounds.h)
            end,
        },
    }

    for _, spec in ipairs(specs) do
        local oldHealthInstance = ISHealthPanel and ISHealthPanel.instance or nil
        local oldCharacterInfoInstance = ISCharacterInfo and ISCharacterInfo.instance or nil
        local ok, view = pcall(spec.factory)
        if ISHealthPanel then
            ISHealthPanel.instance = oldHealthInstance
        end
        if ISCharacterInfo then
            ISCharacterInfo.instance = oldCharacterInfoInstance
        end
        if ok and view then
            view.ehrTabId = spec.id
            self:prepareEmbeddedVanillaView(view)
            view:initialise()
            if not view.javaObject and view.instantiate then
                view:instantiate()
            end
            if spec.id == "info" then
                self:prepareInfoAvatarRefresh(view)
                self:prepareInfoLiteratureButton(view)
            elseif spec.id == "temperature" then
                self:prepareTemperatureView(view)
            elseif spec.id == "health" and self.isRemoteHealthPanel and self.remoteDoctor then
                view.doctorLevel = self.remoteDoctor:getPerkLevel(Perks.Doctor)
                if view.setOtherPlayer then
                    pcall(function() view:setOtherPlayer(self.remoteDoctor) end)
                end
                self:prepareRemoteHealthView(view)
            end
            view:setVisible(false)
            view.ehrVisible = false
            self:addChild(view)
            self.embeddedTabs[spec.id] = view
        end
    end
end

function EHR_HealthPanelUI:layoutEmbeddedVanillaTabs()
    if not self.embeddedTabs then return end

    local bounds = self:getTabContentBounds()
    for _, view in pairs(self.embeddedTabs) do
        view:setX(bounds.x)
        view:setY(bounds.y)
        view:setWidth(bounds.w)
        view:setHeight(bounds.h)
    end
end

function EHR_HealthPanelUI:syncTabVisibility()
    local isEHR = self.activeTab == "ehr"

    if self.bodyPartPanel then
        self.bodyPartPanel:setVisible(isEHR)
    end
    if self.expandButton then
        self.expandButton:setVisible(isEHR)
    end
    if self.antibodiesButton then
        self.antibodiesButton:setVisible(self:shouldShowAntibodiesButton())
    end
    if self.embeddedTabs then
        for id, view in pairs(self.embeddedTabs) do
            local shouldShow = self.activeTab == id
            if view.ehrVisible ~= shouldShow then
                view.ehrVisible = shouldShow
                view:setVisible(shouldShow)
                if shouldShow and id == "info" then
                    view.refreshNeeded = true
                    view.ehrAvatarRefreshTick = 0
                end
            end
        end
    end
end

function EHR_HealthPanelUI:setActiveTab(tabId)
    if not tabId or self.activeTab == tabId then return end

    self.activeTab = tabId
    self.contentScrollY = 0

    if tabId ~= "ehr" and not self.rightExpanded then
        self.rightExpanded = true
        self:setWidth(EHR_HealthPanelUI.EXPANDED_WIDTH)
    end

    self:repositionControls()
    self:syncTabVisibility()
    self:keepOnScreen()
end

function EHR_HealthPanelUI:repositionControls()
    if self.closeButton then
        self.closeButton:setX(self.width - 30)
        self.closeButton:setY(math.floor((self.HEADER_HEIGHT - self.closeButton.height) / 2))
    end
    if self.expandButton then
        self.expandButton:setX(self.width - 60)
        self.expandButton:setY(math.floor((self.HEADER_HEIGHT - self.expandButton.height) / 2))
        self.expandButton:setTitle(self.rightExpanded and "-" or "+")
    end
    if self.antibodiesButton then
        self.antibodiesButton:setX(self.width - 90)
        self.antibodiesButton:setY(math.floor((self.HEADER_HEIGHT - self.antibodiesButton.height) / 2))
    end
end

function EHR_HealthPanelUI:isInResizeHandle(x, y)
    local size = self.RESIZE_SIZE or 18
    return x >= self.width - size and y >= self.height - size
end

function EHR_HealthPanelUI:clampWindowSize(width, height)
    local core = getCore and getCore()
    local maxW = core and (core:getScreenWidth() - math.max(0, self.x) - 8) or width
    local maxH = core and (core:getScreenHeight() - math.max(0, self.y) - 8) or height
    local minW = self.rightExpanded and 700 or (self.MIN_WIDTH or 420)
    local minH = self.MIN_HEIGHT or 420

    return clamp(width, minW, math.max(minW, maxW)), clamp(height, minH, math.max(minH, maxH))
end

function EHR_HealthPanelUI:keepOnScreen()
    local core = getCore and getCore()
    if not core then return end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local x = self.x
    local y = self.y

    if x + self.width > screenW then x = screenW - self.width - 10 end
    if y + self.height > screenH then y = screenH - self.height - 10 end
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end

    self:setX(x)
    self:setY(y)
end

function EHR_HealthPanelUI:ensureUsableSize()
    local minW = self.rightExpanded and 700 or (self.MIN_WIDTH or 420)
    local minH = self.MIN_HEIGHT or 420
    if self.width >= minW and self.height >= minH then return end

    local newW, newH = self:clampWindowSize(self.width, self.height)
    if newW ~= self.width then self:setWidth(newW) end
    if newH ~= self.height then self:setHeight(newH) end
    self:repositionControls()
    self:keepOnScreen()
end

function EHR_HealthPanelUI:stopPointerInteraction()
    local wasMoving = self.dragging or self.resizing
    self.dragging = false
    self.resizing = false
    if wasMoving then
        self:keepOnScreen()
    end
    return wasMoving
end

function EHR_HealthPanelUI:getTextWidth(text, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if getTextManager then
        local ok, width = pcall(function()
            return getTextManager():MeasureStringX(font, text)
        end)
        if ok and width then return width end
    end
    return string.len(text) * 8
end

function EHR_HealthPanelUI:getFontHeight(font)
    font = font or UIFont.Small
    if getTextManager then
        local ok, height = pcall(function()
            return getTextManager():getFontHeight(font)
        end)
        if ok and height then return height end
    end
    if font == UIFont.Medium then return 20 end
    return 16
end

function EHR_HealthPanelUI:getCompactFont()
    if UIFont then
        local ok, font = pcall(function()
            return UIFont.NewSmall
        end)
        if ok and font then return font end
    end
    return UIFont.Small
end

function EHR_HealthPanelUI:getDockedTextY(y, h, font, bias)
    local fontH = self:getFontHeight(font)
    return y + math.floor((h - fontH) / 2) + (bias or self.TEXT_DOCK_Y_BIAS or 0)
end

function EHR_HealthPanelUI:drawTextRight(text, rightX, y, r, g, b, a, font)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), rightX - width, y, r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawTextCenter(text, x, w, y, r, g, b, a, font)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), x + math.floor((w - width) / 2), y, r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawDockedText(text, x, y, w, h, r, g, b, a, font, bias)
    self:drawText(tostring(text or ""), x, self:getDockedTextY(y, h, font, bias), r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawDockedTextRight(text, rightX, y, h, r, g, b, a, font, bias)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), rightX - width, self:getDockedTextY(y, h, font, bias), r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawDockedTextCenter(text, x, y, w, h, r, g, b, a, font, bias)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), x + math.floor((w - width) / 2), self:getDockedTextY(y, h, font, bias), r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:truncateText(text, maxWidth, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if self:getTextWidth(text, font) <= maxWidth then return text end

    local ellipsis = "..."
    local result = text
    while string.len(result) > 1 and self:getTextWidth(result .. ellipsis, font) > maxWidth do
        result = string.sub(result, 1, string.len(result) - 1)
    end
    return result .. ellipsis
end

function EHR_HealthPanelUI:drawRoundIcon(x, y, size, fill, border, label, labelColor)
    fill = fill or EHR_HealthPanelUI.Colors.panelSoft
    border = border or EHR_HealthPanelUI.Colors.border
    labelColor = labelColor or EHR_HealthPanelUI.Colors.text

    local cut = math.floor(size * 0.22)
    self:drawRect(x + cut, y, size - cut * 2, size, fill.a, fill.r, fill.g, fill.b)
    self:drawRect(x, y + cut, size, size - cut * 2, fill.a, fill.r, fill.g, fill.b)
    self:drawRectBorder(x + cut, y, size - cut * 2, size, border.a, border.r, border.g, border.b)
    self:drawRectBorder(x, y + cut, size, size - cut * 2, border.a, border.r, border.g, border.b)

    if label then
        self:drawDockedTextCenter(label, x, y, size, size, labelColor.r, labelColor.g, labelColor.b, labelColor.a, UIFont.Small)
    end
end

function EHR_HealthPanelUI:drawPanelFrame(x, y, w, h, title, iconLabel)
    local c = EHR_HealthPanelUI.Colors
    self:drawRect(x, y, w, h, c.panel.a, c.panel.r, c.panel.g, c.panel.b)
    self:drawWornFrame(x, y, w, h, c.border, math.max(4, math.floor(w / 80)))
    self:drawCornerBolts(x, y, w, h, c.border)
    self:drawRect(x, y, w, 1, 0.85, c.border.r, c.border.g, c.border.b)

    if title then
        local titleX = x + 12
        if iconLabel then
            local iconTexture = self:getPanelIconTexture(iconLabel)
            if iconTexture and self.drawTextureScaled then
                self:drawTextureScaled(iconTexture, x + 8, y + 9, 24, 24, 1.0, 1.0, 1.0, 1.0)
                titleX = x + 38
            else
                self:drawRect(x + 10, y + 13, 16, 16, 0.18, c.red.r, c.red.g, c.red.b)
                self:drawRectBorder(x + 10, y + 13, 16, 16, 0.85, c.border.r, c.border.g, c.border.b)
                self:drawDockedTextCenter(iconLabel, x + 10, y + 13, 16, 16, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Small)
                titleX = x + 34
            end
        end
        self:drawDockedText(title, titleX, y + 8, w - 24, 28, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
        self:drawRect(x + 12, y + 40, w - 24, 1, 0.70, c.border.r, c.border.g, c.border.b)
    end
end

function EHR_HealthPanelUI:getPanelIconTexture(iconKey)
    if not getTexture or not iconKey then return nil end
    local path = EHR_HealthPanelUI.PanelIconPaths[tostring(iconKey)]
    if not path then return nil end

    self.panelIconTextures = self.panelIconTextures or {}
    if self.panelIconTextures[iconKey] ~= nil then
        return self.panelIconTextures[iconKey] or nil
    end

    self.panelIconTextures[iconKey] = getTexture(path) or false
    return self.panelIconTextures[iconKey] or nil
end

function EHR_HealthPanelUI:getTabIconTexture(tabId)
    if not getTexture then return nil end
    self.tabIconTextures = self.tabIconTextures or {}
    if self.tabIconTextures[tabId] ~= nil then
        return self.tabIconTextures[tabId] or nil
    end

    local paths = {
        ehr = "media/textures/EHR_Tab_EHR.png",
        immunity = "media/textures/EHR_Tab_Immune.png",
        info = "media/textures/EHR_Tab_Info.png",
        skills = "media/textures/EHR_Tab_Skills.png",
        health = "media/textures/EHR_Tab_Health.png",
        protection = "media/textures/EHR_Tab_Protection.png",
        temperature = "media/textures/EHR_Tab_Temperature.png",
    }

    local path = paths[tabId]
    self.tabIconTextures[tabId] = path and (getTexture(path) or false) or false
    return self.tabIconTextures[tabId] or nil
end

function EHR_HealthPanelUI:drawSubtleGrid(x, y, w, h, step)
    local c = EHR_HealthPanelUI.Colors
    step = step or 24
    for gx = x, x + w, step do
        self:drawRect(gx, y, 1, h, 0.08, c.border.r, c.border.g, c.border.b)
    end
    for gy = y, y + h, step do
        self:drawRect(x, gy, w, 1, 0.08, c.border.r, c.border.g, c.border.b)
    end
end

function EHR_HealthPanelUI:drawWornFrame(x, y, w, h, accent, density)
    local c = EHR_HealthPanelUI.Colors
    accent = accent or c.border

    self:drawRectBorder(x, y, w, h, 0.58, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    self:drawRect(x, y, w, 1, 0.36, accent.r, accent.g, accent.b)
    self:drawRect(x, y + h - 1, w, 1, 0.18, accent.r, accent.g, accent.b)
    self:drawRect(x, y, 1, h, 0.20, accent.r, accent.g, accent.b)
    self:drawRect(x + w - 1, y, 1, h, 0.16, accent.r, accent.g, accent.b)

    if w > 110 then
        self:drawRect(x + 14, y, math.min(46, w - 28), 1, 0.24, c.textDim.r, c.textDim.g, c.textDim.b)
        self:drawRect(x + w - math.min(62, w - 20), y + h - 1, math.min(38, w - 24), 1, 0.16, c.textDim.r, c.textDim.g, c.textDim.b)
    end
end

function EHR_HealthPanelUI:drawCornerBolts(x, y, w, h, color)
    color = color or EHR_HealthPanelUI.Colors.border
    local a = 0.30
    self:drawRect(x + 5, y + 5, 5, 1, a, color.r, color.g, color.b)
    self:drawRect(x + 5, y + 5, 1, 5, a, color.r, color.g, color.b)
    self:drawRect(x + w - 10, y + 5, 5, 1, a, color.r, color.g, color.b)
    self:drawRect(x + w - 6, y + 5, 1, 5, a, color.r, color.g, color.b)
    self:drawRect(x + 5, y + h - 6, 5, 1, a, color.r, color.g, color.b)
    self:drawRect(x + 5, y + h - 10, 1, 5, a, color.r, color.g, color.b)
    self:drawRect(x + w - 10, y + h - 6, 5, 1, a, color.r, color.g, color.b)
    self:drawRect(x + w - 6, y + h - 10, 1, 5, a, color.r, color.g, color.b)
end

function EHR_HealthPanelUI:drawHazardStripes(x, y, count, color)
    color = color or EHR_HealthPanelUI.Colors.red
    for i = 0, count - 1 do
        local sx = x + i * 13
        self:drawRect(sx, y, 8, 3, 0.55, color.r, color.g, color.b)
        self:drawRect(sx + 3, y + 3, 8, 3, 0.45, color.r, color.g, color.b)
    end
end

function EHR_HealthPanelUI:drawBadgeIcon(x, y, size, accent, label)
    local c = EHR_HealthPanelUI.Colors
    accent = accent or c.red
    self:drawRoundIcon(x, y, size, { r = 0.045, g = 0.035, b = 0.035, a = 0.94 }, accent, nil)
    self:drawRoundIcon(x + 5, y + 5, size - 10, { r = 0.08, g = 0.025, b = 0.025, a = 0.84 }, c.borderDim, nil)
    self:drawDockedTextCenter(label or "?", x, y, size, size, accent.r, accent.g, accent.b, accent.a, UIFont.Medium)
end

function EHR_HealthPanelUI:getDiseaseIconTexture(diseaseId, displayInfo)
    if not getTexture then return nil end

    local iconKey = nil
    if displayInfo and displayInfo.canIdentify == false then
        iconKey = "unknown"
    else
        iconKey = tostring(displayInfo and displayInfo.iconKey or displayInfo and displayInfo.normalizedId or self:getNormalizedDiseaseId(diseaseId) or ""):lower()
    end

    local path = EHR_HealthPanelUI.DiseaseIconPaths[iconKey]
    if not path then return nil end

    self.diseaseIconTextures = self.diseaseIconTextures or {}
    if self.diseaseIconTextures[iconKey] ~= nil then
        return self.diseaseIconTextures[iconKey] or nil
    end

    self.diseaseIconTextures[iconKey] = getTexture(path) or false
    return self.diseaseIconTextures[iconKey] or nil
end

function EHR_HealthPanelUI:drawDiseaseIcon(x, y, size, accent, label, texture)
    if texture and self.drawTextureScaled then
        self:drawTextureScaled(texture, x, y, size, size, 1.0, 1.0, 1.0, 1.0)
        return
    end

    self:drawBadgeIcon(x, y, size, accent, label)
end

function EHR_HealthPanelUI:drawTabGlyph(tabId, x, y, size, active)
    local c = EHR_HealthPanelUI.Colors
    local color = active and c.text or c.textDim
    local a = active and 1.0 or 0.72
    local cx = x + math.floor(size / 2)
    local cy = y + math.floor(size / 2)
    local texture = self:getTabIconTexture(tabId)

    if texture and self.drawTextureScaled then
        self:drawTextureScaled(texture, x, y, size, size, active and 1.0 or 0.62, 1.0, 1.0, 1.0)
        return
    end

    self:drawRect(x + 3, y + 3, size - 6, size - 6, active and 0.16 or 0.07, c.red.r, c.red.g, c.red.b)

    if tabId == "ehr" then
        self:drawRect(x + 2, cy, 8, 2, a, color.r, color.g, color.b)
        self:drawRect(x + 10, cy - 8, 2, 10, a, color.r, color.g, color.b)
        self:drawRect(x + 12, cy + 1, 6, 2, a, color.r, color.g, color.b)
        self:drawRect(x + 18, cy - 5, 2, 9, a, color.r, color.g, color.b)
        self:drawRect(x + 20, cy, 10, 2, a, color.r, color.g, color.b)
        self:drawRect(x + 5, cy - 1, 22, 1, 0.22, c.red.r, c.red.g, c.red.b)
    elseif tabId == "health" then
        self:drawRect(cx - 9, cy - 7, 18, 13, a, color.r, color.g, color.b)
        self:drawRect(cx - 6, cy - 11, 5, 5, a, color.r, color.g, color.b)
        self:drawRect(cx + 1, cy - 11, 5, 5, a, color.r, color.g, color.b)
        self:drawRect(cx - 2, cy - 1, 4, 12, a, color.r, color.g, color.b)
    elseif tabId == "temperature" then
        self:drawRect(cx - 2, y + 5, 4, size - 11, a, color.r, color.g, color.b)
        self:drawRect(cx - 6, y + size - 10, 12, 8, a, color.r, color.g, color.b)
        self:drawRectBorder(cx - 5, y + 4, 10, size - 5, a, color.r, color.g, color.b)
    elseif tabId == "protection" then
        self:drawRect(cx - 10, y + 7, 20, 6, a, color.r, color.g, color.b)
        self:drawRect(cx - 8, y + 13, 16, 10, a, color.r, color.g, color.b)
        self:drawRect(cx - 4, y + 23, 8, 5, a, color.r, color.g, color.b)
        self:drawRect(cx - 1, y + 11, 2, 14, 0.28, c.background.r, c.background.g, c.background.b)
    elseif tabId == "info" then
        self:drawRect(cx - 5, y + 7, 10, 10, a, color.r, color.g, color.b)
        self:drawRect(cx - 9, y + 19, 18, 9, a, color.r, color.g, color.b)
        self:drawRect(cx - 2, y + 20, 4, 7, 0.24, c.background.r, c.background.g, c.background.b)
    elseif tabId == "skills" then
        self:drawRect(cx - 2, y + 5, 4, 22, a, color.r, color.g, color.b)
        self:drawRect(cx - 10, cy - 2, 20, 4, a, color.r, color.g, color.b)
        self:drawRect(cx - 7, cy - 8, 14, 4, a, color.r, color.g, color.b)
        self:drawRect(cx - 7, cy + 6, 14, 4, a, color.r, color.g, color.b)
    elseif tabId == "immunity" then
        self:drawRect(cx - 10, y + 7, 20, 5, a, color.r, color.g, color.b)
        self:drawRect(cx - 8, y + 12, 16, 11, a, color.r, color.g, color.b)
        self:drawRect(cx - 4, y + 23, 8, 5, a, color.r, color.g, color.b)
        self:drawRect(cx - 1, y + 11, 2, 13, 0.88, c.background.r, c.background.g, c.background.b)
        self:drawRect(cx - 5, cy - 1, 10, 2, 0.88, c.background.r, c.background.g, c.background.b)
    else
        self:drawDockedTextCenter("+", x, y, size, size, color.r, color.g, color.b, a, UIFont.Medium)
    end
end

function EHR_HealthPanelUI:drawSectionTitle(text, x, y, w)
    local c = EHR_HealthPanelUI.Colors
    self:drawRect(x, y, w, 28, 0.46, c.redDark.r, c.redDark.g, c.redDark.b)
    self:drawDockedText(text, x + 8, y + 3, w - 16, 28, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Medium)
    self:drawRect(x + 8, y + 27, w - 16, 1, 0.72, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:getKnowledgePlayer()
    if self.isRemoteHealthPanel and self.remoteDoctor then
        return self.remoteDoctor
    end
    return self.player
end

function EHR_HealthPanelUI:getMedicalSkillTier(ignoreDebugBypass)
    if not ignoreDebugBypass and EHR.IsDebugMode and EHR.IsDebugMode() then
        return 4, 10
    end

    local knowledgePlayer = self:getKnowledgePlayer()
    local skillLevel = 0
    if knowledgePlayer and Perks and Perks.Doctor then
        skillLevel = knowledgePlayer:getPerkLevel(Perks.Doctor) or 0
    end

    local tier = 0
    if skillLevel >= 8 then
        tier = 4
    elseif skillLevel >= 6 then
        tier = 3
    elseif skillLevel >= 4 then
        tier = 2
    elseif skillLevel >= 2 then
        tier = 1
    end

    return tier, skillLevel
end

function EHR_HealthPanelUI:getNormalizedDiseaseId(diseaseId)
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.NormalizeDiseaseId then
        return EHR.DiseaseFlyers.NormalizeDiseaseId(diseaseId)
    end
    return diseaseId
end

function EHR_HealthPanelUI:getDiseaseDefinition(diseaseId, disease)
    if type(disease) == "table" then
        if disease.isCorpseExposure then
            return {
                name = disease.displayName or safeText("UI_EHR_CorpseExposure", "Corpse Exposure"),
                symptoms = { safeText("UI_EHR_Symptom_Nausea", "Nausea"), safeText("UI_EHR_Symptom_Dizziness", "Dizziness"), safeText("UI_EHR_Symptom_EyeIrritation", "Eye irritation") },
            }
        end
        if disease.isWoundInfection then
            local partCount = tonumber(disease.infectedCount) or 1
            local partText = partCount > 1 and (" (" .. partCount .. " wounds)") or ""
            return {
                name = safeText("UI_EHR_WoundInfection", "Wound Infection") .. partText,
                symptoms = { safeText("UI_EHR_Symptom_Pain", "Pain"), safeText("UI_EHR_Symptom_Swelling", "Swelling"), safeText("UI_EHR_Symptom_Redness", "Redness"), safeText("UI_EHR_Symptom_Fever", "Fever") },
            }
        end
        if disease.isSepsis then
            return {
                name = safeText("UI_EHR_Sepsis", "Sepsis"),
                symptoms = { safeText("UI_EHR_Symptom_Fever", "Fever"), safeText("UI_EHR_Symptom_RapidHeartbeat", "Rapid heartbeat"), safeText("UI_EHR_Symptom_Confusion", "Confusion"), safeText("UI_EHR_Symptom_ExtremePain", "Extreme pain") },
            }
        end
        if disease.isKnox then
            return {
                name = safeText("UI_EHR_KnoxInfection", "Knox Virus Infection"),
                symptoms = { safeText("UI_EHR_Symptom_Fever", "Fever"), safeText("UI_EHR_Symptom_Nausea", "Nausea"), safeText("UI_EHR_Symptom_Weakness", "Weakness"), safeText("UI_EHR_Symptom_PaleSkin", "Pale skin") },
            }
        end
    end

    local definitions = EHR.Disease and EHR.Disease.Diseases or nil
    local normalized = self:getNormalizedDiseaseId(diseaseId)
    local definition = definitions and (definitions[diseaseId] or definitions[normalized]) or nil
    if definition then
        return definition
    end

    if type(disease) == "table" and disease.displayName then
        return { name = disease.displayName }
    end

    return { name = tostring(diseaseId or "Unknown Disease") }
end

function EHR_HealthPanelUI:getDiseaseName(diseaseId, disease)
    local definition = self:getDiseaseDefinition(diseaseId, disease)
    return (definition and definition.name) or tostring(diseaseId or "Unknown Disease")
end

function EHR_HealthPanelUI:hasDiseaseKnowledge(diseaseId)
    local knowledgePlayer = self:getKnowledgePlayer()
    if not knowledgePlayer then return false end
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.KnowsDisease then
        return EHR.DiseaseFlyers.KnowsDisease(knowledgePlayer, diseaseId) == true
    end
    return false
end

function EHR_HealthPanelUI:isSelfEvidentDisease(diseaseId)
    local normalized = self:getNormalizedDiseaseId(diseaseId)
    local config = EHR.DiseaseFlyers and EHR.DiseaseFlyers.Config or nil
    return config and config.SELF_EVIDENT and config.SELF_EVIDENT[normalized] == true
end

function EHR_HealthPanelUI:getUnknownDiseaseInfo(diseaseId)
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.GetUnknownDiseaseDisplay then
        local info = EHR.DiseaseFlyers.GetUnknownDiseaseDisplay(diseaseId)
        if type(info) == "table" then
            return info
        end
    end
    return {
        displayName = safeText("UI_EHR_DiseaseUnknown", "Unknown Illness"),
        description = safeText("UI_EHR_DiseaseUnknownDesc", "You feel unwell."),
    }
end

function EHR_HealthPanelUI:getDiseaseDisplayInfo(diseaseId, disease)
    local skillTier, skillLevel = self:getMedicalSkillTier(true)
    local normalized = self:getNormalizedDiseaseId(diseaseId)
    local definition = self:getDiseaseDefinition(diseaseId, disease)
    local realName = (definition and definition.name) or tostring(diseaseId or "Unknown Disease")

    if type(disease) == "table" and disease.isKnox then
        local canIdentifyKnox = self:hasDiseaseKnowledge("knox_infection")
        if not canIdentifyKnox then
            local unknownInfo = self:getUnknownDiseaseInfo("knox_infection")
            local unknownName = unknownInfo.displayName or safeText("UI_EHR_DiseaseUnknown", "Unknown Illness")
            return {
                displayName = unknownName,
                realName = unknownName,
                sortName = unknownName,
                normalizedId = "knox_infection",
                iconKey = "unknown",
                canIdentify = false,
                showStageSeverity = false,
                showProgress = false,
                showTreatmentStatus = false,
                detailText = unknownInfo.description or safeText("UI_EHR_DiseaseUnknownDesc", "You feel unwell."),
                progressText = "",
                hideProgressBar = true,
                skillTier = skillTier,
                skillLevel = skillLevel,
            }
        end

        local displayName = disease.displayName or realName
        return {
            displayName = displayName,
            realName = displayName,
            sortName = displayName,
            normalizedId = "knox_infection",
            iconKey = "knox_infection",
            canIdentify = true,
            showStageSeverity = false,
            showProgress = false,
            showTreatmentStatus = true,
            statusText = safeText("UI_EHR_Status_NoCure", "NO CURE"),
            detailText = safeText("UI_EHR_KnoxNoCureDetail", "This is how you die"),
            progressText = "",
            hideProgressBar = true,
            skillTier = skillTier,
            skillLevel = skillLevel,
        }
    end

    if type(disease) == "table" and (disease.isCorpseExposure or disease.isExposureCondition) then
        return {
            displayName = disease.displayName or realName,
            realName = disease.displayName or realName,
            sortName = disease.displayName or realName,
            normalizedId = normalized,
            iconKey = disease.iconKey or normalized,
            canIdentify = true,
            showStageSeverity = true,
            showProgress = true,
            showTreatmentStatus = false,
            skillTier = skillTier,
            skillLevel = skillLevel,
            isCorpseExposure = disease.isCorpseExposure == true,
            isExposureCondition = disease.isExposureCondition == true,
        }
    end

    local diagnosed = type(disease) == "table" and disease.diagnosed == true
    local canIdentify = skillTier >= 4
        or diagnosed
        or self:hasDiseaseKnowledge(normalized)
        or self:isSelfEvidentDisease(normalized)
    local unknownInfo = self:getUnknownDiseaseInfo(normalized)
    local displayName = canIdentify and realName or (unknownInfo.displayName or safeText("UI_EHR_DiseaseUnknown", "Unknown Illness"))
    local detailText = nil
    local detailColor = nil
    local statusText = nil
    local statusColor = nil
    local hideProgressBar = nil
    local showStageSeverity = canIdentify and skillTier >= 2
    local showProgress = canIdentify and skillTier >= 3
    local showTreatmentStatus = canIdentify and skillTier >= 3
    local progressText = nil

    if normalized == "concussion" and canIdentify then
        local stage = type(disease) == "table" and (tonumber(disease.stage) or 1) or 1
        detailText = safeFormat("UI_EHR_DiseaseDetail_StageTimeRest", "Stage %d   Time and rest", stage)
        detailColor = EHR_HealthPanelUI.Colors.green
        statusText = safeText("UI_EHR_Status_Recovering", "RECOVERING")
        statusColor = EHR_HealthPanelUI.Colors.green
    end

    if normalized == "delirium" and canIdentify then
        detailText = safeText("UI_EHR_DeliriumCourseRequired", "Antipsychotic course required")
        detailColor = EHR_HealthPanelUI.Colors.yellow
        statusText = nil
        statusColor = nil
        showStageSeverity = false
        showProgress = false
        showTreatmentStatus = true
        hideProgressBar = true
        progressText = ""
    end

    return {
        displayName = displayName,
        realName = realName,
        sortName = displayName,
        normalizedId = normalized,
        canIdentify = canIdentify,
        showStageSeverity = showStageSeverity,
        showProgress = showProgress,
        showTreatmentStatus = showTreatmentStatus,
        detailText = detailText,
        detailColor = detailColor,
        statusText = statusText,
        statusColor = statusColor,
        progressText = progressText,
        hideProgressBar = hideProgressBar,
        skillTier = skillTier,
        skillLevel = skillLevel,
    }
end

function EHR_HealthPanelUI:getDiseaseProgress(disease)
    if type(disease) ~= "table" then return 0 end

    if disease.progressMode == "stage" then
        local stageProgress = tonumber(disease.stageProgress)
        if stageProgress then
            if stageProgress <= 1 then return clamp(stageProgress * 100, 0, 100) end
            return clamp(stageProgress, 0, 100)
        end

        local progress = tonumber(disease.progress)
        if progress then
            if progress <= 1 then return clamp(progress * 100, 0, 100) end
            return clamp(progress, 0, 100)
        end
    end

    local progress = tonumber(disease.progress)
    if disease.temperatureDriven and progress then
        if progress <= 1 then return progress * 100 end
        return progress
    end

    local started = tonumber(disease.startTime)
    local ended = tonumber(disease.endTime)
    if started and ended and ended > started then
        return clamp(((getWorldAgeHours() - started) / (ended - started)) * 100, 0, 100)
    end

    local duration = tonumber(disease.duration)
    if started and duration and duration > 0 then
        return clamp(((getWorldAgeHours() - started) / duration) * 100, 0, 100)
    end

    progress = tonumber(disease.progress)
    if progress then
        if progress <= 1 then return progress * 100 end
        return progress
    end

    return 0
end

function EHR_HealthPanelUI:getProgressSmoothingKey(diseaseId, disease)
    local playerKey = tostring(self.playerNum or 0)
    if self.player then
        local ok, onlineId = pcall(function()
            return self.player:getOnlineID()
        end)
        if ok and onlineId ~= nil then
            playerKey = tostring(onlineId)
        end
    end

    local diseaseKey = tostring(diseaseId or "")
    if diseaseKey == "" and type(disease) == "table" then
        diseaseKey = tostring(disease.iconKey or disease.displayName or disease.name or "unknown")
    end

    return playerKey .. ":" .. diseaseKey
end

function EHR_HealthPanelUI:getSmoothedDiseaseProgress(diseaseId, disease, targetProgress)
    targetProgress = clamp(tonumber(targetProgress) or 0, 0, 100)
    self.progressSmoothing = self.progressSmoothing or {}

    local key = self:getProgressSmoothingKey(diseaseId, disease)
    local state = self.progressSmoothing[key]
    if not state then
        self.progressSmoothing[key] = { value = targetProgress }
        return targetProgress
    end

    local current = tonumber(state.value) or targetProgress
    local delta = targetProgress - current
    if math.abs(delta) <= 0.15 then
        current = targetProgress
    else
        current = current + delta * 0.12
    end

    state.value = clamp(current, 0, 100)
    return state.value
end

function EHR_HealthPanelUI:isDiseaseTreated(diseaseId)
    local disease = self.cachedData and self.cachedData.diseases and self.cachedData.diseases[diseaseId]
    if type(disease) == "table" and disease.treating == true then
        return true
    end

    local medication = self.cachedData.medication or {}
    local active = medication.activeTreatments or {}
    local normalized = self:getNormalizedDiseaseId(diseaseId)
    return active[diseaseId] ~= nil or active[normalized] ~= nil
end

function EHR_HealthPanelUI:getDiseaseAccent(diseaseId, name)
    local c = EHR_HealthPanelUI.Colors
    local key = tostring(diseaseId or ""):lower() .. " " .. tostring(name or ""):lower()

    if string.find(key, "asperg", 1, true) or string.find(key, "pneum", 1, true) or string.find(key, "resp", 1, true) then
        return c.purple, "R"
    end
    if string.find(key, "food", 1, true) or string.find(key, "toxin", 1, true) or string.find(key, "poison", 1, true) then
        return c.red, "!"
    end
    if string.find(key, "trich", 1, true) or string.find(key, "paras", 1, true) then
        return c.orange, "P"
    end
    if string.find(key, "corpse", 1, true) or string.find(key, "cadaver", 1, true) then
        return c.red, "C"
    end
    if string.find(key, "cold", 1, true) or string.find(key, "flu", 1, true) then
        return c.blue, "+"
    end

    return c.red, "?"
end

function EHR_HealthPanelUI:buildActiveDiseaseTable(diseaseData)
    local activeDiseases = {}
    if type(diseaseData) == "table" and type(diseaseData.active) == "table" then
        for diseaseId, disease in pairs(diseaseData.active) do
            local normalized = self:getNormalizedDiseaseId(diseaseId)
            if normalized == "knox_infection" then
                -- Knox is displayed from the live vanilla/EHR Knox state below.
                -- Skip legacy EHR disease entries so external cures, like LGD
                -- Antibodies, cannot leave a ghost card in the monitor.
                if EHR.KnoxCure and EHR.KnoxCure.IsInfected and self.player then
                    pcall(function()
                        EHR.KnoxCure.IsInfected(self.player)
                    end)
                end
            else
                activeDiseases[diseaseId] = disease
            end
        end
    end
    return activeDiseases
end

function EHR_HealthPanelUI:getCadavericExposureDisplay(exposure, config)
    exposure = tonumber(exposure) or 0
    local highThreshold = tonumber(config and config.ASPERGILLOSIS_EXPOSURE_THRESHOLD) or 120
    if highThreshold <= 0 or exposure <= 0 then
        return "None"
    end

    if exposure >= highThreshold then
        return "High"
    elseif exposure >= highThreshold * 0.60 then
        return "Medium"
    elseif exposure >= (tonumber(config and config.ASPERGILLOSIS_DISPLAY_MIN_EXPOSURE) or 1) then
        return "Low"
    end

    return "None"
end

function EHR_HealthPanelUI:getCadavericExposureProgress(exposure, config)
    exposure = tonumber(exposure) or 0
    local highThreshold = tonumber(config and config.ASPERGILLOSIS_EXPOSURE_THRESHOLD) or 120
    if highThreshold <= 0 then return 0 end

    return clamp(exposure / highThreshold, 0, 1)
end

function EHR_HealthPanelUI:getCorpseExposureColor(exposureLevel)
    if EHR.CorpseSickness and EHR.CorpseSickness.GetExposureColor then
        local ok, result = pcall(function()
            return EHR.CorpseSickness.GetExposureColor(exposureLevel)
        end)
        if ok then
            return result
        end
    end
    return nil
end

function EHR_HealthPanelUI:addSpecialConditionEntries(activeDiseases, data)
    data = data or {}

    if EHR.CorpseSickness and EHR.CorpseSickness.GetExposureDisplay and self.player then
        local ok, exposureLevel = pcall(function()
            return EHR.CorpseSickness.GetExposureDisplay(self.player)
        end)

        if ok and exposureLevel and exposureLevel ~= "None" then
            local exposureData = nil
            if EHR.CorpseSickness.GetExposureData then
                local dataOk, result = pcall(function()
                    return EHR.CorpseSickness.GetExposureData(self.player)
                end)
                if dataOk then
                    exposureData = result
                end
            end

            local exposure = 0
            if type(exposureData) == "table" then
                exposure = math.max(tonumber(exposureData.currentExposure) or 0, tonumber(exposureData.vanillaCorpseExposure) or 0)
            end

            local config = EHR.CorpseSickness.Config or {}
            local highThreshold = tonumber(config.EXPOSURE_THRESHOLD_HIGH) or 100
            local stageByLevel = { Low = 1, Medium = 2, High = 3 }
            local stage = stageByLevel[exposureLevel] or 1
            local exposureColor = nil
            if EHR.CorpseSickness.GetExposureColor then
                local colorOk, result = pcall(function()
                    return EHR.CorpseSickness.GetExposureColor(exposureLevel)
                end)
                if colorOk then
                    exposureColor = result
                end
            end

            activeDiseases["corpse_exposure"] = {
                displayName = safeText("UI_EHR_CorpseExposure", "Corpse Exposure"),
                exposureLevel = exposureLevel,
                exposureColor = exposureColor,
                severity = stage,
                progress = highThreshold > 0 and clamp(exposure / highThreshold, 0, 1) or 0,
                stage = stage,
                isCorpseExposure = true,
                iconKey = "corpse_exposure",
            }
        end
    end

    if EHR.CorpseSickness and EHR.CorpseSickness.GetExposureData and self.player and not activeDiseases["cadaveric_aspergillosis"] then
        local ok, exposureData = pcall(function()
            return EHR.CorpseSickness.GetExposureData(self.player)
        end)

        if ok and type(exposureData) == "table" then
            local config = EHR.CorpseSickness.Config or {}
            local exposure = tonumber(exposureData.fungalExposure) or 0
            local exposureLevel = self:getCadavericExposureDisplay(exposure, config)

            if exposureLevel ~= "None" then
                local highThreshold = tonumber(config.ASPERGILLOSIS_EXPOSURE_THRESHOLD) or 120
                local stageByLevel = { Low = 1, Medium = 2, High = 3 }
                local stage = stageByLevel[exposureLevel] or 1

                activeDiseases["cadaveric_aspergillosis_exposure"] = {
                    displayName = safeText("UI_EHR_CadavericAspergillosisExposure", "Cadaveric Aspergillosis Exposure"),
                    exposureLevel = exposureLevel,
                    exposureColor = self:getCorpseExposureColor(exposureLevel),
                    severity = stage,
                    progress = self:getCadavericExposureProgress(exposure, config),
                    stage = stage,
                    isCorpseExposure = true,
                    iconKey = "cadaveric_aspergillosis",
                }
            end
        end
    end

    if EHR.Environmental and EHR.Environmental.GetHeatExposureDisplay and self.player
            and not activeDiseases["heat_stroke"] then
        local ok, exposureLevel = pcall(function()
            return EHR.Environmental.GetHeatExposureDisplay(self.player)
        end)

        if ok and exposureLevel and exposureLevel ~= "None" then
            local ratio = 0
            local ratioOk, ratioResult = pcall(function()
                return EHR.Environmental.GetHeatExposureRatio(self.player)
            end)
            if ratioOk then ratio = tonumber(ratioResult) or 0 end

            local stageByLevel = { Low = 1, Medium = 2, High = 3 }
            local stage = stageByLevel[exposureLevel] or 1
            local exposureColor = nil
            if EHR.Environmental.GetHeatExposureColor then
                local colorOk, colorResult = pcall(function()
                    return EHR.Environmental.GetHeatExposureColor(exposureLevel)
                end)
                if colorOk then exposureColor = colorResult end
            end

            activeDiseases["heat_exhaustion_exposure"] = {
                displayName = safeText("UI_EHR_Moodle_HeatExposure_Title", "Heat Exhaustion Exposure"),
                exposureLevel = exposureLevel,
                exposureColor = exposureColor,
                severity = stage,
                progress = clamp(ratio, 0, 1),
                stage = stage,
                isExposureCondition = true,
                iconKey = "heat_exhaustion",
            }
        end
    end

    local sepsisData = data.EHR_Sepsis
    if EHR.Sepsis and EHR.Sepsis.GetData and self.player then
        local ok, result = pcall(function()
            return EHR.Sepsis.GetData(self.player)
        end)
        if ok and result then
            sepsisData = result
        end
    end

    local sepsisProgress, sepsisStage = getSepsisProgress(sepsisData)
    if sepsisStage > 0 then
        activeDiseases["Sepsis"] = {
            severity = sepsisStage,
            progress = sepsisProgress,
            treating = (tonumber(sepsisData.treatmentDoses) or 0) > 0,
            stage = sepsisStage,
            isSepsis = true,
            sourceBodyPart = sepsisData.sourceBodyPart,
        }
    end

    local knoxInfected = false
    local knoxProgress = 0
    if self.isRemoteHealthPanel and type(data.EHR_KnoxStatus) == "table" then
        knoxInfected = data.EHR_KnoxStatus.infected == true
        knoxProgress = math.max(0, math.min(1, tonumber(data.EHR_KnoxStatus.progress) or 0))
    elseif EHR.KnoxCure and EHR.KnoxCure.IsInfected and self.player then
        local ok, isInfected = pcall(function()
            return EHR.KnoxCure.IsInfected(self.player)
        end)
        knoxInfected = ok and isInfected == true
        if knoxInfected and EHR.KnoxCure.GetInfectionProgress then
            local progressOk, progress = pcall(function()
                return EHR.KnoxCure.GetInfectionProgress(self.player)
            end)
            if progressOk then
                knoxProgress = math.max(0, math.min(1, tonumber(progress) or 0))
            end
        end
    end

    if knoxInfected then
        activeDiseases["knox_infection"] = {
            displayName = safeText("UI_EHR_KnoxInfection", "Knox Virus Infection"),
            severity = 0,
            progress = knoxProgress,
            stage = 0,
            isKnox = true,
            iconKey = "knox_infection",
            noCure = true,
        }
    end

    local woundData = data.EHR_WoundInfection
    if not self.isRemoteHealthPanel and EHR.WoundInfection and EHR.WoundInfection.GetData and self.player then
        local ok, result = pcall(function()
            return EHR.WoundInfection.GetData(self.player)
        end)
        if ok and result then
            woundData = result
        end
    end

    local worstStage = tonumber(woundData and woundData.worstStage) or 0
    local infectedCount = tonumber(woundData and (woundData.totalInfectedParts or woundData.infectedCount)) or 0
    if infectedCount <= 0 and type(woundData) == "table" and type(woundData.parts) == "table" then
        for _, partData in pairs(woundData.parts) do
            local partStage = tonumber(partData and partData.stage) or 0
            if partStage > 0 then
                infectedCount = infectedCount + 1
                worstStage = math.max(worstStage, partStage)
            end
        end
    end

    if worstStage > 0 then
        local woundProgress, calculatedStage, calculatedPart = getWoundInfectionProgress(woundData)
        if calculatedStage > 0 then
            worstStage = calculatedStage
        end
        activeDiseases["Wound_Infection"] = {
            severity = worstStage,
            progress = woundProgress,
            stage = worstStage,
            isWoundInfection = true,
            infectedCount = math.max(1, infectedCount),
            worstPart = calculatedPart or (woundData and woundData.worstPart or nil),
        }
    end
end

function EHR_HealthPanelUI:updateCachedData()
    if self.isRemoteHealthPanel then
        local patient = self.remotePatient or self.player
        if patient and self.remotePatientOnlineID and getPlayerByOnlineID then
            local ok, refreshed = pcall(function()
                return getPlayerByOnlineID(self.remotePatientOnlineID)
            end)
            if ok and refreshed and refreshed ~= patient then
                self:bindRemotePatient(self.remoteDoctor, refreshed, true)
                patient = refreshed
            end
        end
        self.player = patient
    else
        local player = getSpecificPlayer and getSpecificPlayer(self.playerNum or 0)
        if player then
            if player ~= self.player then
                self:bindPlayer(player, true)
            else
                self.player = player
            end
        else
            self.player = player
        end
    end

    local data = nil
    if self.isRemoteHealthPanel and type(self.remoteExamData) == "table" then
        data = self.remoteExamData
    elseif EHR.GetPlayerData and self.player then
        data = EHR.GetPlayerData(self.player)
    end
    if not data and self.player and self.player.getModData then
        data = self.player:getModData()
    end
    data = data or {}

    local diseaseData = nil
    if self.isRemoteHealthPanel and data.EHR_Disease then
        diseaseData = data.EHR_Disease
    elseif EHR.Disease and EHR.Disease.GetDiseaseData and self.player then
        diseaseData = EHR.Disease.GetDiseaseData(self.player)
    end
    diseaseData = diseaseData or data.EHR_Disease or {}

    local medicationData = {}
    if self.isRemoteHealthPanel and data.EHR_Medication then
        medicationData = data.EHR_Medication or {}
    elseif EHR.Medication and EHR.Medication.GetMedicationData and self.player then
        medicationData = EHR.Medication.GetMedicationData(self.player) or {}
    else
        medicationData = data.EHR_Medication or {}
    end

    local medicationView = nil
    if self.isRemoteHealthPanel and type(data.EHR_MedicationView) == "table" then
        medicationView = data.EHR_MedicationView
    end

    local activeTreatments = {}
    if medicationView and medicationView.activeTreatments then
        activeTreatments = medicationView.activeTreatments or {}
    elseif self.isRemoteHealthPanel and medicationData.activeTreatments then
        activeTreatments = medicationData.activeTreatments or {}
    elseif EHR.Medication and EHR.Medication.GetActiveTreatments and self.player then
        activeTreatments = EHR.Medication.GetActiveTreatments(self.player) or {}
    end

    local doseStatuses = {}
    if medicationView and medicationView.activeDoses then
        doseStatuses = medicationView.activeDoses or {}
    elseif self.isRemoteHealthPanel and medicationData.activeDoses then
        doseStatuses = medicationData.activeDoses or {}
    elseif EHR.Medication and EHR.Medication.GetAllDoseStatuses and self.player then
        doseStatuses = EHR.Medication.GetAllDoseStatuses(self.player) or {}
    end

    local activeSideEffects = {}
    if medicationView and medicationView.activeSideEffects then
        activeSideEffects = medicationView.activeSideEffects or {}
    elseif self.isRemoteHealthPanel and medicationData.activeSideEffects then
        activeSideEffects = medicationData.activeSideEffects or {}
    elseif EHR.Medication and EHR.Medication.GetMonitorSideEffects and self.player then
        activeSideEffects = EHR.Medication.GetMonitorSideEffects(self.player) or {}
    elseif EHR.Medication and EHR.Medication.GetActiveSideEffects and self.player then
        activeSideEffects = EHR.Medication.GetActiveSideEffects(self.player) or {}
    end

    local activeDiseases = self:buildActiveDiseaseTable(diseaseData)
    self:addSpecialConditionEntries(activeDiseases, data)

    local activeMedications = self:buildActiveMedicationList(activeTreatments, doseStatuses)
    self:addKnoxCureMedicationEntries(activeMedications, activeSideEffects)

    self.cachedData = {
        blood = data.EHR_Blood or {},
        diseases = activeDiseases,
        medication = medicationData,
        activeTreatments = activeTreatments,
        doseStatuses = doseStatuses,
        activeMedications = activeMedications,
        activeSideEffects = activeSideEffects,
        bodyStatus = data.EHR_BodyStatus or {},
        immunity = data.EHR_Immunity or {},
    }
end

function EHR_HealthPanelUI:refreshRemoteExamDataIfNeeded()
    if not self.isRemoteHealthPanel or not self.remoteDoctor or not self.remotePatient then return end
    if not EHR.MPExamination or not EHR.MPExamination.RequestExamData then return end
    if not isClient or not isClient() then return end

    local now = getTimestampMs and getTimestampMs() or 0
    if now <= 0 then return end
    if self.lastRemoteExamRefreshMs and (now - self.lastRemoteExamRefreshMs) < 5000 then
        return
    end

    self.lastRemoteExamRefreshMs = now
    EHR.MPExamination.RequestExamData(self.remoteDoctor, self.remotePatient, true)
end

function EHR_HealthPanelUI:getBloodSummary()
    local blood = self.cachedData.blood or {}
    local maxVolume = tonumber(blood.maxVolume) or 5000
    local current = clamp(tonumber(blood.currentVolume) or maxVolume, 0, maxVolume)
    local saline = math.max(0, tonumber(blood.transfusedSaline) or 0)
    local salinePct = 0
    if current > 0 then
        salinePct = clamp((saline / current) * 100, 0, 100)
    end

    local bloodPct = clamp((current / maxVolume) * 100, 0, 100)
    return {
        current = current,
        max = maxVolume,
        bloodPct = bloodPct,
        saline = saline,
        salinePct = salinePct,
        bloodType = blood.bloodType or "?",
        canHeal = blood.canHeal,
        healBlockReason = blood.healBlockReason,
    }
end

function EHR_HealthPanelUI:hasMedicalMonitorWatch()
    if self.isRemoteHealthPanel and type(self.remoteExamData) == "table" then
        if self.remoteExamData.EHR_HasMedicalMonitorWatch ~= nil then
            return self.remoteExamData.EHR_HasMedicalMonitorWatch == true
        end

        local bodyStatus = self.remoteExamData.EHR_BodyStatus
        if type(bodyStatus) == "table" and bodyStatus.hasMedicalMonitorWatch ~= nil then
            return bodyStatus.hasMedicalMonitorWatch == true
        end
    end

    local player = self.player or (getSpecificPlayer and getSpecificPlayer(self.playerNum or 0)) or (getPlayer and getPlayer())
    if not player or not player.getWornItems then return false end

    local wornItems = player:getWornItems()
    if not wornItems then return false end

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item and item.getFullType then
            local fullType = item:getFullType()
            if MEDICAL_MONITOR_WATCH_ITEMS[fullType] then
                if not EHR.WatchBattery or EHR.WatchBattery.IsPowered(item) then return true end
            end
            if item.getType and MEDICAL_MONITOR_WATCH_ITEMS[item:getType()] then
                if not EHR.WatchBattery or EHR.WatchBattery.IsPowered(item) then return true end
            end
        end
    end

    return false
end

function EHR_HealthPanelUI:isMedicalWatchRequired()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.MedicalWatchRequired ~= nil then
        return options.MedicalWatchRequired
    end
    return true
end

function EHR_HealthPanelUI:getBloodBagTexture(summary)
    if not getTexture then return nil end
    self.bloodBagTextures = self.bloodBagTextures or {}

    local bloodPct = tonumber(summary and summary.bloodPct) or 0
    if bloodPct <= 12 then
        if self.bloodBagTextures.empty == nil then
            self.bloodBagTextures.empty = getTexture("media/textures/Item_BloodBagEmpty.png") or false
        end
        if self.bloodBagTextures.empty then return self.bloodBagTextures.empty end
    end

    local bloodType = tostring(summary and summary.bloodType or ""):gsub("%+", "Pos"):gsub("%-", "Neg")
    if bloodType ~= "" then
        local key = "type_" .. bloodType
        if self.bloodBagTextures[key] == nil then
            self.bloodBagTextures[key] = getTexture("media/textures/Item_BloodBag" .. bloodType .. ".png") or false
        end
        if self.bloodBagTextures[key] then return self.bloodBagTextures[key] end
    end

    if self.bloodBagTextures.full == nil then
        self.bloodBagTextures.full = getTexture("media/textures/Item_BloodBag.png") or false
    end
    return self.bloodBagTextures.full or nil
end

function EHR_HealthPanelUI:drawBloodBagFallbackIcon(x, y, w, h, bloodPct)
    local c = EHR_HealthPanelUI.Colors
    local fillPct = clamp((tonumber(bloodPct) or 0) / 100, 0, 1)
    local bodyX = x + 2
    local bodyY = y + 4
    local bodyW = math.max(8, w - 4)
    local bodyH = math.max(10, h - 4)
    local fillH = math.floor((bodyH - 4) * fillPct)

    self:drawRect(bodyX + 4, y, math.max(4, bodyW - 8), 4, 0.95, 0.68, 0.68, 0.68)
    self:drawRect(bodyX, bodyY, bodyW, bodyH, 0.92, 0.06, 0.07, 0.075)
    self:drawRect(bodyX + 2, bodyY + 2, bodyW - 4, bodyH - 4, 0.58, 0.16, 0.16, 0.16)
    if fillH > 0 then
        self:drawRect(bodyX + 2, bodyY + bodyH - 2 - fillH, bodyW - 4, fillH, c.red.a, c.red.r, c.red.g, c.red.b)
    end
    self:drawRect(bodyX + 4, bodyY + 4, math.max(2, bodyW - 8), 2, 0.35, 1, 1, 1)
    self:drawRectBorder(bodyX, bodyY, bodyW, bodyH, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(bodyX + 4, y, math.max(4, bodyW - 8), 4, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:drawBloodBagIcon(x, y, w, h, summary)
    local c = EHR_HealthPanelUI.Colors
    local texture = self:getBloodBagTexture(summary)
    local bloodPct = tonumber(summary and summary.bloodPct) or 0

    if texture and self.drawTextureScaled then
        if bloodPct <= 12 then
            self:drawRect(x + 2, y + 2, w - 4, h - 4, 0.30, 0.54, 0.66, 0.66)
        end
        self:drawTextureScaled(texture, x, y, w, h, 1.0, 1.0, 1.0, 1.0)
        return
    end

    self:drawBloodBagFallbackIcon(x, y, w, h, bloodPct)
end

function EHR_HealthPanelUI:drawBloodBar(x, y, w, h, summary, hideIcon)
    local c = EHR_HealthPanelUI.Colors
    if not hideIcon and w > 72 then
        local iconW = math.min(24, math.max(18, h + 8))
        self:drawBloodBagIcon(x, y - 4, iconW, h + 8, summary)
        x = x + iconW + 7
        w = math.max(20, w - iconW - 7)
    end

    local bloodW = math.floor(w * clamp(summary.bloodPct / 100, 0, 1))
    local salineW = math.floor(w * clamp(summary.salinePct / 100, 0, 1))

    self:drawRect(x - 4, y - 4, w + 8, h + 8, 0.78, 0.015, 0.015, 0.018)
    self:drawRectBorder(x - 4, y - 4, w + 8, h + 8, 0.65, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    self:drawRect(x, y, w, h, 1, 0.08, 0.06, 0.06)
    if bloodW > 0 then
        self:drawRect(x, y, bloodW, h, c.red.a, c.red.r, c.red.g, c.red.b)
        self:drawRect(x, y, bloodW, math.max(2, math.floor(h * 0.22)), 0.22, 1, 0.78, 0.70)
    end
    if salineW > 0 then
        self:drawRect(x + math.max(0, bloodW - salineW), y, salineW, h, c.blue.a, c.blue.r, c.blue.g, c.blue.b)
    end
    self:drawRectBorder(x, y, w, h, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:drawLockedBloodSensor(x, y, w, h)
    local c = EHR_HealthPanelUI.Colors
    self:drawRect(x - 4, y - 4, w + 8, h + 8, 0.78, 0.015, 0.015, 0.018)
    self:drawRectBorder(x - 4, y - 4, w + 8, h + 8, 0.65, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    self:drawRect(x, y, w, h, 1, 0.035, 0.035, 0.04)
    self:drawRect(x, y, w, math.max(2, math.floor(h * 0.22)), 0.14, 0.8, 0.8, 0.72)
    self:drawTextCentre("Medical watch required", x + math.floor(w / 2), y + 1, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    self:drawRectBorder(x, y, w, h, c.borderDim.a, c.borderDim.r, c.borderDim.g, c.borderDim.b)
end

function EHR_HealthPanelUI:drawMedicalWatchIcon(x, y, w, h)
    local c = EHR_HealthPanelUI.Colors
    if getTexture then
        self.medicalWatchTexture = self.medicalWatchTexture or getTexture("media/textures/Item_EhrWatch.png") or false
    end
    self:drawRect(x + 5, y + 4, w - 10, h - 8, 0.34, 0.02, 0.02, 0.025)
    self:drawRectBorder(x + 5, y + 4, w - 10, h - 8, 0.55, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    if self.medicalWatchTexture then
        local iconSize = math.min(w - 8, h - 8)
        self:drawTextureScaled(self.medicalWatchTexture, x + math.floor((w - iconSize) / 2), y + math.floor((h - iconSize) / 2), iconSize, iconSize, 0.42, 0.65, 0.65, 0.65)
    else
        self:drawTextCentre("MW", x + math.floor(w / 2), y + math.floor(h / 2) - 8, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
    end
end

function EHR_HealthPanelUI:drawBloodCompositionPanel()
    local c = EHR_HealthPanelUI.Colors
    local summary = self:getBloodSummary()
    local hasWatch = self:hasMedicalMonitorWatch()
    local x = 12
    local y = self:getContentTop()
    local w = self.width - 24
    local h = self.BLOOD_PANEL_HEIGHT
    local diseaseCount = countTable(self.cachedData.diseases)
    local medicationCount = #(self.cachedData.activeMedications or {})
    local watchRequired = self:isMedicalWatchRequired()
    self:drawPanelFrame(x, y, w, h, "BLOOD COMPOSITION", nil)

    hasWatch = (not watchRequired) or hasWatch

    local iconW = hasWatch and 54 or 64
    local iconH = 70
    local iconX = hasWatch and (x + 18) or (x + 13)
    local iconY = hasWatch and (y + 44) or (y + 38)
    if hasWatch then
        self:drawBloodBagIcon(iconX, iconY, iconW, iconH, summary)
    else
        self:drawMedicalWatchIcon(iconX, iconY, iconW, iconH)
    end

    local percentW = 112
    local barX = iconX + iconW + 22
    local barY = y + 52
    local barW = math.max(120, w - (barX - x) - percentW - 24)
    if hasWatch then
        self:drawBloodBar(barX, barY, barW, 30, summary, true)
        self:drawDockedTextRight(string.format("%d%%", math.floor(summary.bloodPct + 0.5)), x + w - 18, y + 46, 36, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Large)
        if self.rightExpanded then
            self:drawTextRight(string.format("%dmL / %dmL", math.floor(summary.current + 0.5), math.floor(summary.max + 0.5)), x + w - 18, y + 88, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        end
    else
        self:drawLockedBloodSensor(barX, barY, barW, 30)
    end

    local stripY = y + h - 38
    local stripX = barX + 2
    local stripFont = self:getCompactFont()

    if not self.rightExpanded then
        if not hasWatch then
            return
        end
        local compactText = hasWatch and string.format("%dmL / %dmL", math.floor(summary.current + 0.5), math.floor(summary.max + 0.5)) or "Medical watch required"
        self:drawText(self:truncateText(compactText, math.max(80, barW - 4), stripFont), stripX, stripY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, stripFont)
        return
    end

    local stripRight = math.min(barX + barW, x + w - 196)
    if stripRight < stripX + 220 then
        stripRight = barX + barW
    end
    local cells = {}
    if hasWatch then
        table.insert(cells, { text = string.format("Saline: %dmL (%d%%)", math.floor(summary.saline + 0.5), math.floor(summary.salinePct + 0.5)), color = c.blue })
    end
    table.insert(cells, { text = "Conditions: " .. tostring(diseaseCount), color = c.textDim })
    table.insert(cells, { text = "Medications: " .. tostring(medicationCount), color = c.textDim })

        local cursorX = stripX
    for i, cell in ipairs(cells) do
        if i > 1 then
            self:drawRect(cursorX, stripY + 7, 1, 11, 0.62, c.red.r, c.red.g, c.red.b)
            cursorX = cursorX + 14
        end

        local available = stripRight - cursorX
        if available <= 24 then
            break
        end
        local cellColor = cell.color or c.textDim
        local text = self:truncateText(cell.text, available, stripFont)
        self:drawText(text, cursorX, stripY, cellColor.r, cellColor.g, cellColor.b, cellColor.a, stripFont)
        cursorX = cursorX + self:getTextWidth(text, stripFont) + 18
    end
end

function EHR_HealthPanelUI:drawHeader()
    local c = EHR_HealthPanelUI.Colors
    local summary = self:getBloodSummary()

    self:drawRect(0, 0, self.width, self.HEADER_HEIGHT, c.header.a, c.header.r, c.header.g, c.header.b)
    self:drawRect(0, self.HEADER_HEIGHT - 1, self.width, 1, 0.85, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(0, 0, self.width, self.height, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawDockedText(self:truncateText("EHR MEDICAL STATUS", math.max(90, self.width - 190), UIFont.Medium), 14, 0, math.max(90, self.width - 190), self.HEADER_HEIGHT, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
    local rightReserve = self.activeTab == "ehr" and 86 or 50
    if self.antibodiesButton and self.antibodiesButton:isVisible() then
        rightReserve = rightReserve + 30
    end
    self:drawDockedTextRight("[" .. tostring(summary.bloodType) .. "]", self.width - rightReserve, 0, self.HEADER_HEIGHT, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Medium)
end

function EHR_HealthPanelUI:drawTabBar()
    local c = EHR_HealthPanelUI.Colors
    local y = self.HEADER_HEIGHT
    local x = 8
    local h = self.TAB_HEIGHT
    local maxRight = self.width - 8
    local tabs = self:getTabDefinitions()
    local gap = 5
    local available = math.max(80, maxRight - x - gap * math.max(0, #tabs - 1))
    local equalW = math.floor(available / math.max(1, #tabs))

    self.tabBounds = {}
    self:drawRect(0, y, self.width, h, 0.92, 0.025, 0.025, 0.028)
    self:drawRect(0, y + h - 1, self.width, 1, 0.80, c.border.r, c.border.g, c.border.b)

    for _, tab in ipairs(tabs) do
        local label = tostring(tab.label or tab.id)
        local tabW = math.max(68, equalW)
        if tab.id == "ehr" then
            tabW = math.max(tabW, self.width >= 760 and 138 or 72)
        end
        if x + tabW > maxRight then
            tabW = math.max(58, maxRight - x)
        end
        if tabW <= 48 then break end

        local active = self.activeTab == tab.id
        local bg = active and c.redDark or c.background
        local border = active and c.red or c.borderDim
        local tabY = y + 6
        local tabH = h - 12
        local iconSize = math.min(50, math.max(30, math.min(tabH - 10, tabW - 14)))

        self:drawRect(x, tabY, tabW, tabH, active and 0.98 or 0.82, bg.r, bg.g, bg.b)
        self:drawRectBorder(x, tabY, tabW, tabH, active and 0.95 or 0.62, border.r, border.g, border.b)
        self:drawRect(x + 1, tabY + 1, tabW - 2, 1, active and 0.88 or 0.26, border.r, border.g, border.b)
        self:drawRect(x + 1, tabY + tabH - 2, tabW - 2, 1, active and 0.56 or 0.18, border.r, border.g, border.b)
        if active then
            self:drawRect(x + 2, tabY + 2, tabW - 4, tabH - 4, 0.18, c.red.r, c.red.g, c.red.b)
            self:drawRect(x + 3, tabY + tabH - 5, tabW - 6, 2, 0.70, c.red.r, c.red.g, c.red.b)
        end
        self:drawTabGlyph(tab.id, x + math.floor((tabW - iconSize) / 2), tabY + math.floor((tabH - iconSize) / 2), iconSize, active)
        table.insert(self.tabBounds, { id = tab.id, label = label, x = x, y = tabY, w = tabW, h = tabH })

        x = x + tabW + gap
        if x >= maxRight then break end
    end
end

function EHR_HealthPanelUI:drawEmbeddedTabFrame()
    local c = EHR_HealthPanelUI.Colors
    local bounds = self:getTabContentBounds()

    self:drawRect(bounds.x, bounds.y, bounds.w, bounds.h, c.panel.a, c.panel.r, c.panel.g, c.panel.b)
    self:drawRectBorder(bounds.x, bounds.y, bounds.w, bounds.h, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:getLocalMousePosition()
    local mouseX = getMouseX and getMouseX() or 0
    local mouseY = getMouseY and getMouseY() or 0
    local absX = self.getAbsoluteX and self:getAbsoluteX() or (self.x or 0)
    local absY = self.getAbsoluteY and self:getAbsoluteY() or (self.y or 0)
    return mouseX - absX, mouseY - absY
end

function EHR_HealthPanelUI:getHoveredTab()
    local mouseX, mouseY = self:getLocalMousePosition()
    for _, tab in ipairs(self.tabBounds or {}) do
        if mouseX >= tab.x and mouseX <= tab.x + tab.w and mouseY >= tab.y and mouseY <= tab.y + tab.h then
            return tab
        end
    end
    return nil
end

function EHR_HealthPanelUI:drawTabTooltip()
    local tab = self:getHoveredTab()
    if not tab or not tab.label then return end

    local c = EHR_HealthPanelUI.Colors
    local text = tostring(tab.label)
    local font = UIFont.Small
    local tooltipW = self:getTextWidth(text, font) + 22
    local tooltipH = 28
    local x = tab.x + math.floor((tab.w - tooltipW) / 2)
    local y = tab.y + tab.h + 8

    x = clamp(x, 6, math.max(6, self.width - tooltipW - 6))
    if y + tooltipH > self.height - 6 then
        y = tab.y - tooltipH - 6
    end

    self:drawRect(x, y, tooltipW, tooltipH, 0.96, 0.015, 0.012, 0.012)
    self:drawRectBorder(x, y, tooltipW, tooltipH, 0.88, c.border.r, c.border.g, c.border.b)
    self:drawDockedTextCenter(text, x, y, tooltipW, tooltipH, c.text.r, c.text.g, c.text.b, c.text.a, font, -1)
end

function EHR_HealthPanelUI:drawResizeHandle()
    local c = EHR_HealthPanelUI.Colors
    local x = self.width - 16
    local y = self.height - 16

    self:drawRect(x + 10, y + 2, 2, 12, 0.70, c.border.r, c.border.g, c.border.b)
    self:drawRect(x + 6, y + 6, 2, 8, 0.55, c.border.r, c.border.g, c.border.b)
    self:drawRect(x + 2, y + 10, 2, 4, 0.40, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:addMarker(id, label, x, y)
    local c = EHR_HealthPanelUI.Colors
    local isSelected = self.selectedZone == id
    local fill = isSelected and c.bodyHot or c.panelSoft
    local textColor = isSelected and c.green or c.text

    table.insert(self.markerBounds, { id = id, x = x, y = y, w = 24, h = 24 })
    self:drawRoundIcon(x, y, 24, fill, c.border, "+", textColor)
    self:drawText(label, x + 32, y + 4, textColor.r, textColor.g, textColor.b, textColor.a, UIFont.Small)
end

function EHR_HealthPanelUI:drawBodyDiagram(x, y, w, h)
    local c = EHR_HealthPanelUI.Colors
    local cx = x + math.floor(w / 2)
    local top = y + 18

    self.markerBounds = {}

    self:drawRoundIcon(cx - 28, top, 56, c.body, c.border, nil)
    self:drawRect(cx - 42, top + 70, 84, 150, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRectBorder(cx - 42, top + 70, 84, 150, c.border.a, c.border.r, c.border.g, c.border.b)

    self:drawRect(cx - 112, top + 82, 52, 132, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRect(cx + 60, top + 82, 52, 132, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRect(cx - 48, top + 228, 38, 154, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRect(cx + 10, top + 228, 38, 154, c.body.a, c.body.r, c.body.g, c.body.b)

    self:drawRectBorder(cx - 112, top + 82, 52, 132, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(cx + 60, top + 82, 52, 132, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(cx - 48, top + 228, 38, 154, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(cx + 10, top + 228, 38, 154, c.border.a, c.border.r, c.border.g, c.border.b)

    self:addMarker("head", "Head", x + 34, top + 15)
    self:addMarker("chest", "Chest", x + 34, top + 94)
    self:addMarker("abdomen", "Abdomen", x + 34, top + 166)
    self:addMarker("left_arm", "Left arm", x + w - 148, top + 104)
    self:addMarker("right_arm", "Right arm", x + w - 148, top + 150)
    self:addMarker("legs", "Legs", x + w - 148, top + 272)
end

function EHR_HealthPanelUI:getVanillaHealthAdapter()
    if not self.vanillaHealthAdapter then
        self.vanillaHealthAdapter = {
            owner = self,
            otherPlayer = nil,
            actions = {},
            blockingMessage = nil,
        }

        self.vanillaHealthAdapter.toString = function()
            return "EHR_VanillaHealthAdapter"
        end
        self.vanillaHealthAdapter.getAbsoluteX = function(adapter)
            return adapter.owner and adapter.owner:getAbsoluteX() or 0
        end
        self.vanillaHealthAdapter.getAbsoluteY = function(adapter)
            return adapter.owner and adapter.owner:getAbsoluteY() or 0
        end
        self.vanillaHealthAdapter.getDoctor = ISHealthPanel.getDoctor
        self.vanillaHealthAdapter.getPatient = ISHealthPanel.getPatient
        self.vanillaHealthAdapter.checkItems = ISHealthPanel.checkItems
        self.vanillaHealthAdapter.checkContainerItems = ISHealthPanel.checkContainerItems
        self.vanillaHealthAdapter.setBodyPartAction = ISHealthPanel.setBodyPartAction
        self.vanillaHealthAdapter.doBodyPartContextMenu = ISHealthPanel.doBodyPartContextMenu
        self.vanillaHealthAdapter.dropItemsOnBodyPart = ISHealthPanel.dropItemsOnBodyPart
        self.vanillaHealthAdapter.toPlayerInventory = ISHealthPanel.toPlayerInventory
    end

    self.vanillaHealthAdapter.owner = self
    self.vanillaHealthAdapter.character = self.player
    self.vanillaHealthAdapter.playerNum = self.playerNum or (self.player and self.player:getPlayerNum() or 0)
    self.vanillaHealthAdapter.otherPlayer = self.isRemoteHealthPanel and self.remoteDoctor or nil
    if self.isRemoteHealthPanel and self.remoteDoctor then
        self.vanillaHealthAdapter.doctorLevel = self.remoteDoctor:getPerkLevel(Perks.Doctor)
    end
    self.vanillaHealthAdapter.blockingMessage = nil
    self.vanillaHealthAdapter.actions = self.vanillaHealthAdapter.actions or {}

    return self.vanillaHealthAdapter
end

function EHR_HealthPanelUI:clearRemoteBodyContextRetry()
    if self.remoteBodyContextRetry and Events and Events.OnTick then
        pcall(function()
            Events.OnTick.Remove(self.remoteBodyContextRetry)
        end)
    end
    self.remoteBodyContextRetry = nil
end

function EHR_HealthPanelUI:resolveBodyPartForAction(bodyPart, bodyPartType)
    if not self.isRemoteHealthPanel then
        return bodyPart
    end

    self.remoteActionBodyPartCache = self.remoteActionBodyPartCache or {}

    if not bodyPartType then
        bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    end

    local partKey = getBodyPartTypeCacheKey(bodyPartType) or getBodyPartCacheKey(bodyPart)
    local snapshot = self:getRemoteBodyPartSnapshotByType(bodyPartType) or self:getRemoteBodyPartSnapshot(bodyPart)
    local snapshotActionable = snapshotHasActionableStatus(snapshot)

    if bodyPartHasActionableStatus(bodyPart) and bodyPartMatchesSnapshot(bodyPart, snapshot) then
        self.remoteActionBodyPartCache[partKey] = bodyPart
        return bodyPart
    end

    local bodyDamage = self:getPatientBodyDamage()
    if bodyDamage and bodyDamage.getBodyPart and bodyPartType then
        local ok, currentBodyPart = pcall(function()
            return bodyDamage:getBodyPart(bodyPartType)
        end)
        if ok and bodyPartHasActionableStatus(currentBodyPart) and bodyPartMatchesSnapshot(currentBodyPart, snapshot) then
            self.remoteActionBodyPartCache[partKey] = currentBodyPart
            return currentBodyPart
        end
    end

    local cachedBodyPart = self.remoteActionBodyPartCache[partKey]
    if snapshotActionable and bodyPartHasActionableStatus(cachedBodyPart) and bodyPartMatchesSnapshot(cachedBodyPart, snapshot) then
        return cachedBodyPart
    end

    if not snapshotActionable then
        self.remoteActionBodyPartCache[partKey] = nil
    end

    if snapshotActionable then
        return nil
    end

    return bodyPart
end

function EHR_HealthPanelUI:getBodyPartForActionType(bodyPart, bodyPartType)
    if not bodyPartType then
        bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    end

    local bodyDamage = self:getPatientBodyDamage()
    if bodyDamage and bodyDamage.getBodyPart and bodyPartType then
        local ok, currentBodyPart = pcall(function()
            return bodyDamage:getBodyPart(bodyPartType)
        end)
        if ok and currentBodyPart then
            return currentBodyPart
        end
    end

    return bodyPart
end

function EHR_HealthPanelUI:collectDoctorInventoryItems(predicate)
    local items = {}
    local doctor = self.remoteDoctor or (self.isRemoteHealthPanel and self.remoteDoctor) or self.player
    if not doctor or not predicate then return items end

    local function scanContainer(container, seen)
        if not container or seen[container] then return end
        seen[container] = true
        local containerItems = container.getItems and container:getItems() or nil
        if not containerItems or not containerItems.size then return end

        for i = 0, containerItems:size() - 1 do
            local item = containerItems:get(i)
            if item then
                if item.IsInventoryContainer and item:IsInventoryContainer() and item.getInventory then
                    scanContainer(item:getInventory(), seen)
                elseif predicate(item) then
                    table.insert(items, item)
                end
            end
        end
    end

    if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.getContainers then
        local ok, containers = pcall(function()
            return ISInventoryPaneContextMenu.getContainers(doctor)
        end)
        if ok and containers and containers.size then
            local seen = {}
            for i = 0, containers:size() - 1 do
                scanContainer(containers:get(i), seen)
            end
            return items
        end
    end

    scanContainer(doctor.getInventory and doctor:getInventory() or nil, {})
    return items
end

function EHR_HealthPanelUI:firstItemOfType(items, itemType)
    if type(items) ~= "table" then return nil end
    for _, item in ipairs(items) do
        if item and item.getFullType and item:getFullType() == itemType then
            return item
        end
    end
    return nil
end

function EHR_HealthPanelUI:firstItemByTypeOrTag(items, itemType, tagName)
    if type(items) ~= "table" then return nil end
    for _, item in ipairs(items) do
        if item and item.getType and item:getType() == itemType then
            return item
        end
        if item and tagName and item.hasTag and ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of then
            local ok, hasTag = pcall(function()
                return item:hasTag(ItemTag.get(ResourceLocation.of(tagName)))
            end)
            if ok and hasTag then
                return item
            end
        end
    end
    return nil
end

function EHR_HealthPanelUI:itemHasTag(item, tagName)
    if not item or not tagName or not item.hasTag then return false end

    if ItemTag then
        local constants = {
            RemoveBullet = ItemTag.REMOVE_BULLET,
            RemoveGlass = ItemTag.REMOVE_GLASS,
            SewingNeedle = ItemTag.SEWING_NEEDLE,
            Thread = ItemTag.THREAD,
        }
        local constant = constants[tagName]
        if constant then
            local ok, hasTag = pcall(function()
                return item:hasTag(constant)
            end)
            if ok and hasTag then return true end
        end
    end

    if ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of then
        local ok, hasTag = pcall(function()
            return item:hasTag(ItemTag.get(ResourceLocation.of(tagName)))
        end)
        return ok and hasTag == true
    end
    return false
end

function EHR_HealthPanelUI:itemIsBandage(item)
    if not item then return false end

    if item.isCanBandage then
        local ok, canBandage = pcall(function()
            return item:isCanBandage()
        end)
        if ok and canBandage == true then
            return true
        end
    end

    if item.getBandagePower then
        local ok, bandagePower = pcall(function()
            return item:getBandagePower()
        end)
        return ok and (tonumber(bandagePower) or 0) > 0
    end
    return false
end

function EHR_HealthPanelUI:itemIsDisinfectant(item)
    if not item then return false end

    if item.hasComponent and ComponentType and item:hasComponent(ComponentType.FluidContainer) then
        local ok, result = pcall(function()
            local fluidContainer = item:getFluidContainer()
            if not fluidContainer then return false end
            local amount = tonumber(fluidContainer:getAmount()) or 0
            if amount <= 0.15 then return false end
            local alcohol = 0
            if fluidContainer.getProperties and fluidContainer:getProperties() then
                alcohol = tonumber(fluidContainer:getProperties():getAlcohol()) or 0
            end
            return (alcohol / amount + 0.001) >= 0.4
        end)
        if ok and result then return true end
    end

    local okDrainable, drainable = pcall(function()
        return item:IsDrainable()
    end)
    if okDrainable and drainable and item.getAlcoholPower then
        local okAlcohol, alcoholPower = pcall(function()
            return item:getAlcoholPower()
        end)
        return okAlcohol and tonumber(alcoholPower) == 4.0
    end
    return false
end

function EHR_HealthPanelUI:itemIsRemoveGlassTool(item)
    if not item or not item.getType then return false end
    local itemType = item:getType()
    return itemType == "Tweezers"
            or itemType == "SutureNeedleHolder"
            or self:itemHasTag(item, "RemoveGlass")
end

function EHR_HealthPanelUI:itemIsRemoveBulletTool(item)
    if not item or not item.getType then return false end
    local itemType = item:getType()
    return itemType == "Tweezers"
            or itemType == "SutureNeedleHolder"
            or self:itemHasTag(item, "RemoveBullet")
end

function EHR_HealthPanelUI:itemIsBurnCleaner(item)
    return item and item.getBandagePower and (tonumber(item:getBandagePower()) or 0) >= 2
end

function EHR_HealthPanelUI:itemIsSplint(item)
    return item and item.getType and item:getType() == "Splint"
end

function EHR_HealthPanelUI:itemIsSplintBoard(item)
    if not item or not item.getType then return false end
    local itemType = item:getType()
    return itemType == "Plank"
            or itemType == "TreeBranch2"
            or itemType == "WoodenStick2"
            or itemType == "TreeBranch"
            or itemType == "WoodenStick"
end

function EHR_HealthPanelUI:itemIsRippedSheet(item)
    return item and item.getType and item:getType() == "RippedSheets"
end

function EHR_HealthPanelUI:itemIsPoultice(item, itemType)
    return item and item.getType and item:getType() == itemType
end

function EHR_HealthPanelUI:getMedicalItemRef(item)
    if not item then return nil end

    local ref = { item = item }
    pcall(function()
        if item.getID then
            ref.id = item:getID()
        end
    end)
    pcall(function()
        if item.getFullType then
            ref.fullType = item:getFullType()
        end
    end)
    pcall(function()
        if item.getType then
            ref.type = item:getType()
        end
    end)
    return ref
end

function EHR_HealthPanelUI:findDoctorInventoryItem(ref, predicate)
    if type(ref) ~= "table" then return nil end
    local doctor = self.remoteDoctor or self.player
    local inventory = doctor and doctor.getInventory and doctor:getInventory() or nil
    if not inventory then return nil end

    local function matches(item)
        if not item then return false end
        if predicate then
            local ok, result = pcall(predicate, item)
            if not ok or not result then return false end
        end
        return true
    end

    if ref.id ~= nil and inventory.getItemById then
        local item = inventory:getItemById(ref.id)
        if matches(item) then
            return item
        end
    end

    local items = inventory.getItems and inventory:getItems() or nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local sameType = false
                if ref.fullType and item.getFullType and item:getFullType() == ref.fullType then
                    sameType = true
                elseif ref.type and item.getType and item:getType() == ref.type then
                    sameType = true
                end
                if sameType and matches(item) then
                    return item
                end
            end
        end
    end

    if ref.item and ref.item.getContainer and ref.item:getContainer() == inventory and matches(ref.item) then
        return ref.item
    end
    return nil
end

function EHR_HealthPanelUI:queueActualMedicalAction(previousAction, action, bodyPart)
    if not action then
        healthPanelDisinfectDebug("queueActualMedicalAction skipped action=nil")
        return false
    end

    healthPanelDisinfectDebug(string.format("queueActualMedicalAction action=%s previous=%s bodyPart=%s",
        tostring(action), tostring(previousAction), tostring(bodyPart)))

    if previousAction then
        ISTimedActionQueue.addAfter(previousAction, action)
    else
        ISTimedActionQueue.add(action)
    end

    local adapter = self:getVanillaHealthAdapter()
    if adapter then
        adapter.actions = adapter.actions or {}
        adapter.actions[action] = bodyPart
    end

    if self.queueRemoteExamRefreshBurst then
        self:queueRemoteExamRefreshBurst()
    end
    return true
end

function EHR_HealthPanelUI:queueRemoteMedicalAction(factory, bodyPart, itemA, itemB)
    if not factory then
        healthPanelDisinfectDebug("queueRemoteMedicalAction skipped factory=nil")
        return false
    end

    local doctor = self.remoteDoctor or self.player
    local previousAction = nil
    healthPanelDisinfectDebug(string.format("queueRemoteMedicalAction start doctor=%s patient=%s bodyPart=%s itemA=%s itemB=%s",
        debugPlayerName(doctor), debugPlayerName(self.remotePatient or self.player), tostring(bodyPart),
        debugItemName(itemA), debugItemName(itemB)))

    local function moveItem(item)
        if not item or not doctor or not doctor.getInventory or not item.getContainer then return end
        local inventory = doctor:getInventory()
        if item:getContainer() ~= inventory and ISInventoryTransferUtil and ISInventoryTransferUtil.newInventoryTransferAction then
            local transfer = ISInventoryTransferUtil.newInventoryTransferAction(doctor, item, item:getContainer(), inventory)
            if previousAction then
                ISTimedActionQueue.addAfter(previousAction, transfer)
            else
                ISTimedActionQueue.add(transfer)
            end
            previousAction = transfer
        end
    end

    moveItem(itemA)
    moveItem(itemB)

    local deferredAction = EHR_RemoteMedicalAction:new(doctor, self, factory)
    if previousAction then
        ISTimedActionQueue.addAfter(previousAction, deferredAction)
    else
        ISTimedActionQueue.add(deferredAction)
    end

    local adapter = self:getVanillaHealthAdapter()
    if adapter then
        adapter.actions = adapter.actions or {}
        if previousAction then
            adapter.actions[previousAction] = bodyPart
        end
        adapter.actions[deferredAction] = bodyPart
    end

    if self.queueRemoteExamRefreshBurst then
        self:queueRemoteExamRefreshBurst()
    end
    healthPanelDisinfectDebug(string.format("queueRemoteMedicalAction end previous=%s deferred=%s",
        tostring(previousAction), tostring(deferredAction)))
    return true
end

function EHR_HealthPanelUI:addRemoteBandageOptions(context, bodyPart, snapshot)
    if snapshot.bandaged == true then
        context:addOption(getText("ContextMenu_Remove_Bandage"), self, self.onRemoteRemoveBandage, bodyPart)
        return
    end

    if snapshotHasActionableStatus(snapshot) then
        local bandages = self:collectDoctorInventoryItems(function(item)
            return self:itemIsBandage(item)
        end)
        if #bandages > 0 then
            local option = context:addOption(getText("ContextMenu_Bandage"), nil)
            local subMenu = context:getNew(context)
            context:addSubMenu(option, subMenu)
            for _, item in ipairs(bandages) do
                local subOption = subMenu:addOption(item:getName(), self, self.onRemoteApplyBandage, bodyPart, item)
                subOption.itemForTexture = item
            end
        end
    end
end
function EHR_HealthPanelUI:addRemoteStitchOptions(context, bodyPart, snapshot)
    if snapshot.stitched == true then
        context:addOption(getText("ContextMenu_Remove_Stitch"), self, self.onRemoteRemoveStitch, bodyPart)
        return
    end

    if snapshot.deepWounded ~= true or snapshot.haveGlass == true or snapshot.bandaged == true then
        return
    end

    local stitchItems = self:collectDoctorInventoryItems(function(item)
        if not item or not item.getType then return false end
        local itemType = item:getType()
        if itemType == "Needle" or itemType == "Thread" or itemType == "SutureNeedle" then
            return true
        end
        if item.hasTag and ItemTag and ResourceLocation and ItemTag.get and ResourceLocation.of then
            local okNeedle, hasNeedle = pcall(function()
                return item:hasTag(ItemTag.get(ResourceLocation.of("SewingNeedle")))
            end)
            local okThread, hasThread = pcall(function()
                return item:hasTag(ItemTag.get(ResourceLocation.of("Thread")))
            end)
            return (okNeedle and hasNeedle) or (okThread and hasThread)
        end
        return false
    end)

    local sutureNeedle = self:firstItemByTypeOrTag(stitchItems, "SutureNeedle")
    local needle = self:firstItemByTypeOrTag(stitchItems, "Needle", "SewingNeedle")
    local thread = self:firstItemByTypeOrTag(stitchItems, "Thread", "Thread")
    if not sutureNeedle and not (needle and thread) then return end

    local option = context:addOption(getText("ContextMenu_Stitch"), nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)

    if sutureNeedle then
        local subOption = subMenu:addOption(sutureNeedle:getName(), self, self.onRemoteApplyStitch, bodyPart, sutureNeedle, nil)
        subOption.itemForTexture = sutureNeedle
    end
    if needle and thread then
        local text = needle:getName() .. " + " .. thread:getName()
        local subOption = subMenu:addOption(text, self, self.onRemoteApplyStitch, bodyPart, thread, needle)
        subOption.itemForTexture = needle
    end
end

function EHR_HealthPanelUI:addRemoteGlassOptions(context, bodyPart, snapshot)
    if snapshot.haveGlass ~= true or snapshot.bandaged == true then return end

    local tools = self:collectDoctorInventoryItems(function(item)
        return self:itemIsRemoveGlassTool(item)
    end)

    local option = context:addOption(getText("ContextMenu_Remove_Glass"), nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)
    for _, item in ipairs(tools) do
        local subOption = subMenu:addOption(item:getName(), self, self.onRemoteRemoveGlass, bodyPart, item)
        subOption.itemForTexture = item
    end
    subMenu:addOption(getText("ContextMenu_Hand"), self, self.onRemoteRemoveGlass, bodyPart, "Hands")
end

function EHR_HealthPanelUI:addRemotePoulticeOptions(context, bodyPart, snapshot)
    if snapshot.bandaged == true or not snapshotHasActionableStatus(snapshot) then return end

    local definitions = {
        { itemType = "PlantainCataplasm", label = "ContextMenu_PlantainCataplasm", factorMethod = "getPlantainFactor", actionClass = ISPlantainCataplasm },
        { itemType = "ComfreyCataplasm", label = "ContextMenu_ComfreyCataplasm", factorMethod = "getComfreyFactor", actionClass = ISComfreyCataplasm },
        { itemType = "WildGarlicCataplasm", label = "ContextMenu_GarlicCataplasm", factorMethod = "getGarlicFactor", actionClass = ISGarlicCataplasm },
    }

    for _, definition in ipairs(definitions) do
        if definition.actionClass and (tonumber(callBodyPartMethod(bodyPart, definition.factorMethod, 0)) or 0) <= 0 then
            local items = self:collectDoctorInventoryItems(function(item)
                return self:itemIsPoultice(item, definition.itemType)
            end)
            if #items > 0 then
                local option = context:addOption(getText(definition.label), nil)
                local subMenu = context:getNew(context)
                context:addSubMenu(option, subMenu)
                for _, item in ipairs(items) do
                    local subOption = subMenu:addOption(item:getName(), self, self.onRemoteApplyPoultice, bodyPart, item, definition.actionClass)
                    subOption.itemForTexture = item
                end
            end
        end
    end
end

function EHR_HealthPanelUI:addRemoteDisinfectOptions(context, bodyPart, snapshot)
    healthPanelDisinfectDebug(string.format("addRemoteDisinfectOptions bandaged=%s actionable=%s ISDisinfect=%s bodyPart=%s",
        tostring(snapshot and snapshot.bandaged), tostring(snapshotHasActionableStatus(snapshot)), tostring(ISDisinfect ~= nil), tostring(bodyPart)))
    if snapshot.bandaged == true or not snapshotHasActionableStatus(snapshot) or not ISDisinfect then return end

    local items = self:collectDoctorInventoryItems(function(item)
        return self:itemIsDisinfectant(item)
    end)
    healthPanelDisinfectDebug("addRemoteDisinfectOptions items=" .. tostring(#items))
    if #items <= 0 then return end

    local option = context:addOption(getText("ContextMenu_Disinfect"), nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)
    for _, item in ipairs(items) do
        local subOption = subMenu:addOption(item:getName(), self, self.onRemoteDisinfect, bodyPart, item)
        subOption.itemForTexture = item
    end
end

function EHR_HealthPanelUI:addRemoteCleanBurnOptions(context, bodyPart, snapshot)
    if snapshot.bandaged == true or snapshot.needBurnWash ~= true or not ISCleanBurn then return end

    local items = self:collectDoctorInventoryItems(function(item)
        return self:itemIsBurnCleaner(item)
    end)
    if #items <= 0 then return end

    local option = context:addOption(getText("ContextMenu_Clean_Burn"), nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)
    for _, item in ipairs(items) do
        local subOption = subMenu:addOption(item:getName(), self, self.onRemoteCleanBurn, bodyPart, item)
        subOption.itemForTexture = item
    end
end

function EHR_HealthPanelUI:addRemoteBulletOptions(context, bodyPart, snapshot)
    if snapshot.bandaged == true or snapshot.haveBullet ~= true or not ISRemoveBullet then return end

    local tools = self:collectDoctorInventoryItems(function(item)
        return self:itemIsRemoveBulletTool(item)
    end)
    if #tools <= 0 then return end

    local option = context:addOption(getText("ContextMenu_Remove_Bullet"), nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)
    for _, item in ipairs(tools) do
        local subOption = subMenu:addOption(item:getName(), self, self.onRemoteRemoveBullet, bodyPart, item)
        subOption.itemForTexture = item
    end
end

function EHR_HealthPanelUI:addRemoteSplintOptions(context, bodyPart, snapshot)
    if not ISSplint then return end

    local splintFactor = tonumber(snapshot.splintFactor) or tonumber(callBodyPartMethod(bodyPart, "getSplintFactor", 0)) or 0
    if splintFactor > 0 then
        local option = context:addOption(getText("ContextMenu_Remove_Splint"), self, self.onRemoteRemoveSplint, bodyPart)
        local splintType = callBodyPartMethod(bodyPart, "getSplintItem", "")
        if splintType and splintType ~= "" and instanceItem then
            option.itemForTexture = instanceItem(splintType)
        end
        return
    end

    local hasInjury = snapshot.hasInjury == true or callBodyPartMethod(bodyPart, "HasInjury", false) == true
    local stitched = snapshot.stitched == true or callBodyPartMethod(bodyPart, "stitched", false) == true
    if snapshot.bandaged == true
            or not hasInjury
            or stitched
            or (tonumber(snapshot.fractureTime) or tonumber(callBodyPartMethod(bodyPart, "getFractureTime", 0)) or 0) <= 0 then
        return
    end

    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    if BodyPartType and (bodyPartType == BodyPartType.Head or bodyPartType == BodyPartType.Torso_Upper or bodyPartType == BodyPartType.Torso_Lower) then
        return
    end

    local splints = self:collectDoctorInventoryItems(function(item)
        return self:itemIsSplint(item)
    end)
    local boards = self:collectDoctorInventoryItems(function(item)
        return self:itemIsSplintBoard(item)
    end)
    local rippedSheets = self:collectDoctorInventoryItems(function(item)
        return self:itemIsRippedSheet(item)
    end)
    if #splints <= 0 and (#boards <= 0 or #rippedSheets <= 0) then return end

    local option = context:addOption(getText("ContextMenu_Splint"), nil)
    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)

    for _, item in ipairs(splints) do
        local subOption = subMenu:addOption(item:getName(), self, self.onRemoteApplySplint, bodyPart, nil, item)
        subOption.itemForTexture = item
    end
    if #rippedSheets > 0 then
        local rippedSheet = rippedSheets[1]
        for _, board in ipairs(boards) do
            local text = board:getName() .. " + " .. rippedSheet:getName()
            local subOption = subMenu:addOption(text, self, self.onRemoteApplySplint, bodyPart, rippedSheet, board)
            subOption.itemForTexture = board
        end
    end
end

function EHR_HealthPanelUI:openRemoteBodyPartContextMenu(bodyPart, x, y, bodyPartType)
    healthPanelDisinfectDebug(string.format("openRemoteBodyPartContextMenu remote=%s bodyPart=%s bodyPartType=%s",
        tostring(self.isRemoteHealthPanel), tostring(bodyPart), tostring(bodyPartType)))
    if not self.isRemoteHealthPanel then return false end
    local snapshot = self:getRemoteBodyPartSnapshotByType(bodyPartType) or self:getRemoteBodyPartSnapshot(bodyPart)
    healthPanelDisinfectDebug(string.format("openRemoteBodyPartContextMenu snapshot=%s actionable=%s",
        tostring(snapshot), tostring(snapshotHasActionableStatus(snapshot))))
    if not snapshotHasActionableStatus(snapshot) then return false end

    -- Do not resolve the live remote BodyDamage stream while merely opening a
    -- context menu. On B42 that stream may briefly appear as a full-health
    -- snapshot and can overwrite the examined player's vitals. Action handlers
    -- resolve the real body part only after the player chooses an action.
    local contextBodyPart = bodyPart
    if not contextBodyPart then return false end

    local playerNum = self.playerNum or (self.remoteDoctor and self.remoteDoctor.getPlayerNum and self.remoteDoctor:getPlayerNum()) or 0
    local context = ISContextMenu.get(playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
    context.origin = self.bodyPartPanel or self

    self:addRemotePoulticeOptions(context, contextBodyPart, snapshot)
    self:addRemoteBandageOptions(context, contextBodyPart, snapshot)
    self:addRemoteDisinfectOptions(context, contextBodyPart, snapshot)
    self:addRemoteGlassOptions(context, contextBodyPart, snapshot)
    self:addRemoteStitchOptions(context, contextBodyPart, snapshot)
    self:addRemoteSplintOptions(context, contextBodyPart, snapshot)
    self:addRemoteBulletOptions(context, contextBodyPart, snapshot)
    self:addRemoteCleanBurnOptions(context, contextBodyPart, snapshot)

    if context:isEmpty() then
        context:setVisible(false)
    elseif JoypadState and JoypadState.players and JoypadState.players[playerNum + 1] then
        if setJoypadFocus then
            setJoypadFocus(playerNum, context)
        elseif updateJoypadFocus then
            JoypadState.players[playerNum + 1].focus = context
            updateJoypadFocus(JoypadState.players[playerNum + 1])
        end
    end
    return true
end

function EHR_HealthPanelUI:onRemoteApplyBandage(bodyPart, item)
    if not ISApplyBandage or not item then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local itemRef = self:getMedicalItemRef(item)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        local bandage = panel:findDoctorInventoryItem(itemRef, function(candidate)
            return panel:itemIsBandage(candidate)
        end)
        if not actionBodyPart or not bandage then return end
        local action = ISApplyBandage:new(panel.remoteDoctor, panel.remotePatient or panel.player, bandage, actionBodyPart, true)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, item)
end

function EHR_HealthPanelUI:onRemoteApplyBandagePack(bodyPart, item)
    if not EHR or not EHR.BandagePack or not item or not EHR.BandagePack.ApplyPackBandageForPlayer then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local actionBodyPart = self:getBodyPartForActionType(bodyPart, bodyPartType) or bodyPart
    local doctor = self.remoteDoctor or self.player
    local patient = self.remotePatient or self.player
    if EHR.BandagePack.ApplyPackBandageForPlayer(doctor, patient, item, actionBodyPart) then
        if self.markRemoteBodyDamageDirty then self:markRemoteBodyDamageDirty(120) end
        if self.requestRemoteRefresh then pcall(function() self:requestRemoteRefresh() end) end
    end
end

function EHR_HealthPanelUI:onRemoteRemoveBandage(bodyPart)
    if not ISApplyBandage then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        if not actionBodyPart then return end
        local action = ISApplyBandage:new(panel.remoteDoctor, panel.remotePatient or panel.player, nil, actionBodyPart, false)
        if action then
            action.wasBandaged = true
        end
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart)
end

function EHR_HealthPanelUI:onRemoteApplyStitch(bodyPart, stitchItem, carriedNeedle)
    if not ISStitch or not stitchItem then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local stitchRef = self:getMedicalItemRef(stitchItem)
    local needleRef = self:getMedicalItemRef(carriedNeedle)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        local stitch = panel:findDoctorInventoryItem(stitchRef, function(candidate)
            if not candidate or not candidate.getType then return false end
            local itemType = candidate:getType()
            return itemType == "Thread" or itemType == "SutureNeedle"
                    or (candidate.hasTag and ItemTag and ResourceLocation and candidate:hasTag(ItemTag.get(ResourceLocation.of("Thread"))))
        end)
        if needleRef and not panel:findDoctorInventoryItem(needleRef, function(candidate)
            if not candidate or not candidate.getType then return false end
            local itemType = candidate:getType()
            return itemType == "Needle"
                    or (candidate.hasTag and ItemTag and ResourceLocation and candidate:hasTag(ItemTag.get(ResourceLocation.of("SewingNeedle"))))
        end) then
            return
        end
        if not actionBodyPart or not stitch then return end
        if EHR.StitchMinigame and EHR.StitchMinigame.AllowRemoteBodyPart then
            EHR.StitchMinigame.AllowRemoteBodyPart(actionBodyPart)
        end
        local action = ISStitch:new(panel.remoteDoctor, panel.remotePatient or panel.player, stitch, actionBodyPart, true)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, stitchItem, carriedNeedle)
end

function EHR_HealthPanelUI:onRemoteRemoveStitch(bodyPart)
    if not ISStitch then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        if not actionBodyPart then return end
        local action = ISStitch:new(panel.remoteDoctor, panel.remotePatient or panel.player, nil, actionBodyPart, false)
        if action then
            action.isValid = function(actionSelf)
                if ISHealthPanel and ISHealthPanel.DidPatientMove
                        and ISHealthPanel.DidPatientMove(actionSelf.character, actionSelf.otherPlayer, actionSelf.bandagedPlayerX, actionSelf.bandagedPlayerY) then
                    return false
                end
                return true
            end
        end
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart)
end

function EHR_HealthPanelUI:onRemoteApplyPoultice(bodyPart, item, actionClass)
    if not item or not actionClass then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local itemRef = self:getMedicalItemRef(item)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        local poultice = panel:findDoctorInventoryItem(itemRef, function(candidate)
            return candidate and candidate.getType and candidate:getType() == itemRef.type
        end)
        if not actionBodyPart or not poultice then return end
        local action = actionClass:new(panel.remoteDoctor, panel.remotePatient or panel.player, poultice, actionBodyPart)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, item)
end

function EHR_HealthPanelUI:onRemoteDisinfect(bodyPart, item)
    healthPanelDisinfectDebug(string.format("onRemoteDisinfect clicked ISDisinfect=%s bodyPart=%s item=%s",
        tostring(ISDisinfect ~= nil), tostring(bodyPart), debugItemName(item)))
    if not ISDisinfect or not item then
        healthPanelDisinfectDebug("onRemoteDisinfect skipped missing ISDisinfect/item")
        return
    end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local itemRef = self:getMedicalItemRef(item)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        healthPanelDisinfectDebug(string.format("onRemoteDisinfect factory bodyPartType=%s actionBodyPart=%s previous=%s",
            tostring(bodyPartType), tostring(actionBodyPart), tostring(previousAction)))
        local disinfectant = panel:findDoctorInventoryItem(itemRef, function(candidate)
            return panel:itemIsDisinfectant(candidate)
        end)
        healthPanelDisinfectDebug("onRemoteDisinfect factory disinfectant=" .. debugItemName(disinfectant))
        if not actionBodyPart or not disinfectant then
            healthPanelDisinfectDebug("onRemoteDisinfect factory skipped missing actionBodyPart/disinfectant")
            return
        end
        local action = ISDisinfect:new(panel.remoteDoctor, panel.remotePatient or panel.player, disinfectant, actionBodyPart)
        healthPanelDisinfectDebug("onRemoteDisinfect factory created action=" .. tostring(action))
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, item)
end

function EHR_HealthPanelUI:onRemoteCleanBurn(bodyPart, item)
    if not ISCleanBurn or not item then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local itemRef = self:getMedicalItemRef(item)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        local cleaner = panel:findDoctorInventoryItem(itemRef, function(candidate)
            return panel:itemIsBurnCleaner(candidate)
        end)
        if not actionBodyPart or not cleaner then return end
        local action = ISCleanBurn:new(panel.remoteDoctor, panel.remotePatient or panel.player, cleaner, actionBodyPart)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, item)
end

function EHR_HealthPanelUI:onRemoteRemoveBullet(bodyPart, item)
    if not ISRemoveBullet or not item then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local itemRef = self:getMedicalItemRef(item)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        local tool = panel:findDoctorInventoryItem(itemRef, function(candidate)
            return panel:itemIsRemoveBulletTool(candidate)
        end)
        if not actionBodyPart or not tool then return end
        local action = ISRemoveBullet:new(panel.remoteDoctor, panel.remotePatient or panel.player, actionBodyPart)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, item)
end

function EHR_HealthPanelUI:onRemoteApplySplint(bodyPart, rippedSheet, boardOrSplint)
    if not ISSplint or not boardOrSplint then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local rippedRef = self:getMedicalItemRef(rippedSheet)
    local boardRef = self:getMedicalItemRef(boardOrSplint)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        if not actionBodyPart then return end

        local action = nil
        if rippedRef then
            local sheet = panel:findDoctorInventoryItem(rippedRef, function(candidate)
                return panel:itemIsRippedSheet(candidate)
            end)
            local board = panel:findDoctorInventoryItem(boardRef, function(candidate)
                return panel:itemIsSplintBoard(candidate)
            end)
            if not sheet or not board then return end
            action = ISSplint:new(panel.remoteDoctor, panel.remotePatient or panel.player, sheet, board, actionBodyPart, true)
        else
            local splint = panel:findDoctorInventoryItem(boardRef, function(candidate)
                return panel:itemIsSplint(candidate)
            end)
            if not splint then return end
            action = ISSplint:new(panel.remoteDoctor, panel.remotePatient or panel.player, nil, splint, actionBodyPart, true)
        end

        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, rippedSheet, boardOrSplint)
end

function EHR_HealthPanelUI:onRemoteRemoveSplint(bodyPart)
    if not ISSplint then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        if not actionBodyPart then return end
        local action = ISSplint:new(panel.remoteDoctor, panel.remotePatient or panel.player, nil, nil, actionBodyPart, false)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart)
end

function EHR_HealthPanelUI:onRemoteRemoveGlass(bodyPart, item)
    if not ISRemoveGlass then return end
    local bodyPartType = callBodyPartMethod(bodyPart, "getType", nil)
    local useHands = item == nil or item == "Hands"
    local itemRef = useHands and nil or self:getMedicalItemRef(item)
    self:queueRemoteMedicalAction(function(panel, previousAction)
        local actionBodyPart = panel:getBodyPartForActionType(bodyPart, bodyPartType)
        if not actionBodyPart then return end
        if itemRef and not panel:findDoctorInventoryItem(itemRef, function(candidate)
            return panel:itemIsRemoveGlassTool(candidate)
        end) then
            return
        end
        local action = ISRemoveGlass:new(panel.remoteDoctor, panel.remotePatient or panel.player, actionBodyPart, useHands)
        panel:queueActualMedicalAction(previousAction, action, actionBodyPart)
    end, bodyPart, useHands and nil or item)
end

function EHR_HealthPanelUI:queueRemoteBodyContextRetry(bodyPartType, x, y)
    if not self.isRemoteHealthPanel or not Events or not Events.OnTick or not bodyPartType then
        return false
    end

    self:clearRemoteBodyContextRetry()

    local panel = self
    local attemptsLeft = 12

    local function retryContextMenu()
        if not panel or not panel.getIsVisible or not panel:getIsVisible() then
            if panel and panel.clearRemoteBodyContextRetry then
                panel:clearRemoteBodyContextRetry()
            else
                Events.OnTick.Remove(retryContextMenu)
            end
            return
        end

        attemptsLeft = attemptsLeft - 1
        panel:beginRemoteBodyDamageAccess(360)
        panel:syncBodyPartPanelBodyParts()

        local actionBodyPart = panel:resolveBodyPartForAction(nil, bodyPartType)
        if bodyPartHasActionableStatus(actionBodyPart) then
            panel:clearRemoteBodyContextRetry()
            panel:openBodyPartContextMenu(actionBodyPart, x, y, bodyPartType)
            return
        end

        if attemptsLeft <= 0 then
            panel:clearRemoteBodyContextRetry()
        end
    end

    self.remoteBodyContextRetry = retryContextMenu
    Events.OnTick.Add(retryContextMenu)
    return true
end

function EHR_HealthPanelUI:getCleanBandagePackOptionText()
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_BandagePack_ApplyFromPack", "Apply Clean Bandage from Pack")
    end
    return "Apply Clean Bandage from Pack"
end

function EHR_HealthPanelUI:addLocalBandagePackOptions(context, bodyPart)
    return false
end

function EHR_HealthPanelUI:onLocalApplyBandagePack(bodyPart, pack)
    return false
end
function EHR_HealthPanelUI:openBodyPartContextMenu(bodyPart, x, y, bodyPartType)
    healthPanelDisinfectDebug(string.format("openBodyPartContextMenu remote=%s bodyPart=%s bodyPartType=%s x=%s y=%s",
        tostring(self.isRemoteHealthPanel), tostring(bodyPart), tostring(bodyPartType), tostring(x), tostring(y)))
    if not bodyPart or not ISHealthPanel or not ISHealthPanel.doBodyPartContextMenu then return end
    local adapter = self:getVanillaHealthAdapter()
    if not adapter or not adapter.character then return end
    if self.isRemoteHealthPanel then
        if self:openRemoteBodyPartContextMenu(bodyPart, x, y, bodyPartType) then
            return
        end
        -- Remote EHR panels are snapshot-driven. Falling through into vanilla
        -- ISHealthPanel here can request BodyDamageRemote and mutate the patient
        -- toward a default full-health/full-stats state on some MP clients.
        return
    else
        self:ensureRemoteBodyDamageUpdates()
    end

    local actionBodyPart = self:resolveBodyPartForAction(bodyPart, bodyPartType)
    local snapshot = self:getRemoteBodyPartSnapshotByType(bodyPartType) or self:getRemoteBodyPartSnapshot(bodyPart)
    healthPanelDisinfectDebug(string.format("openBodyPartContextMenu resolved actionBodyPart=%s snapshot=%s actionable=%s vanillaActionable=%s",
        tostring(actionBodyPart), tostring(snapshot), tostring(snapshotHasActionableStatus(snapshot)), tostring(bodyPartHasActionableStatus(actionBodyPart))))
    if self.isRemoteHealthPanel
            and snapshotHasActionableStatus(snapshot)
            and not bodyPartHasActionableStatus(actionBodyPart)
            and self:queueRemoteBodyContextRetry(bodyPartType or callBodyPartMethod(bodyPart, "getType", nil), x, y) then
        return
    end

    ISHealthPanel.doBodyPartContextMenu(adapter, actionBodyPart or bodyPart, x, y)
    healthPanelDisinfectDebug("openBodyPartContextMenu delegated to ISHealthPanel.doBodyPartContextMenu")
end

function EHR_HealthPanelUI:dropItemsOnBodyPart(bodyPart, items, bodyPartType)
    if not bodyPart or not items or not ISHealthPanel or not ISHealthPanel.dropItemsOnBodyPart then return end
    local adapter = self:getVanillaHealthAdapter()
    if not adapter or not adapter.character then return end
    if self.isRemoteHealthPanel then
        self:beginRemoteBodyDamageAccess(360)
        self:syncBodyPartPanelBodyParts()
        self:markRemoteBodyDamageDirty(120)
    else
        self:ensureRemoteBodyDamageUpdates()
    end

    local actionBodyPart = self:resolveBodyPartForAction(bodyPart, bodyPartType)
    ISHealthPanel.dropItemsOnBodyPart(adapter, actionBodyPart or bodyPart, items)
end

function EHR_HealthPanelUI:getBodyPartStatuses(bodyPart)
    local c = EHR_HealthPanelUI.Colors
    local statuses = {}
    local seen = {}
    local snapshot = self:getRemoteBodyPartSnapshot(bodyPart)

    local function bodyValue(snapshotKey, methodName, fallback)
        if type(snapshot) == "table" and snapshot[snapshotKey] ~= nil then
            return snapshot[snapshotKey]
        end
        return callBodyPartMethod(bodyPart, methodName, fallback)
    end

    local function add(key, label, color, visualValue, priority)
        if not key or seen[key] then return end
        seen[key] = true
        table.insert(statuses, {
            key = key,
            label = label,
            color = color or c.textDim,
            visualValue = visualValue,
            priority = priority or 0,
        })
    end

    if not bodyPart then return statuses end

    local health = tonumber(bodyValue("health", "getHealth", 100)) or 100
    local bandaged = bodyValue("bandaged", "bandaged", false) == true
    local bandageLife = tonumber(bodyValue("bandageLife", "getBandageLife", 1)) or 1
    local infected = bodyValue("infected", "isInfectedWound", false) == true
    local infectionLevel = tonumber(bodyValue("infectionLevel", "getWoundInfectionLevel", 0)) or 0
    local infectionLevelThreshold = 0.05
    if EHR and EHR.WoundInfection and EHR.WoundInfection.VANILLA_INFECTION_LEVEL_EPSILON then
        infectionLevelThreshold = EHR.WoundInfection.VANILLA_INFECTION_LEVEL_EPSILON
    end
    local additionalPain = tonumber(bodyValue("additionalPain", "getAdditionalPain", 0)) or 0
    local stiffness = tonumber(bodyValue("stiffness", "getStiffness", 0)) or 0
    local hasInjury = bodyValue("hasInjury", "HasInjury", false) == true
    local hasLocalizedDamage = hasInjury
    local ehrWoundPartData = nil

    if self.isRemoteHealthPanel and self.remoteExamData and self.remoteExamData.EHR_WoundInfection then
        local data = self.remoteExamData.EHR_WoundInfection
        local partName = tostring(callBodyPartMethod(bodyPart, "getType", ""))
        ehrWoundPartData = data and data.parts and data.parts[partName] or nil
    elseif self.player and EHR.WoundInfection and EHR.WoundInfection.GetData then
        local data = EHR.WoundInfection.GetData(self.player)
        local partName = tostring(callBodyPartMethod(bodyPart, "getType", ""))
        ehrWoundPartData = data and data.parts and data.parts[partName] or nil
    end

    if bodyValue("bleeding", "bleeding", false) == true then
        hasLocalizedDamage = true
        add("bleeding", safeText("UI_EHR_BodyLegend_Bleeding", "Bleeding"), c.red, 1.00, 110)
    end

    if infected or infectionLevel > infectionLevelThreshold or (type(ehrWoundPartData) == "table" and (tonumber(ehrWoundPartData.stage) or 0) > 0) then
        hasLocalizedDamage = true
        add("infected", safeText("UI_EHR_BodyLegend_Infected", "Infected"), c.purple, 0.80, 100)
    end

    if (tonumber(bodyValue("fractureTime", "getFractureTime", 0)) or 0) > 0 then
        hasLocalizedDamage = true
        add("fracture", "Fracture", c.red, 1.00, 95)
    end
    if bodyValue("haveBullet", "haveBullet", false) == true then
        hasLocalizedDamage = true
        add("bullet", "Lodged bullet", c.red, 1.00, 94)
    end
    if bodyValue("haveGlass", "haveGlass", false) == true then
        hasLocalizedDamage = true
        add("glass", "Glass shards", c.red, 1.00, 92)
    end
    if (tonumber(bodyValue("burnTime", "getBurnTime", 0)) or 0) > 0 then
        hasLocalizedDamage = true
        local label = bodyValue("needBurnWash", "isNeedBurnWash", false) == true and "Burn needs cleaning" or "Burn"
        add("burn", label, c.orange, 0.60, 88)
    end

    if bodyValue("deepWounded", "deepWounded", false) == true then
        hasLocalizedDamage = true
        add("deep_wound", "Deep wound", c.orange, 0.60, 84)
    end
    if bodyValue("bitten", "bitten", false) == true then
        hasLocalizedDamage = true
        add("bite", "Bite", c.red, 1.00, 82)
    end
    if bodyValue("cut", "isCut", false) == true then
        hasLocalizedDamage = true
        add("cut", "Cut", c.orange, 0.60, 78)
    end
    if bodyValue("scratched", "scratched", false) == true then
        hasLocalizedDamage = true
        add("scratch", "Scratch", c.orange, 0.60, 74)
    end

    if additionalPain > 50 then
        add("pain", "Heavy pain", c.orange, 0.60, 72)
    elseif additionalPain > 10 then
        add("pain", safeText("UI_EHR_Symptom_Pain", "Pain"), c.orange, 0.60, 68)
    elseif additionalPain >= 1 then
        add("pain", "Minor pain", c.orange, 0.60, 42)
    end

    if stiffness >= 20 then
        add("stiffness", "Muscle strain", c.orange, 0.60, 70)
    elseif stiffness >= 5 then
        add("stiffness", "Minor stiffness", c.yellow, 0.40, 45)
    elseif stiffness >= 1 then
        add("stiffness", "Slight stiffness", c.yellow, 0.40, 38)
    end

    if bandaged then
        hasLocalizedDamage = true
        if bandageLife <= 0 then
            add("dirty_bandage", safeText("UI_EHR_BodyLegend_DirtyBandage", "Dirty bandage"), c.yellow, 0.40, 89)
        else
            add("bandaged", safeText("UI_EHR_BodyLegend_Bandaged", "Bandaged"), c.green, 0.20, 89)
        end
    end
    if bodyValue("stitched", "stitched", false) == true then
        hasLocalizedDamage = true
        add("stitched", "Stitched", c.green, 0.20, 32)
    end
    if (tonumber(bodyValue("splintFactor", "getSplintFactor", 0)) or 0) > 0 then
        hasLocalizedDamage = true
        add("splinted", "Splinted", c.green, 0.20, 30)
    end
    if (tonumber(bodyValue("plantainFactor", "getPlantainFactor", 0)) or 0) > 0 then
        add("plantain", "Plantain poultice", c.green, 0.20, 26)
    end
    if (tonumber(bodyValue("comfreyFactor", "getComfreyFactor", 0)) or 0) > 0 then
        add("comfrey", "Comfrey poultice", c.green, 0.20, 26)
    end

    if hasLocalizedDamage and health < 45 then
        add("damaged", "Severe damage", c.red, 1.00, 86)
    elseif hasLocalizedDamage and health < 85 then
        local color = health < 45 and c.red or c.orange
        local visualValue = health < 45 and 1.00 or 0.60
        add("damaged", "Damaged", color, visualValue, 40)
    end

    if hasInjury and #statuses == 0 then
        add("injury", "Injury", c.orange, 0.60, 46)
    end

    table.sort(statuses, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    if self.isRemoteHealthPanel then
        local partKey = getBodyPartCacheKey(bodyPart)
        local dirtyTicks = tonumber(self.remoteBodyDamageRefreshTicks) or 0
        self.remoteBodyPartStatusCache = self.remoteBodyPartStatusCache or {}

        if #statuses == 0 and dirtyTicks > 0 then
            local cached = self.remoteBodyPartStatusCache[partKey]
            if cached and cached.statuses and #cached.statuses > 0 then
                return copyBodyPartStatuses(cached.statuses)
            end
        end

        if #statuses > 0 or dirtyTicks <= 0 then
            self.remoteBodyPartStatusCache[partKey] = {
                statuses = copyBodyPartStatuses(statuses),
            }
        end
    end

    return statuses
end

function EHR_HealthPanelUI:getBodyPartVisualValue(bodyPart)
    local statuses = self:getBodyPartStatuses(bodyPart)

    if #statuses > 0 and statuses[1].visualValue then
        return clamp(statuses[1].visualValue, 0, 1)
    end

    -- BodyPart:getHealth() can mirror low overall health from systemic illness,
    -- so the silhouette should only tint for explicit local body-part statuses.
    return 0
end

function EHR_HealthPanelUI:updateVanillaBodyPartPanel()
    if not self.bodyPartPanel or not self.player then return end

    self:syncBodyPartPanelBodyParts()

    local bodyDamage = self:getPatientBodyDamage()
    if not bodyDamage or not bodyDamage.getBodyParts then return end

    local bodyParts = bodyDamage:getBodyParts()
    if not bodyParts then return end

    for i = 0, bodyParts:size() - 1 do
        local bodyPart = bodyParts:get(i)
        if bodyPart and bodyPart.getType then
            self.bodyPartPanel:setValue(bodyPart:getType(), self:getBodyPartVisualValue(bodyPart))
        end
    end
end

function EHR_HealthPanelUI:getSelectedBodyPartText()
    if self.bodyPartPanel and self.bodyPartPanel.selectedBp and self.bodyPartPanel.selectedBp.bodyPart then
        local bodyPart = self.bodyPartPanel.selectedBp.bodyPart
        if BodyPartType and BodyPartType.getDisplayName then
            return BodyPartType.getDisplayName(bodyPart:getType())
        end
        return tostring(bodyPart:getType())
    end
    return "None"
end

function EHR_HealthPanelUI:getSelectedBodyPartStatuses()
    if not self.bodyPartPanel or not self.bodyPartPanel.selectedBp or not self.bodyPartPanel.selectedBp.bodyPart then
        return {}
    end

    return self:getBodyPartStatuses(self.bodyPartPanel.selectedBp.bodyPart)
end

function EHR_HealthPanelUI:getSelectedBodyPartStatus()
    local statuses = self:getSelectedBodyPartStatuses()
    if statuses and statuses[1] then
        return statuses[1].label, statuses[1].color
    end
    return nil
end

function EHR_HealthPanelUI:getOverallHealthPercent()
    if not self.player or not self.player.getBodyDamage then
        return 100
    end

    if self.isRemoteHealthPanel and type(self.remoteExamData) == "table" then
        local bodyStatus = self.remoteExamData.EHR_BodyStatus
        local snapshotHealth = bodyStatus and (bodyStatus.overallHealth or bodyStatus.health or bodyStatus.bodyHealth)
        snapshotHealth = tonumber(snapshotHealth)
        if snapshotHealth then
            if snapshotHealth <= 1 then snapshotHealth = snapshotHealth * 100 end
            return clamp(snapshotHealth, 0, 100)
        end

        local parts = bodyStatus and bodyStatus.parts
        if type(parts) == "table" then
            local total = 0
            local count = 0
            for _, snapshot in pairs(parts) do
                if type(snapshot) == "table" and snapshot.health ~= nil then
                    total = total + clamp(tonumber(snapshot.health) or 100, 0, 100)
                    count = count + 1
                end
            end
            if count > 0 then
                return clamp(total / count, 0, 100)
            end
        end
    end

    local bodyDamage = self:getPatientBodyDamage()
    if not bodyDamage then return 100 end

    local directMethods = {
        "getOverallBodyHealth",
        "getOverallHealth",
    }

    for _, methodName in ipairs(directMethods) do
        local method = bodyDamage[methodName]
        if method then
            local ok, value = pcall(function()
                return method(bodyDamage)
            end)
            value = ok and tonumber(value) or nil
            if value then
                if value <= 1 then value = value * 100 end
                return clamp(value, 0, 100)
            end
        end
    end

    if not bodyDamage.getBodyParts then
        return 100
    end

    local bodyParts = bodyDamage:getBodyParts()
    if not bodyParts or not bodyParts.size then
        return 100
    end

    local total = 0
    local count = 0
    for i = 0, bodyParts:size() - 1 do
        local bodyPart = bodyParts:get(i)
        if bodyPart and bodyPart.getHealth then
            total = total + clamp(tonumber(bodyPart:getHealth()) or 100, 0, 100)
            count = count + 1
        end
    end

    if count <= 0 then
        return 100
    end
    return clamp(total / count, 0, 100)
end

function EHR_HealthPanelUI:getOverallHealthColor(percent)
    local c = EHR_HealthPanelUI.Colors
    percent = tonumber(percent) or 100
    if percent >= 80 then
        return c.green
    end
    if percent >= 50 then
        return c.yellow
    end
    return c.red
end

function EHR_HealthPanelUI:drawOverallHealthBar(x, y, w)
    local c = EHR_HealthPanelUI.Colors
    local percent = self:getOverallHealthPercent()
    local fillColor = self:getOverallHealthColor(percent)
    local barH = 28
    local fillW = math.floor(w * clamp(percent / 100, 0, 1))

    self:drawRect(x, y, w, barH, 0.90, 0.035, 0.030, 0.030)
    if fillW > 0 then
        self:drawRect(x, y, fillW, barH, fillColor.a, fillColor.r, fillColor.g, fillColor.b)
        self:drawRect(x, y, fillW, 4, 0.22, 1.0, 0.86, 0.72)
    end
    self:drawRectBorder(x, y, w, barH, 0.82, c.border.r, c.border.g, c.border.b)
    self:drawDockedTextRight(string.format("%d%%", math.floor(percent + 0.5)), x + w - 8, y, barH, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium, -1)
end

function EHR_HealthPanelUI:drawBodyLegend(x, y, w)
    local c = EHR_HealthPanelUI.Colors
    local items = {
        { label = safeText("UI_EHR_BodyLegend_Bandaged", "Bandaged"), color = c.green },
        { label = safeText("UI_EHR_BodyLegend_DirtyBandage", "Dirty bandage"), color = c.yellow },
        { label = safeText("UI_EHR_BodyLegend_PainWound", "Pain / wound"), color = c.orange },
        { label = safeText("UI_EHR_BodyLegend_Infected", "Infected"), color = c.purple },
        { label = safeText("UI_EHR_BodyLegend_Bleeding", "Bleeding"), color = c.red },
    }

    local rowH = 20
    local textLift = 9
    w = w or 146
    local h = #items * rowH + 10
    self:drawRect(x, y, w, h, 0.56, 0.025, 0.025, 0.028)
    self:drawRectBorder(x, y, w, h, 0.62, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    for i, item in ipairs(items) do
        local rowY = y + 5 + (i - 1) * rowH
        self:drawRect(x + 8, rowY + 5, 8, 8, item.color.a, item.color.r, item.color.g, item.color.b)
        self:drawText(self:truncateText(item.label, w - 30, UIFont.Small), x + 22, rowY - textLift, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    end

    return h
end

function EHR_HealthPanelUI:drawSelectedBodyPartDetails(x, y, w, h, partName, statuses)
    local c = EHR_HealthPanelUI.Colors
    if h < 48 then return end

    statuses = statuses or {}
    local font = self:getCompactFont()
    local rowH = 20
    local textLift = 9
    local title = partName and partName ~= "None" and partName or "No part selected"

    self:drawRect(x, y, w, h, 0.56, 0.025, 0.025, 0.028)
    self:drawRectBorder(x, y, w, h, 0.62, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    local titleY = (partName == nil or partName == "None") and y or (y - 5)
    self:drawDockedText(self:truncateText(title, w - 16, font), x + 8, titleY, w - 16, 22, c.green.r, c.green.g, c.green.b, c.green.a, font, -1)
    self:drawRect(x + 8, y + 22, w - 16, 1, 0.45, c.border.r, c.border.g, c.border.b)

    local rowY = y + 33
    if #statuses == 0 then
        local text = partName == "None" and "Hover a body part" or "No active issues"
        self:drawText(self:truncateText(text, w - 16, font), x + 8, rowY - textLift, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, font)
        return
    end

    local drawn = 0
    for i, status in ipairs(statuses) do
        if rowY + rowH > y + h - 4 then
            local remaining = #statuses - drawn
            if remaining > 0 then
                local more = "+" .. tostring(remaining) .. " more"
                self:drawText(more, x + 8, rowY - 1, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, font)
            end
            break
        end

        local color = status.color or c.textDim
        self:drawRect(x + 8, rowY + 4, 8, 8, color.a, color.r, color.g, color.b)
        self:drawText(self:truncateText(status.label or "Status", w - 30, font), x + 22, rowY - textLift, color.r, color.g, color.b, color.a, font)
        rowY = rowY + rowH
        drawn = drawn + 1
    end
end

function EHR_HealthPanelUI:drawVanillaBodyPanelFrame(x, y, w, h)
    local c = EHR_HealthPanelUI.Colors
    self.markerBounds = {}

    self:drawPanelFrame(x, y, w, h, "BODY STATUS", "body_status")
    self:drawOverallHealthBar(x + 16, y + 50, w - 32)
    self:drawSubtleGrid(x + 12, y + 90, w - 24, math.max(40, h - 126), 22)

    local bodyPartPanel = self:ensureBodyPartPanel()
    if bodyPartPanel then
        self.bodyPartPanel:setVisible(true)
        local legendVisible = w >= 320 and h >= 260
        local bodyX = x + math.floor((w - self.bodyPartPanel.width) / 2)
        if legendVisible then
            bodyX = x + 24
        end
        self.bodyPartPanel:setX(bodyX)
        self.bodyPartPanel:setY(y + 88)
        self:updateVanillaBodyPartPanel()
        if legendVisible then
            local sideX = bodyX + self.bodyPartPanel.width + 30
            local sideW = x + w - sideX - 14
            if sideW < 146 then
                sideW = 146
                sideX = x + w - sideW - 14
                bodyX = math.max(x + 14, sideX - self.bodyPartPanel.width - 24)
                self.bodyPartPanel:setX(bodyX)
            end
            local legendH = self:drawBodyLegend(sideX, y + 108, sideW)
            local detailsY = y + 108 + legendH + 8
            local detailsH = y + h - 44 - detailsY
            if detailsH >= 48 then
                self:drawSelectedBodyPartDetails(sideX, detailsY, sideW, detailsH, self:getSelectedBodyPartText(), self:getSelectedBodyPartStatuses())
            end
        end
    else
        self:drawText("Body panel unavailable", x + 10, y + 90, c.orange.r, c.orange.g, c.orange.b, c.orange.a, UIFont.Small)
    end

    local selectedText = "Selected: " .. self:getSelectedBodyPartText()
    local statuses = self:getSelectedBodyPartStatuses()
    local statusColor = c.green
    if statuses and statuses[1] then
        statusColor = statuses[1].color or statusColor
        if w < 320 then
            local compactStatuses = {}
            for i, status in ipairs(statuses) do
                if i > 3 then break end
                table.insert(compactStatuses, status.label)
            end
            if #compactStatuses > 0 then
                selectedText = selectedText .. " - " .. table.concat(compactStatuses, ", ")
            end
        end
    end
    local selectedFont = self:getCompactFont()
    local selectedW = math.max(60, w - 22)
    selectedText = self:truncateText(selectedText, selectedW, selectedFont)
    self:drawDockedText(selectedText, x + 10, y + h - 30, selectedW, 22, statusColor.r, statusColor.g, statusColor.b, statusColor.a, selectedFont, -1)
end

function EHR_HealthPanelUI:drawLeftPanel()
    local c = EHR_HealthPanelUI.Colors
    local layout = self:getEHRLayout()
    local x = layout.leftX
    local y = layout.leftY
    local w = layout.leftW
    local h = layout.leftH
    local summary = self:getBloodSummary()

    self:drawPanelFrame(x, y, w, h, nil, nil)

    local overviewH = 112
    self:drawPanelFrame(x + 10, y + 10, w - 20, overviewH, "OVERVIEW", "overview")

    local healingText = "Healing: Active"
    local healingColor = c.green
    if summary.canHeal == false then
        healingText = "Healing: Slowed"
        healingColor = c.orange
    end
    self:drawText(healingText, x + 22, y + 53, healingColor.r, healingColor.g, healingColor.b, healingColor.a, UIFont.Medium)

    if summary.healBlockReason and summary.canHeal == false then
        self:drawText("Reason: " .. tostring(summary.healBlockReason), x + 22, y + 84, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    end

    local bodyY = y + overviewH + 12
    self:drawVanillaBodyPanelFrame(x + 10, bodyY, w - 20, math.max(180, y + h - bodyY - 10))
end

function EHR_HealthPanelUI:getTreatmentName(treatment)
    if type(treatment) ~= "table" then return "Treatment" end
    return treatment.medicationName or treatment.medKey or "Treatment"
end

function EHR_HealthPanelUI:getMedicationIconCandidates(treatment)
    local candidates = {}
    local seen = {}

    local function addCandidate(value)
        value = tostring(value or "")
        if value == "" then return end
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        if value == "" or seen[value] then return end
        seen[value] = true
        table.insert(candidates, value)
    end

    if type(treatment) == "table" then
        local medKey = tostring(treatment.medKey or "")
        local medData = EHR.Medication and EHR.Medication.Database and EHR.Medication.Database[medKey] or nil
        if type(medData) == "table" then
            addCandidate(medData.icon)
            addCandidate(medData.itemType)
            addCandidate(medData.item)
        end

        local shortKey = medKey:match("%.([^%.]+)$") or medKey
        addCandidate(shortKey)

        local name = tostring(treatment.medicationName or "")
        name = name:gsub("%b()", "")
        name = name:gsub("[^%w]+", "")
        addCandidate(name)
    end

    return candidates
end

function EHR_HealthPanelUI:getMedicationIconTexture(treatment)
    if not getTexture then return nil end

    self.medicationIconTextures = self.medicationIconTextures or {}
    for _, candidate in ipairs(self:getMedicationIconCandidates(treatment)) do
        local path = "media/textures/Item_" .. candidate .. ".png"
        if self.medicationIconTextures[path] == nil then
            self.medicationIconTextures[path] = getTexture(path) or false
        end
        if self.medicationIconTextures[path] then
            return self.medicationIconTextures[path]
        end
    end

    return nil
end

function EHR_HealthPanelUI:drawMedicationIcon(treatment, x, y, size)
    local c = EHR_HealthPanelUI.Colors
    local texture = self:getMedicationIconTexture(treatment)
    if texture and self.drawTextureScaled then
        self:drawTextureScaled(texture, x, y, size, size, 1.0, 1.0, 1.0, 1.0)
        return
    end
    self:drawRoundIcon(x, y, size, c.panel, c.borderDim, "+", c.textDim)
end

function EHR_HealthPanelUI:buildActiveMedicationList(treatments, doseStatuses)
    local displayed = {}
    local seen = {}

    for keyFromMap, treatment in pairs(treatments or {}) do
        if type(treatment) == "table" then
            treatment.diseaseId = treatment.diseaseId or tostring(keyFromMap)
            local key = treatment.medKey or treatment.medicationName
            if key then seen[key] = true end
            treatment.isTreatingDisease = true
            table.insert(displayed, treatment)
        end
    end

    for keyFromMap, doseStatus in pairs(doseStatuses or {}) do
        if type(doseStatus) == "table" then
            doseStatus.medKey = doseStatus.medKey or tostring(keyFromMap)
            local key = doseStatus.medKey or doseStatus.medicationName
            if key and not seen[key] and (doseStatus.isDoseActive or doseStatus.isOverdue or not doseStatus.treatmentComplete) then
                table.insert(displayed, {
                    medicationName = doseStatus.medicationName,
                    medKey = doseStatus.medKey,
                    tier = doseStatus.tier,
                    hoursRemaining = 0,
                    progress = (tonumber(doseStatus.totalDosesNeeded) or 0) > 0
                        and clamp((tonumber(doseStatus.doseCount) or 0) / (tonumber(doseStatus.totalDosesNeeded) or 1), 0, 1)
                        or 0,
                    doseCount = doseStatus.doseCount,
                    totalDosesNeeded = doseStatus.totalDosesNeeded,
                    dosesRemaining = doseStatus.dosesRemaining,
                    hoursUntilNextDose = doseStatus.hoursUntilNextDose,
                    isDoseActive = doseStatus.isDoseActive,
                    hoursActiveRemaining = doseStatus.hoursActiveRemaining,
                    isOverdue = doseStatus.isOverdue,
                    hoursOverdue = doseStatus.hoursOverdue,
                    courseComplete = doseStatus.treatmentComplete,
                    isTreatingDisease = false,
                })
                seen[key] = true
            end
        end
    end

    return displayed
end

function EHR_HealthPanelUI:addKnoxCureMedicationEntries(activeMedications, activeSideEffects)
    if not self.player or not EHR.KnoxCure or not EHR.KnoxCure.IsImmunoboosterActive then return end
    if not EHR.KnoxCure.IsImmunoboosterActive(self.player) then return end

    local remaining = 0
    if EHR.KnoxCure.GetImmunoboosterRemaining then
        remaining = tonumber(EHR.KnoxCure.GetImmunoboosterRemaining(self.player)) or 0
    end
    if remaining <= 0 then return end

    local duration = 24
    if EHR.KnoxCure.Config and tonumber(EHR.KnoxCure.Config.immunoboosterDuration) then
        duration = tonumber(EHR.KnoxCure.Config.immunoboosterDuration)
    end

    table.insert(activeMedications, {
        medicationName = "Immunobooster Shot",
        medKey = "ImmunoboosterShot",
        icon = "ImmunoboosterShot",
        isTreatingDisease = false,
        effectLabel = safeText("UI_EHR_ProtectionLabel", "Protection:"),
        hoursActiveRemaining = remaining,
        progress = clamp(remaining / math.max(1, duration), 0, 1),
    })

    table.insert(activeSideEffects, {
        effectId = "immunobooster_nausea",
        displayName = "Mild nausea",
        severity = 1,
        hoursRemaining = remaining,
    })
    table.insert(activeSideEffects, {
        effectId = "immunobooster_stamina",
        displayName = "Reduced stamina regen",
        severity = 1,
        hoursRemaining = remaining,
    })
end

function EHR_HealthPanelUI:drawDiseaseRow(diseaseId, disease, x, y, w)
    local c = EHR_HealthPanelUI.Colors
    local displayInfo = self:getDiseaseDisplayInfo(diseaseId, disease)
    local name = displayInfo.displayName
    local stage = type(disease) == "table" and (tonumber(disease.stage) or 1) or 1
    local severity = type(disease) == "table" and (tonumber(disease.severity) or 0.5) or 0.5
    local progress = self:getDiseaseProgress(disease)
    local visualProgress = self:getSmoothedDiseaseProgress(diseaseId, disease, progress)
    local treated = self:isDiseaseTreated(diseaseId)
    local status = displayInfo.statusText or (treated and safeText("UI_EHR_Status_Treating", "TREATING") or safeText("UI_EHR_Status_Untreated", "UNTREATED"))
    local statusColor = displayInfo.statusColor or (displayInfo.statusText and c.red or (treated and c.green or c.orange))
    local accent, iconLabel
    if displayInfo.canIdentify then
        accent, iconLabel = self:getDiseaseAccent(diseaseId, displayInfo.realName)
    else
        accent, iconLabel = c.borderDim, "?"
    end
    local rowH = displayInfo.hideProgressBar and 88 or 108

    self:drawRect(x, y, w, rowH, 0.48, c.panelSoft.r, c.panelSoft.g, c.panelSoft.b)
    self:drawWornFrame(x, y, w, rowH, accent, 7)
    self:drawCornerBolts(x, y, w, rowH, accent)
    self:drawRect(x, y, w, 1, 0.72, c.border.r, c.border.g, c.border.b)
    self:drawHazardStripes(x + w - 78, y + 10, 5, accent)
    local iconSize = tonumber(displayInfo.iconSize) or 80
    local iconX = x + 12 + math.floor((80 - iconSize) / 2)
    local iconY = y + math.floor((rowH - iconSize) / 2)
    self:drawDiseaseIcon(iconX, iconY, iconSize, accent, iconLabel, self:getDiseaseIconTexture(diseaseId, displayInfo))

    local textX = iconX + iconSize + 16
    local textOffset = textX - x
    local textW = displayInfo.showTreatmentStatus and (w - textOffset - 127) or (w - textOffset - 18)
    local detailsText = safeText("UI_EHR_SeverityUnknown", "Severity: ???")
    local detailsColor = c.textDim
    if displayInfo.detailText then
        detailsText = displayInfo.detailText
        detailsColor = displayInfo.detailColor or c.red
    elseif type(disease) == "table" and (disease.isCorpseExposure or disease.isExposureCondition) then
        local exposureLevel = tostring(disease.exposureLevel or "Low")
        detailsText = safeText("UI_EHR_ExposurePrefix", "Exposure: ") .. exposureLevel
        if type(disease.exposureColor) == "table" then
            detailsColor = {
                r = tonumber(disease.exposureColor[1]) or accent.r,
                g = tonumber(disease.exposureColor[2]) or accent.g,
                b = tonumber(disease.exposureColor[3]) or accent.b,
                a = 1.0,
            }
        else
            detailsColor = accent
        end
    elseif displayInfo.showStageSeverity then
        detailsText = safeFormat("UI_EHR_StageSeverity", "Stage %d   Severity %.1f/5", stage, severity)
        detailsColor = c.green
    end
    local progressText = displayInfo.progressText
    if progressText == nil then
        progressText = displayInfo.showProgress and string.format("%d%%", math.floor(visualProgress + 0.5)) or "??%"
    end

    self:drawText(self:truncateText(name, textW, UIFont.Medium), textX, y + 16, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
    self:drawText(detailsText, textX, y + 43, detailsColor.r, detailsColor.g, detailsColor.b, detailsColor.a, UIFont.Small)
    if progressText ~= "" then
        self:drawText(progressText, textX, y + 66, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    end
    if displayInfo.showTreatmentStatus then
        self:drawTextRight(status, x + w - 14, y + 40, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Medium)
    end

    if not displayInfo.hideProgressBar then
        local barX = textX
        local barY = y + 99
        local barW = w - textOffset - 14
        local filled = displayInfo.showProgress and math.floor(barW * clamp(visualProgress / 100, 0, 1)) or 0
        self:drawRect(barX, barY, barW, 6, 1, 0.05, 0.05, 0.05)
        if filled > 0 then
            self:drawRect(barX, barY, filled, 6, c.green.a, c.green.r, c.green.g, c.green.b)
        end
        self:drawRectBorder(barX, barY, barW, 6, c.border.a, c.border.r, c.border.g, c.border.b)
    end

    return rowH + 10
end

function EHR_HealthPanelUI:drawTreatmentRow(treatment, x, y, w)
    local c = EHR_HealthPanelUI.Colors
    local name = self:getTreatmentName(treatment)
    local isTreatingDisease = type(treatment) == "table" and treatment.isTreatingDisease ~= false
    local cureRemaining = type(treatment) == "table" and formatHours(treatment.hoursRemaining or 0) or "--"
    local doseText = ""
    local scheduleText = ""
    local scheduleValue = ""
    local scheduleColor = c.textDim
    local totalDoses = 0
    local progress = 0

    if type(treatment) == "table" then
        totalDoses = tonumber(treatment.totalDosesNeeded) or 0
        progress = clamp(tonumber(treatment.progress) or 0, 0, 1)
        if totalDoses > 0 then
            doseText = safeFormat("UI_EHR_DoseCount", "Dose %d/%d", tonumber(treatment.doseCount) or 0, totalDoses)
            if not isTreatingDisease and treatment.isDoseActive then
                scheduleText = safeText("UI_EHR_MedicationActive", "Active")
                scheduleValue = formatShortHours(treatment.hoursActiveRemaining or 0)
                scheduleColor = c.green
            elseif treatment.isOverdue and not treatment.courseComplete then
                scheduleText = safeText("UI_EHR_MedicationOverdue", "OVERDUE")
                scheduleValue = formatShortHours(treatment.hoursOverdue or 0)
                scheduleColor = c.red
            elseif treatment.courseComplete then
                scheduleText = safeText("UI_EHR_CourseComplete", "Course complete")
                scheduleColor = c.green
            elseif (tonumber(treatment.hoursUntilNextDose) or 0) <= 0.5 then
                scheduleText = safeText("UI_EHR_NextDoseIn", "Next dose in")
                scheduleValue = formatShortHours(treatment.hoursUntilNextDose or 0)
                scheduleColor = c.yellow
            else
                scheduleText = safeText("UI_EHR_NextDoseIn", "Next dose in")
                scheduleValue = formatShortHours(treatment.hoursUntilNextDose or 0)
            end
        end
    end

    local activeRemaining = type(treatment) == "table" and tonumber(treatment.hoursActiveRemaining) or nil
    local activeValue = activeRemaining and activeRemaining > 0 and formatShortHours(activeRemaining) or ""
    local rowH = doseText ~= "" and 78 or 58
    self:drawRect(x, y, w, rowH, 0.32, c.panelSoft.r, c.panelSoft.g, c.panelSoft.b)
    self:drawWornFrame(x, y, w, rowH, c.borderDim, 4)

    local iconSize = 34
    local iconX = x + 10
    local iconY = y + math.floor((rowH - iconSize) / 2)
    self:drawMedicationIcon(treatment, iconX, iconY, iconSize)

    local textX = iconX + iconSize + 9
    self:drawText(self:truncateText(name, w - 236, UIFont.Small), textX, y + 7, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    if isTreatingDisease then
        local valueW = self:getTextWidth(cureRemaining, UIFont.Small)
        self:drawTextRight(cureRemaining, x + w - 10, y + 7, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        self:drawTextRight(self:truncateText(safeText("UI_EHR_TimeToCure", "Time to cure:"), math.max(80, w - 210), UIFont.Small), x + w - valueW - 18, y + 7, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    elseif activeValue ~= "" then
        local valueW = self:getTextWidth(activeValue, UIFont.Small)
        local label = tostring(treatment.effectLabel or "Active:")
        self:drawTextRight(activeValue, x + w - 10, y + 7, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Small)
        self:drawTextRight(self:truncateText(label, math.max(80, w - 210), UIFont.Small), x + w - valueW - 18, y + 7, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Small)
    else
        self:drawTextRight(safeText("UI_EHR_GeneralEffect", "General effect"), x + w - 10, y + 7, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    end

    if doseText ~= "" then
        self:drawText(doseText, textX, y + 30, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        if scheduleValue ~= "" then
            local valueW = self:getTextWidth(scheduleValue, UIFont.Small)
            self:drawTextRight(scheduleValue, x + w - 10, y + 30, scheduleColor.r, scheduleColor.g, scheduleColor.b, scheduleColor.a, UIFont.Small)
            self:drawTextRight(self:truncateText(scheduleText, math.max(72, w - 180), UIFont.Small), x + w - valueW - 18, y + 30, scheduleColor.r, scheduleColor.g, scheduleColor.b, scheduleColor.a, UIFont.Small)
        else
            self:drawTextRight(self:truncateText(scheduleText, math.max(120, w - 120), UIFont.Small), x + w - 10, y + 30, scheduleColor.r, scheduleColor.g, scheduleColor.b, scheduleColor.a, UIFont.Small)
        end
    end

    local barX = textX
    local barY = y + rowH - 14
    local barW = math.max(40, w - (barX - x) - 14)
    local filled = math.floor(barW * progress)
    self:drawRect(barX, barY, barW, 5, 1, 0.05, 0.05, 0.05)
    if filled > 0 then
        self:drawRect(barX, barY, filled, 5, c.green.a, c.green.r, c.green.g, c.green.b)
    end
    self:drawRectBorder(barX, barY, barW, 5, 0.75, c.border.r, c.border.g, c.border.b)

    return rowH + 8
end

function EHR_HealthPanelUI:drawRightPanel()
    local c = EHR_HealthPanelUI.Colors
    local layout = self:getEHRLayout()
    local x = layout.rightX
    local y = layout.rightY
    local w = layout.rightW
    local h = layout.rightH
    local clipY = y + 44
    local clipH = h - 56

    self:drawPanelFrame(x, y, w, h, nil, nil)
    self:drawSectionTitle(safeText("UI_EHR_Details", "DETAILS"), x, y, w)

    self:setStencilRect(x, clipY, w, clipH)

    local contentY = clipY + 8 - (self.contentScrollY or 0)
    local startY = contentY
    local diseases = tableValuesSortedByName(self.cachedData.diseases, function(id, disease)
        local displayInfo = self:getDiseaseDisplayInfo(id, disease)
        return displayInfo.sortName or displayInfo.displayName
    end)

    self:drawSectionTitle(safeText("UI_EHR_ActiveConditions", "ACTIVE CONDITIONS"), x + 8, contentY, w - 16)
    contentY = contentY + 36

    if #diseases == 0 then
        self:drawText(safeText("UI_EHR_NoConditions", "No active conditions"), x + 18, contentY, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Medium)
        contentY = contentY + 42
    else
        for _, item in ipairs(diseases) do
            contentY = contentY + self:drawDiseaseRow(item.id, item.data, x + 8, contentY, w - 16)
        end
    end

    local treatments = self.cachedData.activeMedications or self.cachedData.activeTreatments or {}
    self:drawSectionTitle(safeText("UI_EHR_ActiveMedications", "ACTIVE MEDICATIONS"), x + 8, contentY + 8, w - 16)
    contentY = contentY + 46

    if #treatments == 0 then
        self:drawRect(x + 14, contentY, w - 28, 54, 0.34, c.panelSoft.r, c.panelSoft.g, c.panelSoft.b)
        self:drawWornFrame(x + 14, contentY, w - 28, 54, c.borderDim, 4)
        if getTexture then
            self.noMedsTexture = self.noMedsTexture or getTexture("media/textures/EHR_NoMeds.png") or false
        end
        if self.noMedsTexture and self.drawTextureScaled then
            self:drawTextureScaled(self.noMedsTexture, x + 22, contentY + 10, 34, 34, 0.82, 1.0, 1.0, 1.0)
        else
            self:drawRoundIcon(x + 22, contentY + 14, 26, c.panel, c.borderDim, "", c.textDim)
        end
        self:drawDockedText(safeText("UI_EHR_NoMedications", "No active medications"), x + 64, contentY, w - 92, 54, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
        contentY = contentY + 66
    else
        for _, treatment in ipairs(treatments) do
            contentY = contentY + self:drawTreatmentRow(treatment, x + 14, contentY, w - 28)
        end
    end

    local sideEffects = self.cachedData.activeSideEffects or {}
    self:drawSectionTitle(safeText("UI_EHR_SideEffects", "SIDE EFFECTS"), x + 8, contentY + 8, w - 16)
    contentY = contentY + 46

    if #sideEffects == 0 then
        self:drawText(safeText("UI_EHR_NoSideEffects", "No active side effects"), x + 18, contentY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
        contentY = contentY + 34
    else
        for _, effect in ipairs(sideEffects) do
            local name = effect.displayName or effect.effectId or "Side effect"
            if EHR.Medication and EHR.Medication.GetSideEffectDisplayName and effect.effectId then
                name = EHR.Medication.GetSideEffectDisplayName(effect.effectId, effect)
            end
            local remaining = formatShortHours(effect.hoursRemaining or 0)
            self:drawText(self:truncateText(name, w - 120, UIFont.Small), x + 18, contentY, c.yellow.r, c.yellow.g, c.yellow.b, c.yellow.a, UIFont.Small)
            self:drawTextRight(remaining, x + w - 18, contentY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
            contentY = contentY + 22
        end
    end

    self.contentHeight = math.max(0, contentY - startY + 12)
    self:clearStencilRect()
    self:clampContentScroll()
    self:drawScrollBar(x + w - 10, clipY, 5, clipH)
end

function EHR_HealthPanelUI:getMaxContentScroll()
    local layout = self:getEHRLayout()
    local viewHeight = (layout and layout.rightH or 0) - 56
    return math.max(0, (self.contentHeight or 0) - viewHeight)
end

function EHR_HealthPanelUI:clampContentScroll()
    self.contentScrollY = clamp(self.contentScrollY or 0, 0, self:getMaxContentScroll())
end

function EHR_HealthPanelUI:getImmunityColor(value)
    local c = EHR_HealthPanelUI.Colors
    value = tonumber(value) or 0
    if value >= 80 then return c.green end
    if value >= 60 then return c.blue end
    if value >= 40 then return c.yellow end
    if value >= 20 then return c.orange end
    return c.red
end

function EHR_HealthPanelUI:getImmunityStatusId(value)
    if EHR.Immunity and EHR.Immunity.GetStatusId then
        return EHR.Immunity.GetStatusId(value)
    end

    value = tonumber(value) or 0
    if value < 20 then return "suppressed" end
    if value < 40 then return "compromised" end
    if value < 60 then return "strained" end
    if value < 80 then return "stable" end
    return "strong"
end

function EHR_HealthPanelUI:getImmunityStatusText(statusId)
    local labels = {
        suppressed = safeText("UI_EHR_Immunity_Status_Suppressed", "Suppressed"),
        compromised = safeText("UI_EHR_Immunity_Status_Compromised", "Compromised"),
        strained = safeText("UI_EHR_Immunity_Status_Strained", "Strained"),
        stable = safeText("UI_EHR_Immunity_Status_Stable", "Stable"),
        strong = safeText("UI_EHR_Immunity_Status_Strong", "Strong"),
    }
    return labels[statusId] or labels.strained
end

function EHR_HealthPanelUI:drawImmunityBar(x, y, w, h, value, target, color)
    local c = EHR_HealthPanelUI.Colors
    value = clamp(tonumber(value) or 0, 0, 100)
    target = clamp(tonumber(target) or value, 0, 100)
    color = color or self:getImmunityColor(value)

    self:drawRect(x, y, w, h, 0.90, 0.025, 0.025, 0.028)
    local fillW = math.floor(w * value / 100)
    if fillW > 0 then
        self:drawRect(x, y, fillW, h, color.a, color.r, color.g, color.b)
        self:drawRect(x, y, fillW, math.max(2, math.floor(h * 0.18)), 0.20, 1.0, 0.88, 0.72)
    end
    self:drawRectBorder(x, y, w, h, 0.82, c.border.r, c.border.g, c.border.b)

    local markerX = x + math.floor((w - 2) * target / 100)
    self:drawRect(markerX, y - 2, 2, h + 4, 0.92, c.text.r, c.text.g, c.text.b)
end

function EHR_HealthPanelUI:drawContaminationBar(x, y, w, h, value, color)
    local c = EHR_HealthPanelUI.Colors
    value = clamp(tonumber(value) or 0, 0, 100)
    color = color or self:getImmunityColor(100 - value)

    self:drawRect(x, y, w, h, 0.90, 0.025, 0.025, 0.028)
    local fillW = math.floor(w * value / 100)
    if fillW > 0 then
        self:drawRect(x + 1, y + 1, math.max(0, fillW - 2), h - 2, 0.88, color.r, color.g, color.b)
    end
    self:drawRectBorder(x, y, w, h, c.borderDim.a, c.borderDim.r, c.borderDim.g, c.borderDim.b)
end

function EHR_HealthPanelUI:drawImmunityFactorRow(label, value, x, y, w, rowH)
    local c = EHR_HealthPanelUI.Colors
    local color = self:getImmunityColor(value)
    local font = self:getCompactFont()
    local pctText = string.format("%d%%", math.floor((tonumber(value) or 0) + 0.5))

    self:drawDockedText(self:truncateText(label, w - 70, font), x, y, w - 70, 22, c.text.r, c.text.g, c.text.b, c.text.a, font)
    self:drawDockedTextRight(pctText, x + w, y, 22, color.r, color.g, color.b, color.a, font)
    self:drawImmunityBar(x, y + 27, w, 10, value, value, color)
    self:drawRect(x, y + rowH - 1, w, 1, 0.22, c.borderDim.r, c.borderDim.g, c.borderDim.b)
end

function EHR_HealthPanelUI:drawImmuneStatusPanel()
    local c = EHR_HealthPanelUI.Colors
    local bounds = self:getTabContentBounds()
    local state = self.cachedData and self.cachedData.immunity or {}
    local hasData = type(state) == "table" and state.version ~= nil
    local score = clamp(tonumber(state.score) or 50, 0, 100)
    local target = clamp(tonumber(state.target) or score, 0, 100)
    local enabled = state.enabled ~= false
    local statusText = self:getImmunityStatusText(self:getImmunityStatusId(score))
    local scoreColor = self:getImmunityColor(score)

    local gameplayActive = enabled and state.observationOnly ~= true
    local topH = 190
    self:drawPanelFrame(bounds.x, bounds.y, bounds.w, topH, safeText("UI_EHR_Immunity_Title", "IMMUNE SYSTEM"), nil)

    if not hasData then
        self:drawDockedTextCenter(
            safeText("UI_EHR_Immunity_AwaitingData", "Awaiting immune system data"),
            bounds.x + 20, bounds.y + 58, bounds.w - 40, 54,
            c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium
        )
        return
    end

    self:drawDockedText(
        string.format("%d%%", math.floor(score + 0.5)),
        bounds.x + 18, bounds.y + 50, 150, 44,
        scoreColor.r, scoreColor.g, scoreColor.b, scoreColor.a, UIFont.Large
    )

    if not enabled then
        statusText = safeText("UI_EHR_Immunity_Disabled", "Disabled")
        scoreColor = c.textDim
    end
    self:drawDockedTextRight(
        statusText, bounds.x + bounds.w - 18, bounds.y + 51, 38,
        scoreColor.r, scoreColor.g, scoreColor.b, scoreColor.a, UIFont.Medium
    )

    local barX = bounds.x + 18
    local barY = bounds.y + 101
    local barW = bounds.w - 36
    self:drawImmunityBar(barX, barY, barW, 25, score, target, scoreColor)

    local trendLabels = {
        recovering = safeText("UI_EHR_Immunity_Trend_Recovering", "Recovering"),
        declining = safeText("UI_EHR_Immunity_Trend_Declining", "Declining"),
        stable = safeText("UI_EHR_Immunity_Trend_Stable", "Stable"),
        disabled = safeText("UI_EHR_Immunity_Disabled", "Disabled"),
    }
    local trend = trendLabels[state.trend] or trendLabels.stable
    self:drawDockedText(
        safeText("UI_EHR_Immunity_Trend", "Trend") .. ": " .. trend,
        barX, barY + 31, math.floor(barW / 2), 24,
        c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, self:getCompactFont()
    )
    self:drawDockedTextRight(
        string.format("%s: %d%%", safeText("UI_EHR_Immunity_Target", "Target"), math.floor(target + 0.5)),
        barX + barW, barY + 31, 24,
        c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, self:getCompactFont()
    )

    local riskText
    local riskColor = c.textDim
    if gameplayActive and EHR.Immunity and EHR.Immunity.GetRiskModifierPercent then
        local riskModifier = tonumber(EHR.Immunity.GetRiskModifierPercent(score)) or 0
        local riskSign = riskModifier > 0 and "+" or ""
        riskText = safeText("UI_EHR_Immunity_InfectionRisk", "Infection risk")
            .. ": " .. riskSign .. string.format("%.1f%%", riskModifier)
        if riskModifier > 0.05 then
            riskColor = c.orange
        elseif riskModifier < -0.05 then
            riskColor = c.green
        end
    else
        riskText = safeText("UI_EHR_Immunity_InfectionRisk", "Infection risk")
            .. ": " .. safeText("UI_EHR_Immunity_NotApplied", "Not applied")
    end
    self:drawDockedTextCenter(
        riskText,
        barX, barY + 56, barW, 24,
        riskColor.r, riskColor.g, riskColor.b, riskColor.a, self:getCompactFont()
    )

    local lowerY = bounds.y + topH + 10
    local lowerH = bounds.y + bounds.h - lowerY
    local gap = 10
    local leftW = math.floor((bounds.w - gap) * 0.60)
    local rightW = bounds.w - leftW - gap
    local rightX = bounds.x + leftW + gap

    self:drawPanelFrame(bounds.x, lowerY, leftW, lowerH, safeText("UI_EHR_Immunity_SystemicFactors", "SYSTEMIC FACTORS"), nil)
    local factorRows = {
        { id = "nutrition", label = safeText("UI_EHR_Immunity_Factor_Nutrition", "Nutrition") },
        { id = "hydration", label = safeText("UI_EHR_Immunity_Factor_Hydration", "Hydration") },
        { id = "rest", label = safeText("UI_EHR_Immunity_Factor_Rest", "Rest") },
        { id = "stressControl", label = safeText("UI_EHR_Immunity_Factor_StressControl", "Stress control") },
        { id = "bloodCondition", label = safeText("UI_EHR_Immunity_Factor_BloodCondition", "Blood condition") },
        { id = "healthReserve", label = safeText("UI_EHR_Immunity_Factor_HealthReserve", "Health reserve") },
    }
    local factors = type(state.factors) == "table" and state.factors or {}
    local factorX = bounds.x + 16
    local factorY = lowerY + 51
    local factorW = leftW - 32
    local rowH = math.max(47, math.floor((lowerH - 62) / #factorRows))
    for index, factor in ipairs(factorRows) do
        self:drawImmunityFactorRow(factor.label, factors[factor.id] or 0, factorX, factorY + (index - 1) * rowH, factorW, rowH)
    end

    self:drawPanelFrame(rightX, lowerY, rightW, lowerH, safeText("UI_EHR_Immunity_BarrierDefense", "DIRTINESS / BLOODINESS"), nil)
    local hygiene = type(state.hygiene) == "table" and state.hygiene or nil
    if not hygiene then
        local legacyBarrier = type(state.barrier) == "table" and state.barrier or {}
        local legacyDirtiness = 100 - clamp(tonumber(legacyBarrier.score) or 100, 0, 100)
        hygiene = {
            dirtiness = legacyDirtiness,
            bloodiness = legacyBarrier.hasBlood == true and math.max(1, legacyDirtiness) or 0,
        }
    end

    local dirtiness = clamp(tonumber(hygiene.dirtiness) or 0, 0, 100)
    local bloodiness = clamp(tonumber(hygiene.bloodiness) or 0, 0, 100)
    local dirtColor = self:getImmunityColor(100 - dirtiness)
    local bloodColor = self:getImmunityColor(100 - bloodiness)
    local metricFont = self:getCompactFont()

    self:drawDockedText(
        safeText("UI_EHR_Immunity_HandsArms", "Dirtiness"),
        rightX + 16, lowerY + 52, rightW - 92, 24,
        c.text.r, c.text.g, c.text.b, c.text.a, metricFont
    )
    self:drawDockedTextRight(
        string.format("%d%%", math.floor(dirtiness + 0.5)),
        rightX + rightW - 16, lowerY + 52, 24,
        dirtColor.r, dirtColor.g, dirtColor.b, dirtColor.a, metricFont
    )
    self:drawContaminationBar(rightX + 16, lowerY + 80, rightW - 32, 18, dirtiness, dirtColor)

    self:drawDockedText(
        safeText("UI_EHR_Immunity_BloodContamination", "Bloodiness"),
        rightX + 16, lowerY + 113, rightW - 92, 24,
        c.text.r, c.text.g, c.text.b, c.text.a, metricFont
    )
    self:drawDockedTextRight(
        string.format("%d%%", math.floor(bloodiness + 0.5)),
        rightX + rightW - 16, lowerY + 113, 24,
        bloodColor.r, bloodColor.g, bloodColor.b, bloodColor.a, metricFont
    )
    self:drawContaminationBar(rightX + 16, lowerY + 141, rightW - 32, 18, bloodiness, bloodColor)

    local hygienePenalty = clamp(tonumber(hygiene.immunePenalty) or 0, 0, 55)
    local penaltyColor = c.green
    if hygienePenalty >= 25 then
        penaltyColor = c.red
    elseif hygienePenalty >= 10 then
        penaltyColor = c.orange
    elseif hygienePenalty > 0 then
        penaltyColor = c.yellow
    end
    self:drawDockedText(
        safeText("UI_EHR_Immunity_HygienePenalty", "Immune penalty") .. ": -" .. string.format("%d", math.floor(hygienePenalty + 0.5)),
        rightX + 16, lowerY + 164, rightW - 32, 24,
        penaltyColor.r, penaltyColor.g, penaltyColor.b, penaltyColor.a, metricFont
    )

    local pressuresY = lowerY + 194
    self:drawSectionTitle(safeText("UI_EHR_Immunity_CurrentPressures", "CURRENT PRESSURES"), rightX + 10, pressuresY, rightW - 20)
    local pressureRows = {}
    for _, factor in ipairs(factorRows) do
        local value = tonumber(factors[factor.id]) or 0
        if value < 50 then
            table.insert(pressureRows, { label = factor.label, value = value })
        end
    end
    if state.antibioticSuppressed == true then
        table.insert(pressureRows, {
            label = safeText("UI_EHR_Immunity_AntibioticPressure", "Antibiotic suppression"),
            value = clamp(tonumber(state.antibioticCap) or 35, 0, 100),
            priority = true,
        })
    end
    table.sort(pressureRows, function(a, b)
        if a.priority ~= b.priority then return a.priority == true end
        return a.value < b.value
    end)

    local pressureTextY = pressuresY + 38
    if #pressureRows == 0 then
        self:drawDockedText(
            safeText("UI_EHR_Immunity_NoMajorPressures", "No major systemic pressures"),
            rightX + 18, pressureTextY, rightW - 36, 28,
            c.green.r, c.green.g, c.green.b, c.green.a, self:getCompactFont()
        )
    else
        for index = 1, math.min(4, #pressureRows) do
            local pressure = pressureRows[index]
            local pressureColor = self:getImmunityColor(pressure.value)
            self:drawRect(rightX + 18, pressureTextY + 7, 8, 8, pressureColor.a, pressureColor.r, pressureColor.g, pressureColor.b)
            self:drawDockedText(
                self:truncateText(pressure.label, rightW - 90, self:getCompactFont()),
                rightX + 32, pressureTextY, rightW - 90, 24,
                c.text.r, c.text.g, c.text.b, c.text.a, self:getCompactFont()
            )
            self:drawDockedTextRight(
                string.format("%d%%", math.floor(pressure.value + 0.5)),
                rightX + rightW - 18, pressureTextY, 24,
                pressureColor.r, pressureColor.g, pressureColor.b, pressureColor.a, self:getCompactFont()
            )
            pressureTextY = pressureTextY + 27
        end
    end

    local systemStateText = gameplayActive
        and safeText("UI_EHR_Immunity_GameplayActive", "System state: Active")
        or safeText("UI_EHR_Immunity_MonitoringOnly", "System state: Monitoring only")
    self:drawDockedText(
        systemStateText,
        rightX + 18, lowerY + lowerH - 34, rightW - 36, 24,
        c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, self:getCompactFont()
    )
end

function EHR_HealthPanelUI:drawScrollBar(x, y, w, h)
    local maxScroll = self:getMaxContentScroll()
    if maxScroll <= 0 then return end

    local c = EHR_HealthPanelUI.Colors
    local thumbH = math.max(32, math.floor(h * (h / math.max(h, self.contentHeight or h))))
    local thumbY = y + math.floor((self.contentScrollY / maxScroll) * (h - thumbH))

    self:drawRect(x, y, w, h, 0.45, 0.04, 0.04, 0.04)
    self:drawRect(x, thumbY, w, thumbH, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:resetTemperatureButtonState(view)
    if not view then return end
    if view.viewButtons then
        for _, group in pairs(view.viewButtons) do
            for _, button in ipairs(group) do
                button.pressed = false
                button.mouseOver = false
            end
        end
    end
    if view.toggleAdvBtn then
        view.toggleAdvBtn.pressed = false
        view.toggleAdvBtn.mouseOver = false
    end
end

function EHR_HealthPanelUI:prerender()
    ISPanel.prerender(self)
    if self:closeRemoteExamIfOutOfRange() then return end
    self:ensureUsableSize()
    self:processRemoteBodyDamageRefresh()
    self:refreshRemoteExamDataIfNeeded()
    self:updateCachedData()
    self:layoutEmbeddedVanillaTabs()
    self:syncTabVisibility()

    local c = EHR_HealthPanelUI.Colors
    self:drawRect(0, 0, self.width, self.height, c.background.a, c.background.r, c.background.g, c.background.b)
    self:drawHeader()
    self:drawTabBar()

    if self.activeTab == "ehr" then
        self:drawBloodCompositionPanel()
        self:drawLeftPanel()

        if self.rightExpanded then
            self:drawRightPanel()
        end
    elseif self.activeTab == "immunity" then
        self:drawImmuneStatusPanel()
    else
        self:drawEmbeddedTabFrame()
    end

    self:drawWornFrame(0, 0, self.width, self.height, c.border, 14)
end

function EHR_HealthPanelUI:render()
    self:drawResizeHandle()
    self:drawTabTooltip()
end

function EHR_HealthPanelUI:onMouseWheel(del)
    if self.activeTab ~= "ehr" then return false end
    if not self.rightExpanded then return false end
    local maxScroll = self:getMaxContentScroll()
    if maxScroll <= 0 then return false end

    self.contentScrollY = (self.contentScrollY or 0) + (del * self.SCROLL_STEP)
    self:clampContentScroll()
    return true
end

function EHR_HealthPanelUI:onMouseDown(x, y)
    if self:isInResizeHandle(x, y) then
        self.resizing = true
        self.resizeStartW = self.width
        self.resizeStartH = self.height
        self.resizeMouseStartX = getMouseX()
        self.resizeMouseStartY = getMouseY()
        self:bringToTop()
        return true
    end

    for _, tab in ipairs(self.tabBounds or {}) do
        if x >= tab.x and x <= tab.x + tab.w and y >= tab.y and y <= tab.y + tab.h then
            self:setActiveTab(tab.id)
            return true
        end
    end

    if self.activeTab == "ehr" then
        for _, marker in ipairs(self.markerBounds or {}) do
            if x >= marker.x and x <= marker.x + marker.w and y >= marker.y and y <= marker.y + marker.h then
                self.selectedZone = marker.id
                return true
            end
        end
    end

    if y <= self.HEADER_HEIGHT and x < self.width - 70 then
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

function EHR_HealthPanelUI:onMouseMove(dx, dy)
    if self.resizing then
        local mouseX = getMouseX()
        local mouseY = getMouseY()
        local newW = self.resizeStartW + (mouseX - self.resizeMouseStartX)
        local newH = self.resizeStartH + (mouseY - self.resizeMouseStartY)
        newW, newH = self:clampWindowSize(newW, newH)

        self:setWidth(newW)
        self:setHeight(newH)
        self:repositionControls()
        return true
    end

    if self.dragging then
        local mouseX = getMouseX()
        local mouseY = getMouseY()
        local newX = self.dragStartX + (mouseX - self.dragMouseStartX)
        local newY = self.dragStartY + (mouseY - self.dragMouseStartY)

        local core = getCore and getCore()
        if core then
            newX = math.max(0, math.min(newX, core:getScreenWidth() - self.width))
            newY = math.max(0, math.min(newY, core:getScreenHeight() - self.height))
        end

        self:setX(newX)
        self:setY(newY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function EHR_HealthPanelUI:onMouseUp(x, y)
    self:stopPointerInteraction()
    return ISPanel.onMouseUp(self, x, y)
end

function EHR_HealthPanelUI:onMouseMoveOutside(dx, dy)
    if self.dragging or self.resizing then
        return self:onMouseMove(dx, dy)
    end
    if ISPanel.onMouseMoveOutside then
        return ISPanel.onMouseMoveOutside(self, dx, dy)
    end
    return false
end

function EHR_HealthPanelUI:onMouseUpOutside(x, y)
    self:stopPointerInteraction()
    if ISPanel.onMouseUpOutside then
        return ISPanel.onMouseUpOutside(self, x, y)
    end
    return true
end

function EHR_HealthPanelUI:onClose()
    if self.isRemoteHealthPanel then
        if EHR.UI and EHR.UI.DestroyRemoteHealthPanel then
            EHR.UI.DestroyRemoteHealthPanel(self.remotePatient or self.player or self.ehrRemoteKey)
            return
        end
        self:setVisible(false)
        return
    end

    if EHR.UI and EHR.UI.HideHealthPanel then
        EHR.UI.HideHealthPanel()
        return
    end
    self:setVisible(false)
    EHR.UI.HealthPanelVisible = false
end

function EHR_HealthPanelUI:onToggleRight()
    self.rightExpanded = not self.rightExpanded
    if self.rightExpanded then
        self:setWidth(EHR_HealthPanelUI.EXPANDED_WIDTH)
    else
        self:setWidth(EHR_HealthPanelUI.COLLAPSED_WIDTH)
    end
    self:repositionControls()
    self:keepOnScreen()
end

function EHR_HealthPanelUI:applyDefaultOpenMode()
    local compact = true
    if EHR.UI and EHR.UI.ShouldOpenHealthPanelCompact then
        compact = EHR.UI.ShouldOpenHealthPanelCompact()
    end

    self.rightExpanded = not compact
    self:setWidth(compact and EHR_HealthPanelUI.COLLAPSED_WIDTH or EHR_HealthPanelUI.EXPANDED_WIDTH)
    self:repositionControls()
end

function EHR.UI.ShowHealthPanel(player)
    player = player or (getSpecificPlayer and getSpecificPlayer(0)) or (getPlayer and getPlayer())
    if not player then return end

    suppressLegacyHealthUI(12)

    if not EHR.UI.HealthPanelInstance then
        local core = getCore and getCore()
        local screenW = core and core:getScreenWidth() or 1280
        local screenH = core and core:getScreenHeight() or 720
        local initialW = EHR.UI.ShouldOpenHealthPanelCompact() and EHR_HealthPanelUI.COLLAPSED_WIDTH or EHR_HealthPanelUI.EXPANDED_WIDTH
        local x = math.floor((screenW - initialW) / 2)
        local y = math.floor((screenH - EHR_HealthPanelUI.HEIGHT) / 2)

        local panel = EHR_HealthPanelUI:new(math.max(0, x), math.max(0, y), player)
        panel:initialise()
        panel:instantiate()
        panel:addToUIManager()
        EHR.UI.HealthPanelInstance = panel
    end

    EHR.UI.HealthPanelInstance:bindPlayer(player)
    EHR.UI.HealthPanelInstance.activeTab = "ehr"
    EHR.UI.HealthPanelInstance.contentScrollY = 0
    EHR.UI.HealthPanelInstance:applyDefaultOpenMode()
    EHR.UI.HealthPanelInstance:syncTabVisibility()
    EHR.UI.HealthPanelInstance:setVisible(true)
    EHR.UI.HealthPanelInstance:bringToTop()
    EHR.UI.HealthPanelInstance:keepOnScreen()
    EHR.UI.HealthPanelVisible = true
end

function EHR.UI.HideHealthPanel()
    if EHR.UI.HealthPanelInstance then
        EHR.UI.HealthPanelInstance:setVisible(false)
    end
    EHR.UI.HealthPanelVisible = false
    suppressLegacyHealthUI(12)
end

function EHR.UI.DestroyHealthPanel()
    local panel = EHR.UI.HealthPanelInstance
    if not panel then
        EHR.UI.HealthPanelVisible = false
        return
    end

    pcall(function()
        panel:destroyPlayerBoundViews()
    end)
    pcall(function()
        panel:setVisible(false)
    end)
    pcall(function()
        if panel.removeFromUIManager then
            panel:removeFromUIManager()
        end
    end)

    EHR.UI.HealthPanelInstance = nil
    EHR.UI.HealthPanelVisible = false
end

function EHR.UI.ToggleHealthPanel(player)
    if EHR.UI.HealthPanelInstance and EHR.UI.HealthPanelInstance:isVisible() then
        EHR.UI.HideHealthPanel()
    else
        EHR.UI.ShowHealthPanel(player)
    end
end

local function patchEquippedItemHealthButton()
    if not ISEquippedItem or ISEquippedItem.ehrPrimaryPanelSwapPatch then return end
    if not ISEquippedItem.onOptionMouseDown then return end

    local originalOnOptionMouseDown = ISEquippedItem.onOptionMouseDown
    local originalPrerender = ISEquippedItem.prerender
    ISEquippedItem.ehrPrimaryPanelSwapPatch = true
    EHR.UI.OriginalEquippedItemHealthMouseDown = originalOnOptionMouseDown

    ISEquippedItem.onOptionMouseDown = function(self, button, x, y)
        if button and button.internal == "HEALTH" and EHR.UI then
            if EHR.UI.ShouldHeartButtonOpenEHR and EHR.UI.ShouldHeartButtonOpenEHR() then
                local player = self and self.chr or (getSpecificPlayer and getSpecificPlayer(self and self.playerNum or 0)) or (getPlayer and getPlayer())
                if EHR.UI.ToggleHealthPanel then
                    EHR.UI.ToggleHealthPanel(player)
                    return
                end
            elseif EHR.UI.HideHealthPanelOnly then
                if EHR.UI.ClearLegacyHealthSuppression then
                    EHR.UI.ClearLegacyHealthSuppression()
                end
                EHR.UI.HideHealthPanelOnly()
                if EHR.UI.HideMonitor then
                    EHR.UI.HideMonitor()
                end
            end
        end

        return originalOnOptionMouseDown(self, button, x, y)
    end

    if originalPrerender then
        ISEquippedItem.prerender = function(self)
            originalPrerender(self)
            if self and self.healthBtn and self.heartIconOn and self.heartIconOff
                    and EHR.UI and EHR.UI.ShouldHeartButtonOpenEHR and EHR.UI.ShouldHeartButtonOpenEHR() then
                if EHR.UI.HealthPanelInstance and EHR.UI.HealthPanelInstance:isVisible() then
                    self.healthBtn:setImage(self.heartIconOn)
                else
                    self.healthBtn:setImage(self.heartIconOff)
                end
            end
        end
    end
end

patchEquippedItemHealthButton()
patchCharacterInfoWindowHealthToggle()
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(patchEquippedItemHealthButton)
    Events.OnGameStart.Add(patchCharacterInfoWindowHealthToggle)
end

function EHR.UI.GetRemoteHealthPanelKey(playerOrUsername)
    if not playerOrUsername then return nil end

    if type(playerOrUsername) == "string" then
        if string.sub(playerOrUsername, 1, 5) == "user_" or string.sub(playerOrUsername, 1, 7) == "online_" or string.sub(playerOrUsername, 1, 7) == "player_" then
            return playerOrUsername
        end
        return "user_" .. playerOrUsername
    end

    local username = nil
    pcall(function()
        if playerOrUsername.getUsername then
            username = playerOrUsername:getUsername()
        end
    end)
    if username and username ~= "" then
        return "user_" .. tostring(username)
    end

    local onlineID = nil
    pcall(function()
        if playerOrUsername.getOnlineID then
            onlineID = playerOrUsername:getOnlineID()
        end
    end)
    if onlineID ~= nil then
        return "online_" .. tostring(onlineID)
    end

    local playerNum = nil
    pcall(function()
        if playerOrUsername.getPlayerNum then
            playerNum = playerOrUsername:getPlayerNum()
        end
    end)
    if playerNum ~= nil then
        return "player_" .. tostring(playerNum)
    end

    return tostring(playerOrUsername)
end

function EHR.UI.GetRemoteHealthPanelForPatient(patient)
    local instances = EHR.UI.RemoteHealthPanelInstances
    if not instances then return nil end

    local key = EHR.UI.GetRemoteHealthPanelKey(patient)
    if key and instances[key] then
        return instances[key]
    end

    if type(patient) == "string" then
        for _, panel in pairs(instances) do
            local name = nil
            pcall(function()
                if panel.remotePatient and panel.remotePatient.getUsername then
                    name = panel.remotePatient:getUsername()
                end
            end)
            if name == patient or ("user_" .. tostring(name)) == patient then
                return panel
            end
        end
    end

    return nil
end

function EHR.UI.ShowRemoteHealthPanel(doctor, patient, examData)
    if not doctor or not patient then return nil end

    EHR.UI.RemoteHealthPanelInstances = EHR.UI.RemoteHealthPanelInstances or {}
    local key = EHR.UI.GetRemoteHealthPanelKey(patient)
    if not key then return nil end

    suppressLegacyHealthUI(8)

    local panel = EHR.UI.RemoteHealthPanelInstances[key]
    local created = false
    if not panel then
        local core = getCore and getCore()
        local screenW = core and core:getScreenWidth() or 1280
        local screenH = core and core:getScreenHeight() or 720
        local count = 0
        for _ in pairs(EHR.UI.RemoteHealthPanelInstances) do
            count = count + 1
        end

        local initialW = EHR.UI.ShouldOpenHealthPanelCompact() and EHR_HealthPanelUI.COLLAPSED_WIDTH or EHR_HealthPanelUI.EXPANDED_WIDTH
        local x = math.floor((screenW - initialW) / 2) + (count % 3) * 24
        local y = math.floor((screenH - EHR_HealthPanelUI.HEIGHT) / 2) + (count % 3) * 32

        panel = EHR_HealthPanelUI:new(math.max(0, x), math.max(0, y), patient)
        panel.isRemoteHealthPanel = true
        panel.remoteDoctor = doctor
        panel.remotePatient = patient
        panel.playerNum = doctor.getPlayerNum and doctor:getPlayerNum() or 0
        panel.ehrRemoteKey = key
        panel.remoteExamData = examData
        panel:initialise()
        panel:instantiate()
        panel:addToUIManager()
        EHR.UI.RemoteHealthPanelInstances[key] = panel
        created = true
    end

    panel.ehrRemoteKey = key
    panel.remoteExamData = examData or panel.remoteExamData
    panel:bindRemotePatient(doctor, patient, created or panel.remotePatient ~= patient)
    panel.activeTab = "ehr"
    panel.contentScrollY = 0
    panel:applyDefaultOpenMode()
    panel:repositionControls()
    panel:syncTabVisibility()
    panel:setVisible(true)
    panel:bringToTop()
    panel:keepOnScreen()

    return panel
end

function EHR.UI.UpdateRemoteHealthPanelData(targetUsername, examData)
    if not targetUsername or type(examData) ~= "table" then return false end

    local panel = EHR.UI.GetRemoteHealthPanelForPatient(targetUsername)
    if not panel then
        return false
    end

    panel.remoteExamData = examData
    panel.cachedData = {}
    panel.remoteBodyPartStatusCache = {}
    panel.lastRemoteExamRefreshMs = getTimestampMs and getTimestampMs() or panel.lastRemoteExamRefreshMs
    if panel.syncBodyPartPanelBodyParts then
        panel:syncBodyPartPanelBodyParts()
    end
    return true
end

function EHR.UI.HideRemoteHealthPanel(patientOrKey)
    local panel = EHR.UI.GetRemoteHealthPanelForPatient(patientOrKey)
    if not panel then return end
    panel:setVisible(false)
end

function EHR.UI.DestroyRemoteHealthPanel(patientOrKey)
    local instances = EHR.UI.RemoteHealthPanelInstances
    if not instances then return end

    local key = EHR.UI.GetRemoteHealthPanelKey(patientOrKey)
    local panel = key and instances[key] or EHR.UI.GetRemoteHealthPanelForPatient(patientOrKey)
    if not panel then return end
    key = panel.ehrRemoteKey or key

    if panel.remoteDoctor and panel.remotePatient and panel.remoteDoctor.stopReceivingBodyDamageUpdates then
        pcall(function()
            panel.remoteDoctor:stopReceivingBodyDamageUpdates(panel.remotePatient)
        end)
    end
    pcall(function()
        panel:destroyPlayerBoundViews()
    end)
    pcall(function()
        panel:setVisible(false)
    end)
    pcall(function()
        if panel.removeFromUIManager then
            panel:removeFromUIManager()
        end
    end)

    if key then
        instances[key] = nil
    else
        for storedKey, storedPanel in pairs(instances) do
            if storedPanel == panel then
                instances[storedKey] = nil
                break
            end
        end
    end
end

function EHR.UI.DestroyAllRemoteHealthPanels()
    local instances = EHR.UI.RemoteHealthPanelInstances
    if not instances then return end

    local keys = {}
    for key in pairs(instances) do
        table.insert(keys, key)
    end
    for _, key in ipairs(keys) do
        EHR.UI.DestroyRemoteHealthPanel(key)
    end
end

local function patchRemoteBodyPartActionProgress()
    if not ISHealthPanel or ISHealthPanel.ehrRemotePanelActionPatch then return end
    if not ISHealthPanel.setBodyPartActionForPlayer then return end

    local originalSetBodyPartActionForPlayer = ISHealthPanel.setBodyPartActionForPlayer
    ISHealthPanel.ehrRemotePanelActionPatch = true
    ISHealthPanel.setBodyPartActionForPlayer = function(playerObj, bodyPart, action, jobType, args)
        local result = originalSetBodyPartActionForPlayer(playerObj, bodyPart, action, jobType, args)

        if EHR.UI and EHR.UI.GetRemoteHealthPanelForPatient then
            local panel = EHR.UI.GetRemoteHealthPanelForPatient(playerObj)
            if panel then
                if panel.ensureRemoteBodyDamageUpdates then
                    panel:ensureRemoteBodyDamageUpdates()
                end
                local adapter = panel:getVanillaHealthAdapter()
                if adapter and adapter.setBodyPartAction then
                    if args then
                        args.jobType = jobType
                        if action and action.getJobDelta then
                            pcall(function()
                                args.delta = action:getJobDelta()
                            end)
                        end
                    end
                    adapter:setBodyPartAction(bodyPart, args)
                end
                if not action or not args then
                    if panel.markRemoteBodyDamageDirty then
                        panel:markRemoteBodyDamageDirty(120)
                    end
                    if panel.queueRemoteExamRefreshBurst then
                        panel:queueRemoteExamRefreshBurst()
                    end
                    if EHR.MPExamination and EHR.MPExamination.RequestExamData
                            and panel.remoteDoctor and panel.remotePatient
                            and isClient and isClient() then
                        EHR.MPExamination.RequestExamData(panel.remoteDoctor, panel.remotePatient, true, true)
                    end
                end
            end
        end

        return result
    end
end

patchRemoteBodyPartActionProgress()

if Events then
    Events.OnTick.Add(onTickHideVanilla)
    if Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(function(player)
            if EHR.UI and EHR.UI.HealthPanelInstance and EHR.UI.HealthPanelInstance.player == player and EHR.UI.DestroyHealthPanel then
                EHR.UI.DestroyHealthPanel()
            end
            if EHR.UI and EHR.UI.DestroyRemoteHealthPanel then
                EHR.UI.DestroyRemoteHealthPanel(player)
            end
        end)
    end
    if Events.OnCreatePlayer then
        Events.OnCreatePlayer.Add(function(playerIndex, player)
            if EHR.UI and EHR.UI.HealthPanelInstance and player then
                EHR.UI.HealthPanelInstance:bindPlayer(player, true)
                EHR.UI.HealthPanelInstance:setVisible(false)
                EHR.UI.HealthPanelVisible = false
            end
        end)
    end
end

EHR.Log("HealthPanelUI prototype loaded")

