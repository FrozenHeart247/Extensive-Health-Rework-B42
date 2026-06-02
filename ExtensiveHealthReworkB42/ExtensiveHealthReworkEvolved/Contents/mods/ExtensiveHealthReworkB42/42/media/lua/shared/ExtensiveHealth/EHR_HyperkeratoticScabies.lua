--[[
    Extensive Health Rework B42
    Hyperkeratotic Scabies ground exposure detector
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.HyperkeratoticScabies = EHR.HyperkeratoticScabies or {}

EHR.HyperkeratoticScabies.Config = EHR.HyperkeratoticScabies.Config or {
    CHECK_INTERVAL_HOURS = 1.0,
    GROUND_CHANCE = 0.10,
    BLOCK_WINTER_MONTHS = true,
    BLOCK_SNOW = true,
}

local function worldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime then
        local ok, hour = pcall(function() return gameTime:getWorldAgeHours() end)
        if ok and hour then return tonumber(hour) or 0 end
    end
    return 0
end

local function isValidPlayer(player)
    if not player then return false end
    local okDead, dead = pcall(function()
        if player.isDead then return player:isDead() end
        return false
    end)
    return not (okDead and dead == true)
end

local function isSittingOnGround(player)
    if not player then return false end

    local okSit, sitting = pcall(function()
        if player.isSitOnGround then return player:isSitOnGround() end
        return false
    end)
    if okSit and sitting == true then return true end

    if PlayerSitOnGroundState and player.getCurrentState then
        local okState, isState = pcall(function()
            return player:getCurrentState() == PlayerSitOnGroundState.instance()
        end)
        if okState and isState == true then return true end
    end

    return false
end

local function roll(chance)
    chance = tonumber(chance) or 0
    if chance <= 0 then return false end
    if chance >= 1 then return true end
    if ZombRand then return (ZombRand(1000000) / 1000000) < chance end
    return math.random() < chance
end

local function getDiseaseData(player)
    if not player or not EHR.Disease or not EHR.Disease.GetDiseaseData then return nil end
    return EHR.Disease.GetDiseaseData(player)
end

local function isScabiesActive(player)
    local data = getDiseaseData(player)
    return data and data.active and type(data.active.hyperkeratotic_scabies) == "table"
end

local function stringStarts(value, prefix)
    value = tostring(value or "")
    prefix = tostring(prefix or "")
    return prefix ~= "" and value:sub(1, #prefix) == prefix
end

local function getFloorTextureName(square)
    if not square then return nil end

    local floor = nil
    pcall(function() floor = square:getFloor() end)
    if not floor then return nil end

    local textureName = nil
    pcall(function()
        if floor.getTextureName then textureName = floor:getTextureName() end
    end)
    if textureName and textureName ~= "" then return tostring(textureName) end

    local sprite = nil
    pcall(function() sprite = floor:getSprite() end)
    if sprite then
        pcall(function()
            if sprite.getName then textureName = sprite:getName() end
        end)
    end

    return textureName and tostring(textureName) or nil
end

local function getCurrentMonth()
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime or not gameTime.getMonth then return nil end

    local ok, month = pcall(function() return gameTime:getMonth() end)
    if not ok or month == nil then return nil end

    return (tonumber(month) or 0) + 1
end

local function isWinterMonth()
    local month = getCurrentMonth()
    return month == 12 or month == 1 or month == 2
end

local function hasSnowCover(square)
    local textureName = getFloorTextureName(square)
    if textureName then
        local lower = string.lower(textureName)
        if lower:find("snow", 1, true) then return true end
    end

    local climate = getClimateManager and getClimateManager() or nil
    if climate and climate.getSnowStrength then
        local ok, snow = pcall(function() return climate:getSnowStrength() end)
        if ok and (tonumber(snow) or 0) > 0.10 then return true end
    end

    return false
end

function EHR.HyperkeratoticScabies.IsSeasonBlocked(square)
    local config = EHR.HyperkeratoticScabies.Config or {}
    if config.BLOCK_WINTER_MONTHS ~= false and isWinterMonth() then return true end
    if config.BLOCK_SNOW ~= false and hasSnowCover(square) then return true end
    return false
end

function EHR.HyperkeratoticScabies.IsNaturalGround(square)
    local textureName = getFloorTextureName(square)
    if not textureName then return false end

    local lower = string.lower(textureName)
    if stringStarts(lower, "floors_exterior_natural") then return true end
    if stringStarts(lower, "blends_natural_01") then return true end
    if stringStarts(lower, "blends_natural_02") then return true end
    if lower:find("grass", 1, true) or lower:find("dirt", 1, true) or lower:find("soil", 1, true) then return true end

    return false
end

local function getPartName(partType, part)
    local name = nil
    if BodyPartType and BodyPartType.ToString then
        pcall(function() name = BodyPartType.ToString(partType) end)
    end
    if (not name or name == "") and part and part.getType and BodyPartType and BodyPartType.ToString then
        pcall(function() name = BodyPartType.ToString(part:getType()) end)
    end
    return tostring(name or partType or "")
end

local function isExcludedPart(partType, part)
    local name = string.lower(getPartName(partType, part))
    return name:find("head", 1, true) ~= nil or name:find("neck", 1, true) ~= nil
end

local function chooseBodyPart(player)
    if not player or not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return nil, nil, nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return nil, nil, nil end

    local candidates = {}
    local maxIndex = BodyPartType.ToIndex(BodyPartType.MAX)
    for i = 0, maxIndex - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part and not isExcludedPart(partType, part) then
            table.insert(candidates, { type = partType, part = part, index = i })
        end
    end

    if #candidates == 0 then return nil, nil, nil end

    local selected = candidates[1]
    if ZombRand then
        selected = candidates[ZombRand(#candidates) + 1]
    else
        selected = candidates[math.random(#candidates)]
    end

    return selected.type, selected.part, selected.index
end

local function callBool(target, methods)
    if not target then return false end
    for _, methodName in ipairs(methods) do
        local method = target[methodName]
        if type(method) == "function" then
            local ok, result = pcall(function() return method(target) end)
            if ok and result == true then return true end
        end
    end
    return false
end

local function callNumber(target, methodName, fallback)
    if not target then return fallback end
    local method = target[methodName]
    if type(method) ~= "function" then return fallback end

    local ok, result = pcall(function() return method(target) end)
    if ok and result ~= nil then
        return tonumber(result) or fallback
    end
    return fallback
end

local function callSet(target, methodName, value)
    if not target then return false end
    local method = target[methodName]
    if type(method) ~= "function" then return false end

    local ok = pcall(function() method(target, value) end)
    return ok == true
end

local function getZombieStat(player, stat)
    if not player or not stat then return 0 end
    local stats = player:getStats()
    if not stats or not stats.get then return 0 end

    local ok, value = pcall(function() return stats:get(stat) end)
    if ok then return tonumber(value) or 0 end
    return 0
end

local function setZombieStat(player, stat, value)
    if not player or not stat then return false end
    local stats = player:getStats()
    if not stats or not stats.set then return false end

    local ok = pcall(function() stats:set(stat, value) end)
    return ok == true
end

local function forEachBodyPart(bodyDamage, callback)
    if not bodyDamage or not BodyPartType or not BodyPartType.FromIndex then return false end

    local maxIndex = nil
    if BodyPartType.ToIndex and BodyPartType.MAX then
        local ok, value = pcall(function() return BodyPartType.ToIndex(BodyPartType.MAX) - 1 end)
        if ok then maxIndex = value end
    end
    if not maxIndex or maxIndex < 0 then return false end

    local changed = false
    for i = 0, maxIndex do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part and callback(part, i) then changed = true end
    end
    return changed
end

local function hasBodyPartKnoxPayload(bodyDamage)
    return forEachBodyPart(bodyDamage, function(part)
        return callBool(part, { "IsInfected", "isInfected" })
    end)
end

local function hasKnoxDiseaseEntry(player)
    local modData = player and player.getModData and player:getModData() or nil
    local diseaseData = modData and modData.EHR_Disease
    local active = diseaseData and diseaseData.active
    return type(active) == "table" and (active.Knox_Infection ~= nil or active.knox_infection ~= nil)
end

local function captureKnoxState(player)
    local bodyDamage = player and player.getBodyDamage and player:getBodyDamage() or nil
    if not bodyDamage then return { infected = false } end

    local infected = callBool(bodyDamage, { "IsInfected", "isInfected" })
    infected = infected or hasBodyPartKnoxPayload(bodyDamage)
    infected = infected or callNumber(bodyDamage, "getInfectionTime", -1) >= 0
    infected = infected or callNumber(bodyDamage, "getInfectionMortalityDuration", -1) > 0
    if CharacterStat then
        infected = infected or getZombieStat(player, CharacterStat.ZOMBIE_INFECTION) > 0
        infected = infected or getZombieStat(player, CharacterStat.ZOMBIE_FEVER) > 0
    end
    infected = infected or hasKnoxDiseaseEntry(player)

    return { infected = infected == true }
end

local function clearKnoxIfCreatedByScabies(player, snapshot)
    if not player or (snapshot and snapshot.infected == true) then return end

    local bodyDamage = player:getBodyDamage()
    if bodyDamage then
        callSet(bodyDamage, "setInfected", false)
        callSet(bodyDamage, "setInfectionTime", -1.0)
        callSet(bodyDamage, "setInfectionMortalityDuration", -1.0)
        forEachBodyPart(bodyDamage, function(part)
            local changed = false
            changed = callSet(part, "SetInfected", false) or changed
            changed = callSet(part, "SetFakeInfected", false) or changed
            return changed
        end)
    end

    if CharacterStat then
        setZombieStat(player, CharacterStat.ZOMBIE_INFECTION, 0)
        setZombieStat(player, CharacterStat.ZOMBIE_FEVER, 0)
    end

    local modData = player:getModData()
    local diseaseData = modData and modData.EHR_Disease
    local active = diseaseData and diseaseData.active
    if type(active) == "table" then
        active.Knox_Infection = nil
        active.knox_infection = nil
    end
end

local function setPartScratch(player, part, partType)
    if not part then return false end

    local knoxSnapshot = captureKnoxState(player)
    local changed = false
    local okScratch = false
    if part.setScratched then
        okScratch = pcall(function() part:setScratched(true, true) end)
    end
    if not okScratch and part.SetScratched then
        okScratch = pcall(function() part:SetScratched(true, true) end)
    end
    changed = okScratch or changed

    if part.getScratchTime and part.setScratchTime then
        pcall(function()
            local current = tonumber(part:getScratchTime()) or 0
            if current < 16 then
                part:setScratchTime(16 + (ZombRand and ZombRand(6) or 0))
                changed = true
            end
        end)
    end

    if part.getAdditionalPain and part.setAdditionalPain then
        pcall(function()
            local currentPain = tonumber(part:getAdditionalPain()) or 0
            if currentPain < 8 then
                part:setAdditionalPain(8)
                changed = true
            end
        end)
    end

    local bodyDamage = nil
    pcall(function() bodyDamage = player and player:getBodyDamage() or nil end)
    if changed and bodyDamage and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end
    clearKnoxIfCreatedByScabies(player, knoxSnapshot)

    return changed
end

function EHR.HyperkeratoticScabies.EnsureBitePart(player, disease)
    if not player or not disease then return false end
    if tonumber(disease.scabiesBitePartIndex) then return true end

    local partType, part, index = chooseBodyPart(player)
    if not partType or not part or index == nil then return false end

    disease.scabiesBitePartIndex = index
    disease.scabiesBitePartName = getPartName(partType, part)
    return true
end

function EHR.HyperkeratoticScabies.ApplyScratch(player, source, disease)
    if not isValidPlayer(player) then return false end

    local partType, part, index = chooseBodyPart(player)
    if not partType or not part then return false end

    local changed = setPartScratch(player, part, partType)
    if disease and not tonumber(disease.scabiesBitePartIndex) then
        disease.scabiesBitePartIndex = index
        disease.scabiesBitePartName = getPartName(partType, part)
    end

    if changed and EHR.DEBUG and EHR.Log then
        EHR.Log("Scabies scratch applied to " .. tostring(getPartName(partType, part)) .. " from " .. tostring(source or "unknown"))
    end

    return changed
end

function EHR.HyperkeratoticScabies.ClearAfterCure(player)
    local modData = player and player.getModData and player:getModData() or nil
    if modData and modData.EHR_HyperkeratoticScabies then
        modData.EHR_HyperkeratoticScabies.lastGroundCheckHour = nil
        modData.EHR_HyperkeratoticScabies.lastTriggerHour = nil
    end
end

function EHR.HyperkeratoticScabies.Start(player, source)
    if not isValidPlayer(player) or isScabiesActive(player) then return false end
    if not EHR.Disease or not EHR.Disease.Contract then return false end

    EHR.Disease.Contract(player, "hyperkeratotic_scabies")

    local data = getDiseaseData(player)
    local disease = data and data.active and data.active.hyperkeratotic_scabies or nil
    if not disease then return false end

    disease.source = source or "natural_ground"
    disease.stage = 1
    if not disease.incubationEnd or disease.incubationEnd <= worldHour() then
        disease.incubationEnd = worldHour() + 2
    end
    disease.peakTime = disease.peakTime or (disease.incubationEnd + 24)
    EHR.HyperkeratoticScabies.ApplyScratch(player, "initial_bite", disease)

    local modData = player:getModData()
    modData.EHR_HyperkeratoticScabies = modData.EHR_HyperkeratoticScabies or {}
    modData.EHR_HyperkeratoticScabies.lastTriggerHour = worldHour()

    if player.Say then
        EHR.Locale.Say(player, "Something bit me...")
    end

    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(player)
    end

    return true
end

function EHR.HyperkeratoticScabies.UpdatePlayer(player)
    if not isValidPlayer(player) then return end
    if isScabiesActive(player) then return end
    if not isSittingOnGround(player) then return end

    local modData = player:getModData()
    if not modData then return end
    modData.EHR_HyperkeratoticScabies = modData.EHR_HyperkeratoticScabies or {}

    local square = nil
    pcall(function() square = player:getCurrentSquare() end)
    if not EHR.HyperkeratoticScabies.IsNaturalGround(square) then return end
    if EHR.HyperkeratoticScabies.IsSeasonBlocked(square) then return end

    local now = worldHour()
    local lastCheck = tonumber(modData.EHR_HyperkeratoticScabies.lastGroundCheckHour) or -999999
    local interval = EHR.HyperkeratoticScabies.Config.CHECK_INTERVAL_HOURS or 1
    if (now - lastCheck) < interval then return end

    modData.EHR_HyperkeratoticScabies.lastGroundCheckHour = now

    if roll(EHR.HyperkeratoticScabies.Config.GROUND_CHANCE or 0.10) then
        EHR.HyperkeratoticScabies.Start(player, "natural_ground")
    end
end

function EHR.HyperkeratoticScabies.OnTick()
    local players = {}
    if isServer and isServer() and getOnlinePlayers then
        local online = getOnlinePlayers()
        if online then
            for i = 0, online:size() - 1 do
                local player = online:get(i)
                if player then table.insert(players, player) end
            end
        end
    end

    if #players == 0 and getSpecificPlayer then
        local player = getSpecificPlayer(0)
        if player then table.insert(players, player) end
    end

    for _, player in ipairs(players) do
        local ok, err = pcall(EHR.HyperkeratoticScabies.UpdatePlayer, player)
        if not ok and EHR and EHR.Log then
            EHR.Log("Scabies detector error: " .. tostring(err))
        end
    end
end

if Events and Events.OnTick and not EHR.HyperkeratoticScabies.EventsRegistered then
    Events.OnTick.Add(EHR.HyperkeratoticScabies.OnTick)
    EHR.HyperkeratoticScabies.EventsRegistered = true
end

EHR.Log("EHR_HyperkeratoticScabies.lua loaded")
