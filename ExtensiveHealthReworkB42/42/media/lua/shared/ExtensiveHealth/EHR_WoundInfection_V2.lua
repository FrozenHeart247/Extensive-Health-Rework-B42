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
        [0] = { healingPenalty = 0.0, painBonus = 0 },     -- CLEAN
        [1] = { healingPenalty = 0.25, painBonus = 5 },    -- INFECTED: 25% slower
        [2] = { healingPenalty = 0.50, painBonus = 10 },   -- WORSENING: 50% slower
        [3] = { healingPenalty = 1.0, painBonus = 20 },    -- SEVERE: no healing
        [4] = { healingPenalty = 1.0, painBonus = 30 },    -- SEPTIC
    },

    -- Sepsis trigger conditions
    SEPSIS_SEVERE_COUNT = 1,      -- Number of SEVERE wounds needed
    SEPSIS_WORSENING_COUNT = 2,   -- OR number of WORSENING wounds needed

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

function EHR.WoundInfection.IsVanillaInfected(bodyPart)
    if not bodyPart then return false end
    local success, result = pcall(function()
        return bodyPart:isInfectedWound()
    end)
    return success and result or false
end

function EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)
    if not bodyPart then return 0 end
    local success, result = pcall(function()
        return bodyPart:getWoundInfectionLevel()
    end)
    return success and (result or 0) or 0
end

function EHR.WoundInfection.ClearVanillaInfection(bodyPart)
    if not bodyPart then return end
    pcall(function()
        bodyPart:setWoundInfectionLevel(-1)
        bodyPart:setInfectedWound(false)
    end)
    EHR.Log("Cleared vanilla infection on body part")
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
            totalInfectedParts = 0,
            worstStage = 0,
            lastCheck = 0,
        }
    end
    -- Ensure incubating table exists for older saves
    modData.EHR_WoundInfection.incubating = modData.EHR_WoundInfection.incubating or {}

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

    local currentHour = getGameTime():getWorldAgeHours()
    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage

    -- Track counts for sepsis check
    local infectedCount = 0
    local worseningCount = 0
    local severeCount = 0
    local worstStage = 0

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

                if vanillaInfected then
                    -- Vanilla infection detected
                    local incubationData = data.incubating and data.incubating[partName]

                    if not partData and not incubationData then
                        -- Brand new infection - start incubation period
                        data.incubating = data.incubating or {}
                        data.incubating[partName] = {
                            detectedTime = currentHour,
                            vanillaLevel = vanillaLevel,
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
                            }
                            partData = data.parts[partName]
                            data.incubating[partName] = nil  -- Remove from incubation

                            -- NOW say dialogue - symptoms are showing
                            if player.Say then
                                player:Say(EHR.WoundInfection.StageDialogue[1])
                            end
                            EHR.Log("Wound infection now symptomatic on " .. partName)
                        else
                            -- Still incubating - update vanilla level but don't count it yet
                            incubationData.vanillaLevel = vanillaLevel
                        end
                    elseif partData then
                        -- Existing infection - update vanilla level
                        partData.vanillaLevel = vanillaLevel

                        -- Sync stage with vanilla level if vanilla is ahead
                        if vanillaLevel >= config.VANILLA_SEVERE_THRESHOLD and partData.stage < Stage.SEVERE then
                            partData.stage = Stage.SEVERE
                            partData.stageStartTime = currentHour
                        elseif vanillaLevel >= config.VANILLA_WORSENING_THRESHOLD and partData.stage < Stage.WORSENING then
                            partData.stage = Stage.WORSENING
                            partData.stageStartTime = currentHour
                        end
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
                    -- Vanilla infection cleared
                    if partData and partData.stage > 0 then
                        -- Vanilla cleared but EHR was tracking - clear EHR too
                        EHR.Log("Vanilla cleared infection on " .. partName .. ", clearing EHR tracking")
                        data.parts[partName] = nil
                    end
                    -- Also clear from incubation if it was there
                    if data.incubating and data.incubating[partName] then
                        EHR.Log("Vanilla cleared incubating infection on " .. partName)
                        data.incubating[partName] = nil
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

                    if vanillaInfected then
                        if not partData then
                            data.parts[partName] = {
                                stage = Stage.INFECTED,
                                stageStartTime = currentHour,
                                startTime = currentHour,
                                vanillaLevel = vanillaLevel,
                            }
                            partData = data.parts[partName]
                            if EHR.Dialogue and EHR.Dialogue.SayStageChange then
                                EHR.Dialogue.SayStageChange(player, EHR.WoundInfection.StageDialogue[1])
                            end
                            EHR.Log("New wound infection detected on " .. partName)
                        else
                            partData.vanillaLevel = vanillaLevel
                            if vanillaLevel >= config.VANILLA_SEVERE_THRESHOLD and partData.stage < Stage.SEVERE then
                                partData.stage = Stage.SEVERE
                                partData.stageStartTime = currentHour
                            elseif vanillaLevel >= config.VANILLA_WORSENING_THRESHOLD and partData.stage < Stage.WORSENING then
                                partData.stage = Stage.WORSENING
                                partData.stageStartTime = currentHour
                            end
                        end

                        if partData.stage >= Stage.SEVERE then
                            severeCount = severeCount + 1
                        elseif partData.stage >= Stage.WORSENING then
                            worseningCount = worseningCount + 1
                        else
                            infectedCount = infectedCount + 1
                        end

                        worstStage = math.max(worstStage, partData.stage)
                    else
                        if partData and partData.stage > 0 then
                            EHR.Log("Vanilla cleared infection on " .. partName .. ", clearing EHR tracking")
                            data.parts[partName] = nil
                        end
                    end
                end
            end
        end
    end

    -- Update summary stats
    data.totalInfectedParts = infectedCount + worseningCount + severeCount
    data.worstStage = worstStage
    data.lastCheck = currentHour

    -- Check sepsis trigger
    if severeCount >= config.SEPSIS_SEVERE_COUNT or worseningCount >= config.SEPSIS_WORSENING_COUNT then
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

    for partName, partData in pairs(data.parts) do
        if partData.stage > 0 and partData.stage < Stage.SEPTIC then
            local stageDuration = config.STAGE_DURATION[partData.stage]
            if stageDuration then
                -- Adjust duration by speed multiplier
                local adjustedDuration = stageDuration / speedMult
                local hoursInStage = currentHour - (partData.stageStartTime or currentHour)

                if hoursInStage >= adjustedDuration then
                    -- Progress to next stage
                    local oldStage = partData.stage
                    partData.stage = partData.stage + 1
                    partData.stageStartTime = currentHour

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

--[[
    Apply effects based on infection stage.
]]--
function EHR.WoundInfection.ApplyEffects(player)
    if not player then return end

    local data = EHR.WoundInfection.GetData(player)
    if not data or data.worstStage == 0 then return end

    local config = EHR.WoundInfection.Config
    local effects = config.STAGE_EFFECTS[data.worstStage]
    if not effects then return end

    -- Apply pain
    if effects.painBonus > 0 then
        local stats = player:getStats()
        if stats and stats.getPain and stats.setPain then
            local okPain, currentPain = pcall(function() return stats:getPain() end)
            if okPain and currentPain then
                local targetPain = math.min(100, currentPain + effects.painBonus * 0.01)
                pcall(function() stats:setPain(targetPain) end)
            end
        end
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

    -- Find the worst infected body part as source
    local sourceBodyPart = nil
    local worstStage = 0
    for partName, partData in pairs(data.parts) do
        if partData.stage > worstStage then
            worstStage = partData.stage
            sourceBodyPart = partName
        end
    end

    EHR.Log("Triggering sepsis from wound infection on " .. (sourceBodyPart or "unknown"))
    EHR.Sepsis.Trigger(player, sourceBodyPart)

    -- Mark all parts as SEPTIC
    for partName, partData in pairs(data.parts) do
        if partData.stage >= EHR.WoundInfection.Stage.WORSENING then
            partData.stage = EHR.WoundInfection.Stage.SEPTIC
        end
    end
end

-- ============================================
-- TREATMENT
-- ============================================

function EHR.WoundInfection.OnDisinfect(player, bodyPartType)
    if not player or not bodyPartType then return end

    local data = EHR.WoundInfection.GetData(player)
    if not data then
        EHR.WoundInfection.InitializePlayer(player)
        data = EHR.WoundInfection.GetData(player)
    end
    if not data then return end

    local partName = GetPartName(bodyPartType)
    if not partName then return end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    local bodyPart = bodyDamage:getBodyPart(bodyPartType)
    if not bodyPart then return end

    local config = EHR.WoundInfection.Config
    local Stage = EHR.WoundInfection.Stage
    local currentHour = getGameTime():getWorldAgeHours()

    local vanillaInfected = EHR.WoundInfection.IsVanillaInfected(bodyPart)
    local vanillaLevel = EHR.WoundInfection.GetVanillaInfectionLevel(bodyPart)

    -- =============================================
    -- INCUBATION PREVENTION: Disinfecting during incubation
    -- fully prevents the infection from developing
    -- =============================================

    -- Check if in EHR's incubation tracking
    if data.incubating and data.incubating[partName] then
        -- Clear the incubating infection - disinfectant caught it early!
        data.incubating[partName] = nil

        -- Also clear the vanilla infection since we're preventing it
        EHR.WoundInfection.ClearVanillaInfection(bodyPart)

        EHR.Log("Disinfectant prevented wound infection on " .. partName .. " (caught during incubation)")

        -- Give player feedback
        if player.Say then
            player:Say("Good thing I disinfected that early...")
        end

        EHR.WoundInfection.RecalculateStats(player)
        return
    end

    -- Check if vanilla has infection but EHR hasn't started tracking yet
    -- (player disinfected VERY quickly after getting wounded)
    local partData = data.parts[partName]
    if vanillaInfected and not partData then
        -- Vanilla has an infection that EHR hasn't tracked yet
        -- This means it's very early - disinfecting now prevents it
        EHR.WoundInfection.ClearVanillaInfection(bodyPart)

        EHR.Log("Disinfectant prevented wound infection on " .. partName .. " (caught before EHR tracking)")

        if player.Say then
            player:Say("Good thing I disinfected that early...")
        end

        return
    end

    if not vanillaInfected then
        if data.parts[partName] then
            data.parts[partName] = nil
            EHR.WoundInfection.RecalculateStats(player)
        end
        return
    end

    -- If we get here, there's an active (post-incubation) infection
    -- Disinfecting now won't fully prevent it, but still helps via vanilla mechanics
    if not partData then
        partData = {
            stage = Stage.INFECTED,
            stageStartTime = currentHour,
            startTime = currentHour,
            vanillaLevel = vanillaLevel,
        }
        data.parts[partName] = partData
    end

    partData.vanillaLevel = vanillaLevel

    local newStage = Stage.INFECTED
    if vanillaLevel >= config.VANILLA_SEVERE_THRESHOLD then
        newStage = Stage.SEVERE
    elseif vanillaLevel >= config.VANILLA_WORSENING_THRESHOLD then
        newStage = Stage.WORSENING
    end

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
        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            local bpType = BodyPartType[partName]
            if bpType then
                local bodyPart = bodyDamage:getBodyPart(bpType)
                if bodyPart then
                    EHR.WoundInfection.ClearVanillaInfection(bodyPart)
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

--[[
    Recalculate summary stats.
]]--
function EHR.WoundInfection.RecalculateStats(player)
    local data = EHR.WoundInfection.GetData(player)
    if not data then return end

    local Stage = EHR.WoundInfection.Stage
    local infectedCount = 0
    local worstStage = 0

    for partName, partData in pairs(data.parts) do
        if partData.stage > 0 then
            infectedCount = infectedCount + 1
            worstStage = math.max(worstStage, partData.stage)
        end
    end

    data.totalInfectedParts = infectedCount
    data.worstStage = worstStage
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
    if tickCounter < TICK_INTERVAL then return end
    tickCounter = 0

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        if player and not player:isDead() then
            EHR.WoundInfection.ScanForInfections(player)
            EHR.WoundInfection.UpdateProgression(player)
            EHR.WoundInfection.ApplyEffects(player)
            if isServer and isServer() and player.transmitModData then
                pcall(function() player:transmitModData() end)
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
