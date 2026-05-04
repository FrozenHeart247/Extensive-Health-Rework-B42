--[[
    Extensive Health Rework - Server Commands

    Handles server-side execution of debug menu commands in multiplayer.
    Client sends commands via sendClientCommand, server executes them here.
]]--

-- CRITICAL: This file should ONLY run on the server!
-- If we're on a client, exit immediately
if isClient() then
    return
end

EHR = EHR or {}

local function isEHRDebug()
    if EHR and EHR.IsDebugMode then
        return EHR.IsDebugMode()
    end
    if getDebug then
        return getDebug()
    end
    return false
end

local function log(msg)
    if isEHRDebug() then
        print(msg)
    end
    return
end

log("=========================================")
log("[EHR] EHR_ServerCommands.lua LOADING ON SERVER")
log("[EHR] isServer() = " .. tostring(isServer()))
log("[EHR] isClient() = " .. tostring(isClient()))
log("=========================================")
EHR.ServerCommands = {}

-- ============================================
-- HELPER: Generate blood type (server-authoritative)
-- Uses same distribution as client for consistency
-- ============================================
local function generateBloodType()
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

-- ============================================
-- HELPER: Get or create blood type from GlobalModData (server-side persistent storage)
-- This ensures blood type survives server restarts
-- ============================================
local function getOrCreateBloodType(playerUsername)
    -- GlobalModData persists across server restarts - use it as the authoritative source
    local globalBloodTypes = ModData.getOrCreate("EHR_BloodTypes_Server")

    log("[EHR Server] getOrCreateBloodType for: " .. tostring(playerUsername))
    log("[EHR Server] GlobalModData existing blood type: " .. tostring(globalBloodTypes[playerUsername]))

    if globalBloodTypes[playerUsername] and globalBloodTypes[playerUsername] ~= "PENDING" then
        log("[EHR Server] Returning EXISTING blood type from GlobalModData: " .. globalBloodTypes[playerUsername])
        return globalBloodTypes[playerUsername]
    end

    -- Generate new blood type and store in GlobalModData
    local newBloodType = generateBloodType()
    globalBloodTypes[playerUsername] = newBloodType
    log("[EHR Server] Generated NEW blood type and stored in GlobalModData: " .. newBloodType)

    return newBloodType
end

-- ============================================
-- HELPER: Initialize blood data structure with proper blood type
-- ============================================
local function initializeBloodData(data, playerUsername)
    data.EHR_Blood = data.EHR_Blood or {}
    data.EHR_Blood.maxVolume = data.EHR_Blood.maxVolume or 5000
    data.EHR_Blood.currentVolume = data.EHR_Blood.currentVolume or 5000

    -- CRITICAL: Always get blood type from GlobalModData (authoritative source)
    -- This ensures persistence across reconnects AND server restarts
    if playerUsername then
        local bloodType = getOrCreateBloodType(playerUsername)
        data.EHR_Blood.bloodType = bloodType
        log("[EHR Server] initializeBloodData: Set blood type to " .. bloodType .. " for " .. playerUsername)
    elseif not data.EHR_Blood.bloodType or data.EHR_Blood.bloodType == "PENDING" then
        -- Fallback if no username provided (shouldn't happen)
        data.EHR_Blood.bloodType = generateBloodType()
        log("[EHR Server] initializeBloodData: Generated fallback blood type: " .. data.EHR_Blood.bloodType)
    end

    data.EHR_Blood.transfusedSaline = data.EHR_Blood.transfusedSaline or 0
    data.EHR_Blood.transfusedBlood = data.EHR_Blood.transfusedBlood or 0
    data.EHR_Blood.lastStage = data.EHR_Blood.lastStage or 4
    data.EHR_Blood_Initialized = true
end

-- ============================================
-- HELPER: Wound infection V2 data management
-- ============================================
local function ensureWoundData(data)
    data.EHR_WoundInfection = data.EHR_WoundInfection or {
        parts = {},
        totalInfectedParts = 0,
        worstStage = 0,
        lastCheck = 0,
    }
    return data.EHR_WoundInfection
end

local function recalcWoundStats(woundData)
    if not woundData or not woundData.parts then return end
    local count = 0
    local worst = 0
    for _, partData in pairs(woundData.parts) do
        if partData.stage and partData.stage > 0 then
            count = count + 1
            if partData.stage > worst then
                worst = partData.stage
            end
        end
    end
    woundData.totalInfectedParts = count
    woundData.worstStage = worst
end

local function setWoundStage(data, partName, stage)
    if not partName then return end
    local woundData = ensureWoundData(data)
    local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0

    woundData.parts[partName] = woundData.parts[partName] or {}
    woundData.parts[partName].stage = stage
    woundData.parts[partName].stageStartTime = currentHour
    woundData.parts[partName].startTime = woundData.parts[partName].startTime or currentHour

    recalcWoundStats(woundData)
end

local function clearAllWounds(data)
    local woundData = ensureWoundData(data)
    woundData.parts = {}
    woundData.totalInfectedParts = 0
    woundData.worstStage = 0
    woundData.lastCheck = getGameTime() and getGameTime():getWorldAgeHours() or 0
    data.EHR_WoundInfections = nil
    data.EHR_WoundInfections_Initialized = nil
end

-- ============================================
-- HELPER: Sync ModData to client
-- ============================================
local function syncModDataToClient(player)
    if not player then return end

    local data = player:getModData()

    -- Method 1: Send EHR data directly to client via server command
    if sendServerCommand then
        local ehrData = {
            EHR_Sepsis = data.EHR_Sepsis,
            EHR_Disease = data.EHR_Disease,
            EHR_Blood = data.EHR_Blood,
            EHR_WoundInfection = data.EHR_WoundInfection,
            EHR_WoundInfections = data.EHR_WoundInfections,
            EHR_Medication = data.EHR_Medication,
            EHR_MedicalJournal = data.EHR_MedicalJournal,
            EHR_Temperature = data.EHR_Temperature,  -- MP FIX: Include body temperature in sync
            EHR_KnownDiseases = data.EHR_KnownDiseases,
            EHR_CorpseSickness = data.EHR_CorpseSickness,
        }
        sendServerCommand(player, "EHR_Sync", "UpdateModData", ehrData)
        log("[EHR Server] Sent EHR data to client via sendServerCommand")
    end

    -- Method 2: transmitModData (backup)
    if player.transmitModData then
        pcall(function() player:transmitModData() end)
        log("[EHR Server] ModData transmitted to client")
    end
end

-- ============================================
-- GENERAL COMMANDS
-- ============================================

--[[
    Persist disease knowledge when a flyer is read (MP-safe).
]]--
function EHR.ServerCommands.UnlockDiseaseKnowledge(player, args)
    if not player or not args or not args.diseaseId then return end

    local diseaseId = args.diseaseId
    local data = player:getModData()
    if not data then return end

    data.EHR_KnownDiseases = data.EHR_KnownDiseases or {}
    data.EHR_KnownDiseases[diseaseId] = true

    syncModDataToClient(player)
    log("[EHR Server] Disease knowledge unlocked: " .. tostring(diseaseId))
end

--[[
    Kill a player (server-side) - B42 compatible
]]--
function EHR.ServerCommands.KillPlayer(player, args)
    if not player then return end

    log("[EHR Server] KillPlayer command received for: " .. tostring(player:getUsername()))

    local bodyDamage = player:getBodyDamage()

    -- Method 1: Set overall body health to 0
    if bodyDamage then
        log("[EHR Server] Setting overall body health to 0...")
        pcall(function() bodyDamage:setOverallBodyHealth(0) end)

        -- Damage ALL body parts to 0
        for i = 0, BodyPartType.MAX:index() - 1 do
            local partType = BodyPartType.FromIndex(i)
            if partType then
                local part = bodyDamage:getBodyPart(partType)
                if part then
                    pcall(function() part:setHealth(0) end)
                end
            end
        end
    end

    -- Method 2: Set player health to 0
    log("[EHR Server] Setting player health to 0...")
    pcall(function() player:setHealth(0) end)

    -- Method 3: Try setBodyDamage to max
    if bodyDamage then
        pcall(function() bodyDamage:setInfected(true) end)
        pcall(function() bodyDamage:setInfectionLevel(100) end)
    end

    -- Method 4: Try direct kill methods (B42 may use different names)
    log("[EHR Server] Trying direct kill methods...")

    -- Try various kill method names
    local killMethods = {"Kill", "Die", "kill", "die", "doKill", "doDeath", "setDead"}
    for _, methodName in ipairs(killMethods) do
        if player[methodName] then
            log("[EHR Server] Found method: " .. methodName)
            pcall(function() player[methodName](player) end)
        end
    end

    -- Method 5: Zombification (usually guarantees death)
    log("[EHR Server] Trying zombification...")
    pcall(function() player:setZombie(true) end)

    -- Method 6: Use the character's become corpse method if available
    pcall(function()
        if player.becomeCorpse then
            player:becomeCorpse()
        end
    end)

    log("[EHR Server] KillPlayer command executed - all methods attempted")
end

--[[
    Full heal a player (server-side)
]]--
function EHR.ServerCommands.FullHeal(player, args)
    if not player then return end

    log("[EHR Server] FullHeal command received for: " .. tostring(player:getUsername()))

    local data = player:getModData()

    -- Reset blood
    if EHR.Blood and EHR.Blood.SetBloodVolume then
        EHR.Blood.SetBloodVolume(player, data.EHR_Blood and data.EHR_Blood.maxVolume or 5000)
    end
    if data.EHR_Blood then
        data.EHR_Blood.transfusedSaline = 0
        data.EHR_Blood.transfusedBlood = 0
    end

    -- Clear diseases
    if EHR.Disease and EHR.Disease.CureAll then
        EHR.Disease.CureAll(player)
    elseif data.EHR_Disease and data.EHR_Disease.active then
        for id, _ in pairs(data.EHR_Disease.active) do
            data.EHR_Disease.active[id] = nil
        end
    end

    -- Clear wound infections
    clearAllWounds(data)

    -- Clear sepsis
    EHR.ServerCommands.ClearSepsis(player, args)

    -- Clear medications
    if data.EHR_Medication then
        if data.EHR_Medication.activeTreatments then
            for id, _ in pairs(data.EHR_Medication.activeTreatments) do
                data.EHR_Medication.activeTreatments[id] = nil
            end
        end
        if data.EHR_Medication.activeDoses then
            for id, _ in pairs(data.EHR_Medication.activeDoses) do
                data.EHR_Medication.activeDoses[id] = nil
            end
        end
        if data.EHR_Medication.activeSideEffects then
            for id, _ in pairs(data.EHR_Medication.activeSideEffects) do
                data.EHR_Medication.activeSideEffects[id] = nil
            end
        end
    end

    -- Heal vanilla body damage
    local bodyDamage = player:getBodyDamage()
    if bodyDamage then
        bodyDamage:RestoreToFullHealth()
    end

    -- Reset stats
    local stats = player:getStats()
    if stats and CharacterStat then
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0)
            stats:set(CharacterStat.THIRST, 0)
            stats:set(CharacterStat.FATIGUE, 0)
            stats:set(CharacterStat.STRESS, 0)
            stats:set(CharacterStat.PAIN, 0)
            stats:set(CharacterStat.PANIC, 0)
            stats:set(CharacterStat.BOREDOM, 0)
            stats:set(CharacterStat.UNHAPPINESS, 0)
            stats:set(CharacterStat.SICKNESS, 0)
            stats:set(CharacterStat.FOOD_SICKNESS, 0)
            stats:set(CharacterStat.POISON, 0)
        end)
    end

    syncModDataToClient(player)
    log("[EHR Server] FullHeal command executed")
end

--[[
    Reset all EHR data for a player (server-side)
]]--
function EHR.ServerCommands.ResetAll(player, args)
    if not player then return end

    log("[EHR Server] ResetAll command received for: " .. tostring(player:getUsername()))

    local data = player:getModData()

    -- Clear all EHR data
    data.EHR_Blood = nil
    data.EHR_Blood_Initialized = nil
    data.EHR_Disease = nil
    data.EHR_Disease_Initialized = nil
    data.EHR_WoundInfection = nil
    data.EHR_WoundInfection_V2_Initialized = nil
    data.EHR_WoundInfection_V2_Migrated = nil
    data.EHR_WoundInfections = nil
    data.EHR_WoundInfections_Initialized = nil
    data.EHR_Sepsis = nil
    data.EHR_Sepsis_Initialized = nil
    data.EHR_Medication = nil
    data.EHR_Medications = nil
    data.EHR_SideEffects = nil
    data.EHR_Corpse = nil
    data.EHR_Corpse_Initialized = nil

    -- Re-initialize
    if EHR and EHR.InitializePlayer then
        EHR.InitializePlayer(player)
    end

    syncModDataToClient(player)
    log("[EHR Server] ResetAll command executed")
end

-- ============================================
-- DISEASE COMMANDS
-- ============================================

--[[
    Cure all diseases (server-side)
]]--
function EHR.ServerCommands.CureAllDiseases(player, args)
    if not player then return end

    log("[EHR Server] CureAllDiseases command received for: " .. tostring(player:getUsername()))

    if EHR.Disease and EHR.Disease.CureAll then
        EHR.Disease.CureAll(player)
    else
        local data = player:getModData()
        if data.EHR_Disease and data.EHR_Disease.active then
            for id, _ in pairs(data.EHR_Disease.active) do
                data.EHR_Disease.active[id] = nil
            end
        end
    end

    syncModDataToClient(player)
    log("[EHR Server] CureAllDiseases command executed")
end

--[[
    Inflict a disease (server-side)

    MP FIX: Always create disease directly instead of relying on Contract()
    because Contract() returns early if player isn't initialized on server.
    This ensures the disease is created and synced properly to the client.
]]--
function EHR.ServerCommands.InflictDisease(player, args)
    if not player then return end
    if not args or not args.diseaseId then return end

    local diseaseId = args.diseaseId
    log("[EHR Server] InflictDisease command received: " .. tostring(diseaseId))

    local data = player:getModData()

    -- Ensure disease data structure exists (may not be initialized on server)
    if not data.EHR_Disease then
        data.EHR_Disease = {
            active = {},
            immunity = { general = 1.0 },
            history = { recoveries = {} },
        }
        data.EHR_Disease_Initialized = true
        log("[EHR Server] Created EHR_Disease structure for player")
    end
    
    -- CRITICAL: Also ensure EHR_Initialized is set, otherwise Medical Monitor won't read data!
    if not data.EHR_Initialized then
        data.EHR_Initialized = true
        log("[EHR Server] Set EHR_Initialized flag")
    end
    data.EHR_Disease.active = data.EHR_Disease.active or {}

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    -- Get disease definition for proper duration, or use defaults
    local duration = 72
    if EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId] then
        local def = EHR.Disease.Diseases[diseaseId]
        duration = def.durationMin + ZombRand(def.durationMax - def.durationMin + 1)
        log("[EHR Server] Using disease definition: duration=" .. duration)
    end

    -- Create disease entry directly (bypasses Contract's initialization check)
    data.EHR_Disease.active[diseaseId] = {
        stage = 2,  -- Start at Early stage (skip incubation for debug)
        severity = 0.5,
        startTime = currentHour,
        endTime = currentHour + duration,
        incubationEnd = currentHour,  -- Already past incubation
        peakTime = currentHour + (duration * 0.4),
        diagnosed = false,
    }

    log("[EHR Server] Created disease: " .. diseaseId .. " duration=" .. duration .. "h")

    syncModDataToClient(player)
    log("[EHR Server] InflictDisease command executed and synced to client")
end

-- ============================================
-- BLOOD COMMANDS
-- ============================================

--[[
    Set blood to a percentage (server-side)
]]--
function EHR.ServerCommands.SetBloodPercent(player, args)
    if not player then return end
    if not args or not args.percent then return end

    local pct = args.percent
    log("[EHR Server] SetBloodPercent command received: " .. tostring(pct) .. "%")

    local data = player:getModData()
    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())

    -- Ensure blood structure is fully initialized with proper blood type
    if not data.EHR_Blood or not data.EHR_Blood.maxVolume then
        initializeBloodData(data, playerUsername)
        log("[EHR Server] Initialized blood data structure")
    end

    -- Also ensure EHR_Initialized for Medical Monitor
    if not data.EHR_Initialized then
        data.EHR_Initialized = true
    end

    local maxVol = data.EHR_Blood.maxVolume
    local newVol = (pct / 100) * maxVol

    if EHR.Blood and EHR.Blood.SetBloodVolume then
        EHR.Blood.SetBloodVolume(player, newVol)
    else
        data.EHR_Blood.currentVolume = newVol
    end

    syncModDataToClient(player)
    log("[EHR Server] SetBloodPercent command executed: " .. pct .. "% = " .. newVol .. "ml")
end

--[[
    Adjust blood by amount (server-side)
]]--
function EHR.ServerCommands.AdjustBlood(player, args)
    if not player then return end
    if not args or not args.amount then return end

    local amount = args.amount
    log("[EHR Server] AdjustBlood command received: " .. tostring(amount))

    local data = player:getModData()
    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())

    -- Ensure blood structure is fully initialized with proper blood type
    if not data.EHR_Blood or not data.EHR_Blood.maxVolume then
        initializeBloodData(data, playerUsername)
        log("[EHR Server] Initialized blood data structure")
    end

    -- Also ensure EHR_Initialized for Medical Monitor
    if not data.EHR_Initialized then
        data.EHR_Initialized = true
    end

    local current = data.EHR_Blood.currentVolume
    local maxVol = data.EHR_Blood.maxVolume
    local newVol = math.max(0, math.min(maxVol, current + amount))

    if EHR.Blood and EHR.Blood.SetBloodVolume then
        EHR.Blood.SetBloodVolume(player, newVol)
    else
        data.EHR_Blood.currentVolume = newVol
    end

    syncModDataToClient(player)
    log("[EHR Server] AdjustBlood command executed: " .. current .. " + " .. amount .. " = " .. newVol)
end

--[[
    Add saline transfusion (server-side)
]]--
function EHR.ServerCommands.AddSaline(player, args)
    if not player then return end

    local amount = args and args.amount or 500
    log("[EHR Server] AddSaline command received: " .. tostring(amount))

    local data = player:getModData()
    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())

    -- Ensure blood structure is fully initialized with proper blood type
    if not data.EHR_Blood or not data.EHR_Blood.maxVolume then
        initializeBloodData(data, playerUsername)
    end
    if not data.EHR_Initialized then data.EHR_Initialized = true end

    data.EHR_Blood.transfusedSaline = data.EHR_Blood.transfusedSaline + amount

    -- Also increase current volume
    local current = data.EHR_Blood.currentVolume
    local maxVol = data.EHR_Blood.maxVolume
    local newVol = math.min(maxVol, current + amount)

    if EHR.Blood and EHR.Blood.SetBloodVolume then
        EHR.Blood.SetBloodVolume(player, newVol)
    else
        data.EHR_Blood.currentVolume = newVol
    end

    syncModDataToClient(player)
    log("[EHR Server] AddSaline command executed")
end

--[[
    Clear transfused saline (server-side)
]]--
function EHR.ServerCommands.ClearSaline(player, args)
    if not player then return end

    log("[EHR Server] ClearSaline command received")

    local data = player:getModData()
    if data.EHR_Blood then
        data.EHR_Blood.transfusedSaline = 0
        data.EHR_Blood.transfusedBlood = 0
    end

    syncModDataToClient(player)
    log("[EHR Server] ClearSaline command executed")
end

--[[
    Trigger blood loss blackout (server-side)
]]--
function EHR.ServerCommands.TriggerBlackout(player, args)
    if not player then return end

    log("[EHR Server] TriggerBlackout command received")

    local data = player:getModData()
    data.EHR_Blood = data.EHR_Blood or {}
    data.EHR_Blood.blackoutTriggered = true
    data.EHR_Blood.blackoutTime = 5

    syncModDataToClient(player)
    log("[EHR Server] TriggerBlackout command executed")
end

-- ============================================
-- WOUND/SEPSIS COMMANDS
-- ============================================

--[[
    Clear sepsis for a player (server-side)
]]--
function EHR.ServerCommands.ClearSepsis(player, args)
    if not player then return end

    log("[EHR Server] ClearSepsis command received for: " .. tostring(player:getUsername()))

    local data = player:getModData()

    -- Use proper API if available
    if EHR.Sepsis and EHR.Sepsis.Cure then
        EHR.Sepsis.Cure(player)
    elseif data.EHR_Sepsis then
        -- Manual clear - all fields
        data.EHR_Sepsis.active = false
        data.EHR_Sepsis.stage = 0
        data.EHR_Sepsis.startTime = nil
        data.EHR_Sepsis.stageStartTime = nil
        data.EHR_Sepsis.sourceBodyPart = nil
        data.EHR_Sepsis.treatmentDoses = 0
        data.EHR_Sepsis.lastIVAntibiotics = nil
        -- Set cure cooldown
        local gameTime = getGameTime()
        if gameTime then
            data.EHR_Sepsis.lastCuredTime = gameTime:getWorldAgeHours()
        end
    end

    -- Downgrade septic wounds
    local woundData = data.EHR_WoundInfection
    if woundData and woundData.parts then
        local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
        for _, partData in pairs(woundData.parts) do
            if partData.stage and partData.stage >= 4 then
                partData.stage = 3
                partData.stageStartTime = currentHour
            end
        end
        recalcWoundStats(woundData)
    end

    -- Sync to client
    syncModDataToClient(player)

    log("[EHR Server] ClearSepsis command executed")
end

--[[
    Trigger sepsis (server-side)
]]--
function EHR.ServerCommands.TriggerSepsis(player, args)
    if not player then return end

    log("[EHR Server] TriggerSepsis command received")

    local data = player:getModData()
    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    -- Create complete sepsis structure directly (bypass API to avoid cooldowns)
    data.EHR_Sepsis = {
        active = true,
        stage = 1,
        startTime = currentHour,
        stageStartTime = currentHour,
        sourceBodyPart = "Debug",
        treatmentDoses = 0,
        lastIVAntibiotics = nil,
        lastCuredTime = nil,
    }
    data.EHR_Sepsis_Initialized = true

    syncModDataToClient(player)
    log("[EHR Server] TriggerSepsis command executed")
end

--[[
    Infect a random wound (server-side)
]]--
function EHR.ServerCommands.InfectRandom(player, args)
    if not player then return end

    log("[EHR Server] InfectRandom command received")

    local data = player:getModData()

    -- Pick a random body part
    local bodyParts = {
        "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R",
        "UpperArm_L", "UpperArm_R", "Foot_L", "Foot_R",
        "LowerLeg_L", "LowerLeg_R", "UpperLeg_L", "UpperLeg_R",
        "Torso_Upper", "Torso_Lower", "Head", "Neck", "Groin"
    }
    local randomPart = bodyParts[ZombRand(#bodyParts) + 1]
    local severity = args and args.severity or ZombRand(1, 4)

    setWoundStage(data, randomPart, severity)

    syncModDataToClient(player)
    log("[EHR Server] InfectRandom command executed: " .. randomPart .. " severity " .. severity)
end

--[[
    Clear all wound infections (server-side)
]]--
function EHR.ServerCommands.ClearAllInfections(player, args)
    if not player then return end

    log("[EHR Server] ClearAllInfections command received")

    local data = player:getModData()
    clearAllWounds(data)

    syncModDataToClient(player)
    log("[EHR Server] ClearAllInfections command executed")
end

-- ============================================
-- MEDICATION COMMANDS
-- ============================================

--[[
    Clear all medications (server-side)
]]--
function EHR.ServerCommands.ClearAllMedications(player, args)
    if not player then return end

    log("[EHR Server] ClearAllMedications command received")

    local data = player:getModData()

    if data.EHR_Medication then
        if data.EHR_Medication.activeTreatments then
            for id, _ in pairs(data.EHR_Medication.activeTreatments) do
                data.EHR_Medication.activeTreatments[id] = nil
            end
        end
        if data.EHR_Medication.activeDoses then
            for id, _ in pairs(data.EHR_Medication.activeDoses) do
                data.EHR_Medication.activeDoses[id] = nil
            end
        end
    end

    -- Also clear legacy data
    if data.EHR_Medications then
        for id, _ in pairs(data.EHR_Medications) do
            data.EHR_Medications[id] = nil
        end
    end

    syncModDataToClient(player)
    log("[EHR Server] ClearAllMedications command executed")
end

--[[
    Clear all side effects (server-side)
]]--
function EHR.ServerCommands.ClearSideEffects(player, args)
    if not player then return end

    log("[EHR Server] ClearSideEffects command received")

    local data = player:getModData()

    if data.EHR_Medication and data.EHR_Medication.activeSideEffects then
        for id, _ in pairs(data.EHR_Medication.activeSideEffects) do
            data.EHR_Medication.activeSideEffects[id] = nil
        end
    end

    -- Also clear legacy data
    if data.EHR_SideEffects then
        for id, _ in pairs(data.EHR_SideEffects) do
            data.EHR_SideEffects[id] = nil
        end
    end

    syncModDataToClient(player)
    log("[EHR Server] ClearSideEffects command executed")
end

--[[
    Apply a medication tier (server-side)
]]--
function EHR.ServerCommands.ApplyMedicationTier(player, args)
    if not player then return end
    if not args or not args.tier then return end

    local tier = args.tier
    log("[EHR Server] ApplyMedicationTier command received: tier " .. tostring(tier))

    local data = player:getModData()
    data.EHR_Medication = data.EHR_Medication or {}
    data.EHR_Medication.activeTreatments = data.EHR_Medication.activeTreatments or {}
    data.EHR_Medication.activeDoses = data.EHR_Medication.activeDoses or {}

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    -- Add a test medication for this tier
    local testMedId = "debug_tier" .. tier .. "_" .. tostring(currentHour)
    data.EHR_Medication.activeTreatments[testMedId] = {
        tier = tier,
        startTime = currentHour,
        duration = 24,
        effectiveness = 0.8,
    }
    data.EHR_Medication.activeDoses[testMedId] = 1

    syncModDataToClient(player)
    log("[EHR Server] ApplyMedicationTier command executed")
end

--[[
    Add a side effect (server-side)
]]--
function EHR.ServerCommands.AddSideEffect(player, args)
    if not player then return end
    if not args or not args.effectId then return end

    local effectId = args.effectId
    log("[EHR Server] AddSideEffect command received: " .. tostring(effectId))

    local data = player:getModData()
    data.EHR_Medication = data.EHR_Medication or {}
    data.EHR_Medication.activeSideEffects = data.EHR_Medication.activeSideEffects or {}

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    data.EHR_Medication.activeSideEffects[effectId] = {
        startTime = currentHour,
        duration = 6,
        severity = 0.5,
    }

    syncModDataToClient(player)
    log("[EHR Server] AddSideEffect command executed")
end

-- ============================================
-- STAT COMMANDS
-- ============================================

--[[
    Set a stat value (server-side)
]]--
function EHR.ServerCommands.SetStat(player, args)
    if not player then return end
    if not args or not args.stat or args.value == nil then return end

    local statName = args.stat
    local value = args.value
    log("[EHR Server] SetStat command received: " .. tostring(statName) .. " = " .. tostring(value))

    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat[statName] then
        pcall(function()
            stats:set(CharacterStat[statName], value)
        end)
    end

    log("[EHR Server] SetStat command executed")
end

--[[
    Adjust a stat by amount (server-side)
]]--
function EHR.ServerCommands.AdjustStat(player, args)
    if not player then return end
    if not args or not args.stat or not args.amount then return end

    local statName = args.stat
    local amount = args.amount
    log("[EHR Server] AdjustStat command received: " .. tostring(statName) .. " += " .. tostring(amount))

    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat[statName] then
        pcall(function()
            local current = stats:get(CharacterStat[statName]) or 0
            stats:set(CharacterStat[statName], math.max(0, math.min(1, current + amount)))
        end)
    end

    log("[EHR Server] AdjustStat command executed")
end

--[[
    Apply "Perfect Health" stat preset (server-side)
]]--
function EHR.ServerCommands.StatPresetPerfect(player, args)
    if not player then return end

    log("[EHR Server] StatPresetPerfect command received")

    local stats = player:getStats()
    if stats and CharacterStat then
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0)
            stats:set(CharacterStat.THIRST, 0)
            stats:set(CharacterStat.FATIGUE, 0)
            stats:set(CharacterStat.PAIN, 0)
            stats:set(CharacterStat.STRESS, 0)
            stats:set(CharacterStat.UNHAPPINESS, 0)
            stats:set(CharacterStat.BOREDOM, 0)
            stats:set(CharacterStat.PANIC, 0)
            stats:set(CharacterStat.SICKNESS, 0)
            stats:set(CharacterStat.POISON, 0)
            stats:set(CharacterStat.FOOD_SICKNESS, 0)
            stats:set(CharacterStat.ENDURANCE, 1)
            stats:set(CharacterStat.WETNESS, 0)
        end)
    end

    log("[EHR Server] StatPresetPerfect command executed")
end

--[[
    Apply "Near Death" stat preset (server-side)
]]--
function EHR.ServerCommands.StatPresetNearDeath(player, args)
    if not player then return end

    log("[EHR Server] StatPresetNearDeath command received")

    local stats = player:getStats()
    if stats and CharacterStat then
        pcall(function()
            stats:set(CharacterStat.HUNGER, 0.95)
            stats:set(CharacterStat.THIRST, 0.95)
            stats:set(CharacterStat.FATIGUE, 0.95)
            stats:set(CharacterStat.PAIN, 0.9)
            stats:set(CharacterStat.STRESS, 0.8)
            stats:set(CharacterStat.UNHAPPINESS, 0.9)
            stats:set(CharacterStat.PANIC, 0.8)
            stats:set(CharacterStat.SICKNESS, 0.7)
            stats:set(CharacterStat.ENDURANCE, 0.05)
        end)
    end

    log("[EHR Server] StatPresetNearDeath command executed")
end

--[[
    Apply "Max Bad" stat preset (server-side)
]]--
function EHR.ServerCommands.StatPresetMaxBad(player, args)
    if not player then return end

    log("[EHR Server] StatPresetMaxBad command received")

    local stats = player:getStats()
    if stats and CharacterStat then
        pcall(function()
            stats:set(CharacterStat.HUNGER, 1)
            stats:set(CharacterStat.THIRST, 1)
            stats:set(CharacterStat.FATIGUE, 1)
            stats:set(CharacterStat.PAIN, 1)
            stats:set(CharacterStat.STRESS, 1)
            stats:set(CharacterStat.UNHAPPINESS, 1)
            stats:set(CharacterStat.BOREDOM, 1)
            stats:set(CharacterStat.PANIC, 1)
            stats:set(CharacterStat.SICKNESS, 1)
            stats:set(CharacterStat.POISON, 1)
            stats:set(CharacterStat.FOOD_SICKNESS, 1)
            stats:set(CharacterStat.ENDURANCE, 0)
            stats:set(CharacterStat.WETNESS, 1)
        end)
    end

    log("[EHR Server] StatPresetMaxBad command executed")
end

-- ============================================
-- SCENARIO COMMANDS
-- ============================================

--[[
    Apply a test scenario (server-side)
]]--
function EHR.ServerCommands.ApplyScenario(player, args)
    if not player then return end
    if not args or not args.scenarioId then return end

    local scenarioId = args.scenarioId
    log("[EHR Server] ApplyScenario command received: " .. tostring(scenarioId))

    local data = player:getModData()
    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    if scenarioId == "severe_blood_loss" then
        -- Set blood to 40%
        data.EHR_Blood = data.EHR_Blood or {}
        local maxVol = data.EHR_Blood.maxVolume or 5000
        if EHR.Blood and EHR.Blood.SetBloodVolume then
            EHR.Blood.SetBloodVolume(player, maxVol * 0.4)
        else
            data.EHR_Blood.currentVolume = maxVol * 0.4
        end

    elseif scenarioId == "early_sepsis" then
        data.EHR_Sepsis = {
            active = true,
            stage = 1,
            startTime = currentHour,
            stageStartTime = currentHour,
            sourceBodyPart = "Debug",
            treatmentDoses = 0,
        }
        setWoundStage(data, "Torso_Upper", 4)

    elseif scenarioId == "late_sepsis" then
        data.EHR_Sepsis = {
            active = true,
            stage = 3,
            startTime = currentHour - 48,
            stageStartTime = currentHour,
            sourceBodyPart = "Debug",
            treatmentDoses = 0,
        }

    elseif scenarioId == "multiple_infections" then
        setWoundStage(data, "Hand_L", 2)
        setWoundStage(data, "ForeArm_R", 3)
        setWoundStage(data, "Torso_Upper", 2)

    elseif scenarioId == "disease_combo" then
        -- MP FIX: Always create directly to avoid Contract() early return
        if not data.EHR_Disease then
            data.EHR_Disease = {
                active = {},
                immunity = { general = 1.0 },
                history = { recoveries = {} },
            }
            data.EHR_Disease_Initialized = true
        end
        data.EHR_Disease.active = data.EHR_Disease.active or {}
        -- CRITICAL: Ensure EHR_Initialized is set for Medical Monitor
        if not data.EHR_Initialized then data.EHR_Initialized = true end

        -- Common cold (72 hour duration)
        data.EHR_Disease.active["common_cold"] = {
            stage = 2,
            severity = 0.5,
            startTime = currentHour,
            endTime = currentHour + 72,
            incubationEnd = currentHour,
            peakTime = currentHour + 28,
            diagnosed = false,
        }
        -- Food poisoning (24 hour duration)
        data.EHR_Disease.active["food_poisoning"] = {
            stage = 2,
            severity = 0.6,
            startTime = currentHour,
            endTime = currentHour + 24,
            incubationEnd = currentHour,
            peakTime = currentHour + 10,
            diagnosed = false,
        }

    elseif scenarioId == "critical_condition" then
        -- Blood at 30%
        data.EHR_Blood = data.EHR_Blood or {}
        local maxVol = data.EHR_Blood.maxVolume or 5000
        if EHR.Blood and EHR.Blood.SetBloodVolume then
            EHR.Blood.SetBloodVolume(player, maxVol * 0.3)
        else
            data.EHR_Blood.currentVolume = maxVol * 0.3
        end
        -- Sepsis stage 2
        data.EHR_Sepsis = {
            active = true,
            stage = 2,
            startTime = currentHour - 24,
            stageStartTime = currentHour,
            sourceBodyPart = "Debug",
            treatmentDoses = 0,
        }
        -- Multiple infections
        setWoundStage(data, "Torso_Upper", 4)
        setWoundStage(data, "UpperLeg_L", 3)
        -- Bad stats
        local stats = player:getStats()
        if stats and CharacterStat then
            pcall(function()
                stats:set(CharacterStat.PAIN, 0.8)
                stats:set(CharacterStat.FATIGUE, 0.7)
                stats:set(CharacterStat.SICKNESS, 0.6)
            end)
        end
    end

    syncModDataToClient(player)
    log("[EHR Server] ApplyScenario command executed: " .. scenarioId)
end

-- ============================================
-- TEST/DEBUG COMMANDS
-- ============================================

--[[
    Simple ping command to verify server commands are working
]]--
function EHR.ServerCommands.Ping(player, args)
    if not player then return end

    local message = args and args.message or "Ping received!"
    log("[EHR Server] PING from " .. tostring(player:getUsername()) .. ": " .. message)

    -- Send a response back to the client
    if sendServerCommand then
        sendServerCommand(player, "EHR_Debug", "Pong", { message = "Server received your ping!" })
    end

    log("[EHR Server] PONG sent back to client")
end

-- Global test function that can be called from server console
function EHR_TestServerCommands()
    log("=========================================")
    log("[EHR] EHR_TestServerCommands() called")
    log("[EHR] EHR.ServerCommands exists: " .. tostring(EHR and EHR.ServerCommands ~= nil))
    log("[EHR] Commands available:")
    if EHR and EHR.ServerCommands then
        for name, func in pairs(EHR.ServerCommands) do
            log("  - " .. name .. " (" .. type(func) .. ")")
        end
    end
    log("=========================================")
end

-- ============================================
-- SERVER COMMAND HANDLER
-- ============================================

local function OnClientCommand(module, command, player, args)
    -- DEBUG: Log ALL incoming commands (even non-EHR ones for diagnostics)
    log("[EHR Server DEBUG] ========== OnClientCommand ==========")
    log("[EHR Server DEBUG] module = '" .. tostring(module) .. "'")
    log("[EHR Server DEBUG] command = '" .. tostring(command) .. "'")
    log("[EHR Server DEBUG] player = " .. tostring(player and player:getUsername() or "nil"))

    -- ============================================
    -- MP ITEM SYNC COMMANDS (any player can use)
    -- ============================================
    if module == "EHR" then
        if command == "RemoveItem" and args and args.itemID then
            -- Find and remove the item from player's inventory
            local inventory = player:getInventory()
            if not inventory then return end

            local items = inventory:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item and item:getID() == args.itemID then
                    inventory:Remove(item)
                    log("[EHR] Server: Synced item removal for " .. player:getUsername())
                    return
                end
            end
        elseif command == "UpdateItemDelta" and args and args.itemID and args.usedDelta then
            -- Sync drainable item usedDelta from client
            local inventory = player:getInventory()
            if not inventory then return end

            local items = inventory:getItems()
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item and item:getID() == args.itemID then
                    local newUsed = math.max(0, math.min(1, args.usedDelta))
                    pcall(function() item:setUsedDelta(newUsed) end)
                    if sendItemStats then
                        pcall(function() sendItemStats(item) end)
                    end
                    log("[EHR] Server: Synced item usedDelta for " .. player:getUsername())
                    return
                end
            end
        elseif command == "TrackMedication" and args and args.medKey then
            -- Sync medication tracking from client (for generic medical items)
            local data = player:getModData()
            if not data then return end

            data.EHR_Medication = data.EHR_Medication or {}
            data.EHR_Medication.activeDoses = data.EHR_Medication.activeDoses or {}

            data.EHR_Medication.activeDoses[args.medKey] = {
                medKey = args.medKey,
                medicationName = args.medicationName,
                tier = args.tier or 0,
                doseCount = args.doseCount or 1,
                totalDosesNeeded = args.totalDosesNeeded or 3,
                intervalHours = args.intervalHours or 6,
                lastDoseTime = args.lastDoseTime,
                startTime = args.lastDoseTime,
            }

            syncModDataToClient(player)
            log("[EHR] Server: Tracked medication " .. args.medKey .. " for " .. player:getUsername())
            return
        elseif command == "RequestSync" then
            -- Client requests immediate sync (after transfusion, medication, etc.)
            syncModDataToClient(player)
            log("[EHR] Server: Sync requested by " .. player:getUsername())
            return
        elseif command == "RequestExamData" then
            -- Client requests another player's EHR data for examination
            -- args.targetUsername = username of player to examine
            if not args or not args.targetUsername then
                log("[EHR] Server: RequestExamData missing targetUsername")
                return
            end

            local targetUsername = args.targetUsername
            local targetPlayer = nil

            -- Find target player by username
            local onlinePlayers = getOnlinePlayers()
            if onlinePlayers then
                for i = 0, onlinePlayers:size() - 1 do
                    local p = onlinePlayers:get(i)
                    if p and p:getUsername() == targetUsername then
                        targetPlayer = p
                        break
                    end
                end
            end

            if not targetPlayer then
                log("[EHR] Server: RequestExamData - target player not found: " .. targetUsername)
                -- Send empty response so client knows request failed
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = targetUsername,
                    success = false,
                    error = "Player not found or offline",
                })
                return
            end

            -- Get target player's EHR data
            local targetData = targetPlayer:getModData()
            if not targetData then
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = targetUsername,
                    success = false,
                    error = "No data available",
                })
                return
            end

            -- Compile EHR data to send
            local examData = {
                targetUsername = targetUsername,
                success = true,
                EHR_Blood = targetData.EHR_Blood,
                EHR_Disease = targetData.EHR_Disease,
                EHR_Sepsis = targetData.EHR_Sepsis,
                EHR_WoundInfection = targetData.EHR_WoundInfection,
                EHR_Medication = targetData.EHR_Medication,
                EHR_MedicalJournal = targetData.EHR_MedicalJournal,
                EHR_Temperature = targetData.EHR_Temperature,
                EHR_CorpseSickness = targetData.EHR_CorpseSickness,
                EHR_Initialized = targetData.EHR_Initialized,
            }

            -- Send data to requesting player
            sendServerCommand(player, "EHR_Exam", "ExamDataResponse", examData)
            log("[EHR] Server: Sent exam data for " .. targetUsername .. " to " .. player:getUsername())
            return
        end
        return
    end

    if module == "EHR_Flyers" then
        if command == "UnlockDisease" then
            EHR.ServerCommands.UnlockDiseaseKnowledge(player, args)
        else
            log("[EHR Server] Unknown EHR_Flyers command: " .. tostring(command))
        end
        return
    end

    if module ~= "EHR_Debug" then
        -- Still log that we received SOMETHING
        return
    end

    log("[EHR Server DEBUG] Module matched! Processing command...")

    -- Allow non-admin commands BEFORE admin check
    -- These commands are safe for any player to use (they only affect their own data)
    if command == "RequestInitData" then
        EHR.ServerCommands.RequestInitData(player, args)
        return
    end

    -- Verify player has admin access for debug/cheat commands
    local accessLevel = player:getAccessLevel() or ""
    local isAdmin = accessLevel == "admin" or accessLevel == "moderator" or accessLevel == "gm" or accessLevel == "observer"

    if not isAdmin then
        log("[EHR Server] Command rejected - player " .. tostring(player:getUsername()) .. " is not admin (level: " .. accessLevel .. ")")
        return
    end

    -- General commands (admin only)
    if command == "KillPlayer" then
        EHR.ServerCommands.KillPlayer(player, args)
    elseif command == "FullHeal" then
        EHR.ServerCommands.FullHeal(player, args)
    elseif command == "ResetAll" then
        EHR.ServerCommands.ResetAll(player, args)

    -- Disease commands
    elseif command == "CureAllDiseases" then
        EHR.ServerCommands.CureAllDiseases(player, args)
    elseif command == "InflictDisease" then
        EHR.ServerCommands.InflictDisease(player, args)

    -- Blood commands
    elseif command == "SetBloodPercent" then
        EHR.ServerCommands.SetBloodPercent(player, args)
    elseif command == "AdjustBlood" then
        EHR.ServerCommands.AdjustBlood(player, args)
    elseif command == "AddSaline" then
        EHR.ServerCommands.AddSaline(player, args)
    elseif command == "ClearSaline" then
        EHR.ServerCommands.ClearSaline(player, args)
    elseif command == "TriggerBlackout" then
        EHR.ServerCommands.TriggerBlackout(player, args)

    -- Wound/Sepsis commands
    elseif command == "ClearSepsis" then
        EHR.ServerCommands.ClearSepsis(player, args)
    elseif command == "TriggerSepsis" then
        EHR.ServerCommands.TriggerSepsis(player, args)
    elseif command == "InfectRandom" then
        EHR.ServerCommands.InfectRandom(player, args)
    elseif command == "ClearAllInfections" then
        EHR.ServerCommands.ClearAllInfections(player, args)

    -- Medication commands
    elseif command == "ClearAllMedications" then
        EHR.ServerCommands.ClearAllMedications(player, args)
    elseif command == "ClearSideEffects" then
        EHR.ServerCommands.ClearSideEffects(player, args)
    elseif command == "ApplyMedicationTier" then
        EHR.ServerCommands.ApplyMedicationTier(player, args)
    elseif command == "AddSideEffect" then
        EHR.ServerCommands.AddSideEffect(player, args)

    -- Stat commands
    elseif command == "SetStat" then
        EHR.ServerCommands.SetStat(player, args)
    elseif command == "AdjustStat" then
        EHR.ServerCommands.AdjustStat(player, args)
    elseif command == "StatPresetPerfect" then
        EHR.ServerCommands.StatPresetPerfect(player, args)
    elseif command == "StatPresetNearDeath" then
        EHR.ServerCommands.StatPresetNearDeath(player, args)
    elseif command == "StatPresetMaxBad" then
        EHR.ServerCommands.StatPresetMaxBad(player, args)

    -- Scenario commands
    elseif command == "ApplyScenario" then
        EHR.ServerCommands.ApplyScenario(player, args)

    -- Test/Debug commands
    elseif command == "Ping" then
        EHR.ServerCommands.Ping(player, args)

    -- Data sync commands
    elseif command == "RequestInitData" then
        EHR.ServerCommands.RequestInitData(player, args)

    else
        log("[EHR Server] Unknown command: " .. tostring(command))
    end
end

--[[
    Handle client request for initialization data (blood type, etc.)
    Called when client has "PENDING" blood type
]]--
function EHR.ServerCommands.RequestInitData(player, args)
    if not player then return end

    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())
    log("[EHR Server] ====== RequestInitData ======")
    log("[EHR Server] Player: " .. playerUsername)

    local data = player:getModData()

    -- CRITICAL: Always use GlobalModData for blood type (ensures persistence)
    -- This will either return existing or generate new
    local bloodType = getOrCreateBloodType(playerUsername)

    -- Initialize blood data with the authoritative blood type
    initializeBloodData(data, playerUsername)

    log("[EHR Server] Blood type for " .. playerUsername .. ": " .. tostring(data.EHR_Blood.bloodType))

    -- Ensure other structures exist
    data.EHR_Initialized = true
    data.EHR_Disease = data.EHR_Disease or { active = {}, immunity = {}, history = { contractions = {}, recoveries = {} } }
    data.EHR_Sepsis = data.EHR_Sepsis or { active = false, stage = 0 }
    ensureWoundData(data)
    data.EHR_Medication = data.EHR_Medication or { activeTreatments = {}, activeDoses = {}, activeSideEffects = {} }
    data.EHR_MedicalJournal = data.EHR_MedicalJournal or { entries = {}, discoveries = {} }
    data.EHR_KnownDiseases = data.EHR_KnownDiseases or {}

    -- Sync to client immediately
    syncModDataToClient(player)
    log("[EHR Server] Sent init data to client with blood type: " .. tostring(data.EHR_Blood.bloodType))
    log("[EHR Server] ============================")
end

-- ============================================
-- SERVER-SIDE PLAYER INITIALIZATION
-- ============================================

--[[
    Initialize player data on server when they connect.
    This ensures blood type is generated server-side and synced to client.
]]--
local function OnServerCreatePlayer(playerIndex, player)
    if not player then return end

    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())
    log("[EHR Server] ====== OnServerCreatePlayer ======")
    log("[EHR Server] Player: " .. playerUsername)
    log("[EHR Server] PlayerIndex: " .. tostring(playerIndex))

    local data = player:getModData()

    -- CRITICAL: Get blood type from GlobalModData (authoritative, persists across restarts)
    local bloodType = getOrCreateBloodType(playerUsername)
    log("[EHR Server] Blood type from GlobalModData: " .. tostring(bloodType))

    -- Initialize blood data with authoritative blood type
    initializeBloodData(data, playerUsername)
    log("[EHR Server] After initializeBloodData, blood type: " .. tostring(data.EHR_Blood and data.EHR_Blood.bloodType))

    -- Ensure other EHR data structures exist
    data.EHR_Initialized = true
    data.EHR_Disease = data.EHR_Disease or { active = {}, immunity = {}, history = { contractions = {}, recoveries = {} } }
    data.EHR_Sepsis = data.EHR_Sepsis or { active = false, stage = 0 }
    ensureWoundData(data)
    data.EHR_Medication = data.EHR_Medication or { activeTreatments = {}, activeDoses = {}, activeSideEffects = {} }
    data.EHR_MedicalJournal = data.EHR_MedicalJournal or { entries = {}, discoveries = {} }
    data.EHR_KnownDiseases = data.EHR_KnownDiseases or {}

    log("[EHR Server] ================================")

    -- Sync to client after short delay to ensure client is ready
    -- Using a timer to delay the sync
    local syncUsername = playerUsername  -- Capture for closure
    local function delayedSync()
        if player and player:isAlive() then
            -- Re-verify blood type is correct before sync
            local currentBloodType = data.EHR_Blood and data.EHR_Blood.bloodType
            log("[EHR Server] delayedSync for " .. syncUsername .. " - blood type: " .. tostring(currentBloodType))
            syncModDataToClient(player)
            log("[EHR Server] Synced initial data to client: " .. syncUsername)
        end
    end

    -- Schedule sync after 2 seconds (60 ticks)
    if Events and Events.OnTick then
        local tickCount = 0
        local syncHandler
        syncHandler = function()
            tickCount = tickCount + 1
            if tickCount >= 60 then  -- ~2 seconds delay
                Events.OnTick.Remove(syncHandler)
                delayedSync()
            end
        end
        Events.OnTick.Add(syncHandler)
    else
        -- Fallback: immediate sync
        delayedSync()
    end
end

-- Register server command handler
log("[EHR Server DEBUG] Attempting to register OnClientCommand handler...")
log("[EHR Server DEBUG] Events = " .. tostring(Events))
log("[EHR Server DEBUG] Events.OnClientCommand = " .. tostring(Events and Events.OnClientCommand or "nil"))

if Events and Events.OnClientCommand then
    Events.OnClientCommand.Add(OnClientCommand)
    log("[EHR Server DEBUG] SUCCESS! Server commands registered!")
    log("[EHR] Server commands registered (full MP support)")
else
    log("[EHR Server DEBUG] FAILED! Events.OnClientCommand not available!")
end

-- Register server-side player creation handler
if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(OnServerCreatePlayer)
    log("[EHR Server] Registered OnCreatePlayer handler for MP data initialization")
else
    log("[EHR Server] WARNING: Events.OnCreatePlayer not available!")
end

-- ============================================
-- PERIODIC SYNC SYSTEM
-- Syncs EHR data to all connected players every 30 seconds
-- ============================================

local SYNC_INTERVAL_TICKS = 900  -- ~30 seconds (30 ticks/sec)
local syncTickCounter = 0

local function syncAllPlayers()
    local players = getOnlinePlayers()
    if not players then return end

    local playerCount = players:size()
    if playerCount == 0 then return end

    log("[EHR Server] Periodic sync: syncing " .. playerCount .. " players")

    for i = 0, playerCount - 1 do
        local player = players:get(i)
        if player and player:isAlive() then
            syncModDataToClient(player)
        end
    end
end

-- ============================================
-- SERVER-SIDE DISEASE/SEPSIS PROGRESSION
-- Runs on dedicated server to process effects even when no client is "hosting"
-- ============================================

local PROGRESSION_INTERVAL_TICKS = 300  -- ~10 seconds
local progressionTickCounter = 0

local function processPlayerProgression(player)
    if not player or not player:isAlive() then return end

    local data = player:getModData()
    if not data then return end

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    -- Process Sepsis Progression
    if data.EHR_Sepsis and data.EHR_Sepsis.active then
        local sepsis = data.EHR_Sepsis
        local stageTime = currentHour - (sepsis.stageStartTime or currentHour)

        -- Stage progression times (hours per stage)
        local stageDurations = {6, 12, 24, 48}  -- Stage 1→2, 2→3, 3→4, 4→death
        local currentStage = sepsis.stage or 1

        if currentStage < 4 and stageTime >= (stageDurations[currentStage] or 12) then
            -- Progress to next stage
            sepsis.stage = currentStage + 1
            sepsis.stageStartTime = currentHour
            log("[EHR Server] Player " .. player:getUsername() .. " sepsis progressed to stage " .. sepsis.stage)
        end

        -- Stage 4 = death (handled by client, but server tracks)
        if sepsis.stage >= 4 then
            local stage4Time = currentHour - (sepsis.stageStartTime or currentHour)
            if stage4Time >= 48 then
                -- Player should be dead by now - client handles actual death
                log("[EHR Server] Player " .. player:getUsername() .. " sepsis stage 4 exceeded 48 hours")
            end
        end
    end

    -- Process Disease Progression
    if data.EHR_Disease and data.EHR_Disease.active then
        for diseaseId, disease in pairs(data.EHR_Disease.active) do
            if disease.endTime and currentHour >= disease.endTime then
                -- Disease has run its course - cure it
                data.EHR_Disease.active[diseaseId] = nil
                log("[EHR Server] Player " .. player:getUsername() .. " recovered from " .. diseaseId)
            elseif disease.peakTime and disease.stage then
                -- Update stage based on time
                local totalDuration = (disease.endTime or currentHour) - (disease.startTime or currentHour)
                local elapsed = currentHour - (disease.startTime or currentHour)
                local progress = totalDuration > 0 and (elapsed / totalDuration) or 0

                -- Stage progression: 1=incubation, 2=early, 3=peak, 4=recovery
                local newStage = 2
                if progress < 0.1 then
                    newStage = 1  -- Incubation
                elseif progress < 0.4 then
                    newStage = 2  -- Early
                elseif progress < 0.7 then
                    newStage = 3  -- Peak
                else
                    newStage = 4  -- Recovery
                end

                if newStage ~= disease.stage then
                    disease.stage = newStage
                    log("[EHR Server] Player " .. player:getUsername() .. " " .. diseaseId .. " progressed to stage " .. newStage)
                end
            end
        end
    end

    -- Process Wound Infection Progression
    if data.EHR_WoundInfection and data.EHR_WoundInfection.parts then
        for partName, partData in pairs(data.EHR_WoundInfection.parts) do
            if partData.stage and partData.stage > 0 and partData.stage < 4 then
                local stageTime = currentHour - (partData.stageStartTime or currentHour)
                -- Wounds progress roughly every 12-24 hours without treatment
                local progressionTime = 18 - (partData.stage * 2)  -- Faster at higher stages

                if stageTime >= progressionTime then
                    partData.stage = partData.stage + 1
                    partData.stageStartTime = currentHour
                    log("[EHR Server] Player " .. player:getUsername() .. " wound " .. partName .. " progressed to stage " .. partData.stage)

                    -- Stage 4 can trigger sepsis (handled by client normally, but track here)
                    if partData.stage >= 4 and (not data.EHR_Sepsis or not data.EHR_Sepsis.active) then
                        data.EHR_Sepsis = {
                            active = true,
                            stage = 1,
                            startTime = currentHour,
                            stageStartTime = currentHour,
                            sourceBodyPart = partName,
                            treatmentDoses = 0,
                        }
                        log("[EHR Server] Player " .. player:getUsername() .. " developed sepsis from wound " .. partName)
                    end
                end
            end
        end

        -- Recalculate wound stats
        recalcWoundStats(data.EHR_WoundInfection)
    end

    -- Process Blood Regeneration (slow, ~100mL per hour when healthy)
    if data.EHR_Blood and data.EHR_Blood.currentVolume then
        local blood = data.EHR_Blood
        local maxVol = blood.maxVolume or 5000
        local currentVol = blood.currentVolume or maxVol

        -- Only regen if below max and not actively bleeding
        if currentVol < maxVol and not blood.isCurrentlyBleeding then
            local lastRegenHour = blood.lastRegenHour or currentHour
            local hoursSinceRegen = currentHour - lastRegenHour

            if hoursSinceRegen >= 1 then
                -- Base regen: 100mL/hour, reduced if low blood
                local regenRate = 100
                local bloodPercent = currentVol / maxVol
                if bloodPercent < 0.5 then
                    regenRate = regenRate * bloodPercent * 2  -- Slower when very low
                end

                local regenAmount = regenRate * math.floor(hoursSinceRegen)
                blood.currentVolume = math.min(maxVol, currentVol + regenAmount)
                blood.lastRegenHour = currentHour

                if regenAmount > 0 then
                    log("[EHR Server] Player " .. player:getUsername() .. " blood regen: +" .. math.floor(regenAmount) .. "mL")
                end
            end
        end
    end
end

local function OnServerTick()
    -- Periodic sync
    syncTickCounter = syncTickCounter + 1
    if syncTickCounter >= SYNC_INTERVAL_TICKS then
        syncTickCounter = 0
        syncAllPlayers()
    end

    -- Disease/Sepsis/Wound progression
    progressionTickCounter = progressionTickCounter + 1
    if progressionTickCounter >= PROGRESSION_INTERVAL_TICKS then
        progressionTickCounter = 0

        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local player = players:get(i)
                processPlayerProgression(player)
            end
        end
    end
end

-- Register server tick handler
if Events and Events.OnTick then
    Events.OnTick.Add(OnServerTick)
    log("[EHR Server] Registered OnTick handler for periodic sync and progression")
else
    log("[EHR Server] WARNING: Events.OnTick not available!")
end

-- ============================================
-- EVENT-BASED SYNC TRIGGERS
-- Called by other modules after significant events
-- ============================================

function EHR.ServerCommands.TriggerSync(player)
    if not player then return end
    syncModDataToClient(player)
    log("[EHR Server] Event-triggered sync for " .. tostring(player:getUsername()))
end

-- Global function for other server modules to call
function EHR_TriggerPlayerSync(player)
    if EHR and EHR.ServerCommands and EHR.ServerCommands.TriggerSync then
        EHR.ServerCommands.TriggerSync(player)
    end
end

log("[EHR Server] Full MP support initialized (periodic sync + progression + event triggers)")
