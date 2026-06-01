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
pcall(function() require "ExtensiveHealth/EHR_Blood" end)
pcall(function() require "ExtensiveHealth/EHR_Disease" end)
pcall(function() require "ExtensiveHealth/EHR_Medication" end)
pcall(function() require "ExtensiveHealth/EHR_WoundInfection" end)
pcall(function() require "ExtensiveHealth/EHR_Sepsis" end)
pcall(function() require "ExtensiveHealth/EHR_EnvironmentalDiseases" end)
pcall(function() require "ExtensiveHealth/EHR_KnoxCure" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
pcall(function() require "ExtensiveHealth/EHR_DiseaseFlyers" end)

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
    if EHR and EHR.ShouldLog and EHR.ShouldLog(msg) then
        print(msg)
    end
    return
end

local function serverText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text(key, fallback)
    end
    if getText then
        local ok, value = pcall(getText, key)
        if ok and value and value ~= key then return value end
    end
    return fallback or key
end

local function callBodyPartMethod(bodyPart, methodName, fallback)
    if not bodyPart or not methodName then return fallback end
    local method = bodyPart[methodName]
    if not method then return fallback end
    local ok, result = pcall(function()
        return method(bodyPart)
    end)
    if ok then return result end
    return fallback
end

local function getBodyPartName(bodyPart)
    local partType = callBodyPartMethod(bodyPart, "getType", nil)
    if partType ~= nil then
        return tostring(partType)
    end
    return nil
end

local function buildBodyStatusSnapshot(player)
    local snapshot = {
        parts = {},
        timestamp = getTimestampMs and getTimestampMs() or 0,
    }
    if not player or not player.getBodyDamage then return snapshot end

    local okDamage, bodyDamage = pcall(function()
        return player:getBodyDamage()
    end)
    if not okDamage or not bodyDamage or not bodyDamage.getBodyParts then
        return snapshot
    end

    local okParts, bodyParts = pcall(function()
        return bodyDamage:getBodyParts()
    end)
    if not okParts or not bodyParts or not bodyParts.size then
        return snapshot
    end

    for i = 0, bodyParts:size() - 1 do
        local bodyPart = bodyParts:get(i)
        local partName = getBodyPartName(bodyPart)
        if partName then
            snapshot.parts[partName] = {
                health = tonumber(callBodyPartMethod(bodyPart, "getHealth", 100)) or 100,
                bandaged = callBodyPartMethod(bodyPart, "bandaged", false) == true,
                bandageLife = tonumber(callBodyPartMethod(bodyPart, "getBandageLife", 1)) or 1,
                infected = callBodyPartMethod(bodyPart, "isInfectedWound", false) == true,
                infectionLevel = tonumber(callBodyPartMethod(bodyPart, "getWoundInfectionLevel", 0)) or 0,
                additionalPain = tonumber(callBodyPartMethod(bodyPart, "getAdditionalPain", 0)) or 0,
                stiffness = tonumber(callBodyPartMethod(bodyPart, "getStiffness", 0)) or 0,
                hasInjury = callBodyPartMethod(bodyPart, "HasInjury", false) == true,
                bleeding = callBodyPartMethod(bodyPart, "bleeding", false) == true,
                fractureTime = tonumber(callBodyPartMethod(bodyPart, "getFractureTime", 0)) or 0,
                haveBullet = callBodyPartMethod(bodyPart, "haveBullet", false) == true,
                haveGlass = callBodyPartMethod(bodyPart, "haveGlass", false) == true,
                burnTime = tonumber(callBodyPartMethod(bodyPart, "getBurnTime", 0)) or 0,
                needBurnWash = callBodyPartMethod(bodyPart, "isNeedBurnWash", false) == true,
                deepWounded = callBodyPartMethod(bodyPart, "deepWounded", false) == true,
                bitten = callBodyPartMethod(bodyPart, "bitten", false) == true,
                cut = callBodyPartMethod(bodyPart, "isCut", false) == true,
                scratched = callBodyPartMethod(bodyPart, "scratched", false) == true,
                stitched = callBodyPartMethod(bodyPart, "stitched", false) == true,
                splintFactor = tonumber(callBodyPartMethod(bodyPart, "getSplintFactor", 0)) or 0,
                plantainFactor = tonumber(callBodyPartMethod(bodyPart, "getPlantainFactor", 0)) or 0,
                comfreyFactor = tonumber(callBodyPartMethod(bodyPart, "getComfreyFactor", 0)) or 0,
            }
        end
    end

    return snapshot
end

log("=========================================")
log("[EHR] EHR_ServerCommands.lua LOADING ON SERVER")
log("[EHR] isServer() = " .. tostring(isServer()))
log("[EHR] isClient() = " .. tostring(isClient()))
log("=========================================")
EHR.ServerCommands = {}

local DEBUG_WOUND_VANILLA_LEVELS = {
    [1] = 2,
    [2] = 6,
    [3] = 11,
    [4] = 15,
}

local DEBUG_WOUND_BODY_PARTS = {
    "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R",
    "UpperArm_L", "UpperArm_R", "Foot_L", "Foot_R",
    "LowerLeg_L", "LowerLeg_R", "UpperLeg_L", "UpperLeg_R",
    "Torso_Upper", "Torso_Lower", "Head", "Neck", "Groin",
}

local function getDebugBodyPart(player, partName)
    if not player or not partName or not BodyPartType then return nil end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return nil end

    local partType = BodyPartType[partName]
    if not partType and BodyPartType.FromString then
        local okString, result = pcall(function() return BodyPartType.FromString(partName) end)
        if okString then partType = result end
    end
    if not partType then return nil end

    local okPart, bodyPart = pcall(function()
        return bodyDamage:getBodyPart(partType)
    end)

    return okPart and bodyPart or nil
end

local function setDebugVanillaWoundInfection(player, partName, stage)
    local bodyPart = getDebugBodyPart(player, partName)
    if not bodyPart then return false end

    stage = math.max(0, math.min(4, tonumber(stage) or 0))
    if stage <= 0 then
        if EHR and EHR.WoundInfection and EHR.WoundInfection.ClearVanillaInfection then
            EHR.WoundInfection.ClearVanillaInfection(bodyPart)
        else
            pcall(function() bodyPart:setWoundInfectionLevel(-1) end)
            pcall(function() bodyPart:setInfectedWound(false) end)
        end
        return true
    end

    local level = DEBUG_WOUND_VANILLA_LEVELS[stage] or 2
    pcall(function() bodyPart:setInfectedWound(true) end)
    pcall(function() bodyPart:setWoundInfectionLevel(level) end)
    return true
end

local function clearDebugVanillaWoundInfections(player)
    for _, partName in ipairs(DEBUG_WOUND_BODY_PARTS) do
        setDebugVanillaWoundInfection(player, partName, 0)
    end
end

local function syncDebugBodyPart(bodyPart)
    if syncBodyPart and bodyPart then
        pcall(function() syncBodyPart(bodyPart, 0xFFFFFFFFFFF) end)
    end
end

local function syncDebugVisuals(player)
    if not player then return end
    if syncVisuals then
        pcall(function() syncVisuals(player) end)
    end
    if sendHumanVisual then
        pcall(function() sendHumanVisual(player) end)
    end
    if player.resetModelNextFrame then
        pcall(function() player:resetModelNextFrame() end)
    end
end

local function getDebugBloodBodyPart(bodyPart)
    if not bodyPart or not BloodBodyPartType or not BodyPartType then return nil end
    local ok, result = pcall(function()
        return BloodBodyPartType.FromIndex(BodyPartType.ToIndex(bodyPart:getType()))
    end)
    if ok then return result end
    return nil
end

local function clearDebugBodyPartStiffness(player, bodyPart)
    if not player or not bodyPart then return end
    pcall(function() bodyPart:setStiffness(0) end)
    pcall(function()
        if player.getFitness and BodyPartType and BodyPartType.ToString then
            player:getFitness():removeStiffnessValue(BodyPartType.ToString(bodyPart:getType()))
        end
    end)
end

local function setDebugBandaged(player, bodyPart, bandaged, dirty)
    if not player or not bodyPart then return false end
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return false end

    if bandaged then
        local bandageType = dirty and "Base.RippedSheetsDirty" or "Base.Bandage"
        local bandageLife = dirty and 0 or 10
        pcall(function()
            bodyDamage:SetBandaged(bodyPart:getIndex(), true, bandageLife, false, bandageType)
        end)
    else
        pcall(function()
            bodyDamage:SetBandaged(bodyPart:getIndex(), false, 0, false, nil)
        end)
    end
    return true
end

local function setDebugBleeding(bodyPart, time)
    if not bodyPart then return end
    pcall(function()
        bodyPart:setBleedingTime(math.max(tonumber(time) or 0, tonumber(bodyPart:getBleedingTime()) or 0))
    end)
end

local function clearDebugVanillaBodyPart(player, bodyPart)
    if not bodyPart then return end
    pcall(function() bodyPart:RestoreToFullHealth() end)
    pcall(function() bodyPart:setWoundInfectionLevel(-1) end)
    pcall(function() bodyPart:setInfectedWound(false) end)
    pcall(function() bodyPart:SetBitten(false) end)
    pcall(function() bodyPart:SetInfected(false) end)
    pcall(function() bodyPart:SetFakeInfected(false) end)
    setDebugBandaged(player, bodyPart, false, false)
    clearDebugBodyPartStiffness(player, bodyPart)
    syncDebugBodyPart(bodyPart)
end

local function applyDebugVanillaInjury(player, partName, injuryId)
    local bodyPart = getDebugBodyPart(player, partName)
    if not player or not bodyPart or not injuryId then return false end

    if injuryId == "bleeding" then
        pcall(function() bodyPart:setBleedingTime(10) end)
    elseif injuryId == "scratch" then
        pcall(function() bodyPart:setScratched(true, false) end)
        setDebugBleeding(bodyPart, 4)
    elseif injuryId == "cut" then
        pcall(function() bodyPart:setCut(true) end)
        setDebugBleeding(bodyPart, 8)
    elseif injuryId == "deep_wound" then
        pcall(function() bodyPart:generateDeepWound() end)
    elseif injuryId == "glass" then
        pcall(function() bodyPart:generateDeepShardWound() end)
    elseif injuryId == "bite" then
        pcall(function() bodyPart:SetBitten(true) end)
        pcall(function() bodyPart:SetInfected(true) end)
        pcall(function() bodyPart:SetFakeInfected(false) end)
        setDebugBleeding(bodyPart, 8)
    elseif injuryId == "burn" then
        pcall(function() bodyPart:setBurnTime(50) end)
    elseif injuryId == "bullet" then
        pcall(function() bodyPart:setHaveBullet(true, 0) end)
    elseif injuryId == "fracture" then
        pcall(function() bodyPart:setFractureTime(21) end)
    elseif injuryId == "strain" then
        pcall(function() bodyPart:setStiffness(100) end)
    elseif injuryId == "infect" then
        pcall(function() bodyPart:setInfectedWound(true) end)
        pcall(function() bodyPart:setWoundInfectionLevel(10) end)
    elseif injuryId == "bandage" then
        setDebugBandaged(player, bodyPart, true, false)
    elseif injuryId == "dirty_bandage" then
        setDebugBandaged(player, bodyPart, true, true)
    elseif injuryId == "remove_bandage" then
        setDebugBandaged(player, bodyPart, false, false)
    elseif injuryId == "clear_part" then
        clearDebugVanillaBodyPart(player, bodyPart)
        return true
    else
        return false
    end

    syncDebugBodyPart(bodyPart)
    return true
end

local function applyDebugVanillaVisual(player, partName, visualId)
    local bodyPart = getDebugBodyPart(player, partName)
    local visualPart = getDebugBloodBodyPart(bodyPart)
    if not player or not visualPart or not visualId then return false end

    if visualId == "add_blood" then
        pcall(function() player:addBlood(visualPart, false, true, false) end)
    elseif visualId == "remove_blood" then
        pcall(function()
            if player.getVisual then player:getVisual():setBlood(visualPart, 0) end
        end)
    elseif visualId == "add_dirt" then
        pcall(function() player:addDirt(visualPart, nil, false) end)
    elseif visualId == "remove_dirt" then
        pcall(function()
            if player.getVisual then player:getVisual():setDirt(visualPart, 0) end
        end)
    elseif visualId == "add_hole" then
        pcall(function() player:addHole(visualPart) end)
    elseif visualId == "add_patch" then
        pcall(function() player:addBasicPatch(visualPart) end)
    elseif visualId == "clear_visual" then
        pcall(function()
            if player.getVisual then
                player:getVisual():setBlood(visualPart, 0)
                player:getVisual():setDirt(visualPart, 0)
            end
        end)
    else
        return false
    end

    syncDebugVisuals(player)
    return true
end

local function clearAllDebugVanillaInjuries(player)
    if not player then return end
    for _, partName in ipairs(DEBUG_WOUND_BODY_PARTS) do
        clearDebugVanillaBodyPart(player, getDebugBodyPart(player, partName))
    end
end

local function clearAllDebugVanillaVisuals(player)
    if not player then return end
    for _, partName in ipairs(DEBUG_WOUND_BODY_PARTS) do
        applyDebugVanillaVisual(player, partName, "clear_visual")
    end
    syncDebugVisuals(player)
end

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

local function isValidBloodType(bloodType)
    return bloodType == "O-" or bloodType == "O+" or
           bloodType == "A-" or bloodType == "A+" or
           bloodType == "B-" or bloodType == "B+" or
           bloodType == "AB-" or bloodType == "AB+"
end

local function getBloodTypeStorageKey(player, fallbackUsername)
    local username = tostring(fallbackUsername or "unknown")

    if player and player.getUsername then
        pcall(function()
            username = tostring(player:getUsername() or username)
        end)
    end

    local forename = "unknown"
    local surname = "unknown"
    local profession = "unknown"

    if player and player.getDescriptor then
        pcall(function()
            local descriptor = player:getDescriptor()
            if descriptor then
                forename = tostring(descriptor:getForename() or forename)
                surname = tostring(descriptor:getSurname() or surname)
                if descriptor.getCharacterProfession then
                    local prof = descriptor:getCharacterProfession()
                    if prof then
                        if prof.getName then
                            profession = tostring(prof:getName() or profession)
                        elseif prof.getType then
                            profession = tostring(prof:getType() or profession)
                        else
                            profession = tostring(prof)
                        end
                    end
                end
            end
        end)
    end

    return username .. "|" .. forename .. "|" .. surname .. "|" .. profession
end

local function storeBloodType(player, playerUsername, bloodType)
    if not isValidBloodType(bloodType) then return end

    local globalBloodTypes = ModData.getOrCreate("EHR_BloodTypes_Server")
    local storageKey = getBloodTypeStorageKey(player, playerUsername)
    globalBloodTypes[storageKey] = bloodType
end

-- ============================================
-- HELPER: Get or create blood type from GlobalModData (server-side persistent storage)
-- This ensures blood type survives server restarts
-- ============================================
local function getOrCreateBloodType(player, playerUsername)
    -- GlobalModData persists across server restarts - use it as the authoritative source
    local globalBloodTypes = ModData.getOrCreate("EHR_BloodTypes_Server")
    local storageKey = getBloodTypeStorageKey(player, playerUsername)

    log("[EHR Server] getOrCreateBloodType for: " .. tostring(storageKey))
    log("[EHR Server] GlobalModData existing blood type: " .. tostring(globalBloodTypes[storageKey]))

    if isValidBloodType(globalBloodTypes[storageKey]) then
        log("[EHR Server] Returning EXISTING blood type from GlobalModData: " .. globalBloodTypes[storageKey])
        return globalBloodTypes[storageKey]
    end

    -- Generate new blood type and store in GlobalModData
    local newBloodType = generateBloodType()
    globalBloodTypes[storageKey] = newBloodType
    log("[EHR Server] Generated NEW blood type and stored in GlobalModData: " .. newBloodType)

    return newBloodType
end

-- ============================================
-- HELPER: Initialize blood data structure with proper blood type
-- ============================================
local function initializeBloodData(data, playerUsername, player)
    if data.EHR_DeadCharacter == true then
        data.EHR_Blood = {}
    end

    data.EHR_Blood = data.EHR_Blood or {}
    data.EHR_Blood.maxVolume = data.EHR_Blood.maxVolume or 5000
    data.EHR_Blood.currentVolume = data.EHR_Blood.currentVolume or 5000

    local existingBloodType = data.EHR_Blood.bloodType
    if isValidBloodType(existingBloodType) and data.EHR_DeadCharacter ~= true then
        data.EHR_Blood.bloodType = existingBloodType
        storeBloodType(player, playerUsername, existingBloodType)
        log("[EHR Server] initializeBloodData: Kept existing character blood type " .. existingBloodType .. " for " .. tostring(playerUsername))
    elseif playerUsername then
        local bloodType = getOrCreateBloodType(player, playerUsername)
        data.EHR_Blood.bloodType = bloodType
        log("[EHR Server] initializeBloodData: Set blood type to " .. bloodType .. " for " .. playerUsername)
    else
        -- Fallback if no username provided (shouldn't happen)
        data.EHR_Blood.bloodType = generateBloodType()
        log("[EHR Server] initializeBloodData: Generated fallback blood type: " .. data.EHR_Blood.bloodType)
    end

    data.EHR_DeadCharacter = nil

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
        incubating = {},
        totalInfectedParts = 0,
        worstStage = 0,
        lastCheck = 0,
    }
    data.EHR_WoundInfection.parts = data.EHR_WoundInfection.parts or {}
    data.EHR_WoundInfection.incubating = data.EHR_WoundInfection.incubating or {}
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

local function setWoundStage(data, partName, stage, player)
    if not partName then return end
    local woundData = ensureWoundData(data)
    local currentHour = getGameTime() and getGameTime():getWorldAgeHours() or 0
    stage = math.max(0, math.min(4, tonumber(stage) or 0))

    woundData.incubating[partName] = nil

    if stage <= 0 then
        if player and EHR and EHR.WoundInfection and EHR.WoundInfection.ClearPartSymptomPain then
            EHR.WoundInfection.ClearPartSymptomPain(player, partName)
        end
        woundData.parts[partName] = nil
        setDebugVanillaWoundInfection(player, partName, 0)
    else
        local vanillaLevel = DEBUG_WOUND_VANILLA_LEVELS[stage] or 2
        woundData.parts[partName] = woundData.parts[partName] or {}
        woundData.parts[partName].stage = stage
        woundData.parts[partName].stageStartTime = currentHour
        woundData.parts[partName].startTime = woundData.parts[partName].startTime or currentHour
        woundData.parts[partName].vanillaLevel = vanillaLevel
        woundData.parts[partName].debugForced = true
        woundData.parts[partName].debugForcedTime = currentHour
        setDebugVanillaWoundInfection(player, partName, stage)

        if stage >= 4 and data then
            data.EHR_Sepsis = data.EHR_Sepsis or {
                active = true,
                stage = 1,
                startTime = currentHour,
                treatmentDoses = 0,
                lastHealthDamageHour = currentHour,
                healthCap = nil,
            }
            data.EHR_Sepsis.active = true
            data.EHR_Sepsis.stage = math.max(1, tonumber(data.EHR_Sepsis.stage) or 1)
            data.EHR_Sepsis.stageStartTime = currentHour
            data.EHR_Sepsis.lastHealthDamageHour = currentHour
            data.EHR_Sepsis.healthCap = nil
            data.EHR_Sepsis.sourceBodyPart = partName
            data.EHR_Sepsis_Initialized = true

            woundData.parts[partName].stage = 3
            woundData.parts[partName].stageStartTime = currentHour
            woundData.parts[partName].sepsisTriggered = true
            woundData.parts[partName].lastSepsisTrigger = currentHour
        end
    end

    if player and EHR and EHR.WoundInfection and EHR.WoundInfection.RecalculateStats then
        EHR.WoundInfection.RecalculateStats(player)
    else
        recalcWoundStats(woundData)
    end
end

local function clearAllWounds(data, player)
    local woundData = ensureWoundData(data)
    if player and EHR and EHR.WoundInfection and EHR.WoundInfection.ClearAllSymptomPain then
        EHR.WoundInfection.ClearAllSymptomPain(player)
    end
    woundData.parts = {}
    woundData.incubating = {}
    woundData.totalInfectedParts = 0
    woundData.worstStage = 0
    woundData.lastCheck = getGameTime() and getGameTime():getWorldAgeHours() or 0
    data.EHR_WoundInfections = nil
    data.EHR_WoundInfections_Initialized = nil
    clearDebugVanillaWoundInfections(player)
end

-- ============================================
-- HELPER: Sync ModData to client
-- ============================================
local function syncModDataToClient(player)
    if not player then return end

    local data = player:getModData()

    -- Send only EHR-owned data. Full transmitModData can overwrite other mods'
    -- client-side player fields, such as Lifestyle bathroom/hygiene state.
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
            EHR_KnoxCure = data.EHR_KnoxCure,
        }
        sendServerCommand(player, "EHR_Sync", "UpdateModData", ehrData)
        log("[EHR Server] Sent EHR data to client via sendServerCommand")
    end
end

local function findOnlinePlayerByArgs(args, fallbackPlayer)
    if not args then return fallbackPlayer end

    local targetUsername = args.targetUsername and tostring(args.targetUsername) or nil
    local targetOnlineID = args.targetOnlineID and tostring(args.targetOnlineID) or nil
    local targetDisplayName = args.targetDisplayName and tostring(args.targetDisplayName) or nil

    if not targetUsername and not targetOnlineID and not targetDisplayName then
        return fallbackPlayer
    end

    local onlinePlayers = getOnlinePlayers and getOnlinePlayers() or nil
    if not onlinePlayers then return fallbackPlayer end

    for i = 0, onlinePlayers:size() - 1 do
        local candidate = onlinePlayers:get(i)
        local username = nil
        local onlineID = nil
        local displayName = nil

        if candidate then
            pcall(function()
                if candidate.getUsername then username = candidate:getUsername() end
            end)
            pcall(function()
                if candidate.getOnlineID then onlineID = tostring(candidate:getOnlineID()) end
            end)
            pcall(function()
                if candidate.getDisplayName then displayName = tostring(candidate:getDisplayName()) end
            end)
        end

        if candidate and (
            (targetUsername and username == targetUsername) or
            (targetOnlineID and onlineID == targetOnlineID) or
            (targetDisplayName and displayName == targetDisplayName)
        ) then
            return candidate
        end
    end

    return nil
end

local function findItemInContainer(container, itemID, visited)
    if not container or itemID == nil then return nil, nil end
    visited = visited or {}
    if visited[container] then return nil, nil end
    visited[container] = true

    local items = container:getItems()
    if not items then return nil, nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local okID, currentID = pcall(function() return item:getID() end)
            if okID and tostring(currentID) == tostring(itemID) then
                return item, container
            end

            local nestedContainer = nil
            if item.getInventory then
                local okNested, nested = pcall(function() return item:getInventory() end)
                if okNested then nestedContainer = nested end
            end

            if nestedContainer then
                local found, owner = findItemInContainer(nestedContainer, itemID, visited)
                if found then return found, owner end
            end
        end
    end

    return nil, nil
end

local function findInventoryItemByID(player, itemID)
    if not player or itemID == nil then return nil, nil end
    local inventory = player:getInventory()
    if not inventory then return nil, nil end
    return findItemInContainer(inventory, itemID, {})
end

local function removeInventoryItem(item, fallbackContainer)
    if not item then return false end

    local container = fallbackContainer
    if item.getContainer then
        local okContainer, itemContainer = pcall(function() return item:getContainer() end)
        if okContainer and itemContainer then
            container = itemContainer
        end
    end

    if container then
        local removed = false
        local okRemove = pcall(function()
            container:Remove(item)
            removed = true
        end)
        if okRemove and removed and sendRemoveItemFromContainer then
            pcall(function() sendRemoveItemFromContainer(container, item) end)
        end
        return okRemove and removed
    end

    return false
end

local function syncInventoryItem(item)
    if item and sendItemStats then
        pcall(function() sendItemStats(item) end)
    end
end

local function syncInventoryItemAdded(container, item)
    if not item then return end
    if container and sendAddItemToContainer then
        pcall(function() sendAddItemToContainer(container, item) end)
    end
    syncInventoryItem(item)
end

local getSterilizedBandagePackDoseInfo
local consumeSterilizedBandagePackDose

function EHR.ServerCommands.UnpackCleanBandage(player, args)
    if not player or not args or args.packID == nil then return false end
    local pack, packContainer = findInventoryItemByID(player, args.packID)
    if not pack or not pack.getFullType or pack:getFullType() ~= "ExtensiveHealth.SterilizedBandages" then return false end

    local inventory = player:getInventory()
    if not inventory then return false end

    local remaining = getSterilizedBandagePackDoseInfo(pack)
    if remaining <= 0 then return false end

    local okAdd, bandage = pcall(function() return inventory:AddItem("Base.Bandage") end)
    if not okAdd or not bandage then return false end
    syncInventoryItemAdded(inventory, bandage)

    consumeSterilizedBandagePackDose(pack, packContainer)
    return true
end
function getSterilizedBandagePackDoseInfo(pack)
    local maxDoses = 5
    local useDelta = 0.2
    if EHR and EHR.Medication and EHR.Medication.GetItemDoseInfo then
        local ok, info = pcall(function() return EHR.Medication.GetItemDoseInfo(pack) end)
        if ok and info then
            return tonumber(info.remainingDoses) or 0, tonumber(info.maxDoses) or maxDoses, tonumber(info.useDelta) or useDelta
        end
    end

    if pack and pack.getUseDelta then
        local okDelta, delta = pcall(function() return pack:getUseDelta() end)
        if okDelta and tonumber(delta) and tonumber(delta) > 0 then
            useDelta = tonumber(delta)
            maxDoses = math.max(1, math.floor((1.0 / useDelta) + 0.5))
        end
    end

    local currentUsesFloat = 1.0
    if pack and pack.getCurrentUsesFloat then
        local okCurrent, value = pcall(function() return pack:getCurrentUsesFloat() end)
        if okCurrent and value ~= nil then currentUsesFloat = tonumber(value) or currentUsesFloat end
    elseif pack and pack.getUsedDelta then
        local okUsed, value = pcall(function() return pack:getUsedDelta() end)
        if okUsed and value ~= nil then currentUsesFloat = tonumber(value) or currentUsesFloat end
    end

    currentUsesFloat = math.max(0, math.min(1.0, currentUsesFloat))
    local remaining = math.floor((currentUsesFloat / useDelta) + 0.0001)
    remaining = math.max(0, math.min(maxDoses, remaining))
    return remaining, maxDoses, useDelta
end

function consumeSterilizedBandagePackDose(pack, packContainer)
    local remaining = getSterilizedBandagePackDoseInfo(pack)
    if remaining <= 0 then return false end

    if pack and pack.UseAndSync then
        local ok = pcall(function() pack:UseAndSync() end)
        if ok then
            syncInventoryItem(pack)
            return true
        end
    end

    if pack and pack.Use then
        local ok = pcall(function() pack:Use() end)
        if ok then
            syncInventoryItem(pack)
            return true
        end
    end

    local _, _, useDelta = getSterilizedBandagePackDoseInfo(pack)
    if remaining > 1 and pack.setUsedDelta then
        local newUsed = math.max(0, math.min(1, (remaining - 1) * useDelta))
        pcall(function() pack:setUsedDelta(newUsed) end)
        syncInventoryItem(pack)
    else
        removeInventoryItem(pack, packContainer)
    end
    return true
end
local function getOnlinePlayerByIDSafe(onlineID)
    if onlineID == nil then return nil end
    local numericID = tonumber(onlineID)
    if getPlayerByOnlineID then
        local ok, playerByID = pcall(function() return getPlayerByOnlineID(numericID or onlineID) end)
        if ok and playerByID then return playerByID end
    end
    if getOnlinePlayers then
        local okPlayers, players = pcall(getOnlinePlayers)
        if okPlayers and players and players.size then
            for i = 0, players:size() - 1 do
                local candidate = players:get(i)
                if candidate and candidate.getOnlineID then
                    local okID, candidateID = pcall(function() return candidate:getOnlineID() end)
                    if okID and tonumber(candidateID) == numericID then return candidate end
                end
            end
        end
    end
    return nil
end

local function getBodyPartByIndex(player, bodyPartIndex)
    if not player or bodyPartIndex == nil then return nil end
    local bodyDamage = player:getBodyDamage()
    local bodyParts = bodyDamage and bodyDamage.getBodyParts and bodyDamage:getBodyParts() or nil
    local index = tonumber(bodyPartIndex)
    if not bodyParts or not index then return nil end
    local ok, bodyPart = pcall(function() return bodyParts:get(index) end)
    return ok and bodyPart or nil
end

local function serverBodyPartCanReceiveCleanBandage(bodyPart)
    if not bodyPart then return false end
    if callBodyPartMethod(bodyPart, "bandaged", false) == true then return false end
    if callBodyPartMethod(bodyPart, "HasInjury", false) == true then return true end
    if callBodyPartMethod(bodyPart, "bleeding", false) == true then return true end
    if callBodyPartMethod(bodyPart, "scratched", false) == true then return true end
    if callBodyPartMethod(bodyPart, "deepWounded", false) == true then return true end
    if callBodyPartMethod(bodyPart, "bitten", false) == true then return true end
    if callBodyPartMethod(bodyPart, "isCut", false) == true then return true end
    if callBodyPartMethod(bodyPart, "isBurnt", false) == true then return true end
    return (tonumber(callBodyPartMethod(bodyPart, "getBurnTime", 0)) or 0) > 0
end

function EHR.ServerCommands.ApplyBandagePack(player, args)
    if not player or not args or args.packID == nil or args.bodyPartIndex == nil then return false end
    local pack, packContainer = findInventoryItemByID(player, args.packID)
    if not pack or not pack.getFullType or pack:getFullType() ~= "ExtensiveHealth.SterilizedBandages" then return false end

    local target = player
    if args.targetOnlineID ~= nil then
        target = getOnlinePlayerByIDSafe(args.targetOnlineID) or player
    end
    local bodyPart = getBodyPartByIndex(target, args.bodyPartIndex)
    if not serverBodyPartCanReceiveCleanBandage(bodyPart) then return false end

    local remaining = getSterilizedBandagePackDoseInfo(pack)
    if remaining <= 0 then return false end

    local bodyDamage = target:getBodyDamage()
    if not bodyDamage then return false end

    local doctorLevel = 0
    if player.getPerkLevel and Perks and Perks.Doctor then
        local okLevel, level = pcall(function() return player:getPerkLevel(Perks.Doctor) end)
        if okLevel then doctorLevel = tonumber(level) or 0 end
    end
    if player.isTimedActionInstant and player:isTimedActionInstant() then doctorLevel = 10 end

    local randomBonus = (doctorLevel + 1) * 0.75
    if ZombRandFloat then
        local okRand, value = pcall(function()
            return ZombRandFloat((doctorLevel + 1) * 0.5, (doctorLevel + 1) * 1.0)
        end)
        if okRand and value then randomBonus = value end
    end
    local bandageLife = randomBonus + 4.0

    if callBodyPartMethod(bodyPart, "isGetBandageXp", false) == true and addXp and Perks and Perks.Doctor then
        pcall(function() addXp(player, Perks.Doctor, 5) end)
    end

    pcall(function()
        bodyDamage:SetBandaged(bodyPart:getIndex(), true, bandageLife, false, "Base.Bandage")
    end)
    consumeSterilizedBandagePackDose(pack, packContainer)

    if syncBodyPart then
        pcall(function() syncBodyPart(bodyPart, 0xc001966b8e) end)
    end
    if EHR_TriggerPlayerSync then
        pcall(function() EHR_TriggerPlayerSync(target) end)
    end
    return true
end
local function serverSay(player, text)
    if not player or not text then return end
    if EHR and EHR.Locale and EHR.Locale.Say then
        local ok = pcall(function() EHR.Locale.Say(player, text) end)
        if ok then return end
    end
    if sendServerCommand then
        pcall(function() sendServerCommand(player, "EHR_Dialogue", "Say", { text = tostring(text) }) end)
        return
    end
    if player.Say then
        pcall(function() player:Say(tostring(text)) end)
    end
end

local function addCharacterStat(player, stat, amount, maxValue)
    if not player or not stat or not amount then return end
    local stats = player:getStats()
    if not stats or not CharacterStat or not CharacterStat[stat] then return end

    pcall(function()
        local current = stats:get(CharacterStat[stat]) or 0
        stats:set(CharacterStat[stat], math.min(maxValue or 1, current + amount))
    end)
end

local function ensureServerBloodData(player)
    if not player then return nil end
    local data = nil
    if EHR and EHR.GetPlayerData then
        data = EHR.GetPlayerData(player)
    end
    data = data or player:getModData()
    if not data then return nil end

    local username = nil
    pcall(function() username = player:getUsername() end)
    initializeBloodData(data, username, player)
    return data
end

local function getServerSpoilageState(item, clientState)
    if not item then return "rotten" end

    local md = nil
    pcall(function() md = item:getModData() end)
    local spoilage = md and md.EHR_BloodSpoilage or nil
    if spoilage then
        if spoilage.rotten then return "rotten" end
        if spoilage.stale then return "stale" end
    end

    if item.isRotten then
        local okRotten, rotten = pcall(function() return item:isRotten() end)
        if okRotten and rotten then return "rotten" end
    end
    if item.isFresh then
        local okFresh, fresh = pcall(function() return item:isFresh() end)
        if okFresh and fresh == false then return "stale" end
    end

    if clientState == "fresh" or clientState == "stale" or clientState == "rotten" then
        return clientState
    end

    return "fresh"
end

local function restoreServerBlood(player, data, amount)
    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, amount)
        data.EHR_Blood.transfusedBlood = (data.EHR_Blood.transfusedBlood or 0) + amount
        return
    end

    local current = data.EHR_Blood.currentVolume or 0
    local maxVolume = data.EHR_Blood.maxVolume or 5000
    data.EHR_Blood.currentVolume = math.min(current + amount, maxVolume)
    data.EHR_Blood.transfusedBlood = (data.EHR_Blood.transfusedBlood or 0) + amount
end

local function applyServerSpoiledBloodReaction(player, data, spoilageState)
    local severityMult = spoilageState == "rotten" and 2.0 or 1.0
    local bodyDamage = player and player:getBodyDamage() or nil

    addCharacterStat(player, "SICKNESS", 0.6 * severityMult, 1)
    addCharacterStat(player, "FOOD_SICKNESS", 0.7 * severityMult, 1)
    addCharacterStat(player, "PAIN", 0.5 * severityMult, 1)
    addCharacterStat(player, "PANIC", 0.4 * severityMult, 1)

    if bodyDamage then
        pcall(function()
            local currentTemp = bodyDamage:getTemperature() or 37
            bodyDamage:setTemperature(math.min(41, currentTemp + 2 * severityMult))
        end)
    end

    if bodyDamage and BodyPartType then
        local maxIndex = BodyPartType.ToIndex and BodyPartType.ToIndex(BodyPartType.MAX) or nil
        if maxIndex then
            for _ = 1, math.floor(4 * severityMult) do
                local partType = BodyPartType.FromIndex(ZombRand(maxIndex))
                local part = partType and bodyDamage:getBodyPart(partType) or nil
                if part and part.ReduceHealth then
                    pcall(function() part:ReduceHealth(ZombRand(10, 25) * severityMult) end)
                end
            end
        end
    end

    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, -150 * severityMult)
    elseif data and data.EHR_Blood then
        data.EHR_Blood.currentVolume = math.max(0, (data.EHR_Blood.currentVolume or 5000) - 150 * severityMult)
    end

    serverSay(player, spoilageState == "rotten" and "Oh god... that blood was rotten!" or "That blood tasted off...")
end

local function applyServerBadBloodReaction(player, data)
    addCharacterStat(player, "FOOD_SICKNESS", 0.12, 1)
    addCharacterStat(player, "SICKNESS", 0.18, 1)
    addCharacterStat(player, "PANIC", 0.35, 1)
    addCharacterStat(player, "PAIN", 0.12, 1)

    if EHR.Disease and EHR.Disease.Contract then
        local diseaseData = EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
        local active = diseaseData and diseaseData.active and diseaseData.active.ahtr or nil
        if active then
            active.severity = math.min(1.25, (tonumber(active.severity) or 0.95) + 0.25)
            active.endTime = math.max(tonumber(active.endTime) or 0, getGameTime():getWorldAgeHours() + 72)
            active.incompatibleTransfusion = true
        else
            EHR.Disease.Contract(player, "ahtr")
            diseaseData = EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or diseaseData
            active = diseaseData and diseaseData.active and diseaseData.active.ahtr or nil
            if active then
                active.severity = math.max(tonumber(active.severity) or 0.95, 0.95)
                active.incompatibleTransfusion = true
            end
        end
    end

    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, -150)
    elseif data and data.EHR_Blood then
        data.EHR_Blood.currentVolume = math.max(0, (data.EHR_Blood.currentVolume or 5000) - 150)
    end

    serverSay(player, "Something's wrong... I feel terrible!")
end

local function applyServerBloodBag(player, item, spoilageState)
    local data = ensureServerBloodData(player)
    if not data or not data.EHR_Blood or not item then return false end

    local fullType = item:getFullType()
    local bagType = EHR.Blood and EHR.Blood.BloodBagTypes and EHR.Blood.BloodBagTypes[fullType] or nil
    if not bagType then return false end

    if spoilageState == "stale" then
        applyServerSpoiledBloodReaction(player, data, spoilageState)
    elseif spoilageState == "rotten" then
        applyServerSpoiledBloodReaction(player, data, spoilageState)
        return true
    end

    local playerType = data.EHR_Blood.bloodType
    if EHR.Blood and EHR.Blood.IsCompatible and EHR.Blood.IsCompatible(bagType, playerType) then
        restoreServerBlood(player, data, 500)
        serverSay(player, "That should help...")
    else
        applyServerBadBloodReaction(player, data)
    end

    return true
end

local function applyServerSalineBag(player, item, spoilageState)
    if not player or not item then return false, false end
    local data = ensureServerBloodData(player)
    if not data then return false, false end

    if spoilageState == "rotten" then
        addCharacterStat(player, "SICKNESS", 0.25, 1)
        serverSay(player, "That saline was contaminated!")
        return true, false
    end

    if EHR.Blood and EHR.Blood.UseSalineBag then
        EHR.Blood.UseSalineBag(player, item)
    else
        if EHR.Blood and EHR.Blood.ModifyBloodVolume then
            EHR.Blood.ModifyBloodVolume(player, 250)
        else
            data.EHR_Blood.currentVolume = math.min((data.EHR_Blood.currentVolume or 0) + 250, data.EHR_Blood.maxVolume or 5000)
        end
        data.EHR_Blood.transfusedSaline = (data.EHR_Blood.transfusedSaline or 0) + 250
    end

    if spoilageState == "stale" then
        addCharacterStat(player, "SICKNESS", 0.15, 1)
        serverSay(player, "That saline tasted a bit off...")
    end

    -- EHR.Blood.UseSalineBag intentionally does not consume the item; the action layer does.
    return true, false
end

function EHR.ServerCommands.UseMedication(player, args)
    if not player or not args or not args.itemID then return end
    if not EHR.Medication or not EHR.Medication.UseMedication then
        log("[EHR Server] UseMedication rejected: medication module unavailable")
        return
    end

    local item = findInventoryItemByID(player, args.itemID)
    if not item then
        log("[EHR Server] UseMedication rejected: item not found " .. tostring(args.itemID))
        syncModDataToClient(player)
        return
    end

    if args.itemFullType and item:getFullType() ~= args.itemFullType then
        log("[EHR Server] UseMedication rejected: item type mismatch " .. tostring(args.itemFullType) .. " != " .. tostring(item:getFullType()))
        syncModDataToClient(player)
        return
    end

    local ok, result = pcall(function()
        return EHR.Medication.UseMedication(player, item)
    end)
    if not ok then
        log("[EHR Server] UseMedication failed: " .. tostring(result))
    end

    syncInventoryItem(item)
    syncModDataToClient(player)
end

function EHR.ServerCommands.DrinkWaterRisk(player, args)
    if not player then return end
    if not EHR.Environmental or not EHR.Environmental.OnDrinkWater then
        log("[EHR Server] DrinkWaterRisk rejected: environmental module unavailable")
        return
    end

    local sourceType = "tainted"
    if args and args.sourceType then
        sourceType = tostring(args.sourceType)
    end

    local ok, result = pcall(function()
        return EHR.Environmental.OnDrinkWater(player, nil, sourceType)
    end)
    if not ok then
        log("[EHR Server] DrinkWaterRisk failed: " .. tostring(result))
    end

    syncModDataToClient(player)
end

function EHR.ServerCommands.EnvironmentalSnapshot(player, args)
    if not player then return end
    if not EHR.Environmental or not EHR.Environmental.StoreClientSnapshot then
        log("[EHR Server] EnvironmentalSnapshot rejected: environmental module unavailable")
        return
    end

    local ok, result = pcall(function()
        return EHR.Environmental.StoreClientSnapshot(player, args or {})
    end)
    if not ok then
        log("[EHR Server] EnvironmentalSnapshot failed: " .. tostring(result))
    end
end

function EHR.ServerCommands.FoodDiseaseRisk(player, args)
    if not player then return end
    if not EHR.Disease or not EHR.Disease.ApplyFoodDiseaseRisk then
        log("[EHR Server] FoodDiseaseRisk rejected: disease module unavailable")
        return
    end

    if EHR.Disease.InitializePlayer then
        pcall(function() EHR.Disease.InitializePlayer(player) end)
    end

    local risks = args and args.risks
    if type(risks) ~= "table" then
        log("[EHR Server] FoodDiseaseRisk rejected: missing risk table")
        return
    end

    local itemName = tostring(args.itemName or "unknown")
    local applied = 0
    for _, foodRisk in ipairs(risks) do
        if type(foodRisk) == "table" then
            local diseaseId = tostring(foodRisk.diseaseId or "")
            local reason = tostring(foodRisk.reason or "food")
            local chance = math.max(0, math.min(1, tonumber(foodRisk.chance) or 0))
            if chance > 0 and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId] then
                local ok, result = pcall(function()
                    return EHR.Disease.ApplyFoodDiseaseRisk(player, itemName, diseaseId, reason, chance)
                end)
                if ok then
                    applied = applied + 1
                else
                    log("[EHR Server] FoodDiseaseRisk failed for " .. tostring(diseaseId) .. ": " .. tostring(result))
                end
            end
        end
    end

    if applied > 0 then
        syncModDataToClient(player)
    end
end

local function setCellulitisSource(targetPlayer, args)
    if not targetPlayer or not EHR.Disease or not EHR.Disease.GetDiseaseData then return end

    local diseaseData = EHR.Disease.GetDiseaseData(targetPlayer)
    local cellulitis = diseaseData and diseaseData.active and diseaseData.active.cellulitis or nil
    if not cellulitis then return end

    cellulitis.source = "rough_stitch"
    cellulitis.sourceBodyPart = args and args.sourceBodyPart or cellulitis.sourceBodyPart
    cellulitis.stitchQuality = tonumber(args and args.quality) or cellulitis.stitchQuality
    cellulitis.stitchMisses = tonumber(args and args.misses) or cellulitis.stitchMisses
end

function EHR.ServerCommands.StitchCellulitisRisk(player, args)
    if not player or not args then return end

    local targetPlayer = findOnlinePlayerByArgs(args, player)
    if not targetPlayer then
        log("[EHR Server] StitchCellulitisRisk rejected: target player not found")
        return
    end

    if not EHR.Disease or not EHR.Disease.Contract then
        log("[EHR Server] StitchCellulitisRisk rejected: disease module unavailable")
        return
    end

    local chance = math.max(0, math.min(1, tonumber(args.chance) or 0))
    if chance <= 0 then return end

    local roll = ZombRand and (ZombRand(100) / 100) or 1
    if roll >= chance then return end

    if EHR.Disease.InitializePlayer then
        pcall(function() EHR.Disease.InitializePlayer(targetPlayer) end)
    end

    local diseaseData = EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(targetPlayer) or nil
    if not (diseaseData and diseaseData.active and diseaseData.active.cellulitis) then
        EHR.Disease.Contract(targetPlayer, "cellulitis")
    end

    setCellulitisSource(targetPlayer, args)
    syncModDataToClient(targetPlayer)
end

local function triggerCellulitisSepsisHandoff(targetPlayer, args)
    if not targetPlayer then return false end

    local sourceBodyPart = args and args.sourceBodyPart or "cellulitis"
    if EHR.Sepsis and EHR.Sepsis.Trigger then
        EHR.Sepsis.Trigger(targetPlayer, sourceBodyPart)
    else
        if EHR.Disease and EHR.Disease.Contract then
            EHR.Disease.Contract(targetPlayer, "sepsis")
        end
    end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(targetPlayer) or nil
    if diseaseData and diseaseData.active then
        diseaseData.active.cellulitis = nil
    end

    syncModDataToClient(targetPlayer)
    return true
end

function EHR.ServerCommands.CellulitisSepsisHandoff(player, args)
    if not player then return end

    local targetPlayer = findOnlinePlayerByArgs(args, player)
    if not targetPlayer then
        log("[EHR Server] CellulitisSepsisHandoff rejected: target player not found")
        return
    end

    triggerCellulitisSepsisHandoff(targetPlayer, args or {})
end

function EHR.ServerCommands.FoodToxinRisk(player, args)
    if not player then return end
    if not EHR.Disease or not EHR.Disease.ApplyVanillaPoisonDisease then
        log("[EHR Server] FoodToxinRisk rejected: disease module unavailable")
        return
    end

    if EHR.Disease.InitializePlayer then
        pcall(function() EHR.Disease.InitializePlayer(player) end)
    end

    local itemName = tostring(args and args.itemName or "unknown")
    local poisonPower = math.max(0, math.min(100, tonumber(args and args.poisonPower) or 0))
    local poisonDetectionLevel = math.max(0, tonumber(args and args.poisonDetectionLevel) or 0)
    local toxinType = tostring(args and args.toxinType or "toxin")
    if toxinType ~= "mushroom" and toxinType ~= "berry" then
        toxinType = "toxin"
    end

    local ok, result = pcall(function()
        if EHR.Disease.MarkVanillaPoisonFood then
            EHR.Disease.MarkVanillaPoisonFood(player, itemName, poisonPower, poisonDetectionLevel, toxinType)
        end
        EHR.Disease.ApplyVanillaPoisonDisease(player, itemName, poisonPower, toxinType)
    end)
    if not ok then
        log("[EHR Server] FoodToxinRisk failed: " .. tostring(result))
    end

    syncModDataToClient(player)
end

function EHR.ServerCommands.UseKnoxCureItem(player, args)
    if not player or not args or not args.itemID then return end
    if not EHR.KnoxCure then
        log("[EHR Server] UseKnoxCureItem rejected: KnoxCure module unavailable")
        return
    end

    local item = findInventoryItemByID(player, args.itemID)
    if not item then
        log("[EHR Server] UseKnoxCureItem rejected: item not found " .. tostring(args.itemID))
        syncModDataToClient(player)
        return
    end

    if args.itemFullType and item:getFullType() ~= args.itemFullType then
        log("[EHR Server] UseKnoxCureItem rejected: item type mismatch " .. tostring(args.itemFullType) .. " != " .. tostring(item:getFullType()))
        syncModDataToClient(player)
        return
    end

    local action = tostring(args.action or "")
    if action == "geneTherapy" or action == "antibodyTest" then
        ensureServerBloodData(player)
    end

    local ok, result
    if action == "geneTherapy" and EHR.KnoxCure.UseGeneTherapy then
        ok, result = pcall(EHR.KnoxCure.UseGeneTherapy, player, item)
    elseif action == "phalanx" and EHR.KnoxCure.UsePhalanx then
        ok, result = pcall(EHR.KnoxCure.UsePhalanx, player, item)
    elseif action == "antibodyTest" and EHR.KnoxCure.UseAntibodyTest then
        ok, result = pcall(EHR.KnoxCure.UseAntibodyTest, player, item)
    elseif action == "immunobooster" and EHR.KnoxCure.UseImmunobooster then
        ok, result = pcall(EHR.KnoxCure.UseImmunobooster, player, item)
    else
        log("[EHR Server] UseKnoxCureItem rejected: unknown action " .. action)
    end

    if ok == false then
        log("[EHR Server] UseKnoxCureItem failed: " .. tostring(result))
    end

    syncModDataToClient(player)
end

function EHR.ServerCommands.UseTransfusion(player, args)
    if not player or not args or not args.itemID then return end
    if not EHR.Blood then
        log("[EHR Server] UseTransfusion rejected: blood module unavailable")
        return
    end

    local item, container = findInventoryItemByID(player, args.itemID)
    if not item then
        log("[EHR Server] UseTransfusion rejected: item not found " .. tostring(args.itemID))
        syncModDataToClient(player)
        return
    end

    if args.itemFullType and item:getFullType() ~= args.itemFullType then
        log("[EHR Server] UseTransfusion rejected: item type mismatch " .. tostring(args.itemFullType) .. " != " .. tostring(item:getFullType()))
        syncModDataToClient(player)
        return
    end

    local fullType = item:getFullType()
    local spoilageState = getServerSpoilageState(item, args.spoilageState)
    local consumed = false

    if EHR.Blood.BloodBagTypes and EHR.Blood.BloodBagTypes[fullType] then
        consumed = applyServerBloodBag(player, item, spoilageState)
        if consumed then
            if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
                pcall(function() EHR.SkillXP.OnTransfusion(player, false) end)
            end
            removeInventoryItem(item, container)
        end
    elseif fullType == "ExtensiveHealth.SalineBag" then
        local applied, consumedByBloodApi = applyServerSalineBag(player, item, spoilageState)
        consumed = applied
        if consumed and not consumedByBloodApi then
            removeInventoryItem(item, container)
        end
    else
        log("[EHR Server] UseTransfusion rejected: unsupported item " .. tostring(fullType))
    end

    syncModDataToClient(player)
end

function EHR.ServerCommands.DrawBlood(player, args)
    if not player or not args or not args.itemID then return end
    if not EHR.Blood then
        log("[EHR Server] DrawBlood rejected: blood module unavailable")
        return
    end

    local emptyBag, container = findInventoryItemByID(player, args.itemID)
    if not emptyBag then
        log("[EHR Server] DrawBlood rejected: empty bag not found " .. tostring(args.itemID))
        syncModDataToClient(player)
        return
    end
    if emptyBag:getFullType() ~= "ExtensiveHealth.EmptyBloodBag" then
        log("[EHR Server] DrawBlood rejected: unsupported item " .. tostring(emptyBag:getFullType()))
        syncModDataToClient(player)
        return
    end

    local data = ensureServerBloodData(player)
    if not data or not data.EHR_Blood then return end

    local current = tonumber(data.EHR_Blood.currentVolume) or 5000
    local maxVolume = tonumber(data.EHR_Blood.maxVolume) or 5000
    if maxVolume <= 0 or (current / maxVolume) < 0.80 then
        serverSay(player, serverText("UI_EHR_Transfusion_NotEnoughBloodSafe", "I don't have enough blood to do that safely."))
        syncModDataToClient(player)
        return
    end

    local playerType = data.EHR_Blood.bloodType
    if EHR.Blood.GetPlayerBloodType then
        local okType, typeValue = pcall(function() return EHR.Blood.GetPlayerBloodType(player) end)
        if okType and typeValue then playerType = typeValue end
    end

    local bloodBagItems = {
        ["O-"]  = "ExtensiveHealth.BloodBagONeg",
        ["O+"]  = "ExtensiveHealth.BloodBagOPos",
        ["A-"]  = "ExtensiveHealth.BloodBagANeg",
        ["A+"]  = "ExtensiveHealth.BloodBagAPos",
        ["B-"]  = "ExtensiveHealth.BloodBagBNeg",
        ["B+"]  = "ExtensiveHealth.BloodBagBPos",
        ["AB-"] = "ExtensiveHealth.BloodBagABNeg",
        ["AB+"] = "ExtensiveHealth.BloodBagABPos",
    }
    local filledBagType = bloodBagItems[playerType]
    if not filledBagType then
        serverSay(player, serverText("UI_EHR_Transfusion_SomethingWentWrong", "Something went wrong..."))
        log("[EHR Server] DrawBlood rejected: unknown blood type " .. tostring(playerType))
        syncModDataToClient(player)
        return
    end

    local inventory = player:getInventory()
    local okAdd, filledBag = pcall(function() return inventory:AddItem(filledBagType) end)
    if not okAdd or not filledBag then
        serverSay(player, serverText("UI_EHR_Transfusion_SomethingWentWrong", "Something went wrong..."))
        log("[EHR Server] DrawBlood failed to create " .. tostring(filledBagType) .. ": " .. tostring(filledBag))
        syncModDataToClient(player)
        return
    end

    pcall(function() filledBag:setAge(0) end)
    pcall(function()
        local now = getGameTime() and getGameTime():getWorldAgeHours() or 0
        local modData = filledBag:getModData()
        modData.EHR_BloodSpoilage = {
            createdHour = now,
            lastCheckHour = now,
            warmElapsed = 0,
            stale = false,
            rotten = false,
            isFrozen = false,
        }
        modData.EHR_DonorBloodType = playerType
    end)

    if EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, -500)
    else
        data.EHR_Blood.currentVolume = math.max(0, current - 500)
    end

    removeInventoryItem(emptyBag, container)
    serverSay(player, serverText("UI_EHR_DrawBlood_Complete", "That made me lightheaded..."))

    addCharacterStat(player, "FATIGUE", 0.15, 0.7)
    if CharacterStat and CharacterStat.ENDURANCE then
        local stats = player:getStats()
        if stats then
            pcall(function()
                local endurance = stats:get(CharacterStat.ENDURANCE) or 1
                stats:set(CharacterStat.ENDURANCE, math.max(0.3, endurance - 0.2))
            end)
        end
    end

    if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
        pcall(function() EHR.SkillXP.OnTransfusion(player, true) end)
    end

    syncInventoryItemAdded(inventory, filledBag)
    syncModDataToClient(player)
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
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.NormalizeDiseaseId then
        diseaseId = EHR.DiseaseFlyers.NormalizeDiseaseId(diseaseId)
    end

    local data = player:getModData()
    if not data then return end

    data.EHR_KnownDiseases = data.EHR_KnownDiseases or {}
    data.EHR_KnownDiseases[diseaseId] = true
    data.EHR_MedicalJournal = data.EHR_MedicalJournal or { entries = {}, discoveries = {} }
    data.EHR_MedicalJournal.discoveries = data.EHR_MedicalJournal.discoveries or {}
    data.EHR_MedicalJournal.discoveries[diseaseId] = getGameTime():getWorldAgeHours()
    data.EHR_MedicalJournal.lastUpdated = getGameTime():getWorldAgeHours()

    syncModDataToClient(player)
    if sendServerCommand then
        sendServerCommand(player, "EHR_Flyers", "KnowledgeUnlocked", {
            diseaseId = diseaseId,
            EHR_KnownDiseases = data.EHR_KnownDiseases,
            EHR_MedicalJournal = data.EHR_MedicalJournal,
        })
    end
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
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFever then
        EHR.BodyTemp.ResetDiseaseFever(player, true)
    end

    -- Clear wound infections
    clearAllWounds(data, player)

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

    if EHR and EHR.WoundInfection and EHR.WoundInfection.ClearAllSymptomPain then
        EHR.WoundInfection.ClearAllSymptomPain(player)
    end

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
    data.EHR_Temperature = nil
    clearDebugVanillaWoundInfections(player)

    -- Re-initialize
    if EHR and EHR.InitializePlayer then
        EHR.InitializePlayer(player)
    end
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFever then
        EHR.BodyTemp.ResetDiseaseFever(player, true)
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
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFeverIfStale then
        EHR.BodyTemp.ResetDiseaseFeverIfStale(player, true)
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
    if EHR.Disease and EHR.Disease.SetStage then
        EHR.Disease.SetStage(player, diseaseId, 2)
    end

    log("[EHR Server] Created disease: " .. diseaseId .. " duration=" .. duration .. "h")

    syncModDataToClient(player)
    log("[EHR Server] InflictDisease command executed and synced to client")
end

function EHR.ServerCommands.SetDiseaseStage(player, args)
    if not player then return end
    if not args or not args.diseaseId or not args.stage then return end

    local diseaseId = args.diseaseId
    local stage = math.max(1, math.min(4, tonumber(args.stage) or 2))
    local changed = false

    if EHR.Disease and EHR.Disease.SetStage then
        changed = EHR.Disease.SetStage(player, diseaseId, stage)
    else
        local data = player:getModData()
        if data and data.EHR_Disease and data.EHR_Disease.active and data.EHR_Disease.active[diseaseId] then
            data.EHR_Disease.active[diseaseId].stage = stage
            changed = true
        end
    end
    if changed and EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFeverIfStale then
        EHR.BodyTemp.ResetDiseaseFeverIfStale(player, true)
    end

    if changed then
        syncModDataToClient(player)
        log("[EHR Server] SetDiseaseStage command executed: " .. tostring(diseaseId) .. " -> stage " .. tostring(stage))
    else
        log("[EHR Server] SetDiseaseStage failed: " .. tostring(diseaseId))
    end
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
        initializeBloodData(data, playerUsername, player)
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
        initializeBloodData(data, playerUsername, player)
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
        initializeBloodData(data, playerUsername, player)
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
        data.EHR_Sepsis.lastHealthDamageHour = nil
        data.EHR_Sepsis.healthCap = nil
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
        lastHealthDamageHour = currentHour,
        healthCap = nil,
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

    setWoundStage(data, randomPart, severity, player)

    syncModDataToClient(player)
    log("[EHR Server] InfectRandom command executed: " .. randomPart .. " severity " .. severity)
end

--[[
    Set a specific wound infection stage (server-side)
]]--
function EHR.ServerCommands.SetWoundStage(player, args)
    if not player or not args or not args.partId then return end

    local partName = tostring(args.partId)
    local stage = math.max(0, math.min(4, tonumber(args.stage) or 0))
    local data = player:getModData()

    setWoundStage(data, partName, stage, player)
    syncModDataToClient(player)
    log("[EHR Server] SetWoundStage command executed: " .. partName .. " -> " .. tostring(stage))
end

--[[
    Clear all wound infections (server-side)
]]--
function EHR.ServerCommands.ClearAllInfections(player, args)
    if not player then return end

    log("[EHR Server] ClearAllInfections command received")

    local data = player:getModData()
    clearAllWounds(data, player)

    syncModDataToClient(player)
    log("[EHR Server] ClearAllInfections command executed")
end

function EHR.ServerCommands.ApplyVanillaInjury(player, args)
    if not player or not args then return end

    local partName = tostring(args.partId or "")
    local injuryId = tostring(args.injuryId or "")
    if partName == "" or injuryId == "" then return end

    local ok = applyDebugVanillaInjury(player, partName, injuryId)
    syncModDataToClient(player)
    log("[EHR Server] ApplyVanillaInjury " .. tostring(partName) .. " " .. tostring(injuryId) .. " -> " .. tostring(ok))
end

function EHR.ServerCommands.ClearVanillaInjuries(player, args)
    if not player then return end

    clearAllDebugVanillaInjuries(player)
    syncModDataToClient(player)
    log("[EHR Server] ClearVanillaInjuries command executed")
end

function EHR.ServerCommands.ApplyVanillaVisual(player, args)
    if not player or not args then return end

    local partName = tostring(args.partId or "")
    local visualId = tostring(args.visualId or "")
    if partName == "" or visualId == "" then return end

    local ok = applyDebugVanillaVisual(player, partName, visualId)
    syncModDataToClient(player)
    log("[EHR Server] ApplyVanillaVisual " .. tostring(partName) .. " " .. tostring(visualId) .. " -> " .. tostring(ok))
end

function EHR.ServerCommands.ClearVanillaVisuals(player, args)
    if not player then return end

    clearAllDebugVanillaVisuals(player)
    syncModDataToClient(player)
    log("[EHR Server] ClearVanillaVisuals command executed")
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

    if EHR.Medication and EHR.Medication.ClearAllSideEffectState then
        pcall(function()
            EHR.Medication.ClearAllSideEffectState(player, true)
        end)
    else
        if data.EHR_Medication and data.EHR_Medication.activeSideEffects then
            for id, _ in pairs(data.EHR_Medication.activeSideEffects) do
                data.EHR_Medication.activeSideEffects[id] = nil
            end
        end
        if data.EHR_Medication and data.EHR_Medication.activeGeneralEffects then
            data.EHR_Medication.activeGeneralEffects.staminaLock = nil
            data.EHR_Medication.activeGeneralEffects.fatigueBlock = nil
            data.EHR_Medication.activeGeneralEffects.combatStimulants = nil
            data.EHR_Medication.activeGeneralEffects.mpFatigueRecovery = nil
        end

        -- Also clear legacy data
        if data.EHR_SideEffects then
            for id, _ in pairs(data.EHR_SideEffects) do
                data.EHR_SideEffects[id] = nil
            end
        end

        data.EHR_TendonWeakness = nil
        data.EHR_KidneyStress = nil
        data.EHR_Insomnia = nil
        data.EHR_Immunosuppressed = nil
        data.EHR_LiverStress = nil
        data.EHR_CaffeineAwake = nil
        data.EHR_CombatStimulantsActive = nil
        data.EHR_CombatStimSpeedActive = nil
        data.EHR_CombatStimWeaponId = nil
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

    if EHR.Medication and EHR.Medication.ApplySideEffect then
        pcall(function()
            EHR.Medication.ApplySideEffect(player, effectId, { force = true })
        end)
    else
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
    end

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
            lastHealthDamageHour = currentHour,
            healthCap = nil,
        }
        setWoundStage(data, "Torso_Upper", 4, player)

    elseif scenarioId == "late_sepsis" then
        data.EHR_Sepsis = {
            active = true,
            stage = 3,
            startTime = currentHour - 48,
            stageStartTime = currentHour,
            sourceBodyPart = "Debug",
            treatmentDoses = 0,
            lastHealthDamageHour = currentHour,
            healthCap = nil,
        }

    elseif scenarioId == "multiple_infections" then
        setWoundStage(data, "Hand_L", 2, player)
        setWoundStage(data, "ForeArm_R", 3, player)
        setWoundStage(data, "Torso_Upper", 2, player)

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
        if EHR.Disease and EHR.Disease.SetStage then
            EHR.Disease.SetStage(player, "common_cold", 2)
        end
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
        if EHR.Disease and EHR.Disease.SetStage then
            EHR.Disease.SetStage(player, "food_poisoning", 2)
        end

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
            lastHealthDamageHour = currentHour,
            healthCap = nil,
        }
        -- Multiple infections
        setWoundStage(data, "Torso_Upper", 4, player)
        setWoundStage(data, "UpperLeg_L", 3, player)
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
    local isEHRCommand = module == "EHR" or module == "EHR_Flyers"
    local quietCommand = module == "EHR" and command == "EnvironmentalSnapshot"
    if isEHRCommand and not quietCommand then
        log("[EHR Server DEBUG] ========== OnClientCommand ==========")
        log("[EHR Server DEBUG] module = '" .. tostring(module) .. "'")
        log("[EHR Server DEBUG] command = '" .. tostring(command) .. "'")
        log("[EHR Server DEBUG] player = " .. tostring(player and player:getUsername() or "nil"))
    end

    -- ============================================
    -- MP ITEM SYNC COMMANDS (any player can use)
    -- ============================================
    if module == "EHR" then
        if command == "UseMedication" then
            EHR.ServerCommands.UseMedication(player, args)
            return
        elseif command == "DrinkWaterRisk" then
            EHR.ServerCommands.DrinkWaterRisk(player, args)
            return
        elseif command == "EnvironmentalSnapshot" then
            EHR.ServerCommands.EnvironmentalSnapshot(player, args)
            return
        elseif command == "FoodDiseaseRisk" then
            EHR.ServerCommands.FoodDiseaseRisk(player, args)
            return
        elseif command == "StitchCellulitisRisk" then
            EHR.ServerCommands.StitchCellulitisRisk(player, args)
            return
        elseif command == "CellulitisSepsisHandoff" then
            EHR.ServerCommands.CellulitisSepsisHandoff(player, args)
            return
        elseif command == "FoodToxinRisk" then
            EHR.ServerCommands.FoodToxinRisk(player, args)
            return
        elseif command == "UseKnoxCureItem" then
            EHR.ServerCommands.UseKnoxCureItem(player, args)
            return
        elseif command == "UseTransfusion" then
            EHR.ServerCommands.UseTransfusion(player, args)
            return
        elseif command == "DrawBlood" then
            EHR.ServerCommands.DrawBlood(player, args)
            return
        elseif command == "RemoveItem" and args and args.itemID then
            -- Find and remove the item from player's inventory
            local item, container = findInventoryItemByID(player, args.itemID)
            if item then
                removeInventoryItem(item, container)
                log("[EHR] Server: Synced item removal for " .. player:getUsername())
                return
            end
        elseif command == "UnpackCleanBandage" then
            EHR.ServerCommands.UnpackCleanBandage(player, args)
            return
        elseif command == "ApplyBandagePack" then
            EHR.ServerCommands.ApplyBandagePack(player, args)
            return
        elseif command == "UpdateItemDelta" and args and args.itemID and args.usedDelta then
            -- Sync drainable item usedDelta from client
            local item = findInventoryItemByID(player, args.itemID)
            if item then
                local newUsed = math.max(0, math.min(1, args.usedDelta))
                pcall(function() item:setUsedDelta(newUsed) end)
                syncInventoryItem(item)
                log("[EHR] Server: Synced item usedDelta for " .. player:getUsername())
                return
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
                totalDosesNeeded = args.totalDosesNeeded or 1,
                intervalHours = args.intervalHours or 6,
                activeHours = args.activeHours or args.intervalHours or 6,
                lastDoseTime = args.lastDoseTime,
                startTime = args.lastDoseTime,
                treatingDisease = args.treatingDisease,
                symptomOnly = args.symptomOnly == true,
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
            -- args.targetUsername/targetOnlineID/targetDisplayName = identifiers of player to examine
            if not args or (not args.targetUsername and not args.targetOnlineID and not args.targetDisplayName and not args.targetKey) then
                log("[EHR] Server: RequestExamData missing target identifier")
                return
            end

            local targetUsername = args.targetUsername
            local targetOnlineID = args.targetOnlineID and tostring(args.targetOnlineID) or nil
            local targetDisplayName = args.targetDisplayName and tostring(args.targetDisplayName) or nil
            local requestKey = args.targetKey or targetUsername or (targetOnlineID and ("online_" .. targetOnlineID)) or targetDisplayName
            local targetPlayer = nil

            -- Find target player by the most stable identifiers available. In
            -- MP/listen-server cases getUsername() can be missing on one side
            -- of the client, while onlineID/displayName still resolve.
            local onlinePlayers = getOnlinePlayers()
            if onlinePlayers then
                for i = 0, onlinePlayers:size() - 1 do
                    local p = onlinePlayers:get(i)
                    local username = nil
                    local onlineID = nil
                    local displayName = nil
                    if p then
                        pcall(function() username = p:getUsername() end)
                        pcall(function()
                            if p.getOnlineID then onlineID = tostring(p:getOnlineID()) end
                        end)
                        pcall(function()
                            if p.getDisplayName then displayName = tostring(p:getDisplayName()) end
                        end)
                    end

                    if p and (
                        (targetUsername and username == targetUsername) or
                        (targetOnlineID and onlineID == targetOnlineID) or
                        (targetDisplayName and displayName == targetDisplayName)
                    ) then
                        targetPlayer = p
                        break
                    end
                end
            end

            if not targetPlayer then
                log("[EHR] Server: RequestExamData - target player not found: " .. tostring(requestKey))
                -- Send empty response so client knows request failed
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = requestKey,
                    success = false,
                    error = "Player not found or offline",
                })
                return
            end

            -- Get target player's EHR data
            local targetData = targetPlayer:getModData()
            if not targetData then
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = requestKey,
                    success = false,
                    error = "No data available",
                })
                return
            end

            -- Compile EHR data to send
            local medicationView = nil
            if EHR.Medication then
                medicationView = {
                    activeTreatments = EHR.Medication.GetActiveTreatments and EHR.Medication.GetActiveTreatments(targetPlayer) or {},
                    activeDoses = EHR.Medication.GetAllDoseStatuses and EHR.Medication.GetAllDoseStatuses(targetPlayer) or {},
                    activeSideEffects = EHR.Medication.GetActiveSideEffects and EHR.Medication.GetActiveSideEffects(targetPlayer) or {},
                }
            end

            local actualUsername = targetUsername
            pcall(function() actualUsername = targetPlayer:getUsername() or actualUsername end)

            local examData = {
                targetUsername = requestKey,
                targetActualUsername = actualUsername,
                success = true,
                EHR_Blood = targetData.EHR_Blood,
                EHR_Disease = targetData.EHR_Disease,
                EHR_Sepsis = targetData.EHR_Sepsis,
                EHR_WoundInfection = targetData.EHR_WoundInfection,
                EHR_BodyStatus = buildBodyStatusSnapshot(targetPlayer),
                EHR_Medication = targetData.EHR_Medication,
                EHR_MedicationView = medicationView,
                EHR_MedicalJournal = targetData.EHR_MedicalJournal,
                EHR_Temperature = targetData.EHR_Temperature,
                EHR_CorpseSickness = targetData.EHR_CorpseSickness,
                EHR_KnoxCure = targetData.EHR_KnoxCure,
                EHR_Initialized = targetData.EHR_Initialized,
            }

            -- Send data to requesting player
            sendServerCommand(player, "EHR_Exam", "ExamDataResponse", examData)
            log("[EHR] Server: Sent exam data for " .. tostring(requestKey) .. " to " .. player:getUsername())
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
    elseif command == "SetDiseaseStage" then
        EHR.ServerCommands.SetDiseaseStage(player, args)

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
    elseif command == "SetWoundStage" then
        EHR.ServerCommands.SetWoundStage(player, args)
    elseif command == "ClearAllInfections" then
        EHR.ServerCommands.ClearAllInfections(player, args)
    elseif command == "ApplyVanillaInjury" then
        EHR.ServerCommands.ApplyVanillaInjury(player, args)
    elseif command == "ClearVanillaInjuries" then
        EHR.ServerCommands.ClearVanillaInjuries(player, args)
    elseif command == "ApplyVanillaVisual" then
        EHR.ServerCommands.ApplyVanillaVisual(player, args)
    elseif command == "ClearVanillaVisuals" then
        EHR.ServerCommands.ClearVanillaVisuals(player, args)

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

    -- Initialize blood data with the authoritative blood type
    initializeBloodData(data, playerUsername, player)

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

    -- Initialize blood data with authoritative blood type
    initializeBloodData(data, playerUsername, player)
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

local function OnServerPlayerDeath(player)
    if not player then return end

    local playerUsername = player:getUsername() or ("Player" .. player:getPlayerNum())
    local globalBloodTypes = ModData.getOrCreate("EHR_BloodTypes_Server")
    local storageKey = getBloodTypeStorageKey(player, playerUsername)

    globalBloodTypes[storageKey] = nil
    globalBloodTypes[playerUsername] = nil -- legacy username-only key

    local data = player:getModData()
    if data then
        data.EHR_DeadCharacter = true
    end

    log("[EHR Server] Cleared stored blood type for dead character: " .. tostring(storageKey))
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

if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(OnServerPlayerDeath)
    log("[EHR Server] Registered OnPlayerDeath handler for blood type reset")
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
local MEDICATION_INTERVAL_TICKS = 30    -- ~1 second; keeps delayed side effects responsive in MP
local BLOOD_INTERVAL_TICKS = 30         -- ~1 second; server is authoritative for MP blood
local BLOOD_SYNC_INTERVAL_TICKS = 90    -- ~3 seconds while bleeding; keeps UI responsive without spam
local progressionTickCounter = 0
local medicationTickCounter = 0
local bloodTickCounter = 0
local bloodSyncTickCounter = 0

local function syncBloodDataToClient(player, data)
    if not player or not data or not data.EHR_Blood or not sendServerCommand then return end
    sendServerCommand(player, "EHR_Sync", "UpdateModData", { EHR_Blood = data.EHR_Blood })
end

local function processPlayerBlood(player, shouldSync)
    if not player or not player:isAlive() then return end
    if not (EHR and EHR.Blood and EHR.Blood.UpdateBloodVolume) then return end

    local data = nil
    if EHR.GetPlayerData then
        data = EHR.GetPlayerData(player)
    end
    data = data or player:getModData()
    if not data then return end

    if not data.EHR_Blood then
        local username = nil
        pcall(function() username = player:getUsername() end)
        initializeBloodData(data, username, player)
    end

    local oldVolume = data.EHR_Blood and data.EHR_Blood.currentVolume or nil
    local wasBleeding = data.EHR_Blood and data.EHR_Blood.isCurrentlyBleeding == true

    local ok, err = pcall(function()
        EHR.Blood.UpdateBloodVolume(player, data)
    end)
    if not ok then
        log("[EHR Server] Blood progression failed: " .. tostring(err))
        return
    end

    local newVolume = data.EHR_Blood and data.EHR_Blood.currentVolume or nil
    local isBleedingNow = data.EHR_Blood and data.EHR_Blood.isCurrentlyBleeding == true

    if shouldSync and newVolume then
        local changed = oldVolume == nil or math.abs((newVolume or 0) - (oldVolume or 0)) >= 0.5
        if changed or wasBleeding or isBleedingNow then
            syncBloodDataToClient(player, data)
        end
    end
end

local function processPlayerMedication(player)
    if not player or not player:isAlive() then return end
    if EHR.Medication and EHR.Medication.Update then
        local ok, err = pcall(function()
            EHR.Medication.Update(player)
        end)
        if not ok then
            log("[EHR Server] Medication progression failed: " .. tostring(err))
        end
    end
end

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
            sepsis.lastHealthDamageHour = currentHour
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
                if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFeverIfStale then
                    EHR.BodyTemp.ResetDiseaseFeverIfStale(player, false)
                end
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

                if diseaseId == "cellulitis" and disease.stage >= 4 and not disease.cellulitisSepsisTriggered then
                    local hasTreatment = EHR.Disease
                        and EHR.Disease.HasActiveCurativeTreatment
                        and EHR.Disease.HasActiveCurativeTreatment(player, "cellulitis")

                    if hasTreatment then
                        disease.cellulitisSepsisBlockedByTreatment = true
                    else
                        disease.cellulitisSepsisTriggered = true
                        triggerCellulitisSepsisHandoff(player, {
                            sourceBodyPart = disease.sourceBodyPart or "cellulitis",
                        })
                    end
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
                    local nextStage = partData.stage + 1

                    if nextStage >= 4 then
                        -- Stage 4 is a handoff into systemic sepsis. Keep the
                        -- local wound severe so the UI does not stick at 100%.
                        if not data.EHR_Sepsis or not data.EHR_Sepsis.active then
                            data.EHR_Sepsis = {
                                active = true,
                                stage = 1,
                                startTime = currentHour,
                                stageStartTime = currentHour,
                                sourceBodyPart = partName,
                                treatmentDoses = 0,
                                lastHealthDamageHour = currentHour,
                                healthCap = nil,
                            }
                            data.EHR_Sepsis_Initialized = true
                            log("[EHR Server] Player " .. player:getUsername() .. " developed sepsis from wound " .. partName)
                        end

                        partData.stage = 3
                        partData.stageStartTime = currentHour
                        partData.sepsisTriggered = true
                        partData.lastSepsisTrigger = currentHour
                        log("[EHR Server] Player " .. player:getUsername() .. " wound " .. partName .. " handed off to sepsis")
                    else
                        partData.stage = nextStage
                        partData.stageStartTime = currentHour
                        log("[EHR Server] Player " .. player:getUsername() .. " wound " .. partName .. " progressed to stage " .. partData.stage)
                    end
                end
            end
        end

        -- Recalculate wound stats
        recalcWoundStats(data.EHR_WoundInfection)
    end

    -- Blood regeneration is handled by EHR.Blood.UpdateBloodVolume through
    -- EHR.Blood.ApplyBloodRegeneration. Keeping a second server-only regen here
    -- bypassed sandbox delay/healing checks and made MP players recover too fast.
    processPlayerMedication(player)
end

local function OnServerTick()
    -- Periodic sync
    syncTickCounter = syncTickCounter + 1
    if syncTickCounter >= SYNC_INTERVAL_TICKS then
        syncTickCounter = 0
        syncAllPlayers()
    end

    medicationTickCounter = medicationTickCounter + 1
    if medicationTickCounter >= MEDICATION_INTERVAL_TICKS then
        medicationTickCounter = 0

        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                processPlayerMedication(players:get(i))
            end
        end
    end

    bloodTickCounter = bloodTickCounter + 1
    bloodSyncTickCounter = bloodSyncTickCounter + 1
    if bloodTickCounter >= BLOOD_INTERVAL_TICKS then
        bloodTickCounter = 0

        local shouldSyncBlood = bloodSyncTickCounter >= BLOOD_SYNC_INTERVAL_TICKS
        if shouldSyncBlood then
            bloodSyncTickCounter = 0
        end

        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                processPlayerBlood(players:get(i), shouldSyncBlood)
            end
        end
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
