--[[
    Extensive Health Rework - Immune Status

    Phase 1 is observational only. This module calculates and persists the
    player's immune resilience, but it does not modify disease rolls yet.
]]

EHR = EHR or {}
EHR.Immunity = EHR.Immunity or {}

EHR.Immunity.SCHEMA_VERSION = 2
EHR.Immunity.UPDATE_INTERVAL_HOURS = 0.25
EHR.Immunity.SCHEDULER_INTERVAL_MINUTES = 15
EHR.Immunity.BASE_RECOVERY_PER_HOUR = 1.5
EHR.Immunity.BASE_DECLINE_PER_HOUR = 3.0

local FACTOR_WEIGHTS = {
    nutrition = 0.22,
    hydration = 0.18,
    rest = 0.22,
    stressControl = 0.10,
    bloodCondition = 0.13,
    healthReserve = 0.15,
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

local function roundOne(value)
    return math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
end

local function getWorldAgeHours()
    if not getGameTime then return 0 end
    local ok, gameTime = pcall(getGameTime)
    if not ok or not gameTime or not gameTime.getWorldAgeHours then return 0 end

    local ageOk, age = pcall(function()
        return gameTime:getWorldAgeHours()
    end)
    return ageOk and (tonumber(age) or 0) or 0
end

local function getSandboxValue(name, fallback)
    local settings = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not settings or settings[name] == nil then return fallback end
    return settings[name]
end

local function isClientOnly()
    return isClient and isClient() and not (isServer and isServer())
end

local function getCharacterStat(player, enumName, legacyGetter, fallback)
    if not player or not player.getStats then return fallback end

    local statsOk, stats = pcall(function()
        return player:getStats()
    end)
    if not statsOk or not stats then return fallback end

    if CharacterStat and CharacterStat[enumName] and stats.get then
        local ok, value = pcall(function()
            return stats:get(CharacterStat[enumName])
        end)
        if ok and tonumber(value) then
            return clamp(value, 0, 1)
        end
    end

    if legacyGetter and stats[legacyGetter] then
        local ok, value = pcall(function()
            return stats[legacyGetter](stats)
        end)
        if ok and tonumber(value) then
            return clamp(value, 0, 1)
        end
    end

    return fallback
end

local function getBloodPercent(player)
    if EHR.Blood and EHR.Blood.GetPercent then
        local ok, value = pcall(function()
            return EHR.Blood.GetPercent(player)
        end)
        if ok and tonumber(value) then
            return clamp(value, 0, 100)
        end
    end

    local modData = player and player.getModData and player:getModData() or nil
    local blood = modData and modData.EHR_Blood or nil
    local current = blood and tonumber(blood.currentVolume) or nil
    local maximum = blood and tonumber(blood.maxVolume) or nil
    if current and maximum and maximum > 0 then
        return clamp((current / maximum) * 100, 0, 100)
    end

    return 100
end

local function getOverallHealthPercent(player)
    if not player then return 100 end

    if player.getBodyDamage then
        local ok, bodyDamage = pcall(function()
            return player:getBodyDamage()
        end)
        if ok and bodyDamage and bodyDamage.getOverallBodyHealth then
            local healthOk, health = pcall(function()
                return bodyDamage:getOverallBodyHealth()
            end)
            if healthOk and tonumber(health) then
                return clamp(health, 0, 100)
            end
        end
    end

    if player.getHealth then
        local ok, health = pcall(function()
            return player:getHealth()
        end)
        if ok and tonumber(health) then
            return clamp(health, 0, 100)
        end
    end

    return 100
end

local function getDiseasePressure(player)
    local modData = player and player.getModData and player:getModData() or nil
    if not modData then return 0 end

    local pressure = 0
    local diseaseData = modData.EHR_Disease
    if diseaseData and type(diseaseData.active) == "table" then
        for _, disease in pairs(diseaseData.active) do
            if type(disease) == "table" then
                local stage = tonumber(disease.stage or disease.severity) or 1
                pressure = pressure + 8 + clamp(stage, 1, 4) * 2
            else
                pressure = pressure + 10
            end
        end
    end

    local woundData = modData.EHR_WoundInfection
    if woundData and type(woundData.parts) == "table" then
        for _, partData in pairs(woundData.parts) do
            local stage = tonumber(partData and partData.stage) or 0
            if stage > 0 then
                pressure = pressure + 6 + clamp(stage, 1, 4) * 2
            end
        end
    end

    local sepsis = modData.EHR_Sepsis
    if sepsis and sepsis.active == true then
        pressure = pressure + 25
    end

    return clamp(pressure, 0, 70)
end

local function calculateHygiene(player)
    local empty = {
        dirtiness = 0,
        bloodiness = 0,
        contaminatedParts = 0,
        totalParts = 0,
    }

    if not player or not player.getHumanVisual then
        return empty
    end

    local visualOk, visual = pcall(function()
        return player:getHumanVisual()
    end)
    if not visualOk or not visual then
        return empty
    end

    if not (BloodBodyPartType and BloodBodyPartType.MAX and BloodBodyPartType.FromIndex) then
        return empty
    end

    local countOk, totalParts = pcall(function()
        return BloodBodyPartType.MAX:index()
    end)
    totalParts = countOk and math.max(0, tonumber(totalParts) or 0) or 0
    if totalParts <= 0 then return empty end

    local totalBlood = 0
    local totalDirt = 0
    local contaminatedParts = 0
    for index = 0, totalParts - 1 do
        local partOk, part = pcall(function()
            return BloodBodyPartType.FromIndex(index)
        end)
        if partOk and part then
            local blood, dirt = 0, 0
            if visual.getBlood then
                local ok, value = pcall(function() return visual:getBlood(part) end)
                if ok then blood = clamp(value, 0, 1) end
            end
            if visual.getDirt then
                local ok, value = pcall(function() return visual:getDirt(part) end)
                if ok then dirt = clamp(value, 0, 1) end
            end

            totalBlood = totalBlood + blood
            totalDirt = totalDirt + dirt
            if blood + dirt > 0 then contaminatedParts = contaminatedParts + 1 end
        end
    end

    return {
        dirtiness = roundOne(clamp(totalDirt / totalParts * 100, 0, 100)),
        bloodiness = roundOne(clamp(totalBlood / totalParts * 100, 0, 100)),
        contaminatedParts = contaminatedParts,
        totalParts = totalParts,
    }
end

local function calculateHygienePenalty(dirtiness, bloodiness)
    dirtiness = clamp(dirtiness, 0, 100)
    bloodiness = clamp(bloodiness, 0, 100)

    local dirtPenalty
    if dirtiness <= 5 then
        dirtPenalty = 0
    elseif dirtiness <= 20 then
        dirtPenalty = (dirtiness - 5) / 15 * 12
    elseif dirtiness <= 50 then
        dirtPenalty = 12 + (dirtiness - 20) / 30 * 13
    else
        dirtPenalty = 25 + (dirtiness - 50) / 50 * 10
    end

    local bloodPenalty
    if bloodiness <= 2 then
        bloodPenalty = 0
    elseif bloodiness <= 20 then
        bloodPenalty = (bloodiness - 2) / 18 * 16
    elseif bloodiness <= 50 then
        bloodPenalty = 16 + (bloodiness - 20) / 30 * 14
    else
        bloodPenalty = 30 + (bloodiness - 50) / 50 * 10
    end

    return roundOne(dirtPenalty), roundOne(bloodPenalty), roundOne(clamp(dirtPenalty + bloodPenalty, 0, 55))
end

function EHR.Immunity.IsEnabled()
    return getSandboxValue("ImmunitySystemEnabled", true) ~= false
end

function EHR.Immunity.CalculateFactors(player)
    local hunger = getCharacterStat(player, "HUNGER", "getHunger", 0)
    local thirst = getCharacterStat(player, "THIRST", "getThirst", 0)
    local fatigue = getCharacterStat(player, "FATIGUE", "getFatigue", 0)
    local stress = getCharacterStat(player, "STRESS", "getStress", 0)
    local bloodPercent = getBloodPercent(player)
    local healthPercent = getOverallHealthPercent(player)
    local diseasePressure = getDiseasePressure(player)
    local restScore = fatigue <= 0.5 and 100 or clamp((1 - fatigue) * 200, 0, 100)
    local hygiene = calculateHygiene(player)
    local dirtPenalty, bloodPenalty, hygienePenalty = calculateHygienePenalty(hygiene.dirtiness, hygiene.bloodiness)
    hygiene.dirtPenalty = dirtPenalty
    hygiene.bloodPenalty = bloodPenalty
    hygiene.immunePenalty = hygienePenalty

    local factors = {
        nutrition = roundOne((1 - hunger) * 100),
        hydration = roundOne((1 - thirst) * 100),
        rest = roundOne(restScore),
        stressControl = roundOne((1 - stress) * 100),
        bloodCondition = roundOne(clamp((bloodPercent - 40) / 60 * 100, 0, 100)),
        healthReserve = roundOne(clamp(healthPercent - diseasePressure, 0, 100)),
    }

    local target = 0
    for factorId, weight in pairs(FACTOR_WEIGHTS) do
        target = target + (tonumber(factors[factorId]) or 0) * weight
    end

    target = target - hygienePenalty
    return factors, roundOne(clamp(target, 0, 100)), hygiene
end

function EHR.Immunity.InitializePlayer(player)
    if not player or not player.getModData then return nil end

    local modData = player:getModData()
    local state = modData.EHR_Immunity
    if type(state) ~= "table" then
        state = {}
        modData.EHR_Immunity = state
    end

    local factors, target, hygiene = EHR.Immunity.CalculateFactors(player)
    local now = getWorldAgeHours()

    state.version = EHR.Immunity.SCHEMA_VERSION
    state.factors = type(state.factors) == "table" and state.factors or factors
    state.target = tonumber(state.target) or target
    state.score = tonumber(state.score) or target
    state.hygiene = type(state.hygiene) == "table" and state.hygiene or hygiene
    state.lastUpdateHour = tonumber(state.lastUpdateHour) or now
    state.trend = state.trend or "stable"
    state.enabled = EHR.Immunity.IsEnabled()
    state.observationOnly = true

    return state
end

function EHR.Immunity.UpdatePlayer(player, force)
    if not player or not player.getModData then return nil end
    if player.isAlive then
        local aliveOk, alive = pcall(function()
            return player:isAlive()
        end)
        if aliveOk and not alive then return nil end
    end

    local state = EHR.Immunity.InitializePlayer(player)
    if not state then return nil end

    local now = getWorldAgeHours()
    local lastUpdate = tonumber(state.lastUpdateHour) or now
    local elapsed = now - lastUpdate
    if elapsed < 0 then
        state.lastUpdateHour = now
        elapsed = 0
    end

    if not force and elapsed < EHR.Immunity.UPDATE_INTERVAL_HOURS then
        return state
    end

    local factors, target, hygiene = EHR.Immunity.CalculateFactors(player)
    state.factors = factors
    state.target = target
    state.hygiene = hygiene
    state.enabled = EHR.Immunity.IsEnabled()
    state.observationOnly = true
    state.lastUpdateHour = now

    if not state.enabled then
        state.trend = "disabled"
        return state
    end

    local current = clamp(state.score, 0, 100)
    local sampledHours = math.min(math.max(elapsed, 0), 6)
    local recoveryMultiplier = clamp(getSandboxValue("ImmunityRecoveryRate", 1.0), 0.25, 3.0)
    local declineMultiplier = clamp(getSandboxValue("ImmunityDeclineRate", 1.0), 0.25, 3.0)

    if target > current + 0.05 then
        local maximumGain = EHR.Immunity.BASE_RECOVERY_PER_HOUR * recoveryMultiplier * sampledHours
        state.score = math.min(target, current + maximumGain)
        state.trend = "recovering"
    elseif target < current - 0.05 then
        local maximumLoss = EHR.Immunity.BASE_DECLINE_PER_HOUR * declineMultiplier * sampledHours
        state.score = math.max(target, current - maximumLoss)
        state.trend = "declining"
    else
        state.score = target
        state.trend = "stable"
    end

    state.score = roundOne(clamp(state.score, 0, 100))
    return state
end

function EHR.Immunity.GetData(player)
    if not player or not player.getModData then return nil end
    return player:getModData().EHR_Immunity
end

function EHR.Immunity.GetScore(player)
    local state = EHR.Immunity.GetData(player)
    return state and clamp(state.score, 0, 100) or 50
end

function EHR.Immunity.GetStatusId(score)
    score = clamp(score, 0, 100)
    if score < 20 then return "suppressed" end
    if score < 40 then return "compromised" end
    if score < 60 then return "strained" end
    if score < 80 then return "stable" end
    return "strong"
end

function EHR.Immunity.ResetPlayer(player)
    if not player or not player.getModData then return nil end
    player:getModData().EHR_Immunity = nil
    return EHR.Immunity.InitializePlayer(player)
end

local function collectPlayers()
    local players = {}

    if isServer and isServer() and getOnlinePlayers then
        local ok, onlinePlayers = pcall(getOnlinePlayers)
        if ok and onlinePlayers then
            for index = 0, onlinePlayers:size() - 1 do
                local player = onlinePlayers:get(index)
                if player then table.insert(players, player) end
            end
        end
    end

    if #players == 0 and getSpecificPlayer then
        local ok, player = pcall(function()
            return getSpecificPlayer(0)
        end)
        if ok and player then table.insert(players, player) end
    end

    return players
end

function EHR.Immunity.UpdateAllPlayers()
    if isClientOnly() then return end
    for _, player in ipairs(collectPlayers()) do
        EHR.Immunity.UpdatePlayer(player, false)
    end
end

function EHR.Immunity.OnScheduledMinute()
    local currentMinute = math.floor(getWorldAgeHours() * 60)
    local lastMinute = tonumber(EHR.Immunity._lastScheduledMinute)
    if lastMinute == nil or currentMinute < lastMinute then
        EHR.Immunity._lastScheduledMinute = currentMinute
        return
    end
    if currentMinute - lastMinute < EHR.Immunity.SCHEDULER_INTERVAL_MINUTES then return end

    EHR.Immunity._lastScheduledMinute = currentMinute
    EHR.Immunity.UpdateAllPlayers()
end

function EHR.Immunity.OnCreatePlayer(playerIndex, player)
    if isClientOnly() then return end
    EHR.Immunity.InitializePlayer(player)
end

function EHR.Immunity.OnGameStart()
    if isClientOnly() then return end
    for _, player in ipairs(collectPlayers()) do
        EHR.Immunity.InitializePlayer(player)
        EHR.Immunity.UpdatePlayer(player, true)
    end
    EHR.Immunity._lastScheduledMinute = math.floor(getWorldAgeHours() * 60)
end

if Events and not EHR.Immunity._eventsRegistered then
    EHR.Immunity._eventsRegistered = true

    if Events.OnCreatePlayer then
        Events.OnCreatePlayer.Add(EHR.Immunity.OnCreatePlayer)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(EHR.Immunity.OnGameStart)
    end
    if Events.EveryOneMinute then
        Events.EveryOneMinute.Add(EHR.Immunity.OnScheduledMinute)
    elseif Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(EHR.Immunity.OnScheduledMinute)
    elseif Events.OnTick then
        Events.OnTick.Add(EHR.Immunity.OnScheduledMinute)
    end
end
