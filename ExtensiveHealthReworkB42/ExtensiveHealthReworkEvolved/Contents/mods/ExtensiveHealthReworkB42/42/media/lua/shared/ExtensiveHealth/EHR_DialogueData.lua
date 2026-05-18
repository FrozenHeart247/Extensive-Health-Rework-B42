--[[
    Extensive Health Rework B42
    Dialogue Data Module

    Massive database of skill-tiered dialogue lines for diseases.
    Structure: EHR.DialogueData.Diseases[disease][stage][tierGroup] = {translation_keys}

    Tier Groups:
        clueless (skill 0) - Vague, confused descriptions
        novice (skill 1-3) - Basic awareness, simple terms
        intermediate (skill 4-6) - Can identify common issues
        expert (skill 7-9) - Professional-level knowledge
        master (skill 10) - Full medical terminology

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.DialogueData = {}

-- ============================================
-- DISEASE DIALOGUE DATABASE
-- ============================================

EHR.DialogueData.Diseases = {

    -- ==========================================
    -- SEPSIS
    -- ==========================================
    ["Sepsis"] = {
        [1] = {  -- Stage 1: Early
            clueless = {
                "EHR_Dialogue_Sepsis_S1_Clueless_1",  -- "I feel really off... maybe tired?"
                "EHR_Dialogue_Sepsis_S1_Clueless_2",  -- "Something's not right with me..."
                "EHR_Dialogue_Sepsis_S1_Clueless_3",  -- "Why do I feel so weird?"
                "EHR_Dialogue_Sepsis_S1_Clueless_4",  -- "Just need some rest, probably..."
            },
            novice = {
                "EHR_Dialogue_Sepsis_S1_Novice_1",    -- "I might be getting sick from that wound..."
                "EHR_Dialogue_Sepsis_S1_Novice_2",    -- "That cut doesn't look good, I feel feverish"
                "EHR_Dialogue_Sepsis_S1_Novice_3",    -- "Think my wound might be infected..."
            },
            intermediate = {
                "EHR_Dialogue_Sepsis_S1_Inter_1",     -- "Early signs of infection. Need antibiotics."
                "EHR_Dialogue_Sepsis_S1_Inter_2",     -- "Wound's getting infected, need to treat this fast."
                "EHR_Dialogue_Sepsis_S1_Inter_3",     -- "Systemic infection starting. This is serious."
            },
            expert = {
                "EHR_Dialogue_Sepsis_S1_Expert_1",    -- "SIRS criteria - elevated temp, increased heart rate."
                "EHR_Dialogue_Sepsis_S1_Expert_2",    -- "Early sepsis indicators. IV antibiotics needed."
                "EHR_Dialogue_Sepsis_S1_Expert_3",    -- "Inflammatory response to wound infection detected."
            },
            master = {
                "EHR_Dialogue_Sepsis_S1_Master_1",    -- "Sepsis Stage 1. qSOFA score indicates systemic response."
                "EHR_Dialogue_Sepsis_S1_Master_2",    -- "Presenting with SIRS. Broad-spectrum antibiotics required."
            },
        },
        [2] = {  -- Stage 2: Moderate
            clueless = {
                "EHR_Dialogue_Sepsis_S2_Clueless_1",  -- "I feel terrible... so tired and cold..."
                "EHR_Dialogue_Sepsis_S2_Clueless_2",  -- "Everything hurts... can't think straight..."
            },
            novice = {
                "EHR_Dialogue_Sepsis_S2_Novice_1",    -- "The infection is spreading... need medicine!"
                "EHR_Dialogue_Sepsis_S2_Novice_2",    -- "Getting worse... fever won't break..."
            },
            intermediate = {
                "EHR_Dialogue_Sepsis_S2_Inter_1",     -- "Sepsis progressing. Need stronger antibiotics now."
                "EHR_Dialogue_Sepsis_S2_Inter_2",     -- "Blood pressure dropping. This is septic shock territory."
            },
            expert = {
                "EHR_Dialogue_Sepsis_S2_Expert_1",    -- "Organ dysfunction beginning. Lactate levels likely elevated."
                "EHR_Dialogue_Sepsis_S2_Expert_2",    -- "Severe sepsis. Need fluid resuscitation and antibiotics."
            },
            master = {
                "EHR_Dialogue_Sepsis_S2_Master_1",    -- "Severe sepsis with hypoperfusion. Immediate intervention required."
            },
        },
        [3] = {  -- Stage 3: Severe
            clueless = {
                "EHR_Dialogue_Sepsis_S3_Clueless_1",  -- "I... I can't... everything is wrong..."
                "EHR_Dialogue_Sepsis_S3_Clueless_2",  -- "So cold... can't feel my hands..."
            },
            novice = {
                "EHR_Dialogue_Sepsis_S3_Novice_1",    -- "I'm dying... the infection is killing me..."
            },
            intermediate = {
                "EHR_Dialogue_Sepsis_S3_Inter_1",     -- "Septic shock. Organs are failing. Need emergency care."
            },
            expert = {
                "EHR_Dialogue_Sepsis_S3_Expert_1",    -- "Multi-organ dysfunction syndrome. Mortality rate critical."
            },
            master = {
                "EHR_Dialogue_Sepsis_S3_Master_1",    -- "Refractory septic shock. Without ICU-level intervention, prognosis is terminal."
            },
        },
        [4] = {  -- Stage 4: Critical/Terminal
            clueless = {
                "EHR_Dialogue_Sepsis_S4_Clueless_1",  -- "..."  (barely conscious)
            },
            novice = {
                "EHR_Dialogue_Sepsis_S4_Novice_1",    -- "This is it... goodbye..."
            },
            intermediate = {
                "EHR_Dialogue_Sepsis_S4_Inter_1",     -- "Total organ failure... nothing can save me now..."
            },
            expert = {
                "EHR_Dialogue_Sepsis_S4_Expert_1",    -- "Terminal sepsis... no viable treatment options remain..."
            },
            master = {
                "EHR_Dialogue_Sepsis_S4_Master_1",    -- "End-stage multiple organ dysfunction syndrome..."
            },
        },
    },

    -- ==========================================
    -- FOOD POISONING
    -- ==========================================
    ["FoodPoisoning"] = {
        [1] = {  -- Stage 1: Onset
            clueless = {
                "EHR_Dialogue_FoodPoisoning_S1_Clueless_1",  -- "My stomach feels weird..."
                "EHR_Dialogue_FoodPoisoning_S1_Clueless_2",  -- "I don't feel so good..."
                "EHR_Dialogue_FoodPoisoning_S1_Clueless_3",  -- "Something I ate maybe?"
            },
            novice = {
                "EHR_Dialogue_FoodPoisoning_S1_Novice_1",    -- "Think I got food poisoning..."
                "EHR_Dialogue_FoodPoisoning_S1_Novice_2",    -- "Shouldn't have eaten that..."
            },
            intermediate = {
                "EHR_Dialogue_FoodPoisoning_S1_Inter_1",     -- "Foodborne illness. Need to stay hydrated."
                "EHR_Dialogue_FoodPoisoning_S1_Inter_2",     -- "Early food poisoning. Probably bacterial."
            },
            expert = {
                "EHR_Dialogue_FoodPoisoning_S1_Expert_1",    -- "Acute gastroenteritis from contaminated food. Onset suggests bacterial toxin."
            },
            master = {
                "EHR_Dialogue_FoodPoisoning_S1_Master_1",    -- "Foodborne intoxication, likely Staphylococcal or Bacillus cereus based on onset time."
            },
        },
        [2] = {  -- Stage 2: Acute
            clueless = {
                "EHR_Dialogue_FoodPoisoning_S2_Clueless_1",  -- "Ugh... gonna be sick..."
                "EHR_Dialogue_FoodPoisoning_S2_Clueless_2",  -- "Why won't this stop..."
            },
            novice = {
                "EHR_Dialogue_FoodPoisoning_S2_Novice_1",    -- "Bad food poisoning... need water..."
            },
            intermediate = {
                "EHR_Dialogue_FoodPoisoning_S2_Inter_1",     -- "Severe dehydration risk. Need oral rehydration."
            },
            expert = {
                "EHR_Dialogue_FoodPoisoning_S2_Expert_1",    -- "Acute phase. Monitor for signs of dehydration and electrolyte imbalance."
            },
            master = {
                "EHR_Dialogue_FoodPoisoning_S2_Master_1",    -- "Peak toxin effect. Supportive care and fluid replacement indicated."
            },
        },
        [3] = {  -- Stage 3: Severe
            clueless = {
                "EHR_Dialogue_FoodPoisoning_S3_Clueless_1",  -- "I'm so weak... can't stop..."
            },
            novice = {
                "EHR_Dialogue_FoodPoisoning_S3_Novice_1",    -- "This is really bad... I'm too weak..."
            },
            intermediate = {
                "EHR_Dialogue_FoodPoisoning_S3_Inter_1",     -- "Severe dehydration. Need IV fluids if possible."
            },
            expert = {
                "EHR_Dialogue_FoodPoisoning_S3_Expert_1",    -- "Hypovolemic state from fluid loss. Critical dehydration."
            },
            master = {
                "EHR_Dialogue_FoodPoisoning_S3_Master_1",    -- "Severe gastroenteritis with hypovolemia. IV fluid resuscitation required."
            },
        },
        [4] = {  -- Stage 4: Critical
            clueless = {
                "EHR_Dialogue_FoodPoisoning_S4_Clueless_1",  -- "...help..."
            },
            novice = {
                "EHR_Dialogue_FoodPoisoning_S4_Novice_1",    -- "I can't take anymore..."
            },
            intermediate = {
                "EHR_Dialogue_FoodPoisoning_S4_Inter_1",     -- "Organ stress from dehydration... this could kill me..."
            },
            expert = {
                "EHR_Dialogue_FoodPoisoning_S4_Expert_1",    -- "Cardiac and renal compromise from severe dehydration."
            },
            master = {
                "EHR_Dialogue_FoodPoisoning_S4_Master_1",    -- "Multi-system failure secondary to hypovolemic shock."
            },
        },
    },

    -- ==========================================
    -- HYPOTHERMIA
    -- ==========================================
    ["Hypothermia"] = {
        [1] = {  -- Stage 1: Mild
            clueless = {
                "EHR_Dialogue_Hypothermia_S1_Clueless_1",  -- "Brrr... it's cold..."
                "EHR_Dialogue_Hypothermia_S1_Clueless_2",  -- "Can't stop shivering..."
                "EHR_Dialogue_Hypothermia_S1_Clueless_3",  -- "My hands are so cold..."
            },
            novice = {
                "EHR_Dialogue_Hypothermia_S1_Novice_1",    -- "Getting too cold... need to warm up..."
                "EHR_Dialogue_Hypothermia_S1_Novice_2",    -- "Think I'm getting hypothermia..."
            },
            intermediate = {
                "EHR_Dialogue_Hypothermia_S1_Inter_1",     -- "Mild hypothermia. Need shelter and warmth now."
                "EHR_Dialogue_Hypothermia_S1_Inter_2",     -- "Core temp dropping. Shivering is a warning sign."
            },
            expert = {
                "EHR_Dialogue_Hypothermia_S1_Expert_1",    -- "Stage 1 hypothermia - shivering, vasoconstriction. Need passive rewarming."
            },
            master = {
                "EHR_Dialogue_Hypothermia_S1_Master_1",    -- "Mild hypothermia, core temp 32-35C. Remove wet clothing, passive external rewarming."
            },
        },
        [2] = {  -- Stage 2: Moderate
            clueless = {
                "EHR_Dialogue_Hypothermia_S2_Clueless_1",  -- "S-so sleepy... just want to rest..."
                "EHR_Dialogue_Hypothermia_S2_Clueless_2",  -- "Fingers won't work right..."
            },
            novice = {
                "EHR_Dialogue_Hypothermia_S2_Novice_1",    -- "This is bad... can't feel my hands anymore..."
            },
            intermediate = {
                "EHR_Dialogue_Hypothermia_S2_Inter_1",     -- "Moderate hypothermia. Confusion setting in. Need heat source."
            },
            expert = {
                "EHR_Dialogue_Hypothermia_S2_Expert_1",    -- "Stage 2 hypothermia - decreased shivering, mental confusion. Active rewarming needed."
            },
            master = {
                "EHR_Dialogue_Hypothermia_S2_Master_1",    -- "Moderate hypothermia, core 28-32C. Active external rewarming, handle gently to avoid cardiac arrhythmia."
            },
        },
        [3] = {  -- Stage 3: Severe
            clueless = {
                "EHR_Dialogue_Hypothermia_S3_Clueless_1",  -- "...not...cold...anymore..."  (paradoxical warmth)
            },
            novice = {
                "EHR_Dialogue_Hypothermia_S3_Novice_1",    -- "Feel warm now... that's bad, isn't it..."
            },
            intermediate = {
                "EHR_Dialogue_Hypothermia_S3_Inter_1",     -- "Severe hypothermia. Paradoxical warmth means I'm dying."
            },
            expert = {
                "EHR_Dialogue_Hypothermia_S3_Expert_1",    -- "Severe hypothermia - paradoxical undressing, cardiac risk. ICU-level care needed."
            },
            master = {
                "EHR_Dialogue_Hypothermia_S3_Master_1",    -- "Severe hypothermia, core below 28C. Risk of ventricular fibrillation. Active core rewarming required."
            },
        },
        [4] = {  -- Stage 4: Profound
            clueless = {
                "EHR_Dialogue_Hypothermia_S4_Clueless_1",  -- "..."  (unresponsive)
            },
            novice = {
                "EHR_Dialogue_Hypothermia_S4_Novice_1",    -- "Can't... move..."
            },
            intermediate = {
                "EHR_Dialogue_Hypothermia_S4_Inter_1",     -- "Heart... stopping..."
            },
            expert = {
                "EHR_Dialogue_Hypothermia_S4_Expert_1",    -- "Profound hypothermia... cardiac standstill imminent..."
            },
            master = {
                "EHR_Dialogue_Hypothermia_S4_Master_1",    -- "Core temp critical. Apparent death. CPR and ECMO rewarming only hope."
            },
        },
    },

    -- ==========================================
    -- HEAT STROKE
    -- ==========================================
    ["HeatStroke"] = {
        [1] = {
            clueless = {
                "EHR_Dialogue_HeatStroke_S1_Clueless_1",  -- "So hot... head is pounding..."
                "EHR_Dialogue_HeatStroke_S1_Clueless_2",  -- "Feel dizzy from the heat..."
            },
            novice = {
                "EHR_Dialogue_HeatStroke_S1_Novice_1",    -- "Getting heat exhaustion... need shade and water..."
            },
            intermediate = {
                "EHR_Dialogue_HeatStroke_S1_Inter_1",     -- "Early heat illness. Core temp rising. Need cooling now."
            },
            expert = {
                "EHR_Dialogue_HeatStroke_S1_Expert_1",    -- "Heat exhaustion progressing. Risk of exertional heat stroke."
            },
            master = {
                "EHR_Dialogue_HeatStroke_S1_Master_1",    -- "Thermoregulatory stress. Remove from heat, begin cooling measures."
            },
        },
        [2] = {
            clueless = {
                "EHR_Dialogue_HeatStroke_S2_Clueless_1",  -- "Can't... think... too hot..."
            },
            novice = {
                "EHR_Dialogue_HeatStroke_S2_Novice_1",    -- "Heat stroke... need to cool down fast!"
            },
            intermediate = {
                "EHR_Dialogue_HeatStroke_S2_Inter_1",     -- "Heat stroke developing. Mental status changes. Emergency cooling needed."
            },
            expert = {
                "EHR_Dialogue_HeatStroke_S2_Expert_1",    -- "Classic heat stroke - hyperthermia with CNS dysfunction. Ice water immersion if available."
            },
            master = {
                "EHR_Dialogue_HeatStroke_S2_Master_1",    -- "Exertional heat stroke, core likely >40C. Rapid cooling critical to prevent rhabdomyolysis."
            },
        },
        [3] = {
            clueless = {
                "EHR_Dialogue_HeatStroke_S3_Clueless_1",  -- "Everything... spinning..."
            },
            novice = {
                "EHR_Dialogue_HeatStroke_S3_Novice_1",    -- "I'm burning up inside..."
            },
            intermediate = {
                "EHR_Dialogue_HeatStroke_S3_Inter_1",     -- "Severe heat stroke. Organ damage occurring."
            },
            expert = {
                "EHR_Dialogue_HeatStroke_S3_Expert_1",    -- "Multi-organ dysfunction from hyperthermia. Coagulopathy likely."
            },
            master = {
                "EHR_Dialogue_HeatStroke_S3_Master_1",    -- "Severe heat stroke with DIC and rhabdomyolysis. Mortality risk extreme."
            },
        },
        [4] = {
            clueless = {
                "EHR_Dialogue_HeatStroke_S4_Clueless_1",  -- "..."
            },
            novice = {
                "EHR_Dialogue_HeatStroke_S4_Novice_1",    -- "Can't... breathe..."
            },
            intermediate = {
                "EHR_Dialogue_HeatStroke_S4_Inter_1",     -- "Organs... shutting down..."
            },
            expert = {
                "EHR_Dialogue_HeatStroke_S4_Expert_1",    -- "Terminal hyperthermia... brain damage irreversible..."
            },
            master = {
                "EHR_Dialogue_HeatStroke_S4_Master_1",    -- "End-stage heat stroke with cerebral edema and multi-system failure."
            },
        },
    },

    -- ==========================================
    -- FLU
    -- ==========================================
    ["Flu"] = {
        [1] = {
            clueless = {
                "EHR_Dialogue_Flu_S1_Clueless_1",  -- "Got the sniffles..."
                "EHR_Dialogue_Flu_S1_Clueless_2",  -- "Think I'm catching something..."
            },
            novice = {
                "EHR_Dialogue_Flu_S1_Novice_1",    -- "Coming down with the flu..."
            },
            intermediate = {
                "EHR_Dialogue_Flu_S1_Inter_1",     -- "Influenza symptoms. Rest and fluids needed."
            },
            expert = {
                "EHR_Dialogue_Flu_S1_Expert_1",    -- "Typical influenza presentation. Monitor for complications."
            },
            master = {
                "EHR_Dialogue_Flu_S1_Master_1",    -- "Influenza-like illness, likely viral URI. Symptomatic treatment indicated."
            },
        },
        [2] = {
            clueless = {
                "EHR_Dialogue_Flu_S2_Clueless_1",  -- "Feel awful... body aches everywhere..."
            },
            novice = {
                "EHR_Dialogue_Flu_S2_Novice_1",    -- "Bad flu... fever and chills..."
            },
            intermediate = {
                "EHR_Dialogue_Flu_S2_Inter_1",     -- "Moderate flu. Watch for pneumonia signs."
            },
            expert = {
                "EHR_Dialogue_Flu_S2_Expert_1",    -- "Influenza with systemic symptoms. Risk of secondary bacterial infection."
            },
            master = {
                "EHR_Dialogue_Flu_S2_Master_1",    -- "Moderate influenza. Oseltamivir within 48h of onset would be ideal."
            },
        },
        [3] = {
            clueless = {
                "EHR_Dialogue_Flu_S3_Clueless_1",  -- "Can barely move... so weak..."
            },
            novice = {
                "EHR_Dialogue_Flu_S3_Novice_1",    -- "Worst flu ever... can't breathe right..."
            },
            intermediate = {
                "EHR_Dialogue_Flu_S3_Inter_1",     -- "Severe flu with respiratory involvement. Need antibiotics for secondary infection."
            },
            expert = {
                "EHR_Dialogue_Flu_S3_Expert_1",    -- "Complicated influenza, possible viral pneumonia or bacterial superinfection."
            },
            master = {
                "EHR_Dialogue_Flu_S3_Master_1",    -- "Severe influenza with ARDS risk. Empiric antibiotics for bacterial co-infection."
            },
        },
        [4] = {
            clueless = {
                "EHR_Dialogue_Flu_S4_Clueless_1",  -- "Can't... breathe..."
            },
            novice = {
                "EHR_Dialogue_Flu_S4_Novice_1",    -- "The flu is killing me..."
            },
            intermediate = {
                "EHR_Dialogue_Flu_S4_Inter_1",     -- "Pneumonia complications... respiratory failure..."
            },
            expert = {
                "EHR_Dialogue_Flu_S4_Expert_1",    -- "Influenza-associated ARDS... ventilator support needed..."
            },
            master = {
                "EHR_Dialogue_Flu_S4_Master_1",    -- "Fulminant influenza with cytokine storm and multi-organ failure."
            },
        },
    },

    -- ==========================================
    -- WOUND INFECTION
    -- ==========================================
    ["WoundInfection"] = {
        [1] = {
            clueless = {
                "EHR_Dialogue_WoundInfection_S1_Clueless_1",  -- "This wound looks red..."
                "EHR_Dialogue_WoundInfection_S1_Clueless_2",  -- "It hurts more than before..."
            },
            novice = {
                "EHR_Dialogue_WoundInfection_S1_Novice_1",    -- "Wound is getting infected... need to clean it..."
            },
            intermediate = {
                "EHR_Dialogue_WoundInfection_S1_Inter_1",     -- "Local wound infection. Needs cleaning and antibiotics."
            },
            expert = {
                "EHR_Dialogue_WoundInfection_S1_Expert_1",    -- "Cellulitis developing. Oral antibiotics should suffice at this stage."
            },
            master = {
                "EHR_Dialogue_WoundInfection_S1_Master_1",    -- "Localized bacterial infection, likely Staph aureus. Debridement and antibiotics."
            },
        },
        [2] = {
            clueless = {
                "EHR_Dialogue_WoundInfection_S2_Clueless_1",  -- "There's pus coming out..."
            },
            novice = {
                "EHR_Dialogue_WoundInfection_S2_Novice_1",    -- "Infection is spreading... this is bad..."
            },
            intermediate = {
                "EHR_Dialogue_WoundInfection_S2_Inter_1",     -- "Advancing cellulitis. Risk of systemic spread."
            },
            expert = {
                "EHR_Dialogue_WoundInfection_S2_Expert_1",    -- "Progressing soft tissue infection. IV antibiotics warranted."
            },
            master = {
                "EHR_Dialogue_WoundInfection_S2_Master_1",    -- "Spreading cellulitis with abscess formation. I&D may be necessary."
            },
        },
        [3] = {
            clueless = {
                "EHR_Dialogue_WoundInfection_S3_Clueless_1",  -- "My whole arm/leg is swelling..."
            },
            novice = {
                "EHR_Dialogue_WoundInfection_S3_Novice_1",    -- "Infection is really bad now... feel feverish..."
            },
            intermediate = {
                "EHR_Dialogue_WoundInfection_S3_Inter_1",     -- "Severe wound infection. May become septic."
            },
            expert = {
                "EHR_Dialogue_WoundInfection_S3_Expert_1",    -- "Necrotizing soft tissue infection possible. Urgent surgical evaluation needed."
            },
            master = {
                "EHR_Dialogue_WoundInfection_S3_Master_1",    -- "Suspected necrotizing fasciitis. Emergent surgical debridement is life-saving."
            },
        },
        [4] = {
            clueless = {
                "EHR_Dialogue_WoundInfection_S4_Clueless_1",  -- "The skin is turning black..."
            },
            novice = {
                "EHR_Dialogue_WoundInfection_S4_Novice_1",    -- "I'm going to lose this limb... or worse..."
            },
            intermediate = {
                "EHR_Dialogue_WoundInfection_S4_Inter_1",     -- "Gangrene... without amputation, I'll die..."
            },
            expert = {
                "EHR_Dialogue_WoundInfection_S4_Expert_1",    -- "Gas gangrene or necrotizing fasciitis. Amputation or death."
            },
            master = {
                "EHR_Dialogue_WoundInfection_S4_Master_1",    -- "Fournier's gangrene or Type I necrotizing fasciitis. Mortality exceeds 30% even with surgery."
            },
        },
    },

    -- TODO: Add remaining diseases:
    -- Cold, Salmonella, Gastroenteritis, CorpseDisease,
    -- TuberculosisCavitary, TuberculosisMilliary, Tetanus, Rabies,
    -- Frostbite, and any others
}

-- ============================================
-- FALSE ASSUMPTION DIALOGUE
-- When player misdiagnoses a condition
-- ============================================

EHR.DialogueData.FalseAssumptions = {
    -- Sepsis misdiagnosed as other conditions
    ["Sepsis_as_FoodPoisoning"] = {
        "EHR_Dialogue_False_SepsisAsFood_1",  -- "Must've eaten something bad..."
        "EHR_Dialogue_False_SepsisAsFood_2",  -- "Probably just food poisoning, it'll pass..."
        "EHR_Dialogue_False_SepsisAsFood_3",  -- "Bad food is all, need to rest..."
    },
    ["Sepsis_as_Flu"] = {
        "EHR_Dialogue_False_SepsisAsFlu_1",   -- "Just a bad flu, I'll sleep it off..."
        "EHR_Dialogue_False_SepsisAsFlu_2",   -- "Caught something, chicken soup time..."
    },
    ["Sepsis_as_Exhaustion"] = {
        "EHR_Dialogue_False_SepsisAsExhaustion_1",  -- "Just tired... need more sleep..."
    },

    -- Food poisoning misdiagnosed
    ["FoodPoisoning_as_Flu"] = {
        "EHR_Dialogue_False_FoodAsFlu_1",     -- "Must be the flu going around..."
    },
    ["FoodPoisoning_as_Anxiety"] = {
        "EHR_Dialogue_False_FoodAsAnxiety_1", -- "Just stress... my stomach always acts up..."
    },

    -- Hypothermia misdiagnosed
    ["Hypothermia_as_Flu"] = {
        "EHR_Dialogue_False_HypoAsFlu_1",     -- "Coming down with something... feel cold and achy..."
    },
    ["Hypothermia_as_Exhaustion"] = {
        "EHR_Dialogue_False_HypoAsExhaustion_1", -- "Just need to rest... so tired..."
    },

    -- Heat stroke misdiagnosed
    ["HeatStroke_as_Fever"] = {
        "EHR_Dialogue_False_HeatAsFever_1",   -- "Running a fever... need medicine..."
    },
    ["HeatStroke_as_Dehydration"] = {
        "EHR_Dialogue_False_HeatAsDehydration_1", -- "Just dehydrated... drink some water..."
    },

    -- Generic fallback
    ["Unknown_as_Unknown"] = {
        "EHR_Dialogue_False_Unknown_1",       -- "I'm fine... just need rest..."
        "EHR_Dialogue_False_Unknown_2",       -- "It's nothing serious..."
    },
}

-- ============================================
-- TREATMENT HINTS
-- What treatment is suggested based on diagnosis
-- ============================================

EHR.DialogueData.TreatmentHints = {
    ["Sepsis"] = {
        novice = "EHR_Dialogue_Treat_Sepsis_Novice",        -- "Maybe some medicine would help?"
        intermediate = "EHR_Dialogue_Treat_Sepsis_Inter",   -- "Need antibiotics and rest"
        expert = "EHR_Dialogue_Treat_Sepsis_Expert",        -- "IV antibiotics, fluids, and monitoring"
        master = "EHR_Dialogue_Treat_Sepsis_Master",        -- "Broad-spectrum IV antibiotics, fluid resuscitation, source control"
    },
    ["FoodPoisoning"] = {
        novice = "EHR_Dialogue_Treat_FoodPoisoning_Novice",
        intermediate = "EHR_Dialogue_Treat_FoodPoisoning_Inter",
        expert = "EHR_Dialogue_Treat_FoodPoisoning_Expert",
        master = "EHR_Dialogue_Treat_FoodPoisoning_Master",
    },
    ["Hypothermia"] = {
        novice = "EHR_Dialogue_Treat_Hypothermia_Novice",
        intermediate = "EHR_Dialogue_Treat_Hypothermia_Inter",
        expert = "EHR_Dialogue_Treat_Hypothermia_Expert",
        master = "EHR_Dialogue_Treat_Hypothermia_Master",
    },
    ["HeatStroke"] = {
        novice = "EHR_Dialogue_Treat_HeatStroke_Novice",
        intermediate = "EHR_Dialogue_Treat_HeatStroke_Inter",
        expert = "EHR_Dialogue_Treat_HeatStroke_Expert",
        master = "EHR_Dialogue_Treat_HeatStroke_Master",
    },
    ["Flu"] = {
        novice = "EHR_Dialogue_Treat_Flu_Novice",
        intermediate = "EHR_Dialogue_Treat_Flu_Inter",
        expert = "EHR_Dialogue_Treat_Flu_Expert",
        master = "EHR_Dialogue_Treat_Flu_Master",
    },
    ["WoundInfection"] = {
        novice = "EHR_Dialogue_Treat_WoundInfection_Novice",
        intermediate = "EHR_Dialogue_Treat_WoundInfection_Inter",
        expert = "EHR_Dialogue_Treat_WoundInfection_Expert",
        master = "EHR_Dialogue_Treat_WoundInfection_Master",
    },
}

-- ============================================
-- WRONG TREATMENT SUGGESTIONS
-- What treatment a misdiagnosis would suggest
-- ============================================

EHR.DialogueData.WrongTreatments = {
    ["Sepsis_as_FoodPoisoning"] = {
        "EHR_Dialogue_WrongTreat_SepsisAsFood_1",  -- "Just need to rest and let it pass..."
        "EHR_Dialogue_WrongTreat_SepsisAsFood_2",  -- "Drink fluids, it's just food poisoning..."
    },
    ["Sepsis_as_Flu"] = {
        "EHR_Dialogue_WrongTreat_SepsisAsFlu_1",   -- "Some cold medicine should help..."
    },
    ["Hypothermia_as_Flu"] = {
        "EHR_Dialogue_WrongTreat_HypoAsFlu_1",     -- "Take some medicine for the fever..."
    },
}

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

--[[
    Get dialogue entries for a disease/stage/tier combination.
    @param disease (string) - Disease ID
    @param stage (number) - Stage 1-4
    @param tierGroup (string) - "clueless", "novice", etc.
    @return table - Array of translation keys, or nil if not found
]]--
function EHR.DialogueData.GetDiseaseDialogue(disease, stage, tierGroup)
    if not EHR.DialogueData.Diseases[disease] then
        return nil
    end
    if not EHR.DialogueData.Diseases[disease][stage] then
        return nil
    end
    return EHR.DialogueData.Diseases[disease][stage][tierGroup]
end

--[[
    Get a random dialogue entry for a disease/stage/tier.
    @param disease (string) - Disease ID
    @param stage (number) - Stage 1-4
    @param tierGroup (string) - Tier group name
    @return string - Translation key, or nil if not found
]]--
function EHR.DialogueData.GetRandomDialogueKey(disease, stage, tierGroup)
    local entries = EHR.DialogueData.GetDiseaseDialogue(disease, stage, tierGroup)
    if not entries or #entries == 0 then
        return nil
    end
    local index = ZombRand(#entries) + 1
    return entries[index]
end

--[[
    Get false assumption dialogue for a misdiagnosis.
    @param actualDisease (string) - What the disease actually is
    @param diagnosedAs (string) - What it was diagnosed as
    @return string - Translation key, or nil
]]--
function EHR.DialogueData.GetFalseAssumptionKey(actualDisease, diagnosedAs)
    local key = actualDisease .. "_as_" .. diagnosedAs
    local entries = EHR.DialogueData.FalseAssumptions[key]

    if not entries then
        -- Try generic fallback
        entries = EHR.DialogueData.FalseAssumptions["Unknown_as_Unknown"]
    end

    if not entries or #entries == 0 then
        return nil
    end

    local index = ZombRand(#entries) + 1
    return entries[index]
end

--[[
    Get treatment hint for a disease and tier.
    @param disease (string) - Disease ID
    @param tierGroup (string) - Tier group name
    @return string - Translation key, or nil
]]--
function EHR.DialogueData.GetTreatmentHintKey(disease, tierGroup)
    if not EHR.DialogueData.TreatmentHints[disease] then
        return nil
    end

    -- Clueless tier doesn't get treatment hints
    if tierGroup == "clueless" then
        return nil
    end

    return EHR.DialogueData.TreatmentHints[disease][tierGroup]
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log("DialogueData module loaded (skill-tiered dialogue database)")
