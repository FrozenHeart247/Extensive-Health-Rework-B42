--[[
    Extensive Health Rework B42
    Multiplayer offline-progression freeze

    The server stores a lightweight last-seen marker and rebases only explicit
    EHR medical clocks when a character reconnects. This preserves remaining
    disease/treatment time without touching histories, counters or durations.
]]--

if not (isServer and isServer()) then return end

EHR = EHR or {}
EHR.OfflineProgression = EHR.OfflineProgression or {}

local Offline = EHR.OfflineProgression
if Offline._eventsRegistered then return end

Offline.VERSION = 1
Offline.MARKER_KEY = "EHR_OfflineProgression"
Offline.HEARTBEAT_POLL_TICKS = 60
Offline.HEARTBEAT_REAL_SECONDS = 30
Offline.HEARTBEAT_WORLD_HOURS = 0.1
Offline.MIN_GAP_HOURS = 0.0001

-- A character object is the identity of one live connection. Usernames and
-- online IDs can be reused after death/reconnect and must not suppress a real
-- offline rebase for the replacement object.
local onlineSessions = setmetatable({}, { __mode = "k" })
local heartbeatPollTicks = 0
local lastHeartbeatRealSeconds = nil
local lastHeartbeatWorldHour = nil

local DISEASE_TIME_FIELDS = {
    "startTime", "incubationEnd", "peakTime", "endTime",
    "stageStartTime", "lastStageTime",
    "lastCoughHour", "lastSneezeHour", "lastRandomDialogueHour",
    "pneumoniaLastDamageHour", "heatStrokeLastDamageHour",
    "hypothermiaLastDamageHour", "lastHeatStrokeCollapseCheckHour",
    "symptomReliefUntil", "corpseSicknessNauseaReliefUntil",
    "corpseSicknessSymptomTargetUntil", "concussionSicknessTargetUntil",
    "ahtrSicknessTargetUntil", "debugCommonColdStage4GraceUntil",
    "debugForcedStageAt",
}

local WOUND_PART_TIME_FIELDS = {
    "startTime", "stageStartTime", "vanillaClearedTime", "lastSepsisTrigger",
}

local WOUND_INCUBATION_TIME_FIELDS = {
    "detectedTime", "vanillaClearedTime",
}

local MEDICATION_TREATMENT_TIME_FIELDS = { "startTime" }
local MEDICATION_DOSE_TIME_FIELDS = { "startTime", "firstDoseTime", "lastDoseTime" }
local MEDICATION_SIDE_EFFECT_TIME_FIELDS = { "startTime", "lastThirstHour", "lastBathroomHour" }
local MEDICATION_GENERAL_EFFECT_TIME_FIELDS = {
    "startTime", "endTime", "lastUpdateHour", "lastTemperatureUpdateHour",
}

local function log(message)
    if EHR and EHR.Log then EHR.Log(message) else print("[EHR] " .. tostring(message)) end
end

local function worldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime or not gameTime.getWorldAgeHours then return nil end
    local ok, value = pcall(function() return gameTime:getWorldAgeHours() end)
    return ok and tonumber(value) or nil
end

local function realSeconds()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return tonumber(value) / 1000 end
    end
    if os and os.time then
        local ok, value = pcall(os.time)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return nil
end

local function isAlivePlayer(player)
    if not player then return false end
    if not player.isAlive then return true end
    local ok, alive = pcall(function() return player:isAlive() end)
    return not ok or alive == true
end

local function newShiftPlan()
    return { entries = {}, seen = {} }
end

local function queueTimeField(plan, container, key)
    if type(plan) ~= "table" or type(container) ~= "table" then return end
    local value = tonumber(container[key])
    if value == nil or value ~= value then return end

    local seenForContainer = plan.seen[container]
    if not seenForContainer then
        seenForContainer = {}
        plan.seen[container] = seenForContainer
    elseif seenForContainer[key] then
        return
    end
    seenForContainer[key] = true

    table.insert(plan.entries, { container = container, key = key, value = value })
end

local function queueTimeFields(plan, container, fields)
    if type(container) ~= "table" then return end
    for _, key in ipairs(fields) do queueTimeField(plan, container, key) end
end

local function queueRecordSet(plan, records, fields)
    if type(records) ~= "table" then return end
    for _, record in pairs(records) do queueTimeFields(plan, record, fields) end
end

local function queueMedicationClocks(plan, medication)
    if type(medication) ~= "table" then return end
    queueRecordSet(plan, medication.activeTreatments, MEDICATION_TREATMENT_TIME_FIELDS)
    queueRecordSet(plan, medication.activeDoses, MEDICATION_DOSE_TIME_FIELDS)
    queueRecordSet(plan, medication.activeSideEffects, MEDICATION_SIDE_EFFECT_TIME_FIELDS)
    queueRecordSet(plan, medication.activeGeneralEffects, MEDICATION_GENERAL_EFFECT_TIME_FIELDS)
end

local function buildShiftPlan(modData, skipMedication)
    local plan = newShiftPlan()
    if type(modData) ~= "table" then return plan end

    local diseases = type(modData.EHR_Disease) == "table" and modData.EHR_Disease.active or nil
    queueRecordSet(plan, diseases, DISEASE_TIME_FIELDS)

    local wounds = type(modData.EHR_WoundInfection) == "table" and modData.EHR_WoundInfection or nil
    if wounds then
        queueRecordSet(plan, wounds.parts, WOUND_PART_TIME_FIELDS)
        queueRecordSet(plan, wounds.incubating, WOUND_INCUBATION_TIME_FIELDS)
    end

    local sepsis = type(modData.EHR_Sepsis) == "table" and modData.EHR_Sepsis or nil
    if sepsis and (sepsis.active == true or (tonumber(sepsis.stage) or 0) > 0) then
        queueTimeFields(plan, sepsis, { "startTime", "stageStartTime", "lastHealthDamageHour" })
    end

    local medication = type(modData.EHR_Medication) == "table" and modData.EHR_Medication or nil
    if not skipMedication then queueMedicationClocks(plan, medication) end

    queueTimeFields(plan, modData.EHR_Concussion, { "cooldownUntil" })

    local temperature = type(modData.EHR_Temperature) == "table" and modData.EHR_Temperature or nil
    if temperature then
        queueTimeFields(plan, temperature, { "lastUpdateHour", "diseaseTargetTempUntil" })
    end

    return plan
end

local function applyShiftPlan(plan, gapHours)
    local gap = tonumber(gapHours) or 0
    if gap <= 0 then return 0 end
    local shifted = 0
    for _, entry in ipairs(plan.entries) do
        entry.container[entry.key] = entry.value + gap
        shifted = shifted + 1
    end
    return shifted
end

function Offline.ShiftPlayerState(player, gapHours)
    if not player or not player.getModData then return 0 end
    local gap = tonumber(gapHours) or 0
    if gap <= Offline.MIN_GAP_HOURS then return 0 end
    local modData = player:getModData()
    if type(modData) ~= "table" then return 0 end
    return applyShiftPlan(buildShiftPlan(modData), gap)
end

local function setFreshMarker(modData, currentHour)
    modData[Offline.MARKER_KEY] = { version = Offline.VERSION, lastSeenWorldHour = currentHour }
    return modData[Offline.MARKER_KEY]
end

function Offline.HandlePlayerConnected(player, currentHour)
    if not player or not player.getModData then return false, 0, "no_player" end
    local now = tonumber(currentHour) or worldHour()
    if now == nil then return false, 0, "no_world_time" end

    if onlineSessions[player] then
        Offline.TouchPlayer(player, now)
        return false, 0, "already_online"
    end

    local modData = player:getModData()
    if type(modData) ~= "table" then return false, 0, "no_mod_data" end
    local marker = modData[Offline.MARKER_KEY]
    local savedHour = type(marker) == "table" and tonumber(marker.version) == Offline.VERSION
        and tonumber(marker.lastSeenWorldHour) or nil
    local medication = type(modData.EHR_Medication) == "table" and modData.EHR_Medication or nil
    local medicationHour = medication and tonumber(medication.offlineLastSeenWorldHour) or savedHour
    local gap = savedHour and now - savedHour or 0
    -- The medication anchor travels in the same save/sync table as its clocks.
    -- Prefer it to a missing/older standalone heartbeat; never infer elapsed
    -- offline time from firstDoseTime (which includes legitimate online play).
    local medicationGap = medicationHour and now - medicationHour or 0
    local shifted = gap > Offline.MIN_GAP_HOURS
        and applyShiftPlan(buildShiftPlan(modData, true), gap) or 0
    if medicationGap > Offline.MIN_GAP_HOURS then
        local medicationPlan = newShiftPlan()
        queueMedicationClocks(medicationPlan, medication)
        shifted = shifted + applyShiftPlan(medicationPlan, medicationGap)
    end
    if type(marker) ~= "table" or not savedHour then marker = setFreshMarker(modData, now) end

    marker.version = Offline.VERSION
    marker.lastSeenWorldHour = now
    marker.lastAppliedOfflineHours = math.max(0, gap, medicationGap)
    marker.lastAppliedWorldHour = now
    marker.lastShiftedFieldCount = shifted
    if medication then medication.offlineLastSeenWorldHour = now end
    onlineSessions[player] = true

    if math.max(gap, medicationGap) > Offline.MIN_GAP_HOURS then
        log(string.format("Offline progression frozen for %.2f world hours (%d medical clocks shifted)", math.max(gap, medicationGap), shifted))
    elseif gap < -Offline.MIN_GAP_HOURS then
        log("Offline progression marker was ahead of world time; marker safely reset")
    elseif not savedHour and not medicationHour then
        log("Offline progression marker initialized; legacy offline time was not guessed")
    end
    return shifted > 0, shifted, shifted > 0 and "shifted" or "no_gap"
end

function Offline.EnsureSessionPrepared(player, currentHour)
    local applied, shifted, reason = Offline.HandlePlayerConnected(player, currentHour)
    local prepared = reason ~= "no_player" and reason ~= "no_world_time" and reason ~= "no_mod_data"
    return prepared, applied, shifted, reason
end

function Offline.TouchPlayer(player, currentHour)
    if not player or not player.getModData then return false end
    local now = tonumber(currentHour) or worldHour()
    if now == nil then return false end
    local modData = player:getModData()
    if type(modData) ~= "table" then return false end
    local marker = modData[Offline.MARKER_KEY]
    if type(marker) ~= "table" or tonumber(marker.version) ~= Offline.VERSION then
        marker = setFreshMarker(modData, now)
    else
        marker.lastSeenWorldHour = now
    end
    if type(modData.EHR_Medication) == "table" then
        modData.EHR_Medication.offlineLastSeenWorldHour = now
    end
    return marker ~= nil
end

function Offline.OnCreatePlayer(_, player) Offline.EnsureSessionPrepared(player) end

function Offline.OnPlayerDisconnect(player)
    if not player then return end
    Offline.TouchPlayer(player)
    onlineSessions[player] = nil
end

function Offline.OnPlayerDeath(player)
    if not player or not player.getModData then return end
    onlineSessions[player] = nil
    local modData = player:getModData()
    if type(modData) == "table" then modData[Offline.MARKER_KEY] = nil end
end

function Offline.OnTick()
    heartbeatPollTicks = heartbeatPollTicks + 1
    if heartbeatPollTicks < Offline.HEARTBEAT_POLL_TICKS then return end
    heartbeatPollTicks = 0

    local players = getOnlinePlayers and getOnlinePlayers() or nil
    local now = worldHour()
    if not players or now == nil then return end

    local currentRealSeconds = realSeconds()
    local dueByRealTime = lastHeartbeatRealSeconds == nil
        or currentRealSeconds == nil
        or (currentRealSeconds - lastHeartbeatRealSeconds) >= Offline.HEARTBEAT_REAL_SECONDS
    local dueByWorldTime = lastHeartbeatWorldHour == nil
        or now < lastHeartbeatWorldHour
        or (now - lastHeartbeatWorldHour) >= Offline.HEARTBEAT_WORLD_HOURS
    if not dueByRealTime and not dueByWorldTime then return end

    lastHeartbeatRealSeconds = currentRealSeconds
    lastHeartbeatWorldHour = now

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if isAlivePlayer(player) then
            if not onlineSessions[player] then
                Offline.HandlePlayerConnected(player, now)
            else
                Offline.TouchPlayer(player, now)
            end
        end
    end
end

Offline._eventsRegistered = true
if Events then
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(Offline.OnCreatePlayer) end
    if Events.OnPlayerDisconnect then Events.OnPlayerDisconnect.Add(Offline.OnPlayerDisconnect) end
    if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(Offline.OnPlayerDeath) end
    if Events.OnTick then Events.OnTick.Add(Offline.OnTick) end
end

log("MP offline-progression freeze registered")
