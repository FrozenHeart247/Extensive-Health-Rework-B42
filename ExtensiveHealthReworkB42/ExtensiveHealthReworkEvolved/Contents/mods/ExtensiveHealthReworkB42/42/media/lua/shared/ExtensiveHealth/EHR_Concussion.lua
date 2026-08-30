--[[
    Extensive Health Rework B42
    Concussion trauma detector

    Triggers only from real height drops or severe vehicle crashes. EHR's
    scripted collapses stay on the same Z level, so they cannot cause this.
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.Concussion = EHR.Concussion or {}

local function isPureClient()
    return isClient and isClient() and not (isServer and isServer())
end
EHR.Concussion.State = EHR.Concussion.State or {}

EHR.Concussion.Config = {
    FALL_CHANCE = 0.65,
    VEHICLE_CHANCE = 0.45,
    COOLDOWN_HOURS = 0.25,
    FAILED_ROLL_COOLDOWN_HOURS = 0.02,
    debugConcussion = true,
    debugConcussionThrottleHours = 0.02,
    FALL_DROP_FLOORS = 2.0,
    TRAUMA_PENDING_HOURS = 0.06,
    FALL_PENDING_HOURS = 0.02,
    CRASH_PENDING_HOURS = 0.06,
    FALL_MAX_HORIZONTAL_TILES = 0.85,
    STAIR_SCAN_RADIUS = 2,
    MIN_FALL_HEALTH_LOSS = 3.0,
    MIN_HEAD_PAIN_GAIN = 5.0,
    MIN_HEAD_HEALTH_LOSS = 1.0,
    MIN_PART_HEALTH_LOSS = 1.0,
    MIN_MAJOR_PART_HEALTH_LOSS = 6.0,
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

local function requestServerConcussionCandidate(player, source)
    if not sendClientCommand then return false end

    local allowedSources = {
        ["fall"] = true,
        ["vehicle crash"] = true,
    }
    source = tostring(source or "")
    if not allowedSources[source] then return false end

    -- This is only a network flood guard. The server still owns the actual
    -- disease/cooldown checks and performs its own concussion roll.
    local key = playerKey(player)
    local state = EHR.Concussion.State[key] or {}
    EHR.Concussion.State[key] = state

    local nowMs = nil
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok then nowMs = tonumber(value) end
    end
    local lastMs = tonumber(state.lastCandidateRequestMs)
    if nowMs and lastMs and nowMs >= lastMs and (nowMs - lastMs) < 750 then
        return false
    end
    if nowMs then state.lastCandidateRequestMs = nowMs end

    sendClientCommand(player, "EHR", "ConcussionCandidate", { source = source })
    return true
end

local function playerName(player)
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

local function concussionDebugEnabled()
    return EHR.Concussion
        and EHR.Concussion.Config
        and EHR.Concussion.Config.debugConcussion == false
end

local function getSandboxNumber(name, default, minValue, maxValue)
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework or nil
    local value = options and options[name] or nil
    value = tonumber(value)
    if value == nil then value = tonumber(default) or 0 end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function getFallChance(cfg)
    local baseChance = tonumber(cfg and cfg.FALL_CHANCE) or 0.65
    return math.max(0, math.min(1, baseChance * getSandboxNumber("ConcussionFallChanceMultiplier", 1.0, 0.0, 5.0)))
end

local function getVehicleChance(cfg)
    local baseChance = tonumber(cfg and cfg.VEHICLE_CHANCE) or 0.45
    return math.max(0, math.min(1, baseChance * getSandboxNumber("ConcussionVehicleChanceMultiplier", 1.0, 0.0, 5.0)))
end

function EHR.Concussion.GetChanceForSource(source)
    if source == "fall" then
        return getFallChance(EHR.Concussion.Config)
    end
    if source == "vehicle crash" then
        return getVehicleChance(EHR.Concussion.Config)
    end
    return nil
end

local function debugConcussion(player, state, reason, detail, force)
    if not concussionDebugEnabled() then return end

    local now = worldHour()
    if state and not force then
        local throttle = tonumber(EHR.Concussion.Config.debugConcussionThrottleHours) or 0.02
        local lastReason = tostring(state.EHR_ConcussionDebugLastReason or "")
        local lastHour = tonumber(state.EHR_ConcussionDebugLastHour) or -999999
        if lastReason == tostring(reason or "") and (now - lastHour) < throttle then return end
        state.EHR_ConcussionDebugLastReason = tostring(reason or "")
        state.EHR_ConcussionDebugLastHour = now
    end

    print("[EHR][Concussion][" .. playerName(player) .. "] "
        .. tostring(reason or "state") .. ": " .. tostring(detail or ""))
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
        headHealthLoss = 0,
        partHealthLoss = 0,
        maxPartPainGain = 0,
        woundIncrease = math.max(0, (tonumber(after.woundScore) or 0) - (tonumber(before.woundScore) or 0)),
        severeWoundIncrease = math.max(0, (tonumber(after.severeWoundScore) or 0) - (tonumber(before.severeWoundScore) or 0)),
    }

    local beforeParts = before.parts or {}
    for partName, current in pairs(after.parts or {}) do
        local previous = beforeParts[partName] or current
        local partHealthLoss = math.max(0, (tonumber(previous.health) or tonumber(current.health) or 100) - (tonumber(current.health) or 100))
        delta.partHealthLoss = delta.partHealthLoss + partHealthLoss
        if tostring(partName or ""):find("head", 1, true) then
            delta.headHealthLoss = math.max(delta.headHealthLoss, partHealthLoss)
        end
        delta.maxPartPainGain = math.max(delta.maxPartPainGain, math.max(0, (tonumber(current.pain) or 0) - (tonumber(previous.pain) or 0)))
    end

    return delta
end

local function isTraumaticInjury(delta, cfg, source)
    if not delta then return false end

    local minHeadPainGain = source == "vehicle crash" and (cfg.MIN_CRASH_HEAD_PAIN_GAIN or 2.5) or (cfg.MIN_HEAD_PAIN_GAIN or 5)
    local hasHeadImpact = delta.headPainGain >= minHeadPainGain
        or delta.headHealthLoss >= (cfg.MIN_HEAD_HEALTH_LOSS or 1.0)
    local hasMajorTrauma = delta.severeWoundIncrease > 0
        or delta.partHealthLoss >= (cfg.MIN_MAJOR_PART_HEALTH_LOSS or 6.0)

    if source == "fall" then
        -- Overencumbrance and other non-impact drains can lower body/part health
        -- during the short fall window. A fall concussion requires a head hit or
        -- a fresh wound/severe injury, not generic HP loss.
        return hasHeadImpact
            or delta.severeWoundIncrease > 0
            or (delta.woundIncrease > 0 and delta.partHealthLoss >= (cfg.MIN_PART_HEALTH_LOSS or 1.0))
    end

    if source ~= "vehicle crash" then
        -- Overencumbrance, pain drift, and controlled Z transitions can change
        -- health/pain without a head impact. Non-vehicle trauma needs a head hit
        -- or a major fresh injury, not generic body damage.
        return hasHeadImpact or hasMajorTrauma
    end

    -- Vehicle speed can fluctuate in MP or during vehicle transitions. Require
    -- an actual fresh wound/head hit/major body-part loss instead of overall HP
    -- drain alone.
    return hasHeadImpact
        or hasMajorTrauma
        or (delta.woundIncrease > 0 and delta.partHealthLoss >= (cfg.MIN_PART_HEALTH_LOSS or 1.0))
end

local function debugTraumaLog(kind, pending, delta)
    if not EHR.DEBUG and not concussionDebugEnabled() then return end
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
    if chance <= 0 then return false, 1 end
    if chance >= 1 then return true, 0 end
    local value = ZombRand and (ZombRand(1000000) / 1000000) or math.random()
    return value < chance, value
end

function EHR.Concussion.Start(player, source, force)
    -- Disease progression is server-authoritative in MP. A pure client used to
    -- create a local concussion after its own trauma roll, but SafeTransmitModData
    -- intentionally does not upload client ModData and the client disease tick is
    -- disabled. That left a visible concussion which could never progress.
    if isPureClient() then
        debugConcussion(player, nil, "start-blocked", "server-authoritative MP state", true)
        return false
    end

    if not isValidPlayer(player) then
        debugConcussion(player, nil, "start-blocked", "invalid/dead player", true)
        return false
    end
    if EHR.Disease and EHR.Disease.IsDiseaseEnabled and not EHR.Disease.IsDiseaseEnabled("concussion") then
        debugConcussion(player, nil, "start-blocked", "disabled by sandbox", true)
        return false
    end
    if EHR.Concussion.IsActive(player) then
        debugConcussion(player, nil, "start-blocked", "already active", true)
        return false
    end

    local now = worldHour()
    local modData = player:getModData()
    modData.EHR_Concussion = modData.EHR_Concussion or {}
    if not force and (modData.EHR_Concussion.cooldownUntil or 0) > now then
        debugConcussion(player, modData.EHR_Concussion, "start-blocked", string.format(
            "cooldown %.2fh left source=%s force=%s",
            (tonumber(modData.EHR_Concussion.cooldownUntil) or now) - now,
            tostring(source or "trauma"),
            tostring(force == true)
        ), true)
        return false
    end

    local data = ensureDiseaseData(player)
    if not data or not data.active then
        debugConcussion(player, modData.EHR_Concussion, "start-blocked", "disease data unavailable", true)
        return false
    end

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
        EHR.Locale.Say(player, "My head... something is wrong.")
    end

    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(player)
    end

    EHR.Log("Concussion triggered by " .. tostring(source or "trauma"))
    debugConcussion(player, modData.EHR_Concussion, "contracted", string.format(
        "source=%s duration=%.1fh severity=%.2f cooldown=%.2fh",
        tostring(source or "trauma"),
        duration,
        data.active.concussion.severity or 0,
        EHR.Concussion.Config.COOLDOWN_HOURS or 0
    ), true)
    return true
end

function EHR.Concussion.TryStart(player, source, chance)
    if not isValidPlayer(player) then
        debugConcussion(player, nil, "try-blocked", "invalid/dead player", true)
        return false
    end
    if EHR.Disease and EHR.Disease.IsDiseaseEnabled and not EHR.Disease.IsDiseaseEnabled("concussion") then
        debugConcussion(player, nil, "try-blocked", "disabled by sandbox", true)
        return false
    end
    if EHR.Concussion.IsActive(player) then
        debugConcussion(player, nil, "try-blocked", "already active", true)
        return false
    end

    local now = worldHour()
    local modData = player:getModData()
    modData.EHR_Concussion = modData.EHR_Concussion or {}
    if (modData.EHR_Concussion.cooldownUntil or 0) > now then
        debugConcussion(player, modData.EHR_Concussion, "try-blocked", string.format(
            "cooldown %.2fh left source=%s chance=%.2f%%",
            (tonumber(modData.EHR_Concussion.cooldownUntil) or now) - now,
            tostring(source or "trauma"),
            (tonumber(chance) or 0) * 100
        ), true)
        return false
    end

    if isPureClient() then
        -- The client has the most reliable short-lived fall/crash evidence, but
        -- it may only nominate itself. The server validates the source, chooses
        -- the chance and performs all state mutations.
        return requestServerConcussionCandidate(player, source)
    end

    local success, rollValue = roll(chance)
    debugConcussion(player, modData.EHR_Concussion, "roll", string.format(
        "source=%s chance=%.2f%% roll=%.2f%% result=%s",
        tostring(source or "trauma"),
        (tonumber(chance) or 0) * 100,
        (tonumber(rollValue) or 0) * 100,
        success and "CONTRACTED" or "no proc"
    ), true)

    if success then
        return EHR.Concussion.Start(player, source, true)
    end

    modData.EHR_Concussion.cooldownUntil = now + (EHR.Concussion.Config.FAILED_ROLL_COOLDOWN_HOURS or 1)
    debugConcussion(player, modData.EHR_Concussion, "failed-roll-cooldown", string.format(
        "source=%s cooldown=%.2fh",
        tostring(source or "trauma"),
        EHR.Concussion.Config.FAILED_ROLL_COOLDOWN_HOURS or 0
    ), true)
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
        debugConcussion(player, state, "pending-trauma-valid", string.format(
            "key=%s source=%s healthLoss=%.2f partHealthLoss=%.2f headPainGain=%.2f wound+%.0f severe+%.0f chance=%.2f%%",
            tostring(key),
            tostring(pending.source or "trauma"),
            tonumber(delta.overallHealthLoss) or 0,
            tonumber(delta.partHealthLoss) or 0,
            tonumber(delta.headPainGain) or 0,
            tonumber(delta.woundIncrease) or 0,
            tonumber(delta.severeWoundIncrease) or 0,
            (tonumber(chance) or 0) * 100
        ), true)
        EHR.Concussion.TryStart(player, pending.source or "trauma", chance)
        state[key] = nil
        return
    end

    local pendingWindow = cfg.TRAUMA_PENDING_HOURS or 0.06
    if pending.source == "fall" then
        pendingWindow = cfg.FALL_PENDING_HOURS or pendingWindow
    elseif pending.source == "vehicle crash" then
        pendingWindow = cfg.CRASH_PENDING_HOURS or pendingWindow
    end

    if now - (tonumber(pending.time) or now) > pendingWindow then
        debugConcussion(player, state, "pending-trauma-expired", string.format(
            "key=%s source=%s window=%.2fh healthLoss=%.2f headPainGain=%.2f severe+%.0f",
            tostring(key),
            tostring(pending.source or "trauma"),
            pendingWindow,
            tonumber(delta.overallHealthLoss) or 0,
            tonumber(delta.headPainGain) or 0,
            tonumber(delta.severeWoundIncrease) or 0
        ), true)
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

local function getFallTrackingZ(z)
    z = tonumber(z) or 0
    if z < 0 then return 0 end
    return z
end

local function isBasementZTransition(currentZ, lastZ)
    currentZ = tonumber(currentZ) or 0
    lastZ = tonumber(lastZ)
    return currentZ < 0 or (lastZ ~= nil and lastZ < 0)
end

local function getPlayerXY(player)
    local x, y = 0, 0
    pcall(function()
        if player and player.getX then x = player:getX() end
        if player and player.getY then y = player:getY() end
    end)
    return tonumber(x) or 0, tonumber(y) or 0
end

local function getPlayerSquare(player)
    local square = nil
    pcall(function()
        if player and player.getSquare then
            square = player:getSquare()
        elseif player and player.getCurrentSquare then
            square = player:getCurrentSquare()
        end
    end)
    return square
end

local function getGridSquareAt(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then return nil end

    local square = nil
    pcall(function()
        square = cell:getGridSquare(
            math.floor(tonumber(x) or 0),
            math.floor(tonumber(y) or 0),
            math.floor(tonumber(z) or 0)
        )
    end)
    return square
end

local function squareHasStairs(square)
    if not square then return false end

    local methods = {
        "HasStairs",
        "HasStairsBelow",
        "HasStairsNorth",
        "HasStairsWest",
    }
    for _, methodName in ipairs(methods) do
        local method = square[methodName]
        if method then
            local ok, value = pcall(function() return method(square) end)
            if ok and value == true then return true end
        end
    end

    local modData = nil
    pcall(function()
        if square.getModData then modData = square:getModData() end
    end)
    if modData and (modData.ConnectedToStairstrue or modData.ConnectedToStairsfalse) then
        return true
    end

    if IsoObjectType and square.has then
        local stairTypes = {
            "stairsBN",
            "stairsBW",
            "stairsMN",
            "stairsMW",
            "stairsTN",
            "stairsTW",
        }
        for _, stairTypeName in ipairs(stairTypes) do
            local stairType = IsoObjectType[stairTypeName]
            if stairType then
                local ok, value = pcall(function() return square:has(stairType) end)
                if ok and value == true then return true end
            end
        end
    end

    local objects = nil
    pcall(function()
        if square.getObjects then objects = square:getObjects() end
    end)
    if objects then
        local objectCount = 0
        pcall(function()
            if objects.size then objectCount = objects:size() end
        end)
        for i = 0, objectCount - 1 do
            local object = nil
            pcall(function() object = objects:get(i) end)
            if object then
                local okStairs, isStairs = pcall(function()
                    if object.isStairsObject then return object:isStairsObject() end
                    return false
                end)
                if okStairs and isStairs == true then return true end

                local okType, objectType = pcall(function()
                    if object.getType then return object:getType() end
                    return nil
                end)
                if okType and objectType and IsoObjectType then
                    if objectType == IsoObjectType.stairsBN or objectType == IsoObjectType.stairsBW
                        or objectType == IsoObjectType.stairsMN or objectType == IsoObjectType.stairsMW
                        or objectType == IsoObjectType.stairsTN or objectType == IsoObjectType.stairsTW then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function isNearStairsAt(x, y, z, radius)
    radius = tonumber(radius) or 2
    local baseX = math.floor(tonumber(x) or 0)
    local baseY = math.floor(tonumber(y) or 0)
    local baseZ = math.floor(tonumber(z) or 0)

    for dz = -1, 1 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if squareHasStairs(getGridSquareAt(baseX + dx, baseY + dy, baseZ + dz)) then
                    return true
                end
            end
        end
    end

    return false
end

local function isStairTransition(player, state, x, y, z, cfg)
    local radius = cfg.STAIR_SCAN_RADIUS or 2
    local currentSquare = getPlayerSquare(player) or getGridSquareAt(x, y, z)
    if squareHasStairs(currentSquare) or squareHasStairs(state.lastSquare) then
        return true
    end

    if radius > 0 then
        if isNearStairsAt(x, y, z, radius) then return true end
        if state.lastX and state.lastY and state.lastZ and isNearStairsAt(state.lastX, state.lastY, state.lastZ, radius) then
            return true
        end
        if state.highestZ and isNearStairsAt(x, y, state.highestZ, radius) then
            return true
        end
    end

    return false
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
    local fallZ = getFallTrackingZ(z)
    local x, y = getPlayerXY(player)
    local snapshot = getBodySnapshot(player)
    local health = snapshot.overallHealth
    local headPain = snapshot.headPain
    local vehicle = getVehicle(player)
    local lastSnapshot = state.lastSnapshot or snapshot

    local vehicleChance = getVehicleChance(cfg)
    local fallChance = getFallChance(cfg)
    resolvePendingTrauma(player, state, "pendingCrash", now, cfg, snapshot, vehicleChance)
    resolvePendingTrauma(player, state, "pendingFall", now, cfg, snapshot, fallChance)

    if not vehicle then
        local lastFallZ = tonumber(state.lastFallZ)
        if lastFallZ == nil then
            lastFallZ = getFallTrackingZ(state.lastZ)
        end

        state.highestZ = math.max(tonumber(state.highestZ) or fallZ, lastFallZ or fallZ, fallZ)
        local drop = math.max((tonumber(state.highestZ) or fallZ) - fallZ, (lastFallZ or fallZ) - fallZ)
        local basementTransition = isBasementZTransition(z, state.lastZ)

        if basementTransition then
            if drop >= (cfg.FALL_DROP_FLOORS or 1.0) then
                local detail = string.format(
                    "rawZ %.2f -> %.2f, fallZ %.2f, trackedDrop %.2f, highestZ %.2f",
                    tonumber(state.lastZ) or z,
                    z,
                    fallZ,
                    drop,
                    tonumber(state.highestZ) or fallZ
                )
                debugConcussion(player, state, "ignored-basement-z", detail, true)
                if EHR.DEBUG then
                    EHR.Log("Concussion ignored basement Z transition: " .. detail)
                end
            end
            state.highestZ = fallZ
        elseif drop >= (cfg.FALL_DROP_FLOORS or 1.0) then
            local stairTransition = isStairTransition(player, state, x, y, z, cfg)
            debugConcussion(player, state, stairTransition and "fall-candidate-near-stairs" or "fall-candidate", string.format(
                "rawZ %.2f lastZ %.2f fallZ %.2f drop %.2f x=%.2f y=%.2f stairs=%s chance=%.2f%% pending=requires trauma",
                z,
                tonumber(state.lastZ) or z,
                fallZ,
                drop,
                x,
                y,
                tostring(stairTransition),
                fallChance * 100
            ), true)
            if EHR.DEBUG then
                EHR.Log(string.format(
                    "Concussion fall trauma window: drop %.2f, stairs=%s, chance %.0f%%",
                    drop,
                    tostring(stairTransition),
                    fallChance * 100
                ))
            end
            setPendingTrauma(state, "pendingFall", now, "fall", lastSnapshot, {
                drop = drop,
                nearStairs = stairTransition == true,
                x = x,
                y = y,
                z = z,
            })
            state.highestZ = fallZ
        elseif fallZ > (tonumber(state.highestZ) or fallZ) then
            debugConcussion(player, state, "highest-z-updated", string.format(
                "highestZ %.2f -> %.2f rawZ=%.2f",
                tonumber(state.highestZ) or fallZ,
                fallZ,
                z
            ))
            state.highestZ = fallZ
        end
    else
        state.pendingFall = nil
        state.highestZ = fallZ
    end

    if vehicle then
        local speed = getVehicleSpeedKmh(vehicle)
        local previousSpeed = tonumber(state.lastVehicleSpeed) or speed
        local speedDrop = previousSpeed - speed

        if speedDrop >= (cfg.CRASH_SPEED_DROP_KMH or 28) then
            debugConcussion(player, state, "vehicle-impact-candidate", string.format(
                "speed %.1f -> %.1f drop %.1f threshold %.1f",
                previousSpeed,
                speed,
                speedDrop,
                cfg.CRASH_SPEED_DROP_KMH or 28
            ), true)
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
    state.lastFallZ = fallZ
    state.lastX = x
    state.lastY = y
    state.lastHealth = health
    state.lastHeadPain = headPain
    state.lastSnapshot = snapshot
    state.lastSquare = getPlayerSquare(player) or getGridSquareAt(x, y, z)
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
