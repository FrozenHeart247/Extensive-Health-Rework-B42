--[[
    Extensive Health Rework B42
    Corpse Sickness Module (Unified System)

    Handles acute corpse exposure sickness plus damp/cold corpse-spore illness.
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
        respirator = 1.00,
        dust_mask = 0.80,
        surgical_mask = 0.65,
        cloth_mask = 0.50,
        bandana = 0.50,
        none = 0.00,
    },

    -- Time to get sick (hours of exposure at threshold)
    MIN_EXPOSURE_TIME_HOURS = 1,

    -- Search radius for corpses (tiles)
    SEARCH_RADIUS = 10,

    -- Update frequency (game ticks)
    UPDATE_TICKS = 300,
    QUICK_CLAMP_TICKS = 1,

    -- Immunity duration after recovery (hours)
    IMMUNITY_DURATION = 2,

    -- Exposure decay per hour when safe
    EXPOSURE_DECAY_PER_HOUR = 30,

    -- How quickly corpse-driven vanilla sickness fades after leaving corpses (0-1 stat scale per hour)
    VANILLA_SICKNESS_DECAY_PER_HOUR = 0.75,


    -- Smooth vanilla corpse-sickness bridge so B42 vanilla spikes do not instantly become Medium/High EHR exposure
    VANILLA_BRIDGE_RISE_PER_HOUR = 20,
    VANILLA_BRIDGE_DECAY_PER_HOUR = 60,
    VANILLA_SICKNESS_CLAMP_BUFFER = 0.005,
    VANILLA_SICKNESS_CLEAR_THRESHOLD = 0.005,
    VANILLA_SICKNESS_CLEAR_EXPOSURE = 1,
    FOOD_SICKNESS_SUPPRESS_DURATION = 0.5,
    FOOD_RISK_GRACE_HOURS = 6,

    -- Cadaveric aspergillosis: fungal spores from damp/cold decomposing corpses
    ASPERGILLOSIS_EXPOSURE_THRESHOLD = 120,
    ASPERGILLOSIS_MIN_EXPOSURE_TIME_HOURS = 1.5,
    ASPERGILLOSIS_CHECK_INTERVAL_HOURS = 1.0,
    ASPERGILLOSIS_EXPOSURE_DECAY_PER_HOUR = 25,
    ASPERGILLOSIS_GAIN_RATE = 1.8,
    ASPERGILLOSIS_WETNESS_THRESHOLD = 0.30,
    ASPERGILLOSIS_COLD_TEMP = 10,
    ASPERGILLOSIS_DAMP_MULTIPLIER = 1.6,
    ASPERGILLOSIS_COLD_MULTIPLIER = 1.25,
    ASPERGILLOSIS_INDOOR_MULTIPLIER = 1.15,
    ASPERGILLOSIS_BASE_CHANCE = 0.35,
    ASPERGILLOSIS_MAX_CHANCE = 0.85,
    ASPERGILLOSIS_TEST_ALL_CORPSES_ROTTEN = true,

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

    local putrefaction = options.PutrefactionSicknessEnabled
    local cadaveric = options.CadavericAspergillosisEnabled
    if cadaveric == nil then cadaveric = options.AspergilliosisEnabled end

    return (putrefaction ~= false) or (cadaveric ~= false)
end

local function getSpeedMultiplier()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not options then return 1.0 end
    return options.CorpseDiseaseSpeed or 1.0
end

local function isAspergillosisEnabled()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not options then return true end

    if options.CadavericAspergillosisEnabled ~= nil then
        return options.CadavericAspergillosisEnabled
    end

    -- Legacy fallback for saves/servers that still have the old misspelled option.
    if options.AspergilliosisEnabled ~= nil then
        return options.AspergilliosisEnabled
    end

    return true
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
        vanillaCorpseExposure = 0,
        lastVanillaSickness = 0,
        lastVanillaCorpseSignalHour = 0,
        suppressFoodSicknessUntil = 0,
        immuneUntil = 0,
        fungalExposure = 0,
        fungalMaxExposure = 0,
        fungalTimeInArea = 0,
        lastFungalUpdateHour = 0,
        lastFungalCheckHour = 0,
        lastFungalCorpseCount = 0,
        lastFungalRiskReason = nil,
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
        data.vanillaCorpseExposure = data.vanillaCorpseExposure or 0
        data.lastVanillaSickness = data.lastVanillaSickness or 0
        data.lastVanillaCorpseSignalHour = data.lastVanillaCorpseSignalHour or 0
        data.suppressFoodSicknessUntil = data.suppressFoodSicknessUntil or 0
        data.immuneUntil = data.immuneUntil or 0
        data.fungalExposure = data.fungalExposure or 0
        data.fungalMaxExposure = data.fungalMaxExposure or 0
        data.fungalTimeInArea = data.fungalTimeInArea or 0
        data.lastFungalUpdateHour = data.lastFungalUpdateHour or 0
        data.lastFungalCheckHour = data.lastFungalCheckHour or 0
        data.lastFungalCorpseCount = data.lastFungalCorpseCount or 0
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
    data.vanillaCorpseExposure = 0
    data.lastVanillaSickness = 0
    data.lastVanillaCorpseSignalHour = 0
    data.suppressFoodSicknessUntil = 0
    data.lastWarningTime = 0
    data.lastUpdateHour = getGameTime():getWorldAgeHours()

    EHR.CorpseSickness.GrantImmunity(player)

    local targetB42 = 0
    if EHR.Disease and EHR.Disease.GetTargetVanillaSickness then
        targetB42 = (EHR.Disease.GetTargetVanillaSickness(player, "corpse_sickness") or 0) / 100
    end

    local stats = player:getStats()
    if stats and CharacterStat then
        if CharacterStat.SICKNESS then
            pcall(function()
                local current = stats:get(CharacterStat.SICKNESS) or 0
                stats:set(CharacterStat.SICKNESS, math.min(current, targetB42))
            end)
        end
        if CharacterStat.FOOD_SICKNESS then
            pcall(function()
                local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
                stats:set(CharacterStat.FOOD_SICKNESS, math.min(current, targetB42))
            end)
        end
    end

    EHR.CorpseSickness.ClampVanillaSickness(player, 0)
    EHR.CorpseSickness.SuppressFoodSicknessComponent(player)

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
    local seenCorpses = {}

    local function safeCall(fn, fallback)
        local ok, value = pcall(fn)
        if ok then return value end
        return fallback
    end

    local playerSquare = player.getCurrentSquare and safeCall(function() return player:getCurrentSquare() end, nil) or nil

    local function getSquareRoom(square)
        if not square or not square.getRoom then return nil end
        return safeCall(function() return square:getRoom() end, nil)
    end

    local function getSquareBuilding(square, room)
        if square and square.getBuilding then
            local building = safeCall(function() return square:getBuilding() end, nil)
            if building then return building end
        end
        if room and room.getBuilding then
            return safeCall(function() return room:getBuilding() end, nil)
        end
        return nil
    end

    local function isSquareOutside(square)
        if not square then return false end
        if square.isOutside then
            local outside = safeCall(function() return square:isOutside() end, nil)
            if outside ~= nil then return outside == true end
        end
        if square.isInARoom then
            local inRoom = safeCall(function() return square:isInARoom() end, nil)
            if inRoom ~= nil then return not inRoom end
        end
        return getSquareRoom(square) == nil
    end

    local playerRoom = getSquareRoom(playerSquare)
    local playerBuilding = getSquareBuilding(playerSquare, playerRoom)
    local playerOutside = isSquareOutside(playerSquare)

    local function sharesCorpseAir(corpseSquare)
        if not playerSquare or not corpseSquare then return true end

        local corpseOutside = isSquareOutside(corpseSquare)
        if playerOutside ~= corpseOutside then
            return false
        end
        if playerOutside then
            return true
        end

        local corpseRoom = getSquareRoom(corpseSquare)
        local corpseBuilding = getSquareBuilding(corpseSquare, corpseRoom)
        if playerBuilding and corpseBuilding then
            return playerBuilding == corpseBuilding
        end
        if playerRoom and corpseRoom then
            return playerRoom == corpseRoom
        end

        return false
    end

    local function getListSize(objects)
        if not objects then return 0 end
        if objects.size then
            local value = safeCall(function() return objects:size() end, 0)
            return tonumber(value) or 0
        end
        if type(objects) == "table" then
            return #objects
        end
        return 0
    end

    local function getListItem(objects, index)
        if not objects then return nil end
        if objects.get then
            return safeCall(function() return objects:get(index) end, nil)
        end
        if type(objects) == "table" then
            return objects[index + 1]
        end
        return nil
    end

    local function addCorpse(corpse)
        if not corpse or not instanceof then return end

        local isDeadBody = safeCall(function() return instanceof(corpse, "IsoDeadBody") end, false)
        if not isDeadBody then return end

        local corpseSquare = nil
        if corpse.getSquare then
            corpseSquare = safeCall(function() return corpse:getSquare() end, nil)
        end
        if not corpseSquare then return end
        if not sharesCorpseAir(corpseSquare) then return end

        local cx = corpse.getX and safeCall(function() return corpse:getX() end, nil) or nil
        local cy = corpse.getY and safeCall(function() return corpse:getY() end, nil) or nil
        local cz = corpse.getZ and safeCall(function() return corpse:getZ() end, nil) or nil

        if not cx and corpseSquare.getX then cx = safeCall(function() return corpseSquare:getX() end, nil) end
        if not cy and corpseSquare.getY then cy = safeCall(function() return corpseSquare:getY() end, nil) end
        if not cz and corpseSquare.getZ then cz = safeCall(function() return corpseSquare:getZ() end, nil) end
        if not cx or not cy or cz == nil then return end

        if math.abs(cx - px) > config.SEARCH_RADIUS or math.abs(cy - py) > config.SEARCH_RADIUS then return end
        if math.floor(cz) ~= math.floor(pz) then return end

        local corpseKey = string.format("%.0f_%.0f_%.0f", cx, cy, cz)
        if seenCorpses[corpseKey] then return end
        seenCorpses[corpseKey] = true

        result.count = result.count + 1

        local deathTime = nil
        if corpse.getDeathTime then
            local dt = safeCall(function() return corpse:getDeathTime() end, nil)
            if dt and dt > 0 then
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

    local function scanObjectList(objects)
        local size = getListSize(objects)
        if size <= 0 then return end

        for i = 0, size - 1 do
            addCorpse(getListItem(objects, i))
        end
    end

    for dx = -config.SEARCH_RADIUS, config.SEARCH_RADIUS do
        for dy = -config.SEARCH_RADIUS, config.SEARCH_RADIUS do
            local sq = safeCall(function()
                return cell:getGridSquare(math.floor(px + dx), math.floor(py + dy), math.floor(pz))
            end, nil)

            if sq then
                if sq.getStaticMovingObjects then
                    scanObjectList(safeCall(function() return sq:getStaticMovingObjects() end, nil))
                end
                if sq.getMovingObjects then
                    scanObjectList(safeCall(function() return sq:getMovingObjects() end, nil))
                end
            end
        end
    end

    if result.count == 0 and cell.getObjectListForLua then
        scanObjectList(safeCall(function() return cell:getObjectListForLua() end, nil))
    end

    return result
end
-- ============================================
-- PROTECTION + ENVIRONMENT
-- ============================================

local function hasTag(item, tag)
    if not item or not tag or not item.getScriptItem then return false end

    local scriptItem = item:getScriptItem()
    if not scriptItem then return false end

    local tags = scriptItem:getTags()
    return tags and tags:contains(tag) == true
end

local function hasAnyTag(item, tags)
    if not tags then return false end
    for _, tag in ipairs(tags) do
        if hasTag(item, tag) then
            return true
        end
    end
    return false
end

local function containsAny(text, terms)
    if not text then return false end
    for _, term in ipairs(terms) do
        if text:find(term, 1, true) then
            return true
        end
    end
    return false
end

local function getItemText(item)
    if not item then return "" end

    local parts = {}
    if item.getType then
        local ok, value = pcall(function() return item:getType() end)
        if ok and value then table.insert(parts, tostring(value)) end
    end
    if item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value then table.insert(parts, tostring(value)) end
    end
    if item.getDisplayName then
        local ok, value = pcall(function() return item:getDisplayName() end)
        if ok and value then table.insert(parts, tostring(value)) end
    end

    return string.lower(table.concat(parts, " "))
end

local function getDrainableLevel(item)
    if not item then return nil end

    local methods = { "getCurrentUsesFloat", "getUsedDelta", "getDelta" }
    for _, method in ipairs(methods) do
        if item[method] then
            local ok, value = pcall(function() return item[method](item) end)
            if ok and type(value) == "number" then
                return value
            end
        end
    end

    return nil
end

local function isFilterlessMask(item)
    local text = getItemText(item)
    if containsAny(text, { "nofilter", "no filter", "_nofilter" }) then
        return true
    end

    return hasAnyTag(item, {
        "gasmasknofilter",
        "base:gasmasknofilter",
        "GasMaskNoFilter",
        "respiratornofilter",
        "base:respiratornofilter",
        "RespiratorNoFilter",
    })
end

local function hasUsableFilter(item)
    if isFilterlessMask(item) then
        return false
    end

    local level = getDrainableLevel(item)
    if level ~= nil then
        return level > 0.001
    end

    return true
end

local function getBodyLocationText(item)
    if not item or not item.getBodyLocation then return "" end
    local ok, value = pcall(function() return item:getBodyLocation() end)
    if not ok or not value then return "" end
    local loc = string.lower(tostring(value))
    loc = string.gsub(loc, "^base:", "")
    return loc
end

local function isFaceProtectionCandidate(item)
    if not item then return false end

    local loc = getBodyLocationText(item)
    if containsAny(loc, { "mask", "mouth", "face", "neck" }) then
        return true
    end

    if hasAnyTag(item, {
        "GasMask", "gasMask", "gasmask", "base:gasmask",
        "GasMaskNoFilter", "gasmasknofilter", "base:gasmasknofilter",
        "Respirator", "respirator", "base:respirator",
        "RespiratorNoFilter", "respiratornofilter", "base:respiratornofilter",
        "AirFilter", "airfilter", "FilterMask", "filtermask",
        "DustMask", "dustmask", "base:dustmask", "N95", "n95",
        "SurgicalMask", "surgicalmask", "MedicalMask", "medicalmask",
        "Bandana", "bandana", "Scarf", "scarf", "ClothMask", "clothmask",
        "FaceCover", "facecover", "NBC", "nbc", "Hazmat", "hazmat",
    }) then
        return true
    end

    local text = getItemText(item)
    return containsAny(text, {
        "mask",
        "respirator",
        "bandana",
        "scarf",
        "balaclava",
        "facecover",
        "face cover",
        "mouthcover",
        "mouth cover",
    })
end

local function getFaceProtectionItems(player)
    local result = {}
    if not player or not player.getWornItems then return result end

    local wornItems = player:getWornItems()
    if not wornItems then return result end

    local count = wornItems:size()
    for i = 0, count - 1 do
        local item = wornItems:getItemByIndex(i)
        if isFaceProtectionCandidate(item) then
            table.insert(result, item)
        end
    end

    return result
end

local function getTaggedProtection(item, config)
    if hasAnyTag(item, { "GasMask", "gasMask", "gasmask", "base:gasmask", "NBC", "nbc", "Hazmat", "hazmat" }) then
        if hasUsableFilter(item) then
            return config.PROTECTION.gas_mask
        end
        return config.PROTECTION.dust_mask
    end
    if hasAnyTag(item, { "Respirator", "respirator", "base:respirator", "AirFilter", "airfilter", "FilterMask", "filtermask" }) then
        if hasUsableFilter(item) then
            return config.PROTECTION.respirator
        end
        return config.PROTECTION.dust_mask
    end
    if hasAnyTag(item, { "DustMask", "dustmask", "base:dustmask", "N95", "n95" }) then
        return config.PROTECTION.dust_mask
    end
    if hasAnyTag(item, { "SurgicalMask", "surgicalmask", "MedicalMask", "medicalmask" }) then
        return config.PROTECTION.surgical_mask
    end
    if hasAnyTag(item, { "Bandana", "bandana", "Scarf", "scarf", "ClothMask", "clothmask", "FaceCover", "facecover" }) then
        return config.PROTECTION.cloth_mask
    end
    return nil
end

local function getNamedProtection(item, config)
    local text = getItemText(item)

    if containsAny(text, { "gasmask", "gas mask", "hat_gasmask", "nbc", "hazmat" }) then
        if hasUsableFilter(item) then
            return config.PROTECTION.gas_mask
        end
        return config.PROTECTION.dust_mask
    end
    if containsAny(text, { "respirator", "airfilter", "air filter" }) then
        if hasUsableFilter(item) then
            return config.PROTECTION.respirator
        end
        return config.PROTECTION.dust_mask
    end
    if containsAny(text, { "dustmask", "dust mask", "n95", "filtermask", "filter mask" }) then
        return config.PROTECTION.dust_mask
    end
    if containsAny(text, { "surgicalmask", "surgical mask", "medicalmask", "medical mask" }) then
        return config.PROTECTION.surgical_mask
    end
    if containsAny(text, { "bandana", "scarf", "balaclava", "clothmask", "cloth mask", "mouthmask", "mouth mask" }) then
        return config.PROTECTION.cloth_mask
    end
    if text:find("mask", 1, true) then
        return config.PROTECTION.cloth_mask
    end

    return nil
end

function EHR.CorpseSickness.GetProtectionLevel(player)
    if not player then return 0 end

    local config = EHR.CorpseSickness.Config
    local protection = config.PROTECTION.none
    local items = getFaceProtectionItems(player)

    for _, item in ipairs(items) do
        local itemProtection = getTaggedProtection(item, config) or getNamedProtection(item, config)
        if itemProtection and itemProtection > protection then
            protection = itemProtection
        end
    end

    return protection
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

local function getPlayerWetness(player)
    if EHR.Environmental and EHR.Environmental.GetWetness then
        local ok, wetness = pcall(function() return EHR.Environmental.GetWetness(player) end)
        if ok and wetness then return wetness end
    end

    local stats = player and player:getStats()
    if stats and CharacterStat and CharacterStat.WETNESS then
        local ok, wetness = pcall(function() return stats:get(CharacterStat.WETNESS) end)
        if ok and wetness then return wetness end
    end

    if player and player.getWetness then
        local ok, wetness = pcall(function() return player:getWetness() end)
        if ok and wetness then return wetness end
    end

    return 0
end

local function getAirTemperature()
    if EHR.Environmental and EHR.Environmental.GetAirTemperature then
        local ok, temp = pcall(function() return EHR.Environmental.GetAirTemperature() end)
        if ok and temp then return temp end
    end

    local climate = getClimateManager and getClimateManager() or nil
    if climate and climate.getTemperature then
        local ok, temp = pcall(function() return climate:getTemperature() end)
        if ok and temp then return temp end
    end

    return 15
end

local function isRainingNow()
    local climate = getClimateManager and getClimateManager() or nil
    if climate then
        if climate.getPrecipitationIntensity then
            local ok, intensity = pcall(function() return climate:getPrecipitationIntensity() end)
            if ok and tonumber(intensity) and tonumber(intensity) > 0.03 then return true end
        end

        if climate.getRainIntensity then
            local ok, intensity = pcall(function() return climate:getRainIntensity() end)
            if ok and tonumber(intensity) and tonumber(intensity) > 0.03 then return true end
        end

        if climate.isRaining then
            local ok, raining = pcall(function() return climate:isRaining() end)
            if ok and raining == true then return true end
        end
    end

    if RainManager and RainManager.isRaining then
        local ok, raining = pcall(function() return RainManager.isRaining() end)
        if ok and raining == true then return true end
    end

    return false
end

local function isPlayerOutside(player)
    local sq = player and player:getCurrentSquare()
    if not sq then return false end

    if sq.isOutside then
        local ok, outside = pcall(function() return sq:isOutside() end)
        if ok and outside ~= nil then return outside == true end
    end

    if sq.isInARoom then
        local ok, inRoom = pcall(function() return sq:isInARoom() end)
        if ok and inRoom ~= nil then return not inRoom end
    end

    if sq.getRoom then
        local ok, room = pcall(function() return sq:getRoom() end)
        if ok then return room == nil end
    end

    return false
end

function EHR.CorpseSickness.GetFungalEnvironment(player)
    local config = EHR.CorpseSickness.Config
    local wetness = getPlayerWetness(player)
    local airTemp = getAirTemperature()
    local outside = isPlayerOutside(player)
    local raining = outside and isRainingNow()

    local isDamp = wetness >= (config.ASPERGILLOSIS_WETNESS_THRESHOLD or 0.30) or raining
    local isCold = airTemp <= (config.ASPERGILLOSIS_COLD_TEMP or 10)
    if not isDamp and not isCold then
        return 0, false, "dry"
    end

    local multiplier = 1.0
    local reasons = {}
    if isDamp then
        multiplier = multiplier * (config.ASPERGILLOSIS_DAMP_MULTIPLIER or 1.6)
        table.insert(reasons, "damp")
    end
    if isCold then
        multiplier = multiplier * (config.ASPERGILLOSIS_COLD_MULTIPLIER or 1.25)
        table.insert(reasons, "cold")
    end
    if not outside then
        multiplier = multiplier * (config.ASPERGILLOSIS_INDOOR_MULTIPLIER or 1.15)
        table.insert(reasons, "indoors")
    end

    return multiplier, true, table.concat(reasons, "+")
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

function EHR.CorpseSickness.UpdateAspergillosisExposure(player)
    if not player then return end

    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return end

    local config = EHR.CorpseSickness.Config
    local currentHour = getGameTime():getWorldAgeHours()
    local lastHour = data.lastFungalUpdateHour or currentHour
    local deltaHours = currentHour - lastHour
    if deltaHours <= 0 or deltaHours > 1 then
        deltaHours = 5 / 3600
    end
    data.lastFungalUpdateHour = currentHour

    local function decayFungalExposure()
        local decay = (config.ASPERGILLOSIS_EXPOSURE_DECAY_PER_HOUR or 25) * deltaHours
        data.fungalExposure = math.max(0, (data.fungalExposure or 0) - decay)
        data.fungalTimeInArea = math.max(0, (data.fungalTimeInArea or 0) - deltaHours)
        if data.fungalExposure <= 0 then
            data.fungalMaxExposure = 0
            data.lastFungalRiskReason = nil
            data.lastFungalCorpseCount = 0
        end
    end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active and diseaseData.active["cadaveric_aspergillosis"] then
        data.fungalExposure = 0
        data.fungalTimeInArea = 0
        data.lastFungalCorpseCount = 0
        return
    end

    if not isAspergillosisEnabled() then
        decayFungalExposure()
        return
    end

    if EHR.CorpseSickness.IsProtectedInVehicle(player) then
        decayFungalExposure()
        return
    end

    local protection = EHR.CorpseSickness.GetProtectionLevel(player)
    if protection >= 1.0 then
        decayFungalExposure()
        return
    end

    local corpseInfo = EHR.CorpseSickness.ScanNearbyCorpses(player)
    data.lastFungalCorpseCount = corpseInfo.count or 0

    local envMultiplier, hasFungalWeather, reason = EHR.CorpseSickness.GetFungalEnvironment(player)
    local sporeLoad
    if config.ASPERGILLOSIS_TEST_ALL_CORPSES_ROTTEN then
        sporeLoad = (corpseInfo.count or 0) * 2.0
    else
        sporeLoad = ((corpseInfo.decomposingCount or 0) * 1.0)
            + ((corpseInfo.rottenCount or 0) * 2.0)
            + ((corpseInfo.freshCount or 0) * 0.05)
    end

    if sporeLoad <= 0 or not hasFungalWeather then
        decayFungalExposure()
        return
    end

    local gain = sporeLoad
        * (config.ASPERGILLOSIS_GAIN_RATE or 1.8)
        * envMultiplier
        * (1 - protection)
        * getSpeedMultiplier()
        * deltaHours

    data.fungalExposure = math.max(0, (data.fungalExposure or 0) + gain)
    data.fungalMaxExposure = math.max(data.fungalMaxExposure or 0, data.fungalExposure)
    data.fungalTimeInArea = (data.fungalTimeInArea or 0) + deltaHours
    data.lastFungalRiskReason = reason

    local threshold = config.ASPERGILLOSIS_EXPOSURE_THRESHOLD or 120
    local minTime = config.ASPERGILLOSIS_MIN_EXPOSURE_TIME_HOURS or 1.5
    local checkInterval = config.ASPERGILLOSIS_CHECK_INTERVAL_HOURS or 1.0

    if data.fungalExposure < threshold or data.fungalTimeInArea < minTime then
        return
    end

    if currentHour - (data.lastFungalCheckHour or 0) < checkInterval then
        return
    end
    data.lastFungalCheckHour = currentHour

    local overThreshold = math.max(0, data.fungalExposure - threshold) / threshold
    local chance = (config.ASPERGILLOSIS_BASE_CHANCE or 0.35) + (overThreshold * 0.30)
    chance = math.min(config.ASPERGILLOSIS_MAX_CHANCE or 0.85, chance)

    local contracted = false
    if EHR.Disease and EHR.Disease.TryContract then
        contracted = EHR.Disease.TryContract(player, "cadaveric_aspergillosis", chance)
    elseif EHR.Disease and EHR.Disease.Contract then
        EHR.Disease.Contract(player, "cadaveric_aspergillosis")
        contracted = true
    end

    if contracted then
        data.fungalExposure = 0
        data.fungalMaxExposure = 0
        data.fungalTimeInArea = 0
        data.lastFungalCorpseCount = 0
        data.lastFungalRiskReason = nil
        if player.Say then
            player:Say("*coughs* My chest feels wrong after breathing that air...")
        end
        EHR.Log("Player contracted cadaveric aspergillosis from damp corpse exposure")
    end
end

function EHR.CorpseSickness.UpdateExposure(player)
    if not player then return end

    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return end

    EHR.CorpseSickness.UpdateAspergillosisExposure(player)

    if EHR.CorpseSickness.IsImmune(player) then
        data.currentExposure = 0
        data.vanillaCorpseExposure = 0
        data.lastVanillaCorpseSignalHour = 0
        data.timeInArea = 0
        EHR.CorpseSickness.ClampVanillaSickness(player, 0)
        EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
        return
    end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active and diseaseData.active["corpse_sickness"] then
        data.vanillaCorpseExposure = 0
        return
    end

    local config = EHR.CorpseSickness.Config
    local currentHour = getGameTime():getWorldAgeHours()
    local lastHour = data.lastUpdateHour or currentHour
    local deltaHours = currentHour - lastHour
    if deltaHours <= 0 or deltaHours > 1 then
        deltaHours = 5 / 3600
    end
    data.lastUpdateHour = currentHour

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

    if EHR.CorpseSickness.IsProtectedInVehicle(player) then
        local decay = config.EXPOSURE_DECAY_PER_HOUR * deltaHours
        data.currentExposure = math.max(0, data.currentExposure - decay)
        data.vanillaCorpseExposure = 0
        data.lastVanillaCorpseSignalHour = 0
        data.timeInArea = 0
        EHR.CorpseSickness.DecayVanillaSickness(player, data.currentExposure, deltaHours)
        EHR.CorpseSickness.ClampVanillaSickness(player, data.currentExposure)
        EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
        if data.currentExposure <= (config.VANILLA_SICKNESS_CLEAR_EXPOSURE or 1) then
            EHR.CorpseSickness.ClearTinyVanillaSickness(player, config.VANILLA_SICKNESS_CLEAR_THRESHOLD or 0.005)
        end
        local protectionTarget = EHR.CorpseSickness.GetVanillaSicknessTarget(data.currentExposure)
        data.lastVanillaSickness = math.min(vanillaSickness, protectionTarget + (config.VANILLA_SICKNESS_CLAMP_BUFFER or 0.005))
        return
    end

    local corpseInfo = EHR.CorpseSickness.ScanNearbyCorpses(player)
    data.lastCorpseCount = corpseInfo.count

    local envMultiplier = EHR.CorpseSickness.GetEnvironmentMultiplier(player)
    local protection = EHR.CorpseSickness.GetProtectionLevel(player)
    local isFullyProtected = protection >= 1.0

    local hasActiveFoodDisease = EHR.CorpseSickness.HasActiveFoodDisease(player)
    local hasRecentFoodRisk = EHR.CorpseSickness.HasRecentFoodRisk(player, currentHour)

    local rawVanillaCorpseSignal = corpseInfo.count > 0
        and vanillaSickness > 0.01
        and not hasActiveFoodDisease
        and not hasRecentFoodRisk
        and not isFullyProtected
    if rawVanillaCorpseSignal then
        data.lastVanillaCorpseSignalHour = currentHour
    end

    local hasVanillaCorpseSignal = rawVanillaCorpseSignal

    if corpseInfo.count > 0 or hasVanillaCorpseSignal or (data.currentExposure or 0) > 0 or (data.vanillaCorpseExposure or 0) > 0 then
        data.suppressFoodSicknessUntil = currentHour + (config.FOOD_SICKNESS_SUPPRESS_DURATION or 0.5)
    end

    if corpseInfo.totalEmission <= 0 then
        if corpseInfo.count > 0 then
            corpseInfo.totalEmission = math.max(1, math.min(corpseInfo.count, config.CORPSE_COUNT_DANGEROUS))
        elseif hasVanillaCorpseSignal then
            corpseInfo.totalEmission = 0
        else
            local decay = config.EXPOSURE_DECAY_PER_HOUR * deltaHours
            data.currentExposure = math.max(0, data.currentExposure - decay)
            local bridgeDecay = (config.VANILLA_BRIDGE_DECAY_PER_HOUR or config.EXPOSURE_DECAY_PER_HOUR) * deltaHours
            data.vanillaCorpseExposure = math.max(0, (data.vanillaCorpseExposure or 0) - bridgeDecay)
            local effectiveExposureLevel = math.max(data.currentExposure, data.vanillaCorpseExposure or 0)
            data.timeInArea = 0
            EHR.CorpseSickness.DecayVanillaSickness(player, effectiveExposureLevel, deltaHours)
            if effectiveExposureLevel <= (config.VANILLA_SICKNESS_CLEAR_EXPOSURE or 1) then
                EHR.CorpseSickness.ClearTinyVanillaSickness(player, config.VANILLA_SICKNESS_CLEAR_THRESHOLD or 0.005)
            end
            local target = EHR.CorpseSickness.GetVanillaSicknessTarget(effectiveExposureLevel)
            data.lastVanillaSickness = math.min(vanillaSickness, target + (config.VANILLA_SICKNESS_CLAMP_BUFFER or 0.005))
            return
        end
    end

    if protection >= 1.0 then
        local decay = config.EXPOSURE_DECAY_PER_HOUR * deltaHours
        data.currentExposure = math.max(0, data.currentExposure - decay)
        data.vanillaCorpseExposure = 0
        data.lastVanillaCorpseSignalHour = 0
        data.timeInArea = 0
        EHR.CorpseSickness.DecayVanillaSickness(player, data.currentExposure, deltaHours)
        EHR.CorpseSickness.ClampVanillaSickness(player, data.currentExposure)
        EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
        if data.currentExposure <= (config.VANILLA_SICKNESS_CLEAR_EXPOSURE or 1) then
            EHR.CorpseSickness.ClearTinyVanillaSickness(player, config.VANILLA_SICKNESS_CLEAR_THRESHOLD or 0.005)
        end
        local protectionTarget = EHR.CorpseSickness.GetVanillaSicknessTarget(data.currentExposure)
        data.lastVanillaSickness = math.min(vanillaSickness, protectionTarget + (config.VANILLA_SICKNESS_CLAMP_BUFFER or 0.005))
        return
    end

    local baseExposure = corpseInfo.totalEmission * deltaHours
    local effectiveExposure = baseExposure * envMultiplier * (1 - protection) * getSpeedMultiplier()

    data.currentExposure = data.currentExposure + effectiveExposure

    local currentVanillaExposure = data.vanillaCorpseExposure or 0
    if hasVanillaCorpseSignal then
        local vanillaExposure = (vanillaSickness / 0.6) * config.EXPOSURE_THRESHOLD_HIGH
        vanillaExposure = math.min(config.EXPOSURE_THRESHOLD_HIGH, math.max(0, vanillaExposure))

        if vanillaSickness >= 0.55 then
            vanillaExposure = math.max(vanillaExposure, config.EXPOSURE_THRESHOLD_HIGH)
        elseif vanillaSickness >= 0.35 then
            vanillaExposure = math.max(vanillaExposure, config.EXPOSURE_THRESHOLD_MEDIUM)
        elseif vanillaSickness >= 0.15 then
            vanillaExposure = math.max(vanillaExposure, config.EXPOSURE_THRESHOLD_LOW)
        end

        local bridgeStep = (config.VANILLA_BRIDGE_RISE_PER_HOUR or 20) * deltaHours
        data.vanillaCorpseExposure = math.min(vanillaExposure, currentVanillaExposure + bridgeStep)
    else
        local bridgeDecay = (config.VANILLA_BRIDGE_DECAY_PER_HOUR or config.EXPOSURE_DECAY_PER_HOUR) * deltaHours
        data.vanillaCorpseExposure = math.max(0, currentVanillaExposure - bridgeDecay)
    end

    local effectiveExposureLevel = math.max(data.currentExposure, data.vanillaCorpseExposure or 0)
    data.maxExposure = math.max(data.maxExposure, effectiveExposureLevel)
    data.timeInArea = data.timeInArea + deltaHours

    local shouldWarn = effectiveExposureLevel >= config.MIN_EXPOSURE_FOR_WARNING
        and data.timeInArea >= config.MIN_TIME_FOR_WARNING
        and currentHour - (data.lastWarningTime or 0) > 0.5

    if shouldWarn then
        EHR.CorpseSickness.ShowSmellWarning(player)
        data.lastWarningTime = currentHour
    end

    local function logCorpseTrigger(reason)
        EHR.Log(string.format(
            "Corpse sickness trigger (%s): exposure=%.1f current=%.1f vanilla=%.1f time=%.2fh corpses=%d fresh=%d decomposing=%d rotten=%d emission=%.2f env=%.2f protection=%.2f vanillaSignal=%s",
            tostring(reason),
            effectiveExposureLevel or 0,
            data.currentExposure or 0,
            data.vanillaCorpseExposure or 0,
            data.timeInArea or 0,
            corpseInfo.count or 0,
            corpseInfo.freshCount or 0,
            corpseInfo.decomposingCount or 0,
            corpseInfo.rottenCount or 0,
            corpseInfo.totalEmission or 0,
            envMultiplier or 0,
            protection or 0,
            tostring(hasVanillaCorpseSignal)
        ))
    end

    local canTriggerCorpseSickness = not EHR.CorpseSickness.HasActiveCorpseDisease(player)

    if canTriggerCorpseSickness and effectiveExposureLevel >= config.EXPOSURE_THRESHOLD_HIGH then
        if data.timeInArea >= config.MIN_EXPOSURE_TIME_HOURS then
            logCorpseTrigger("high")
            EHR.CorpseSickness.TriggerSickness(player)
        end
    elseif canTriggerCorpseSickness and effectiveExposureLevel >= config.EXPOSURE_THRESHOLD_MEDIUM then
        if data.timeInArea >= config.MIN_EXPOSURE_TIME_HOURS and ZombRand(100) < 30 then
            logCorpseTrigger("medium")
            EHR.CorpseSickness.TriggerSickness(player)
        end
    end
    EHR.CorpseSickness.ApplyNauseaMoodle(player, effectiveExposureLevel)

    local storedVanillaSickness = vanillaSickness
    if hasVanillaCorpseSignal then
        EHR.CorpseSickness.ClampVanillaSickness(player, effectiveExposureLevel)
        EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
        local target = EHR.CorpseSickness.GetVanillaSicknessTarget(effectiveExposureLevel)
        storedVanillaSickness = math.min(storedVanillaSickness, target + (config.VANILLA_SICKNESS_CLAMP_BUFFER or 0.005))
    end
    data.lastVanillaSickness = storedVanillaSickness
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
    exposure = exposure or 0
    if exposure <= 0 then return 0 end

    local highThreshold = config.EXPOSURE_THRESHOLD_HIGH or 100
    if highThreshold <= 0 then return 0 end

    return math.min(0.6, math.max(0, (exposure / highThreshold) * 0.6))
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

function EHR.CorpseSickness.HasActiveCorpseDisease(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    return diseaseData and diseaseData.active and diseaseData.active["corpse_sickness"] ~= nil
end

function EHR.CorpseSickness.HasActiveFoodDisease(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    if not diseaseData or not diseaseData.active then return false end

    for diseaseId, disease in pairs(diseaseData.active) do
        local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId]
        if disease and (diseaseId == "food_poisoning" or (def and def.category == "food")) then
            return true
        end
    end

    return false
end

function EHR.CorpseSickness.HasRecentFoodRisk(player, currentHour)
    if not player then return false end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    local history = diseaseData and diseaseData.history
    local foodMemory = EHR.Disease and EHR.Disease.GetFoodRiskMemory and EHR.Disease.GetFoodRiskMemory(player)
    local lastBadFood = (history and history.lastBadFood) or (foodMemory and foodMemory.lastBadFood)
    if not lastBadFood then return false end

    currentHour = currentHour or getGameTime():getWorldAgeHours()
    local foodCuredTime = history and history.lastFoodCuredTime
    if foodCuredTime and foodCuredTime >= lastBadFood then
        if EHR.Disease and EHR.Disease.ClearFoodRiskMemory then
            EHR.Disease.ClearFoodRiskMemory(player)
        end
        if history and EHR.Disease and EHR.Disease.ClearFoodRiskHistory then
            EHR.Disease.ClearFoodRiskHistory(history)
        elseif history then
            history.lastBadFood = nil
            history.lastFoodRiskReason = nil
          history.lastFoodRiskChance = nil
          history.lastFoodAccumulatedRisk = nil
          history.lastFoodRiskDiseaseId = nil
          history.foodRiskAccumulated = nil
          history.foodRiskLastTime = nil
          history.foodRiskAccumulatedByDisease = nil
          history.foodRiskLastTimeByDisease = nil
        end
        return false
    end

    local elapsed = currentHour - lastBadFood
    local graceHours = EHR.CorpseSickness.Config.FOOD_RISK_GRACE_HOURS or 6
    if elapsed >= graceHours then
        if EHR.Disease and EHR.Disease.ClearFoodRiskMemory then
            EHR.Disease.ClearFoodRiskMemory(player)
        end
        if history and EHR.Disease and EHR.Disease.ClearFoodRiskHistory then
            EHR.Disease.ClearFoodRiskHistory(history)
        elseif history then
            history.lastBadFood = nil
            history.lastFoodRiskReason = nil
          history.lastFoodRiskChance = nil
          history.lastFoodAccumulatedRisk = nil
          history.lastFoodRiskDiseaseId = nil
          history.foodRiskAccumulated = nil
          history.foodRiskLastTime = nil
          history.foodRiskAccumulatedByDisease = nil
          history.foodRiskLastTimeByDisease = nil
        end
        return false
    end

    local decayPerHour = EHR.Disease
        and EHR.Disease.FoodRiskAccumulation
        and EHR.Disease.FoodRiskAccumulation.decayPerHour
        or 0.20
    local baseRisk = (history and (history.lastFoodAccumulatedRisk or history.foodRiskAccumulated)) or 0
    if foodMemory then
        baseRisk = math.max(baseRisk, foodMemory.accumulated or 0)
    end
    local baseRiskElapsed = math.max(0, currentHour - ((history and history.foodRiskLastTime) or (foodMemory and foodMemory.lastTime) or lastBadFood))
    local accumulatedRisk = math.max(0, baseRisk - (decayPerHour * baseRiskElapsed))

    if history and history.foodRiskAccumulatedByDisease then
        history.foodRiskLastTimeByDisease = history.foodRiskLastTimeByDisease or {}
        for diseaseId, risk in pairs(history.foodRiskAccumulatedByDisease) do
            local lastRiskTime = history.foodRiskLastTimeByDisease[diseaseId] or history.foodRiskLastTime or lastBadFood
            local riskElapsed = math.max(0, currentHour - lastRiskTime)
            local decayedRisk = math.max(0, (risk or 0) - (decayPerHour * riskElapsed))
            history.foodRiskAccumulatedByDisease[diseaseId] = decayedRisk
            accumulatedRisk = math.max(accumulatedRisk, decayedRisk)
        end
    end
    if foodMemory and foodMemory.accumulatedByDisease then
        foodMemory.lastTimeByDisease = foodMemory.lastTimeByDisease or {}
        for diseaseId, risk in pairs(foodMemory.accumulatedByDisease) do
            local lastRiskTime = foodMemory.lastTimeByDisease[diseaseId] or foodMemory.lastTime or lastBadFood
            local riskElapsed = math.max(0, currentHour - lastRiskTime)
            local decayedRisk = math.max(0, (risk or 0) - (decayPerHour * riskElapsed))
            foodMemory.accumulatedByDisease[diseaseId] = decayedRisk
            accumulatedRisk = math.max(accumulatedRisk, decayedRisk)
        end
    end

    if accumulatedRisk > 0.01 then
        if history then
            history.lastFoodAccumulatedRisk = accumulatedRisk
        end
        if foodMemory then
            foodMemory.accumulated = accumulatedRisk
        end
        return true
    end

    if elapsed > 0.25 and not EHR.CorpseSickness.HasActiveFoodDisease(player) then
        local stats = player:getStats()
        if stats and CharacterStat and CharacterStat.FOOD_SICKNESS then
            local ok, foodSickness = pcall(function() return stats:get(CharacterStat.FOOD_SICKNESS) end)
            if ok and (foodSickness or 0) <= 0.02 then
                if EHR.Disease and EHR.Disease.ClearFoodRiskMemory then
                    EHR.Disease.ClearFoodRiskMemory(player)
                end
                if history and EHR.Disease and EHR.Disease.ClearFoodRiskHistory then
                    EHR.Disease.ClearFoodRiskHistory(history)
                elseif history then
                    history.lastBadFood = nil
                    history.lastFoodRiskReason = nil
                  history.lastFoodRiskChance = nil
                  history.lastFoodAccumulatedRisk = nil
                  history.lastFoodRiskDiseaseId = nil
                  history.foodRiskAccumulated = nil
                  history.foodRiskLastTime = nil
                  history.foodRiskAccumulatedByDisease = nil
                  history.foodRiskLastTimeByDisease = nil
                end
                return false
            end
        end
    end

    return true
end

function EHR.CorpseSickness.ShouldSuppressFoodSickness(player, currentHour)
    if not player then return false end
    if EHR.CorpseSickness.HasActiveFoodDisease(player) then return false end
    if EHR.CorpseSickness.HasRecentFoodRisk(player, currentHour) then return false end

    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return false end

    currentHour = currentHour or getGameTime():getWorldAgeHours()
    if data.suppressFoodSicknessUntil and data.suppressFoodSicknessUntil > currentHour then
        return true
    end

    return (data.currentExposure or 0) > 0 or (data.vanillaCorpseExposure or 0) > 0
end

function EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
    if not player then return end
    if not EHR.CorpseSickness.ShouldSuppressFoodSickness(player) then return end

    local stats = player:getStats()
    if not stats or not CharacterStat or not CharacterStat.FOOD_SICKNESS then return end

    pcall(function()
        local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
        if current > 0 then
            stats:set(CharacterStat.FOOD_SICKNESS, 0)
        end
    end)
end

function EHR.CorpseSickness.GetCurrentVanillaSickness(player)
    if not player then return 0 end

    local stats = player:getStats()
    if not stats or not CharacterStat then return 0 end

    local value = 0
    if CharacterStat.SICKNESS then
        local ok, current = pcall(function() return stats:get(CharacterStat.SICKNESS) end)
        if ok and current then value = math.max(value, current) end
    end
    if CharacterStat.FOOD_SICKNESS then
        local ok, current = pcall(function() return stats:get(CharacterStat.FOOD_SICKNESS) end)
        if ok and current then value = math.max(value, current) end
    end

    return value
end

function EHR.CorpseSickness.QuickClampVanillaSickness(player)
    if not player then return end
    local isImmune = EHR.CorpseSickness.IsImmune(player)
    if EHR.CorpseSickness.HasOtherActiveDisease(player) then return end
    if EHR.CorpseSickness.HasActiveFoodDisease(player) then return end
    if EHR.CorpseSickness.HasRecentFoodRisk(player) then return end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active and diseaseData.active["corpse_sickness"] then
        return
    end

    local vanillaSickness = EHR.CorpseSickness.GetCurrentVanillaSickness(player)
    if vanillaSickness <= 0.01 then return end

    local data = EHR.CorpseSickness.GetExposureData(player)
    if not data then return end

    local currentHour = getGameTime():getWorldAgeHours()
    local protection = EHR.CorpseSickness.GetProtectionLevel(player)
    local fullyProtected = protection >= 1.0 or EHR.CorpseSickness.IsProtectedInVehicle(player)
    local exposure = math.max(data.currentExposure or 0, data.vanillaCorpseExposure or 0)
    local shouldClamp = isImmune or fullyProtected

    if not shouldClamp then
        local corpseInfo = EHR.CorpseSickness.ScanNearbyCorpses(player)
        shouldClamp = corpseInfo and (corpseInfo.count or 0) > 0
    end

    if not shouldClamp then return end

    data.suppressFoodSicknessUntil = currentHour + (EHR.CorpseSickness.Config.FOOD_SICKNESS_SUPPRESS_DURATION or 0.5)
    if isImmune then
        data.currentExposure = 0
        data.vanillaCorpseExposure = 0
        data.lastVanillaCorpseSignalHour = 0
        data.timeInArea = 0
        exposure = 0
    elseif fullyProtected then
        data.vanillaCorpseExposure = 0
        data.lastVanillaCorpseSignalHour = 0
        exposure = data.currentExposure or 0
    end

    EHR.CorpseSickness.ClampVanillaSickness(player, exposure)
    EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
end
function EHR.CorpseSickness.DecayVanillaSickness(player, exposure, deltaHours)
    if not player or not deltaHours or deltaHours <= 0 then return end
    if EHR.CorpseSickness.HasActiveCorpseDisease(player) then return end
    if EHR.CorpseSickness.HasOtherActiveDisease(player) then return end
    if EHR.CorpseSickness.HasActiveFoodDisease(player) then return end
    if EHR.CorpseSickness.HasRecentFoodRisk(player) then return end

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
            if EHR.CorpseSickness.ShouldSuppressFoodSickness(player) then
                stats:set(CharacterStat.FOOD_SICKNESS, 0)
            elseif current > target then
                stats:set(CharacterStat.FOOD_SICKNESS, math.max(target, current - step))
            end
        end)
    end
end

function EHR.CorpseSickness.ClearTinyVanillaSickness(player, threshold)
    if not player then return end
    if EHR.CorpseSickness.HasOtherActiveDisease(player) then return end
    if EHR.CorpseSickness.HasActiveFoodDisease(player) then return end
    if EHR.CorpseSickness.HasRecentFoodRisk(player) then return end

    local stats = player:getStats()
    if not stats or not CharacterStat then return end

    threshold = threshold or 0.06

    if CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            if current <= threshold then
                stats:set(CharacterStat.SICKNESS, 0)
            end
        end)
    end

    if CharacterStat.FOOD_SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            if current <= threshold then
                stats:set(CharacterStat.FOOD_SICKNESS, 0)
            end
        end)
    end
end
function EHR.CorpseSickness.ClampVanillaSickness(player, exposure)
    if not player then return end
    if EHR.CorpseSickness.HasActiveCorpseDisease(player) then return end
    if EHR.CorpseSickness.HasOtherActiveDisease(player) then return end
    if EHR.CorpseSickness.HasActiveFoodDisease(player) then return end
    if EHR.CorpseSickness.HasRecentFoodRisk(player) then return end

    local stats = player:getStats()
    if not stats or not CharacterStat then return end

    local target = EHR.CorpseSickness.GetVanillaSicknessTarget(exposure or 0)
    local maxAllowed = target + (EHR.CorpseSickness.Config.VANILLA_SICKNESS_CLAMP_BUFFER or 0.005)
    if target <= 0 then
        maxAllowed = 0
    end

    if CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            if current > maxAllowed then
                stats:set(CharacterStat.SICKNESS, maxAllowed)
            end
        end)
    end

    if CharacterStat.FOOD_SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            if EHR.CorpseSickness.ShouldSuppressFoodSickness(player) then
                stats:set(CharacterStat.FOOD_SICKNESS, 0)
            elseif current > maxAllowed then
                stats:set(CharacterStat.FOOD_SICKNESS, maxAllowed)
            end
        end)
    end
end

function EHR.CorpseSickness.ApplyNauseaMoodle(player, exposure)
    if not player or not exposure then return end

    if EHR.CorpseSickness.HasActiveCorpseDisease(player) then return end

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
            data.vanillaCorpseExposure = 0
            data.lastVanillaCorpseSignalHour = 0
            data.suppressFoodSicknessUntil = 0
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
    local exposure = math.max(data.currentExposure or 0, data.vanillaCorpseExposure or 0)
    if exposure >= config.EXPOSURE_THRESHOLD_HIGH then
        return "High"
    elseif exposure >= config.EXPOSURE_THRESHOLD_MEDIUM then
        return "Medium"
    elseif exposure >= config.EXPOSURE_THRESHOLD_LOW then
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
            state.quickClampTick = (state.quickClampTick or 0) + 1

            if state.quickClampTick >= (EHR.CorpseSickness.Config.QUICK_CLAMP_TICKS or 10) then
                state.quickClampTick = 0
                EHR.CorpseSickness.QuickClampVanillaSickness(player)
            end

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
