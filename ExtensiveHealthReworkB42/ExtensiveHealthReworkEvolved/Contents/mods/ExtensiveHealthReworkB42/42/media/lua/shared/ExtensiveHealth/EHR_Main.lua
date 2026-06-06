--[[
    Extensive Health Rework B42
    Main Module - Entry Point

    Clean rewrite - minimal and testable
]]--

EHR = EHR or {}
require "ExtensiveHealth/EHR_Localization"
EHR.VERSION = "2.8.1"  -- Temperature rework, blood spoilage, MP fixes, Lifestyle compat improvements

-- Debug flag - default value (overridden by sandbox setting)
EHR.DEBUG = false
-- Temporary focused debug for wound disinfect flow. Set to false to silence.
EHR.DISINFECT_DEBUG = true

-- ============================================
-- DEATH CAUSE TRACKING (for debugging mystery deaths)
-- ============================================
EHR.DeathTracking = {
    lastCause = nil,       -- Last recorded death cause
    timestamp = nil,       -- When it was set
    playerName = nil,      -- Which player
}

--[[
    Record a death cause before killing the player
    Call this BEFORE setting health to 0 or killing
    @param player - The player about to die
    @param cause - String describing the cause (e.g. "Hemodilution - 65% saline ratio")
]]--
function EHR.RecordDeathCause(player, cause)
    if not player then return end

    local playerName = "Unknown"
    pcall(function() playerName = player:getUsername() or ("Player " .. player:getPlayerNum()) end)

    EHR.DeathTracking.lastCause = cause
    EHR.DeathTracking.timestamp = os.time()
    EHR.DeathTracking.playerName = playerName

    -- Always log death cause
    print("[EHR DEATH] Player: " .. playerName .. " | Cause: " .. tostring(cause))
    EHR.Log("DEATH RECORDED: " .. playerName .. " - " .. tostring(cause))

    -- Store in player modData for persistence
    local modData = player:getModData()
    if modData then
        modData.EHR_DeathCause = cause
        modData.EHR_DeathTime = os.time()
    end
end

--[[
    Get the last recorded death cause for a player
]]--
function EHR.GetDeathCause(player)
    if player then
        local modData = player:getModData()
        if modData and modData.EHR_DeathCause then
            return modData.EHR_DeathCause
        end
    end
    return EHR.DeathTracking.lastCause or "Unknown (not tracked by EHR)"
end

local function EHR_DeathSnapshotTry(fn, default)
    local ok, value = pcall(fn)
    if ok then return value end
    return default
end

local function EHR_DeathSnapshotNum(value, decimals)
    local num = tonumber(value)
    if not num then return "?" end
    decimals = decimals or 2
    return string.format("%." .. tostring(decimals) .. "f", num)
end

local function EHR_DeathSnapshotBodyPartName(bodyPart)
    if not bodyPart then return "UnknownPart" end
    local partType = EHR_DeathSnapshotTry(function() return bodyPart:getType() end, nil)
    if BodyPartType and BodyPartType.getDisplayName and partType then
        return EHR_DeathSnapshotTry(function() return BodyPartType.getDisplayName(partType) end, tostring(partType))
    end
    return tostring(partType or "UnknownPart")
end

local function EHR_DeathSnapshotBodyPartFlag(bodyPart, methodName)
    return EHR_DeathSnapshotTry(function()
        local method = bodyPart and bodyPart[methodName]
        if method then return method(bodyPart) end
        return false
    end, false) == true
end

local function EHR_DeathSnapshotBodyPartNum(bodyPart, methodName, default)
    return tonumber(EHR_DeathSnapshotTry(function()
        local method = bodyPart and bodyPart[methodName]
        if method then return method(bodyPart) end
        return default
    end, default)) or default
end

local function EHR_PrintDeathSnapshot(player)
    if not player then return end

    print("[EHR] ---- Death Snapshot ----")

    local modData = EHR_DeathSnapshotTry(function() return player:getModData() end, nil)
    local bodyDamage = EHR_DeathSnapshotTry(function() return player:getBodyDamage() end, nil)
    local stats = EHR_DeathSnapshotTry(function() return player:getStats() end, nil)

    if bodyDamage then
        print("[EHR] BodyDamage: overallHealth=" ..
            EHR_DeathSnapshotNum(EHR_DeathSnapshotTry(function() return bodyDamage:getOverallBodyHealth() end, nil), 2))
    end

    if stats and CharacterStat then
        local statNames = {
            "SICKNESS", "FOOD_SICKNESS", "TEMPERATURE", "THIRST", "HUNGER",
            "FATIGUE", "ENDURANCE", "PAIN", "STRESS", "PANIC", "WETNESS"
        }
        local parts = {}
        for _, statName in ipairs(statNames) do
            local stat = CharacterStat[statName]
            if stat then
                local value = EHR_DeathSnapshotTry(function() return stats:get(stat) end, nil)
                if value ~= nil then
                    table.insert(parts, statName .. "=" .. EHR_DeathSnapshotNum(value, 3))
                end
            end
        end
        print("[EHR] CharacterStats: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    end

    if modData and modData.EHR_Blood then
        local blood = modData.EHR_Blood
        print("[EHR] Blood: volume=" .. EHR_DeathSnapshotNum(blood.currentVolume, 0) ..
            "/" .. EHR_DeathSnapshotNum(blood.maxVolume, 0) ..
            " type=" .. tostring(blood.bloodType) ..
            " saline=" .. EHR_DeathSnapshotNum(blood.transfusedSaline or 0, 0) ..
            " salineRatio=" .. EHR_DeathSnapshotNum((tonumber(blood.salineRatio) or 0) * 100, 1) .. "%" ..
            " bleeding=" .. tostring(blood.isCurrentlyBleeding) ..
            " lossRate=" .. EHR_DeathSnapshotNum(blood.lossRate or 0, 2))
    end

    if modData and modData.EHR_Disease and modData.EHR_Disease.active then
        local activeLines = {}
        for diseaseId, disease in pairs(modData.EHR_Disease.active) do
            if type(disease) == "table" then
                table.insert(activeLines, tostring(diseaseId) ..
                    "(stage=" .. tostring(disease.stage) ..
                    ", progress=" .. EHR_DeathSnapshotNum(disease.progress or 0, 2) ..
                    ", severity=" .. EHR_DeathSnapshotNum(disease.severity or 0, 2) ..
                    ", treated=" .. tostring(disease.treated) .. ")")
            else
                table.insert(activeLines, tostring(diseaseId) .. "=" .. tostring(disease))
            end
        end
        print("[EHR] Active diseases: " .. (#activeLines > 0 and table.concat(activeLines, "; ") or "none"))
    end

    if modData and modData.EHR_Medication then
        local med = modData.EHR_Medication
        local doseLines = {}
        if type(med.activeDoses) == "table" then
            for medKey, dose in pairs(med.activeDoses) do
                if type(dose) == "table" then
                    table.insert(doseLines, tostring(medKey) ..
                        "(dose=" .. tostring(dose.doseCount) .. "/" .. tostring(dose.totalDosesNeeded) ..
                        ", target=" .. tostring(dose.treatingDisease) .. ")")
                else
                    table.insert(doseLines, tostring(medKey))
                end
            end
        end
        local sideLines = {}
        if type(med.activeSideEffects) == "table" then
            for effectId, effectData in pairs(med.activeSideEffects) do
                table.insert(sideLines, tostring(effectId) ..
                    (type(effectData) == "table" and ("(" .. tostring(effectData.duration) .. "h)") or ""))
            end
        end
        print("[EHR] Active medication doses: " .. (#doseLines > 0 and table.concat(doseLines, "; ") or "none"))
        print("[EHR] Active side effects: " .. (#sideLines > 0 and table.concat(sideLines, "; ") or "none"))
    end

    if modData and modData.EHR_Sepsis then
        print("[EHR] Sepsis data: active=" .. tostring(modData.EHR_Sepsis.active) ..
            " stage=" .. tostring(modData.EHR_Sepsis.stage) ..
            " progress=" .. EHR_DeathSnapshotNum(modData.EHR_Sepsis.progress or 0, 2) ..
            " treated=" .. tostring(modData.EHR_Sepsis.treated))
    end

    if modData and modData.EHR_WoundInfection and modData.EHR_WoundInfection.parts then
        local woundLines = {}
        for partName, woundData in pairs(modData.EHR_WoundInfection.parts) do
            if type(woundData) == "table" then
                table.insert(woundLines, tostring(partName) ..
                    "(stage=" .. tostring(woundData.stage) ..
                    ", progress=" .. EHR_DeathSnapshotNum(woundData.progress or 0, 2) ..
                    ", treated=" .. tostring(woundData.treated) .. ")")
            end
        end
        print("[EHR] Wound infection parts: " .. (#woundLines > 0 and table.concat(woundLines, "; ") or "none"))
    end

    if bodyDamage then
        local bodyParts = EHR_DeathSnapshotTry(function() return bodyDamage:getBodyParts() end, nil)
        local woundLines = {}
        if bodyParts and bodyParts.size and bodyParts.get then
            local count = EHR_DeathSnapshotTry(function() return bodyParts:size() end, 0) or 0
            for i = 0, count - 1 do
                local bodyPart = EHR_DeathSnapshotTry(function() return bodyParts:get(i) end, nil)
                if bodyPart then
                    local health = EHR_DeathSnapshotBodyPartNum(bodyPart, "getHealth", 100)
                    local pain = EHR_DeathSnapshotBodyPartNum(bodyPart, "getAdditionalPain", 0)
                    local stiff = EHR_DeathSnapshotBodyPartNum(bodyPart, "getStiffness", 0)
                    local woundInfection = EHR_DeathSnapshotBodyPartNum(bodyPart, "getWoundInfectionLevel", 0)
                    local flags = {}
                    local flagMethods = {
                        bleeding = "bleeding",
                        bandaged = "bandaged",
                        infected = "isInfectedWound",
                        bite = "bitten",
                        scratch = "scratched",
                        cut = "isCut",
                        deep = "deepWounded",
                        glass = "haveGlass",
                        bullet = "haveBullet",
                    }
                    for label, methodName in pairs(flagMethods) do
                        if EHR_DeathSnapshotBodyPartFlag(bodyPart, methodName) then
                            table.insert(flags, label)
                        end
                    end
                    local fracture = EHR_DeathSnapshotBodyPartNum(bodyPart, "getFractureTime", 0)
                    local burn = EHR_DeathSnapshotBodyPartNum(bodyPart, "getBurnTime", 0)
                    if fracture > 0 then table.insert(flags, "fracture=" .. EHR_DeathSnapshotNum(fracture, 1)) end
                    if burn > 0 then table.insert(flags, "burn=" .. EHR_DeathSnapshotNum(burn, 1)) end
                    if health < 99 or pain > 0 or stiff > 0 or woundInfection > 0 or #flags > 0 then
                        table.insert(woundLines, EHR_DeathSnapshotBodyPartName(bodyPart) ..
                            "(hp=" .. EHR_DeathSnapshotNum(health, 1) ..
                            ", pain=" .. EHR_DeathSnapshotNum(pain, 1) ..
                            ", stiff=" .. EHR_DeathSnapshotNum(stiff, 1) ..
                            ", inf=" .. EHR_DeathSnapshotNum(woundInfection, 1) ..
                            ", flags=" .. (#flags > 0 and table.concat(flags, "|") or "none") .. ")")
                    end
                end
            end
        end
        print("[EHR] Body part issues: " .. (#woundLines > 0 and table.concat(woundLines, "; ") or "none"))
    end

    print("[EHR] ---- End Death Snapshot ----")
end

--[[
    Player death handler - shows death cause and resets state
]]--
function EHR.OnPlayerDeath(player)
    if not player then return end

    local cause = EHR.GetDeathCause(player)
    local playerName = "Unknown"
    pcall(function() playerName = player:getUsername() or ("Player " .. player:getPlayerNum()) end)

    local playerID = tostring(player:getUsername() or player:getPlayerNum())

    local modData = player:getModData()
    if modData then
        modData.EHR_DeadCharacter = true
    end

    -- Print to console for debugging
    print("=====================================")
    print("[EHR] PLAYER DEATH REPORT")
    print("[EHR] Player: " .. playerName)
    print("[EHR] Cause: " .. tostring(cause))
    print("[EHR] Time: " .. os.date("%Y-%m-%d %H:%M:%S"))
    EHR_PrintDeathSnapshot(player)
    print("=====================================")

    -- CRITICAL: Reset all player-specific state
    EHR.ResetPlayerState(playerID)

    -- CRITICAL: Reset lockedHealth for this player
    if EHR.ResetLockedHealth then
        EHR.ResetLockedHealth(playerID)
    end

    -- CRITICAL: Reset blood debug counters
    if EHR.ResetBloodDebugCounters then
        EHR.ResetBloodDebugCounters()
    end

    -- CRITICAL: Reset hook flags so they re-apply on new character
    EHR.ResetHooks()

    -- Clear death tracking for next death
    EHR.DeathTracking.lastCause = nil
end

-- Get debug mode from sandbox (with default)
function EHR.IsDebugMode()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local debugSetting = SandboxVars.ExtensiveHealthRework.DebugMode
        if debugSetting ~= nil then
            return debugSetting
        end
    end
    return EHR.DEBUG
end

function EHR.IsVerboseLoggingEnabled()
    if EHR.VerboseLogging == true or EHR.DEBUG_LOGGING == true then
        return true
    end

    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local sandbox = SandboxVars.ExtensiveHealthRework
        if sandbox.VerboseLogging ~= nil then
            return sandbox.VerboseLogging == true
        end
        if sandbox.DebugLogging ~= nil then
            return sandbox.DebugLogging == true
        end
    end

    return false
end

function EHR.ShouldLog(message)
    if EHR.IsVerboseLoggingEnabled() then
        return true
    end

    local text = string.lower(tostring(message or ""))
    return string.find(text, "error", 1, true) ~= nil
        or string.find(text, "warning", 1, true) ~= nil
        or string.find(text, "failed", 1, true) ~= nil
end

-- Quiet by default. Debug menu access should not spam the console every tick.
function EHR.Log(message)
    if EHR.ShouldLog(message) then
        print("[EHR] " .. tostring(message))
    end
end

function EHR.GetItemIconTexture(item)
    if not item then return nil end

    local texture = nil
    local ok, value

    if item.getTex then
        ok, value = pcall(function() return item:getTex() end)
        if ok and value then texture = value end
    end

    if not texture and item.getTexture then
        ok, value = pcall(function() return item:getTexture() end)
        if ok and value then texture = value end
    end

    if not texture and item.getNormalTexture then
        ok, value = pcall(function() return item:getNormalTexture() end)
        if ok and value then texture = value end
    end

    if texture and texture.splitIcon then
        ok, value = pcall(function() return texture:splitIcon() end)
        if ok and value then return value end
    end

    return texture
end

function EHR.SetContextOptionIcon(option, item)
    if not option or not item or option.iconTexture then return option end

    local texture = EHR.GetItemIconTexture and EHR.GetItemIconTexture(item) or nil
    if texture then
        option.iconTexture = texture
    end

    return option
end

--[[
    Initialize player data
    Called when player is created
]]--
function EHR.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if modData.EHR_Initialized then
        EHR.Log("Player already initialized")
        return
    end

    EHR.Log("Initializing player health data...")

    -- BUG FIX: Preserve existing blood type if present (fixes blood type changing on save/load)
    local isDeadCharacterData = modData.EHR_DeadCharacter == true
    local existingBloodType = (not isDeadCharacterData) and modData.EHR_Blood and modData.EHR_Blood.bloodType or nil
    local existingVolume = (not isDeadCharacterData) and modData.EHR_Blood and modData.EHR_Blood.currentVolume or nil

    -- Determine if we're in MP context
    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())
    local isServerContext = isServer()
    local isClientContext = isClient()
    local isDedicatedServer = isServerContext and not isClientContext
    local isMP = isClientContext and not isDedicatedServer

    EHR.Log("InitializePlayer context: isServer=" .. tostring(isServerContext) .. ", isClient=" .. tostring(isClientContext) .. ", isMP=" .. tostring(isMP))
    EHR.Log("Existing blood type: " .. tostring(existingBloodType))

    local bloodType = existingBloodType

    if isMP then
        -- MP CLIENT: Blood type is managed by the SERVER
        -- Set to PENDING if we don't have one - server will send the real one
        if not bloodType or bloodType == "PENDING" then
            bloodType = "PENDING"
            EHR.Log("MP Client: blood type set to PENDING, will receive from server")
        else
            EHR.Log("MP Client: keeping existing blood type: " .. bloodType)
        end
    else
        -- SINGLE PLAYER: Generate blood type locally
        if not bloodType or bloodType == "PENDING" then
            bloodType = EHR.GenerateBloodType()
            EHR.Log("SP: Generated blood type: " .. bloodType)
        else
            EHR.Log("SP: Keeping existing blood type: " .. bloodType)
        end
    end

    modData.EHR_Blood = {
        currentVolume = existingVolume or 5000,  -- mL (preserve if exists, else default)
        maxVolume = 5000,
        bloodType = bloodType,
        lossRate = 0,  -- mL per minute (display only, approximate)
        -- Cumulative tracking fields (v2.7.0+)
        lastBleedTime = 0,      -- Game hour when last bleeding occurred (for regen delay)
        isCurrentlyBleeding = false,  -- True if any wound is actively bleeding
        lossAccumulator = 0,    -- Accumulates fractional blood loss between drains
        lastRegenHour = 0,      -- Game hour of last regeneration (for elapsed time calculation)
    }

    modData.EHR_DeadCharacter = nil
    modData.EHR_Initialized = true
    modData.EHR_Version = EHR.VERSION

    EHR.Log("Player initialized with blood type: " .. modData.EHR_Blood.bloodType)
end

--[[
    Generate random blood type
]]--
function EHR.GenerateBloodType()
    local types = {"O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"}
    local weights = {7, 36, 6, 34, 2, 9, 1, 5}  -- Real-world distribution

    local totalWeight = 0
    for _, w in ipairs(weights) do
        totalWeight = totalWeight + w
    end

    local roll = ZombRand(totalWeight)
    local cumulative = 0

    for i, w in ipairs(weights) do
        cumulative = cumulative + w
        if roll < cumulative then
            return types[i]
        end
    end

    return "O+"  -- Fallback
end

--[[
    Get player mod data (with nil safety)
]]--
function EHR.GetPlayerData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData or not modData.EHR_Initialized then return nil end
    return modData
end

local TICK_INTERVAL = 30  -- Update blood display every 30 ticks (~1 second)
local SYNC_TICK_INTERVAL = 300  -- ~10 seconds

-- MP: Track if we've requested init data from server
local hasRequestedInitData = false
local initDataRequestTick = 0
local initDataRequestAttempts = 0
local INIT_REQUEST_INTERVAL_TICKS = 90  -- ~3 seconds
local MAX_INIT_REQUEST_ATTEMPTS = 5

-- MP: per-player tick state (avoid shared counters across players)
local tickStateByPlayer = {}

-- CRITICAL FIX: Cleanup function to prevent memory leak
-- Called when player logs out or dies to free their tick state
local function cleanupTickState(playerID)
    if playerID and tickStateByPlayer[playerID] then
        tickStateByPlayer[playerID] = nil
        EHR.Log("Cleaned up tickStateByPlayer for: " .. tostring(playerID))
    end
end

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
        state = { tick = 0, sync = 0 }
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

local function handleInitDataRequest(player, data)
    if not player or not data then return end
    if hasRequestedInitData then return end

    local bloodType = data.EHR_Blood and data.EHR_Blood.bloodType
    if bloodType == "PENDING" then
        initDataRequestTick = initDataRequestTick + 1
        if initDataRequestTick == 1 then
            EHR.Log("Blood type is PENDING, will request from server in ~3 seconds...")
        end
        if initDataRequestTick >= INIT_REQUEST_INTERVAL_TICKS then
            initDataRequestTick = 0
            initDataRequestAttempts = initDataRequestAttempts + 1
            if sendClientCommand then
                EHR.Log("====== Requesting init data from server ======")
                EHR.Log("Player: " .. tostring(player:getUsername()))
                EHR.Log("Current blood type: " .. tostring(bloodType))
                sendClientCommand(player, "EHR_Debug", "RequestInitData", {})
                EHR.Log("Request sent!")
                EHR.Log("===============================================")
            else
                EHR.Log("ERROR: sendClientCommand not available!")
            end
            if initDataRequestAttempts >= MAX_INIT_REQUEST_ATTEMPTS then
                hasRequestedInitData = true
                EHR.Log("Init data request attempts exhausted; giving up.")
            end
        end
    elseif bloodType and bloodType ~= "PENDING" then
        if not hasRequestedInitData then
            EHR.Log("Already have valid blood type: " .. tostring(bloodType))
        end
        hasRequestedInitData = true  -- Already have valid blood type
    end
end

function EHR.SyncEHRModDataToClient(player)
    if not player or not sendServerCommand then return false end

    local data = player:getModData()
    if not data then return false end

    sendServerCommand(player, "EHR_Sync", "UpdateModData", {
        EHR_Sepsis = data.EHR_Sepsis,
        EHR_Disease = data.EHR_Disease,
        EHR_Blood = data.EHR_Blood,
        EHR_WoundInfection = data.EHR_WoundInfection,
        EHR_WoundInfections = data.EHR_WoundInfections,
        EHR_Medication = data.EHR_Medication,
        EHR_MedicalJournal = data.EHR_MedicalJournal,
        EHR_Temperature = data.EHR_Temperature,
        EHR_KnownDiseases = data.EHR_KnownDiseases,
        EHR_KnoxHeraldRead = data.EHR_KnoxHeraldRead,
        EHR_KnoxKnowledgeSource = data.EHR_KnoxKnowledgeSource,
        EHR_CorpseSickness = data.EHR_CorpseSickness,
        EHR_KnoxCure = data.EHR_KnoxCure,
    })

    return true
end

function EHR.SafeTransmitModData(player)
    if not player then return false end

    if isServer and isServer() then
        return EHR.SyncEHRModDataToClient(player)
    end

    -- In SP/client contexts the local player modData is already available.
    -- Avoid full transmitModData here: other mods store live client-side state
    -- in the same table, and broad syncs can roll that state backwards.
    return true
end

local function processPlayerTick(player)
    if not player then return end
    if not player:isAlive() then return end

    local data = EHR.GetPlayerData(player)
    if not data then return end

    -- Healing control runs every tick to catch and block vanilla healing
    if EHR.Blood and EHR.Blood.ControlHealing then
        EHR.Blood.ControlHealing(player, data)
    end

    local state = getTickState(player)

    -- Blood volume update runs every ~1 second
    state.tick = state.tick + 1
    if state.tick >= TICK_INTERVAL then
        state.tick = 0

        if EHR.Blood and EHR.Blood.UpdateBloodVolume then
            EHR.Blood.UpdateBloodVolume(player, data)
        end

        -- Effects run less frequently
        if EHR.Blood and EHR.Blood.ApplyEffects then
            EHR.Blood.ApplyEffects(player, data)
        end
    end

    if isServer and isServer() then
        state.sync = state.sync + 1
        if state.sync >= SYNC_TICK_INTERVAL then
            state.sync = 0
            if not EHR.SyncEHRModDataToClient(player) then
                EHR.Log("EHR MP sync skipped: sendServerCommand unavailable")
            end
        end
    end
end

--[[
    Main update loop
    Blood display updates every ~1 second
    Healing control runs every tick to catch vanilla healing
]]--
function EHR.OnTick()
    -- MP: client-only init request flow
    if isClient and isClient() and not (isServer and isServer()) then
        local player = getSpecificPlayer(0)
        if not player or not player:isAlive() then return end
        local data = EHR.GetPlayerData(player)
        if not data then return end
        handleInitDataRequest(player, data)
        return
    end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

--[[
    Player creation handler - ensures clean state before initialization
]]--
function EHR.OnCreatePlayer(playerIndex, player)
    EHR.Log("OnCreatePlayer fired for index " .. playerIndex)

    -- Reset MP request flags for new session
    hasRequestedInitData = false
    initDataRequestTick = 0

    local playerID = tostring(player:getUsername() or player:getPlayerNum())

    -- If this is an existing character (relog), do not wipe persistent data
    -- BUG FIX v2.7.4: Check ALL possible EHR data fields to prevent accidental data wipes
    -- Previously only checked 4 fields - if a player had sepsis/medication/wounds but not those 4, data was wiped!
    local modData = player:getModData()
    local hasExistingData = modData and (
        modData.EHR_Initialized or
        modData.EHR_Blood or
        modData.EHR_Disease or
        modData.EHR_MedicalJournal or
        modData.EHR_Sepsis or
        modData.EHR_WoundInfections or
        modData.EHR_WoundInfection or
        modData.EHR_WoundInfection_V2_Initialized or
        modData.EHR_Medication or
        modData.EHR_Medications or  -- Legacy field
        modData.EHR_Temperature or
        modData.EHR_Corpse or
        modData.EHR_CorpseSickness
    )

    local isDeadCharacterData = modData and modData.EHR_DeadCharacter == true

    if hasExistingData and not isDeadCharacterData then
        EHR.Log("OnCreatePlayer: Existing EHR data found, preserving player state")
        -- Log which fields exist for debugging
        if EHR.DEBUG then
            local fields = {}
            if modData.EHR_Initialized then table.insert(fields, "Initialized") end
            if modData.EHR_Blood then table.insert(fields, "Blood") end
            if modData.EHR_Disease then table.insert(fields, "Disease") end
            if modData.EHR_MedicalJournal then table.insert(fields, "Journal") end
            if modData.EHR_Sepsis then table.insert(fields, "Sepsis") end
            if modData.EHR_WoundInfections then table.insert(fields, "WoundsLegacy") end
            if modData.EHR_WoundInfection then table.insert(fields, "WoundsV2") end
            if modData.EHR_Medication then table.insert(fields, "Medication") end
            if modData.EHR_Temperature then table.insert(fields, "Temperature") end
            if modData.EHR_Corpse then table.insert(fields, "Corpse") end
            if modData.EHR_CorpseSickness then table.insert(fields, "CorpseSickness") end
            EHR.Log("  Found data in: " .. table.concat(fields, ", "))
        end
        EHR.InitializePlayer(player)
        return
    end

    if isDeadCharacterData then
        EHR.Log("OnCreatePlayer: Dead-character EHR data found, forcing fresh blood type roll")
    end

    -- CRITICAL: Log when we're about to wipe data - this helps debug data loss reports
    print("[EHR WARNING] OnCreatePlayer: No existing EHR data found for player " .. playerID .. " - initializing fresh state")

    -- Ensure any stale state is cleared before initialization
    EHR.ResetPlayerState(playerID)
    if EHR.ResetLockedHealth then
        EHR.ResetLockedHealth(playerID)
    end

    -- CRITICAL: Force fresh initialization for new characters
    -- Clear any stale flags that might prevent re-initialization
    -- BUG FIX: Clear ALL EHR modules, not just blood/disease (sepsis was persisting between characters!)
    modData = player:getModData()
    if modData then
        -- Preserve blood type only for the same living character. A newly-created
        -- survivor after death should roll their own blood type.
        local existingBloodType = (not isDeadCharacterData) and modData.EHR_Blood and modData.EHR_Blood.bloodType or nil

        -- Core systems
        modData.EHR_Initialized = nil
        modData.EHR_Blood = nil
        modData.EHR_Blood_Initialized = nil
        modData.EHR_DeadCharacter = nil

        -- Restore blood type if it existed (will be used by InitializePlayer)
        if existingBloodType then
            modData.EHR_Blood = { bloodType = existingBloodType }
            EHR.Log("Preserved blood type: " .. existingBloodType)
        end
        modData.EHR_Disease = nil
        modData.EHR_Disease_Initialized = nil
        modData.EHR_DeathCause = nil

        -- Sepsis system (BUG FIX: Was not being cleared, causing sepsis to persist between characters!)
        modData.EHR_Sepsis = nil
        modData.EHR_Sepsis_Initialized = nil

        -- Wound infections (legacy + V2)
        modData.EHR_WoundInfections = nil
        modData.EHR_WoundInfections_Initialized = nil
        modData.EHR_WoundInfection = nil
        modData.EHR_WoundInfection_V2_Initialized = nil
        modData.EHR_WoundInfection_V2_Migrated = nil

        -- Medication systems
        modData.EHR_Medication = nil   -- Actual medication system
        modData.EHR_Medications = nil  -- Legacy medication data
        modData.EHR_SideEffects = nil  -- Legacy side effects

        -- Other modules
        modData.EHR_Corpse = nil
        modData.EHR_Corpse_Initialized = nil
        modData.EHR_CorpseSickness = nil
        -- NOTE: Do NOT clear EHR_MedicalJournal - it should persist across saves/reloads!

        EHR.Log("Cleared ALL stale modData for new character (sepsis fix)")
    end

    -- Now initialize fresh
    EHR.InitializePlayer(player)
end

--[[
    Game start handler
]]--
function EHR.OnGameStart()
    EHR.Log("=================================")
    EHR.Log("Extensive Health Rework v" .. EHR.VERSION)
    EHR.Log("=================================")

    -- Initialize existing player if game already started
    local player = getSpecificPlayer(0)
    if player then
        EHR.InitializePlayer(player)
    end
end

-- CRITICAL FIX: MP player disconnect handler to prevent memory leak
-- Called when a player disconnects from the server (without dying)
function EHR.OnPlayerDisconnect(player)
    if not player then return end
    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    EHR.Log("Player disconnecting: " .. playerID)
    -- Clean up per-player tick state
    cleanupTickState(playerID)
end

-- Register events
if Events then
    Events.OnTick.Add(EHR.OnTick)
    Events.OnCreatePlayer.Add(EHR.OnCreatePlayer)
    Events.OnGameStart.Add(EHR.OnGameStart)
    -- Death tracking for debugging
    if Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(EHR.OnPlayerDeath)
        EHR.Log("Death tracking registered")
    end
    -- CRITICAL FIX: MP disconnect handler to prevent memory leak
    if Events.OnPlayerDisconnect then
        Events.OnPlayerDisconnect.Add(EHR.OnPlayerDisconnect)
        EHR.Log("Disconnect cleanup registered")
    end
    EHR.Log("Events registered")
end


-- ============================================
-- PLAYER STATE RESET (Called on death/respawn)
-- ============================================

--[[
    Reset all module-level state for a player
    Called on both OnPlayerDeath and OnCreatePlayer to ensure clean slate

    @param playerID - The player identifier to clear (username or playerNum string)
]]--
function EHR.ResetPlayerState(playerID)
    if not playerID then return end

    EHR.Log("=== RESETTING STATE FOR PLAYER: " .. tostring(playerID) .. " ===")

    -- CRITICAL FIX: Clean up per-player tick state to prevent memory leak
    cleanupTickState(playerID)

    -- 1. Reset Blood module state
    if EHR.Blood then
        -- Clear blackout data for this player
        if EHR.Blood.blackoutData then
            EHR.Blood.blackoutData[playerID] = nil
        end

        -- Clear external API flags
        EHR.Blood.AllowHealingOverride = false
        if EHR.Blood.SkipHealingControl then
            EHR.Blood.SkipHealingControl[playerID] = nil
        end
    end

    -- 2. Reset Narcotics compat state
    if EHR.Narcotics and EHR.Narcotics.ResetState then
        EHR.Narcotics.ResetState(playerID)
    end

    EHR.Log("State reset complete for player: " .. tostring(playerID))
end

--[[
    Reset ALL hook initialization flags
    Called when ANY player dies to ensure hooks will re-apply
    This is necessary because hooks modify global action classes
]]--
function EHR.ResetHooks()
    EHR.Log("=== RESETTING HOOK INITIALIZATION FLAGS ===")

    -- Food hook
    if EHR.FoodHook then
        EHR.FoodHook.initialized = false
    end

    -- Wound hook
    if EHR.WoundHook then
        EHR.WoundHook.initialized = false
    end

    -- MiniHealth compat
    if EHR.MiniHealthCompat and EHR.MiniHealthCompat.Reset then
        EHR.MiniHealthCompat.Reset()
    end

    EHR.Log("Hook flags reset complete")
end

--[[
    Reset lockedHealth table (exposed for external reset)
    This will be set by EHR_Blood.lua due to local scope
]]--
EHR.ResetLockedHealth = nil

EHR.Log("Main module loaded")
