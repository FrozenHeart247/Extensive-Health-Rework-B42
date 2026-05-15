--[[
    Extensive Health Rework B42
    Concussion trauma detector

    Triggers only from real height drops or severe vehicle crashes. EHR's
    scripted collapses stay on the same Z level, so they cannot cause this.
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.Concussion = EHR.Concussion or {}
EHR.Concussion.State = EHR.Concussion.State or {}

EHR.Concussion.Config = {
    FALL_CHANCE = 0.35,
    VEHICLE_CHANCE = 0.45,
    COOLDOWN_HOURS = 0.25,
    FAILED_ROLL_COOLDOWN_HOURS = 0.02,
    FALL_DROP_FLOORS = 0.75,
    TRAUMA_PENDING_HOURS = 0.35,
    FALL_PENDING_HOURS = 0.35,
    MIN_FALL_HEALTH_LOSS = 3.0,
    MIN_HEAD_PAIN_GAIN = 5.0,
    MIN_PART_HEALTH_LOSS = 1.0,
    MIN_PART_PAIN_GAIN = 4.0,
    CRASH_SPEED_DROP_KMH = 28.0,
    CRASH_SEVERE_DROP_KMH = 55.0,
    MIN_CRASH_HEALTH_LOSS = 1.5,
    MIN_CRASH_HEAD_PAIN_GAIN = 2.5,
}

local function worldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime then
        local ok, hour = pcall(function() return gameTime:getWorldAgeHours() end)
        if ok and hour then return hour end
    end
    return 0
end

local function playerKey(player)
    if not player then return "unknown" end
    local okId, onlineId = pcall(function()
        if player.getOnlineID then return player:getOnlineID() end
        return nil
    end)
    if okId and onlineId then return "id:" .. tostring(onlineId) end

    local okUser, username = pcall(function()
        if player.getUsername then return player:getUsername() end
        return nil
    end)
    if okUser and username then return "u:" .. tostring(username) end

    local okNum, playerNum = pcall(function()
        if player.getPlayerNum then return player:getPlayerNum() end
        return nil
    end)
    if okNum and playerNum ~= nil then return "p:" .. tostring(playerNum) end

    return tostring(player)
end

local function isValidPlayer(player)
    if not player then return false end
    local okDead, dead = pcall(function()
        if player.isDead then return player:isDead() end
        return false
    end)
    return not (okDead and dead == true)
end

local function getOverallHealth(player)
    local bodyDamage = nil
    pcall(function() bodyDamage = player and player:getBodyDamage() or nil end)
    if bodyDamage and bodyDamage.getOverallBodyHealth then
        local ok, health = pcall(function() return bodyDamage:getOverallBodyHealth() end)
        if ok and health then return tonumber(health) or 100 end
    end

    if player and player.getHealth then
        local ok, health = pcall(function() return player:getHealth() end)
        if ok and health then
            health = tonumber(health) or 1
            if health <= 1.5 then return health * 100 end
            return health
        end
    end

    return 100
end

local function getBodyPartName(partType, part)
    local name = nil
    if BodyPartType and BodyPartType.ToString then
        pcall(function() name = BodyPartType.ToString(partType) end)
    end
    if (not name or name == "") and part and part.getType and BodyPartType and BodyPartType.ToString then
        pcall(function() name = BodyPartType.ToString(part:getType()) end)
    end
    return tostring(name or partType or ""):lower()
end

local function isHeadPart(partType, part)
    return getBodyPartName(partType, part):find("head", 1, true) ~= nil
end

local function getHeadPain(player)
    local bodyDamage = nil
    pcall(function() bodyDamage = player and player:getBodyDamage() or nil end)
    if not bodyDamage or not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return 0 end

    local pain = 0
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part and isHeadPart(partType, part) and part.getAdditionalPain then
            local ok, partPain = pcall(function() return part:getAdditionalPain() end)
            if ok and partPain then
                pain = math.max(pain, tonumber(partPain) or 0)
            end
        end
    end

    return pain
end

local function clearHeadPain(player)
    local bodyDamage = nil
    pcall(function() bodyDamage = player and player:getBodyDamage() or nil end)
    if not bodyDamage or not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return end

    local changed = false
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part and isHeadPart(partType, part) and part.getAdditionalPain and part.setAdditionalPain then
            pcall(function()
                local current = tonumber(part:getAdditionalPain()) or 0
                if current <= 55 then
                    part:setAdditionalPain(0)
                else
                    part:setAdditionalPain(math.max(0, current - 25))
                end
                changed = true
            end)
        end
    end

    if changed and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end
end

function EHR.Concussion.ClearHeadPain(player)
    clearHeadPain(player)
end

function EHR.Concussion.ClearAfterCure(player)
    clearHeadPain(player)

    local modData = player and player.getModData and player:getModData() or nil
    if modData and modData.EHR_Concussion then
        modData.EHR_Concussion.cooldownUntil = nil
        modData.EHR_Concussion.lastSource = nil
    end

    EHR.Concussion.State[playerKey(player)] = nil
end

local function safePartBool(part, methodName)
    if not part or not methodName or not part[methodName] then return false end
    local ok, value = pcall(function() return part[methodName](part) end)
    return ok and value == true
end

local function safePartNumber(part, methodName, fallback)
    if not part or not methodName or not part[methodName] then return fallback or 0 end
    local ok, value = pcall(function() return part[methodName](part) end)
    if ok and value ~= nil then return tonumber(value) or (fallback or 0) end
    return fallback or 0
end

local function getBodySnapshot(player)
    local bodyDamage = nil
    pcall(function() bodyDamage = player and player:getBodyDamage() or nil end)

    local snapshot = {
        overallHealth = getOverallHealth(player),
        headPain = getHeadPain(player),
        woundScore = 0,
        severeWoundScore = 0,
        parts = {},
    }

    if not bodyDamage or not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then
        return snapshot
    end

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part then
            local name = getBodyPartName(partType, part)
            local health = safePartNumber(part, "getHealth", 100)
            local pain = safePartNumber(part, "getAdditionalPain", 0)
            local woundScore = 0
            local severeScore = 0

            if safePartBool(part, "bleeding") then woundScore = woundScore + 2 end
            if safePartBool(part, "scratched") then woundScore = woundScore + 1 end
            if safePartBool(part, "isCut") then woundScore = woundScore + 2 end
            if safePartBool(part, "bitten") then
                woundScore = woundScore + 4
                severeScore = severeScore + 1
            end
            if safePartBool(part, "deepWounded") then
                woundScore = woundScore + 4
                severeScore = severeScore + 1
            end
            if safePartBool(part, "haveGlass") then
                woundScore = woundScore + 3
                severeScore = severeScore + 1
            end
            if safePartBool(part, "haveBullet") then
                woundScore = woundScore + 4
                severeScore = severeScore + 1
            end
            if safePartNumber(part, "getFractureTime", 0) > 0 then
                woundScore = woundScore + 4
                severeScore = severeScore + 1
            end
            if safePartNumber(part, "getBurnTime", 0) > 0 then
                woundScore = woundScore + 2
            end

            snapshot.woundScore = snapshot.woundScore + woundScore
            snapshot.severeWoundScore = snapshot.severeWoundScore + severeScore
            snapshot.parts[name] = {
                health = health,
                pain = pain,
                woundScore = woundScore,
                severeWoundScore = severeScore,
            }
        end
    end

    return snapshot
end

local function getTraumaDelta(before, after)
    before = before or {}
    after = after or {}

    local delta = {
        overallHealthLoss = math.max(0, (tonumber(before.overallHealth) or tonumber(after.overallHealth) or 100) - (tonumber(after.overallHealth) or 100)),
        headPainGain = math.max(0, (tonumber(after.headPain) or 0) - (tonumber(before.headPain) or tonumber(after.headPain) or 0)),
        partHealthLoss = 0,
        maxPartPainGain = 0,
        woundIncrease = math.max(0, (tonumber(after.woundScore) or 0) - (tonumber(before.woundScore) or 0)),
        severeWoundIncrease = math.max(0, (tonumber(after.severeWoundScore) or 0) - (tonumber(before.severeWoundScore) or 0)),
    }

    local beforeParts = before.parts or {}
    for partName, current in pairs(after.parts or {}) do
        local previous = beforeParts[partName] or current
        delta.partHealthLoss = delta.partHealthLoss + math.max(0, (tonumber(previous.health) or tonumber(current.health) or 100) - (tonumber(current.health) or 100))
        delta.maxPartPainGain = math.max(delta.maxPartPainGain, math.max(0, (tonumber(current.pain) or 0) - (tonumber(previous.pain) or 0)))
    end

    return delta
end

local function isTraumaticInjury(delta, cfg, source)
    if not delta then return false end

    local minHealthLoss = source == "vehicle crash" and (cfg.MIN_CRASH_HEALTH_LOSS or 1.5) or (cfg.MIN_FALL_HEALTH_LOSS or 3)
    local minHeadPainGain = source == "vehicle crash" and (cfg.MIN_CRASH_HEAD_PAIN_GAIN or 2.5) or (cfg.MIN_HEAD_PAIN_GAIN or 5)

    return delta.woundIncrease > 0
        or delta.severeWoundIncrease > 0
        or delta.partHealthLoss >= (cfg.MIN_PART_HEALTH_LOSS or 1.0)
        or delta.maxPartPainGain >= (cfg.MIN_PART_PAIN_GAIN or 4.0)
        or delta.overallHealthLoss >= minHealthLoss
        or delta.headPainGain >= minHeadPainGain
end

local function debugTraumaLog(kind, pending, delta)
    if not EHR.DEBUG then return end
    EHR.Log(string.format(
        "Concussion %s injury detected: healthLoss %.2f, partHealthLoss %.2f, headPainGain %.2f, partPainGain %.2f, wound +%.0f, severe +%.0f",
        tostring(kind),
        tonumber(delta.overallHealthLoss) or 0,
        tonumber(delta.partHealthLoss) or 0,
        tonumber(delta.headPainGain) or 0,
        tonumber(delta.maxPartPainGain) or 0,
        tonumber(delta.woundIncrease) or 0,
        tonumber(delta.severeWoundIncrease) or 0
    ))
end

local function getVehicle(player)
    local vehicle = nil
    pcall(function()
        if player and player.getVehicle then vehicle = player:getVehicle() end
    end)
    return vehicle
end

local function getVehicleSpeedKmh(vehicle)
    if not vehicle then return 0 end
    local okSpeed, speed = pcall(function()
        if vehicle.getCurrentSpeedKmHour then return vehicle:getCurrentSpeedKmHour() end
        return nil
    end)
    if okSpeed and speed then return math.abs(tonumber(speed) or 0) end

    local ok2d, speed2d = pcall(function()
        if vehicle.getSpeed2D then return vehicle:getSpeed2D() end
        return nil
    end)
    if ok2d and speed2d then return math.abs((tonumber(speed2d) or 0) * 120) end

    return 0
end

local function ensureDiseaseData(player)
    if EHR.Disease and EHR.Disease.InitializePlayer then
        pcall(function() EHR.Disease.InitializePlayer(player) end)
    end

    local modData = player and player:getModData() or nil
    if not modData then return nil end
    modData.EHR_Disease = modData.EHR_Disease or {
        active = {},
        immunity = { general = 1.0 },
        history = { recoveries = {} },
    }
    modData.EHR_Disease.active = modData.EHR_Disease.active or {}
    modData.EHR_Disease.immunity = modData.EHR_Disease.immunity or { general = 1.0 }
    modData.EHR_Disease.history = modData.EHR_Disease.history or { recoveries = {} }
    modData.EHR_Disease_Initialized = true
    modData.EHR_Initialized = true
    return modData.EHR_Disease
end

function EHR.Concussion.IsActive(player)
    local data = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
    return data and data.active and data.active.concussion ~= nil
end

local function roll(chance)
    chance = tonumber(chance) or 0
    if chance <= 0 then return false end
    if chance >= 1 then return true end
    if ZombRand then return (ZombRand(1000000) / 1000000) < chance end
    return math.random() < chance
end

function EHR.Concussion.Start(player, source, force)
    if not isValidPlayer(player) then return false end
    if EHR.Disease and EHR.Disease.IsDiseaseEnabled and not EHR.Disease.IsDiseaseEnabled("concussion") then
        return false
    end
    if EHR.Concussion.IsActive(player) then return false end

    local now = worldHour()
    local modData = player:getModData()
    modData.EHR_Concussion = modData.EHR_Concussion or {}
    if not force and (modData.EHR_Concussion.cooldownUntil or 0) > now then
        return false
    end

    local data = ensureDiseaseData(player)
    if not data or not data.active then return false end

    local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases.concussion or nil
    local duration = (def and def.durationMin) or 48
    if def and def.durationMax and def.durationMax > duration and ZombRand then
        duration = duration + ZombRand(def.durationMax - duration + 1)
    end

    data.active.concussion = {
        startTime = now,
        incubationEnd = now,
        peakTime = now,
        endTime = now + duration,
        stage = 3,
        stageCount = 3,
        severity = math.max(0.45, math.min(1.0, (def and def.baseSeverity or 0.65) + ((ZombRand and ZombRand(21) or 10) / 100 - 0.10))),
        diagnosed = true,
        progress = 0,
        source = source or "trauma",
        reverseProgression = true,
        noCure = true,
    }

    modData.EHR_Concussion.cooldownUntil = now + (EHR.Concussion.Config.COOLDOWN_HOURS or 24)
    modData.EHR_Concussion.lastSource = source or "trauma"

    if player.Say then
        player:Say("My head... something is wrong.")
    end

    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end

    EHR.Log("Concussion triggered by " .. tostring(source or "trauma"))
    return true
end

function EHR.Concussion.TryStart(player, source, chance)
    if not isValidPlayer(player) then return false end
    if EHR.Disease and EHR.Disease.IsDiseaseEnabled and not EHR.Disease.IsDiseaseEnabled("concussion") then
        return false
    end
    if EHR.Concussion.IsActive(player) then return false end

    local now = worldHour()
    local modData = player:getModData()
    modData.EHR_Concussion = modData.EHR_Concussion or {}
    if (modData.EHR_Concussion.cooldownUntil or 0) > now then return false end

    if roll(chance) then
        return EHR.Concussion.Start(player, source, true)
    end

    modData.EHR_Concussion.cooldownUntil = now + (EHR.Concussion.Config.FAILED_ROLL_COOLDOWN_HOURS or 1)
    return false
end

local function normalizeOldCooldown(player, now, cfg)
    local modData = player and player.getModData and player:getModData() or nil
    local concussionData = modData and modData.EHR_Concussion or nil
    if not concussionData then return end

    local cooldownUntil = tonumber(concussionData.cooldownUntil)
    local maxCooldown = tonumber(cfg.COOLDOWN_HOURS) or 0.25
    if cooldownUntil and cooldownUntil > now + maxCooldown then
        concussionData.cooldownUntil = now + maxCooldown
    end
end

local function setPendingTrauma(state, key, now, source, beforeSnapshot, extra)
    local pending = state[key]
    if pending and (now - (tonumber(pending.time) or now)) <= 0.02 then
        return
    end

    state[key] = {
        time = now,
        source = source,
        before = beforeSnapshot,
        extra = extra or {},
    }
end

local function resolvePendingTrauma(player, state, key, now, cfg, currentSnapshot, chance)
    local pending = state[key]
    if not pending then return end

    local delta = getTraumaDelta(pending.before, currentSnapshot)
    if isTraumaticInjury(delta, cfg, pending.source) then
        debugTraumaLog(pending.source or key, pending, delta)
        EHR.Concussion.TryStart(player, pending.source or "trauma", chance)
        state[key] = nil
        return
    end

    if now - (tonumber(pending.time) or now) > (cfg.TRAUMA_PENDING_HOURS or cfg.FALL_PENDING_HOURS or 0.35) then
        state[key] = nil
    end
end

local function getPlayerZ(player)
    local z = 0
    pcall(function()
        if player and player.getZ then z = player:getZ() end
    end)
    return tonumber(z) or 0
end

function EHR.Concussion.UpdateTracking(player)
    if not isValidPlayer(player) then return end

    local cfg = EHR.Concussion.Config
    local key = playerKey(player)
    local state = EHR.Concussion.State[key] or {}
    EHR.Concussion.State[key] = state

    local now = worldHour()
    if (state.nextCheckHour or 0) > now then return end
    state.nextCheckHour = now + 0.00035 -- about 1.25 in-game seconds
    normalizeOldCooldown(player, now, cfg)

    local z = getPlayerZ(player)
    local snapshot = getBodySnapshot(player)
    local health = snapshot.overallHealth
    local headPain = snapshot.headPain
    local vehicle = getVehicle(player)
    local lastSnapshot = state.lastSnapshot or snapshot

    resolvePendingTrauma(player, state, "pendingFall", now, cfg, snapshot, cfg.FALL_CHANCE or 0.35)
    resolvePendingTrauma(player, state, "pendingCrash", now, cfg, snapshot, cfg.VEHICLE_CHANCE or 0.45)

    if not vehicle then
        state.highestZ = math.max(tonumber(state.highestZ) or z, tonumber(state.lastZ) or z, z)
        local drop = math.max((tonumber(state.highestZ) or z) - z, (tonumber(state.lastZ) or z) - z)
        if drop >= (cfg.FALL_DROP_FLOORS or 0.75) then
            setPendingTrauma(state, "pendingFall", now, "fall", lastSnapshot, {
                fromZ = state.highestZ,
                toZ = z,
            })
            state.highestZ = z
        elseif z > (tonumber(state.highestZ) or z) then
            state.highestZ = z
        end
    else
        state.pendingFall = nil
        state.highestZ = z
    end

    if vehicle then
        local speed = getVehicleSpeedKmh(vehicle)
        local previousSpeed = tonumber(state.lastVehicleSpeed) or speed
        local speedDrop = previousSpeed - speed

        if speedDrop >= (cfg.CRASH_SPEED_DROP_KMH or 28) then
            if EHR.DEBUG then
                EHR.Log(string.format(
                    "Concussion vehicle impact window opened: speedDrop %.1f km/h",
                    speedDrop
                ))
            end
            setPendingTrauma(state, "pendingCrash", now, "vehicle crash", lastSnapshot, {
                speedDrop = speedDrop,
            })
        end

        state.lastVehicleSpeed = speed
        state.lastVehicleSnapshot = snapshot
    else
        local previousSpeed = tonumber(state.lastVehicleSpeed) or 0
        if previousSpeed >= (cfg.CRASH_SPEED_DROP_KMH or 28) then
            setPendingTrauma(state, "pendingCrash", now, "vehicle crash", state.lastVehicleSnapshot or lastSnapshot, {
                speedDrop = previousSpeed,
                leftVehicle = true,
            })
        end
        state.lastVehicleSpeed = nil
        state.lastVehicleSnapshot = nil
    end

    state.lastZ = z
    state.lastHealth = health
    state.lastHeadPain = headPain
    state.lastSnapshot = snapshot
end

function EHR.Concussion.OnPlayerUpdate(player)
    local ok, err = pcall(EHR.Concussion.UpdateTracking, player)
    if not ok and EHR and EHR.Log then
        EHR.Log("Concussion tracking error: " .. tostring(err))
    end
end

function EHR.Concussion.OnPlayerDeath(player)
    EHR.Concussion.State[playerKey(player)] = nil
end

function EHR.Concussion.OnTick()
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
        EHR.Concussion.OnPlayerUpdate(player)
    end
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(EHR.Concussion.OnPlayerUpdate)
end

if Events and Events.OnTick then
    Events.OnTick.Add(EHR.Concussion.OnTick)
end

if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(EHR.Concussion.OnPlayerDeath)
end

EHR.Log("EHR_Concussion.lua loaded")
