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
pcall(function() require "ExtensiveHealth/EHR_BodyTemperature" end)
pcall(function() require "ExtensiveHealth/EHR_KnoxCure" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
pcall(function() require "ExtensiveHealth/EHR_DiseaseFlyers" end)
pcall(function() require "ExtensiveHealth/EHR_Immunity" end)
pcall(function() require "ExtensiveHealth/EHR_PainkillerAddiction" end)
pcall(function() require "ExtensiveHealth/EHR_WatchBatteryCore" end)

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

    local directHealthMethods = {
        "getOverallBodyHealth",
        "getOverallHealth",
        "getHealth",
    }
    for _, methodName in ipairs(directHealthMethods) do
        local method = bodyDamage[methodName]
        if method then
            local okHealth, health = pcall(function()
                return method(bodyDamage)
            end)
            health = okHealth and tonumber(health) or nil
            if health then
                if health <= 1 then health = health * 100 end
                snapshot.overallHealth = math.max(0, math.min(100, health))
                break
            end
        end
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
                garlicFactor = tonumber(callBodyPartMethod(bodyPart, "getGarlicFactor", 0)) or 0,
            }
        end
    end

    return snapshot
end

local MEDICAL_MONITOR_WATCH_ITEMS = {
    ["ExtensiveHealth.EHRMedicalWatch_Left"] = true,
    ["ExtensiveHealth.EHRMedicalWatch_Right"] = true,
    EHRMedicalWatch_Left = true,
    EHRMedicalWatch_Right = true,
}

local function playerHasMedicalMonitorWatch(player)
    if not player or not player.getWornItems then return false end

    local okWorn, wornItems = pcall(function()
        return player:getWornItems()
    end)
    if not okWorn or not wornItems or not wornItems.size then return false end

    for i = 0, wornItems:size() - 1 do
        local item = nil
        pcall(function()
            item = wornItems:getItemByIndex(i)
        end)
        if item then
            local fullType = nil
            local itemType = nil
            pcall(function()
                if item.getFullType then fullType = item:getFullType() end
            end)
            pcall(function()
                if item.getType then itemType = item:getType() end
            end)
            if (fullType and MEDICAL_MONITOR_WATCH_ITEMS[fullType])
                    or (itemType and MEDICAL_MONITOR_WATCH_ITEMS[itemType]) then
                if not EHR.WatchBattery or EHR.WatchBattery.IsPowered(item) then return true end
            end
        end
    end

    return false
end

log("=========================================")
log("[EHR] EHR_ServerCommands.lua LOADING ON SERVER")
log("[EHR] isServer() = " .. tostring(isServer()))
log("[EHR] isClient() = " .. tostring(isClient()))
log("=========================================")
EHR.ServerCommands = {}
EHR.ServerCommands.RecentMedicationRequests = {}
EHR.ServerCommands.PendingExamConsents = {}
EHR.ServerCommands.ExamSessions = {}
EHR.ServerCommands.ExamRequestTimes = {}
EHR.ServerCommands.EnvironmentalSnapshotTimes = {}
EHR.ServerCommands.StitchRiskPermits = {}
EHR.ServerCommands.PendingMedicationConsents = {}
EHR.ServerCommands.PendingMedicationConsentByPair = {}
EHR.ServerCommands.MedicationActionPermits = {}
EHR.ServerCommands.NextMedicationActionId = 0

-- Network timed actions and overlapping vanilla consumption hooks can deliver
-- the same completed dose more than once. Keep a short server-side idempotency
-- window: normal pill actions take longer than this, while duplicate packets
-- and action relaunches arrive nearly together.
function EHR.ServerCommands.ClaimMedicationRequest(player, requestKey)
    if not player or not requestKey then return false end

    local now = getTimestampMs and getTimestampMs() or nil
    if not now then
        local gameTime = getGameTime and getGameTime() or nil
        now = gameTime and gameTime:getWorldAgeHours() * 3600000 or 0
    end

    local playerKey = nil
    pcall(function()
        if player.getOnlineID then playerKey = "id:" .. tostring(player:getOnlineID()) end
    end)
    if not playerKey then
        pcall(function()
            if player.getUsername then playerKey = "user:" .. tostring(player:getUsername()) end
        end)
    end
    playerKey = playerKey or tostring(player)

    local recent = EHR.ServerCommands.RecentMedicationRequests
    local playerRequests = recent[playerKey] or {}
    recent[playerKey] = playerRequests

    for key, timestamp in pairs(playerRequests) do
        if type(timestamp) ~= "number" or now < timestamp or (now - timestamp) > 10000 then
            playerRequests[key] = nil
        end
    end

    local previous = playerRequests[requestKey]
    if previous and (now - previous) < 2500 then
        return false
    end

    playerRequests[requestKey] = now
    return true
end

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
    data.EHR_WoundInfection.immuneContained = data.EHR_WoundInfection.immuneContained or {}
    data.EHR_WoundInfection.antisepticBlocked = data.EHR_WoundInfection.antisepticBlocked or {}
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
            EHR_KnoxHeraldRead = data.EHR_KnoxHeraldRead,
            EHR_KnoxKnowledgeSource = data.EHR_KnoxKnowledgeSource,
            EHR_CorpseSickness = data.EHR_CorpseSickness,
            EHR_KnoxCure = data.EHR_KnoxCure,
            EHR_Immunity = data.EHR_Immunity,
        }
        sendServerCommand(player, "EHR_Sync", "UpdateModData", ehrData)
        log("[EHR Server] Sent EHR data to client via sendServerCommand")
    end
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

local function findItemTypeInContainer(container, fullType, visited)
    if not container or not fullType then return nil, nil end
    visited = visited or {}
    if visited[container] then return nil, nil end
    visited[container] = true

    local items = container:getItems()
    if not items then return nil, nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local itemFullType = nil
            pcall(function() itemFullType = item:getFullType() end)
            if itemFullType == fullType then
                return item, container
            end

            local nestedContainer = nil
            if item.getInventory then
                local okNested, nested = pcall(function() return item:getInventory() end)
                if okNested then nestedContainer = nested end
            end
            if nestedContainer then
                local found, owner = findItemTypeInContainer(nestedContainer, fullType, visited)
                if found then return found, owner end
            end
        end
    end

    return nil, nil
end

local function findInventoryItemByFullType(player, fullType)
    if not player or not fullType then return nil, nil end
    local inventory = player:getInventory()
    if not inventory then return nil, nil end
    return findItemTypeInContainer(inventory, fullType, {})
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

local function getPlayerOnlineIDString(player)
    if not player or not player.getOnlineID then return nil end
    local ok, value = pcall(function() return player:getOnlineID() end)
    if not ok or value == nil then return nil end
    return tostring(value)
end

local function getPlayerUsernameString(player)
    if not player or not player.getUsername then return nil end
    local ok, value = pcall(function() return player:getUsername() end)
    if not ok or not value or value == "" then return nil end
    return tostring(value)
end

local function getPlayerNetworkKey(player)
    local onlineID = getPlayerOnlineIDString(player)
    local username = getPlayerUsernameString(player)
    if onlineID and username then return "id:" .. onlineID .. "|user:" .. username end
    if onlineID then return "id:" .. onlineID end
    if username then return "user:" .. username end
    return tostring(player)
end

local function getServerNowMs()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and value then return tonumber(value) or 0 end
    end
    local gameTime = getGameTime and getGameTime() or nil
    return gameTime and gameTime:getWorldAgeHours() * 3600000 or 0
end

-- Security-sensitive medical commands must never resolve by display name.
-- Online ID is authoritative; an accompanying username must agree with it.
local function findOnlinePlayerStrict(args, fallbackPlayer)
    if type(args) ~= "table" then return fallbackPlayer end

    local requestedID = args.targetOnlineID ~= nil and tostring(args.targetOnlineID) or nil
    local requestedUsername = args.targetUsername and tostring(args.targetUsername) or nil
    if not requestedID and not requestedUsername then return fallbackPlayer end

    local onlinePlayers = getOnlinePlayers and getOnlinePlayers() or nil
    if not onlinePlayers then return nil end

    local matched = nil
    for i = 0, onlinePlayers:size() - 1 do
        local candidate = onlinePlayers:get(i)
        if candidate then
            local candidateID = getPlayerOnlineIDString(candidate)
            local candidateUsername = getPlayerUsernameString(candidate)
            local idMatches = requestedID and candidateID == requestedID
            local usernameMatches = requestedUsername and candidateUsername == requestedUsername

            if requestedID then
                if idMatches then
                    if requestedUsername and not usernameMatches then return nil end
                    return candidate
                end
            elseif usernameMatches then
                if matched then return nil end -- Reject ambiguous usernames.
                matched = candidate
            end
        end
    end

    return matched
end

local function sendWatchBatteryState(player, watch)
    if not player or not watch or not EHR.WatchBattery or not EHR.WatchBattery.IsMedicalWatch(watch) then return end
    if not sendServerCommand then return end

    local state = EHR.WatchBattery.GetState(watch)
    if not state then return end
    local itemID = nil
    pcall(function() itemID = watch:getID() end)
    if itemID == nil then return end

    sendServerCommand(player, "EHR_WatchBattery", "Sync", {
        itemID = itemID,
        installed = state.installed == true,
        charge = tonumber(state.charge) or 0,
    })
end

local function getServerBatteryCharge(item)
    if not item or not item.getFullType or not EHR.WatchBattery then return 0 end
    if item:getFullType() ~= EHR.WatchBattery.BATTERY_TYPE then return 0 end
    local ok, value = pcall(function() return item:getCurrentUsesFloat() end)
    if not ok then return 0 end
    return math.max(0, math.min(1, tonumber(value) or 0))
end

function EHR.ServerCommands.InsertWatchBattery(player, args)
    if not player or not args or args.watchID == nil or args.batteryID == nil or not EHR.WatchBattery then return end

    local watch = findInventoryItemByID(player, args.watchID)
    local battery, batteryContainer = findInventoryItemByID(player, args.batteryID)
    if not EHR.WatchBattery.IsMedicalWatch(watch) then return end

    local state = EHR.WatchBattery.GetState(watch)
    local charge = getServerBatteryCharge(battery)
    if not state or state.installed or charge <= 0 then
        sendWatchBatteryState(player, watch)
        return
    end
    if not removeInventoryItem(battery, batteryContainer) then
        sendWatchBatteryState(player, watch)
        return
    end

    EHR.WatchBattery.SetState(watch, true, charge)
    sendWatchBatteryState(player, watch)
end

function EHR.ServerCommands.RemoveWatchBattery(player, args)
    if not player or not args or args.watchID == nil or not EHR.WatchBattery then return end

    local watch = findInventoryItemByID(player, args.watchID)
    if not EHR.WatchBattery.IsMedicalWatch(watch) then return end

    local state = EHR.WatchBattery.GetState(watch)
    if not state or not state.installed then
        sendWatchBatteryState(player, watch)
        return
    end

    local charge = state.charge
    EHR.WatchBattery.SetState(watch, false, 0)
    EHR.WatchBattery.DisableAlarm(watch)

    local inventory = player:getInventory()
    local battery = inventory and inventory:AddItem(EHR.WatchBattery.BATTERY_TYPE) or nil
    if battery and battery.setUsedDelta then
        pcall(function() battery:setUsedDelta(charge) end)
    end
    if battery then syncInventoryItemAdded(inventory, battery) end
    sendWatchBatteryState(player, watch)
end

local function visitServerContainer(container, callback, visited)
    if not container or not container.getItems then return end
    visited = visited or {}
    if visited[container] then return end
    visited[container] = true

    local items = container:getItems()
    if not items or not items.size then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            callback(item)
            if item.getInventory then
                local ok, nested = pcall(function() return item:getInventory() end)
                if ok and nested then visitServerContainer(nested, callback, visited) end
            end
        end
    end
end

function EHR.ServerCommands.RequestWatchBatterySync(player)
    if not player or not EHR.WatchBattery then return end
    visitServerContainer(player:getInventory(), function(item)
        if EHR.WatchBattery.IsMedicalWatch(item) then sendWatchBatteryState(player, item) end
    end)
end

local function drainOnlineWatchBatteries()
    if not (isServer and isServer()) then return end
    if not EHR.WatchBattery or not getOnlinePlayers then return end
    local players = getOnlinePlayers()
    if not players then return end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        for _, watch in ipairs(EHR.WatchBattery.GetWornMedicalWatches(player)) do
            local changed, depleted = EHR.WatchBattery.Drain(watch, EHR.WatchBattery.TEN_MINUTE_HOURS)
            if changed then
                if depleted then EHR.WatchBattery.DisableAlarm(watch) end
                sendWatchBatteryState(player, watch)
            end
        end
    end
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
    local remaining = math.floor((currentUsesFloat / useDelta) + 0.5)
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

local function setSterilizedBandagePackRemaining(pack, remaining)
    if not pack then return false end
    local _, maxDoses, useDelta = getSterilizedBandagePackDoseInfo(pack)
    remaining = math.max(0, math.min(maxDoses, math.floor((tonumber(remaining) or 0) + 0.0001)))

    local usedDelta = remaining * useDelta
    if remaining >= maxDoses then
        usedDelta = 1.0
    end
    usedDelta = math.max(0, math.min(1.0, usedDelta))

    if pack.setUsedDelta then
        local ok = pcall(function() pack:setUsedDelta(usedDelta) end)
        if ok then
            syncInventoryItem(pack)
            return true
        end
    end
    return false
end

local function findSterilizedBandagePackWithSpace(container, visited)
    if not container then return nil, nil end
    visited = visited or {}
    if visited[container] then return nil, nil end
    visited[container] = true

    local items = container.getItems and container:getItems() or nil
    if not items or not items.size then return nil, nil end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if item.getFullType and item:getFullType() == "ExtensiveHealth.SterilizedBandages" then
                local remaining, maxDoses = getSterilizedBandagePackDoseInfo(item)
                if remaining < maxDoses then
                    return item, container
                end
            end

            local nestedContainer = nil
            if item.getInventory then
                local okNested, nested = pcall(function() return item:getInventory() end)
                if okNested then nestedContainer = nested end
            end
            if nestedContainer then
                local found, owner = findSterilizedBandagePackWithSpace(nestedContainer, visited)
                if found then return found, owner end
            end
        end
    end

    return nil, nil
end

function EHR.ServerCommands.AddCleanBandageToPack(player, args)
    if not player or not args or args.bandageID == nil then return false end

    local bandage, bandageContainer = findInventoryItemByID(player, args.bandageID)
    if not bandage or not bandage.getFullType or bandage:getFullType() ~= "Base.Bandage" then
        return false
    end

    local inventory = player:getInventory()
    if not inventory then return false end

    local explicitPack = args.packID ~= nil
    local pack, packContainer = nil, nil
    if explicitPack then
        pack, packContainer = findInventoryItemByID(player, args.packID)
        if not pack or not pack.getFullType or pack:getFullType() ~= "ExtensiveHealth.SterilizedBandages" then
            return false
        end
    else
        pack, packContainer = findSterilizedBandagePackWithSpace(inventory, {})
    end

    if not pack then
        local okAdd, newPack = pcall(function() return inventory:AddItem("ExtensiveHealth.SterilizedBandages") end)
        if not okAdd or not newPack then return false end
        pack = newPack
        packContainer = inventory
        setSterilizedBandagePackRemaining(pack, 0)
        syncInventoryItemAdded(inventory, pack)
    end

    local remaining, maxDoses = getSterilizedBandagePackDoseInfo(pack)
    if remaining >= maxDoses then return false end
    if not removeInventoryItem(bandage, bandageContainer) then return false end

    setSterilizedBandagePackRemaining(pack, remaining + 1)
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
    return false
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

local BLOOD_SPOILAGE_SEVERITY = {
    fresh = 0,
    stale = 1,
    rotten = 2,
}

local function combineBloodSpoilageState(currentState, candidateState)
    local currentSeverity = BLOOD_SPOILAGE_SEVERITY[currentState] or 0
    local candidateSeverity = BLOOD_SPOILAGE_SEVERITY[candidateState]
    if candidateSeverity and candidateSeverity > currentSeverity then
        return candidateState
    end
    return BLOOD_SPOILAGE_SEVERITY[currentState] and currentState or "fresh"
end

local function getServerSpoilageState(item, clientState)
    if not item then return "rotten" end

    -- Never let a client-provided state improve the server-observed state. The
    -- worst valid state from modData, the Food API and the request wins.
    local resolvedState = "fresh"
    local md = nil
    pcall(function() md = item:getModData() end)
    local spoilage = md and md.EHR_BloodSpoilage or nil
    if spoilage then
        if spoilage.stale then
            resolvedState = combineBloodSpoilageState(resolvedState, "stale")
        end
        if spoilage.rotten then
            resolvedState = combineBloodSpoilageState(resolvedState, "rotten")
        end
    end

    if item.isRotten then
        local okRotten, rotten = pcall(function() return item:isRotten() end)
        if okRotten and rotten then
            resolvedState = combineBloodSpoilageState(resolvedState, "rotten")
        end
    end
    if item.isFresh then
        local okFresh, fresh = pcall(function() return item:isFresh() end)
        if okFresh and fresh == false then
            resolvedState = combineBloodSpoilageState(resolvedState, "stale")
        end
    end

    return combineBloodSpoilageState(resolvedState, clientState)
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

    if not EHR.ServerCommands.ClaimMedicationRequest(player, "item:" .. tostring(args.itemID)) then
        log("[EHR Server] Ignored duplicate medication request for item " .. tostring(args.itemID))
        syncModDataToClient(player)
        return
    end

    local ok, result = pcall(function()
        return EHR.Medication.UseMedication(player, item)
    end)
    if not ok then
        log("[EHR Server] UseMedication failed: " .. tostring(result))
    end

    -- ConsumeOneDose owns both drainable-stat and final-removal replication.
    -- Sending the same item stats again here created a second competing update.
    syncModDataToClient(player)
end

function EHR.ServerCommands.UseConsumedMedication(player, args)
    if not player or not args or not args.itemFullType then return end
    if not EHR.Medication or not EHR.Medication.UseConsumedMedication then
        log("[EHR Server] UseConsumedMedication rejected: medication module unavailable")
        return
    end


    local itemFullType = tostring(args.itemFullType)
    if not EHR.ServerCommands.ClaimMedicationRequest(player, "consumed:" .. itemFullType) then
        log("[EHR Server] Ignored duplicate vanilla medication effect for " .. itemFullType)
        syncModDataToClient(player)
        return
    end

    local ok, result = pcall(function()
        return EHR.Medication.UseConsumedMedication(player, itemFullType)
    end)
    if not ok then
        log("[EHR Server] UseConsumedMedication failed: " .. tostring(result))
    end

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

    -- The client normally sends on change or a 15-second heartbeat. Keep a
    -- server-side floor as protection against outdated or modified clients
    -- flooding the command dispatcher.
    local playerKey = getPlayerNetworkKey(player)
    local nowMs = getServerNowMs()
    local previousMs = EHR.ServerCommands.EnvironmentalSnapshotTimes[playerKey]
    if previousMs and nowMs >= previousMs and (nowMs - previousMs) < 1000 then
        return
    end
    EHR.ServerCommands.EnvironmentalSnapshotTimes[playerKey] = nowMs

    local ok, result = pcall(function()
        return EHR.Environmental.StoreClientSnapshot(player, args or {})
    end)
    if not ok then
        log("[EHR Server] EnvironmentalSnapshot failed: " .. tostring(result))
    end
end

local HEAT_STROKE_BATH_DURATION_HOURS = 3.0
local HEAT_STROKE_BATH_COMPLETION_TOLERANCE_HOURS = 0.1
local HEAT_STROKE_BATH_HEARTBEAT_GRACE_HOURS = 0.25
local HEAT_STROKE_BATH_MAIN_SPRITES = {
    fixtures_bathroom_01_25 = true,
    fixtures_bathroom_01_26 = true,
    fixtures_bathroom_01_52 = true,
    fixtures_bathroom_01_55 = true,
}

local function heatStrokeBathCurrentHour()
    local gameTime = getGameTime and getGameTime() or nil
    return gameTime and gameTime:getWorldAgeHours() or 0
end

local function clearHeatStrokeBathServerState(player)
    local modData = player and player.getModData and player:getModData() or nil
    if not modData then return end

    modData.EHR_HeatStrokeColdBathActive = nil
    modData.EHR_HeatStrokeColdBathUntil = nil
    modData.EHR_HeatStrokeColdBathStartHour = nil
    modData.EHR_HeatStrokeColdBathX = nil
    modData.EHR_HeatStrokeColdBathY = nil
    modData.EHR_HeatStrokeColdBathZ = nil
end

local function getHeatStrokeDisease(player)
    if not (player and EHR.Disease and EHR.Disease.GetDiseaseData) then return nil end
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    return diseaseData and diseaseData.active and diseaseData.active.heat_stroke or nil
end

local function heatStrokeBathSpriteName(object)
    if not object then return nil end
    local sprite = nil
    pcall(function() sprite = object:getSprite() end)
    if not sprite then return nil end

    local name = nil
    pcall(function() name = sprite:getName() end)
    return name and tostring(name) or nil
end

local function squareHasHeatStrokeBath(square)
    if not square then return false end

    local objects = nil
    pcall(function() objects = square:getObjects() end)
    if not objects then return false end

    for i = 0, objects:size() - 1 do
        if HEAT_STROKE_BATH_MAIN_SPRITES[heatStrokeBathSpriteName(objects:get(i))] then
            return true
        end
    end
    return false
end

local function validateHeatStrokeBath(player, args)
    if not player or type(args) ~= "table" then return false end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if not x or not y or not z then return false end
    if x ~= math.floor(x) or y ~= math.floor(y) or z ~= math.floor(z) then return false end

    local playerX, playerY, playerZ = nil, nil, nil
    local gotPlayerPosition = pcall(function()
        playerX = player:getX()
        playerY = player:getY()
        playerZ = player:getZ()
    end)
    if not gotPlayerPosition or not playerX or not playerY or not playerZ then return false end
    if math.abs(playerZ - z) > 0.01 then return false end

    local dx = playerX - x
    local dy = playerY - y
    if (dx * dx) + (dy * dy) > 9 then return false end

    local cell = getCell and getCell() or nil
    if not cell then return false end

    local square = nil
    local gotSquare = pcall(function() square = cell:getGridSquare(x, y, z) end)
    return gotSquare and squareHasHeatStrokeBath(square)
end

local function sameHeatStrokeBath(modData, args)
    return tonumber(modData.EHR_HeatStrokeColdBathX) == tonumber(args.x)
        and tonumber(modData.EHR_HeatStrokeColdBathY) == tonumber(args.y)
        and tonumber(modData.EHR_HeatStrokeColdBathZ) == tonumber(args.z)
end

local function resetHeatStrokeAfterBath(player, now)
    if EHR.Environmental then
        if EHR.Environmental.InitializePlayer then
            pcall(EHR.Environmental.InitializePlayer, player)
        end

        local exposure = EHR.Environmental.GetExposureData and EHR.Environmental.GetExposureData(player) or nil
        if exposure then
            exposure.heatExposure = 0
            exposure.heatStrokeExposure = 0
            exposure.lastHeatStrokeRiskCheck = now
        end

        if EHR.Environmental.SetHeatStrokeSleepRegenSuppressed then
            pcall(EHR.Environmental.SetHeatStrokeSleepRegenSuppressed, player, false)
        end
        if EHR.Environmental.ClearHeatMovementPenalty then
            pcall(EHR.Environmental.ClearHeatMovementPenalty, player)
        end
    end

    if EHR.BodyTemp then
        if EHR.BodyTemp.WriteDiseaseBodyTemperature then
            pcall(EHR.BodyTemp.WriteDiseaseBodyTemperature, player, 37.0)
        end

        local tempData = EHR.BodyTemp.GetTemperatureData and EHR.BodyTemp.GetTemperatureData(player) or nil
        if tempData then
            tempData.bodyTemp = 37.0
            tempData.diseaseTargetTemp = nil
            tempData.diseaseTargetTempUntil = nil
        end

        if EHR.BodyTemp.ResetDiseaseFeverIfStale then
            pcall(EHR.BodyTemp.ResetDiseaseFeverIfStale, player, true)
        end
    end
end

function EHR.ServerCommands.HeatStrokeBath(player, args)
    if not player or type(args) ~= "table" then return end

    local action = tostring(args.action or "")
    local modData = player:getModData()
    local now = heatStrokeBathCurrentHour()

    if action == "stop" then
        clearHeatStrokeBathServerState(player)
        return
    end

    if action == "start" then
        if not getHeatStrokeDisease(player) or not validateHeatStrokeBath(player, args) then
            clearHeatStrokeBathServerState(player)
            syncModDataToClient(player)
            log("[EHR Server] HeatStrokeBath start rejected")
            return
        end

        modData.EHR_HeatStrokeColdBathActive = true
        modData.EHR_HeatStrokeColdBathUntil = now + HEAT_STROKE_BATH_HEARTBEAT_GRACE_HOURS
        modData.EHR_HeatStrokeColdBathStartHour = now
        modData.EHR_HeatStrokeColdBathX = tonumber(args.x)
        modData.EHR_HeatStrokeColdBathY = tonumber(args.y)
        modData.EHR_HeatStrokeColdBathZ = tonumber(args.z)
        log("[EHR Server] HeatStrokeBath started for " .. tostring(player:getUsername()))
        return
    end

    local activeUntil = tonumber(modData.EHR_HeatStrokeColdBathUntil) or 0
    local bathIsActive = modData.EHR_HeatStrokeColdBathActive == true
        and activeUntil > now
        and sameHeatStrokeBath(modData, args)
        and getHeatStrokeDisease(player) ~= nil
        and validateHeatStrokeBath(player, args)

    if action == "heartbeat" then
        if bathIsActive then
            modData.EHR_HeatStrokeColdBathUntil = now + HEAT_STROKE_BATH_HEARTBEAT_GRACE_HOURS
        else
            clearHeatStrokeBathServerState(player)
        end
        return
    end

    if action ~= "complete" then return end

    local startedAt = tonumber(modData.EHR_HeatStrokeColdBathStartHour) or now
    local minimumDuration = HEAT_STROKE_BATH_DURATION_HOURS - HEAT_STROKE_BATH_COMPLETION_TOLERANCE_HOURS
    if not bathIsActive or (now - startedAt) < minimumDuration then
        clearHeatStrokeBathServerState(player)
        syncModDataToClient(player)
        log("[EHR Server] HeatStrokeBath completion rejected")
        return
    end

    local cured = false
    if EHR.Disease and EHR.Disease.Cure then
        local ok, result = pcall(EHR.Disease.Cure, player, "heat_stroke")
        cured = ok and result == true
    end

    if cured then
        resetHeatStrokeAfterBath(player, now)
    end
    clearHeatStrokeBathServerState(player)
    syncModDataToClient(player)
    log("[EHR Server] HeatStrokeBath completed for " .. tostring(player:getUsername())
        .. ", cured=" .. tostring(cured))
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

    local itemName = string.sub(tostring(args.itemName or "unknown"), 1, 128)
    local applied = 0
    local processed = 0
    for _, foodRisk in ipairs(risks) do
        if processed >= 3 then break end
        processed = processed + 1
        if type(foodRisk) == "table" then
            local diseaseId = tostring(foodRisk.diseaseId or "")
            local reason = tostring(foodRisk.reason or "food")
            local suppliedChance = math.max(0, math.min(1, tonumber(foodRisk.chance) or 0))
            local chance, rejectionReason, clamped = EHR.Disease.ValidateFoodDiseaseRisk(
                diseaseId,
                reason,
                suppliedChance
            )
            if chance then
                if clamped then
                    log(string.format(
                        "[EHR Server] FoodDiseaseRisk clamped: disease=%s reason=%s supplied=%.4f accepted=%.4f",
                        diseaseId,
                        reason,
                        suppliedChance,
                        chance
                    ))
                end
                local ok, result = pcall(function()
                    return EHR.Disease.ApplyFoodDiseaseRisk(player, itemName, diseaseId, reason, chance)
                end)
                if ok then
                    applied = applied + 1
                else
                    log("[EHR Server] FoodDiseaseRisk failed for " .. tostring(diseaseId) .. ": " .. tostring(result))
                end
            elseif suppliedChance > 0 then
                log(string.format(
                    "[EHR Server] FoodDiseaseRisk rejected: disease=%s reason=%s rejection=%s",
                    diseaseId,
                    reason,
                    tostring(rejectionReason or "invalid risk")
                ))
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

local function resolveWoundBodyPartType(partName)
    if not BodyPartType or not partName then return nil end
    partName = tostring(partName)

    local partType = BodyPartType[partName]
    if not partType and BodyPartType.FromString then
        local ok, result = pcall(function() return BodyPartType.FromString(partName) end)
        if ok then partType = result end
    end

    if not partType or tostring(partType) == "MAX" or tostring(partType) ~= partName then
        return nil
    end
    return partType
end

local function playersAreCloseEnoughForTreatment(doctor, patient)
    if not doctor or not patient then return false end
    if doctor == patient then return true end

    local ok, closeEnough = pcall(function()
        if doctor.getVehicle and patient.getVehicle then
            local doctorVehicle = doctor:getVehicle()
            if doctorVehicle and doctorVehicle == patient:getVehicle() then
                return true
            end
        end
        if math.abs((doctor:getZ() or 0) - (patient:getZ() or 0)) > 0.01 then return false end
        local dx = (doctor:getX() or 0) - (patient:getX() or 0)
        local dy = (doctor:getY() or 0) - (patient:getY() or 0)
        return (dx * dx + dy * dy) <= 9
    end)
    return ok and closeEnough == true
end

local EXAM_CONSENT_TTL_MS = 45000
local EXAM_SESSION_TTL_MS = 300000
local EXAM_REQUEST_MIN_INTERVAL_MS = 750
local STITCH_RISK_PERMIT_TTL_MS = 180000
local STITCH_ROUGH_CELLULITIS_CHANCE = 0.40
local MEDICATION_CONSENT_TTL_MS = 45000
local MEDICATION_ACTION_TTL_MS = 180000

local function medicalPairKey(doctor, patient)
    if not doctor or not patient then return nil end
    return getPlayerNetworkKey(doctor) .. "->" .. getPlayerNetworkKey(patient)
end

local function pruneTimedEntries(entries, nowMs)
    for key, entry in pairs(entries or {}) do
        local expiresAt = type(entry) == "table" and tonumber(entry.expiresAt) or tonumber(entry)
        if not expiresAt or nowMs < 0 or nowMs > expiresAt then
            entries[key] = nil
        end
    end
end

local function hasActiveExamSession(doctor, patient, refresh)
    if not doctor or not patient then return false end
    if doctor == patient then return true end
    if not playersAreCloseEnoughForTreatment(doctor, patient) then return false end

    local nowMs = getServerNowMs()
    local pairKey = medicalPairKey(doctor, patient)
    local session = pairKey and EHR.ServerCommands.ExamSessions[pairKey] or nil
    if not session or nowMs > (tonumber(session.expiresAt) or 0) then
        if pairKey then EHR.ServerCommands.ExamSessions[pairKey] = nil end
        return false
    end

    if refresh then
        session.expiresAt = nowMs + EXAM_SESSION_TTL_MS
        session.lastUsedAt = nowMs
    end
    return true
end

function EHR.ServerCommands.BeginExamConsent(player, args)
    if not player then return end
    local patient = findOnlinePlayerStrict(args, nil)
    if not patient or patient == player then return end
    if not playersAreCloseEnoughForTreatment(player, patient) then return end

    local pairKey = medicalPairKey(player, patient)
    if not pairKey then return end
    local nowMs = getServerNowMs()
    EHR.ServerCommands.PendingExamConsents[pairKey] = {
        doctorKey = getPlayerNetworkKey(player),
        patientKey = getPlayerNetworkKey(patient),
        expiresAt = nowMs + EXAM_CONSENT_TTL_MS,
    }
end

function EHR.ServerCommands.GrantExamConsent(patient, args)
    if not patient then return end

    local doctorArgs = {
        targetOnlineID = args and args.doctorOnlineID,
        targetUsername = args and args.doctorUsername,
    }
    local doctor = findOnlinePlayerStrict(doctorArgs, nil)
    if not doctor or doctor == patient then return end

    local pairKey = medicalPairKey(doctor, patient)
    local nowMs = getServerNowMs()
    local pending = pairKey and EHR.ServerCommands.PendingExamConsents[pairKey] or nil
    if pending and nowMs > (tonumber(pending.expiresAt) or 0) then
        EHR.ServerCommands.PendingExamConsents[pairKey] = nil
        pending = nil
    end
    if not playersAreCloseEnoughForTreatment(doctor, patient) then
        if pairKey then EHR.ServerCommands.PendingExamConsents[pairKey] = nil end
        return
    end

    -- The command sender is the patient. This is sufficient proof of consent
    -- even for a normal vanilla Medical Check that did not start through EHR.
    -- A doctor cannot manufacture this packet on the patient's connection.
    if pairKey then EHR.ServerCommands.PendingExamConsents[pairKey] = nil end
    EHR.ServerCommands.ExamSessions[pairKey] = {
        doctorKey = getPlayerNetworkKey(doctor),
        patientKey = getPlayerNetworkKey(patient),
        grantedBy = getPlayerNetworkKey(patient),
        grantedAt = nowMs,
        lastUsedAt = nowMs,
        expiresAt = nowMs + EXAM_SESSION_TTL_MS,
    }

    sendServerCommand(doctor, "EHR_Exam", "ExamSessionGranted", {
        targetOnlineID = getPlayerOnlineIDString(patient),
        targetUsername = getPlayerUsernameString(patient),
        expiresInMs = EXAM_SESSION_TTL_MS,
    })
end

function EHR.ServerCommands.DenyExamConsent(patient, args)
    if not patient then return end
    local doctor = findOnlinePlayerStrict({
        targetOnlineID = args and args.doctorOnlineID,
        targetUsername = args and args.doctorUsername,
    }, nil)
    if not doctor or doctor == patient then return end

    local pairKey = medicalPairKey(doctor, patient)
    if not pairKey or not EHR.ServerCommands.PendingExamConsents[pairKey] then return end
    EHR.ServerCommands.PendingExamConsents[pairKey] = nil
    sendServerCommand(doctor, "EHR_Exam", "ExamSessionDenied", {
        targetOnlineID = getPlayerOnlineIDString(patient),
        targetUsername = getPlayerUsernameString(patient),
    })
end

function EHR.ServerCommands.EndExamSession(player, args)
    if not player then return end
    local patient = findOnlinePlayerStrict(args, nil)
    local pairKey = patient and medicalPairKey(player, patient) or nil
    if pairKey then
        EHR.ServerCommands.ExamSessions[pairKey] = nil
        EHR.ServerCommands.ExamRequestTimes[pairKey] = nil
    end
end

local function medicationConsentKey(doctor, patient, requestId)
    local pairKey = medicalPairKey(doctor, patient)
    if not pairKey or requestId == nil then return nil end
    return pairKey .. ":" .. tostring(requestId)
end

local function getServerMedicationAdminType(medData)
    if not medData then return "default" end
    if medData.adminType then return tostring(medData.adminType) end
    if medData.requiresIVKit then return "iv" end
    if medData.isEmergency then return "emergency" end
    if medData.requiresSyringe then return "injection" end
    if medData.isTopical then return "cream" end

    local name = string.lower(tostring(medData.displayName or ""))
    if string.find(name, "inhaler", 1, true) then return "inhaler" end
    if string.find(name, "cream", 1, true) or string.find(name, "ointment", 1, true) then return "cream" end
    if string.find(name, "syrup", 1, true) or string.find(name, "liquid", 1, true) then return "liquid" end
    if string.find(name, "capsule", 1, true) then return "capsule" end
    return "pill"
end

local REMOTE_TREATMENT_KIND_MEDICATION = "medication"
local REMOTE_TREATMENT_KIND_BLOOD = "blood_transfusion"

local function getServerBloodBagType(fullType)
    if not fullType or not EHR.Blood or not EHR.Blood.BloodBagTypes then return nil end
    return EHR.Blood.BloodBagTypes[fullType]
end

local function getServerTreatmentAdminType(treatmentKind, medData)
    if treatmentKind == REMOTE_TREATMENT_KIND_BLOOD then return "iv" end
    return getServerMedicationAdminType(medData)
end

local function getServerTreatmentDisplayName(item, fullType, treatmentKind, medData)
    if treatmentKind == REMOTE_TREATMENT_KIND_MEDICATION then
        return EHR.Medication.GetDisplayName
            and EHR.Medication.GetDisplayName(fullType, medData)
            or medData.displayName or fullType
    end

    local displayName = nil
    if item and item.getDisplayName then
        pcall(function() displayName = item:getDisplayName() end)
    end
    return displayName or fullType
end

local function sendMedicationRequestRejected(doctor, requestId, reason, command)
    if not doctor or not sendServerCommand then return end
    sendServerCommand(doctor, "EHR_Exam", command or "MedicationRequestRejected", {
        requestId = requestId,
        reason = tostring(reason or "Medication administration request rejected"),
    })
end

local function validateRemoteTreatment(doctor, patient, itemID, expectedFullType,
        expectedTreatmentKind, previousSpoilageState, expectedIVKitID)
    if not doctor or not patient or doctor == patient then
        return nil, nil, nil, nil, nil, "Invalid doctor or patient"
    end
    if not hasActiveExamSession(doctor, patient, true) then
        return nil, nil, nil, nil, nil, "Examination session is not authorized or patient is out of range"
    end

    local doctorDead = false
    local patientDead = false
    pcall(function() doctorDead = doctor:isDead() end)
    pcall(function() patientDead = patient:isDead() end)
    if doctorDead or patientDead then
        return nil, nil, nil, nil, nil, "Doctor or patient is no longer available"
    end

    local item = itemID ~= nil and findInventoryItemByID(doctor, itemID) or nil
    if not item then
        return nil, nil, nil, nil, nil, "Treatment item is no longer in the doctor's inventory"
    end

    local fullType = item.getFullType and item:getFullType() or nil
    if not fullType or (expectedFullType and tostring(fullType) ~= tostring(expectedFullType)) then
        return nil, nil, nil, nil, nil, "Treatment item changed"
    end

    local treatmentKind = getServerBloodBagType(fullType)
        and REMOTE_TREATMENT_KIND_BLOOD or REMOTE_TREATMENT_KIND_MEDICATION
    if expectedTreatmentKind and treatmentKind ~= expectedTreatmentKind then
        return nil, nil, nil, nil, nil, "Treatment type changed"
    end

    if treatmentKind == REMOTE_TREATMENT_KIND_BLOOD then
        local spoilageState = getServerSpoilageState(item, previousSpoilageState)
        if spoilageState == "rotten" then
            return nil, nil, nil, nil, nil, "Rotten blood cannot be administered"
        end

        local ivKit = nil
        if expectedIVKitID ~= nil then
            ivKit = findInventoryItemByID(doctor, expectedIVKitID)
            local ivKitType = ivKit and ivKit.getFullType and ivKit:getFullType() or nil
            if ivKitType ~= "ExtensiveHealth.IVKit" then
                return nil, nil, nil, nil, nil, "IV Administration Kit is no longer available"
            end
        else
            ivKit = findInventoryItemByFullType(doctor, "ExtensiveHealth.IVKit")
            if not ivKit then
                return nil, nil, nil, nil, nil, "Requires IV Administration Kit"
            end
        end

        return item, nil, treatmentKind, spoilageState, ivKit, nil
    end

    local medData = EHR.Medication and EHR.Medication.Database and EHR.Medication.Database[fullType] or nil
    if not medData then
        return nil, nil, nil, nil, nil, "Item is not a recognized medication"
    end
    if medData.remoteAdministration == false then
        return nil, nil, nil, nil, nil, "This medication cannot be administered to another player"
    end

    if EHR.Medication.GetItemDoseInfo then
        local okDose, doseInfo = pcall(EHR.Medication.GetItemDoseInfo, item)
        if okDose and doseInfo and (tonumber(doseInfo.remainingDoses) or 0) <= 0 then
            return nil, nil, nil, nil, nil, "Medication package is empty"
        end
    end

    if EHR.Medication.CanUseMedication then
        local okCanUse, canUse, reason = pcall(EHR.Medication.CanUseMedication, patient, item, doctor)
        if not okCanUse then
            return nil, nil, nil, nil, nil, "Medication validation failed"
        end
        if canUse ~= true then
            return nil, nil, nil, nil, nil, tostring(reason or "Medication cannot be used right now")
        end
    end

    return item, medData, treatmentKind, nil, nil, nil
end

function EHR.ServerCommands.RequestAdministerMedication(doctor, args)
    if not doctor or type(args) ~= "table" then return end
    local requestId = math.floor(tonumber(args.requestId) or -1)
    if requestId < 1 or requestId > 1000000000 then return end

    local patient = findOnlinePlayerStrict(args, nil)
    if not patient or patient == doctor then
        sendMedicationRequestRejected(doctor, requestId, "Patient is unavailable")
        return
    end

    local item, medData, treatmentKind, spoilageState, _, reason = validateRemoteTreatment(
        doctor, patient, args.itemID, args.itemFullType, nil, args.spoilageState, nil
    )
    if not item then
        sendMedicationRequestRejected(doctor, requestId, reason)
        return
    end

    local pairKey = medicalPairKey(doctor, patient)
    local consentKey = medicationConsentKey(doctor, patient, requestId)
    if not pairKey or not consentKey then return end

    local previousKey = EHR.ServerCommands.PendingMedicationConsentByPair[pairKey]
    if previousKey and previousKey ~= consentKey then
        EHR.ServerCommands.PendingMedicationConsents[previousKey] = nil
    end

    local nowMs = getServerNowMs()
    local fullType = item:getFullType()
    local medicationName = getServerTreatmentDisplayName(item, fullType, treatmentKind, medData)
    if treatmentKind == REMOTE_TREATMENT_KIND_BLOOD and spoilageState == "stale" then
        medicationName = tostring(medicationName) .. " - "
            .. serverText("UI_EHR_Transfusion_StaleSuffix", "STALE!")
    end
    local adminType = getServerTreatmentAdminType(treatmentKind, medData)

    EHR.ServerCommands.PendingMedicationConsents[consentKey] = {
        requestId = requestId,
        doctorKey = getPlayerNetworkKey(doctor),
        patientKey = getPlayerNetworkKey(patient),
        doctorOnlineID = getPlayerOnlineIDString(doctor),
        doctorUsername = getPlayerUsernameString(doctor),
        patientOnlineID = getPlayerOnlineIDString(patient),
        patientUsername = getPlayerUsernameString(patient),
        itemID = item:getID(),
        itemFullType = fullType,
        medicationName = tostring(medicationName),
        adminType = adminType,
        treatmentKind = treatmentKind,
        spoilageState = spoilageState,
        expiresAt = nowMs + MEDICATION_CONSENT_TTL_MS,
    }
    EHR.ServerCommands.PendingMedicationConsentByPair[pairKey] = consentKey

    sendServerCommand(patient, "EHR_Exam", "MedicationConsentRequest", {
        requestId = requestId,
        doctorOnlineID = getPlayerOnlineIDString(doctor),
        doctorUsername = getPlayerUsernameString(doctor),
        doctorDisplayName = getPlayerUsernameString(doctor),
        medicationName = tostring(medicationName),
        itemFullType = fullType,
        adminType = adminType,
        treatmentKind = treatmentKind,
        spoilageState = spoilageState,
        expiresInMs = MEDICATION_CONSENT_TTL_MS,
    })
end

function EHR.ServerCommands.RespondAdministerMedicationConsent(patient, args)
    if not patient or type(args) ~= "table" then return end
    local requestId = math.floor(tonumber(args.requestId) or -1)
    if requestId < 1 then return end

    local doctor = findOnlinePlayerStrict({
        targetOnlineID = args.doctorOnlineID,
        targetUsername = args.doctorUsername,
    }, nil)
    if not doctor or doctor == patient then return end

    local pairKey = medicalPairKey(doctor, patient)
    local consentKey = medicationConsentKey(doctor, patient, requestId)
    local pending = consentKey and EHR.ServerCommands.PendingMedicationConsents[consentKey] or nil
    local nowMs = getServerNowMs()
    if not pending or pending.patientKey ~= getPlayerNetworkKey(patient)
            or pending.doctorKey ~= getPlayerNetworkKey(doctor)
            or nowMs > (tonumber(pending.expiresAt) or 0) then
        if consentKey then EHR.ServerCommands.PendingMedicationConsents[consentKey] = nil end
        sendMedicationRequestRejected(doctor, requestId, "Medication consent request expired")
        return
    end

    EHR.ServerCommands.PendingMedicationConsents[consentKey] = nil
    if pairKey and EHR.ServerCommands.PendingMedicationConsentByPair[pairKey] == consentKey then
        EHR.ServerCommands.PendingMedicationConsentByPair[pairKey] = nil
    end

    if args.accepted ~= true then
        sendMedicationRequestRejected(doctor, requestId, "Patient declined the medication", "MedicationConsentDenied")
        return
    end

    local item, medData, treatmentKind, spoilageState, ivKit, reason = validateRemoteTreatment(
        doctor, patient, pending.itemID, pending.itemFullType,
        pending.treatmentKind, pending.spoilageState, nil
    )
    if not item then
        sendMedicationRequestRejected(doctor, requestId, reason)
        return
    end

    EHR.ServerCommands.NextMedicationActionId = (EHR.ServerCommands.NextMedicationActionId % 1000000000) + 1
    local actionId = EHR.ServerCommands.NextMedicationActionId
    local adminType = getServerTreatmentAdminType(treatmentKind, medData)
    local ivKitID = nil
    if ivKit and ivKit.getID then
        local okIVKitID = pcall(function() ivKitID = ivKit:getID() end)
        if not okIVKitID or ivKitID == nil then
            sendMedicationRequestRejected(doctor, requestId, "IV Administration Kit could not be reserved")
            return
        end
    end
    EHR.ServerCommands.MedicationActionPermits[tostring(actionId)] = {
        actionId = actionId,
        requestId = requestId,
        doctorKey = getPlayerNetworkKey(doctor),
        patientKey = getPlayerNetworkKey(patient),
        patientOnlineID = getPlayerOnlineIDString(patient),
        patientUsername = getPlayerUsernameString(patient),
        itemID = item:getID(),
        itemFullType = item:getFullType(),
        medicationName = pending.medicationName,
        adminType = adminType,
        treatmentKind = treatmentKind,
        spoilageState = spoilageState,
        ivKitID = ivKitID,
        expiresAt = nowMs + MEDICATION_ACTION_TTL_MS,
    }

    sendServerCommand(doctor, "EHR_Exam", "MedicationConsentGranted", {
        requestId = requestId,
        actionId = actionId,
        targetOnlineID = getPlayerOnlineIDString(patient),
        targetUsername = getPlayerUsernameString(patient),
        itemID = item:getID(),
        itemFullType = item:getFullType(),
        medicationName = pending.medicationName,
        adminType = adminType,
        treatmentKind = treatmentKind,
        spoilageState = spoilageState,
        expiresInMs = MEDICATION_ACTION_TTL_MS,
    })
end

function EHR.ServerCommands.CancelAdministerMedicationRequest(doctor, args)
    if not doctor or type(args) ~= "table" then return end
    local requestId = math.floor(tonumber(args.requestId) or -1)
    if requestId < 1 then return end
    local patient = findOnlinePlayerStrict(args, nil)
    if not patient or patient == doctor then return end

    local pairKey = medicalPairKey(doctor, patient)
    local consentKey = medicationConsentKey(doctor, patient, requestId)
    local pending = consentKey and EHR.ServerCommands.PendingMedicationConsents[consentKey] or nil
    if not pending or pending.doctorKey ~= getPlayerNetworkKey(doctor) then return end

    EHR.ServerCommands.PendingMedicationConsents[consentKey] = nil
    if pairKey and EHR.ServerCommands.PendingMedicationConsentByPair[pairKey] == consentKey then
        EHR.ServerCommands.PendingMedicationConsentByPair[pairKey] = nil
    end
    sendServerCommand(patient, "EHR_Exam", "MedicationConsentCancelled", {
        requestId = requestId,
    })
end

function EHR.ServerCommands.CancelAdministerMedication(doctor, args)
    if not doctor or type(args) ~= "table" or args.actionId == nil then return end
    local key = tostring(math.floor(tonumber(args.actionId) or -1))
    local permit = EHR.ServerCommands.MedicationActionPermits[key]
    if permit and permit.doctorKey == getPlayerNetworkKey(doctor) then
        EHR.ServerCommands.MedicationActionPermits[key] = nil
    end
end

local function sendMedicationAdministerResult(player, role, success, permit, message)
    if not player or not sendServerCommand then return end
    sendServerCommand(player, "EHR_Exam", "MedicationAdministerResult", {
        success = success == true,
        role = role,
        requestId = permit and permit.requestId or nil,
        actionId = permit and permit.actionId or nil,
        targetOnlineID = permit and permit.patientOnlineID or nil,
        targetUsername = permit and permit.patientUsername or nil,
        itemFullType = permit and permit.itemFullType or nil,
        medicationName = permit and permit.medicationName or nil,
        treatmentKind = permit and permit.treatmentKind or nil,
        message = tostring(message or "Medication administration failed"),
    })
end

local function applyRemoteBloodTransfusion(doctor, patient, bag, ivKit, spoilageState)
    if not doctor or not patient or not bag or not ivKit then
        return false, "Blood transfusion supplies are no longer available"
    end

    -- Request, consent and completion each validate the exact bag. Completion
    -- also pins the exact IV kit selected when consent was granted, so neither
    -- item can be substituted after the patient accepts.
    local bloodData = ensureServerBloodData(patient)
    if not bloodData or not bloodData.EHR_Blood then
        return false, "Patient blood data is unavailable"
    end

    local okApply, applied = pcall(applyServerBloodBag, patient, bag, spoilageState)
    if not okApply or applied ~= true then
        local detail = okApply and "blood bag could not be applied" or tostring(applied)
        return false, "Blood transfusion failed: " .. detail
    end

    -- All prerequisites are prevalidated above. Consume each exact object only
    -- after the patient effect succeeds; the permit was already invalidated, so
    -- this completion cannot be replayed.
    local bagRemoved = removeInventoryItem(bag)
    local ivKitRemoved = removeInventoryItem(ivKit)
    if not bagRemoved or not ivKitRemoved then
        log("[EHR Server] Blood transfusion inventory removal failed: bag="
            .. tostring(bagRemoved) .. " ivKit=" .. tostring(ivKitRemoved))
        return false, "Blood transfusion applied, but supply removal failed"
    end

    if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
        local okXP, xpError = pcall(EHR.SkillXP.OnTransfusion, doctor, true)
        if not okXP then
            log("[EHR Server] Blood transfusion XP failed: " .. tostring(xpError))
        end
    end

    return true, nil
end

local REMOTE_VANILLA_PILL_TYPES = {
    ["Base.Pills"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.PillsAntiDep"] = true,
}

local function applyRemoteVanillaPill(doctor, patient, item, fullType)
    if not doctor or not patient or not item or not REMOTE_VANILLA_PILL_TYPES[fullType] then
        return false, "Vanilla pill administration data is invalid"
    end
    if not EHR.Medication or not EHR.Medication.UseConsumedMedication then
        return false, "EHR medication tracking is unavailable"
    end

    -- Vanilla JustTookPill applies the native effect and calls UseAndSync on
    -- the doctor's exact item. Use the effect-only EHR path first so the same
    -- physical tablet is never consumed twice.
    local okEHR, ehrApplied = pcall(
        EHR.Medication.UseConsumedMedication, patient, fullType, doctor
    )
    if not okEHR or ehrApplied ~= true then
        local detail = okEHR and "EHR effect could not be applied" or tostring(ehrApplied)
        return false, "Vanilla pill administration failed: " .. detail
    end

    local bodyDamage = patient.getBodyDamage and patient:getBodyDamage() or nil
    if not bodyDamage or not bodyDamage.JustTookPill then
        return false, "Vanilla medication effect is unavailable"
    end
    local okVanilla, vanillaError = pcall(function()
        bodyDamage:JustTookPill(item)
    end)
    if not okVanilla then
        return false, "Vanilla medication effect failed: " .. tostring(vanillaError)
    end

    if sendPlayerEffects then
        pcall(function() sendPlayerEffects(patient) end)
    end
    return true, nil
end

function EHR.ServerCommands.CompleteAdministerMedication(doctor, args)
    if not doctor or type(args) ~= "table" or args.actionId == nil then return end
    local key = tostring(math.floor(tonumber(args.actionId) or -1))
    local permit = EHR.ServerCommands.MedicationActionPermits[key]
    if not permit or permit.doctorKey ~= getPlayerNetworkKey(doctor) then return end

    -- One completion attempt per patient-approved permit, including failures.
    EHR.ServerCommands.MedicationActionPermits[key] = nil
    if getServerNowMs() > (tonumber(permit.expiresAt) or 0) then
        sendMedicationAdministerResult(doctor, "doctor", false, permit, "Medication administration authorization expired")
        return
    end

    local patient = findOnlinePlayerStrict({
        targetOnlineID = permit.patientOnlineID,
        targetUsername = permit.patientUsername,
    }, nil)
    local completionSpoilageState = combineBloodSpoilageState(
        permit.spoilageState,
        args.spoilageState
    )
    local item, medData, treatmentKind, spoilageState, ivKit, reason = validateRemoteTreatment(
        doctor, patient, permit.itemID, permit.itemFullType,
        permit.treatmentKind, completionSpoilageState, permit.ivKitID
    )
    if not item then
        sendMedicationAdministerResult(doctor, "doctor", false, permit, reason)
        if patient then
            sendMedicationAdministerResult(patient, "patient", false, permit, reason)
            syncModDataToClient(patient)
        end
        syncModDataToClient(doctor)
        return
    end

    local success = false
    if treatmentKind == REMOTE_TREATMENT_KIND_BLOOD then
        success, reason = applyRemoteBloodTransfusion(doctor, patient, item, ivKit, spoilageState)
    elseif medData and medData.useVanillaActionOnly == true
            and REMOTE_VANILLA_PILL_TYPES[permit.itemFullType] then
        success, reason = applyRemoteVanillaPill(
            doctor, patient, item, permit.itemFullType
        )
    else
        local ok, used = pcall(EHR.Medication.UseMedication, patient, item, doctor)
        success = ok and used == true
        if not success then
            reason = ok and "Medication could not be used" or ("Medication administration failed: " .. tostring(used))
        end
    end

    if not success then
        sendMedicationAdministerResult(doctor, "doctor", false, permit, reason)
        sendMedicationAdministerResult(patient, "patient", false, permit, reason)
        syncModDataToClient(patient)
        syncModDataToClient(doctor)
        return
    end

    syncModDataToClient(patient)
    syncModDataToClient(doctor)
    local patientName = getPlayerUsernameString(patient) or "patient"
    local doctorMessage = "Administered " .. tostring(permit.medicationName) .. " to " .. tostring(patientName) .. "."
    local patientMessage = tostring(getPlayerUsernameString(doctor) or "A doctor")
        .. " administered " .. tostring(permit.medicationName) .. "."
    sendMedicationAdministerResult(doctor, "doctor", true, permit, doctorMessage)
    sendMedicationAdministerResult(patient, "patient", true, permit, patientMessage)
end

local function claimExamRequest(doctor, patient)
    local pairKey = medicalPairKey(doctor, patient)
    if not pairKey then return false end
    local nowMs = getServerNowMs()
    local previous = EHR.ServerCommands.ExamRequestTimes[pairKey]
    if previous and nowMs >= previous and (nowMs - previous) < EXAM_REQUEST_MIN_INTERVAL_MS then
        return false
    end
    EHR.ServerCommands.ExamRequestTimes[pairKey] = nowMs
    return true
end

local function getServerBodyPart(player, partName)
    local partType = resolveWoundBodyPartType(partName)
    if not player or not partType or not player.getBodyDamage then return nil, nil end
    local ok, bodyPart = pcall(function()
        return player:getBodyDamage():getBodyPart(partType)
    end)
    if not ok then return nil, nil end
    return bodyPart, partType
end

local function isStitchItem(item)
    if not item then return false end
    local itemType = nil
    pcall(function() itemType = item:getType() end)
    return itemType == "Thread" or itemType == "SutureNeedle"
end

function EHR.ServerCommands.BeginStitchRiskSession(player, args)
    if not player or type(args) ~= "table" then return end
    local patient = findOnlinePlayerStrict(args, player)
    if not patient or not playersAreCloseEnoughForTreatment(player, patient) then return end
    if patient ~= player and not hasActiveExamSession(player, patient, true) then return end

    local bodyPart, partType = getServerBodyPart(patient, args.sourceBodyPart)
    if not bodyPart or not partType then return end
    local deepWounded = callBodyPartMethod(bodyPart, "deepWounded", false) == true
    local hasGlass = callBodyPartMethod(bodyPart, "haveGlass", false) == true
    local stitched = callBodyPartMethod(bodyPart, "stitched", false) == true
    if not deepWounded or hasGlass or stitched then return end

    local item = args.itemID and findInventoryItemByID(player, args.itemID) or nil
    if not isStitchItem(item) then return end

    local permitKey = medicalPairKey(player, patient) .. ":" .. tostring(partType)
    EHR.ServerCommands.StitchRiskPermits[permitKey] = {
        expiresAt = getServerNowMs() + STITCH_RISK_PERMIT_TTL_MS,
        patientKey = getPlayerNetworkKey(patient),
        bodyPart = tostring(partType),
    }
end

function EHR.ServerCommands.WoundDisinfected(player, args)
    -- Deprecated. MP disinfection is now applied from the authoritative
    -- ISDisinfect/ISApplyBandage server timed-action hooks below. Accepting a
    -- client completion command allowed treatment without consuming an item.
    return
end

local SERVER_DISINFECTANT_BANDAGES = {
    ["Base.AlcoholBandage"] = true,
    ["ExtensiveHealth.AlchoholicBandage"] = true,
}

local function applyAuthoritativeWoundDisinfection(patient, bodyPart)
    if not patient or not bodyPart or not EHR.WoundInfection or not EHR.WoundInfection.OnDisinfect then
        return
    end
    local partType = callBodyPartMethod(bodyPart, "getType", nil)
    if not partType then return end
    EHR.WoundInfection.OnDisinfect(patient, partType)
    syncModDataToClient(patient)
end

local function installAuthoritativeMedicalActionHooks()
    pcall(function() require "TimedActions/ISDisinfect" end)
    pcall(function() require "TimedActions/ISApplyBandage" end)

    if ISDisinfect and ISDisinfect.complete
            and ISDisinfect.complete ~= ISDisinfect._ehrServerCompleteWrapper then
        local originalComplete = ISDisinfect.complete
        local wrapper = function(action)
            local result = originalComplete(action)
            if result ~= false and action then
                applyAuthoritativeWoundDisinfection(action.otherPlayer or action.character, action.bodyPart)
            end
            return result
        end
        ISDisinfect._ehrServerCompleteOriginal = originalComplete
        ISDisinfect._ehrServerCompleteWrapper = wrapper
        ISDisinfect.complete = wrapper
    end

    if ISApplyBandage and ISApplyBandage.complete
            and ISApplyBandage.complete ~= ISApplyBandage._ehrServerCompleteWrapper then
        local originalComplete = ISApplyBandage.complete
        local wrapper = function(action)
            local shouldDisinfect = false
            if action and action.doIt == true and action.item then
                local fullType = nil
                pcall(function() fullType = action.item:getFullType() end)
                shouldDisinfect = SERVER_DISINFECTANT_BANDAGES[fullType] == true
            end

            local result = originalComplete(action)
            if result ~= false and shouldDisinfect and action then
                applyAuthoritativeWoundDisinfection(action.otherPlayer or action.character, action.bodyPart)
            end
            return result
        end
        ISApplyBandage._ehrServerCompleteOriginal = originalComplete
        ISApplyBandage._ehrServerCompleteWrapper = wrapper
        ISApplyBandage.complete = wrapper
    end
end

if isServer and isServer() then
    installAuthoritativeMedicalActionHooks()
end

function EHR.ServerCommands.StitchCellulitisRisk(player, args)
    if not player or not args then return end

    local targetPlayer = findOnlinePlayerStrict(args, player)
    if not targetPlayer then
        log("[EHR Server] StitchCellulitisRisk rejected: target player not found")
        return
    end
    if not playersAreCloseEnoughForTreatment(player, targetPlayer) then return end
    if targetPlayer ~= player and not hasActiveExamSession(player, targetPlayer, true) then return end

    if not EHR.Disease or not EHR.Disease.Contract then
        log("[EHR Server] StitchCellulitisRisk rejected: disease module unavailable")
        return
    end

    local bodyPart, partType = getServerBodyPart(targetPlayer, args.sourceBodyPart)
    if not bodyPart or not partType then return end
    local permitKey = medicalPairKey(player, targetPlayer) .. ":" .. tostring(partType)
    local permit = EHR.ServerCommands.StitchRiskPermits[permitKey]
    local nowMs = getServerNowMs()
    if not permit or nowMs > (tonumber(permit.expiresAt) or 0) then
        EHR.ServerCommands.StitchRiskPermits[permitKey] = nil
        return
    end
    EHR.ServerCommands.StitchRiskPermits[permitKey] = nil -- One roll per minigame.

    local quality = math.max(0, math.min(1, tonumber(args.quality) or 1))
    if quality >= 0.72 then return end
    args.quality = quality
    args.misses = math.max(0, math.min(20, math.floor(tonumber(args.misses) or 0)))
    args.sourceBodyPart = tostring(partType)

    -- The client reports performance, but never controls probability.
    local chance = STITCH_ROUGH_CELLULITIS_CHANCE
    if EHR.Immunity and EHR.Immunity.ModifyDiseaseChance then
        chance = EHR.Immunity.ModifyDiseaseChance(
            targetPlayer,
            "cellulitis",
            chance,
            { kind = "rough_stitch" }
        )
    end

    local roll = ZombRand and (ZombRand(1000000) / 1000000) or 1
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

    -- Disease progression may request this only for the command sender. Never
    -- accept a client-selected remote target for a lethal disease transition.
    triggerCellulitisSepsisHandoff(player, args or {})
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
    local isBloodBag = EHR.Blood.BloodBagTypes and EHR.Blood.BloodBagTypes[fullType] ~= nil
    local isSalineBag = fullType == "ExtensiveHealth.SalineBag"

    if not isBloodBag and not isSalineBag then
        log("[EHR Server] UseTransfusion rejected: unsupported item " .. tostring(fullType))
        syncModDataToClient(player)
        return
    end

    if spoilageState == "rotten" then
        log("[EHR Server] UseTransfusion rejected: transfusion item is rotten")
        serverSay(player, "This transfusion item is contaminated and cannot be used.")
        syncModDataToClient(player)
        return
    end

    -- The MP action leaves both supplies for the authoritative server. Resolve
    -- and validate both before applying any patient effect or consuming either.
    local ivKit, ivKitContainer = findInventoryItemByFullType(player, "ExtensiveHealth.IVKit")
    if not ivKit then
        log("[EHR Server] UseTransfusion rejected: IV Administration Kit not found")
        serverSay(player, serverText("UI_EHR_MedAction_RequiresIVKit", "Requires: IV Kit"))
        syncModDataToClient(player)
        return
    end

    if isBloodBag then
        consumed = applyServerBloodBag(player, item, spoilageState)
        if consumed then
            local itemRemoved = removeInventoryItem(item, container)
            local ivKitRemoved = removeInventoryItem(ivKit, ivKitContainer)
            if not itemRemoved or not ivKitRemoved then
                log("[EHR Server] UseTransfusion inventory removal failed: item="
                    .. tostring(itemRemoved) .. " ivKit=" .. tostring(ivKitRemoved))
            end
            if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
                pcall(function() EHR.SkillXP.OnTransfusion(player, true) end)
            end
        end
    elseif isSalineBag then
        local applied, consumedByBloodApi = applyServerSalineBag(player, item, spoilageState)
        consumed = applied
        if consumed then
            local itemRemoved = true
            if not consumedByBloodApi then
                itemRemoved = removeInventoryItem(item, container)
            end
            local ivKitRemoved = removeInventoryItem(ivKit, ivKitContainer)
            if not itemRemoved or not ivKitRemoved then
                log("[EHR Server] UseTransfusion inventory removal failed: item="
                    .. tostring(itemRemoved) .. " ivKit=" .. tostring(ivKitRemoved))
            end
        end
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

    local isKnox = EHR.DiseaseFlyers
        and EHR.DiseaseFlyers.IsKnoxDiseaseId
        and EHR.DiseaseFlyers.IsKnoxDiseaseId(diseaseId)
    local knoxSource = EHR.DiseaseFlyers and EHR.DiseaseFlyers.KNOX_UNLOCK_SOURCE or "kentucky_herald_july16"
    local allowKnox = args.allowKnox == true or args.source == knoxSource
    if isKnox and not allowKnox then
        log("[EHR Server] Knox disease knowledge rejected: Kentucky Herald July 16 required.")
        return
    end

    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.UnlockDiseaseKnowledge then
        EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId, {
            allowKnox = allowKnox,
            source = args.source,
            silent = true,
        })
    else
        data.EHR_KnownDiseases = data.EHR_KnownDiseases or {}
        data.EHR_KnownDiseases[diseaseId] = true
        if isKnox then
            data.EHR_KnoxHeraldRead = true
            data.EHR_KnoxKnowledgeSource = knoxSource
        end
        data.EHR_MedicalJournal = data.EHR_MedicalJournal or { entries = {}, discoveries = {} }
        data.EHR_MedicalJournal.discoveries = data.EHR_MedicalJournal.discoveries or {}
        data.EHR_MedicalJournal.discoveries[diseaseId] = getGameTime():getWorldAgeHours()
        data.EHR_MedicalJournal.lastUpdated = getGameTime():getWorldAgeHours()
    end

    syncModDataToClient(player)
    if sendServerCommand then
        sendServerCommand(player, "EHR_Flyers", "KnowledgeUnlocked", {
            diseaseId = diseaseId,
            EHR_KnownDiseases = data.EHR_KnownDiseases,
            EHR_MedicalJournal = data.EHR_MedicalJournal,
            EHR_KnoxHeraldRead = data.EHR_KnoxHeraldRead,
            EHR_KnoxKnowledgeSource = data.EHR_KnoxKnowledgeSource,
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

local function sendAdminCommandFeedback(player, text)
    if not player or not text or not sendServerCommand then return end
    pcall(function()
        sendServerCommand(player, "EHR_Dialogue", "Say", { text = tostring(text) })
    end)
end

local function normalizePlayerLookupName(value)
    value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if value:sub(1, 1) == "\"" and value:sub(-1) == "\"" then
        value = value:sub(2, -2)
    end
    return value:lower()
end

local function findOnlinePlayerByName(value)
    local wanted = normalizePlayerLookupName(value)
    if wanted == "" then return nil end

    local exact = nil
    local partial = nil
    local partialCount = 0
    local onlinePlayers = getOnlinePlayers()
    if not onlinePlayers then return nil end

    for i = 0, onlinePlayers:size() - 1 do
        local candidate = onlinePlayers:get(i)
        if candidate then
            local names = {}
            pcall(function() names[#names + 1] = candidate:getUsername() end)
            pcall(function()
                if candidate.getDisplayName then
                    names[#names + 1] = candidate:getDisplayName()
                end
            end)
            pcall(function()
                if candidate.getDescriptor and candidate:getDescriptor() then
                    names[#names + 1] = candidate:getDescriptor():getForename()
                    names[#names + 1] = candidate:getDescriptor():getSurname()
                end
            end)

            for _, name in ipairs(names) do
                local lookup = normalizePlayerLookupName(name)
                if lookup ~= "" then
                    if lookup == wanted then
                        exact = candidate
                        break
                    end
                    if lookup:find(wanted, 1, true) then
                        partial = candidate
                        partialCount = partialCount + 1
                    end
                end
            end
            if exact then break end
        end
    end

    if exact then return exact end
    if partialCount == 1 then return partial end
    return nil
end

function EHR.ServerCommands.FullHealTarget(requester, args)
    if not requester then return end

    local targetName = args and (args.targetUsername or args.target or args.username or args.player) or nil
    local target = nil
    if targetName and tostring(targetName):gsub("%s+", "") ~= "" then
        target = findOnlinePlayerByName(targetName)
    else
        target = requester
    end

    if not target then
        sendAdminCommandFeedback(requester, "EHR: player not found: " .. tostring(targetName or ""))
        return
    end

    EHR.ServerCommands.FullHeal(target, {})

    local healedName = "player"
    pcall(function() healedName = target:getUsername() or healedName end)
    sendAdminCommandFeedback(requester, "EHR: full heal applied to " .. tostring(healedName))
    if target ~= requester then
        sendAdminCommandFeedback(target, "EHR: an admin restored your health.")
    end
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
    data.EHR_Immunity = nil
    clearDebugVanillaWoundInfections(player)

    -- Re-initialize
    if EHR and EHR.InitializePlayer then
        EHR.InitializePlayer(player)
    end
    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFever then
        EHR.BodyTemp.ResetDiseaseFever(player, true)
    end
    if EHR.Immunity and EHR.Immunity.ResetPlayer then
        EHR.Immunity.ResetPlayer(player)
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
    local quietCommand = module == "EHR" and (
        command == "EnvironmentalSnapshot"
        or (command == "HeatStrokeBath" and args and args.action == "heartbeat")
    )
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
        elseif command == "UseConsumedMedication" then
            EHR.ServerCommands.UseConsumedMedication(player, args)
            return
        elseif command == "DrinkWaterRisk" then
            EHR.ServerCommands.DrinkWaterRisk(player, args)
            return
        elseif command == "EnvironmentalSnapshot" then
            EHR.ServerCommands.EnvironmentalSnapshot(player, args)
            return
        elseif command == "BeginExamConsent" then
            EHR.ServerCommands.BeginExamConsent(player, args)
            return
        elseif command == "GrantExamConsent" then
            EHR.ServerCommands.GrantExamConsent(player, args)
            return
        elseif command == "DenyExamConsent" then
            EHR.ServerCommands.DenyExamConsent(player, args)
            return
        elseif command == "EndExamSession" then
            EHR.ServerCommands.EndExamSession(player, args)
            return
        elseif command == "RequestAdministerMedication" then
            EHR.ServerCommands.RequestAdministerMedication(player, args)
            return
        elseif command == "RespondAdministerMedicationConsent" then
            EHR.ServerCommands.RespondAdministerMedicationConsent(player, args)
            return
        elseif command == "CancelAdministerMedicationRequest" then
            EHR.ServerCommands.CancelAdministerMedicationRequest(player, args)
            return
        elseif command == "CompleteAdministerMedication" then
            EHR.ServerCommands.CompleteAdministerMedication(player, args)
            return
        elseif command == "CancelAdministerMedication" then
            EHR.ServerCommands.CancelAdministerMedication(player, args)
            return
        elseif command == "BeginStitchRiskSession" then
            EHR.ServerCommands.BeginStitchRiskSession(player, args)
            return
        elseif command == "HeatStrokeBath" then
            EHR.ServerCommands.HeatStrokeBath(player, args)
            return
        elseif command == "FoodDiseaseRisk" then
            EHR.ServerCommands.FoodDiseaseRisk(player, args)
            return
        elseif command == "WoundDisinfected" then
            EHR.ServerCommands.WoundDisinfected(player, args)
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
        elseif command == "InsertWatchBattery" then
            EHR.ServerCommands.InsertWatchBattery(player, args)
            return
        elseif command == "RemoveWatchBattery" then
            EHR.ServerCommands.RemoveWatchBattery(player, args)
            return
        elseif command == "RequestWatchBatterySync" then
            EHR.ServerCommands.RequestWatchBatterySync(player)
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
        elseif command == "AddCleanBandageToPack" then
            EHR.ServerCommands.AddCleanBandageToPack(player, args)
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
                analgesicInitialPain = args.analgesicInitialPain,
            }

            if args.medKey == "Base.Pills"
                and EHR.PainkillerAddiction
                and EHR.PainkillerAddiction.OnPainkillerDose then
                EHR.PainkillerAddiction.OnPainkillerDose(player, args.lastDoseTime)
            end

            syncModDataToClient(player)
            log("[EHR] Server: Tracked medication " .. args.medKey .. " for " .. player:getUsername())
            return
        elseif command == "RequestSync" then
            -- Client requests immediate sync (after transfusion, medication, etc.)
            syncModDataToClient(player)
            log("[EHR] Server: Sync requested by " .. player:getUsername())
            return
        elseif command == "RequestExamData" then
            -- Remote medical data is available only inside a short-lived
            -- patient-approved examination session.
            if not args or (not args.targetUsername and args.targetOnlineID == nil) then
                log("[EHR] Server: RequestExamData missing target identifier")
                return
            end

            local targetUsername = args.targetUsername and tostring(args.targetUsername) or nil
            local targetOnlineID = args.targetOnlineID and tostring(args.targetOnlineID) or nil
            local requestKey = tostring(args.targetKey or targetUsername or ("online_" .. tostring(targetOnlineID)))
            if #requestKey > 96 then requestKey = string.sub(requestKey, 1, 96) end
            local requestId = tonumber(args.requestId)
            local targetPlayer = findOnlinePlayerStrict(args, nil)

            if not targetPlayer then
                log("[EHR] Server: RequestExamData - target player not found: " .. tostring(requestKey))
                -- Send empty response so client knows request failed
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = requestKey,
                    requestId = requestId,
                    success = false,
                    error = "Player not found or offline",
                })
                return
            end

            if not hasActiveExamSession(player, targetPlayer, true) then
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = requestKey,
                    requestId = requestId,
                    success = false,
                    error = "Examination session is not authorized or patient is out of range",
                })
                return
            end

            if not claimExamRequest(player, targetPlayer) then
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = requestKey,
                    requestId = requestId,
                    success = false,
                    error = "rate_limited",
                })
                return
            end

            -- Get target player's EHR data
            local targetData = targetPlayer:getModData()
            if not targetData then
                sendServerCommand(player, "EHR_Exam", "ExamDataResponse", {
                    targetUsername = requestKey,
                    requestId = requestId,
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
                    activeSideEffects = EHR.Medication.GetMonitorSideEffects and EHR.Medication.GetMonitorSideEffects(targetPlayer)
                        or (EHR.Medication.GetActiveSideEffects and EHR.Medication.GetActiveSideEffects(targetPlayer) or {}),
                }
            end

            local actualUsername = targetUsername
            pcall(function() actualUsername = targetPlayer:getUsername() or actualUsername end)

            local knoxStatus = {
                infected = false,
                progress = 0,
            }
            if EHR.KnoxCure then
                if EHR.KnoxCure.IsInfected then
                    local ok, infected = pcall(function()
                        return EHR.KnoxCure.IsInfected(targetPlayer)
                    end)
                    knoxStatus.infected = ok and infected == true
                end
                if EHR.KnoxCure.GetInfectionProgress then
                    local ok, progress = pcall(function()
                        return EHR.KnoxCure.GetInfectionProgress(targetPlayer)
                    end)
                    if ok then
                        knoxStatus.progress = math.max(0, math.min(1, tonumber(progress) or 0))
                    end
                end
            end

            local bodyStatusSnapshot = buildBodyStatusSnapshot(targetPlayer)
            local hasMedicalMonitorWatch = playerHasMedicalMonitorWatch(targetPlayer)
            bodyStatusSnapshot.hasMedicalMonitorWatch = hasMedicalMonitorWatch

            local environmentalExposureView = nil
            if EHR.Environmental then
                local exposureData = nil
                if EHR.Environmental.GetExposureData then
                    pcall(function() exposureData = EHR.Environmental.GetExposureData(targetPlayer) end)
                end
                environmentalExposureView = {
                    heatExposure = tonumber(exposureData and exposureData.heatExposure) or 0,
                    heatStrokeExposure = tonumber(exposureData and exposureData.heatStrokeExposure) or 0,
                }
                if EHR.Environmental.GetHeatExposureDisplay then
                    pcall(function()
                        environmentalExposureView.heatExposureLevel = EHR.Environmental.GetHeatExposureDisplay(targetPlayer)
                    end)
                end
                if EHR.Environmental.GetHeatExposureRatio then
                    pcall(function()
                        environmentalExposureView.heatExposureRatio = EHR.Environmental.GetHeatExposureRatio(targetPlayer)
                    end)
                end
            end

            local serverWorldHour = nil
            pcall(function() serverWorldHour = getGameTime():getWorldAgeHours() end)

            local examData = {
                targetUsername = requestKey,
                targetActualUsername = actualUsername,
                targetOnlineID = getPlayerOnlineIDString(targetPlayer),
                requestId = requestId,
                success = true,
                EHR_Blood = targetData.EHR_Blood,
                EHR_Disease = targetData.EHR_Disease,
                EHR_Sepsis = targetData.EHR_Sepsis,
                EHR_WoundInfection = targetData.EHR_WoundInfection,
                EHR_BodyStatus = bodyStatusSnapshot,
                EHR_HasMedicalMonitorWatch = hasMedicalMonitorWatch,
                EHR_Medication = targetData.EHR_Medication,
                EHR_MedicationView = medicationView,
                EHR_MedicalJournal = targetData.EHR_MedicalJournal,
                EHR_Temperature = targetData.EHR_Temperature,
                EHR_CorpseSickness = targetData.EHR_CorpseSickness,
                EHR_EnvironmentalExposure = environmentalExposureView,
                EHR_KnoxCure = targetData.EHR_KnoxCure,
                EHR_KnoxStatus = knoxStatus,
                EHR_Immunity = targetData.EHR_Immunity,
                EHR_Initialized = targetData.EHR_Initialized,
                serverWorldHour = serverWorldHour,
                snapshotTimestamp = getTimestampMs and getTimestampMs() or 0,
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
    elseif command == "FullHealTarget" then
        EHR.ServerCommands.FullHealTarget(player, args)
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
    if EHR.Immunity and EHR.Immunity.InitializePlayer then
        EHR.Immunity.InitializePlayer(player)
        EHR.Immunity.UpdatePlayer(player, true)
    end

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
    if EHR.Immunity and EHR.Immunity.InitializePlayer then
        EHR.Immunity.InitializePlayer(player)
        EHR.Immunity.UpdatePlayer(player, true)
    end

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

if Events and Events.EveryTenMinutes then
    Events.EveryTenMinutes.Add(drainOnlineWatchBatteries)
    log("[EHR Server] Medical Monitor Watch battery drain registered")
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

local MEDICATION_INTERVAL_TICKS = 30    -- ~1 second; keeps delayed side effects responsive in MP
local BLOOD_INTERVAL_TICKS = 30         -- ~1 second; server is authoritative for MP blood
local BLOOD_SYNC_INTERVAL_TICKS = 90    -- ~3 seconds while bleeding; keeps UI responsive without spam
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

local function OnServerTick()
    -- Periodic sync
    syncTickCounter = syncTickCounter + 1
    if syncTickCounter >= SYNC_INTERVAL_TICKS then
        syncTickCounter = 0
        syncAllPlayers()

        local nowMs = getServerNowMs()
        pruneTimedEntries(EHR.ServerCommands.PendingExamConsents, nowMs)
        pruneTimedEntries(EHR.ServerCommands.ExamSessions, nowMs)
        pruneTimedEntries(EHR.ServerCommands.StitchRiskPermits, nowMs)
        pruneTimedEntries(EHR.ServerCommands.PendingMedicationConsents, nowMs)
        pruneTimedEntries(EHR.ServerCommands.MedicationActionPermits, nowMs)
        for pairKey, consentKey in pairs(EHR.ServerCommands.PendingMedicationConsentByPair) do
            if not EHR.ServerCommands.PendingMedicationConsents[consentKey] then
                EHR.ServerCommands.PendingMedicationConsentByPair[pairKey] = nil
            end
        end
        for key, timestamp in pairs(EHR.ServerCommands.ExamRequestTimes) do
            if type(timestamp) ~= "number" or nowMs < timestamp or (nowMs - timestamp) > EXAM_SESSION_TTL_MS then
                EHR.ServerCommands.ExamRequestTimes[key] = nil
            end
        end
        for key, timestamp in pairs(EHR.ServerCommands.EnvironmentalSnapshotTimes) do
            if type(timestamp) ~= "number" or nowMs < timestamp or (nowMs - timestamp) > 600000 then
                EHR.ServerCommands.EnvironmentalSnapshotTimes[key] = nil
            end
        end
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

    -- Disease, sepsis and wound progression are owned by their canonical
    -- shared modules, which already run authoritatively on the server. A second
    -- simplified loop here used different stage rules and could overwrite
    -- manual/reverse/permanent disease state. Medication remains on the
    -- dedicated one-second path above.
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
