--[[
    Extensive Health Rework B42
    Skill XP Module

    Awards First Aid (Doctor) XP for performing medical actions.
    Encourages learning through practice - treating diseases,
    taking medications, and self-examination all contribute to skill growth.

    XP amounts are configurable and scale based on action difficulty.

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.SkillXP = {}

-- ============================================
-- XP REWARD CONFIGURATION
-- ============================================

-- Base XP amounts for different medical actions
-- These can be adjusted for balance
EHR.SkillXP.Rewards = {
    -- Self-examination (small rewards for awareness)
    examination_self = 1,           -- Basic self-check
    examination_identify_disease = 3, -- Successfully identify a disease
    examination_detailed = 5,        -- Expert-level detailed examination

    -- Medication use
    medication_take_any = 5,         -- Successful medication use, regardless of tier
    medication_take_basic = 1,       -- Legacy tiered medication XP
    medication_take_otc = 2,         -- Take over-the-counter medication
    medication_take_rx = 4,          -- Take prescription medication
    medication_take_clinical = 6,    -- Take clinical-grade medication (IV, injections)

    -- Treatment progress
    treatment_dose_correct = 3,      -- Take correct medication for disease
    treatment_dose_wrong = 0,        -- Wrong medication (no XP - learn from mistakes)
    treatment_complete = 15,         -- Successfully complete a treatment course

    -- Disease management
    disease_cure = 20,               -- Cure a disease
    disease_manage_symptoms = 2,     -- Successfully manage symptoms

    -- Blood/Saline administration
    blood_transfusion = 10,          -- Administer blood transfusion
    saline_iv = 5,                   -- Administer saline IV

    -- Wound care (if integrated)
    wound_bandage = 2,               -- Apply bandage
    wound_disinfect = 3,             -- Disinfect wound
    wound_stitch = 5,                -- Stitch a wound

    -- Sepsis treatment
    sepsis_treatment_dose = 8,       -- Take sepsis treatment
    sepsis_cure = 25,                -- Survive/cure sepsis

    -- Diagnosis accuracy bonuses
    diagnosis_correct = 5,           -- Correct diagnosis made
    diagnosis_wrong = 0,             -- Wrong diagnosis (no XP)
}

-- Cooldowns to prevent XP farming (in game hours)
EHR.SkillXP.Cooldowns = {
    examination_self = 1,            -- Can gain XP once per hour from self-exam
    medication_take = 0.5,           -- Per medication type
    treatment_dose = 0,              -- No cooldown - each dose counts
}

-- ============================================
-- PLAYER DATA TRACKING
-- ============================================

local XP_DATA_KEY = "EHR_SkillXP_Data"

--[[
    Get or initialize XP tracking data for a player.
    @param player (IsoPlayer)
    @return table
]]--
function EHR.SkillXP.GetData(player)
    if not player then return nil end

    local modData = player:getModData()
    if not modData then return nil end

    if not modData[XP_DATA_KEY] then
        modData[XP_DATA_KEY] = {
            totalXPAwarded = 0,
            lastActions = {},  -- Track cooldowns {actionKey = lastTimeHours}
            actionCounts = {}, -- Track total counts {actionType = count}
        }
    end

    return modData[XP_DATA_KEY]
end

-- ============================================
-- XP AWARDING
-- ============================================

--[[
    Award First Aid XP to a player.

    @param player (IsoPlayer)
    @param amount (number) - Base XP amount
    @param actionType (string) - Type of action for tracking
    @param cooldownKey (string, optional) - Unique key for cooldown tracking
    @return boolean - True if XP was awarded
]]--
function EHR.SkillXP.AwardXP(player, amount, actionType, cooldownKey)
    if not player or not amount or amount <= 0 then
        return false
    end

    -- Check if XP system is enabled in sandbox options
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        if SandboxVars.ExtensiveHealthRework.FirstAidXPEnabled == false then
            return false  -- XP system disabled
        end
    end

    -- Get tracking data
    local data = EHR.SkillXP.GetData(player)
    if not data then return false end

    -- Check cooldown if specified
    if cooldownKey then
        local cooldownHours = EHR.SkillXP.Cooldowns[actionType] or 0
        if cooldownHours > 0 then
            local currentHours = getGameTime():getWorldAgeHours()
            local lastTime = data.lastActions[cooldownKey] or 0

            if currentHours - lastTime < cooldownHours then
                if EHR.DEBUG then
                    EHR.Log(string.format("SkillXP: Action '%s' on cooldown (%.1fh remaining)",
                        cooldownKey, cooldownHours - (currentHours - lastTime)))
                end
                return false
            end

            -- Update last action time
            data.lastActions[cooldownKey] = currentHours
        end
    end

    -- Apply XP multiplier from sandbox options
    local multiplier = 1.0
    if SandboxVars and SandboxVars.ExtensiveHealthRework and SandboxVars.ExtensiveHealthRework.FirstAidXPMultiplier then
        multiplier = SandboxVars.ExtensiveHealthRework.FirstAidXPMultiplier
    end

    local finalXP = math.floor(amount * multiplier)
    if finalXP <= 0 then return false end

    -- Award XP to Doctor (First Aid) perk.
    -- EHR already applies its own sandbox multiplier above; bypass the vanilla
    -- trait/occupation multiplier so configured rewards are the XP actually seen.
    local xpObj = player:getXp()
    if xpObj and Perks and Perks.Doctor then
        xpObj:AddXP(Perks.Doctor, finalXP, false, false, false, false)

        -- Track statistics
        data.totalXPAwarded = (data.totalXPAwarded or 0) + finalXP
        data.actionCounts[actionType] = (data.actionCounts[actionType] or 0) + 1

        if EHR.DEBUG then
            EHR.Log(string.format("SkillXP: Awarded %d XP for '%s' (multiplier: %.1fx, total: %d)",
                finalXP, actionType, multiplier, data.totalXPAwarded))
        end

        return true
    end

    return false
end

--[[
    Award XP based on action type with automatic amount lookup.

    @param player (IsoPlayer)
    @param actionType (string) - Key from EHR.SkillXP.Rewards
    @param cooldownKey (string, optional) - For cooldown tracking
    @return boolean
]]--
function EHR.SkillXP.AwardForAction(player, actionType, cooldownKey)
    local amount = EHR.SkillXP.Rewards[actionType]
    if not amount or amount <= 0 then
        return false
    end

    return EHR.SkillXP.AwardXP(player, amount, actionType, cooldownKey)
end

-- ============================================
-- CONVENIENCE FUNCTIONS
-- ============================================

--[[
    Award XP for taking medication.
    @param player (IsoPlayer)
    @param medData (table) - Medication data with tier info
]]--
function EHR.SkillXP.OnMedicationTaken(player, medData)
    if not player or not medData then return end

    -- Medication XP is awarded only after EHR.Medication.UseMedication successfully
    -- consumes a dose, so blocked actions cannot farm First Aid.
    EHR.SkillXP.AwardForAction(player, "medication_take_any")
end

--[[
    Award XP for disease treatment progress.
    @param player (IsoPlayer)
    @param diseaseId (string)
    @param wasCorrectMed (boolean)
]]--
function EHR.SkillXP.OnTreatmentDose(player, diseaseId, wasCorrectMed)
    if not player then return end

    if wasCorrectMed then
        EHR.SkillXP.AwardForAction(player, "treatment_dose_correct")
    end
    -- No XP for wrong medication - player learns through failure
end

--[[
    Award XP when a disease is cured.
    @param player (IsoPlayer)
    @param diseaseId (string)
]]--
function EHR.SkillXP.OnDiseaseCured(player, diseaseId)
    if not player then return end

    EHR.SkillXP.AwardForAction(player, "disease_cure")

    -- Bonus for sepsis cure
    if diseaseId == "Sepsis" then
        EHR.SkillXP.AwardForAction(player, "sepsis_cure")
    end
end

--[[
    Award XP for self-examination.
    @param player (IsoPlayer)
    @param skillTier (number) - Player's medical skill tier
    @param foundIssues (boolean) - Whether examination found health issues
]]--
function EHR.SkillXP.OnSelfExamination(player, skillTier, foundIssues)
    if not player then return end

    local actionType = "examination_self"

    if foundIssues then
        if skillTier >= 3 then
            actionType = "examination_detailed"
        elseif skillTier >= 1 then
            actionType = "examination_identify_disease"
        end
    end

    EHR.SkillXP.AwardForAction(player, actionType, "self_exam")
end

--[[
    Award XP for blood/saline administration.
    @param player (IsoPlayer)
    @param isBlood (boolean) - True for blood, false for saline
]]--
function EHR.SkillXP.OnTransfusion(player, isBlood)
    if not player then return end

    if isBlood then
        EHR.SkillXP.AwardForAction(player, "blood_transfusion")
    else
        EHR.SkillXP.AwardForAction(player, "saline_iv")
    end
end

--[[
    Award XP for correct diagnosis.
    @param player (IsoPlayer)
    @param wasCorrect (boolean)
]]--
function EHR.SkillXP.OnDiagnosis(player, wasCorrect)
    if not player then return end

    if wasCorrect then
        EHR.SkillXP.AwardForAction(player, "diagnosis_correct")
    end
end

--[[
    Award XP for sepsis treatment.
    @param player (IsoPlayer)
]]--
function EHR.SkillXP.OnSepsisTreatment(player)
    if not player then return end

    EHR.SkillXP.AwardForAction(player, "sepsis_treatment_dose")
end

-- ============================================
-- STATISTICS
-- ============================================

--[[
    Get XP statistics for a player.
    @param player (IsoPlayer)
    @return table
]]--
function EHR.SkillXP.GetStatistics(player)
    local data = EHR.SkillXP.GetData(player)
    if not data then
        return {totalXPAwarded = 0, actionCounts = {}}
    end

    return {
        totalXPAwarded = data.totalXPAwarded or 0,
        actionCounts = data.actionCounts or {},
    }
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log("SkillXP module loaded (First Aid XP rewards)")
