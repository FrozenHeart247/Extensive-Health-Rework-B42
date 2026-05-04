--[[
    Extensive Health Rework B42
    Corpse Sickness Module (Unified System)

    Replaces aspergillosis + putrefaction with a single corpse exposure illness.
    MP note: exposure tracking and disease application run server-side and
    sync ModData to clients for UI display.
]]--

require "ExtensiveHealth/EHR_Disease"

EHR = EHR or {}
EHR.CorpseSickness = EHR.CorpseSickness or {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.CorpseSickness.Config = {
    -- Exposure thresholds
    EXPOSURE_THRESHOLD_LOW = 30,
    EXPOSURE_THRESHOLD_MEDIUM = 60,
    EXPOSURE_THRESHOLD_HIGH = 100,

    -- Corpse count thresholds (for debug/UI)
    CORPSE_COUNT_SAFE = 2,
    CORPSE_COUNT_RISKY = 5,
    CORPSE_COUNT_DANGEROUS = 10,

    -- Corpse age categories (hours since death)
    CORPSE_AGE_FRESH = 24,
    CORPSE_AGE_DECOMPOSING = 48,
    CORPSE_AGE_ROTTEN = 48,

    -- Emission rates by age (points per hour per corpse)
    EMISSION_RATE = {
        fresh = 1,
        decomposing = 2,
        rotten = 5,
    },

    -- Environment multipliers
    INDOOR_MULTIPLIER = 1.5,
    ENCLOSED_MULTIPLIER = 2.0,

    -- Protection values (reduction percentage)
    PROTECTION = {
        gas_mask = 1.00,
        surgical_mask = 0.75,
        bandana = 0.50,
        none = 0.00,
    },

    -- Time to get sick (hours of exposure at threshold)
    MIN_EXPOSURE_TIME_HOURS = 1,

    -- Search radius for corpses (tiles)
    SEARCH_RADIUS = 10,

    -- Update frequency (game ticks)
    UPDATE_TICKS = 300,

    -- Immunity duration after recovery (hours)
    IMMUNITY_DURATION = 2,

    -- Exposure decay per hour when safe
    EXPOSURE_DECAY_PER_HOUR = 30,

    -- How quickly corpse-driven vanilla sickness fades after leaving corpses (0-1 stat scale per hour)
    VANILLA_SICKNESS_DECAY_PER_HOUR = 0.75,

    -- Dialogue lines for smell warning
    SMELL_DIALOGUES = {
        "Ugh, that smell...",
        "Something's rotting nearby.",
        "The stench of death...",
        "I can smell decomposition.",
        "That's the smell of decay.",
    },

    -- Minimum exposure before smell warnings are shown
    MIN_EXPOSURE_FOR_WARNING = 15,

    -- Minimum time in corpse area (hours) before warnings trigger
    MIN_TIME_FOR_WARNING = 0.25,  -- 15 minutes
}

-- ============================================
-- STATE + SETTINGS
-- ============================================

EHR.CorpseSickness.FirstSeenCorpses = EHR.CorpseSickness.FirstSeenCorpses or {}

local function isEnabled()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not options then return true end

    if options.CorpseSicknessEnabled ~= nil then
        return options.CorpseSicknessEnabled
    end

    if options.AspergilliosisEnabled ~= nil or options.PutrefactionSicknessEnabled ~= nil then
        local asp = options.AspergilliosisEnabled
        local put = options.PutrefactionSicknessEnabled
        if asp == nil and put == nil then return true end
        return (asp ~= false) or (put ~= false)
    end

    return true
end

local function getSpeedMultiplier()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not options then return 1.0 end
    return options.CorpseDiseaseSpeed or 1.0
end

-- ============================================
-- EXPOSURE TRACKING
-- ============================================

function EHR.CorpseSickness.GetExposureData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData then return nil end

    modData.EHR_CorpseSickness = modData.EHR_CorpseSickness or {
        currentExposure = 0,
        maxExposure = 0,
        timeInArea = 0,
        lastUpdateHour = 0,
        lastWarningTime = 0,
        lastCorpseCount = 0,
        immuneUntil = 0,
    }
    return modData.EHR_CorpseSickness
end

function EHR.CorpseSickness.InitializePlayer(player)
    local data = EHR.CorpseSickness.GetExposureData(player)
    if data then
        data.currentExposure = data.currentExposure or 0
        data.maxExposure = data.maxExposure or 0
        data.timeInArea = data.timeInArea or 0
        data.lastUpdateHour = data.lastUpdateHour or 0
        data.lastWarningTime = data.lastWarningTime or 0
        data.lastCorpseCount = data.lastCorpseCount or 0
        data.immuneUntil = data.immuneUntil or 0
    end
end

function EHR.CorpseSickness.MigrateOldData(player)
    if not player then return end
    local modData = player:getModData()
    if not modData then return end

    if modData.EHR_Disease and modData.EHR_Disease.active then
        modData.EHR_Disease.active["aspergillosis"] = nil
        modData.EHR_Disease.active["putrefaction_sickness"] = nil
    end

    modData.EHR_Corpse = nil
    modData.EHR_Corpse_Initialized = nil
end

function EHR.CorpseSickness.IsImmune(player)
    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return false end

    local currentTime = getGameTime():getWorldAgeHours()
    if data.immuneUntil and data.immuneUntil > currentTime then
        local maxUntil = currentTime + EHR.CorpseSickness.Config.IMMUNITY_DURATION
        if data.immuneUntil > maxUntil then
            data.immuneUntil = maxUntil
        end
    end
    return data.immuneUntil and currentTime < data.immuneUntil
end

function EHR.CorpseSickness.GrantImmunity(player)
    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return end

    local currentTime = getGameTime():getWorldAgeHours()
    data.immuneUntil = currentTime + EHR.CorpseSickness.Config.IMMUNITY_DURATION
    EHR.Log("Corpse sickness immunity granted until hour " .. data.immuneUntil)
end

function EHR.CorpseSickness.ResetAfterCure(player)
    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return end

    data.currentExposure = 0
    data.maxExposure = 0
    data.timeInArea = 0
    data.lastCorpseCount = 0
    data.lastWarningTime = 0
    data.lastUpdateHour = getGameTime():getWorldAgeHours()

    EHR.CorpseSickness.GrantImmunity(player)

    local stats = player:getStats()
    if stats and CharacterStat then
        if CharacterStat.SICKNESS then
            pcall(function()
                local current = stats:get(CharacterStat.SICKNESS) or 0
                stats:set(CharacterStat.SICKNESS, math.min(current, 0.1))
            end)
        end
        if CharacterStat.FOOD_SICKNESS then
            pcall(function()
                local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
                stats:set(CharacterStat.FOOD_SICKNESS, math.min(current, 0.1))
            end)
        end
    end

    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end

    EHR.Log("Corpse sickness exposure reset after cure")
end

-- ============================================
-- CORPSE DETECTION
-- ============================================

function EHR.CorpseSickness.ScanNearbyCorpses(player)
    local result = {
        count = 0,
        freshCount = 0,
        decomposingCount = 0,
        rottenCount = 0,
        totalEmission = 0,
    }

    if not player then return result end

    local config = EHR.CorpseSickness.Config
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local cell = getCell()
    if not cell then return result end

    local currentTime = getGameTime():getWorldAgeHours()

    for dx = -config.SEARCH_RADIUS, config.SEARCH_RADIUS do
        for dy = -config.SEARCH_RADIUS, config.SEARCH_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local objects = sq:getStaticMovingObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local corpse = objects:get(i)
                        if corpse and instanceof(corpse, "IsoDeadBody") then
                            local corpseSquare = corpse:getSquare()
                            if corpseSquare then
                                result.count = result.count + 1

                                local corpseKey = string.format("%.0f_%.0f_%.0f",
                                    corpse:getX(), corpse:getY(), corpse:getZ())

                                local deathTime = nil
                                if corpse.getDeathTime then
                                    local ok, dt = pcall(function() return corpse:getDeathTime() end)
                                    if ok and dt and dt > 0 then
                                        deathTime = dt
                                    end
                                end

                                if not deathTime then
                                    if not EHR.CorpseSickness.FirstSeenCorpses[corpseKey] then
                                        EHR.CorpseSickness.FirstSeenCorpses[corpseKey] = currentTime
                                    end
                                    deathTime = EHR.CorpseSickness.FirstSeenCorpses[corpseKey]
                                end

                                local corpseAge = currentTime - deathTime
                                if corpseAge < 0 then corpseAge = 0 end

                                if corpseAge < config.CORPSE_AGE_FRESH then
                                    result.freshCount = result.freshCount + 1
                                    result.totalEmission = result.totalEmission + config.EMISSION_RATE.fresh
                                elseif corpseAge < config.CORPSE_AGE_DECOMPOSING then
                                    result.decomposingCount = result.decomposingCount + 1
                                    result.totalEmission = result.totalEmission + config.EMISSION_RATE.decomposing
                                else
                                    result.rottenCount = result.rottenCount + 1
                                    result.totalEmission = result.totalEmission + config.EMISSION_RATE.rotten
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return result
end

-- ============================================
-- PROTECTION + ENVIRONMENT
-- ============================================

local function hasTag(item, tag)
    if not item or not item.hasTag then return false end
    local ok, result = pcall(function() return item:hasTag(tag) end)
    return ok and result == true
end

local function getMaskItem(player)
    if not player or not player.getWornItems then return nil end

    local wornItems = player:getWornItems()
    if not wornItems then return nil end

    local count = wornItems:size()
    for i = 0, count - 1 do
        local item = wornItems:getItemByIndex(i)
        if item and item.getBodyLocation then
            local loc = item:getBodyLocation()
            local locName = loc and tostring(loc) or nil
            if locName == "Mask" or locName == "MaskEyes" or locName == "MaskFull" then
                return item
            end
        end
    end

    return nil
end

function EHR.CorpseSickness.GetProtectionLevel(player)
    if not player then return 0 end

    local config = EHR.CorpseSickness.Config
    local mask = getMaskItem(player)

    -- Tag-based checks (preferred)
    if mask then
        if hasTag(mask, "GasMask") or hasTag(mask, "NBC") then
            return config.PROTECTION.gas_mask
        end
        if hasTag(mask, "SurgicalMask") or hasTag(mask, "MedicalMask") then
            return config.PROTECTION.surgical_mask
        end
        if hasTag(mask, "Bandana") or hasTag(mask, "Scarf") then
            return config.PROTECTION.bandana
        end
    end

    -- Slot/type fallback
    if mask then
        local maskType = mask.getType and mask:getType() or ""
        if maskType:find("GasMask") or maskType:find("NBC") then
            return config.PROTECTION.gas_mask
        end
        if maskType:find("SurgicalMask") or maskType:find("MedicalMask") then
            return config.PROTECTION.surgical_mask
        end
        if maskType:find("Bandana") or maskType:find("Scarf") then
            return config.PROTECTION.bandana
        end
    end

    return config.PROTECTION.none
end

function EHR.CorpseSickness.GetEnvironmentMultiplier(player)
    if not player then return 1.0 end

    local config = EHR.CorpseSickness.Config
    local sq = player:getCurrentSquare()
    if not sq then return 1.0 end

    if sq.isOutside and sq:isOutside() then
        return 1.0
    end

    local room = nil
    if sq.getRoom then
        local ok, r = pcall(function() return sq:getRoom() end)
        if ok then room = r end
    end

    if room and room.getAreaSquares then
        local ok, area = pcall(function() return room:getAreaSquares() end)
        if ok and area and area <= 20 then
            return config.ENCLOSED_MULTIPLIER
        end
    end

    return config.INDOOR_MULTIPLIER
end

--[[
    Check if player is safely inside a sealed vehicle.
    Returns true if player is in a vehicle with all doors and windows closed/intact.
]]--
function EHR.CorpseSickness.IsProtectedInVehicle(player)
    if not player then return false end

    local ok, vehicle = pcall(function() return player:getVehicle() end)
    if not ok or not vehicle then return false end

    -- Check all doors and windows using pcall for B42 compatibility
    local ok2, partCount = pcall(function() return vehicle:getPartCount() end)
    if not ok2 or not partCount or partCount <= 0 then return false end

    for i = 0, partCount - 1 do
        local ok3, part = pcall(function() return vehicle:getPartByIndex(i) end)
        if ok3 and part then
            -- Get part ID safely (B42 uses getId() not getType())
            local partId = nil
            local ok4, id = pcall(function() return part:getId() end)
            if ok4 and id then
                partId = id
            else
                -- Fallback to getType if getId doesn't exist
                local ok5, ptype = pcall(function() return part:getType() end)
                if ok5 and ptype then partId = ptype end
            end

            if partId then
                local typeLower = string.lower(tostring(partId))

                -- Check doors
                if typeLower:find("door") then
                    local ok6, door = pcall(function() return part:getDoor() end)
                    if ok6 and door then
                        local ok7, isOpen = pcall(function() return door:isOpen() end)
                        if ok7 and isOpen then
                            return false
                        end
                    end
                    -- Check if door is destroyed/missing
                    local ok8, condition = pcall(function() return part:getCondition() end)
                    if ok8 and condition and condition <= 0 then
                        return false
                    end
                end

                -- Check windows
                if typeLower:find("window") then
                    local ok9, window = pcall(function() return part:getWindow() end)
                    if ok9 and window then
                        local ok10, isOpen = pcall(function() return window:isOpen() end)
                        if ok10 and isOpen then
                            return false
                        end
                        local ok11, isDestroyed = pcall(function() return window:isDestroyed() end)
                        if ok11 and isDestroyed then
                            return false
                        end
                    end
                    -- Check window condition (0 = broken)
                    local ok12, condition = pcall(function() return part:getCondition() end)
                    if ok12 and condition and condition <= 0 then
                        return false
                    end
                end
            end
        end
    end

    -- All doors closed and windows intact - player is protected
    return true
end

-- ============================================
-- EXPOSURE UPDATE
-- ============================================

function EHR.CorpseSickness.UpdateExposure(player)
    if not player then return end

    if EHR.CorpseSickness.IsImmune(player) then
        return
    end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active and diseaseData.active["corpse_sickness"] then
        return
    end

    -- Check if player is safely inside a sealed vehicle
    if EHR.CorpseSickness.IsProtectedInVehicle(player) then
        -- Player is protected - decay exposure but don't accumulate
        local data = EHR.CorpseSickness.GetExposureData(player)
        if data then
            local currentHour = getGameTime():getWorldAgeHours()
            local lastHour = data.lastUpdateHour or currentHour
            local deltaHours = currentHour - lastHour
            if deltaHours > 0 and deltaHours <= 1 then
                local config = EHR.CorpseSickness.Config
                local decay = config.EXPOSURE_DECAY_PER_HOUR * deltaHours
                data.currentExposure = math.max(0, data.currentExposure - decay)
            end
            data.lastUpdateHour = currentHour
            data.timeInArea = 0
            EHR.CorpseSickness.DecayVanillaSickness(player, data.currentExposure, deltaHours)
        end
        return
    end

    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return end

    local config = EHR.CorpseSickness.Config
    local corpseInfo = EHR.CorpseSickness.ScanNearbyCorpses(player)
    data.lastCorpseCount = corpseInfo.count

    local vanillaSickness = 0
    local stats = player:getStats()
    if stats and CharacterStat then
        if CharacterStat.SICKNESS then
            local ok, value = pcall(function() return stats:get(CharacterStat.SICKNESS) end)
            if ok and value then vanillaSickness = math.max(vanillaSickness, value) end
        end
        if CharacterStat.FOOD_SICKNESS then
            local ok, value = pcall(function() return stats:get(CharacterStat.FOOD_SICKNESS) end)
            if ok and value then vanillaSickness = math.max(vanillaSickness, value) end
        end
    end


    local currentHour = getGameTime():getWorldAgeHours()
    local lastHour = data.lastUpdateHour or currentHour
    local deltaHours = currentHour - lastHour
    if deltaHours <= 0 or deltaHours > 1 then
        deltaHours = 5 / 3600
    end
    data.lastUpdateHour = currentHour

    if corpseInfo.totalEmission <= 0 then
        if corpseInfo.count > 0 and vanillaSickness > 0.01 then
            corpseInfo.totalEmission = math.max(1, math.min(corpseInfo.count, config.CORPSE_COUNT_DANGEROUS))
        else
            local decay = config.EXPOSURE_DECAY_PER_HOUR * deltaHours
            data.currentExposure = math.max(0, data.currentExposure - decay)
            data.timeInArea = 0
            EHR.CorpseSickness.DecayVanillaSickness(player, data.currentExposure, deltaHours)
            return
        end
    end

    local envMultiplier = EHR.CorpseSickness.GetEnvironmentMultiplier(player)
    local protection = EHR.CorpseSickness.GetProtectionLevel(player)
    if protection >= 1.0 then
        EHR.CorpseSickness.DecayVanillaSickness(player, data.currentExposure, deltaHours)
        return
    end

    local baseExposure = corpseInfo.totalEmission * deltaHours
    local effectiveExposure = baseExposure * envMultiplier * (1 - protection) * getSpeedMultiplier()

    data.currentExposure = data.currentExposure + effectiveExposure
    data.maxExposure = math.max(data.maxExposure, data.currentExposure)
    data.timeInArea = data.timeInArea + deltaHours

    -- Only show smell warnings after sufficient exposure AND time
    local shouldWarn = data.currentExposure >= config.MIN_EXPOSURE_FOR_WARNING
        and data.timeInArea >= config.MIN_TIME_FOR_WARNING
        and currentHour - (data.lastWarningTime or 0) > 0.5

    if shouldWarn then
        EHR.CorpseSickness.ShowSmellWarning(player)
        data.lastWarningTime = currentHour
    end

    if data.currentExposure >= config.EXPOSURE_THRESHOLD_HIGH then
        if data.timeInArea >= config.MIN_EXPOSURE_TIME_HOURS then
            EHR.CorpseSickness.TriggerSickness(player)
        end
    elseif data.currentExposure >= config.EXPOSURE_THRESHOLD_MEDIUM then
        if data.timeInArea >= config.MIN_EXPOSURE_TIME_HOURS and ZombRand(100) < 30 then
            EHR.CorpseSickness.TriggerSickness(player)
        end
    end

    EHR.CorpseSickness.ApplyNauseaMoodle(player, data.currentExposure)
end

-- ============================================
-- EFFECTS
-- ============================================

function EHR.CorpseSickness.ShowSmellWarning(player)
    if not player or not player.Say then return end
    local dialogues = EHR.CorpseSickness.Config.SMELL_DIALOGUES
    local line = dialogues[ZombRand(#dialogues) + 1]
    player:Say(line)
end

function EHR.CorpseSickness.GetVanillaSicknessTarget(exposure)
    local config = EHR.CorpseSickness.Config
    if exposure >= config.EXPOSURE_THRESHOLD_HIGH then
        return 0.6
    elseif exposure >= config.EXPOSURE_THRESHOLD_MEDIUM then
        return 0.4
    elseif exposure >= config.EXPOSURE_THRESHOLD_LOW then
        return 0.2
    end
    return 0
end

function EHR.CorpseSickness.HasOtherActiveDisease(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return false end
    for diseaseId, _ in pairs(diseaseData.active) do
        if diseaseId ~= "corpse_sickness" then
            return true
        end
    end
    return false
end

function EHR.CorpseSickness.DecayVanillaSickness(player, exposure, deltaHours)
    if not player or not deltaHours or deltaHours <= 0 then return end
    if EHR.CorpseSickness.HasOtherActiveDisease(player) then return end

    local stats = player:getStats()
    if not stats or not CharacterStat then return end

    local target = EHR.CorpseSickness.GetVanillaSicknessTarget(exposure or 0)
    local step = EHR.CorpseSickness.Config.VANILLA_SICKNESS_DECAY_PER_HOUR * deltaHours

    if CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            if current > target then
                stats:set(CharacterStat.SICKNESS, math.max(target, current - step))
            end
        end)
    end

    if CharacterStat.FOOD_SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            if current > target then
                stats:set(CharacterStat.FOOD_SICKNESS, math.max(target, current - step))
            end
        end)
    end
end

function EHR.CorpseSickness.ApplyNauseaMoodle(player, exposure)
    if not player or not exposure then return end

    local stats = player:getStats()
    if not stats or not CharacterStat or not CharacterStat.SICKNESS then return end

    local current = stats:get(CharacterStat.SICKNESS) or 0
    local target = EHR.CorpseSickness.GetVanillaSicknessTarget(exposure)

    if target > current then
        pcall(function() stats:set(CharacterStat.SICKNESS, target) end)
    end
end

function EHR.CorpseSickness.TriggerSickness(player)
    if not player then return end

    local contracted = false
    if EHR.Disease and EHR.Disease.TryContract then
        contracted = EHR.Disease.TryContract(player, "corpse_sickness", 1.0)
    elseif EHR.Disease and EHR.Disease.AddDisease then
        EHR.Disease.AddDisease(player, "corpse_sickness")
        contracted = true
    end

    if contracted then
        local data = EHR.CorpseSickness.GetExposureData(player)
        if data then
            data.currentExposure = 0
            data.timeInArea = 0
        end
        if player.Say then
            player:Say("I don't feel so good... must be the corpses.")
        end
        EHR.Log("Player contracted corpse sickness")
    end
end

-- ============================================
-- UI DISPLAY
-- ============================================

function EHR.CorpseSickness.GetExposureDisplay(player)
    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return "None" end

    local config = EHR.CorpseSickness.Config
    if data.currentExposure >= config.EXPOSURE_THRESHOLD_HIGH then
        return "High"
    elseif data.currentExposure >= config.EXPOSURE_THRESHOLD_MEDIUM then
        return "Medium"
    elseif data.currentExposure >= config.EXPOSURE_THRESHOLD_LOW then
        return "Low"
    end
    return "None"
end

function EHR.CorpseSickness.GetExposureColor(level)
    local colors = {
        None = {0.5, 0.5, 0.5},
        Low = {0.8, 0.8, 0.2},
        Medium = {1.0, 0.5, 0.0},
        High = {1.0, 0.2, 0.2},
    }
    return colors[level] or colors.None
end

-- ============================================
-- EVENT HOOKS
-- ============================================

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

function EHR.CorpseSickness.OnTick()
    if EHR.Disease and EHR.Disease.IsEnabled and not EHR.Disease.IsEnabled() then
        return
    end
    if not isEnabled() then return end

    if isClient and isClient() and not (isServer and isServer()) then
        return
    end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        if player and player:isAlive() then
            EHR.CorpseSickness.InitializePlayer(player)
            EHR.CorpseSickness.MigrateOldData(player)

            local state = getTickState(player)
            state.tick = state.tick + 1
            if state.tick >= EHR.CorpseSickness.Config.UPDATE_TICKS then
                state.tick = 0
                EHR.CorpseSickness.UpdateExposure(player)
                if player.transmitModData then
                    pcall(function() player:transmitModData() end)
                end
            end
        end
    end
end

function EHR.CorpseSickness.OnGameStart()
    local player = getSpecificPlayer(0)
    if player then
        EHR.CorpseSickness.InitializePlayer(player)
        EHR.CorpseSickness.MigrateOldData(player)
    end
end

function EHR.CorpseSickness.OnCreatePlayer(playerIndex, player)
    EHR.CorpseSickness.InitializePlayer(player)
    EHR.CorpseSickness.MigrateOldData(player)
end

if Events and not EHR.CorpseSickness._eventsRegistered then
    EHR.CorpseSickness._eventsRegistered = true

    Events.OnTick.Add(EHR.CorpseSickness.OnTick)
    Events.OnGameStart.Add(EHR.CorpseSickness.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.CorpseSickness.OnCreatePlayer)
end

EHR.Log("EHR_CorpseSickness.lua loaded")
