--[[
    Extensive Health Rework - Medication System

    4-Tier Medication System:
    - Tier 0: Vanilla items (minimal relief, 10-20% symptom reduction)
    - Tier 1: OTC (Over-the-counter) - 30-50% symptom relief only
    - Tier 2: Prescription - Cures disease at normal rate
    - Tier 3: Clinical Grade - 2x cure speed + side effects

    Author: ExtensiveHealthRework Team
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
        usageMessage = "You take painkillers. The pain eases slightly.",
    },

    -- Base.PillsVitamins (B42 caffeine pills)
    ["Base.PillsVitamins"] = {
        tier = 0,
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
        treats = {},
        displayName = "Sleeping Pills",
        icon = "PillsSleeping",
        useVanillaActionOnly = true,
        skipDrugInteractions = true,
        appliesWithoutDisease = true,
        effectDurationHours = 8,
        usageMessage = "You take sleeping pills. Drowsiness settles in.",
    },

    -- Base.PillsBeta
    ["Base.PillsBeta"] = {
        tier = 0,
        treats = {"heat_exhaustion", "hypothermia"},
        displayName = "Beta Blockers",
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

    ["ExtensiveHealth.CoughSyrup"] = {
        tier = 1,
        treats = {"common_cold", "pneumonia", "cadaveric_aspergillosis"},
        displayName = "Cough Syrup",
        usageMessage = "You drink the cough syrup. The coughing subsides.",
        symptomReduction = {
            coughing = 0.50,
        },
    },

    ["ExtensiveHealth.ElectrolytePowder"] = {
        tier = 1,
        treats = {"dysentery", "food_poisoning", "gastroenteritis", "toxin_poisoning", "heat_exhaustion", "heat_stroke"},
        displayName = "Electrolyte Powder",
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
        treats = {"wound_infection", "trichinosis", "tetanus", "ahtr"},
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
        treats = {"dysentery", "heat_exhaustion"},
        displayName = "Oral Rehydration Kit",
        usageMessage = "You prepare and drink the rehydration solution.",
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
        usageMessage = "You use the respiratory support kit. Fresh oxygen and airway support help you recover.",
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
        treats = {},
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
                player:Say("*gasps* The adrenaline is kicking in!")
                EHR.Log("Epinephrine woke player from blackout sleep!")
            end
            EHR.Log("Epinephrine administered - emergency stimulant effects applied")
        end,
        sideEffects = {"headache", "insomnia"},
    },

    -- =========================================
    -- EXTERNAL MOD COMPATIBILITY: They Knew
    -- Knox Virus cure from They Knew mod
    -- =========================================

    ["TheyKnew.Zomboxivir"] = {
        tier = 3,
        treats = {}, -- Knox cure handled via immediateEffects
        displayName = "Zomboxivir Ampule",
        usageMessage = "*breaks ampule* The experimental cure enters your bloodstream...",
        isKnoxCure = true,
        totalDosesNeeded = 1, -- Single use cure
        immediateEffects = function(player)
            if not player then return end
            -- Use EHR's Knox cure system if available
            if EHR.KnoxCure and EHR.KnoxCure.IsInfected and EHR.KnoxCure.CureInfection then
                if EHR.KnoxCure.IsInfected(player) then
                    EHR.KnoxCure.CureInfection(player)
                    player:Say("*gasps* I can feel it... the infection is gone!")
                    EHR.Log("Zomboxivir cured Knox infection via EHR system")
                else
                    player:Say("I'm not infected... that was a waste.")
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
        usageMessage = "You take Zomboxolone. It slows the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 10, -- Drainable bottle
    },

    ["TheyKnew.ZomboxolonePill"] = {
        tier = 2,
        treats = {},
        displayName = "Zomboxolone Pill",
        usageMessage = "You take a Zomboxolone pill. It slows the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 1,
    },

    ["TheyKnew.Zomboxycycline"] = {
        tier = 2,
        treats = {},
        displayName = "Zomboxycycline",
        usageMessage = "You take Zomboxycycline. It fights the infection...",
        isKnoxSuppressant = true,
        totalDosesNeeded = 10, -- Drainable bottle
    },

    ["TheyKnew.ZomboxycyclinePill"] = {
        tier = 2,
        treats = {},
        displayName = "Zomboxycycline Pill",
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
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationRaiseStat(stats, CharacterStat.THIRST, 0.72)
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.78)
            end
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
        effects = function(player)
            local stats = EHRMedicationGetStats(player)
            if stats and CharacterStat then
                EHRMedicationCapStat(stats, CharacterStat.ENDURANCE, 0.55)
            end
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
                raiseStat(CharacterStat.THIRST, thirstTarget)
                capStat(CharacterStat.ENDURANCE, enduranceCap)
            end

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
    ["Base.Pills"] = { doseInterval = 4, dosesRequired = 3 },
    ["Base.PillsVitamins"] = { doseInterval = 12, dosesRequired = 1 },
    ["Base.PillsSleepingTablets"] = { doseInterval = 8, dosesRequired = 1 },
    ["Base.PillsBeta"] = { doseInterval = 8, dosesRequired = 3 },

    -- Tier 1 - OTC (every 4-6 hours)
    ["ExtensiveHealth.ColdFluTablets"] = { doseInterval = 4, dosesRequired = 8 },
    ["ExtensiveHealth.AntipyreticTablets"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.CoughSyrup"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.ElectrolytePowder"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.BronchodilatorInhaler"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.AntiNauseaTablets"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntiInflammatory"] = { doseInterval = 6, dosesRequired = 4 },
    ["ExtensiveHealth.AntiDiarrheal"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.MuscleRelaxants"] = { doseInterval = 8, dosesRequired = 3 },
    ["ExtensiveHealth.NitricOxideBooster"] = { doseInterval = 3, dosesRequired = 1 },
    ["ExtensiveHealth.CoughSuppressant"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntisepticCream"] = { doseInterval = 8, dosesRequired = 3 },

    -- Tier 2 - Prescription (every 6-12 hours)
    ["ExtensiveHealth.AntiviralCapsules"] = { doseInterval = 8, dosesRequired = 6 },
    ["ExtensiveHealth.PrescriptionAntibiotics"] = { doseInterval = 8, dosesRequired = 9 },
    ["ExtensiveHealth.AntifungalTablets"] = { doseInterval = 12, dosesRequired = 10 },
    ["ExtensiveHealth.ActivatedCharcoal"] = { doseInterval = 0, dosesRequired = 1 },  -- Single dose absorbs toxins
    ["ExtensiveHealth.AntiparasiticPills"] = { doseInterval = 12, dosesRequired = 14 },
    ["ExtensiveHealth.TopicalPermethrin"] = { doseInterval = 12, dosesRequired = 6 },
    ["ExtensiveHealth.OralRehydrationKit"] = { doseInterval = 6, dosesRequired = 8 },  -- Full rehydration course
    ["ExtensiveHealth.InstantIcePack"] = { doseInterval = 1, dosesRequired = 4 },  -- Emergency cooling course
    ["ExtensiveHealth.Furosemide"] = { doseInterval = 8, dosesRequired = 6 },  -- Transfusion reaction support course
    ["ExtensiveHealth.Antipsychotics"] = { doseInterval = 12, dosesRequired = 8 },  -- 4-day mental health course
    ["ExtensiveHealth.TetanusAntitoxin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
    ["ExtensiveHealth.TBAntibiotics"] = { doseInterval = 24, dosesRequired = 21 },
    ["ExtensiveHealth.AntibioticOintment"] = { doseInterval = 8, dosesRequired = 6 },  -- Reduced from 9
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

    -- External mod compatibility (They Knew)
    ["TheyKnew.Zomboxivir"] = { doseInterval = 0, dosesRequired = 1 },  -- Single ampule cure
    ["TheyKnew.Zomboxolone"] = { doseInterval = 8, dosesRequired = 10 },  -- Drainable bottle (10 doses)
    ["TheyKnew.ZomboxolonePill"] = { doseInterval = 8, dosesRequired = 1 },  -- Single pill from bottle
    ["TheyKnew.Zomboxycycline"] = { doseInterval = 8, dosesRequired = 10 },  -- Drainable bottle (10 doses)
    ["TheyKnew.ZomboxycyclinePill"] = { doseInterval = 8, dosesRequired = 1 },  -- Single pill from bottle
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

function EHR.Medication.GetEarlyDoseOverdoseInfo(player, medData, itemFullType)
    if not player or not medData then return nil end

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
        player:Say("Too many doses... something is very wrong...")
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

    if lethalOffScheduleCount >= 3 then
        EHR.Medication.KillFromOverdose(player, overdoseInfo, lethalOffScheduleCount)
        return true
    end

    if player:isLocalPlayer() then
        local earlyText = string.format("%.1f", overdoseInfo.earlyBy or 0)
        if (overdoseInfo.intensity or 1) >= 3 then
            player:Say("I took that way too soon... I feel awful.")
        elseif (overdoseInfo.intensity or 1) >= 2 then
            player:Say("That dose was too early. My body is reacting badly.")
        else
            player:Say("I should have waited another " .. earlyText .. "h before taking that.")
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
    ["Caffeine Pills"] = "stimulant",
    ["Beta Blockers"] = "beta blocker",

    -- Tier 1 - OTC
    ["Cold & Flu Tablets"] = "cold flu",
    ["Cough Syrup"] = "cough suppressant",
    ["Electrolyte Powder"] = "electrolyte",
    ["Bronchodilator Inhaler"] = "bronchodilator",
    ["Anti-Nausea Tablets"] = "anti-nausea",
    ["Anti-Inflammatory Pills"] = "anti-inflammatory",
    ["Anti-Diarrheal Tablets"] = "anti-diarrheal",
    ["Muscle Relaxants"] = "muscle relaxant",
    ["Nitric Oxide Boosters"] = "stimulant",
    ["Cough Suppressant"] = "cough suppressant",
    ["Antiseptic Cream"] = "antiseptic",

    -- Tier 2 - Prescription
    ["Antiviral Capsules"] = "antiviral",
    ["Prescription Antibiotics"] = "antibiotic",
    ["Antifungal Tablets"] = "antifungal",
    ["Activated Charcoal"] = "charcoal",
    ["Antiparasitic Pills"] = "antiparasitic",
    ["Topical Permethrin"] = "antiparasitic",
    ["Oral Rehydration Kit"] = "rehydration",
    ["Antipsychotics"] = "antipsychotic",
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
    local remaining = math.floor((currentUsesFloat / useDelta) + 0.0001)
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
            local newUsed = newRemaining * useDelta
            if newRemaining >= (doseInfo.maxDoses or 1) then
                newUsed = 1.0
            end
            newUsed = math.max(0, math.min(1.0, newUsed))

            local okSet = pcall(function() item:setUsedDelta(newUsed) end)
            if okSet then
                if isClient() and itemID then
                    sendClientCommand(player, "EHR", "UpdateItemDelta", {itemID = itemID, usedDelta = newUsed})
                end
                return true, "dose", useDelta, newUsed, newRemaining
            end
        end
    end

    if isClient() and itemID then
        sendClientCommand(player, "EHR", "RemoveItem", {itemID = itemID})
    end
    inventory:Remove(item)

    return true, "removed", useDelta, 1.0
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

function EHR.Medication.CanUseMedication(player, item)
    if not player or not item then return false, "Invalid parameters" end

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

    if medData.blockWhileDoseActive and EHR.Medication.GetDoseStatus then
        local ok, status = pcall(EHR.Medication.GetDoseStatus, player, itemFullType)
        local doseDue = ok and status and not status.treatmentComplete
            and (status.isOverdue == true or (tonumber(status.hoursUntilNextDose) or 0) <= 0)
        if ok and status and status.isDoseActive and not doseDue then
            return false, medData.activeDoseMessage or "The current dose is still active"
        end
    end

    -- Check for required supplies
    if medData.requiresIVKit then
        local inventory = player:getInventory()
        if not inventory:containsTypeRecurse("ExtensiveHealth.IVKit") then
            return false, "Requires IV Administration Kit"
        end
    end

    if medData.requiresSyringe then
        local inventory = player:getInventory()
        if not inventory:containsTypeRecurse("ExtensiveHealth.Syringe") then
            return false, "Requires Sterile Syringe"
        end
    end

    -- Allow using medication even without the disease (preventative use, symptom relief, etc.)
    return true, nil
end

function EHR.Medication.UseMedication(player, item)
    if not player or not item then return false end

    local canUse, reason = EHR.Medication.CanUseMedication(player, item)
    if not canUse then
        if player:isLocalPlayer() then
            player:Say(reason)
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

    -- Display usage message
    if medData.usageMessage and player:isLocalPlayer() then
        player:Say(medData.usageMessage)
    end

    -- Consume required supplies (with MP sync)
    -- These are now drainable items with multiple uses
    local inventory = player:getInventory()
    if medData.requiresIVKit then
        local ivKit = inventory:getFirstTypeRecurse("ExtensiveHealth.IVKit")
        if ivKit then
            EHR.Medication.ConsumeOneDose(player, ivKit, inventory)
        end
    end
    if medData.requiresSyringe then
        local syringe = inventory:getFirstTypeRecurse("ExtensiveHealth.Syringe")
        if syringe then
            EHR.Medication.ConsumeOneDose(player, syringe, inventory)
        end
    end

    -- Apply immediate effects (for emergency medications like Epinephrine)
    if medData.immediateEffects then
        medData.immediateEffects(player)
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

    if treatedAny and medData.hydrationSupport and EHR.Medication.StartHydrationSupport then
        EHR.Medication.StartHydrationSupport(player, medData)
    end

    -- If no disease was treated, still track the dose for drug interaction purposes
    if not treatedAny then
        if medData.appliesWithoutDisease and EHR.Medication.ApplyGeneralSymptomRelief then
            EHR.Medication.ApplyGeneralSymptomRelief(player, medData)
        end
        EHR.Medication.TrackDoseOnly(player, medData, itemFullType)
    end

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

    local consumed, consumeMode, useDelta, newUsed, remainingDoses = EHR.Medication.ConsumeOneDose(player, item, inventory)
    if consumed and consumeMode == "dose" then
        if remainingDoses == nil and useDelta and useDelta > 0 then
            remainingDoses = math.floor((newUsed / useDelta) + 0.0001)
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
        EHR.SkillXP.OnMedicationTaken(player, {
            tier = tier,
            displayName = medData.displayName,
            medId = itemFullType,
            treatedDisease = treatedAny,
        })
    end

    -- Award XP for correct treatment dose
    if treatedAny and EHR.SkillXP and EHR.SkillXP.OnTreatmentDose then
        EHR.SkillXP.OnTreatmentDose(player, "disease", true)
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
    if medData.staminaLock and EHR.Medication.StartStaminaLock then
        EHR.Medication.StartStaminaLock(player, medData)
    end
    if medData.fatigueBlock and EHR.Medication.StartFatigueBlock then
        EHR.Medication.StartFatigueBlock(player, medData)
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

function EHR.Medication.UpdateGeneralEffects(player, medTracking, currentHour)
    if not player or not medTracking or not medTracking.activeGeneralEffects then return end

    local effect = medTracking.activeGeneralEffects.bronchodilator
    if type(effect) == "table" then
        local endTime = tonumber(effect.endTime) or currentHour
        if currentHour >= endTime then
            medTracking.activeGeneralEffects.bronchodilator = nil
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

    local stamina = medTracking.activeGeneralEffects.staminaLock
    if type(stamina) == "table" then
        local endTime = tonumber(stamina.endTime) or currentHour
        if currentHour >= endTime then
            local delayedSideEffect = stamina.delayedSideEffect
            medTracking.activeGeneralEffects.staminaLock = nil
            if delayedSideEffect and EHR.Medication.ApplySideEffect then
                EHR.Medication.ApplySideEffect(player, delayedSideEffect)
            end
        else
            local targetEndurance = math.max(0, math.min(1, tonumber(stamina.targetEndurance) or 1.0))
            EHR_MedicationSetStat(player, CharacterStat and CharacterStat.ENDURANCE, targetEndurance)
        end
    end

    local fatigueBlock = medTracking.activeGeneralEffects.fatigueBlock
    local modData = player:getModData()
    if type(fatigueBlock) == "table" then
        local endTime = tonumber(fatigueBlock.endTime) or currentHour
        if currentHour >= endTime then
            local crashSideEffect = fatigueBlock.crashSideEffect
            medTracking.activeGeneralEffects.fatigueBlock = nil
            if modData then
                modData.EHR_CaffeineAwake = nil
            end
            EHR_MedicationSetStat(player, CharacterStat and CharacterStat.FATIGUE, 1.0)
            if crashSideEffect and EHR.Medication.ApplySideEffect then
                EHR.Medication.ApplySideEffect(player, crashSideEffect)
            end
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
            startTime = currentHour,
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

    -- Track dose for this medication
    if not medTracking.activeDoses[medKey] then
        -- First dose of this medication
        medTracking.activeDoses[medKey] = {
            lastDoseTime = currentHour,
            doseCount = 1,
            totalDosesNeeded = doseTiming.dosesRequired,
            intervalHours = doseTiming.doseInterval,
            activeHours = doseTiming.activeHours,
            medicationName = medData.displayName,
            tier = medData.tier,
            treatingDisease = diseaseId,
            symptomOnly = doseTiming.symptomOnly,
            requiresDoseCourse = canCure,
        }
    else
        -- Subsequent dose
        local doseData = medTracking.activeDoses[medKey]
        doseData.lastDoseTime = currentHour
        doseData.doseCount = (doseData.doseCount or 0) + 1
        doseData.totalDosesNeeded = doseTiming.dosesRequired
        doseData.intervalHours = doseTiming.doseInterval
        doseData.activeHours = doseTiming.activeHours
        doseData.medicationName = medData.displayName
        doseData.tier = medData.tier
        doseData.treatingDisease = diseaseId
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
            medTracking.activeTreatments[diseaseId] = {
                startTime = currentHour,
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

            if player:isLocalPlayer() then
                player:Say("I don't feel right... these medications might not mix well.")
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

function EHR.Medication.ApplySideEffect(player, effectId)
    if not player or not effectId then return end

    local sideEffect = EHR.Medication.SideEffects[effectId]
    if not sideEffect then return end

    local medTracking = EHR.Medication.GetMedicationData(player)
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    medTracking.activeSideEffects[effectId] = {
        startTime = currentHour,
        duration = sideEffect.duration,
    }

    -- Apply immediate effect
    if sideEffect.effects then
        sideEffect.effects(player, medTracking.activeSideEffects[effectId])
    end

    if player:isLocalPlayer() then
        player:Say("Side effect: " .. sideEffect.displayName)

        if effectId == "dizziness" and EHR.ToxinVision and EHR.ToxinVision.StartMedicationEpisode then
            EHR.ToxinVision.StartMedicationEpisode(player)
        end
    end

    EHR.Log("Applied side effect: " .. effectId .. " (duration: " .. sideEffect.duration .. " hours)")
end

function EHR.Medication.CureModuleDisease(player, diseaseId, treatment)
    if not player or not diseaseId then return false end

    if diseaseId == "wound_infection" then
        if EHR.WoundInfection and EHR.WoundInfection.CureAll then
            EHR.WoundInfection.CureAll(player, treatment and treatment.medicationName or "medication")
        elseif EHR.WoundInfection and EHR.WoundInfection.OnTakeAntibiotics then
            EHR.WoundInfection.OnTakeAntibiotics(player)
        end
        return true
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

    if EHR.Medication.UpdateGeneralEffects then
        EHR.Medication.UpdateGeneralEffects(player, medTracking, currentHour)
    end

    -- Update active treatments
    local treatmentsToRemove = {}
    for diseaseId, treatment in pairs(medTracking.activeTreatments) do
        if type(treatment) ~= "table" then
            table.insert(treatmentsToRemove, diseaseId)
        else
            local startTime = tonumber(treatment.startTime)
            local cureTimeHours = tonumber(treatment.cureTimeHours)

            if not startTime or not cureTimeHours or cureTimeHours <= 0 then
                table.insert(treatmentsToRemove, diseaseId)
                EHR.Log("Removed invalid active treatment data for " .. tostring(diseaseId))
            else
                local elapsed = math.max(0, currentHour - startTime)
                local courseComplete = EHR.Medication.IsTreatmentCourseComplete(player, treatment)

                if elapsed >= cureTimeHours and courseComplete then
                    -- Treatment complete - cure the disease
                    local moduleCured = EHR.Medication.CureModuleDisease
                        and EHR.Medication.CureModuleDisease(player, diseaseId, treatment)
                    if moduleCured then
                        if player:isLocalPlayer() then
                            player:Say("Treatment complete. " .. (treatment.medicationName or "Medication") .. " has cured your condition.")
                        end
                    elseif EHR.Disease and EHR.Disease.Cure then
                        EHR.Disease.Cure(player, diseaseId)
                        if player:isLocalPlayer() then
                            player:Say("Treatment complete. " .. (treatment.medicationName or "Medication") .. " has cured your condition.")
                        end
                    end
                    table.insert(treatmentsToRemove, diseaseId)
                elseif elapsed >= cureTimeHours and not courseComplete then
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
    end

    -- Update active side effects
    local effectsToRemove = {}
    for effectId, effectData in pairs(medTracking.activeSideEffects) do
        if type(effectData) ~= "table" then
            table.insert(effectsToRemove, effectId)
        else
            local sideEffect = EHR.Medication.SideEffects[effectId]
            if not sideEffect then
                table.insert(effectsToRemove, effectId)
            else
                local startTime = tonumber(effectData.startTime) or currentHour
                local duration = tonumber(effectData.duration) or sideEffect.duration or 0
                effectData.startTime = startTime
                effectData.duration = duration

                local elapsed = math.max(0, currentHour - startTime)

                if duration <= 0 or elapsed >= duration then
                    -- Side effect expired
                    if sideEffect.onEnd then
                        sideEffect.onEnd(player)
                    end
                    table.insert(effectsToRemove, effectId)
                    EHR.Log("Side effect expired: " .. effectId)
                else
                    -- Reapply effect each tick
                    if sideEffect.effects then
                        sideEffect.effects(player, effectData)
                    end
                end
            end
        end
    end

    for _, effectId in ipairs(effectsToRemove) do
        medTracking.activeSideEffects[effectId] = nil
    end

    EHRMedicationClearStaleSideEffectFlags(player, medTracking.activeSideEffects)

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
            local cureTimeHours = tonumber(treatment.cureTimeHours)
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
            if startTime and duration then
                local elapsed = math.max(0, currentHour - startTime)
                local remaining = duration - elapsed

                table.insert(effects, {
                    effectId = effectId,
                    displayName = sideEffect.displayName,
                    severity = sideEffect.severity,
                    hoursRemaining = math.max(0, remaining),
                })
            end
        end
    end

    return effects
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

                -- Show usage message if defined
                if medData.usageMessage and character:isLocalPlayer() then
                    character:Say(medData.usageMessage)
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
