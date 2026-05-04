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

    -- Exposure time requirements (in game hours)
    coldExposureForCold = 2.0,      -- Hours of cold+wet for common cold
    coldExposureForHypo = 0.5,      -- Hours of freezing+wet for hypothermia
    heatExposureForExhaustion = 3.0,  -- Hours of hot + exertion for heat exhaustion (was 1.0)
    heatExposureForStroke = 0.5,      -- Hours at extreme heat for heat stroke
    heatMinimumExposure = 1.0,        -- Minimum hours before disease check can trigger

    -- Water contamination risk
    untreatedWaterRisk = 0.35,      -- 35% base chance from untreated water
    toiletWaterRisk = 0.60,         -- 60% from toilet water
    riverWaterRisk = 0.25,          -- 25% from river (lower but still risky)
    rainCollectorRisk = 0.05,       -- 5% from rain collectors (mostly safe)

    -- Cold -> Pneumonia progression check interval (game hours)
    coldProgressionCheckInterval = 6,   -- Check every 6 game hours

    -- Sound radii for zombie attraction (MIN-004 fix)
    sound = {
        sneezeRadius = 8,
        sneezeVolume = 5,
        coughRadius = 12,
        coughVolume = 8,
        coughSevereRadius = 25,
        coughSevereVolume = 15,
        vomitRadius = 15,
        vomitVolume = 10,
    },
}

-- ============================================
-- EXPOSURE TRACKING
-- ============================================

-- Track environmental exposure per player
EHR.Environmental.ExposureData = {}

--[[
    Initialize exposure tracking for a player
]]--
function EHR.Environmental.InitializePlayer(player)
    if not player then return end

    local playerID = tostring(player:getUsername() or player:getPlayerNum())

    if EHR.Environmental.ExposureData[playerID] then
        return -- Already initialized
    end

    EHR.Environmental.ExposureData[playerID] = {
        -- Cold exposure tracking
        coldExposure = 0,           -- Accumulated cold exposure (hours)
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

        -- Heat -> Heat Stroke progression
        heatExhaustionHour = nil,   -- When heat exhaustion was contracted
        lastHeatProgressionCheck = 0,

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
    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    return EHR.Environmental.ExposureData[playerID]
end

-- ============================================
-- ENVIRONMENT READING
-- ============================================

--[[
    Get current air temperature (Celsius)
    B42: getClimateManager():getTemperature()
]]--
function EHR.Environmental.GetAirTemperature()
    local climate = getClimateManager()
    if climate and climate.getTemperature then
        local success, temp = pcall(function() return climate:getTemperature() end)
        if success and temp then
            return temp
        end
    end
    return 15 -- Default moderate temp if can't read
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
            return temp
        end
    end

    -- Fallback: try legacy method
    if player.getTemperature then
        local success, temp = pcall(function() return player:getTemperature() end)
        if success and temp then
            return temp
        end
    end

    return 0.5 -- Default normal
end

--[[
    Get player wetness (0-1 scale)
    B42: CharacterStat.WETNESS through stats:get()
]]--
function EHR.Environmental.GetWetness(player)
    local stats = player:getStats()
    if not stats then return 0 end

    if CharacterStat and CharacterStat.WETNESS then
        local success, wet = pcall(function() return stats:get(CharacterStat.WETNESS) end)
        if success and wet then
            return wet
        end
    end

    -- Fallback: try legacy method
    if player.getWetness then
        local success, wet = pcall(function() return player:getWetness() end)
        if success and wet then
            return wet
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

    local modData = player:getModData()
    if not modData or not modData.EHR_Disease then return end

    -- Check if mod is managing a temperature-related or respiratory disease
    local active = modData.EHR_Disease.active or {}
    local hasModHypothermia = active["hypothermia"] ~= nil
    local hasModHeatExhaustion = active["heat_exhaustion"] ~= nil
    local hasModHeatStroke = active["heat_stroke"] ~= nil
    local hasModCold = active["common_cold"] ~= nil
    local hasModPneumonia = active["pneumonia"] ~= nil

    if not (hasModHypothermia or hasModHeatExhaustion or hasModHeatStroke or hasModCold or hasModPneumonia) then
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
    local hasModTuberculosis = active["tuberculosis"] ~= nil
    local hasModFoodDisease = false

    for diseaseId, disease in pairs(active) do
        local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId]
        if disease and (diseaseId == "food_poisoning" or (def and def.category == "food")) then
            hasModFoodDisease = true
            break
        end
    end

    local hasAnyModRespiratory = hasModCold or hasModPneumonia or hasModCorpseSickness or hasModTuberculosis

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
    local hasFoodSicknessSignal = hasModFoodDisease or currentFoodSickness > 0.01

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
        local lowThreshold = EHR.CorpseSickness.Config and EHR.CorpseSickness.Config.EXPOSURE_THRESHOLD_LOW or 30
        if exposure >= lowThreshold then
            hasCorpseExposure = true
        elseif currentSickness > 0.01 and not hasFoodSicknessSignal and EHR.CorpseSickness.ScanNearbyCorpses then
            local ok, corpseInfo = pcall(function() return EHR.CorpseSickness.ScanNearbyCorpses(player) end)
            if ok and corpseInfo and (corpseInfo.count or 0) > 0 then
                hasCorpseExposure = true
            end
        end
    end

    if hasAnyModRespiratory then
        -- Mod HAS a respiratory disease - sync SICKNESS to mod's disease stage
        local targetSickness = 0
        local respiratoryDiseases = {"common_cold", "pneumonia", "corpse_sickness", "tuberculosis"}

        for _, diseaseId in ipairs(respiratoryDiseases) do
            local disease = active[diseaseId]
            if disease and disease.stage then
                local stageValue = EHR.Disease.VanillaSicknessLevels[disease.stage] or 0
                targetSickness = math.max(targetSickness, stageValue)
            end
        end

        local targetB42 = targetSickness / 100
        local difference = math.abs(currentSickness - targetB42)

        -- Only update if significantly different (dead zone to prevent flicker)
        if difference > 0.10 then
            pcall(function() stats:set(CharacterStat.SICKNESS, targetB42) end)
            if EHR.DEBUG then
                EHR.Log(string.format("SuppressVanillaCold: Synced SICKNESS %.3f -> %.3f (mod respiratory disease active)",
                    currentSickness, targetB42))
            end
        end
    else
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

--[[
    Update cold exposure tracking
    Called periodically from main tick handler
]]--
function EHR.Environmental.UpdateColdExposure(player, deltaHours)
    local config = EHR.Environmental.Config
    local exposure = EHR.Environmental.GetExposureData(player)
    if not exposure then return end

    local airTemp = EHR.Environmental.GetAirTemperature()
    local bodyTemp = EHR.Environmental.GetBodyTemperature(player)
    local wetness = EHR.Environmental.GetWetness(player)
    local isIndoors = EHR.Environmental.IsIndoors(player)
    local isNearHeat = EHR.Environmental.IsNearHeat(player)

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

    -- Reset exposure if warm
    if isWarm then
        -- Recover from cold exposure while warm
        exposure.coldExposure = math.max(0, exposure.coldExposure - deltaHours * 2)
        exposure.hypothermiaExposure = math.max(0, exposure.hypothermiaExposure - deltaHours * 3)
        exposure.wetDuration = math.max(0, exposure.wetDuration - deltaHours)
        exposure.indoorDuration = exposure.indoorDuration + deltaHours
        return
    end

    -- Track wetness duration
    if wetness > config.wetThreshold then
        exposure.wetDuration = exposure.wetDuration + deltaHours
    else
        exposure.wetDuration = math.max(0, exposure.wetDuration - deltaHours * 0.5)
    end

    -- Check cold conditions
    local isCold = airTemp < config.coldTemp
    local isFreezing = airTemp < config.freezingTemp
    local isHypoRisk = airTemp < config.hypothermiaTemp
    local isWet = wetness > config.wetThreshold
    local isSoaked = wetness > config.soakedThreshold

    -- Cold exposure accumulates faster when wet
    local coldMultiplier = 1.0
    if isWet then coldMultiplier = 1.5 end
    if isSoaked then coldMultiplier = 2.5 end

    -- Accumulate cold exposure
    if isCold and (isWet or not isIndoors) then
        exposure.coldExposure = exposure.coldExposure + (deltaHours * coldMultiplier)

        if EHR.DEBUG then
            EHR.Log(string.format("Cold exposure: %.2f hours (temp=%.1f, wet=%.2f, mult=%.1f)",
                exposure.coldExposure, airTemp, wetness, coldMultiplier))
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
    EHR.Environmental.CheckColdDiseases(player, exposure)
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

    local airTemp = EHR.Environmental.GetAirTemperature()
    local isExerting = EHR.Environmental.IsExerting(player)
    local isInShade = EHR.Environmental.IsInShade(player)
    local thirst = 0

    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.THIRST then
        local success, t = pcall(function() return stats:get(CharacterStat.THIRST) end)
        if success and t then thirst = t end
    end

    -- Reset exposure if cool/shaded
    if airTemp < config.hotTemp or (isInShade and airTemp < config.veryHotTemp) then
        -- Recover from heat exposure while cool
        exposure.heatExposure = math.max(0, exposure.heatExposure - deltaHours * 3)
        exposure.heatStrokeExposure = math.max(0, exposure.heatStrokeExposure - deltaHours * 4)
        return
    end

    -- Check heat conditions
    local isHot = airTemp >= config.hotTemp
    local isVeryHot = airTemp >= config.veryHotTemp
    local isExtremeHeat = airTemp >= config.extremeHeatTemp
    local isDehydrated = thirst > 0.4
    local isSeverelyDehydrated = thirst > 0.7

    -- Heat exposure accumulates faster when exerting and dehydrated
    -- (Reduced multipliers to prevent instant disease contraction)
    local heatMultiplier = 1.0
    if isExerting then heatMultiplier = heatMultiplier * 1.5 end          -- Was 2.0
    if isDehydrated then heatMultiplier = heatMultiplier * 1.3 end        -- Was 1.5
    if isSeverelyDehydrated then heatMultiplier = heatMultiplier * 1.5 end -- Was 2.0
    if not isInShade then heatMultiplier = heatMultiplier * 1.2 end       -- Was 1.3

    -- Accumulate heat exposure
    if isHot and (isExerting or isDehydrated or not isInShade) then
        exposure.heatExposure = exposure.heatExposure + (deltaHours * heatMultiplier)

        if EHR.DEBUG then
            EHR.Log(string.format("Heat exposure: %.2f hours (temp=%.1f, exert=%s, thirst=%.2f)",
                exposure.heatExposure, airTemp, tostring(isExerting), thirst))
        end
    end

    -- Accumulate heat stroke exposure (requires extreme heat or very hot + dehydrated)
    if isExtremeHeat or (isVeryHot and isSeverelyDehydrated) then
        local strokeMultiplier = isExtremeHeat and 2.0 or 1.0
        if not isInShade then strokeMultiplier = strokeMultiplier * 1.5 end

        exposure.heatStrokeExposure = exposure.heatStrokeExposure + (deltaHours * strokeMultiplier)

        if EHR.DEBUG then
            EHR.Log(string.format("Heat stroke exposure: %.2f hours (temp=%.1f)",
                exposure.heatStrokeExposure, airTemp))
        end
    end

    -- Check for disease contraction
    EHR.Environmental.CheckHeatDiseases(player, exposure)
end

--[[
    Check if heat exposure should cause diseases
]]--
function EHR.Environmental.CheckHeatDiseases(player, exposure)
    local config = EHR.Environmental.Config

    -- Check sandbox setting
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.HeatExhaustionEnabled == false then return end

    -- If body temperature system is enabled, it handles heat exhaustion triggering
    -- via body temperature thresholds instead of exposure time
    if EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled() then
        -- Body temp system handles disease triggering in EHR.BodyTemp.CheckDiseaseThresholds()
        -- Still track exposure for logging purposes but don't trigger diseases here
        if EHR.DEBUG then
            EHR.Log("Heat diseases: Deferring to body temperature system")
        end
        return
    end

    -- Fallback: Exposure-based triggering when body temp system is disabled
    -- Require minimum exposure time before any disease check
    -- This prevents instant disease contraction when sun moodle first appears
    local minExposure = config.heatMinimumExposure or 1.0
    if exposure.heatExposure < minExposure then
        if EHR.DEBUG then
            EHR.Log(string.format("Heat: Below minimum exposure (%.2f/%.2f hours)",
                exposure.heatExposure, minExposure))
        end
        return
    end

    -- Check for Heat Exhaustion
    if exposure.heatExposure >= config.heatExposureForExhaustion then
        -- Don't contract if already have heat exhaustion or heat stroke
        local diseaseData = EHR.Disease.GetDiseaseData(player)
        if diseaseData and diseaseData.active then
            if diseaseData.active["heat_exhaustion"] or diseaseData.active["heat_stroke"] then
                return
            end
            -- BUG-010 FIX: Block if have cold diseases (mutual exclusion)
            if diseaseData.active["common_cold"] or diseaseData.active["pneumonia"] or
               diseaseData.active["hypothermia"] then
                return
            end
        end

        local exposureRatio = exposure.heatExposure / config.heatExposureForExhaustion
        local baseChance = math.min(0.6, 0.2 * exposureRatio)

        EHR.Log(string.format("Heat exhaustion check: %.2f hours exposure, base chance %.0f%%",
            exposure.heatExposure, baseChance * 100))

        if EHR.Disease.TryContract(player, "heat_exhaustion", baseChance) then
            exposure.heatExhaustionHour = getGameTime():getWorldAgeHours()
            exposure.heatExposure = 0
        end
    end
end

--[[
    Check if heat exhaustion should progress to heat stroke
]]--
function EHR.Environmental.CheckHeatProgression(player, exposure)
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return end

    local heatExhaustion = diseaseData.active["heat_exhaustion"]
    if not heatExhaustion then return end

    local def = EHR.Disease.Diseases["heat_exhaustion"]
    if not def or not def.canProgress then return end

    local currentHour = getGameTime():getWorldAgeHours()

    -- Check progression interval
    if currentHour - (exposure.lastHeatProgressionCheck or 0) < 1 then  -- Check every hour
        return
    end
    exposure.lastHeatProgressionCheck = currentHour

    -- Only progress from peak stage
    if heatExhaustion.stage ~= 3 then return end

    -- Check how long in peak stage
    local peakDuration = currentHour - (heatExhaustion.stageStartTime or heatExhaustion.startTime)
    if peakDuration < (def.progressAfterHours or 4) then return end

    -- Check if player is still in heat
    local airTemp = EHR.Environmental.GetAirTemperature()
    local isInShade = EHR.Environmental.IsInShade(player)

    if isInShade and airTemp < EHR.Environmental.Config.veryHotTemp then
        return  -- Cooling down, won't progress
    end

    local progressChance = def.progressChance or 0.40

    -- Dehydration increases progression
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.THIRST then
        local thirst = stats:get(CharacterStat.THIRST) or 0
        if thirst > 0.6 then
            progressChance = progressChance * 1.5
        end
    end

    EHR.Log(string.format("Heat stroke progression check: peak duration=%.1fh, chance=%.0f%%",
        peakDuration, progressChance * 100))

    local roll = ZombRand(100) / 100
    if roll < progressChance then
        EHR.Log("Heat exhaustion progressed to HEAT STROKE!")

        -- Remove heat exhaustion
        diseaseData.active["heat_exhaustion"] = nil

        -- Contract heat stroke
        EHR.Disease.Contract(player, "heat_stroke")

        if player.Say then
            player:Say("*collapses* Can't... everything's burning...")
        end
    end
end

--[[
    Check if heat disease should be blocked from recovering
]]--
function EHR.Environmental.CheckHeatCooling(player)
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return end

    -- Check both heat exhaustion and heat stroke
    for _, diseaseId in ipairs({"heat_exhaustion", "heat_stroke"}) do
        local disease = diseaseData.active[diseaseId]
        if disease then
            local def = EHR.Disease.Diseases[diseaseId]
            if def and def.requiresCoolingForRecovery then
                local airTemp = EHR.Environmental.GetAirTemperature()
                local isInShade = EHR.Environmental.IsInShade(player)
                local isCool = isInShade or airTemp < EHR.Environmental.Config.hotTemp

                -- If in recovery (stage 4) but not cool, regress
                if disease.stage == 4 and not isCool then
                    disease.stage = 3
                    disease.stageStartTime = getGameTime():getWorldAgeHours()

                    EHR.Log(diseaseId .. ": Regressed from recovery to peak (not cool enough)")

                    if player.Say then
                        player:Say("*pants* Still too hot... can't recover...")
                    end
                end

                disease.coolingBlocked = not isCool
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
    if exposure.coldExposure >= config.coldExposureForCold then
        -- Don't contract if already have cold, pneumonia, or hypothermia
        local diseaseData = EHR.Disease.GetDiseaseData(player)
        if diseaseData and diseaseData.active then
            if diseaseData.active["common_cold"] or diseaseData.active["pneumonia"] or
               diseaseData.active["hypothermia"] then
                return
            end
            -- BUG-010 FIX: Block if have heat diseases (mutual exclusion)
            if diseaseData.active["heat_exhaustion"] or diseaseData.active["heat_stroke"] then
                return
            end
        end

        -- Base chance increases with exposure time
        local exposureRatio = exposure.coldExposure / config.coldExposureForCold
        local baseChance = math.min(0.5, 0.15 * exposureRatio)  -- 15-50% based on exposure

        EHR.Log(string.format("Cold exposure check: %.2f hours, base chance %.0f%%",
            exposure.coldExposure, baseChance * 100))

        if EHR.Disease.TryContract(player, "common_cold", baseChance) then
            -- Record when cold was contracted for pneumonia progression
            exposure.coldContractedHour = getGameTime():getWorldAgeHours()
            -- Reset exposure after contracting
            exposure.coldExposure = 0
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
            if diseaseData.active["heat_exhaustion"] or diseaseData.active["heat_stroke"] then
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
function EHR.Environmental.CheckColdProgression(player, exposure)
    local config = EHR.Environmental.Config
    local diseaseData = EHR.Disease.GetDiseaseData(player)

    if not diseaseData or not diseaseData.active then return end
    local cold = diseaseData.active["common_cold"]
    if not cold then return end

    -- Get disease definition
    local coldDef = EHR.Disease.Diseases["common_cold"]
    if not coldDef or not coldDef.canProgress then return end

    local currentHour = getGameTime():getWorldAgeHours()

    -- Check progression interval
    if currentHour - (exposure.lastProgressionCheck or 0) < config.coldProgressionCheckInterval then
        return
    end
    exposure.lastProgressionCheck = currentHour

    -- Calculate how long player has had the cold
    local coldDuration = currentHour - cold.startTime

    -- Only check progression after minimum time
    if coldDuration < (coldDef.progressAfterHours or 72) then
        return
    end

    -- Check if player has taken treatment (reduces progression chance)
    local progressChance = coldDef.progressChance or 0.30
    if cold.treated then
        progressChance = progressChance * (1 - (coldDef.treatmentReducesProgress or 0.5))
    end

    -- Environmental factors increase progression
    local airTemp = EHR.Environmental.GetAirTemperature()
    local bodyTemp = EHR.Environmental.GetBodyTemperature(player)
    local wetness = EHR.Environmental.GetWetness(player)
    local isIndoors = EHR.Environmental.IsIndoors(player)

    -- BUG-017 FIX: Cold environment check should use body temperature for indoor players
    -- Outdoor air temp is irrelevant if player is warm indoors
    local isPlayerCold = false
    if isIndoors then
        -- Indoor: use body temperature (cold if below normal)
        isPlayerCold = bodyTemp < 0.45
    else
        -- Outdoor: use air temperature as before
        isPlayerCold = airTemp < config.coldTemp
    end

    -- Cold environment increases progression risk
    if isPlayerCold then
        progressChance = progressChance * 1.3
    end
    if wetness > config.wetThreshold then
        progressChance = progressChance * 1.2
    end
    if not isIndoors then
        progressChance = progressChance * 1.1
    end

    -- Immunity factors
    local immunity = EHR.Disease.CalculateImmunity(player)
    progressChance = progressChance / immunity

    EHR.Log(string.format("Cold progression check: duration=%.1fh, chance=%.0f%% (treated=%s)",
        coldDuration, progressChance * 100, tostring(cold.treated or false)))

    -- Roll for progression
    local roll = ZombRand(100) / 100
    if roll < progressChance then
        -- Progress to pneumonia!
        EHR.Log("Cold progressed to PNEUMONIA!")

        -- Remove cold
        diseaseData.active["common_cold"] = nil

        -- Contract pneumonia (guaranteed)
        EHR.Disease.Contract(player, "pneumonia")

        -- Player announcement
        if player.Say then
            player:Say("*coughs violently* This isn't just a cold anymore...")
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
    if sourceType == "toilet" then
        return config.toiletWaterRisk, "toilet"
    elseif sourceType == "river" or sourceType == "lake" then
        return config.riverWaterRisk, "river"
    elseif sourceType == "rainCollector" then
        return config.rainCollectorRisk, "rain"
    elseif sourceType == "tap" then
        -- Tap water after power outage is risky
        -- Check if power is on
        local sandbox = SandboxVars
        local daysBeforeApocalypse = (sandbox and sandbox.WaterShutModifier) or 14
        local gameTime = getGameTime()
        local daysSurvived = gameTime:getDay()

        if daysSurvived > daysBeforeApocalypse then
            return config.untreatedWaterRisk, "shutoff"
        else
            return 0, "safe" -- Municipal water still running
        end
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

    -- COMMON COLD: Sneezing (zombie attraction)
    if diseaseId == "common_cold" and effects.sneezingChance then
        if ZombRand(1000) / 1000 < effects.sneezingChance then
            EHR.Environmental.TriggerSneeze(player)
        end
    end

    -- PNEUMONIA: Coughing fits (severe zombie attraction)
    if diseaseId == "pneumonia" and effects.coughingChance then
        if ZombRand(1000) / 1000 < effects.coughingChance then
            EHR.Environmental.TriggerCough(player, true) -- severe = true
        end
    end

    -- PNEUMONIA/HYPOTHERMIA: Sprint restriction
    if effects.canSprint == false then
        -- B42: Try to prevent sprinting
        if player.setCanSprint then
            pcall(function() player:setCanSprint(false) end)
        end
    end

    -- Movement speed penalty
    if effects.movementPenalty and effects.movementPenalty < 1.0 then
        if player.setSpeedMod then
            pcall(function() player:setSpeedMod(effects.movementPenalty) end)
        end
    end

    -- DYSENTERY: Vomiting
    if diseaseId == "dysentery" and effects.vomitChance then
        if ZombRand(1000) / 1000 < effects.vomitChance then
            EHR.Environmental.TriggerVomit(player)
        end
    end

    -- DYSENTERY: Blood loss (integration with Blood module)
    if diseaseId == "dysentery" and effects.bloodLoss then
        if EHR.Blood and EHR.Blood.ModifyBloodVolume then
            -- Apply blood loss using v2.7.0+ API (small amount per tick)
            EHR.Blood.ModifyBloodVolume(player, -effects.bloodLoss)
        end
    end

    -- HYPOTHERMIA: Confusion effects
    if diseaseId == "hypothermia" and effects.confusionChance then
        if ZombRand(1000) / 1000 < effects.confusionChance then
            EHR.Environmental.TriggerConfusion(player)
        end
    end

    -- HEAT EXHAUSTION: Muscle cramps
    if diseaseId == "heat_exhaustion" and effects.crampChance then
        if ZombRand(1000) / 1000 < effects.crampChance then
            EHR.Environmental.TriggerCramp(player)
        end
    end

    -- HEAT EXHAUSTION/STROKE: Dizziness
    if (diseaseId == "heat_exhaustion" or diseaseId == "heat_stroke") and effects.dizzinessChance then
        if ZombRand(1000) / 1000 < effects.dizzinessChance then
            EHR.Environmental.TriggerDizziness(player)
        end
    end

    -- HEAT EXHAUSTION/STROKE: Vomiting from heat
    if (diseaseId == "heat_exhaustion" or diseaseId == "heat_stroke") and effects.vomitChance then
        if ZombRand(1000) / 1000 < effects.vomitChance then
            EHR.Environmental.TriggerVomit(player)
        end
    end

    -- HEAT STROKE: Collapse
    if diseaseId == "heat_stroke" and effects.collapseChance then
        if ZombRand(1000) / 1000 < effects.collapseChance then
            EHR.Environmental.TriggerCollapse(player)
        end
    end

    -- HEAT STROKE: Confusion
    if diseaseId == "heat_stroke" and effects.confusionChance then
        if ZombRand(1000) / 1000 < effects.confusionChance then
            EHR.Environmental.TriggerConfusion(player)
        end
    end

    -- Stat drains
    if effects.fatigueDrain and CharacterStat and CharacterStat.FATIGUE then
        local current = stats:get(CharacterStat.FATIGUE) or 0
        pcall(function()
            stats:set(CharacterStat.FATIGUE, math.min(1, current + effects.fatigueDrain))
        end)
    end

    if effects.thirstDrain and CharacterStat and CharacterStat.THIRST then
        local current = stats:get(CharacterStat.THIRST) or 0
        pcall(function()
            stats:set(CharacterStat.THIRST, math.min(1, current + effects.thirstDrain))
        end)
    end

    if effects.hungerDrain and CharacterStat and CharacterStat.HUNGER then
        local current = stats:get(CharacterStat.HUNGER) or 0
        pcall(function()
            stats:set(CharacterStat.HUNGER, math.min(1, current + effects.hungerDrain))
        end)
    end
end

-- ============================================
-- SYMPTOM TRIGGERS
-- ============================================

--[[
    Trigger a sneeze (common cold)
    Creates noise that can attract zombies
]]--
function EHR.Environmental.TriggerSneeze(player)
    local cfg = EHR.Environmental.Config.sound

    -- Say sneeze dialogue
    if player.Say then
        local sneezes = {"*ACHOO!*", "*sneezes*", "*achoo!*"}
        player:Say(sneezes[ZombRand(#sneezes) + 1])
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
function EHR.Environmental.TriggerCough(player, severe)
    local cfg = EHR.Environmental.Config.sound

    -- Say cough dialogue
    if player.Say then
        if severe then
            local coughs = {
                "*VIOLENT COUGHING FIT*",
                "*coughs uncontrollably*",
                "*COUGHING* Can't... stop...",
            }
            player:Say(coughs[ZombRand(#coughs) + 1])
        else
            local coughs = {"*cough*", "*coughs*", "*cough cough*"}
            player:Say(coughs[ZombRand(#coughs) + 1])
        end
    end

    -- Create noise for zombie attraction
    local radius = severe and cfg.coughSevereRadius or cfg.coughRadius
    local volume = severe and cfg.coughSevereVolume or cfg.coughVolume

    if player.addWorldSoundUnlessInvisible then
        pcall(function()
            player:addWorldSoundUnlessInvisible(radius, volume, true)
        end)
    elseif addSound then
        pcall(function()
            addSound(player, player:getX(), player:getY(), player:getZ(), radius, volume)
        end)
    end

    EHR.Log(string.format("Player coughed (severe=%s, radius=%d)", tostring(severe), radius))
end

--[[
    Trigger vomiting (dysentery)
    Causes food/water loss and noise
]]--
function EHR.Environmental.TriggerVomit(player)
    local cfg = EHR.Environmental.Config.sound

    -- Say vomit dialogue
    if player.Say then
        local vomits = {"*vomits*", "*retches violently*", "*throws up*"}
        player:Say(vomits[ZombRand(#vomits) + 1])
    end

    -- Increase hunger (lost food)
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.HUNGER then
        local current = stats:get(CharacterStat.HUNGER) or 0
        pcall(function()
            stats:set(CharacterStat.HUNGER, math.min(1, current + 0.1))
        end)
    end

    -- Increase thirst (lost fluids)
    if stats and CharacterStat and CharacterStat.THIRST then
        local current = stats:get(CharacterStat.THIRST) or 0
        pcall(function()
            stats:set(CharacterStat.THIRST, math.min(1, current + 0.15))
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

--[[
    Trigger confusion effect (hypothermia)
    Causes disorientation
]]--
function EHR.Environmental.TriggerConfusion(player)
    -- Say confusion dialogue
    if player.Say then
        local confused = {
            "*stumbles* Where... am I?",
            "*confused* What was I doing...?",
            "*disoriented* Can't... think straight...",
        }
        player:Say(confused[ZombRand(#confused) + 1])
    end

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
        player:Say(cramps[ZombRand(#cramps) + 1])
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
function EHR.Environmental.TriggerDizziness(player)
    if player.Say then
        local dizzy = {
            "*dizzy* World's spinning...",
            "*stumbles*",
            "*sways* Can't focus...",
        }
        player:Say(dizzy[ZombRand(#dizzy) + 1])
    end

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

--[[
    Trigger collapse (heat stroke)
    Causes player to fall down temporarily
]]--
function EHR.Environmental.TriggerCollapse(player)
    if player.Say then
        player:Say("*collapses*")
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
    -- GetAirTemperature() returns OUTDOOR temp, not room temp
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

    -- Check if player is warm (now includes body temperature)
    local isWarm = EHR.Environmental.IsWarmEnoughForRecovery(player)

    -- If in recovery (stage 4) but not warm, regress to peak (stage 3)
    if hypothermia.stage == 4 and not isWarm then
        hypothermia.stage = 3
        hypothermia.stageStartTime = getGameTime():getWorldAgeHours()

        EHR.Log("Hypothermia: Regressed from recovery to peak (not warm enough)")

        if player.Say then
            player:Say("*shivers* I'm getting cold again... can't stay warm...")
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
                player:Say("*gasps* Can't... breathe...")
            elseif diseaseId == "hypothermia" then
                player:Say("So... cold... tired...")
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
                        player:Say("This medicine should help...")
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

    -- Check heat exhaustion -> heat stroke progression
    EHR.Environmental.CheckHeatProgression(player, exposure)

    -- Check hypothermia warmth requirement (MED-003)
    EHR.Environmental.CheckHypothermiaWarmth(player)

    -- Check heat cooling requirement
    EHR.Environmental.CheckHeatCooling(player)

    -- Apply disease-specific effects for active diseases
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active then
        for diseaseId, disease in pairs(diseaseData.active) do
            local def = EHR.Disease.Diseases[diseaseId]
            if def then
                -- Apply environmental disease effects
                if diseaseId == "common_cold" or diseaseId == "pneumonia" or
                   diseaseId == "dysentery" or diseaseId == "hypothermia" or
                   diseaseId == "heat_exhaustion" or diseaseId == "heat_stroke" then
                    EHR.Environmental.ApplyDiseaseEffects(player, diseaseId, disease, def)
                    EHR.Environmental.CheckDiseaseLethal(player, diseaseId, disease, def)
                end
            end
        end
    end
end

--[[
    Main tick handler for environmental diseases
]]--
function EHR.Environmental.OnTick()
    -- Check if disease system is enabled
    if EHR.Disease and not EHR.Disease.IsEnabled() then return end

    -- MP: server-authoritative progression, client-only suppression
    if isClient and isClient() and not (isServer and isServer()) then
        local player = getSpecificPlayer(0)
        if player then
            if not (EHR.BodyTemp and EHR.BodyTemp.IsEnabled and EHR.BodyTemp.IsEnabled()) then
                EHR.Environmental.SuppressVanillaTemperature(player)
            end
            EHR.Environmental.SuppressVanillaCold(player)
        end
        return
    end

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
