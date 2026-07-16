-- Optional MoodleFramework integration.
-- EHR works without MoodleFramework; this file simply stays dormant.

EHR = EHR or {}
EHR.Moodles = EHR.Moodles or {}

pcall(function() require "ExtensiveHealth/EHR_Main" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
pcall(function() require "ExtensiveHealth/EHR_DiseaseFlyers" end)
pcall(function() require "ExtensiveHealth/EHR_Disease" end)
pcall(function() require "ExtensiveHealth/EHR_CorpseSickness" end)
pcall(function() require "ExtensiveHealth/EHR_EnvironmentalDiseases" end)
pcall(function() require "ExtensiveHealth/EHR_WoundInfection" end)
pcall(function() require "ExtensiveHealth/EHR_Sepsis" end)
pcall(function() require "ExtensiveHealth/EHR_Medication" end)
pcall(function() require "ExtensiveHealth/EHR_KnoxCure" end)

local MODULE = EHR.Moodles

local MOODLE_MEDICAL = "EHR_MedicalAlert"
local LEGACY_MOODLE_EXPOSURE = "EHR_ExposureAlert"
local MOODLE_CORPSE_EXPOSURE = "EHR_CorpseExposure"
local MOODLE_CADAVERIC_EXPOSURE = "EHR_CadavericExposure"
local MOODLE_HEAT_EXPOSURE = "EHR_HeatExposure"
local MOODLE_COLD_EXPOSURE = "EHR_ColdExposure"
local MOODLE_FREEZING_EXPOSURE = "EHR_FreezingExposure"
local UPDATE_TICKS = 90

local MOODLE_NAMES = {
    MOODLE_MEDICAL,
    MOODLE_CORPSE_EXPOSURE,
    MOODLE_CADAVERIC_EXPOSURE,
    MOODLE_HEAT_EXPOSURE,
    MOODLE_COLD_EXPOSURE,
    MOODLE_FREEZING_EXPOSURE,
}

local BAD = 2
local LEVEL_VALUE = {
    [1] = -0.25,
    [2] = -0.50,
    [3] = -0.75,
    [4] = -1.00,
}

local ICONS = {
    medical = "media/textures/EHR_Disease_Unknown.png",
    corpse = "media/textures/EHR_Disease_CorpseSickness.png",
    cadaveric = "media/textures/EHR_Disease_CadavericAspergillosis.png",
    heat = "media/textures/EHR_Disease_HeatExhaustion.png",
    cold = "media/textures/EHR_Disease_CommonCold.png",
    freezing = "media/textures/EHR_Disease_Hypotermia.png",
}

local registeredNames = MODULE.registeredNames or {}
MODULE.registeredNames = registeredNames

local textureCache = {}

local function L(key, fallback)
    if EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text(key, fallback)
    end
    return fallback or key
end

local function safeCall(fn, default)
    local ok, result = pcall(fn)
    if ok then return result end
    return default
end

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getTextureCached(path)
    if not getTexture or not path then return nil end
    if textureCache[path] ~= nil then
        return textureCache[path] or nil
    end

    local texture = getTexture(path)
    textureCache[path] = texture or false
    return texture
end

local function isMFReady()
    return type(MF) == "table"
        and type(MF.createMoodle) == "function"
        and type(MF.getMoodle) == "function"
end

local function registerMoodle(name)
    if registeredNames[name] then return true end
    if not isMFReady() then return false end

    local ok = pcall(function()
        MF.createMoodle(name)
    end)
    if ok then
        registeredNames[name] = true
    end
    return ok
end

local function ensureMoodlesRegistered()
    if not isMFReady() then return false end
    for _, name in ipairs(MOODLE_NAMES) do
        registerMoodle(name)
    end
    for _, name in ipairs(MOODLE_NAMES) do
        if registeredNames[name] ~= true then return false end
    end
    return true
end

local function ensureMoodleObject(name, playerNum)
    if not ensureMoodlesRegistered() then return nil end

    local moodle = safeCall(function()
        return MF.getMoodle(name, playerNum)
    end, nil)

    if not moodle and MF.ISMoodle and MF.ISMoodle.new and getSpecificPlayer then
        local player = getSpecificPlayer(playerNum)
        if player then
            moodle = safeCall(function()
                return MF.ISMoodle:new(name, player)
            end, nil)
        end
    end

    if moodle and not moodle.ehrConfigured then
        moodle:setThresholds(-1.0, -0.75, -0.50, -0.01, nil, nil, nil, nil)
        moodle:setChevronCount(0)
        moodle.ehrConfigured = true
    end

    return moodle
end

local function levelFromStage(stage)
    stage = math.floor(tonumber(stage) or 1)
    return clamp(stage, 1, 4)
end

local function activeDiseaseCountAndLevel(player)
    local count = 0
    local level = 0

    local diseaseData = nil
    if EHR.Disease and EHR.Disease.GetDiseaseData then
        diseaseData = safeCall(function()
            return EHR.Disease.GetDiseaseData(player)
        end, nil)
    end

    diseaseData = diseaseData or (player and player:getModData() and player:getModData().EHR_Disease) or nil
    local active = type(diseaseData) == "table" and diseaseData.active or nil

    if type(active) == "table" then
        for diseaseId, disease in pairs(active) do
            local normalized = diseaseId
            if EHR.DiseaseFlyers and EHR.DiseaseFlyers.NormalizeDiseaseId then
                normalized = safeCall(function()
                    return EHR.DiseaseFlyers.NormalizeDiseaseId(diseaseId)
                end, diseaseId)
            end

            if normalized ~= "knox_infection" then
                count = count + 1
                level = math.max(level, levelFromStage(type(disease) == "table" and disease.stage or 1))
            end
        end
    end

    if EHR.KnoxCure and EHR.KnoxCure.IsInfected then
        local infected = safeCall(function()
            return EHR.KnoxCure.IsInfected(player)
        end, false)
        if infected then
            count = count + 1
            level = math.max(level, 4)
        end
    end

    return count, level
end

local function woundInfectionLevel(player)
    if not (EHR.WoundInfection and EHR.WoundInfection.HasAnyInfection) then return 0 end

    local hasWoundInfection = safeCall(function()
        return EHR.WoundInfection.HasAnyInfection(player)
    end, false)
    if not hasWoundInfection then return 0 end

    local data = EHR.WoundInfection.GetData and safeCall(function()
        return EHR.WoundInfection.GetData(player)
    end, nil) or nil

    return levelFromStage(data and data.worstStage or 1)
end

local function sepsisLevel(player)
    if not (EHR.Sepsis and EHR.Sepsis.GetData) then return 0 end
    local data = safeCall(function()
        return EHR.Sepsis.GetData(player)
    end, nil)
    if not data or data.active ~= true or not data.stage or data.stage <= 0 then return 0 end
    return levelFromStage((tonumber(data.stage) or 1) + 1)
end

local function sideEffectLevel(player)
    if not (EHR.Medication and EHR.Medication.GetActiveSideEffects) then return 0 end

    local effects = safeCall(function()
        return EHR.Medication.GetActiveSideEffects(player)
    end, {}) or {}
    if type(effects) ~= "table" or #effects <= 0 then return 0 end

    local level = #effects > 1 and 2 or 1
    for _, effect in ipairs(effects) do
        local severity = tostring(effect and effect.severity or ""):lower()
        if severity == "critical" or severity == "severe" or severity == "high" then
            level = math.max(level, 3)
        elseif severity == "medium" or severity == "moderate" then
            level = math.max(level, 2)
        end
    end

    return level
end

local function getMedicalAlert(player)
    if not player then return nil end

    local diseaseCount, level = activeDiseaseCountAndLevel(player)
    local woundLevel = woundInfectionLevel(player)
    local sepsis = sepsisLevel(player)
    local sideEffects = sideEffectLevel(player)

    level = math.max(level, woundLevel, sepsis, sideEffects)
    if diseaseCount <= 0 and woundLevel <= 0 and sepsis <= 0 and sideEffects <= 0 then
        return nil
    end

    local title = L("UI_EHR_Moodle_MedicalAlert_Title", "Medical Alert")
    local desc = L("UI_EHR_Moodle_MedicalAlert_Desc", "Something is wrong. Check EHR Monitor.")

    if sideEffects > 0 and diseaseCount <= 0 and woundLevel <= 0 and sepsis <= 0 then
        desc = L("UI_EHR_Moodle_MedicalAlert_SideEffects", "Medication side effects active. Check EHR Monitor.")
    elseif diseaseCount > 1 then
        desc = L("UI_EHR_Moodle_MedicalAlert_Multiple", "Multiple active conditions. Check EHR Monitor.")
    end

    return {
        level = clamp(level, 1, 4),
        icon = ICONS.medical,
        title = title,
        description = desc,
    }
end

local function levelScore(level)
    if level == "High" then return 3 end
    if level == "Medium" then return 2 end
    if level == "Low" then return 1 end
    return 0
end

local function cadavericExposureLevel(player)
    if not (EHR.CorpseSickness and EHR.CorpseSickness.GetExposureData) then return "None", 0 end

    local data = safeCall(function()
        return EHR.CorpseSickness.GetExposureData(player)
    end, nil)
    if type(data) ~= "table" then return "None", 0 end

    local config = EHR.CorpseSickness.Config or {}
    local exposure = tonumber(data.fungalExposure) or 0
    local highThreshold = tonumber(config.ASPERGILLOSIS_EXPOSURE_THRESHOLD) or 120
    local minExposure = tonumber(config.ASPERGILLOSIS_DISPLAY_MIN_EXPOSURE) or 1

    if highThreshold <= 0 or exposure <= 0 or exposure < minExposure then
        return "None", 0
    end
    if exposure >= highThreshold then return "High", 1 end
    if exposure >= highThreshold * 0.60 then return "Medium", clamp(exposure / highThreshold, 0, 1) end
    return "Low", clamp(exposure / highThreshold, 0, 1)
end

local function corpseExposureLevel(player)
    if not (EHR.CorpseSickness and EHR.CorpseSickness.GetExposureDisplay) then return "None", 0 end

    local level = safeCall(function()
        return EHR.CorpseSickness.GetExposureDisplay(player)
    end, "None")
    if not level or level == "None" then return "None", 0 end

    local ratio = 0
    local data = EHR.CorpseSickness.GetExposureData and safeCall(function()
        return EHR.CorpseSickness.GetExposureData(player)
    end, nil) or nil
    if type(data) == "table" then
        local exposure = math.max(tonumber(data.currentExposure) or 0, tonumber(data.vanillaCorpseExposure) or 0)
        local threshold = tonumber(EHR.CorpseSickness.Config and EHR.CorpseSickness.Config.EXPOSURE_THRESHOLD_HIGH) or 100
        if threshold > 0 then ratio = clamp(exposure / threshold, 0, 1) end
    end

    return level, ratio
end

local function heatExposureLevel(player)
    if not (EHR.Environmental and EHR.Environmental.GetHeatExposureDisplay) then return "None", 0 end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and safeCall(function()
        return EHR.Disease.GetDiseaseData(player)
    end, nil) or nil
    local active = type(diseaseData) == "table" and diseaseData.active or nil
    if type(active) == "table" and (active.heat_exhaustion or active.heat_stroke) then
        return "None", 0
    end

    local level = safeCall(function()
        return EHR.Environmental.GetHeatExposureDisplay(player)
    end, "None")
    if not level or level == "None" then return "None", 0 end

    local ratio = EHR.Environmental.GetHeatExposureRatio and safeCall(function()
        return EHR.Environmental.GetHeatExposureRatio(player)
    end, 0) or 0
    return level, clamp(ratio, 0, 1)
end

local function exposureLevelFromRatio(ratio)
    ratio = math.max(0, tonumber(ratio) or 0)
    if ratio < 0.05 then return "None", clamp(ratio, 0, 1) end
    if ratio >= 0.85 then return "High", clamp(ratio, 0, 1) end
    if ratio >= 0.50 then return "Medium", clamp(ratio, 0, 1) end
    return "Low", clamp(ratio, 0, 1)
end

local function coldExposureLevels(player)
    if not (EHR.Environmental and EHR.Environmental.GetExposureData) then
        return "None", 0, "None", 0
    end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and safeCall(function()
        return EHR.Disease.GetDiseaseData(player)
    end, nil) or nil
    local active = type(diseaseData) == "table" and diseaseData.active or nil

    local exposure = safeCall(function()
        return EHR.Environmental.GetExposureData(player)
    end, nil)
    if type(exposure) ~= "table" then
        return "None", 0, "None", 0
    end

    local config = EHR.Environmental.Config or {}
    local coldThreshold = tonumber(config.coldExposureForCold) or 2.0
    local soakedThreshold = tonumber(config.soakedExposureForCold) or coldThreshold
    local hypoThreshold = tonumber(config.coldExposureForHypo) or 0.5

    local coldRatio = 0
    if coldThreshold > 0 then
        coldRatio = (tonumber(exposure.coldExposure) or 0) / coldThreshold
    end

    local soakedRatio = 0
    if soakedThreshold > 0 then
        soakedRatio = (tonumber(exposure.soakedColdExposure) or 0) / soakedThreshold
    end

    local hypoRatio = 0
    if hypoThreshold > 0 then
        hypoRatio = (tonumber(exposure.hypothermiaExposure) or 0) / hypoThreshold
    end

    local coldLevel, coldDisplayRatio = exposureLevelFromRatio(math.max(coldRatio, soakedRatio))
    local freezingLevel, freezingDisplayRatio = exposureLevelFromRatio(hypoRatio)

    if type(active) == "table" then
        if active.common_cold or active.pneumonia then
            coldLevel, coldDisplayRatio = "None", 0
        end
        if active.hypothermia then
            freezingLevel, freezingDisplayRatio = "None", 0
        end
    end

    return coldLevel, coldDisplayRatio, freezingLevel, freezingDisplayRatio
end

local function makeExposureAlert(exposureLevel, icon, titleKey, titleFallback)
    local level = levelScore(exposureLevel)
    if level <= 0 then return nil end
    return {
        level = level,
        exposureLevel = exposureLevel,
        icon = icon,
        title = L(titleKey, titleFallback),
        description = L("UI_EHR_Moodle_ExposureAlert_Desc", "Exposure level: ") .. tostring(exposureLevel),
    }
end

local function applyMoodle(playerNum, name, alert)
    local moodle = ensureMoodleObject(name, playerNum)
    if not moodle then return end

    if not alert then
        moodle:setValue(0)
        return
    end

    local level = clamp(alert.level or 1, 1, 4)
    local texture = getTextureCached(alert.icon) or getTextureCached(ICONS.medical)
    if texture then
        moodle:setPicture(BAD, level, texture)
    end
    moodle:setTitle(BAD, level, alert.title or "")
    moodle:setDescription(BAD, level, alert.description or "")
    moodle:setValue(LEVEL_VALUE[level] or LEVEL_VALUE[1])
end

local function hideLegacyExposureMoodle(playerNum)
    if not isMFReady() then return end
    local moodle = safeCall(function()
        return MF.getMoodle(LEGACY_MOODLE_EXPOSURE, playerNum)
    end, nil)
    if moodle then moodle:setValue(0) end
end

function MODULE.UpdatePlayer(playerNum)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player then return end

    local corpseLevel = corpseExposureLevel(player)
    local cadavericLevel = cadavericExposureLevel(player)
    local heatLevel = heatExposureLevel(player)
    local coldLevel, _, freezingLevel = coldExposureLevels(player)

    applyMoodle(playerNum, MOODLE_MEDICAL, getMedicalAlert(player))
    applyMoodle(playerNum, MOODLE_CORPSE_EXPOSURE,
        makeExposureAlert(corpseLevel, ICONS.corpse, "UI_EHR_CorpseExposure", "Corpse Exposure"))
    applyMoodle(playerNum, MOODLE_CADAVERIC_EXPOSURE,
        makeExposureAlert(cadavericLevel, ICONS.cadaveric,
            "UI_EHR_CadavericAspergillosisExposure", "Cadaveric Aspergillosis Exposure"))
    applyMoodle(playerNum, MOODLE_HEAT_EXPOSURE,
        makeExposureAlert(heatLevel, ICONS.heat, "UI_EHR_Moodle_HeatExposure_Title", "Heat Exposure"))
    applyMoodle(playerNum, MOODLE_COLD_EXPOSURE,
        makeExposureAlert(coldLevel, ICONS.cold, "UI_EHR_Moodle_ColdRisk_Title", "Cold Risk"))
    applyMoodle(playerNum, MOODLE_FREEZING_EXPOSURE,
        makeExposureAlert(freezingLevel, ICONS.freezing,
            "UI_EHR_Moodle_FreezingExposure_Title", "Freezing Exposure"))
    hideLegacyExposureMoodle(playerNum)
end

function MODULE.UpdateAll()
    if not ensureMoodlesRegistered() then return end

    local count = 1
    if getNumActivePlayers then
        count = safeCall(function() return getNumActivePlayers() end, 1) or 1
    end
    if count < 1 then count = 1 end

    for playerNum = 0, count - 1 do
        MODULE.UpdatePlayer(playerNum)
    end
end

local function onTick()
    MODULE.tickCounter = (MODULE.tickCounter or 0) + 1
    if MODULE.tickCounter < UPDATE_TICKS then return end
    MODULE.tickCounter = 0
    MODULE.UpdateAll()
end

local function onCreatePlayer(playerNum)
    if ensureMoodlesRegistered() then
        MODULE.UpdatePlayer(playerNum or 0)
    end
end

local function onGameStart()
    MODULE.tickCounter = UPDATE_TICKS
    MODULE.UpdateAll()
end

if not MODULE.eventsRegistered then
    MODULE.eventsRegistered = true
    if Events and Events.OnTick then Events.OnTick.Add(onTick) end
    if Events and Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
    if Events and Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
end

if EHR.Log then EHR.Log("EHR_Moodles.lua loaded (optional MoodleFramework integration)") end
