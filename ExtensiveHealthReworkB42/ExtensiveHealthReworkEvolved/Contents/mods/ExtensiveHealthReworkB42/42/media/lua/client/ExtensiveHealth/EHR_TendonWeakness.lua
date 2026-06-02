--[[
    Extensive Health Rework B42
    Tendon weakness side-effect instability

    Client-side stumble/fall episodes for medications that apply the
    tendon_weakness side effect.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Dialogue"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.TendonWeakness = EHR.TendonWeakness or {}

local tableUnpack = unpack or table.unpack

EHR.TendonWeakness.Config = {
    CHECK_INTERVAL_HOURS = 1 / 60,      -- one game minute
    INITIAL_MIN_MINUTES = 5,
    INITIAL_MAX_MINUTES = 12,
    FALL_COOLDOWN_HOURS = 0.5,          -- 30 game minutes

    STANDING_CHANCE = 6,
    WALKING_CHANCE = 22,
    RUNNING_CHANCE = 45,
    SPRINTING_CHANCE = 65,

    TETANUS_FALL_COOLDOWN_HOURS = 0.5,
    TETANUS_FALL_CHANCE = 42,
}

EHR.TendonWeakness.Dialogue = {
    "My leg just gave out...",
    "My tendons feel weak...",
    "I can't trust my legs...",
    "My knees buckled...",
}

EHR.TendonWeakness.TetanusDialogue = {
    "My whole body just seized...",
    "The spasms threw me off balance...",
    "I can't control these cramps...",
    "Everything locked up at once...",
}

EHR.TendonWeakness.State = EHR.TendonWeakness.State or {}

local function getWorldHour()
    local gameTime = getGameTime and getGameTime()
    if not gameTime then return 0 end
    return gameTime:getWorldAgeHours()
end

local function randomMinutesAsHours(minMinutes, maxMinutes)
    return (minMinutes + ZombRand((maxMinutes - minMinutes) + 1)) / 60
end

local function safeBool(obj, methodName)
    if not obj or not methodName or not obj[methodName] then return false end

    local ok, result = pcall(function()
        return obj[methodName](obj)
    end)

    return ok and result == true
end

local function safeCall(obj, methodName, ...)
    if not obj or not methodName or not obj[methodName] then return false end

    local args = { ... }
    local ok = pcall(function()
        obj[methodName](obj, tableUnpack(args))
    end)

    return ok
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
    if safeBool(player, "isDead") then return false end
    if player.isAlive and not safeBool(player, "isAlive") then return false end
    return true
end

function EHR.TendonWeakness.GetState(playerIndex)
    EHR.TendonWeakness.State[playerIndex] = EHR.TendonWeakness.State[playerIndex] or {}
    return EHR.TendonWeakness.State[playerIndex]
end

function EHR.TendonWeakness.IsActive(player)
    if not isPlayerValid(player) then return false end

    local modData = player:getModData()
    if not modData then return false end

    local medData = modData.EHR_Medication
    local activeEffects = medData and medData.activeSideEffects
    local effect = activeEffects and activeEffects.tendon_weakness

    if type(effect) == "table" then
        local currentHour = getWorldHour()
        local startTime = tonumber(effect.startTime) or currentHour
        local duration = tonumber(effect.duration) or 0

        if duration > 0 and currentHour < startTime + duration then
            modData.EHR_TendonWeakness = true
            return true
        end

        activeEffects.tendon_weakness = nil
    end

    -- Old debug tools can remove the side effect table without running onEnd.
    if modData.EHR_TendonWeakness then
        modData.EHR_TendonWeakness = nil
    end

    return false
end

function EHR.TendonWeakness.IsTetanusFallActive(player)
    if not isPlayerValid(player) then return false end

    local modData = player:getModData()
    local diseaseData = modData and modData.EHR_Disease
    local tetanus = diseaseData and diseaseData.active and diseaseData.active.tetanus
    if not tetanus then return false end

    local stage = tonumber(tetanus.stage) or 1
    if stage ~= 3 then return false end

    if EHR.Disease and EHR.Disease.HasActiveCurativeTreatment
        and EHR.Disease.HasActiveCurativeTreatment(player, "tetanus") then
        return false
    end

    if EHR.Disease and EHR.Disease.GetActiveSymptomReduction then
        local muscleRelief = EHR.Disease.GetActiveSymptomReduction(player, "tetanus", "muscleSpasms") or 0
        if muscleRelief >= 0.65 then return false end
    end

    return true
end

function EHR.TendonWeakness.GetMovementState(player)
    if safeBool(player, "isSprinting") then return "sprinting" end
    if safeBool(player, "isRunning") or safeBool(player, "IsRunning") then return "running" end
    if safeBool(player, "isPlayerMoving") then return "walking" end
    return "standing"
end

function EHR.TendonWeakness.GetFallChance(movementState)
    local cfg = EHR.TendonWeakness.Config

    if movementState == "sprinting" then return cfg.SPRINTING_CHANCE end
    if movementState == "running" then return cfg.RUNNING_CHANCE end
    if movementState == "walking" then return cfg.WALKING_CHANCE end
    return cfg.STANDING_CHANCE
end

function EHR.TendonWeakness.CanFall(player)
    if not isPlayerValid(player) then return false end

    if safeBool(player, "isAsleep") then return false end
    if safeBool(player, "isClimbing") then return false end
    if safeBool(player, "isKnockedDown") then return false end
    if safeBool(player, "isOnFloor") then return false end
    if safeBool(player, "isSitOnGround") then return false end
    if safeBool(player, "isSittingOnFurniture") then return false end
    if safeBool(player, "isBumped") then return false end

    local okVehicle, vehicle = pcall(function() return player:getVehicle() end)
    if okVehicle and vehicle then return false end

    return true
end

function EHR.TendonWeakness.SayFallLine(player, state)
    if not player or not player.Say then return end

    local lines = EHR.TendonWeakness.Dialogue
    if not lines or #lines == 0 then return end

    local index = ZombRand(#lines) + 1
    if #lines > 1 and state and state.lastLineIndex == index then
        index = (index % #lines) + 1
    end
    if state then state.lastLineIndex = index end

    local line = lines[index]
    if EHR.Dialogue and EHR.Dialogue.SayPeriodic then
        EHR.Dialogue.SayPeriodic(player, line, 1)
    else
        EHR.Locale.Say(player, line)
    end
end

function EHR.TendonWeakness.SayTetanusFallLine(player, state)
    if not player or not player.Say then return end

    local lines = EHR.TendonWeakness.TetanusDialogue
    if not lines or #lines == 0 then return end

    local index = ZombRand(#lines) + 1
    if #lines > 1 and state and state.lastTetanusLineIndex == index then
        index = (index % #lines) + 1
    end
    if state then state.lastTetanusLineIndex = index end

    local line = lines[index]
    if EHR.Dialogue and EHR.Dialogue.SayPeriodic then
        EHR.Dialogue.SayPeriodic(player, line, 1)
    else
        EHR.Locale.Say(player, line)
    end
end

function EHR.TendonWeakness.GetBumpFallType(movementState)
    if movementState == "running" or movementState == "sprinting" then
        return "pushedBehind"
    end
    return "pushedFront"
end

function EHR.TendonWeakness.TriggerFall(player, movementState)
    if not EHR.TendonWeakness.CanFall(player) then return false end

    local bumpFallType = EHR.TendonWeakness.GetBumpFallType(movementState)

    if player.setBumpType and player.setVariable then
        local ok = pcall(function()
            player:setBumpType("stagger")
            player:setVariable("BumpDone", false)
            player:setVariable("BumpFall", true)
            player:setVariable("BumpFallType", bumpFallType)
        end)
        if ok and bumpFallType == "pushedBehind" then
            safeCall(player, "setFallOnFront", true)
        end
        if ok then return true end
    end

    if bumpFallType == "pushedBehind" then
        safeCall(player, "setFallOnFront", true)
    end
    if safeCall(player, "setKnockedDown", true) then return true end
    if safeCall(player, "setFallOnFront", true) then return true end

    return false
end

function EHR.TendonWeakness.ResetState(state)
    state.active = false
    state.nextCheckHour = nil
    state.nextAllowedFallHour = nil
end

function EHR.TendonWeakness.UpdateTetanusFalls(player, state, currentHour)
    if not state then return end

    if not EHR.TendonWeakness.IsTetanusFallActive(player) then
        state.tetanusNextAllowedFallHour = nil
        return
    end

    if not state.tetanusNextAllowedFallHour then
        state.tetanusNextAllowedFallHour = currentHour + randomMinutesAsHours(4, 10)
        return
    end

    if currentHour < state.tetanusNextAllowedFallHour then return end
    if not EHR.TendonWeakness.CanFall(player) then return end

    local fallChance = EHR.TendonWeakness.Config.TETANUS_FALL_CHANCE
    if EHR.Disease and EHR.Disease.GetActiveSymptomReduction then
        local muscleRelief = EHR.Disease.GetActiveSymptomReduction(player, "tetanus", "muscleSpasms") or 0
        fallChance = math.floor(fallChance * math.max(0.20, 1 - (muscleRelief * 1.4)))
    end

    if ZombRand(100) >= fallChance then
        state.tetanusNextAllowedFallHour = currentHour + EHR.TendonWeakness.Config.TETANUS_FALL_COOLDOWN_HOURS
        return
    end

    -- Use the standing bump profile: this is the backward fall animation, not the running face-forward one.
    if EHR.TendonWeakness.TriggerFall(player, "standing") then
        state.tetanusNextAllowedFallHour = currentHour + EHR.TendonWeakness.Config.TETANUS_FALL_COOLDOWN_HOURS
        EHR.TendonWeakness.SayTetanusFallLine(player, state)
        EHR.Log("TendonWeakness: triggered tetanus backward fall")
    end
end

function EHR.TendonWeakness.UpdatePlayer(player, playerIndex, currentHour)
    local state = EHR.TendonWeakness.GetState(playerIndex)
    EHR.TendonWeakness.UpdateTetanusFalls(player, state, currentHour)

    if not EHR.TendonWeakness.IsActive(player) then
        if state.active then
            EHR.TendonWeakness.ResetState(state)
        end
        return
    end

    if not state.active then
        state.active = true
        state.nextCheckHour = currentHour
        state.nextAllowedFallHour = currentHour + randomMinutesAsHours(
            EHR.TendonWeakness.Config.INITIAL_MIN_MINUTES,
            EHR.TendonWeakness.Config.INITIAL_MAX_MINUTES
        )
        return
    end

    if currentHour < (state.nextCheckHour or 0) then return end
    state.nextCheckHour = currentHour + EHR.TendonWeakness.Config.CHECK_INTERVAL_HOURS

    if currentHour < (state.nextAllowedFallHour or 0) then return end
    if not EHR.TendonWeakness.CanFall(player) then return end

    local movementState = EHR.TendonWeakness.GetMovementState(player)
    local fallChance = EHR.TendonWeakness.GetFallChance(movementState)

    if ZombRand(100) >= fallChance then return end

    if EHR.TendonWeakness.TriggerFall(player, movementState) then
        state.nextAllowedFallHour = currentHour + EHR.TendonWeakness.Config.FALL_COOLDOWN_HOURS
        EHR.TendonWeakness.SayFallLine(player, state)
        EHR.Log("TendonWeakness: triggered fall (" .. tostring(movementState) .. ")")
    end
end

function EHR.TendonWeakness.OnTick()
    local currentHour = getWorldHour()

    for i = 0, getLocalPlayerCount() - 1 do
        local player = getSpecificPlayer and getSpecificPlayer(i) or nil
        local playerIndex = getPlayerIndex(player, i)
        EHR.TendonWeakness.UpdatePlayer(player, playerIndex, currentHour)
    end
end

function EHR.TendonWeakness.OnPlayerDeath(player)
    local playerIndex = getPlayerIndex(player, 0)
    EHR.TendonWeakness.State[playerIndex] = nil
end

if Events then
    Events.OnTick.Add(EHR.TendonWeakness.OnTick)
    if Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(EHR.TendonWeakness.OnPlayerDeath)
    end
end

EHR.Log("TendonWeakness module loaded")
