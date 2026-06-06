--[[
    Extensive Health Rework B42
    Wound Infection Module V2 - Vanilla Integration

    HYBRID APPROACH (v2.8.0):
    - Vanilla handles initial infection detection (isInfectedWound())
    - EHR tracks progression: INFECTED → WORSENING → SEVERE → Sepsis
    - EHR clears vanilla infection when treatment succeeds
    - Timing: 12h → 24h → 48h stages (~84h total to sepsis)

    Vanilla API Used:
    - bodyPart:isInfectedWound() - Check bacterial wound infection
    - bodyPart:getWoundInfectionLevel() - Get numeric level (0-10+)
    - bodyPart:setWoundInfectionLevel(-1) - Clear infection
    - bodyPart:setInfectedWound(false) - Clear infection flag

    Author: ExtensiveHealthRework Team
    Version: 2.8.0
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.WoundInfection = EHR.WoundInfection or {}

-- ============================================
-- STAGE ENUM (Simplified for V2)
-- ============================================

EHR.WoundInfection.Stage = {
    CLEAN = 0,       -- No infection
    INFECTED = 1,    -- Vanilla infection detected, EHR tracking starts
    WORSENING = 2,   -- Infection spreading, 50% slower healing
    SEVERE = 3,      -- Critical, no healing, pre-sepsis
    SEPTIC = 4,      -- Triggers sepsis module (no longer tracked here)
}

EHR.WoundInfection.StageName = {
    [0] = "Clean",
    [1] = "Infected",
    [2] = "Worsening",
    [3] = "Severe",
    [4] = "Septic",
}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.WoundInfection.Config = {
    -- Incubation period: hours after vanilla detects infection before symptoms appear
    -- Real wound infections take 24-72 hours to show symptoms
    INCUBATION_HOURS = 12,  -- 12 hours before EHR starts tracking/displaying

    -- Hours at each stage before progression (Medium timing per user decision)
    STAGE_DURATION = {
        [1] = 12,  -- INFECTED: 12 hours before WORSENING
        [2] = 24,  -- WORSENING: 24 hours before SEVERE
        [3] = 48,  -- SEVERE: 48 hours before triggering SEPSIS
    },

    -- Effects per stage
    STAGE_EFFECTS = {
        [0] = { healingPenalty = 0.0, painBonus = 0, feverTarget = nil },    -- CLEAN
        [1] = { healingPenalty = 0.25, painBonus = 0, feverTarget = nil },   -- INFECTED: no pain yet
        [2] = { healingPenalty = 0.50, painBonus = 10, feverTarget = nil },  -- WORSENING: local pain
        [3] = { healingPenalty = 1.0, painBonus = 30, feverTarget = 38.0 },  -- SEVERE: pain + fever
        [4] = { healingPenalty = 1.0, painBonus = 30, feverTarget = 38.0 },  -- SEPTIC handoff
    },

    -- Sepsis trigger condition.
    -- A wound must finish the SEVERE stage and reach SEPTIC; severe/worsening
    -- wounds alone should not instantly jump into systemic sepsis.
    SEPSIS_SEVERE_COUNT = 0,      -- Legacy setting, no longer used for auto-trigger
    SEPSIS_WORSENING_COUNT = 0,   -- Legacy setting, no longer used for auto-trigger

    -- Antibiotic effectiveness (stages reduced per dose)
    ANTIBIOTIC_REDUCTION = 1,     -- Reduce by 1 stage per antibiotic dose

    -- Vanilla infection level thresholds
    VANILLA_WORSENING_THRESHOLD = 5,   -- Level >= 5 = worsening
    VANILLA_SEVERE_THRESHOLD = 10,     -- Level >= 10 = severe
}

-- Dialogue for stage changes
EHR.WoundInfection.StageDialogue = {
    [1] = "This wound looks infected...",
    [2] = "*winces* The infection is getting worse...",
    [3] = "*gasps* This infection is critical... I need antibiotics now!",
    [4] = "The infection is in my blood... I'm burning up...",
}

-- ============================================
-- HELPERS
-- ============================================

local function GetPartName(bodyPartType)
    if not bodyPartType then return nil end
    local success, name = pcall(function() return tostring(bodyPartType) end)
    return success and name or nil
end

-- ============================================
-- SANDBOX SETTINGS
-- ============================================

function EHR.WoundInfection.GetSetting(name, default)
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local value = SandboxVars.ExtensiveHealthRework[name]
        if value ~= nil then return value end
    end
    return default
end

function EHR.WoundInfection.IsEnabled()
    return EHR.WoundInfection.GetSetting("WoundInfectionEnabled", true)
end

function EHR.WoundInfection.GetSpeedMultiplier()
    return EHR.WoundInfection.GetSetting("WoundInfectionSpeed", 1.0)
end

-- ============================================
-- VANILLA API WRAPPERS (with pcall safety)
-- ============================================

EHR.WoundInfection.VANILLA_INFECTION_LEVEL_EPSILON = 0.05

function EHR.WoundInfection.IsVanillaInfected(bodyPart)
    if not bodyPart then return false end
    local flagOk, flag = pcall(function()
        return bodyPart:isInfectedWound()
    end)
    if flagOk and flag then return true end

    -- In B42/MP the vanilla wound infection can briefly have a positive level
    -- while the boolean flag is false or not yet replicated. Ignore tiny
    -- residue after disinfecting, but still catch meaningful unsynced levels.
    local levelOk, level = pcall(function()
        return bodyPart:getWoundInfectionLevel()
    end)
    return levelOk and (tonumber(level) or 0) > EHR.WoundInfection.VANILLA_INFECTION_LEVEL_EPSILON or false
end

function EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
    if not bodyPart then return 0 end
    local success, result = pcall(function()
        return bodyPart:getWoundInfectionLevel()
    end)
    return success and (result or 0) or 0
end

local function BodyPartHasActiveWound(bodyPart)
    if not bodyPart then return false end

    local function check(call)
        local ok, value = pcall(call)
        return ok and value == true
    end

    local function checkPositive(call)
        local ok, value = pcall(call)
        return ok and tonumber(value) and tonumber(value) > 0
    end

    if check(function() return bodyPart:bleeding() end) then return true end
    if check(function() return bodyPart:scratched() end) then return true end
    if check(function() return bodyPart:isCut() end) then return true end
    if check(function() return bodyPart:bitten() end) then return true end
    if check(function() return bodyPart:deepWounded() end) then return true end
    if check(function() return bodyPart:isDeepWounded() end) then return true end
    if check(function() return bodyPart:isBurnt() end) then return true end
    if check(function() return bodyPart:haveGlass() end) then return true end
    if check(function() return bodyPart:haveBullet() end) then return true end

    if checkPositive(function() return bodyPart:getBleedingTime() end) then return true end
    if checkPositive(function() return bodyPart:getScratchTime() end) then return true end
    if checkPositive(function() return bodyPart:getCutTime() end) then return true end
    if checkPositive(function() return bodyPart:getBiteTime() end) then return true end
    if checkPositive(function() return bodyPart:getDeepWoundTime() end) then return true end
    if checkPositive(function() return bodyPart:getBurnTime() end) then return true end

    return false
end

local function WoundInfectionDebug(message)
    if EHR and EHR.DISINFECT_DEBUG == true then
        print("[EHR][DisinfectDebug][WoundInfection] " .. tostring(message))
    end
end

local function DebugBodyPartState(bodyPart)
    if not bodyPart then return "bodyPart=nil" end
    local infected, level, alcohol, partType = nil, nil, nil, nil
    pcall(function() if bodyPart.isInfectedWound then infected = bodyPart:isInfectedWound() end end)
    pcall(function() if bodyPart.getWoundInfectionLevel then level = bodyPart:getWoundInfectionLevel() end end)
    pcall(function() if bodyPart.getAlcoholLevel then alcohol = bodyPart:getAlcoholLevel() end end)
    pcall(function() if bodyPart.getType then partType = bodyPart:getType() end end)
    return string.format("part=%s infected=%s level=%s alcohol=%s",
        tostring(partType), tostring(infected), tostring(level), tostring(alcohol))
end

local function DebugScanState(data, partName, bodyPart, marker)
    if not (EHR and EHR.DISINFECT_DEBUG == true) or not data or not partName then return end
    data._debugVanillaScan = data._debugVanillaScan or {}
    if data._debugVanillaScan[partName] == marker then return end
    data._debugVanillaScan[partName] = marker
    WoundInfectionDebug("scan " .. tostring(marker) .. " " .. DebugBodyPartState(bodyPart))
end

local function SuppressVanillaInfectionDuringAntiseptic(player, data, partName, bodyPart, vanillaLevel)
    if not data or not partName or not bodyPart then return end

    data.antisepticBlocked = data.antisepticBlocked or {}
    data.antisepticBlocked[partName] = {
        blockedTime = getGameTime() and getGameTime():getWorldAgeHours() or 0,
        vanillaLevel = math.max(1, tonumber(vanillaLevel) or 1),
    }

    if data.incubating then
        data.incubating[partName] = nil
    end

    EHR.WoundInfection.ClearVanillaInfection(bodyPart, "antiseptic-protection")
    EHR.Log("Antiseptic cream suppressed wound infection on " .. tostring(partName))
end

local function RestoreSuppressedVanillaInfection(data, partName, bodyPart)
    if not data or not data.antisepticBlocked or not partName or not bodyPart then
        return false
    end

    local blocked = data.antisepticBlocked[partName]
    if type(blocked) ~= "table" then
        data.antisepticBlocked[partName] = nil
        return false
    end

    if not BodyPartHasActiveWound(bodyPart) then
        data.antisepticBlocked[partName] = nil
        return false
    end

    local level = math.max(1, tonumber(blocked.vanillaLevel) or 1)
    pcall(function()
        bodyPart:setWoundInfectionLevel(level)
        bodyPart:setInfectedWound(true)
    end)

    data.antisepticBlocked[partName] = nil
    EHR.Log("Antiseptic protection expired; wound infection risk returned on " .. tostring(partName))
    return true
end

local function GetBodyPartByName(player, partName)
    if not player or not partName or not BodyPartType then return nil, nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return nil, nil end

    local partType = BodyPartType[partName]
    if not partType and BodyPartType.FromString then
        local ok, result = pcall(function() return BodyPartType.FromString(partName) end)
        if ok then partType = result end
    end

    if not partType and BodyPartType.values then
        local okValues, values = pcall(function() return BodyPartType.values() end)
        if okValues and values then
            local function checkCandidate(candidate)
                if candidate and tostring(candidate) == tostring(partName) then
                    partType = candidate
                    return true
                end
                return false
            end
            if type(values) == "table" then
                for _, candidate in ipairs(values) do
                    if checkCandidate(candidate) then break end
                end
            elseif type(values.size) == "function" and type(values.get) == "function" then
                for i = 0, values:size() - 1 do
                    if checkCandidate(values:get(i)) then break end
                end
            end
        end
    end

    if not partType then return nil, nil end

    local okPart, bodyPart = pcall(function()
        return bodyDamage:getBodyPart(partType)
    end)
    if not okPart or not bodyPart then return nil, bodyDamage end
    return bodyPart, bodyDamage
end

local function SetWoundSymptomPain(player, partName, partData, targetPain)
    if not partData then return false end
    local bodyPart, bodyDamage = GetBodyPartByName(player, partName)
    if not bodyPart or not bodyPart.getAdditionalPain or not bodyPart.setAdditionalPain then
        return false
    end

    local okCurrent, currentPain = pcall(function() return bodyPart:getAdditionalPain() end)
    if not okCurrent then return false end

    currentPain = tonumber(currentPain) or 0
    local previousApplied = tonumber(partData.ehrPainApplied) or 0
    targetPain = math.max(0, math.min(100, tonumber(targetPain) or 0))

    local basePain = math.max(0, currentPain - previousApplied)
    local nextPain = math.max(0, math.min(100, basePain + targetPain))
    if math.abs(nextPain - currentPain) > 0.1 then
        pcall(function() bodyPart:setAdditionalPain(nextPain) end)
        if bodyDamage and bodyDamage.DamageUpdate then
            pcall(function() bodyDamage:DamageUpdate() end)
        end
    end

    partData.ehrPainApplied = targetPain
    return true
end

local function ClearWoundSymptomPain(player, partName, partData)
    if not partData or not partData.ehrPainApplied or partData.ehrPainApplied <= 0 then return false end
    local bodyPart, bodyDamage = GetBodyPartByName(player, partName)
    if not bodyPart or not bodyPart.getAdditionalPain or not bodyPart.setAdditionalPain then return false end

    local okCurrent, currentPain = pcall(function() return bodyPart:getAdditionalPain() end)
    if not okCurrent then return false end

    currentPain = tonumber(currentPain) or 0
    local nextPain = math.max(0, currentPain - (tonumber(partData.ehrPainApplied) or 0))
    pcall(function() bodyPart:setAdditionalPain(nextPain) end)
    partData.ehrPainApplied = 0

    if bodyDamage and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end
    return true
end

function EHR.WoundInfection.ClearPartSymptomPain(player, partName)
    local data = EHR.WoundInfection.GetData(player)
    local partData = data and data.parts and data.parts[partName] or nil
    return ClearWoundSymptomPain(player, partName, partData)
end

function EHR.WoundInfection.ClearAllSymptomPain(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data or not data.parts then return false end

    local changed = false
    for partName, partData in pairs(data.parts) do
        changed = ClearWoundSymptomPain(player, partName, partData) or changed
    end
    return changed
end

function EHR.WoundInfection.ClearVanillaInfection(bodyPart, reason)
    if not bodyPart then return end
    WoundInfectionDebug("ClearVanillaInfection before reason=" .. tostring(reason or "unspecified") .. " " .. DebugBodyPartState(bodyPart))
    local okLevel, errLevel = pcall(function() bodyPart:setWoundInfectionLevel(-1) end)
    local okFlag, errFlag = pcall(function() bodyPart:setInfectedWound(false) end)
    local okSync, errSync = pcall(function()
        if syncBodyPart then
            syncBodyPart(bodyPart, 0x00608200)
        end
    end)
    WoundInfectionDebug(string.format("ClearVanillaInfection calls reason=%s level=%s/%s flag=%s/%s sync=%s/%s after %s",
        tostring(reason or "unspecified"), tostring(okLevel), tostring(errLevel), tostring(okFlag), tostring(errFlag),
        tostring(okSync), tostring(errSync), DebugBodyPartState(bodyPart)))
    EHR.Log("Cleared vanilla infection on body part")
end

function EHR.WoundInfection.IsGodModeActive(player)
    if not player then return false end
    if player.isGodMod then
        local ok, value = pcall(function() return player:isGodMod() end)
        if ok and value == true then return true end
    end
    return false
end

function EHR.WoundInfection.ClearForGodMode(player)
    if not player then return false end

    local data = EHR.WoundInfection.GetData(player)
    if not data then return false end

    local changed = false

    if type(data.parts) == "table" then
        for partName, partData in pairs(data.parts) do
            changed = true
            ClearWoundSymptomPain(player, partName, partData)

            local bodyPart = GetBodyPartByName(player, partName)
            if bodyPart then
                EHR.WoundInfection.ClearVanillaInfection(bodyPart, "god-mode-active")
            end
        end
    end

    if type(data.incubating) == "table" then
        for partName, _ in pairs(data.incubating) do
            changed = true
            local bodyPart = GetBodyPartByName(player, partName)
            if bodyPart then
                EHR.WoundInfection.ClearVanillaInfection(bodyPart, "god-mode-incubating")
            end
        end
    end

    if type(data.antisepticBlocked) == "table" then
        for _ in pairs(data.antisepticBlocked) do
            changed = true
            break
        end
    end

    if not changed then return false end

    data.parts = {}
    data.incubating = {}
    data.antisepticBlocked = {}
    data.totalInfectedParts = 0
    data.infectedCount = 0
    data.worstStage = 0
    data.worstPart = nil
    data.lastGodModeClear = getGameTime() and getGameTime():getWorldAgeHours() or 0

    EHR.WoundInfection.RecalculateStats(player)

    if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFeverIfStale then
        EHR.BodyTemp.ResetDiseaseFeverIfStale(player, true)
    end

    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(player)
    end

    EHR.Log("Wound infection state cleared because God mode is active")
    return true
end

-- ============================================
-- MODDATA MANAGEMENT
-- ============================================

function EHR.WoundInfection.MigrateLegacyData(player, modData)
    if not player or not modData then return end
    if modData.EHR_WoundInfection_V2_Migrated then return end
    if type(modData.EHR_WoundInfections) ~= "table" then
        modData.EHR_WoundInfection_V2_Migrated = true
        return
    end

    local legacy = modData.EHR_WoundInfections
    local currentHour = getGameTime():getWorldAgeHours()
    local Stage = EHR.WoundInfection.Stage

    modData.EHR_WoundInfection = modData.EHR_WoundInfection or {
        parts = {},
        incubating = {},
        antisepticBlocked = {},
        totalInfectedParts = 0,
        worstStage = 0,
        lastCheck = 0,
    }

    for partName, legacyStage in pairs(legacy) do
        local newStage = nil
        if legacyStage >= 4 then
            newStage = Stage.SEPTIC
        elseif legacyStage == 3 then
            newStage = Stage.SEVERE
        elseif legacyStage == 2 then
            newStage = Stage.INFECTED
        end

        if newStage then
            modData.EHR_WoundInfection.parts[partName] = {
                stage = newStage,
                stageStartTime = currentHour,
                startTime = currentHour,
                vanillaLevel = 0,
            }
        end
    end

    EHR.WoundInfection.RecalculateStats(player)

    -- Clear legacy data to avoid confusing mixed state
    modData.EHR_WoundInfections = nil
    modData.EHR_WoundInfections_Initialized = nil
    modData.EHR_WoundInfection_V2_Migrated = true
end

function EHR.WoundInfection.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if modData.EHR_WoundInfection_V2_Initialized then return end

    EHR.Log("Initializing wound infection V2 data...")

    if not modData.EHR_WoundInfection then
        modData.EHR_WoundInfection = {
            parts = {},              -- Keyed by body part name (active infections)
            incubating = {},         -- Keyed by body part name (infections in incubation)
            antisepticBlocked = {},  -- Keyed by body part name (temporarily suppressed infections)
            totalInfectedParts = 0,
            worstStage = 0,
            lastCheck = 0,
        }
    end
    -- Ensure incubating table exists for older saves
    modData.EHR_WoundInfection.incubating = modData.EHR_WoundInfection.incubating or {}
    modData.EHR_WoundInfection.antisepticBlocked = modData.EHR_WoundInfection.antisepticBlocked or {}

    EHR.WoundInfection.MigrateLegacyData(player, modData)

    modData.EHR_WoundInfection_V2_Initialized = true
end

function EHR.WoundInfection.GetData(player)
    if not player then return nil end
    local modData = player:getModData()
    return modData.EHR_WoundInfection
end

function EHR.WoundInfection.GetPartData(player, bodyPartName)
    local data = EHR.WoundInfection.GetData(player)
    if not data then return nil end
    return data.parts[bodyPartName]
end

function EHR.WoundInfection.CountInfectedParts(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data or not data.parts then return 0 end

    local count = 0
    for _, partData in pairs(data.parts) do
        if partData.stage and partData.stage > 0 then
            count = count + 1
        end
    end

    return count
end

function EHR.WoundInfection.HasAnyInfection(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data then return false end
    if data.totalInfectedParts and data.totalInfectedParts > 0 then
        return true
    end
    if data.parts then
        for _, partData in pairs(data.parts) do
            if partData.stage and partData.stage > 0 then
                return true
            end
        end
    end
    return false
end

function EHR.WoundInfection.IsTreatmentActive(player)
    if not player or not EHR.Medication or not EHR.Medication.GetMedicationData then
        return false
    end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local treatment = medTracking and medTracking.activeTreatments and medTracking.activeTreatments["wound_infection"] or nil
    if type(treatment) ~= "table" then return false end

    if treatment.medKey and EHR.Medication.GetDoseStatus then
        local status = EHR.Medication.GetDoseStatus(player, treatment.medKey)
        if status and status.isStaleOverdue then
            return false
        end
    end

    return true
end

function EHR.WoundInfection.IsAntisepticProtectionActive(player)
    if not player or not EHR.Medication or not EHR.Medication.GetDoseStatus then
        return false
    end

    local status = EHR.Medication.GetDoseStatus(player, "ExtensiveHealth.AntisepticCream")
    if status and status.isDoseActive == true then
        return true
    end

    status = EHR.Medication.GetDoseStatus(player, "Antiseptic Cream")
    return status and status.isDoseActive == true
end

-- ============================================
-- CORE LOGIC
-- ============================================

--[[
    Scan all body parts for vanilla infections.
    Create or update EHR tracking for infected parts.
]]--
function EHR.WoundInfection.ScanForInfections(player)
    if not player then return end
    if not EHR.WoundInfection.IsEnabled() then return end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    local data = EHR.WoundInfection.GetData(player)
    if not data then
        EHR.WoundInfection.InitializePlayer(player)
        data = EHR.WoundInfection.GetData(player)
        if not data then return end
    end
    data.antisepticBlocked = data.antisepticBlocked or {}

    local currentHour = getGameTime():getWorldAgeHours()
    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage

    -- Track counts for sepsis check
    local infectedCount = 0
    local worseningCount = 0
    local severeCount = 0
    local worstStage = 0
    local antisepticProtection = EHR.WoundInfection.IsAntisepticProtectionActive(player)

    -- Iterate all body parts (B42-safe, with fallbacks)
    if not BodyPartType then
        EHR.Log("WoundInfection: BodyPartType not available")
        return
    end

    local bodyPartTypes = nil
    local okValues, valuesResult = pcall(function()
        return BodyPartType.values and BodyPartType.values() or nil
    end)
    if okValues and valuesResult then
        bodyPartTypes = valuesResult
    end

    if bodyPartTypes then
        local function processBodyPartType(bpType)
            if not bpType then return end
            local partName = tostring(bpType)
            if partName == "MAX" or partName == "FromString" then
                return
            end
            local okBodyPart, bodyPart = pcall(function()
                return bodyDamage:getBodyPart(bpType)
            end)
            if not okBodyPart or not bodyPart then return end

            if bodyPart then
                local vanillaInfected = EHR.WoundInfection.IsVanillaInfected(bodyPart)
                local vanillaLevel = EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
                local partData = data.parts[partName]
                if not antisepticProtection and not vanillaInfected and not partData then
                    vanillaInfected = RestoreSuppressedVanillaInfection(data, partName, bodyPart)
                    if vanillaInfected then
                        vanillaLevel = EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
                    end
                elseif not BodyPartHasActiveWound(bodyPart) and data.antisepticBlocked then
                    data.antisepticBlocked[partName] = nil
                end

                if vanillaInfected then
                    local incubationMarker = data.incubating and data.incubating[partName] and "incubating" or "none"
                    local partStage = partData and partData.stage or "none"
                    DebugScanState(data, partName, bodyPart, string.format("vanilla-seen level=%s partStage=%s incubation=%s",
                        tostring(vanillaLevel), tostring(partStage), tostring(incubationMarker)))

                    if antisepticProtection and not partData then
                        SuppressVanillaInfectionDuringAntiseptic(player, data, partName, bodyPart, vanillaLevel)
                        return
                    end

                    -- Vanilla infection detected
                    local incubationData = data.incubating and data.incubating[partName]

                    if not partData and not incubationData then
                        -- Brand new infection - start incubation period
                        data.incubating = data.incubating or {}
                        data.incubating[partName] = {
                            detectedTime = currentHour,
                            vanillaLevel = vanillaLevel,
                            vanillaFlagActive = true,
                        }
                        EHR.Log("Wound infection incubating on " .. partName .. " (will show symptoms in " .. config.INCUBATION_HOURS .. "h)")
                        -- No dialogue yet - infection not symptomatic
                    elseif incubationData and not partData then
                        -- Check if incubation period has passed
                        local incubationTime = currentHour - incubationData.detectedTime
                        local adjustedIncubation = config.INCUBATION_HOURS / EHR.WoundInfection.GetSpeedMultiplier()

                        if incubationTime >= adjustedIncubation then
                            -- Incubation complete - start tracking
                            data.parts[partName] = {
                                stage = Stage.INFECTED,
                                stageStartTime = currentHour,
                                startTime = incubationData.detectedTime,
                                vanillaLevel = vanillaLevel,
                                vanillaFlagActive = true,
                            }
                            partData = data.parts[partName]
                            data.incubating[partName] = nil  -- Remove from incubation

                            -- NOW say dialogue - symptoms are showing
                            if player.Say then
                                EHR.Locale.Say(player, EHR.WoundInfection.StageDialogue[1])
                            end
                            EHR.Log("Wound infection now symptomatic on " .. partName)
                        else
                            -- Still incubating - update vanilla level but don't count it yet
                            incubationData.vanillaLevel = vanillaLevel
                            incubationData.vanillaFlagActive = true
                            incubationData.vanillaClearedTime = nil
                        end
                    elseif partData then
                        -- Existing infection - update vanilla level
                        partData.vanillaLevel = vanillaLevel
                        partData.vanillaFlagActive = true
                        partData.vanillaClearedTime = nil

                        -- Once EHR is tracking symptoms, progression is time-based.
                        -- Vanilla wound levels are kept for diagnostics but should
                        -- not jump an active infection straight into sepsis.
                    end

                    -- Count by stage (only if past incubation)
                    if partData and partData.stage then
                        if partData.stage >= Stage.SEVERE then
                            severeCount = severeCount + 1
                        elseif partData.stage >= Stage.WORSENING then
                            worseningCount = worseningCount + 1
                        elseif partData.stage >= Stage.INFECTED then
                            infectedCount = infectedCount + 1
                        end
                        worstStage = math.max(worstStage, partData.stage)
                    end
                else
                    local hadTrackedState = (partData and partData.stage and partData.stage > 0)
                            or (data.incubating and data.incubating[partName] ~= nil)
                    if hadTrackedState then
                        local incubationMarker = data.incubating and data.incubating[partName] and "incubating" or "none"
                        local partStage = partData and partData.stage or "none"
                        DebugScanState(data, partName, bodyPart, string.format("vanilla-missing partStage=%s incubation=%s",
                            tostring(partStage), tostring(incubationMarker)))
                    end

                    -- Vanilla infection cleared.
                    -- Once symptoms are tracked by EHR, vanilla flags are no longer authoritative:
                    -- normal bandaging/vanilla cleanup can clear them before the infection is cured.
                    if partData and partData.stage > 0 then
                        partData.vanillaLevel = 0
                        partData.vanillaFlagActive = false
                        partData.vanillaClearedTime = partData.vanillaClearedTime or currentHour
                    end
                    -- Vanilla can briefly clear its wound infection flag before EHR incubation finishes.
                    -- Once EHR has caught the infection, keep incubation alive; explicit disinfect actions
                    -- clear it through OnDisinfect instead.
                    local incubationData = data.incubating and data.incubating[partName]
                    if incubationData then
                        incubationData.vanillaFlagActive = false
                        incubationData.vanillaClearedTime = incubationData.vanillaClearedTime or currentHour

                        local incubationTime = currentHour - incubationData.detectedTime
                        local adjustedIncubation = config.INCUBATION_HOURS / EHR.WoundInfection.GetSpeedMultiplier()

                        if incubationTime >= adjustedIncubation then
                            data.parts[partName] = {
                                stage = Stage.INFECTED,
                                stageStartTime = currentHour,
                                startTime = incubationData.detectedTime,
                                vanillaLevel = incubationData.vanillaLevel or 0,
                                vanillaFlagActive = false,
                                vanillaClearedTime = incubationData.vanillaClearedTime,
                            }
                            partData = data.parts[partName]
                            data.incubating[partName] = nil

                            if player.Say then
                                EHR.Locale.Say(player, EHR.WoundInfection.StageDialogue[1])
                            end
                            EHR.Log("Wound infection now symptomatic on " .. partName .. " (vanilla flag cleared during incubation)")
                        end
                    end

                    if partData and partData.stage then
                        if partData.stage >= Stage.SEVERE then
                            severeCount = severeCount + 1
                        elseif partData.stage >= Stage.WORSENING then
                            worseningCount = worseningCount + 1
                        elseif partData.stage >= Stage.INFECTED then
                            infectedCount = infectedCount + 1
                        end
                        worstStage = math.max(worstStage, partData.stage)
                    end
                end
            end
        end

        if type(bodyPartTypes) == "table" then
            for _, bpType in ipairs(bodyPartTypes) do
                processBodyPartType(bpType)
            end
        elseif type(bodyPartTypes.size) == "function" and type(bodyPartTypes.get) == "function" then
            for i = 0, bodyPartTypes:size() - 1 do
                processBodyPartType(bodyPartTypes:get(i))
            end
        else
            -- Unknown container type, fall back to index iteration
            bodyPartTypes = nil
        end
    else
        local maxIndex = nil
        if BodyPartType.MAX then
            if BodyPartType.ToIndex then
                maxIndex = BodyPartType.ToIndex(BodyPartType.MAX)
            elseif BodyPartType.MAX.index then
                maxIndex = BodyPartType.MAX:index()
            elseif type(BodyPartType.MAX) == "number" then
                maxIndex = BodyPartType.MAX
            end
        end
        if not maxIndex or type(maxIndex) ~= "number" then
            maxIndex = 20
        end

        if BodyPartType.FromIndex then
            for i = 0, maxIndex - 1 do
                local bpType = BodyPartType.FromIndex(i)
                if bpType and tostring(bpType) == "MAX" then
                    bpType = nil
                end
                local okBodyPart, bodyPart = pcall(function()
                    return bpType and bodyDamage:getBodyPart(bpType) or nil
                end)
                if not okBodyPart then
                    bodyPart = nil
                end

                if bodyPart then
                    local partName = tostring(bpType)
                    local vanillaInfected = EHR.WoundInfection.IsVanillaInfected(bodyPart)
                    local vanillaLevel = EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
                    local partData = data.parts[partName]
                    if not antisepticProtection and not vanillaInfected and not partData then
                        vanillaInfected = RestoreSuppressedVanillaInfection(data, partName, bodyPart)
                        if vanillaInfected then
                            vanillaLevel = EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
                        end
                    elseif not BodyPartHasActiveWound(bodyPart) and data.antisepticBlocked then
                        data.antisepticBlocked[partName] = nil
                    end

                    if vanillaInfected then
                        local incubationMarker = data.incubating and data.incubating[partName] and "incubating" or "none"
                        local partStage = partData and partData.stage or "none"
                        DebugScanState(data, partName, bodyPart, string.format("fallback-vanilla-seen level=%s partStage=%s incubation=%s",
                            tostring(vanillaLevel), tostring(partStage), tostring(incubationMarker)))

                        if antisepticProtection and not partData then
                            SuppressVanillaInfectionDuringAntiseptic(player, data, partName, bodyPart, vanillaLevel)
                        else
                        if not partData then
                            data.parts[partName] = {
                                stage = Stage.INFECTED,
                                stageStartTime = currentHour,
                                startTime = currentHour,
                                vanillaLevel = vanillaLevel,
                                vanillaFlagActive = true,
                            }
                            partData = data.parts[partName]
                            if EHR.Dialogue and EHR.Dialogue.SayStageChange then
                                EHR.Dialogue.SayStageChange(player, EHR.WoundInfection.StageDialogue[1])
                            end
                            EHR.Log("New wound infection detected on " .. partName)
                        else
                            partData.vanillaLevel = vanillaLevel
                            partData.vanillaFlagActive = true
                            partData.vanillaClearedTime = nil
                            -- Existing EHR infections progress by time, not by
                            -- vanilla wound level spikes.
                        end

                        if partData.stage >= Stage.SEVERE then
                            severeCount = severeCount + 1
                        elseif partData.stage >= Stage.WORSENING then
                            worseningCount = worseningCount + 1
                        else
                            infectedCount = infectedCount + 1
                        end

                        worstStage = math.max(worstStage, partData.stage)
                        end
                    else
                        local hadTrackedState = (partData and partData.stage and partData.stage > 0)
                                or (data.incubating and data.incubating[partName] ~= nil)
                        if hadTrackedState then
                            local incubationMarker = data.incubating and data.incubating[partName] and "incubating" or "none"
                            local partStage = partData and partData.stage or "none"
                            DebugScanState(data, partName, bodyPart, string.format("fallback-vanilla-missing partStage=%s incubation=%s",
                                tostring(partStage), tostring(incubationMarker)))
                        end

                        if partData and partData.stage > 0 then
                            partData.vanillaLevel = 0
                            partData.vanillaFlagActive = false
                            partData.vanillaClearedTime = partData.vanillaClearedTime or currentHour
                        end
                    end
                end
            end
        end
    end

    -- Update summary stats from EHR active infections, not only from current vanilla flags.
    infectedCount = 0
    worseningCount = 0
    severeCount = 0
    local septicCount = 0
    worstStage = 0
    local worstPart = nil
    for partName, partData in pairs(data.parts) do
        local stage = tonumber(partData and partData.stage) or 0
        if stage >= Stage.SEPTIC then
            septicCount = septicCount + 1
        elseif stage >= Stage.SEVERE then
            severeCount = severeCount + 1
        elseif stage >= Stage.WORSENING then
            worseningCount = worseningCount + 1
        elseif stage >= Stage.INFECTED then
            infectedCount = infectedCount + 1
        end
        if stage > worstStage then
            worstStage = stage
            worstPart = partName
        end
    end

    data.totalInfectedParts = infectedCount + worseningCount + severeCount + septicCount
    data.infectedCount = data.totalInfectedParts
    data.worstStage = worstStage
    data.worstPart = worstPart
    data.lastCheck = currentHour

    -- Check sepsis trigger only after a wound actually reaches SEPTIC.
    if septicCount > 0 then
        EHR.WoundInfection.TriggerSepsis(player, data)
    end
end

--[[
    Update progression of tracked infections.
    Called after scanning.
]]--
function EHR.WoundInfection.UpdateProgression(player)
    if not player then return end

    local data = EHR.WoundInfection.GetData(player)
    if not data then return end

    local currentHour = getGameTime():getWorldAgeHours()
    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage
    local speedMult = EHR.WoundInfection.GetSpeedMultiplier()
    local treatmentActive = EHR.WoundInfection.IsTreatmentActive(player)

    local progressed = false
    local shouldTriggerSepsis = false
    for partName, partData in pairs(data.parts) do
        if partData.stage > 0 and partData.stage < Stage.SEPTIC then
            local stageDuration = config.STAGE_DURATION[partData.stage]
            if stageDuration then
                -- Adjust duration by speed multiplier
                local adjustedDuration = stageDuration / speedMult
                local hoursInStage = currentHour - (partData.stageStartTime or currentHour)

                if hoursInStage >= adjustedDuration then
                    if treatmentActive then
                        partData.stageStartTime = currentHour
                        if partData.treatmentHeldStage ~= partData.stage then
                            partData.treatmentHeldStage = partData.stage
                            EHR.Log("Wound infection progression held by active treatment on " .. tostring(partName))
                        end
                    else
                        partData.treatmentHeldStage = nil
                    -- Progress to next stage
                        local oldStage = partData.stage
                        local newStage = partData.stage + 1
                        partData.stage = newStage
                        partData.stageStartTime = currentHour
                        progressed = true
                        if newStage >= Stage.SEPTIC then
                            shouldTriggerSepsis = true
                        end

                        EHR.Log(string.format("Wound infection on %s progressed: %s -> %s",
                            partName,
                            EHR.WoundInfection.StageName[oldStage],
                            EHR.WoundInfection.StageName[partData.stage]))

                        -- Say dialogue
                        local dialogue = EHR.WoundInfection.StageDialogue[partData.stage]
                        if dialogue and EHR.Dialogue and EHR.Dialogue.SayStageChange then
                            EHR.Dialogue.SayStageChange(player, dialogue)
                        end
                    end
                end
            end
        end
    end

    if progressed then
        EHR.WoundInfection.RecalculateStats(player)
        if shouldTriggerSepsis or data.worstStage >= Stage.SEPTIC then
            EHR.WoundInfection.TriggerSepsis(player, data)
        end
    end
end

--[[
    Apply effects based on infection stage.
]]--
function EHR.WoundInfection.ApplyEffects(player)
    if not player then return end

    local data = EHR.WoundInfection.GetData(player)
    if not data or data.worstStage == 0 then return end

    local config = EHR.WoundInfection.Config
    local feverTarget = nil

    local painRelief = 0
    local feverRelief = 0
    if EHR.Disease and EHR.Disease.GetActiveSymptomReduction then
        painRelief = EHR.Disease.GetActiveSymptomReduction(player, "wound_infection", "pain") or 0
        feverRelief = EHR.Disease.GetActiveSymptomReduction(player, "wound_infection", "fever") or 0
    end

    if data.parts then
        for partName, partData in pairs(data.parts) do
            local stage = tonumber(partData and partData.stage) or 0
            local effects = config.STAGE_EFFECTS[stage]
            if effects then
                local targetPain = (tonumber(effects.painBonus) or 0) * math.max(0, 1 - painRelief)
                SetWoundSymptomPain(player, partName, partData, targetPain)

                if effects.feverTarget then
                    feverTarget = math.max(feverTarget or effects.feverTarget, effects.feverTarget)
                end
            end
        end
    end

    if feverTarget and EHR.BodyTemp and EHR.BodyTemp.MoveDiseaseFeverToward then
        local target = feverTarget
        local step = 0.020
        if feverRelief > 0 then
            local strongFeverReducer = feverRelief >= 0.60
            local feverFloor = strongFeverReducer and 37.0 or 37.3
            local feverDrop = strongFeverReducer and 2.0 or math.min(0.8, feverRelief * 1.2)
            target = math.max(feverFloor, target - feverDrop)
            step = step * math.max(0.35, 1 - feverRelief)
        end
        EHR.BodyTemp.MoveDiseaseFeverToward(player, target, step)
    end
end

--[[
    Trigger sepsis from wound infection.
]]--
function EHR.WoundInfection.TriggerSepsis(player, data)
    if not EHR.Sepsis or not EHR.Sepsis.Trigger then
        EHR.Log("WARNING: Sepsis module not available")
        return
    end

    local currentHour = getGameTime():getWorldAgeHours()
    local Stage = EHR.WoundInfection.Stage

    -- Find the worst infected body part as source
    local sourceBodyPart = nil
    local worstStage = 0
    for partName, partData in pairs(data.parts) do
        if partData.stage > worstStage then
            worstStage = partData.stage
            sourceBodyPart = partName
        end
    end

    if worstStage < Stage.SEPTIC then
        return
    end

    if EHR.WoundInfection.IsTreatmentActive(player) then
        for partName, partData in pairs(data.parts) do
            if partData.stage and partData.stage >= Stage.SEPTIC then
                partData.stage = Stage.SEVERE
                partData.stageStartTime = currentHour
                partData.sepsisBlockedByTreatment = true
            end
        end
        EHR.WoundInfection.RecalculateStats(player)
        EHR.Log("Sepsis trigger blocked by active wound infection treatment")
        return
    end

    EHR.Log("Triggering sepsis from wound infection on " .. (sourceBodyPart or "unknown"))

    local alreadySeptic = false
    if EHR.Sepsis.HasSepsis then
        alreadySeptic = EHR.Sepsis.HasSepsis(player)
    else
        local sepsisData = EHR.Sepsis.GetData and EHR.Sepsis.GetData(player) or nil
        alreadySeptic = sepsisData and sepsisData.stage and sepsisData.stage > 0
    end

    if not alreadySeptic then
        EHR.Sepsis.Trigger(player, sourceBodyPart)
    end

    -- SEPTIC is a handoff state. After sepsis is started, keep the local wound
    -- severe instead of leaving a permanent 100% wound card in the monitor.
    for partName, partData in pairs(data.parts) do
        if partData.stage and partData.stage >= Stage.SEPTIC then
            partData.stage = Stage.SEVERE
            partData.stageStartTime = currentHour
            partData.sepsisTriggered = true
            partData.lastSepsisTrigger = currentHour
        end
    end

    EHR.WoundInfection.RecalculateStats(player)
end

-- ============================================
-- TREATMENT
-- ============================================

function EHR.WoundInfection.OnDisinfect(player, bodyPartType)
    if not player or not bodyPartType then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] OnDisinfect skip missing player/bodyPartType")
        end
        return
    end

    local data = EHR.WoundInfection.GetData(player)
    if not data then
        EHR.WoundInfection.InitializePlayer(player)
        data = EHR.WoundInfection.GetData(player)
    end
    if not data then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] OnDisinfect skip no data")
        end
        return
    end

    local partName = GetPartName(bodyPartType)
    if not partName then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] OnDisinfect skip no partName")
        end
        return
    end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] OnDisinfect skip no bodyDamage part=" .. tostring(partName))
        end
        return
    end

    local bodyPart = bodyDamage:getBodyPart(bodyPartType)
    if not bodyPart then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] OnDisinfect skip no bodyPart part=" .. tostring(partName))
        end
        return
    end

    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage
    local currentHour = getGameTime():getWorldAgeHours()

    local vanillaInfected = EHR.WoundInfection.IsVanillaInfected(bodyPart)
    local vanillaLevel = EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
    local partData = data.parts[partName]
    local incubating = data.incubating and data.incubating[partName] ~= nil
    if EHR and EHR.DISINFECT_DEBUG == true then
        local alcohol = nil
        pcall(function() if bodyPart.getAlcoholLevel then alcohol = bodyPart:getAlcoholLevel() end end)
        print(string.format("[EHR][DisinfectDebug][WoundInfection] OnDisinfect start part=%s vanilla=%s level=%s alcohol=%s incubating=%s partStage=%s",
            tostring(partName), tostring(vanillaInfected), tostring(vanillaLevel), tostring(alcohol),
            tostring(incubating), tostring(partData and partData.stage or nil)))
    end

    -- =============================================
    -- INCUBATION PREVENTION: Disinfecting during incubation
    -- fully prevents the infection from developing
    -- =============================================

    -- Check if in EHR's incubation tracking
    if data.incubating and data.incubating[partName] then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] branch=incubation-prevention part=" .. tostring(partName))
        end
        -- Clear the incubating infection - disinfectant caught it early!
        data.incubating[partName] = nil

        -- Also clear the vanilla infection since we're preventing it
        EHR.WoundInfection.ClearVanillaInfection(bodyPart, "disinfect-incubating")

        EHR.Log("Disinfectant prevented wound infection on " .. partName .. " (caught during incubation)")

        -- Give player feedback
        if player.Say then
            EHR.Locale.Say(player, "Good thing I disinfected that early...")
        end

        EHR.WoundInfection.RecalculateStats(player)
        return
    end

    -- Check if vanilla has infection but EHR hasn't started tracking yet
    -- (player disinfected VERY quickly after getting wounded)
    if vanillaInfected and not partData then
        if EHR and EHR.DISINFECT_DEBUG == true then
            print("[EHR][DisinfectDebug][WoundInfection] branch=early-vanilla part=" .. tostring(partName))
        end
        -- Vanilla has an infection that EHR hasn't tracked yet
        -- This means it's very early - disinfecting now prevents it
        EHR.WoundInfection.ClearVanillaInfection(bodyPart, "disinfect-early-vanilla")

        EHR.Log("Disinfectant prevented wound infection on " .. partName .. " (caught before EHR tracking)")

        if player.Say then
            EHR.Locale.Say(player, "Good thing I disinfected that early...")
        end

        return
    end

    if not vanillaInfected then
        if partData and partData.stage and partData.stage > 0 then
            if EHR and EHR.DISINFECT_DEBUG == true then
                print("[EHR][DisinfectDebug][WoundInfection] branch=active-ehr-no-vanilla part=" .. tostring(partName))
            end
            -- Active infection is already symptomatic; disinfectant can slow local progression,
            -- but lack of a vanilla flag does not mean the infection is cured.
            partData.vanillaLevel = 0
            partData.vanillaFlagActive = false
            partData.vanillaClearedTime = partData.vanillaClearedTime or currentHour
            partData.stageStartTime = currentHour
            EHR.WoundInfection.RecalculateStats(player)
            if player.Say then
                EHR.Locale.Say(player, "I cleaned it, but the infection is still there...")
            end
        else
            if EHR and EHR.DISINFECT_DEBUG == true then
                print("[EHR][DisinfectDebug][WoundInfection] branch=no-vanilla-no-active part=" .. tostring(partName))
            end
        end
        return
    end

    -- If we get here, there's an active (post-incubation) infection
    -- Disinfecting now won't fully prevent it, but still helps via vanilla mechanics
    if EHR and EHR.DISINFECT_DEBUG == true then
        print("[EHR][DisinfectDebug][WoundInfection] branch=active-vanilla part=" .. tostring(partName))
    end
    if not partData then
        partData = {
            stage = Stage.INFECTED,
            stageStartTime = currentHour,
            startTime = currentHour,
            vanillaLevel = vanillaLevel,
            vanillaFlagActive = true,
        }
        data.parts[partName] = partData
    end

    partData.vanillaLevel = vanillaLevel
    partData.vanillaFlagActive = true
    partData.vanillaClearedTime = nil

    -- A disinfect action should clear the vanilla wound infection marker on
    -- first use. EHR's symptomatic infection remains active and must still be
    -- treated with the proper medication path.
    EHR.WoundInfection.ClearVanillaInfection(bodyPart, "disinfect-active-vanilla")
    partData.vanillaLevel = 0
    partData.vanillaFlagActive = false
    partData.vanillaClearedTime = currentHour

    local newStage = partData.stage or Stage.INFECTED

    if partData.stage ~= newStage then
        partData.stage = newStage
        partData.stageStartTime = currentHour
    else
        partData.stageStartTime = currentHour
    end

    EHR.WoundInfection.RecalculateStats(player)
end

--[[
    Handle antibiotic treatment.
    Reduces infection stage and clears vanilla infection if cured.
]]--
function EHR.WoundInfection.OnTakeAntibiotics(player, bodyPartName)
    if not player then return end

    local data = EHR.WoundInfection.GetData(player)
    if not data then return end

    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage

    -- If specific body part, treat just that
    if bodyPartName then
        local partData = data.parts[bodyPartName]
        if partData and partData.stage > 0 then
            EHR.WoundInfection.TreatPart(player, bodyPartName, partData)
        end
    else
        -- Treat all infected parts
        for partName, partData in pairs(data.parts) do
            if partData.stage > 0 and partData.stage < Stage.SEPTIC then
                EHR.WoundInfection.TreatPart(player, partName, partData)
            end
        end
    end

    -- Recalculate stats
    EHR.WoundInfection.RecalculateStats(player)
end

--[[
    Treat a specific body part.
]]--
function EHR.WoundInfection.TreatPart(player, partName, partData)
    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage

    local oldStage = partData.stage
    partData.stage = math.max(0, partData.stage - config.ANTIBIOTIC_REDUCTION)

    EHR.Log(string.format("Treated wound infection on %s: %s -> %s",
        partName,
        EHR.WoundInfection.StageName[oldStage],
        EHR.WoundInfection.StageName[partData.stage]))

    -- If cured, clear vanilla infection too
    if partData.stage == Stage.CLEAN then
        ClearWoundSymptomPain(player, partName, partData)

        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            local bpType = BodyPartType[partName]
            if bpType then
                local bodyPart = bodyDamage:getBodyPart(bpType)
                if bodyPart then
                    EHR.WoundInfection.ClearVanillaInfection(bodyPart, "antibiotic-cured")
                end
            end
        end

        -- Remove from tracking
        local data = EHR.WoundInfection.GetData(player)
        if data then
            data.parts[partName] = nil
        end

        EHR.Log("Wound infection on " .. partName .. " fully cured")
    else
        -- Reset stage timer
        partData.stageStartTime = getGameTime():getWorldAgeHours()
    end

    -- MP: Trigger server sync after wound treatment
    if isClient() then
        sendClientCommand(player, "EHR", "RequestSync", {})
    end
end

function EHR.WoundInfection.CureAll(player, source)
    if not player then return false end

    local data = EHR.WoundInfection.GetData(player)
    if not data or not data.parts then return false end

    local curedAny = false
    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)

    for partName, partData in pairs(data.parts) do
        if partData and (tonumber(partData.stage) or 0) > 0 then
            curedAny = true
            ClearWoundSymptomPain(player, partName, partData)

            if bodyDamage and BodyPartType and BodyPartType[partName] then
                local bodyPart = nil
                pcall(function() bodyPart = bodyDamage:getBodyPart(BodyPartType[partName]) end)
                if bodyPart then
                    EHR.WoundInfection.ClearVanillaInfection(bodyPart, "cure-all")
                end
            end

            data.parts[partName] = nil
        end
    end

    EHR.WoundInfection.RecalculateStats(player)

    if curedAny then
        if EHR.BodyTemp and EHR.BodyTemp.ResetDiseaseFeverIfStale then
            EHR.BodyTemp.ResetDiseaseFeverIfStale(player, true)
        end
        EHR.Log("Wound infection fully cured by " .. tostring(source or "treatment"))
    end

    if isClient() then
        sendClientCommand(player, "EHR", "RequestSync", {})
    end

    return curedAny
end

--[[
    Recalculate summary stats.
]]--
function EHR.WoundInfection.RecalculateStats(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data then return end

    local Stage = EHR.WoundInfection.Stage
    local infectedCount = 0
    local worstStage = 0
    local worstPart = nil

    for partName, partData in pairs(data.parts) do
        local stage = tonumber(partData and partData.stage) or 0
        if stage > 0 then
            infectedCount = infectedCount + 1
            if stage > worstStage then
                worstStage = stage
                worstPart = partName
            end
        end
    end

    data.totalInfectedParts = infectedCount
    data.infectedCount = infectedCount
    data.worstStage = worstStage
    data.worstPart = worstPart
end

-- ============================================
-- HEALING CONTROL
-- ============================================

--[[
    Check if wounds can heal normally.
    @return boolean, string - canHeal, reason
]]--
function EHR.WoundInfection.CanHeal(player, bodyPartName)
    if not player then return true, nil end

    local data = EHR.WoundInfection.GetData(player)
    if not data then return true, nil end

    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage

    -- Check specific body part if provided
    if bodyPartName then
        local partData = data.parts[bodyPartName]
        if partData then
            local effects = config.STAGE_EFFECTS[partData.stage]
            if effects and effects.healingPenalty >= 1.0 then
                return false, "Severe infection"
            elseif effects and effects.healingPenalty > 0 then
                return true, "Reduced (infection)"
            end
        end
        return true, nil
    end

    -- Check worst stage overall
    if data.worstStage >= Stage.SEVERE then
        return false, "Severe wound infection"
    elseif data.worstStage >= Stage.INFECTED then
        return true, "Reduced (wound infection)"
    end

    return true, nil
end

--[[
    Get the healing penalty multiplier (0 = full speed, 1 = no healing).
]]--
function EHR.WoundInfection.GetHealingPenalty(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data then return 0 end

    local config = EHR.WoundInfection.Config
    local effects = config.STAGE_EFFECTS[data.worstStage]

    return effects and effects.healingPenalty or 0
end

-- ============================================
-- STATUS FOR UI
-- ============================================

--[[
    Get infection status text for UI display.
]]--
function EHR.WoundInfection.GetStatusText(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data or data.worstStage == 0 then
        return "No wound infections"
    end

    local count = data.totalInfectedParts
    local stageName = EHR.WoundInfection.StageName[data.worstStage] or "Unknown"

    if count == 1 then
        return string.format("1 wound: %s", stageName)
    else
        return string.format("%d wounds, worst: %s", count, stageName)
    end
end

--[[
    Get status color for UI.
]]--
function EHR.WoundInfection.GetStatusColor(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data then return {r=0.5, g=0.5, b=0.5} end

    local Stage = EHR.WoundInfection.Stage

    if data.worstStage >= Stage.SEVERE then
        return {r=0.9, g=0.1, b=0.1}  -- Red
    elseif data.worstStage >= Stage.WORSENING then
        return {r=0.9, g=0.5, b=0.1}  -- Orange
    elseif data.worstStage >= Stage.INFECTED then
        return {r=0.9, g=0.9, b=0.1}  -- Yellow
    else
        return {r=0.5, g=0.9, b=0.5}  -- Green
    end
end

-- ============================================
-- TICK HANDLER
-- ============================================

local tickCounter = 0
local TICK_INTERVAL = 900  -- Every ~30 seconds
local effectTickCounter = 0
local EFFECT_TICK_INTERVAL = 120  -- Keep pain/fever stable during time acceleration

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

function EHR.WoundInfection.OnTick()
    if not EHR.WoundInfection.IsEnabled() then return end
    if isClient and isClient() and not (isServer and isServer()) then return end

    tickCounter = tickCounter + 1
    effectTickCounter = effectTickCounter + 1

    local runScan = tickCounter >= TICK_INTERVAL
    local runEffects = effectTickCounter >= EFFECT_TICK_INTERVAL
    if not runScan and not runEffects then return end

    if runScan then tickCounter = 0 end
    if runEffects then effectTickCounter = 0 end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        if player and not player:isDead() then
            if EHR.WoundInfection.IsGodModeActive(player) then
                EHR.WoundInfection.ClearForGodMode(player)
            else
                if runScan then
                    EHR.WoundInfection.ScanForInfections(player)
                    EHR.WoundInfection.UpdateProgression(player)
                end
                if runEffects or runScan then
                    EHR.WoundInfection.ApplyEffects(player)
                end
                if runScan and EHR and EHR.SafeTransmitModData then
                    EHR.SafeTransmitModData(player)
                end
            end
        end
    end
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function EHR.WoundInfection.OnGameStart()
    EHR.Log("Wound Infection V2 module initialized")
    local player = getSpecificPlayer(0)
    if player then
        EHR.WoundInfection.InitializePlayer(player)
    end
end

function EHR.WoundInfection.OnCreatePlayer(playerIndex, player)
    EHR.WoundInfection.InitializePlayer(player)
end

function EHR.WoundInfection.OnPlayerDeath(player)
    EHR.Log("Player died, clearing wound infection data")
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events then
    Events.OnTick.Add(EHR.WoundInfection.OnTick)
    Events.OnGameStart.Add(EHR.WoundInfection.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.WoundInfection.OnCreatePlayer)
    Events.OnPlayerDeath.Add(EHR.WoundInfection.OnPlayerDeath)
end

EHR.Log = EHR.Log or function(msg) print("[EHR] " .. tostring(msg)) end
EHR.Log("EHR_WoundInfection_V2.lua loaded")
