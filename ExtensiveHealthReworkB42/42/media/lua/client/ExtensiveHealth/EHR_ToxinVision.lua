--[[
    Extensive Health Rework B42
    Toxin poisoning visual disturbance

    Uses the vanilla SearchMode overlay override for short, reversible
    blurred-vision episodes during stage 3 toxin poisoning.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_Dialogue"

EHR = EHR or {}
EHR.ToxinVision = EHR.ToxinVision or {}

local tableUnpack = unpack or table.unpack

EHR.ToxinVision.Config = {
    CHECK_INTERVAL_HOURS = 1 / 60,      -- one game minute
    MIN_DURATION_MINUTES = 10,
    MAX_DURATION_MINUTES = 20,
    MEDICATION_MIN_DURATION_MINUTES = 10,
    MEDICATION_MAX_DURATION_MINUTES = 20,
    SYMPTOM_MIN_DURATION_MINUTES = 5,
    SYMPTOM_MAX_DURATION_MINUTES = 10,
    MIN_INTERVAL_MINUTES = 25,
    MAX_INTERVAL_MINUTES = 45,

    RADIUS_EXTERIOR = 3.5,
    RADIUS_INTERIOR = 3.0,
    GRADIENT_EXTERIOR = 5.0,
    GRADIENT_INTERIOR = 4.5,
    BLUR_EXTERIOR = 0.62,
    BLUR_INTERIOR = 0.52,
    DESAT_EXTERIOR = 0.30,
    DESAT_INTERIOR = 0.24,
    DARKNESS_EXTERIOR = 0.10,
    DARKNESS_INTERIOR = 0.07,
}

EHR.ToxinVision.Dialogue = {
    "My vision is blurring...",
    "Everything is swimming...",
    "I can't focus my eyes...",
    "The room won't stay still...",
    "My eyes feel clouded...",
}

EHR.ToxinVision.State = EHR.ToxinVision.State or {}
EHR.ToxinVision.NextCheckHour = 0

local pairGetters = {
    radius = "getRadius",
    gradient = "getGradientWidth",
    blur = "getBlur",
    desat = "getDesat",
    dark = "getDarkness",
}

local function safeCall(obj, method, ...)
    if not obj or not method then return nil, false end
    local fn = obj[method]
    if not fn then return nil, false end

    local args = { ... }
    local ok, result = pcall(function()
        return fn(obj, tableUnpack(args))
    end)

    if not ok then return nil, false end
    return result, true
end

local function getWorldHour()
    local gameTime = getGameTime and getGameTime()
    if not gameTime then return 0 end
    return gameTime:getWorldAgeHours()
end

local function randomMinutesAsHours(minMinutes, maxMinutes)
    return (minMinutes + ZombRand((maxMinutes - minMinutes) + 1)) / 60
end

local function getLocalPlayerCount()
    if getNumActivePlayers then
        local ok, count = pcall(getNumActivePlayers)
        if ok and count and count > 0 then return count end
    end
    return 1
end

local function getPlayerIndex(player, fallback)
    if player then
        local ok, playerNum = pcall(function() return player:getPlayerNum() end)
        if ok and playerNum ~= nil then return playerNum end
    end
    return fallback or 0
end

local function isPlayerValid(player)
    if not player then return false end
    local ok, dead = pcall(function() return player:isDead() end)
    return not (ok and dead)
end

local function getSearchObjects(playerIndex)
    if not getSearchMode then return nil, nil end

    local ok, searchMode = pcall(getSearchMode)
    if not ok or not searchMode then return nil, nil end

    local playerSearchMode = safeCall(searchMode, "getSearchModeForPlayer", playerIndex)
    if not playerSearchMode then return nil, nil end

    return searchMode, playerSearchMode
end

local function getPair(playerSearchMode, key)
    local getter = pairGetters[key]
    if not getter then return nil end
    return safeCall(playerSearchMode, getter)
end

local function clampPairValue(pair, value)
    if type(value) ~= "number" then return value end

    local minValue, minOk = safeCall(pair, "getMin")
    local maxValue, maxOk = safeCall(pair, "getMax")

    if minOk and type(minValue) == "number" and value < minValue then
        value = minValue
    end
    if maxOk and type(maxValue) == "number" and value > maxValue then
        value = maxValue
    end

    return value
end

local function capturePair(playerSearchMode, key)
    local pair = getPair(playerSearchMode, key)
    if not pair then return nil end

    local exterior, exteriorOk = safeCall(pair, "getExterior")
    local interior, interiorOk = safeCall(pair, "getInterior")

    return {
        exterior = exterior,
        exteriorOk = exteriorOk,
        interior = interior,
        interiorOk = interiorOk,
    }
end

local function restorePair(playerSearchMode, key, savedPair)
    if not savedPair then return end

    local pair = getPair(playerSearchMode, key)
    if not pair then return end

    if savedPair.exteriorOk then
        safeCall(pair, "setExterior", savedPair.exterior)
    end
    if savedPair.interiorOk then
        safeCall(pair, "setInterior", savedPair.interior)
    end
end

local function setPair(playerSearchMode, key, exterior, interior)
    local pair = getPair(playerSearchMode, key)
    if not pair then return end

    safeCall(pair, "setExterior", clampPairValue(pair, exterior))
    safeCall(pair, "setInterior", clampPairValue(pair, interior))
end

local function captureSearchState(playerIndex)
    local searchMode, playerSearchMode = getSearchObjects(playerIndex)
    if not searchMode or not playerSearchMode then return nil end

    local enabled, enabledOk = safeCall(searchMode, "isEnabled", playerIndex)
    local override, overrideOk = safeCall(searchMode, "isOverride", playerIndex)

    return {
        enabled = enabled,
        enabledOk = enabledOk,
        override = override,
        overrideOk = overrideOk,
        pairs = {
            radius = capturePair(playerSearchMode, "radius"),
            gradient = capturePair(playerSearchMode, "gradient"),
            blur = capturePair(playerSearchMode, "blur"),
            desat = capturePair(playerSearchMode, "desat"),
            dark = capturePair(playerSearchMode, "dark"),
        },
    }
end

local function restoreSearchState(playerIndex, saved)
    if not saved then return end

    local searchMode, playerSearchMode = getSearchObjects(playerIndex)
    if not searchMode or not playerSearchMode then return end

    restorePair(playerSearchMode, "radius", saved.pairs and saved.pairs.radius)
    restorePair(playerSearchMode, "gradient", saved.pairs and saved.pairs.gradient)
    restorePair(playerSearchMode, "blur", saved.pairs and saved.pairs.blur)
    restorePair(playerSearchMode, "desat", saved.pairs and saved.pairs.desat)
    restorePair(playerSearchMode, "dark", saved.pairs and saved.pairs.dark)

    if saved.overrideOk then
        safeCall(searchMode, "setOverride", playerIndex, saved.override)
    end
    if saved.enabledOk then
        safeCall(searchMode, "setEnabled", playerIndex, saved.enabled)
    end
end

function EHR.ToxinVision.Apply(playerIndex)
    local searchMode, playerSearchMode = getSearchObjects(playerIndex)
    if not searchMode or not playerSearchMode then return false end

    safeCall(searchMode, "setEnabled", playerIndex, true)
    safeCall(searchMode, "setOverride", playerIndex, true)

    local cfg = EHR.ToxinVision.Config
    setPair(playerSearchMode, "radius", cfg.RADIUS_EXTERIOR, cfg.RADIUS_INTERIOR)
    setPair(playerSearchMode, "gradient", cfg.GRADIENT_EXTERIOR, cfg.GRADIENT_INTERIOR)
    setPair(playerSearchMode, "blur", cfg.BLUR_EXTERIOR, cfg.BLUR_INTERIOR)
    setPair(playerSearchMode, "desat", cfg.DESAT_EXTERIOR, cfg.DESAT_INTERIOR)
    setPair(playerSearchMode, "dark", cfg.DARKNESS_EXTERIOR, cfg.DARKNESS_INTERIOR)

    return true
end

function EHR.ToxinVision.GetState(playerIndex)
    EHR.ToxinVision.State[playerIndex] = EHR.ToxinVision.State[playerIndex] or {}
    return EHR.ToxinVision.State[playerIndex]
end

function EHR.ToxinVision.HasPeakToxinPoisoning(player)
    if not isPlayerValid(player) then return false end
    if not EHR.Disease or not EHR.Disease.GetDiseaseData then return false end

    local data = EHR.Disease.GetDiseaseData(player)
    local toxin = data and data.active and data.active.toxin_poisoning
    return toxin and toxin.stage == 3
end

function EHR.ToxinVision.HasMedicationDizziness(player, currentHour)
    if not isPlayerValid(player) then return false end

    local modData = player:getModData()
    local medData = modData and modData.EHR_Medication
    local activeEffects = medData and medData.activeSideEffects
    local effect = activeEffects and activeEffects.dizziness
    if type(effect) ~= "table" then return false end

    currentHour = currentHour or getWorldHour()
    local startTime = tonumber(effect.startTime) or currentHour
    local duration = tonumber(effect.duration) or 0
    return duration > 0 and currentHour < startTime + duration
end

function EHR.ToxinVision.SayBlurLine(player, state)
    if not player or not player.Say then return end

    local lines = EHR.ToxinVision.Dialogue
    if not lines or #lines == 0 then return end

    local index = ZombRand(#lines) + 1
    if #lines > 1 and state and state.lastLineIndex == index then
        index = (index % #lines) + 1
    end
    if state then state.lastLineIndex = index end

    local line = lines[index]
    if EHR.Dialogue and EHR.Dialogue.SayStageChange then
        EHR.Dialogue.SayStageChange(player, line)
    else
        player:Say(line)
    end
end

function EHR.ToxinVision.ScheduleNextEpisode(state, currentHour)
    local cfg = EHR.ToxinVision.Config
    state.nextEpisodeHour = currentHour + randomMinutesAsHours(cfg.MIN_INTERVAL_MINUTES, cfg.MAX_INTERVAL_MINUTES)
end

function EHR.ToxinVision.StartEpisode(player, playerIndex, currentHour)
    local state = EHR.ToxinVision.GetState(playerIndex)
    if state.active then return end

    local saved = captureSearchState(playerIndex)
    if not saved then
        state.nextEpisodeHour = currentHour + randomMinutesAsHours(5, 10)
        return
    end

    local cfg = EHR.ToxinVision.Config
    state.savedSearchState = saved
    state.active = true
    state.source = "toxin"
    state.activeUntilHour = currentHour + randomMinutesAsHours(cfg.MIN_DURATION_MINUTES, cfg.MAX_DURATION_MINUTES)

    if EHR.ToxinVision.Apply(playerIndex) then
        EHR.ToxinVision.SayBlurLine(player, state)
        EHR.Log("ToxinVision: blurred vision episode started")
    else
        EHR.ToxinVision.StopEpisode(playerIndex, currentHour, true)
    end
end

function EHR.ToxinVision.StartMedicationEpisode(player)
    if not isPlayerValid(player) then return false end

    local playerIndex = getPlayerIndex(player, 0)
    local state = EHR.ToxinVision.GetState(playerIndex)
    if state.active then return false end

    local currentHour = getWorldHour()
    if not EHR.ToxinVision.HasMedicationDizziness(player, currentHour) then return false end

    local saved = captureSearchState(playerIndex)
    if not saved then return false end

    local cfg = EHR.ToxinVision.Config
    state.savedSearchState = saved
    state.active = true
    state.source = "medication"
    state.activeUntilHour = currentHour + randomMinutesAsHours(
        cfg.MEDICATION_MIN_DURATION_MINUTES,
        cfg.MEDICATION_MAX_DURATION_MINUTES
    )

    if EHR.ToxinVision.Apply(playerIndex) then
        EHR.Log("ToxinVision: medication dizziness episode started")
        return true
    end

    EHR.ToxinVision.StopEpisode(playerIndex, currentHour, false)
    return false
end

function EHR.ToxinVision.StartSymptomEpisode(player)
    if not isPlayerValid(player) then return false end

    local playerIndex = getPlayerIndex(player, 0)
    local state = EHR.ToxinVision.GetState(playerIndex)
    if state.active then return false end

    local currentHour = getWorldHour()
    local saved = captureSearchState(playerIndex)
    if not saved then return false end

    local cfg = EHR.ToxinVision.Config
    state.savedSearchState = saved
    state.active = true
    state.source = "symptom"
    state.activeUntilHour = currentHour + randomMinutesAsHours(
        cfg.SYMPTOM_MIN_DURATION_MINUTES,
        cfg.SYMPTOM_MAX_DURATION_MINUTES
    )

    if EHR.ToxinVision.Apply(playerIndex) then
        EHR.Log("ToxinVision: symptom dizziness episode started")
        return true
    end

    EHR.ToxinVision.StopEpisode(playerIndex, currentHour, false)
    return false
end

function EHR.ToxinVision.StopEpisode(playerIndex, currentHour, scheduleNext)
    local state = EHR.ToxinVision.GetState(playerIndex)

    if state.active or state.savedSearchState then
        restoreSearchState(playerIndex, state.savedSearchState)
    end

    state.active = false
    state.source = nil
    state.activeUntilHour = nil
    state.savedSearchState = nil

    if scheduleNext then
        EHR.ToxinVision.ScheduleNextEpisode(state, currentHour or getWorldHour())
    end
end

function EHR.ToxinVision.UpdatePlayer(player, playerIndex, currentHour)
    local state = EHR.ToxinVision.GetState(playerIndex)

    if not EHR.ToxinVision.HasPeakToxinPoisoning(player) then
        if state.source == "toxin" then
            EHR.ToxinVision.StopEpisode(playerIndex, currentHour, false)
        end
        state.nextEpisodeHour = nil
        return
    end

    if state.active then return end

    if not state.nextEpisodeHour then
        state.nextEpisodeHour = currentHour
    end

    if currentHour >= state.nextEpisodeHour then
        EHR.ToxinVision.StartEpisode(player, playerIndex, currentHour)
    end
end

function EHR.ToxinVision.OnTick()
    local currentHour = getWorldHour()
    local shouldCheckDisease = currentHour >= (EHR.ToxinVision.NextCheckHour or 0)

    if shouldCheckDisease then
        EHR.ToxinVision.NextCheckHour = currentHour + EHR.ToxinVision.Config.CHECK_INTERVAL_HOURS
    end

    for i = 0, getLocalPlayerCount() - 1 do
        local player = getSpecificPlayer and getSpecificPlayer(i) or nil
        local playerIndex = getPlayerIndex(player, i)
        local state = EHR.ToxinVision.GetState(playerIndex)

        if state.active then
            if state.source == "medication" and not EHR.ToxinVision.HasMedicationDizziness(player, currentHour) then
                EHR.ToxinVision.StopEpisode(playerIndex, currentHour, false)
            elseif currentHour >= (state.activeUntilHour or 0) then
                EHR.ToxinVision.StopEpisode(playerIndex, currentHour, state.source == "toxin")
            else
                EHR.ToxinVision.Apply(playerIndex)
            end
        end

        if shouldCheckDisease then
            EHR.ToxinVision.UpdatePlayer(player, playerIndex, currentHour)
        end
    end
end

function EHR.ToxinVision.OnPlayerDeath(player)
    local playerIndex = getPlayerIndex(player, 0)
    EHR.ToxinVision.StopEpisode(playerIndex, getWorldHour(), false)
    EHR.ToxinVision.State[playerIndex] = nil
end

if Events then
    Events.OnTick.Add(EHR.ToxinVision.OnTick)
    if Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(EHR.ToxinVision.OnPlayerDeath)
    end
end

EHR.Log("ToxinVision module loaded")
