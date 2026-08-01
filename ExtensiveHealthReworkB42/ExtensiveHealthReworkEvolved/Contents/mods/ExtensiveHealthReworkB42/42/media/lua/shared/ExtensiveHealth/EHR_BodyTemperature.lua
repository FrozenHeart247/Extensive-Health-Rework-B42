--[[
    Extensive Health Rework B42
    Body Temperature Module

    Vanilla-driven body temperature bridge.
    Provides gradual pre-disease effects (shivering, sweating) and smooth
    transitions to hypothermia; heat-stroke risk is managed by environmental exposure.

    Normal body temperature: 36.6°C (97.9°F)
    Hypothermia starts: <= 35.0°C
    Heat exhaustion risk: > 40.5°C

    v1.1.0 - Vanilla Thermoregulator heat-balance adapter for ICL
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.BodyTemp = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.BodyTemp.Config = {
    -- Normal body temperature (Celsius)
    normalTemp = 36.6,

    -- Comfort zone (air temperature range where body maintains 36.6°C easily)
    -- Within this range, body temperature stays stable without effort
    comfortZoneMin = 10.0,   -- Below this, start feeling cold (lowered from 12.0)
    comfortZoneMax = 28.0,   -- Above this, start feeling hot
    comfortZoneCenter = 20.0, -- Ideal temperature (for reference)

    -- Cold thresholds (Celsius) - adjusted to be less sensitive
    -- Normal body temp can range 36.0-37.5°C in healthy people
    coldStage1 = 35.8,   -- Chilly (lowered from 36.5 - 36.4°C is normal!)
    coldStage2 = 35.5,   -- Cold (lowered from 36.0)
    coldStage3 = 35.0,   -- Very Cold
    coldStage4 = 34.0,   -- Severe Cold

    -- Hypothermia disease thresholds (Celsius)
    hypothermiaStage1 = 35.0,
    hypothermiaStage2 = 34.0,
    hypothermiaStage3 = 32.0,
    hypothermiaStage4 = 31.0,
    hypothermiaClearTemp = 35.5,
    hypothermiaStageHysteresis = 0.25,

    -- Hot thresholds (Celsius)
    hotStage1 = 37.5,    -- Warm
    hotStage2 = 38.5,    -- Hot
    hotStage3 = 39.5,    -- Very Hot
    hotStage4 = 40.5,    -- Heat Exhaustion Risk

    -- Survivable body temp range
    minBodyTemp = 28.0,
    maxBodyTemp = 42.0,

    -- Temperature change rate (°C per game hour)
    -- Adjusted for PZ's compressed timeframe (realistic but faster)
    baseChangeRate = 0.8,  -- 10x faster than real life (~4 game hours to reach hypothermia risk)
    coldPressureFactor = 0.55, -- Cold-side target shift. Higher means cold can push below 36C.
    heatPressureFactor = 0.09, -- Heat-side target shift. Kept conservative; heat stroke uses world exposure too.
    metabolicRestingRate = 1.5, -- Vanilla Metabolics.Default, in MET.
    metabolicMaxRate = 10.3, -- Vanilla Metabolics.MAX, in MET.
    metabolicMaxTargetShift = 2.4, -- Core target increase at maximum vanilla heat generation.
    metabolicSleepTargetShift = 0.2, -- Small core target decrease below the resting metabolic rate.
    metabolicHeatingRateMaxMultiplier = 4.0, -- Faster core heating at maximum activity.
    metabolicClothingRateBonus = 1.0, -- Extra max-rate multiplier at full insulation.

    -- Disease trigger timing (game hours at dangerous temp)
    hypothermiaTriggerTime = 0.5,    -- Legacy chance timer; hypothermia now stages from <= 35°C
    heatExhaustionTriggerTime = 0.5, -- 30 game minutes at > 40.5°C

    -- Effect intervals (game hours)
    shiverDialogueInterval = 0.5,    -- 30 game minutes (reduced frequency)
    sweatDialogueInterval = 0.5,     -- 30 game minutes (reduced frequency)
    effectApplicationInterval = 0.05, -- 3 game minutes

    -- Hysteresis buffer to prevent stage flickering (°C)
    stageHysteresis = 0.3,

    -- Movement penalties per stage (multiplier)
    coldMovementPenalty = {
        [0] = 0,      -- Normal
        [1] = 0,      -- Chilly - no penalty
        [2] = 0.05,   -- Cold - 5% slower
        [3] = 0.15,   -- Very Cold - 15% slower
        [4] = 0.25,   -- Danger - 25% slower
    },

    -- Fatigue drain multiplier per cold stage
    coldFatigueDrain = {
        [0] = 1.0,
        [1] = 1.0,
        [2] = 1.10,   -- +10% fatigue
        [3] = 1.25,   -- +25% fatigue
        [4] = 1.50,   -- +50% fatigue
    },

    -- Thirst drain multiplier per hot stage
    hotThirstDrain = {
        [0] = 1.0,
        [1] = 1.10,   -- +10% thirst
        [2] = 1.25,   -- +25% thirst
        [3] = 1.50,   -- +50% thirst
        [4] = 2.00,   -- +100% thirst
    },

    -- Stamina regen reduction per hot stage
    hotStaminaPenalty = {
        [0] = 0,
        [1] = 0,
        [2] = 0.15,   -- -15% stamina regen
        [3] = 0.30,   -- -30% stamina regen
        [4] = 0.50,   -- -50% stamina regen
    },
}

-- Cold dialogue by stage
EHR.BodyTemp.ColdDialogue = {
    [1] = {
        "UI_EHR_Temp_Chilly1",
        "UI_EHR_Temp_Chilly2",
    },
    [2] = {
        "UI_EHR_Temp_Cold1",
        "UI_EHR_Temp_Cold2",
    },
    [3] = {
        "UI_EHR_Temp_VeryCold1",
        "UI_EHR_Temp_VeryCold2",
    },
    [4] = {
        "UI_EHR_Temp_Freezing1",
        "UI_EHR_Temp_Freezing2",
    },
}

-- Hot dialogue by stage
EHR.BodyTemp.HotDialogue = {
    [1] = {
        "UI_EHR_Temp_Warm1",
        "UI_EHR_Temp_Warm2",
    },
    [2] = {
        "UI_EHR_Temp_Hot1",
        "UI_EHR_Temp_Hot2",
    },
    [3] = {
        "UI_EHR_Temp_VeryHot1",
        "UI_EHR_Temp_VeryHot2",
    },
    [4] = {
        "UI_EHR_Temp_Overheating1",
        "UI_EHR_Temp_Overheating2",
    },
}

-- ============================================
-- STATE CACHE (for hysteresis)
-- ============================================

-- Per-player state cache to prevent flickering
local playerTempStates = {}  -- playerID -> {coldStage, hotStage}

-- ============================================
-- SANDBOX HELPERS
-- ============================================

function EHR.BodyTemp.IsEnabled()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local enabled = SandboxVars.ExtensiveHealthRework.BodyTemperatureEnabled
        if enabled ~= nil then return enabled end
    end
    return true -- Default enabled
end

local function EHR_BodyTempGetRealisticTemperatureCompatMode()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local mode = SandboxVars.ExtensiveHealthRework.RealisticTemperatureCompatibility
        mode = tonumber(mode)
        if mode == 2 then return "enabled" end
        if mode == 3 then return "disabled" end
    end

    return "auto"
end

function EHR.BodyTemp.DetectRealisticTemperatureActive()
    if _G and _G.RC_TempSim then return true end

    if getActivatedMods then
        local ok, activeMods = pcall(getActivatedMods)
        if ok and activeMods and activeMods.contains then
            return activeMods:contains("RC_RealisticColdMod")
                or activeMods:contains("RealisticTemperature")
        end
    end

    return false
end

function EHR.BodyTemp.IsRealisticTemperatureActive()
    local mode = EHR_BodyTempGetRealisticTemperatureCompatMode()
    if mode == "enabled" then return true end
    if mode == "disabled" then return false end

    return EHR.BodyTemp.DetectRealisticTemperatureActive()
end

local ICL_BODY_ENVIRONMENT_HEAT_PROBE_TICKS = 30
local iclBodyEnvironmentCache = setmetatable({}, { __mode = "k" })

function EHR.BodyTemp.GetIndoorClimateLiteEnvironment(player)
    if not player or not EHR.Environmental then return nil end

    local dedicatedServer = isServer and isServer()
        and not (isClient and isClient())

    -- Local thermoregulation calls this every tick. Read ICL's already-cached
    -- public sample directly instead of rebuilding the full environmental
    -- disease snapshot (shade, headwear and a 3x3 object scan) every frame.
    if not dedicatedServer and EHR.Environmental.GetIndoorClimateLiteSample then
        local okSample, sample = pcall(
            EHR.Environmental.GetIndoorClimateLiteSample,
            player
        )
        if okSample and type(sample) == "table" and tonumber(sample.airC) then
            local cache = iclBodyEnvironmentCache[player]
            if not cache then
                cache = { heatProbeTick = ICL_BODY_ENVIRONMENT_HEAT_PROBE_TICKS }
                iclBodyEnvironmentCache[player] = cache
            end

            cache.heatProbeTick = (cache.heatProbeTick or 0) + 1
            if cache.heatProbeTick >= ICL_BODY_ENVIRONMENT_HEAT_PROBE_TICKS then
                cache.heatProbeTick = 0
                if EHR.Environmental.IsNearHeat then
                    local okHeat, isNearHeat = pcall(
                        EHR.Environmental.IsNearHeat,
                        player
                    )
                    if okHeat then cache.isNearHeat = isNearHeat == true end
                end
            end

            return {
                airTemp = tonumber(sample.airC),
                isIndoors = sample.indoors == true,
                isNearHeat = cache.isNearHeat == true,
                temperatureSource = "IndoorClimateLite",
                iclActive = true,
                iclVersion = sample.version,
                iclOutdoorAirTemp = tonumber(sample.outdoorC),
                iclVanillaAirTemp = tonumber(sample.vanillaAirC),
                iclTargetAirTemp = tonumber(sample.targetC),
                iclLeakScore = tonumber(sample.leakScore),
                iclPowered = sample.powered == true,
                roomKey = sample.roomKey,
                buildingKey = sample.buildingKey,
            }
        end
    end

    if not EHR.Environmental.GetRuntimeEnvironment then return nil end
    local ok, env = pcall(EHR.Environmental.GetRuntimeEnvironment, player)
    if not ok
            or type(env) ~= "table"
            or env.temperatureSource ~= "IndoorClimateLite"
            or env.iclActive ~= true
            or not tonumber(env.airTemp) then
        return nil
    end

    return env
end

function EHR.BodyTemp.IsIndoorClimateLiteActive(player)
    if EHR.BodyTemp.IsRealisticTemperatureActive
            and EHR.BodyTemp.IsRealisticTemperatureActive() then
        return false
    end
    return EHR.BodyTemp.GetIndoorClimateLiteEnvironment(player) ~= nil
end

function EHR.BodyTemp.GetSpeedMultiplier()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local speed = SandboxVars.ExtensiveHealthRework.TemperatureChangeSpeed
        if speed ~= nil then return speed end
    end
    return 1.0
end

function EHR.BodyTemp.PreDiseaseEffectsEnabled()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local enabled = SandboxVars.ExtensiveHealthRework.PreDiseaseEffectsEnabled
        if enabled ~= nil then return enabled end
    end
    return true
end

local function EHR_BodyTempClampNumber(value, minValue, maxValue)
    value = tonumber(value)
    if not value then return nil end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function EHR_BodyTempGetSandboxNumber(name, default, minValue, maxValue)
    local value = nil
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        value = SandboxVars.ExtensiveHealthRework[name]
    end
    value = tonumber(value)
    if value == nil then value = tonumber(default) or 0 end
    return EHR_BodyTempClampNumber(value, minValue, maxValue) or value
end

function EHR.BodyTemp.GetHypothermiaThresholds()
    local cfg = EHR.BodyTemp.Config or {}
    local stage1 = EHR_BodyTempGetSandboxNumber("HypothermiaStage1Temp", cfg.hypothermiaStage1 or 35.0, 30.0, 37.0)
    local stage2 = EHR_BodyTempGetSandboxNumber("HypothermiaStage2Temp", cfg.hypothermiaStage2 or 34.0, 29.0, 36.5)
    local stage3 = EHR_BodyTempGetSandboxNumber("HypothermiaStage3Temp", cfg.hypothermiaStage3 or 32.0, 28.0, 36.0)
    local stage4 = EHR_BodyTempGetSandboxNumber("HypothermiaStage4Temp", cfg.hypothermiaStage4 or 31.0, 27.0, 35.5)
    local clear = EHR_BodyTempGetSandboxNumber("HypothermiaClearTemp", cfg.hypothermiaClearTemp or 35.5, 31.0, 38.0)

    stage2 = math.min(stage2, stage1 - 0.1)
    stage3 = math.min(stage3, stage2 - 0.1)
    stage4 = math.min(stage4, stage3 - 0.1)
    clear = math.max(clear, stage1)

    return {
        stage1 = stage1,
        stage2 = stage2,
        stage3 = stage3,
        stage4 = stage4,
        clear = clear,
    }
end

-- ============================================
-- DATA INITIALIZATION
-- ============================================

local TEMP_DATA_KEY = "EHR_Temperature"

--[[
    Initialize temperature tracking for a player.
    @param player (IsoPlayer)
]]--
function EHR.BodyTemp.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if not modData then return end

    if not modData[TEMP_DATA_KEY] then
        local currentHour = getGameTime():getWorldAgeHours()

        modData[TEMP_DATA_KEY] = {
            -- Core temperature tracking (Celsius)
            bodyTemp = EHR.BodyTemp.Config.normalTemp,
            targetTemp = EHR.BodyTemp.Config.normalTemp,
            lastUpdateHour = currentHour,

            -- Effect tracking (prevent dialogue spam)
            lastShiverTime = 0,
            lastSweatTime = 0,
            lastEffectTime = 0,

            -- Disease threshold timing
            timeAtDangerousTemp = 0,
            dangerZone = nil,  -- "cold" or "hot" or nil

            -- Stage tracking (0-4)
            coldStage = 0,
            hotStage = 0,

            -- Previous stages (for stage change detection)
            prevColdStage = 0,
            prevHotStage = 0,
        }

        if EHR.DEBUG then
            EHR.Log("BodyTemp: Initialized player temperature data")
        end
    end

    return modData[TEMP_DATA_KEY]
end

--[[
    Get temperature data for a player.
    @param player (IsoPlayer)
    @return table or nil
]]--
function EHR.BodyTemp.GetTemperatureData(player)
    if not player then return nil end

    local modData = player:getModData()
    if not modData then return nil end

    return modData[TEMP_DATA_KEY]
end

local function EHR_BodyTempIsRemoteMPClient()
    return isClient and isClient() and not (isServer and isServer())
end

function EHR.BodyTemp.GetActiveWarmingPackEffect(player)
    if not player then return nil end

    local modData = nil
    pcall(function() modData = player:getModData() end)
    local medication = modData and modData.EHR_Medication or nil
    local effects = type(medication) == "table" and medication.activeGeneralEffects or nil
    local effect = type(effects) == "table" and effects.warmingPack or nil
    if type(effect) ~= "table" then return nil end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    if currentHour >= (tonumber(effect.endTime) or currentHour) then return nil end
    return effect, currentHour
end

function EHR.BodyTemp.ApplyWarmingPackEffect(player, currentTemp)
    currentTemp = tonumber(currentTemp)
    if not currentTemp or EHR_BodyTempIsRemoteMPClient() then
        return currentTemp, false, 0, false, nil
    end

    local effect, currentHour = EHR.BodyTemp.GetActiveWarmingPackEffect(player)
    if not effect then return currentTemp, false, 0, false, nil end

    local targetTemp = math.max(36.0, math.min(37.0, tonumber(effect.targetCoreTemp) or 37.0))
    local lastUpdateHour = tonumber(effect.lastTemperatureUpdateHour) or currentHour
    local deltaHours = math.max(0, math.min(0.25, currentHour - lastUpdateHour))
    effect.lastTemperatureUpdateHour = currentHour

    if deltaHours <= 0 or currentTemp >= targetTemp then
        return currentTemp, false, 0, true, targetTemp
    end

    local warmingRate = math.max(0.1, math.min(4.0, tonumber(effect.warmingRatePerHour) or 3.2))
    local warmingDelta = math.min(targetTemp - currentTemp, warmingRate * deltaHours)
    return currentTemp + warmingDelta, warmingDelta > 0, warmingDelta, true, targetTemp
end

local function EHR_BodyTempNormalizeCelsius(value)
    value = tonumber(value)
    if not value then return nil end

    -- Most EHR code uses real Celsius. Some vanilla B42 stats are exposed on a
    -- normalized scale where ~0.5 is normal, so convert only when needed.
    if value >= 25.0 and value <= 45.0 then
        return value
    end

    if value >= -1.5 and value <= 2.0 then
        local normalTemp = EHR.BodyTemp.Config and EHR.BodyTemp.Config.normalTemp or 36.6
        return normalTemp + ((value - 0.5) * 8.0)
    end

    return nil
end

local function EHR_BodyTempCelsiusToNativeStat(stats, celsius)
    celsius = tonumber(celsius)
    if not stats or not celsius then return celsius end
    if not CharacterStat or not CharacterStat.TEMPERATURE then return celsius end

    local ok, current = pcall(function() return stats:get(CharacterStat.TEMPERATURE) end)
    current = ok and tonumber(current) or nil
    if current and current >= -1.5 and current <= 2.0 then
        local normalTemp = EHR.BodyTemp.Config and EHR.BodyTemp.Config.normalTemp or 36.6
        return ((celsius - normalTemp) / 8.0) + 0.5
    end

    return celsius
end

function EHR.BodyTemp.ReadVanillaBodyTemperature(player)
    if not player then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage and bodyDamage.getTemperature then
        local ok, temp = pcall(function() return bodyDamage:getTemperature() end)
        temp = ok and EHR_BodyTempNormalizeCelsius(temp) or nil
        if temp then return temp end
    end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        local ok, temp = pcall(function() return stats:get(CharacterStat.TEMPERATURE) end)
        temp = ok and EHR_BodyTempNormalizeCelsius(temp) or nil
        if temp then return temp end
    end

    if player.getTemperature then
        local ok, temp = pcall(function() return player:getTemperature() end)
        temp = ok and EHR_BodyTempNormalizeCelsius(temp) or nil
        if temp then return temp end
    end

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if tempData then
        return EHR_BodyTempNormalizeCelsius(tempData.bodyTemp)
    end

    return EHR.BodyTemp.Config.normalTemp or 36.6
end

local function EHR_BodyTempWriteRealisticTemperatureCore(player, bodyTemp)
    if not player or not bodyTemp then return false end
    if not (EHR.BodyTemp.IsRealisticTemperatureActive and EHR.BodyTemp.IsRealisticTemperatureActive()) then
        return false
    end

    local modData = nil
    pcall(function() modData = player:getModData() end)
    local rec = modData and modData.RC_TempSimBodyTemp or nil
    if type(rec) ~= "table" then return false end

    if EHR.RealisticTemperatureCompat
            and EHR.RealisticTemperatureCompat.ShouldOwnFever
            and EHR.RealisticTemperatureCompat.ShouldOwnFever(player)
            and rec._ehrRtBaseCore == nil
            and type(rec.core) == "number" then
        rec._ehrRtBaseCore = rec.core
    end

    rec.core = bodyTemp
    rec._lastBodyTempStatsApplied = bodyTemp
    rec._bodyTempDirty = true
    rec._ehrDiseaseFeverCore = bodyTemp
    return true
end

function EHR.BodyTemp.WriteDiseaseBodyTemperature(player, bodyTemp)
    if not player then return false end
    bodyTemp = EHR_BodyTempNormalizeCelsius(bodyTemp)
    if not bodyTemp then return false end

    -- Disease fever is owned by EHR even when an external temperature mod is
    -- active. Environmental body temperature still follows vanilla/compat mods,
    -- but fever must be mirrored to vanilla fields so moodles, the temperature
    -- tab, and other systems can actually see it.

    local wrote = EHR_BodyTempWriteRealisticTemperatureCore(player, bodyTemp)
    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage and bodyDamage.setTemperature then
        local ok = pcall(function() bodyDamage:setTemperature(bodyTemp) end)
        wrote = wrote or ok
    end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        local statTemp = EHR_BodyTempCelsiusToNativeStat(stats, bodyTemp)
        local ok = pcall(function() stats:set(CharacterStat.TEMPERATURE, statTemp) end)
        wrote = wrote or ok
    end

    return wrote
end

function EHR.BodyTemp.MaintainDiseaseFeverBridge(player)
    if not player then return false end
    if EHR.RealisticTemperatureCompat
            and EHR.RealisticTemperatureCompat.ShouldOwnFever
            and EHR.RealisticTemperatureCompat.ShouldOwnFever(player) then
        return false
    end

    local tempData = EHR.BodyTemp.GetTemperatureData and EHR.BodyTemp.GetTemperatureData(player) or nil
    local bodyTemp = tempData and tonumber(tempData.bodyTemp) or nil
    local indoorClimateManaged = tempData
        and (
            tempData.environmentManagedBy == "IndoorClimateLite"
            or tempData.environmentManagedBy == "VanillaHeatAdapter"
        )
    local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource
        and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)
    if not indoorClimateManaged and not hasFeverSource then return false end

    local normalTemp = EHR.BodyTemp.Config.normalTemp or 36.6

    -- Vanilla moodles read CharacterStat.TEMPERATURE every frame. While the ICL
    -- adapter is active, vanilla Thermoregulator can overwrite that field, so
    -- continuously preserve the corrected managed core value.
    -- Fever-only use keeps the previous above-normal guard.
    -- In MP, when ICL's air is identical to vanilla air, the adapter mirrors the
    -- real vanilla core and must not write it back: doing so erases vanilla's
    -- freshly calculated Chilly/Hot state on the very same frame.
    if tempData
            and tempData.vanillaDirectCore == true
            and not hasFeverSource then
        return false
    end

    bodyTemp = EHR_BodyTempNormalizeCelsius(bodyTemp)
    if not bodyTemp then return false end
    if not indoorClimateManaged and bodyTemp <= normalTemp + 0.05 then return false end

    return EHR.BodyTemp.WriteDiseaseBodyTemperature(player, bodyTemp)
end

function EHR.BodyTemp.IsHypothermiaEnabled()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local enabled = SandboxVars.ExtensiveHealthRework.HypothermiaEnabled
        if enabled ~= nil then return enabled end
    end
    return true
end

function EHR.BodyTemp.GetHypothermiaStageFromBodyTemp(bodyTemp, currentStage)
    local cfg = EHR.BodyTemp.Config
    local thresholds = EHR.BodyTemp.GetHypothermiaThresholds()
    bodyTemp = tonumber(bodyTemp)
    if not bodyTemp then return 0 end

    currentStage = tonumber(currentStage) or 0
    local hyst = cfg.hypothermiaStageHysteresis or 0.25

    if bodyTemp <= thresholds.stage4 then return 4 end
    if bodyTemp <= thresholds.stage3 then return 3 end
    if bodyTemp <= thresholds.stage2 then return 2 end
    if bodyTemp <= thresholds.stage1 then return 1 end

    if currentStage >= 4 and bodyTemp <= (thresholds.stage4 + hyst) then return 4 end
    if currentStage >= 3 and bodyTemp <= (thresholds.stage3 + hyst) then return 3 end
    if currentStage >= 2 and bodyTemp <= (thresholds.stage2 + hyst) then return 2 end
    if currentStage >= 1 and bodyTemp <= thresholds.clear then return 1 end

    return 0
end

local function EHR_BodyTempGetHypothermiaProgress(stage, bodyTemp)
    local cfg = EHR.BodyTemp.Config
    local thresholds = EHR.BodyTemp.GetHypothermiaThresholds()
    stage = tonumber(stage) or 0
    bodyTemp = tonumber(bodyTemp) or cfg.normalTemp

    if stage <= 0 then return 0 end
    if stage == 1 then
        local span = math.max(0.1, thresholds.stage1 - thresholds.stage2)
        return 0.05 + (math.min(1, math.max(0, (thresholds.stage1 - bodyTemp) / span)) * 0.20)
    elseif stage == 2 then
        local span = math.max(0.1, thresholds.stage2 - thresholds.stage3)
        return 0.30 + (math.min(1, math.max(0, (thresholds.stage2 - bodyTemp) / span)) * 0.25)
    elseif stage == 3 then
        local span = math.max(0.1, thresholds.stage3 - thresholds.stage4)
        return 0.60 + (math.min(1, math.max(0, (thresholds.stage3 - bodyTemp) / span)) * 0.25)
    end

    return 0.95
end

function EHR.BodyTemp.SyncHypothermiaFromTemperature(player, tempData)
    if not player or not tempData then return end
    if not EHR.BodyTemp.IsHypothermiaEnabled() then return end
    if not EHR.Disease or not EHR.Disease.GetDiseaseData then return end

    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return end

    local disease = diseaseData.active["hypothermia"]
    local currentStage = disease and disease.stage or 0
    local stage = EHR.BodyTemp.GetHypothermiaStageFromBodyTemp(tempData.bodyTemp, currentStage)
    local currentHour = getGameTime():getWorldAgeHours()

    if stage <= 0 then
        if disease and disease.temperatureDriven then
            diseaseData.active["hypothermia"] = nil
            tempData.hypothermiaStage = 0
            if EHR.Environmental and EHR.Environmental.ClearHypothermiaMovementPenalty then
                EHR.Environmental.ClearHypothermiaMovementPenalty(player)
            end
            if EHR.DEBUG then
                EHR.Log("BodyTemp: Hypothermia cleared by rewarming")
            end
        end
        return
    end

    local def = EHR.Disease.Diseases and EHR.Disease.Diseases["hypothermia"] or nil
    if not def then return end

    local created = false
    if not disease then
        disease = {
            startTime = currentHour,
            incubationEnd = currentHour,
            peakTime = currentHour,
            endTime = currentHour + 9999,
            stage = stage,
            severity = def.baseSeverity or 0.8,
            diagnosed = false,
            temperatureDriven = true,
            stageStartTime = currentHour,
            symptomCooldowns = {},
        }
        diseaseData.active["hypothermia"] = disease
        created = true
    end

    local oldStage = tonumber(disease.stage) or stage
    disease.temperatureDriven = true
    disease.stage = stage
    disease.progress = EHR_BodyTempGetHypothermiaProgress(stage, tempData.bodyTemp)
    disease.stageProgress = disease.progress
    disease.endTime = currentHour + 9999
    disease.incubationEnd = disease.startTime or currentHour
    disease.peakTime = currentHour
    local thresholds = EHR.BodyTemp.GetHypothermiaThresholds()
    disease.severity = math.max(0.55, math.min(1.0, 0.50 + (stage * 0.12) + math.max(0, (thresholds.stage1 - (tonumber(tempData.bodyTemp) or thresholds.stage1)) * 0.04)))
    tempData.hypothermiaStage = stage

    if created or oldStage ~= stage then
        disease.stageStartTime = currentHour
        if EHR.DEBUG then
            EHR.Log(string.format("BodyTemp: Hypothermia temperature stage %d (%.1fC)", stage, tempData.bodyTemp or 0))
        end
        if (created or stage > oldStage) and EHR.Dialogue and EHR.Dialogue.SayStageChange and def.stageEntryDialogue and def.stageEntryDialogue[stage] then
            EHR.Dialogue.SayStageChange(player, def.stageEntryDialogue[stage])
        end
    end
end

EHR.BodyTemp.DiseaseFeverTargets = EHR.BodyTemp.DiseaseFeverTargets or {
    cadaveric_aspergillosis = {
        [2] = 38.2,
        [3] = 39.4,
        [4] = 37.6,
    },
    trichinosis = {
        [2] = 38.0,
        [3] = 38.9,
        [4] = 37.4,
    },
    hyperkeratotic_scabies = {
        [2] = 38.0,
        [3] = 40.0,
        [4] = 40.0,
    },
    cellulitis = {
        [2] = 37.8,
        [3] = 38.6,
        [4] = 39.2,
    },
    pneumonia = {
        [1] = 38.0,
        [2] = 40.0,
        [3] = 40.0,
        [4] = 40.0,
    },
    common_cold = {
        [2] = 37.6,
        [3] = 38.0,
    },
    tuberculosis = {
        [2] = 37.7,
        [3] = 38.4,
        [4] = 37.3,
    },
    tetanus = {
        [3] = 39.0,
        [4] = 37.4,
    },
    ahtr = {
        [2] = 40.0,
        [3] = 40.1,
        [4] = 39.7,
    },
    sepsis = {
        [1] = 38.0,
        [2] = 38.6,
        [3] = 39.4,
        [4] = 40.0,
    },
    wound_infection = {
        [3] = 38.0,
        [4] = 38.0,
    },
}

local function EHR_BodyTempGetStageTarget(targets, stage)
    if not targets or not stage then return nil end
    local target = targets[stage]
    if target then return target end

    local bestStage = nil
    for candidateStage, _ in pairs(targets) do
        if candidateStage <= stage and (not bestStage or candidateStage > bestStage) then
            bestStage = candidateStage
        end
    end

    return bestStage and targets[bestStage] or nil
end

local function EHR_BodyTempApplyMedicationFeverRelief(player, diseaseId, target)
    if not player or not diseaseId or not target then return target end
    if not EHR or not EHR.Disease or not EHR.Disease.GetActiveSymptomReduction then return target end
    local cfg = EHR.BodyTemp and EHR.BodyTemp.Config or {}

    local ok, relief = pcall(function()
        return EHR.Disease.GetActiveSymptomReduction(player, diseaseId, "fever")
    end)
    relief = ok and tonumber(relief) or 0
    if relief <= 0 then return target end

    local strongFeverReducer = relief >= 0.60
    local feverFloor = strongFeverReducer and (cfg.normalTemp or 36.6) or 37.4
    local feverDrop = strongFeverReducer and 4.0 or math.min(1.2, relief * 1.8)
    return math.max(feverFloor, target - feverDrop)
end

function EHR.BodyTemp.GetActiveDiseaseFeverTarget(player)
    if not player then return nil end

    local modData = nil
    pcall(function() modData = player:getModData() end)
    if not modData then return nil end

    local bestTarget = nil
    local active = modData.EHR_Disease and modData.EHR_Disease.active or nil
    if active then
        for diseaseId, targets in pairs(EHR.BodyTemp.DiseaseFeverTargets) do
            if diseaseId ~= "sepsis" then
                local disease = active[diseaseId]
                local stage = disease and (tonumber(disease.stage) or 1) or nil
                local target = EHR_BodyTempGetStageTarget(targets, stage)
                if target then
                    target = EHR_BodyTempApplyMedicationFeverRelief(player, diseaseId, target)
                    bestTarget = math.max(bestTarget or target, target)
                end
            end
        end
    end

    local sepsis = modData.EHR_Sepsis
    local sepsisStage = sepsis and tonumber(sepsis.stage) or 0
    if sepsisStage > 0 then
        local target = EHR_BodyTempGetStageTarget(EHR.BodyTemp.DiseaseFeverTargets.sepsis, sepsisStage)
        if target then
            target = EHR_BodyTempApplyMedicationFeverRelief(player, "sepsis", target)
            bestTarget = math.max(bestTarget or target, target)
        end
    end

    local woundData = modData.EHR_WoundInfection
    local woundStage = woundData and tonumber(woundData.worstStage) or 0
    if woundStage > 0 then
        local target = EHR_BodyTempGetStageTarget(EHR.BodyTemp.DiseaseFeverTargets.wound_infection, woundStage)
        if target then
            target = EHR_BodyTempApplyMedicationFeverRelief(player, "wound_infection", target)
            bestTarget = math.max(bestTarget or target, target)
        end
    end

    return bestTarget
end

function EHR.BodyTemp.HasActiveDiseaseFeverSource(player)
    return EHR.BodyTemp.GetActiveDiseaseFeverTarget(player) ~= nil
end

function EHR.BodyTemp.MoveDiseaseFeverToward(player, target, step)
    if not player or not target or not step or step <= 0 then return false end

    local cfg = EHR.BodyTemp.Config
    target = math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, target))

    local vanillaTemp = EHR.BodyTemp.ReadVanillaBodyTemperature and EHR.BodyTemp.ReadVanillaBodyTemperature(player) or nil

    local function moveValue(current)
        current = tonumber(current) or vanillaTemp or target
        if target >= current and vanillaTemp and current < vanillaTemp then
            current = vanillaTemp
        end
        if math.abs(target - current) <= step then return target end
        if current < target then return current + step end
        return current - step
    end

    local tempData = nil
    if EHR.BodyTemp.GetTemperatureData then
        tempData = EHR.BodyTemp.GetTemperatureData(player)
    end
    if not tempData and EHR.BodyTemp.InitializePlayer then
        tempData = EHR.BodyTemp.InitializePlayer(player)
    end

    local nextTemp = nil
    if tempData and tempData.bodyTemp then
        nextTemp = moveValue(tempData.bodyTemp)
        tempData.bodyTemp = nextTemp
        tempData.targetTemp = target
        tempData.diseaseTargetTemp = target
        tempData.diseaseFeverActive = target > ((cfg.normalTemp or 36.6) + 0.2)

        local gameTime = getGameTime and getGameTime() or nil
        tempData.diseaseTargetTempUntil = gameTime and (gameTime:getWorldAgeHours() + 1.0) or nil
    end

    if not nextTemp then
        nextTemp = moveValue(vanillaTemp or target)
    end

    if EHR.BodyTemp.WriteDiseaseBodyTemperature then
        EHR.BodyTemp.WriteDiseaseBodyTemperature(player, nextTemp)
    end

    return nextTemp ~= nil
end

function EHR.BodyTemp.ResetDiseaseFever(player, snapToNormal)
    if not player then return false end

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if not tempData and EHR.BodyTemp.InitializePlayer then
        tempData = EHR.BodyTemp.InitializePlayer(player)
    end
    if not tempData then return false end

    local normalTemp = EHR.BodyTemp.Config.normalTemp or 36.6
    local vanillaTemp = EHR.BodyTemp.ReadVanillaBodyTemperature and EHR.BodyTemp.ReadVanillaBodyTemperature(player) or normalTemp
    tempData.diseaseTargetTemp = nil
    tempData.diseaseTargetTempUntil = nil
    tempData.diseaseFeverActive = false
    tempData.targetTemp = vanillaTemp
    tempData.hotStage = 0
    tempData.prevHotStage = 0
    tempData.timeAtDangerousTemp = 0
    tempData.dangerZone = nil
    tempData.currentThirstMult = 1.0
    tempData.currentStaminaPenalty = 0

    if snapToNormal ~= false then
        tempData.bodyTemp = normalTemp

        if EHR.BodyTemp.WriteDiseaseBodyTemperature then
            EHR.BodyTemp.WriteDiseaseBodyTemperature(player, normalTemp)
        end
    else
        tempData.bodyTemp = vanillaTemp
    end

    if EHR.BodyTemp.ResetVanillaSuppression then
        EHR.BodyTemp.ResetVanillaSuppression()
    end

    return true
end

function EHR.BodyTemp.ResetDiseaseFeverIfStale(player, snapToNormal)
    if EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player) then
        return false
    end

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if not tempData or (not tempData.diseaseTargetTemp and not tempData.diseaseFeverActive) then
        return false
    end

    return EHR.BodyTemp.ResetDiseaseFever(player, snapToNormal)
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

--[[
    Check if player is currently exerting (sprinting, in combat, etc.)
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.BodyTemp.IsExerting(player)
    if not player then return false end

    -- Check sprint
    if player:isSprinting() then return true end

    -- Check if in combat (swinging weapon)
    if player:isDoShove() then return true end

    -- Check if running (not walking)
    if player:isRunning() then return true end

    -- Check stamina drain as proxy for exertion
    local stats = player:getStats()
    if stats then
        local endurance = 1.0
        if CharacterStat and CharacterStat.ENDURANCE then
            local success, val = pcall(function() return stats:get(CharacterStat.ENDURANCE) end)
            if success and val then endurance = val end
        end
        -- If endurance is draining significantly, player is exerting
        if endurance < 0.7 then return true end
    end

    return false
end

--[[
    Read the vanilla Thermoregulator's continuous metabolic heat value.

    Heat Generation in the vanilla temperature panel is based on
    metabolicRateReal (MET), not only on whether the player is running. EHR
    owns core temperature while Indoor Climate Lite is active, so the same
    value must be folded into EHR's target temperature or activity heat is
    otherwise lost.

    @param player (IsoPlayer)
    @return table - available, rate, ui, normalizedLoad, targetShift
]]--
function EHR.BodyTemp.GetMetabolicHeatState(player)
    local cfg = EHR.BodyTemp.Config
    local restingRate = tonumber(cfg.metabolicRestingRate) or 1.5
    local maximumRate = math.max(restingRate + 0.1, tonumber(cfg.metabolicMaxRate) or 10.3)
    local state = {
        available = false,
        rate = nil,
        ui = nil,
        normalizedLoad = 0,
        targetShift = 0,
        source = "Unavailable",
    }
    if not player then return state end

    pcall(function()
        local bodyDamage = player:getBodyDamage()
        local thermoregulator = bodyDamage and bodyDamage:getThermoregulator() or nil
        if not thermoregulator then return end

        if thermoregulator.getMetabolicRateReal then
            state.rate = tonumber(thermoregulator:getMetabolicRateReal())
            state.source = state.rate and "MetabolicRateReal" or state.source
        elseif thermoregulator.getHeatGeneration then
            state.rate = tonumber(thermoregulator:getHeatGeneration())
            state.source = state.rate and "HeatGeneration" or state.source
        end

        if thermoregulator.getHeatGenerationUI then
            state.ui = tonumber(thermoregulator:getHeatGenerationUI())
        end
    end)

    -- B42 exposes the real MET value, but invert the vanilla UI mapping as a
    -- compatibility fallback in case a later build exposes only the bar value.
    if not state.rate and state.ui then
        local ui = math.max(0, math.min(1, state.ui))
        if ui < 0.5 then
            state.rate = (ui / 0.5) * restingRate
        else
            state.rate = restingRate + (((ui - 0.5) / 0.5) * (maximumRate - restingRate))
        end
        state.source = "HeatGenerationUI"
    end

    local rate = tonumber(state.rate)
    if not rate then return state end

    rate = math.max(0, math.min(maximumRate, rate))
    state.rate = rate
    state.available = true

    if rate >= restingRate then
        state.normalizedLoad = math.max(
            0,
            math.min(1, (rate - restingRate) / (maximumRate - restingRate))
        )
        state.targetShift = state.normalizedLoad * (tonumber(cfg.metabolicMaxTargetShift) or 2.4)
    else
        local sleepingRate = 0.8
        local restingSpan = math.max(0.1, restingRate - sleepingRate)
        local restingDeficit = math.max(0, math.min(1, (restingRate - rate) / restingSpan))
        state.normalizedLoad = -restingDeficit
        state.targetShift = -restingDeficit * (tonumber(cfg.metabolicSleepTargetShift) or 0.2)
    end

    return state
end

--[[
    Check if player is dehydrated.
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.BodyTemp.IsDehydrated(player)
    if not player then return false end

    local stats = player:getStats()
    if not stats then return false end

    if CharacterStat and CharacterStat.THIRST then
        local success, thirst = pcall(function() return stats:get(CharacterStat.THIRST) end)
        if success and thirst and thirst > 0.5 then
            return true
        end
    end

    return false
end

function EHR.BodyTemp.IsDiseaseFeverActive(player, tempData)
    if not player then return false end

    local cfg = EHR.BodyTemp.Config
    local normalTemp = cfg.normalTemp or 36.6
    local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)

    if tempData and tempData.diseaseTargetTemp and hasFeverSource then
        local gameTime = getGameTime and getGameTime() or nil
        local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
        local untilHour = tonumber(tempData.diseaseTargetTempUntil)
        local targetTemp = tonumber(tempData.diseaseTargetTemp) or normalTemp

        if (not untilHour or untilHour >= currentHour) and targetTemp > normalTemp + 0.2 then
            return true
        end
    end

    if hasFeverSource then
        return true
    end

    return false
end

--[[
    Get clothing insulation value (0-1 scale).
    Higher = more insulation from cold AND heat.
    @param player (IsoPlayer)
    @return number
]]--
function EHR.BodyTemp.GetClothingInsulation(player)
    if not player then return 0 end

    local insulation = 0
    local wornItems = player:getWornItems()

    if wornItems then
        local count = wornItems:size()
        for i = 0, count - 1 do
            local item = wornItems:getItemByIndex(i)
            if item then
                local itemInsulation = 0.08  -- Base value per clothing piece (buffed from 0.05)

                -- Try to get actual insulation value from item if available
                local scriptItem = item:getScriptItem()
                if scriptItem then
                    -- Check for insulation property (some items have this)
                    local success, value = pcall(function()
                        return scriptItem:getInsulation()
                    end)
                    if success and value and value > 0 then
                        itemInsulation = value * 0.6  -- Scale it appropriately (buffed from 0.5)
                    end
                end

                -- Body location-based insulation bonuses (BUFFED ~50-60%)
                local location = item:getBodyLocation()
                if location then
                    local loc = tostring(location)

                    -- Major coverage areas (torso) provide most warmth
                    if loc == "Jacket" or loc == "JacketHat" or loc == "JacketHat_Bulky" then
                        itemInsulation = itemInsulation + 0.40  -- buffed from 0.25
                    elseif loc == "Sweater" or loc == "SweaterHat" then
                        itemInsulation = itemInsulation + 0.32  -- buffed from 0.20
                    elseif loc == "TorsoExtra" or loc == "TorsoExtraVest" then
                        itemInsulation = itemInsulation + 0.24  -- buffed from 0.15
                    elseif loc == "Tshirt" or loc == "Shirt" then
                        itemInsulation = itemInsulation + 0.16  -- buffed from 0.10

                    -- Leg coverage
                    elseif loc == "Pants" or loc == "Legs1" then
                        itemInsulation = itemInsulation + 0.20  -- buffed from 0.12
                    elseif loc == "Skirt" or loc == "Legs5" then
                        itemInsulation = itemInsulation + 0.10  -- buffed from 0.06

                    -- Head and extremities (important for heat loss prevention)
                    elseif loc == "Hat" or loc == "FullHat" or loc == "MaskFull" then
                        itemInsulation = itemInsulation + 0.14  -- buffed from 0.08
                    elseif loc == "MaskEyes" or loc == "Mask" then
                        itemInsulation = itemInsulation + 0.05  -- buffed from 0.03

                    -- Footwear
                    elseif loc == "Shoes" then
                        itemInsulation = itemInsulation + 0.10  -- buffed from 0.06

                    -- Gloves
                    elseif loc == "Hands" or loc == "HandsLeft" or loc == "HandsRight" then
                        itemInsulation = itemInsulation + 0.08  -- buffed from 0.05

                    -- Full body suits
                    elseif loc == "FullSuit" or loc == "FullSuitHead" or loc == "Boilersuit" then
                        itemInsulation = itemInsulation + 0.45  -- buffed from 0.25

                    -- Socks and underwear (minor)
                    elseif loc == "Socks" then
                        itemInsulation = itemInsulation + 0.05  -- buffed from 0.03
                    elseif loc == "Underwear" or loc == "UnderwearTop" or loc == "UnderwearBottom" then
                        itemInsulation = itemInsulation + 0.04  -- buffed from 0.02
                    end
                end

                insulation = insulation + itemInsulation
            end
        end
    end

    -- Cap at 0.95 (buffed from 0.9 - good winter gear can nearly fully insulate)
    return math.min(0.95, insulation)
end

-- ============================================
-- STAGE CALCULATION
-- ============================================

--[[
    Get cold stage (0-4) based on body temperature with hysteresis.
    @param bodyTemp (number) - Body temperature in Celsius
    @param player (IsoPlayer) - Optional player for state tracking
    @return number
]]--
function EHR.BodyTemp.GetColdStage(bodyTemp, player)
    local cfg = EHR.BodyTemp.Config
    local hyst = cfg.stageHysteresis or 0.3

    -- Get player state cache
    local playerID = player and player:getUsername() or "default"
    if not playerTempStates[playerID] then
        playerTempStates[playerID] = {coldStage = 0, hotStage = 0}
    end
    local currentStage = playerTempStates[playerID].coldStage

    -- Calculate new stage with hysteresis
    local newStage = currentStage

    if currentStage == 0 then
        -- Normal -> Chilly requires crossing threshold
        if bodyTemp < cfg.coldStage1 then newStage = 1 end
    elseif currentStage == 1 then
        -- Chilly -> Normal requires going ABOVE threshold + hysteresis
        if bodyTemp > cfg.coldStage1 + hyst then newStage = 0
        elseif bodyTemp < cfg.coldStage2 then newStage = 2 end
    elseif currentStage == 2 then
        if bodyTemp > cfg.coldStage2 + hyst then newStage = 1
        elseif bodyTemp < cfg.coldStage3 then newStage = 3 end
    elseif currentStage == 3 then
        if bodyTemp > cfg.coldStage3 + hyst then newStage = 2
        elseif bodyTemp < cfg.coldStage4 then newStage = 4 end
    elseif currentStage == 4 then
        if bodyTemp > cfg.coldStage4 + hyst then newStage = 3 end
    end

    playerTempStates[playerID].coldStage = newStage
    return newStage
end

--[[
    Get hot stage (0-4) based on body temperature with hysteresis.
    @param bodyTemp (number) - Body temperature in Celsius
    @param player (IsoPlayer) - Optional player for state tracking
    @return number
]]--
function EHR.BodyTemp.GetHotStage(bodyTemp, player)
    local cfg = EHR.BodyTemp.Config
    local hyst = cfg.stageHysteresis or 0.3

    -- Get player state cache
    local playerID = player and player:getUsername() or "default"
    if not playerTempStates[playerID] then
        playerTempStates[playerID] = {coldStage = 0, hotStage = 0}
    end
    local currentStage = playerTempStates[playerID].hotStage

    -- Calculate new stage with hysteresis
    local newStage = currentStage

    if currentStage == 0 then
        if bodyTemp > cfg.hotStage1 then newStage = 1 end
    elseif currentStage == 1 then
        if bodyTemp < cfg.hotStage1 - hyst then newStage = 0
        elseif bodyTemp > cfg.hotStage2 then newStage = 2 end
    elseif currentStage == 2 then
        if bodyTemp < cfg.hotStage2 - hyst then newStage = 1
        elseif bodyTemp > cfg.hotStage3 then newStage = 3 end
    elseif currentStage == 3 then
        if bodyTemp < cfg.hotStage3 - hyst then newStage = 2
        elseif bodyTemp > cfg.hotStage4 then newStage = 4 end
    elseif currentStage == 4 then
        if bodyTemp < cfg.hotStage4 - hyst then newStage = 3 end
    end

    playerTempStates[playerID].hotStage = newStage
    return newStage
end

-- ============================================
-- TEMPERATURE CALCULATION
-- ============================================

--[[
    Calculate target body temperature based on environment.
    @param player (IsoPlayer)
    @return number - Target body temperature in Celsius
]]--
function EHR.BodyTemp.CalculateTargetTempLegacy(player)
    if not player then return EHR.BodyTemp.Config.normalTemp end

    local cfg = EHR.BodyTemp.Config
    local BASE_TEMP = cfg.normalTemp  -- 36.6°C

    -- Get environmental factors
    local airTemp = 15  -- Default moderate
    if EHR.Environmental and EHR.Environmental.GetAirTemperature then
        airTemp = EHR.Environmental.GetAirTemperature(player)
    end

    local wetness = 0
    if EHR.Environmental and EHR.Environmental.GetWetness then
        wetness = EHR.Environmental.GetWetness(player)
    end

    local isIndoors = false
    if EHR.Environmental and EHR.Environmental.IsIndoors then
        isIndoors = EHR.Environmental.IsIndoors(player)
    end

    local isNearHeat = false
    if EHR.Environmental and EHR.Environmental.IsNearHeat then
        isNearHeat = EHR.Environmental.IsNearHeat(player)
    end

    local isExerting = EHR.BodyTemp.IsExerting(player)
    local clothingInsulation = EHR.BodyTemp.GetClothingInsulation(player)

    -- Calculate effective air temperature (shelter modifies extreme temps)
    local effectiveAirTemp = airTemp

    -- Indoors provides shelter - effective temp is warmer in cold, cooler in heat
    if isIndoors then
        local shelterBaseTemp = 15  -- Buildings maintain ~15°C minimum without heating
        if airTemp < shelterBaseTemp then
            -- Cold weather: effective indoor temp is much warmer
            effectiveAirTemp = shelterBaseTemp - (shelterBaseTemp - airTemp) * 0.2
        elseif airTemp > 28 then
            -- Hot weather: indoor is cooler (shade effect)
            effectiveAirTemp = 28 + (airTemp - 28) * 0.5
        end

        if EHR.DEBUG then
            EHR.Log(string.format("BodyTemp: Indoor effective temp: outdoor=%.1f°C, effective=%.1f°C", airTemp, effectiveAirTemp))
        end
    end

    -- Apply clothing insulation to expand effective comfort zone
    -- Good clothing expands the range where player feels comfortable
    -- Multiplier 25 allows max gear (0.95) to extend comfort to about -14°C
    local effectiveComfortMin = cfg.comfortZoneMin - (clothingInsulation * 25)  -- Can push comfort down by up to ~24°C
    effectiveComfortMin = cfg.comfortZoneMin - (clothingInsulation * 8)
    local effectiveComfortMax = cfg.comfortZoneMax + (clothingInsulation * 5)   -- Less effect on heat (clothing makes you hotter)

    -- Debug logging
    if EHR.DEBUG then
        EHR.Log(string.format("BodyTemp: Comfort zone: %.1f-%.1f°C (base: %.1f-%.1f), insulation=%.2f, effectiveAir=%.1f°C",
            effectiveComfortMin, effectiveComfortMax, cfg.comfortZoneMin, cfg.comfortZoneMax, clothingInsulation, effectiveAirTemp))
    end

    -- Calculate temperature deviation from comfort zone
    -- Within comfort zone = no deviation (body maintains 37°C easily)
    local tempDeviation = 0
    if effectiveAirTemp < effectiveComfortMin then
        -- Too cold - calculate how far below comfort zone
        tempDeviation = effectiveAirTemp - effectiveComfortMin
    elseif effectiveAirTemp > effectiveComfortMax then
        -- Too hot - calculate how far above comfort zone
        tempDeviation = effectiveAirTemp - effectiveComfortMax
    end
    -- else: within comfort zone, no deviation

    -- Body resists environmental changes, but extreme temps still affect you
    -- At 0.09, even max gear at -25°C will slowly make you chilly
    -- This creates realistic "you can survive but not thrive" in extreme cold
    if effectiveAirTemp < (cfg.comfortZoneMin or 10.0) then
        local coldExposure = (cfg.comfortZoneMin or 10.0) - effectiveAirTemp
        local coldProtection = math.min(0.65, math.max(0, clothingInsulation) * 0.45)
        local wetMult = 1.0
        if wetness > 0.3 then
            wetMult = 1 + (wetness * 1.75)
        end
        tempDeviation = -(coldExposure * (1 - coldProtection) * wetMult)
    end

    local resistanceFactor = cfg.heatPressureFactor or 0.09
    if tempDeviation < 0 then
        resistanceFactor = cfg.coldPressureFactor or 0.20
    end
    local envShift = tempDeviation * resistanceFactor

    -- Wetness amplifies cooling in cold weather (evaporative heat loss)
    if false and wetness > 0.3 and effectiveAirTemp < effectiveComfortMin then
        local wetMult = 1 + (wetness * 2.0)  -- Up to 3x cooling when wet and cold
        envShift = envShift * wetMult
    end

    -- Wetness slightly helps in hot weather (sweating works better)
    if wetness > 0.3 and effectiveAirTemp > effectiveComfortMax then
        local wetMult = 1 - (wetness * 0.3)  -- Up to 30% less heating when wet
        if envShift > 0 then
            envShift = envShift * wetMult
        end
    end

    -- Heat source provides warming
    if isNearHeat then
        -- Greatly reduce any cooling effect
        if envShift < 0 then
            envShift = envShift * 0.15  -- 85% reduction in cooling near heat
        end
        -- Ensure minimum positive shift near heat (gentle warming)
        if envShift < 0.15 then
            envShift = 0.15
        end
    end

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if tempData then
        tempData.environmentColdPressure = (not isNearHeat) and effectiveAirTemp < (cfg.comfortZoneMin or 10.0)
        tempData.lastEffectiveAirTemp = effectiveAirTemp
        tempData.lastEffectiveComfortMin = effectiveComfortMin
    end

    -- Exertion generates metabolic heat
    if isExerting then
        envShift = envShift + 0.3  -- +0.3°C from activity (reduced from 0.4)
    end

    -- Clothing reduces heat gain in hot weather (makes it harder to cool down)
    -- but we already accounted for cold protection via expanded comfort zone
    if envShift > 0 and clothingInsulation > 0.3 then
        -- Heavy clothing makes you hotter faster in the heat
        local heatTrappingFactor = 1 + (clothingInsulation * 0.5)
        envShift = envShift * heatTrappingFactor
    end

    -- Calculate final target
    local targetTemp = BASE_TEMP + envShift

    -- Clamp to survivable range
    return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, targetTemp))
end

-- Temperature model v2.
-- Uses local character air temperature when B42 exposes it, then applies a
-- simple heat-balance model. Clothing mitigates cold/heat pressure; it no
-- longer expands the comfort zone so far that body temp gets stuck on a
-- 36C plateau. At ordinary indoor temperatures the target returns to 37C.
function EHR.BodyTemp.CalculateTargetTemp(player)
    if not player then return EHR.BodyTemp.Config.normalTemp end

    local cfg = EHR.BodyTemp.Config
    local normalTemp = cfg.normalTemp or 36.6
    local ambientTemp = nil
    local usedCharacterAir = false
    local usedRealisticTemperatureAir = false
    local usedIndoorClimateLiteAir = false
    local runtimeEnvironment = nil

    if EHR.BodyTemp.IsRealisticTemperatureActive and EHR.BodyTemp.IsRealisticTemperatureActive() then
        local rt = _G and _G.RC_TempSim or nil
        if rt and type(rt.getSimulatedTemperatureSample) == "function" then
            local ok, sample = pcall(function()
                return rt.getSimulatedTemperatureSample(player, { consumer = "ehr_body" })
            end)
            if ok and type(sample) == "table" then
                ambientTemp = tonumber(sample.airC)
            end
        end
        if not ambientTemp and rt and type(rt.getSimulatedTemperatureForPlayer) == "function" then
            local ok, temp = pcall(function()
                return rt.getSimulatedTemperatureForPlayer(player)
            end)
            if ok then
                ambientTemp = tonumber(temp)
            end
        end
        if ambientTemp then
            usedCharacterAir = true
            usedRealisticTemperatureAir = true
        end
    end

    if not ambientTemp and EHR.BodyTemp.GetIndoorClimateLiteEnvironment then
        runtimeEnvironment = EHR.BodyTemp.GetIndoorClimateLiteEnvironment(player)
        if runtimeEnvironment then
            ambientTemp = tonumber(runtimeEnvironment.airTemp)
            usedCharacterAir = ambientTemp ~= nil
            usedIndoorClimateLiteAir = ambientTemp ~= nil
        end
    end

    local climate = getClimateManager and getClimateManager() or nil
    if not ambientTemp and climate and climate.getAirTemperatureForCharacter then
        local ok, temp = pcall(function()
            return climate:getAirTemperatureForCharacter(player, false)
        end)
        if ok and temp then
            ambientTemp = tonumber(temp)
            usedCharacterAir = ambientTemp ~= nil
        end
    end

    if not ambientTemp and EHR.Environmental and EHR.Environmental.GetAirTemperature then
        ambientTemp = tonumber(EHR.Environmental.GetAirTemperature(player))
    end
    ambientTemp = ambientTemp or 15.0

    local isIndoors = false
    if runtimeEnvironment then
        isIndoors = runtimeEnvironment.isIndoors == true
    elseif EHR.Environmental and EHR.Environmental.IsIndoors then
        isIndoors = EHR.Environmental.IsIndoors(player)
    end

    -- Fallback shelter approximation is only used when the character-aware
    -- climate API is unavailable.
    if isIndoors and not usedCharacterAir then
        if ambientTemp < 18.0 then
            ambientTemp = 18.0 + ((ambientTemp - 18.0) * 0.20)
        elseif ambientTemp > 28.0 then
            ambientTemp = 28.0 + ((ambientTemp - 28.0) * 0.45)
        end
    end

    local wetness = 0
    if runtimeEnvironment and tonumber(runtimeEnvironment.wetness) then
        wetness = tonumber(runtimeEnvironment.wetness) or 0
    elseif EHR.Environmental and EHR.Environmental.GetWetness then
        wetness = tonumber(EHR.Environmental.GetWetness(player)) or 0
    end
    wetness = math.max(0, math.min(1, wetness))

    local isNearHeat = false
    if runtimeEnvironment then
        isNearHeat = runtimeEnvironment.isNearHeat == true
    elseif EHR.Environmental and EHR.Environmental.IsNearHeat then
        isNearHeat = EHR.Environmental.IsNearHeat(player)
    end

    local isExerting = EHR.BodyTemp.IsExerting(player)
    local metabolicState = EHR.BodyTemp.GetMetabolicHeatState(player)
    local clothingInsulation = math.max(0, math.min(1, EHR.BodyTemp.GetClothingInsulation(player) or 0))

    local coldComfort = 18.0
    local heatComfort = 28.0
    local targetTemp = normalTemp
    local coldPressure = 0
    local heatPressure = 0
    local clothingHeatBurden = 0

    if ambientTemp < coldComfort then
        local exposure = coldComfort - ambientTemp
        local clothingProtection = math.min(0.70, clothingInsulation * 0.55)
        local wetPenalty = wetness > 0.15 and (1 + wetness * 1.6) or 1
        coldPressure = exposure * (1 - clothingProtection) * wetPenalty
        targetTemp = targetTemp - (coldPressure * 0.33)
    elseif ambientTemp > heatComfort then
        local exposure = ambientTemp - heatComfort
        local clothingHeatPenalty = 1 + (clothingInsulation * 0.45)
        local wetCooling = wetness > 0.2 and (1 - math.min(0.30, wetness * 0.25)) or 1
        heatPressure = exposure * clothingHeatPenalty * wetCooling
        targetTemp = targetTemp + (heatPressure * 0.20)
    end

    -- Heavy insulated clothing traps heat even before the weather is formally
    -- "hot". This is what makes full winter gear uncomfortable at 22-25C while
    -- still avoiding instant heat stroke from standing still in mild weather.
    if ambientTemp >= 20.0 and clothingInsulation > 0.35 then
        local insulationLoad = math.min(1.0, (clothingInsulation - 0.35) / 0.65)
        local warmAirLoad = math.min(1.35, math.max(0, (ambientTemp - 20.0) / 10.0))
        local wetCooling = wetness > 0.2 and (1 - math.min(0.35, wetness * 0.30)) or 1
        clothingHeatBurden = insulationLoad * (0.35 + (warmAirLoad * 0.75)) * wetCooling
        if isIndoors and ambientTemp < heatComfort then
            clothingHeatBurden = clothingHeatBurden * 0.75
        end
        targetTemp = targetTemp + clothingHeatBurden
    end

    local metabolicHeatShift = 0
    if metabolicState and metabolicState.available then
        metabolicHeatShift = tonumber(metabolicState.targetShift) or 0
    elseif isExerting then
        -- Compatibility fallback for a game build without Thermoregulator
        -- access. Do not add this on top of the real vanilla heat value.
        metabolicHeatShift = 0.25
    end
    targetTemp = targetTemp + metabolicHeatShift

    if isNearHeat then
        targetTemp = math.max(targetTemp, normalTemp + 0.25)
    end

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if tempData then
        tempData.environmentColdPressure = coldPressure > 0.05
            and not isNearHeat
            and targetTemp < normalTemp - 0.05
        tempData.environmentHeatPressure = targetTemp > normalTemp + 0.05
            and (heatPressure > 0.05 or clothingHeatBurden > 0.05 or metabolicHeatShift > 0.05)
        tempData.lastEffectiveAirTemp = ambientTemp
        tempData.lastEffectiveComfortMin = coldComfort
        tempData.lastClothingInsulation = clothingInsulation
        tempData.lastClothingHeatBurden = clothingHeatBurden
        tempData.lastMetabolicRate = metabolicState and tonumber(metabolicState.rate) or nil
        tempData.lastHeatGenerationUI = metabolicState and tonumber(metabolicState.ui) or nil
        tempData.lastMetabolicLoad = metabolicState and tonumber(metabolicState.normalizedLoad) or 0
        tempData.lastMetabolicHeatShift = metabolicHeatShift
        tempData.lastMetabolicHeatSource = metabolicState and metabolicState.source or "ExertionFallback"
        tempData.lastUsedCharacterAirTemp = usedCharacterAir
        tempData.lastUsedRealisticTemperatureAir = usedRealisticTemperatureAir
        tempData.lastUsedIndoorClimateLiteAir = usedIndoorClimateLiteAir
        tempData.lastTemperatureSource = usedRealisticTemperatureAir
            and "RealisticTemperature"
            or (usedIndoorClimateLiteAir and "IndoorClimateLite" or "ClimateManager")
        tempData.lastIndoorClimateLiteTarget = runtimeEnvironment
            and tonumber(runtimeEnvironment.iclTargetAirTemp)
            or nil
        tempData.lastIndoorClimateLiteOutdoor = runtimeEnvironment
            and tonumber(runtimeEnvironment.iclOutdoorAirTemp)
            or nil
        tempData.lastIndoorClimateLiteLeak = runtimeEnvironment
            and tonumber(runtimeEnvironment.iclLeakScore)
            or nil
    end

    return math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, targetTemp))
end

--[[
    Calculate temperature change rate.
    @param currentTemp (number)
    @param targetTemp (number)
    @return number - Change in °C to apply
]]--
function EHR.BodyTemp.CalculateChangeRate(currentTemp, targetTemp, deltaHours)
    local cfg = EHR.BodyTemp.Config
    local speedMult = EHR.BodyTemp.GetSpeedMultiplier()

    local diff = targetTemp - currentTemp
    if math.abs(diff) < 0.01 then return 0 end

    -- Larger differences change slightly faster (but not linearly)
    local magnitudeMod = math.sqrt(math.abs(diff)) * 0.5 + 0.5

    -- Base rate per hour, adjusted for delta time
    local rate = cfg.baseChangeRate * magnitudeMod * speedMult * deltaHours

    -- Direction
    if diff < 0 then rate = -rate end

    -- Don't overshoot target
    if math.abs(rate) > math.abs(diff) then
        return diff
    end

    return rate
end

-- ============================================
-- VANILLA HEAT-BALANCE ADAPTER
-- ============================================

-- Vanilla already calculates metabolic heat, per-body-part clothing coverage,
-- holes, garment/body wetness, wind resistance and physiological responses.
-- ICL only needs to replace the environmental-air part of that balance.
local vanillaHeatAdapterStates = setmetatable({}, { __mode = "k" })
local VANILLA_ADAPTER_NODE_REFRESH_TICKS = 6
local VANILLA_ADAPTER_AIR_EPSILON = 0.01

local function EHR_BodyTempSafeMethodNumber(object, methodName)
    if not object then return nil end
    local okMethod, method = pcall(function() return object[methodName] end)
    if not okMethod or not method then return nil end

    local ok, value = pcall(method, object)
    value = ok and tonumber(value) or nil
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function EHR_BodyTempGetThermoregulator(player)
    if not player or not player.getBodyDamage then return nil end

    local ok, thermo = pcall(function()
        local bodyDamage = player:getBodyDamage()
        return bodyDamage and bodyDamage:getThermoregulator() or nil
    end)
    if not ok then return nil end
    return thermo
end

local function EHR_BodyTempIsDedicatedServer()
    return isServer and isServer()
        and not (isClient and isClient())
end

-- Reproduces the environmental part of B42 Thermoregulator.updateNodesHeatDelta.
-- The remaining node terms and metabolic heat are kept from vanilla's
-- getDbg_totalHeat(), so this must only be used as a difference calculation.
function EHR.BodyTemp.CalculateVanillaNodeEnvironmentalHeat(node, airTemp, airAndWindTemp)
    if not node then return nil end

    local skinTemp = EHR_BodyTempSafeMethodNumber(node, "getSkinCelcius")
    local skinSurface = EHR_BodyTempSafeMethodNumber(node, "getSkinSurface")
    local insulation = EHR_BodyTempSafeMethodNumber(node, "getInsulation")
    local windResistance = EHR_BodyTempSafeMethodNumber(node, "getWindresist")
    local bodyWetness = EHR_BodyTempSafeMethodNumber(node, "getBodyWetness")
    airTemp = tonumber(airTemp)
    airAndWindTemp = tonumber(airAndWindTemp) or airTemp

    if not skinTemp or not skinSurface or not insulation
            or not windResistance or not bodyWetness or not airTemp then
        return nil
    end

    insulation = math.max(0, insulation)
    windResistance = math.max(0, windResistance)
    bodyWetness = math.max(0, math.min(1, bodyWetness))

    local externalTemp = airTemp
    if airAndWindTemp < airTemp then
        externalTemp = airTemp
            - ((airTemp - airAndWindTemp) / (1 + windResistance))
    end

    local heatDelta = externalTemp - skinTemp
    if heatDelta < 0 then
        heatDelta = heatDelta * (1 + (0.75 * bodyWetness))
    else
        heatDelta = heatDelta / (1 + (3.0 * bodyWetness))
    end

    return heatDelta * 0.3 / (1 + insulation) * skinSurface
end

local function EHR_BodyTempCalculateAmbientCorrection(thermo, vanillaAir, vanillaWindAir, desiredAir, desiredWindAir)
    local nodeCount = EHR_BodyTempSafeMethodNumber(thermo, "getNodeSize")
    if not nodeCount then return nil end

    nodeCount = math.max(0, math.floor(nodeCount))
    local vanillaEnvironmentalHeat = 0
    local desiredEnvironmentalHeat = 0

    for index = 0, nodeCount - 1 do
        local okNode, node = pcall(function() return thermo:getNode(index) end)
        if not okNode or not node then return nil end

        local vanillaNodeHeat = EHR.BodyTemp.CalculateVanillaNodeEnvironmentalHeat(
            node, vanillaAir, vanillaWindAir
        )
        local desiredNodeHeat = EHR.BodyTemp.CalculateVanillaNodeEnvironmentalHeat(
            node, desiredAir, desiredWindAir
        )
        if vanillaNodeHeat == nil or desiredNodeHeat == nil then return nil end

        vanillaEnvironmentalHeat = vanillaEnvironmentalHeat + vanillaNodeHeat
        desiredEnvironmentalHeat = desiredEnvironmentalHeat + desiredNodeHeat
    end

    return desiredEnvironmentalHeat - vanillaEnvironmentalHeat,
        vanillaEnvironmentalHeat,
        desiredEnvironmentalHeat,
        nodeCount
end

local function EHR_BodyTempGetAdapterState(player)
    local state = vanillaHeatAdapterStates[player]
    if not state then
        state = {
            refreshTick = VANILLA_ADAPTER_NODE_REFRESH_TICKS,
            ambientCorrection = 0,
            warnings = {},
        }
        vanillaHeatAdapterStates[player] = state
    end
    return state
end

local function EHR_BodyTempAdapterWarnOnce(state, key, message)
    if not state then return end
    state.warnings = state.warnings or {}
    if state.warnings[key] then return end
    state.warnings[key] = true

    if EHR and EHR.Log then
        EHR.Log("WARNING: BodyTemp Adapter: " .. tostring(message))
    elseif print then
        print("[EHR] WARNING: BodyTemp Adapter: " .. tostring(message))
    end
end

local function EHR_BodyTempHasActiveFeverSafely(player, tempData)
    if tempData and tempData.diseaseFeverActive == true then return true end
    if not EHR.BodyTemp.HasActiveDiseaseFeverSource then return false end

    local ok, hasFever = pcall(EHR.BodyTemp.HasActiveDiseaseFeverSource, player)
    return ok and hasFever == true
end

local function EHR_BodyTempGetEnvironmentIdentity(environment)
    if type(environment) ~= "table" then return "none" end
    return tostring(
        environment.roomKey
        or environment.iclRoomKey
        or environment.buildingKey
        or environment.iclBuildingKey
        or (environment.isIndoors and "indoors" or "outdoors")
    )
end

function EHR.BodyTemp.GetClientReportedBodyTemperature(player)
    if not EHR_BodyTempIsDedicatedServer()
            or not EHR.Environmental
            or not EHR.Environmental.GetRuntimeEnvironment then
        return nil
    end

    local ok, environment = pcall(EHR.Environmental.GetRuntimeEnvironment, player)
    if not ok or type(environment) ~= "table" then return nil end

    local bodyTemp = tonumber(environment.bodyTempC)
    if not bodyTemp or bodyTemp < 20 or bodyTemp > 42 then return nil end
    return bodyTemp
end

-- Applies one vanilla-sized core-temperature step. This runs every game tick;
-- the expensive 17-node environmental correction is cached for a few ticks.
function EHR.BodyTemp.UpdateVanillaHeatAdapter(player)
    if not player then return false end
    if EHR.BodyTemp.IsRealisticTemperatureActive
            and EHR.BodyTemp.IsRealisticTemperatureActive() then
        return false
    end

    local state = EHR_BodyTempGetAdapterState(player)
    local multiplayerClient = isClient and isClient()
    local dedicatedServer = EHR_BodyTempIsDedicatedServer()
    local environment = EHR.BodyTemp.GetIndoorClimateLiteEnvironment
        and EHR.BodyTemp.GetIndoorClimateLiteEnvironment(player)
        or nil
    if not environment then
        state.missingEnvironmentTicks = (state.missingEnvironmentTicks or 0) + 1
        if state.missingEnvironmentTicks >= 300 then
            EHR_BodyTempAdapterWarnOnce(
                state,
                "missingIndoorClimateSample",
                "the local IndoorClimateLite sample is unavailable; the vanilla adapter is not running"
            )
        end
        return false
    end
    state.missingEnvironmentTicks = 0

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    local thermo = EHR_BodyTempGetThermoregulator(player)
    if not tempData or not thermo then
        if tempData then tempData.vanillaHeatAdapterAvailable = false end
        if tempData and not thermo then
            EHR_BodyTempAdapterWarnOnce(
                state,
                "missingThermoregulator",
                "local Thermoregulator is unavailable; using the compatibility fallback"
            )
        end
        return false
    end

    local totalHeat = EHR_BodyTempSafeMethodNumber(thermo, "getDbg_totalHeat")
    local bodyHeatMultiplier = EHR_BodyTempSafeMethodNumber(thermo, "getBodyHeatMultiplier")
    local vanillaCoreDelta = EHR_BodyTempSafeMethodNumber(thermo, "getCoreHeatDelta")
    local setPoint = EHR_BodyTempSafeMethodNumber(thermo, "getSetPoint")
    local vanillaCore = EHR_BodyTempSafeMethodNumber(thermo, "getCoreTemperature")
        or EHR.BodyTemp.ReadVanillaBodyTemperature(player)
    local vanillaAir = EHR_BodyTempSafeMethodNumber(thermo, "getTemperatureAir")
    local vanillaWindAir = EHR_BodyTempSafeMethodNumber(thermo, "getTemperatureAirAndWind")
        or vanillaAir

    if not totalHeat or not bodyHeatMultiplier or not setPoint
            or not vanillaCore or not vanillaAir then
        tempData.vanillaHeatAdapterAvailable = false
        return false
    end

    -- Some MP clients briefly expose a zero BodyHeatMultiplier while the local
    -- Thermoregulator is being initialized or resynchronized. A zero value
    -- makes an otherwise valid heat balance look permanently frozen. Recover
    -- the multiplier from vanilla's own core delta, or reuse the last valid
    -- local value. If neither exists, let the slower compatibility model run.
    if bodyHeatMultiplier > 0 then
        state.lastPositiveBodyHeatMultiplier = bodyHeatMultiplier
    elseif multiplayerClient then
        -- This value is not used for integration on an MP client. The client
        -- mirrors the server-replicated core and must never replay a serialized
        -- CoreHeatDelta locally.
        bodyHeatMultiplier = tonumber(state.lastPositiveBodyHeatMultiplier) or 0.001
    else
        local derivedMultiplier = nil
        if vanillaCoreDelta
                and math.abs(totalHeat) > 0.000001
                and math.abs(vanillaCoreDelta) > 0.000000001 then
            derivedMultiplier = math.abs(vanillaCoreDelta / totalHeat)
        end

        bodyHeatMultiplier = derivedMultiplier
            or tonumber(state.lastPositiveBodyHeatMultiplier)
        if not bodyHeatMultiplier or bodyHeatMultiplier <= 0 then
            tempData.vanillaHeatAdapterAvailable = false
            EHR_BodyTempAdapterWarnOnce(
                state,
                "zeroBodyHeatMultiplier",
                "MP returned a zero body-heat multiplier; using the compatibility fallback until vanilla initializes it"
            )
            return false
        end
    end

    local desiredAir = tonumber(environment.airTemp) or vanillaAir
    local isIndoors = environment.isIndoors == true

    -- ICL's final air already contains its heaters/fans. Preserve the stronger
    -- native value when EHR positively identifies a lit vanilla heat source.
    if isIndoors and environment.isNearHeat == true and vanillaAir > desiredAir then
        desiredAir = vanillaAir
    end

    local desiredWindAir = vanillaWindAir
    if isIndoors then
        desiredWindAir = desiredAir
    else
        local windChill = math.max(0, vanillaAir - vanillaWindAir)
        desiredWindAir = desiredAir - windChill
    end

    local environmentIdentity = EHR_BodyTempGetEnvironmentIdentity(environment)
    state.refreshTick = (state.refreshTick or 0) + 1

    local airChanged = state.desiredAir == nil
        or math.abs(desiredAir - state.desiredAir) >= VANILLA_ADAPTER_AIR_EPSILON
        or state.vanillaAir == nil
        or math.abs(vanillaAir - state.vanillaAir) >= VANILLA_ADAPTER_AIR_EPSILON
    local environmentChanged = state.environmentIdentity ~= environmentIdentity
    local shouldRefresh = airChanged
        or environmentChanged
        or state.refreshTick >= VANILLA_ADAPTER_NODE_REFRESH_TICKS

    if multiplayerClient then
        -- In B42 MP, CoreHeatDelta is serialized but totalHeat is not. The
        -- client therefore sees a stale server delta alongside totalHeat=0.
        -- All ICL correction is server-owned; the client only mirrors core.
        state.ambientCorrection = 0
        state.vanillaEnvironmentalHeat = nil
        state.desiredEnvironmentalHeat = nil
        state.nodeCount = EHR_BodyTempSafeMethodNumber(thermo, "getNodeSize")
        state.refreshTick = 0
    elseif math.abs(desiredAir - vanillaAir) < VANILLA_ADAPTER_AIR_EPSILON
            and math.abs(desiredWindAir - vanillaWindAir) < VANILLA_ADAPTER_AIR_EPSILON then
        state.ambientCorrection = 0
        state.vanillaEnvironmentalHeat = nil
        state.desiredEnvironmentalHeat = nil
        state.nodeCount = EHR_BodyTempSafeMethodNumber(thermo, "getNodeSize")
        state.refreshTick = 0
    elseif shouldRefresh then
        local correction, vanillaEnvironmentalHeat, desiredEnvironmentalHeat, nodeCount =
            EHR_BodyTempCalculateAmbientCorrection(
                thermo,
                vanillaAir,
                vanillaWindAir,
                desiredAir,
                desiredWindAir
            )
        if correction == nil then
            tempData.vanillaHeatAdapterAvailable = false
            return false
        end

        state.ambientCorrection = correction
        state.vanillaEnvironmentalHeat = vanillaEnvironmentalHeat
        state.desiredEnvironmentalHeat = desiredEnvironmentalHeat
        state.nodeCount = nodeCount
        state.refreshTick = 0
    end

    state.desiredAir = desiredAir
    state.vanillaAir = vanillaAir
    state.environmentIdentity = environmentIdentity

    local ambientCorrection = tonumber(state.ambientCorrection) or 0
    local correctedTotalHeat = totalHeat + ambientCorrection
    local incomingCore = tonumber(tempData.bodyTemp) or vanillaCore
    local hasFeverSource = EHR_BodyTempHasActiveFeverSafely(player, tempData)
    local usesDirectVanillaCore = multiplayerClient and not hasFeverSource

    -- MP periodically replaces EHR_Temperature with the server's ModData table.
    -- Keep the continuously integrated core in client-local state so that a
    -- stale server snapshot cannot reset the calculation every sync. Disease
    -- fever is authoritative and is intentionally allowed to update that state.
    if state.managedCore == nil then
        state.managedCore = dedicatedServer and vanillaCore or incomingCore
    elseif hasFeverSource then
        state.managedCore = incomingCore
    end

    local managedCore = tonumber(state.managedCore) or incomingCore
    local coreDelta = 0
    local coreDeltaSource = "VanillaCore"
    local correctionCoreDelta = 0
    local appliedThermalStep = false

    if usesDirectVanillaCore then
        -- The authoritative server has already applied vanilla metabolism,
        -- clothing and ICL's environmental correction. Mirror its replicated
        -- core and leave vanilla moodles completely untouched.
        managedCore = vanillaCore
        coreDelta = managedCore - (tonumber(state.managedCore) or managedCore)
        appliedThermalStep = true
        coreDeltaSource = "ServerCore"
    else
        coreDelta = correctedTotalHeat * bodyHeatMultiplier

        -- These are the same expansion rules used by vanilla updateHeatDeltas().
        if coreDelta < 0 and managedCore > setPoint then
            coreDelta = coreDelta * (1 + ((managedCore - setPoint) / 2))
        elseif coreDelta > 0 and managedCore < setPoint then
            coreDelta = coreDelta * (1 + ((setPoint - managedCore) / 4))
        end
        coreDeltaSource = "TotalHeat"
        appliedThermalStep = true
    end

    if not usesDirectVanillaCore then
        coreDelta = coreDelta * math.max(0, tonumber(EHR.BodyTemp.GetSpeedMultiplier()) or 1)
        managedCore = math.max(
            EHR.BodyTemp.Config.minBodyTemp or 28.0,
            math.min(EHR.BodyTemp.Config.maxBodyTemp or 42.0, managedCore + coreDelta)
        )
    end

    local warmedCore, warmingApplied, warmingCoreDelta, warmingActive, warmingTarget =
        EHR.BodyTemp.ApplyWarmingPackEffect(player, managedCore)
    if warmingApplied then
        managedCore = warmedCore
        coreDelta = coreDelta + warmingCoreDelta
        coreDeltaSource = coreDeltaSource .. "+WarmingPack"
    end
    state.managedCore = managedCore

    tempData.bodyTemp = managedCore
    tempData.environmentBodyTemp = managedCore
    tempData.environmentTargetTemp = managedCore
    tempData.targetTemp = managedCore
    tempData.environmentManagedBy = "VanillaHeatAdapter"
    tempData.vanillaHeatAdapterAvailable = true
    tempData.lastEffectiveAirTemp = desiredAir
    tempData.lastThermoregulatorAir = vanillaAir
    tempData.lastThermoregulatorWindAir = vanillaWindAir
    tempData.lastVanillaTotalHeat = totalHeat
    tempData.lastAmbientHeatCorrection = tonumber(state.ambientCorrection) or 0
    tempData.lastCorrectedTotalHeat = correctedTotalHeat
    tempData.lastVanillaCoreDelta = vanillaCoreDelta or (totalHeat * bodyHeatMultiplier)
    tempData.lastAmbientCoreDelta = correctionCoreDelta
    tempData.lastAppliedCoreDelta = coreDelta
    tempData.lastCoreDeltaSource = coreDeltaSource
    tempData.warmingPackActive = warmingActive
    tempData.warmingPackTargetTemp = warmingActive and warmingTarget or nil
    tempData.lastWarmingPackCoreDelta = warmingCoreDelta
    tempData.lastAppliedThermalStep = appliedThermalStep
    tempData.lastVanillaEnvironmentalHeat = state.vanillaEnvironmentalHeat
    tempData.lastDesiredEnvironmentalHeat = state.desiredEnvironmentalHeat
    tempData.lastThermalNodeCount = state.nodeCount
    tempData.lastMetabolicRate = EHR_BodyTempSafeMethodNumber(thermo, "getMetabolicRateReal")
    tempData.lastHeatGenerationUI = EHR_BodyTempSafeMethodNumber(thermo, "getHeatGenerationUI")
    tempData.lastUsedIndoorClimateLiteAir = true
    tempData.lastTemperatureSource = isIndoors
        and "IndoorClimateLiteVanillaAdapter"
        or "VanillaThermoregulator"
    -- A listen-server/authoritative process may still enter direct-core mode.
    -- When the pack contributed heat, allow the bridge below to publish that
    -- adjusted core instead of immediately replacing it with the old snapshot.
    tempData.vanillaDirectCore = usesDirectVanillaCore and not warmingApplied

    if multiplayerClient and state.lastLoggedDirectMode ~= usesDirectVanillaCore then
        state.lastLoggedDirectMode = usesDirectVanillaCore
        state.mpSampleTick = 0
        state.mpFollowupLogged = false
        if print then
            print(string.format(
                "[EHR Temperature] MP mode: %s air=%.2f vanillaAir=%.2f ambientHeat=%+.5f core=%.3f",
                usesDirectVanillaCore and "ServerCore" or "LocalFever",
                desiredAir,
                vanillaAir,
                ambientCorrection,
                managedCore
            ))
        end
    end

    if dedicatedServer and not state.serverAdapterLogged then
        state.serverAdapterLogged = true
        if print then
            print(string.format(
                "[EHR Temperature] Server adapter active: air=%.2f vanillaAir=%.2f multiplier=%.8f heat=%+.5f ambientHeat=%+.5f applied=%+.7f core=%.3f",
                desiredAir,
                vanillaAir,
                bodyHeatMultiplier,
                totalHeat,
                ambientCorrection,
                coreDelta,
                managedCore
            ))
        end
    end

    if not state.mpAdapterLogged and multiplayerClient then
        state.mpAdapterLogged = true
        if print then
            print(string.format(
                "[EHR Temperature] MP adapter active: air=%.2f vanillaAir=%.2f multiplier=%.8f heat=%+.5f vanillaDelta=%+.7f corrected=%+.5f source=%s core=%.3f",
                desiredAir,
                vanillaAir,
                bodyHeatMultiplier,
                totalHeat,
                tonumber(vanillaCoreDelta) or 0,
                correctedTotalHeat,
                coreDeltaSource,
                managedCore
            ))
        end
    end

    state.mpSampleTick = (state.mpSampleTick or 0) + 1
    if multiplayerClient
            and not state.mpFollowupLogged
            and state.mpSampleTick >= 300 then
        state.mpFollowupLogged = true
        if print then
            print(string.format(
                "[EHR Temperature] MP adapter sample: air=%.2f vanillaAir=%.2f vanillaCore=%.3f vanillaDelta=%+.7f ambientDelta=%+.7f applied=%+.7f thermalStep=%s source=%s core=%.3f",
                desiredAir,
                vanillaAir,
                vanillaCore,
                tonumber(vanillaCoreDelta) or 0,
                correctionCoreDelta,
                coreDelta,
                tostring(appliedThermalStep),
                coreDeltaSource,
                managedCore
            ))
        end
    end

    state.debugTick = (state.debugTick or 0) + 1
    if EHR.DEBUG and state.debugTick >= 60 then
        state.debugTick = 0
        EHR.Log(string.format(
            "BodyTemp Adapter: %s air=%.2f vanillaAir=%.2f MET=%.2f vanillaHeat=%+.4f airCorrection=%+.4f correctedHeat=%+.4f coreDelta=%+.5f core=%.3f",
            isIndoors and "indoors" or "outdoors",
            desiredAir,
            vanillaAir,
            tonumber(tempData.lastMetabolicRate) or 0,
            totalHeat,
            tonumber(state.ambientCorrection) or 0,
            correctedTotalHeat,
            coreDelta,
            managedCore
        ))
    end

    return true
end

--[[
    Update body temperature for a player.
    @param player (IsoPlayer)
    @param deltaHours (number) - Game hours since last update
]]--
function EHR.BodyTemp.UpdateBodyTemperature(player, deltaHours)
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if not tempData then return end

    local cfg = EHR.BodyTemp.Config
    local vanillaTemp = EHR.BodyTemp.ReadVanillaBodyTemperature(player) or tempData.bodyTemp or cfg.normalTemp
    vanillaTemp = math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, vanillaTemp))

    local oldTemp = tonumber(tempData.bodyTemp) or vanillaTemp
    local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)
    local realisticTemperatureManaged = EHR.BodyTemp.IsRealisticTemperatureActive
        and EHR.BodyTemp.IsRealisticTemperatureActive()
    local indoorClimateEnvironment = nil
    if not realisticTemperatureManaged and EHR.BodyTemp.GetIndoorClimateLiteEnvironment then
        indoorClimateEnvironment = EHR.BodyTemp.GetIndoorClimateLiteEnvironment(player)
    end
    local indoorClimateManaged = indoorClimateEnvironment ~= nil
    local clientReportedTemp = EHR.BodyTemp.GetClientReportedBodyTemperature
        and EHR.BodyTemp.GetClientReportedBodyTemperature(player)
        or nil
    local adapterManaged = tempData.vanillaHeatAdapterAvailable == true
        and tempData.environmentManagedBy == "VanillaHeatAdapter"
    local managedEnvironment = realisticTemperatureManaged
        or indoorClimateManaged
        or clientReportedTemp ~= nil
    local environmentTarget = vanillaTemp

    if realisticTemperatureManaged then
        -- Realistic Temperature owns environmental body heat and core temp.
        -- EHR only mirrors that value here, then layers disease fever on top.
        local rec = nil
        pcall(function()
            local modData = player and player:getModData()
            rec = modData and modData.RC_TempSimBodyTemp or nil
        end)
        if type(rec) == "table" then
            environmentTarget = tonumber(rec._ehrRtBaseCore) or tonumber(rec.core) or vanillaTemp
        end
        environmentTarget = math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, environmentTarget))
        tempData.bodyTemp = environmentTarget
        tempData.environmentManagedBy = "RealisticTemperature"
    elseif adapterManaged then
        -- The per-tick adapter has already applied vanilla metabolic heat plus
        -- ICL's environmental-air correction. This periodic update only handles
        -- fever/stages and must not run the legacy target-temperature model.
        environmentTarget = tonumber(tempData.environmentBodyTemp)
            or tonumber(tempData.bodyTemp)
            or vanillaTemp
        tempData.bodyTemp = environmentTarget
        tempData.environmentManagedBy = "VanillaHeatAdapter"
    elseif clientReportedTemp then
        -- Fallback for the short interval before the dedicated server receives
        -- its first ICL environmental snapshot. Once the server adapter is
        -- active it is authoritative and must not be overwritten by a delayed
        -- client body-temperature report.
        environmentTarget = math.max(
            cfg.minBodyTemp or 28.0,
            math.min(cfg.maxBodyTemp or 42.0, clientReportedTemp)
        )
        tempData.bodyTemp = environmentTarget
        tempData.environmentBodyTemp = environmentTarget
        tempData.environmentManagedBy = "ClientThermoregulator"
        tempData.vanillaHeatAdapterAvailable = false
    elseif indoorClimateManaged then
        -- Compatibility fallback for a build where the Thermoregulator debug
        -- APIs are unavailable. The normal B42 path uses VanillaHeatAdapter.
        environmentTarget = EHR.BodyTemp.CalculateTargetTemp(player)
        environmentTarget = math.max(
            cfg.minBodyTemp or 28.0,
            math.min(cfg.maxBodyTemp or 42.0, tonumber(environmentTarget) or vanillaTemp)
        )
        local environmentalChange = EHR.BodyTemp.CalculateChangeRate(
            oldTemp,
            environmentTarget,
            tonumber(deltaHours) or 0
        )

        -- Metabolic heat rises much faster than passive environmental drift in
        -- vanilla. Scale only upward movement, using the same continuous MET
        -- load that drives the Heat Generation bar. Insulation further traps
        -- activity heat, while cooling after activity retains the normal rate.
        local metabolicLoad = math.max(0, math.min(1, tonumber(tempData.lastMetabolicLoad) or 0))
        local clothingInsulation = math.max(0, math.min(1, tonumber(tempData.lastClothingInsulation) or 0))
        local heatingRateMultiplier = 1.0
        if environmentalChange > 0 and metabolicLoad > 0 then
            local maxMultiplier = math.max(
                1.0,
                tonumber(cfg.metabolicHeatingRateMaxMultiplier) or 4.0
            )
            local clothingBonus = math.max(
                0,
                tonumber(cfg.metabolicClothingRateBonus) or 1.0
            )
            heatingRateMultiplier = 1
                + (metabolicLoad * ((maxMultiplier - 1) + (clothingInsulation * clothingBonus)))
            environmentalChange = math.min(
                environmentTarget - oldTemp,
                environmentalChange * heatingRateMultiplier
            )
        end
        tempData.lastMetabolicHeatingRateMultiplier = heatingRateMultiplier

        tempData.bodyTemp = math.max(
            cfg.minBodyTemp or 28.0,
            math.min(cfg.maxBodyTemp or 42.0, oldTemp + environmentalChange)
        )
        tempData.environmentManagedBy = "IndoorClimateLite"
    else
        -- Without RT compatibility, vanilla owns environmental heating/cooling.
        -- EHR mirrors it for UI and thresholds, and only nudges disease fever.
        tempData.bodyTemp = vanillaTemp
        oldTemp = tonumber(oldTemp) or vanillaTemp
        tempData.environmentManagedBy = "Vanilla"
    end

    local warmedTemp, warmingApplied, warmingDelta, warmingActive, warmingTarget =
        EHR.BodyTemp.ApplyWarmingPackEffect(player, tempData.bodyTemp)
    if warmingApplied then
        tempData.bodyTemp = math.max(
            cfg.minBodyTemp or 28.0,
            math.min(cfg.maxBodyTemp or 42.0, warmedTemp)
        )
    end
    tempData.warmingPackActive = warmingActive
    tempData.warmingPackTargetTemp = warmingActive and warmingTarget or nil
    tempData.lastWarmingPackCoreDelta = warmingDelta

    tempData.environmentTargetTemp = environmentTarget
    tempData.targetTemp = warmingActive and math.max(environmentTarget, warmingTarget) or environmentTarget
    local bodyTemperatureWriteAttempted = false

    if hasFeverSource then
        local gameTime = getGameTime and getGameTime() or nil
        local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
        local keepExistingTarget = tempData.diseaseTargetTemp and (not tempData.diseaseTargetTempUntil or tempData.diseaseTargetTempUntil >= currentHour)

        if not keepExistingTarget then
            local activeTarget = EHR.BodyTemp.GetActiveDiseaseFeverTarget and EHR.BodyTemp.GetActiveDiseaseFeverTarget(player) or nil
            if activeTarget then
                tempData.diseaseTargetTemp = activeTarget
                tempData.diseaseTargetTempUntil = gameTime and (currentHour + 1.0) or tempData.diseaseTargetTempUntil
            end
        end
    else
        tempData.diseaseTargetTemp = nil
        tempData.diseaseTargetTempUntil = nil
        tempData.diseaseFeverActive = false
    end

    if hasFeverSource and tempData.diseaseTargetTemp then
        local diseaseTarget = math.max(
            cfg.minBodyTemp or 28.0,
            math.min(cfg.maxBodyTemp or 42.0, tonumber(tempData.diseaseTargetTemp) or environmentTarget)
        )
        local current = managedEnvironment and (tonumber(tempData.bodyTemp) or oldTemp) or oldTemp
        if diseaseTarget >= environmentTarget and current < environmentTarget then
            current = environmentTarget
        end

        local step = math.max(0.01, (cfg.baseChangeRate or 0.8) * (tonumber(deltaHours) or 0.05))
        if math.abs(diseaseTarget - current) <= step then
            tempData.bodyTemp = diseaseTarget
        elseif current < diseaseTarget then
            tempData.bodyTemp = current + step
        else
            tempData.bodyTemp = current - step
        end

        tempData.bodyTemp = math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, tempData.bodyTemp))
        tempData.targetTemp = diseaseTarget
        tempData.diseaseFeverActive = tempData.bodyTemp > ((cfg.normalTemp or 36.6) + 0.2)

        if EHR.BodyTemp.WriteDiseaseBodyTemperature then
            EHR.BodyTemp.WriteDiseaseBodyTemperature(player, tempData.bodyTemp)
            bodyTemperatureWriteAttempted = true
        end
    elseif realisticTemperatureManaged then
        tempData.bodyTemp = environmentTarget
        tempData.targetTemp = environmentTarget
        tempData.diseaseFeverActive = false
    end

    if (managedEnvironment or warmingApplied)
            and not bodyTemperatureWriteAttempted
            and not (tempData.vanillaDirectCore == true and not hasFeverSource and not warmingApplied)
            and EHR.BodyTemp.WriteDiseaseBodyTemperature then
        EHR.BodyTemp.WriteDiseaseBodyTemperature(player, tempData.bodyTemp)
    end

    -- Update stages (with hysteresis to prevent flickering)
    tempData.prevColdStage = tempData.coldStage
    tempData.prevHotStage = tempData.hotStage
    tempData.coldStage = EHR.BodyTemp.GetColdStage(tempData.bodyTemp, player)
    tempData.diseaseFeverActive = EHR.BodyTemp.IsDiseaseFeverActive(player, tempData)
    tempData.hotStage = EHR.BodyTemp.GetHotStage(tempData.bodyTemp, player)
    if tempData.diseaseFeverActive and (not tempData.environmentTargetTemp or tempData.environmentTargetTemp < cfg.hotStage1) then
        tempData.hotStage = 0
        local playerID = player and player:getUsername() or "default"
        if playerTempStates[playerID] then
            playerTempStates[playerID].hotStage = 0
        end
    end

    local change = (tonumber(tempData.bodyTemp) or 0) - oldTemp
    local targetTemp = tempData.targetTemp or tempData.bodyTemp
    if EHR.DEBUG and math.abs(change) > 0.001 then
        EHR.Log(string.format("BodyTemp: %.2f°C -> %.2f°C (target: %.2f°C, change: %+.3f)",
            oldTemp, tempData.bodyTemp, targetTemp, change))
    end
end

-- ============================================
-- PRE-DISEASE EFFECTS
-- ============================================

--[[
    Apply pre-disease effects based on temperature stage.
    @param player (IsoPlayer)
    @param tempData (table)
]]--
function EHR.BodyTemp.ApplyPreDiseaseEffects(player, tempData)
    if not player or not tempData then return end
    if not EHR.BodyTemp.PreDiseaseEffectsEnabled() then return end

    local currentHour = getGameTime():getWorldAgeHours()
    local cfg = EHR.BodyTemp.Config

    -- Cold effects
    if tempData.coldStage > 0 then
        EHR.BodyTemp.ApplyColdEffects(player, tempData, currentHour)
    else
        tempData.currentMovementPenalty = 0
        tempData.currentFatigueMult = 1.0
    end

    -- Hot effects
    if tempData.hotStage > 0 then
        EHR.BodyTemp.ApplyHotEffects(player, tempData, currentHour)
    else
        tempData.currentThirstMult = 1.0
        tempData.currentStaminaPenalty = 0
    end
end

--[[
    Apply cold-related effects.
]]--
function EHR.BodyTemp.ApplyColdEffects(player, tempData, currentHour)
    local cfg = EHR.BodyTemp.Config
    local stage = tempData.coldStage

    -- Dialogue (with cooldown, uses EHR.Dialogue system for frequency control)
    if currentHour - tempData.lastShiverTime >= cfg.shiverDialogueInterval then
        local dialogues = EHR.BodyTemp.ColdDialogue[stage]
        if dialogues and #dialogues > 0 then
            local dialogueKey = dialogues[ZombRand(#dialogues) + 1]
            local text = getText(dialogueKey) or dialogueKey

            -- Use the dialogue system for frequency control
            local said = false
            if EHR.Dialogue and EHR.Dialogue.SayPeriodic then
                said = EHR.Dialogue.SayPeriodic(player, text, 1)  -- 1 = always (cooldown handles timing)
            else
                -- Fallback if dialogue system not loaded
                EHR.Locale.Say(player, text)
                said = true
            end

            if said then
                tempData.lastShiverTime = currentHour
                if EHR.DEBUG then
                    EHR.Log("BodyTemp: Cold dialogue stage " .. stage .. ": " .. text)
                end
            end
        end
    end

    -- Movement penalty is applied via integration with movement system
    -- For now, we store the penalty value for other systems to read
    tempData.currentMovementPenalty = cfg.coldMovementPenalty[stage] or 0
    tempData.currentFatigueMult = cfg.coldFatigueDrain[stage] or 1.0
end

--[[
    Apply heat-related effects.
]]--
function EHR.BodyTemp.ApplyHotEffects(player, tempData, currentHour)
    local cfg = EHR.BodyTemp.Config
    local stage = tempData.hotStage

    -- Dialogue (with cooldown, uses EHR.Dialogue system for frequency control)
    if currentHour - tempData.lastSweatTime >= cfg.sweatDialogueInterval then
        local dialogues = EHR.BodyTemp.HotDialogue[stage]
        if dialogues and #dialogues > 0 then
            local dialogueKey = dialogues[ZombRand(#dialogues) + 1]
            local text = getText(dialogueKey) or dialogueKey

            -- Use the dialogue system for frequency control
            local said = false
            if EHR.Dialogue and EHR.Dialogue.SayPeriodic then
                said = EHR.Dialogue.SayPeriodic(player, text, 1)  -- 1 = always (cooldown handles timing)
            else
                -- Fallback if dialogue system not loaded
                EHR.Locale.Say(player, text)
                said = true
            end

            if said then
                tempData.lastSweatTime = currentHour
                if EHR.DEBUG then
                    EHR.Log("BodyTemp: Hot dialogue stage " .. stage .. ": " .. text)
                end
            end
        end
    end

    -- Store penalty values for other systems
    tempData.currentThirstMult = cfg.hotThirstDrain[stage] or 1.0
    tempData.currentStaminaPenalty = cfg.hotStaminaPenalty[stage] or 0
end

-- ============================================
-- DISEASE THRESHOLD CHECKS
-- ============================================

--[[
    Check if body temperature has been in danger zone long enough to trigger disease.
    @param player (IsoPlayer)
    @param tempData (table)
]]--
function EHR.BodyTemp.CheckDiseaseThresholds(player, tempData, deltaHours)
    if not player or not tempData then return end

    local cfg = EHR.BodyTemp.Config

    -- Hypothermia is stage-driven by current core temperature.
    EHR.BodyTemp.SyncHypothermiaFromTemperature(player, tempData)

    -- Track the hot danger zone for UI/debug data only. Heat-stroke risk is
    -- handled by heat-exhaustion exposure in EHR_EnvironmentalDiseases.
    if tempData.hotStage >= 4 then
        -- In hot danger zone
        if tempData.dangerZone ~= "hot" then
            tempData.dangerZone = "hot"
            tempData.timeAtDangerousTemp = 0
            if EHR.DEBUG then
                EHR.Log("BodyTemp: Entered hot danger zone (> 40.5°C)")
            end
        end

        tempData.timeAtDangerousTemp = tempData.timeAtDangerousTemp + deltaHours

    elseif tempData.dangerZone == "hot" then
        -- Not in danger zone, reset
        if EHR.DEBUG then
            EHR.Log("BodyTemp: Exited heat danger zone, resetting timer")
        end
        tempData.dangerZone = nil
        tempData.timeAtDangerousTemp = 0
    end
end

--[[
    Attempt to trigger hypothermia disease.
]]--
function EHR.BodyTemp.TryTriggerHypothermia(player, tempData)
    if not EHR.Disease or not EHR.Disease.TryContract then return end

    -- Check if already has hypothermia
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active and diseaseData.active["hypothermia"] then
        return  -- Already have it
    end

    -- Calculate chance based on:
    -- - Time in danger zone (longer = higher)
    -- - Current body temp (lower = higher)
    -- - Wetness (wetter = higher)
    local cfg = EHR.BodyTemp.Config
    local timeRatio = tempData.timeAtDangerousTemp / cfg.hypothermiaTriggerTime
    local tempSeverity = ((cfg.hypothermiaStage1 or 35.0) - tempData.bodyTemp) / 6  -- 0-1 based on how far below 35°C

    local wetness = 0
    if EHR.Environmental and EHR.Environmental.GetWetness then
        wetness = EHR.Environmental.GetWetness(player)
    end

    local baseChance = 0.30  -- 30% base
    local chance = baseChance * (1 + timeRatio * 0.5) * (1 + tempSeverity) * (1 + wetness * 0.5)
    chance = math.min(0.90, chance)  -- Cap at 90%

    if EHR.DEBUG then
        EHR.Log(string.format("BodyTemp: Hypothermia check - chance=%.1f%%, time=%.2fh, temp=%.1f°C, wet=%.1f",
            chance * 100, tempData.timeAtDangerousTemp, tempData.bodyTemp, wetness))
    end

    -- Try to contract
    if EHR.Disease.TryContract(player, "hypothermia", chance) then
        -- Reset danger zone tracking
        tempData.timeAtDangerousTemp = 0
        if EHR.DEBUG then
            EHR.Log("BodyTemp: Hypothermia contracted!")
        end

        -- MP: Trigger server sync after disease contraction
        if isClient() then
            sendClientCommand(player, "EHR", "RequestSync", {})
        end
    end
end

--[[
    Legacy compatibility hook. Heat exhaustion is now an exposure meter owned by
    EHR.Environmental; it must never be contracted as a disease from body heat.
]]--
function EHR.BodyTemp.TryTriggerHeatExhaustion(player, tempData)
    return
end

-- ============================================
-- VANILLA SUPPRESSION (Hybrid Approach)
-- ============================================

-- State tracking for hybrid suppression
local vanillaSuppression = {
    thermoregulatorDisabled = false,  -- Whether we've disabled the thermoregulator
    lastPlayer = nil,                  -- Track player to reset on player change
    suppressTickCounter = 0,           -- Counter for throttled safety checks
    SAFETY_CHECK_INTERVAL = 30,        -- Only check every 30 ticks (~1 second)
    NORMAL_BODY_TEMP = 36.6,           -- Target temperature (Celsius)
    TOLERANCE = 1.0,                   -- Only force if off by more than 1°C
}

function EHR.BodyTemp.GetVanillaSuppressionTarget(player)
    local normalTemp = EHR.BodyTemp.Config.normalTemp or vanillaSuppression.NORMAL_BODY_TEMP
    if not player then return normalTemp end

    local cfg = EHR.BodyTemp.Config
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)
    local managedTemp = tempData and tonumber(tempData.bodyTemp) or nil
    if tempData and tempData.diseaseTargetTemp then
        local gameTime = getGameTime and getGameTime() or nil
        local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
        local untilHour = tonumber(tempData.diseaseTargetTempUntil)
        if not hasFeverSource or (untilHour and untilHour < currentHour) then
            tempData.diseaseTargetTemp = nil
            tempData.diseaseTargetTempUntil = nil
            if not hasFeverSource then
                tempData.diseaseFeverActive = false
            end
        else
            local feverTemp = managedTemp or tonumber(tempData.diseaseTargetTemp) or normalTemp
            return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, feverTemp))
        end
    end

    if hasFeverSource and EHR.BodyTemp.GetActiveDiseaseFeverTarget then
        local feverTemp = EHR.BodyTemp.GetActiveDiseaseFeverTarget(player)
        if feverTemp then
            return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, feverTemp))
        end
    end

    if managedTemp then
        return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, managedTemp))
    end

    return normalTemp
end

--[[
    Attempt to disable the vanilla Thermoregulator simulation.
    This stops vanilla temperature calculations at the source.
    @param player (IsoPlayer)
    @return boolean - True if successfully disabled
]]--
local function tryDisableThermoregulator(player)
    if not player then return false end

    local success = pcall(function()
        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            local thermo = bodyDamage:getThermoregulator()
            if thermo and thermo.setSimulationMultiplier then
                thermo:setSimulationMultiplier(0)
                return true
            end
        end
    end)

    return success
end

--[[
    Hybrid vanilla temperature suppression.

    Strategy:
    1. Primary: Disable thermoregulator once (stops vanilla at source)
    2. Safety net: Check every ~30 ticks and force if needed

    This reduces writes from ~60/sec to ~2/sec while maintaining reliability.

    @param player (IsoPlayer)
]]--
function EHR.BodyTemp.SuppressVanillaTemperature(player)
    if not player then return end
    -- Vanilla is authoritative again. Keep this function as a no-op because
    -- older call sites still use it every tick.
    do return end

    -- Reset state if player changed (new game, different save, etc.)
    if vanillaSuppression.lastPlayer ~= player then
        vanillaSuppression.thermoregulatorDisabled = false
        vanillaSuppression.lastPlayer = player
        vanillaSuppression.suppressTickCounter = 0
    end

    -- PRIMARY: Try to disable thermoregulator once
    if not vanillaSuppression.thermoregulatorDisabled then
        if tryDisableThermoregulator(player) then
            vanillaSuppression.thermoregulatorDisabled = true
            if EHR.DEBUG then
                EHR.Log("BodyTemp: Thermoregulator disabled (primary suppression active)")
            end
        end
    end

    -- SAFETY NET: Throttled check every N ticks
    vanillaSuppression.suppressTickCounter = vanillaSuppression.suppressTickCounter + 1
    if vanillaSuppression.suppressTickCounter < vanillaSuppression.SAFETY_CHECK_INTERVAL then
        return  -- Skip this tick
    end
    vanillaSuppression.suppressTickCounter = 0  -- Reset counter

    -- Check if vanilla temperature drifted (mod conflict, game load, etc.)
    local stats = player:getStats()
    if not stats then return end

    if not CharacterStat or not CharacterStat.TEMPERATURE then return end

    local success, current = pcall(function()
        return stats:get(CharacterStat.TEMPERATURE)
    end)

    if not success or current == nil then return end

    local targetTemp = EHR.BodyTemp.GetVanillaSuppressionTarget(player)
    local cfg = EHR.BodyTemp.Config
    local normalTemp = cfg.normalTemp or vanillaSuppression.NORMAL_BODY_TEMP
    local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    local managedTemp = tempData and tonumber(tempData.bodyTemp) or nil
    local plannedTarget = tempData and (tonumber(tempData.targetTemp) or tonumber(tempData.environmentTargetTemp)) or nil
    local activelyCooling = managedTemp and plannedTarget and plannedTarget < managedTemp - 0.01

    -- If vanilla has already cooled the character while EHR is also cooling,
    -- accept the colder value instead of snapping upward. When EHR is warming,
    -- do not accept the colder value or the character can get stuck cold.
    -- Fever sources still win and may force temperature upward intentionally.
    if current > (cfg.minBodyTemp or 28.0) and managedTemp and current < managedTemp - 0.01 and targetTemp <= normalTemp + 0.2 and activelyCooling and not hasFeverSource then
        if tempData then
            tempData.bodyTemp = current
            if EHR.DEBUG then
                EHR.Log(string.format("BodyTemp: Accepted cooler vanilla temperature %.2fC", current))
            end
        end
        return
    end

    -- Only force if significantly off from the mod-managed temperature
    if math.abs(current - targetTemp) > vanillaSuppression.TOLERANCE then
        pcall(function()
            stats:set(CharacterStat.TEMPERATURE, targetTemp)
        end)

        -- If we had to force, thermoregulator might have re-enabled
        vanillaSuppression.thermoregulatorDisabled = false

        if EHR.DEBUG then
            EHR.Log(string.format("BodyTemp: Safety net triggered - forced TEMPERATURE: %.1f -> %.1f",
                current, targetTemp))
        end
    end
end

--[[
    Force re-initialization of vanilla suppression.
    Call this after game load or when suppression seems broken.
]]--
function EHR.BodyTemp.ResetVanillaSuppression()
    vanillaSuppression.thermoregulatorDisabled = false
    vanillaSuppression.lastPlayer = nil
    vanillaSuppression.suppressTickCounter = 0
    if EHR.DEBUG then
        EHR.Log("BodyTemp: Vanilla suppression reset")
    end
end

-- ============================================
-- PUBLIC API
-- ============================================

--[[
    Get current body temperature for a player.
    @param player (IsoPlayer)
    @return number or nil
]]--
function EHR.BodyTemp.GetBodyTemperature(player)
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if tempData then
        return tempData.bodyTemp
    end
    return nil
end

--[[
    Check if player is warm enough for hypothermia recovery.
    Used by EHR_EnvironmentalDiseases.lua
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.BodyTemp.IsWarmEnoughForRecovery(player)
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if tempData and tempData.bodyTemp then
        -- Body temp > 36.0°C = warm enough
        return tempData.bodyTemp > 36.0
    end
    return false
end

--[[
    Check if player is cool enough for heat-stroke recovery.
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.BodyTemp.IsCoolEnoughForRecovery(player)
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if tempData and tempData.bodyTemp then
        -- Body temp < 38.5°C = cool enough
        return tempData.bodyTemp < 38.5
    end
    return false
end

-- ============================================
-- TICK MANAGEMENT
-- ============================================

local BODY_TEMP_TICK_INTERVAL = 60  -- Every ~2 seconds at 30 ticks/sec

-- MP: per-player tick state (avoid shared counters across players)
local tickStateByPlayer = {}

local function getPlayerId(player)
    if not player then return nil end
    local onlineId = nil
    pcall(function() onlineId = player:getOnlineID() end)
    if onlineId and onlineId >= 0 then
        return tostring(onlineId)
    end
    local username = nil
    pcall(function() username = player:getUsername() end)
    if username and username ~= "" then
        return username
    end
    local num = nil
    pcall(function() num = player:getPlayerNum() end)
    return tostring(num or "0")
end

local function getTickState(player)
    local id = getPlayerId(player) or "0"
    local state = tickStateByPlayer[id]
    if not state then
        state = { tick = 0 }
        tickStateByPlayer[id] = state
    end
    return state
end

local function getActivePlayers()
    local players = {}
    if isServer and isServer() and getOnlinePlayers then
        local online = getOnlinePlayers()
        if online then
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if p then
                    table.insert(players, p)
                end
            end
        end
    end

    if #players == 0 then
        local player = getSpecificPlayer(0)
        if player then
            table.insert(players, player)
        end
    end

    return players
end

local function processPlayerTick(player, clientPredictionOnly)
    if not player or not player:isAlive() then return end

    -- Check if custom body temp system is enabled
    -- If disabled, don't suppress vanilla temp - allows other temp mods to work
    if not EHR.BodyTemp.IsEnabled() then return end

    -- Initialization and the vanilla adapter run before the slower medical
    -- checks. Vanilla's heat delta is a per-tick value and must not be sampled
    -- only once every BODY_TEMP_TICK_INTERVAL.
    EHR.BodyTemp.InitializePlayer(player)
    if EHR.BodyTemp.UpdateVanillaHeatAdapter then
        EHR.BodyTemp.UpdateVanillaHeatAdapter(player)
    end

    -- Legacy no-op: vanilla is authoritative for environmental temperature.
    EHR.BodyTemp.SuppressVanillaTemperature(player)
    if EHR.BodyTemp.MaintainDiseaseFeverBridge then
        EHR.BodyTemp.MaintainDiseaseFeverBridge(player)
    end

    -- Throttled updates for our system
    local state = getTickState(player)
    state.tick = state.tick + 1
    if state.tick < BODY_TEMP_TICK_INTERVAL then return end
    state.tick = 0

    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if not tempData then return end

    -- Calculate delta time
    local currentHour = getGameTime():getWorldAgeHours()
    local lastHour = tempData.lastUpdateHour or currentHour
    local deltaHours = currentHour - lastHour

    -- MEDIUM FIX: Improved edge case handling with explicit bounds and logging
    -- Clamp delta to reasonable range: 0 to 1 hour (prevents:
    --   - Negative values: time sync issues, loading, or game time manipulation
    --   - Large values: >1hr deltas from loading saved games or paused play)
    local DELTA_MIN = 0
    local DELTA_MAX = 1.0  -- Maximum 1 hour delta per update
    local DELTA_DEFAULT = 0.05  -- ~3 game minutes fallback (typical tick interval)

    if deltaHours < DELTA_MIN then
        -- Time went backwards - this is a bug or game reload, skip processing
        if EHR.DEBUG then
            EHR.Log(string.format("BodyTemp: Negative delta (%.3f) - time reset or sync issue", deltaHours))
        end
        deltaHours = DELTA_DEFAULT
    elseif deltaHours > DELTA_MAX then
        -- Large delta from game load or pause - cap to prevent temperature shock
        if EHR.DEBUG then
            EHR.Log(string.format("BodyTemp: Large delta (%.2fh) capped to %.2fh", deltaHours, DELTA_MAX))
        end
        deltaHours = DELTA_MAX
    end
    tempData.lastUpdateHour = currentHour

    -- Update body temperature
    EHR.BodyTemp.UpdateBodyTemperature(player, deltaHours)

    if clientPredictionOnly then
        return
    end

    -- Apply pre-disease effects (shivering, sweating, dialogue)
    EHR.BodyTemp.ApplyPreDiseaseEffects(player, tempData)

    -- Check disease thresholds
    EHR.BodyTemp.CheckDiseaseThresholds(player, tempData, deltaHours)
end

function EHR.BodyTemp.OnTick()
    -- MP: the local client owns its live Thermoregulator/ICL heat balance.
    -- Disease contraction remains server-authoritative via bodyTempC snapshots.
    if isClient and isClient() and not (isServer and isServer()) then
        local player = getSpecificPlayer(0)
        processPlayerTick(player, true)
        return
    end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player, false)
    end
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events and Events.OnTick then
    Events.OnTick.Add(EHR.BodyTemp.OnTick)
    EHR.Log("Body Temperature module events registered")
end

EHR.Log("Body Temperature module loaded v1.1.0 (vanilla heat adapter)")
