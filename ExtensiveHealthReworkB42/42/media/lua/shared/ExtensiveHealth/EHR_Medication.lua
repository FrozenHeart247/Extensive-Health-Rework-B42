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
        treats = {"common_cold", "pneumonia", "heat_exhaustion"},
        displayName = "Painkillers",
        usageMessage = "You take painkillers. The pain eases slightly.",
    },

    -- Base.PillsVitamins
    ["Base.PillsVitamins"] = {
        tier = 0,
        treats = {"common_cold", "food_poisoning", "gastroenteritis"},
        displayName = "Vitamins",
        usageMessage = "You take vitamins. You feel slightly better.",
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
        usageMessage = "You take the cold & flu tablets. Symptoms begin to ease.",
        symptomReduction = {
            fever = 0.35,
            fatigue = 0.30,
            pain = 0.25,
        },
    },

    ["ExtensiveHealth.CoughSyrup"] = {
        tier = 1,
        treats = {"common_cold", "pneumonia"},
        displayName = "Cough Syrup",
        usageMessage = "You drink the cough syrup. The coughing subsides.",
        symptomReduction = {
            coughing = 0.50,
        },
    },

    ["ExtensiveHealth.ElectrolytePowder"] = {
        tier = 1,
        treats = {"dysentery", "food_poisoning", "gastroenteritis", "heat_exhaustion"},
        displayName = "Electrolyte Powder",
        usageMessage = "You mix and drink the electrolyte solution. You feel more hydrated.",
        symptomReduction = {
            dehydration = 0.40,
            weakness = 0.30,
        },
    },

    ["ExtensiveHealth.BronchodilatorInhaler"] = {
        tier = 1,
        treats = {"pneumonia", "corpse_sickness"},
        displayName = "Bronchodilator Inhaler",
        usageMessage = "You use the inhaler. Breathing becomes easier.",
        symptomReduction = {
            breathingDifficulty = 0.45,
        },
    },

    ["ExtensiveHealth.AntiNauseaTablets"] = {
        tier = 1,
        treats = {"food_poisoning", "gastroenteritis", "corpse_sickness"},
        displayName = "Anti-Nausea Tablets",
        usageMessage = "You take anti-nausea tablets. Your stomach settles.",
        symptomReduction = {
            nausea = 0.50,
            vomiting = 0.40,
        },
    },

    ["ExtensiveHealth.AntiInflammatory"] = {
        tier = 1,
        treats = {"wound_infection", "trichinosis", "tetanus"},
        displayName = "Anti-Inflammatory Pills",
        usageMessage = "You take anti-inflammatory pills. Swelling begins to reduce.",
        symptomReduction = {
            inflammation = 0.40,
            pain = 0.35,
        },
    },

    ["ExtensiveHealth.AntiDiarrheal"] = {
        tier = 1,
        treats = {"dysentery", "food_poisoning", "gastroenteritis"},
        displayName = "Anti-Diarrheal Tablets",
        usageMessage = "You take anti-diarrheal tablets. Your stomach calms.",
        symptomReduction = {
            diarrhea = 0.50,
        },
    },

    ["ExtensiveHealth.MuscleRelaxants"] = {
        tier = 1,
        treats = {"tetanus", "trichinosis"},
        displayName = "Muscle Relaxants",
        usageMessage = "You take muscle relaxants. The cramping eases.",
        symptomReduction = {
            muscleSpasms = 0.40,
            pain = 0.30,
        },
    },

    ["ExtensiveHealth.CoughSuppressant"] = {
        tier = 1,
        treats = {"common_cold", "pneumonia", "tuberculosis"},
        displayName = "Cough Suppressant",
        usageMessage = "You take cough suppressant. The urge to cough fades.",
        symptomReduction = {
            coughing = 0.45,
        },
    },

    ["ExtensiveHealth.AntisepticCream"] = {
        tier = 1,
        treats = {"wound_infection"},
        displayName = "Antiseptic Cream",
        usageMessage = "You apply antiseptic cream to the wound.",
        isTopical = true,
        symptomReduction = {
            infection = 0.25,
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
        treats = {"corpse_sickness"},
        displayName = "Antifungal Tablets",
        usageMessage = "You take antifungal tablets. The fungal infection is being treated.",
        cureTimeHours = 120, -- 5 days to cure
    },

    ["ExtensiveHealth.ActivatedCharcoal"] = {
        tier = 2,
        treats = {"food_poisoning", "corpse_sickness"},
        displayName = "Activated Charcoal",
        usageMessage = "You swallow activated charcoal. It absorbs the toxins.",
        cureTimeHours = 6, -- Fallback cure time
        diseaseCureTimeHours = {
            food_poisoning = 6,
            corpse_sickness = 8,
        },
    },

    ["ExtensiveHealth.AntiparasiticPills"] = {
        tier = 2,
        treats = {"trichinosis"},
        displayName = "Antiparasitic Pills",
        usageMessage = "You take antiparasitic medication. The parasites will die.",
        cureTimeHours = 168, -- 7 days to cure
    },

    ["ExtensiveHealth.OralRehydrationKit"] = {
        tier = 2,
        treats = {"dysentery", "heat_exhaustion"},
        displayName = "Oral Rehydration Kit",
        usageMessage = "You prepare and drink the rehydration solution.",
        cureTimeHours = 48, -- 2 days to cure
    },

    ["ExtensiveHealth.TetanusAntitoxin"] = {
        tier = 2,
        treats = {"tetanus"},
        displayName = "Tetanus Antitoxin",
        usageMessage = "You inject the tetanus antitoxin. It neutralizes the toxin.",
        requiresSyringe = true,
        cureTimeHours = 120, -- 5 days to cure
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
        treats = {"wound_infection", "sepsis", "pneumonia", "cellulitis"},
        displayName = "Broad Spectrum Antibiotics",
        usageMessage = "You take broad spectrum antibiotics. They fight multiple infections.",
        cureTimeHours = 72,
    },

    -- =========================================
    -- TIER 3 - CLINICAL GRADE MEDICATION
    -- Rare - Large Hospitals, Military Medical
    -- =========================================

    ["ExtensiveHealth.CorticosteroidInjection"] = {
        tier = 3,
        treats = {"corpse_sickness", "pneumonia"},
        displayName = "Corticosteroid Injection",
        usageMessage = "You inject corticosteroids. Inflammation reduces rapidly.",
        requiresSyringe = true,
        cureTimeHours = 24, -- Fast cure
        sideEffects = {"immunosuppression", "insomnia"},
    },

    ["ExtensiveHealth.IVAntibiotics"] = {
        tier = 3,
        treats = {"sepsis", "wound_infection", "cellulitis"},
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
        treats = {"corpse_sickness"},
        displayName = "IV Amphotericin B",
        usageMessage = "You administer IV Amphotericin. This antifungal is extremely potent.",
        requiresIVKit = true,
        cureTimeHours = 48,
        sideEffects = {"fever", "kidney_stress", "fatigue"},
    },

    ["ExtensiveHealth.ChelationKit"] = {
        tier = 3,
        treats = {"corpse_sickness"},
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
        treats = {"gastroenteritis", "dysentery"},
        displayName = "IV Ciprofloxacin",
        usageMessage = "You administer IV Ciprofloxacin. Bacterial infection is being eliminated.",
        requiresIVKit = true,
        cureTimeHours = 24,
        sideEffects = {"tendon_weakness", "dizziness"},
    },

    ["ExtensiveHealth.TetanusImmunoglobulin"] = {
        tier = 3,
        treats = {"tetanus"},
        displayName = "Tetanus Immunoglobulin",
        usageMessage = "You inject Tetanus Immunoglobulin. Immediate protection granted.",
        requiresSyringe = true,
        cureTimeHours = 48,
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

EHR.Medication.SideEffects = {
    -- Mild Side Effects (annoying but not dangerous)
    ["nausea"] = {
        displayName = "Nausea",
        duration = 4, -- hours
        severity = 1,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.FOOD_SICKNESS then
                local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
                stats:set(CharacterStat.FOOD_SICKNESS, math.min(current + 0.15, 0.4))
            end
        end,
    },

    ["headache"] = {
        displayName = "Headache",
        duration = 6,
        severity = 1,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.PAIN then
                local current = stats:get(CharacterStat.PAIN) or 0
                stats:set(CharacterStat.PAIN, math.min(current + 0.2, 0.5))
            end
        end,
    },

    ["dizziness"] = {
        displayName = "Dizziness",
        duration = 3,
        severity = 1,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.DISCOMFORT then
                local current = stats:get(CharacterStat.DISCOMFORT) or 0
                stats:set(CharacterStat.DISCOMFORT, math.min(current + 0.25, 0.6))
            end
        end,
    },

    ["fatigue"] = {
        displayName = "Fatigue",
        duration = 8,
        severity = 1,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.FATIGUE then
                local current = stats:get(CharacterStat.FATIGUE) or 0
                stats:set(CharacterStat.FATIGUE, math.min(current + 0.15, 0.6))
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
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.UNHAPPINESS then
                local current = stats:get(CharacterStat.UNHAPPINESS) or 0
                stats:set(CharacterStat.UNHAPPINESS, math.min(current + 0.1, 0.4))
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
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.PAIN then
                local current = stats:get(CharacterStat.PAIN) or 0
                stats:set(CharacterStat.PAIN, math.min(current + 0.1, 0.3))
            end
        end,
    },

    ["abdominal_pain"] = {
        displayName = "Abdominal Pain",
        duration = 4,
        severity = 1,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.PAIN then
                local current = stats:get(CharacterStat.PAIN) or 0
                stats:set(CharacterStat.PAIN, math.min(current + 0.15, 0.4))
            end
        end,
    },

    -- Moderate Side Effects (significant but manageable)
    ["fever"] = {
        displayName = "Drug-Induced Fever",
        duration = 6,
        severity = 2,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat then
                if CharacterStat.TEMPERATURE then
                    local current = stats:get(CharacterStat.TEMPERATURE) or 0
                    stats:set(CharacterStat.TEMPERATURE, math.min(current + 0.2, 0.7))
                end
                if CharacterStat.THIRST then
                    local current = stats:get(CharacterStat.THIRST) or 0
                    stats:set(CharacterStat.THIRST, math.min(current + 0.1, 0.8))
                end
            end
        end,
    },

    ["severe_fatigue"] = {
        displayName = "Severe Fatigue",
        duration = 12,
        severity = 2,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.FATIGUE then
                local current = stats:get(CharacterStat.FATIGUE) or 0
                stats:set(CharacterStat.FATIGUE, math.min(current + 0.3, 0.8))
            end
            if stats and CharacterStat and CharacterStat.ENDURANCE then
                local current = stats:get(CharacterStat.ENDURANCE) or 1
                stats:set(CharacterStat.ENDURANCE, math.max(current - 0.3, 0.2))
            end
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
            local stats = player:getStats()
            if stats and CharacterStat then
                if CharacterStat.PAIN then
                    local current = stats:get(CharacterStat.PAIN) or 0
                    stats:set(CharacterStat.PAIN, math.min(current + 0.25, 0.6))
                end
                if CharacterStat.DISCOMFORT then
                    local current = stats:get(CharacterStat.DISCOMFORT) or 0
                    stats:set(CharacterStat.DISCOMFORT, math.min(current + 0.3, 0.7))
                end
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
        duration = 24,
        severity = 3,
        effects = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.THIRST then
                local current = stats:get(CharacterStat.THIRST) or 0
                stats:set(CharacterStat.THIRST, math.min(current + 0.2, 0.9))
            end
            -- Increased water need
            local modData = player:getModData()
            modData.EHR_KidneyStress = true
        end,
        onEnd = function(player)
            local modData = player:getModData()
            modData.EHR_KidneyStress = nil
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
    ["Base.PillsVitamins"] = { doseInterval = 24, dosesRequired = 1 },
    ["Base.PillsBeta"] = { doseInterval = 8, dosesRequired = 3 },

    -- Tier 1 - OTC (every 4-6 hours)
    ["ExtensiveHealth.ColdFluTablets"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.CoughSyrup"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.ElectrolytePowder"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.BronchodilatorInhaler"] = { doseInterval = 4, dosesRequired = 4 },
    ["ExtensiveHealth.AntiNauseaTablets"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntiInflammatory"] = { doseInterval = 6, dosesRequired = 4 },
    ["ExtensiveHealth.AntiDiarrheal"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.MuscleRelaxants"] = { doseInterval = 8, dosesRequired = 3 },
    ["ExtensiveHealth.CoughSuppressant"] = { doseInterval = 6, dosesRequired = 3 },
    ["ExtensiveHealth.AntisepticCream"] = { doseInterval = 8, dosesRequired = 3 },

    -- Tier 2 - Prescription (every 6-12 hours)
    ["ExtensiveHealth.AntiviralCapsules"] = { doseInterval = 8, dosesRequired = 6 },
    ["ExtensiveHealth.PrescriptionAntibiotics"] = { doseInterval = 8, dosesRequired = 9 },
    ["ExtensiveHealth.AntifungalTablets"] = { doseInterval = 12, dosesRequired = 10 },
    ["ExtensiveHealth.ActivatedCharcoal"] = { doseInterval = 0, dosesRequired = 1 },  -- Single dose absorbs toxins
    ["ExtensiveHealth.AntiparasiticPills"] = { doseInterval = 12, dosesRequired = 14 },
    ["ExtensiveHealth.OralRehydrationKit"] = { doseInterval = 4, dosesRequired = 3 },  -- Reduced from 6
    ["ExtensiveHealth.TetanusAntitoxin"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
    ["ExtensiveHealth.TBAntibiotics"] = { doseInterval = 24, dosesRequired = 21 },
    ["ExtensiveHealth.AntibioticOintment"] = { doseInterval = 8, dosesRequired = 6 },  -- Reduced from 9
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = { doseInterval = 8, dosesRequired = 6 },  -- Reduced from 9

    -- Tier 3 - Clinical (mostly single dose for emergency/IV treatments)
    ["ExtensiveHealth.CorticosteroidInjection"] = { doseInterval = 0, dosesRequired = 1 },  -- Single injection
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

local function EHR_MedicationGetDoseTiming(medData, itemFullType, tierEffects)
    medData = medData or {}

    local dosingSchedule = (itemFullType and EHR.Medication.DosingSchedules[itemFullType]) or EHR.Medication.DefaultDosing
    local doseInterval = medData.doseIntervalHours or medData.intervalHours or dosingSchedule.doseInterval or 6
    local canCure = (tierEffects and tierEffects.canCure)
        or medData.cureTimeHours ~= nil
        or medData.diseaseCureTimeHours ~= nil
        or medData.isKnoxCure == true
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
    if medData.isTopical then return nil end

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
        sicknessTarget = math.min(0.60, 0.42 + (0.04 * intensity)),
        enduranceCap = math.max(0.45, 0.57 - (0.04 * intensity)),
        thirstTarget = math.min(0.78, 0.64 + (0.04 * intensity)),
        healthCap = math.max(45, 70 - (7 * intensity)),
    }
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

    medTracking.activeSideEffects[overdoseInfo.effectId] = {
        startTime = currentHour,
        duration = duration,
        intensity = overdoseInfo.intensity or 1,
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
            tostring(overdoseInfo.intensity or 1) .. ")")
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
        message = "Chelation + IV Antifungal: Severe kidney stress!",
        effect = function(player)
            local stats = player:getStats()
            if stats and CharacterStat and CharacterStat.THIRST then
                local current = stats:get(CharacterStat.THIRST) or 0
                stats:set(CharacterStat.THIRST, math.min(1, current + 0.3))
            end
            local modData = player:getModData()
            modData.EHR_KidneyStress = true
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
        message = "Multiple antibiotics + Rifampicin: High liver/kidney stress!",
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
        message = "NSAIDs + Antibiotics: Increased GI upset and kidney stress",
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
    ["Vitamins"] = "vitamin",
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
    ["Cough Suppressant"] = "cough suppressant",
    ["Antiseptic Cream"] = "antiseptic",

    -- Tier 2 - Prescription
    ["Antiviral Capsules"] = "antiviral",
    ["Prescription Antibiotics"] = "antibiotic",
    ["Antifungal Tablets"] = "antifungal",
    ["Activated Charcoal"] = "charcoal",
    ["Antiparasitic Pills"] = "antiparasitic",
    ["Oral Rehydration Kit"] = "rehydration",
    ["Tetanus Antitoxin"] = "antitoxin",
    ["TB Antibiotics (Isoniazid)"] = "tb antibiotics",
    ["Antibiotic Ointment"] = "antibiotic",
    ["Broad Spectrum Antibiotics"] = "antibiotic",

    -- Tier 3 - Clinical
    ["Corticosteroid Injection"] = "corticosteroid",
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
    return modData.EHR_Medication
end

-- ============================================
-- MEDICATION APPLICATION
-- ============================================

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

    -- B42 normal items can expose getUseDelta(), but they cannot always store UsedDelta.
    local canUseDose = useDelta > 0 and item.getUsedDelta and item.setUsedDelta

    if canUseDose then
        local currentUsed = 0
        local okCurrent, usedDelta = pcall(function() return item:getUsedDelta() end)
        if okCurrent and usedDelta then
            currentUsed = usedDelta
        end
        local newUsed = currentUsed + useDelta

        if newUsed < 1.0 then
            local okSet = pcall(function() item:setUsedDelta(newUsed) end)
            if okSet then
                if isClient() and itemID then
                    sendClientCommand(player, "EHR", "UpdateItemDelta", {itemID = itemID, usedDelta = newUsed})
                end
                return true, "dose", useDelta, newUsed
            end
        end
    end

    if isClient() and itemID then
        sendClientCommand(player, "EHR", "RemoveItem", {itemID = itemID})
    end
    inventory:Remove(item)

    return true, "removed", useDelta, 1.0
end

function EHR.Medication.CanUseMedication(player, item)
    if not player or not item then return false, "Invalid parameters" end

    local itemFullType = item:getFullType()
    local medData = EHR.Medication.Database[itemFullType]

    if not medData then
        return false, "Not a recognized medication"
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
    if diseaseData and diseaseData.active then
        for _, diseaseId in ipairs(medData.treats) do
            if diseaseData.active[diseaseId] then
                EHR.Medication.ApplyTreatment(player, diseaseId, medData, tierEffects, itemFullType)
                treatedAny = true
            end
        end
    end

    -- If no disease was treated, still track the dose for drug interaction purposes
    if not treatedAny then
        EHR.Medication.TrackDoseOnly(player, medData, itemFullType)
    end

    if earlyDoseOverdose then
        EHR.Medication.ApplyEarlyDoseOverdose(player, earlyDoseOverdose)
    end

    -- Apply side effects for Tier 3 medications
    if tier == 3 and medData.sideEffects then
        for _, effectId in ipairs(medData.sideEffects) do
            EHR.Medication.ApplySideEffect(player, effectId)
        end
    end

    -- Check for drug interactions
    EHR.Medication.CheckAndApplyInteractions(player)

    local consumed, consumeMode, useDelta, newUsed = EHR.Medication.ConsumeOneDose(player, item, inventory)
    if consumed and consumeMode == "dose" then
        local remainingDoses = 0
        if useDelta and useDelta > 0 then
            remainingDoses = math.floor((1.0 - newUsed) / useDelta)
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
                    part:setAdditionalPain(math.max(0, currentPain - (reduction * 20)))
                end)
            end
        end
    end

    if changed and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end

    return changed
end

local function EHR_MedicationApplyImmediateSymptomRelief(player, diseaseId, medData)
    local reductions = medData and medData.symptomReduction
    if not reductions then return end

    local didRelieve = false
    local isFoodborne = diseaseId == "food_poisoning" or diseaseId == "gastroenteritis" or diseaseId == "dysentery"

    if isFoodborne and reductions.nausea then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.04 * reductions.nausea, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.SICKNESS, -0.03 * reductions.nausea, 0, 1) or didRelieve
    end

    if isFoodborne and reductions.vomiting then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.FOOD_SICKNESS, -0.05 * reductions.vomiting, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.HUNGER, -0.02 * reductions.vomiting, 0, 1) or didRelieve
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.THIRST, -0.04 * reductions.vomiting, 0, 1) or didRelieve
    end

    if reductions.dehydration then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.THIRST, -0.10 * reductions.dehydration, 0, 1) or didRelieve
    end

    if reductions.weakness then
        didRelieve = EHR_MedicationAdjustStat(player, CharacterStat and CharacterStat.ENDURANCE, 0.12 * reductions.weakness, 0, 1) or didRelieve
    end

    if reductions.muscleSpasms then
        didRelieve = EHR_MedicationReduceMuscleStiffness(player, reductions.muscleSpasms) or didRelieve
    end

    if reductions.pain then
        didRelieve = EHR_MedicationReducePain(player, reductions.pain) or didRelieve
    end

    if didRelieve then
        EHR.Log("Applied immediate symptom relief from " .. (medData.displayName or "medication") .. " to " .. tostring(diseaseId))
    end
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

    EHR_MedicationApplyImmediateSymptomRelief(player, diseaseId, medData)

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
    end

    -- Start or continue cure process if tier can cure.
    if tierEffects.canCure then
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
            local category = EHR.Medication.DrugCategories[doseData.medicationName]
            if category then
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
    if doseTiming.symptomOnly and not doseData.requiresDoseCourse then
        totalDosesNeeded = 1
    end

    local doseCount = doseData.doseCount or 0
    local treatmentComplete = doseCount >= totalDosesNeeded
    local nextDoseIn = (not treatmentComplete and intervalHours > 0) and math.max(0, intervalHours - elapsed) or 0
    local isOverdue = (not treatmentComplete) and intervalHours > 0 and elapsed > intervalHours
    local hoursOverdue = isOverdue and (elapsed - intervalHours) or 0
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
        treatmentComplete = treatmentComplete,
        symptomOnly = doseTiming.symptomOnly or doseData.symptomOnly == true,
    }
end

function EHR.Medication.GetAllDoseStatuses(player)
    local medTracking = EHR.Medication.GetMedicationData(player)
    if not medTracking then return {} end

    local statuses = {}

    for medKey, doseData in pairs(medTracking.activeDoses) do
        local status = EHR.Medication.GetDoseStatus(player, medKey)
        if status and (status.isDoseActive or status.isOverdue or not status.treatmentComplete) then
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
    end

    EHR.Log("Applied side effect: " .. effectId .. " (duration: " .. sideEffect.duration .. " hours)")
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
                    if EHR.Disease and EHR.Disease.Cure then
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
            local startTime = tonumber(effectData.startTime) or currentHour
            local duration = tonumber(effectData.duration) or (sideEffect and sideEffect.duration) or 0
            effectData.startTime = startTime
            effectData.duration = duration

            local elapsed = math.max(0, currentHour - startTime)

            if duration <= 0 or elapsed >= duration then
                -- Side effect expired
                if sideEffect and sideEffect.onEnd then
                    sideEffect.onEnd(player)
                end
                table.insert(effectsToRemove, effectId)
                EHR.Log("Side effect expired: " .. effectId)
            else
                -- Reapply effect each tick
                if sideEffect and sideEffect.effects then
                    sideEffect.effects(player, effectData)
                end
            end
        end
    end

    for _, effectId in ipairs(effectsToRemove) do
        medTracking.activeSideEffects[effectId] = nil
    end

    -- Remove completed symptom-only dose entries once their actual effect has ended.
    local dosesToRemove = {}
    for medKey, _ in pairs(medTracking.activeDoses) do
        local status = EHR.Medication.GetDoseStatus(player, medKey)
        if status and status.treatmentComplete and not status.isDoseActive and not status.isOverdue then
            local usedByTreatment = false
            for _, treatment in pairs(medTracking.activeTreatments) do
                if treatment.medKey == medKey then
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
