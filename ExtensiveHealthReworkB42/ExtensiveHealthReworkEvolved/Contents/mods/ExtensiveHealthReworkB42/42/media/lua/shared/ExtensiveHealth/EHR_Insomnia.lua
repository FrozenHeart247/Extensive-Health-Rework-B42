--[[
    Extensive Health Rework B42
    Insomnia trigger and sleep-lock support
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
if not EHR.Disease then
    pcall(function() require "ExtensiveHealth/EHR_Disease" end)
end
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
EHR.Insomnia = EHR.Insomnia or {}
EHR.Insomnia.State = EHR.Insomnia.State or {}

EHR.Insomnia.Config = {
    FATIGUE_THRESHOLD = 0.80,
    HOURS_AT_HIGH_FATIGUE_TO_TRIGGER = 12,
    CHECK_INTERVAL_HOURS = 0.05,
    STAGE_1_HOURS = 24,
    STAGE_2_HOURS = 48,
    STIMULANT_CRASH_CHANCE = 0.10,
    -- Keep the per-crash roll at 10%, but avoid stacking several stimulant
    -- crash rolls into a near-guaranteed insomnia proc in one play session.
    STIMULANT_RISK_COOLDOWN_HOURS = 12,
}

local function worldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        local ok, hour = pcall(function() return gameTime:getWorldAgeHours() end)
        if ok and hour then return tonumber(hour) or 0 end
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

local function isAsleep(player)
    local ok, asleep = pcall(function()
        if player and player.isAsleep then return player:isAsleep() end
        return false
    end)
    return ok and asleep == true
end

local function getFatigue(player)
    local stats = nil
    pcall(function() stats = player and player:getStats() or nil end)
    if not stats then return 0 end

    if CharacterStat and CharacterStat.FATIGUE and stats.get then
        local ok, value = pcall(function() return stats:get(CharacterStat.FATIGUE) end)
        if ok and value then return tonumber(value) or 0 end
    end

    if stats.getFatigue then
        local ok, value = pcall(function() return stats:getFatigue() end)
        if ok and value then return tonumber(value) or 0 end
    end

    return 0
end

local function getState(player)
    local key = playerKey(player)
    EHR.Insomnia.State[key] = EHR.Insomnia.State[key] or {}
    return EHR.Insomnia.State[key]
end

local function getActiveDisease(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
    return diseaseData and diseaseData.active and diseaseData.active.insomnia or nil
end

local function transmit(player)
    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(player)
    end
end

function EHR.Insomnia.HasActive(player)
    return getActiveDisease(player) ~= nil
end

function EHR.Insomnia.HasActiveSleepAid(player)
    return EHR.Medication
        and EHR.Medication.HasActiveSleepAid
        and EHR.Medication.HasActiveSleepAid(player) == true
end

function EHR.Insomnia.Contract(player, source)
    if not isValidPlayer(player) or EHR.Insomnia.HasActive(player) then return false end
    if not (EHR.Disease and EHR.Disease.Contract) then return false end

    EHR.Disease.Contract(player, "insomnia")

    local disease = getActiveDisease(player)
    if not disease then return false end

    local now = worldHour()
    disease.startTime = now
    disease.incubationEnd = now
    disease.peakTime = now + EHR.Insomnia.Config.STAGE_1_HOURS
    disease.endTime = now + 999999
    disease.stage = 1
    disease.stageCount = 3
    disease.progress = 0
    disease.stageProgress = 0
    disease.progressMode = "stage"
    disease.manualProgression = true
    disease.noNaturalRecovery = true
    disease.insomniaSource = source or "fatigue"

    local state = getState(player)
    state.highFatigueSince = nil
    state.lastStage = 1

    transmit(player)
    return true
end

function EHR.Insomnia.ClearAfterCure(player)
    local state = getState(player)
    state.highFatigueSince = nil
    state.lastStage = nil
    state.nextCheckHour = nil

    local modData = player and player.getModData and player:getModData() or nil
    if modData then modData.EHR_Insomnia = nil end
end

function EHR.Insomnia.ShouldBlockSleep(player)
    local disease = getActiveDisease(player)
    if not disease then return false end
    local stage = tonumber(disease.stage) or 1
    if stage < 2 then return false end
    return not EHR.Insomnia.HasActiveSleepAid(player)
end

function EHR.Insomnia.UpdateActiveDisease(player, currentHour)
    local disease = getActiveDisease(player)
    if not disease then return false end

    local startTime = tonumber(disease.startTime) or currentHour
    local elapsed = math.max(0, currentHour - startTime)
    local cfg = EHR.Insomnia.Config
    local oldStage = tonumber(disease.stage) or 1
    local newStage = 1
    local stageStart = startTime
    local stageDuration = cfg.STAGE_1_HOURS

    if elapsed >= cfg.STAGE_2_HOURS then
        newStage = 3
        stageStart = startTime + cfg.STAGE_2_HOURS
        stageDuration = 1
    elseif elapsed >= cfg.STAGE_1_HOURS then
        newStage = 2
        stageStart = startTime + cfg.STAGE_1_HOURS
        stageDuration = cfg.STAGE_2_HOURS - cfg.STAGE_1_HOURS
    end

    local stageElapsed = math.max(0, currentHour - stageStart)
    local stageProgress = 1
    if newStage < 3 then
        stageProgress = math.max(0, math.min(1, stageElapsed / math.max(0.05, stageDuration)))
    end

    disease.stage = newStage
    disease.stageCount = 3
    disease.incubationEnd = startTime
    disease.peakTime = startTime + cfg.STAGE_1_HOURS
    disease.endTime = currentHour + 999999
    disease.progress = math.max(0, math.min(1, elapsed / cfg.STAGE_2_HOURS))
    disease.stageProgress = stageProgress
    disease.stageStartTime = stageStart
    disease.progressMode = "stage"
    disease.manualProgression = true
    disease.noNaturalRecovery = true

    if oldStage ~= newStage then
        local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases.insomnia
        if def and def.stageEntryDialogue and def.stageEntryDialogue[newStage] and EHR.Dialogue then
            EHR.Dialogue.SayStageChange(player, def.stageEntryDialogue[newStage])
        end
        transmit(player)
    end

    return true
end

function EHR.Insomnia.UpdateFatigueTrigger(player, currentHour)
    if EHR.Insomnia.HasActive(player) then return end
    if isAsleep(player) then
        getState(player).highFatigueSince = nil
        return
    end

    local state = getState(player)
    local fatigue = getFatigue(player)
    local cfg = EHR.Insomnia.Config

    if fatigue >= cfg.FATIGUE_THRESHOLD then
        state.highFatigueSince = state.highFatigueSince or currentHour
        if (currentHour - state.highFatigueSince) >= cfg.HOURS_AT_HIGH_FATIGUE_TO_TRIGGER then
            EHR.Insomnia.Contract(player, "prolonged_fatigue")
        end
    else
        state.highFatigueSince = nil
    end
end

function EHR.Insomnia.RollStimulantCrash(player, source)
    if not isValidPlayer(player) or EHR.Insomnia.HasActive(player) then return false end

    local now = worldHour()
    local state = getState(player)
    if state.lastStimulantRiskHour and (now - state.lastStimulantRiskHour) < EHR.Insomnia.Config.STIMULANT_RISK_COOLDOWN_HOURS then
        return false
    end

    state.lastStimulantRiskHour = now
    local roll = ZombRand(10000) / 10000
    if roll < EHR.Insomnia.Config.STIMULANT_CRASH_CHANCE then
        return EHR.Insomnia.Contract(player, source or "stimulant_crash")
    end

    return false
end

function EHR.Insomnia.UpdateTracking(player)
    if not isValidPlayer(player) then return end

    local currentHour = worldHour()
    local state = getState(player)
    if currentHour < (tonumber(state.nextCheckHour) or 0) then return end
    state.nextCheckHour = currentHour + EHR.Insomnia.Config.CHECK_INTERVAL_HOURS

    EHR.Insomnia.UpdateActiveDisease(player, currentHour)
    EHR.Insomnia.UpdateFatigueTrigger(player, currentHour)
end

function EHR.Insomnia.OnPlayerUpdate(player)
    local ok, err = pcall(EHR.Insomnia.UpdateTracking, player)
    if not ok and EHR and EHR.Log then
        EHR.Log("Insomnia tracking error: " .. tostring(err))
    end
end

function EHR.Insomnia.OnTick()
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
        for i = 0, 3 do
            local player = getSpecificPlayer(i)
            if player then table.insert(players, player) end
        end
    end

    for _, player in ipairs(players) do
        EHR.Insomnia.OnPlayerUpdate(player)
    end
end

function EHR.Insomnia.OnPlayerDeath(player)
    EHR.Insomnia.State[playerKey(player)] = nil
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(EHR.Insomnia.OnPlayerUpdate)
end

if Events and Events.OnTick then
    Events.OnTick.Add(EHR.Insomnia.OnTick)
end

if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(EHR.Insomnia.OnPlayerDeath)
end

EHR.Log("EHR_Insomnia.lua loaded")
