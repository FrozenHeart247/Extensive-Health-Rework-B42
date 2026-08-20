pcall(function() require "ExtensiveHealth/EHR_Localization" end)
--[[
    Extensive Health Rework - Medication System

    4-Tier Medication System:
    - Tier 0: Vanilla items (minimal relief, 10-20% symptom reduction)
    - Tier 1: OTC (Over-the-counter) - 30-50% symptom relief only
    - Tier 2: Prescription - Cures disease at normal rate
    - Tier 3: Clinical Grade - 2x cure speed + side effects

    Author: Frozen_Heart
    Version: 1.0
]]

if not EHR then EHR = {} end
EHR.Medication = EHR.Medication or {}

-- ============================================
-- TRANSLATION HELPER
-- ============================================

--[[
    Get translated medication display name
    Tries to find translation key, falls back to displayName

    @param medId - Medication ID (e.g., "ExtensiveHealth.ColdFluTablets")
    @param medData - Optional medication data table (if already fetched)
    @return Translated display name or fallback
]]--
function EHR.Medication.GetDisplayName(medId, medData)
    -- Get medication data if not provided
    if not medData then
        medData = EHR.Medication.Database[medId]
    end
    if not medData then return medId end

    -- Check if getText is available (client-side only)
    if getText then
        -- Try explicit nameKey first
        if medData.nameKey then
            local translated = getText(medData.nameKey)
            if translated and translated ~= medData.nameKey then
                return translated
            end
        end

        -- Try auto-generated key based on displayName
        -- Convert "Cold & Flu Tablets" -> "UI_EHR_Med_ColdFluTablets"
        if medData.displayName then
            local keyName = medData.displayName:gsub("[%s%-%&%(%)]", ""):gsub("%.", "")
            local autoKey = "UI_EHR_Med_" .. keyName
            local translated = getText(autoKey)
            if translated and translated ~= autoKey then
                return translated
            end
        end
    end

    -- Fallback to displayName
    return medData.displayName or medId
end

--[[
    Get translated side effect display name
    @param effectId - Side effect ID (e.g., "nausea")
    @param effectData - Optional effect data table
    @return Translated display name or fallback
]]--
function EHR.Medication.GetSideEffectDisplayName(effectId, effectData)
    if not effectData then
        effectData = EHR.Medication.SideEffects and EHR.Medication.SideEffects[effectId]
    end
    if not effectData then return effectId end

    -- Check if getText is available (client-side only)
    if getText then
        -- Try the side effect translation key (already defined in UI_EN.txt)
        local key = "UI_SideEffect_" .. effectId:gsub("^%l", string.upper):gsub("_(%l)", function(c) return c:upper() end)
        local translated = getText(key)
        if translated and translated ~= key then
            return translated
        end
    end

    -- Fallback to displayName
    return effectData.displayName or effectId
end

-- ============================================
-- MEDICATION TIER DEFINITIONS
-- ============================================

EHR.Medication.Tiers = {
    VANILLA = 0,      -- Existing PZ items
    OTC = 1,          -- Over-the-counter
    PRESCRIPTION = 2, -- Prescription required
    CLINICAL = 3      -- Hospital/Military only
}

EHR.Medication.TierEffectiveness = {
    [0] = { symptomRelief = 0.15, cureRate = 0.0,  canCure = false }, -- Vanilla: 15% symptom relief, no cure
    [1] = { symptomRelief = 0.40, cureRate = 0.0,  canCure = false }, -- OTC: 40% symptom relief, no cure
    [2] = { symptomRelief = 0.60, cureRate = 1.0,  canCure = true  }, -- Prescription: 60% relief, normal cure
    [3] = { symptomRelief = 0.80, cureRate = 2.0,  canCure = true  }, -- Clinical: 80% relief, 2x cure speed
}

-- ============================================
-- MEDICATION DATABASE
-- All medications mapped to diseases they treat
-- ============================================

EHR.Medication.Database = {
    -- =========================================
    -- TIER 0 - VANILLA ITEMS
    -- =========================================

    -- Base.Antibiotics (vanilla)
    ["Base.Antibiotics"] = {
        tier = 0,
        treats = {"wound_infection", "sepsis", "cellulitis"},
        displayName = "Antibiotics",
        usageMessage = "You take the antibiotics. They provide minor relief.",
    },

    -- Base.Pills (vanilla painkillers)
    ["Base.Pills"] = {
        tier = 0,
        treats = {},
        displayName = "Painkillers",
        icon = "Painkillers",
        useVanillaActionOnly = true,
        skipDrugInteractions = true,
        effectDurationHours = 3,
        analgesic = {
            rampHours = 0.5,
        },
        usageMessage = "You take painkillers. The pain begins to fade.",
    },

    -- Base.PillsVitamins (B42 caffeine pills)
    ["Base.PillsVitamins"] = {
        tier = 1,
        treats = {},
        displayName = "Caffeine Pills",
        icon = "PillsCaffeine",
        usageMessage = "You take caffeine pills. Exhaustion vanishes, but this will crash hard later.",
        appliesWithoutDisease = true,
        effectDurationHours = 12,
        blockWhileDoseActive = true,
        activeDoseMessage = "The caffeine is still active. More would be a very bad idea.",
        fatigueBlock = {
            durationHours = 12,
            crashSideEffect = "caffeine_crash",
        },
        sideEffects = {"caffeine_crash"},
    },

    -- Base.PillsSleepingTablets (vanilla sleeping pills)
    ["Base.PillsSleepingTablets"] = {
        tier = 0,
        treats = {"insomnia"},
        displayName = "Sleeping Pills",
        icon = "PillsSleeping",
        useVanillaActionOnly = true,
        skipDrugInteractions = true,
        appliesWithoutDisease = true,
        effectDurationHours = 8,
        canCure = false,
        sleepAid = {
            durationHours = 8,
        },
        usageMessage = "You take sleeping pills. Drowsiness settles in.",
    },

    -- Base.PillsAntiDep (vanilla antidepressants)
    ["Base.PillsAntiDep"] = {
        tier = 2,
        treats = {"insomnia"},
        displayName = "Antidepressants",
        icon = "PillsAntidepressant",
        useVanillaActionOnly = true,
        skipDrugInteractions = true,
        appliesWithoutDisease = true,
        effectDurationHours = 12,
        cureTimeHours = 168,
        treatmentTimeText = "168 hours (14-dose course)",
        blockWhileDoseActive = true,
        activeDoseMessage = "The antidepressant dose is still active.",
        sleepAid = {
            durationHours = 12,
        },
        symptomReduction = {
            stress = 0.35,
            fatigue = 0.20,
        },
        usageMessage = "You take antidepressants. The edge softens a little.",
    },

    -- Base.PillsBeta
    ["Base.PillsBeta"] = {
        tier = 0,
        treats = {"hypothermia"},
        displayName = "Beta Blockers",
        icon = "PillsBetablocker",
        effectDurationHours = 2,
        betaBlocker = true,
        monitorSideEffects = {
            {
                effectId = "beta_blocker_sleep_disruption",
                displayName = "Sleep disruption (cannot sleep)",
                severity = 1,
            },
            {
                effectId = "beta_blocker_blood_loss_risk",
                displayName = "Reduced blood-loss tolerance",
                severity = 2,
            },
        },
        usageMessage = "You take beta blockers. Your heart rate stabilizes.",
    },

    -- =========================================
    -- TIER 1 - OTC (OVER THE COUNTER)
    -- Common - Pharmacies, Bathrooms, Stores
    -- =========================================

    ["ExtensiveHealth.ColdFluTablets"] = {
        tier = 1,
        treats = {"common_cold"},
        displayName = "Cold & Flu Tablets",
        usageMessage = "You take the cold & flu tablets. The cold should start clearing up.",
        canCure = true,
        cureTimeHours = 28,
        treatmentTimeText = "28 hours (8-dose course)",
        blockWhileDoseActive = true,
        activeDoseMessage = "The current cold medicine dose is still active.",
        symptomReduction = {
            fever = 0.35,
            fatigue = 0.30,
            pain = 0.25,
        },
    },

    ["ExtensiveHealth.CommonColdTea"] = {
        tier = 1,
        treats = {"common_cold"},
        displayName = "Herbal Tea",
        icon = "CommonColdTea",
        adminType = "liquid",
        useVanillaActionOnly = true,
        consumeViaFoodHook = true,
        remoteAdministration = false,
        usageMessage = "You drink the herbal tea. Warmth settles in your chest.",
        canCure = true,
        cureTimeHours = 28,
        treatmentTimeText = "28 hours (8-dose course)",
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The herbal tea dose is still active.",
        appliesWithoutDisease = true,
        hydrationSupport = {
            durationHours = 0.35,
            immediateBoost = 0.04,
            hydrationBoost = 0.08,
            restorePerHour = 0.25,
        },
        symptomReduction = {
            fever = 0.25,
            fatigue = 0.20,
            pain = 0.15,
        },
    },

    ["ExtensiveHealth.AntipyreticTablets"] = {
        tier = 1,
        treats = {
            "common_cold",
            "influenza",
            "pneumonia",
            "trichinosis",
            "cadaveric_aspergillosis",
            "wound_infection",
            "cellulitis",
            "tetanus",
            "sepsis",
            "tuberculosis",
            "ahtr",
            "hyperkeratotic_scabies",
        },
        displayName = "Antipyretic Tablets",
        usageMessage = "You take antipyretic tablets. The fever begins to ease.",
        effectDurationHours = 4,
        symptomReduction = {
            fever = 0.60,
        },
    },

    ["ExtensiveHealth.AntipyreticTea"] = {
        tier = 1,
        treats = {
            "common_cold",
            "influenza",
            "pneumonia",
            "trichinosis",
            "cadaveric_aspergillosis",
            "wound_infection",
            "cellulitis",
            "tetanus",
            "sepsis",
            "tuberculosis",
            "ahtr",
            "hyperkeratotic_scabies",
        },
        displayName = "Antipyretic Tea",
        icon = "AntipyreticTea",
        adminType = "liquid",
        useVanillaActionOnly = true,
        consumeViaFoodHook = true,
        remoteAdministration = false,
        usageMessage = "You drink the antipyretic tea. The fever begins to ease.",
        appliesWithoutDisease = true,
        effectDurationHours = 4,
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The antipyretic tea dose is still active. More now will be wasted.",
        hydrationSupport = {
            durationHours = 0.35,
            immediateBoost = 0.04,
            hydrationBoost = 0.08,
            restorePerHour = 0.25,
        },
        symptomReduction = {
            fever = 0.60,
        },
    },

    ["ExtensiveHealth.CoughSyrup"] = {
        tier = 1,
        treats = {"common_cold", "pneumonia", "cadaveric_aspergillosis"},
        displayName = "Cough Syrup",
        usageMessage = "You drink the cough syrup. The coughing subsides.",
        symptomReduction = {
            coughing = 0.50,
        },
    },

    ["ExtensiveHealth.HomemadeCoughSyrup"] = {
        tier = 1,
        treats = {"common_cold", "pneumonia", "cadaveric_aspergillosis"},
        displayName = "Homemade Cough Syrup",
        icon = "HomemadeCoughSyrup",
        usageMessage = "You drink the homemade cough syrup. The coughing subsides.",
        symptomReduction = {
            coughing = 0.50,
        },
    },

    ["ExtensiveHealth.ElectrolytePowder"] = {
        tier = 1,
        treats = {"dysentery", "food_poisoning", "gastroenteritis", "toxin_poisoning", "heat_stroke"},
        displayName = "Electrolyte Powder",
        adminType = "liquid",
        usageMessage = "You mix and drink the electrolyte solution. You feel more hydrated.",
        appliesWithoutDisease = true,
        effectDurationHours = 0.5,
        hydrationSupport = {
            durationHours = 0.5,
            immediateBoost = 0.10,
            hydrationBoost = 0.20,
            restorePerHour = 0.50,
        },
        symptomReduction = {
            dehydration = 0.40,
            weakness = 0.30,
        },
    },

    ["ExtensiveHealth.BronchodilatorInhaler"] = {
        tier = 1,
        treats = {"pneumonia", "corpse_sickness", "cadaveric_aspergillosis"},
        displayName = "Bronchodilator Inhaler",
        usageMessage = "You use the inhaler. Breathing becomes easier.",
        appliesWithoutDisease = true,
        effectDurationHours = 0.5,
        respiratorySupport = {
            durationHours = 0.5,
            immediateBoost = 0.10,
            enduranceBoost = 0.20,
            restorePerHour = 0.85,
        },
        symptomReduction = {
            breathingDifficulty = 0.45,
            weakness = 0.25,
        },
    },

    ["ExtensiveHealth.AntiNauseaTablets"] = {
        tier = 1,
        treats = {"food_poisoning", "gastroenteritis", "toxin_poisoning", "corpse_sickness", "dysentery", "ahtr"},
        displayName = "Anti-Nausea Tablets",
        usageMessage = "You take anti-nausea tablets. Your stomach settles.",
        appliesWithoutDisease = true,
        symptomReduction = {
            nausea = 0.50,
            vomiting = 0.40,
            dysenteryVomiting = 0.75,
            sickness = 0.30,
        },
    },

    ["ExtensiveHealth.AntiInflammatory"] = {
        tier = 1,
        treats = {"wound_infection", "cellulitis", "trichinosis", "tetanus", "ahtr"},
        displayName = "Anti-Inflammatory Pills",
        usageMessage = "You take anti-inflammatory pills. Swelling begins to reduce.",
        symptomReduction = {
            inflammation = 0.50,
            pain = 0.55,
            fever = 0.30,
        },
    },

    ["ExtensiveHealth.AntiDiarrheal"] = {
        tier = 1,
        treats = {"dysentery"},
        displayName = "Anti-Diarrheal Tablets",
        usageMessage = "You take anti-diarrheal tablets. The cramps and urgency ease.",
        symptomReduction = {
            diarrhea = 0.85,
            dysenteryCaps = 1.00,
            bathroomNeed = 0.85,
        },
    },

    ["ExtensiveHealth.MuscleRelaxants"] = {
        tier = 1,
        treats = {"tetanus", "trichinosis"},
        displayName = "Muscle Relaxants",
        usageMessage = "You take muscle relaxants. The cramping eases.",
        appliesWithoutDisease = true,
        symptomReduction = {
            muscleSpasms = 0.40,
            pain = 0.30,
        },
    },

    ["ExtensiveHealth.HomemadeMuscleRelaxant"] = {
        tier = 1,
        treats = {"tetanus", "trichinosis"},
        displayName = "Homemade Muscle Relaxant",
        icon = "HomemadeMuscleRelaxant",
        usageMessage = "You take the homemade muscle relaxant. The cramping eases.",
        appliesWithoutDisease = true,
        symptomReduction = {
            muscleSpasms = 0.40,
            pain = 0.30,
        },
    },

    ["ExtensiveHealth.HomemadePainkillers"] = {
        tier = 0,
        treats = {},
        displayName = "Homemade Painkillers",
        icon = "HomemadePainkillers",
        usageMessage = "You take homemade painkillers. The pain eases slightly.",
        appliesWithoutDisease = true,
        skipDrugInteractions = true,
        symptomReduction = {
            pain = 0.35,
        },
    },

    ["ExtensiveHealth.HomemadeSleepingPills"] = {
        tier = 0,
        treats = {"insomnia"},
        displayName = "Homemade Sleeping Pills",
        icon = "HomemadeSleepingPills",
        skipDrugInteractions = true,
        appliesWithoutDisease = true,
        effectDurationHours = 8,
        canCure = false,
        sleepAid = {
            durationHours = 8,
        },
        usageMessage = "You take homemade sleeping pills. Drowsiness settles in.",
    },

    ["ExtensiveHealth.RelaxantTea"] = {
        tier = 1,
        treats = {},
        displayName = "Relaxant Tea",
        icon = "RelaxantTea",
        adminType = "liquid",
        useVanillaActionOnly = true,
        consumeViaFoodHook = true,
        remoteAdministration = false,
        usageMessage = "You drink the relaxant tea. Your nerves begin to loosen.",
        appliesWithoutDisease = true,
        effectDurationHours = 3,
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The relaxant tea dose is still active. More now will be wasted.",
        stressSupport = {
            durationHours = 3,
            targetStress = 0.0,
            restorePerHour = 0.35,
        },
        symptomReduction = {
            stress = 0.35,
        },
    },

    ["ExtensiveHealth.NitricOxideBooster"] = {
        tier = 1,
        treats = {},
        displayName = "Nitric Oxide Boosters",
        icon = "NitricOxideBooster",
        usageMessage = "You take a nitric oxide booster. Your muscles feel flooded with energy.",
        appliesWithoutDisease = true,
        effectDurationHours = 3,
        blockWhileDoseActive = true,
        activeDoseMessage = "The nitric oxide booster is still active.",
        staminaLock = {
            durationHours = 3,
            targetEndurance = 1.0,
            delayedSideEffect = "whole_body_muscle_pain",
        },
        sideEffects = {"whole_body_muscle_pain"},
    },

    ["ExtensiveHealth.CombatStimulants"] = {
        tier = 3,
        treats = {},
        displayName = "Combat Stimulants",
        icon = "CombatStimulants",
        adminType = "pill",
        usageMessage = "You take combat stimulants. Everything sharpens, fast.",
        appliesWithoutDisease = true,
        effectDurationHours = 3,
        blockWhileDoseActive = true,
        activeDoseMessage = "The combat stimulants are still active. Another dose would be reckless.",
        combatStimulants = {
            durationHours = 3,
            attackSpeedMultiplier = 2.0,
            speedMod = 1.12,
            maxEndurance = 0.92,
            restorePerHour = 0.45,
            delayedSideEffect = "combat_stimulant_crash",
        },
    },

    ["ExtensiveHealth.CoughSuppressant"] = {
        tier = 1,
        treats = {"common_cold", "pneumonia", "cadaveric_aspergillosis", "tuberculosis"},
        displayName = "Cough Suppressant",
        usageMessage = "You take cough suppressant. The urge to cough fades.",
        symptomReduction = {
            coughing = 0.45,
        },
    },

    ["ExtensiveHealth.AntisepticCream"] = {
        tier = 2,
        treats = {"wound_infection"},
        displayName = "Antiseptic Cream",
        usageMessage = "You apply antiseptic cream to the wound.",
        isTopical = true,
        requiresActiveWound = true,
        preventionOnly = true,
        effectDurationHours = 8,
        symptomReduction = {
            infection = 1.00,
        },
    },

    ["ExtensiveHealth.HomemadeAntisepticCream"] = {
        tier = 2,
        treats = {"wound_infection"},
        displayName = "Homemade Antiseptic Cream",
        icon = "HomemadeAntisepticCream",
        usageMessage = "You apply homemade antiseptic cream to the wound.",
        isTopical = true,
        requiresActiveWound = true,
        preventionOnly = true,
        effectDurationHours = 8,
        symptomReduction = {
            infection = 1.00,
        },
    },

    -- =========================================
    -- TIER 2 - PRESCRIPTION MEDICATION
    -- Uncommon - Clinics, Pharmacies, Hospitals
    -- =========================================

    ["ExtensiveHealth.AntiviralCapsules"] = {
        tier = 2,
        treats = {"common_cold", "gastroenteritis"},
        displayName = "Antiviral Capsules",
        usageMessage = "You take antiviral capsules. Your body fights the infection.",
        cureTimeHours = 48, -- 2 days to cure
    },

    ["ExtensiveHealth.PrescriptionAntibiotics"] = {
        tier = 2,
        treats = {"wound_infection", "cellulitis", "pneumonia"},
        displayName = "Prescription Antibiotics",
        usageMessage = "You take prescription antibiotics. The infection should clear.",
        cureTimeHours = 72, -- 3 days to cure
    },

    ["ExtensiveHealth.AntifungalTablets"] = {
        tier = 2,
        treats = {"cadaveric_aspergillosis"},
        displayName = "Antifungal Tablets",
        usageMessage = "You take antifungal tablets. The fungal infection is being treated.",
        cureTimeHours = 120, -- 5 days to cure
        symptomReduction = {
            coughing = 0.40,
            breathingDifficulty = 0.35,
            weakness = 0.25,
            fever = 0.35,
            dehydration = 0.25,
        },
    },

    ["ExtensiveHealth.ActivatedCharcoal"] = {
        tier = 2,
        treats = {"food_poisoning", "toxin_poisoning"},
        displayName = "Activated Charcoal",
        usageMessage = "You swallow activated charcoal. It absorbs the toxins.",
        cureTimeHours = 6, -- Fallback cure time
        diseaseCureTimeHours = {
            food_poisoning = 6,
            toxin_poisoning = 12,
        },
    },

    ["ExtensiveHealth.HomeMadeActivatedCharcoal"] = {
        tier = 2,
        treats = {"food_poisoning", "toxin_poisoning"},
        displayName = "Homemade Activated Charcoal",
        usageMessage = "You swallow homemade activated charcoal. It absorbs the toxins.",
        cureTimeHours = 6,
        diseaseCureTimeHours = {
            food_poisoning = 6,
            toxin_poisoning = 12,
        },
    },

    ["ExtensiveHealth.AntiparasiticPills"] = {
        tier = 2,
        treats = {"trichinosis", "hyperkeratotic_scabies"},
        displayName = "Antiparasitic Pills",
        usageMessage = "You take antiparasitic medication. The parasites will die.",
        cureTimeHours = 168, -- 7 days to cure
        diseaseCureTimeHours = {
            trichinosis = 168,
            hyperkeratotic_scabies = 168,
        },
        symptomReduction = {
            pain = 0.30,
            fever = 0.25,
            healthDrain = 0.45,
        },
    },

    ["ExtensiveHealth.TopicalPermethrin"] = {
        tier = 2,
        treats = {"hyperkeratotic_scabies"},
        displayName = "Topical Permethrin",
        icon = "TopicalPermethrin",
        usageMessage = "You apply topical permethrin. The mites should start dying off.",
        isTopical = true,
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The current permethrin dose is still active. More now will be wasted.",
        cureTimeHours = 72,
        treatmentTimeText = "72 hours (6-dose course)",
        symptomReduction = {
            pain = 0.45,
            fever = 0.30,
            healthDrain = 0.65,
        },
    },

    ["ExtensiveHealth.HomemadeTopicalPermethrin"] = {
        tier = 2,
        treats = {"hyperkeratotic_scabies"},
        displayName = "Homemade Topical Permethrin",
        icon = "HomemadeTopicalPermethrin",
        usageMessage = "You apply homemade topical permethrin. The mites should start dying off.",
        isTopical = true,
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The current permethrin dose is still active. More now will be wasted.",
        cureTimeHours = 72,
        treatmentTimeText = "72 hours (6-dose course)",
        symptomReduction = {
            pain = 0.45,
            fever = 0.30,
            healthDrain = 0.65,
        },
    },

    ["ExtensiveHealth.OralRehydrationKit"] = {
        tier = 2,
        treats = {"dysentery"},
        displayName = "Oral Rehydration Kit",
        adminType = "liquid",
        usageMessage = "You prepare and drink the rehydration solution.",
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The current rehydration dose is still active. More now will be wasted.",
        cureTimeHours = 48, -- 2 days to cure
        treatmentTimeText = "48 hours (8-dose course)",
        hydrationSupport = {
            durationHours = 1.0,
            immediateBoost = 0.12,
            hydrationBoost = 0.25,
            restorePerHour = 0.65,
        },
        symptomReduction = {
            dehydration = 0.75,
            weakness = 0.25,
        },
    },

    ["ExtensiveHealth.InstantIcePack"] = {
        tier = 2,
        treats = {"heat_stroke"},
        displayName = "Instant Ice Pack",
        usageMessage = "You crack an instant ice pack and start cooling down.",
        adminType = "emergency",
        blockWhileDoseActive = true,
        activeDoseMessage = "The current ice pack is still cooling you down.",
        cureTimeHours = 4,
        treatmentTimeText = "4 hours (4-dose cooling course)",
        effectDurationHours = 1.1,
        symptomReduction = {
            fever = 0.95,
            dehydration = 0.98,
            dizziness = 0.98,
            confusion = 0.98,
            collapse = 0.98,
            healthDrain = 0.98,
            vomiting = 0.90,
            weakness = 0.80,
        },
    },

    ["ExtensiveHealth.WarmingPack"] = {
        tier = 1,
        treats = {},
        displayName = "Warming Pack",
        icon = "WarmingPackeges",
        nameKey = "UI_EHR_Med_WarmingPack",
        usageMessage = "You activate the warming pack and hold it close to your body.",
        adminType = "emergency",
        effectDurationHours = 2.0,
        doseIntervalHours = 2.0,
        totalDosesNeeded = 1,
        overdoseRisk = false,
        warmingSupport = {
            durationHours = 2.0,
            targetCoreTemp = 37.0,
            warmingRatePerHour = 3.2,
        },
    },

    ["ExtensiveHealth.Furosemide"] = {
        tier = 2,
        treats = {"ahtr"},
        displayName = "Furosemide",
        usageMessage = "You take furosemide. It should help your body clear the transfusion reaction.",
        alwaysApplySideEffects = true,
        cureTimeHours = 48,
        treatmentTimeText = "48 hours (6-dose course)",
        symptomReduction = {
            healthDrain = 0.45,
            fever = 0.25,
            pain = 0.25,
            nausea = 0.25,
            weakness = 0.25,
        },
        sideEffects = {"dehydration", "lower_back_pain", "diuretic_urination"},
    },

    ["ExtensiveHealth.Antipsychotics"] = {
        tier = 2,
        treats = {"delirium"},
        displayName = "Antipsychotics",
        icon = "Antipsychotics",
        usageMessage = "You take antipsychotics. The noise should start losing its grip.",
        cureTimeHours = 96,
        treatmentTimeText = "96 hours (8-dose course)",
    },

    ["ExtensiveHealth.DualOrexinReceptor"] = {
        tier = 2,
        treats = {"insomnia"},
        displayName = "Dual Orexin Receptor",
        icon = "DualOrexinReceptor",
        usageMessage = "You take the dual orexin receptor medication. Sleep feels reachable again.",
        appliesWithoutDisease = true,
        effectDurationHours = 12,
        cureTimeHours = 96,
        treatmentTimeText = "96 hours (8-dose course)",
        blockWhileDoseActive = true,
        activeDoseMessage = "The current orexin dose is still active.",
        sleepAid = {
            durationHours = 12,
        },
        symptomReduction = {
            fatigue = 0.35,
            stress = 0.30,
        },
    },

    ["ExtensiveHealth.Buprenorphine"] = {
        tier = 2,
        treats = {"painkiller_addiction"},
        displayName = "Buprenorphine",
        icon = "Buprenorphine",
        usageMessage = "You take buprenorphine. The withdrawal begins to settle.",
        effectDurationHours = 12,
        cureTimeHours = 120,
        treatmentTimeText = "120 hours (10-dose course)",
        blockWhileDoseActive = true,
        activeDoseMessage = "The current buprenorphine dose is still active.",
    },

    ["ExtensiveHealth.TetanusAntitoxin"] = {
        tier = 2,
        treats = {"tetanus"},
        displayName = "Tetanus Antitoxin",
        usageMessage = "You inject the tetanus antitoxin. It neutralizes the toxin.",
        requiresSyringe = true,
        cureTimeHours = 120, -- 5 days to cure
        symptomReduction = {
            muscleSpasms = 0.55,
            pain = 0.45,
            fever = 0.45,
            weakness = 0.35,
        },
    },

    ["ExtensiveHealth.TBAntibiotics"] = {
        tier = 2,
        treats = {"tuberculosis"},
        displayName = "TB Antibiotics (Isoniazid)",
        usageMessage = "You take TB antibiotics. This requires a long treatment course.",
        cureTimeHours = 504, -- 21 days to cure (TB is chronic)
    },

    ["ExtensiveHealth.AntibioticOintment"] = {
        tier = 2,
        treats = {"wound_infection", "cellulitis"},
        displayName = "Antibiotic Ointment",
        usageMessage = "You apply antibiotic ointment to the infected area.",
        isTopical = true,
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The current ointment dose is still active. More now will be wasted.",
        cureTimeHours = 72,
    },

    ["ExtensiveHealth.HomemadeAntibioticOintment"] = {
        tier = 2,
        treats = {"wound_infection", "cellulitis"},
        displayName = "Homemade Antibiotic Ointment",
        icon = "AntibioticOitment",
        usageMessage = "You apply homemade antibiotic ointment to the infected area.",
        isTopical = true,
        blockWhileDoseActive = true,
        consumeWhileDoseActive = true,
        activeDoseMessage = "The current ointment dose is still active. More now will be wasted.",
        cureTimeHours = 72,
    },

    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = {
        tier = 2,
        treats = {"wound_infection", "sepsis", "pneumonia", "cellulitis", "dysentery"},
        displayName = "Broad Spectrum Antibiotics",
        usageMessage = "You take broad spectrum antibiotics. They fight multiple infections.",
        cureTimeHours = 72,
    },

    ["ExtensiveHealth.PlantBasedAntibiotics"] = {
        tier = 2,
        treats = {"wound_infection", "sepsis", "pneumonia", "cellulitis", "dysentery"},
        displayName = "Plant-Based Antibiotics",
        icon = "PlantBasedAntibiotics",
        usageMessage = "You take plant-based antibiotics. They should help fight the infection.",
        cureTimeHours = 72,
    },

    -- =========================================
    -- TIER 3 - CLINICAL GRADE MEDICATION
    -- Rare - Large Hospitals, Military Medical
    -- =========================================

    ["ExtensiveHealth.CorticosteroidInjection"] = {
        tier = 3,
        treats = {"corpse_sickness"},
        displayName = "Corticosteroid Injection",
        usageMessage = "You inject corticosteroids. Inflammation reduces rapidly.",
        requiresSyringe = true,
        cureTimeHours = 24, -- Fast cure
        treatmentTimeText = "12 hours",
        sideEffects = {"immunosuppression", "insomnia"},
    },

    ["ExtensiveHealth.RespiratorySupportKit"] = {
        tier = 3,
        treats = {"corpse_sickness"},
        displayName = "Respiratory Support Kit",
        adminType = "inhaler",
        usageMessage = "You use the respiratory support kit. Fresh oxygen and airway support help you recover.",
        blockWhileDoseActive = true,
        effectDurationHours = 3,
        activeDoseMessage = "The current respiratory support dose is still active. Wait before using the next dose.",
        cureTimeHours = 12, -- Tier 3 cure rate halves this to a 6 hour, 3-dose support course.
        treatmentTimeText = "6 hours (3 doses)",
        symptomReduction = {
            breathingDifficulty = 0.80,
            dizziness = 0.50,
            nausea = 0.35,
            weakness = 0.35,
        },
    },

    ["ExtensiveHealth.IVFluids"] = {
        tier = 3,
        treats = {"ahtr"},
        displayName = "IV Fluids",
        usageMessage = "You start IV fluids. The reaction should stabilize over time.",
        requiresIVKit = true,
        cureTimeHours = 48, -- Tier 3 cure rate makes this a 24 hour course.
        treatmentTimeText = "24 hours (IV support)",
        hydrationSupport = {
            durationHours = 2.0,
            immediateBoost = 0.12,
            hydrationBoost = 0.30,
            restorePerHour = 0.50,
        },
        symptomReduction = {
            dehydration = 0.80,
            healthDrain = 0.70,
            weakness = 0.50,
            nausea = 0.35,
            fever = 0.25,
            pain = 0.20,
        },
    },

    ["ExtensiveHealth.IVAntibiotics"] = {
        tier = 3,
        treats = {"sepsis", "wound_infection", "cellulitis", "dysentery"},
        displayName = "IV Antibiotics",
        usageMessage = "You administer IV antibiotics. The infection is being eliminated.",
        requiresIVKit = true,
        cureTimeHours = 36, -- Fast cure
        sideEffects = {"nausea", "fatigue"},
    },

    ["ExtensiveHealth.IVMetronidazole"] = {
        tier = 3,
        treats = {"dysentery", "sepsis"},
        displayName = "IV Metronidazole",
        usageMessage = "You administer IV Metronidazole. Anaerobic bacteria are dying.",
        requiresIVKit = true,
        cureTimeHours = 24,
        sideEffects = {"metallic_taste", "nausea"},
    },

    ["ExtensiveHealth.IVAmphotericin"] = {
        tier = 3,
        treats = {"cadaveric_aspergillosis"},
        displayName = "IV Amphotericin B",
        usageMessage = "You administer IV Amphotericin. This antifungal is extremely potent.",
        requiresIVKit = true,
        cureTimeHours = 24,
        treatmentTimeText = "24 hours",
        symptomReduction = {
            coughing = 0.65,
            breathingDifficulty = 0.55,
            weakness = 0.45,
            fever = 0.55,
            dehydration = 0.45,
        },
        sideEffects = {"fever", "kidney_stress", "fatigue"},
    },

    ["ExtensiveHealth.ChelationKit"] = {
        tier = 3,
        treats = {"toxin_poisoning"},
        displayName = "Chelation Therapy Kit",
        usageMessage = "You begin chelation therapy. Heavy metals are being removed.",
        requiresIVKit = true,
        cureTimeHours = 48,
        sideEffects = {"headache", "fatigue", "nausea"},
    },

    ["ExtensiveHealth.AlbendazoleInjection"] = {
        tier = 3,
        treats = {"trichinosis"},
        displayName = "Albendazole Injection",
        usageMessage = "You inject Albendazole. The parasites are being destroyed.",
        requiresSyringe = true,
        cureTimeHours = 72,
        sideEffects = {"abdominal_pain", "dizziness"},
    },

    ["ExtensiveHealth.IVCiprofloxacin"] = {
        tier = 3,
        treats = {"gastroenteritis", "dysentery", "pneumonia"},
        displayName = "IV Ciprofloxacin",
        usageMessage = "You administer IV Ciprofloxacin. Bacterial infection is being eliminated.",
        requiresIVKit = true,
        cureTimeHours = 24,
        treatmentTimeText = "12 hours (FAST)",
        sideEffects = {"tendon_weakness", "dizziness"},
    },

    ["ExtensiveHealth.TetanusImmunoglobulin"] = {
        tier = 3,
        treats = {"tetanus"},
        displayName = "Tetanus Immunoglobulin",
        usageMessage = "You inject Tetanus Immunoglobulin. Immediate protection granted.",
        requiresSyringe = true,
        cureTimeHours = 48,
        symptomReduction = {
            muscleSpasms = 0.75,
            pain = 0.60,
            fever = 0.60,
            weakness = 0.50,
        },
        sideEffects = {"injection_site_pain", "fever"},
    },

    ["ExtensiveHealth.RifampicinComboPack"] = {
        tier = 3,
        treats = {"tuberculosis"},
        displayName = "Rifampicin Combination Pack",
        adminType = "pill",
        usageMessage = "You begin the Rifampicin combination treatment. This is powerful.",
        cureTimeHours = 336, -- 14 days (still long but faster than Tier 2)
        sideEffects = {"orange_urine", "liver_stress", "fatigue"},
    },

    ["ExtensiveHealth.IVVancomycin"] = {
        tier = 3,
        treats = {"sepsis", "cellulitis"},
        displayName = "IV Vancomycin",
        usageMessage = "You administer IV Vancomycin. Last-resort antibiotic activated.",
        requiresIVKit = true,
        cureTimeHours = 48,
        sideEffects = {"red_man_syndrome", "kidney_stress"},
    },

    ["ExtensiveHealth.EmergencySepsisKit"] = {
        tier = 3,
        treats = {"sepsis"},
        displayName = "Emergency Sepsis Kit",
        usageMessage = "You use the emergency sepsis kit. Multiple antibiotics administered.",
        requiresIVKit = true,
        cureTimeHours = 24, -- Fastest sepsis cure
        sideEffects = {"severe_fatigue", "nausea", "fever"},
    },

    -- =========================================
    -- SPECIAL MEDICATIONS
    -- =========================================

    ["ExtensiveHealth.Epinephrine"] = {
        tier = 3,
        treats = {}, -- Doesn't treat diseases directly
        displayName = "Epinephrine Auto-Injector",
        usageMessage = "You inject the epinephrine. Your heart races and alertness spikes!",
        isEmergency = true,
        -- Special effects handled separately - revives from blackout, counters anaphylaxis
        immediateEffects = function(player)
            if not player then return end
            local stats = player:getStats()
            if stats then
                -- Reduce fatigue dramatically
                if CharacterStat and CharacterStat.FATIGUE then
                    stats:set(CharacterStat.FATIGUE, 0)
                end
                -- Reduce pain temporarily
                if CharacterStat and CharacterStat.PAIN then
                    local current = stats:get(CharacterStat.PAIN) or 0
                    stats:set(CharacterStat.PAIN, math.max(0, current - 0.5))
                end
                -- Increase panic (adrenaline rush)
                if CharacterStat and CharacterStat.PANIC then
                    local current = stats:get(CharacterStat.PANIC) or 0
                    stats:set(CharacterStat.PANIC, math.min(1, current + 0.3))
                end
                -- Increase endurance temporarily
                if CharacterStat and CharacterStat.ENDURANCE then
                    stats:set(CharacterStat.ENDURANCE, 1)
                end
            end
            -- Wake player from forced sleep (blackout)
            if player:isAsleep() then
                if player.setAsleep then
                    player:setAsleep(false)
                end
                if player.setForceWakeUpTime then
                    player:setForceWakeUpTime(-1)  -- Clear forced wake time
                end
                EHR.Locale.Say(player, "*gasps* The adrenaline is kicking in!")
                EHR.Log("Epinephrine woke player from blackout sleep!")
            end
            EHR.Log("Epinephrine administered - emergency stimulant effects applied")
        end,
        sideEffects = {"headache", "insomnia"},
    },

    ["ExtensiveHealth.LastChanceEpinephrine"] = {
        tier = 3,
        treats = {},
        displayName = "Emergency Epinephrine Auto-Injector",
        icon = "Epinephrine",
        adminType = "injection",
        usageMessage = "You trigger the auto-injector. Adrenaline floods your system.",
        isEmergency = true,
        appliesWithoutDisease = true,
        effectDurationHours = 1,
        blockWhileDoseActive = true,
        immediateEffectsMustSucceed = true,
        activeDoseMessage = "The epinephrine surge is still active.",
        overdoseRisk = false,
        lastChanceEpinephrine = {
            healthThreshold = 15,
            targetOverallHealth = 75,
            durationHours = 1,
            speedMod = 1.20,
            highHealthDeathChance = 50,
            crashFatigueFloor = 0.50,
            mildHeadacheSideEffect = "last_chance_epinephrine_headache",
            thirstSideEffect = "last_chance_epinephrine_thirst",
            severeHeadacheSideEffect = "last_chance_epinephrine_severe_headache",
        },
        immediateEffects = function(player)
            if EHR.Medication.ApplyLastChanceEpinephrine then
                return EHR.Medication.ApplyLastChanceEpinephrine(
                    player,
                    EHR.Medication.Database["ExtensiveHealth.LastChanceEpinephrine"]
                )
            end
            return false
        end,
    },

    -- =========================================
    -- EXTERNAL MOD COMPATIBILITY: They Knew
    -- Knox Virus cure from They Knew mod
    -- =========================================

    ["TheyKnew.Zomboxivir"] = {
        tier = 3,
        treats = {}, -- Knox cure handled via immediateEffects
        displayName = "Zomboxivir Ampule",
        adminType = "injection",
        usageMessage = "*breaks ampule* The experimental cure enters your bloodstream...",
        isKnoxCure = true,
        totalDosesNeeded = 1, -- Single use cure
        immediateEffects = function(player)
            if not player then return end
            -- Use EHR's Knox cure system if available
            if EHR.KnoxCure and EHR.KnoxCure.IsInfected and EHR.KnoxCure.CureInfection then
                if EHR.KnoxCure.IsInfected(player) then
                    EHR.KnoxCure.CureInfection(player)
                    EHR.Locale.Say(player, "*gasps* I can feel it... the infection is gone!")
                    EHR.Log("Zomboxivir cured Knox infection via EHR system")
                else
                    EHR.Locale.Say(player, "I'm not infected... that was a waste.")
                    EHR.Log("Zomboxivir used but player not infected")
                end
            else
                EHR.Log("Zomboxivir: KnoxCure module not loaded, They Knew handles cure")
            end
        end,
    },

    ["TheyKnew.Zomboxolone"] = {
        tier = 2,
        treats = {}, -- Symptom relief
        displayName = "Zomboxolone",
        useVanillaActionOnly = true,
        remoteAdministration = false,
        usageMessage = "You take Zomboxolone. It slows the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 10, -- Drainable bottle
    },

    ["TheyKnew.ZomboxolonePill"] = {
        tier = 2,
        treats = {},
        displayName = "Zomboxolone Pill",
        useVanillaActionOnly = true,
        remoteAdministration = false,
        usageMessage = "You take a Zomboxolone pill. It slows the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 1,
    },

    ["TheyKnew.Zomboxycycline"] = {
        tier = 2,
        treats = {},
        displayName = "Zomboxycycline",
        useVanillaActionOnly = true,
        remoteAdministration = false,
        usageMessage = "You take Zomboxycycline. It fights the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 10, -- Drainable bottle
    },

    ["TheyKnew.ZomboxycyclinePill"] = {
        tier = 2,
        treats = {},
        displayName = "Zomboxycycline Pill",
        useVanillaActionOnly = true,
        remoteAdministration = false,
        usageMessage = "You take a Zomboxycycline pill. It fights the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 1,
    },
}

-- ============================================
-- SIDE EFFECT DEFINITIONS
-- ============================================

local function EHRMedicationGetStats(player)
    if not player then return nil end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    return stats
end

local function EHRMedicationIsClient()
    return isClient and isClient()
end

local function EHRMedicationIsServer()
    return isServer and isServer()
end

local function EHRMedicationIsMultiplayer()
    return EHRMedicationIsClient() or EHRMedicationIsServer()
end

local function EHRMedicationIsAuthoritative()
    return not EHRMedicationIsClient()
end

local function EHRMedicationRequestSync(player)
    if not player or not EHRMedicationIsServer() then return end
    if EHR_TriggerPlayerSync then
        pcall(function() EHR_TriggerPlayerSync(player) end)
    elseif player.transmitModData then
        pcall(function() player:transmitModData() end)
    end
end

local function EHRMedicationRefreshMoodles(player, force)
    if not player then return end

    local modData = nil
    pcall(function() modData = player:getModData() end)
    local currentHour = 0
    pcall(function()
        local gameTime = getGameTime and getGameTime() or nil
        currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    end)

    if modData and not force then
        local lastRefresh = tonumber(modData.EHR_LastMedicationMoodleRefresh) or -999
        if currentHour - lastRefresh < 0.01 then
            return
        end
    end
    if modData then
        modData.EHR_LastMedicationMoodleRefresh = currentHour
    end

    local moodles = nil
    pcall(function() moodles = player:getMoodles() end)
    if moodles and moodles.Update then
        pcall(function() moodles:Update() end)
    end

    if EHRMedicationIsClient() and player.isLocalPlayer and player:isLocalPlayer() and sendPlayerStat and CharacterStat then
        local statsToSync = {
            CharacterStat.PAIN,
            CharacterStat.DISCOMFORT,
            CharacterStat.FATIGUE,
            CharacterStat.ENDURANCE,
            CharacterStat.SICKNESS,
            CharacterStat.FOOD_SICKNESS,
            CharacterStat.THIRST,
        }
        for _, stat in ipairs(statsToSync) do
            if stat then
                pcall(function() sendPlayerStat(player, stat) end)
            end
        end
    end
end

local function EHRMedicationRaiseStat(stats, stat, target)
    if not stats or not stat or target == nil then return end

    pcall(function()
        local current = stats:get(stat) or 0
        if current < target then
            stats:set(stat, target)
        end
    end)
end

local function EHRMedicationCapStat(stats, stat, cap)
    if not stats or not stat or cap == nil then return end

    pcall(function()
        local current = stats:get(stat) or 0
        if current > cap then
            stats:set(stat, cap)
        end
    end)
end

local function EHRMedicationApplyTimedThirst(player, effectData, initialAmount, perHour, ceiling)
    if not player or not effectData then return end

    local stats = EHRMedicationGetStats(player)
    if not stats or not CharacterStat or not CharacterStat.THIRST then return end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    ceiling = math.max(0, math.min(1, tonumber(ceiling) or 1))

    if not effectData.initialThirstApplied then
        local amount = math.max(0, tonumber(initialAmount) or 0)
        if amount > 0 then
            pcall(function()
                local currentThirst = stats:get(CharacterStat.THIRST) or 0
                stats:set(CharacterStat.THIRST, math.min(ceiling, currentThirst + amount))
            end)
        end
        effectData.initialThirstApplied = true
        effectData.lastThirstHour = currentHour
        return
    end

    local lastHour = tonumber(effectData.lastThirstHour) or currentHour
    local deltaHours = math.max(0, math.min(0.25, currentHour - lastHour))
    if deltaHours <= 0 then return end

    effectData.lastThirstHour = currentHour
    local rate = math.max(0, tonumber(perHour) or 0)
    if rate <= 0 then return end

    pcall(function()
        local currentThirst = stats:get(CharacterStat.THIRST) or 0
        stats:set(CharacterStat.THIRST, math.min(ceiling, currentThirst + (rate * deltaHours)))
    end)
end

local function EHRMedicationGetBodyPartName(partType, part)
    local partName = nil

    if BodyPartType and BodyPartType.ToString then
        pcall(function()
            partName = BodyPartType.ToString(partType)
        end)
    end

    if (not partName or partName == "") and part and part.getType and BodyPartType and BodyPartType.ToString then
        pcall(function()
            partName = BodyPartType.ToString(part:getType())
        end)
    end

    return tostring(partName or partType or "")
end

local function EHRMedicationIsKidneyBackPart(partName)
    local name = tostring(partName or ""):lower()
    return name:find("back", 1, true)
        or (name:find("torso", 1, true) and (name:find("lower", 1, true) or name:find("upper", 1, true)))
end

local function EHRMedicationForEachBodyPart(player, callback)
    if not player or not callback then return false end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return false end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return false end

    local changed = false
    local okMax, maxIndex = pcall(function()
        return BodyPartType.ToIndex(BodyPartType.MAX)
    end)
    if not okMax or not maxIndex then return false end

    for i = 0, maxIndex - 1 do
        local partType = nil
        pcall(function() partType = BodyPartType.FromIndex(i) end)
        local part = nil
        if partType then
            pcall(function() part = bodyDamage:getBodyPart(partType) end)
        end
        if part then
            local partName = EHRMedicationGetBodyPartName(partType, part)
            changed = callback(bodyDamage, partType, part, partName) or changed
        end
    end

    return changed
end

local function EHRMedicationDamageUpdate(player)
    if not player then return end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end
    EHRMedicationRefreshMoodles(player, true)
end

local function EHRMedicationApplyKidneyBackPain(player, effectData)
    if not player then return false end

    local modData = player:getModData()
    if not modData then return false end
    local alreadyApplied = effectData and effectData.backPainApplied

    modData.EHR_KidneyStressBodyPain = modData.EHR_KidneyStressBodyPain or {}
    local tracked = modData.EHR_KidneyStressBodyPain

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        if not EHRMedicationIsKidneyBackPart(partName) then return false end

        local lowerBack = tostring(partName):lower():find("lower", 1, true) ~= nil
        local targetStiffness = lowerBack and 32 or 18
        local targetPain = lowerBack and 18 or 10

        local currentStiffness = 0
        local currentPain = 0
        pcall(function()
            if part.getStiffness then currentStiffness = part:getStiffness() or 0 end
        end)
        pcall(function()
            if part.getAdditionalPain then currentPain = part:getAdditionalPain() or 0 end
        end)

        if not tracked[partName] then
            tracked[partName] = {
                stiffness = currentStiffness,
                pain = currentPain,
                targetStiffness = targetStiffness,
                targetPain = targetPain,
            }
        end

        local partChanged = false
        if part.setStiffness and currentStiffness < targetStiffness then
            local okSet = pcall(function()
                part:setStiffness(targetStiffness)
            end)
            partChanged = okSet or partChanged
        end

        if part.setAdditionalPain and currentPain < targetPain then
            local okSet = pcall(function()
                part:setAdditionalPain(targetPain)
            end)
            partChanged = okSet or partChanged
        end

        return partChanged
    end)

    if changed then
        EHRMedicationDamageUpdate(player)
    end

    if effectData then
        effectData.backPainApplied = changed or effectData.backPainApplied
    end

    return changed or alreadyApplied
end

local function EHRMedicationClearKidneyBackPain(player)
    if not player then return end

    local modData = player:getModData()
    local tracked = modData and modData.EHR_KidneyStressBodyPain or nil
    if not tracked then return end

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        local record = tracked[partName]
        if not record then return false end

        local partChanged = false
        local currentStiffness = nil
        local currentPain = nil

        pcall(function()
            if part.getStiffness then currentStiffness = part:getStiffness() end
        end)
        pcall(function()
            if part.getAdditionalPain then currentPain = part:getAdditionalPain() end
        end)

        if part.setStiffness and currentStiffness and currentStiffness <= (record.targetStiffness or 0) + 2 then
            local restore = math.max(0, tonumber(record.stiffness) or 0)
            local okSet = pcall(function()
                part:setStiffness(restore)
            end)
            partChanged = okSet or partChanged

            if okSet and restore <= 0.1 and player.getFitness and BodyPartType and BodyPartType.ToString then
                pcall(function()
                    player:getFitness():removeStiffnessValue(BodyPartType.ToString(partType))
                end)
            end
        end

        if part.setAdditionalPain and currentPain and currentPain <= (record.targetPain or 0) + 2 then
            local restore = math.max(0, tonumber(record.pain) or 0)
            local okSet = pcall(function()
                part:setAdditionalPain(restore)
            end)
            partChanged = okSet or partChanged
        end

        return partChanged
    end)

    if changed then
        EHRMedicationDamageUpdate(player)
    end

    modData.EHR_KidneyStressBodyPain = nil
end

local function EHRMedicationIsWholeBodyMusclePart(partName)
    local name = tostring(partName or ""):lower()
    return name:find("arm", 1, true)
        or name:find("hand", 1, true)
        or name:find("leg", 1, true)
        or name:find("foot", 1, true)
        or name:find("torso", 1, true)
        or name:find("groin", 1, true)
end

local function EHRMedicationApplyWholeBodyMusclePain(player, effectData)
    if not player then return false end

    local modData = player:getModData()
    if not modData then return false end

    modData.EHR_WholeBodyMusclePain = modData.EHR_WholeBodyMusclePain or {}
    local tracked = modData.EHR_WholeBodyMusclePain

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        if not EHRMedicationIsWholeBodyMusclePart(partName) then return false end

        local targetStiffness = 34
        local targetPain = 18
        local currentStiffness = 0
        local currentPain = 0

        pcall(function()
            if part.getStiffness then currentStiffness = part:getStiffness() or 0 end
        end)
        pcall(function()
            if part.getAdditionalPain then currentPain = part:getAdditionalPain() or 0 end
        end)

        if not tracked[partName] then
            tracked[partName] = {
                stiffness = currentStiffness,
                pain = currentPain,
                targetStiffness = targetStiffness,
                targetPain = targetPain,
            }
        end

        local partChanged = false
        if part.setStiffness and currentStiffness < targetStiffness then
            local okSet = pcall(function()
                part:setStiffness(targetStiffness)
            end)
            partChanged = okSet or partChanged
        end

        if part.setAdditionalPain and currentPain < targetPain then
            local okSet = pcall(function()
                part:setAdditionalPain(targetPain)
            end)
            partChanged = okSet or partChanged
        end

        return partChanged
    end)

    if changed then
        EHRMedicationDamageUpdate(player)
    end

    if effectData then
        effectData.musclePainApplied = changed or effectData.musclePainApplied
    end

    return changed or (effectData and effectData.musclePainApplied == true)
end

local function EHRMedicationClearWholeBodyMusclePain(player)
    if not player then return end

    local modData = player:getModData()
    local tracked = modData and modData.EHR_WholeBodyMusclePain or nil
    if not tracked then return end

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        local record = tracked[partName]
        if not record then return false end

        local partChanged = false
        local currentStiffness = nil
        local currentPain = nil

        pcall(function()
            if part.getStiffness then currentStiffness = part:getStiffness() end
        end)
        pcall(function()
            if part.getAdditionalPain then currentPain = part:getAdditionalPain() end
        end)

        if part.setStiffness and currentStiffness and currentStiffness <= (record.targetStiffness or 0) + 2 then
            local restore = math.max(0, tonumber(record.stiffness) or 0)
            local okSet = pcall(function()
                part:setStiffness(restore)
            end)
            partChanged = okSet or partChanged

            if okSet and restore <= 0.1 and player.getFitness and BodyPartType and BodyPartType.ToString then
                pcall(function()
                    player:getFitness():removeStiffnessValue(BodyPartType.ToString(partType))
                end)
            end
        end

        if part.setAdditionalPain and currentPain and currentPain <= (record.targetPain or 0) + 2 then
            local restore = math.max(0, tonumber(record.pain) or 0)
            local okSet = pcall(function()
                part:setAdditionalPain(restore)
            end)
            partChanged = okSet or partChanged
        end

        return partChanged
    end)

    if changed then
        EHRMedicationDamageUpdate(player)
    end

    modData.EHR_WholeBodyMusclePain = nil
end

local function EHRMedicationIsCombatStimulantLimbPart(partName)
    local name = tostring(partName or ""):lower()
    return name:find("arm", 1, true)
        or name:find("hand", 1, true)
        or name:find("leg", 1, true)
        or name:find("foot", 1, true)
end

local function EHRMedicationApplyCombatStimulantLimbPain(player, effectData)
    if not player then return false end

    local modData = player:getModData()
    if not modData then return false end

    modData.EHR_CombatStimulantLimbPain = modData.EHR_CombatStimulantLimbPain or {}
    local tracked = modData.EHR_CombatStimulantLimbPain

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        if not EHRMedicationIsCombatStimulantLimbPart(partName) then return false end

        local targetStiffness = 28
        local targetPain = 16
        local currentStiffness = 0
        local currentPain = 0

        pcall(function()
            if part.getStiffness then currentStiffness = part:getStiffness() or 0 end
        end)
        pcall(function()
            if part.getAdditionalPain then currentPain = part:getAdditionalPain() or 0 end
        end)

        if not tracked[partName] then
            tracked[partName] = {
                stiffness = currentStiffness,
                pain = currentPain,
                targetStiffness = targetStiffness,
                targetPain = targetPain,
            }
        end

        local partChanged = false
        if part.setStiffness and currentStiffness < targetStiffness then
            local okSet = pcall(function()
                part:setStiffness(targetStiffness)
            end)
            partChanged = okSet or partChanged
        end

        if part.setAdditionalPain and currentPain < targetPain then
            local okSet = pcall(function()
                part:setAdditionalPain(targetPain)
            end)
            partChanged = okSet or partChanged
        end

        return partChanged
    end)

    if changed then
        EHRMedicationDamageUpdate(player)
    end

    if effectData then
        effectData.limbPainApplied = changed or effectData.limbPainApplied
    end

    return changed or (effectData and effectData.limbPainApplied == true)
end

local function EHRMedicationClearCombatStimulantLimbPain(player)
    if not player then return end

    local modData = player:getModData()
    local tracked = modData and modData.EHR_CombatStimulantLimbPain or nil
    if not tracked then return end

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        local record = tracked[partName]
        if not record then return false end

        local partChanged = false
        local currentStiffness = nil
        local currentPain = nil

        pcall(function()
            if part.getStiffness then currentStiffness = part:getStiffness() end
        end)
        pcall(function()
            if part.getAdditionalPain then currentPain = part:getAdditionalPain() end
        end)

        if part.setStiffness and currentStiffness and currentStiffness <= (record.targetStiffness or 0) + 2 then
            local restore = math.max(0, tonumber(record.stiffness) or 0)
            local okSet = pcall(function()
                part:setStiffness(restore)
            end)
            partChanged = okSet or partChanged

            if okSet and restore <= 0.1 and player.getFitness and BodyPartType and BodyPartType.ToString then
                pcall(function()
                    player:getFitness():removeStiffnessValue(BodyPartType.ToString(partType))
                end)
            end
        end

        if part.setAdditionalPain and currentPain and currentPain <= (record.targetPain or 0) + 2 then
            local restore = math.max(0, tonumber(record.pain) or 0)
            local okSet = pcall(function()
                part:setAdditionalPain(restore)
            end)
            partChanged = okSet or partChanged
        end

        return partChanged
    end)

    if changed then
        EHRMedicationDamageUpdate(player)
    end

    modData.EHR_CombatStimulantLimbPain = nil
end

local EHR_LAST_CHANCE_HEAD_PAIN_TARGETS = {
    last_chance_epinephrine_headache = 22,
    last_chance_epinephrine_severe_headache = 75,
}

local function EHRMedicationIsHeadPart(partName)
    return tostring(partName or ""):lower() == "head"
end

-- CharacterStat.PAIN is recalculated by vanilla after OnPlayerUpdate, so a
-- direct stat floor disappears in the same frame. Keep the headache on the
-- Head body part instead and remember the pre-effect value so expiry removes
-- only pain owned by this medication.
local function EHRMedicationReconcileLastChanceHeadPain(player, ignoredEffectId)
    if not player then return false end

    local modData = player:getModData()
    if not modData then return false end

    local currentHour = 0
    pcall(function()
        local gameTime = getGameTime and getGameTime() or nil
        currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    end)

    local desiredPain = 0
    local medTracking = modData.EHR_Medication
    local activeSideEffects = type(medTracking) == "table" and medTracking.activeSideEffects or nil
    if type(activeSideEffects) == "table" then
        for effectId, painTarget in pairs(EHR_LAST_CHANCE_HEAD_PAIN_TARGETS) do
            local effectData = effectId ~= ignoredEffectId and activeSideEffects[effectId] or nil
            if type(effectData) == "table" and effectData.clientExpired ~= true then
                local startTime = tonumber(effectData.startTime) or currentHour
                local duration = tonumber(effectData.duration) or 3
                if duration <= 0 or currentHour - startTime < duration then
                    desiredPain = math.max(desiredPain, painTarget)
                end
            end
        end
    end

    local tracked = modData.EHR_LastChanceHeadPain
    if desiredPain > 0 and type(tracked) ~= "table" then
        tracked = {}
        modData.EHR_LastChanceHeadPain = tracked
    end
    if type(tracked) ~= "table" then return false end

    local changed = EHRMedicationForEachBodyPart(player, function(bodyDamage, partType, part, partName)
        if not EHRMedicationIsHeadPart(partName) then return false end
        if not part.getAdditionalPain or not part.setAdditionalPain then return false end

        local currentPain = 0
        local okCurrent = pcall(function()
            currentPain = tonumber(part:getAdditionalPain()) or 0
        end)
        if not okCurrent then return false end

        local record = tracked[partName]
        if desiredPain > 0 then
            if type(record) ~= "table" then
                record = {
                    pain = currentPain,
                    targetPain = math.max(currentPain, desiredPain),
                    lastAppliedPain = currentPain,
                }
                tracked[partName] = record
            end

            local previousTarget = math.max(0, tonumber(record.targetPain) or 0)
            local lastAppliedPain = math.max(0, tonumber(record.lastAppliedPain) or previousTarget)
            -- Another wound/disease may legitimately change AdditionalPain while
            -- the headache is active. Adopt that live value as the new baseline
            -- before reapplying our floor so expiry never erases external pain.
            if math.abs(currentPain - lastAppliedPain) > 0.5 then
                record.pain = currentPain
            end
            local nextTarget = math.max(math.max(0, tonumber(record.pain) or 0), desiredPain)
            local shouldRaise = currentPain < nextTarget - 0.01
            local shouldLowerOwnedPain = nextTarget < previousTarget
                and math.abs(currentPain - lastAppliedPain) <= 0.5
                and currentPain > nextTarget + 0.01
            record.targetPain = nextTarget

            if shouldRaise or shouldLowerOwnedPain then
                local okSet = pcall(function() part:setAdditionalPain(nextTarget) end)
                if okSet then record.lastAppliedPain = nextTarget end
                return okSet
            end
            record.lastAppliedPain = currentPain
            return false
        end

        if type(record) == "table" then
            local previousTarget = math.max(0, tonumber(record.targetPain) or 0)
            local lastAppliedPain = math.max(0, tonumber(record.lastAppliedPain) or previousTarget)
            if math.abs(currentPain - lastAppliedPain) > 0.5 then
                record.pain = currentPain
            end
            local baseline = math.max(0, tonumber(record.pain) or 0)
            tracked[partName] = nil
            if math.abs(currentPain - baseline) > 0.01 then
                return pcall(function() part:setAdditionalPain(baseline) end)
            end
        end
        return false
    end)

    if desiredPain <= 0 then
        modData.EHR_LastChanceHeadPain = nil
    end
    if changed then
        EHRMedicationDamageUpdate(player)
    end
    return changed
end

local function EHRMedicationClearStaleSideEffectFlags(player, activeSideEffects)
    if not player then return end

    local modData = player:getModData()
    if not modData then return end

    if not activeSideEffects or not activeSideEffects.tendon_weakness then
        modData.EHR_TendonWeakness = nil
    end
    if not activeSideEffects or (not activeSideEffects.kidney_stress and not activeSideEffects.lower_back_pain) then
        modData.EHR_KidneyStress = nil
        EHRMedicationClearKidneyBackPain(player)
    end
    if not activeSideEffects or not activeSideEffects.whole_body_muscle_pain then
        EHRMedicationClearWholeBodyMusclePain(player)
    end
    if not activeSideEffects or not activeSideEffects.combat_stimulant_crash then
        EHRMedicationClearCombatStimulantLimbPain(player)
    end
    if not activeSideEffects
        or (not activeSideEffects.last_chance_epinephrine_headache
            and not activeSideEffects.last_chance_epinephrine_severe_headache) then
        EHRMedicationReconcileLastChanceHeadPain(player)
    end
end

EHR.Medication.SideEffects = {
    -- Mild Side Effects (annoying but not dangerous)
    ["nausea"] = {
        displayName = "Nausea",
        duration = 4, -- hours
        severity = 1,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.FOOD_SICKNESS, 0.32)
                EHRMedicationRaiseStat(stats, CharacterStat.SICKNESS, 0.28)
                EHRMedicationRaiseStat(stats, CharacterStat.THIRST, 0.25)
            end
        end,
    },

    ["headache"] = {
        displayName = "Headache",
        duration = 6,
        severity = 1,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, 0.35)
                EHRMedicationRaiseStat(stats, CharacterStat.STRESS, 0.12)
            end
        end,
    },

    ["last_chance_epinephrine_headache"] = {
        displayName = "Epinephrine Crash Headache",
        duration = 3,
        severity = 1,
        effects = function(player)
            EHRMedicationReconcileLastChanceHeadPain(player)
        end,
        onEnd = function(player)
            EHRMedicationReconcileLastChanceHeadPain(player, "last_chance_epinephrine_headache")
        end,
    },

    ["last_chance_epinephrine_severe_headache"] = {
        displayName = "Severe Epinephrine Headache",
        duration = 3,
        severity = 3,
        effects = function(player)
            EHRMedicationReconcileLastChanceHeadPain(player)
        end,
        onEnd = function(player)
            EHRMedicationReconcileLastChanceHeadPain(player, "last_chance_epinephrine_severe_headache")
        end,
    },

    ["last_chance_epinephrine_thirst"] = {
        displayName = "Epinephrine Thirst",
        duration = 3,
        severity = 1,
        effects = function(player, effectData)
            EHRMedicationApplyTimedThirst(player, effectData, 0.10, 0.12, 0.85)
        end,
    },

    ["dizziness"] = {
        displayName = "Dizziness",
        duration = 3,
        severity = 1,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.DISCOMFORT, 0.45)
                EHRMedicationRaiseStat(stats, CharacterStat.PANIC, 0.12)
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.85)
            end
        end,
    },

    ["fatigue"] = {
        displayName = "Fatigue",
        duration = 8,
        severity = 1,
        mpFatigueRecoveryTarget = 0.25,
        mpFatigueRecoveryHours = 4,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.42)
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.78)
            end
        end,
    },

    ["insomnia"] = {
        displayName = "Insomnia",
        duration = 12,
        severity = 1,
        effects = function(player)
            -- Makes it harder to sleep - handled in sleep system
            local modData = player:getModData()
            modData.EHR_Insomnia = true
        end,
        onEnd = function(player)
            local modData = player:getModData()
            modData.EHR_Insomnia = nil
        end,
    },

    ["metallic_taste"] = {
        displayName = "Metallic Taste",
        duration = 4,
        severity = 1,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.UNHAPPINESS, 0.22)
            end
        end,
    },

    ["orange_urine"] = {
        displayName = "Orange Urine",
        duration = 24,
        severity = 1,
        -- Cosmetic only, no gameplay effect
        effects = function(player) end,
    },

    ["injection_site_pain"] = {
        displayName = "Injection Site Pain",
        duration = 6,
        severity = 1,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, 0.25)
            end
        end,
    },

    ["dehydration"] = {
        displayName = "Dehydration",
        duration = 8,
        severity = 2,
        effects = function(player, effectData)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.78)
            end
            EHRMedicationApplyTimedThirst(player, effectData or {}, 0.14, 0.14, 0.76)
        end,
    },

    ["lower_back_pain"] = {
        displayName = "Lower Back Pain",
        duration = 8,
        severity = 2,
        effects = function(player, effectData)
            local backPainApplied = EHRMedicationApplyKidneyBackPain(player, effectData)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, backPainApplied and 0.24 or 0.30)
                EHRMedicationRaiseStat(stats, CharacterStat.DISCOMFORT, 0.18)
            end
        end,
    },

    ["diuretic_urination"] = {
        displayName = "Diuretic Effect",
        duration = 8,
        severity = 2,
        effects = function(player, effectData)
            if EHR.LifestyleCompat and EHR.LifestyleCompat.ApplyMedicationBathroomPressure then
                EHR.LifestyleCompat.ApplyMedicationBathroomPressure(player, effectData, 18.0)
            end
        end,
    },

    ["abdominal_pain"] = {
        displayName = "Abdominal Pain",
        duration = 4,
        severity = 1,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, 0.38)
                EHRMedicationRaiseStat(stats, CharacterStat.FOOD_SICKNESS, 0.20)
                EHRMedicationRaiseStat(stats, CharacterStat.SICKNESS, 0.18)
            end
        end,
    },

    -- Moderate Side Effects (significant but manageable)
    ["fever"] = {
        displayName = "Drug-Induced Fever",
        duration = 6,
        severity = 2,
        mpFatigueRecoveryTarget = 0.25,
        mpFatigueRecoveryHours = 4,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.TEMPERATURE, 0.65)
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.32)
            end
        end,
    },

    ["severe_fatigue"] = {
        displayName = "Severe Fatigue",
        duration = 12,
        severity = 2,
        mpFatigueRecoveryTarget = 0.35,
        mpFatigueRecoveryHours = 5,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.75)
                EHRMedicationRaiseStat(stats, CharacterStat.SICKNESS, 0.22)
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.50)
            end
        end,
    },

    ["caffeine_crash"] = {
        displayName = "Caffeine Crash",
        duration = 2,
        severity = 2,
        mpFatigueRecoveryTarget = 0.35,
        mpFatigueRecoveryHours = 4,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.85)
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.55)
            end
        end,
    },

    ["combat_stimulant_crash"] = {
        displayName = "Combat Stimulant Crash",
        duration = 6,
        severity = 2,
        mpFatigueRecoveryTarget = 0.40,
        mpFatigueRecoveryHours = 6,
        effects = function(player, effectData)
            if not player then return end
            effectData = effectData or {}

            EHRMedicationApplyCombatStimulantLimbPain(player, effectData)

            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.80)
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, 0.34)
                EHRMedicationRaiseStat(stats, CharacterStat.DISCOMFORT, 0.28)

                local gameTime = getGameTime and getGameTime() or nil
                local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
                if not effectData.initialThirstApplied then
                    pcall(function()
                        local currentThirst = stats:get(CharacterStat.THIRST) or 0
                        stats:set(CharacterStat.THIRST, math.min(1, currentThirst + 0.08))
                    end)
                    effectData.initialThirstApplied = true
                    effectData.lastThirstHour = currentHour
                else
                    local lastHour = tonumber(effectData.lastThirstHour) or currentHour
                    local deltaHours = math.max(0, math.min(0.25, currentHour - lastHour))
                    if deltaHours > 0 then
                        pcall(function()
                            local currentThirst = stats:get(CharacterStat.THIRST) or 0
                            stats:set(CharacterStat.THIRST, math.min(1, currentThirst + (0.075 * deltaHours)))
                        end)
                        effectData.lastThirstHour = currentHour
                    end
                end
            end
        end,
        onEnd = function(player)
            EHRMedicationClearCombatStimulantLimbPain(player)
        end,
    },

    ["whole_body_muscle_pain"] = {
        displayName = "Whole-Body Muscle Pain",
        duration = 6,
        severity = 2,
        effects = function(player, effectData)
            EHRMedicationApplyWholeBodyMusclePain(player, effectData)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, 0.32)
                EHRMedicationRaiseStat(stats, CharacterStat.DISCOMFORT, 0.22)
            end
        end,
        onEnd = function(player)
            EHRMedicationClearWholeBodyMusclePain(player)
        end,
    },

    ["tendon_weakness"] = {
        displayName = "Tendon Weakness",
        duration = 24,
        severity = 2,
        effects = function(player)
            -- Reduces movement speed slightly
            local modData = player:getModData()
            modData.EHR_TendonWeakness = true

            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.70)
            end
        end,
        onEnd = function(player)
            local modData = player:getModData()
            modData.EHR_TendonWeakness = nil
        end,
    },

    ["red_man_syndrome"] = {
        displayName = "Red Man Syndrome",
        duration = 2,
        severity = 2,
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, 0.45)
                EHRMedicationRaiseStat(stats, CharacterStat.DISCOMFORT, 0.55)
                EHRMedicationRaiseStat(stats, CharacterStat.STRESS, 0.35)
            end
        end,
    },

    -- Severe Side Effects (dangerous, require management)
    ["immunosuppression"] = {
        displayName = "Immunosuppression",
        duration = 48,
        severity = 3,
        effects = function(player)
            -- Makes player more susceptible to diseases
            local modData = player:getModData()
            modData.EHR_Immunosuppressed = true
        end,
        onEnd = function(player)
            local modData = player:getModData()
            modData.EHR_Immunosuppressed = nil
        end,
    },

    ["kidney_stress"] = {
        displayName = "Kidney Stress",
        duration = 18,
        severity = 2,
        mpFatigueRecoveryTarget = 0.30,
        mpFatigueRecoveryHours = 5,
        effects = function(player, effectData)
            local modData = player:getModData()
            modData.EHR_KidneyStress = true
            local backPainApplied = EHRMedicationApplyKidneyBackPain(player, effectData)

            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.38)
                EHRMedicationRaiseStat(stats, CharacterStat.SICKNESS, 0.16)
                EHRMedicationRaiseStat(stats, CharacterStat.PAIN, backPainApplied and 0.30 or 0.38)
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.78)
            end
        end,
        onEnd = function(player)
            local modData = player:getModData()
            modData.EHR_KidneyStress = nil
            EHRMedicationClearKidneyBackPain(player)
        end,
    },

    ["liver_stress"] = {
        displayName = "Liver Stress",
        duration = 48,
        severity = 3,
        mpFatigueRecoveryTarget = 0.30,
        mpFatigueRecoveryHours = 6,
        effects = function(player)
            -- Reduces effectiveness of other medications
            local modData = player:getModData()
            modData.EHR_LiverStress = true

            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.UNHAPPINESS, 0.28)
                EHRMedicationRaiseStat(stats, CharacterStat.FATIGUE, 0.35)
                EHRMedicationRaiseStat(stats, CharacterStat.FOOD_SICKNESS, 0.18)
                EHRMedicationRaiseStat(stats, CharacterStat.SICKNESS, 0.16)
            end
        end,
        onEnd = function(player)
            local modData = player:getModData()
            modData.EHR_LiverStress = nil
        end,
    },

    ["medication_overdose"] = {
        displayName = "Medication Overdose",
        duration = 10,
        severity = 3,
        effects = function(player, effectData)
            if not player then return end

            effectData = effectData or {}
            local intensity = math.max(1, math.min(3, effectData.intensity or 1))
            local sicknessTarget = effectData.sicknessTarget or math.min(0.60, 0.42 + (0.04 * intensity))
            local enduranceCap = effectData.enduranceCap or math.max(0.45, 0.57 - (0.04 * intensity))
            local thirstTarget = effectData.thirstTarget or math.min(0.78, 0.64 + (0.04 * intensity))
            local healthCap = effectData.healthCap or math.max(45, 70 - (7 * intensity))

            local stats = nil
            pcall(function() stats = player:getStats() end)
            if stats and CharacterStat then
                local function raiseStat(stat, target)
                    if not stat then return end
                    pcall(function()
                        local current = stats:get(stat) or 0
                        if current < target then
                            stats:set(stat, target)
                        end
                    end)
                end

                local function capStat(stat, target)
                    if not stat then return end
                    pcall(function()
                        local current = stats:get(stat) or 0
                        if current > target then
                            stats:set(stat, target)
                        end
                    end)
                end

                raiseStat(CharacterStat.SICKNESS, sicknessTarget)
                raiseStat(CharacterStat.FOOD_SICKNESS, math.min(0.50, sicknessTarget))
                capStat(CharacterStat.ENDURANCE, enduranceCap)
            end

            EHRMedicationApplyTimedThirst(
                player,
                effectData,
                0.08 + (0.03 * intensity),
                0.10 + (0.03 * intensity),
                thirstTarget
            )

            local bodyDamage = nil
            pcall(function() bodyDamage = player:getBodyDamage() end)
            if bodyDamage then
                local okHealth, currentHealth = pcall(function()
                    return bodyDamage:getOverallBodyHealth()
                end)

                if okHealth and currentHealth and currentHealth > healthCap then
                    local damageAmount = currentHealth - healthCap
                    local reduced = false
                    if bodyDamage.ReduceGeneralHealth then
                        reduced = pcall(function()
                            bodyDamage:ReduceGeneralHealth(damageAmount)
                        end)
                    end

                    if not reduced then
                        pcall(function()
                            bodyDamage:setOverallBodyHealth(healthCap)
                        end)
                    else
                        local okAfter, afterHealth = pcall(function()
                            return bodyDamage:getOverallBodyHealth()
                        end)
                        if okAfter and afterHealth and afterHealth > healthCap then
                            pcall(function()
                                bodyDamage:setOverallBodyHealth(healthCap)
                            end)
                        end
                    end

                    if bodyDamage.DamageUpdate then
                        pcall(function() bodyDamage:DamageUpdate() end)
                    end
                end
            end
        end,
    },
}

-- ============================================
-- MEDICATION DOSING SCHEDULES
-- How often each medication needs to be retaken
-- ============================================

EHR.Medication.DosingSchedules = {
    -- Tier 0 - Basic (every 4 hours)
    ["Base.Antibiotics"] = { doseInterval = 4, dosesRequired = 6 },
    ["Base.Pills"] = { doseInterval = 3, dosesRequired = 1, activeHours = 3 },
    ["ExtensiveHealth.HomemadePainkillers"] = { doseInterval = 4, dosesRequired = 3 },
    ["Base.PillsVitamins"] = { doseInterval = 12, dosesRequired = 1 },
    ["Base.PillsSleepingTablets"] = { doseInterval = 8, dosesRequired = 1 },
    ["ExtensiveHealth.HomemadeSleepingPills"] = { doseInterval = 8, dosesRequired = 1 },
    ["Base.PillsAntiDep"] = { doseInterval = 12, dosesRequired = 14 },
    ["Base.PillsBeta"] = { doseInterval = 2, dosesRequired = 1, activeHours = 2 },

    -- Tier 1 - OTC (every 4-6 hours)
    ["ExtensiveHealth.ColdFluTablets"] = { doseInterval = 4, dosesRequired = 8 },
    ["ExtensiveHealth.CommonColdTea"] = { doseInterval = 4, dosesRequired = 8 },
    ["ExtensiveHealth.AntipyreticTablets"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntipyreticTea"] = { doseInterval = 6, dosesRequired = 1 },
    ["ExtensiveHealth.CoughSyrup"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.HomemadeCoughSyrup"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.ElectrolytePowder"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.BronchodilatorInhaler"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.AntiNauseaTablets"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntiInflammatory"] = { doseInterval = 6, dosesRequired = 4 },
    ["ExtensiveHealth.AntiDiarrheal"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.MuscleRelaxants"] = { doseInterval = 8, dosesRequired = 3 },
    ["ExtensiveHealth.HomemadeMuscleRelaxant"] = { doseInterval = 8, dosesRequired = 3 },
    ["ExtensiveHealth.RelaxantTea"] = { doseInterval = 3, dosesRequired = 1 },
    ["ExtensiveHealth.NitricOxideBooster"] = { doseInterval = 3, dosesRequired = 1 },
    ["ExtensiveHealth.CombatStimulants"] = { doseInterval = 3, dosesRequired = 1 },
    ["ExtensiveHealth.CoughSuppressant"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntisepticCream"] = { doseInterval = 8, dosesRequired = 3 },
    ["ExtensiveHealth.HomemadeAntisepticCream"] = { doseInterval = 8, dosesRequired = 3 },

    -- Tier 2 - Prescription (every 6-12 hours)
    ["ExtensiveHealth.AntiviralCapsules"] = { doseInterval = 8, dosesRequired = 6 },
    ["ExtensiveHealth.PrescriptionAntibiotics"] = { doseInterval = 8, dosesRequired = 9 },
    ["ExtensiveHealth.AntifungalTablets"] = { doseInterval = 12, dosesRequired = 10 },
    ["ExtensiveHealth.ActivatedCharcoal"] = { doseInterval = 0, dosesRequired = 1 },  -- Single dose absorbs toxins
    ["ExtensiveHealth.HomeMadeActivatedCharcoal"] = { doseInterval = 0, dosesRequired = 1 },  -- Craftable single-dose toxin binder
    ["ExtensiveHealth.AntiparasiticPills"] = { doseInterval = 12, dosesRequired = 14 },
    ["ExtensiveHealth.TopicalPermethrin"] = { doseInterval = 12, dosesRequired = 6 },
    ["ExtensiveHealth.HomemadeTopicalPermethrin"] = { doseInterval = 12, dosesRequired = 6 },
    ["ExtensiveHealth.OralRehydrationKit"] = { doseInterval = 6, dosesRequired = 8 },  -- Full rehydration course
    ["ExtensiveHealth.InstantIcePack"] = { doseInterval = 1, dosesRequired = 4 },  -- Emergency cooling course
    ["ExtensiveHealth.Furosemide"] = { doseInterval = 8, dosesRequired = 6 },  -- Transfusion reaction support course
    ["ExtensiveHealth.Antipsychotics"] = { doseInterval = 12, dosesRequired = 8 },  -- 4-day mental health course
    ["ExtensiveHealth.DualOrexinReceptor"] = { doseInterval = 12, dosesRequired = 8 },  -- 4-day insomnia course
    ["ExtensiveHealth.Buprenorphine"] = { doseInterval = 12, dosesRequired = 10 },  -- 5-day addiction treatment course
    ["ExtensiveHealth.TetanusAntitoxin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
    ["ExtensiveHealth.TBAntibiotics"] = { doseInterval = 24, dosesRequired = 21 },
    ["ExtensiveHealth.AntibioticOintment"] = { doseInterval = 8, dosesRequired = 6 },  -- Reduced from 9
    ["ExtensiveHealth.HomemadeAntibioticOintment"] = { doseInterval = 8, dosesRequired = 6 },
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = { doseInterval = 8, dosesRequired = 6 },  -- Reduced from 9
    ["ExtensiveHealth.PlantBasedAntibiotics"] = { doseInterval = 8, dosesRequired = 6 },

    -- Tier 3 - Clinical (mostly single dose for emergency/IV treatments)
    ["ExtensiveHealth.CorticosteroidInjection"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
    ["ExtensiveHealth.RespiratorySupportKit"] = { doseInterval = 3, dosesRequired = 3 },  -- Short oxygen/airway support course
    ["ExtensiveHealth.IVFluids"] = { doseInterval = 0, dosesRequired = 1 },  -- Single IV support session
    ["ExtensiveHealth.IVAntibiotics"] = { doseInterval = 0, dosesRequired = 1 },  -- Single IV infusion
    ["ExtensiveHealth.IVMetronidazole"] = { doseInterval = 0, dosesRequired = 1 },  -- Single IV infusion
    ["ExtensiveHealth.IVAmphotericin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single IV infusion
    ["ExtensiveHealth.ChelationKit"] = { doseInterval = 0, dosesRequired = 1 },  -- Single chelation session
    ["ExtensiveHealth.AlbendazoleInjection"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
    ["ExtensiveHealth.IVCiprofloxacin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single IV infusion
    ["ExtensiveHealth.TetanusImmunoglobulin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
    ["ExtensiveHealth.RifampicinComboPack"] = { doseInterval = 24, dosesRequired = 14 },  -- TB requires full course
    ["ExtensiveHealth.IVVancomycin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single IV infusion
    ["ExtensiveHealth.EmergencySepsisKit"] = { doseInterval = 0, dosesRequired = 1 },  -- Emergency single use
    ["ExtensiveHealth.LastChanceEpinephrine"] = { doseInterval = 1, dosesRequired = 1, activeHours = 1 },

    -- External mod compatibility (They Knew)
    ["TheyKnew.Zomboxivir"] = { doseInterval = 0, dosesRequired = 1 },  -- Single ampule cure
    ["TheyKnew.Zomboxolone"] = { doseInterval = 8, dosesRequired = 10 },  -- Drainable bottle (10 doses)
    ["TheyKnew.ZomboxolonePill"] = { doseInterval = 8, dosesRequired = 1 },  -- Single pill from bottle
    ["TheyKnew.Zomboxycycline"] = { doseInterval = 8, dosesRequired = 10 },  -- Drainable bottle (10 doses)
    ["TheyKnew.ZomboxycyclinePill"] = { doseInterval = 8, dosesRequired = 1 },  -- Single pill from bottle
}

-- Medications that suppress positive immune-system bonuses while their current
-- dose is active. Keep this keyed by full type so homemade and clinical variants
-- do not depend on localized display names.
EHR.Medication.AntibioticMedications = {
    ["Base.Antibiotics"] = true,
    ["ExtensiveHealth.PrescriptionAntibiotics"] = true,
    ["ExtensiveHealth.TBAntibiotics"] = true,
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = true,
    ["ExtensiveHealth.PlantBasedAntibiotics"] = true,
    ["ExtensiveHealth.IVAntibiotics"] = true,
    ["ExtensiveHealth.IVMetronidazole"] = true,
    ["ExtensiveHealth.IVCiprofloxacin"] = true,
    ["ExtensiveHealth.RifampicinComboPack"] = true,
    ["ExtensiveHealth.IVVancomycin"] = true,
    ["ExtensiveHealth.EmergencySepsisKit"] = true,
}

-- Only these systemic medicines can trigger the severe off-schedule overdose layer.
-- Topical/support items still track dose schedules, but repeating them early no longer
-- applies the dangerous generic overdose package.
EHR.Medication.OverdoseRiskMedications = {
    ["Base.PillsAntiDep"] = true,

    ["ExtensiveHealth.AntiviralCapsules"] = true,
    ["ExtensiveHealth.PrescriptionAntibiotics"] = true,
    ["ExtensiveHealth.AntifungalTablets"] = true,
    ["ExtensiveHealth.AntiparasiticPills"] = true,
    ["ExtensiveHealth.Furosemide"] = true,
    ["ExtensiveHealth.Antipsychotics"] = true,
    ["ExtensiveHealth.DualOrexinReceptor"] = true,
    ["ExtensiveHealth.Buprenorphine"] = true,
    ["ExtensiveHealth.TBAntibiotics"] = true,
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = true,
    ["ExtensiveHealth.PlantBasedAntibiotics"] = true,
    ["ExtensiveHealth.RifampicinComboPack"] = true,

    ["TheyKnew.Zomboxolone"] = true,
    ["TheyKnew.Zomboxycycline"] = true,
}

-- Default dosing for medications not in the schedule
EHR.Medication.DefaultDosing = { doseInterval = 6, dosesRequired = 1 }

local function EHR_MedicationCanCure(medData, tierEffects)
    if medData and (medData.preventionOnly == true or medData.canCure == false) then
        return false
    end

    return (tierEffects and tierEffects.canCure == true)
        or (medData and (
            medData.canCure == true
            or medData.cureTimeHours ~= nil
            or medData.diseaseCureTimeHours ~= nil
            or medData.isKnoxCure == true
        ))
end

local function EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
    medData = medData or {}

    local dosingSchedule = (itemFullType and EHR.Medication.DosingSchedules[itemFullType]) or EHR.Medication.DefaultDosing
    local doseInterval = medData.doseIntervalHours or medData.intervalHours or dosingSchedule.doseInterval or 6

    local canCure = EHR_MedicationCanCure(medData, tierEffects)
    local hasSymptomRelief = medData.symptomReduction ~= nil
        or medData.analgesic ~= nil
        or ((tierEffects and tierEffects.symptomRelief or 0) > 0)
    local symptomOnly = hasSymptomRelief and not canCure

    local dosesRequired = medData.totalDosesNeeded or dosingSchedule.dosesRequired or 1
    if symptomOnly and not medData.requiresDoseCourse then
        dosesRequired = 1
    end

    local activeHours = medData.effectDurationHours
        or medData.symptomReliefHours
        or dosingSchedule.activeHours
        or doseInterval
    if activeHours <= 0 and hasSymptomRelief then
        activeHours = 4
    end

    return {
        doseInterval = math.max(0, doseInterval or 0),
        dosesRequired = math.max(1, dosesRequired or 1),
        activeHours = math.max(0, activeHours or 0),
        symptomOnly = symptomOnly,
    }
end

function EHR.Medication.GetDoseTiming(medData, itemFullType, tierEffects)
    return EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
end

function EHR.Medication.CanCauseMedicationOverdose(medData, itemFullType)
    if not medData then return false end
    if medData.overdoseRisk ~= nil then
        return medData.overdoseRisk == true
    end
    if medData.isTopical == true or medData.preventionOnly == true then
        return false
    end

    local riskTable = EHR.Medication.OverdoseRiskMedications or {}
    return riskTable[itemFullType] == true
end

function EHR.Medication.GetEarlyDoseOverdoseInfo(player, medData, itemFullType)
    if not player or not medData then return nil end
    if not EHR.Medication.CanCauseMedicationOverdose(medData, itemFullType) then return nil end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking or not medTracking.activeDoses then return nil end

    local tier = medData.tier or 0
    local tierEffects = EHR.Medication.TierEffectiveness[tier] or EHR.Medication.TierEffectiveness[0]
    local doseTiming = EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)

    if (doseTiming.dosesRequired or 1) < 6 then return nil end
    if (doseTiming.doseInterval or 0) <= 0 then return nil end

    local medKey = itemFullType or medData.displayName
    local existingDose = medTracking.activeDoses[medKey]
    if not existingDose or not existingDose.lastDoseTime then return nil end

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local elapsed = math.max(0, currentHour - existingDose.lastDoseTime)
    local earlyBy = doseTiming.doseInterval - elapsed
    if earlyBy <= 0.05 then return nil end

    local earlyRatio = math.max(0, math.min(1, earlyBy / doseTiming.doseInterval))
    local intensity = 1
    if earlyRatio >= 0.75 then
        intensity = 2
    end
    if earlyRatio >= 0.92 then
        intensity = 3
    end

    local existingOverdose = medTracking.activeSideEffects and medTracking.activeSideEffects["medication_overdose"]
    if existingOverdose and existingOverdose.intensity then
        intensity = math.min(3, math.max(intensity, existingOverdose.intensity + 1))
    end

    return {
        effectId = "medication_overdose",
        medKey = medKey,
        medicationName = medData.displayName or medKey,
        currentHour = currentHour,
        earlyBy = earlyBy,
        intervalHours = doseTiming.doseInterval,
        intensity = intensity,
        duration = math.min(10, 7 + intensity),
        nonLethalOverdose = medData.isTopical == true or medData.overdoseNonLethal == true,
        sicknessTarget = math.min(0.60, 0.42 + (0.04 * intensity)),
        enduranceCap = math.max(0.45, 0.57 - (0.04 * intensity)),
        thirstTarget = math.min(0.78, 0.64 + (0.04 * intensity)),
        healthCap = math.max(45, 70 - (7 * intensity)),
    }
end

function EHR.Medication.KillFromOverdose(player, overdoseInfo, offScheduleCount)
    if not player then return false end

    local medName = overdoseInfo and overdoseInfo.medicationName or "medication"
    local cause = string.format(
        "Medication Overdose - repeated off-schedule doses of %s (%d early doses)",
        tostring(medName),
        tonumber(offScheduleCount) or 3
    )

    if EHR.RecordDeathCause then
        EHR.RecordDeathCause(player, cause)
    end

    if player.isLocalPlayer and player:isLocalPlayer() and player.Say then
        EHR.Locale.Say(player, "Too many doses... something is very wrong...")
    end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage and bodyDamage.setOverallBodyHealth then
        pcall(function() bodyDamage:setOverallBodyHealth(0) end)
    end

    if player.setHealth then
        pcall(function() player:setHealth(0) end)
    end

    EHR.Log(cause)
    return true
end

function EHR.Medication.ApplyEarlyDoseOverdose(player, overdoseInfo)
    if not player or not overdoseInfo then return false end

    local sideEffect = EHR.Medication.SideEffects and EHR.Medication.SideEffects[overdoseInfo.effectId]
    if not sideEffect then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    local currentHour = overdoseInfo.currentHour
    if not currentHour then
        local gameTime = getGameTime()
        currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    end

    local existing = medTracking.activeSideEffects[overdoseInfo.effectId]
    local duration = overdoseInfo.duration or sideEffect.duration or 10
    if existing and existing.startTime and existing.duration then
        local remaining = math.max(0, existing.duration - (currentHour - existing.startTime))
        duration = math.max(duration, remaining)
    end

    local offScheduleCount = (existing and tonumber(existing.offScheduleCount)) or 0
    offScheduleCount = offScheduleCount + 1
    local lethalOffScheduleCount = (existing and tonumber(existing.lethalOffScheduleCount)) or 0
    if overdoseInfo.nonLethalOverdose ~= true then
        lethalOffScheduleCount = lethalOffScheduleCount + 1
    end

    medTracking.activeSideEffects[overdoseInfo.effectId] = {
        startTime = currentHour,
        duration = duration,
        intensity = overdoseInfo.intensity or 1,
        offScheduleCount = offScheduleCount,
        lethalOffScheduleCount = lethalOffScheduleCount,
        nonLethalOverdose = overdoseInfo.nonLethalOverdose == true,
        medKey = overdoseInfo.medKey,
        medicationName = overdoseInfo.medicationName,
        earlyBy = overdoseInfo.earlyBy,
        intervalHours = overdoseInfo.intervalHours,
        sicknessTarget = overdoseInfo.sicknessTarget,
        enduranceCap = overdoseInfo.enduranceCap,
        thirstTarget = overdoseInfo.thirstTarget,
        healthCap = overdoseInfo.healthCap,
    }

    if sideEffect.effects then
        sideEffect.effects(player, medTracking.activeSideEffects[overdoseInfo.effectId])
    end
    EHRMedicationRefreshMoodles(player, true)

    if lethalOffScheduleCount >= 3 then
        EHR.Medication.KillFromOverdose(player, overdoseInfo, lethalOffScheduleCount)
        return true
    end

    if player.isLocalPlayer and player:isLocalPlayer() then
        local earlyText = string.format("%.1f", overdoseInfo.earlyBy or 0)
        if (overdoseInfo.intensity or 1) >= 3 then
            EHR.Locale.Say(player, "I took that way too soon... I feel awful.")
        elseif (overdoseInfo.intensity or 1) >= 2 then
            EHR.Locale.Say(player, "That dose was too early. My body is reacting badly.")
        else
            EHR.Locale.Say(player, "I should have waited another " .. earlyText .. "h before taking that.")
        end
    end

    EHR.Log("Early dose overdose from " .. tostring(overdoseInfo.medicationName) ..
            " (" .. string.format("%.2f", overdoseInfo.earlyBy or 0) .. "h early, intensity " ..
            tostring(overdoseInfo.intensity or 1) .. ", count " .. tostring(offScheduleCount) ..
            ", lethal count " .. tostring(lethalOffScheduleCount) .. ")")
    return true
end

-- ============================================
-- DRUG INTERACTION DATABASE
-- ============================================

EHR.Medication.DrugInteractions = {
    -- =========================================
    -- DANGEROUS COMBINATIONS
    -- =========================================
    {
        drugs = {"antibiotic", "corticosteroid"},
        severity = "danger",
        message = "Antibiotics + Corticosteroids: Risk of immunosuppression!",
        effect = function(player)
            local modData = player:getModData()
            modData.EHR_Immunosuppressed = true
        end,
    },
    {
        drugs = {"chelation", "iv antifungal"},
        severity = "danger",
        message = "Chelation + IV Antifungal: Strong kidney stress!",
        effect = function(player)
            local stats = player:getStats()
            if stats and CharacterStat then
                if CharacterStat.FATIGUE then
                    local current = stats:get(CharacterStat.FATIGUE) or 0
                    stats:set(CharacterStat.FATIGUE, math.min(0.65, current + 0.18))
                end
                if CharacterStat.SICKNESS then
                    local current = stats:get(CharacterStat.SICKNESS) or 0
                    stats:set(CharacterStat.SICKNESS, math.min(0.35, current + 0.12))
                end
            end
        end,
    },
    {
        drugs = {"rifampicin", "tb antibiotics"},
        severity = "danger",
        message = "Rifampicin + Isoniazid: SEVERE liver toxicity risk!",
        effect = function(player)
            local modData = player:getModData()
            modData.EHR_LiverStress = true
            -- Increase unhappiness from feeling unwell
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.UNHAPPINESS then
                local current = stats:get(CharacterStat.UNHAPPINESS) or 0
                stats:set(CharacterStat.UNHAPPINESS, math.min(1, current + 0.2))
            end
        end,
    },
    {
        drugs = {"antibiotic", "rifampicin"},
        severity = "danger",
        message = "Multiple antibiotics + Rifampicin: High liver stress!",
        effect = function(player)
            local modData = player:getModData()
            modData.EHR_LiverStress = true
        end,
    },

    -- =========================================
    -- WARNING COMBINATIONS
    -- =========================================
    {
        drugs = {"muscle relaxant", "beta blocker"},
        severity = "warning",
        message = "Muscle Relaxants + Beta Blockers: May cause excessive sedation",
        effect = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.FATIGUE then
                local current = stats:get(CharacterStat.FATIGUE) or 0
                stats:set(CharacterStat.FATIGUE, math.min(0.8, current + 0.15))
            end
        end,
    },
    {
        drugs = {"anti-inflammatory", "corticosteroid"},
        severity = "warning",
        message = "Anti-inflammatory + Corticosteroids: Increased GI bleeding risk",
        effect = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.PAIN then
                local current = stats:get(CharacterStat.PAIN) or 0
                stats:set(CharacterStat.PAIN, math.min(0.5, current + 0.1))
            end
        end,
    },
    {
        drugs = {"antiviral", "tb antibiotics"},
        severity = "warning",
        message = "Antivirals + TB Antibiotics: Liver stress risk",
        effect = function(player)
            local modData = player:getModData()
            modData.EHR_LiverStress = true
        end,
    },
    {
        drugs = {"anti-inflammatory", "antibiotic"},
        severity = "warning",
        message = "NSAIDs + Antibiotics: Increased GI upset",
        effect = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.FOOD_SICKNESS then
                local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
                stats:set(CharacterStat.FOOD_SICKNESS, math.min(0.3, current + 0.1))
            end
        end,
    },
    {
        drugs = {"painkiller", "muscle relaxant"},
        severity = "warning",
        message = "Painkillers + Muscle Relaxants: Increased drowsiness",
        effect = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.FATIGUE then
                local current = stats:get(CharacterStat.FATIGUE) or 0
                stats:set(CharacterStat.FATIGUE, math.min(0.7, current + 0.1))
            end
        end,
    },
    {
        drugs = {"charcoal", "antibiotic"},
        severity = "warning",
        message = "Activated Charcoal absorbs antibiotics - reduced effectiveness!",
        effect = nil, -- Just a warning, charcoal blocks absorption
    },
    {
        drugs = {"epinephrine", "beta blocker"},
        severity = "warning",
        message = "Epinephrine + Beta Blockers: Reduced epinephrine effectiveness!",
        effect = nil,
    },

    -- =========================================
    -- MILD INTERACTIONS (Info only)
    -- =========================================
    {
        drugs = {"cough suppressant", "cold flu"},
        severity = "mild",
        message = "Multiple cold medications - watch for drowsiness",
        effect = nil,
    },
    {
        drugs = {"anti-nausea", "anti-diarrheal"},
        severity = "mild",
        message = "Multiple GI medications - watch for constipation",
        effect = nil,
    },
    {
        drugs = {"antibiotic", "antifungal"},
        severity = "mild",
        message = "Antibiotic + Antifungal: Minor GI upset possible",
        effect = nil,
    },
    {
        drugs = {"electrolyte", "rehydration"},
        severity = "mild",
        message = "Multiple rehydration solutions - excessive electrolytes",
        effect = nil,
    },
}

-- Map medication names to interaction categories
EHR.Medication.DrugCategories = {
    -- Tier 0 - Vanilla
    ["Antibiotics"] = "antibiotic",
    ["Painkillers"] = "painkiller",
    ["Homemade Painkillers"] = "painkiller",
    ["Caffeine Pills"] = "stimulant",
    ["Homemade Sleeping Pills"] = "sleep aid",
    ["Antidepressants"] = "antidepressant",
    ["Beta Blockers"] = "beta blocker",

    -- Tier 1 - OTC
    ["Cold & Flu Tablets"] = "cold flu",
    ["Cough Syrup"] = "cough suppressant",
    ["Homemade Cough Syrup"] = "cough suppressant",
    ["Electrolyte Powder"] = "electrolyte",
    ["Bronchodilator Inhaler"] = "bronchodilator",
    ["Anti-Nausea Tablets"] = "anti-nausea",
    ["Anti-Inflammatory Pills"] = "anti-inflammatory",
    ["Anti-Diarrheal Tablets"] = "anti-diarrheal",
    ["Muscle Relaxants"] = "muscle relaxant",
    ["Homemade Muscle Relaxant"] = "muscle relaxant",
    ["Nitric Oxide Boosters"] = "stimulant",
    ["Combat Stimulants"] = "stimulant",
    ["Cough Suppressant"] = "cough suppressant",
    ["Antiseptic Cream"] = "antiseptic",

    -- Tier 2 - Prescription
    ["Antiviral Capsules"] = "antiviral",
    ["Prescription Antibiotics"] = "antibiotic",
    ["Antifungal Tablets"] = "antifungal",
    ["Activated Charcoal"] = "charcoal",
    ["Homemade Activated Charcoal"] = "charcoal",
    ["Antiparasitic Pills"] = "antiparasitic",
    ["Topical Permethrin"] = "antiparasitic",
    ["Oral Rehydration Kit"] = "rehydration",
    ["Antipsychotics"] = "antipsychotic",
    ["Dual Orexin Receptor"] = "sleep aid",
    ["Tetanus Antitoxin"] = "antitoxin",
    ["TB Antibiotics (Isoniazid)"] = "tb antibiotics",
    ["Antibiotic Ointment"] = "antibiotic",
    ["Broad Spectrum Antibiotics"] = "antibiotic",

    -- Tier 3 - Clinical
    ["Corticosteroid Injection"] = "corticosteroid",
    ["Respiratory Support Kit"] = "respiratory support",
    ["IV Antibiotics"] = "iv antibiotic",
    ["IV Metronidazole"] = "iv antibiotic",
    ["IV Amphotericin B"] = "iv antifungal",
    ["Chelation Therapy Kit"] = "chelation",
    ["Albendazole Injection"] = "antiparasitic",
    ["IV Ciprofloxacin"] = "iv antibiotic",
    ["Tetanus Immunoglobulin"] = "immunoglobulin",
    ["Rifampicin Combination Pack"] = "rifampicin",
    ["IV Vancomycin"] = "iv antibiotic",
    ["Emergency Sepsis Kit"] = "iv antibiotic",

    -- Special
    ["Epinephrine Auto-Injector"] = "epinephrine",
}

-- ============================================
-- ACTIVE MEDICATION TRACKING
-- ============================================

function EHR.Medication.GetMedicationData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData.EHR_Medication then
        modData.EHR_Medication = {
            activeTreatments = {},  -- { diseaseId = { medId, startTime, cureTimeHours } }
            activeSideEffects = {}, -- { effectId = { startTime, duration } }
            activeDoses = {},       -- { medId = { lastDoseTime, doseCount, totalDosesNeeded, intervalHours } }
            activeGeneralEffects = {},
        }
    end
    -- Migration: ensure medication tracking tables exist on older saves / hook-created data.
    if not modData.EHR_Medication.activeTreatments then
        modData.EHR_Medication.activeTreatments = {}
    end
    if not modData.EHR_Medication.activeSideEffects then
        modData.EHR_Medication.activeSideEffects = {}
    end
    if not modData.EHR_Medication.activeDoses then
        modData.EHR_Medication.activeDoses = {}
    end
    if not modData.EHR_Medication.activeGeneralEffects then
        modData.EHR_Medication.activeGeneralEffects = {}
    end
    return modData.EHR_Medication
end

function EHR.Medication.GetLastChanceOverallHealth(player)
    if not player or not player.getBodyDamage then return nil end

    local bodyDamage = nil
    local health = nil
    local ok = pcall(function()
        bodyDamage = player:getBodyDamage()
        if bodyDamage and bodyDamage.getOverallBodyHealth then
            health = tonumber(bodyDamage:getOverallBodyHealth())
        end
    end)
    if not ok or not bodyDamage or health == nil then return nil end
    return math.max(0, math.min(100, health)), bodyDamage
end

-- Overall health is recalculated from weighted BodyPart.health every BodyDamage update.
-- Scale every existing health deficit by the same factor, then set the aggregate
-- value to the exact target. BodyPart:SetHealth only changes the numeric health
-- field; wound flags, wound timers, bandages and bleeding are deliberately untouched.
function EHR.Medication.RestoreLastChanceOverallHealth(player, targetHealth)
    local currentHealth, bodyDamage = EHR.Medication.GetLastChanceOverallHealth(player)
    targetHealth = math.max(0, math.min(100, tonumber(targetHealth) or 75))
    if currentHealth == nil or not bodyDamage then return false, currentHealth end
    if currentHealth >= targetHealth then return true, currentHealth, true end
    if not bodyDamage.getBodyParts or not bodyDamage.calculateOverallHealth then
        return false, currentHealth
    end

    local snapshot = {}
    local targetReached = false
    local restoredHealth = nil
    local parts = nil
    local ok, err = pcall(function()
        parts = bodyDamage:getBodyParts()
        if not parts or not parts.size or not parts.get then
            error("body-part collection unavailable")
        end

        local count = tonumber(parts:size()) or 0
        if count <= 0 then error("no body parts") end
        for i = 0, count - 1 do
            local part = parts:get(i)
            if not part or not part.getHealth or not part.SetHealth then
                error("body-part health API unavailable")
            end
            snapshot[#snapshot + 1] = {
                part = part,
                health = math.max(0, math.min(100, tonumber(part:getHealth()) or 0)),
            }
        end

        local function applyDeficitFactor(factor)
            factor = math.max(0, math.min(1, factor))
            for _, entry in ipairs(snapshot) do
                local deficit = 100 - entry.health
                entry.part:SetHealth(100 - (deficit * factor))
            end
            bodyDamage:calculateOverallHealth()
            return tonumber(bodyDamage:getOverallBodyHealth()) or 0
        end

        -- factor 0 is the maximum reachable aggregate without touching wound state;
        -- factor 1 is the original body-part health layout.
        local maxReachable = applyDeficitFactor(0)
        if maxReachable < targetHealth - 0.1 then
            error(string.format(
                "target %.2f is unreachable (maximum %.2f)",
                targetHealth,
                maxReachable
            ))
        end

        local low = 0
        local high = 1
        for _ = 1, 16 do
            local mid = (low + high) * 0.5
            local observed = applyDeficitFactor(mid)
            if observed >= targetHealth then
                low = mid
            else
                high = mid
            end
        end
        local calculatedHealth = applyDeficitFactor(low)
        targetReached = calculatedHealth >= targetHealth - 0.1
        if not targetReached then
            error(string.format(
                "target %.2f was not reached after scaling (observed %.2f)",
                targetHealth,
                calculatedHealth
            ))
        end

        -- Keep the immediate display exact. On the next vanilla recalculation the
        -- proportional body-part layout remains at the same target (unless an
        -- independent pill/temperature damage source makes 75 unreachable).
        if bodyDamage.setOverallBodyHealth then
            bodyDamage:setOverallBodyHealth(targetHealth)
        end
        restoredHealth = bodyDamage.getOverallBodyHealth
            and tonumber(bodyDamage:getOverallBodyHealth()) or nil
        if restoredHealth == nil or restoredHealth ~= restoredHealth
                or restoredHealth == math.huge or restoredHealth == -math.huge
                or restoredHealth < targetHealth - 0.1 then
            error("final aggregate health verification failed")
        end
        if EHR.Blood and EHR.Blood.AcceptCurrentHealth then
            if EHR.Blood.AcceptCurrentHealth(player) ~= true then
                error("blood healing-lock baseline was not accepted")
            end
        end
    end)

    if not ok then
        for _, entry in ipairs(snapshot) do
            pcall(function() entry.part:SetHealth(entry.health) end)
        end
        if bodyDamage and bodyDamage.calculateOverallHealth then
            pcall(function() bodyDamage:calculateOverallHealth() end)
        end
        if bodyDamage and bodyDamage.setOverallBodyHealth and currentHealth ~= nil then
            pcall(function() bodyDamage:setOverallBodyHealth(currentHealth) end)
        end
        EHR.Log("Last-chance epinephrine health restore failed: " .. tostring(err))
        return false, currentHealth
    end

    return true, restoredHealth, targetReached and restoredHealth >= targetHealth - 0.1
end

function EHR.Medication.CaptureLastChanceBodyPartHealth(player)
    if not player or not player.getBodyDamage then return nil end

    local snapshot = nil
    local ok = pcall(function()
        local bodyDamage = player:getBodyDamage()
        local parts = bodyDamage and bodyDamage:getBodyParts() or nil
        if not parts or not parts.size or not parts.get then return end

        local count = tonumber(parts:size()) or 0
        if count <= 0 then return end
        local values = {
            parts = {},
            count = count,
            overallHealth = tonumber(bodyDamage:getOverallBodyHealth()),
        }
        for i = 0, count - 1 do
            local part = parts:get(i)
            local partType = part and part.getType and part:getType() or nil
            local partName = partType ~= nil and tostring(partType) or nil
            local health = part and part.getHealth and tonumber(part:getHealth()) or nil
            if not partName or partName == "" or health == nil or values.parts[partName] ~= nil then
                error("invalid body-part snapshot source")
            end
            values.parts[partName] = { health = math.max(0, math.min(100, health)) }
        end
        snapshot = values
    end)
    if not ok then return nil end
    return snapshot
end

-- The server sends its exact post-rescue BodyPart values to the owning client.
-- Validate the complete named map before mutating anything, then apply atomically;
-- this avoids independently scaling a stale client-side wound snapshot in MP.
function EHR.Medication.ApplyLastChanceBodyPartHealth(player, snapshot, targetHealth)
    if not player or type(snapshot) ~= "table" or type(snapshot.parts) ~= "table"
            or not player.getBodyDamage then return false end

    local bodyDamage = nil
    local originalOverall = nil
    local originals = {}
    local validated = {}
    local okValidate = pcall(function()
        bodyDamage = player:getBodyDamage()
        originalOverall = bodyDamage and bodyDamage.getOverallBodyHealth
            and tonumber(bodyDamage:getOverallBodyHealth()) or nil
        local parts = bodyDamage and bodyDamage:getBodyParts() or nil
        if not parts or not parts.size or not parts.get then error("body-part collection unavailable") end

        local count = tonumber(parts:size()) or 0
        if count <= 0 then error("no body parts") end
        if math.floor(tonumber(snapshot.count) or -1) ~= count then
            error("body-part snapshot count mismatch")
        end
        local packetCount = 0
        for _, _ in pairs(snapshot.parts) do packetCount = packetCount + 1 end
        if packetCount ~= count then error("body-part snapshot map is incomplete") end

        for i = 0, count - 1 do
            local part = parts:get(i)
            local partType = part and part.getType and part:getType() or nil
            local partName = partType ~= nil and tostring(partType) or nil
            local record = partName and snapshot.parts[partName] or nil
            local health = type(record) == "table" and tonumber(record.health) or nil
            if not part or not part.getHealth or not part.SetHealth or health == nil
                    or health ~= health or health == math.huge or health == -math.huge then
                error("invalid body-part snapshot")
            end
            originals[#originals + 1] = { part = part, health = tonumber(part:getHealth()) or 0 }
            validated[#validated + 1] = { part = part, health = math.max(0, math.min(100, health)) }
        end
    end)
    if not okValidate or not bodyDamage then return false end

    local okApply = pcall(function()
        for _, entry in ipairs(validated) do
            entry.part:SetHealth(entry.health)
        end
        if bodyDamage.calculateOverallHealth then bodyDamage:calculateOverallHealth() end
        local expectedOverall = tonumber(snapshot.overallHealth) or tonumber(targetHealth)
        if expectedOverall ~= nil and (expectedOverall ~= expectedOverall
                or expectedOverall == math.huge or expectedOverall == -math.huge) then
            error("invalid body-part aggregate snapshot")
        end
        if bodyDamage.setOverallBodyHealth and expectedOverall then
            expectedOverall = math.max(0, math.min(100, expectedOverall))
            bodyDamage:setOverallBodyHealth(expectedOverall)
            local observed = bodyDamage.getOverallBodyHealth and tonumber(bodyDamage:getOverallBodyHealth()) or nil
            if observed == nil or math.abs(observed - expectedOverall) > 0.1 then
                error("body-part snapshot aggregate mismatch")
            end
        end
        if EHR.Blood and EHR.Blood.AcceptCurrentHealth then
            if EHR.Blood.AcceptCurrentHealth(player) ~= true then
                error("blood healing-lock baseline was not accepted")
            end
        end
    end)
    if okApply then return true end

    for _, entry in ipairs(originals) do
        pcall(function() entry.part:SetHealth(entry.health) end)
    end
    if bodyDamage.calculateOverallHealth then
        pcall(function() bodyDamage:calculateOverallHealth() end)
    end
    if originalOverall ~= nil and originalOverall == originalOverall
            and originalOverall ~= math.huge and originalOverall ~= -math.huge
            and bodyDamage.setOverallBodyHealth then
        pcall(function() bodyDamage:setOverallBodyHealth(originalOverall) end)
    end
    return false
end

-- ============================================
-- MEDICATION APPLICATION
-- ============================================

function EHR.Medication.GetDoseCapacityFromDelta(useDelta)
    if not useDelta or useDelta <= 0 then return 1 end
    return math.max(1, math.floor((1.0 / useDelta) + 0.5))
end

function EHR.Medication.GetItemDoseInfo(item)
    if not item or not item.getUseDelta then return nil end
    if not item.getCurrentUsesFloat or not item.setUsedDelta then return nil end

    if instanceof then
        local okType, isDrainable = pcall(function() return instanceof(item, "DrainableComboItem") end)
        if okType and not isDrainable then return nil end
    end

    local okDelta, useDelta = pcall(function() return item:getUseDelta() end)
    if not okDelta or not useDelta or useDelta <= 0 then return nil end

    local currentUsesFloat = 1.0
    local okCurrent, value = pcall(function() return item:getCurrentUsesFloat() end)
    if okCurrent and value then
        currentUsesFloat = value
    end

    local maxDoses = EHR.Medication.GetDoseCapacityFromDelta(useDelta)
    currentUsesFloat = math.max(0, math.min(1.0, currentUsesFloat))
    -- Drainable values are floating-point fills, not exact integer counters.
    -- Round to the nearest dose so a full 1/6 package is six doses rather than
    -- five and legacy partial packages remain usable after the precision fix.
    local remaining = math.floor((currentUsesFloat / useDelta) + 0.5)
    remaining = math.max(0, math.min(maxDoses, remaining))

    return {
        useDelta = useDelta,
        usedDelta = currentUsesFloat,
        currentUsesFloat = currentUsesFloat,
        maxDoses = maxDoses,
        remainingDoses = remaining,
    }
end

--[[
    Consume one dose of a drainable item, or remove a single-use item.
    Handles both multi-use (drainable) and single-use items.
    @param player (IsoPlayer)
    @param item (InventoryItem)
    @param inventory (ItemContainer) - Player's inventory
]]--
function EHR.Medication.ConsumeOneDose(player, item, inventory)
    if not item or not inventory then return false, "invalid" end
    local itemContainer = inventory
    if item.getContainer then
        local ok, container = pcall(function() return item:getContainer() end)
        if ok and container then
            itemContainer = container
        end
    end

    local itemID = nil
    if item.getID then
        local ok, id = pcall(function() return item:getID() end)
        if ok then
            itemID = id
        end
    end

    local useDelta = 0
    if item.getUseDelta then
        local ok, delta = pcall(function() return item:getUseDelta() end)
        if ok and delta then
            useDelta = delta
        end
    end

    -- Drainable medications store remaining fill as current uses / setUsedDelta.
    local canUseDose = useDelta > 0 and item.setUsedDelta

    if canUseDose then
        local doseInfo = EHR.Medication.GetItemDoseInfo(item)
        local remainingDoses = doseInfo and doseInfo.remainingDoses or 0

        if remainingDoses > 1 then
            local newRemaining = remainingDoses - 1
            -- Subtract from the actual fill. Reconstructing fill from an
            -- already-rounded dose count could consume two doses at once on
            -- old items whose UseDelta was 0.1667.
            local newUsed = (tonumber(doseInfo.currentUsesFloat) or 0) - useDelta
            newUsed = math.max(0, math.min(1.0, newUsed))

            local okSet = pcall(function() item:setUsedDelta(newUsed) end)
            if okSet then
                if isClient() and itemID then
                    sendClientCommand(player, "EHR", "UpdateItemDelta", {itemID = itemID, usedDelta = newUsed})
                elseif isServer and isServer() and sendItemStats then
                    -- Server-authoritative EHR actions do not pass through a
                    -- vanilla drainable timed action. Explicitly replicate the
                    -- new fill level so MP clients do not keep a stale stack.
                    pcall(function() sendItemStats(item) end)
                end
                return true, "dose", useDelta, newUsed, newRemaining
            end
        end
    end

    local okRemove = pcall(function() itemContainer:Remove(item) end)
    if not okRemove then return false, "remove_failed" end
    if itemID ~= nil and inventory.containsID then
        local okContains, stillPresent = pcall(function() return inventory:containsID(itemID) end)
        if okContains and stillPresent == true then
            return false, "remove_unconfirmed"
        end
        -- Remove() completed synchronously. If an optional verification helper
        -- itself is unavailable, trust the successful mutation rather than
        -- reporting failure after the item is already gone.
    end
    if isClient() and itemID then
        sendClientCommand(player, "EHR", "RemoveItem", {itemID = itemID})
    elseif isServer and isServer() and sendRemoveItemFromContainer then
        -- Removing the final dose only from the server container leaves a
        -- ghost item on the owning client. Mirror the vanilla server helpers.
        pcall(function() sendRemoveItemFromContainer(itemContainer, item) end)
    end

    return true, "removed", useDelta, 1.0
end

-- Strict, single-use emergency medications reserve their item before applying
-- irreversible effects. The authoritative Lua call is synchronous, so no other
-- inventory operation can interleave between this removal and commit/rollback.
function EHR.Medication.ReserveSingleUseMedication(player, item, inventory)
    if not player or not item or not inventory then return nil end

    -- InventoryItem itself exposes getUseDelta() and B42 initializes that field
    -- to 0.03125 even for ordinary base:normal items.  A positive useDelta is
    -- therefore not proof that an item is drainable.  Reserve only true
    -- single-use items and let ConsumeOneDose handle DrainableComboItem doses.
    local isDrainable = false
    local drainableTypeKnown = false
    if instanceof then
        local okType, value = pcall(function()
            return instanceof(item, "DrainableComboItem")
        end)
        if okType then
            isDrainable = value == true
            drainableTypeKnown = true
        end
    end
    if not drainableTypeKnown and item.IsDrainable then
        local okType, value = pcall(function() return item:IsDrainable() end)
        if okType then
            isDrainable = value == true
            drainableTypeKnown = true
        end
    end
    if not drainableTypeKnown or isDrainable then return nil end

    local container = inventory
    if item.getContainer then
        local okContainer, value = pcall(function() return item:getContainer() end)
        if okContainer and value then container = value end
    end
    if not container or not container.Remove or not container.AddItem then return nil end

    local itemID = nil
    if item.getID then
        local okID, value = pcall(function() return item:getID() end)
        if okID then itemID = value end
    end
    if itemID ~= nil and inventory.containsID then
        local okPresent, present = pcall(function() return inventory:containsID(itemID) end)
        if not okPresent or present ~= true then return nil end
    end

    local okRemove = pcall(function() container:Remove(item) end)
    if not okRemove then return nil end
    if itemID ~= nil and inventory.containsID then
        local okPresent, present = pcall(function() return inventory:containsID(itemID) end)
        if okPresent and present == true then return nil end
        -- As above, a failed optional post-check must not strand a successfully
        -- reserved item in a no-effect/no-rollback state.
    end

    return {
        player = player,
        item = item,
        inventory = inventory,
        container = container,
        itemID = itemID,
    }
end

function EHR.Medication.RollbackReservedMedication(reservation)
    if type(reservation) ~= "table" or not reservation.item or not reservation.container then return false end
    local okAdd = pcall(function() reservation.container:AddItem(reservation.item) end)
    if not okAdd then return false end
    if reservation.itemID ~= nil and reservation.inventory and reservation.inventory.containsID then
        local okPresent, present = pcall(function()
            return reservation.inventory:containsID(reservation.itemID)
        end)
        return okPresent and present == true
    end
    return true
end

function EHR.Medication.CommitReservedMedication(reservation)
    if type(reservation) ~= "table" or not reservation.item or not reservation.container then return false end
    if isServer and isServer() and sendRemoveItemFromContainer then
        local okSync = pcall(function()
            sendRemoveItemFromContainer(reservation.container, reservation.item)
        end)
        if not okSync then
            EHR.Log("WARNING: Reserved medication removal could not be replicated immediately")
        end
    elseif isClient and isClient() and sendClientCommand and reservation.itemID ~= nil then
        pcall(function()
            sendClientCommand(reservation.player, "EHR", "RemoveItem", { itemID = reservation.itemID })
        end)
    end
    return true
end

local function EHR_MedicationBodyPartHasActiveWound(bodyPart)
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

function EHR.Medication.HasActiveWound(player)
    if not player or not player.getBodyDamage then return false end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return false end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return false end

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local bodyPart = partType and bodyDamage:getBodyPart(partType) or nil
        if EHR_MedicationBodyPartHasActiveWound(bodyPart) then
            return true
        end
    end

    return false
end

local function EHR_MedicationHasActiveGeneralEffect(player, effectKey)
    if not player or not effectKey then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local effect = medTracking
        and medTracking.activeGeneralEffects
        and medTracking.activeGeneralEffects[effectKey]
    if type(effect) ~= "table" then return false end

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local endTime = tonumber(effect.endTime) or currentHour

    return currentHour < endTime
end

function EHR.Medication.ShouldConsumeActiveDoseWithoutTreatment(player, medData, itemFullType)
    if not player or not medData or medData.consumeWhileDoseActive ~= true then return false end
    if not EHR.Medication.GetDoseStatus then return false end

    local ok, status = pcall(EHR.Medication.GetDoseStatus, player, itemFullType)
    if not ok or not status then return false end

    local doseDue = not status.treatmentComplete
        and (status.isOverdue == true or (tonumber(status.hoursUntilNextDose) or 0) <= 0)

    return status.isDoseActive == true and not doseDue
end

function EHR.Medication.CanUseMedication(player, item, supplyPlayer)
    if not player or not item then return false, "Invalid parameters" end

    -- When one player treats another, disease/effect checks belong to the
    -- patient while required supplies belong to the practitioner.
    supplyPlayer = supplyPlayer or player

    local itemFullType = item:getFullType()
    local medData = EHR.Medication.Database[itemFullType]

    if not medData then
        return false, "Not a recognized medication"
    end

    if medData.requiresActiveWound and not EHR.Medication.HasActiveWound(player) then
        return false, "Requires an active wound"
    end

    if medData.staminaLock and EHR_MedicationHasActiveGeneralEffect(player, "staminaLock") then
        return false, medData.activeDoseMessage or "The current dose is still active"
    end

    if medData.fatigueBlock and EHR_MedicationHasActiveGeneralEffect(player, "fatigueBlock") then
        return false, medData.activeDoseMessage or "The current dose is still active"
    end

    if medData.combatStimulants and EHR_MedicationHasActiveGeneralEffect(player, "combatStimulants") then
        return false, medData.activeDoseMessage or "The current dose is still active"
    end

    if medData.lastChanceEpinephrine then
        if EHR_MedicationHasActiveGeneralEffect(player, "lastChanceEpinephrine") then
            return false, medData.activeDoseMessage or "The current dose is still active"
        end
        if EHR.Medication.GetLastChanceOverallHealth(player) == nil then
            return false, "Overall health data is unavailable"
        end
    end

    if medData.warmingSupport and EHR_MedicationHasActiveGeneralEffect(player, "warmingPack") then
        return false, medData.activeDoseMessage or "A warming pack is already active"
    end

    if medData.sleepAid and EHR_MedicationHasActiveGeneralEffect(player, "sleepAid")
            and EHR.Medication.GetDoseStatus then
        -- The general sleepAid flag is shared by antidepressants, sleeping
        -- pills and other sleep supports. It means the patient may sleep; it
        -- does not mean this exact medication was already administered.
        local ok, status = pcall(EHR.Medication.GetDoseStatus, player, itemFullType)
        local doseDue = ok and status and not status.treatmentComplete
            and (status.isOverdue == true or (tonumber(status.hoursUntilNextDose) or 0) <= 0)
        if ok and status and status.isDoseActive and not doseDue then
            return false, medData.activeDoseMessage or "A sleep-aid dose is still active"
        end
    end

    if medData.blockWhileDoseActive and EHR.Medication.GetDoseStatus then
        local ok, status = pcall(EHR.Medication.GetDoseStatus, player, itemFullType)
        local doseDue = ok and status and not status.treatmentComplete
            and (status.isOverdue == true or (tonumber(status.hoursUntilNextDose) or 0) <= 0)
        if ok and status and status.isDoseActive and not doseDue then
            if medData.consumeWhileDoseActive == true then
                return true, nil
            end
            return false, medData.activeDoseMessage or "The current dose is still active"
        end
    end

    -- Check for required supplies
    if medData.requiresIVKit then
        local inventory = supplyPlayer:getInventory()
        if not inventory:containsTypeRecurse("ExtensiveHealth.IVKit") then
            return false, "Requires IV Administration Kit"
        end
    end

    if medData.requiresSyringe then
        local inventory = supplyPlayer:getInventory()
        if not inventory:containsTypeRecurse("ExtensiveHealth.Syringe") then
            return false, "Requires Sterile Syringe"
        end
    end

    -- Allow using medication even without the disease (preventative use, symptom relief, etc.)
    return true, nil
end

function EHR.Medication.RequestUseMedication(player, item)
    if not player or not item then return false end

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR", "UseMedication", {
            itemID = item:getID(),
            itemFullType = item:getFullType(),
        })
        return true
    end

    return EHR.Medication.UseMedication(player, item)
end

-- Vanilla antibiotics are intentionally weaker than EHR prescription drugs,
-- but Wound Infection V2 still defines a direct one-stage treatment per dose.
-- Its legacy client hook cannot authoritatively change the condition in MP, so
-- both EHR and already-consumed vanilla action paths call this shared helper.
function EHR.Medication.ApplyVanillaAntibioticWoundEffect(player, itemFullType)
    if not player or itemFullType ~= "Base.Antibiotics" then return false end
    if not (EHR.WoundInfection and EHR.WoundInfection.OnTakeAntibiotics) then return false end

    local hasInfection = false
    if EHR.WoundInfection.HasAnyInfection then
        local ok, active = pcall(EHR.WoundInfection.HasAnyInfection, player)
        hasInfection = ok and active == true
    elseif EHR.Medication.IsModuleDiseaseActive then
        local ok, active = pcall(EHR.Medication.IsModuleDiseaseActive, player, "wound_infection")
        hasInfection = ok and active == true
    end
    if not hasInfection then return false end

    local ok, err = pcall(EHR.WoundInfection.OnTakeAntibiotics, player)
    if not ok then
        EHR.Log("WARNING: Vanilla antibiotic wound treatment failed: " .. tostring(err))
        return false
    end
    return true
end

function EHR.Medication.UseConsumedMedication(player, itemFullType, administeringPlayer)
    if not player or not itemFullType then return false end

    -- Self-use awards the patient as before. Remote vanilla-pill administration
    -- can pass the doctor so the same procedure does not grant First Aid XP to
    -- the person receiving the dose.
    local xpOwner = administeringPlayer or player

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR", "UseConsumedMedication", {
            itemFullType = tostring(itemFullType),
        })
        return true
    end

    local medData = EHR.Medication.Database and EHR.Medication.Database[itemFullType]
    if not medData then return false end

    local tier = medData.tier or 0
    local tierEffects = EHR.Medication.TierEffectiveness[tier] or EHR.Medication.TierEffectiveness[0]
    local medTracking = EHR.Medication.GetMedicationData(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData(player)
    local medKey = itemFullType
    local canAdvanceDose = true

    if EHR.Medication.ShouldConsumeActiveDoseWithoutTreatment(player, medData, itemFullType) then
        if medData.activeDoseMessage and player.isLocalPlayer and player:isLocalPlayer() then
            EHR.Locale.Say(player, medData.activeDoseMessage)
        end
        EHRMedicationRequestSync(player)
        EHR.Log("Consumed food medication during active dose without treatment progress: " .. tostring(itemFullType))
        return true
    end

    if medData.blockWhileDoseActive and EHR.Medication.GetDoseStatus then
        local ok, status = pcall(EHR.Medication.GetDoseStatus, player, itemFullType)
        local doseDue = ok and status and not status.treatmentComplete
            and (status.isOverdue == true or (tonumber(status.hoursUntilNextDose) or 0) <= 0)
        if ok and status and status.isDoseActive and not doseDue then
            if medData.activeDoseMessage and player.isLocalPlayer and player:isLocalPlayer() then
                EHR.Locale.Say(player, medData.activeDoseMessage)
            end
            EHRMedicationRequestSync(player)
            EHR.Log("Consumed blocked food medication during active dose without treatment progress: " .. tostring(itemFullType))
            return true
        end
    end

    if medData.usageMessage and player.isLocalPlayer and player:isLocalPlayer() then
        EHR.Locale.Say(player, medData.usageMessage)
    end

    local treatedAny = false
    if canAdvanceDose then
        local moduleTreatmentApplied = {}

        if diseaseData and diseaseData.active and medData.preventionOnly ~= true then
            for _, diseaseId in ipairs(medData.treats or {}) do
                if diseaseData.active[diseaseId] then
                    EHR.Medication.ApplyTreatment(player, diseaseId, medData, tierEffects, medKey)
                    treatedAny = true
                end
            end
        end

        if EHR.Medication.ApplyModuleTreatment then
            for _, diseaseId in ipairs(medData.treats or {}) do
                if EHR.Medication.ApplyModuleTreatment(player, diseaseId, medData, tierEffects, medKey) then
                    moduleTreatmentApplied[diseaseId] = true
                    treatedAny = true
                end
            end
        end

        if EHR.Medication.ApplyModuleSymptomTreatment then
            for _, diseaseId in ipairs(medData.treats or {}) do
                if not moduleTreatmentApplied[diseaseId]
                    and EHR.Medication.ApplyModuleSymptomTreatment(player, diseaseId, medData, tierEffects, medKey) then
                    treatedAny = true
                end
            end
        end

        local appliedVanillaWoundEffect = EHR.Medication.ApplyVanillaAntibioticWoundEffect
            and EHR.Medication.ApplyVanillaAntibioticWoundEffect(player, itemFullType)

        if treatedAny and medData.hydrationSupport and EHR.Medication.StartHydrationSupport then
            EHR.Medication.StartHydrationSupport(player, medData)
        end

        if not treatedAny then
            if medData.appliesWithoutDisease and EHR.Medication.ApplyGeneralSymptomRelief then
                EHR.Medication.ApplyGeneralSymptomRelief(player, medData)
            end
            EHR.Medication.TrackDoseOnly(player, medData, medKey)
        end
        if appliedVanillaWoundEffect then treatedAny = true end
    end

    if medData.stressSupport and EHR.Medication.StartStressSupport then
        EHR.Medication.StartStressSupport(player, medData)
    end
    if medData.sleepAid and EHR.Medication.StartSleepAid then
        EHR.Medication.StartSleepAid(player, medData)
    end

    EHR.Medication.CheckAndApplyInteractions(player)
    if EHR.Medication.RefreshImmunityForAntibiotic then
        EHR.Medication.RefreshImmunityForAntibiotic(player, itemFullType)
    end

    if EHR.SkillXP and EHR.SkillXP.OnMedicationTaken then
        EHR.SkillXP.OnMedicationTaken(xpOwner, {
            tier = tier,
            displayName = medData.displayName,
            medId = medKey,
            treatedDisease = treatedAny,
        })
    end

    if treatedAny and EHR.SkillXP and EHR.SkillXP.OnTreatmentDose then
        EHR.SkillXP.OnTreatmentDose(xpOwner, "disease", true)
    end

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR", "RequestSync", {})
    end

    EHR.Log("Applied consumed medication: " .. tostring(itemFullType) .. " (treated disease: " .. tostring(treatedAny) .. ")")
    return true
end

function EHR.Medication.UseMedication(player, item, administeringPlayer)
    if not player or not item then return false end

    -- In MP, medication effects and item consumption must be server-authoritative.
    -- Client-side callers still use this public function, but it becomes a request.
    if isClient and isClient() and sendClientCommand then
        return EHR.Medication.RequestUseMedication(player, item)
    end

    local inventoryOwner = administeringPlayer or player
    local canUse, reason = EHR.Medication.CanUseMedication(player, item, inventoryOwner)
    if not canUse then
        if player.isLocalPlayer and player:isLocalPlayer() then
            EHR.Locale.Say(player, reason)
        end
        return false
    end

    local itemFullType = item:getFullType()
    local medData = EHR.Medication.Database[itemFullType]
    local tier = medData.tier
    local tierEffects = EHR.Medication.TierEffectiveness[tier]

    local medTracking = EHR.Medication.GetMedicationData(player)
    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData(player)
    local earlyDoseOverdose = EHR.Medication.GetEarlyDoseOverdoseInfo(player, medData, itemFullType)
    local inventory = inventoryOwner:getInventory()
    local reservedImmediateDose = nil
    local immediateDoseCommitted = false

    if EHR.Medication.ShouldConsumeActiveDoseWithoutTreatment(player, medData, itemFullType) then
        if medData.activeDoseMessage and player.isLocalPlayer and player:isLocalPlayer() then
            EHR.Locale.Say(player, medData.activeDoseMessage)
        end

        local consumed, consumeMode, useDelta, newUsed, remainingDoses = EHR.Medication.ConsumeOneDose(inventoryOwner, item, inventory)
        if consumed and consumeMode == "dose" then
            if remainingDoses == nil and useDelta and useDelta > 0 then
                remainingDoses = math.floor((newUsed / useDelta) + 0.5)
            end
            EHR.Log("Consumed early dose without treatment progress: " .. itemFullType ..
                    " (" .. tostring(remainingDoses) .. " doses remaining)")
        elseif consumed and consumeMode == "removed" then
            EHR.Log("Consumed early final dose without treatment progress: " .. itemFullType)
        else
            EHR.Log("WARNING: Failed to consume early wasted medication item: " .. itemFullType)
            return false
        end

        if isClient() then
            sendClientCommand(player, "EHR", "RequestSync", {})
        end

        return true
    end

    -- Display usage message
    if medData.usageMessage and player.isLocalPlayer and player:isLocalPlayer() then
        EHR.Locale.Say(player, medData.usageMessage)
    end

    -- Consume required supplies (with MP sync)
    -- These are now drainable items with multiple uses
    if medData.requiresIVKit then
        local ivKit = inventory:getFirstTypeRecurse("ExtensiveHealth.IVKit")
        if ivKit then
            EHR.Medication.ConsumeOneDose(inventoryOwner, ivKit, inventory)
        end
    end
    if medData.requiresSyringe then
        local syringe = inventory:getFirstTypeRecurse("ExtensiveHealth.Syringe")
        if syringe then
            EHR.Medication.ConsumeOneDose(inventoryOwner, syringe, inventory)
        end
    end

    -- Strict emergency effects can kill or make a large immediate health change.
    -- Reserve the exact single-use item first, but replicate removal only after
    -- the transactional effect succeeds. A rejected restore returns the same
    -- object to its original container.
    if medData.immediateEffectsMustSucceed then
        reservedImmediateDose = EHR.Medication.ReserveSingleUseMedication(
            inventoryOwner,
            item,
            inventory
        )
        if not reservedImmediateDose then
            EHR.Log("Could not reserve strict emergency medication: " .. itemFullType)
            return false
        end
    end

    -- Apply immediate effects (for emergency medications like Epinephrine)
    if medData.immediateEffects then
        local okImmediate, immediateResult = pcall(medData.immediateEffects, player)
        if not okImmediate then
            if reservedImmediateDose
                    and not EHR.Medication.RollbackReservedMedication(reservedImmediateDose) then
                EHR.Log("ERROR: Failed to restore reserved medication after immediate-effect error: " .. itemFullType)
            end
            EHR.Log("Immediate effects failed for " .. (medData.displayName or itemFullType)
                .. ": " .. tostring(immediateResult))
            return false
        end
        if immediateResult == false
                or (medData.immediateEffectsMustSucceed and immediateResult ~= true) then
            if reservedImmediateDose
                    and not EHR.Medication.RollbackReservedMedication(reservedImmediateDose) then
                EHR.Log("ERROR: Failed to restore reserved medication after rejected immediate effect: " .. itemFullType)
            end
            EHR.Log("Immediate effects did not complete for: " .. (medData.displayName or itemFullType))
            return false
        end
        if reservedImmediateDose then
            immediateDoseCommitted = EHR.Medication.CommitReservedMedication(reservedImmediateDose) == true
            if not immediateDoseCommitted then
                EHR.Medication.RollbackReservedMedication(reservedImmediateDose)
                EHR.Log("Immediate medication reservation could not be committed: " .. itemFullType)
                return false
            end
            reservedImmediateDose = nil
        end
        EHR.Log("Applied immediate effects for: " .. (medData.displayName or itemFullType))
    end

    -- Track whether we treated any disease
    local treatedAny = false

    -- Apply treatment to all matching diseases (if any)
    if diseaseData and diseaseData.active and medData.preventionOnly ~= true then
        for _, diseaseId in ipairs(medData.treats) do
            if diseaseData.active[diseaseId] then
                EHR.Medication.ApplyTreatment(player, diseaseId, medData, tierEffects, itemFullType)
                treatedAny = true
            end
        end
    end

    -- Some EHR conditions are module-backed instead of stored in EHR_Disease.active.
    local moduleTreatmentApplied = {}
    if EHR.Medication.ApplyModuleTreatment then
        for _, diseaseId in ipairs(medData.treats) do
            if EHR.Medication.ApplyModuleTreatment(player, diseaseId, medData, tierEffects, itemFullType) then
                moduleTreatmentApplied[diseaseId] = true
                treatedAny = true
            end
        end
    end

    -- Symptom-only meds still need a disease target so active relief is visible.
    if EHR.Medication.ApplyModuleSymptomTreatment then
        for _, diseaseId in ipairs(medData.treats) do
            if not moduleTreatmentApplied[diseaseId]
                and EHR.Medication.ApplyModuleSymptomTreatment(player, diseaseId, medData, tierEffects, itemFullType) then
                treatedAny = true
            end
        end
    end

    local appliedVanillaWoundEffect = EHR.Medication.ApplyVanillaAntibioticWoundEffect
        and EHR.Medication.ApplyVanillaAntibioticWoundEffect(player, itemFullType)

    if treatedAny and medData.hydrationSupport and EHR.Medication.StartHydrationSupport then
        EHR.Medication.StartHydrationSupport(player, medData)
    end
    if medData.stressSupport and EHR.Medication.StartStressSupport then
        EHR.Medication.StartStressSupport(player, medData)
    end

    if medData.sleepAid and EHR.Medication.StartSleepAid then
        EHR.Medication.StartSleepAid(player, medData)
    end

    -- If no disease was treated, still track the dose for drug interaction purposes
    if not treatedAny then
        if medData.appliesWithoutDisease and EHR.Medication.ApplyGeneralSymptomRelief then
            EHR.Medication.ApplyGeneralSymptomRelief(player, medData)
        end
        EHR.Medication.TrackDoseOnly(player, medData, itemFullType)
    end
    if appliedVanillaWoundEffect then treatedAny = true end

    if earlyDoseOverdose then
        EHR.Medication.ApplyEarlyDoseOverdose(player, earlyDoseOverdose)
    end

    -- Apply side effects for Tier 3 medications and specifically flagged lower-tier drugs.
    if medData.sideEffects and (tier == 3 or medData.alwaysApplySideEffects) then
        for _, effectId in ipairs(medData.sideEffects) do
            EHR.Medication.ApplySideEffect(player, effectId)
        end
    end

    if diseaseId == "tetanus" then
        disease.tetanusHealthCap = nil
        disease.tetanusSevereHealthCap = nil
    end

    -- Check for drug interactions
    EHR.Medication.CheckAndApplyInteractions(player)

    if EHR.Medication.RefreshImmunityForAntibiotic then
        EHR.Medication.RefreshImmunityForAntibiotic(player, itemFullType)
    end

    local consumed, consumeMode, useDelta, newUsed, remainingDoses
    if immediateDoseCommitted then
        consumed, consumeMode, useDelta, newUsed, remainingDoses = true, "removed", 0, 1.0, 0
    else
        consumed, consumeMode, useDelta, newUsed, remainingDoses = EHR.Medication.ConsumeOneDose(
            inventoryOwner,
            item,
            inventory
        )
    end
    if consumed and consumeMode == "dose" then
        if remainingDoses == nil and useDelta and useDelta > 0 then
            remainingDoses = math.floor((newUsed / useDelta) + 0.5)
        end
        EHR.Log("Used dose of: " .. itemFullType .. " (" .. remainingDoses .. " doses remaining)")
    elseif consumed and consumeMode == "removed" then
        EHR.Log("Used last dose of: " .. itemFullType)
    else
        EHR.Log("WARNING: Failed to consume medication item: " .. itemFullType)
    end

    EHR.Log("Used medication: " .. itemFullType .. " (Tier " .. tier .. ", treated disease: " .. tostring(treatedAny) .. ")")

    -- Award First Aid XP for taking medication
    if EHR.SkillXP and EHR.SkillXP.OnMedicationTaken then
        EHR.SkillXP.OnMedicationTaken(inventoryOwner, {
            tier = tier,
            displayName = medData.displayName,
            medId = itemFullType,
            treatedDisease = treatedAny,
        })
    end

    -- Award XP for correct treatment dose
    if treatedAny and EHR.SkillXP and EHR.SkillXP.OnTreatmentDose then
        EHR.SkillXP.OnTreatmentDose(inventoryOwner, "disease", true)
    end

    -- MP: Trigger server sync after medication use
    if isClient() then
        sendClientCommand(player, "EHR", "RequestSync", {})
    end

    return true
end

-- Track a dose without treating a disease (for preventative use / drug interactions)
function EHR.Medication.TrackDoseOnly(player, medData, itemFullType)
    if not player or not medData then return end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    local tierEffects = EHR.Medication.TierEffectiveness[medData.tier or 0]
    local doseTiming = EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
    local medKey = itemFullType or medData.displayName

    if not medTracking.activeDoses[medKey] then
        medTracking.activeDoses[medKey] = {
            lastDoseTime = currentHour,
            doseCount = 1,
            totalDosesNeeded = doseTiming.dosesRequired,
            intervalHours = doseTiming.doseInterval,
            activeHours = doseTiming.activeHours,
            medicationName = medData.displayName,
            tier = medData.tier,
            treatingDisease = nil,  -- No disease being treated
            symptomOnly = doseTiming.symptomOnly,
            requiresDoseCourse = false,
        }
    else
        local doseData = medTracking.activeDoses[medKey]
        doseData.lastDoseTime = currentHour
        doseData.doseCount = (doseData.doseCount or 0) + 1
        doseData.totalDosesNeeded = doseTiming.dosesRequired
        doseData.intervalHours = doseTiming.doseInterval
        doseData.activeHours = doseTiming.activeHours
        doseData.medicationName = medData.displayName
        doseData.tier = medData.tier
        doseData.treatingDisease = nil
        doseData.symptomOnly = doseTiming.symptomOnly
        doseData.requiresDoseCourse = false
    end

    if medData.respiratorySupport and EHR.Medication.StartRespiratorySupport then
        EHR.Medication.StartRespiratorySupport(player, medData)
    end
    if medData.hydrationSupport and EHR.Medication.StartHydrationSupport then
        EHR.Medication.StartHydrationSupport(player, medData)
    end
    if medData.stressSupport and EHR.Medication.StartStressSupport then
        EHR.Medication.StartStressSupport(player, medData)
    end
    if medData.staminaLock and EHR.Medication.StartStaminaLock then
        EHR.Medication.StartStaminaLock(player, medData)
    end
    if medData.fatigueBlock and EHR.Medication.StartFatigueBlock then
        EHR.Medication.StartFatigueBlock(player, medData)
    end
    if medData.combatStimulants and EHR.Medication.StartCombatStimulants then
        EHR.Medication.StartCombatStimulants(player, medData)
    end
    if medData.sleepAid and EHR.Medication.StartSleepAid then
        EHR.Medication.StartSleepAid(player, medData)
    end
    if medData.warmingSupport and EHR.Medication.StartWarmingSupport then
        EHR.Medication.StartWarmingSupport(player, medData)
    end

    if medData.analgesic then
        local trackedDose = medTracking.activeDoses[medKey]
        if type(trackedDose) == "table" then
            local initialPain = 0
            pcall(function()
                local stats = player:getStats()
                if stats and CharacterStat and CharacterStat.PAIN then
                    initialPain = tonumber(stats:get(CharacterStat.PAIN)) or 0
                end
            end)
            trackedDose.analgesicInitialPain = math.max(0, math.min(100, initialPain))
        end
    end

    if medKey == "Base.Pills" then
        if not (EHR.PainkillerAddiction and EHR.PainkillerAddiction.OnPainkillerDose) then
            pcall(function() require "ExtensiveHealth/EHR_PainkillerAddiction" end)
        end
        if EHR.PainkillerAddiction and EHR.PainkillerAddiction.OnPainkillerDose then
            EHR.PainkillerAddiction.OnPainkillerDose(player, currentHour)
        end
    end

    EHR.Log("Tracked dose (no disease): " .. medData.displayName)
end

function EHR.Medication.GetCureTimeHours(medData, diseaseId, tierEffects)
    if not medData then return 72 end

    local cureTimeHours = medData.cureTimeHours or 72
    if diseaseId and medData.diseaseCureTimeHours and medData.diseaseCureTimeHours[diseaseId] then
        cureTimeHours = medData.diseaseCureTimeHours[diseaseId]
    end

    local cureRate = tierEffects and tierEffects.cureRate or 1.0
    if cureRate <= 0 then cureRate = 1.0 end

    return cureTimeHours / cureRate
end

function EHR.Medication.GetTreatmentTimeText(medData)
    if not medData then return nil end

    if medData.treatmentTimeText then
        return medData.treatmentTimeText
    end

    if medData.diseaseCureTimeHours and medData.treats then
        local parts = {}
        for _, diseaseId in ipairs(medData.treats) do
            local hours = medData.diseaseCureTimeHours[diseaseId]
            if hours then
                local diseaseDef = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId]
                local diseaseName = diseaseDef and diseaseDef.name or diseaseId
                table.insert(parts, diseaseName .. ": " .. tostring(hours) .. "h")
            end
        end

        if #parts > 0 then
            return table.concat(parts, ", ")
        end
    end

    if medData.cureTimeHours then
        return tostring(medData.cureTimeHours) .. " hours"
    end

    return nil
end

local function EHR_MedicationIsMusclePart(partType, part)
    local partName = nil

    if BodyPartType and BodyPartType.ToString then
        pcall(function()
            partName = BodyPartType.ToString(partType)
        end)
    end

    if (not partName or partName == "") and part and part.getType and BodyPartType and BodyPartType.ToString then
        pcall(function()
            partName = BodyPartType.ToString(part:getType())
        end)
    end

    partName = tostring(partName or partType or ""):lower()
    return partName:find("arm", 1, true)
        or partName:find("hand", 1, true)
        or partName:find("leg", 1, true)
        or partName:find("foot", 1, true)
        or partName:find("torso", 1, true)
        or partName:find("groin", 1, true)
end

local function EHR_MedicationReducePain(player, reduction)
    if not player or not reduction or reduction <= 0 then return false end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if not stats then return false end

    local changed = false
    if CharacterStat and CharacterStat.PAIN then
        changed = pcall(function()
            local current = stats:get(CharacterStat.PAIN) or 0
            local drop = current > 1.5 and math.max(3, reduction * 35) or math.max(0.05, reduction * 0.45)
            stats:set(CharacterStat.PAIN, math.max(0, current - drop))
        end) or changed
    end

    if (not changed) and stats.getPain and stats.setPain then
        changed = pcall(function()
            local current = stats:getPain() or 0
            local drop = current > 1.5 and math.max(3, reduction * 35) or math.max(0.05, reduction * 0.45)
            stats:setPain(math.max(0, current - drop))
        end) or changed
    end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage and BodyPartType and BodyPartType.ToIndex and BodyPartType.FromIndex then
        local partDrop = math.max(2.0, reduction * 18)
        local partChanged = false
        for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
            local partType = BodyPartType.FromIndex(i)
            local part = partType and bodyDamage:getBodyPart(partType) or nil
            if part and part.getAdditionalPain and part.setAdditionalPain then
                pcall(function()
                    local currentPain = part:getAdditionalPain() or 0
                    if currentPain > 0 then
                        part:setAdditionalPain(math.max(0, currentPain - partDrop))
                        partChanged = true
                    end
                end)
            end
        end

        if partChanged and bodyDamage.DamageUpdate then
            pcall(function() bodyDamage:DamageUpdate() end)
        end
        changed = changed or partChanged
    end

    return changed
end

local function EHR_MedicationAdjustStat(player, stat, delta, minValue, maxValue)
    if not player or not stat or not delta or delta == 0 then return false end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if not stats then return false end

    minValue = minValue or 0
    maxValue = maxValue or 1

    local changed = false
    pcall(function()
        local current = stats:get(stat) or 0
        local nextValue = math.max(minValue, math.min(maxValue, current + delta))
        if math.abs(nextValue - current) > 0.0001 then
            stats:set(stat, nextValue)
            changed = true
        end
    end)

    return changed
end

local function EHR_MedicationGetStat(player, stat)
    if not player or not stat then return nil end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if not stats then return nil end

    local ok, value = pcall(function()
        return stats:get(stat)
    end)

    if ok then
        return value
    end

    return nil
end

local function EHR_MedicationSetStat(player, stat, value)
    if not player or not stat or value == nil then return false end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if not stats then return false end

    local ok = pcall(function()
        stats:set(stat, math.max(0, math.min(1, value)))
    end)

    return ok == true
end

local EHR_MP_FATIGUE_SIDE_EFFECTS = {
    fatigue = true,
    severe_fatigue = true,
    caffeine_crash = true,
    combat_stimulant_crash = true,
    kidney_stress = true,
    liver_stress = true,
    fever = true,
}

local function EHRMedicationHasActiveFatiguePressure(medTracking, currentHour)
    if not medTracking then return false end
    currentHour = currentHour or 0

    local activeSideEffects = medTracking.activeSideEffects or {}
    for effectId, effectData in pairs(activeSideEffects) do
        if EHR_MP_FATIGUE_SIDE_EFFECTS[effectId] and type(effectData) == "table" then
            local sideEffect = EHR.Medication.SideEffects and EHR.Medication.SideEffects[effectId]
            local startTime = tonumber(effectData.startTime) or currentHour
            local duration = tonumber(effectData.duration) or (sideEffect and sideEffect.duration) or 0
            if duration <= 0 or currentHour - startTime < duration then
                return true
            end
        end
    end

    local general = medTracking.activeGeneralEffects or {}
    if type(general.fatigueBlock) == "table" or type(general.combatStimulants) == "table" then
        return true
    end

    return false
end

local function EHRMedicationStartMPFatigueRecovery(player, targetFatigue, durationHours)
    if not player or not EHRMedicationIsMultiplayer() then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end
    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local duration = math.max(1, tonumber(durationHours) or 4)
    local target = math.max(0, math.min(0.80, tonumber(targetFatigue) or 0.35))

    medTracking.activeGeneralEffects.mpFatigueRecovery = {
        startTime = currentHour,
        lastUpdateHour = currentHour,
        endTime = currentHour + duration,
        targetFatigue = target,
        restorePerHour = math.max(0.08, math.min(0.35, (1.0 - target) / duration)),
    }

    return true
end

local function EHRMedicationUpdateMPFatigueRecovery(player, medTracking, currentHour)
    if not player or not medTracking or not EHRMedicationIsMultiplayer() then return end

    local recovery = medTracking.activeGeneralEffects and medTracking.activeGeneralEffects.mpFatigueRecovery
    if type(recovery) ~= "table" then return end

    if EHRMedicationHasActiveFatiguePressure(medTracking, currentHour) then
        recovery.lastUpdateHour = currentHour
        return
    end

    local lastUpdateHour = tonumber(recovery.lastUpdateHour) or currentHour
    local deltaHours = math.max(0, math.min(0.25, currentHour - lastUpdateHour))
    recovery.lastUpdateHour = currentHour

    local currentFatigue = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.FATIGUE)
    local targetFatigue = math.max(0, math.min(0.80, tonumber(recovery.targetFatigue) or 0.35))
    local changed = false

    if currentFatigue and currentFatigue > targetFatigue and deltaHours > 0 then
        local restorePerHour = math.max(0.04, tonumber(recovery.restorePerHour) or 0.16)
        local nextFatigue = math.max(targetFatigue, currentFatigue - (restorePerHour * deltaHours))
        changed = EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, nextFatigue) or changed
    end

    local endTime = tonumber(recovery.endTime) or currentHour
    local refreshedFatigue = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.FATIGUE) or 0
    if currentHour >= endTime or refreshedFatigue <= targetFatigue + 0.01 then
        medTracking.activeGeneralEffects.mpFatigueRecovery = nil
    end

    if changed then
        EHRMedicationRefreshMoodles(player)
    end
end

function EHR.Medication.StartMPFatigueRecovery(player, targetFatigue, durationHours)
    return EHRMedicationStartMPFatigueRecovery(player, targetFatigue, durationHours)
end

local function EHR_MedicationReduceFever(player, reduction, activeHours)
    if not player or not reduction or reduction <= 0 then return false end

    local strongFeverReducer = reduction >= 0.60
    local feverFloor = strongFeverReducer and 37.0 or 37.4
    local drop = strongFeverReducer and 4.0 or math.max(0.10, math.min(1.0, reduction * 0.85))
    local targetDrop = strongFeverReducer and 4.0 or math.min(1.2, reduction * 1.8)
    local changed = false

    if EHR and EHR.BodyTemp then
        local tempData = nil
        if EHR.BodyTemp.GetTemperatureData then
            tempData = EHR.BodyTemp.GetTemperatureData(player)
        end
        if not tempData and EHR.BodyTemp.InitializePlayer then
            tempData = EHR.BodyTemp.InitializePlayer(player)
        end

        if tempData and tempData.bodyTemp then
            local current = tonumber(tempData.bodyTemp) or 37.0
            if current > feverFloor then
                tempData.bodyTemp = math.max(feverFloor, current - drop)
                tempData.targetTemp = math.min(tonumber(tempData.targetTemp) or tempData.bodyTemp, tempData.bodyTemp)
                changed = true
            end

            local diseaseTarget = tonumber(tempData.diseaseTargetTemp)
            if diseaseTarget and diseaseTarget > feverFloor then
                local loweredTarget = math.max(feverFloor, diseaseTarget - targetDrop)
                tempData.diseaseTargetTemp = math.min(diseaseTarget, loweredTarget)
                tempData.targetTemp = math.min(tonumber(tempData.targetTemp) or loweredTarget, loweredTarget)
                local gameTime = getGameTime and getGameTime() or nil
                if gameTime then
                    local hours = tonumber(activeHours) or 0.25
                    tempData.diseaseTargetTempUntil = gameTime:getWorldAgeHours() + math.max(0.25, hours)
                end
                changed = true
            end
        end
    end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if stats and CharacterStat and CharacterStat.TEMPERATURE then
        pcall(function()
            local current = stats:get(CharacterStat.TEMPERATURE) or 37.0
            if current > feverFloor then
                stats:set(CharacterStat.TEMPERATURE, math.max(feverFloor, current - drop))
                changed = true
            end
        end)
    end

    if stats and CharacterStat and CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            if current > 0 then
                stats:set(CharacterStat.SICKNESS, math.max(0, current - (0.08 * reduction)))
                changed = true
            end
        end)
    end

    return changed
end

function EHR.Medication.StartRespiratorySupport(player, medData)
    local support = medData and medData.respiratorySupport
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local currentEndurance = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.ENDURANCE) or 1
    local duration = support.durationHours or medData.effectDurationHours or 0.5
    local immediateBoost = support.immediateBoost or 0
    local boost = support.enduranceBoost or 0.20
    local restorePerHour = support.restorePerHour or 0.85
    if immediateBoost > 0 and currentEndurance < 1 then
        local boostedEndurance = math.min(1, currentEndurance + immediateBoost)
        if EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, boostedEndurance) then
            currentEndurance = boostedEndurance
        end
    end

    local targetEndurance = math.min(1, currentEndurance + boost)

    local existing = medTracking.activeGeneralEffects.bronchodilator
    if type(existing) == "table" and (existing.endTime or 0) > currentHour then
        targetEndurance = math.max(targetEndurance, existing.targetEndurance or 0)
    end

    medTracking.activeGeneralEffects.bronchodilator = {
        startTime = currentHour,
        endTime = currentHour + math.max(0.05, duration),
        lastUpdateHour = currentHour,
        targetEndurance = targetEndurance,
        restorePerHour = restorePerHour,
        medicationName = medData.displayName or "Bronchodilator Inhaler",
    }

    return true
end

function EHR.Medication.StartHydrationSupport(player, medData)
    local support = medData and medData.hydrationSupport
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local currentThirst = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.THIRST) or 0
    local duration = support.durationHours or medData.effectDurationHours or 0.5
    local immediateBoost = support.immediateBoost or 0
    local boost = support.hydrationBoost or 0.20
    local restorePerHour = support.restorePerHour or 0.50

    if immediateBoost > 0 and currentThirst > 0 then
        local boostedThirst = math.max(0, currentThirst - immediateBoost)
        if EHR_MedicationSetStat(player, CharacterStat and CharacterStat.THIRST, boostedThirst) then
            currentThirst = boostedThirst
        end
    end

    local targetThirst = math.max(0, currentThirst - boost)

    local existing = medTracking.activeGeneralEffects.electrolytes
    if type(existing) == "table" and (existing.endTime or 0) > currentHour then
        targetThirst = math.min(targetThirst, existing.targetThirst or 1)
    end

    medTracking.activeGeneralEffects.electrolytes = {
        startTime = currentHour,
        endTime = currentHour + math.max(0.05, duration),
        lastUpdateHour = currentHour,
        targetThirst = targetThirst,
        restorePerHour = restorePerHour,
        medicationName = medData.displayName or "Electrolyte Powder",
    }

    return true
end

function EHR.Medication.StartWarmingSupport(player, medData)
    if not player or not medData or type(medData.warmingSupport) ~= "table" then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end
    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local support = medData.warmingSupport
    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local durationHours = math.max(0.05, tonumber(support.durationHours)
        or tonumber(medData.effectDurationHours) or 2.0)

    medTracking.activeGeneralEffects.warmingPack = {
        startTime = currentHour,
        endTime = currentHour + durationHours,
        lastTemperatureUpdateHour = currentHour,
        targetCoreTemp = math.max(36.0, math.min(37.0, tonumber(support.targetCoreTemp) or 37.0)),
        warmingRatePerHour = math.max(0.1, math.min(4.0, tonumber(support.warmingRatePerHour) or 3.2)),
        medicationName = medData.displayName or "Warming Pack",
    }

    EHRMedicationRequestSync(player)
    return true
end

function EHR.Medication.StartStressSupport(player, medData)
    local support = medData and medData.stressSupport
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local currentStress = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.STRESS) or 0
    local duration = support.durationHours or medData.effectDurationHours or 3
    local targetStress = math.max(0, math.min(1, support.targetStress or 0))
    local restorePerHour = support.restorePerHour or 0.35

    medTracking.activeGeneralEffects.relaxantTea = {
        startTime = currentHour,
        endTime = currentHour + math.max(0.05, duration),
        lastUpdateHour = currentHour,
        targetStress = math.min(currentStress, targetStress),
        restorePerHour = restorePerHour,
        medicationName = medData.displayName or "Relaxant Tea",
    }

    return true
end

function EHR.Medication.StartStaminaLock(player, medData)
    local support = medData and medData.staminaLock
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local duration = support.durationHours or medData.effectDurationHours or 3
    local targetEndurance = math.max(0, math.min(1, support.targetEndurance or 1.0))

    medTracking.activeGeneralEffects.staminaLock = {
        startTime = currentHour,
        endTime = currentHour + math.max(0.05, duration),
        targetEndurance = targetEndurance,
        delayedSideEffect = support.delayedSideEffect,
        medicationName = medData.displayName or "Nitric Oxide Boosters",
    }

    EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, targetEndurance)
    return true
end

function EHR.Medication.StartFatigueBlock(player, medData)
    local support = medData and medData.fatigueBlock
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local duration = support.durationHours or medData.effectDurationHours or 12

    medTracking.activeGeneralEffects.fatigueBlock = {
        startTime = currentHour,
        endTime = currentHour + math.max(0.05, duration),
        crashSideEffect = support.crashSideEffect,
        medicationName = medData.displayName or "Caffeine Pills",
    }

    local modData = player:getModData()
    if modData then
        modData.EHR_CaffeineAwake = true
    end

    EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, 0)
    return true
end

function EHR.Medication.IsCaffeineAwake(player)
    if not player then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local effect = medTracking and medTracking.activeGeneralEffects and medTracking.activeGeneralEffects.fatigueBlock
    if type(effect) ~= "table" then return false end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    return currentHour < (tonumber(effect.endTime) or 0)
end

-- Beta blockers use the EHR dose timer as their single source of truth. This
-- keeps the monitor, panic suppression, sleep block and blood-volume effects
-- synchronized even though the vanilla beta effect has a much shorter timer.
function EHR.Medication.IsBetaBlockerActive(player)
    if not player or not EHR.Medication.GetDoseStatus then return false end

    local ok, status = pcall(EHR.Medication.GetDoseStatus, player, "Base.PillsBeta")
    return ok and status ~= nil and status.isDoseActive == true
end

function EHR.Medication.IsAnalgesicActive(player)
    if not player or not EHR.Medication.GetDoseStatus then return false end

    local ok, status = pcall(EHR.Medication.GetDoseStatus, player, "Base.Pills")
    return ok and status ~= nil and status.isDoseActive == true
end

-- Pain itself is a 0..100 CharacterStat in B42. Only the final perceived pain
-- is changed here; body-part AdditionalPain remains intact, so untreated wounds
-- become painful again naturally after the analgesic wears off.
local function EHRMedicationSetPerceivedPain(player, value)
    if not player or not CharacterStat or not CharacterStat.PAIN then return false end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if not stats then return false end

    local ok = pcall(function()
        stats:set(CharacterStat.PAIN, math.max(0, math.min(100, tonumber(value) or 0)))
    end)
    return ok == true
end

local function EHRMedicationUpdateAnalgesic(player, medTracking, currentHour)
    if not player or not medTracking then return end

    local doseData = medTracking.activeDoses and medTracking.activeDoses["Base.Pills"] or nil
    local medData = EHR.Medication.Database and EHR.Medication.Database["Base.Pills"] or nil
    local analgesic = medData and medData.analgesic or nil
    local active = type(doseData) == "table"
        and analgesic ~= nil
        and EHR.Medication.IsAnalgesicActive
        and EHR.Medication.IsAnalgesicActive(player)
    local modData = player:getModData()

    if not active then
        if modData then
            modData.EHR_AnalgesicActive = nil
        end
        return
    end

    if modData then
        modData.EHR_AnalgesicActive = true
    end

    local currentPain = 0
    local hasPain = false
    pcall(function()
        local stats = player:getStats()
        if stats and CharacterStat and CharacterStat.PAIN then
            currentPain = tonumber(stats:get(CharacterStat.PAIN)) or 0
            hasPain = true
        end
    end)
    if not hasPain then return end

    local initialPain = tonumber(doseData.analgesicInitialPain)
    if initialPain == nil then
        initialPain = math.max(0, math.min(100, currentPain))
        doseData.analgesicInitialPain = initialPain
    end

    local startTime = tonumber(doseData.lastDoseTime) or currentHour
    local elapsed = math.max(0, currentHour - startTime)
    local rampHours = math.max(0.01, tonumber(analgesic.rampHours) or 0.5)
    local progress = math.max(0, math.min(1, elapsed / rampHours))
    local targetPain = math.max(0, initialPain * (1 - progress))

    -- A new injury may raise pain again while the medicine is active. Capping
    -- the final stat every update keeps that pain masked without erasing its source.
    if currentPain > targetPain + 0.001 then
        if EHRMedicationSetPerceivedPain(player, targetPain) then
            EHRMedicationRefreshMoodles(player)
        end
    end
end

function EHR.Medication.StartSleepAid(player, medData)
    local support = medData and medData.sleepAid
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local duration = support.durationHours or medData.effectDurationHours or 8
    local newEndTime = currentHour + math.max(0.05, duration)
    local existing = medTracking.activeGeneralEffects.sleepAid
    local existingEndTime = type(existing) == "table" and tonumber(existing.endTime) or nil
    local existingIsActive = existingEndTime ~= nil and existingEndTime > currentHour
    local combinedStartTime = currentHour
    local combinedEndTime = newEndTime
    local combinedMedicationName = medData.displayName or "Sleep Aid"

    if existingIsActive then
        combinedStartTime = math.min(tonumber(existing.startTime) or currentHour, currentHour)
        combinedEndTime = math.max(existingEndTime, newEndTime)
        if existingEndTime > newEndTime then
            combinedMedicationName = existing.medicationName or combinedMedicationName
        end
    end

    medTracking.activeGeneralEffects.sleepAid = {
        startTime = combinedStartTime,
        endTime = combinedEndTime,
        medicationName = combinedMedicationName,
    }

    return true
end

function EHR.Medication.HasActiveSleepAid(player)
    if not player then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local effect = medTracking and medTracking.activeGeneralEffects and medTracking.activeGeneralEffects.sleepAid
    if type(effect) ~= "table" then return false end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    return currentHour < (tonumber(effect.endTime) or 0)
end

local function EHRMedicationClearCombatStress(player)
    if not player or not CharacterStat then return end

    EHR_MedicationSetStat(player, CharacterStat.STRESS, 0)
    EHR_MedicationSetStat(player, CharacterStat.PANIC, 0)
    EHR_MedicationSetStat(player, CharacterStat.UNHAPPINESS, 0)
end

local function EHRMedicationGetItemId(item)
    if not item or not item.getID then return nil end
    local ok, id = pcall(function() return item:getID() end)
    if ok then return id end
    return nil
end

local function EHRMedicationFindItemById(container, itemId, depth)
    if not container or itemId == nil then return nil end
    depth = depth or 0
    if depth > 4 then return nil end

    local items = nil
    pcall(function() items = container:getItems() end)
    if not items then return nil end

    local size = 0
    pcall(function() size = items:size() end)
    size = tonumber(size) or 0
    if size <= 0 then return nil end

    for i = 0, size - 1 do
        local item = nil
        pcall(function() item = items:get(i) end)
        if item then
            local id = EHRMedicationGetItemId(item)
            if id ~= nil and tostring(id) == tostring(itemId) then
                return item
            end

            local nested = nil
            if item.getInventory then
                pcall(function() nested = item:getInventory() end)
            end
            local found = EHRMedicationFindItemById(nested, itemId, depth + 1)
            if found then return found end
        end
    end

    return nil
end

local function EHRMedicationRestoreCombatWeaponSpeed(player, explicitWeapon)
    if not player then return false end

    local modData = player:getModData()
    local weapon = explicitWeapon
    if not weapon and modData and modData.EHR_CombatStimWeaponId then
        local inventory = nil
        pcall(function() inventory = player:getInventory() end)
        weapon = EHRMedicationFindItemById(inventory, modData.EHR_CombatStimWeaponId)
    end

    local restored = false
    if weapon and weapon.getModData and weapon.setBaseSpeed then
        local itemData = weapon:getModData()
        local originalSpeed = tonumber(itemData and itemData.EHR_CombatStimBaseSpeed)
        if originalSpeed and originalSpeed > 0 then
            restored = pcall(function()
                weapon:setBaseSpeed(originalSpeed)
            end) or restored
        end
        if itemData then
            itemData.EHR_CombatStimBaseSpeed = nil
            itemData.EHR_CombatStimAppliedSpeed = nil
        end
    end

    if modData then
        modData.EHR_CombatStimWeaponId = nil
    end

    return restored
end

local function EHRMedicationApplyCombatWeaponSpeed(player, effect)
    if not player or not effect then return false end

    local weapon = nil
    pcall(function() weapon = player:getPrimaryHandItem() end)
    local modData = player:getModData()

    if not weapon or not weapon.getBaseSpeed or not weapon.setBaseSpeed or not weapon.getModData then
        if modData and modData.EHR_CombatStimWeaponId then
            EHRMedicationRestoreCombatWeaponSpeed(player)
        end
        return false
    end

    local weaponId = EHRMedicationGetItemId(weapon)
    if modData and modData.EHR_CombatStimWeaponId and tostring(modData.EHR_CombatStimWeaponId) ~= tostring(weaponId) then
        EHRMedicationRestoreCombatWeaponSpeed(player)
    end

    local itemData = weapon:getModData()
    if not itemData then return false end

    local currentSpeed = nil
    pcall(function() currentSpeed = weapon:getBaseSpeed() end)
    currentSpeed = tonumber(currentSpeed)
    if not currentSpeed or currentSpeed <= 0 then return false end

    local originalSpeed = tonumber(itemData.EHR_CombatStimBaseSpeed)
    if not originalSpeed or originalSpeed <= 0 then
        originalSpeed = currentSpeed
        itemData.EHR_CombatStimBaseSpeed = originalSpeed
    end

    local multiplier = math.max(1.0, tonumber(effect.attackSpeedMultiplier) or 2.0)
    local targetSpeed = originalSpeed * multiplier
    local appliedSpeed = tonumber(itemData.EHR_CombatStimAppliedSpeed)
    if (not appliedSpeed) or math.abs(appliedSpeed - targetSpeed) > 0.001 then
        local okSet = pcall(function()
            weapon:setBaseSpeed(targetSpeed)
        end)
        if okSet then
            itemData.EHR_CombatStimAppliedSpeed = targetSpeed
            if modData then
                modData.EHR_CombatStimWeaponId = weaponId
            end
            return true
        end
    end

    if modData then
        modData.EHR_CombatStimWeaponId = weaponId
    end
    return true
end

local function EHRMedicationHasOtherSpeedPenalty(player)
    if not player then return false end

    local modData = player:getModData()
    local active = modData and modData.EHR_Disease and modData.EHR_Disease.active or nil
    if not active or not EHR or not EHR.Disease or not EHR.Disease.Diseases then return false end

    for diseaseId, disease in pairs(active) do
        local def = EHR.Disease.Diseases[diseaseId]
        local effects = def and def.effects and def.effects[disease.stage or 1]
        local movementPenalty = effects and tonumber(effects.movementPenalty)
        if movementPenalty and movementPenalty < 1.0 then
            return true
        end
    end

    return false
end

local function EHRMedicationClearCombatSpeedBoost(player)
    if not player then return end

    local modData = player:getModData()
    if not modData or not modData.EHR_CombatStimSpeedActive then return end

    if player.setSpeedMod and not EHRMedicationHasOtherSpeedPenalty(player) then
        pcall(function() player:setSpeedMod(1.0) end)
    end

    modData.EHR_CombatStimSpeedActive = nil
end

local function EHRMedicationApplyCombatSpeedBoost(player, effect)
    if not player or not effect or not player.setSpeedMod then return false end
    if EHRMedicationHasOtherSpeedPenalty(player) then return false end

    local speedMod = math.max(1.0, math.min(1.25, tonumber(effect.speedMod) or 1.0))
    if speedMod <= 1.001 then return false end

    local ok = pcall(function() player:setSpeedMod(speedMod) end)
    if ok then
        local modData = player:getModData()
        if modData then
            modData.EHR_CombatStimSpeedActive = true
        end
        return true
    end

    return false
end

function EHR.Medication.StartCombatStimulants(player, medData)
    local support = medData and medData.combatStimulants
    if not player or not support then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local duration = support.durationHours or medData.effectDurationHours or 3

    medTracking.activeGeneralEffects.combatStimulants = {
        startTime = currentHour,
        endTime = currentHour + math.max(0.05, duration),
        lastUpdateHour = currentHour,
        attackSpeedMultiplier = support.attackSpeedMultiplier or 2.0,
        speedMod = support.speedMod or 1.12,
        maxEndurance = support.maxEndurance or 0.92,
        restorePerHour = support.restorePerHour or 0.45,
        delayedSideEffect = support.delayedSideEffect,
        medicationName = medData.displayName or "Combat Stimulants",
    }

    local modData = player:getModData()
    if modData then
        modData.EHR_CombatStimulantsActive = true
    end

    EHRMedicationClearCombatStress(player)
    EHRMedicationApplyCombatWeaponSpeed(player, medTracking.activeGeneralEffects.combatStimulants)
    EHRMedicationApplyCombatSpeedBoost(player, medTracking.activeGeneralEffects.combatStimulants)
    return true
end

function EHR.Medication.KillFromLastChanceEpinephrine(player)
    if not player then return false end
    local cause = "Emergency Epinephrine Auto-Injector - fatal stroke after administration above 15% overall health"
    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)

    local originalOverall = nil
    if bodyDamage and bodyDamage.getOverallBodyHealth then
        local okHealth, value = pcall(function() return tonumber(bodyDamage:getOverallBodyHealth()) end)
        if okHealth and value ~= nil and value == value
                and value ~= math.huge and value ~= -math.huge then
            originalOverall = value
        end
    end
    local originalPlayerHealth = nil
    if player.getHealth then
        local okHealth, value = pcall(function() return tonumber(player:getHealth()) end)
        if okHealth and value ~= nil and value == value
                and value ~= math.huge and value ~= -math.huge then
            originalPlayerHealth = value
        end
    end
    if originalOverall == nil and originalPlayerHealth == nil then
        EHR.Log("ERROR: Fatal epinephrine reaction could not snapshot authoritative health")
        return false
    end

    if originalOverall ~= nil and bodyDamage and bodyDamage.setOverallBodyHealth then
        pcall(function() bodyDamage:setOverallBodyHealth(0) end)
    end
    if originalPlayerHealth ~= nil and player.setHealth then
        pcall(function() player:setHealth(0) end)
    end

    local confirmed = false
    if bodyDamage and bodyDamage.getOverallBodyHealth then
        local okHealth, value = pcall(function() return tonumber(bodyDamage:getOverallBodyHealth()) end)
        confirmed = okHealth and value ~= nil and value <= 0
    end
    if not confirmed and player.getHealth then
        local okHealth, value = pcall(function() return tonumber(player:getHealth()) end)
        confirmed = okHealth and value ~= nil and value <= 0
    end
    if not confirmed then
        if originalOverall ~= nil and bodyDamage and bodyDamage.setOverallBodyHealth then
            pcall(function() bodyDamage:setOverallBodyHealth(originalOverall) end)
        end
        if originalPlayerHealth ~= nil and player.setHealth then
            pcall(function() player:setHealth(originalPlayerHealth) end)
        end
        EHR.Log("ERROR: Fatal epinephrine reaction could not set authoritative health to zero")
        return false
    end

    if EHR.RecordDeathCause then
        pcall(function() EHR.RecordDeathCause(player, cause) end)
    end
    if player.isLocalPlayer and player:isLocalPlayer() and player.Say then
        EHR.Locale.Say(player, "My heart--")
    end
    EHR.Log(cause)
    return true
end

function EHR.Medication.RollLastChanceEpinephrineDeath(chancePercent)
    local chance = math.max(0, math.min(100, tonumber(chancePercent) or 50))
    if chance <= 0 then return false end
    if chance >= 100 then return true end

    local roll = nil
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(100) end)
        if ok then roll = tonumber(value) end
    end
    if roll == nil then
        roll = math.random(0, 99)
    end
    return roll < chance
end

function EHR.Medication.ApplyLastChanceRescueVitals(player, targetHealth, highRiskSurvivor, bodyPartSnapshot)
    if not player then return false end

    local dead = false
    if player.isDead then
        local okDead, value = pcall(function() return player:isDead() end)
        dead = okDead and value == true
    end
    if not dead and player.getHealth then
        local okHealth, value = pcall(function() return tonumber(player:getHealth()) end)
        dead = okHealth and value ~= nil and value <= 0
    end
    if dead then return false end

    local restored = false
    local reachedTarget = false
    if type(bodyPartSnapshot) == "table" and EHR.Medication.ApplyLastChanceBodyPartHealth then
        restored = EHR.Medication.ApplyLastChanceBodyPartHealth(player, bodyPartSnapshot, targetHealth)
        reachedTarget = restored
    else
        local restoreResult, _, targetResult = EHR.Medication.RestoreLastChanceOverallHealth(player, targetHealth)
        restored = restoreResult
        reachedTarget = targetResult
    end
    if restored ~= true or reachedTarget ~= true then return false end

    EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, 1.0)
    EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, 0.0)

    if highRiskSurvivor then
        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.SICKNESS, 1.0)
        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, 1.0)
        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.STRESS, 1.0)
        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.UNHAPPINESS, 1.0)
    end
    EHRMedicationRefreshMoodles(player, true)
    return true, EHR.Medication.CaptureLastChanceBodyPartHealth(player)
end

function EHR.Medication.ApplyLastChanceEpinephrine(player, medData)
    local support = medData and medData.lastChanceEpinephrine
    if not player or not support or not EHRMedicationIsAuthoritative() then return false end

    if player.isDead then
        local okDead, dead = pcall(function() return player:isDead() end)
        if okDead and dead == true then return false end
    end
    if player.getHealth then
        local okHealth, health = pcall(function() return tonumber(player:getHealth()) end)
        if okHealth and health ~= nil and health <= 0 then return false end
    end

    local currentHealth = EHR.Medication.GetLastChanceOverallHealth(player)
    if currentHealth == nil or currentHealth <= 0 then return false end
    local threshold = tonumber(support.healthThreshold) or 15
    local highRisk = currentHealth > threshold

    if highRisk and EHR.Medication.RollLastChanceEpinephrineDeath(support.highHealthDeathChance) then
        local fatalToken = "fatal:" .. tostring(currentHealth)
        pcall(function()
            fatalToken = "fatal:" .. tostring(player:getUsername() or player:getOnlineID() or "player")
                .. ":" .. tostring(getTimestampMs and getTimestampMs() or currentHealth)
        end)
        if EHR.Medication.KillFromLastChanceEpinephrine(player) ~= true then
            return false
        end
        if EHRMedicationIsServer() and sendServerCommand then
            pcall(function()
                sendServerCommand(player, "EHR_LastChanceEpinephrine", "ApplyFatal", {
                    token = fatalToken,
                })
            end)
        end
        -- A fatal roll is still a successfully administered, consumed dose.
        return true
    end

    local targetHealth = tonumber(support.targetOverallHealth) or 75
    local rescued, bodyPartSnapshot = EHR.Medication.ApplyLastChanceRescueVitals(player, targetHealth, highRisk)
    if not rescued then
        EHR.Log("Last-chance epinephrine rescue aborted: target health was not safely reached")
        return false
    end

    local medTracking = EHR.Medication.GetMedicationData(player)
    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}
    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local duration = math.max(0.05, tonumber(support.durationHours) or 1)
    medTracking.lastChanceUseSerial = (tonumber(medTracking.lastChanceUseSerial) or 0) + 1
    local playerKey = "player"
    pcall(function()
        playerKey = tostring(player:getUsername() or player:getOnlineID() or player:getPlayerNum() or "player")
    end)
    local applicationToken = string.format(
        "%s:%.6f:%d",
        playerKey,
        currentHour,
        medTracking.lastChanceUseSerial
    )
    medTracking.activeGeneralEffects.lastChanceEpinephrine = {
        startTime = currentHour,
        endTime = currentHour + duration,
        lastUpdateHour = currentHour,
        speedMod = math.max(1.0, math.min(1.25, tonumber(support.speedMod) or 1.20)),
        crashFatigueFloor = math.max(0, math.min(1, tonumber(support.crashFatigueFloor) or 0.50)),
        mildHeadacheSideEffect = support.mildHeadacheSideEffect,
        thirstSideEffect = support.thirstSideEffect,
        applicationToken = applicationToken,
        medicationName = medData.displayName or "Emergency Epinephrine Auto-Injector",
    }

    if highRisk and support.severeHeadacheSideEffect and EHR.Medication.ApplySideEffect then
        EHR.Medication.ApplySideEffect(player, support.severeHeadacheSideEffect, {
            force = true,
            duration = 3,
        })
    end

    if EHRMedicationIsServer() and sendServerCommand then
        pcall(function()
            sendServerCommand(player, "EHR_LastChanceEpinephrine", "ApplyRescueVitals", {
                token = applicationToken,
                targetHealth = targetHealth,
                highRiskSurvivor = highRisk == true,
                bodyPartHealth = bodyPartSnapshot,
                boostEndTime = currentHour + duration,
                speedMod = medTracking.activeGeneralEffects.lastChanceEpinephrine.speedMod,
            })
        end)
    end
    EHRMedicationRequestSync(player)
    EHR.Log(string.format(
        "Last-chance epinephrine survived (health %.2f, high-risk=%s)",
        currentHealth,
        tostring(highRisk)
    ))
    return true
end

local function EHRMedicationRollInsomniaCrash(player, source)
    if not player then return false end
    if not (EHR.Insomnia and EHR.Insomnia.RollStimulantCrash) then
        pcall(function() require "ExtensiveHealth/EHR_Insomnia" end)
    end
    if EHR.Insomnia and EHR.Insomnia.RollStimulantCrash then
        local ok, result = pcall(EHR.Insomnia.RollStimulantCrash, player, source)
        return ok and result == true
    end
    return false
end

function EHR.Medication.UpdateGeneralEffects(player, medTracking, currentHour)
    if not player or not medTracking then return end
    medTracking.activeGeneralEffects = medTracking.activeGeneralEffects or {}

    local authoritative = EHRMedicationIsAuthoritative()
    local changed = false
    EHRMedicationUpdateMPFatigueRecovery(player, medTracking, currentHour)
    EHRMedicationUpdateAnalgesic(player, medTracking, currentHour)

    local betaModData = player:getModData()
    local betaActive = EHR.Medication.IsBetaBlockerActive
        and EHR.Medication.IsBetaBlockerActive(player)
    if betaActive then
        if betaModData then
            betaModData.EHR_BetaBlockerActive = true
        end
        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.PANIC, 0)
    elseif betaModData and betaModData.EHR_BetaBlockerActive then
        betaModData.EHR_BetaBlockerActive = nil
        -- Stop any remaining vanilla timer when the two-hour EHR effect ends.
        if player.setBetaEffect then
            pcall(function() player:setBetaEffect(0) end)
        end
    end

    local sleepAid = medTracking.activeGeneralEffects.sleepAid
    if type(sleepAid) == "table" then
        local endTime = tonumber(sleepAid.endTime) or currentHour
        if currentHour >= endTime then
            medTracking.activeGeneralEffects.sleepAid = nil
            changed = true
        end
    end

    local warmingPack = medTracking.activeGeneralEffects.warmingPack
    if type(warmingPack) == "table" then
        local endTime = tonumber(warmingPack.endTime) or currentHour
        if currentHour >= endTime then
            medTracking.activeGeneralEffects.warmingPack = nil
            changed = true
        end
    end

    local effect = medTracking.activeGeneralEffects.bronchodilator
    if type(effect) == "table" then
        local endTime = tonumber(effect.endTime) or currentHour
        if currentHour >= endTime then
            medTracking.activeGeneralEffects.bronchodilator = nil
            changed = true
        else
            local lastUpdateHour = tonumber(effect.lastUpdateHour) or currentHour
            local deltaHours = currentHour - lastUpdateHour
            if deltaHours > 0 then
                effect.lastUpdateHour = currentHour

                local currentEndurance = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.ENDURANCE)
                if currentEndurance then
                    local targetEndurance = math.max(0, math.min(1, tonumber(effect.targetEndurance) or currentEndurance))
                    if currentEndurance < targetEndurance then
                        local restorePerHour = math.max(0, tonumber(effect.restorePerHour) or 0.85)
                        local nextEndurance = math.min(targetEndurance, currentEndurance + (restorePerHour * deltaHours))
                        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, nextEndurance)
                    end
                end
            end
        end
    end

    local hydration = medTracking.activeGeneralEffects.electrolytes
    if type(hydration) == "table" then
        local endTime = tonumber(hydration.endTime) or currentHour
        if currentHour >= endTime then
            medTracking.activeGeneralEffects.electrolytes = nil
            changed = true
        else
            local lastUpdateHour = tonumber(hydration.lastUpdateHour) or currentHour
            local deltaHours = currentHour - lastUpdateHour
            if deltaHours > 0 then
                hydration.lastUpdateHour = currentHour

                local currentThirst = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.THIRST)
                if currentThirst then
                    local targetThirst = math.max(0, math.min(1, tonumber(hydration.targetThirst) or currentThirst))
                    if currentThirst > targetThirst then
                        local restorePerHour = math.max(0, tonumber(hydration.restorePerHour) or 0.50)
                        local nextThirst = math.max(targetThirst, currentThirst - (restorePerHour * deltaHours))
                        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.THIRST, nextThirst)
                    end
                end
            end
        end
    end

    local stressSupport = medTracking.activeGeneralEffects.relaxantTea
    if type(stressSupport) == "table" then
        local endTime = tonumber(stressSupport.endTime) or currentHour
        if currentHour >= endTime then
            medTracking.activeGeneralEffects.relaxantTea = nil
            changed = true
        else
            local lastUpdateHour = tonumber(stressSupport.lastUpdateHour) or currentHour
            local deltaHours = math.max(0, math.min(0.25, currentHour - lastUpdateHour))
            if deltaHours > 0 then
                stressSupport.lastUpdateHour = currentHour

                local currentStress = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.STRESS)
                if currentStress then
                    local targetStress = math.max(0, math.min(1, tonumber(stressSupport.targetStress) or 0))
                    if currentStress > targetStress then
                        local restorePerHour = math.max(0, tonumber(stressSupport.restorePerHour) or 0.35)
                        local nextStress = math.max(targetStress, currentStress - (restorePerHour * deltaHours))
                        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.STRESS, nextStress)
                    end
                end
            end
        end
    end

    local stamina = medTracking.activeGeneralEffects.staminaLock
    if type(stamina) == "table" then
        local endTime = tonumber(stamina.endTime) or currentHour
        if currentHour >= endTime then
            local delayedSideEffect = stamina.delayedSideEffect
            medTracking.activeGeneralEffects.staminaLock = nil
            changed = true
            if authoritative and delayedSideEffect and EHR.Medication.ApplySideEffect then
                EHR.Medication.ApplySideEffect(player, delayedSideEffect)
            end
            if authoritative then
                EHRMedicationRollInsomniaCrash(player, "nitric_oxide_crash")
            end
        else
            local targetEndurance = math.max(0, math.min(1, tonumber(stamina.targetEndurance) or 1.0))
            EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, targetEndurance)
        end
    end

    local combatStim = medTracking.activeGeneralEffects.combatStimulants
    if type(combatStim) == "table" then
        local endTime = tonumber(combatStim.endTime) or currentHour
        if currentHour >= endTime then
            local delayedSideEffect = combatStim.delayedSideEffect
            medTracking.activeGeneralEffects.combatStimulants = nil
            changed = true
            EHRMedicationRestoreCombatWeaponSpeed(player)
            EHRMedicationClearCombatSpeedBoost(player)
            local modDataCombat = player:getModData()
            if modDataCombat then
                modDataCombat.EHR_CombatStimulantsActive = nil
            end
            if authoritative and delayedSideEffect and EHR.Medication.ApplySideEffect then
                EHR.Medication.ApplySideEffect(player, delayedSideEffect)
            end
            if authoritative then
                EHRMedicationRollInsomniaCrash(player, "combat_stimulant_crash")
            end
        else
            local lastUpdateHour = tonumber(combatStim.lastUpdateHour) or currentHour
            local deltaHours = math.max(0, math.min(0.25, currentHour - lastUpdateHour))
            combatStim.lastUpdateHour = currentHour

            EHRMedicationClearCombatStress(player)
            EHRMedicationApplyCombatWeaponSpeed(player, combatStim)
            EHRMedicationApplyCombatSpeedBoost(player, combatStim)

            if deltaHours > 0 then
                local currentEndurance = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.ENDURANCE)
                if currentEndurance then
                    local maxEndurance = math.max(0.20, math.min(0.98, tonumber(combatStim.maxEndurance) or 0.92))
                    if currentEndurance < maxEndurance then
                        local restorePerHour = math.max(0, tonumber(combatStim.restorePerHour) or 0.45)
                        local nextEndurance = math.min(maxEndurance, currentEndurance + (restorePerHour * deltaHours))
                        EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, nextEndurance)
                    end
                end
            end

            local modDataCombat = player:getModData()
            if modDataCombat then
                modDataCombat.EHR_CombatStimulantsActive = true
            end
        end
    end

    local lastChance = medTracking.activeGeneralEffects.lastChanceEpinephrine
    if type(lastChance) == "table" then
        local endTime = tonumber(lastChance.endTime) or currentHour
        if currentHour >= endTime then
            local crashFatigueFloor = math.max(0, math.min(1, tonumber(lastChance.crashFatigueFloor) or 0.50))
            local mildHeadache = lastChance.mildHeadacheSideEffect
            local thirstEffect = lastChance.thirstSideEffect
            medTracking.activeGeneralEffects.lastChanceEpinephrine = nil
            changed = true

            if authoritative then
                local currentFatigue = EHR_MedicationGetStat(player, CharacterStat and CharacterStat.FATIGUE) or 0
                if currentFatigue < crashFatigueFloor then
                    EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, crashFatigueFloor)
                end
                if EHRMedicationIsServer() and sendServerCommand then
                    pcall(function()
                        sendServerCommand(player, "EHR_LastChanceEpinephrine", "ApplyCrashFatigue", {
                            token = tostring(lastChance.applicationToken or lastChance.startTime or currentHour) .. ":crash",
                            fatigueFloor = crashFatigueFloor,
                        })
                    end)
                end
                if mildHeadache and EHR.Medication.ApplySideEffect then
                    EHR.Medication.ApplySideEffect(player, mildHeadache, { force = true, duration = 3 })
                end
                if thirstEffect and EHR.Medication.ApplySideEffect then
                    EHR.Medication.ApplySideEffect(player, thirstEffect, { force = true, duration = 3 })
                end
                EHRMedicationRefreshMoodles(player, true)
            end
        else
            lastChance.lastUpdateHour = currentHour
        end
    end

    local fatigueBlock = medTracking.activeGeneralEffects.fatigueBlock
    local modData = player:getModData()
    if type(fatigueBlock) == "table" then
        local endTime = tonumber(fatigueBlock.endTime) or currentHour
        if currentHour >= endTime then
            local crashSideEffect = fatigueBlock.crashSideEffect
            medTracking.activeGeneralEffects.fatigueBlock = nil
            changed = true
            if modData then
                modData.EHR_CaffeineAwake = nil
            end
            if EHRMedicationIsMultiplayer() then
                EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, 0.85)
            else
                EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, 1.0)
            end
            if authoritative and crashSideEffect and EHR.Medication.ApplySideEffect then
                EHR.Medication.ApplySideEffect(player, crashSideEffect)
            end
            if authoritative then
                EHRMedicationRollInsomniaCrash(player, "caffeine_crash")
            end
            EHRMedicationRefreshMoodles(player, true)
        else
            if modData then
                modData.EHR_CaffeineAwake = true
            end
            EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, 0)
            if player.isAsleep then
                local asleep = false
                pcall(function() asleep = player:isAsleep() end)
                if asleep then
                    if player.setAsleep then pcall(function() player:setAsleep(false) end) end
                    if player.setForceWakeUpTime then pcall(function() player:setForceWakeUpTime(-1) end) end
                end
            end
        end
    elseif modData then
        modData.EHR_CaffeineAwake = nil
    end

    return changed
end

local function EHR_MedicationClampStatMax(player, stat, maxAllowed)
    if not player or not stat or not maxAllowed then return false end

    local stats = nil
    pcall(function() stats = player:getStats() end)
    if not stats then return false end

    local changed = false
    pcall(function()
        local current = stats:get(stat) or 0
        if current > maxAllowed then
            stats:set(stat, math.max(0, math.min(1, maxAllowed)))
            changed = true
        end
    end)

    if CharacterStat and stat == CharacterStat.SICKNESS and stats.getSickness and stats.setSickness then
        pcall(function()
            local current = stats:getSickness() or 0
            if current > maxAllowed then
                stats:setSickness(math.max(0, math.min(1, maxAllowed)))
                changed = true
            end
        end)
    end

    if changed and isClient and isClient() and sendPlayerStat and CharacterStat and stat == CharacterStat.SICKNESS then
        pcall(function() sendPlayerStat(player, CharacterStat.SICKNESS) end)
    end

    return changed
end

local function EHR_MedicationSetCorpseNauseaTarget(player, diseaseId, reductions, doseTiming, currentHour)
    if diseaseId ~= "corpse_sickness" or not player or not reductions then return false end
    local nauseaRelief = math.max(reductions.nausea or 0, reductions.sickness or 0)
    if nauseaRelief <= 0 then return false end

    local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player)
    local disease = diseaseData and diseaseData.active and diseaseData.active["corpse_sickness"]
    if not disease then return false end

    local stage = disease.stage or 1
    local target = 0.14
    if stage == 2 then
        target = 0.20
    elseif stage == 3 then
        target = 0.36
    elseif stage == 4 then
        target = 0.12
    end

    currentHour = currentHour or (getGameTime and getGameTime():getWorldAgeHours()) or 0
    local activeHours = doseTiming and doseTiming.activeHours or 0.25
    if activeHours <= 0 then activeHours = 0.25 end

    disease.corpseSicknessNauseaRelief = nauseaRelief
    disease.corpseSicknessNauseaReliefUntil = currentHour + activeHours
    disease.corpseSicknessSymptomTarget = target
    disease.corpseSicknessSymptomTargetUntil = currentHour + activeHours

    local maxAllowed = target + 0.015
    local stats = player:getStats()
    local beforeEnum, beforeLegacy, afterEnum, afterLegacy = nil, nil, nil, nil
    if stats and CharacterStat and CharacterStat.SICKNESS then
        pcall(function() beforeEnum = stats:get(CharacterStat.SICKNESS) end)
    end
    if stats and stats.getSickness then
        pcall(function() beforeLegacy = stats:getSickness() end)
    end

    local changed = false
    changed = EHR_MedicationClampStatMax(player, CharacterStat and CharacterStat.SICKNESS, maxAllowed) or changed
    changed = EHR_MedicationClampStatMax(player, CharacterStat and CharacterStat.FOOD_SICKNESS, maxAllowed) or changed

    if stats and CharacterStat and CharacterStat.SICKNESS then
        pcall(function() afterEnum = stats:get(CharacterStat.SICKNESS) end)
    end
    if stats and stats.getSickness then
        pcall(function() afterLegacy = stats:getSickness() end)
    end

    EHR.Log(string.format(
        "Corpse nausea relief target: stage %s, sickness cap %.1f%% for %.1fh (enum %s -> %s, legacy %s -> %s)",
        tostring(stage),
        maxAllowed * 100,
        activeHours,
        tostring(beforeEnum),
        tostring(afterEnum),
        tostring(beforeLegacy),
        tostring(afterLegacy)
    ))

    return changed
end

local function EHR_MedicationReduceMuscleStiffness(player, reduction)
    if not player or not reduction or reduction <= 0 then return false end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return false end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return false end

    local changed = false
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil

        if part and EHR_MedicationIsMusclePart(partType, part) then
            local okCurrent, currentStiffness = pcall(function()
                return part:getStiffness()
            end)

            currentStiffness = (okCurrent and currentStiffness) or 0
            if currentStiffness > 0 and part.setStiffness then
                local drop = math.max(10, currentStiffness * math.min(0.85, reduction * 1.75))
                local newStiffness = math.max(0, currentStiffness - drop)
                local okSet = pcall(function()
                    part:setStiffness(newStiffness)
                end)

                if okSet then
                    changed = true
                    if newStiffness <= 0.1 and player.getFitness and BodyPartType.ToString then
                        pcall(function()
                            player:getFitness():removeStiffnessValue(BodyPartType.ToString(partType))
                        end)
                    end
                end
            end

            if part.getAdditionalPain and part.setAdditionalPain then
                pcall(function()
                    local currentPain = part:getAdditionalPain() or 0
                    local newPain = math.max(0, currentPain - (reduction * 20))
                    if newPain < currentPain then
                        part:setAdditionalPain(newPain)
                        changed = true
                    end
                end)
            end
        end
    end

    if changed and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end

    return changed
end

local function EHR_MedicationApplyImmediateSymptomRelief(player, diseaseId, medData, doseTiming, currentHour)
    local reductions = medData and medData.symptomReduction
    if not reductions then return end

    local didRelieve = false
    local hasRespiratorySupport = medData and medData.respiratorySupport ~= nil
    local hasHydrationSupport = medData and medData.hydrationSupport ~= nil
    local isFoodborne = diseaseId == "food_poisoning"
            or diseaseId == "gastroenteritis"
            or diseaseId == "dysentery"
            or diseaseId == "toxin_poisoning"
    local nauseaComponentDisease = isFoodborne or diseaseId == "corpse_sickness"

    if reductions.nausea then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.10 * reductions.nausea, 0, 1) or didRelieve
        if nauseaComponentDisease then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.08 * reductions.nausea, 0, 1) or didRelieve
        end
    end

    if reductions.vomiting then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.04 * reductions.vomiting, 0, 1) or didRelieve
        if nauseaComponentDisease then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.05 * reductions.vomiting, 0, 1) or didRelieve
        end
        if isFoodborne then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.HUNGER, -0.02 * reductions.vomiting, 0, 1) or didRelieve
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.THIRST, -0.04 * reductions.vomiting, 0, 1) or didRelieve
        end
    end

    if reductions.sickness then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.12 * reductions.sickness, 0, 1) or didRelieve
        if nauseaComponentDisease then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.08 * reductions.sickness, 0, 1) or didRelieve
        end
    end

    if reductions.stress then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.STRESS, -0.16 * reductions.stress, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.PANIC, -0.12 * reductions.stress, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.UNHAPPINESS, -0.08 * reductions.stress, 0, 1) or didRelieve
    end

    didRelieve = EHR_MedicationSetCorpseNauseaTarget(player, diseaseId, reductions, doseTiming, currentHour) or didRelieve

    if reductions.dehydration and not hasHydrationSupport then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.THIRST, -0.10 * reductions.dehydration, 0, 1) or didRelieve
    end

    if reductions.fever then
        didRelieve = EHR_MedicationReduceFever(player, reductions.fever, doseTiming and doseTiming.activeHours) or didRelieve
    end

    if reductions.breathingDifficulty then
        if not hasRespiratorySupport then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.ENDURANCE, 0.14 * reductions.breathingDifficulty, 0, 1) or didRelieve
        end
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.DISCOMFORT, -0.06 * reductions.breathingDifficulty, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.PANIC, -0.04 * reductions.breathingDifficulty, 0, 1) or didRelieve
    end

    if reductions.weakness then
        if not hasRespiratorySupport then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.ENDURANCE, 0.12 * reductions.weakness, 0, 1) or didRelieve
        end
    end

    if reductions.muscleSpasms then
        didRelieve = EHR_MedicationReduceMuscleStiffness(player, reductions.muscleSpasms) or didRelieve
    end

    if reductions.pain then
        didRelieve = EHR_MedicationReducePain(player, reductions.pain) or didRelieve
    end

    if didRelieve then
        local moodles = nil
        if player then
            pcall(function() moodles = player:getMoodles() end)
        end
        if moodles and moodles.Update then
            pcall(function() moodles:Update() end)
        end
        EHR.Log("Applied immediate symptom relief from " .. (medData.displayName or "medication") .. " to " .. tostring(diseaseId))
    end
end

function EHR.Medication.IsModuleDiseaseActive(player, diseaseId)
    if not player or not diseaseId then return false end

    if diseaseId == "wound_infection" then
        if EHR.WoundInfection and EHR.WoundInfection.GetData then
            if EHR.WoundInfection.HasTreatableInfection then
                local ok, active = pcall(EHR.WoundInfection.HasTreatableInfection, player)
                if ok and active == true then return true end
            end
            local woundData = EHR.WoundInfection.GetData(player)
            if woundData and (tonumber(woundData.worstStage) or 0) > 0 then
                return true
            end
            if woundData and woundData.parts then
                for _, partData in pairs(woundData.parts) do
                    if partData and (tonumber(partData.stage) or 0) > 0 then
                        return true
                    end
                end
            end
        end
        return false
    end

    if diseaseId == "sepsis" then
        if EHR.Sepsis and EHR.Sepsis.HasSepsis then
            return EHR.Sepsis.HasSepsis(player)
        end
        if EHR.Sepsis and EHR.Sepsis.GetData then
            local sepsisData = EHR.Sepsis.GetData(player)
            return sepsisData and sepsisData.active == true and (tonumber(sepsisData.stage) or 0) > 0
        end
        local modData = player:getModData()
        local sepsisData = modData and modData.EHR_Sepsis
        return sepsisData and sepsisData.active == true and (tonumber(sepsisData.stage) or 0) > 0
    end

    return false
end

function EHR.Medication.ApplyModuleSymptomTreatment(player, diseaseId, medData, tierEffects, itemFullType)
    if not player or not diseaseId or not medData or not medData.symptomReduction then return false end
    if not EHR.Medication.IsModuleDiseaseActive or not EHR.Medication.IsModuleDiseaseActive(player, diseaseId) then
        return false
    end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local timing = EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
    local medKey = itemFullType or medData.displayName

    EHR_MedicationApplyImmediateSymptomRelief(player, diseaseId, medData, timing, currentHour)

    if not medTracking.activeDoses[medKey] then
        medTracking.activeDoses[medKey] = {
            lastDoseTime = currentHour,
            doseCount = 1,
            totalDosesNeeded = timing.dosesRequired,
            intervalHours = timing.doseInterval,
            activeHours = timing.activeHours,
            medicationName = medData.displayName,
            tier = medData.tier,
            treatingDisease = diseaseId,
            moduleTargets = { [diseaseId] = true },
            symptomOnly = true,
            requiresDoseCourse = false,
        }
    else
        local doseData = medTracking.activeDoses[medKey]
        local sameDoseEvent = math.abs((tonumber(doseData.lastDoseTime) or -999999) - currentHour) < 0.001
        doseData.lastDoseTime = currentHour
        if not sameDoseEvent then
            doseData.doseCount = (doseData.doseCount or 0) + 1
        end
        doseData.totalDosesNeeded = timing.dosesRequired
        doseData.intervalHours = timing.doseInterval
        doseData.activeHours = timing.activeHours
        doseData.medicationName = medData.displayName
        doseData.tier = medData.tier
        doseData.treatingDisease = doseData.treatingDisease or diseaseId
        doseData.moduleTargets = doseData.moduleTargets or {}
        doseData.moduleTargets[diseaseId] = true
        doseData.symptomOnly = true
        doseData.requiresDoseCourse = false
    end

    EHR.Log("Applied module symptom relief from " .. (medData.displayName or medKey) .. " to " .. tostring(diseaseId))
    return true
end

function EHR.Medication.ApplyModuleTreatment(player, diseaseId, medData, tierEffects, itemFullType)
    if not player or not diseaseId or not medData then return false end
    if medData.preventionOnly == true then return false end
    if not EHR_MedicationCanCure(medData, tierEffects) then return false end
    if not EHR.Medication.IsModuleDiseaseActive or not EHR.Medication.IsModuleDiseaseActive(player, diseaseId) then
        return false
    end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return false end

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local doseTiming = EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
    local medKey = itemFullType or medData.displayName

    if tierEffects.symptomRelief > 0 then
        EHR_MedicationApplyImmediateSymptomRelief(player, diseaseId, medData, doseTiming, currentHour)
    end

    local doseData = medTracking.activeDoses[medKey]
    if not doseData then
        doseData = {
            firstDoseTime = currentHour,
            lastDoseTime = currentHour,
            doseCount = 1,
            totalDosesNeeded = doseTiming.dosesRequired,
            intervalHours = doseTiming.doseInterval,
            activeHours = doseTiming.activeHours,
            medicationName = medData.displayName,
            tier = medData.tier,
            treatingDisease = diseaseId,
            moduleTargets = { [diseaseId] = true },
            symptomOnly = false,
            requiresDoseCourse = true,
        }
        medTracking.activeDoses[medKey] = doseData
    else
        if not tonumber(doseData.firstDoseTime) then
            local previousTreatment = medTracking.activeTreatments[diseaseId]
            if type(previousTreatment) == "table" and previousTreatment.medKey == medKey then
                doseData.firstDoseTime = tonumber(previousTreatment.startTime)
            end
            if not tonumber(doseData.firstDoseTime) then
                local previousLastDose = tonumber(doseData.lastDoseTime) or currentHour
                local previousDoseCount = math.max(1, tonumber(doseData.doseCount) or 1)
                local intervalHours = math.max(0, tonumber(doseData.intervalHours) or doseTiming.doseInterval or 0)
                doseData.firstDoseTime = math.max(0, previousLastDose - ((previousDoseCount - 1) * intervalHours))
            end
        end
        local sameDoseEvent = math.abs((tonumber(doseData.lastDoseTime) or -999999) - currentHour) < 0.001
        doseData.lastDoseTime = currentHour
        if not sameDoseEvent then
            doseData.doseCount = (doseData.doseCount or 0) + 1
        end
        doseData.totalDosesNeeded = doseTiming.dosesRequired
        doseData.intervalHours = doseTiming.doseInterval
        doseData.activeHours = doseTiming.activeHours
        doseData.medicationName = medData.displayName
        doseData.tier = medData.tier
        doseData.treatingDisease = doseData.treatingDisease or diseaseId
        doseData.moduleTargets = doseData.moduleTargets or {}
        doseData.moduleTargets[diseaseId] = true
        doseData.symptomOnly = false
        doseData.requiresDoseCourse = true
    end

    if medData.respiratorySupport and EHR.Medication.StartRespiratorySupport then
        EHR.Medication.StartRespiratorySupport(player, medData)
    end

    local cureTimeHours = EHR.Medication.GetCureTimeHours(medData, diseaseId, tierEffects)
    local existingTreatment = medTracking.activeTreatments[diseaseId]
    if existingTreatment and existingTreatment.medKey == medKey then
        existingTreatment.cureTimeHours = existingTreatment.cureTimeHours or cureTimeHours
        existingTreatment.medicationName = medData.displayName
        existingTreatment.tier = medData.tier
        existingTreatment.medKey = medKey
        existingTreatment.moduleBacked = true
        existingTreatment.awaitingDoses = nil
    else
        medTracking.activeTreatments[diseaseId] = {
            startTime = tonumber(doseData.firstDoseTime) or currentHour,
            cureTimeHours = cureTimeHours,
            medicationName = medData.displayName,
            tier = medData.tier,
            medKey = medKey,
            moduleBacked = true,
            awaitingDoses = nil,
        }
    end

    EHR.Log("Applied module treatment from " .. (medData.displayName or medKey) ..
        " to " .. tostring(diseaseId) .. " - dose " ..
        tostring(doseData.doseCount or 0) .. "/" .. tostring(doseData.totalDosesNeeded or 1))
    return true
end

function EHR.Medication.ApplyGeneralSymptomRelief(player, medData)
    local reductions = medData and medData.symptomReduction
    if not reductions then return false end

    local didRelieve = false
    local hasRespiratorySupport = medData and medData.respiratorySupport ~= nil
    local hasHydrationSupport = medData and medData.hydrationSupport ~= nil
    if reductions.nausea then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.08 * reductions.nausea, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.05 * reductions.nausea, 0, 1) or didRelieve
    end

    if reductions.sickness then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.10 * reductions.sickness, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.06 * reductions.sickness, 0, 1) or didRelieve
    end

    if reductions.vomiting then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.03 * reductions.vomiting, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.04 * reductions.vomiting, 0, 1) or didRelieve
    end

    if reductions.stress then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.STRESS, -0.14 * reductions.stress, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.PANIC, -0.10 * reductions.stress, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.UNHAPPINESS, -0.08 * reductions.stress, 0, 1) or didRelieve
    end

    if reductions.breathingDifficulty then
        if not hasRespiratorySupport then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.ENDURANCE, 0.12 * reductions.breathingDifficulty, 0, 1) or didRelieve
        end
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.DISCOMFORT, -0.05 * reductions.breathingDifficulty, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.PANIC, -0.03 * reductions.breathingDifficulty, 0, 1) or didRelieve
    end

    if reductions.dehydration and not hasHydrationSupport then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.THIRST, -0.08 * reductions.dehydration, 0, 1) or didRelieve
    end

    if reductions.fever then
        didRelieve = EHR_MedicationReduceFever(player, reductions.fever * 0.70) or didRelieve
    end

    if reductions.muscleSpasms then
        didRelieve = EHR_MedicationReduceMuscleStiffness(player, reductions.muscleSpasms) or didRelieve
    end

    if reductions.pain then
        didRelieve = EHR_MedicationReducePain(player, reductions.pain) or didRelieve
    end

    if reductions.weakness then
        if not hasRespiratorySupport and not hasHydrationSupport then
            didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.ENDURANCE, 0.12 * reductions.weakness, 0, 1) or didRelieve
        end
    end

    if didRelieve then
        EHR.Log("Applied general symptom relief from " .. (medData.displayName or "medication"))
    end

    return didRelieve
end

function EHR.Medication.ApplyTreatment(player, diseaseId, medData, tierEffects, itemFullType)
    if not player or not diseaseId then return end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    local disease = diseaseData.active[diseaseId]

    if not disease then return end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()
    local doseTiming = EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
    local medKey = itemFullType or medData.displayName
    local canCure = EHR_MedicationCanCure(medData, tierEffects)

    -- Apply symptom relief
    if tierEffects.symptomRelief > 0 then
        local currentSymptomSeverity = disease.symptomSeverity or 1.0
        if not disease.symptomReliefUntil or disease.symptomReliefUntil <= currentHour then
            currentSymptomSeverity = 1.0
        end

        disease.symptomSeverity = math.min(currentSymptomSeverity, 1 - tierEffects.symptomRelief)
        disease.symptomReliefUntil = currentHour + doseTiming.activeHours
        disease.symptomReliefMedKey = medKey
        EHR.Log("Applied symptom relief: " .. (tierEffects.symptomRelief * 100) .. "% to " .. diseaseId)
    end

    EHR_MedicationApplyImmediateSymptomRelief(player, diseaseId, medData, doseTiming, currentHour)
    if medData.respiratorySupport and EHR.Medication.StartRespiratorySupport then
        EHR.Medication.StartRespiratorySupport(player, medData)
    end
    if medData.sleepAid and EHR.Medication.StartSleepAid then
        EHR.Medication.StartSleepAid(player, medData)
    end

    -- Track dose for this medication
    if not medTracking.activeDoses[medKey] then
        -- First dose of this medication
        medTracking.activeDoses[medKey] = {
            firstDoseTime = currentHour,
            lastDoseTime = currentHour,
            doseCount = 1,
            totalDosesNeeded = doseTiming.dosesRequired,
            intervalHours = doseTiming.doseInterval,
            activeHours = doseTiming.activeHours,
            medicationName = medData.displayName,
            tier = medData.tier,
            treatingDisease = diseaseId,
            diseaseTargets = { [diseaseId] = true },
            symptomOnly = doseTiming.symptomOnly,
            requiresDoseCourse = canCure,
        }
    else
        -- Subsequent dose
        local doseData = medTracking.activeDoses[medKey]
        if not tonumber(doseData.firstDoseTime) then
            local previousTreatment = medTracking.activeTreatments[diseaseId]
            if type(previousTreatment) == "table" and previousTreatment.medKey == medKey then
                doseData.firstDoseTime = tonumber(previousTreatment.startTime)
            end
            if not tonumber(doseData.firstDoseTime) then
                local previousLastDose = tonumber(doseData.lastDoseTime) or currentHour
                local previousDoseCount = math.max(1, tonumber(doseData.doseCount) or 1)
                local intervalHours = math.max(0, tonumber(doseData.intervalHours) or doseTiming.doseInterval or 0)
                doseData.firstDoseTime = math.max(0, previousLastDose - ((previousDoseCount - 1) * intervalHours))
            end
        end
        local sameDoseEvent = math.abs((tonumber(doseData.lastDoseTime) or -999999) - currentHour) < 0.001
        doseData.lastDoseTime = currentHour
        if not sameDoseEvent then
            doseData.doseCount = (doseData.doseCount or 0) + 1
        end
        doseData.totalDosesNeeded = doseTiming.dosesRequired
        doseData.intervalHours = doseTiming.doseInterval
        doseData.activeHours = doseTiming.activeHours
        doseData.medicationName = medData.displayName
        doseData.tier = medData.tier
        doseData.diseaseTargets = doseData.diseaseTargets or {}
        if doseData.treatingDisease then
            doseData.diseaseTargets[doseData.treatingDisease] = true
        end
        doseData.diseaseTargets[diseaseId] = true
        doseData.treatingDisease = doseData.treatingDisease or diseaseId
        doseData.symptomOnly = doseTiming.symptomOnly
        doseData.requiresDoseCourse = canCure
    end

    -- Start or continue cure process if tier can cure.
    if canCure then
        local cureTimeHours = EHR.Medication.GetCureTimeHours(medData, diseaseId, tierEffects)
        local existingTreatment = medTracking.activeTreatments[diseaseId]

        if existingTreatment and existingTreatment.medKey == medKey then
            -- Continuing the same course should not reset accumulated treatment time.
            existingTreatment.cureTimeHours = existingTreatment.cureTimeHours or cureTimeHours
            existingTreatment.medicationName = medData.displayName
            existingTreatment.tier = medData.tier
            existingTreatment.medKey = medKey
            existingTreatment.awaitingDoses = nil

            local doseData = medTracking.activeDoses[medKey] or {}
            EHR.Log("Continued treatment for " .. diseaseId .. " - dose " ..
                    tostring(doseData.doseCount or 0) .. "/" ..
                    tostring(doseData.totalDosesNeeded or 1))
        else
            local doseData = medTracking.activeDoses[medKey] or {}
            medTracking.activeTreatments[diseaseId] = {
                startTime = tonumber(doseData.firstDoseTime) or currentHour,
                cureTimeHours = cureTimeHours,
                medicationName = medData.displayName,
                tier = medData.tier,
                medKey = medKey,
                awaitingDoses = nil,
            }

            EHR.Log("Started treatment for " .. diseaseId .. " - cure in " ..
                    medTracking.activeTreatments[diseaseId].cureTimeHours .. " hours")
        end
    end

    -- Check for drug interactions
    EHR.Medication.CheckAndApplyInteractions(player)
end

-- ============================================
-- DRUG INTERACTION CHECKING
-- ============================================

function EHR.Medication.GetActiveCategories(player)
    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return {} end

    local categories = {}

    for medKey, doseData in pairs(medTracking.activeDoses) do
        local status = EHR.Medication.GetDoseStatus(player, medKey)
        if status and status.isDoseActive then
            local medData = EHR.Medication.Database and EHR.Medication.Database[medKey] or nil
            local category = EHR.Medication.DrugCategories[doseData.medicationName]
            if category and not (medData and medData.skipDrugInteractions) then
                categories[category] = true
            end
        end
    end

    return categories
end

function EHR.Medication.CheckDrugInteractions(player)
    local activeCategories = EHR.Medication.GetActiveCategories(player)
    local interactions = {}

    for _, interaction in ipairs(EHR.Medication.DrugInteractions) do
        local allPresent = true
        for _, drug in ipairs(interaction.drugs) do
            if not activeCategories[drug] then
                allPresent = false
                break
            end
        end

        if allPresent then
            table.insert(interactions, {
                severity = interaction.severity,
                message = interaction.message,
            })
        end
    end

    return interactions
end

function EHR.Medication.CheckAndApplyInteractions(player)
    local activeCategories = EHR.Medication.GetActiveCategories(player)

    for _, interaction in ipairs(EHR.Medication.DrugInteractions) do
        local allPresent = true
        for _, drug in ipairs(interaction.drugs) do
            if not activeCategories[drug] then
                allPresent = false
                break
            end
        end

        if allPresent and interaction.effect then
            interaction.effect(player)
            EHR.Log("Drug interaction triggered: " .. interaction.message)

            if player.isLocalPlayer and player:isLocalPlayer() then
                EHR.Locale.Say(player, "I don't feel right... these medications might not mix well.")
            end
        end
    end
end

-- ============================================
-- DOSE STATUS FUNCTIONS
-- ============================================

local function EHR_MedicationGetMaxOverdueHours(intervalHours)
    intervalHours = tonumber(intervalHours) or 0
    if intervalHours <= 0 then return 0 end
    return math.max(24, math.min(72, intervalHours * 3))
end

function EHR.Medication.GetDoseStatus(player, medKey)
    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking or not medTracking.activeDoses[medKey] then
        return nil
    end

    local doseData = medTracking.activeDoses[medKey]
    if type(doseData) ~= "table" or not doseData.lastDoseTime then
        return nil
    end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    local elapsed = currentHour - doseData.lastDoseTime
    local medData = EHR.Medication.Database and EHR.Medication.Database[medKey] or nil
    local tier = doseData.tier or (medData and medData.tier) or 0
    local tierEffects = EHR.Medication.TierEffectiveness[tier] or EHR.Medication.TierEffectiveness[0]
    local doseTiming = EHR_MedicationGetDoseTiming(medData or { tier = tier }, medKey, tierEffects)
    local intervalHours = doseData.intervalHours
    if intervalHours == nil then intervalHours = doseTiming.doseInterval end
    local activeHours = doseData.activeHours
    if activeHours == nil then activeHours = doseTiming.activeHours end
    local totalDosesNeeded = doseData.totalDosesNeeded or doseTiming.dosesRequired
    if medKey == "Base.PillsBeta" or medKey == "Base.Pills" then
        -- Migrate active vanilla-drug doses saved by older builds to the current
        -- EHR duration/course definition instead of retaining stale schedules.
        intervalHours = doseTiming.doseInterval
        activeHours = doseTiming.activeHours
        totalDosesNeeded = doseTiming.dosesRequired
    end
    local medCanCure = EHR_MedicationCanCure(medData, tierEffects)
    local requiresDoseCourse = doseData.requiresDoseCourse == true
        or (doseData.treatingDisease ~= nil and medCanCure)
    if doseTiming.symptomOnly and not requiresDoseCourse then
        totalDosesNeeded = 1
    end

    local doseCount = doseData.doseCount or 0
    local treatmentComplete = doseCount >= totalDosesNeeded
    local nextDoseIn = (not treatmentComplete and intervalHours > 0) and math.max(0, intervalHours - elapsed) or 0
    local isOverdue = (not treatmentComplete) and intervalHours > 0 and elapsed > intervalHours
    local hoursOverdue = isOverdue and (elapsed - intervalHours) or 0
    local maxOverdueHours = EHR_MedicationGetMaxOverdueHours(intervalHours)
    local isDoseActive = activeHours > 0 and elapsed >= 0 and elapsed <= activeHours
    local hoursActiveRemaining = isDoseActive and math.max(0, activeHours - elapsed) or 0

    return {
        medKey = medKey,
        medicationName = doseData.medicationName,
        tier = tier,
        treatingDisease = doseData.treatingDisease,
        doseCount = doseCount,
        totalDosesNeeded = totalDosesNeeded,
        dosesRemaining = math.max(0, totalDosesNeeded - doseCount),
        intervalHours = intervalHours,
        activeHours = activeHours,
        hoursSinceLastDose = elapsed,
        hoursUntilNextDose = nextDoseIn,
        isDoseActive = isDoseActive,
        hoursActiveRemaining = hoursActiveRemaining,
        isOverdue = isOverdue,
        hoursOverdue = hoursOverdue,
        maxOverdueHours = maxOverdueHours,
        isStaleOverdue = isOverdue and maxOverdueHours > 0 and hoursOverdue > maxOverdueHours,
        treatmentComplete = treatmentComplete,
        symptomOnly = doseTiming.symptomOnly or doseData.symptomOnly == true,
        requiresDoseCourse = requiresDoseCourse,
    }
end

function EHR.Medication.IsAntibioticMedication(medKey, doseData)
    local medData = EHR.Medication.Database and EHR.Medication.Database[medKey] or nil
    if medData and medData.isTopical == true then
        return false
    end

    if EHR.Medication.AntibioticMedications
            and EHR.Medication.AntibioticMedications[medKey] == true then
        return true
    end

    if medData and medData.isAntibiotic ~= nil then
        return medData.isAntibiotic == true
    end

    local medicationName = doseData and doseData.medicationName
        or (medData and medData.displayName)
    local category = medicationName
        and EHR.Medication.DrugCategories
        and EHR.Medication.DrugCategories[medicationName]
        or nil

    return category == "antibiotic"
        or category == "iv antibiotic"
        or category == "tb antibiotics"
        or category == "rifampicin"
end

function EHR.Medication.HasActiveAntibiotic(player)
    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking or type(medTracking.activeDoses) ~= "table" then
        return false
    end

    for medKey, doseData in pairs(medTracking.activeDoses) do
        if EHR.Medication.IsAntibioticMedication(medKey, doseData) then
            local ok, status = pcall(EHR.Medication.GetDoseStatus, player, medKey)
            if ok and status and status.isDoseActive then
                return true, medKey, status
            end
        end
    end

    return false
end

function EHR.Medication.RefreshImmunityForAntibiotic(player, medKey)
    if not EHR.Medication.IsAntibioticMedication(medKey) then return false end
    if not EHR.Immunity or type(EHR.Immunity.UpdatePlayer) ~= "function" then return false end

    local ok = pcall(EHR.Immunity.UpdatePlayer, player, true)
    return ok
end

function EHR.Medication.GetAllDoseStatuses(player)
    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return {} end

    local statuses = {}

    for medKey, doseData in pairs(medTracking.activeDoses) do
        local status = EHR.Medication.GetDoseStatus(player, medKey)
        if status and not status.isStaleOverdue and (status.isDoseActive or status.isOverdue or not status.treatmentComplete) then
            table.insert(statuses, status)
        end
    end

    -- Sort by urgency (overdue first, then by time until next dose)
    table.sort(statuses, function(a, b)
        if a.isOverdue and not b.isOverdue then return true end
        if b.isOverdue and not a.isOverdue then return false end
        if a.isOverdue and b.isOverdue then
            return a.hoursOverdue > b.hoursOverdue
        end
        return a.hoursUntilNextDose < b.hoursUntilNextDose
    end)

    return statuses
end

function EHR.Medication.IsTreatmentCourseComplete(player, treatment)
    if not player or not treatment then return false end
    if not treatment.medKey then return true end

    local status = EHR.Medication.GetDoseStatus(player, treatment.medKey)
    if not status then
        -- Older saves may have active treatment data without dose metadata.
        return true
    end

    return status.treatmentComplete == true
end

-- Multi-dose courses finish on their final scheduled dose. Configured cure time
-- remains authoritative for single-dose treatments that are meant to work over time.
function EHR.Medication.GetTreatmentCompletionHours(player, treatment)
    if not treatment then return 0 end

    local configuredHours = math.max(0, tonumber(treatment.cureTimeHours) or 0)
    if not player or not treatment.medKey then
        return configuredHours
    end

    local status = EHR.Medication.GetDoseStatus(player, treatment.medKey)
    if not status or status.requiresDoseCourse ~= true then
        return configuredHours
    end

    local totalDoses = math.max(1, tonumber(status.totalDosesNeeded) or 1)
    local intervalHours = math.max(0, tonumber(status.intervalHours) or 0)
    if totalDoses <= 1 or intervalHours <= 0 then
        return configuredHours
    end

    return (totalDoses - 1) * intervalHours
end

function EHR.Medication.ApplySideEffect(player, effectId, options)
    if not player or not effectId then return end

    local sideEffect = EHR.Medication.SideEffects[effectId]
    if not sideEffect then return end
    options = options or {}

    local medTracking = EHR.Medication.GetMedicationData(player)
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()
    local existing = medTracking.activeSideEffects and medTracking.activeSideEffects[effectId]
    if existing and type(existing) == "table" and not options.force then
        local existingDuration = tonumber(existing.duration) or sideEffect.duration or 0
        local existingStart = tonumber(existing.startTime) or currentHour
        if existingDuration <= 0 or currentHour - existingStart < existingDuration then
            if sideEffect.effects then
                sideEffect.effects(player, existing)
            end
            EHRMedicationRefreshMoodles(player, true)
            EHR.Log("Side effect already active, not refreshing timer: " .. tostring(effectId))
            return false
        end
    end

    medTracking.activeSideEffects[effectId] = {
        startTime = currentHour,
        duration = options.duration or sideEffect.duration,
    }

    -- Apply immediate effect
    if sideEffect.effects then
        sideEffect.effects(player, medTracking.activeSideEffects[effectId])
    end
    EHRMedicationRefreshMoodles(player, true)
    EHRMedicationRequestSync(player)

    if player.isLocalPlayer and player:isLocalPlayer() then
        EHR.Locale.Say(player, "Side effect: " .. sideEffect.displayName)

        if effectId == "dizziness" and EHR.ToxinVision and EHR.ToxinVision.StartMedicationEpisode then
            EHR.ToxinVision.StartMedicationEpisode(player)
        end
    end

    EHR.Log("Applied side effect: " .. effectId .. " (duration: " .. sideEffect.duration .. " hours)")
    return true
end

function EHR.Medication.CureModuleDisease(player, diseaseId, treatment)
    if not player or not diseaseId then return false end

    if diseaseId == "wound_infection" then
        if EHR.WoundInfection and EHR.WoundInfection.CureAll then
            return EHR.WoundInfection.CureAll(
                player,
                treatment and treatment.medicationName or "medication"
            ) == true
        elseif EHR.WoundInfection and EHR.WoundInfection.OnTakeAntibiotics then
            EHR.WoundInfection.OnTakeAntibiotics(player)
            return true
        end
        return false
    end

    if diseaseId == "sepsis" then
        if EHR.Sepsis and EHR.Sepsis.Cure then
            local hasSepsis = true
            if EHR.Sepsis.HasSepsis then
                hasSepsis = EHR.Sepsis.HasSepsis(player)
            end
            if hasSepsis then
                EHR.Sepsis.Cure(player)
            end
        end
        return true
    end

    return false
end

-- ============================================
-- MEDICATION UPDATE LOOP
-- ============================================

function EHR.Medication.Update(player)
    if not player then return end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()
    local authoritative = EHRMedicationIsAuthoritative()

    local syncNeeded = false
    if EHR.Medication.UpdateGeneralEffects then
        syncNeeded = EHR.Medication.UpdateGeneralEffects(player, medTracking, currentHour) == true or syncNeeded
    end

    -- Update active treatments
    local treatmentsToRemove = {}
    for diseaseId, treatment in pairs(medTracking.activeTreatments) do
        if type(treatment) ~= "table" then
            table.insert(treatmentsToRemove, diseaseId)
        else
            local startTime = tonumber(treatment.startTime)
            local cureTimeHours = EHR.Medication.GetTreatmentCompletionHours(player, treatment)

            if not startTime or not cureTimeHours or cureTimeHours <= 0 then
                if authoritative then
                    table.insert(treatmentsToRemove, diseaseId)
                    EHR.Log("Removed invalid active treatment data for " .. tostring(diseaseId))
                end
            else
                local elapsed = math.max(0, currentHour - startTime)
                local courseComplete = EHR.Medication.IsTreatmentCourseComplete(player, treatment)

                if authoritative and elapsed >= cureTimeHours and courseComplete then
                    -- Treatment complete - cure the disease
                    local moduleCured = EHR.Medication.CureModuleDisease
                        and EHR.Medication.CureModuleDisease(player, diseaseId, treatment)
                    if moduleCured then
                        if player.isLocalPlayer and player:isLocalPlayer() then
                            EHR.Locale.Say(player, "Treatment complete. " .. (treatment.medicationName or "Medication") .. " has cured your condition.")
                        end
                    elseif EHR.Disease and EHR.Disease.Cure then
                        EHR.Disease.Cure(player, diseaseId)
                        if player.isLocalPlayer and player:isLocalPlayer() then
                            EHR.Locale.Say(player, "Treatment complete. " .. (treatment.medicationName or "Medication") .. " has cured your condition.")
                        end
                    end
                    table.insert(treatmentsToRemove, diseaseId)
                    syncNeeded = true
                elseif authoritative and elapsed >= cureTimeHours and not courseComplete then
                    if not treatment.awaitingDoses then
                        treatment.awaitingDoses = true
                        EHR.Log("Treatment time reached for " .. diseaseId .. " but course still needs more doses")
                    end
                end
            end
        end
    end

    for _, diseaseId in ipairs(treatmentsToRemove) do
        medTracking.activeTreatments[diseaseId] = nil
        syncNeeded = true
    end

    -- Update active side effects
    local effectsToRemove = {}
    local appliedStatEffect = false
    for effectId, effectData in pairs(medTracking.activeSideEffects) do
        if type(effectData) ~= "table" then
            if authoritative then
                table.insert(effectsToRemove, effectId)
            end
        else
            local sideEffect = EHR.Medication.SideEffects[effectId]
            if not sideEffect then
                if authoritative then
                    table.insert(effectsToRemove, effectId)
                end
            else
                local startTime = tonumber(effectData.startTime) or currentHour
                local duration = tonumber(effectData.duration) or sideEffect.duration or 0
                if startTime > currentHour + 168 then
                    -- Older debug builds used os.time() here; convert impossible timestamps
                    -- back to world-age hours so MP cleanup can expire them normally.
                    startTime = currentHour
                end
                effectData.startTime = startTime
                effectData.duration = duration

                local elapsed = math.max(0, currentHour - startTime)

                if duration <= 0 or elapsed >= duration then
                    -- Side effect expired
                    if not effectData.clientExpired and sideEffect.onEnd then
                        sideEffect.onEnd(player)
                    end
                    if not effectData.clientExpired and EHRMedicationIsMultiplayer() and sideEffect.mpFatigueRecoveryTarget then
                        EHRMedicationStartMPFatigueRecovery(player, sideEffect.mpFatigueRecoveryTarget, sideEffect.mpFatigueRecoveryHours)
                    end
                    if authoritative then
                        table.insert(effectsToRemove, effectId)
                    else
                        effectData.clientExpired = true
                    end
                    if not effectData.clientExpiredLogged then
                        EHR.Log("Side effect expired: " .. effectId)
                        effectData.clientExpiredLogged = true
                    end
                else
                    -- Reapply effect each tick
                    if sideEffect.effects then
                        sideEffect.effects(player, effectData)
                        appliedStatEffect = true
                    end
                end
            end
        end
    end

    for _, effectId in ipairs(effectsToRemove) do
        medTracking.activeSideEffects[effectId] = nil
        syncNeeded = true
    end

    EHRMedicationClearStaleSideEffectFlags(player, medTracking.activeSideEffects)
    if appliedStatEffect then
        EHRMedicationRefreshMoodles(player)
    end
    if syncNeeded then
        EHRMedicationRequestSync(player)
    end

    -- Remove completed symptom-only dose entries once their actual effect has ended,
    -- and clear abandoned multi-dose courses so OVERDUE alerts do not live forever.
    local dosesToRemove = {}
    local treatmentsToAbandon = {}
    for medKey, _ in pairs(medTracking.activeDoses) do
        local status = EHR.Medication.GetDoseStatus(player, medKey)
        if not status then
            table.insert(dosesToRemove, medKey)
        elseif status.isStaleOverdue then
            table.insert(dosesToRemove, medKey)
            for diseaseId, treatment in pairs(medTracking.activeTreatments) do
                if type(treatment) == "table" and treatment.medKey == medKey then
                    treatmentsToAbandon[diseaseId] = true
                end
            end
            EHR.Log(string.format(
                "Abandoned stale dose schedule for %s (overdue %.1fh)",
                tostring(status.medicationName or medKey),
                tonumber(status.hoursOverdue) or 0
            ))
        elseif status.treatmentComplete and not status.isDoseActive and not status.isOverdue then
            local usedByTreatment = false
            for _, treatment in pairs(medTracking.activeTreatments) do
                if type(treatment) == "table" and treatment.medKey == medKey then
                    usedByTreatment = true
                    break
                end
            end

            if not usedByTreatment then
                table.insert(dosesToRemove, medKey)
            end
        end
    end

    for _, medKey in ipairs(dosesToRemove) do
        medTracking.activeDoses[medKey] = nil
    end

    for diseaseId, _ in pairs(treatmentsToAbandon) do
        medTracking.activeTreatments[diseaseId] = nil
        EHR.Log("Abandoned active treatment after missed dose window: " .. tostring(diseaseId))
    end
end

function EHR.Medication.ClearAllSideEffectState(player, resetStats)
    if not player then return false end

    local modData = player:getModData()
    if not modData then return false end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if medTracking then
        if medTracking.activeSideEffects then
            for effectId, effectData in pairs(medTracking.activeSideEffects) do
                local sideEffect = EHR.Medication.SideEffects and EHR.Medication.SideEffects[effectId]
                if sideEffect and sideEffect.onEnd then
                    pcall(function() sideEffect.onEnd(player, effectData) end)
                end
                medTracking.activeSideEffects[effectId] = nil
            end
        end

        if medTracking.activeGeneralEffects then
            medTracking.activeGeneralEffects.staminaLock = nil
            medTracking.activeGeneralEffects.fatigueBlock = nil
            medTracking.activeGeneralEffects.combatStimulants = nil
            medTracking.activeGeneralEffects.lastChanceEpinephrine = nil
            medTracking.activeGeneralEffects.mpFatigueRecovery = nil
            medTracking.activeGeneralEffects.warmingPack = nil
        end
    end

    if modData.EHR_SideEffects then
        for effectId, _ in pairs(modData.EHR_SideEffects) do
            modData.EHR_SideEffects[effectId] = nil
        end
    end

    EHRMedicationRestoreCombatWeaponSpeed(player)
    EHRMedicationClearCombatSpeedBoost(player)
    EHRMedicationClearKidneyBackPain(player)
    EHRMedicationClearWholeBodyMusclePain(player)
    EHRMedicationClearCombatStimulantLimbPain(player)
    modData.EHR_TendonWeakness = nil
    modData.EHR_KidneyStress = nil
    modData.EHR_Insomnia = nil
    modData.EHR_Immunosuppressed = nil
    modData.EHR_LiverStress = nil
    modData.EHR_CaffeineAwake = nil
    modData.EHR_CombatStimulantsActive = nil
    modData.EHR_CombatStimSpeedActive = nil
    modData.EHR_CombatStimWeaponId = nil

    if resetStats ~= false then
        local stats = EHRMedicationGetStats(player)
        if stats and CharacterStat then
            EHRMedicationCapStat(stats, CharacterStat.PAIN, 0.05)
            EHRMedicationCapStat(stats, CharacterStat.DISCOMFORT, 0.05)
            EHRMedicationCapStat(stats, CharacterStat.FATIGUE, 0.25)
            EHRMedicationCapStat(stats, CharacterStat.SICKNESS, 0.05)
            EHRMedicationCapStat(stats, CharacterStat.FOOD_SICKNESS, 0.05)
            EHRMedicationCapStat(stats, CharacterStat.THIRST, 0.45)
            EHRMedicationRaiseStat(stats, CharacterStat.ENDURANCE, 0.70)
            if stats.getSickness and stats.setSickness then
                pcall(function()
                    local current = stats:getSickness() or 0
                    if current > 0.05 then
                        stats:setSickness(0.05)
                    end
                end)
            end
        end
    end

    EHRMedicationClearStaleSideEffectFlags(player, {})
    EHRMedicationRefreshMoodles(player, true)
    return true
end

-- ============================================
-- GET ACTIVE TREATMENT INFO (for UI)
-- ============================================

function EHR.Medication.GetActiveTreatments(player)
    if not player then return {} end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return {} end

    local treatments = {}
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    for diseaseId, treatment in pairs(medTracking.activeTreatments) do
        if type(treatment) == "table" then
            local startTime = tonumber(treatment.startTime)
            local cureTimeHours = EHR.Medication.GetTreatmentCompletionHours(player, treatment)
            if startTime and cureTimeHours and cureTimeHours > 0 then
                local elapsed = math.max(0, currentHour - startTime)
                local remaining = cureTimeHours - elapsed
                local progress = elapsed / cureTimeHours

                -- Get dose information if available
                local doseInfo = nil
                if treatment.medKey then
                    doseInfo = EHR.Medication.GetDoseStatus(player, treatment.medKey)
                end
                local courseComplete = EHR.Medication.IsTreatmentCourseComplete(player, treatment)

                table.insert(treatments, {
                    diseaseId = diseaseId,
                    medKey = treatment.medKey,
                    medicationName = treatment.medicationName,
                    tier = treatment.tier,
                    hoursRemaining = math.max(0, remaining),
                    progress = math.min(1, progress),
                    -- Dose timing info
                    doseCount = doseInfo and doseInfo.doseCount or 0,
                    totalDosesNeeded = doseInfo and doseInfo.totalDosesNeeded or 0,
                    dosesRemaining = doseInfo and doseInfo.dosesRemaining or 0,
                    hoursUntilNextDose = doseInfo and doseInfo.hoursUntilNextDose or 0,
                    isDoseActive = doseInfo and doseInfo.isDoseActive or false,
                    hoursActiveRemaining = doseInfo and doseInfo.hoursActiveRemaining or 0,
                    isOverdue = doseInfo and doseInfo.isOverdue or false,
                    hoursOverdue = doseInfo and doseInfo.hoursOverdue or 0,
                    courseComplete = courseComplete,
                    awaitingDoses = treatment.awaitingDoses == true,
                })
            end
        end
    end

    return treatments
end

function EHR.Medication.GetActiveSideEffects(player)
    if not player then return {} end

    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return {} end

    local effects = {}
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    for effectId, effectData in pairs(medTracking.activeSideEffects) do
        local sideEffect = EHR.Medication.SideEffects[effectId]
        if sideEffect and type(effectData) == "table" then
            local startTime = tonumber(effectData.startTime)
            local duration = tonumber(effectData.duration) or sideEffect.duration
            if startTime and duration and effectData.clientExpired ~= true then
                local elapsed = math.max(0, currentHour - startTime)
                local remaining = duration - elapsed

                if remaining > (1 / 60) then
                    table.insert(effects, {
                        effectId = effectId,
                        displayName = sideEffect.displayName,
                        severity = sideEffect.severity,
                        hoursRemaining = math.max(0, remaining),
                    })
                end
            end
        end
    end

    return effects
end

-- Add predictable dose-bound effects to the UI without registering them as
-- activeSideEffects. The latter is also consumed by moodles and gameplay
-- effect handlers, while this list is informational and monitor-only.
function EHR.Medication.AppendDoseSideEffectsForMonitor(effects, doseStatuses)
    effects = effects or {}

    local seen = {}
    for _, effect in pairs(effects) do
        if type(effect) == "table" and effect.effectId then
            seen[tostring(effect.effectId)] = true
        end
    end

    for keyFromMap, status in pairs(doseStatuses or {}) do
        if type(status) == "table" and status.isDoseActive == true then
            local remaining = math.max(0, tonumber(status.hoursActiveRemaining) or 0)
            if remaining > (1 / 60) then
                local medKey = status.medKey or tostring(keyFromMap)
                local medData = EHR.Medication.Database and EHR.Medication.Database[medKey] or nil
                for _, effectData in ipairs((medData and medData.monitorSideEffects) or {}) do
                    local effectId = effectData.effectId
                    if effectId and not seen[effectId] then
                        table.insert(effects, {
                            effectId = effectId,
                            displayName = EHR.Medication.GetSideEffectDisplayName(effectId, effectData),
                            severity = tonumber(effectData.severity) or 1,
                            hoursRemaining = remaining,
                            medicationName = status.medicationName or (medData and medData.displayName),
                            doseBound = true,
                        })
                        seen[effectId] = true
                    end
                end
            end
        end
    end

    return effects
end

function EHR.Medication.GetMonitorSideEffects(player)
    if not player then return {} end

    local effects = EHR.Medication.GetActiveSideEffects(player)
    local doseStatuses = EHR.Medication.GetAllDoseStatuses(player)
    return EHR.Medication.AppendDoseSideEffectsForMonitor(effects, doseStatuses)
end

-- ============================================
-- CONTEXT MENU INTEGRATION
-- ============================================

local function OnMedicationContextMenu(player, context, items)
    -- Skip if enhanced medication action module is loaded (handles context menu with timed actions)
    if EHR.MedicationAction and EHR.MedicationAction.Enabled then
        return
    end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then
            if v.items and v.items[1] then
                item = v.items[1]
            end
        end

        if item and instanceof(item, "InventoryItem") then
            local itemFullType = item:getFullType()
            local medData = EHR.Medication.Database[itemFullType]

            if medData then
                local canUse, reason = EHR.Medication.CanUseMedication(playerObj, item)
                local tierName = ""
                if medData.tier == 0 then tierName = " (Basic)"
                elseif medData.tier == 1 then tierName = " (OTC)"
                elseif medData.tier == 2 then tierName = " (Prescription)"
                elseif medData.tier == 3 then tierName = " (Clinical)"
                end

                local optionName = "Use " .. medData.displayName .. tierName
                local option = context:addOption(optionName, playerObj, function(plr)
                    EHR.Medication.UseMedication(plr, item)
                end)
                if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

                if not canUse then
                    option.notAvailable = true
                    local tooltip = ISWorldObjectContextMenu.addToolTip()
                    tooltip:setName(medData.displayName)
                    tooltip.description = reason
                    option.toolTip = tooltip
                end
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(OnMedicationContextMenu)

-- ============================================
-- HOOK INTO MAIN UPDATE LOOP
-- ============================================

local function OnPlayerUpdate(player)
    if not player or player:isDead() then return end
    EHR.Medication.Update(player)
end

Events.OnPlayerUpdate.Add(OnPlayerUpdate)

-- ============================================
-- VANILLA MEDICATION CONSUMPTION TRACKING
-- Hook into game's native eat/use system
-- ============================================

-- Track when vanilla medications are consumed via game's native handlers
-- This catches medications used through right-click "Eat" or "Take" options
-- HIGH FIX: Added protection for item deletion during processing
local function OnEatItemHandler(character, item)
    -- HIGH FIX: Wrap in pcall to prevent crash if item is deleted mid-processing
    local success, err = pcall(function()
        if not character or not item then return end
        if not character:isLocalPlayer() then return end

        -- HIGH FIX: Validate item still exists and has getFullType method
        if not item.getFullType then return end
        local itemFullType = item:getFullType()
        if not itemFullType then return end

        local medData = EHR.Medication.Database[itemFullType]

        if medData and medData.consumeViaFoodHook == true then
            return
        end

        -- Only track if it's a recognized medication and wasn't already tracked
        -- (EHR context menu usage already tracks, so check if recently tracked)
        if medData then
            local medTracking = EHR.Medication.GetMedicationData(character)
            if not medTracking then return end  -- HIGH FIX: Additional nil guard

            local gameTime = getGameTime()
            if not gameTime then return end  -- HIGH FIX: Additional nil guard
            local currentHour = gameTime:getWorldAgeHours()

            local medKey = itemFullType
            local existingDose = medTracking.activeDoses[medKey]

            -- If no existing dose OR last dose was more than 1 minute ago, track this as a new dose
            -- (prevents double-tracking when using EHR context menu)
            local shouldTrack = true
            if existingDose and existingDose.lastDoseTime then
                local timeSinceLastDose = currentHour - existingDose.lastDoseTime
                -- 1 minute = 1/60 hour ≈ 0.017
                if timeSinceLastDose < 0.02 then
                    shouldTrack = false -- Already tracked very recently (likely from EHR context menu)
                end
            end

            if shouldTrack then
                EHR.Log("Vanilla medication consumed via native handler: " .. itemFullType)

                -- In MP the server owns EHR disease and medication state. The
                -- vanilla action has already consumed the physical dose, so
                -- request the effect-only server path and do not mutate the
                -- client's temporary copy of EHR modData.
                if isClient and isClient() and EHR.Medication.UseConsumedMedication then
                    EHR.Medication.UseConsumedMedication(character, itemFullType)
                    return
                end

                if EHR.Medication.ShouldConsumeActiveDoseWithoutTreatment(character, medData, itemFullType) then
                    if medData.activeDoseMessage and character:isLocalPlayer() then
                        EHR.Locale.Say(character, medData.activeDoseMessage)
                    end
                    EHR.Log("Vanilla medication consumed too early without treatment progress: " .. itemFullType)
                    return
                end

                -- Check if treating any disease
                local diseaseData = EHR.Disease and EHR.Disease.GetDiseaseData(character)
                local treatedDisease = false

                if diseaseData and diseaseData.active and medData.treats then
                    for _, diseaseId in ipairs(medData.treats) do
                        if diseaseData.active[diseaseId] then
                            -- Apply treatment
                            local tier = medData.tier or 0
                            local tierEffects = EHR.Medication.TierEffectiveness[tier]
                            if tierEffects then
                                EHR.Medication.ApplyTreatment(character, diseaseId, medData, tierEffects, itemFullType)
                                treatedDisease = true
                            end
                        end
                    end
                end

                -- If no disease treated, still track the dose
                if not treatedDisease then
                    EHR.Medication.TrackDoseOnly(character, medData, itemFullType)
                end

                EHR.Medication.RefreshImmunityForAntibiotic(character, itemFullType)

                -- Show usage message if defined
                if medData.usageMessage and character:isLocalPlayer() then
                    EHR.Locale.Say(character, medData.usageMessage)
                end
            end
        end
    end)

    -- HIGH FIX: Log any errors but don't crash
    if not success and err then
        if EHR and EHR.Log then
            EHR.Log("WARNING: OnEatItemHandler error (item may have been deleted): " .. tostring(err))
        end
    end
end

-- Hook into PZ's OnEat callback
if Events.OnEat then
    Events.OnEat.Add(OnEatItemHandler)
    EHR.Log("Hooked OnEat event for vanilla medication tracking")
end

-- Alternative hook for B42's newer item consumption system
if Events.OnPlayerEatFood then
    Events.OnPlayerEatFood.Add(OnEatItemHandler)
    EHR.Log("Hooked OnPlayerEatFood event for vanilla medication tracking")
end

EHR.Log("EHR_Medication.lua loaded - 4-Tier Medication System active")
