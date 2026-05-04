--[[
    Extensive Health Rework B42
    Medical Skill System Module

    Calculates effective medical skill based on First Aid perk level,
    traits, and occupations. Used for skill-based dialogue and diagnosis accuracy.

    Skill Tiers (0-10):
        0 = Clueless - "Something feels wrong..."
        1-3 = Novice - "I think I might be sick..."
        4-6 = Intermediate - "These symptoms suggest..."
        7-9 = Expert - "Classic presentation of..."
        10 = Master - Full medical terminology

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.MedicalSkill = {}

-- ============================================
-- CONSTANTS
-- ============================================

-- Skill tier definitions
EHR.MedicalSkill.Tiers = {
    CLUELESS = 0,
    NOVICE_LOW = 1,
    NOVICE_MID = 2,
    NOVICE_HIGH = 3,
    INTERMEDIATE_LOW = 4,
    INTERMEDIATE_MID = 5,
    INTERMEDIATE_HIGH = 6,
    EXPERT_LOW = 7,
    EXPERT_MID = 8,
    EXPERT_HIGH = 9,
    MASTER = 10,
}

-- Map skill levels to tier group names for dialogue selection
EHR.MedicalSkill.TierGroups = {
    [0] = "clueless",
    [1] = "novice",
    [2] = "novice",
    [3] = "novice",
    [4] = "intermediate",
    [5] = "intermediate",
    [6] = "intermediate",
    [7] = "expert",
    [8] = "expert",
    [9] = "expert",
    [10] = "master",
}

-- Tier group display names
EHR.MedicalSkill.TierGroupNames = {
    clueless = "Clueless",
    novice = "Novice",
    intermediate = "Intermediate",
    expert = "Expert",
    master = "Master",
}

-- Trait bonuses to medical skill
EHR.MedicalSkill.TraitBonuses = {
    -- Medical occupation traits (grant flat bonuses)
    ["Doctor"] = 3,
    ["Nurse"] = 2,
    ["FirstAider"] = 1,
    -- Negative traits (handled separately in accuracy calculation)
    ["Hypochondriac"] = 0,  -- Affects accuracy, not skill level
    ["Oblivious"] = 0,      -- Affects accuracy, not skill level
}

-- Condition type specializations (occupation bonuses for specific conditions)
EHR.MedicalSkill.Specializations = {
    -- Environmental conditions
    environmental = {
        ["ParkRanger"] = 1,    -- Better at recognizing hypothermia, heat stroke
        ["Lumberjack"] = 1,    -- Outdoor experience
    },
    -- Physical injuries
    injury = {
        ["ConstructionWorker"] = 1,  -- Familiar with workplace injuries
        ["Metalworker"] = 1,         -- Burn experience
        ["Mechanic"] = 1,            -- Cut/laceration experience
    },
    -- Food-related illness
    food = {
        ["Chef"] = 1,          -- Knows food safety
        ["BurgerFlipper"] = 1, -- Food handling experience
    },
    -- General disease (no specialization bonuses)
    disease = {},
}

-- Misdiagnosis mapping: actual disease -> possible wrong diagnoses
EHR.MedicalSkill.MisdiagnosisMap = {
    -- Bacterial/Infection
    ["Sepsis"] = {"FoodPoisoning", "Flu", "WoundInfection", "Exhaustion"},
    ["WoundInfection"] = {"Bruise", "Sprain", "MinorCut"},
    ["Tetanus"] = {"Flu", "MuscleCramp", "Exhaustion"},

    -- Foodborne
    ["FoodPoisoning"] = {"Flu", "Gastroenteritis", "Nausea", "Anxiety"},
    ["Salmonella"] = {"FoodPoisoning", "Flu", "StomachBug"},
    ["Gastroenteritis"] = {"FoodPoisoning", "Flu", "Anxiety"},

    -- Environmental
    ["Hypothermia"] = {"Flu", "Exhaustion", "Shock", "Cold"},
    ["HeatStroke"] = {"Fever", "Dehydration", "FoodPoisoning", "Exhaustion"},
    ["Frostbite"] = {"Bruise", "Numbness", "Sprain"},

    -- Respiratory
    ["Flu"] = {"Cold", "Exhaustion", "Allergies"},
    ["Cold"] = {"Allergies", "Exhaustion", "MinorFlu"},
    ["TuberculosisCavitary"] = {"Flu", "Cold", "Bronchitis", "Allergies"},
    ["TuberculosisMilliary"] = {"Flu", "Exhaustion", "FoodPoisoning"},

    -- Corpse-related
    ["CorpseDisease"] = {"FoodPoisoning", "Flu", "Nausea"},

    -- Other
    ["Rabies"] = {"Flu", "Anxiety", "Exhaustion", "Infection"},

    -- Fallback
    ["Unknown"] = {"Illness", "Fatigue", "Stress"},
}

-- ============================================
-- SKILL CALCULATION
-- ============================================

--[[
    Calculate the effective medical skill for a player.
    Takes into account First Aid perk level, traits, and condition specialization.

    @param player (IsoPlayer) - The player to check
    @param conditionType (string, optional) - Type of condition for specialization bonus
                                              ("environmental", "injury", "food", "disease")
    @return number - Effective skill level (0-10)
]]--
function EHR.MedicalSkill.GetEffectiveSkill(player, conditionType)
    if not player then return 0 end

    -- Base skill from First Aid perk (Doctor perk in PZ)
    local baseSkill = 0
    if player.getPerkLevel then
        local success, level = pcall(function()
            return player:getPerkLevel(Perks.Doctor)
        end)
        if success and level then
            baseSkill = level
        end
    end

    local bonus = 0

    -- Trait bonuses
    if player.HasTrait then
        for trait, traitBonus in pairs(EHR.MedicalSkill.TraitBonuses) do
            local hasTraitSuccess, hasTrait = pcall(function()
                return player:HasTrait(trait)
            end)
            if hasTraitSuccess and hasTrait and traitBonus > 0 then
                bonus = bonus + traitBonus
            end
        end
    end

    -- Condition specialization bonuses
    if conditionType and EHR.MedicalSkill.Specializations[conditionType] then
        local specializations = EHR.MedicalSkill.Specializations[conditionType]
        if player.HasTrait then
            for trait, specBonus in pairs(specializations) do
                local hasTraitSuccess, hasTrait = pcall(function()
                    return player:HasTrait(trait)
                end)
                if hasTraitSuccess and hasTrait then
                    bonus = bonus + specBonus
                end
            end
        end
    end

    -- Cap at 10
    return math.min(10, baseSkill + bonus)
end

--[[
    Get the tier group name for a skill level.
    Used for dialogue selection.

    @param skillLevel (number) - Skill level 0-10
    @return string - Tier group name ("clueless", "novice", etc.)
]]--
function EHR.MedicalSkill.GetTierGroup(skillLevel)
    skillLevel = math.max(0, math.min(10, skillLevel or 0))
    return EHR.MedicalSkill.TierGroups[skillLevel] or "clueless"
end

--[[
    Get display name for a tier group.

    @param tierGroup (string) - Tier group name
    @return string - Display name ("Clueless", "Novice", etc.)
]]--
function EHR.MedicalSkill.GetTierGroupDisplayName(tierGroup)
    return EHR.MedicalSkill.TierGroupNames[tierGroup] or "Unknown"
end

-- ============================================
-- DIAGNOSIS ACCURACY
-- ============================================

--[[
    Calculate diagnosis accuracy for a player.
    Higher skill = more accurate diagnoses.
    Certain traits modify accuracy (Hypochondriac, Oblivious).

    @param player (IsoPlayer) - The player
    @param effectiveSkill (number, optional) - Pre-calculated effective skill
    @return number - Accuracy as decimal (0.0 to 1.0)
]]--
function EHR.MedicalSkill.GetDiagnosisAccuracy(player, effectiveSkill)
    if not player then return 0.4 end

    effectiveSkill = effectiveSkill or EHR.MedicalSkill.GetEffectiveSkill(player, "disease")

    -- Base accuracy: 40% at skill 0, +6% per level, 100% at skill 10
    local accuracy = 0.40 + (effectiveSkill * 0.06)

    -- Trait modifiers
    if player.HasTrait then
        -- Hypochondriac: More likely to think something is wrong when it isn't
        -- Manifests as 30% more wrong diagnoses
        local hasHypo, isHypo = pcall(function()
            return player:HasTrait("Hypochondriac")
        end)
        if hasHypo and isHypo then
            accuracy = accuracy * 0.7
        end

        -- Oblivious: Misses subtle symptoms
        -- 50% chance to miss early-stage symptoms entirely
        local hasObl, isObl = pcall(function()
            return player:HasTrait("Oblivious")
        end)
        if hasObl and isObl then
            accuracy = accuracy * 0.5
        end
    end

    return math.min(1.0, math.max(0.0, accuracy))
end

--[[
    Roll for diagnosis accuracy.
    Returns whether the player correctly identifies the condition.

    @param player (IsoPlayer) - The player
    @param actualDisease (string) - The actual disease ID
    @param stage (number) - Current stage of the disease
    @return diagnosedAs (string), isCorrect (boolean)
]]--
function EHR.MedicalSkill.RollDiagnosis(player, actualDisease, stage)
    local effectiveSkill = EHR.MedicalSkill.GetEffectiveSkill(player, "disease")
    local accuracy = EHR.MedicalSkill.GetDiagnosisAccuracy(player, effectiveSkill)

    -- Early stages are harder to diagnose correctly
    -- Stage 1: -20% accuracy, Stage 2: -10%, Stage 3+: no penalty
    local stagePenalty = 0
    if stage == 1 then
        stagePenalty = 0.20
    elseif stage == 2 then
        stagePenalty = 0.10
    end

    local finalAccuracy = math.max(0.1, accuracy - stagePenalty)

    -- Roll for correct diagnosis
    if ZombRand(100) < (finalAccuracy * 100) then
        return actualDisease, true  -- Correct diagnosis
    else
        -- Wrong diagnosis - return a plausible misdiagnosis
        local misdiagnosis = EHR.MedicalSkill.GetMisdiagnosis(actualDisease, stage)
        return misdiagnosis, false
    end
end

--[[
    Get a plausible wrong diagnosis for a condition.
    Used when diagnosis roll fails.

    @param actualDisease (string) - The actual disease ID
    @param stage (number) - Current stage (affects misdiagnosis selection)
    @return string - Misdiagnosed condition ID
]]--
function EHR.MedicalSkill.GetMisdiagnosis(actualDisease, stage)
    local options = EHR.MedicalSkill.MisdiagnosisMap[actualDisease]

    if not options or #options == 0 then
        -- Fallback to generic misdiagnosis
        options = EHR.MedicalSkill.MisdiagnosisMap["Unknown"] or {"Illness"}
    end

    -- Pick a random misdiagnosis from the list
    local index = ZombRand(#options) + 1
    return options[index]
end

-- ============================================
-- MP EXAMINATION SUPPORT
-- ============================================

--[[
    Calculate combined skill when one player examines another.
    Uses the higher skill of the two, with a small bonus from the lower.

    @param examiner (IsoPlayer) - The player performing examination
    @param patient (IsoPlayer) - The player being examined
    @return number - Combined effective skill (0-10)
]]--
function EHR.MedicalSkill.GetCombinedSkill(examiner, patient)
    local examinerSkill = EHR.MedicalSkill.GetEffectiveSkill(examiner, "disease")
    local patientSkill = EHR.MedicalSkill.GetEffectiveSkill(patient, "disease")

    local higher = math.max(examinerSkill, patientSkill)
    local lower = math.min(examinerSkill, patientSkill)

    -- Bonus: +1 for every 3 levels of the lower skill (max +3)
    local bonus = math.floor(lower / 3)

    return math.min(10, higher + bonus)
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

--[[
    Check if player has any medical trait (Doctor, Nurse, FirstAider).
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.MedicalSkill.HasMedicalBackground(player)
    if not player or not player.HasTrait then return false end

    local medicalTraits = {"Doctor", "Nurse", "FirstAider"}
    for _, trait in ipairs(medicalTraits) do
        local success, hasTrait = pcall(function()
            return player:HasTrait(trait)
        end)
        if success and hasTrait then
            return true
        end
    end

    return false
end

--[[
    Check if player has negative perception traits.
    @param player (IsoPlayer)
    @return hasHypochondriac (boolean), hasOblivious (boolean)
]]--
function EHR.MedicalSkill.GetNegativeTraits(player)
    if not player or not player.HasTrait then return false, false end

    local hasHypo = false
    local hasObl = false

    local success1, result1 = pcall(function()
        return player:HasTrait("Hypochondriac")
    end)
    if success1 then hasHypo = result1 end

    local success2, result2 = pcall(function()
        return player:HasTrait("Oblivious")
    end)
    if success2 then hasObl = result2 end

    return hasHypo, hasObl
end

--[[
    Get a summary of player's medical capabilities for debug/UI.
    @param player (IsoPlayer)
    @return table - Summary with skill, tier, accuracy, traits
]]--
function EHR.MedicalSkill.GetSkillSummary(player)
    if not player then
        return {
            baseSkill = 0,
            effectiveSkill = 0,
            tierGroup = "clueless",
            tierGroupName = "Clueless",
            accuracy = 0.4,
            hasMedicalBackground = false,
            isHypochondriac = false,
            isOblivious = false,
        }
    end

    local baseSkill = 0
    if player.getPerkLevel then
        local success, level = pcall(function()
            return player:getPerkLevel(Perks.Doctor)
        end)
        if success and level then
            baseSkill = level
        end
    end

    local effectiveSkill = EHR.MedicalSkill.GetEffectiveSkill(player, "disease")
    local tierGroup = EHR.MedicalSkill.GetTierGroup(effectiveSkill)
    local accuracy = EHR.MedicalSkill.GetDiagnosisAccuracy(player, effectiveSkill)
    local hasHypo, hasObl = EHR.MedicalSkill.GetNegativeTraits(player)

    return {
        baseSkill = baseSkill,
        effectiveSkill = effectiveSkill,
        tierGroup = tierGroup,
        tierGroupName = EHR.MedicalSkill.GetTierGroupDisplayName(tierGroup),
        accuracy = accuracy,
        accuracyPercent = math.floor(accuracy * 100),
        hasMedicalBackground = EHR.MedicalSkill.HasMedicalBackground(player),
        isHypochondriac = hasHypo,
        isOblivious = hasObl,
    }
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log("MedicalSkill module loaded (skill-based diagnosis)")
