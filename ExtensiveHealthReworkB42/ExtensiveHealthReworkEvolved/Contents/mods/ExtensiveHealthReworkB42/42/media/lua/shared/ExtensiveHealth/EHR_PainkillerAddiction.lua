--[[
    Extensive Health Rework B42
    Persistent painkiller addiction tracking and progression
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
if not EHR.Disease then
    pcall(function() require "ExtensiveHealth/EHR_Disease" end)
end

EHR.PainkillerAddiction = EHR.PainkillerAddiction or {}

EHR.PainkillerAddiction.Config = {
    CHECK_INTERVAL_HOURS = 0.05,
    STAGE_1_HOURS = 24,
    STAGE_2_HOURS = 48,

    DOSE_WINDOW_HOURS = 24,
    EARLY_REDOSE_HOURS = 3,
    DUPLICATE_DOSE_WINDOW_HOURS = 0.02,

    -- Dependency grows slowly under ordinary use, then rises sharply at the
    -- fifth and sixth doses taken during a rolling 24-hour window.
    BASE_DOSE_RISK = 1,
    FIFTH_DOSE_RISK = 8,
    SIXTH_DOSE_RISK = 14,
    EXCESS_DOSE_RISK = 20,
    EARLY_REDOSE_RISK = 4,
    ADDICTION_THRESHOLD = 100,

    -- Latent risk begins to fade only after a full day without painkillers.
    RISK_DECAY_DELAY_HOURS = 24,
    RISK_DECAY_PER_DAY = 10,
}

local function worldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        local ok, hour = pcall(function() return gameTime:getWorldAgeHours() end)
        if ok and hour then return tonumber(hour) or 0 end
    end
    return 0
end

local function isPureClient()
    return isClient and isClient() and not (isServer and isServer())
end

local function isValidPlayer(player)
    if not player then return false end
    local okDead, dead = pcall(function()
        if player.isDead then return player:isDead() end
        return false
    end)
    return not (okDead and dead == true)
end

local function getState(player, create)
    local modData = player and player.getModData and player:getModData() or nil
    if not modData then return nil end

    if type(modData.EHR_PainkillerAddiction) ~= "table" then
        if create == false then return nil end
        modData.EHR_PainkillerAddiction = {
            risk = 0,
            doseHours = {},
        }
    end

    local state = modData.EHR_PainkillerAddiction
    if type(state.doseHours) ~= "table" then state.doseHours = {} end
    state.risk = math.max(0, math.min(100, tonumber(state.risk) or 0))
    return state
end

local function getActiveDisease(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
    return diseaseData and diseaseData.active and diseaseData.active.painkiller_addiction or nil
end

local function transmit(player)
    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(player)
    end
end

local function trimDoseHistory(state, currentHour)
    local cutoff = currentHour - EHR.PainkillerAddiction.Config.DOSE_WINDOW_HOURS
    local recent = {}
    for _, doseHour in ipairs(state.doseHours or {}) do
        local numericHour = tonumber(doseHour)
        if numericHour and numericHour > cutoff and numericHour <= currentHour + 0.05 then
            table.insert(recent, numericHour)
        end
    end
    state.doseHours = recent
    return recent
end

local function updateLatentRiskDecay(state, currentHour)
    if not state then return end

    local previousUpdate = tonumber(state.lastRiskUpdateHour) or currentHour
    local lastDoseHour = tonumber(state.lastDoseHour)
    if currentHour < previousUpdate then
        state.lastRiskUpdateHour = currentHour
        return
    end

    if lastDoseHour then
        local decayStart = math.max(previousUpdate, lastDoseHour + EHR.PainkillerAddiction.Config.RISK_DECAY_DELAY_HOURS)
        if currentHour > decayStart then
            local decayPerHour = EHR.PainkillerAddiction.Config.RISK_DECAY_PER_DAY / 24
            state.risk = math.max(0, (tonumber(state.risk) or 0) - ((currentHour - decayStart) * decayPerHour))
        end
    end

    state.lastRiskUpdateHour = currentHour
    trimDoseHistory(state, currentHour)
end

function EHR.PainkillerAddiction.HasActive(player)
    return getActiveDisease(player) ~= nil
end

function EHR.PainkillerAddiction.IsWithdrawalSuppressed(player)
    if not isValidPlayer(player) then return false end

    if EHR.Medication and EHR.Medication.IsAnalgesicActive
        and EHR.Medication.IsAnalgesicActive(player) then
        return true
    end

    if EHR.Medication and EHR.Medication.GetDoseStatus then
        local ok, status = pcall(
            EHR.Medication.GetDoseStatus,
            player,
            "ExtensiveHealth.Buprenorphine"
        )
        if ok and status and status.isDoseActive then
            return true
        end
    end

    return false
end

function EHR.PainkillerAddiction.GetRisk(player)
    local state = getState(player, false)
    return state and (tonumber(state.risk) or 0) or 0
end

function EHR.PainkillerAddiction.Contract(player, source)
    if not isValidPlayer(player) or EHR.PainkillerAddiction.HasActive(player) then return false end
    if not (EHR.Disease and EHR.Disease.Contract) then return false end

    if not (EHR.Disease.Diseases and EHR.Disease.Diseases.painkiller_addiction) then
        pcall(function() require "ExtensiveHealth/EHR_DiseaseDefinitions" end)
    end
    if not (EHR.Disease.Diseases and EHR.Disease.Diseases.painkiller_addiction) then return false end

    EHR.Disease.Contract(player, "painkiller_addiction")

    local disease = getActiveDisease(player)
    if not disease then return false end

    local currentHour = worldHour()
    local cfg = EHR.PainkillerAddiction.Config
    disease.startTime = currentHour
    disease.incubationEnd = currentHour
    disease.peakTime = currentHour + cfg.STAGE_1_HOURS
    disease.endTime = currentHour + 999999
    disease.stage = 1
    disease.stageCount = 3
    disease.progress = 0
    disease.stageProgress = 0
    disease.progressMode = "stage"
    disease.manualProgression = true
    disease.noNaturalRecovery = true
    disease.addictionSource = source or "painkiller_overuse"

    local state = getState(player, true)
    state.risk = cfg.ADDICTION_THRESHOLD
    state.lastStage = 1

    transmit(player)
    return true
end

function EHR.PainkillerAddiction.ClearAfterCure(player)
    local modData = player and player.getModData and player:getModData() or nil
    if modData then modData.EHR_PainkillerAddiction = nil end
end

function EHR.PainkillerAddiction.OnPainkillerDose(player, doseHour)
    -- Clients report the vanilla pill use through TrackMedication. The server
    -- owns the dependency score so a dose cannot be counted twice in MP.
    if isPureClient() or not isValidPlayer(player) then return false end
    if EHR.PainkillerAddiction.HasActive(player) then return false end

    local currentHour = tonumber(doseHour) or worldHour()
    local state = getState(player, true)
    local lastProcessed = tonumber(state.lastProcessedDoseHour)
    if lastProcessed and math.abs(currentHour - lastProcessed) <= EHR.PainkillerAddiction.Config.DUPLICATE_DOSE_WINDOW_HOURS then
        return false
    end

    updateLatentRiskDecay(state, currentHour)

    local previousDoseHour = tonumber(state.lastDoseHour)
    local recent = trimDoseHistory(state, currentHour)
    table.insert(recent, currentHour)

    local dosesInWindow = #recent
    local cfg = EHR.PainkillerAddiction.Config
    local doseRisk = cfg.BASE_DOSE_RISK
    if dosesInWindow == 5 then
        doseRisk = cfg.FIFTH_DOSE_RISK
    elseif dosesInWindow == 6 then
        doseRisk = cfg.SIXTH_DOSE_RISK
    elseif dosesInWindow >= 7 then
        doseRisk = cfg.EXCESS_DOSE_RISK
    end

    local timeSincePrevious = previousDoseHour and (currentHour - previousDoseHour) or nil
    local earlyRedose = timeSincePrevious and timeSincePrevious >= 0 and timeSincePrevious < cfg.EARLY_REDOSE_HOURS
    if earlyRedose then doseRisk = doseRisk + cfg.EARLY_REDOSE_RISK end

    state.risk = math.min(cfg.ADDICTION_THRESHOLD, (tonumber(state.risk) or 0) + doseRisk)
    state.lastDoseHour = currentHour
    state.lastProcessedDoseHour = currentHour
    state.lastRiskUpdateHour = currentHour
    state.lastDoseCount24h = dosesInWindow

    if EHR.DEBUG and EHR.Log then
        EHR.Log(string.format(
            "Painkiller dependency: dose %d/24h, +%.1f risk, total %.1f/%.0f",
            dosesInWindow,
            doseRisk,
            state.risk,
            cfg.ADDICTION_THRESHOLD
        ))
    end

    if state.risk >= cfg.ADDICTION_THRESHOLD then
        return EHR.PainkillerAddiction.Contract(player, "painkiller_overuse")
    end

    transmit(player)
    return true
end

function EHR.PainkillerAddiction.UpdateActiveDisease(player, currentHour)
    local disease = getActiveDisease(player)
    if not disease then return false end

    local startTime = tonumber(disease.startTime) or currentHour
    local elapsed = math.max(0, currentHour - startTime)
    local cfg = EHR.PainkillerAddiction.Config
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
        local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases.painkiller_addiction
        local withdrawalSuppressed = EHR.PainkillerAddiction.IsWithdrawalSuppressed(player)
        if not withdrawalSuppressed and def and def.stageEntryDialogue and def.stageEntryDialogue[newStage] and EHR.Dialogue then
            EHR.Dialogue.SayStageChange(player, def.stageEntryDialogue[newStage])
        end
        transmit(player)
    end

    return true
end

function EHR.PainkillerAddiction.UpdateTracking(player)
    if isPureClient() or not isValidPlayer(player) then return end

    local disease = getActiveDisease(player)
    local state = getState(player, disease ~= nil)
    if not state then return end

    local currentHour = worldHour()
    if currentHour < (tonumber(state.nextCheckHour) or 0) then return end
    state.nextCheckHour = currentHour + EHR.PainkillerAddiction.Config.CHECK_INTERVAL_HOURS

    if disease then
        EHR.PainkillerAddiction.UpdateActiveDisease(player, currentHour)
    else
        updateLatentRiskDecay(state, currentHour)
    end
end

function EHR.PainkillerAddiction.OnPlayerUpdate(player)
    local ok, err = pcall(EHR.PainkillerAddiction.UpdateTracking, player)
    if not ok and EHR and EHR.Log then
        EHR.Log("Painkiller addiction tracking error: " .. tostring(err))
    end
end

function EHR.PainkillerAddiction.OnTick()
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
        EHR.PainkillerAddiction.OnPlayerUpdate(player)
    end
end

function EHR.PainkillerAddiction.OnPlayerDeath(player)
    EHR.PainkillerAddiction.ClearAfterCure(player)
end

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(EHR.PainkillerAddiction.OnPlayerUpdate)
end

if Events and Events.OnTick then
    Events.OnTick.Add(EHR.PainkillerAddiction.OnTick)
end

if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(EHR.PainkillerAddiction.OnPlayerDeath)
end

EHR.Log("EHR_PainkillerAddiction.lua loaded")
