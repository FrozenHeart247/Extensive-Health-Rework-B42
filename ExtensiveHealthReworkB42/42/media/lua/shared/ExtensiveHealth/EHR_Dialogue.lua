--[[
    Extensive Health Rework B42
    Dialogue System Module

    Centralized control for all character dialogue/speech.
    Respects DialogueFrequency sandbox setting.
    Integrates with MedicalSkill for skill-based dialogue selection.

    Frequency Levels:
        1 = Off (no dialogue)
        2 = Rare (25% chance for random, critical only)
        3 = Normal (100% default behavior)
        4 = Frequent (200% chance for random events)

    v1.1.0 - Added skill-based dialogue system
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_MedicalSkill"
require "ExtensiveHealth/EHR_DialogueData"

EHR = EHR or {}
EHR.Dialogue = {}

-- ============================================
-- DIALOGUE COOLDOWN TRACKING
-- Limits messages to once per disease per severity per day
-- ============================================

-- Track last dialogue time: dialogueCooldowns[playerId][disease][stage] = worldHour
EHR.Dialogue.cooldowns = {}

-- Cooldown duration in game hours (24 = 1 day)
EHR.Dialogue.COOLDOWN_HOURS = 24

--[[
    Get a unique player ID for tracking
]]--
local function getPlayerId(player)
    if not player then return "unknown" end
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
    return tostring(player:getPlayerNum() or 0)
end

--[[
    Check if dialogue is on cooldown for this disease+stage
    @param player (IsoPlayer) - The player
    @param disease (string) - Disease ID
    @param stage (number) - Stage/severity level
    @return boolean - True if on cooldown (should NOT say)
]]--
function EHR.Dialogue.IsOnCooldown(player, disease, stage)
    if not player or not disease then return false end

    local playerId = getPlayerId(player)
    local cooldowns = EHR.Dialogue.cooldowns[playerId]
    if not cooldowns then return false end

    local diseaseCooldowns = cooldowns[disease]
    if not diseaseCooldowns then return false end

    local lastTime = diseaseCooldowns[stage]
    if not lastTime then return false end

    local currentHour = getGameTime():getWorldAgeHours()
    return (currentHour - lastTime) < EHR.Dialogue.COOLDOWN_HOURS
end

--[[
    Record that dialogue was said for this disease+stage
    @param player (IsoPlayer) - The player
    @param disease (string) - Disease ID
    @param stage (number) - Stage/severity level
]]--
function EHR.Dialogue.RecordCooldown(player, disease, stage)
    if not player or not disease then return end

    local playerId = getPlayerId(player)
    local currentHour = getGameTime():getWorldAgeHours()

    EHR.Dialogue.cooldowns[playerId] = EHR.Dialogue.cooldowns[playerId] or {}
    EHR.Dialogue.cooldowns[playerId][disease] = EHR.Dialogue.cooldowns[playerId][disease] or {}
    EHR.Dialogue.cooldowns[playerId][disease][stage] = currentHour
end

--[[
    Clear all cooldowns for a player (e.g., when disease is cured)
    @param player (IsoPlayer) - The player
    @param disease (string, optional) - Disease ID to clear, or nil for all
]]--
function EHR.Dialogue.ClearCooldowns(player, disease)
    if not player then return end

    local playerId = getPlayerId(player)
    if not EHR.Dialogue.cooldowns[playerId] then return end

    if disease then
        EHR.Dialogue.cooldowns[playerId][disease] = nil
    else
        EHR.Dialogue.cooldowns[playerId] = nil
    end
end

-- ============================================
-- CONSTANTS
-- ============================================

-- Frequency multipliers for each sandbox setting (1-indexed, setting is 1-4)
EHR.Dialogue.FREQUENCY_MULTIPLIERS = {
    [1] = 0,      -- Off
    [2] = 0.25,   -- Rare
    [3] = 1.0,    -- Normal
    [4] = 2.0,    -- Frequent
}

-- Dialogue types
EHR.Dialogue.Types = {
    CRITICAL = "critical",     -- Always say (death, major events) unless Off
    STAGE_CHANGE = "stage",    -- Stage transitions - say unless Off
    RANDOM = "random",         -- Random chance events - affected by frequency
    PERIODIC = "periodic",     -- Periodic reminders - affected by frequency
}

-- ============================================
-- CONFIGURATION
-- ============================================

--[[
    Get the current dialogue frequency multiplier from sandbox settings.
    @return number - Multiplier (0, 0.25, 1.0, or 2.0)
]]--
function EHR.Dialogue.GetFrequencyMultiplier()
    local setting = 3  -- Default to Normal (option 3)

    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local rawSetting = SandboxVars.ExtensiveHealthRework.DialogueFrequency
        if rawSetting and type(rawSetting) == "number" then
            setting = math.floor(rawSetting)
        end
    end

    -- Clamp to valid range (1-4)
    setting = math.max(1, math.min(4, setting))

    return EHR.Dialogue.FREQUENCY_MULTIPLIERS[setting] or 1.0
end

--[[
    Check if dialogue is completely disabled.
    @return boolean - True if dialogue is off
]]--
function EHR.Dialogue.IsDisabled()
    return EHR.Dialogue.GetFrequencyMultiplier() == 0
end

-- ============================================
-- CORE DIALOGUE FUNCTIONS
-- ============================================

--[[
    Make the player say a line of dialogue, respecting frequency settings.

    @param player (IsoPlayer) - The player to speak
    @param text (string) - The text to say (already localized via getText)
    @param dialogueType (string) - Type from EHR.Dialogue.Types
    @param baseChance (number, optional) - For RANDOM type, base 1-in-X chance (default 1 = always)
    @return boolean - True if dialogue was said
]]--
function EHR.Dialogue.Say(player, text, dialogueType, baseChance)
    -- Safety checks
    if not player or not player.Say then return false end
    if not text or text == "" then return false end

    local multiplier = EHR.Dialogue.GetFrequencyMultiplier()
    dialogueType = dialogueType or EHR.Dialogue.Types.STAGE_CHANGE
    baseChance = baseChance or 1

    -- Off = no dialogue at all
    if multiplier == 0 then
        return false
    end

    -- Critical and stage change always happen (unless Off)
    if dialogueType == EHR.Dialogue.Types.CRITICAL or
       dialogueType == EHR.Dialogue.Types.STAGE_CHANGE then
        player:Say(text)
        return true
    end

    -- Random and periodic events use probability
    if dialogueType == EHR.Dialogue.Types.RANDOM or
       dialogueType == EHR.Dialogue.Types.PERIODIC then
        -- Adjust chance based on multiplier
        -- Higher multiplier = more likely to speak
        -- baseChance is "1 in X", so we divide by multiplier to increase frequency
        local adjustedChance = math.ceil(baseChance / multiplier)
        adjustedChance = math.max(1, adjustedChance)  -- At least 1 in 1

        if ZombRand(adjustedChance) < 1 then
            player:Say(text)
            return true
        end
    end

    return false
end

--[[
    Say a critical dialogue (death, major events).
    Always says unless dialogue is completely off.

    @param player (IsoPlayer) - The player
    @param text (string) - The text to say
    @return boolean - True if said
]]--
function EHR.Dialogue.SayCritical(player, text)
    return EHR.Dialogue.Say(player, text, EHR.Dialogue.Types.CRITICAL)
end

--[[
    Say a stage change dialogue (entering new disease/blood stage).
    Always says unless dialogue is completely off.

    @param player (IsoPlayer) - The player
    @param text (string) - The text to say
    @return boolean - True if said
]]--
function EHR.Dialogue.SayStageChange(player, text)
    return EHR.Dialogue.Say(player, text, EHR.Dialogue.Types.STAGE_CHANGE)
end

--[[
    Say a random dialogue with specified base chance.
    Frequency setting affects the actual chance.

    @param player (IsoPlayer) - The player
    @param text (string) - The text to say
    @param oneInX (number) - Base chance as "1 in X" (e.g., 400 = 1 in 400)
    @return boolean - True if said
]]--
function EHR.Dialogue.SayRandom(player, text, oneInX)
    return EHR.Dialogue.Say(player, text, EHR.Dialogue.Types.RANDOM, oneInX)
end

--[[
    Say a periodic reminder dialogue.
    Used for recurring status messages.

    @param player (IsoPlayer) - The player
    @param text (string) - The text to say
    @param oneInX (number) - Base chance as "1 in X"
    @return boolean - True if said
]]--
function EHR.Dialogue.SayPeriodic(player, text, oneInX)
    return EHR.Dialogue.Say(player, text, EHR.Dialogue.Types.PERIODIC, oneInX)
end

-- ============================================
-- CONVENIENCE WRAPPERS
-- ============================================

--[[
    Check if random dialogue should happen (without saying).
    Useful when you need to do something else besides just Say().

    @param oneInX (number) - Base chance as "1 in X"
    @return boolean - True if the check passes
]]--
function EHR.Dialogue.ShouldSayRandom(oneInX)
    local multiplier = EHR.Dialogue.GetFrequencyMultiplier()

    if multiplier == 0 then return false end

    local adjustedChance = math.ceil(oneInX / multiplier)
    adjustedChance = math.max(1, adjustedChance)

    return ZombRand(adjustedChance) < 1
end

--[[
    Get the current frequency setting name for UI display.
    @return string - "Off", "Rare", "Normal", or "Frequent"
]]--
function EHR.Dialogue.GetFrequencyName()
    local setting = 3
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local rawSetting = SandboxVars.ExtensiveHealthRework.DialogueFrequency
        if rawSetting and type(rawSetting) == "number" then
            setting = math.floor(rawSetting)
        end
    end
    setting = math.max(1, math.min(4, setting))

    local names = {"Off", "Rare", "Normal", "Frequent"}
    return names[setting] or "Normal"
end

-- ============================================
-- SKILL-BASED DIALOGUE SYSTEM
-- ============================================

--[[
    Get skill-appropriate dialogue text for a disease/stage.
    Uses player's effective medical skill to select dialogue tier.

    @param player (IsoPlayer) - The player
    @param disease (string) - Disease ID (e.g., "Sepsis", "FoodPoisoning")
    @param stage (number) - Current stage (1-4)
    @param isCorrectDiagnosis (boolean) - Whether diagnosis was correct
    @param diagnosedAs (string, optional) - What disease was diagnosed (for misdiagnosis)
    @return string - Localized dialogue text, or nil if none found
]]--
function EHR.Dialogue.GetSkillDialogue(player, disease, stage, isCorrectDiagnosis, diagnosedAs)
    if not player then return nil end

    -- Get player's effective skill and tier group
    local effectiveSkill = EHR.MedicalSkill.GetEffectiveSkill(player, "disease")
    local tierGroup = EHR.MedicalSkill.GetTierGroup(effectiveSkill)

    local dialogueKey

    if isCorrectDiagnosis then
        -- Correct diagnosis - use real disease dialogue
        dialogueKey = EHR.DialogueData.GetRandomDialogueKey(disease, stage, tierGroup)
    else
        -- Wrong diagnosis - use false assumption dialogue
        diagnosedAs = diagnosedAs or "Unknown"
        dialogueKey = EHR.DialogueData.GetFalseAssumptionKey(disease, diagnosedAs)
    end

    -- Return localized text if key found
    if dialogueKey then
        local text = getText(dialogueKey)
        -- Fallback if translation not found
        -- PZ returns "?" for missing keys, not the key itself
        if text == dialogueKey or text == "?" or text == nil or text == "" then
            -- Return a generic message based on tier
            if tierGroup == "clueless" then
                return "Something feels wrong..."
            elseif tierGroup == "novice" then
                return "I don't feel well..."
            else
                return "I'm experiencing symptoms..."
            end
        end
        return text
    end

    return nil
end

--[[
    Say dialogue with automatic diagnosis roll.
    Rolls for diagnosis accuracy, selects appropriate dialogue, and speaks.
    Also records to Medical Journal if available.

    COOLDOWN: Limited to once per disease per stage per day to reduce spam.

    @param player (IsoPlayer) - The player
    @param disease (string) - The actual disease ID
    @param stage (number) - Current stage (1-4)
    @param dialogueType (string) - Type from EHR.Dialogue.Types
    @return boolean - True if dialogue was said
    @return boolean - True if diagnosis was correct
]]--
function EHR.Dialogue.SayWithDiagnosis(player, disease, stage, dialogueType)
    -- Safety checks
    if not player or not player.Say then return false, false end
    if EHR.Dialogue.IsDisabled() then return false, false end

    -- Check cooldown - only one message per disease per stage per day
    if EHR.Dialogue.IsOnCooldown(player, disease, stage) then
        return false, false
    end

    -- Roll for diagnosis accuracy
    local diagnosedAs, isCorrect = EHR.MedicalSkill.RollDiagnosis(player, disease, stage)

    -- Get skill-appropriate dialogue
    local text = EHR.Dialogue.GetSkillDialogue(player, disease, stage, isCorrect, diagnosedAs)

    if text then
        -- Use existing frequency-aware Say function
        local said = EHR.Dialogue.Say(player, text, dialogueType or EHR.Dialogue.Types.STAGE_CHANGE)

        if said then
            -- Record cooldown so we don't repeat this disease+stage today
            EHR.Dialogue.RecordCooldown(player, disease, stage)

            -- Record to Medical Journal if available
            if EHR.MedicalJournal and EHR.MedicalJournal.RecordDiagnosis then
                EHR.MedicalJournal.RecordDiagnosis(player, disease, stage, diagnosedAs, isCorrect)
            end

            -- Handle misdiagnosis consequences
            if not isCorrect then
                EHR.Dialogue.HandleMisdiagnosis(player, disease, diagnosedAs)
            end
        end

        return said, isCorrect
    end

    return false, false
end

--[[
    Handle consequences of a misdiagnosis.
    Stores misdiagnosis in ModData for treatment system to check.

    @param player (IsoPlayer) - The player
    @param actualDisease (string) - What the disease actually is
    @param diagnosedAs (string) - What it was diagnosed as
]]--
function EHR.Dialogue.HandleMisdiagnosis(player, actualDisease, diagnosedAs)
    if not player then return end

    -- Store misdiagnosis in ModData for treatment checks
    local modData = player:getModData()
    if modData then
        modData.EHR_LastMisdiagnosis = {
            actual = actualDisease,
            diagnosed = diagnosedAs,
            time = getGameTime():getWorldAgeHours(),
        }

        -- Log for debug
        if EHR.DEBUG then
            EHR.Log(string.format("Misdiagnosis: %s diagnosed as %s", actualDisease, diagnosedAs))
        end
    end
end

--[[
    Check if player has a recent misdiagnosis stored.
    Used by treatment system to determine if wrong treatment is being applied.

    @param player (IsoPlayer) - The player
    @param maxAgeHours (number, optional) - Max age of misdiagnosis to consider (default 24)
    @return table or nil - Misdiagnosis data, or nil if none/expired
]]--
function EHR.Dialogue.GetRecentMisdiagnosis(player, maxAgeHours)
    if not player then return nil end

    maxAgeHours = maxAgeHours or 24

    local modData = player:getModData()
    if not modData or not modData.EHR_LastMisdiagnosis then
        return nil
    end

    local misdiagnosis = modData.EHR_LastMisdiagnosis
    local currentTime = getGameTime():getWorldAgeHours()

    -- Check if misdiagnosis is still recent
    if currentTime - misdiagnosis.time > maxAgeHours then
        -- Clear expired misdiagnosis
        modData.EHR_LastMisdiagnosis = nil
        return nil
    end

    return misdiagnosis
end

--[[
    Clear stored misdiagnosis (e.g., after correct diagnosis or treatment).

    @param player (IsoPlayer) - The player
]]--
function EHR.Dialogue.ClearMisdiagnosis(player)
    if not player then return end

    local modData = player:getModData()
    if modData then
        modData.EHR_LastMisdiagnosis = nil
    end
end

--[[
    Say treatment hint dialogue based on player's skill.
    Only triggered for intermediate+ skill levels with correct diagnosis.

    @param player (IsoPlayer) - The player
    @param disease (string) - Disease ID
    @return boolean - True if hint was said
]]--
function EHR.Dialogue.SayTreatmentHint(player, disease)
    if not player or not player.Say then return false end
    if EHR.Dialogue.IsDisabled() then return false end

    local effectiveSkill = EHR.MedicalSkill.GetEffectiveSkill(player, "disease")
    local tierGroup = EHR.MedicalSkill.GetTierGroup(effectiveSkill)

    -- Clueless tier doesn't get treatment hints
    if tierGroup == "clueless" then
        return false
    end

    local hintKey = EHR.DialogueData.GetTreatmentHintKey(disease, tierGroup)
    if hintKey then
        local text = getText(hintKey)
        -- PZ returns "?" for missing keys
        if text and text ~= hintKey and text ~= "?" and text ~= "" then
            return EHR.Dialogue.SayRandom(player, text, 3)  -- 1 in 3 chance
        end
    end

    return false
end

--[[
    Check if player is enabled for dialogue (helper for external modules).
    @return boolean - True if dialogue system is active
]]--
function EHR.Dialogue.IsEnabled()
    return not EHR.Dialogue.IsDisabled()
end

--[[
    Say a disease-related message with cooldown (once per disease per stage per day).
    Use this for periodic disease symptoms to avoid spam.

    @param player (IsoPlayer) - The player
    @param text (string) - The text to say
    @param disease (string) - Disease ID for cooldown tracking
    @param stage (number) - Stage/severity for cooldown tracking
    @param dialogueType (string, optional) - Type from EHR.Dialogue.Types
    @return boolean - True if said
]]--
function EHR.Dialogue.SayDiseaseMessage(player, text, disease, stage, dialogueType)
    if not player or not player.Say then return false end
    if EHR.Dialogue.IsDisabled() then return false end
    if not text or text == "" then return false end

    -- Check cooldown
    if EHR.Dialogue.IsOnCooldown(player, disease, stage) then
        return false
    end

    -- Say the message
    local said = EHR.Dialogue.Say(player, text, dialogueType or EHR.Dialogue.Types.STAGE_CHANGE)

    if said then
        -- Record cooldown
        EHR.Dialogue.RecordCooldown(player, disease, stage)
    end

    return said
end

--[[
    Say a random disease message with cooldown.
    Combines random chance with once-per-day cooldown.

    @param player (IsoPlayer) - The player
    @param text (string) - The text to say
    @param disease (string) - Disease ID for cooldown tracking
    @param stage (number) - Stage/severity for cooldown tracking
    @param oneInX (number) - Random chance (1 in X)
    @return boolean - True if said
]]--
function EHR.Dialogue.SayRandomDiseaseMessage(player, text, disease, stage, oneInX)
    if not player or not player.Say then return false end
    if EHR.Dialogue.IsDisabled() then return false end
    if not text or text == "" then return false end

    -- Check cooldown first (saves the random roll if on cooldown)
    if EHR.Dialogue.IsOnCooldown(player, disease, stage) then
        return false
    end

    -- Random chance check
    local said = EHR.Dialogue.SayRandom(player, text, oneInX)

    if said then
        -- Record cooldown
        EHR.Dialogue.RecordCooldown(player, disease, stage)
    end

    return said
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log("Dialogue module loaded (frequency control + skill-based dialogue)")
