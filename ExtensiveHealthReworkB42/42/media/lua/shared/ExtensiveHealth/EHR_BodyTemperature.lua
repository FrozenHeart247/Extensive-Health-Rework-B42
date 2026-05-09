--[[
    Extensive Health Rework B42
    Body Temperature Module

    Custom body temperature tracking system that replaces vanilla TEMPERATURE stat.
    Provides gradual pre-disease effects (shivering, sweating) and smooth
    transitions to hypothermia/heat exhaustion diseases.

    Normal body temperature: 37.0°C (98.6°F)
    Hypothermia risk: < 34.0°C
    Heat exhaustion risk: > 40.5°C

    v1.0.0 - Initial implementation
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.BodyTemp = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.BodyTemp.Config = {
    -- Normal body temperature (Celsius)
    normalTemp = 37.0,

    -- Comfort zone (air temperature range where body maintains 37°C easily)
    -- Within this range, body temperature stays stable without effort
    comfortZoneMin = 10.0,   -- Below this, start feeling cold (lowered from 12.0)
    comfortZoneMax = 28.0,   -- Above this, start feeling hot
    comfortZoneCenter = 20.0, -- Ideal temperature (for reference)

    -- Cold thresholds (Celsius) - adjusted to be less sensitive
    -- Normal body temp can range 36.0-37.5°C in healthy people
    coldStage1 = 36.0,   -- Chilly (lowered from 36.5 - 36.4°C is normal!)
    coldStage2 = 35.5,   -- Cold (lowered from 36.0)
    coldStage3 = 35.0,   -- Very Cold
    coldStage4 = 34.0,   -- Hypothermia Risk

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

    -- Disease trigger timing (game hours at dangerous temp)
    hypothermiaTriggerTime = 0.5,    -- 30 game minutes at < 34°C to trigger hypothermia
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
    pneumonia = {
        [2] = 38.1,
        [3] = 39.0,
        [4] = 37.6,
    },
    common_cold = {
        [3] = 37.8,
        [4] = 37.2,
    },
    tuberculosis = {
        [2] = 37.7,
        [3] = 38.4,
        [4] = 37.3,
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
            bestTarget = math.max(bestTarget or target, target)
        end
    end

    local woundData = modData.EHR_WoundInfection
    local woundStage = woundData and tonumber(woundData.worstStage) or 0
    if woundStage > 0 then
        local target = EHR_BodyTempGetStageTarget(EHR.BodyTemp.DiseaseFeverTargets.wound_infection, woundStage)
        if target then
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

    local function moveValue(current)
        current = tonumber(current) or target
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
        tempData.diseaseFeverActive = target > ((cfg.normalTemp or 37.0) + 0.2)

        local gameTime = getGameTime and getGameTime() or nil
        tempData.diseaseTargetTempUntil = gameTime and (gameTime:getWorldAgeHours() + 1.0) or nil
    end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        pcall(function()
            if not nextTemp then
                local current = stats:get(CharacterStat.TEMPERATURE) or target
                nextTemp = moveValue(current)
            end
            stats:set(CharacterStat.TEMPERATURE, nextTemp)
        end)
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

    local normalTemp = EHR.BodyTemp.Config.normalTemp or 37.0
    tempData.diseaseTargetTemp = nil
    tempData.diseaseTargetTempUntil = nil
    tempData.diseaseFeverActive = false
    tempData.targetTemp = normalTemp
    tempData.hotStage = 0
    tempData.prevHotStage = 0
    tempData.timeAtDangerousTemp = 0
    tempData.dangerZone = nil
    tempData.currentThirstMult = 1.0
    tempData.currentStaminaPenalty = 0

    if snapToNormal ~= false then
        tempData.bodyTemp = normalTemp

        local stats = nil
        pcall(function() stats = player:getStats() end)
        if stats and CharacterStat and CharacterStat.TEMPERATURE then
            pcall(function()
                stats:set(CharacterStat.TEMPERATURE, normalTemp)
            end)
        end
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
    local normalTemp = cfg.normalTemp or 37.0
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
function EHR.BodyTemp.CalculateTargetTemp(player)
    if not player then return EHR.BodyTemp.Config.normalTemp end

    local cfg = EHR.BodyTemp.Config
    local BASE_TEMP = cfg.normalTemp  -- 37.0°C

    -- Get environmental factors
    local airTemp = 15  -- Default moderate
    if EHR.Environmental and EHR.Environmental.GetAirTemperature then
        airTemp = EHR.Environmental.GetAirTemperature()
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
    local resistanceFactor = 0.09
    local envShift = tempDeviation * resistanceFactor

    -- Wetness amplifies cooling in cold weather (evaporative heat loss)
    if wetness > 0.3 and effectiveAirTemp < effectiveComfortMin then
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

--[[
    Update body temperature for a player.
    @param player (IsoPlayer)
    @param deltaHours (number) - Game hours since last update
]]--
function EHR.BodyTemp.UpdateBodyTemperature(player, deltaHours)
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    if not tempData then return end

    -- Calculate target temperature
    local targetTemp = EHR.BodyTemp.CalculateTargetTemp(player)
    tempData.environmentTargetTemp = targetTemp
    if tempData.diseaseTargetTemp then
        local gameTime = getGameTime and getGameTime() or nil
        local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
        local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)
        if not hasFeverSource then
            tempData.diseaseTargetTemp = nil
            tempData.diseaseTargetTempUntil = nil
            tempData.diseaseFeverActive = false
        elseif not tempData.diseaseTargetTempUntil or tempData.diseaseTargetTempUntil >= currentHour then
            local diseaseTarget = math.max(
                EHR.BodyTemp.Config.minBodyTemp,
                math.min(EHR.BodyTemp.Config.maxBodyTemp, tonumber(tempData.diseaseTargetTemp) or targetTemp)
            )
            if diseaseTarget >= EHR.BodyTemp.Config.normalTemp then
                targetTemp = math.max(targetTemp, diseaseTarget)
            else
                targetTemp = math.min(targetTemp, diseaseTarget)
            end
        else
            tempData.diseaseTargetTemp = nil
            tempData.diseaseTargetTempUntil = nil
        end
    end
    tempData.targetTemp = targetTemp

    -- Calculate change
    local change = EHR.BodyTemp.CalculateChangeRate(tempData.bodyTemp, targetTemp, deltaHours)

    -- Apply change
    local oldTemp = tempData.bodyTemp
    tempData.bodyTemp = tempData.bodyTemp + change

    -- Clamp to survivable range
    local cfg = EHR.BodyTemp.Config
    tempData.bodyTemp = math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, tempData.bodyTemp))

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
                player:Say(text)
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
                player:Say(text)
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

    -- Check hypothermia threshold (body temp < 34°C)
    if tempData.coldStage >= 4 then
        -- In cold danger zone
        if tempData.dangerZone ~= "cold" then
            tempData.dangerZone = "cold"
            tempData.timeAtDangerousTemp = 0
            if EHR.DEBUG then
                EHR.Log("BodyTemp: Entered cold danger zone (< 34°C)")
            end
        end

        tempData.timeAtDangerousTemp = tempData.timeAtDangerousTemp + deltaHours

        -- Check if time threshold reached
        if tempData.timeAtDangerousTemp >= cfg.hypothermiaTriggerTime then
            EHR.BodyTemp.TryTriggerHypothermia(player, tempData)
        end

    -- Check heat exhaustion threshold (body temp > 40.5°C)
    elseif tempData.hotStage >= 4 then
        -- In hot danger zone
        if tempData.dangerZone ~= "hot" then
            tempData.dangerZone = "hot"
            tempData.timeAtDangerousTemp = 0
            if EHR.DEBUG then
                EHR.Log("BodyTemp: Entered hot danger zone (> 40.5°C)")
            end
        end

        tempData.timeAtDangerousTemp = tempData.timeAtDangerousTemp + deltaHours

        -- Check if time threshold reached
        if tempData.timeAtDangerousTemp >= cfg.heatExhaustionTriggerTime then
            EHR.BodyTemp.TryTriggerHeatExhaustion(player, tempData)
        end

    else
        -- Not in danger zone, reset
        if tempData.dangerZone then
            if EHR.DEBUG then
                EHR.Log("BodyTemp: Exited danger zone, resetting timer")
            end
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
    local tempSeverity = (cfg.coldStage4 - tempData.bodyTemp) / 6  -- 0-1 based on how far below 34°C

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
    Attempt to trigger heat exhaustion disease.
]]--
function EHR.BodyTemp.TryTriggerHeatExhaustion(player, tempData)
    if not EHR.Disease or not EHR.Disease.TryContract then return end

    -- Check if already has heat exhaustion or heat stroke
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active then
        if diseaseData.active["heat_exhaustion"] or diseaseData.active["heat_stroke"] then
            return  -- Already have it
        end
    end

    -- Calculate chance based on:
    -- - Time in danger zone
    -- - Current body temp (higher = higher)
    -- - Dehydration
    -- - Exertion
    local cfg = EHR.BodyTemp.Config
    local timeRatio = tempData.timeAtDangerousTemp / cfg.heatExhaustionTriggerTime
    local tempSeverity = (tempData.bodyTemp - cfg.hotStage4) / 2  -- 0-1 based on how far above 40.5°C

    local isDehydrated = EHR.BodyTemp.IsDehydrated(player)
    local isExerting = EHR.BodyTemp.IsExerting(player)

    local baseChance = 0.25  -- 25% base
    local chance = baseChance * (1 + timeRatio * 0.5) * (1 + tempSeverity)
    if isDehydrated then chance = chance * 1.5 end
    if isExerting then chance = chance * 1.3 end
    chance = math.min(0.85, chance)  -- Cap at 85%

    if EHR.DEBUG then
        EHR.Log(string.format("BodyTemp: Heat exhaustion check - chance=%.1f%%, time=%.2fh, temp=%.1f°C, dehydrated=%s, exerting=%s",
            chance * 100, tempData.timeAtDangerousTemp, tempData.bodyTemp, tostring(isDehydrated), tostring(isExerting)))
    end

    -- Try to contract
    if EHR.Disease.TryContract(player, "heat_exhaustion", chance) then
        -- Reset danger zone tracking
        tempData.timeAtDangerousTemp = 0
        if EHR.DEBUG then
            EHR.Log("BodyTemp: Heat exhaustion contracted!")
        end

        -- MP: Trigger server sync after disease contraction
        if isClient() then
            sendClientCommand(player, "EHR", "RequestSync", {})
        end
    end
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
    NORMAL_BODY_TEMP = 37.0,           -- Target temperature (Celsius)
    TOLERANCE = 1.0,                   -- Only force if off by more than 1°C
}

function EHR.BodyTemp.GetVanillaSuppressionTarget(player)
    local normalTemp = EHR.BodyTemp.Config.normalTemp or vanillaSuppression.NORMAL_BODY_TEMP
    if not player then return normalTemp end

    local cfg = EHR.BodyTemp.Config
    local tempData = EHR.BodyTemp.GetTemperatureData(player)
    local hasFeverSource = EHR.BodyTemp.HasActiveDiseaseFeverSource and EHR.BodyTemp.HasActiveDiseaseFeverSource(player)
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
            local feverTemp = tonumber(tempData.bodyTemp) or tonumber(tempData.diseaseTargetTemp) or normalTemp
            return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, feverTemp))
        end
    end

    if hasFeverSource and EHR.BodyTemp.GetActiveDiseaseFeverTarget then
        local feverTemp = EHR.BodyTemp.GetActiveDiseaseFeverTarget(player)
        if feverTemp then
            return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, feverTemp))
        end
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
    Check if player is cool enough for heat exhaustion recovery.
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

local function processPlayerTick(player)
    if not player or not player:isAlive() then return end

    -- Check if custom body temp system is enabled
    -- If disabled, don't suppress vanilla temp - allows other temp mods to work
    if not EHR.BodyTemp.IsEnabled() then return end

    -- Suppress vanilla temperature when our system is active
    -- This prevents vanilla hypothermia/hyperthermia moodles from conflicting
    EHR.BodyTemp.SuppressVanillaTemperature(player)

    -- Throttled updates for our system
    local state = getTickState(player)
    state.tick = state.tick + 1
    if state.tick < BODY_TEMP_TICK_INTERVAL then return end
    state.tick = 0

    -- Initialize if needed
    EHR.BodyTemp.InitializePlayer(player)

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

    -- Apply pre-disease effects (shivering, sweating, dialogue)
    EHR.BodyTemp.ApplyPreDiseaseEffects(player, tempData)

    -- Check disease thresholds
    EHR.BodyTemp.CheckDiseaseThresholds(player, tempData, deltaHours)
end

function EHR.BodyTemp.OnTick()
    -- MP: server-authoritative processing, client-only suppression
    if isClient and isClient() and not (isServer and isServer()) then
        local player = getSpecificPlayer(0)
        if player and EHR.BodyTemp.IsEnabled() then
            EHR.BodyTemp.SuppressVanillaTemperature(player)
        end
        return
    end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events and Events.OnTick then
    Events.OnTick.Add(EHR.BodyTemp.OnTick)
    EHR.Log("Body Temperature module events registered")
end

EHR.Log("Body Temperature module loaded v1.0.0")
