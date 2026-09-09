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
pcall(function() require "MF_ISMoodle" end)

local MODULE = EHR.Moodles

local MOODLE_MEDICAL = "EHR_MedicalAlert"
local LEGACY_MOODLE_EXPOSURE = "EHR_ExposureAlert"
local MOODLE_CORPSE_EXPOSURE = "EHR_CorpseExposure"
local MOODLE_CADAVERIC_EXPOSURE = "EHR_CadavericExposure"
local MOODLE_HEAT_EXPOSURE = "EHR_HeatExposure"
local MOODLE_COLD_EXPOSURE = "EHR_ColdExposure"
local RETIRED_MOODLE_FREEZING_EXPOSURE = "EHR_FreezingExposure"
local UPDATE_TICKS = 90
local NEUTRAL_VALUE = 0.50

local MOODLE_NAMES = {
    MOODLE_MEDICAL,
    MOODLE_CORPSE_EXPOSURE,
    MOODLE_CADAVERIC_EXPOSURE,
    MOODLE_HEAT_EXPOSURE,
    MOODLE_COLD_EXPOSURE,
}

local BAD = 2
local LEVEL_VALUE = {
    [1] = 0.35,
    [2] = 0.25,
    [3] = 0.15,
    [4] = 0.05,
}

local ICONS = {
    medical = "media/textures/EHR_Disease_UnknownMoodle.png",
    corpse = "media/textures/EHR_Disease_CorpseSicknessMoodle.png",
    cadaveric = "media/textures/EHR_Disease_CadavericAspergillosisMoodle.png",
    heat = "media/textures/EHR_Disease_HeatExhaustionMoodle.png",
    cold = "media/textures/EHR_Disease_CommonColdMoodle.png",
}

-- EHR moodle pictures are complete circular badges already. Use MF's public
-- background override to prevent its solid fill from becoming a white square.
local TRANSPARENT_MOODLE_TEXTURE = "media/textures/emptyTexture.png"

local textureCache = {}
local configuredObjects = MODULE.configuredObjects or {}
MODULE.configuredObjects = configuredObjects
local registrationErrors = MODULE.registrationErrors or {}
MODULE.registrationErrors = registrationErrors
local registrationComplete = false

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

local function shouldShowEHRMoodles()
    if EHR.Keybinds and EHR.Keybinds.ShouldShowMoodles then
        return safeCall(function()
            return EHR.Keybinds.ShouldShowMoodles()
        end, true) ~= false
    end
    return true
end

local function registerMoodle(name)
    if not isMFReady() then return false end

    -- MoodleFramework owns the complete object lifecycle. createMoodle() is
    -- idempotent and registers its own OnCreatePlayer callback once per name.
    local ok, err = pcall(MF.createMoodle, name)
    if ok then return true end

    if not registrationErrors[name] then
        registrationErrors[name] = true
        if EHR.Log then
            EHR.Log("MoodleFramework registration failed for " .. tostring(name) .. ": " .. tostring(err))
        end
    end
    return false
end

local function ensureMoodlesRegistered()
    if registrationComplete then return true end
    if not isMFReady() then return false end
    for _, name in ipairs(MOODLE_NAMES) do
        if not registerMoodle(name) then return false end
    end
    registrationComplete = true
    return true
end

local function installMF27ConstructorGuard()
    if not isMFReady()
        or type(MF.MoodleData) ~= "table"
        or type(MF.ISMoodle) ~= "table"
        or type(MF.ISMoodle.new) ~= "function"
        or MF.ISMoodle._EHRMF27ConstructorGuard
        or MF.ISMoodle._TrueSmokingCtorHotfix then
        return
    end

    -- MF 2.7/B42.20 initializes storage through MF.ISMoodle:getMoodleData()
    -- instead of the newly-created object. Temporarily exposing the constructor
    -- arguments on the class lets the upstream createMoodle lifecycle finish.
    -- This guard does not create, store, position, or dispose EHR moodles.
    local originalNew = MF.ISMoodle.new
    MF.ISMoodle._EHRMF27ConstructorGuard = true

    function MF.ISMoodle:new(moodleName, character)
        local oldName = rawget(self, "name")
        local oldChar = rawget(self, "char")
        self.name = moodleName
        self.char = character

        local ok, result = pcall(originalNew, self, moodleName, character)

        self.name = oldName
        self.char = oldChar
        if not ok then error(result) end
        return result
    end
end

local function ensureMoodleObject(name, playerNum)
    if not ensureMoodlesRegistered() then return nil end

    local moodle = safeCall(function()
        return MF.getMoodle(name, playerNum)
    end, nil)
    if not moodle then return nil end

    local objectKey = tostring(playerNum) .. ":" .. tostring(name)
    if configuredObjects[objectKey] ~= moodle then
        -- Keep all values inside MoodleFramework's documented 0..1 contract.
        -- 0.50 is neutral/hidden; lower values map to bad levels 1..4.
        moodle:setThresholds(0.05, 0.15, 0.25, 0.35, nil, nil, nil, nil)
        moodle:setChevronCount(0)

        local transparentTexture = getTextureCached(TRANSPARENT_MOODLE_TEXTURE)
        if transparentTexture then
            for level = 1, 4 do
                moodle:setBackground(BAD, level, transparentTexture)
            end
        end

        configuredObjects[objectKey] = moodle
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
    local highRiskRatio = math.max(0, math.min(1,
        tonumber(config.ASPERGILLOSIS_HIGH_RISK_RATIO) or 0.85))
    local minExposure = tonumber(config.ASPERGILLOSIS_DISPLAY_MIN_EXPOSURE) or 1

    if highThreshold <= 0 or exposure <= 0 or exposure < minExposure then
        return "None", 0
    end
    if exposure >= highThreshold * highRiskRatio then
        return "High", clamp(exposure / highThreshold, 0, 1)
    end
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
    if type(active) == "table" then
        if active.heat_stroke then
            return "High", 1
        end
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
        return "None", 0
    end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and safeCall(function()
        return EHR.Disease.GetDiseaseData(player)
    end, nil) or nil
    local active = type(diseaseData) == "table" and diseaseData.active or nil

    local exposure = safeCall(function()
        return EHR.Environmental.GetExposureData(player)
    end, nil)
    if type(exposure) ~= "table" then
        return "None", 0
    end

    local config = EHR.Environmental.Config or {}
    local coldThreshold = tonumber(config.coldExposureForCold) or 2.0
    local soakedThreshold = tonumber(config.soakedExposureForCold) or coldThreshold

    local coldRatio = 0
    if coldThreshold > 0 then
        coldRatio = (tonumber(exposure.coldExposure) or 0) / coldThreshold
    end

    local soakedRatio = 0
    if soakedThreshold > 0 then
        soakedRatio = (tonumber(exposure.soakedColdExposure) or 0) / soakedThreshold
    end

    -- The wet-only common-cold route now starts above 90% character wetness.
    -- Show Cold Exposure immediately at Low instead of waiting until 5% of the
    -- one-hour exposure timer has accumulated. Respect the environmental risk
    -- flag so controlled bathing and a nearby heat source do not show a false
    -- warning.
    local soakedWetnessThreshold = tonumber(config.commonColdSoakedThreshold) or 0.90
    local wetness = EHR.Environmental.GetWetness and safeCall(function()
        return EHR.Environmental.GetWetness(player)
    end, 0) or 0
    local immediateSoakedRisk = (tonumber(wetness) or 0) > soakedWetnessThreshold
    if exposure.commonColdSoakedRisk == false then
        immediateSoakedRisk = false
    end
    if immediateSoakedRisk then
        soakedRatio = math.max(soakedRatio, 0.05)
    end

    local coldLevel, coldDisplayRatio = exposureLevelFromRatio(math.max(coldRatio, soakedRatio))

    -- Cold Exposure is the high-wetness warning requested by EHR. Do not let a
    -- saved/decaying accumulator display it below the live 90% gate. This also
    -- cleans up exposure accumulated by older builds that interpreted B42's
    -- 0..100 WETNESS stat as if it were already normalized.
    if not immediateSoakedRisk then
        coldLevel, coldDisplayRatio = "None", 0
    end

    if type(active) == "table" then
        if active.common_cold or active.pneumonia then
            coldLevel, coldDisplayRatio = "None", 0
        end
    end

    return coldLevel, coldDisplayRatio
end

local function makeExposureAlert(exposureLevel, icon, titleKey, titleFallback)
    local level = levelScore(exposureLevel)
    if level <= 0 then return nil end
    return {
        level = level,
        exposureLevel = exposureLevel,
        icon = icon,
        title = L(titleKey, titleFallback),
        description = L("UI_EHR_Moodle_ExposureAlert_Desc", "Exposure level: ") .. EHR.Locale.ExposureLevel(exposureLevel),
    }
end

local function applyMoodle(playerNum, name, alert)
    local moodle = ensureMoodleObject(name, playerNum)
    if not moodle then return end

    if not alert then
        moodle:setValue(NEUTRAL_VALUE)
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

local function hideRetiredMoodles(playerNum)
    if not isMFReady() then return end

    local retiredNames = {
        LEGACY_MOODLE_EXPOSURE,
        RETIRED_MOODLE_FREEZING_EXPOSURE,
    }
    for _, name in ipairs(retiredNames) do
        local moodle = safeCall(function()
            return MF.getMoodle(name, playerNum)
        end, nil)
        if moodle then
            safeCall(function() moodle:setValue(NEUTRAL_VALUE) end)
        end
    end
end

local function hideAllEHRMoodles(playerNum)
    if not isMFReady() then return end

    for _, name in ipairs(MOODLE_NAMES) do
        local moodle = safeCall(function()
            return MF.getMoodle(name, playerNum)
        end, nil)
        if moodle then
            safeCall(function() moodle:setValue(NEUTRAL_VALUE) end)
        end
    end

    hideRetiredMoodles(playerNum)
end

function MODULE.UpdatePlayer(playerNum)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player then return end

    -- This is a client-only display preference. Keep every disease/exposure
    -- system active and only clear EHR's MoodleFramework objects.
    if not shouldShowEHRMoodles() then
        hideAllEHRMoodles(playerNum)
        return
    end

    local corpseLevel = corpseExposureLevel(player)
    local cadavericLevel = cadavericExposureLevel(player)
    local heatLevel = heatExposureLevel(player)
    local coldLevel = coldExposureLevels(player)

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
    -- Hide framework objects left behind by an in-session Lua reload from an
    -- older EHR build, without registering those retired identifiers again.
    hideRetiredMoodles(playerNum)
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

-- Register before EHR's own OnCreatePlayer callback so MoodleFramework creates
-- every object first and EHR only configures/updates the returned instances.
installMF27ConstructorGuard()
ensureMoodlesRegistered()

if not MODULE.eventsRegistered then
    MODULE.eventsRegistered = true
    if Events and Events.OnTick then Events.OnTick.Add(onTick) end
    if Events and Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
    if Events and Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
end

if EHR.Log then EHR.Log("EHR_Moodles.lua loaded (optional MoodleFramework integration)") end
