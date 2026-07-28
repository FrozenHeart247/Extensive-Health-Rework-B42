--[[
    Extensive Health Rework B42
    Environmental Diseases Module

    Handles disease transmission from environmental factors:
    - Cold weather + wetness -> Common Cold -> Pneumonia progression
    - Contaminated water -> Dysentery
    - Extreme cold + wet exposure -> Hypothermia

    B42 API Notes:
    - CharacterStat.TEMPERATURE: Player body temperature (0-1 scale, ~0.5 = normal)
    - CharacterStat.WETNESS: How wet the player is (0-1 scale)
    - player:getTemperature() may also work for body temp
    - getClimateManager():getTemperature() for air temperature
    - player:getCurrentSquare():isInARoom() for indoor check

    v1.0.0 - Initial implementation
]]--

require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_DiseaseDefinitions"
require "ExtensiveHealth/EHR_BodyTemperature"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.Environmental = {}

-- ============================================
-- CONFIGURATION
-- ============================================

-- Temperature thresholds (Celsius, game uses roughly real-world temps)
EHR.Environmental.Config = {
    -- Cold exposure thresholds
    coldTemp = 5,               -- Below this is "cold" (Celsius)
    freezingTemp = 0,           -- Below this is "freezing"
    hypothermiaTemp = -5,       -- Below this = rapid hypothermia risk

    -- Heat exposure thresholds
    hotTemp = 30,               -- Above this is "hot" (Celsius)
    veryHotTemp = 35,           -- Above this is "very hot"
    extremeHeatTemp = 40,       -- Above this = rapid heat stroke risk

    -- Wetness thresholds (0-1 scale)
    wetThreshold = 0.3,         -- Above this counts as "wet"
    soakedThreshold = 0.7,      -- Above this counts as "soaked"
    commonColdSoakedThreshold = 0.90, -- Wet-only common cold requires at least 90% character wetness

    -- Exposure time requirements (in game hours)
    coldExposureForCold = 2.0,      -- Hours of cold+wet for common cold
    soakedExposureForCold = 1.0,    -- Hours at 90%+ wetness before wet-only common cold rolls
    commonColdRiskCheckInterval = 1.0, -- Roll common cold risk at most once per game hour
    coldExposureForHypo = 0.5,      -- Hours of freezing+wet for hypothermia
    heatExposureForExhaustion = 4.0,  -- Hours from clean exposure to full heat exhaustion risk at 30C
    heatExposureForStroke = 0.5,      -- Hours at extreme heat for heat stroke
    heatMinimumExposure = 1.0,        -- Minimum hours before disease check can trigger
    heatExposureLowRatio = 0.05,      -- UI card appears almost immediately once heat starts building
    heatExposureMediumRatio = 0.50,   -- UI-only warning threshold
    heatExposureHighRatio = 0.85,     -- Heat stroke rolls begin here
    heatIndoorRecoveryRate = 2.25,    -- Indoor cooling removes exposure quickly
    heatCoolRecoveryRate = 1.25,      -- Outdoor cool weather recovery
    heatHeadwearMultiplier = 0.30,    -- Caps/hats reduce heat exposure by ~70%
    heatStrokeRiskCheckInterval = 5 / 60, -- Check heat stroke risk every 5 game minutes at High exposure
    heatStrokeLowChance = 0.03,
    heatStrokePreHighChance = 0.10,
    heatStrokeHighChance = 0.35,
    heatStrokeFullChance = 1.00,
    heatStrokeAmbientCoolingTemp = 10.0,
    heatStrokeAmbientCoolingHours = 3.0,
    heatStrokeAmbientCoolingDecay = 0.5,
    heatExposureStartHour = 9,
    heatExposureEndHour = 20,

    -- Water contamination risk
    untreatedWaterRisk = 0.25,      -- 25% per drink from contaminated/untreated water
    toiletWaterRisk = 0.50,         -- 50% per direct drink from toilets
    riverWaterRisk = 0.15,          -- No extra river/lake multiplier
    rainCollectorRisk = 0.05,       -- 5% from rain collectors (mostly safe)

    -- Cold -> Pneumonia progression check interval (game hours)
    coldProgressionCheckInterval = 6,   -- Check every 6 game hours
    debugCommonCold = false,             -- Set false to silence common cold exposure/progression diagnostics
    commonColdDebugThrottleHours = 0.25,

    -- Sound radii for zombie attraction (MIN-004 fix)
    sound = {
        sneezeRadius = 8,
        sneezeVolume = 5,
        sneezeSfx = "EHRSneeze",
        sneezeMaleSfx = "EHRSneezeMale",
        sneezeFemaleSfx = "EHRSneezeFemale",
        coughRadius = 12,
        coughVolume = 8,
        coughSevereRadius = 25,
        coughSevereVolume = 15,
        coughSfx = "EHRCough",
        coughMaleSfx = "EHRCoughMale",
        coughFemaleSfx = "EHRCoughFemale",
        coughSevereSfx = "EHRCoughSevere",
        coughSevereMaleSfx = "EHRCoughSevereMale",
        coughSevereFemaleSfx = "EHRCoughSevereFemale",
        coughMuffledRadiusMultiplier = 0.15,
        coughMuffledVolumeMultiplier = 0.20,
        vomitRadius = 15,
        vomitVolume = 10,
    },
}

local function EHR_EnvironmentalWorldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        return tonumber(gameTime:getWorldAgeHours()) or 0
    end
    return 0
end

local function EHR_EnvironmentalClampNumber(value, minValue, maxValue)
    value = tonumber(value)
    if not value then return nil end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function EHR_EnvironmentalGetSandboxNumber(name, default, minValue, maxValue)
    local value = nil
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        value = SandboxVars.ExtensiveHealthRework[name]
    end
    value = tonumber(value)
    if value == nil then value = tonumber(default) or 0 end
    return EHR_EnvironmentalClampNumber(value, minValue, maxValue) or value
end

local function EHR_EnvironmentalGetSandboxBoolean(name, default)
    local value = nil
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        value = SandboxVars.ExtensiveHealthRework[name]
    end
    if value == nil then return default == true end
    return value == true or value == 1 or value == "true"
end

function EHR.Environmental.AreCoughSoundsEnabled()
    return EHR_EnvironmentalGetSandboxBoolean("CoughSoundsEnabled", true)
end

function EHR.Environmental.GetHeatTemperatureThreshold()
    local config = EHR.Environmental.Config or {}
    return EHR_EnvironmentalGetSandboxNumber("HeatExposureTemperatureThreshold", config.hotTemp or 30.0, 20.0, 50.0)
end

function EHR.Environmental.GetHeatExposureHoursToFull()
    local config = EHR.Environmental.Config or {}
    return EHR_EnvironmentalGetSandboxNumber("HeatExposureHoursToFull", config.heatExposureForExhaustion or 4.0, 0.25, 24.0)
end

function EHR.Environmental.GetHeatExposureGainMultiplier()
    return EHR_EnvironmentalGetSandboxNumber("HeatExposureGainMultiplier", 1.0, 0.0, 5.0)
end

function EHR.Environmental.GetHeatExposureRecoveryMultiplier()
    return EHR_EnvironmentalGetSandboxNumber("HeatExposureRecoveryMultiplier", 1.0, 0.0, 5.0)
end

function EHR.Environmental.GetHeatExposureStartHour()
    local config = EHR.Environmental.Config or {}
    return math.floor(EHR_EnvironmentalGetSandboxNumber(
        "HeatExposureStartHour", config.heatExposureStartHour or 9, 0, 23))
end

function EHR.Environmental.GetHeatExposureEndHour()
    local config = EHR.Environmental.Config or {}
    return math.floor(EHR_EnvironmentalGetSandboxNumber(
        "HeatExposureEndHour", config.heatExposureEndHour or 20, 0, 23))
end

function EHR.Environmental.IsHeatExposureActiveHour(timeOfDay)
    if timeOfDay == nil then
        local gameTime = getGameTime and getGameTime() or nil
        if gameTime and gameTime.getTimeOfDay then
            pcall(function() timeOfDay = gameTime:getTimeOfDay() end)
        end
    end

    timeOfDay = tonumber(timeOfDay)
    if timeOfDay == nil then return true end
    timeOfDay = timeOfDay % 24

    local startHour = EHR.Environmental.GetHeatExposureStartHour()
    local endHour = EHR.Environmental.GetHeatExposureEndHour()
    if startHour == endHour then return true end

    if startHour < endHour then
        return timeOfDay >= startHour and timeOfDay < endHour
    end
    return timeOfDay >= startHour or timeOfDay < endHour
end

function EHR.Environmental.GetHeatStrokeChanceMultiplier()
    return EHR_EnvironmentalGetSandboxNumber("HeatStrokeChanceMultiplier", 1.0, 0.0, 5.0)
end

function EHR.Environmental.GetHeatHeadwearExposureMultiplier()
    local config = EHR.Environmental.Config or {}
    return EHR_EnvironmentalGetSandboxNumber("HeatHeadwearExposureMultiplier", config.heatHeadwearMultiplier or 0.30, 0.0, 1.0)
end

function EHR.Environmental.GetCommonColdExposureMultiplier()
    return EHR_EnvironmentalGetSandboxNumber("CommonColdExposureMultiplier", 1.0, 0.0, 5.0)
end

function EHR.Environmental.GetCommonColdChanceMultiplier()
    return EHR_EnvironmentalGetSandboxNumber("CommonColdChanceMultiplier", 1.0, 0.0, 5.0)
end

function EHR.Environmental.GetDysenteryChanceMultiplier()
    return EHR_EnvironmentalGetSandboxNumber("DysenteryChanceMultiplier", 1.0, 0.0, 5.0)
end

local function EHR_EnvironmentalPlayerName(player)
    local name = "unknown"
    pcall(function()
        if player and player.getUsername then
            name = tostring(player:getUsername() or name)
        elseif player and player.getPlayerNum then
            name = "Player" .. tostring(player:getPlayerNum())
        end
    end)
    return name
end

local function EHR_EnvironmentalCommonColdDebugEnabled()
    local config = EHR.Environmental and EHR.Environmental.Config or {}
    return config.debugCommonCold == true
end

local function EHR_EnvironmentalRuntimeMode()
    if EHR.Environmental and EHR.Environmental._skipDiseaseChecks then return "client-predict" end
    if isServer and isServer() then return "server-auth" end
    if isClient and isClient() then return "client-auth" end
    return "single"
end

local function EHR_EnvironmentalDebugCommonCold(player, state, reason, detail, force)
    if not EHR_EnvironmentalCommonColdDebugEnabled() then return end

    local now = EHR_EnvironmentalWorldHour()
    if state and not force then
        local throttle = tonumber(EHR.Environmental.Config.commonColdDebugThrottleHours) or 0.25
        local lastReason = tostring(state.EHR_CommonColdDebugLastReason or "")
        local lastHour = tonumber(state.EHR_CommonColdDebugLastHour) or -999999
        if lastReason == tostring(reason or "") and (now - lastHour) < throttle then return end
        state.EHR_CommonColdDebugLastReason = tostring(reason or "")
        state.EHR_CommonColdDebugLastHour = now
    end

    print("[EHR][CommonCold][" .. EHR_EnvironmentalPlayerName(player) .. "] "
        .. tostring(reason or "state") .. ": " .. tostring(detail or ""))
end

-- ============================================
-- EXPOSURE TRACKING
-- ============================================

-- Track environmental exposure per player
EHR.Environmental.ExposureData = {}
EHR.Environmental.ClientSnapshots = EHR.Environmental.ClientSnapshots or {}

function EHR.Environmental.GetPlayerKey(player)
    if not player then return "0" end

    local onlineId = nil
    if player.getOnlineID then
        pcall(function() onlineId = player:getOnlineID() end)
    end
    if onlineId and onlineId >= 0 then
        return tostring(onlineId)
    end

    local username = nil
    if player.getUsername then
        pcall(function() username = player:getUsername() end)
    end
    if username and username ~= "" then
        return tostring(username)
    end

    local playerNum = nil
    if player.getPlayerNum then
        pcall(function() playerNum = player:getPlayerNum() end)
    end
    return tostring(playerNum or "0")
end

--[[
    Initialize exposure tracking for a player
]]--
function EHR.Environmental.InitializePlayer(player)
    if not player then return end

    local playerID = EHR.Environmental.GetPlayerKey(player)
    local currentHour = EHR_EnvironmentalWorldHour()

    if EHR.Environmental.ExposureData[playerID] then
        return -- Already initialized
    end

    EHR.Environmental.ExposureData[playerID] = {
        -- Cold exposure tracking
        coldExposure = 0,           -- Accumulated cold exposure (hours)
        soakedColdExposure = 0,     -- Accumulated heavy-wetness exposure (hours)
        hypothermiaExposure = 0,    -- Accumulated freezing exposure (hours)
        lastColdCheck = 0,          -- Last game hour we checked

        -- Heat exposure tracking
        heatExposure = 0,           -- Accumulated heat exposure (hours)
        heatStrokeExposure = 0,     -- Accumulated extreme heat exposure (hours)
        lastHeatCheck = 0,          -- Last game hour we checked

        -- Wetness tracking
        wetDuration = 0,            -- How long player has been wet (hours)

        -- Indoor tracking
        indoorDuration = 0,         -- Time spent indoors (for recovery)

        -- Cold -> Pneumonia progression
        coldContractedHour = nil,   -- When cold was contracted
        lastProgressionCheck = 0,   -- Last time we checked for pneumonia progression
        lastCommonColdRoll = 0,     -- Last time common cold contraction rolled

        -- High heat-exhaustion exposure -> Heat Stroke rolls
        lastHeatStrokeRiskCheck = currentHour,

        -- Water tracking
        lastUntreatedWater = nil,   -- Last time drank untreated water
    }

    EHR.Log("Environmental: Initialized tracking for player " .. playerID)
end

--[[
    Get exposure data for a player
]]--
function EHR.Environmental.GetExposureData(player)
    if not player then return nil end
    local playerID = EHR.Environmental.GetPlayerKey(player)
    return EHR.Environmental.ExposureData[playerID]
end

-- ============================================
-- ENVIRONMENT READING
-- ============================================

--[[
    Read Indoor Climate Lite's public ambient sample when it is active.
    ICL never writes body temperature; EHR remains the sole health-model owner.
]]--
function EHR.Environmental.GetIndoorClimateLiteSample(player)
    local icl = _G and _G.IndoorClimateLite or nil
    if not icl or type(icl.getTemperatureSample) ~= "function" then return nil end

    local ok, sample = pcall(function()
        return icl.getTemperatureSample(player)
    end)
    if not ok or type(sample) ~= "table" then return nil end

    local active = sample.active
    if active == nil and type(icl.isActive) == "function" then
        local okActive, currentActive = pcall(icl.isActive)
        active = okActive and currentActive or false
    end
    if active ~= true then return nil end

    local airTemp = tonumber(sample.airC)
    if not airTemp or airTemp < -80 or airTemp > 80 then return nil end
    return sample
end

--[[
    Get current effective air temperature (Celsius).
    Prefers an existing multiplayer client snapshot, then ICL's local sample,
    and finally the global ClimateManager outdoor temperature.
]]--
function EHR.Environmental.GetAirTemperature(player)
    if player and EHR.Environmental.GetClientSnapshot then
        local okSnapshot, snapshot = pcall(EHR.Environmental.GetClientSnapshot, player)
        if okSnapshot
                and type(snapshot) == "table"
                and snapshot.temperatureSource == "IndoorClimateLite"
                and snapshot.iclActive == true
                and tonumber(snapshot.airTemp) then
            return tonumber(snapshot.airTemp)
        end
    end

    local iclSample = EHR.Environmental.GetIndoorClimateLiteSample(player)
    if iclSample then
        return tonumber(iclSample.airC)
    end

    local climate = getClimateManager()
    if climate and climate.getTemperature then
        local success, temp = pcall(function() return climate:getTemperature() end)
        if success and temp then
            return temp
        end
    end
    return 15 -- Default moderate temp if can't read
end

function EHR.Environmental.GetVehicleInsideTemperature(player)
    if not player or not player.getVehicle then return nil end

    local okVehicle, vehicle = pcall(function()
        return player:getVehicle()
    end)
    if not okVehicle or not vehicle or not vehicle.getInsideTemperature then return nil end

    local okTemp, temp = pcall(function()
        return vehicle:getInsideTemperature()
    end)
    temp = tonumber(temp)
    if not okTemp or not temp then return nil end
    if temp < -80 or temp > 90 then return nil end

    return temp
end

function EHR.Environmental.GetEffectiveHeatAirTemperature(player, fallbackAirTemp)
    local vehicleTemp = EHR.Environmental.GetVehicleInsideTemperature(player)
    if vehicleTemp then
        return vehicleTemp, true
    end

    return tonumber(fallbackAirTemp) or EHR.Environmental.GetAirTemperature(player), false
end

local function EHR_EnvironmentalNormalizeBodyTempStat(value)
    value = tonumber(value)
    if not value then return nil end

    -- Realistic Temperature stores CharacterStat.TEMPERATURE as real Celsius.
    -- This module's legacy thresholds use vanilla's normalized 0-1-ish scale.
    if value >= 25.0 and value <= 45.0 then
        return ((value - 37.0) / 8.0) + 0.5
    end

    return value
end

--[[
    Get player body temperature (0-1 scale, ~0.5 = normal)
    B42: CharacterStat.TEMPERATURE through stats:get()
]]--
function EHR.Environmental.GetBodyTemperature(player)
    local stats = player:getStats()
    if not stats then return 0.5 end

    if CharacterStat and CharacterStat.TEMPERATURE then
        local success, temp = pcall(function() return stats:get(CharacterStat.TEMPERATURE) end)
        if success and temp then
            return EHR_EnvironmentalNormalizeBodyTempStat(temp) or temp
        end
    end

    -- Fallback: try legacy method
    if player.getTemperature then
        local success, temp = pcall(function() return player:getTemperature() end)
        if success and temp then
            return EHR_EnvironmentalNormalizeBodyTempStat(temp) or temp
        end
    end

    return 0.5 -- Default normal
end

local function EHR_EnvironmentalNormalizeWetness(value, percentScale)
    value = tonumber(value)
    if not value then return 0 end

    -- B42 registers CharacterStat.WETNESS on a 0..100 scale. Older APIs and
    -- existing EHR snapshots use 0..1, so accept both representations.
    if percentScale == true or value > 1.5 then
        value = value / 100
    end

    return math.max(0, math.min(1, value))
end

--[[
    Get player wetness normalized to the EHR 0-1 scale.
    B42 CharacterStat.WETNESS itself is 0-100.
]]--
function EHR.Environmental.GetWetness(player)
    if not player then return 0 end
    local stats = player:getStats()
    if not stats then return 0 end

    if CharacterStat and CharacterStat.WETNESS then
        local success, wet = pcall(function() return stats:get(CharacterStat.WETNESS) end)
        if success and wet then
            return EHR_EnvironmentalNormalizeWetness(wet, true)
        end
    end

    -- Fallback: try legacy method
    if player.getWetness then
        local success, wet = pcall(function() return player:getWetness() end)
        if success and wet then
            return EHR_EnvironmentalNormalizeWetness(wet, true)
        end
    end

    return 0 -- Default dry
end

-- ============================================
-- VANILLA DISEASE SUPPRESSION
-- ============================================

--[[
    Suppress vanilla temperature effects when mod is managing temperature diseases.
    Vanilla uses CharacterStat.TEMPERATURE to drive hypothermia/hyperthermia moodles.
    We clamp it to safe range to prevent vanilla death while our system runs.

    Also handles cold/pneumonia - these diseases affect body temperature regulation.
]]--
function EHR.Environmental.SuppressVanillaTemperature(player)
    if not player then return end

    if EHR.BodyTemp and EHR.BodyTemp.IsRealisticTemperatureActive and EHR.BodyTemp.IsRealisticTemperatureActive() then
        return
    end

    local modData = player:getModData()
    if not modData or not modData.EHR_Disease then return end

    -- Check if mod is managing a temperature-related or respiratory disease
    local active = modData.EHR_Disease.active or {}
    local hasModHypothermia = active["hypothermia"] ~= nil
    local hasModHeatStroke = active["heat_stroke"] ~= nil
    local hasModCold = active["common_cold"] ~= nil
    local hasModPneumonia = active["pneumonia"] ~= nil
    local hasModAspergillosis = active["cadaveric_aspergillosis"] ~= nil

    if not (hasModHypothermia or hasModHeatStroke or hasModCold or hasModPneumonia or hasModAspergillosis) then
        return  -- No mod temperature/respiratory disease, don't interfere with vanilla
    end

    -- Use existing GetBodyTemperature for consistency
    local currentTemp = EHR.Environmental.GetBodyTemperature(player)
    if not currentTemp then return end

    -- Safe range: 0.35-0.65 prevents vanilla hypothermia/hyperthermia moodle triggers
    -- Normal body temp is ~0.5 on 0-1 scale
    local safeMin = 0.35
    local safeMax = 0.65
    local safeMid = 0.50

    if currentTemp < safeMin or currentTemp > safeMax then
        local stats = player:getStats()
        if stats and CharacterStat and CharacterStat.TEMPERATURE then
            pcall(function() stats:set(CharacterStat.TEMPERATURE, safeMid) end)
            if EHR.DEBUG then
                EHR.Log(string.format("SuppressVanilla: Clamped TEMPERATURE from %.3f to %.3f (mod managing disease)",
                    currentTemp, safeMid))
            end
        end
    end
end

--[[
    Suppress vanilla cold/sickness effects when mod is managing respiratory diseases.
    Vanilla HAS_A_COLD moodle is driven by SICKNESS stat combined with cold exposure.

    This fixes the "coughing moodle appearing when mod shows no conditions" bug.
]]--
function EHR.Environmental.SuppressVanillaCold(player)
    if not player then return end

    local modData = player:getModData()
    if not modData or not modData.EHR_Disease then return end

    local stats = player:getStats()
    if not stats then return end

    -- Check if mod is managing any respiratory disease
    local active = modData.EHR_Disease.active or {}
    local hasModCold = active["common_cold"] ~= nil
    local hasModPneumonia = active["pneumonia"] ~= nil
    local hasModCorpseSickness = active["corpse_sickness"] ~= nil
    local hasModAspergillosis = active["cadaveric_aspergillosis"] ~= nil
    local hasModTuberculosis = active["tuberculosis"] ~= nil
    local hasModFoodDisease = false

    for diseaseId, disease in pairs(active) do
        local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId]
        if disease and (diseaseId == "food_poisoning" or (def and def.category == "food")) then
            hasModFoodDisease = true
            break
        end
    end

    local hasAnyModRespiratory = hasModCold or hasModPneumonia or hasModCorpseSickness or hasModAspergillosis or hasModTuberculosis

    if not CharacterStat or not CharacterStat.SICKNESS then return end

    local success, currentSickness = pcall(function() return stats:get(CharacterStat.SICKNESS) end)
    if not success or not currentSickness then return end

    local currentFoodSickness = 0
    if CharacterStat.FOOD_SICKNESS then
        local okFood, foodValue = pcall(function() return stats:get(CharacterStat.FOOD_SICKNESS) end)
        if okFood and foodValue then
            currentFoodSickness = foodValue
        end
    end
    local corpseSuppressesFoodSickness = EHR.CorpseSickness
        and EHR.CorpseSickness.ShouldSuppressFoodSickness
        and EHR.CorpseSickness.ShouldSuppressFoodSickness(player)

    if corpseSuppressesFoodSickness and EHR.CorpseSickness.SuppressFoodSicknessComponent then
        EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
    end

    local hasFoodSicknessSignal = hasModFoodDisease
        or (currentFoodSickness > 0.01 and not corpseSuppressesFoodSickness)

    local hasCorpseExposure = false
    if EHR.CorpseSickness and EHR.CorpseSickness.GetExposureDisplay then
        local level = EHR.CorpseSickness.GetExposureDisplay(player)
        if level and level ~= "None" then
            hasCorpseExposure = true
        end
    end

    -- Do not erase vanilla corpse sickness while EHR exposure is still below its
    -- own display threshold. B42 vanilla sickness can start rising before EHR
    -- reaches "Low" exposure, so nearby corpses must opt out of suppression too.
    if not hasCorpseExposure and EHR.CorpseSickness then
        local corpseData = modData.EHR_CorpseSickness
        local exposure = corpseData and (corpseData.currentExposure or 0) or 0
        local vanillaExposure = corpseData and (corpseData.vanillaCorpseExposure or 0) or 0
        local residualExposure = math.max(exposure, vanillaExposure)
        local fullyProtectedFromCorpses = EHR.CorpseSickness.GetProtectionLevel
            and EHR.CorpseSickness.GetProtectionLevel(player) >= 1.0
        if residualExposure > 0 then
            hasCorpseExposure = true
        elseif not fullyProtectedFromCorpses and currentSickness > 0.01 and not hasFoodSicknessSignal and EHR.CorpseSickness.ScanNearbyCorpses then
            local ok, corpseInfo = pcall(function() return EHR.CorpseSickness.ScanNearbyCorpses(player) end)
            if ok and corpseInfo and (corpseInfo.count or 0) > 0 then
                hasCorpseExposure = true
            end
        end
    end

    local realisticTemperatureActive = EHR.BodyTemp
        and EHR.BodyTemp.IsRealisticTemperatureActive
        and EHR.BodyTemp.IsRealisticTemperatureActive()

    if hasAnyModRespiratory then
        -- Mod HAS a respiratory disease - sync SICKNESS to mod's disease stage
        local targetSickness = 0
        local vanillaSicknessLevels = (EHR.Disease and EHR.Disease.VanillaSicknessLevels) or {
            [0] = 0,
            [1] = 10,
            [2] = 35,
            [3] = 60,
            [4] = 20,
        }
        local respiratoryDiseases = {"common_cold", "pneumonia", "corpse_sickness", "cadaveric_aspergillosis", "tuberculosis"}
        local corpseReliefCapped = false
        local gameTime = getGameTime and getGameTime() or nil
        local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

        for _, diseaseId in ipairs(respiratoryDiseases) do
            local disease = active[diseaseId]
            if disease and disease.stage then
                local stageValue = vanillaSicknessLevels[disease.stage] or 0
                if diseaseId == "common_cold" then
                    -- Common cold now drives the vanilla cold moodle directly.
                    -- Do not turn it into the nausea/sickness moodle.
                    stageValue = 0
                elseif diseaseId == "corpse_sickness" then
                    local symptomTarget = disease.corpseSicknessSymptomTarget
                    local symptomTargetUntil = disease.corpseSicknessSymptomTargetUntil
                    if symptomTarget and symptomTargetUntil and symptomTargetUntil > currentHour then
                        stageValue = math.min(stageValue, math.max(0, math.min(100, symptomTarget * 100)))
                        corpseReliefCapped = true
                    end
                end
                targetSickness = math.max(targetSickness, stageValue)
            end
        end

        local targetB42 = targetSickness / 100
        local currentLegacySickness = currentSickness
        if stats.getSickness then
            local okLegacy, legacyValue = pcall(function() return stats:getSickness() end)
            if okLegacy and legacyValue then
                currentLegacySickness = legacyValue
            end
        end
        local effectiveCurrentSickness = math.max(currentSickness, currentLegacySickness)
        local difference = math.abs(effectiveCurrentSickness - targetB42)

        -- Only update if significantly different (dead zone to prevent flicker)
        if difference > 0.10 or (corpseReliefCapped and effectiveCurrentSickness > targetB42 + 0.015) then
            pcall(function() stats:set(CharacterStat.SICKNESS, targetB42) end)
            if stats.setSickness then
                pcall(function() stats:setSickness(targetB42) end)
            end
            if EHR.DEBUG then
                EHR.Log(string.format("SuppressVanillaCold: Synced SICKNESS %.3f/%.3f -> %.3f (mod respiratory disease active%s)",
                    currentSickness,
                    currentLegacySickness,
                    targetB42,
                    corpseReliefCapped and ", corpse nausea relief cap" or ""))
            end
        end
    else
        if realisticTemperatureActive then
            -- Let Realistic Temperature own vanilla cold/sickness when EHR is
            -- not currently managing a respiratory/food/corpse sickness source.
            return
        end

        -- No mod respiratory disease - if vanilla SICKNESS is elevated (from vanilla cold), suppress it
        -- This prevents vanilla coughing moodle when mod shows "0 Conditions"
        if not hasCorpseExposure and not hasFoodSicknessSignal and currentSickness > 0.15 then
            pcall(function() stats:set(CharacterStat.SICKNESS, 0) end)
            if EHR.DEBUG then
                EHR.Log(string.format("SuppressVanillaCold: Suppressed vanilla SICKNESS %.3f -> 0 (no mod disease)",
                    currentSickness))
            end
        end
    end
end

--[[
    Check if player is indoors
    B42: getCurrentSquare():isInARoom() or getSquare():getRoom()
]]--
function EHR.Environmental.IsIndoors(player)
    local square = player:getCurrentSquare()
    if not square then return false end

    -- Try isInARoom first
    if square.isInARoom then
        local success, result = pcall(function() return square:isInARoom() end)
        if success then return result end
    end

    -- Try getRoom (returns nil if outside)
    if square.getRoom then
        local success, room = pcall(function() return square:getRoom() end)
        if success and room then
            return true
        end
    end

    -- Check if there's a roof above
    if square.Is then
        local success, hasRoof = pcall(function() return square:Is(IsoFlagType.exterior) end)
        if success then
            return not hasRoof -- exterior = outside
        end
    end

    return false
end

--[[
    Check if player is near a heat source (fire, furnace, etc.)
    Simplified check - looks for lit stoves/fireplaces nearby
]]--
function EHR.Environmental.IsNearHeat(player)
    local square = player:getCurrentSquare()
    if not square then return false end

    -- Check surrounding squares (3x3 area)
    local x, y, z = square:getX(), square:getY(), square:getZ()

    for dx = -1, 1 do
        for dy = -1, 1 do
            local checkSquare = getCell():getGridSquare(x + dx, y + dy, z)
            if checkSquare then
                -- Check for lit objects (campfires, stoves, etc.)
                local objects = checkSquare:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if obj then
                            -- Check if it's a heat source
                            local sprite = obj:getSprite()
                            if sprite then
                                local spriteName = sprite:getName() or ""
                                -- Common heat source sprites
                                if string.find(spriteName, "fireplace") or
                                   string.find(spriteName, "campfire") or
                                   string.find(spriteName, "stove") or
                                   string.find(spriteName, "oven") then
                                    -- Check if it's lit/on
                                    if obj.isLit then
                                        local success, lit = pcall(function() return obj:isLit() end)
                                        if success and lit then
                                            return true
                                        end
                                    end
                                    if obj.Activated then
                                        local success, active = pcall(function() return obj:Activated() end)
                                        if success and active then
                                            return true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

--[[
    Check if player is exerting themselves (sprinting, fighting, heavy carrying)
    B42: Check sprinting/running state and endurance drain
]]--
function EHR.Environmental.IsExerting(player)
    -- Check if sprinting
    if player.isSprinting then
        local success, sprinting = pcall(function() return player:isSprinting() end)
        if success and sprinting then
            return true
        end
    end

    -- Check if running
    if player.isRunning then
        local success, running = pcall(function() return player:isRunning() end)
        if success and running then
            return true
        end
    end

    -- Check if in combat (attacking)
    if player.isAiming then
        local success, aiming = pcall(function() return player:isAiming() end)
        if success and aiming then
            return true
        end
    end

    -- Check endurance (low endurance = was exerting)
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.ENDURANCE then
        local success, endurance = pcall(function() return stats:get(CharacterStat.ENDURANCE) end)
        if success and endurance and endurance < 0.5 then
            return true
        end
    end

    return false
end

function EHR.Environmental.GetHeatHeadwearMultiplier(player)
    if not player then return 1.0 end

    local function normalizeLocation(value)
        local loc = string.lower(tostring(value or ""))
        loc = string.gsub(loc, "^base:", "")
        loc = string.gsub(loc, "[_%-%s]", "")
        return loc
    end

    local function itemText(item)
        local parts = {}
        local methods = { "getFullType", "getDisplayName", "getName", "getType" }
        for _, method in ipairs(methods) do
            if item[method] then
                local ok, value = pcall(function() return item[method](item) end)
                if ok and value then
                    table.insert(parts, tostring(value))
                end
            end
        end
        return string.lower(table.concat(parts, " "))
    end

    local function isHeadwear(item)
        if not item then return false end

        local location = nil
        if item.getBodyLocation then
            pcall(function() location = item:getBodyLocation() end)
        end
        local loc = normalizeLocation(location)
        if loc == "hat" or loc == "fullhat" or loc == "jackethat" or
           loc == "jackethatbulky" or loc == "sweaterhat" or loc == "fullsuithead" then
            return true
        end

        if string.find(loc, "hat", 1, true) or string.find(loc, "head", 1, true) then
            return true
        end

        local text = itemText(item)
        return string.find(text, "hat", 1, true) ~= nil
            or string.find(text, "cap", 1, true) ~= nil
            or string.find(text, "beanie", 1, true) ~= nil
            or string.find(text, "helmet", 1, true) ~= nil
            or string.find(text, "fedora", 1, true) ~= nil
            or string.find(text, "boonie", 1, true) ~= nil
            or string.find(text, "beret", 1, true) ~= nil
    end

    local wornItems = nil
    pcall(function() wornItems = player:getWornItems() end)
    if not wornItems then
        local headItem = nil
        pcall(function()
            if player.getClothingItem_Head then
                headItem = player:getClothingItem_Head()
            end
        end)
        return isHeadwear(headItem) and EHR.Environmental.GetHeatHeadwearExposureMultiplier() or 1.0
    end

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if isHeadwear(item) then
            return EHR.Environmental.GetHeatHeadwearExposureMultiplier()
        end
    end

    return 1.0
end

--[[
    Check if player is in shade/indoors (for heat protection)
]]--
function EHR.Environmental.IsInShade(player)
    -- Indoors counts as shade
    if EHR.Environmental.IsIndoors(player) then
        return true
    end

    -- Check for tree cover or structures above
    local square = player:getCurrentSquare()
    if not square then return false end

    -- Check for roof/cover above
    if square.Is then
        local success, hasRoof = pcall(function() return square:Is(IsoFlagType.exterior) end)
        if success and not hasRoof then
            return true  -- Not exterior = has cover
        end
    end

    -- Could add tree detection here in future

    return false
end

-- ============================================
-- COLD EXPOSURE LOGIC
-- ============================================

local function EHR_EnvironmentalIsControlledBathing(player)
    if not player then return false end

    local modData = player:getModData()
    if modData then
        if modData.EHR_HeatStrokeColdBathActive == true then
            local untilHour = tonumber(modData.EHR_HeatStrokeColdBathUntil) or 0
            local worldHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
            if untilHour <= 0 or worldHour <= untilHour then
                return true
            end
        end

        if modData.IsDoingShower == true or
           modData.isDoingShower == true or
           modData.IsBathing == true or
           modData.isBathing == true or
           modData.LSBathing == true or
           modData.LSShowering == true or
           modData.takingBath == true or
           modData.TakingBath == true then
            return true
        end
    end

    if EHR.LifestyleCompat and EHR.LifestyleCompat.IsShowering then
        local ok, isShowering = pcall(EHR.LifestyleCompat.IsShowering, player)
        if ok and isShowering == true then
            return true
        end
    end

    return false
end

local function EHR_EnvironmentalReadThirst(player)
    if not player then return 0 end
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.THIRST then
        local success, thirst = pcall(function() return stats:get(CharacterStat.THIRST) end)
        if success and thirst then return tonumber(thirst) or 0 end
    end
    return 0
end

local function EHR_EnvironmentalClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value then return fallback end
    if minValue and value < minValue then return minValue end
    if maxValue and value > maxValue then return maxValue end
    return value
end

local function EHR_EnvironmentalReadBodyTempCelsius(player)
    if EHR.BodyTemp and EHR.BodyTemp.GetBodyTemperature then
        local ok, value = pcall(EHR.BodyTemp.GetBodyTemperature, player)
        value = ok and tonumber(value) or nil
        if value and value >= 20 and value <= 42 then return value end
    end

    local normalized = EHR.Environmental.GetBodyTemperature(player)
    normalized = tonumber(normalized)
    if not normalized then return nil end
    if normalized >= 20 and normalized <= 42 then return normalized end

    -- Environmental disease code intentionally uses its legacy normalized
    -- scale, where 0.5 represents 37C.
    return ((normalized - 0.5) * 8.0) + 37.0
end

function EHR.Environmental.BuildClientSnapshot(player)
    if not player then return nil end

    local iclSample = EHR.Environmental.GetIndoorClimateLiteSample(player)
    local usesIndoorClimateLite = iclSample ~= nil
    local airTemp = usesIndoorClimateLite
        and tonumber(iclSample.airC)
        or EHR.Environmental.GetAirTemperature(player)
    local heatAirTemp, isInVehicle = EHR.Environmental.GetEffectiveHeatAirTemperature(player, airTemp)
    local isIndoors = EHR.Environmental.IsIndoors(player) == true
    if usesIndoorClimateLite and iclSample.indoors ~= nil then
        isIndoors = iclSample.indoors == true
    end

    return {
        hour = getGameTime() and getGameTime():getWorldAgeHours() or 0,
        airTemp = airTemp,
        heatAirTemp = heatAirTemp,
        isInVehicle = isInVehicle == true,
        bodyTemp = EHR.Environmental.GetBodyTemperature(player),
        bodyTempC = EHR_EnvironmentalReadBodyTempCelsius(player),
        wetness = EHR.Environmental.GetWetness(player),
        isIndoors = isIndoors,
        isNearHeat = EHR.Environmental.IsNearHeat(player) == true,
        isExerting = EHR.Environmental.IsExerting(player) == true,
        isInShade = isIndoors or EHR.Environmental.IsInShade(player) == true,
        controlledBathing = EHR_EnvironmentalIsControlledBathing(player) == true,
        headwearMultiplier = EHR.Environmental.GetHeatHeadwearMultiplier(player),
        thirst = EHR_EnvironmentalReadThirst(player),
        temperatureSource = usesIndoorClimateLite and "IndoorClimateLite" or "ClimateManager",
        iclActive = usesIndoorClimateLite,
        iclVersion = usesIndoorClimateLite and tostring(iclSample.version or "") or nil,
        iclOutdoorAirTemp = usesIndoorClimateLite and tonumber(iclSample.outdoorC) or nil,
        iclVanillaAirTemp = usesIndoorClimateLite and tonumber(iclSample.vanillaAirC) or nil,
        iclTargetAirTemp = usesIndoorClimateLite and tonumber(iclSample.targetC) or nil,
        iclLeakScore = usesIndoorClimateLite and tonumber(iclSample.leakScore) or nil,
        iclPowered = usesIndoorClimateLite and iclSample.powered == true or false,
    }
end

function EHR.Environmental.StoreClientSnapshot(player, args)
    if not player or type(args) ~= "table" then return end

    local playerID = EHR.Environmental.GetPlayerKey(player)
    local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
    local usesIndoorClimateLite = args.temperatureSource == "IndoorClimateLite"
        and args.iclActive == true
    local iclVersion = usesIndoorClimateLite and tostring(args.iclVersion or "") or nil
    if iclVersion and #iclVersion > 32 then
        iclVersion = string.sub(iclVersion, 1, 32)
    end

    EHR.Environmental.ClientSnapshots[playerID] = {
        hour = EHR_EnvironmentalClampNumber(args.hour, currentHour - 1.0, currentHour + 1.0, currentHour),
        receivedHour = currentHour,
        airTemp = EHR_EnvironmentalClampNumber(args.airTemp, -80, 80, EHR.Environmental.GetAirTemperature(player)),
        heatAirTemp = EHR_EnvironmentalClampNumber(args.heatAirTemp, -80, 90, args.airTemp),
        isInVehicle = args.isInVehicle == true,
        bodyTemp = EHR_EnvironmentalClampNumber(args.bodyTemp, 0, 1.5, 0.5),
        bodyTempC = EHR_EnvironmentalClampNumber(args.bodyTempC, 20, 42, nil),
        wetness = EHR_EnvironmentalClampNumber(args.wetness, 0, 1.5, 0),
        isIndoors = args.isIndoors == true,
        isNearHeat = args.isNearHeat == true,
        isExerting = args.isExerting == true,
        isInShade = args.isInShade == true,
        controlledBathing = args.controlledBathing == true,
        headwearMultiplier = EHR_EnvironmentalClampNumber(args.headwearMultiplier, 0.05, 2.0, 1.0),
        thirst = EHR_EnvironmentalClampNumber(args.thirst, 0, 1.5, 0),
        temperatureSource = usesIndoorClimateLite and "IndoorClimateLite" or "ClimateManager",
        iclActive = usesIndoorClimateLite,
        iclVersion = iclVersion,
        iclOutdoorAirTemp = usesIndoorClimateLite
            and EHR_EnvironmentalClampNumber(args.iclOutdoorAirTemp, -80, 80, args.airTemp)
            or nil,
        iclVanillaAirTemp = usesIndoorClimateLite
            and EHR_EnvironmentalClampNumber(args.iclVanillaAirTemp, -80, 80, args.airTemp)
            or nil,
        iclTargetAirTemp = usesIndoorClimateLite
            and EHR_EnvironmentalClampNumber(args.iclTargetAirTemp, -80, 80, args.airTemp)
            or nil,
        iclLeakScore = usesIndoorClimateLite
            and EHR_EnvironmentalClampNumber(args.iclLeakScore, 0, 1, 0)
            or nil,
        iclPowered = usesIndoorClimateLite and args.iclPowered == true or false,
    }
end

function EHR.Environmental.GetClientSnapshot(player)
    if not (isServer and isServer()) then return nil end
    if not player then return nil end

    local playerID = EHR.Environmental.GetPlayerKey(player)
    local snapshot = EHR.Environmental.ClientSnapshots[playerID]
    if not snapshot then return nil end

    local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
    if (currentHour - (snapshot.receivedHour or 0)) > 0.5 then
        return nil
    end

    return snapshot
end

function EHR.Environmental.GetRuntimeEnvironment(player)
    local snapshot = EHR.Environmental.GetClientSnapshot(player)
    if snapshot then
        return snapshot
    end

    return EHR.Environmental.BuildClientSnapshot(player)
end

--[[
    Update cold exposure tracking
    Called periodically from main tick handler
]]--
function EHR.Environmental.UpdateColdExposure(player, deltaHours)
    local config = EHR.Environmental.Config
    local exposure = EHR.Environmental.GetExposureData(player)
    if not exposure then return end
    local coldExposureMultiplier = EHR.Environmental.GetCommonColdExposureMultiplier()

    local env = EHR.Environmental.GetRuntimeEnvironment(player) or {}
    local airTemp = tonumber(env.airTemp) or EHR.Environmental.GetAirTemperature(player)
    local bodyTemp = tonumber(env.bodyTemp) or EHR.Environmental.GetBodyTemperature(player)
    local wetness = tonumber(env.wetness) or EHR.Environmental.GetWetness(player)
    local isIndoors = env.isIndoors == true
    local isNearHeat = env.isNearHeat == true

    -- BUG-017 FIX: Use body temperature to determine if player is warm
    -- airTemp is OUTDOOR temperature, which is wrong for indoor warmth checks
    -- Body temperature accounts for room heating, clothing, exercise, etc.
    --
    -- Warmth conditions (any of these = warm):
    -- 1. Near a heat source (fire, stove, campfire)
    -- 2. Indoors with normal+ body temp (>0.4) = sheltered and not freezing
    -- 3. Normal+ body temp (>0.48) = player is maintaining warmth (clothes, activity, etc.)
    --    BALANCE FIX: Lowered from 0.55 to 0.48 - if you're managing your temperature
    --    and staying at normal body temp (~0.5), you shouldn't get sick from cold exposure
    -- 4. Outdoors in warm weather (airTemp > coldTemp)
    local isWarm = isNearHeat or
                   (isIndoors and bodyTemp > 0.4) or
                   bodyTemp > 0.48 or
                   (not isIndoors and airTemp > config.coldTemp)

    if EHR.DEBUG then
        EHR.Log(string.format("Cold check: indoors=%s, bodyTemp=%.2f, airTemp=%.1f, isWarm=%s",
            tostring(isIndoors), bodyTemp, airTemp, tostring(isWarm)))
    end

    -- Lifestyle baths/showers intentionally make the character wet. Treat that as
    -- controlled bathing wetness so it does not become a common-cold trigger.
    if env.controlledBathing == true then
        exposure.commonColdRiskActive = false
        exposure.commonColdFreezingWetRisk = false
        exposure.commonColdSoakedRisk = false
        exposure.coldExposure = math.max(0, exposure.coldExposure - deltaHours * 3)
        exposure.soakedColdExposure = math.max(0, (exposure.soakedColdExposure or 0) - deltaHours * 3)
        exposure.wetDuration = math.max(0, exposure.wetDuration - deltaHours)
        exposure.indoorDuration = exposure.indoorDuration + deltaHours
        EHR_EnvironmentalDebugCommonCold(player, exposure, "controlled-bathing", string.format(
            "wet=%.2f exposure drained; bath/shower wetness ignored",
            wetness
        ), true)

        if EHR.DEBUG then
            EHR.Log(string.format("Cold exposure skipped during controlled bath/shower (wet=%.2f)", wetness))
        end

        return
    end

    -- Check cold conditions
    local isWet = wetness > config.wetThreshold
    local isSoaked = wetness > config.soakedThreshold
    local isHeavilySoaked = wetness >= (config.commonColdSoakedThreshold or 0.90)
    local isFreezing = airTemp <= config.freezingTemp
    local isHypoRisk = airTemp < config.hypothermiaTemp

    -- Common cold should require freezing world weather + wetness, or extreme wetness by itself.
    -- Indoor shelter protects from the weather route, but being soaked through still matters unless near heat.
    local freezingWetRisk = isFreezing and isWet and not isIndoors and not isNearHeat
    local soakedRisk = isHeavilySoaked and not isNearHeat
    local coldRiskActive = freezingWetRisk or soakedRisk
    exposure.commonColdRiskActive = coldRiskActive
    exposure.commonColdFreezingWetRisk = freezingWetRisk
    exposure.commonColdSoakedRisk = soakedRisk

    EHR_EnvironmentalDebugCommonCold(player, exposure, "state", string.format(
        "mode=%s delta=%.3fh temp=%.1fC body=%.3f wet=%.2f indoor=%s heat=%s warm=%s freezingWet=%s soakedRisk=%s exp=%.2f/%.2fh soakedExp=%.2f/%.2fh checks=%s",
        EHR_EnvironmentalRuntimeMode(),
        tonumber(deltaHours) or 0,
        airTemp,
        bodyTemp,
        wetness,
        tostring(isIndoors),
        tostring(isNearHeat),
        tostring(isWarm),
        tostring(freezingWetRisk),
        tostring(soakedRisk),
        tonumber(exposure.coldExposure) or 0,
        tonumber(config.coldExposureForCold) or 0,
        tonumber(exposure.soakedColdExposure) or 0,
        tonumber(config.soakedExposureForCold) or 0,
        EHR.Environmental._skipDiseaseChecks and "skipped-client-predict" or "enabled"
    ))

    -- Reset exposure if warm and there is no active wet/freezing cold risk.
    if isWarm and not coldRiskActive then
        -- Recover from cold exposure while warm
        exposure.coldExposure = math.max(0, exposure.coldExposure - deltaHours * 2)
        exposure.soakedColdExposure = math.max(0, (exposure.soakedColdExposure or 0) - deltaHours * 2)
        exposure.hypothermiaExposure = math.max(0, exposure.hypothermiaExposure - deltaHours * 3)
        exposure.wetDuration = math.max(0, exposure.wetDuration - deltaHours)
        exposure.indoorDuration = exposure.indoorDuration + deltaHours
        EHR_EnvironmentalDebugCommonCold(player, exposure, "recovering", string.format(
            "warm/no-risk; exp=%.2f soakedExp=%.2f hypoExp=%.2f",
            tonumber(exposure.coldExposure) or 0,
            tonumber(exposure.soakedColdExposure) or 0,
            tonumber(exposure.hypothermiaExposure) or 0
        ))
        return
    end

    -- Track wetness duration
    if wetness > config.wetThreshold then
        exposure.wetDuration = exposure.wetDuration + deltaHours
    else
        exposure.wetDuration = math.max(0, exposure.wetDuration - deltaHours * 0.5)
    end

    -- Freezing wetness and heavy wetness are tracked separately so wet-only balance
    -- does not make the weather route too aggressive.
    local coldMultiplier = freezingWetRisk and 1.5 or 0
    if isSoaked and freezingWetRisk then
        coldMultiplier = 2.25
    end

    -- Accumulate freezing+wet exposure
    if freezingWetRisk then
        exposure.coldExposure = exposure.coldExposure + (deltaHours * coldMultiplier * coldExposureMultiplier)
    else
        exposure.coldExposure = math.max(0, exposure.coldExposure - deltaHours)
    end

    -- Accumulate heavy-wetness-only exposure
    if soakedRisk then
        exposure.soakedColdExposure = (exposure.soakedColdExposure or 0) + (deltaHours * coldExposureMultiplier)
    else
        exposure.soakedColdExposure = math.max(0, (exposure.soakedColdExposure or 0) - deltaHours)
    end

    if coldRiskActive then
        if EHR.DEBUG then
            EHR.Log(string.format("Cold exposure: freezing=%.2f, soaked=%.2f (temp=%.1f, wet=%.2f, mult=%.2f, freezingWet=%s, soakedRisk=%s)",
                exposure.coldExposure, exposure.soakedColdExposure or 0, airTemp, wetness, coldMultiplier,
                tostring(freezingWetRisk), tostring(soakedRisk)))
        end
    end

    -- Accumulate hypothermia exposure (requires freezing + wet OR extreme cold)
    if (isFreezing and isSoaked) or isHypoRisk then
        local hypoMultiplier = isHypoRisk and 2.0 or 1.0
        if isSoaked then hypoMultiplier = hypoMultiplier * 1.5 end

        exposure.hypothermiaExposure = exposure.hypothermiaExposure + (deltaHours * hypoMultiplier)

        if EHR.DEBUG then
            EHR.Log(string.format("Hypothermia exposure: %.2f hours (temp=%.1f, wet=%.2f)",
                exposure.hypothermiaExposure, airTemp, wetness))
        end
    end

    -- Check for disease contraction
    if not EHR.Environmental._skipDiseaseChecks then
        EHR.Environmental.CheckColdDiseases(player, exposure)
    else
        EHR_EnvironmentalDebugCommonCold(player, exposure, "client-predict-only",
            "local MP prediction updated exposure; disease contraction waits for server-authoritative tick")
    end
end

-- ============================================
-- HEAT EXPOSURE LOGIC
-- ============================================

--[[
    Update heat exposure tracking
    Called periodically from main tick handler
]]--
function EHR.Environmental.UpdateHeatExposure(player, deltaHours)
    local config = EHR.Environmental.Config
    local exposure = EHR.Environmental.GetExposureData(player)
    if not exposure then return end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
    local activeDiseases = diseaseData and diseaseData.active or nil
    if activeDiseases and activeDiseases["heat_exhaustion"] then
        -- Save migration: heat exhaustion used to be stored as a disease.
        -- Convert it back into the High exposure state instead of leaving a
        -- stage-based condition stuck in an existing save.
        activeDiseases["heat_exhaustion"] = nil
        local threshold = EHR.Environmental.GetHeatExposureHoursToFull()
        local highRatio = tonumber(config.heatExposureHighRatio) or 0.85
        exposure.heatExposure = math.max(tonumber(exposure.heatExposure) or 0, threshold * highRatio)
        exposure.heatStrokeExposure = exposure.heatExposure
        exposure.lastHeatStrokeRiskCheck = EHR_EnvironmentalWorldHour()
        if EHR.Environmental.ClearHeatMovementPenalty then
            EHR.Environmental.ClearHeatMovementPenalty(player)
        end
        EHR.Log("Migrated legacy heat_exhaustion disease to High heat exposure")
    end

    if activeDiseases and activeDiseases["heat_stroke"] then
        exposure.heatExposure = 0
        exposure.heatStrokeExposure = 0
        exposure.lastHeatStrokeRiskCheck = EHR_EnvironmentalWorldHour()
        return
    end

    local env = EHR.Environmental.GetRuntimeEnvironment(player) or {}
    local airTemp = tonumber(env.heatAirTemp) or tonumber(env.airTemp) or EHR.Environmental.GetAirTemperature(player)
    local isIndoors = env.isIndoors == true
    local isInShade = env.isInShade == true
    local isExerting = env.isExerting == true
    local thirst = tonumber(env.thirst) or 0
    local hotTemp = EHR.Environmental.GetHeatTemperatureThreshold()
    local recoveryMultiplier = EHR.Environmental.GetHeatExposureRecoveryMultiplier()
    local currentHour = EHR_EnvironmentalWorldHour()

    local function recover(rate, strokeRate)
        exposure.heatExposure = math.max(0,
            (tonumber(exposure.heatExposure) or 0) - deltaHours * rate * recoveryMultiplier)
        exposure.heatStrokeExposure = math.max(0,
            (tonumber(exposure.heatStrokeExposure) or 0) - deltaHours * strokeRate * recoveryMultiplier)
        -- Safe time is not a missed sequence of heat-risk rolls. Keeping this
        -- clock current prevents a long indoor stay or save reload from being
        -- converted into a burst of catch-up checks on the next hot step.
        exposure.lastHeatStrokeRiskCheck = currentHour
    end

    if isIndoors then
        recover(config.heatIndoorRecoveryRate or 2.25, 3)

        if EHR.DEBUG and exposure.heatExposure > 0 then
            EHR.Log(string.format("Heat exposure cooling indoors: %.2f hours (world temp=%.1f)",
                exposure.heatExposure, airTemp))
        end
        return
    end

    if not EHR.Environmental.IsHeatExposureActiveHour() then
        recover(config.heatCoolRecoveryRate or 1.25, 2)

        if EHR.DEBUG and exposure.heatExposure > 0 then
            EHR.Log(string.format("Heat exposure cooling outside active hours: %.2f hours", exposure.heatExposure))
        end
        return
    end

    if airTemp < hotTemp then
        recover(config.heatCoolRecoveryRate or 1.25, 2)
        return
    end

    -- Shade is effective in ordinary hot weather. Extreme ambient heat can
    -- still build exposure in shade, but much more slowly.
    if isInShade and airTemp < (config.veryHotTemp or 35) then
        recover((config.heatCoolRecoveryRate or 1.25) * 0.5, 1)
        return
    end

    local isDehydrated = thirst > 0.4
    local isSeverelyDehydrated = thirst > 0.7

    -- World-temperature driven heat exposure. 30C+ is enough on its own;
    -- exertion/dehydration only speed it up.
    local heatMultiplier = 1.0
    heatMultiplier = heatMultiplier * math.min(1.75, 1 + math.max(0, airTemp - hotTemp) * 0.06)
    if isExerting then heatMultiplier = heatMultiplier * 1.25 end
    if isDehydrated then heatMultiplier = heatMultiplier * 1.15 end
    if isSeverelyDehydrated then heatMultiplier = heatMultiplier * 1.25 end
    if isInShade then heatMultiplier = heatMultiplier * 0.35 end
    heatMultiplier = heatMultiplier * (tonumber(env.headwearMultiplier) or EHR.Environmental.GetHeatHeadwearMultiplier(player))
    heatMultiplier = heatMultiplier * EHR.Environmental.GetHeatExposureGainMultiplier()

    exposure.heatExposure = math.max(0, exposure.heatExposure + (deltaHours * heatMultiplier))

    if EHR.DEBUG then
        local source = env.isInVehicle and "vehicle" or "world"
        EHR.Log(string.format("Heat exposure: %.2f hours (%s temp=%.1f, mult=%.2f, exert=%s, thirst=%.2f)",
            exposure.heatExposure, source, airTemp, heatMultiplier, tostring(isExerting), thirst))
    end

    exposure.heatStrokeExposure = exposure.heatExposure

    -- Check for disease contraction
    if not EHR.Environmental._skipDiseaseChecks then
        EHR.Environmental.CheckHeatDiseases(player, exposure)
    end
end

--[[
    Check if heat exposure should cause diseases
]]--
function EHR.Environmental.CheckHeatDiseases(player, exposure)
    local config = EHR.Environmental.Config

    -- Check sandbox setting
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.HeatExhaustionEnabled == false then return end
    if options and options.HeatStrokeEnabled == false then return end

    if not (EHR.Disease and EHR.Disease.GetDiseaseData and
            EHR.Disease.TryContract and EHR.Disease.Contract) then return end

    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active then
        if diseaseData.active["heat_stroke"] then return end
        if diseaseData.active["common_cold"] or diseaseData.active["pneumonia"] or diseaseData.active["hypothermia"] then
            return
        end
    end

    local threshold = EHR.Environmental.GetHeatExposureHoursToFull()
    if threshold <= 0 then return end

    local accumulated = tonumber(exposure.heatExposure) or 0
    local ratio = accumulated / threshold
    local highRatio = tonumber(config.heatExposureHighRatio) or 0.85
    if ratio < highRatio then return end

    local currentHour = getGameTime and getGameTime():getWorldAgeHours() or 0
    local interval = config.heatStrokeRiskCheckInterval or (5 / 60)
    local elapsedSinceRiskCheck = currentHour - (exposure.lastHeatStrokeRiskCheck or 0)
    local guaranteed = ratio >= 1.0
    if not guaranteed and elapsedSinceRiskCheck < interval then return end
    exposure.lastHeatStrokeRiskCheck = currentHour

    local chance = 1.0
    if not guaranteed then
        local highChance = tonumber(config.heatStrokeHighChance) or 0.35
        local t = math.max(0, math.min(1,
            (ratio - highRatio) / math.max(0.01, 1.0 - highRatio)))
        chance = highChance + (t * (1.0 - highChance))

        local stats = player:getStats()
        if stats and CharacterStat and CharacterStat.THIRST then
            local ok, thirst = pcall(function() return stats:get(CharacterStat.THIRST) end)
            if ok and thirst then
                if thirst > 0.7 then
                    chance = chance * 1.35
                elseif thirst > 0.4 then
                    chance = chance * 1.15
                end
            end
        end
        if EHR.Environmental.IsExerting(player) then
            chance = chance * 1.15
        end
        chance = chance * EHR.Environmental.GetHeatStrokeChanceMultiplier()
        chance = math.max(0, math.min(0.95, chance))
    end

    EHR.Log(string.format("Heat stroke risk: exposure %.0f%%, chance %.0f%%",
        math.min(100, ratio * 100), chance * 100))

    local contracted = false
    if guaranteed then
        EHR.Disease.Contract(player, "heat_stroke")
        local currentData = EHR.Disease.GetDiseaseData(player)
        contracted = currentData and currentData.active and currentData.active["heat_stroke"] ~= nil
    else
        contracted = EHR.Disease.TryContract(player, "heat_stroke", chance) == true
    end

    if contracted then
        exposure.heatExposure = 0
        exposure.heatStrokeExposure = 0
    end
end

function EHR.Environmental.GetHeatExposureRatio(player)
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.HeatExhaustionEnabled == false then return 0 end

    local exposure = EHR.Environmental.GetExposureData(player)
    local threshold = EHR.Environmental.GetHeatExposureHoursToFull()
    if not exposure or threshold <= 0 then return 0 end

    return math.max(0, math.min(1.25, (tonumber(exposure.heatExposure) or 0) / threshold))
end

function EHR.Environmental.GetHeatExposureDisplay(player)
    local ratio = EHR.Environmental.GetHeatExposureRatio(player)
    local config = EHR.Environmental.Config or {}
    if ratio <= 0 then return "None" end

    if ratio >= (config.heatExposureHighRatio or 0.85) then
        return "High"
    elseif ratio >= (config.heatExposureMediumRatio or 0.50) then
        return "Medium"
    elseif ratio >= (config.heatExposureLowRatio or 0.05) then
        return "Low"
    end

    return "Low"
end

function EHR.Environmental.GetHeatExposureColor(level)
    local colors = {
        None = {0.5, 0.5, 0.5},
        Low = {0.95, 0.74, 0.18},
        Medium = {1.0, 0.45, 0.10},
        High = {1.0, 0.12, 0.08},
    }
    return colors[level] or colors.None
end

--[[
    Check if heat disease should be blocked from recovering
]]--
function EHR.Environmental.CheckHeatCooling(player, deltaHours)
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return end

    local env = EHR.Environmental.GetRuntimeEnvironment(player) or {}
    local airTemp = tonumber(env.heatAirTemp) or tonumber(env.airTemp) or EHR.Environmental.GetAirTemperature(player)

    -- Heat exhaustion is exposure only; cooling recovery applies to heat stroke.
    for _, diseaseId in ipairs({"heat_stroke"}) do
        local disease = diseaseData.active[diseaseId]
        if disease then
            local def = EHR.Disease.Diseases[diseaseId]
            if def and def.requiresCoolingForRecovery then
                local isInShade = env.isInShade == true
                local hotTemp = EHR.Environmental.GetHeatTemperatureThreshold()
                local veryHotTemp = tonumber(EHR.Environmental.Config.veryHotTemp) or 35
                local isCool = airTemp < hotTemp or (isInShade and airTemp < veryHotTemp)

                -- If in recovery (stage 4) but not cool, regress
                if disease.stage == 4 and not isCool then
                    disease.stage = 3
                    disease.stageStartTime = getGameTime():getWorldAgeHours()

                    EHR.Log(diseaseId .. ": Regressed from recovery to peak (not cool enough)")

                    if player.Say then
                        EHR.Locale.Say(player, "*pants* Still too hot... can't recover...")
                    end
                end

                disease.coolingBlocked = not isCool
            end

            if diseaseId == "heat_stroke" and EHR.Environmental.UpdateHeatStrokeAmbientCooling then
                EHR.Environmental.UpdateHeatStrokeAmbientCooling(player, disease, deltaHours or 0, airTemp)
            end
        end
    end
end

-- ============================================
-- COLD DISEASE CHECKS
-- ============================================

--[[
    Check if cold exposure should cause diseases
]]--
function EHR.Environmental.CheckColdDiseases(player, exposure)
    local config = EHR.Environmental.Config

    -- Check for Common Cold
    local freezingExposure = exposure.coldExposure or 0
    local soakedExposure = exposure.soakedColdExposure or 0
    local freezingReady = freezingExposure >= config.coldExposureForCold
    local soakedReady = soakedExposure >= (config.soakedExposureForCold or 1.0)
    local currentRiskActive = exposure.commonColdRiskActive == true

    if not (freezingReady or soakedReady) then
        EHR_EnvironmentalDebugCommonCold(player, exposure, "not-ready", string.format(
            "freezing=%.2f/%.2fh soaked=%.2f/%.2fh",
            freezingExposure,
            tonumber(config.coldExposureForCold) or 0,
            soakedExposure,
            tonumber(config.soakedExposureForCold) or 0
        ))
    end

    if (freezingReady or soakedReady) and not currentRiskActive then
        EHR_EnvironmentalDebugCommonCold(player, exposure, "blocked-no-current-risk", string.format(
            "stored exposure is ready but current risk is inactive; freezing=%.2fh soaked=%.2fh freezingWet=%s soakedRisk=%s",
            freezingExposure,
            soakedExposure,
            tostring(exposure.commonColdFreezingWetRisk == true),
            tostring(exposure.commonColdSoakedRisk == true)
        ))
    elseif freezingReady or soakedReady then
        local gameTime = getGameTime and getGameTime() or nil
        local now = gameTime and gameTime:getWorldAgeHours() or 0
        local lastRoll = tonumber(exposure.lastCommonColdRoll) or -999999
        local rollInterval = config.commonColdRiskCheckInterval or 1.0
        if (now - lastRoll) < rollInterval then
            EHR_EnvironmentalDebugCommonCold(player, exposure, "roll-cooldown", string.format(
                "next roll in %.2fh; freezing=%.2f soaked=%.2f",
                math.max(0, rollInterval - (now - lastRoll)),
                freezingExposure,
                soakedExposure
            ))
            return
        end
        exposure.lastCommonColdRoll = now

        -- Don't contract if already have cold, pneumonia, or hypothermia
        local diseaseData = EHR.Disease.GetDiseaseData(player)
        if diseaseData and diseaseData.active then
            if diseaseData.active["common_cold"] or diseaseData.active["pneumonia"] or
               diseaseData.active["hypothermia"] then
                EHR_EnvironmentalDebugCommonCold(player, exposure, "blocked-active-disease",
                    "already has common cold/pneumonia/hypothermia")
                return
            end
            -- BUG-010 FIX: Block if have heat diseases (mutual exclusion)
            if diseaseData.active["heat_stroke"] then
                EHR_EnvironmentalDebugCommonCold(player, exposure, "blocked-heat-disease",
                    "heat disease active")
                return
            end
        end

        -- Base chance increases with exposure time
        local freezingRatio = freezingExposure / config.coldExposureForCold
        local soakedRatio = soakedExposure / (config.soakedExposureForCold or 1.0)
        local freezingChance = freezingReady and math.min(0.35, 0.10 * freezingRatio) or 0
        local soakedChance = soakedReady and math.min(0.25, 0.08 * soakedRatio) or 0
        local baseChance = math.min(1.0, math.max(freezingChance, soakedChance) * EHR.Environmental.GetCommonColdChanceMultiplier())

        EHR.Log(string.format("Cold exposure check: freezing=%.2fh, soaked=%.2fh, base chance %.0f%%",
            freezingExposure, soakedExposure, baseChance * 100))

        local contracted = EHR.Disease.TryContract(player, "common_cold", baseChance)
        EHR_EnvironmentalDebugCommonCold(player, exposure, "roll", string.format(
            "freezing=%.2fh soaked=%.2fh chance=%.2f%% result=%s",
            freezingExposure,
            soakedExposure,
            baseChance * 100,
            contracted and "CONTRACTED" or "no proc"
        ), true)

        if contracted then
            -- Record when cold was contracted for pneumonia progression
            exposure.coldContractedHour = getGameTime():getWorldAgeHours()
            -- Reset exposure after contracting
            exposure.coldExposure = 0
            exposure.soakedColdExposure = 0
        end
    end

    -- Check for Hypothermia (separate from cold)
    -- Check sandbox setting first (allows disabling for Realistic Temperatures compatibility)
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.HypothermiaEnabled == false then
        -- Hypothermia disabled, skip check
        return
    end

    -- If body temperature system is enabled, it handles hypothermia triggering
    -- via body temperature thresholds instead of exposure time
    if EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled() then
        -- Body temp system handles disease triggering in EHR.BodyTemp.CheckDiseaseThresholds()
        if EHR.DEBUG then
            EHR.Log("Hypothermia: Deferring to body temperature system")
        end
        return
    end

    -- Fallback: Exposure-based triggering when body temp system is disabled
    if exposure.hypothermiaExposure >= config.coldExposureForHypo then
        local diseaseData = EHR.Disease.GetDiseaseData(player)
        if diseaseData and diseaseData.active then
            if diseaseData.active["hypothermia"] then
                return -- Already have hypothermia
            end
            -- BUG-010 FIX: Block hypothermia if have heat diseases (mutual exclusion)
            if diseaseData.active["heat_stroke"] then
                return
            end
        end

        -- Hypothermia is more certain when exposed
        local exposureRatio = exposure.hypothermiaExposure / config.coldExposureForHypo
        local baseChance = math.min(0.8, 0.3 * exposureRatio)  -- 30-80% based on exposure

        EHR.Log(string.format("Hypothermia exposure check: %.2f hours, base chance %.0f%%",
            exposure.hypothermiaExposure, baseChance * 100))

        if EHR.Disease.TryContract(player, "hypothermia", baseChance) then
            -- Reset exposure after contracting
            exposure.hypothermiaExposure = 0
        end
    end
end

-- ============================================
-- COLD -> PNEUMONIA PROGRESSION
-- ============================================

--[[
    Check if common cold should progress to pneumonia
    Called periodically for players with active cold
]]--
local function EHR_EnvironmentalHasActiveDiseaseTreatment(player, diseaseId)
    if not player or not diseaseId then return false end

    local modData = player:getModData()
    local medTracking = modData and modData.EHR_Medication
    if not medTracking then return false end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    local treatments = medTracking.activeTreatments
    local treatment = treatments and treatments[diseaseId]
    if type(treatment) == "table" and treatment.awaitingDoses ~= true then
        local startTime = tonumber(treatment.startTime)
        local cureTimeHours = tonumber(treatment.cureTimeHours)
        if not startTime or not cureTimeHours or cureTimeHours <= 0 or (currentHour - startTime) < cureTimeHours then
            return true
        end
    end

    local activeDoses = medTracking.activeDoses
    if type(activeDoses) ~= "table" then return false end

    for medKey, doseData in pairs(activeDoses) do
        if type(doseData) == "table" then
            local moduleTargets = doseData.moduleTargets
            local matchesDisease = doseData.treatingDisease == diseaseId
                or (type(moduleTargets) == "table" and moduleTargets[diseaseId] == true)

            if matchesDisease then
                if EHR.Medication and EHR.Medication.GetDoseStatus then
                    local ok, status = pcall(EHR.Medication.GetDoseStatus, player, medKey)
                    if ok and status and status.isDoseActive then
                        return true
                    end
                elseif doseData.lastDoseTime then
                    local activeHours = tonumber(doseData.activeHours) or tonumber(doseData.intervalHours) or 0
                    if activeHours > 0 and (currentHour - doseData.lastDoseTime) <= activeHours then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function EHR_EnvironmentalHasActiveDiseaseCureTreatment(player, diseaseId)
    if not player or not diseaseId then return false end

    local modData = player:getModData()
    local medTracking = modData and modData.EHR_Medication
    if not medTracking then return false end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    local treatments = medTracking.activeTreatments
    local treatment = treatments and treatments[diseaseId]
    if type(treatment) == "table" and treatment.awaitingDoses ~= true then
        local startTime = tonumber(treatment.startTime)
        local cureTimeHours = tonumber(treatment.cureTimeHours)
        if not startTime or not cureTimeHours or cureTimeHours <= 0 or (currentHour - startTime) < cureTimeHours then
            return true
        end
    end

    local activeDoses = medTracking.activeDoses
    if type(activeDoses) ~= "table" then return false end

    for medKey, doseData in pairs(activeDoses) do
        if type(doseData) == "table" and doseData.requiresDoseCourse == true and doseData.symptomOnly ~= true then
            local moduleTargets = doseData.moduleTargets
            local matchesDisease = doseData.treatingDisease == diseaseId
                or (type(moduleTargets) == "table" and moduleTargets[diseaseId] == true)

            if matchesDisease then
                if EHR.Medication and EHR.Medication.GetDoseStatus then
                    local ok, status = pcall(EHR.Medication.GetDoseStatus, player, medKey)
                    if ok and status and status.isDoseActive then
                        return true
                    end
                elseif doseData.lastDoseTime then
                    local activeHours = tonumber(doseData.activeHours) or tonumber(doseData.intervalHours) or 0
                    if activeHours > 0 and (currentHour - doseData.lastDoseTime) <= activeHours then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function EHR_EnvironmentalSetVanillaCold(player, strength)
    if not player or not player.getBodyDamage then return end

    local okBody, bodyDamage = pcall(function()
        return player:getBodyDamage()
    end)
    if not okBody or not bodyDamage then return end

    strength = tonumber(strength) or 0
    if bodyDamage.setCatchACold then
        pcall(function()
            bodyDamage:setCatchACold(0.0)
        end)
    end

    if bodyDamage.setColdStrength then
        pcall(function()
            bodyDamage:setColdStrength(math.max(0, strength))
        end)
    end

    if bodyDamage.setHasACold then
        pcall(function()
            bodyDamage:setHasACold(strength > 0)
        end)
    end
end

function EHR.Environmental.ClearVanillaCold(player)
    EHR_EnvironmentalSetVanillaCold(player, 0)
end

function EHR.Environmental.CheckColdProgression(player, exposure)
    local diseaseData = EHR.Disease.GetDiseaseData(player)

    if not diseaseData or not diseaseData.active then return end
    local cold = diseaseData.active["common_cold"]
    if not cold then return end

    -- Get disease definition
    local coldDef = EHR.Disease.Diseases["common_cold"]
    if not coldDef or not coldDef.canProgress then return end

    -- Pneumonia is a late untreated complication, not an early cold upgrade.
    local currentHour = EHR_EnvironmentalWorldHour()
    if (cold.stage or 1) ~= 4 then
        EHR_EnvironmentalDebugCommonCold(player, cold, "progression-stage-wait", string.format(
            "stage=%s; pneumonia roll only on stage 4",
            tostring(cold.stage or 1)
        ))
        return
    end

    local graceUntil = tonumber(cold.debugCommonColdStage4GraceUntil)
    if graceUntil and currentHour < graceUntil then
        EHR_EnvironmentalDebugCommonCold(player, cold, "debug-stage4-grace", string.format(
            "waiting %.2fh before pneumonia/resolution roll",
            graceUntil - currentHour
        ))
        return
    elseif graceUntil then
        cold.debugCommonColdStage4GraceUntil = nil
    end

    if EHR_EnvironmentalHasActiveDiseaseTreatment(player, "common_cold") then
        cold.pneumoniaRollDone = nil
        EHR_EnvironmentalDebugCommonCold(player, cold, "progression-blocked-treatment",
            "common cold treatment is active", true)
        if EHR.DEBUG then
            EHR.Log("Cold progression skipped: common cold treatment is active")
        end
        return
    end

    if cold.pneumoniaRollDone then
        EHR_EnvironmentalDebugCommonCold(player, cold, "progression-roll-done",
            "stage 4 complication already resolved")
        return
    end

    local baseProgressChance = coldDef.progressChance or 0.35
    local progressChance = baseProgressChance
    if EHR.Immunity and EHR.Immunity.ModifyDiseaseChance then
        progressChance = EHR.Immunity.ModifyDiseaseChance(
            player,
            "pneumonia",
            baseProgressChance,
            { kind = "common_cold_complication" }
        )
    end
    cold.pneumoniaRollDone = true

    if EHR.DEBUG or (EHR.Immunity and EHR.Immunity.DEBUG_ROLLS == true) then
        EHR.Log(string.format("Cold stage 4 complication roll: base=%.0f%%, immune-adjusted=%.0f%%",
            baseProgressChance * 100, progressChance * 100))
    end

    -- Roll for progression
    local roll = ZombRand(100) / 100
    EHR_EnvironmentalDebugCommonCold(player, cold, "stage4-roll", string.format(
        "chance=%.2f%% roll=%.2f%% result=%s",
        progressChance * 100,
        roll * 100,
        roll < progressChance and "PNEUMONIA" or "RECOVER"
    ), true)

    if roll < progressChance then
        -- Progress to pneumonia!
        EHR.Log("Cold progressed to PNEUMONIA!")

        -- Remove cold and clear the vanilla cold moodle before applying the complication.
        diseaseData.active["common_cold"] = nil
        EHR_EnvironmentalSetVanillaCold(player, 0)

        -- Contract pneumonia (guaranteed)
        EHR.Disease.Contract(player, "pneumonia")

        -- Player announcement
        if player.Say then
            EHR.Locale.Say(player, "*coughs violently* This isn't just a cold anymore...")
        end
    else
        EHR.Log("Cold resolved without pneumonia.")
        EHR_EnvironmentalSetVanillaCold(player, 0)
        if EHR.Disease and EHR.Disease.Cure then
            EHR.Disease.Cure(player, "common_cold")
        else
            diseaseData.active["common_cold"] = nil
        end

        if player.Say then
            EHR.Locale.Say(player, "*sniff* I think I'm finally getting over this cold...")
        end
    end
end

-- ============================================
-- WATER CONTAMINATION
-- ============================================

--[[
    Check if water source is contaminated
    Called when player drinks water

    @param waterItem - The water container item
    @param sourceType - Optional: "tap", "river", "rainCollector", "toilet", etc.
    @return risk (0-1), reason (string)
]]--
function EHR.Environmental.GetWaterContaminationRisk(waterItem, sourceType)
    local config = EHR.Environmental.Config

    -- Known world-source hooks can override generic tainted water for clearer risk/logging.
    if sourceType == "rainCollector" then
        return config.rainCollectorRisk, "rain"
    elseif sourceType == "toilet" then
        return config.toiletWaterRisk, "toilet"
    elseif sourceType == "river" or sourceType == "lake" then
        return config.riverWaterRisk, "river"
    end

    -- Check if water is already marked as tainted
    if waterItem then
        -- Try B42 methods for tainted water
        if waterItem.isTaintedWater then
            local success, tainted = pcall(function() return waterItem:isTaintedWater() end)
            if success and tainted then
                return config.untreatedWaterRisk, "tainted"
            end
        end

        -- Check if water has been boiled/treated
        if waterItem.isCookable then
            local success, cookable = pcall(function() return waterItem:isCookable() end)
            if success and cookable then
                -- Check if it's been cooked
                if waterItem.isCooked then
                    local cooked = waterItem:isCooked()
                    if cooked then
                        return 0.01, "boiled" -- Minimal risk for boiled water
                    end
                end
            end
        end
    end

    -- Determine risk based on source type
    if sourceType == "tainted" or sourceType == "contaminated" then
        return config.untreatedWaterRisk, "tainted"
    elseif sourceType == "tap" then
        -- Sinks/faucets should remain a clean-water source for dysentery logic.
        -- Unsafe world sources are passed explicitly as toilet/river/rainCollector/tainted.
        return 0, "safe"
    end

    -- Default: assume untreated
    return config.untreatedWaterRisk, "unknown"
end

--[[
    Handle player drinking potentially contaminated water
    Called from FoodHook or drink action override
]]--
function EHR.Environmental.OnDrinkWater(player, waterItem, sourceType)
    if not player then return end

    -- Initialize if needed
    EHR.Environmental.InitializePlayer(player)

    local risk, reason = EHR.Environmental.GetWaterContaminationRisk(waterItem, sourceType)
    risk = math.max(0, math.min(1, (tonumber(risk) or 0) * EHR.Environmental.GetDysenteryChanceMultiplier()))

    if risk <= 0.01 then
        if EHR.DEBUG then
            EHR.Log("Water is safe: " .. reason)
        end
        return
    end

    EHR.Log(string.format("Contaminated water consumed: %s (%.0f%% risk)", reason, risk * 100))

    -- Try to contract dysentery
    if EHR.Disease.TryContract(player, "dysentery", risk) then
        -- Record for tracking
        local exposure = EHR.Environmental.GetExposureData(player)
        if exposure then
            exposure.lastUntreatedWater = getGameTime():getWorldAgeHours()
        end
    end
end

-- ============================================
-- DISEASE EFFECT HANDLERS
-- ============================================

local EHR_EnvironmentalDiseaseFeverTargets = {
    common_cold = {
        [2] = { temp = 37.6, step = 0.018 },
        [3] = { temp = 38.0, step = 0.025 },
    },
    pneumonia = {
        [1] = { temp = 38.0, step = 0.030 },
        [2] = { temp = 40.0, step = 0.070 },
        [3] = { temp = 40.0, step = 0.075 },
        [4] = { temp = 40.0, step = 0.075 },
    },
    heat_stroke = {
        [1] = { temp = 40.5, step = 0.110 },
        [2] = { temp = 40.5, step = 0.120 },
        [3] = { temp = 40.5, step = 0.130 },
        [4] = { temp = 40.5, step = 0.100 },
    },
}

local function EHR_EnvironmentalApplyBodyFever(player, diseaseId, disease)
    local stage = disease and (tonumber(disease.stage) or 1) or 1
    local feverInfo = EHR_EnvironmentalDiseaseFeverTargets[diseaseId]
        and EHR_EnvironmentalDiseaseFeverTargets[diseaseId][stage]
    if not feverInfo or not (EHR.BodyTemp and EHR.BodyTemp.MoveDiseaseFeverToward) then return end

    local symptomMult = 1.0
    if EHR.Disease and EHR.Disease.GetActiveSymptomMultiplier then
        symptomMult = EHR.Disease.GetActiveSymptomMultiplier(player, diseaseId, disease)
    end

    local feverRelief = 0
    if EHR.Disease and EHR.Disease.GetActiveSymptomReduction then
        feverRelief = EHR.Disease.GetActiveSymptomReduction(player, diseaseId, "fever")
    end

    local feverTarget = feverInfo.temp
    local feverStep = feverInfo.step
    if feverRelief > 0 then
        local strongFeverReducer = feverRelief >= 0.60
        local feverFloor = strongFeverReducer and 37.0 or 37.4
        local feverDrop = strongFeverReducer and 4.0 or math.min(1.2, feverRelief * 1.8)
        feverTarget = math.max(feverFloor, feverTarget - feverDrop)
        feverStep = feverStep * math.max(0.35, 1 - feverRelief)
    end

    local severity = tonumber(disease and disease.severity) or 0.5
    EHR.BodyTemp.MoveDiseaseFeverToward(
        player,
        feverTarget,
        feverStep * severity * math.max(0.25, symptomMult or 1.0)
    )
end

local function EHR_EnvironmentalGetCurrentHour()
    local gameTime = getGameTime and getGameTime() or nil
    return gameTime and gameTime:getWorldAgeHours() or 0
end

function EHR.Environmental.IsHeatStrokeColdBathActive(player)
    local modData = player and player:getModData() or nil
    if not modData or modData.EHR_HeatStrokeColdBathActive ~= true then return false end

    local untilHour = tonumber(modData.EHR_HeatStrokeColdBathUntil) or 0
    if untilHour <= EHR_EnvironmentalGetCurrentHour() then
        modData.EHR_HeatStrokeColdBathActive = nil
        modData.EHR_HeatStrokeColdBathUntil = nil
        return false
    end

    return true
end

function EHR.Environmental.ApplyHeatStrokeColdBathStabilization(player, disease)
    if disease then
        disease.heatStrokeLastDamageHour = EHR_EnvironmentalGetCurrentHour()
    end

    if EHR.BodyTemp and EHR.BodyTemp.MoveDiseaseFeverToward then
        EHR.BodyTemp.MoveDiseaseFeverToward(player, 37.2, 0.22)
    elseif EHR.BodyTemp and EHR.BodyTemp.WriteDiseaseBodyTemperature then
        EHR.BodyTemp.WriteDiseaseBodyTemperature(player, 37.2)
    end
end

function EHR.Environmental.IsHeatStrokeAmbientCoolingActive(player, disease)
    return disease ~= nil and disease.heatStrokeAmbientCoolingActive == true
end

function EHR.Environmental.UpdateHeatStrokeAmbientCooling(player, disease, deltaHours, airTemp)
    if not player or not disease then return false end

    local config = EHR.Environmental.Config or {}
    local threshold = tonumber(config.heatStrokeAmbientCoolingTemp) or 10.0
    local requiredHours = tonumber(config.heatStrokeAmbientCoolingHours) or 3.0
    local decay = tonumber(config.heatStrokeAmbientCoolingDecay) or 0.5
    local currentTemp = tonumber(airTemp)
    if not currentTemp then
        local env = EHR.Environmental.GetRuntimeEnvironment(player) or {}
        currentTemp = tonumber(env.heatAirTemp) or tonumber(env.airTemp) or EHR.Environmental.GetAirTemperature(player)
    end

    local elapsed = tonumber(deltaHours) or 0
    if elapsed < 0 or elapsed > 0.5 then elapsed = 0 end

    local progress = tonumber(disease.heatStrokeAmbientCoolingHours) or 0
    if currentTemp <= threshold then
        progress = math.min(requiredHours, progress + elapsed)
        disease.heatStrokeAmbientCoolingHours = progress
        disease.heatStrokeAmbientCoolingActive = true
        disease.coolingBlocked = false
        disease.heatStrokeLastDamageHour = EHR_EnvironmentalGetCurrentHour()

        if EHR.DEBUG then
            EHR.Log(string.format("Heat stroke ambient cooling: %.2f/%.2fh at %.1fC",
                progress, requiredHours, currentTemp))
        end

        if progress >= requiredHours and EHR.Disease and EHR.Disease.Cure then
            EHR.Log("Heat stroke cured by sustained cold exposure")
            EHR.Disease.Cure(player, "heat_stroke")
        end

        return true
    end

    if progress > 0 then
        progress = math.max(0, progress - (elapsed * decay))
        disease.heatStrokeAmbientCoolingHours = progress > 0 and progress or nil
    end
    disease.heatStrokeAmbientCoolingActive = nil
    return false
end

local function EHR_EnvironmentalIsPlayerAsleep(player)
    if not player or not player.isAsleep then return false end

    local ok, asleep = pcall(function()
        return player:isAsleep()
    end)

    return ok and asleep == true
end

local function EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, reductionKey)
    local multiplier = 1.0

    if EHR.Disease and EHR.Disease.GetActiveSymptomMultiplier then
        local ok, result = pcall(EHR.Disease.GetActiveSymptomMultiplier, player, diseaseId, disease)
        if ok and type(result) == "number" then
            multiplier = result
        end
    end

    if reductionKey and EHR.Disease and EHR.Disease.GetActiveSymptomReduction then
        local ok, reduction = pcall(EHR.Disease.GetActiveSymptomReduction, player, diseaseId, reductionKey)
        if ok and type(reduction) == "number" and reduction > 0 then
            multiplier = multiplier * math.max(0, 1 - reduction)
        end
    end

    return math.max(0.02, math.min(1.0, multiplier))
end

local function EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, reductionKey)
    if not (EHR.Disease and EHR.Disease.GetActiveSymptomReduction) then return 0 end

    local ok, reduction = pcall(EHR.Disease.GetActiveSymptomReduction, player, diseaseId, reductionKey)
    if not ok or type(reduction) ~= "number" then return 0 end
    return math.max(0, math.min(0.95, reduction))
end

local function EHR_EnvironmentalHasOtherSprintBlock(player, ignoredDiseaseId)
    local modData = player and player:getModData() or nil
    local active = modData and modData.EHR_Disease and modData.EHR_Disease.active or nil
    if not active or not EHR.Disease or not EHR.Disease.Diseases then return false end

    for diseaseId, disease in pairs(active) do
        if diseaseId ~= ignoredDiseaseId then
            local def = EHR.Disease.Diseases[diseaseId]
            local effects = def and def.effects and def.effects[disease.stage or 1]
            if effects and effects.canSprint == false then
                return true
            end
        end
    end

    return false
end

local function EHR_EnvironmentalHasOtherSpeedPenalty(player, ignoredDiseaseId)
    local modData = player and player:getModData() or nil
    local active = modData and modData.EHR_Disease and modData.EHR_Disease.active or nil
    if not active or not EHR.Disease or not EHR.Disease.Diseases then return false end

    for diseaseId, disease in pairs(active) do
        if diseaseId ~= ignoredDiseaseId then
            local def = EHR.Disease.Diseases[diseaseId]
            local effects = def and def.effects and def.effects[disease.stage or 1]
            if effects and tonumber(effects.movementPenalty) and tonumber(effects.movementPenalty) < 1.0 then
                return true
            end
        end
    end

    return false
end

function EHR.Environmental.ClearHypothermiaMovementPenalty(player)
    if not player then return end

    local modData = player:getModData()
    if not modData or not modData.EHR_HypothermiaSpeedActive then return end

    if player.setSpeedMod and not EHR_EnvironmentalHasOtherSpeedPenalty(player, "hypothermia") then
        pcall(function() player:setSpeedMod(1.0) end)
    end
    if player.setCanSprint and not EHR_EnvironmentalHasOtherSprintBlock(player, "hypothermia") then
        pcall(function() player:setCanSprint(true) end)
    end

    modData.EHR_HypothermiaSpeedActive = nil
end

function EHR.Environmental.ClearHeatMovementPenalty(player)
    if not player then return end

    local modData = player:getModData()
    if not modData or not modData.EHR_HeatSpeedActive then return end

    if player.setSpeedMod and not EHR_EnvironmentalHasOtherSpeedPenalty(player, nil) then
        pcall(function() player:setSpeedMod(1.0) end)
    end
    if player.setCanSprint and not EHR_EnvironmentalHasOtherSprintBlock(player, nil) then
        pcall(function() player:setCanSprint(true) end)
    end

    modData.EHR_HeatSpeedActive = nil
end

local function EHR_EnvironmentalKillPlayer(player, cause)
    if not player then return end

    if EHR.RecordDeathCause then
        pcall(function() EHR.RecordDeathCause(player, cause or "Severe heat stroke") end)
    end

    pcall(function()
        if player.setHealth then player:setHealth(0) end
    end)

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage and bodyDamage.setOverallBodyHealth then
        pcall(function() bodyDamage:setOverallBodyHealth(0) end)
    end
end

local function EHR_EnvironmentalApplyBodyHealthDamage(player, amount, cause)
    if not player or not amount or amount <= 0 then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return nil end

    local okHealth, currentHealth = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)
    if not okHealth or not currentHealth then return nil end

    if currentHealth <= 0 then return 0 end

    local reduced = false
    if bodyDamage.ReduceGeneralHealth then
        reduced = pcall(function()
            bodyDamage:ReduceGeneralHealth(amount)
        end)
    end

    if reduced then
        local okAfter, afterHealth = pcall(function()
            return bodyDamage:getOverallBodyHealth()
        end)
        if okAfter and afterHealth then
            if afterHealth <= 0 then
                EHR_EnvironmentalKillPlayer(player, cause)
                return 0
            end
            if afterHealth < currentHealth then
                return afterHealth
            end
        end
    end

    local newHealth = math.max(0, currentHealth - amount)
    if newHealth <= 0 then
        EHR_EnvironmentalKillPlayer(player, cause)
        return 0
    end

    if bodyDamage.setOverallBodyHealth then
        pcall(function()
            bodyDamage:setOverallBodyHealth(newHealth)
        end)
    elseif player.setHealth and player.getHealth then
        pcall(function()
            player:setHealth(math.max(0, (player:getHealth() or currentHealth) - amount))
        end)
    end

    return newHealth
end

local function EHR_EnvironmentalClampBodyHealth(player, maxHealth)
    if not player or maxHealth == nil then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage or not bodyDamage.getOverallBodyHealth then return nil end

    local okHealth, currentHealth = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)
    if not okHealth or not currentHealth then return nil end

    local healthCap = math.max(0, math.min(100, tonumber(maxHealth) or 100))
    if currentHealth <= healthCap then return currentHealth end

    local clamped = false
    if bodyDamage.ReduceGeneralHealth then
        clamped = pcall(function()
            bodyDamage:ReduceGeneralHealth(currentHealth - healthCap)
        end)
    end

    if clamped then
        local okAfter, afterHealth = pcall(function()
            return bodyDamage:getOverallBodyHealth()
        end)
        if okAfter and afterHealth and afterHealth <= healthCap + 0.05 then
            return afterHealth
        end
    end

    pcall(function()
        bodyDamage:setOverallBodyHealth(healthCap)
    end)

    return healthCap
end

local function EHR_EnvironmentalApplyHeatStrokeHealthDrain(player, disease, effects)
    local drainPerHour = tonumber(effects and effects.healthDrainPerHour) or 0
    if drainPerHour <= 0 then
        if disease then disease.heatStrokeLastDamageHour = nil end
        return
    end

    if EHR_EnvironmentalGetActiveSymptomReduction(player, "heat_stroke", "healthDrain") >= 0.95 then
        disease.heatStrokeLastDamageHour = EHR_EnvironmentalGetCurrentHour()
        return
    end

    local now = EHR_EnvironmentalGetCurrentHour()
    local last = tonumber(disease and disease.heatStrokeLastDamageHour) or now
    local elapsed = now - last
    if elapsed < 0 or elapsed > 0.5 then
        elapsed = 0
    end
    if disease then disease.heatStrokeLastDamageHour = now end
    if elapsed <= 0 then return end

    local symptomMult = EHR_EnvironmentalGetSymptomMultiplier(player, "heat_stroke", disease, "healthDrain")
    local damage = drainPerHour * elapsed * symptomMult
    if damage <= 0.05 then return end

    EHR_EnvironmentalApplyBodyHealthDamage(
        player,
        damage,
        "Heat Stroke - uncontrolled hyperthermia"
    )
end

local function EHR_EnvironmentalGetBodyHealth(player)
    if not player or not player.getBodyDamage then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage or not bodyDamage.getOverallBodyHealth then return nil end

    local ok, health = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)

    return ok and tonumber(health) or nil
end

local EHR_EnvironmentalHeatStrokeRegenFields = {
    {
        key = "standard",
        get = function(bodyDamage) return bodyDamage:getStandardHealthAddition() end,
        set = function(bodyDamage, value) bodyDamage:setStandardHealthAddition(value) end,
    },
    {
        key = "reduced",
        get = function(bodyDamage) return bodyDamage:getReducedHealthAddition() end,
        set = function(bodyDamage, value) bodyDamage:setReducedHealthAddition(value) end,
    },
    {
        key = "severe",
        get = function(bodyDamage) return bodyDamage:getSeverlyReducedHealthAddition() end,
        set = function(bodyDamage, value) bodyDamage:setSeverlyReducedHealthAddition(value) end,
    },
    {
        key = "sleeping",
        get = function(bodyDamage) return bodyDamage:getSleepingHealthAddition() end,
        set = function(bodyDamage, value) bodyDamage:setSleepingHealthAddition(value) end,
    },
    {
        key = "food",
        get = function(bodyDamage) return bodyDamage:getHealthFromFood() end,
        set = function(bodyDamage, value) bodyDamage:setHealthFromFood(value) end,
    },
    {
        key = "foodTimer",
        get = function(bodyDamage) return bodyDamage:getHealthFromFoodTimer() end,
        set = function(bodyDamage, value) bodyDamage:setHealthFromFoodTimer(value) end,
    },
}

function EHR.Environmental.SetHeatStrokeSleepRegenSuppressed(player, suppressed)
    if not player or not player.getBodyDamage or not player.getModData then return false end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    local modData = player:getModData()
    if not bodyDamage or not modData then return false end

    local state = modData.EHR_HeatStrokeRegenState
    if suppressed then
        if type(state) ~= "table" then
            state = { active = true }
            for _, field in ipairs(EHR_EnvironmentalHeatStrokeRegenFields) do
                local ok, value = pcall(field.get, bodyDamage)
                if ok and type(value) == "number" then
                    state[field.key] = value
                end
            end
            modData.EHR_HeatStrokeRegenState = state
        else
            state.active = true
        end

        for _, field in ipairs(EHR_EnvironmentalHeatStrokeRegenFields) do
            pcall(field.set, bodyDamage, 0)
        end
        return true
    end

    if type(state) ~= "table" then return false end
    for _, field in ipairs(EHR_EnvironmentalHeatStrokeRegenFields) do
        local original = tonumber(state[field.key])
        if original then
            pcall(field.set, bodyDamage, original)
        end
    end
    modData.EHR_HeatStrokeRegenState = nil
    return true
end

local function EHR_EnvironmentalApplyEnduranceCap(player, cap, diseaseId, reductionKey)
    cap = tonumber(cap)
    if not player or not cap or cap <= 0 or not CharacterStat or not CharacterStat.ENDURANCE then return end

    local stats = player:getStats()
    if not stats then return end

    local relief = EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, reductionKey or "breathingDifficulty")
    local effectiveCap = math.min(1.0, cap + ((1.0 - cap) * relief))

    pcall(function()
        local current = stats:get(CharacterStat.ENDURANCE) or 1
        if current > effectiveCap then
            stats:set(CharacterStat.ENDURANCE, effectiveCap)
        end
    end)
end

local function EHR_EnvironmentalApplyHypothermiaHealthDrain(player, disease, effects)
    local drainPerHour = tonumber(effects and effects.healthDrainPerHour) or 0
    if drainPerHour <= 0 then
        if disease then disease.hypothermiaLastDamageHour = nil end
        return
    end

    local now = EHR_EnvironmentalGetCurrentHour()
    local last = tonumber(disease and disease.hypothermiaLastDamageHour) or now
    local elapsed = now - last
    if elapsed < 0 or elapsed > 0.5 then
        elapsed = 0
    end
    if disease then disease.hypothermiaLastDamageHour = now end
    if elapsed <= 0 then return end

    local stage = tonumber(disease and disease.stage) or 1
    local symptomMult = EHR_EnvironmentalGetSymptomMultiplier(player, "hypothermia", disease, "weakness")
    local damage = drainPerHour * elapsed * symptomMult
    if damage <= 0.05 then return end

    EHR_EnvironmentalApplyBodyHealthDamage(
        player,
        damage,
        string.format("Hypothermia - core temperature collapse at stage %d", stage)
    )
end

local function EHR_EnvironmentalApplyHypothermiaEffects(player, disease, effects)
    if not player or not disease or not effects then return end

    local modData = player:getModData()
    if modData then
        modData.EHR_HypothermiaSpeedActive = true
    end

    if effects.canSprint ~= false and player.setCanSprint and not EHR_EnvironmentalHasOtherSprintBlock(player, "hypothermia") then
        pcall(function() player:setCanSprint(true) end)
    end

    if effects.enduranceCap then
        EHR_EnvironmentalApplyEnduranceCap(player, effects.enduranceCap, "hypothermia", "weakness")
    end

    EHR_EnvironmentalApplyHypothermiaHealthDrain(player, disease, effects)
end

local function EHR_EnvironmentalApplyPneumoniaHealthDrain(player, disease, effects)
    local drainPerHour = tonumber(effects and effects.healthDrainPerHour) or 0
    if drainPerHour <= 0 then
        if disease then
            disease.pneumoniaLastDamageHour = nil
            disease.pneumoniaPendingHealthDamage = nil
            disease.pneumoniaHealthCap = nil
        end
        return
    end

    if EHR_EnvironmentalHasActiveDiseaseCureTreatment(player, "pneumonia") then
        if disease then
            disease.pneumoniaLastDamageHour = EHR_EnvironmentalGetCurrentHour()
            disease.pneumoniaPendingHealthDamage = nil
            disease.pneumoniaHealthCap = nil
        end
        return
    end

    if disease and disease.pneumoniaHealthCap then
        EHR_EnvironmentalClampBodyHealth(player, disease.pneumoniaHealthCap)
    end

    local now = EHR_EnvironmentalGetCurrentHour()
    local last = tonumber(disease and disease.pneumoniaLastDamageHour)
        or math.max(0, now - 0.05)
    local elapsed = now - last
    if elapsed < 0 then elapsed = 0 end
    elapsed = math.min(elapsed, 0.5)
    if disease then disease.pneumoniaLastDamageHour = now end
    if elapsed <= 0 then return end

    local symptomMult = EHR_EnvironmentalGetSymptomMultiplier(player, "pneumonia", disease, "healthDrain")
    local damage = drainPerHour * elapsed * symptomMult
    if disease then
        damage = damage + (tonumber(disease.pneumoniaPendingHealthDamage) or 0)
    end
    if damage <= 0.05 then
        if disease then disease.pneumoniaPendingHealthDamage = damage end
        return
    end

    local cap = tonumber(effects.healthDamageCap)
    if cap then
        local currentHealth = EHR_EnvironmentalGetBodyHealth(player)
        if not currentHealth or currentHealth <= cap then
            if disease then disease.pneumoniaPendingHealthDamage = nil end
            return
        end
        damage = math.min(damage, currentHealth - cap)
    end

    if disease then disease.pneumoniaPendingHealthDamage = nil end
    local newHealth = EHR_EnvironmentalApplyBodyHealthDamage(player, damage, "Pneumonia - respiratory failure")
    if disease and newHealth then
        local healthFloor = tonumber(effects.healthDamageCap) or 0
        local newCap = math.max(healthFloor, newHealth)
        disease.pneumoniaHealthCap = math.min(tonumber(disease.pneumoniaHealthCap) or newCap, newCap)
        EHR_EnvironmentalClampBodyHealth(player, disease.pneumoniaHealthCap)
    end
end

local function EHR_EnvironmentalHasHydrationSupport(player)
    if not player then return false end

    local modData = player:getModData()
    local medTracking = modData and modData.EHR_Medication
    local generalEffects = medTracking and medTracking.activeGeneralEffects
    local hydration = generalEffects and generalEffects.electrolytes
    if type(hydration) ~= "table" then return false end

    local endTime = tonumber(hydration.endTime) or 0
    return endTime > EHR_EnvironmentalGetCurrentHour()
end

local function EHR_EnvironmentalHasDysenteryCapRelief(player)
    if not (EHR.Disease and EHR.Disease.GetActiveSymptomReduction) then return false end

    local ok, reduction = pcall(EHR.Disease.GetActiveSymptomReduction, player, "dysentery", "dysenteryCaps")
    return ok and type(reduction) == "number" and reduction > 0
end

local function EHR_EnvironmentalApplyCappedStatDrain(stats, stat, drain, cap)
    if not stats or not stat then return end

    drain = tonumber(drain) or 0
    if drain <= 0 then return end

    local current = stats:get(stat) or 0
    local nextValue = math.min(1, current + drain)
    if cap ~= nil then
        nextValue = math.min(nextValue, math.max(0, math.min(1, tonumber(cap) or 1)))
    end

    if nextValue > current then
        pcall(function()
            stats:set(stat, nextValue)
        end)
    end
end

local function EHR_EnvironmentalApplyBloodLossFloor(player, bloodLoss, bloodFloor)
    bloodLoss = tonumber(bloodLoss) or 0
    if bloodLoss <= 0 then return end
    if not (EHR.Blood and EHR.Blood.ModifyBloodVolume) then return end

    if bloodFloor ~= nil and EHR.GetPlayerData then
        local data = EHR.GetPlayerData(player)
        local bloodData = data and data.EHR_Blood
        if bloodData then
            local currentVolume = tonumber(bloodData.currentVolume) or tonumber(bloodData.maxVolume) or 5000
            bloodFloor = tonumber(bloodFloor) or 0
            if currentVolume <= bloodFloor then return end
            bloodLoss = math.min(bloodLoss, currentVolume - bloodFloor)
        end
    end

    if bloodLoss > 0 then
        EHR.Blood.ModifyBloodVolume(player, -bloodLoss)
    end
end

local function EHR_EnvironmentalGetBodyPartName(partType, part)
    local partName = nil

    if BodyPartType and BodyPartType.ToString then
        pcall(function()
            partName = BodyPartType.ToString(partType)
        end)
    end

    if (not partName or partName == "") and part and part.getType and BodyPartType and BodyPartType.ToString then
        pcall(function()
            partName = BodyPartType.ToString(part:getType())
        end)
    end

    return tostring(partName or partType or "")
end

local function EHR_EnvironmentalFindAbdomenPart(bodyDamage)
    if not bodyDamage or not BodyPartType then return nil, nil end

    local preferred = {"Torso_Lower", "Groin", "Torso_Upper"}
    for _, partName in ipairs(preferred) do
        local partType = BodyPartType[partName]
        if not partType and BodyPartType.FromString then
            local ok, result = pcall(function()
                return BodyPartType.FromString(partName)
            end)
            if ok then partType = result end
        end
        if not partType and BodyPartType.values then
            local okValues, values = pcall(function()
                return BodyPartType.values()
            end)
            if okValues and values then
                local function checkCandidate(candidate)
                    if candidate and tostring(candidate) == tostring(partName) then
                        partType = candidate
                        return true
                    end
                    return false
                end

                if type(values) == "table" then
                    for _, candidate in ipairs(values) do
                        if checkCandidate(candidate) then break end
                    end
                elseif type(values.size) == "function" and type(values.get) == "function" then
                    for i = 0, values:size() - 1 do
                        if checkCandidate(values:get(i)) then break end
                    end
                end
            end
        end

        local part = nil
        if partType then
            pcall(function()
                part = bodyDamage:getBodyPart(partType)
            end)
        end
        if part then return part, partName end
    end

    if BodyPartType.ToIndex and BodyPartType.FromIndex and BodyPartType.MAX then
        for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
            local partType = BodyPartType.FromIndex(i)
            local part = partType and bodyDamage:getBodyPart(partType) or nil
            local partName = EHR_EnvironmentalGetBodyPartName(partType, part)
            local partKey = partName:lower()
            if part and (partKey:find("torso_lower", 1, true)
                    or partKey:find("lower_torso", 1, true)
                    or partKey:find("lower torso", 1, true)
                    or (partKey:find("torso", 1, true) and partKey:find("lower", 1, true))
                    or partKey:find("abdomen", 1, true)
                    or partKey:find("stomach", 1, true)
                    or partKey:find("groin", 1, true)) then
                return part, partName
            end
        end
    end

    return nil, nil
end

local function EHR_EnvironmentalApplyTrackedAbdominalPain(player, targetPain)
    if not player then return end

    local bodyDamage = nil
    pcall(function()
        bodyDamage = player:getBodyDamage()
    end)
    if not bodyDamage then return end

    local bodyPart, partName = EHR_EnvironmentalFindAbdomenPart(bodyDamage)
    if not bodyPart or not bodyPart.getAdditionalPain or not bodyPart.setAdditionalPain then return end

    local modData = player:getModData()
    modData.EHR_DysenteryPain = modData.EHR_DysenteryPain or {}
    local painData = modData.EHR_DysenteryPain
    local painKey = tostring(partName or "abdomen")

    local applied = tonumber(painData[painKey]) or 0
    targetPain = math.max(0, math.min(60, tonumber(targetPain) or 0))
    local step = targetPain > applied and 3.0 or 2.4

    local nextApplied = applied
    if targetPain > applied then
        if applied <= 0.05 then
            nextApplied = math.min(targetPain, math.max(step, targetPain * 0.35))
        else
            nextApplied = math.min(targetPain, applied + step)
        end
    elseif targetPain < applied then
        nextApplied = math.max(targetPain, applied - step)
    end

    local currentPain = nil
    pcall(function()
        currentPain = bodyPart:getAdditionalPain() or 0
    end)

    local shouldRefresh = targetPain > 0
        and nextApplied > 0
        and currentPain ~= nil
        and currentPain < (nextApplied - 0.5)

    if math.abs(nextApplied - applied) < 0.01 and not shouldRefresh then return end

    local delta = nextApplied - applied
    pcall(function()
        local livePain = currentPain
        if livePain == nil then livePain = bodyPart:getAdditionalPain() or 0 end

        local desiredPain = livePain + delta
        if nextApplied > 0 and livePain < nextApplied then
            desiredPain = math.max(desiredPain, nextApplied)
        end

        bodyPart:setAdditionalPain(math.max(0, desiredPain))
    end)

    if nextApplied <= 0.05 then
        painData[painKey] = nil
    else
        painData[painKey] = nextApplied
    end

    if bodyDamage.DamageUpdate then
        pcall(function()
            bodyDamage:DamageUpdate()
        end)
    end
end

function EHR.Environmental.ClearDysenteryPain(player)
    if not player then return end

    local modData = player:getModData()
    local painData = modData and modData.EHR_DysenteryPain
    if type(painData) ~= "table" then return end

    local bodyDamage = nil
    pcall(function()
        bodyDamage = player:getBodyDamage()
    end)
    if not bodyDamage then
        modData.EHR_DysenteryPain = nil
        return
    end

    for painKey, applied in pairs(painData) do
        local bodyPart = nil
        if tostring(painKey) == "abdomen" then
            bodyPart = EHR_EnvironmentalFindAbdomenPart(bodyDamage)
        else
            local partType = BodyPartType and BodyPartType[tostring(painKey)] or nil
            if not partType and BodyPartType and BodyPartType.FromString then
                local ok, result = pcall(function()
                    return BodyPartType.FromString(tostring(painKey))
                end)
                if ok then partType = result end
            end
            if partType then
                pcall(function()
                    bodyPart = bodyDamage:getBodyPart(partType)
                end)
            end
        end

        if bodyPart and bodyPart.getAdditionalPain and bodyPart.setAdditionalPain then
            pcall(function()
                local currentPain = bodyPart:getAdditionalPain() or 0
                bodyPart:setAdditionalPain(math.max(0, currentPain - (tonumber(applied) or 0)))
            end)
        end
    end

    modData.EHR_DysenteryPain = nil
    if bodyDamage.DamageUpdate then
        pcall(function()
            bodyDamage:DamageUpdate()
        end)
    end
end

local function EHR_EnvironmentalFindChestPart(bodyDamage)
    if not bodyDamage or not BodyPartType then return nil, nil end

    local preferred = {"Torso_Upper", "UpperTorso", "Chest"}
    for _, partName in ipairs(preferred) do
        local partType = BodyPartType[partName]
        if not partType and BodyPartType.FromString then
            local ok, result = pcall(function()
                return BodyPartType.FromString(partName)
            end)
            if ok then partType = result end
        end

        local part = nil
        if partType then
            pcall(function()
                part = bodyDamage:getBodyPart(partType)
            end)
        end
        if part then return part, partName end
    end

    if BodyPartType.ToIndex and BodyPartType.FromIndex and BodyPartType.MAX then
        for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
            local partType = BodyPartType.FromIndex(i)
            local part = partType and bodyDamage:getBodyPart(partType) or nil
            local partName = EHR_EnvironmentalGetBodyPartName(partType, part)
            local partKey = partName:lower()
            if part and (partKey:find("torso_upper", 1, true)
                    or partKey:find("upper_torso", 1, true)
                    or partKey:find("upper torso", 1, true)
                    or partKey:find("chest", 1, true)
                    or (partKey:find("torso", 1, true) and partKey:find("upper", 1, true))) then
                return part, partName
            end
        end
    end

    return nil, nil
end

local function EHR_EnvironmentalApplyTrackedChestPain(player, targetPain)
    if not player then return end

    local bodyDamage = nil
    pcall(function()
        bodyDamage = player:getBodyDamage()
    end)
    if not bodyDamage then return end

    local bodyPart, partName = EHR_EnvironmentalFindChestPart(bodyDamage)
    if not bodyPart or not bodyPart.getAdditionalPain or not bodyPart.setAdditionalPain then return end

    local modData = player:getModData()
    modData.EHR_PneumoniaPain = modData.EHR_PneumoniaPain or {}
    local painData = modData.EHR_PneumoniaPain
    local painKey = tostring(partName or "chest")

    local record = painData[painKey]
    local applied = 0
    if type(record) == "table" then
        applied = tonumber(record.applied) or 0
    else
        applied = tonumber(record) or 0
    end

    local currentPain = 0
    pcall(function()
        currentPain = bodyPart:getAdditionalPain() or 0
    end)

    targetPain = math.max(0, math.min(70, tonumber(targetPain) or 0))
    local basePain = math.max(0, currentPain - applied)

    if targetPain <= 0 then
        if applied <= 0.05 then return end
        pcall(function()
            bodyPart:setAdditionalPain(basePain)
        end)
        painData[painKey] = nil
    else
        local desiredPain = basePain + targetPain
        if math.abs(currentPain - desiredPain) > 0.25 then
            pcall(function()
                bodyPart:setAdditionalPain(math.max(0, desiredPain))
            end)
        end
        painData[painKey] = {
            applied = targetPain,
            base = basePain,
        }
    end

    if bodyDamage.DamageUpdate then
        pcall(function()
            bodyDamage:DamageUpdate()
        end)
    end
end

function EHR.Environmental.ClearPneumoniaPain(player)
    if not player then return end

    local modData = player:getModData()
    local painData = modData and modData.EHR_PneumoniaPain
    if type(painData) ~= "table" then return end

    local bodyDamage = nil
    pcall(function()
        bodyDamage = player:getBodyDamage()
    end)
    if not bodyDamage then
        modData.EHR_PneumoniaPain = nil
        return
    end

    for painKey, applied in pairs(painData) do
        local bodyPart = nil
        local appliedAmount = 0
        if type(applied) == "table" then
            appliedAmount = tonumber(applied.applied) or 0
        else
            appliedAmount = tonumber(applied) or 0
        end

        if tostring(painKey) == "chest" then
            bodyPart = EHR_EnvironmentalFindChestPart(bodyDamage)
        else
            local partType = BodyPartType and BodyPartType[tostring(painKey)] or nil
            if not partType and BodyPartType and BodyPartType.FromString then
                local ok, result = pcall(function()
                    return BodyPartType.FromString(tostring(painKey))
                end)
                if ok then partType = result end
            end
            if partType then
                pcall(function()
                    bodyPart = bodyDamage:getBodyPart(partType)
                end)
            end
        end

        if bodyPart and bodyPart.getAdditionalPain and bodyPart.setAdditionalPain then
            pcall(function()
                local currentPain = bodyPart:getAdditionalPain() or 0
                bodyPart:setAdditionalPain(math.max(0, currentPain - appliedAmount))
            end)
        end
    end

    modData.EHR_PneumoniaPain = nil
    if bodyDamage.DamageUpdate then
        pcall(function()
            bodyDamage:DamageUpdate()
        end)
    end
end

local function EHR_EnvironmentalApplyPneumoniaEffects(player, disease, effects)
    if not player or not disease or not effects then return false end

    local currentHour = EHR_EnvironmentalGetCurrentHour()
    if effects.coughIntervalHours and effects.coughIntervalHours > 0 then
        if EHR_EnvironmentalIsPlayerAsleep(player) then
            disease.lastCoughHour = currentHour
        else
            local symptomMult = EHR_EnvironmentalGetSymptomMultiplier(player, "pneumonia", disease, "coughing")
            local effectiveInterval = effects.coughIntervalHours / math.max(0.10, symptomMult)
            local lastCough = tonumber(disease.lastCoughHour)
                or tonumber(disease.stageStartTime)
                or currentHour

            if symptomMult > 0.05 and currentHour - lastCough >= effectiveInterval then
                EHR.Environmental.TriggerCough(player, effects.severeCough == true)
                disease.lastCoughHour = currentHour
            end
        end
    end

    local enduranceCap = tonumber(effects.enduranceCap)
    if not enduranceCap and (tonumber(disease.stage) or 1) >= 3 then
        enduranceCap = 0.70
    end
    EHR_EnvironmentalApplyEnduranceCap(player, enduranceCap, "pneumonia", "breathingDifficulty")
    local painMult = EHR_EnvironmentalGetSymptomMultiplier(player, "pneumonia", disease, "pain")
    EHR_EnvironmentalApplyTrackedChestPain(player, (effects.chestPain or 0) * painMult)
    EHR_EnvironmentalApplyPneumoniaHealthDrain(player, disease, effects)

    return true
end

local function EHR_EnvironmentalApplyDysenteryEffects(player, disease, effects)
    if not player or not disease or not effects then return false end

    local stats = player:getStats()
    if not stats then return false end

    local diarrheaMultiplier = EHR_EnvironmentalGetSymptomMultiplier(player, "dysentery", disease, "diarrhea")
    local vomitMultiplier = EHR_EnvironmentalGetSymptomMultiplier(player, "dysentery", disease, "vomiting")
    local dysenteryVomitMultiplier = EHR_EnvironmentalGetSymptomMultiplier(player, "dysentery", disease, "dysenteryVomiting")
    vomitMultiplier = math.min(vomitMultiplier, dysenteryVomitMultiplier)
    local hydrationSupport = EHR_EnvironmentalHasHydrationSupport(player)
    local capRelief = EHR_EnvironmentalHasDysenteryCapRelief(player)
    local thirstCap = (hydrationSupport or capRelief) and nil or effects.thirstCap
    local hungerCap = capRelief and nil or effects.hungerCap

    if effects.vomitChance and effects.vomitChance > 0 then
        local vomitChance = effects.vomitChance * vomitMultiplier
        if ZombRand(10000) / 10000 < vomitChance then
            EHR.Environmental.TriggerVomit(player, {
                hungerLoss = 0.06,
                thirstLoss = hydrationSupport and 0.03 or 0.08,
                hungerCap = hungerCap,
                thirstCap = thirstCap,
            })
        end
    end

    if effects.bloodLoss and effects.bloodLoss > 0 then
        EHR_EnvironmentalApplyBloodLossFloor(
            player,
            effects.bloodLoss * diarrheaMultiplier,
            effects.bloodLossFloor
        )
    end

    if effects.thirstDrain and CharacterStat and CharacterStat.THIRST then
        local thirstDrain = effects.thirstDrain * diarrheaMultiplier
        if hydrationSupport then
            thirstDrain = thirstDrain * 0.25
        end
        if capRelief then
            thirstDrain = thirstDrain * 0.35
        end
        EHR_EnvironmentalApplyCappedStatDrain(
            stats,
            CharacterStat.THIRST,
            thirstDrain,
            thirstCap
        )
    end

    if effects.hungerDrain and CharacterStat and CharacterStat.HUNGER then
        local hungerDrain = effects.hungerDrain * diarrheaMultiplier
        if capRelief then
            hungerDrain = hungerDrain * 0.35
        end
        EHR_EnvironmentalApplyCappedStatDrain(
            stats,
            CharacterStat.HUNGER,
            hungerDrain,
            hungerCap
        )
    end

    EHR_EnvironmentalApplyTrackedAbdominalPain(player, effects.abdominalPain or 0)

    return true
end

--[[
    Apply environmental disease effects
    Called from disease progression system

    These are disease-specific effects not covered by generic ApplyEffects
]]--
function EHR.Environmental.ApplyDiseaseEffects(player, diseaseId, disease, def)
    local stage = disease.stage
    local effects = def.effects and def.effects[stage]
    if not effects then return end

    local stats = player:getStats()
    if not stats then return end

    if diseaseId == "heat_stroke" and (
        EHR.Environmental.IsHeatStrokeColdBathActive(player) or
        EHR.Environmental.IsHeatStrokeAmbientCoolingActive(player, disease)
    ) then
        EHR.Environmental.SetHeatStrokeSleepRegenSuppressed(player, false)
        disease.heatStrokeSleepHealthCap = nil
        EHR.Environmental.ApplyHeatStrokeColdBathStabilization(player, disease)
        return
    end

    if diseaseId == "heat_stroke" then
        EHR.Environmental.SetHeatStrokeSleepRegenSuppressed(
            player,
            EHR_EnvironmentalIsPlayerAsleep(player)
        )
        disease.heatStrokeSleepHealthCap = nil -- Remove legacy data from the unsafe HP-cap implementation.
    end

    EHR_EnvironmentalApplyBodyFever(player, diseaseId, disease)
    if diseaseId == "heat_stroke" then
        EHR_EnvironmentalApplyHeatStrokeHealthDrain(player, disease, effects)
    elseif diseaseId == "hypothermia" then
        EHR_EnvironmentalApplyHypothermiaEffects(player, disease, effects)
    end
    local dysenteryHandled = false
    local commonColdFatigueHandled = false
    local pneumoniaHandled = false

    -- COMMON COLD: Vanilla cold moodle, capped fatigue, and sneezing.
    if diseaseId == "common_cold" then
        EHR_EnvironmentalSetVanillaCold(player, effects.coldStrength or 0)

        if effects.sneezeIntervalHours and effects.sneezeIntervalHours > 0 then
            local currentHour = EHR_EnvironmentalGetCurrentHour()
            local symptomMult = EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "coughing")
            local effectiveInterval = effects.sneezeIntervalHours / math.max(0.10, symptomMult)
            local lastSneeze = tonumber(disease.lastSneezeHour)
                or tonumber(disease.stageStartTime)
                or currentHour

            if symptomMult > 0.05 and currentHour - lastSneeze >= effectiveInterval then
                EHR.Environmental.TriggerSneeze(player)
                disease.lastSneezeHour = currentHour
            end
        end

        local fatigueCap = tonumber(effects.fatigueCap)
        if fatigueCap and fatigueCap > 0 and effects.fatigueDrain and CharacterStat and CharacterStat.FATIGUE then
            local current = stats:get(CharacterStat.FATIGUE) or 0
            if current < fatigueCap then
                local drain = effects.fatigueDrain
                    * EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "fatigue")
                pcall(function()
                    stats:set(CharacterStat.FATIGUE, math.min(fatigueCap, current + drain))
                end)
            end
            commonColdFatigueHandled = true
        end

        if (disease.stage or 1) == 4 and (effects.coldStrength or 0) <= 0 then
            EHR_EnvironmentalSetVanillaCold(player, 0)
        end
    end

    -- COMMON COLD: Sneezing (legacy definitions without coldStrength)
    if diseaseId == "common_cold" and not effects.sneezeIntervalHours and effects.sneezingChance then
        if ZombRand(1000) / 1000 < effects.sneezingChance then
            EHR.Environmental.TriggerSneeze(player)
        end
    end

    if diseaseId == "pneumonia" then
        pneumoniaHandled = EHR_EnvironmentalApplyPneumoniaEffects(player, disease, effects)
    end

    -- PNEUMONIA: Legacy coughing fits (old definitions without interval data)
    if diseaseId == "pneumonia" and not pneumoniaHandled and effects.coughingChance then
        if ZombRand(1000) / 1000 < effects.coughingChance then
            EHR.Environmental.TriggerCough(player, true)
        end
    end

    -- PNEUMONIA/HYPOTHERMIA: Sprint restriction
    if effects.canSprint == false then
        -- B42: Try to prevent sprinting
        if player.setCanSprint then
            pcall(function() player:setCanSprint(false) end)
        end
        if diseaseId == "heat_stroke" then
            local modData = player:getModData()
            if modData then modData.EHR_HeatSpeedActive = true end
        end
    end

    -- Movement speed penalty
    if effects.movementPenalty and effects.movementPenalty < 1.0 then
        local applySpeedPenalty = true
        if diseaseId == "hypothermia" and EHR_EnvironmentalHasOtherSpeedPenalty(player, "hypothermia") then
            applySpeedPenalty = false
        end
        if applySpeedPenalty and player.setSpeedMod then
            pcall(function() player:setSpeedMod(effects.movementPenalty) end)
        end
        if diseaseId == "heat_stroke" then
            local modData = player:getModData()
            if modData then modData.EHR_HeatSpeedActive = true end
        end
    end

    if diseaseId == "dysentery" then
        dysenteryHandled = EHR_EnvironmentalApplyDysenteryEffects(player, disease, effects)
    end

    -- DYSENTERY: Vomiting
    if diseaseId == "dysentery" and not dysenteryHandled and effects.vomitChance then
        if ZombRand(1000) / 1000 < effects.vomitChance then
            EHR.Environmental.TriggerVomit(player)
        end
    end

    -- DYSENTERY: Blood loss (integration with Blood module)
    if diseaseId == "dysentery" and not dysenteryHandled and effects.bloodLoss then
        if EHR.Blood and EHR.Blood.ModifyBloodVolume then
            -- Apply blood loss using v2.7.0+ API (small amount per tick)
            EHR.Blood.ModifyBloodVolume(player, -effects.bloodLoss)
        end
    end

    -- HYPOTHERMIA: Confusion effects
    if diseaseId == "hypothermia" and effects.confusionChance then
        if ZombRand(1000) / 1000 < effects.confusionChance then
            EHR.Environmental.TriggerConfusion(player, "hypothermia_confusion", (disease.stage or 1) >= 4 and 0.12 or 0.22)
        end
    end

    -- HYPOTHERMIA: dizziness/blurred vision from severe cold
    if diseaseId == "hypothermia" and effects.dizzinessChance then
        if ZombRand(1000) / 1000 < effects.dizzinessChance then
            EHR.Environmental.TriggerDizziness(player, "hypothermia_dizziness", 0.18)
        end
    end

    -- HYPOTHERMIA: collapse and forced sleep in profound hypothermia
    if diseaseId == "hypothermia" and effects.blackoutChance then
        if ZombRand(1000) / 1000 < effects.blackoutChance then
            EHR.Environmental.TriggerHypothermiaBlackout(player)
        end
    end

    -- HEAT STROKE: Dizziness
    if diseaseId == "heat_stroke" and effects.dizzinessChance then
        local chance = effects.dizzinessChance
        if EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, "dizziness") >= 0.95 then
            chance = 0
        end
        chance = chance * EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "dizziness")
        if ZombRand(1000) / 1000 < chance then
            EHR.Environmental.TriggerDizziness(player, "heat_stroke_symptoms", 0.20)
        end
    end

    -- HEAT STROKE: Vomiting from heat
    if diseaseId == "heat_stroke" and effects.vomitChance then
        local chance = effects.vomitChance
        if EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, "vomiting") >= 0.85 then
            chance = 0
        end
        chance = chance * EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "vomiting")
        if ZombRand(1000) / 1000 < chance then
            EHR.Environmental.TriggerVomit(player)
        end
    end

    -- HEAT STROKE: Collapse
    if diseaseId == "heat_stroke" and effects.collapseChance then
        local now = EHR_EnvironmentalGetCurrentHour()
        local checkInterval = 5 / 60 -- One collapse roll per 5 game minutes.
        local lastCheck = tonumber(disease.lastHeatStrokeCollapseCheckHour)
        if not lastCheck then
            disease.lastHeatStrokeCollapseCheckHour = now
        elseif now - lastCheck >= checkInterval then
            disease.lastHeatStrokeCollapseCheckHour = now

            local chance = effects.collapseChance
            if EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, "collapse") >= 0.95 then
                chance = 0
            end
            chance = chance * EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "collapse")
            if ZombRand(1000) / 1000 < chance then
                EHR.Environmental.TriggerHeatStrokeBlackout(player)
            end
        end
    end

    -- HEAT STROKE: Confusion
    if diseaseId == "heat_stroke" and effects.confusionChance then
        local chance = effects.confusionChance
        if EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, "confusion") >= 0.95 then
            chance = 0
        end
        chance = chance * EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "confusion")
        if ZombRand(1000) / 1000 < chance then
            EHR.Environmental.TriggerConfusion(player, "heat_stroke_symptoms", 0.20)
        end
    end

    -- Stat drains
    if effects.fatigueDrain and not commonColdFatigueHandled and CharacterStat and CharacterStat.FATIGUE then
        local current = stats:get(CharacterStat.FATIGUE) or 0
        pcall(function()
            stats:set(CharacterStat.FATIGUE, math.min(1, current + effects.fatigueDrain))
        end)
    end

    if effects.thirstDrain and not dysenteryHandled and CharacterStat and CharacterStat.THIRST then
        local thirstDrain = effects.thirstDrain
        if diseaseId == "heat_stroke" then
            if EHR_EnvironmentalGetActiveSymptomReduction(player, diseaseId, "dehydration") >= 0.95 then
                thirstDrain = 0
            else
                thirstDrain = thirstDrain * EHR_EnvironmentalGetSymptomMultiplier(player, diseaseId, disease, "dehydration")
            end
        end
        local current = stats:get(CharacterStat.THIRST) or 0
        pcall(function()
            stats:set(CharacterStat.THIRST, math.min(1, current + thirstDrain))
        end)
    end

    if effects.hungerDrain and not dysenteryHandled and CharacterStat and CharacterStat.HUNGER then
        local current = stats:get(CharacterStat.HUNGER) or 0
        pcall(function()
            stats:set(CharacterStat.HUNGER, math.min(1, current + effects.hungerDrain))
        end)
    end
end

-- ============================================
-- SYMPTOM TRIGGERS
-- ============================================

local function EHR_EnvironmentalIsFemale(player)
    if not player then return false end

    if player.isFemale then
        local ok, value = pcall(function()
            return player:isFemale()
        end)
        if ok and value ~= nil then
            return value == true
        end
    end

    if player.getDescriptor then
        local okDesc, descriptor = pcall(function()
            return player:getDescriptor()
        end)
        if okDesc and descriptor and descriptor.isFemale then
            local ok, value = pcall(function()
                return descriptor:isFemale()
            end)
            if ok and value ~= nil then
                return value == true
            end
        end
    end

    return false
end

local function EHR_EnvironmentalGetSneezeSfx(player, cfg)
    local female = EHR_EnvironmentalIsFemale(player)
    if female and cfg.sneezeFemaleSfx then
        return cfg.sneezeFemaleSfx
    end
    return cfg.sneezeMaleSfx or cfg.sneezeSfx
end

--[[
    Trigger a sneeze (common cold)
    Creates noise that can attract zombies
]]--
function EHR.Environmental.TriggerSneeze(player)
    local cfg = EHR.Environmental.Config.sound

    -- Say sneeze dialogue
    if player.Say then
        local sneezes = {"*ACHOO!*", "*sneezes*", "*achoo!*"}
        EHR.Locale.Say(player, sneezes[ZombRand(#sneezes) + 1])
    end

    -- Play the audible sneeze SFX at the same moment as the dialogue bark.
    local sfx = EHR_EnvironmentalGetSneezeSfx(player, cfg)
    if sfx and sfx ~= "" and player.playSound then
        pcall(function()
            player:playSound(sfx)
        end)
    end

    -- Create noise for zombie attraction
    -- B42: addWorldSoundUnlessInvisible(radius, volume, stressSound)
    -- stressSound = true makes the sound attract zombies
    if player.addWorldSoundUnlessInvisible then
        pcall(function()
            player:addWorldSoundUnlessInvisible(cfg.sneezeRadius, cfg.sneezeVolume, true)
        end)
    elseif addSound then
        -- Fallback sound method
        pcall(function()
            addSound(player, player:getX(), player:getY(), player:getZ(), cfg.sneezeRadius, cfg.sneezeVolume)
        end)
    end

    EHR.Log("Player sneezed (zombie attraction radius: " .. cfg.sneezeRadius .. ")")
end

--[[
    Trigger a cough (pneumonia)
    Creates LOUD noise that attracts zombies

    @param severe - If true, it's a violent coughing fit
]]--
local function EHR_EnvironmentalGetCoughSfx(player, severe, cfg)
    local female = EHR_EnvironmentalIsFemale(player)

    if severe then
        if female and cfg.coughSevereFemaleSfx then
            return cfg.coughSevereFemaleSfx
        end
        return cfg.coughSevereMaleSfx or cfg.coughSevereSfx
    end

    if female and cfg.coughFemaleSfx then
        return cfg.coughFemaleSfx
    end
    return cfg.coughMaleSfx or cfg.coughSfx
end

local function EHR_EnvironmentalItemMufflesCough(item)
    if not item or not item.hasTag then return false end

    if item.getCurrentUses then
        local okUses, uses = pcall(function()
            return item:getCurrentUses()
        end)
        if okUses and tonumber(uses) and tonumber(uses) <= 0 then
            return false
        end
    end

    local muffleTag = ItemTag and ItemTag.MUFFLE_SNEEZE or nil
    if not muffleTag and ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of then
        pcall(function()
            muffleTag = ItemTag.get(ResourceLocation.of("base:mufflesneeze"))
        end)
    end
    if not muffleTag then return false end

    local ok, hasTag = pcall(function()
        return item:hasTag(muffleTag)
    end)
    return ok and hasTag == true
end

local function EHR_EnvironmentalGetCoughMufflingItem(player)
    if not player then return nil end

    local primary = nil
    local secondary = nil
    pcall(function() primary = player:getPrimaryHandItem() end)
    if EHR_EnvironmentalItemMufflesCough(primary) then
        return primary
    end

    pcall(function() secondary = player:getSecondaryHandItem() end)
    if secondary ~= primary and EHR_EnvironmentalItemMufflesCough(secondary) then
        return secondary
    end

    return nil
end

local function EHR_EnvironmentalConsumeCoughMufflingItem(item)
    if not item or not item.UseAndSync then return false end
    local ok = pcall(function()
        item:UseAndSync()
    end)
    return ok
end

local function EHR_EnvironmentalGetMuffledCoughSfx(player)
    if EHR_EnvironmentalIsFemale(player) then
        return "VoiceFemaleMuffledCough"
    end
    return "VoiceMaleMuffledCough"
end

function EHR.Environmental.TriggerCough(player, severe)
    if not player or EHR_EnvironmentalIsPlayerAsleep(player) then return false end

    local modData = player:getModData()
    local currentHour = EHR_EnvironmentalGetCurrentHour()
    local lastSoundHour = tonumber(modData and modData.EHR_LastCoughSoundHour) or -999999
    if currentHour - lastSoundHour < 0.02 then
        return false
    end
    if modData then
        modData.EHR_LastCoughSoundHour = currentHour
    end

    local cfg = EHR.Environmental.Config.sound
    local mufflingItem = EHR_EnvironmentalGetCoughMufflingItem(player)
    local isMuffled = mufflingItem ~= nil

    -- Say cough dialogue
    if player.Say then
        if severe then
            local coughs = {
                "*VIOLENT COUGHING FIT*",
                "*coughs uncontrollably*",
                "*COUGHING* Can't... stop...",
            }
            EHR.Locale.Say(player, coughs[ZombRand(#coughs) + 1])
        else
            local coughs = {"*cough*", "*coughs*", "*cough cough*"}
            EHR.Locale.Say(player, coughs[ZombRand(#coughs) + 1])
        end
    end

    -- Audible SFX for the player. Zombie attraction is still handled by world sound below.
    if EHR.Environmental.AreCoughSoundsEnabled() then
        local sfx = isMuffled
            and EHR_EnvironmentalGetMuffledCoughSfx(player)
            or EHR_EnvironmentalGetCoughSfx(player, severe, cfg)
        if sfx and sfx ~= "" and player.playSound then
            pcall(function()
                player:playSound(sfx)
            end)
        end
    end

    -- Create noise for zombie attraction
    local radius = severe and cfg.coughSevereRadius or cfg.coughRadius
    local volume = severe and cfg.coughSevereVolume or cfg.coughVolume
    if isMuffled then
        radius = math.max(1, math.floor((radius * (cfg.coughMuffledRadiusMultiplier or 0.15)) + 0.5))
        volume = math.max(1, math.floor((volume * (cfg.coughMuffledVolumeMultiplier or 0.20)) + 0.5))
    end

    if player.addWorldSoundUnlessInvisible then
        pcall(function()
            player:addWorldSoundUnlessInvisible(radius, volume, true)
        end)
    elseif addSound then
        pcall(function()
            addSound(player, player:getX(), player:getY(), player:getZ(), radius, volume)
        end)
    end

    if isMuffled then
        EHR_EnvironmentalConsumeCoughMufflingItem(mufflingItem)
    end

    EHR.Log(string.format(
        "Player coughed (severe=%s, muffled=%s, radius=%d)",
        tostring(severe),
        tostring(isMuffled),
        radius
    ))
    return true
end

--[[
    Trigger vomiting (dysentery/heat)
    Causes food/water loss and noise
]]--
function EHR.Environmental.TriggerVomit(player, options)
    local cfg = EHR.Environmental.Config.sound
    options = options or {}

    -- Say vomit dialogue
    if player.Say then
        local vomits = {"*vomits*", "*retches violently*", "*throws up*"}
        EHR.Locale.Say(player, vomits[ZombRand(#vomits) + 1])
    end

    -- Increase hunger (lost food)
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.HUNGER and not options.skipHungerLoss then
        local current = stats:get(CharacterStat.HUNGER) or 0
        local loss = tonumber(options.hungerLoss) or 0.1
        local nextValue = math.min(1, current + loss)
        if options.hungerCap ~= nil then
            nextValue = math.min(nextValue, math.max(0, math.min(1, tonumber(options.hungerCap) or 1)))
        end
        pcall(function()
            if nextValue > current then
                stats:set(CharacterStat.HUNGER, nextValue)
            end
        end)
    end

    -- Increase thirst (lost fluids)
    if stats and CharacterStat and CharacterStat.THIRST and not options.skipThirstLoss then
        local current = stats:get(CharacterStat.THIRST) or 0
        local loss = tonumber(options.thirstLoss) or 0.15
        local nextValue = math.min(1, current + loss)
        if options.thirstCap ~= nil then
            nextValue = math.min(nextValue, math.max(0, math.min(1, tonumber(options.thirstCap) or 1)))
        end
        pcall(function()
            if nextValue > current then
                stats:set(CharacterStat.THIRST, nextValue)
            end
        end)
    end

    -- Sound from vomiting
    if player.addWorldSoundUnlessInvisible then
        pcall(function()
            player:addWorldSoundUnlessInvisible(cfg.vomitRadius, cfg.vomitVolume, true)
        end)
    end

    EHR.Log("Player vomited")
end

local function EHR_EnvironmentalSayLimited(player, cooldownKey, cooldownHours, lines)
    if not player or not player.Say or not lines or #lines == 0 then return false end

    if cooldownKey and cooldownHours and cooldownHours > 0 then
        local modData = player:getModData()
        if modData then
            modData.EHR_EnvironmentalDialogueCooldowns = modData.EHR_EnvironmentalDialogueCooldowns or {}
            local currentHour = EHR_EnvironmentalGetCurrentHour()
            local lastHour = tonumber(modData.EHR_EnvironmentalDialogueCooldowns[cooldownKey]) or -999999
            if (currentHour - lastHour) >= 0 and (currentHour - lastHour) < cooldownHours then
                return false
            end
            modData.EHR_EnvironmentalDialogueCooldowns[cooldownKey] = currentHour
        end
    end

    EHR.Locale.Say(player, lines[ZombRand(#lines) + 1])
    return true
end

--[[
    Trigger confusion effect (hypothermia)
    Causes disorientation
]]--
function EHR.Environmental.TriggerConfusion(player, cooldownKey, cooldownHours)
    -- Say confusion dialogue
    EHR_EnvironmentalSayLimited(player, cooldownKey, cooldownHours, {
        "*stumbles* Where... am I?",
        "*confused* What was I doing...?",
        "*disoriented* Can't... think straight...",
    })

    -- Apply panic (disorientation effect)
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.PANIC then
        local current = stats:get(CharacterStat.PANIC) or 0
        pcall(function()
            stats:set(CharacterStat.PANIC, math.min(1, current + 0.15))
        end)
    end

    EHR.Log("Player confused (hypothermia)")
end

--[[
    Trigger muscle cramp (heat exhaustion)
    Causes pain and movement slowdown
]]--
function EHR.Environmental.TriggerCramp(player)
    if player.Say then
        local cramps = {
            "*cramps* Ow, my leg!",
            "*muscles seize up*",
            "*winces* Cramp!",
        }
        EHR.Locale.Say(player, cramps[ZombRand(#cramps) + 1])
    end

    -- Apply pain
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.PAIN then
        local current = stats:get(CharacterStat.PAIN) or 0
        pcall(function()
            stats:set(CharacterStat.PAIN, math.min(1, current + 0.1))
        end)
    end

    EHR.Log("Player cramped (heat exhaustion)")
end

--[[
    Trigger dizziness (heat exhaustion/stroke)
    Causes disorientation and stumbling
]]--
function EHR.Environmental.TriggerDizziness(player, cooldownKey, cooldownHours)
    local isLocalPlayer = false
    if player and player.isLocalPlayer then
        pcall(function()
            isLocalPlayer = player:isLocalPlayer()
        end)
    end

    if isLocalPlayer and EHR.ToxinVision and EHR.ToxinVision.StartSymptomEpisode then
        pcall(function()
            EHR.ToxinVision.StartSymptomEpisode(player)
        end)
    end

    EHR_EnvironmentalSayLimited(player, cooldownKey, cooldownHours, {
        "*dizzy* World's spinning...",
        "*stumbles*",
        "*sways* Can't focus...",
    })

    -- Apply panic (disorientation)
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.PANIC then
        local current = stats:get(CharacterStat.PANIC) or 0
        pcall(function()
            stats:set(CharacterStat.PANIC, math.min(1, current + 0.2))
        end)
    end

    EHR.Log("Player dizzy (heat)")
end

local function EHR_EnvironmentalTriggerBackwardFall(player)
    if not player then return false end

    if EHR.TendonWeakness and EHR.TendonWeakness.TriggerFall then
        local ok, result = pcall(EHR.TendonWeakness.TriggerFall, player, "standing")
        if ok and result then return true end
    end

    if player.setBumpType and player.setVariable then
        local ok = pcall(function()
            player:setBumpType("stagger")
            player:setVariable("BumpDone", false)
            player:setVariable("BumpFall", true)
            player:setVariable("BumpFallType", "pushedFront")
        end)
        if ok then return true end
    end

    if player.setKnockedDown then
        local ok = pcall(function() player:setKnockedDown(true) end)
        if ok then return true end
    end

    return false
end

local function EHR_EnvironmentalForceSleep(player, hours)
    if not player then return false end

    hours = math.max(0.25, tonumber(hours) or 1)

    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.FATIGUE then
        pcall(function()
            stats:set(CharacterStat.FATIGUE, 1)
        end)
    end

    local timeOfDay = 0
    local gameTime = GameTime and GameTime.getInstance and GameTime.getInstance() or (getGameTime and getGameTime() or nil)
    if gameTime and gameTime.getTimeOfDay then
        pcall(function()
            timeOfDay = gameTime:getTimeOfDay()
        end)
    end

    local wakeUpTime = timeOfDay + hours
    while wakeUpTime >= 24 do
        wakeUpTime = wakeUpTime - 24
    end

    pcall(function()
        if player.setForceWakeUpTime then player:setForceWakeUpTime(wakeUpTime) end
        if player.setAsleepTime then player:setAsleepTime(0.0) end
        if player.setAsleep then player:setAsleep(true) end
    end)

    local sleepingEvent = getSleepingEvent and getSleepingEvent() or nil
    if sleepingEvent and sleepingEvent.setPlayerFallAsleep then
        pcall(function()
            sleepingEvent:setPlayerFallAsleep(player, hours)
        end)
    end

    if UIManager and player.getPlayerNum then
        local playerNum = player:getPlayerNum()
        pcall(function()
            if UIManager.setFadeBeforeUI then UIManager.setFadeBeforeUI(playerNum, true) end
            if UIManager.FadeOut then UIManager.FadeOut(playerNum, 1) end
        end)
    end

    return true
end

function EHR.Environmental.TriggerHeatStrokeBlackout(player)
    if not player then return false end
    if EHR.Environmental.IsHeatStrokeColdBathActive and EHR.Environmental.IsHeatStrokeColdBathActive(player) then
        return false
    end

    local alive = true
    if player.isAlive then
        pcall(function()
            alive = player:isAlive()
        end)
    end
    if not alive then return false end

    local asleep = false
    if player.isAsleep then
        pcall(function()
            asleep = player:isAsleep()
        end)
    end
    if asleep then return false end

    -- Disable vanilla health additions before forced sleep begins. This pauses
    -- sleep/food regeneration without repeatedly damaging individual body parts.
    EHR.Environmental.SetHeatStrokeSleepRegenSuppressed(player, true)

    EHR_EnvironmentalSayLimited(player, "heat_stroke_symptoms", 0.20, {
        "*delirious* Too hot...",
        "*confused* I can't stay awake...",
        "*dazed* Everything is burning...",
        "*collapses*",
    })

    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.PANIC then
        pcall(function()
            stats:set(CharacterStat.PANIC, math.max(stats:get(CharacterStat.PANIC) or 0, 0.8))
        end)
    end

    EHR_EnvironmentalTriggerBackwardFall(player)
    EHR_EnvironmentalForceSleep(player, 1)

    EHR.Log("Heat stroke blackout triggered - backward fall and 1 hour forced sleep")
    return true
end

function EHR.Environmental.TriggerHypothermiaBlackout(player)
    if not player then return false end

    local alive = true
    if player.isAlive then
        pcall(function()
            alive = player:isAlive()
        end)
    end
    if not alive then return false end

    local asleep = false
    if player.isAsleep then
        pcall(function()
            asleep = player:isAsleep()
        end)
    end
    if asleep then return false end

    local modData = player:getModData()
    local now = EHR_EnvironmentalGetCurrentHour()
    local cooldownHours = 0.75
    local lastBlackout = tonumber(modData and modData.EHR_HypothermiaBlackoutHour) or nil
    if lastBlackout and (now - lastBlackout) >= 0 and (now - lastBlackout) < cooldownHours then
        return false
    end

    if modData then
        modData.EHR_HypothermiaBlackoutHour = now
    end

    EHR_EnvironmentalSayLimited(player, "hypothermia_blackout", 0.30, {
        "*slurred* Can't... stay awake...",
        "*collapses* So cold...",
        "*dazed* Everything is fading...",
        "*mumbles* Need... warmth...",
    })

    EHR_EnvironmentalTriggerBackwardFall(player)
    EHR_EnvironmentalForceSleep(player, 1)

    EHR.Log("Hypothermia blackout triggered - backward fall and 1 hour forced sleep")
    return true
end

--[[
    Trigger collapse (heat stroke)
    Causes player to fall down temporarily
]]--
function EHR.Environmental.TriggerCollapse(player)
    if player.Say then
        EHR.Locale.Say(player, "*collapses*")
    end

    -- Apply massive fatigue
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.FATIGUE then
        local current = stats:get(CharacterStat.FATIGUE) or 0
        pcall(function()
            stats:set(CharacterStat.FATIGUE, math.min(1, current + 0.3))
        end)
    end

    -- Apply panic
    if stats and CharacterStat and CharacterStat.PANIC then
        pcall(function()
            stats:set(CharacterStat.PANIC, 0.8)
        end)
    end

    -- Try to knock player down (B42 method)
    if player.setKnockedDown then
        pcall(function() player:setKnockedDown(true) end)
    elseif player.setFallOnFront then
        pcall(function() player:setFallOnFront(true) end)
    end

    EHR.Log("Player collapsed (heat stroke)")
end

-- ============================================
-- HYPOTHERMIA WARMTH CHECK (MED-003 fix)
-- ============================================

--[[
    Check if player is "warm" for hypothermia recovery
    BUG-016 FIX: Added body temperature check

    Warmth sources (any of these = warm):
    - Near a heat source (fireplace, stove, campfire)
    - Indoors with air temp > 5C
    - Body temperature > 0.5 (normal is ~0.5, higher = warming up)
    - This covers hot baths, exercising, heating systems
]]--
function EHR.Environmental.IsWarmEnoughForRecovery(player)
    -- Check custom body temperature system first (if enabled)
    if EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled() then
        if EHR.BodyTemp.IsWarmEnoughForRecovery(player) then
            if EHR.DEBUG then
                local tempData = EHR.BodyTemp.GetTemperatureData(player)
                local temp = tempData and tempData.bodyTemp or 0
                EHR.Log(string.format("Hypothermia recovery: Custom body temp %.1fC is warm enough", temp))
            end
            return true
        end
        -- If body temp system says not warm enough, check heat source as override
        if EHR.Environmental.IsNearHeat(player) then
            return true
        end
        return false
    end

    -- Fallback to vanilla-based checks when body temp system is disabled
    -- Check if near heat source
    if EHR.Environmental.IsNearHeat(player) then
        return true
    end

    local bodyTemp = EHR.Environmental.GetBodyTemperature(player)
    local isIndoors = EHR.Environmental.IsIndoors(player)

    -- BUG-017 FIX: Use body temperature for indoor warmth check
    -- GetAirTemperature(player) may return ICL's simulated room temperature.
    -- Body temperature reflects actual player warmth from room heating, clothing, etc.
    --
    -- Indoor with reasonable body temp (>0.4) = warm enough
    -- This handles heated rooms, good clothing insulation, etc.
    if isIndoors and bodyTemp > 0.4 then
        if EHR.DEBUG then
            EHR.Log(string.format("Hypothermia recovery: Indoors with body temp %.2f", bodyTemp))
        end
        return true
    end

    -- High body temp (>0.55) = actively warming up (works anywhere)
    -- This covers hot baths, exercise, heaters, etc.
    if bodyTemp > 0.55 then
        EHR.Log(string.format("Hypothermia recovery: Body temp %.2f is warm enough", bodyTemp))
        return true
    end

    return false
end

--[[
    Check if hypothermia should be blocked from recovering
    Hypothermia cannot naturally progress to recovery (stage 4) unless player is warm
    If player is in recovery but gets cold again, regress to peak stage

    BUG-016 FIX: Extended duration while cold, use body temperature for warmth
]]--
function EHR.Environmental.CheckHypothermiaWarmth(player)
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return end

    local hypothermia = diseaseData.active["hypothermia"]
    if not hypothermia then return end

    local def = EHR.Disease.Diseases["hypothermia"]
    if not def or not def.requiresWarmthForRecovery then return end
    if def.stageDrivenByBodyTemperature and EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled() then
        return
    end

    -- Check if player is warm (now includes body temperature)
    local isWarm = EHR.Environmental.IsWarmEnoughForRecovery(player)

    -- If in recovery (stage 4) but not warm, regress to peak (stage 3)
    if hypothermia.stage == 4 and not isWarm then
        hypothermia.stage = 3
        hypothermia.stageStartTime = getGameTime():getWorldAgeHours()

        EHR.Log("Hypothermia: Regressed from recovery to peak (not warm enough)")

        if player.Say then
            EHR.Locale.Say(player, "*shivers* I'm getting cold again... can't stay warm...")
        end
    end

    -- BUG-016 FIX: If at peak (stage 3) and NOT warm, block recovery AND extend duration
    if hypothermia.stage == 3 and not isWarm then
        hypothermia.warmthBlocked = true

        -- Extend endTime to prevent automatic recovery
        -- Push endTime forward by 0.1 game hours per check while cold
        local currentHour = getGameTime():getWorldAgeHours()
        if hypothermia.endTime and currentHour > hypothermia.endTime - 2 then
            hypothermia.endTime = hypothermia.endTime + 0.1
            if EHR.DEBUG then
                EHR.Log(string.format("Hypothermia: Extended duration (not warm), new end: %.1f", hypothermia.endTime))
            end
        end
    else
        hypothermia.warmthBlocked = false

        -- If warm and was previously blocked, allow recovery to happen
        if isWarm and hypothermia.stage == 3 then
            EHR.Log("Hypothermia: Player is warm, recovery can proceed")
        end
    end
end

-- ============================================
-- DEATH CHECKS
-- ============================================

--[[
    Check if lethal disease should kill player
    Called during disease progression for canKill diseases
]]--
function EHR.Environmental.CheckDiseaseLethal(player, diseaseId, disease, def)
    if not def.canKill then return end

    -- Heat stroke is lethal through continuous health damage, not a random instant death roll.
    if def.killMechanic == "healthDrain" then return end

    if disease.stage ~= def.deathStage then return end

    -- Special case: Dysentery kills through dehydration
    if def.killMechanic == "dehydration" then
        local stats = player:getStats()
        if stats and CharacterStat and CharacterStat.THIRST then
            local thirst = stats:get(CharacterStat.THIRST) or 0
            if thirst >= (def.deathThirstLevel or 0.95) then
                EHR.Log("Player died from dehydration (dysentery)")
                -- Let vanilla handle death from dehydration
                -- Just ensure thirst stays maxed
                pcall(function()
                    stats:set(CharacterStat.THIRST, 1.0)
                end)
            end
        end
        return
    end

    -- Check for treatment reducing death chance
    local deathChance = def.deathChancePerHour or 0.01
    if disease.treated and def.treatmentReducesDeath then
        deathChance = deathChance * (1 - def.treatmentReducesDeath)
    end

    -- Hypothermia: Being warm PREVENTS death (not just reduces chance)
    -- BUG-018 FIX: If player is warm (indoors 22C, near heat, etc.), they should NOT die
    -- Previous code only reduced death by 95%, which still allowed random deaths over time
    if diseaseId == "hypothermia" then
        -- BUG-017 FIX: Use IsWarmEnoughForRecovery() for consistent warmth check
        -- This uses body temperature instead of outdoor air temperature
        local isWarm = EHR.Environmental.IsWarmEnoughForRecovery(player)
        if isWarm then
            -- CRITICAL: Being warm completely prevents hypothermia death
            -- You don't die from hypothermia while in a 22C room!
            if EHR.DEBUG then
                EHR.Log("Hypothermia: Player is warm - death check SKIPPED (cannot die while warm)")
            end
            return  -- Exit function entirely - no death check when warm
        end
    end

    -- Convert per-hour to per-tick (assume this runs every ~2 seconds)
    -- ~1800 ticks per game hour, we run every 60 ticks = 30 checks/hour
    local tickChance = deathChance / 30

    if ZombRand(10000) / 10000 < tickChance then
        EHR.Log(string.format("LETHAL: %s killed player (chance was %.4f%%)", def.name, tickChance * 100))

        -- DEATH CAUSE TRACKING: Record cause before killing
        local stageName = {"Incubation", "Early", "Peak", "Recovery"}
        EHR.RecordDeathCause(player, string.format("%s (Stage %d - %s) - lethal disease progression",
            def.name or diseaseId, disease.stage or 0, stageName[disease.stage] or "Unknown"))

        -- Trigger death
        if player.setHealth then
            pcall(function() player:setHealth(0) end)
        end

        -- Death message
        if player.Say then
            if diseaseId == "pneumonia" then
                EHR.Locale.Say(player, "*gasps* Can't... breathe...")
            elseif diseaseId == "cadaveric_aspergillosis" then
                EHR.Locale.Say(player, "*wheezes* Can't... breathe...")
            elseif diseaseId == "hypothermia" then
                EHR.Locale.Say(player, "So... cold... tired...")
            end
        end
    end
end

-- ============================================
-- TREATMENT HOOKS
-- ============================================

--[[
    Check if consuming an item treats a disease
    Called when player uses medicine items
]]--
function EHR.Environmental.CheckTreatment(player, item)
    if not player or not item then return end

    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return end

    -- Get item type
    local itemType = nil
    if item.getType then
        local success, result = pcall(function() return item:getType() end)
        if success then itemType = result end
    end
    if not itemType and item.getFullType then
        local success, result = pcall(function() return item:getFullType() end)
        if success then itemType = result end
    end

    if not itemType then return end
    itemType = tostring(itemType)

    -- Check each active disease for treatment
    for diseaseId, disease in pairs(diseaseData.active) do
        local def = EHR.Disease.Diseases[diseaseId]
        if def and def.treatmentItem then
            -- Check if this item matches treatment
            if string.find(itemType, def.treatmentItem) then
                disease.treated = true
                EHR.Log(string.format("Treated %s with %s", diseaseId, itemType))

                -- Some diseases can be cured with treatment
                if def.treatmentCured and disease.stage >= 2 then
                    -- Move to recovery stage
                    disease.stage = 4

                    if player.Say then
                        EHR.Locale.Say(player, "This medicine should help...")
                    end
                end
            end
        end
    end
end

-- ============================================
-- TICK MANAGEMENT
-- ============================================

local ENVIRONMENTAL_TICK_INTERVAL = 90  -- Check every 90 ticks (~3 seconds)

local GAME_HOUR_CHECK_INTERVAL = 0.1    -- Check every ~6 game minutes

-- MP: per-player tick state (avoid shared counters across players)
local tickStateByPlayer = {}

local function getPlayerId(player)
    return EHR.Environmental.GetPlayerKey(player)
end

local function getTickState(player)
    local id = getPlayerId(player) or "0"
    local state = tickStateByPlayer[id]
    if not state then
        state = { tick = 0, lastHour = 0 }
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

local function processPlayerTick(player)
    if not player or not player:isAlive() then return end

    -- CRITICAL: Suppress vanilla effects EVERY TICK
    -- Must run before throttle to prevent vanilla from killing player between our checks

    -- Temperature suppression: If body temp system is enabled, it handles this in its own OnTick
    -- Only call old suppression if body temp system is disabled
    if not (EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled()) then
        EHR.Environmental.SuppressVanillaTemperature(player)
    end

    -- Cold/Sickness suppression: Always run (handles SICKNESS stat for coughing moodle)
    -- This is separate from body temperature suppression
    EHR.Environmental.SuppressVanillaCold(player)

    -- Initialize if needed
    EHR.Environmental.InitializePlayer(player)

    -- Get exposure data
    local exposure = EHR.Environmental.GetExposureData(player)
    if not exposure then return end

    local state = getTickState(player)

    -- Throttle updates
    state.tick = state.tick + 1
    if state.tick < ENVIRONMENTAL_TICK_INTERVAL then
        return
    end
    state.tick = 0

    -- Calculate delta time in game hours
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()
    local lastHour = state.lastHour > 0 and state.lastHour or currentHour
    local deltaHours = currentHour - lastHour

    -- Sanity check (don't process huge deltas from loading)
    if deltaHours > 1 or deltaHours < 0 then
        deltaHours = GAME_HOUR_CHECK_INTERVAL
    end
    state.lastHour = currentHour

    -- Update cold exposure
    EHR.Environmental.UpdateColdExposure(player, deltaHours)

    -- Update heat exposure
    EHR.Environmental.UpdateHeatExposure(player, deltaHours)

    -- Check cold -> pneumonia progression
    EHR.Environmental.CheckColdProgression(player, exposure)

    -- Check hypothermia warmth requirement (MED-003)
    EHR.Environmental.CheckHypothermiaWarmth(player)

    -- Check heat cooling requirement
    EHR.Environmental.CheckHeatCooling(player, deltaHours)

    -- Apply disease-specific effects for active diseases
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    local hasHypothermia = false
    local hasHeatCondition = false
    if diseaseData and diseaseData.active then
        for diseaseId, disease in pairs(diseaseData.active) do
            if diseaseId == "hypothermia" then
                hasHypothermia = true
            end
            if diseaseId == "heat_stroke" then
                hasHeatCondition = true
            end
            local def = EHR.Disease.Diseases[diseaseId]
            if def then
                -- Apply environmental disease effects
                if diseaseId == "common_cold" or diseaseId == "pneumonia" or
                   diseaseId == "dysentery" or diseaseId == "hypothermia" or
                   diseaseId == "heat_stroke" then
                    EHR.Environmental.ApplyDiseaseEffects(player, diseaseId, disease, def)
                    EHR.Environmental.CheckDiseaseLethal(player, diseaseId, disease, def)
                end
            end
        end
    end
    if not hasHypothermia then
        EHR.Environmental.ClearHypothermiaMovementPenalty(player)
    end
    if not hasHeatCondition then
        EHR.Environmental.SetHeatStrokeSleepRegenSuppressed(player, false)
        EHR.Environmental.ClearHeatMovementPenalty(player)
    end
end

local function processClientEnvironmentalTick(player, snapshotOnly)
    if not player or not player:isAlive() then return end

    EHR.Environmental.InitializePlayer(player)

    local exposure = EHR.Environmental.GetExposureData(player)
    if not exposure then return end

    local state = getTickState(player)
    state.tick = state.tick + 1
    if state.tick < ENVIRONMENTAL_TICK_INTERVAL then
        return
    end
    state.tick = 0

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local lastHour = state.lastHour > 0 and state.lastHour or currentHour
    local deltaHours = currentHour - lastHour
    if deltaHours > 1 or deltaHours < 0 then
        deltaHours = GAME_HOUR_CHECK_INTERVAL
    end
    state.lastHour = currentHour

    local snapshot = EHR.Environmental.BuildClientSnapshot(player)
    if snapshot and isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR", "EnvironmentalSnapshot", snapshot)
    end

    if snapshotOnly then return end

    -- Keep local exposure cards responsive in multiplayer, but leave disease
    -- contraction/progression to the server-authoritative tick.
    EHR.Environmental._skipDiseaseChecks = true
    local okCold, errCold = pcall(EHR.Environmental.UpdateColdExposure, player, deltaHours)
    local okHeat, errHeat = pcall(EHR.Environmental.UpdateHeatExposure, player, deltaHours)
    EHR.Environmental._skipDiseaseChecks = false

    if EHR.DEBUG then
        if not okCold then EHR.Log("Environmental client cold prediction failed: " .. tostring(errCold)) end
        if not okHeat then EHR.Log("Environmental client heat prediction failed: " .. tostring(errHeat)) end
    end
end

--[[
    Main tick handler for environmental diseases
]]--
function EHR.Environmental.OnTick()
    local diseaseEnabled = not EHR.Disease or EHR.Disease.IsEnabled()

    -- MP: server-authoritative progression, client-only suppression
    if isClient and isClient() and not (isServer and isServer()) then
        local player = getSpecificPlayer(0)
        if player then
            if diseaseEnabled then
                if not (EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled()) then
                    EHR.Environmental.SuppressVanillaTemperature(player)
                end
                EHR.Environmental.SuppressVanillaCold(player)
            end
            -- The snapshot also carries ICL ambient data for EHR body
            -- temperature, so keep it alive when diseases are disabled.
            processClientEnvironmentalTick(player, not diseaseEnabled)
        end
        return
    end

    if not diseaseEnabled then return end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- DRINK HOOK ENHANCEMENT
-- ============================================

--[[
    Enhanced drink hook that checks water contamination
    Called from FoodHook module
]]--
function EHR.Environmental.OnDrink(player, item, sourceType)
    EHR.Environmental.OnDrinkWater(player, item, sourceType)
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function EHR.Environmental.OnGameStart()
    EHR.Log("Environmental diseases module OnGameStart")

    local player = getSpecificPlayer(0)
    if player then
        EHR.Environmental.InitializePlayer(player)
    end
end

function EHR.Environmental.OnCreatePlayer(playerIndex, player)
    EHR.Log("Environmental diseases module OnCreatePlayer: " .. playerIndex)
    EHR.Environmental.InitializePlayer(player)
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

-- Guard against double registration (MIN-003 fix)
if Events and not EHR.Environmental._eventsRegistered then
    EHR.Environmental._eventsRegistered = true

    Events.OnTick.Add(EHR.Environmental.OnTick)
    Events.OnGameStart.Add(EHR.Environmental.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.Environmental.OnCreatePlayer)

    EHR.Log("Environmental diseases module events registered")
end

EHR.Log("Environmental diseases module loaded v1.0.0")
