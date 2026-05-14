--[[
    Extensive Health Rework B42
    Disease Definitions - Phase 1 Environmental Diseases

    This file extends EHR.Disease.Diseases with new disease definitions.
    Load order: After EHR_Disease.lua

    New diseases:
    - Common Cold: Cold weather + wet exposure, can progress to pneumonia
    - Pneumonia: From untreated cold, LETHAL without antibiotics
    - Dysentery: Contaminated water, LETHAL through dehydration
    - Hypothermia: Cold + wet exposure, LETHAL cardiac arrest

    v1.0.0 - Initial implementation
]]--

require "ExtensiveHealth/EHR_Disease"

EHR = EHR or {}

-- Ensure Disease module is loaded
if not EHR.Disease or not EHR.Disease.Diseases then
    EHR.Log("ERROR: EHR_DiseaseDefinitions loaded before EHR_Disease!")
    return
end

-- ============================================
-- COMMON COLD
-- ============================================
--[[
    Transmission: Cold weather + wet exposure (handled by EHR_EnvironmentalDiseases)
    Duration: 2-4 days, untreated stage 4 has a 50% pneumonia complication roll
    Effects: Sneezing (attracts zombies), mild debuffs
    Not lethal on its own
]]--
EHR.Disease.Diseases["common_cold"] = {
    name = "Common Cold",
    -- Timing (in game hours)
    incubationMin = 12,     -- 12 hours minimum
    incubationMax = 24,     -- 24 hours maximum
    durationMin = 48,       -- 2 days minimum
    durationMax = 96,       -- 4 days maximum
    -- Stage duration percentages (must sum to 1.0)
    stageDurations = {
        [1] = 0.20,  -- 20% incubation
        [2] = 0.30,  -- 30% early
        [3] = 0.30,  -- 30% peak
        [4] = 0.20,  -- 20% recovery
    },
    -- Severity affects symptom intensity
    baseSeverity = 0.3,
    -- Can this disease kill directly?
    canKill = false,
    -- Can progress to another disease
    canProgress = true,
    progressTo = "pneumonia",
    progressChance = 0.50,          -- 50% chance for pneumonia on untreated stage 4
    progressAfterHours = 0,         -- Stage 4 handles the late complication roll
    -- Treatment that prevents progression
    treatmentItem = "Pills",        -- Any pills help (B42 item type)
    treatmentReducesProgress = 0.5, -- Reduces progression chance by 50%
    -- Stages: 1=incubation, 2=early, 3=peak, 4=recovery
    stageCount = 4,
    -- Stage effects (handled by EHR_EnvironmentalDiseases)
    effects = {
        -- Incubation: no visible effects
        [1] = {
            fatigueDrain = 0,
            staminaPenalty = 0,
            sneezeIntervalHours = 3,
        },
        -- Early: mild symptoms
        [2] = {
            fatigueDrain = 0.001,       -- Slight fatigue buildup
            fatigueCap = 0.10,          -- Tired, but not bedridden
            staminaPenalty = 0.05,      -- 5% stamina penalty
            coldStrength = 35,          -- Vanilla cold moodle
            sneezeIntervalHours = 1,
        },
        -- Peak: worst symptoms
        [3] = {
            fatigueDrain = 0.003,
            fatigueCap = 0.25,
            staminaPenalty = 0.15,
            coldStrength = 65,
            sneezeIntervalHours = 0.5,
        },
        -- Recovery/complication check: symptoms fade unless pneumonia triggers
        [4] = {
            fatigueDrain = 0,
            staminaPenalty = 0,
            coldStrength = 0,
            sneezeIntervalHours = 3,
        },
    },
    -- Stage entry dialogue (said ONCE when entering each stage)
    stageEntryDialogue = {
        [1] = "*sniff* I feel a bit run down...",
        [2] = "Great... I think I'm catching a cold...",
        [3] = "*ACHOO!* This cold is kicking my ass...",
        [4] = "*sniff* I think the worst is over...",
    },
    -- Random dialogue hints per stage (occasional)
    dialogue = {
        [1] = {
            "I feel a bit off...",
            "*sniff*",
            "Hope I'm not getting sick...",
        },
        [2] = {
            "*coughs*",
            "My throat's getting scratchy...",
            "*sniff* Ugh...",
            "I should find some medicine...",
        },
        [3] = {
            "*ACHOO!*",
            "*coughs violently*",
            "Can't stop sneezing...",
            "*blows nose*",
            "I feel terrible...",
        },
        [4] = {
            "Starting to feel better...",
            "*sniff* Almost over it...",
            "Should be back to normal soon...",
        },
    },
}

-- ============================================
-- PNEUMONIA
-- ============================================
--[[
    Transmission: From untreated cold, smoke inhalation, dust
    Duration: 5-9 days, LETHAL without antibiotics
    Effects: Severe coughing (zombie attraction!), can't sprint, stamina destroyed
    Key mechanic: Coughing fits that attract zombies (~25 tile radius in peak)
]]--
EHR.Disease.Diseases["pneumonia"] = {
    name = "Pneumonia",
    category = "environmental",
    -- Timing (in game hours)
    incubationMin = 12,     -- 12 hours minimum
    incubationMax = 24,     -- 24 hours maximum
    durationMin = 120,      -- 5 days minimum
    durationMax = 216,      -- 9 days maximum
    -- Stage duration percentages (must sum to 1.0)
    stageDurations = {
        [1] = 0.10,  -- 10% incubation (short)
        [2] = 0.25,  -- 25% early
        [3] = 0.45,  -- 45% peak (long danger period)
        [4] = 0.20,  -- 20% recovery
    },
    -- Severity
    baseSeverity = 0.7,
    -- LETHAL without treatment
    canKill = true,
    killMechanic = "healthDrain",    -- Stage 3/4 health drain handles lethality
    -- Treatment
    treatmentItem = "Antibiotics",   -- Requires antibiotics
    treatmentCured = true,           -- Antibiotics can cure (move to recovery)
    treatmentReducesDeath = 0.9,     -- 90% reduction in death chance when treated
    -- Stages
    stageCount = 4,
    -- Stage effects (handled by EHR_EnvironmentalDiseases)
    effects = {
        [1] = {
            fatigueDrain = 0.001,
            staminaPenalty = 0.05,
            coughIntervalHours = 2.0,
            severeCough = false,
            chestPain = 6,
            canSprint = true,
        },
        [2] = {
            fatigueDrain = 0.005,
            staminaPenalty = 0.25,
            coughIntervalHours = 1.0,
            severeCough = true,
            enduranceCap = 0.70,
            chestPain = 20,
            canSprint = true,
        },
        [3] = {
            fatigueDrain = 0.010,
            staminaPenalty = 0.50,
            coughIntervalHours = 0.75,
            severeCough = true,
            enduranceCap = 0.70,
            chestPain = 30,
            healthDrainPerHour = 2.5,
            healthDamageCap = 30,
            canSprint = true,
        },
        [4] = {
            fatigueDrain = 0.012,
            staminaPenalty = 0.50,
            coughIntervalHours = 0.75,
            severeCough = true,
            enduranceCap = 0.70,
            chestPain = 35,
            healthDrainPerHour = 4.0,
            canSprint = true,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "My chest feels tight... this isn't just a cold...",
        [2] = "*coughs* Something's wrong with my lungs...",
        [3] = "*violent coughing* I can barely breathe... I need antibiotics...",
        [4] = "*deep breath* I think the infection is clearing...",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "Hard to catch my breath...",
            "My chest hurts...",
        },
        [2] = {
            "*coughs* Can't shake this...",
            "Breathing is getting harder...",
            "*wheezes*",
            "I need medicine...",
        },
        [3] = {
            "*COUGHING FIT*",
            "*gasps for air*",
            "Can't... breathe...",
            "*violent coughing*",
            "I'm going to die without antibiotics...",
        },
        [4] = {
            "Breathing easier now...",
            "*occasional cough*",
            "Getting stronger...",
        },
    },
}

-- ============================================
-- DYSENTERY
-- ============================================
--[[
    Transmission: Contaminated/untreated water (handled by EHR_EnvironmentalDiseases)
    Duration: 3-5 days, LETHAL through dehydration
    Effects: Extreme thirst drain, vomiting, blood volume loss
    Key mechanic: Kills through dehydration, not direct damage
]]--
EHR.Disease.Diseases["dysentery"] = {
    name = "Dysentery",
    -- Timing (in game hours)
    incubationMin = 6,      -- 6 hours minimum
    incubationMax = 12,     -- 12 hours maximum
    durationMin = 72,       -- 3 days minimum
    durationMax = 120,      -- 5 days maximum
    -- Stage duration percentages (must sum to 1.0)
    stageDurations = {
        [1] = 0.10,  -- 10% incubation (fast onset)
        [2] = 0.25,  -- 25% early
        [3] = 0.40,  -- 40% peak (dehydration danger)
        [4] = 0.25,  -- 25% recovery
    },
    -- Severity
    baseSeverity = 0.6,
    -- LETHAL through dehydration
    canKill = true,
    killMechanic = "dehydration",    -- Doesn't kill directly, drains thirst
    deathThirstLevel = 0.95,         -- Death when thirst > 95%
    -- Treatment
    treatmentItem = "Antibiotics",
    treatmentCured = true,
    treatmentReducesDrain = 0.7,     -- 70% reduction in fluid loss when treated
    -- Stages
    stageCount = 4,
    -- Stage effects (handled by EHR_EnvironmentalDiseases)
    effects = {
        [1] = {
            thirstDrain = 0.0003,
            hungerDrain = 0.0002,
            thirstCap = 0.10,
            hungerCap = 0.10,
            vomitChance = 0,
            bloodLoss = 0,
            abdominalPain = 0,
        },
        [2] = {
            thirstDrain = 0.0025,       -- Moderate fluid loss, capped unless unsupported
            hungerDrain = 0.0015,
            thirstCap = 0.50,
            hungerCap = 0.50,
            vomitChance = 0.00035,      -- Very rare vomiting
            bloodLoss = 0.05,           -- mL per tick (bloody diarrhea)
            bloodLossFloor = 4550,
            abdominalPain = 18,
        },
        [3] = {
            thirstDrain = 0.0065,       -- Dangerous dehydration, no cap
            hungerDrain = 0.0035,
            vomitChance = 0.004,        -- Frequent vomiting
            bloodLoss = 0.18,           -- Noticeable blood loss, but not the kill path
            bloodLossFloor = 3850,
            abdominalPain = 28,
            movementPenalty = 0.7,      -- 30% slower (weakness)
        },
        [4] = {
            thirstDrain = 0.0003,
            hungerDrain = 0.0002,
            thirstCap = 0.10,
            hungerCap = 0.10,
            vomitChance = 0,
            bloodLoss = 0,
            abdominalPain = 0,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "My stomach is making weird noises...",
        [2] = "Oh god... something's very wrong with my gut...",
        [3] = "*groans in agony* I can't stop... I need water... antibiotics...",
        [4] = "I think the worst has passed... I'm so weak...",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "Stomach doesn't feel right...",
            "Shouldn't have drunk that water...",
        },
        [2] = {
            "*stomach cramps*",
            "I need to find a bathroom...",
            "*groans*",
            "So thirsty...",
        },
        [3] = {
            "*violent cramping*",
            "I'm losing so much fluid...",
            "*retches*",
            "I'm going to dehydrate...",
            "*groans in pain*",
        },
        [4] = {
            "Finally keeping fluids down...",
            "So weak but recovering...",
        },
    },
}

-- ============================================
-- HYPOTHERMIA
-- ============================================
--[[
    Transmission: Cold + wet exposure over time (handled by EHR_EnvironmentalDiseases)
    Duration: 1-2 days (fast but deadly)
    Effects: Movement penalty, can't sprint, confusion, cardiac arrest in peak
    Key mechanic: LETHAL - cardiac arrest in peak stage unless warmed
    Treatment: Getting warm (near fire, indoors), no medicine cures this
]]--
EHR.Disease.Diseases["hypothermia"] = {
    name = "Hypothermia",
    -- Timing (in game hours) - shorter than other diseases
    incubationMin = 1,      -- 1 hour minimum (fast onset)
    incubationMax = 3,      -- 3 hours maximum
    durationMin = 24,       -- 1 day minimum
    durationMax = 48,       -- 2 days maximum
    -- Stage duration percentages (must sum to 1.0)
    stageDurations = {
        [1] = 0.15,  -- 15% incubation (very fast)
        [2] = 0.25,  -- 25% early
        [3] = 0.35,  -- 35% peak (cardiac risk)
        [4] = 0.25,  -- 25% recovery
    },
    -- Special: stage is controlled directly by current body temperature.
    stageDrivenByBodyTemperature = true,
    requiresWarmthForRecovery = true,
    -- Severity
    baseSeverity = 0.8,
    -- LETHAL - continuous cold damage instead of random instant death
    canKill = true,
    killMechanic = "healthDrain",
    deathChancePerHour = 0,
    deathStage = 4,
    -- Treatment (warmth-based, not medicine)
    treatmentWarmth = true,          -- Requires getting warm
    treatmentItem = nil,             -- No pill fixes this
    treatmentReducesDeath = 0.95,    -- Being warm almost eliminates death
    -- Stages
    stageCount = 4,
    -- Stage effects (handled by EHR_EnvironmentalDiseases)
    effects = {
        [1] = {
            staminaPenalty = 0.12,
            canSprint = true,
            movementPenalty = 0.90,
            enduranceCap = 0.86,
            fatigueDrain = 0.00035,
        },
        [2] = {
            staminaPenalty = 0.35,
            canSprint = false,
            movementPenalty = 0.76,
            enduranceCap = 0.70,
            fatigueDrain = 0.00075,
            healthDrainPerHour = 2.0,
            confusionChance = 0.002,
        },
        [3] = {
            staminaPenalty = 0.70,
            canSprint = false,
            movementPenalty = 0.52,
            enduranceCap = 0.45,
            fatigueDrain = 0.0012,
            healthDrainPerHour = 8.0,
            confusionChance = 0.006,
            dizzinessChance = 0.010,
        },
        [4] = {
            staminaPenalty = 0.85,
            canSprint = false,
            movementPenalty = 0.42,
            enduranceCap = 0.32,
            fatigueDrain = 0.0018,
            healthDrainPerHour = 18.0,
            confusionChance = 0.010,
            dizzinessChance = 0.016,
            blackoutChance = 0.008,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "S-so cold... can't stop shivering...",
        [2] = "I c-can't feel my fingers... need warmth...",
        [3] = "Everything's... getting fuzzy... so... tired...",
        [4] = "*warming up* I thought I was going to die...",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "*shivers*",
            "So cold...",
            "Need to find shelter...",
        },
        [2] = {
            "*teeth chattering*",
            "Can't... stop... shaking...",
            "*shivers violently*",
            "Need fire... warmth...",
        },
        [3] = {
            "*slurred* So... sleepy...",
            "*confused* Where... am I?",
            "*mumbles incoherently*",
            "Just... want to... rest...",
        },
        [4] = {
            "Feeling warmer now...",
            "*stops shivering*",
            "That was close...",
        },
    },
}

-- ============================================
-- CORPSE SICKNESS (Unified)
-- ============================================
--[[
    Transmission: Prolonged exposure to decomposing corpses
    Duration: 1-3 days, non-lethal but debilitating
    Effects: Nausea, coughing, weakness, fatigue
    Treatment: Fresh air + rest; meds only reduce symptoms
]]--
EHR.Disease.Diseases["corpse_sickness"] = {
    name = "Corpse Exposure Illness",
    incubationMin = 6,
    incubationMax = 18,
    durationMin = 24,
    durationMax = 72,
    stageDurations = {
        [1] = 0.15,
        [2] = 0.35,
        [3] = 0.35,
        [4] = 0.15,
    },
    baseSeverity = 0.6,
    canKill = false,
    stageCount = 4,
    effects = {
        [1] = {
            fatigueDrain = 0.001,
            staminaPenalty = 0.05,
            coughingChance = 0,
            vomitChance = 0,
        },
        [2] = {
            fatigueDrain = 0.003,
            staminaPenalty = 0.15,
            coughingChance = 0.002,
            vomitChance = 0.002,
        },
        [3] = {
            fatigueDrain = 0.006,
            staminaPenalty = 0.35,
            coughingChance = 0.006,
            vomitChance = 0.005,
            movementPenalty = 0.85,
        },
        [4] = {
            fatigueDrain = 0.002,
            staminaPenalty = 0.10,
            coughingChance = 0.001,
        },
    },
    stageEntryDialogue = {
        [1] = "That smell is getting to me...",
        [2] = "I feel nauseous and weak...",
        [3] = "*coughs* I need fresh air... now...",
        [4] = "I think I'm finally recovering...",
    },
    dialogue = {
        [1] = {
            "Ugh... the stench...",
            "Something's rotting nearby...",
        },
        [2] = {
            "*gagging*",
            "My stomach is turning...",
            "I feel sick...",
        },
        [3] = {
            "*coughs*",
            "Head is pounding...",
            "I need to get away from these bodies...",
        },
        [4] = {
            "Breathing easier now...",
            "Never staying near corpses again...",
        },
    },
}

-- ============================================
-- CADAVERIC ASPERGILLOSIS
-- ============================================
--[[
    Transmission: Fungal spores from damp/cold decomposing corpses
    Duration: 7-14 days, potentially lethal without antifungals
    Effects: Respiratory issues, fever, coughing, severe fatigue
    Treatment: Antifungal tablets or IV Amphotericin; inhaler/cough meds reduce symptoms
]]--
EHR.Disease.Diseases["cadaveric_aspergillosis"] = {
    name = "Cadaveric Aspergillosis",
    category = "corpse",
    incubationMin = 24,
    incubationMax = 72,
    durationMin = 168,
    durationMax = 336,
    stageDurations = {
        [1] = 0.15,
        [2] = 0.30,
        [3] = 0.40,
        [4] = 0.15,
    },
    baseSeverity = 0.75,
    canKill = true,
    deathChancePerHour = 0.004,
    deathStage = 3,
    stageCount = 4,
    treatments = {
        tier0 = {},
        tier1 = {"ExtensiveHealth.CoughSyrup", "ExtensiveHealth.CoughSuppressant", "ExtensiveHealth.BronchodilatorInhaler"},
        tier2 = {"ExtensiveHealth.AntifungalTablets"},
        tier3 = {"ExtensiveHealth.IVAmphotericin"},
    },
    effects = {
        [1] = {
            fatigueDrain = 0.001,
            staminaPenalty = 0.05,
            coughingChance = 0,
        },
        [2] = {
            fatigueDrain = 0.004,
            staminaPenalty = 0.20,
            coughingChance = 0.003,
            thirstDrain = 0.002,
        },
        [3] = {
            fatigueDrain = 0.009,
            staminaPenalty = 0.45,
            coughingChance = 0.012,
            thirstDrain = 0.006,
            movementPenalty = 0.75,
            canSprint = false,
            breathingDifficulty = true,
        },
        [4] = {
            fatigueDrain = 0.003,
            staminaPenalty = 0.15,
            coughingChance = 0.002,
        },
    },
    stageEntryDialogue = {
        [1] = "My throat feels dusty after breathing that air...",
        [2] = "*coughs* Something is wrong with my lungs...",
        [3] = "*wheezes* I need antifungals... now...",
        [4] = "The cough is finally easing...",
    },
    dialogue = {
        [1] = {
            "My chest feels scratchy...",
            "That damp corpse air got into my lungs...",
        },
        [2] = {
            "*coughs*",
            "My chest feels tight...",
            "I feel feverish...",
        },
        [3] = {
            "*wheezing cough*",
            "I can barely breathe...",
            "This feels like a lung infection...",
        },
        [4] = {
            "Breathing a little easier...",
            "The fever is breaking...",
        },
    },
}

-- ============================================
-- HEAT EXHAUSTION (Phase 3)
-- ============================================
--[[
    Transmission: High temperature + physical exertion + dehydration
    Duration: 4-12 hours (fast recovery possible)
    Effects: Dizziness, nausea, weakness, thirst drain
    Can progress to: Heat Stroke (LETHAL)
    Treatment: Water, shade, rest, remove clothing
]]--
EHR.Disease.Diseases["heat_exhaustion"] = {
    name = "Heat Exhaustion",
    -- Timing (in game hours) - shorter illness
    incubationMin = 1,      -- 1 hour minimum
    incubationMax = 2,      -- 2 hours maximum
    durationMin = 4,        -- 4 hours minimum
    durationMax = 12,       -- 12 hours maximum
    -- Stage duration percentages
    stageDurations = {
        [1] = 0.15,  -- 15% incubation
        [2] = 0.30,  -- 30% early (heat cramps)
        [3] = 0.35,  -- 35% peak (heat exhaustion)
        [4] = 0.20,  -- 20% recovery
    },
    -- Special: requires cooling to recover
    requiresCoolingForRecovery = true,
    -- Severity
    baseSeverity = 0.5,
    -- Can progress to heat stroke (LETHAL)
    canProgress = true,
    progressTo = "heat_stroke",
    progressChance = 0.40,          -- 40% if untreated in heat
    progressAfterHours = 4,         -- After 4 hours in peak without cooling
    -- Can kill if progresses to heat stroke
    canKill = false,  -- Heat exhaustion itself doesn't kill
    -- Treatment
    treatmentCooling = true,
    treatmentItem = nil,            -- No medicine, need shade + water
    -- Stages
    stageCount = 4,
    -- Stage effects
    effects = {
        [1] = {
            thirstDrain = 0.003,
            staminaPenalty = 0.10,
            sweating = true,
        },
        [2] = {
            thirstDrain = 0.008,
            staminaPenalty = 0.25,
            movementPenalty = 0.85,
            crampChance = 0.005,    -- Muscle cramps
        },
        [3] = {
            thirstDrain = 0.015,
            staminaPenalty = 0.50,
            movementPenalty = 0.70,
            vomitChance = 0.005,
            dizzinessChance = 0.010,
            canSprint = false,
        },
        [4] = {
            thirstDrain = 0.005,
            staminaPenalty = 0.20,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "Getting really hot... sweating buckets.",
        [2] = "*wipes sweat* Leg cramping up... need water.",
        [3] = "*dizzy* Everything's spinning... can't take this heat...",
        [4] = "Finally cooling down... that was close.",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "It's so hot...",
            "Sweating through my clothes...",
        },
        [2] = {
            "*cramps* Ow, my leg!",
            "So thirsty...",
            "Need to get out of this sun...",
        },
        [3] = {
            "*dizzy* World's spinning...",
            "*nauseous* Feel like I'm going to be sick...",
            "Why did I stop sweating? That's bad...",
            "Need shade... water... now...",
        },
        [4] = {
            "Feeling better now...",
            "Need to be more careful in this heat.",
        },
    },
}

-- ============================================
-- HEAT STROKE (Hidden - progression from Heat Exhaustion)
-- ============================================
--[[
    This is the LETHAL version of heat exhaustion
    Player doesn't contract this directly - only progresses from heat exhaustion
    Short, intense, deadly
]]--
EHR.Disease.Diseases["heat_stroke"] = {
    name = "Heat Stroke",
    incubationMin = 0,      -- No incubation, immediate danger
    incubationMax = 0,
    durationMin = 4,        -- 4 hours minimum
    durationMax = 8,        -- 8 hours maximum
    stageDurations = {
        [1] = 0.15,  -- Immediate critical onset
        [2] = 0.25,  -- Escalating dehydration and organ strain
        [3] = 0.45,  -- Long peak (danger)
        [4] = 0.15,  -- Recovery if survived and cooled
    },
    requiresCoolingForRecovery = true,
    baseSeverity = 0.95,
    canKill = true,
    killMechanic = "healthDrain",
    deathStage = 2,
    treatmentCooling = true,
    treatmentReducesDeath = 0.85,
    treatments = {
        tier1 = {"ExtensiveHealth.ElectrolytePowder"},
        tier2 = {"ExtensiveHealth.InstantIcePack"},
    },
    stageCount = 4,
    effects = {
        [1] = {
            thirstDrain = 0.004,
            staminaPenalty = 0.70,
            movementPenalty = 0.65,
            canSprint = false,
            dizzinessChance = 0.080,
            confusionChance = 0.080,
            collapseChance = 0.060,
        },
        [2] = {
            thirstDrain = 0.010,
            healthDrainPerHour = 10,
            staminaPenalty = 0.85,
            movementPenalty = 0.50,
            canSprint = false,
            dizzinessChance = 0.120,
            confusionChance = 0.120,
            collapseChance = 0.100,
        },
        [3] = {
            thirstDrain = 0.016,
            healthDrainPerHour = 24,
            staminaPenalty = 0.95,
            movementPenalty = 0.35,
            canSprint = false,
            dizzinessChance = 0.180,
            confusionChance = 0.180,
            collapseChance = 0.140,
        },
        [4] = {
            thirstDrain = 0.008,
            healthDrainPerHour = 16,
            staminaPenalty = 0.75,
            movementPenalty = 0.50,
            canSprint = false,
            dizzinessChance = 0.120,
            confusionChance = 0.120,
            collapseChance = 0.100,
        },
    },
    stageEntryDialogue = {
        [1] = "*dazed* I'm burning up... I need to cool down now...",
        [2] = "*gasping* Can't... think straight... so hot...",
        [3] = "*delirious* Where... am I? Everything's... burning...",
        [4] = "*weak* Still too hot... need to keep cooling down...",
    },
    dialogue = {
        [1] = {
            "So hot... can't think...",
            "*dizzy* The air is shimmering...",
            "Need shade... now...",
            "*confused* Why is everything so bright?",
        },
        [2] = {
            "*panting*",
            "Can't think...",
            "*confused* I need water... or ice...",
            "*mumbling* Too hot... too hot...",
        },
        [3] = {
            "*delirious mumbling*",
            "*collapses*",
            "Help...",
            "Everything's burning...",
            "*confused* Where am I?",
        },
        [4] = {
            "*weak* Still burning...",
            "Need to cool down... keep cooling down...",
            "*dizzy* Can't stay on my feet...",
        },
    },
    dialogueChanceBase = {
        [1] = 80,
        [2] = 95,
        [3] = 110,
        [4] = 100,
    },
    dialogueCooldownHours = 0.35,
}

-- ============================================
-- TRICHINOSIS (Phase 3 - Parasitic)
-- ============================================
--[[
    Transmission: Raw/undercooked wild game meat (rats, boars, carnivores)
    Duration: 7-12 days (longest non-chronic disease)
    Effects: Severe muscle pain (key symptom), facial swelling, fever
    Treatment: Anti-parasitic medication (rare)
    Key: Muscle pain is distinctive - affects melee damage
]]--
EHR.Disease.Diseases["trichinosis"] = EHR.Disease.Diseases["trichinosis"] or {
    name = "Trichinosis",
    -- Timing (in game hours)
    incubationMin = 24,     -- 24 hours minimum
    incubationMax = 48,     -- 48 hours maximum
    durationMin = 168,      -- 7 days minimum
    durationMax = 288,      -- 12 days maximum
    -- Stage duration percentages
    stageDurations = {
        [1] = 0.15,  -- 15% incubation (larvae in intestines)
        [2] = 0.20,  -- 20% early (intestinal phase)
        [3] = 0.40,  -- 40% peak (muscular phase - painful)
        [4] = 0.25,  -- 25% recovery
    },
    -- Severity
    baseSeverity = 0.7,
    -- Can kill in rare cases
    canKill = true,
    deathChancePerHour = 0.002,     -- Low but present (heart involvement)
    deathStage = 3,
    -- Treatment
    treatmentItem = "AntiParasitic",
    treatmentCured = true,
    treatmentReducesDeath = 0.95,
    -- Stages
    stageCount = 4,
    -- Stage effects
    effects = {
        [1] = {
            -- Larvae developing, no symptoms
        },
        [2] = {
            thirstDrain = 0.002,
            vomitChance = 0.002,
            fatigueDrain = 0.002,
            -- Mild intestinal symptoms
        },
        [3] = {
            fatigueDrain = 0.008,
            staminaPenalty = 0.40,
            movementPenalty = 0.60,
            meleePenalty = 0.50,        -- 50% less melee damage (muscle pain)
            canSprint = false,
            painLevel = 4,              -- Severe muscle pain
        },
        [4] = {
            fatigueDrain = 0.003,
            staminaPenalty = 0.20,
            movementPenalty = 0.85,
            meleePenalty = 0.75,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "That rat meat tasted off...",
        [2] = "Stomach's been upset since that meal... feeling feverish.",
        [3] = "*groans* My muscles are on FIRE... everything hurts to move...",
        [4] = "Pain's finally fading... still sore everywhere.",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "Hope I cooked that enough...",
            "That wild meat smelled funny...",
        },
        [2] = {
            "*stomach cramps*",
            "This isn't normal food poisoning...",
            "Getting feverish...",
        },
        [3] = {
            "*screams in pain* MY MUSCLES!",
            "Can barely move my arms...",
            "Feel like I've been beaten with a bat...",
            "Is something... moving inside me?",
            "Face feels swollen...",
        },
        [4] = {
            "Can finally move without screaming...",
            "Never eating raw meat again. Ever.",
        },
    },
}

-- ============================================
-- GASTROENTERITIS (Phase 3 - Hand Hygiene)
-- ============================================
--[[
    Transmission: Eating with dirty/bloody hands
    Duration: 1-3 days (shorter, less severe)
    Effects: Vomiting, diarrhea, dehydration risk
    Treatment: Hydration, rest, anti-nausea meds
    Key: Teaches hand hygiene - wash before eating
]]--
EHR.Disease.Diseases["gastroenteritis"] = EHR.Disease.Diseases["gastroenteritis"] or {
    name = "Gastroenteritis",
    -- Timing (in game hours)
    incubationMin = 4,      -- 4 hours minimum
    incubationMax = 12,     -- 12 hours maximum
    durationMin = 24,       -- 1 day minimum
    durationMax = 72,       -- 3 days maximum
    -- Stage duration percentages
    stageDurations = {
        [1] = 0.15,  -- 15% incubation
        [2] = 0.25,  -- 25% early
        [3] = 0.35,  -- 35% peak
        [4] = 0.25,  -- 25% recovery
    },
    -- Severity (less severe than dysentery)
    baseSeverity = 0.4,
    -- Usually not lethal
    canKill = false,
    -- Treatment
    treatmentItem = "Pills",        -- Anti-nausea helps
    treatmentReducesDrain = 0.5,
    -- Stages
    stageCount = 4,
    -- Stage effects
    effects = {
        [1] = {
            hungerDrain = 0.002,
            -- Just feeling off
        },
        [2] = {
            thirstDrain = 0.004,
            vomitChance = 0.004,
            fatigueDrain = 0.002,
        },
        [3] = {
            thirstDrain = 0.010,
            vomitChance = 0.008,
            fatigueDrain = 0.004,
            movementPenalty = 0.85,
        },
        [4] = {
            thirstDrain = 0.002,
            vomitChance = 0.001,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "Don't feel hungry... stomach's a bit off.",
        [2] = "Feeling nauseous... shouldn't have eaten with dirty hands.",
        [3] = "*retches* Can't keep anything down...",
        [4] = "Stomach's settling... think I can eat something small.",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "Stomach feels weird...",
            "Not hungry...",
        },
        [2] = {
            "Getting nauseous...",
            "*stomach gurgles*",
            "Should've washed my hands...",
        },
        [3] = {
            "*vomits*",
            "Can't keep anything down...",
            "*groans*",
        },
        [4] = {
            "Feeling better...",
            "Can eat small bites now...",
        },
    },
}

-- ============================================
-- TETANUS (Phase 4 - Endgame)
-- ============================================
--[[
    Transmission: Deep puncture wounds + rust/dirt (rare)
    Duration: 14-21 days (if survived)
    Effects: Lockjaw (can't eat), muscle spasms, breathing difficulty
    Lethality: CRITICAL (50%+ without antitoxin)
    Treatment: Tetanus antitoxin (very rare)
    Key: Terrifying late-game disease - noise/light triggers spasms
]]--
EHR.Disease.Diseases["tetanus"] = {
    name = "Tetanus",
    -- Timing (in game hours) - long incubation
    incubationMin = 72,     -- 3 days minimum
    incubationMax = 168,    -- 7 days maximum
    durationMin = 336,      -- 14 days minimum
    durationMax = 504,      -- 21 days maximum
    -- Stage duration percentages
    stageDurations = {
        [1] = 0.25,  -- 25% incubation (long, wound seems healed)
        [2] = 0.15,  -- 15% early (local tetanus)
        [3] = 0.40,  -- 40% peak (generalized tetanus - DANGER)
        [4] = 0.20,  -- 20% recovery
    },
    -- Severity
    baseSeverity = 0.95,
    -- CRITICAL LETHALITY
    canKill = true,
    deathChancePerHour = 0.02,      -- 2% per hour in peak = very deadly
    deathStage = 3,
    -- Treatment
    treatmentItem = "TetanusAntitoxin",
    treatmentCured = false,         -- Can't cure, just reduces death chance
    treatmentReducesDeath = 0.80,   -- 80% reduction with antitoxin
    -- Special mechanics
    cannotEatInPeak = true,         -- Lockjaw prevents eating
    spasmsTriggeredByNoise = true,  -- Loud noises trigger spasms
    -- Stages
    stageCount = 4,
    -- Stage effects
    effects = {
        [1] = {
            -- Wound seems to be healing normally
            jawStiffness = 0.1,     -- Very slight (late incubation)
        },
        [2] = {
            jawStiffness = 0.5,     -- Noticeable lockjaw
            fatigueDrain = 0.003,
            staminaPenalty = 0.15,
            movementPenalty = 0.90,
            spasmChance = 0.002,
        },
        [3] = {
            jawStiffness = 1.0,     -- Full lockjaw - CANNOT EAT
            fatigueDrain = 0.010,
            staminaPenalty = 0.80,
            movementPenalty = 0.40,
            canSprint = false,
            spasmChance = 0.015,    -- Frequent spasms
            painLevel = 4,
            breathingDifficulty = true,
        },
        [4] = {
            jawStiffness = 0.3,     -- Can eat small amounts
            fatigueDrain = 0.005,
            staminaPenalty = 0.40,
            movementPenalty = 0.70,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "Jaw feels a bit stiff... that wound is taking a while to heal.",
        [2] = "*tries to open mouth* Can barely open my jaw... something's wrong.",
        [3] = "*muscles lock up* AHHH! Can't... move... can't breathe!",
        [4] = "*gasps* Spasms are... less frequent... I might survive this.",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "Jaw's a bit tight...",
            "That rusty nail wound still bothers me...",
        },
        [2] = {
            "*strains to open mouth*",
            "Muscles keep twitching...",
            "Eating is getting hard...",
        },
        [3] = {
            "*VIOLENT SPASM*",
            "*teeth clenched* CAN'T OPEN MY MOUTH!",
            "*back arches painfully*",
            "*gasping* Every sound makes it worse!",
            "I need the antitoxin or I'm dead...",
        },
        [4] = {
            "Can finally open my mouth a little...",
            "Spasms are getting less frequent...",
            "That was the worst thing I've ever experienced...",
        },
    },
}

-- ============================================
-- TUBERCULOSIS (Phase 4 - Endgame Chronic)
-- ============================================
--[[
    Transmission: Cumulative long-term corpse exposure (months)
    Duration: Weeks to months (chronic, requires sustained treatment)
    Effects: Bloody cough, weight loss, severe fatigue
    Lethality: CRITICAL without multi-drug treatment course
    Treatment: Multiple antibiotics for 2-4 weeks
    Key: Long-term consequence of poor corpse management
]]--
EHR.Disease.Diseases["tuberculosis"] = {
    name = "Tuberculosis",
    -- Timing (in game hours)
    incubationMin = 168,    -- 7 days minimum
    incubationMax = 336,    -- 14 days maximum
    durationMin = 504,      -- 21 days minimum (3 weeks)
    durationMax = 1008,     -- 42 days maximum (6 weeks)
    -- Stage duration percentages
    stageDurations = {
        [1] = 0.20,  -- 20% latent (may never progress if healthy)
        [2] = 0.25,  -- 25% active TB (early)
        [3] = 0.35,  -- 35% advanced TB (peak)
        [4] = 0.20,  -- 20% recovery (requires ongoing treatment)
    },
    -- Special: Can remain latent indefinitely if immunity high
    canRemainLatent = true,
    latentProgressChance = 0.05,    -- 5% per day to progress from latent
    immunityPreventsProgress = 0.7, -- High immunity (>0.7) prevents progression
    -- Severity
    baseSeverity = 0.85,
    -- CRITICAL LETHALITY
    canKill = true,
    deathChancePerHour = 0.005,     -- 0.5% per hour in peak = ~12% per day
    deathStage = 3,
    -- Treatment - requires sustained multi-drug regimen
    treatmentItem = "Antibiotics",
    treatmentRequiresDays = 21,     -- Must take for 21 days
    treatmentDosesPerDay = 2,       -- 2 doses per day
    treatmentCured = true,
    treatmentReducesDeath = 0.90,
    -- Relapse if treatment stopped early
    relapseChance = 0.5,            -- 50% chance if stopped before 21 days
    -- Stages
    stageCount = 4,
    -- Stage effects
    effects = {
        [1] = {
            -- Latent: Minimal symptoms, may not progress
        },
        [2] = {
            coughingChance = 0.002,
            fatigueDrain = 0.003,
            hungerDrain = 0.002,    -- Weight loss begins
            staminaPenalty = 0.15,
        },
        [3] = {
            coughingChance = 0.010,
            coughBlood = true,      -- Bloody cough (distinctive)
            fatigueDrain = 0.008,
            hungerDrain = 0.005,    -- Significant weight loss
            staminaPenalty = 0.45,
            movementPenalty = 0.75,
        },
        [4] = {
            coughingChance = 0.003,
            fatigueDrain = 0.003,
            staminaPenalty = 0.20,
            -- Must continue treatment
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "",  -- No dialogue for latent (unaware)
        [2] = "This cough has been going on for weeks... waking up drenched in sweat.",
        [3] = "*coughs blood* Oh god... that's blood. This is TB, isn't it?",
        [4] = "Medicine's working. Slowly. Have to keep taking the pills...",
    },
    -- Random dialogue
    dialogue = {
        [1] = {},  -- No symptoms in latent
        [2] = {
            "*chronic cough*",
            "Night sweats again...",
            "Losing weight no matter how much I eat...",
        },
        [3] = {
            "*coughs blood* That's... that's not good.",
            "Can barely get out of bed...",
            "Feel like I'm wasting away...",
            "Need antibiotics. Multiple kinds. For weeks.",
        },
        [4] = {
            "Have to keep taking the pills...",
            "Stopping early would be a death sentence...",
            "I'm getting better. Slowly.",
        },
    },
}

-- ============================================
-- CONCUSSION (Trauma)
-- ============================================
--[[
    Trigger: Real height fall with injury, or severe vehicle crash.
    Duration: 48 hours, reverse progression from Stage 3 down to Stage 1.
    Effects: Headache, nausea, dizziness/blurred vision.
    Treatment: Rest and time. No direct cure.
]]--
EHR.Disease.Diseases["concussion"] = {
    name = "Concussion",
    category = "wound",

    incubationMin = 0,
    incubationMax = 0,
    durationMin = 48,
    durationMax = 48,

    stageCount = 3,
    reverseProgression = true,
    noStandardTreatment = true,
    noCure = true,
    applyEffectsInStage1 = true,

    baseSeverity = 0.65,
    canKill = false,

    symptoms = {"headache", "dizziness", "blurred_vision", "nausea"},

    stageEntryDialogue = {
        [3] = "My head is ringing... I need to sit still.",
        [2] = "The worst of it is fading, but my head still hurts.",
        [1] = "The fog is lifting. Still need to take it easy.",
    },

    dialogueChanceBase = {
        [3] = 10,
        [2] = 16,
        [1] = 28,
    },
    dialogueCooldownHours = 2,

    dialogue = {
        [3] = {
            "My head is pounding...",
            "Everything keeps spinning...",
            "I feel like I'm going to throw up...",
            "Can't focus. Need to rest.",
        },
        [2] = {
            "Still dizzy...",
            "My head hurts, but not as bad.",
            "Need to move carefully.",
        },
        [1] = {
            "Just a little headache now...",
            "Almost steady again.",
            "The nausea is mostly gone.",
        },
    },
}

-- ============================================
-- KNOX VIRUS INFECTION (Zombie Infection)
-- ============================================
--[[
    Transmission: Zombie bite (vanilla mechanic)
    Duration: Variable based on sandbox settings
    Effects: Fever, deterioration, eventual death and zombification
    Treatment: Knox cure items (Gene Therapy, Phalanx, Immunobooster)
    SPECIAL: Uses vanilla zombie infection mechanics, not EHR disease system
    This definition exists for display purposes in the Medical Monitor
]]--
EHR.Disease.Diseases["Knox_Infection"] = {
    name = "Knox Virus Infection",
    -- Note: Timing is controlled by vanilla sandbox settings, not these values
    incubationMin = 0,
    incubationMax = 0,
    durationMin = 24,       -- Minimum survival time (vanilla)
    durationMax = 72,       -- Maximum survival time (vanilla)
    -- Stage durations (for display purposes)
    stageDurations = {
        [1] = 0.20,  -- Early infection
        [2] = 0.30,  -- Developing
        [3] = 0.30,  -- Critical
        [4] = 0.20,  -- Terminal
    },
    -- Severity
    baseSeverity = 1.0,     -- Maximum severity - this is THE apocalypse virus
    -- LETHAL - 100% fatal without cure
    canKill = true,
    deathChancePerHour = 0.0,   -- Death is handled by vanilla, not EHR
    deathStage = 4,             -- Terminal stage
    -- Treatment (special handling via EHR_KnoxCure.lua)
    treatmentItem = nil,        -- Uses Knox cure system, not standard treatment
    specialTreatment = true,    -- Flag for UI to show special treatment options
    -- Stages
    stageCount = 4,
    -- Symptoms (for display)
    symptoms = {"fever", "chills", "confusion", "aggression", "deterioration"},
    -- Stage effects (display only - vanilla handles actual effects)
    effects = {
        [1] = {
            description = "Early Infection",
            feverLevel = 0.3,
        },
        [2] = {
            description = "Progressing",
            feverLevel = 0.5,
        },
        [3] = {
            description = "Critical",
            feverLevel = 0.8,
        },
        [4] = {
            description = "Terminal",
            feverLevel = 1.0,
        },
    },
    -- Stage entry dialogue
    stageEntryDialogue = {
        [1] = "I... I've been bitten. This can't be happening...",
        [2] = "*shivers* Getting feverish... it's the virus, isn't it?",
        [3] = "*confused* Can't think straight... time's running out...",
        [4] = "*resigned* This is it... I can feel myself slipping away...",
    },
    -- Random dialogue
    dialogue = {
        [1] = {
            "Maybe it won't take... maybe I'll be okay...",
            "I need to find a cure... there has to be something...",
            "*checks bite mark* It's getting red...",
        },
        [2] = {
            "The fever... it's getting worse...",
            "I don't have much time...",
            "*shivers uncontrollably*",
            "Need to find Phalanx... or Gene Therapy...",
        },
        [3] = {
            "*mumbles incoherently*",
            "Who... who are you? Where am I?",
            "The hunger... it's... different...",
            "*aggressive outburst* Stay away from me!",
        },
        [4] = {
            "*barely conscious*",
            "Tell them... tell them I tried...",
            "I'm sorry... I'm so sorry...",
        },
    },
    -- Special flags for Knox
    isKnoxVirus = true,
    usesVanillaMechanics = true,
    curableBy = {"GeneTherapyKit", "PhalanxPills"},
    preventableBy = {"ImmunoboosterShot"},
}

-- Log loaded diseases
local diseaseCount = 0
for _ in pairs(EHR.Disease.Diseases) do
    diseaseCount = diseaseCount + 1
end

EHR.Log(string.format("Disease definitions loaded. Total diseases: %d", diseaseCount))
EHR.Log("  - common_cold: Cold weather + wet -> can progress to pneumonia")
EHR.Log("  - pneumonia: LETHAL without antibiotics, coughing attracts zombies")
EHR.Log("  - dysentery: Contaminated water -> LETHAL dehydration")
EHR.Log("  - hypothermia: Cold + wet -> LETHAL cardiac arrest")
EHR.Log("  - corpse_sickness: Prolonged corpse exposure -> nausea + weakness")
EHR.Log("  - cadaveric_aspergillosis: Damp/cold corpses -> fungal lung infection")
EHR.Log("  - heat_exhaustion: Heat + exertion -> can progress to heat stroke")
EHR.Log("  - heat_stroke: LETHAL without cooling")
EHR.Log("  - trichinosis: Raw meat -> SEVERE muscle pain + potential death")
EHR.Log("  - gastroenteritis: Dirty hands + eating -> vomiting, dehydration")
EHR.Log("  - tetanus: Rusty wounds -> LETHAL lockjaw, spasms")
EHR.Log("  - tuberculosis: Long-term corpse exposure -> LETHAL chronic illness")
EHR.Log("  - concussion: Falls/crashes -> head trauma, nausea, dizziness")
EHR.Log("  - Knox_Infection: Zombie bite -> LETHAL without Knox cure items")
