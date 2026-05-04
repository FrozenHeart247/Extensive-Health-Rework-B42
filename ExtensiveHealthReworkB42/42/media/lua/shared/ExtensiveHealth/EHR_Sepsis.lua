--[[
    Extensive Health Rework B42
    Sepsis Module

    Systemic blood infection (septicemia):
    - Triggered by severe/multiple wound infections
    - Whole-body disease, not limb-specific
    - Lethal without IV antibiotics treatment
    - Stages: EARLY -> PROGRESSING -> SEVERE -> TERMINAL -> death

    v1.0.0 - Initial implementation

    B42 API Notes:
    - CharacterStat.SICKNESS for fever display (0-1 scale)
    - CharacterStat.STRESS for confusion effect
    - All healing blocked during active sepsis
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Disease"

EHR = EHR or {}
EHR.Sepsis = {}

-- ============================================
-- MP FIX: Debug Menu Grace Period
-- ============================================
-- Tracks when debug menu sets data to prevent server sync overwrites
-- Key: player username, Value: os.time() when debug data was set
EHR.Sepsis.DebugGracePeriod = {}
EHR.Sepsis.GRACE_PERIOD_SECONDS = 10  -- Don't overwrite for 10 seconds after debug set

-- Call this from debug menu when setting sepsis data
function EHR.Sepsis.MarkDebugSet(player)
    if not player then return end
    local username = player:getUsername() or tostring(player:getPlayerNum())
    EHR.Sepsis.DebugGracePeriod[username] = os.time()
    print("[EHR Sepsis] Debug grace period started for " .. username)
end

-- Check if we're in grace period (shouldn't overwrite debug data)
function EHR.Sepsis.IsInDebugGracePeriod(player)
    if not player then return false end
    local username = player:getUsername() or tostring(player:getPlayerNum())
    local setTime = EHR.Sepsis.DebugGracePeriod[username]
    if not setTime then return false end

    local elapsed = os.time() - setTime
    if elapsed < EHR.Sepsis.GRACE_PERIOD_SECONDS then
        return true
    else
        -- Grace period expired, clear it
        EHR.Sepsis.DebugGracePeriod[username] = nil
        return false
    end
end

-- Helper to get sandbox settings with defaults
function EHR.Sepsis.GetSetting(name, default)
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local value = SandboxVars.ExtensiveHealthRework[name]
        if value ~= nil then
            return value
        end
    end
    return default
end

-- Check if sepsis system is enabled
function EHR.Sepsis.IsEnabled()
    return EHR.Sepsis.GetSetting("SepsisEnabled", true)
end

-- Get sepsis speed multiplier
function EHR.Sepsis.GetSpeedMultiplier()
    return EHR.Sepsis.GetSetting("SepsisSpeed", 1.0)
end

-- ============================================
-- STAGE ENUM
-- ============================================

EHR.Sepsis.Stage = {
    NONE = 0,           -- No sepsis
    EARLY = 1,          -- Early sepsis: treatable with 2 IV doses
    PROGRESSING = 2,    -- Progressing: treatable with 3 IV doses
    SEVERE = 3,         -- Severe: treatable with 5 IV doses
    TERMINAL = 4,       -- Terminal: 7 IV doses + 50% luck
}

-- ============================================
-- CONFIGURATION
-- ============================================

-- Hours at each stage before progression
EHR.Sepsis.StageDuration = {
    [1] = 12,   -- EARLY: 12 hours to PROGRESSING
    [2] = 8,    -- PROGRESSING: 8 hours to SEVERE
    [3] = 6,    -- SEVERE: 6 hours to TERMINAL
    [4] = 4,    -- TERMINAL: 4 hours to death
}

-- IV antibiotic doses required per stage
EHR.Sepsis.TreatmentDosesRequired = {
    [1] = 2,    -- EARLY: 2 doses to cure
    [2] = 3,    -- PROGRESSING: 3 doses
    [3] = 5,    -- SEVERE: 5 doses
    [4] = 7,    -- TERMINAL: 7 doses + 50% survival chance
}

-- Effects per stage
EHR.Sepsis.StageEffects = {
    [1] = {
        feverBonus = 0.15,      -- +15% sickness stat (mild fever)
        confusionChance = 0.0,
        deathChancePerCheck = 0.0,
    },
    [2] = {
        feverBonus = 0.30,      -- +30% sickness (moderate fever)
        confusionChance = 0.1,  -- 10% per check
        deathChancePerCheck = 0.0,
    },
    [3] = {
        feverBonus = 0.50,      -- +50% sickness (high fever)
        confusionChance = 0.3,  -- 30% per check
        deathChancePerCheck = 0.01,  -- 1% per check
    },
    [4] = {
        feverBonus = 0.70,      -- +70% sickness (critical)
        confusionChance = 0.5,  -- 50% per check
        deathChancePerCheck = 0.05,  -- 5% per check
    },
}

-- ============================================
-- DIALOGUE
-- ============================================

EHR.Sepsis.StageEntryDialogue = {
    [1] = "Something's very wrong... the infection is in my blood...",
    [2] = "I'm shaking... can't think straight...",
    [3] = "*shivering uncontrollably* I need IV antibiotics NOW!",
    [4] = "I'm dying... this is it...",
}

EHR.Sepsis.Dialogue = {
    [1] = { "I feel weak all over...", "Cold and hot at the same time..." },
    [2] = { "Can't focus...", "My heart is racing...", "Where am I?" },
    [3] = { "*delirious mumbling*", "Is someone there?", "I can't see straight..." },
    [4] = { "*barely conscious*", "*labored breathing*" },
}

-- ============================================
-- TICK MANAGEMENT
-- ============================================

local SEPSIS_TICK_INTERVAL = 300  -- Every 300 ticks (~10 seconds)

local SEPSIS_DIALOGUE_INTERVAL = 1800  -- Every ~1 minute

-- MP: per-player tick state (avoid shared counters across players)
local tickStateByPlayer = {}

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
        state = { sepsis = 0, dialogue = 0, debug = 0 }
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

-- ============================================
-- INITIALIZATION
-- ============================================

--[[
    Initialize sepsis data for a player
]]--
function EHR.Sepsis.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if modData.EHR_Sepsis_Initialized then
        return
    end

    -- MP FIX: Don't overwrite during debug grace period
    -- Debug menu sets data and we need to protect it from server sync overwrites
    if EHR.Sepsis.IsInDebugGracePeriod(player) then
        print("[EHR Sepsis] In debug grace period, skipping initialization")
        -- If debug data exists, mark as initialized to prevent future calls
        if modData.EHR_Sepsis and modData.EHR_Sepsis.stage and modData.EHR_Sepsis.stage > 0 then
            modData.EHR_Sepsis_Initialized = true
        end
        return
    end

    -- SAFETY: If sepsis data already exists with active stage, don't reinitialize!
    -- This prevents accidental resets from event handler race conditions
    if modData.EHR_Sepsis and modData.EHR_Sepsis.stage and modData.EHR_Sepsis.stage > 0 then
        EHR.Log("SAFETY: Sepsis already active (stage " .. modData.EHR_Sepsis.stage .. "), preserving state")
        modData.EHR_Sepsis_Initialized = true
        return
    end

    EHR.Log("Initializing sepsis data...")

    modData.EHR_Sepsis = {
        active = false,
        stage = 0,
        startTime = nil,
        stageStartTime = nil,
        sourceBodyPart = nil,
        lastIVAntibiotics = nil,
        treatmentDoses = 0,
        lastCuredTime = nil,  -- Cooldown to prevent immediate re-trigger after cure
    }

    modData.EHR_Sepsis_Initialized = true
    EHR.Log("Sepsis module initialized for player")
end

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

--[[
    Get sepsis data for a player
]]--
function EHR.Sepsis.GetData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData or not modData.EHR_Sepsis then return nil end
    return modData.EHR_Sepsis
end

--[[
    Check if player has active sepsis
    STABILITY FIX: Use stage > 0 as source of truth, not the active flag
    This prevents flickering - once triggered, stays until properly cured
]]--
function EHR.Sepsis.HasSepsis(player)
    local data = EHR.Sepsis.GetData(player)
    if not data then return false end
    -- Stage > 0 is the real indicator, active flag is secondary
    return data.stage and data.stage > 0
end

--[[
    Get current sepsis stage
]]--
function EHR.Sepsis.GetStage(player)
    local data = EHR.Sepsis.GetData(player)
    if not data then return 0 end
    return data.stage or 0
end

-- ============================================
-- TRIGGER
-- ============================================

--[[
    Trigger sepsis in a player
    Called by WoundInfection when a wound reaches SEPTIC stage
    or when 3+ wounds are INFECTED
]]--
function EHR.Sepsis.Trigger(player, sourcePartName)
    local data = EHR.Sepsis.GetData(player)
    if not data then
        EHR.Sepsis.InitializePlayer(player)
        data = EHR.Sepsis.GetData(player)
    end
    if not data then return end

    -- Already have sepsis? Use stage > 0 as source of truth (more stable than active flag)
    if data.stage and data.stage > 0 then
        EHR.Log("Sepsis already active (stage " .. data.stage .. "), ignoring trigger")
        return
    end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    -- Cooldown check: prevent re-trigger within 2 hours of being cured
    -- This gives player time to treat underlying infections
    local RETRIGGER_COOLDOWN_HOURS = 2.0
    if data.lastCuredTime then
        local hoursSinceCure = currentHour - data.lastCuredTime
        if hoursSinceCure < RETRIGGER_COOLDOWN_HOURS then
            EHR.Log(string.format("Sepsis trigger blocked - cooldown active (%.1fh remaining)",
                RETRIGGER_COOLDOWN_HOURS - hoursSinceCure))
            return
        end
    end

    data.active = true
    data.stage = EHR.Sepsis.Stage.EARLY
    data.startTime = currentHour
    data.stageStartTime = currentHour
    data.sourceBodyPart = sourcePartName
    data.treatmentDoses = 0
    data.lastIVAntibiotics = nil

    EHR.Log(string.format("SEPSIS TRIGGERED! Source: %s", sourcePartName or "unknown"))

    -- Entry dialogue
    if player.Say and EHR.Sepsis.StageEntryDialogue[1] then
        player:Say(EHR.Sepsis.StageEntryDialogue[1])
    end
end

-- ============================================
-- PROGRESSION
-- ============================================

--[[
    Update sepsis progression
]]--
function EHR.Sepsis.UpdateProgression(player)
    local data = EHR.Sepsis.GetData(player)
    if not data or not data.stage or data.stage <= 0 then return end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    local stage = data.stage
    local hoursInStage = currentHour - (data.stageStartTime or currentHour)
    local baseDuration = EHR.Sepsis.StageDuration[stage]

    if not baseDuration then return end

    -- Apply speed multiplier (higher speed = shorter duration)
    local duration = baseDuration / EHR.Sepsis.GetSpeedMultiplier()

    -- Check for progression
    if hoursInStage >= duration then
        local oldStage = stage
        local newStage = stage + 1

        if newStage > EHR.Sepsis.Stage.TERMINAL then
            -- Death
            EHR.Sepsis.OnDeath(player, "sepsis_timeout")
            return
        end

        data.stage = newStage
        data.stageStartTime = currentHour

        EHR.Log(string.format("Sepsis progressed: stage %d -> %d", oldStage, newStage))

        -- Entry dialogue
        if player.Say and EHR.Sepsis.StageEntryDialogue[newStage] then
            player:Say(EHR.Sepsis.StageEntryDialogue[newStage])
        end
    end
end

-- ============================================
-- EFFECTS
-- ============================================

--[[
    Apply sepsis effects (fever, confusion, death check)
]]--
function EHR.Sepsis.ApplyEffects(player)
    local data = EHR.Sepsis.GetData(player)
    if not data or not data.stage or data.stage <= 0 then return end

    local stats = player:getStats()
    if not stats then return end

    local effects = EHR.Sepsis.StageEffects[data.stage]
    if not effects then return end

    -- 1. Fever (via SICKNESS stat for moodle display)
    if CharacterStat and CharacterStat.SICKNESS and effects.feverBonus > 0 then
        pcall(function()
            -- Set sickness to show fever moodle
            local current = stats:get(CharacterStat.SICKNESS) or 0
            local target = math.max(current, effects.feverBonus)
            stats:set(CharacterStat.SICKNESS, target)
        end)
    end

    -- 2. Confusion (via STRESS stat spike)
    if effects.confusionChance > 0 and ZombRand(100) < (effects.confusionChance * 100) then
        if CharacterStat and CharacterStat.STRESS then
            pcall(function()
                local current = stats:get(CharacterStat.STRESS) or 0
                stats:set(CharacterStat.STRESS, math.min(1, current + 0.2))
            end)
        end

        -- Random confusion dialogue
        if player.Say and ZombRand(100) < 30 then
            local confusionLines = { "Where am I?", "What's happening?", "I can't think..." }
            player:Say(confusionLines[ZombRand(#confusionLines) + 1])
        end
    end

    -- 3. Random death check (severe/terminal stages)
    if effects.deathChancePerCheck > 0 then
        if ZombRand(100) < (effects.deathChancePerCheck * 100) then
            EHR.Sepsis.OnDeath(player, "sepsis_organ_failure")
        end
    end
end

-- ============================================
-- DEATH
-- ============================================

--[[
    Handle sepsis death
]]--
function EHR.Sepsis.OnDeath(player, reason)
    EHR.Log(string.format("Sepsis death: %s", reason))

    -- Final dialogue
    if player.Say then
        player:Say("*collapses*")
    end

    -- Build descriptive death cause for tracking
    local data = EHR.Sepsis.GetData(player)
    local stageNames = {
        [1] = "Early",
        [2] = "Progressing",
        [3] = "Severe",
        [4] = "TERMINAL",
    }
    local stageName = data and stageNames[data.stage] or "Unknown"
    local deathCause

    if reason == "sepsis_timeout" then
        deathCause = string.format("Sepsis (Stage %d - %s) - untreated blood infection progressed beyond terminal stage",
            data and data.stage or 0, stageName)
    elseif reason == "sepsis_organ_failure" then
        deathCause = string.format("Sepsis Organ Failure (Stage %d - %s) - multi-organ failure from systemic blood infection",
            data and data.stage or 0, stageName)
    else
        deathCause = string.format("Sepsis Death (Stage %d - %s) - %s",
            data and data.stage or 0, stageName, reason or "unknown cause")
    end

    -- Record death cause before killing
    if EHR.RecordDeathCause then
        EHR.RecordDeathCause(player, deathCause)
    end

    -- Kill the player
    if player.setHealth then
        pcall(function() player:setHealth(0) end)
    end

    -- Alternative: use body damage
    local bodyDamage = player:getBodyDamage()
    if bodyDamage and bodyDamage.setOverallBodyHealth then
        pcall(function() bodyDamage:setOverallBodyHealth(0) end)
    end
end

-- ============================================
-- TREATMENT
-- ============================================

--[[
    Called when player uses IV antibiotics
    Returns: true if item should be consumed
]]--
function EHR.Sepsis.OnTakeIVAntibiotics(player)
    local data = EHR.Sepsis.GetData(player)
    if not data then return false end

    -- Use stage > 0 as source of truth
    if not data.stage or data.stage <= 0 then
        if player.Say then
            player:Say("I don't need this right now...")
        end
        return false  -- Don't consume
    end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    data.treatmentDoses = (data.treatmentDoses or 0) + 1
    data.lastIVAntibiotics = currentHour

    local required = EHR.Sepsis.TreatmentDosesRequired[data.stage] or 3
    local remaining = required - data.treatmentDoses

    EHR.Log(string.format("IV antibiotics: dose %d/%d for stage %d",
        data.treatmentDoses, required, data.stage))

    -- Award First Aid XP for sepsis treatment dose
    if EHR.SkillXP and EHR.SkillXP.OnSepsisTreatment then
        EHR.SkillXP.OnSepsisTreatment(player)
    end

    if data.treatmentDoses >= required then
        if data.stage == EHR.Sepsis.Stage.TERMINAL then
            -- Terminal stage: 50% cure chance
            if ZombRand(100) < 50 then
                EHR.Sepsis.Cure(player)
                if player.Say then
                    player:Say("*gasps* I... I think it's working...")
                end
            else
                if player.Say then
                    player:Say("*weakly* It's not enough... I can feel it...")
                end
                -- Reset doses, player needs to try again
                data.treatmentDoses = 0
            end
        else
            -- Non-terminal: guaranteed cure at dose threshold
            EHR.Sepsis.Cure(player)
            if player.Say then
                player:Say("*relief* The fever is breaking... I might make it...")
            end
        end
    else
        if player.Say then
            player:Say(string.format("I need %d more doses...", remaining))
        end
    end

    return true  -- Consume item
end

--[[
    Cure sepsis
]]--
function EHR.Sepsis.Cure(player)
    local data = EHR.Sepsis.GetData(player)
    if not data then return end

    EHR.Log("Sepsis CURED!")

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    data.active = false
    data.stage = EHR.Sepsis.Stage.NONE
    data.startTime = nil
    data.stageStartTime = nil
    data.sourceBodyPart = nil
    data.treatmentDoses = 0
    data.lastIVAntibiotics = nil
    data.lastCuredTime = currentHour  -- Set cooldown to prevent immediate re-trigger

    -- CRITICAL FIX: Clear SEPTIC wounds to prevent re-triggering
    -- When sepsis is cured, downgrade any SEPTIC wounds back to SEVERE
    -- This prevents the cure->retrigger loop
    if EHR.WoundInfection and EHR.WoundInfection.GetData then
        local woundData = EHR.WoundInfection.GetData(player)
        if woundData and woundData.parts then
            for partName, partData in pairs(woundData.parts) do
                if partData.stage >= 4 then  -- SEPTIC stage
                    -- Downgrade to SEVERE (stage 3) so patient still needs treatment
                    -- but won't immediately re-trigger sepsis
                    partData.stage = 3  -- SEVERE
                    partData.stageStartTime = currentHour
                    EHR.Log(string.format("Downgraded SEPTIC wound on %s to SEVERE after sepsis cure", partName))
                end
            end
        end
    end

    -- Clear sickness stat
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.SICKNESS then
        pcall(function()
            -- Don't zero it completely, just reduce
            local current = stats:get(CharacterStat.SICKNESS) or 0
            stats:set(CharacterStat.SICKNESS, math.max(0, current - 0.5))
        end)
    end

    -- Build immunity to wound infections
    if EHR.Disease and EHR.Disease.GetDiseaseData then
        local diseaseData = EHR.Disease.GetDiseaseData(player)
        if diseaseData and diseaseData.immunity then
            diseaseData.immunity["wound_infection"] = math.min(0.5,
                (diseaseData.immunity["wound_infection"] or 0) + 0.25)
        end
    end

    -- Award First Aid XP for curing sepsis (major achievement)
    if EHR.SkillXP and EHR.SkillXP.OnDiseaseCured then
        EHR.SkillXP.OnDiseaseCured(player, "Sepsis")
    end

    -- Record cure in Medical Journal
    if EHR.MedicalJournal and EHR.MedicalJournal.RecordCure then
        EHR.MedicalJournal.RecordCure(player, "Sepsis")
    end

    -- MP: Trigger server sync after sepsis cure
    if isClient() then
        sendClientCommand(player, "EHR", "RequestSync", {})
    end
end

-- ============================================
-- QUERY FUNCTIONS (for UI/other modules)
-- ============================================

--[[
    Get status text for UI
]]--
function EHR.Sepsis.GetStatusText(player)
    local data = EHR.Sepsis.GetData(player)
    if not data or not data.stage or data.stage <= 0 then return "" end

    local stageNames = {
        [1] = "Early",
        [2] = "Progressing",
        [3] = "Severe",
        [4] = "TERMINAL",
    }

    local stageName = stageNames[data.stage] or "Unknown"
    local required = EHR.Sepsis.TreatmentDosesRequired[data.stage] or 0
    local doses = data.treatmentDoses or 0

    return string.format("SEPSIS: %s (%d/%d doses)", stageName, doses, required)
end

--[[
    Get color for sepsis status
]]--
function EHR.Sepsis.GetStatusColor(player)
    local data = EHR.Sepsis.GetData(player)
    if not data or not data.stage or data.stage <= 0 then
        return {r = 0.5, g = 0.5, b = 0.5}  -- Gray
    end

    local stage = data.stage

    if stage == 1 then
        return {r = 0.87, g = 0.4, b = 0.0}   -- Orange (EARLY)
    elseif stage == 2 then
        return {r = 0.87, g = 0.13, b = 0.13}  -- Red (PROGRESSING)
    elseif stage == 3 then
        return {r = 0.67, g = 0.0, b = 0.0}   -- Dark red (SEVERE)
    else
        return {r = 0.5, g = 0.0, b = 0.0}    -- Very dark red (TERMINAL)
    end
end

--[[
    Get time remaining estimate
]]--
function EHR.Sepsis.GetTimeRemaining(player)
    local data = EHR.Sepsis.GetData(player)
    if not data or not data.stage or data.stage <= 0 then return nil end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    local hoursInStage = currentHour - (data.stageStartTime or currentHour)
    local duration = EHR.Sepsis.StageDuration[data.stage] or 12
    local remaining = duration - hoursInStage

    return math.max(0, remaining)
end

-- ============================================
-- DIALOGUE
-- ============================================

--[[
    Check if player should say something about sepsis
]]--
function EHR.Sepsis.CheckDialogue(player)
    local data = EHR.Sepsis.GetData(player)
    if not data or not data.stage or data.stage <= 0 then return end
    if not player.Say then return end

    local dialogueList = EHR.Sepsis.Dialogue[data.stage]
    if not dialogueList or #dialogueList == 0 then return end

    -- Higher chance for worse stages
    local speakChance = data.stage * 15  -- 15%, 30%, 45%, 60%

    if ZombRand(100) < speakChance then
        local line = dialogueList[ZombRand(#dialogueList) + 1]
        player:Say(line)
    end
end

-- ============================================
-- MAIN TICK HANDLER
-- ============================================

-- Debug: track last known stage and data reference to detect unexpected resets
local lastKnownSepsisStage = {}
local lastKnownSepsisData = {}
local function processPlayerTick(player)
    -- Check if sepsis is enabled in sandbox
    if not EHR.Sepsis.IsEnabled() then
        return
    end

    if not player then return end
    if not player:isAlive() then return end

    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    local modData = player:getModData()

    -- DEBUG: Check raw modData every tick
    local state = getTickState(player)
    state.debug = state.debug + 1
    local rawSepsisExists = modData.EHR_Sepsis ~= nil
    local rawStage = rawSepsisExists and modData.EHR_Sepsis.stage or -1

    -- Log every 60 ticks (~2 seconds) when sepsis should be active
    if lastKnownSepsisStage[playerID] and lastKnownSepsisStage[playerID] > 0 then
        if state.debug >= 60 then
            state.debug = 0
            print("[EHR SEPSIS DEBUG] Tick check: rawExists=" .. tostring(rawSepsisExists) .. ", rawStage=" .. tostring(rawStage) .. ", lastKnown=" .. tostring(lastKnownSepsisStage[playerID]))
        end
    end

    -- MP FIX: Don't initialize during debug grace period - protect debug data
    if EHR.Sepsis.IsInDebugGracePeriod(player) then
        -- During grace period, trust whatever data exists
        if modData.EHR_Sepsis and modData.EHR_Sepsis.stage and modData.EHR_Sepsis.stage > 0 then
            -- Debug data exists, track it
            lastKnownSepsisStage[playerID] = modData.EHR_Sepsis.stage
            modData.EHR_Sepsis_Initialized = true
            print("[EHR SEPSIS] Grace period active, preserving debug sepsis stage=" .. modData.EHR_Sepsis.stage)
        end
        return  -- Skip normal processing during grace period
    end

    -- Initialize if needed
    if not modData.EHR_Sepsis_Initialized then
        EHR.Sepsis.InitializePlayer(player)
        return
    end

    local data = EHR.Sepsis.GetData(player)

    -- DEBUG: Detect unexpected resets (data nil OR stage 0)
    local currentStage = data and data.stage or 0
    local lastStage = lastKnownSepsisStage[playerID] or 0

    if lastStage > 0 and currentStage == 0 then
        -- Check if this was an INTENTIONAL cure (lastCuredTime is set)
        -- If so, don't recover - the cure was deliberate!
        local wasCured = modData.EHR_Sepsis and modData.EHR_Sepsis.lastCuredTime ~= nil

        if wasCured then
            -- Intentional cure - clear tracking and don't recover
            print("[EHR SEPSIS] Stage cleared intentionally (cure detected), clearing tracking")
            lastKnownSepsisStage[playerID] = 0
        else
            -- Stage was reset unexpectedly! Log it
            print("[EHR SEPSIS BUG] Stage reset detected!")
            print("[EHR SEPSIS BUG] Was stage " .. lastStage .. ", now " .. currentStage)
            print("[EHR SEPSIS BUG] data exists: " .. tostring(data ~= nil))
            print("[EHR SEPSIS BUG] modData.EHR_Sepsis exists: " .. tostring(modData.EHR_Sepsis ~= nil))
            print("[EHR SEPSIS BUG] EHR_Sepsis_Initialized: " .. tostring(modData.EHR_Sepsis_Initialized))

            -- RECOVERY: Restore the data if possible
            if not modData.EHR_Sepsis then
                -- Data object was destroyed! Recreate it
                print("[EHR SEPSIS BUG] Data object was DESTROYED! Recreating...")
                local gameTime = getGameTime()
                local currentHour = gameTime:getWorldAgeHours()
                modData.EHR_Sepsis = {
                    active = true,
                    stage = lastStage,
                    startTime = currentHour,
                    stageStartTime = currentHour,
                    sourceBodyPart = "Recovered",
                    treatmentDoses = 0,
                    lastIVAntibiotics = nil,
                    lastCuredTime = nil,
                }
                print("[EHR SEPSIS BUG] RECOVERED - Recreated data with stage " .. lastStage)
            elseif modData.EHR_Sepsis.stage == 0 then
                -- Stage was reset but data exists
                print("[EHR SEPSIS BUG] Stage was zeroed! Restoring...")
                modData.EHR_Sepsis.stage = lastStage
                modData.EHR_Sepsis.active = true
                print("[EHR SEPSIS BUG] RECOVERED - Restored stage to " .. lastStage)
            end

            -- Update data reference after recovery
            data = EHR.Sepsis.GetData(player)
        end
    end

    -- Update tracking
    if data and data.stage and data.stage > 0 then
        lastKnownSepsisStage[playerID] = data.stage
    end

    -- Use stage > 0 as source of truth (more stable than active flag)
    if not data or not data.stage or data.stage <= 0 then return end

    -- Sepsis checks (every ~10 seconds)
    state.sepsis = state.sepsis + 1
    if state.sepsis >= SEPSIS_TICK_INTERVAL then
        state.sepsis = 0

        -- 1. Update progression
        EHR.Sepsis.UpdateProgression(player)

        -- 2. Apply effects (fever, confusion, death check)
        EHR.Sepsis.ApplyEffects(player)
    end

    -- Dialogue checks (every ~1 minute)
    state.dialogue = state.dialogue + 1
    if state.dialogue >= SEPSIS_DIALOGUE_INTERVAL then
        state.dialogue = 0
        EHR.Sepsis.CheckDialogue(player)
    end
end

function EHR.Sepsis.OnTick()
    if not EHR.Sepsis.IsEnabled() then
        return
    end

    -- MP: server-authoritative processing
    if isClient and isClient() and not (isServer and isServer()) then return end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function EHR.Sepsis.OnGameStart()
    EHR.Log("Sepsis module OnGameStart")

    local player = getSpecificPlayer(0)
    if player then
        EHR.Sepsis.InitializePlayer(player)
    end
end

function EHR.Sepsis.OnCreatePlayer(playerIndex, player)
    EHR.Log("Sepsis module OnCreatePlayer: " .. playerIndex)
    EHR.Sepsis.InitializePlayer(player)
end

function EHR.Sepsis.OnPlayerDeath(player)
    if not player then return end
    local modData = player:getModData()
    if not modData then return end

    modData.EHR_Sepsis = nil
    modData.EHR_Sepsis_Initialized = nil

    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    lastKnownSepsisStage[playerID] = 0
    lastKnownSepsisData[playerID] = nil

    EHR.Log("Sepsis module: Cleared sepsis data on death")
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events then
    Events.OnTick.Add(EHR.Sepsis.OnTick)
    Events.OnGameStart.Add(EHR.Sepsis.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.Sepsis.OnCreatePlayer)
    Events.OnPlayerDeath.Add(EHR.Sepsis.OnPlayerDeath)

    EHR.Log("Sepsis module events registered")
end

EHR.Log("Sepsis module loaded v1.0.0")
