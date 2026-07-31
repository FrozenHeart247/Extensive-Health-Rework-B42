pcall(function() require "ExtensiveHealth/EHR_Localization" end)
--[[
    Extensive Health Rework - Tooltip Data

    Contains tooltip text and metadata for all EHR items.
    This file defines the tooltip content that will be registered at runtime.

    Author: ExtensiveHealthRework Team
    Version: 1.0
]]

EHR = EHR or {}
EHR.Tooltips = EHR.Tooltips or {}

-- ============================================
-- TOOLTIP DATA STRUCTURE
-- Each item can have:
--   - description: Main tooltip text (multi-line with <LINE>)
--   - tier: Medication tier (0-3)
--   - category: Item category for display
--   - effects: List of effects (for medications)
--   - sideEffects: List of side effects
--   - requirements: Items needed to use (syringe, IV kit, etc.)
--   - treatmentTime: How long it takes to cure
--   - cures: List of diseases it cures
--   - relieves: List of symptoms it relieves (not cure)
--   - perishable: If true, shows time until spoilage in tooltip
-- ============================================

EHR.Tooltips.Data = {
    -- =========================================
    -- BLOOD BAGS
    -- =========================================
    ["ExtensiveHealth.BloodBagONeg"] = {
        category = "Blood Product",
        description = "Blood bag containing O- blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: O-, O+, A-, A+, B-, B+, AB-, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagOPos"] = {
        category = "Blood Product",
        description = "Blood bag containing O+ blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: O+, A+, B+, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagANeg"] = {
        category = "Blood Product",
        description = "Blood bag containing A- blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: A-, A+, AB-, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagAPos"] = {
        category = "Blood Product",
        description = "Blood bag containing A+ blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: A+, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagBNeg"] = {
        category = "Blood Product",
        description = "Blood bag containing B- blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: B-, B+, AB-, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagBPos"] = {
        category = "Blood Product",
        description = "Blood bag containing B+ blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: B+, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagABNeg"] = {
        category = "Blood Product",
        description = "Blood bag containing AB- blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: AB-, AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.BloodBagABPos"] = {
        category = "Blood Product",
        description = "Blood bag containing AB+ blood.",
        effects = {
            "Restores 500mL blood volume",
        },
        bloodCompatibility = "Compatible with: AB+",
        warning = "PERISHABLE: Freeze for storage. Spoils after 2h outside frozen storage!",
        perishable = true,
    },
    ["ExtensiveHealth.EmptyBloodBag"] = {
        category = "Blood Product",
        description = "Sterile empty blood collection bag.",
        effects = {
            "Used to draw and store your own blood",
            "Creates a filled bag matching your blood type",
            "Filled bags are perishable",
        },
        requirements = {"80%+ blood volume"},
        warning = "Drawing blood consumes the empty bag and temporarily lowers blood volume.",
    },

    -- =========================================
    -- IV SUPPLIES
    -- =========================================
    ["ExtensiveHealth.SalineBag"] = {
        category = "IV Supply",
        description = "Sterile saline IV bag.",
        effects = {
            "No blood type matching required",
            "Restores 250mL blood volume",
            "WARNING: Excessive saline dilutes blood",
        },
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.IVKit"] = {
        category = "Medical Supply",
        description = "Complete IV administration kit with tubing, needles, and connectors.",
        effects = {
            "Required for blood/saline transfusions",
            "Required for IV medications",
            "Single use - consumed on use",
        },
    },
    ["ExtensiveHealth.Syringe"] = {
        category = "Medical Supply",
        description = "Sterile disposable syringe.",
        effects = {
            "Required for injectable medications",
            "Single use - consumed on use",
        },
    },
    ["ExtensiveHealth.SterilizedBandages"] = {
        category = "Medical Supply",
        description = "Sealed pack of clean bandages.",
        effects = {
            "Unpack to get a clean bandage",
            "Holds up to 5 bandages",
            "Can be refilled with clean bandages",
        },
        warning = "Does not disinfect wounds",
    },
    ["ExtensiveHealth.AlchoholicBandage"] = {
        category = "Medical Supply",
        description = "Alcohol-prepared clean bandage.",
        effects = {
            "Disinfects the wound",
            "Applies a clean bandage",
            "Single use - consumed on use",
        },
    },
    ["ExtensiveHealth.Epinephrine"] = {
        category = "Emergency",
        description = "Emergency epinephrine auto-injector.",
        effects = {
            "Treats severe allergic reactions",
            "Can revive from cardiac arrest",
            "Immediate effect",
        },
    },

    -- =========================================
    -- TIER 1 - OTC (OVER THE COUNTER)
    -- =========================================
    ["Base.Pills"] = {
        category = "Vanilla Medication",
        tier = 0,
        description = "Standard painkiller bottle.",
        relieves = {"Pain"},
        effects = {
            "Uses vanilla painkiller behavior",
            "Multi-dose bottle",
        },
    },
    ["ExtensiveHealth.HomemadePainkillers"] = {
        category = "Vanilla Medication",
        tier = 0,
        description = "Homemade painkiller preparation.",
        relieves = {"Pain"},
        effects = {
            "Reduces body-part pain",
            "Multi-dose bottle",
            "Crafted from black sage, chamomile and lemongrass",
        },
    },
    ["Base.PillsVitamins"] = {
        category = "Stimulant",
        tier = 0,
        description = "Strong caffeine pills.",
        relieves = {"Fatigue"},
        effects = {
            "Removes fatigue immediately",
            "Prevents fatigue gain for 12 hours",
            "Prevents sleep while active",
            "Multi-dose bottle",
        },
        sideEffects = {"Caffeine Crash"},
        warning = "When the effect ends, fatigue immediately crashes to maximum.",
    },
    ["Base.PillsSleepingTablets"] = {
        category = "Vanilla Medication",
        tier = 0,
        description = "Sleeping tablet bottle.",
        relieves = {"Insomnia"},
        effects = {
            "Uses vanilla sleeping pill behavior",
            "Tracked by EHR medication monitoring",
            "Multi-dose bottle",
        },
    },
    ["ExtensiveHealth.HomemadeSleepingPills"] = {
        category = "Vanilla Medication",
        tier = 0,
        description = "Homemade sleeping pill bottle.",
        relieves = {"Insomnia"},
        effects = {
            "Allows sleep while active",
            "Tracked by EHR medication monitoring",
            "Multi-dose bottle",
            "Crafted from chamomile, black sage and honey",
        },
    },
    ["Base.PillsAntiDep"] = {
        category = "Prescription",
        tier = 2,
        description = "Antidepressant tablets.",
        relieves = {"Stress", "Insomnia sleep lock"},
        cures = {"Insomnia"},
        treatmentTime = "168 hours (14-dose course)",
        effects = {
            "Allows sleep while the dose is active",
            "Long-course insomnia treatment",
            "Multi-dose bottle",
        },
    },
    ["Base.PillsBeta"] = {
        category = "Vanilla Medication",
        tier = 0,
        description = "Beta blocker tablets.",
        relieves = {"Panic", "Heart strain"},
        effects = {
            "Suppresses panic for about 2 hours",
            "Prevents normal sleep while active",
            "Worsens weakness and blackout risk when blood volume is low",
            "Multi-dose bottle",
        },
    },
    ["Base.Antibiotics"] = {
        category = "Vanilla Medication",
        tier = 0,
        description = "Basic antibiotics.",
        relieves = {"Minor infection support"},
        cures = {"Wound Infection", "Cellulitis", "Sepsis"},
        treatmentTime = "24 hours / 6-dose course",
        effects = {
            "Provides low-tier EHR infection treatment",
            "Does not replace full prescription or clinical courses",
            "Tracked by EHR medication monitoring",
            "Multi-dose bottle",
        },
    },
    ["ExtensiveHealth.ColdFluTablets"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Over-the-counter cold and flu treatment tablets.",
        relieves = {"Fever", "Fatigue", "Minor pain"},
        effects = {"40% symptom relief", "28 hour / 8-dose treatment course"},
        cures = {"Common Cold"},
        warning = "Requires full dose course",
    },
    ["ExtensiveHealth.CommonColdTea"] = {
        category = "Herbal Medicine",
        tier = 1,
        description = "Warm herbal tea for common cold recovery.",
        relieves = {"Mild thirst", "Fever", "Fatigue", "Minor pain"},
        effects = {
            "CURES common cold with an 8-dose course",
            "Small immediate hydration boost",
            "Returns an empty mug after drinking",
        },
        cures = {"Common Cold"},
        warning = "Requires full dose course",
    },
    ["ExtensiveHealth.AntipyreticTablets"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Fever-reducing tablets.",
        relieves = {"Disease fever"},
        effects = {
            "60% fever relief",
            "Can normalize illness fever to 37.0 C",
            "Works against illness-related fever",
        },
        cures = {},
        warning = "Does NOT cool environmental overheating",
    },
    ["ExtensiveHealth.AntipyreticTea"] = {
        category = "Herbal Medicine",
        tier = 1,
        description = "Herbal fever-reducing tea.",
        relieves = {"Disease fever", "Mild thirst"},
        effects = {
            "60% fever relief",
            "Can normalize illness fever to 37.0 C",
            "Returns an empty mug after drinking",
        },
        cures = {},
        warning = "Does NOT cool environmental overheating",
    },
    ["ExtensiveHealth.CoughSyrup"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Liquid cough medicine.",
        relieves = {"Coughing"},
        effects = {
            "50% cough reduction",
            "Good for stealth - less noise!",
        },
        warning = "Does NOT cure",
    },
    ["ExtensiveHealth.HomemadeCoughSyrup"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Homemade liquid cough medicine.",
        relieves = {"Coughing"},
        effects = {
            "50% cough reduction",
            "Good for stealth - less noise!",
            "Crafted from honey, mallow, chamomile and berries",
        },
        warning = "Does NOT cure",
    },
    ["ExtensiveHealth.ElectrolytePowder"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Electrolyte replacement powder - mix with water.",
        relieves = {"Dehydration symptoms"},
        effects = {
            "Immediate hydration boost",
            "Gradual hydration support for 30 minutes",
            "40% dehydration symptom relief",
        },
        warning = "Does NOT cure dehydration-based diseases",
    },
    ["ExtensiveHealth.BronchodilatorInhaler"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Inhaler for respiratory distress.",
        relieves = {"Breathing difficulty"},
        effects = {
            "Opens airways",
            "45% breathing improvement",
            "Helps with pneumonia/fungal infections",
        },
        warning = "Does NOT cure",
    },
    ["ExtensiveHealth.AntiNauseaTablets"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Anti-nausea medication.",
        relieves = {"Nausea", "Vomiting"},
        effects = {"50% symptom relief"},
        warning = "Does NOT cure food poisoning",
    },
    ["ExtensiveHealth.AntiInflammatory"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Non-steroidal anti-inflammatory pills (NSAIDs).",
        relieves = {"Swelling", "Pain", "Inflammation", "Mild fever"},
        effects = {"50% inflammation reduction", "55% pain relief", "30% fever relief"},
        warning = "Does NOT cure infections",
    },
    ["ExtensiveHealth.AntiDiarrheal"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Anti-diarrheal tablets.",
        relieves = {"Dysentery diarrhea", "Bathroom urgency", "Hunger/thirst caps"},
        effects = {"85% diarrhea relief", "Temporarily suppresses dysentery caps", "Strongly lowers bathroom need"},
        warning = "Does NOT cure dysentery",
    },
    ["ExtensiveHealth.MuscleRelaxants"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Over-the-counter muscle relaxants.",
        relieves = {"Muscle spasms", "Muscle pain"},
        effects = {"40% spasm reduction"},
        warning = "Does NOT cure tetanus/parasites",
    },
    ["ExtensiveHealth.HomemadeMuscleRelaxant"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Homemade muscle relaxant preparation.",
        relieves = {"Muscle spasms", "Muscle pain"},
        effects = {
            "40% spasm reduction",
            "Crafted from black sage, chamomile, comfrey and honey",
        },
        warning = "Does NOT cure tetanus/parasites",
    },
    ["ExtensiveHealth.RelaxantTea"] = {
        category = "Herbal Medicine",
        tier = 1,
        description = "Calming herbal tea for stress relief.",
        relieves = {"Stress", "Panic", "Unhappiness", "Mild thirst"},
        effects = {
            "Gradually reduces stress toward zero over 3 hours",
            "Small immediate calming effect",
            "Returns an empty mug after drinking",
        },
        warning = "Does NOT cure mental illness",
    },
    ["ExtensiveHealth.NitricOxideBooster"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Performance booster tablets.",
        relieves = {"Endurance loss"},
        effects = {
            "Locks endurance at 100% for 3 hours",
            "Multi-dose bottle",
        },
        sideEffects = {"Whole-Body Muscle Pain"},
        warning = "Muscle pain begins after the booster wears off and lasts 6 hours.",
    },
    ["ExtensiveHealth.CombatStimulants"] = {
        category = "Military Stimulant",
        tier = 3,
        description = "Restricted battlefield stimulant bottle.",
        relieves = {"Stress", "Panic", "Unhappiness", "Endurance loss"},
        effects = {
            "Doubles equipped weapon attack speed for 3 hours",
            "Blocks stress, panic and unhappiness while active",
            "Strong endurance support without locking stamina to 100%",
            "8-dose bottle",
            "Slightly increases running speed",
        },
        sideEffects = {"Combat Stimulant Crash"},
        warning = "Crash after use: 80% fatigue, dehydration and limb muscle pain for 6 hours.",
    },
    ["ExtensiveHealth.CoughSuppressant"] = {
        category = "OTC Medication",
        tier = 1,
        description = "Cough suppressant tablets.",
        relieves = {"Coughing"},
        effects = {
            "45% cough reduction",
            "Avoid attracting zombies!",
        },
        warning = "Does NOT cure",
    },
    ["ExtensiveHealth.AntisepticCream"] = {
        category = "Prescription",
        tier = 2,
        description = "Topical antiseptic cream.",
        effects = {
            "Apply to wounds to prevent infection",
            "100% wound infection prevention while active",
        },
        warning = "Does NOT cure established infections",
    },
    ["ExtensiveHealth.HomemadeAntisepticCream"] = {
        category = "Prescription",
        tier = 2,
        description = "Homemade topical antiseptic cream.",
        effects = {
            "Apply to wounds to prevent infection",
            "100% wound infection prevention while active",
            "Crafted from tallow, honey and fresh medicinal plants",
        },
        warning = "Does NOT cure established infections",
    },

    -- =========================================
    -- TIER 2 - PRESCRIPTION MEDICATION
    -- =========================================
    ["ExtensiveHealth.AntiviralCapsules"] = {
        category = "Prescription",
        tier = 2,
        description = "Prescription antiviral medication.",
        cures = {"Common Cold", "Gastroenteritis"},
        treatmentTime = "48 hours",
        effects = {"CURES viral infections"},
    },
    ["ExtensiveHealth.PrescriptionAntibiotics"] = {
        category = "Prescription",
        tier = 2,
        description = "Strong prescription antibiotics.",
        cures = {"Wound Infection", "Cellulitis", "Pneumonia"},
        treatmentTime = "72 hours",
        effects = {"CURES bacterial infections"},
    },
    ["ExtensiveHealth.AntifungalTablets"] = {
        category = "Prescription",
        tier = 2,
        description = "Oral antifungal medication.",
        cures = {"Cadaveric Aspergillosis"},
        treatmentTime = "5 days",
        effects = {
            "CURES fungal respiratory illness",
            "Reduces cough, fever, dehydration and breathing trouble",
        },
    },
    ["ExtensiveHealth.ActivatedCharcoal"] = {
        category = "Prescription",
        tier = 2,
        description = "Medical-grade activated charcoal.",
        cures = {"Food Poisoning", "Toxin Poisoning"},
        treatmentTime = "Food poisoning: 6 hours; toxin poisoning: 12 hours",
        effects = {"Absorbs toxins", "CURES ingested poison/toxin illness"},
    },
    ["ExtensiveHealth.HomeMadeActivatedCharcoal"] = {
        category = "Prescription",
        tier = 2,
        description = "Homemade activated charcoal preparation.",
        cures = {"Food Poisoning", "Toxin Poisoning"},
        treatmentTime = "Food poisoning: 6 hours; toxin poisoning: 12 hours",
        effects = {"Absorbs toxins", "CURES ingested poison/toxin illness", "Crafted with charcoal and lemon"},
    },
    ["ExtensiveHealth.AntiparasiticPills"] = {
        category = "Prescription",
        tier = 2,
        description = "Antiparasitic medication.",
        cures = {"Trichinosis", "Hyperkeratotic Scabies"},
        treatmentTime = "7 days",
        effects = {"CURES parasitic infections"},
    },
    ["ExtensiveHealth.TopicalPermethrin"] = {
        category = "Prescription",
        tier = 2,
        description = "Topical permethrin cream.",
        cures = {"Hyperkeratotic Scabies"},
        treatmentTime = "72 hours (6-dose course)",
        effects = {"Topical application", "CURES scabies infestation", "Reduces itching, fever and skin-trauma health loss"},
    },
    ["ExtensiveHealth.HomemadeTopicalPermethrin"] = {
        category = "Prescription",
        tier = 2,
        description = "Homemade topical permethrin preparation.",
        cures = {"Hyperkeratotic Scabies"},
        treatmentTime = "72 hours (6-dose course)",
        effects = {
            "Topical application",
            "CURES scabies infestation",
            "Reduces itching, fever and skin-trauma health loss",
            "Crafted from marigold, honey, garlic and disinfectant",
        },
    },
    ["ExtensiveHealth.OralRehydrationKit"] = {
        category = "Prescription",
        tier = 2,
        description = "Medical rehydration solution kit.",
        cures = {"Dysentery", "Heat Exhaustion"},
        treatmentTime = "48 hours (8-dose course)",
        effects = {"CURES dehydration-based conditions", "Restores hydration during treatment"},
    },
    ["ExtensiveHealth.InstantIcePack"] = {
        category = "Prescription",
        tier = 2,
        description = "Emergency instant cooling pack box.",
        cures = {"Heat Stroke"},
        treatmentTime = "4 hours (4-dose cooling course)",
        effects = {
            "CURES heat stroke with repeated cooling",
            "Reduces fever, confusion, collapse risk, dehydration and health loss",
        },
    },
    ["ExtensiveHealth.TetanusAntitoxin"] = {
        category = "Prescription",
        tier = 2,
        description = "Tetanus antitoxin injection.",
        cures = {"Tetanus"},
        treatmentTime = "5 days",
        effects = {"Neutralizes tetanus toxin"},
        requirements = {"Syringe"},
    },
    ["ExtensiveHealth.TBAntibiotics"] = {
        category = "Prescription",
        tier = 2,
        description = "Isoniazid - first-line TB treatment.",
        cures = {"Tuberculosis"},
        treatmentTime = "21 days",
        effects = {"CURES tuberculosis (prolonged treatment)"},
        warning = "TB is chronic - requires long treatment",
    },
    ["ExtensiveHealth.AntibioticOintment"] = {
        category = "Prescription",
        tier = 2,
        description = "Prescription antibiotic ointment.",
        cures = {"Wound Infection", "Cellulitis"},
        treatmentTime = "72 hours",
        effects = {"Topical application", "CURES skin infections"},
    },
    ["ExtensiveHealth.HomemadeAntibioticOintment"] = {
        category = "Prescription",
        tier = 2,
        description = "Homemade antibiotic ointment.",
        cures = {"Wound Infection", "Cellulitis"},
        treatmentTime = "72 hours",
        effects = {
            "Topical application",
            "CURES skin infections",
            "Crafted from tallow, honey and fresh medicinal plants",
        },
    },
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = {
        category = "Prescription",
        tier = 2,
        description = "Broad spectrum antibiotic pills.",
        cures = {"Multiple bacterial infections", "Pneumonia", "Sepsis"},
        treatmentTime = "72 hours",
        effects = {"CURES multiple bacterial infections"},
    },
    ["ExtensiveHealth.PlantBasedAntibiotics"] = {
        category = "Prescription",
        tier = 2,
        description = "Plant-based broad spectrum antibiotic preparation.",
        cures = {"Multiple bacterial infections", "Pneumonia", "Sepsis"},
        treatmentTime = "72 hours",
        effects = {"CURES multiple bacterial infections", "Crafted from fresh medicinal herbs"},
    },
    ["ExtensiveHealth.Furosemide"] = {
        category = "Prescription",
        tier = 2,
        description = "Loop diuretic for severe transfusion reactions.",
        cures = {"AHTR"},
        treatmentTime = "48 hours (6-dose course)",
        effects = {"CURES acute hemolytic transfusion reaction", "Reduces hemolysis-related health loss and fever"},
        sideEffects = {"Dehydration", "Lower Back Pain", "Diuretic Effect"},
    },
    ["ExtensiveHealth.Antipsychotics"] = {
        category = "Prescription",
        tier = 2,
        description = "Prescription antipsychotic medication.",
        cures = {"Delirium"},
        treatmentTime = "96 hours (8-dose course)",
        effects = {"CURES stress-induced delirium"},
    },
    ["ExtensiveHealth.DualOrexinReceptor"] = {
        category = "Prescription",
        tier = 2,
        description = "Dual orexin receptor sleep medication.",
        relieves = {"Insomnia sleep lock", "Stress"},
        cures = {"Insomnia"},
        treatmentTime = "96 hours (8-dose course)",
        effects = {
            "Allows sleep while the dose is active",
            "CURES insomnia over a full course",
        },
    },

    -- =========================================
    -- TIER 3 - CLINICAL GRADE MEDICATION
    -- =========================================
    ["ExtensiveHealth.CorticosteroidInjection"] = {
        category = "Clinical",
        tier = 3,
        description = "Hospital-grade corticosteroid injection.",
        cures = {"Corpse Sickness"},
        treatmentTime = "12 hours (FAST)",
        effects = {"FAST CURE for severe corpse airway inflammation"},
        sideEffects = {"Immunosuppression", "Insomnia"},
        requirements = {"Syringe"},
    },
    ["ExtensiveHealth.RespiratorySupportKit"] = {
        category = "Clinical",
        tier = 3,
        description = "Portable oxygen and airway support kit.",
        cures = {"Corpse Sickness"},
        treatmentTime = "6 hours (3 doses)",
        effects = {
            "FAST CURE for corpse exposure illness",
            "Strong breathing, dizziness, nausea and weakness relief",
            "3 uses per kit, one dose every 3 hours",
        },
    },
    ["ExtensiveHealth.IVFluids"] = {
        category = "Clinical",
        tier = 3,
        description = "Intravenous fluid support.",
        cures = {"AHTR"},
        treatmentTime = "24 hours (IV support)",
        effects = {"FAST CURE for acute transfusion reaction", "Strong hydration and health-loss relief"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.IVAntibiotics"] = {
        category = "Clinical",
        tier = 3,
        description = "Intravenous antibiotic solution.",
        cures = {"Severe bacterial infections"},
        treatmentTime = "36 hours (FAST)",
        effects = {"FAST CURE for severe infections"},
        sideEffects = {"Nausea", "Fatigue"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.IVMetronidazole"] = {
        category = "Clinical",
        tier = 3,
        description = "IV Metronidazole for anaerobic bacteria.",
        cures = {"Dysentery", "Sepsis"},
        treatmentTime = "24 hours (FAST)",
        effects = {"FAST CURE for anaerobic infections"},
        sideEffects = {"Metallic Taste", "Nausea"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.IVAmphotericin"] = {
        category = "Clinical",
        tier = 3,
        description = "IV Amphotericin B - powerful antifungal.",
        cures = {"Severe Cadaveric Aspergillosis"},
        treatmentTime = "24 hours (FAST)",
        effects = {
            "FAST CURE for severe fungal respiratory illness",
            "Strong cough, fever, dehydration and breathing relief",
        },
        sideEffects = {"Fever", "Kidney Stress", "Fatigue"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.ChelationKit"] = {
        category = "Clinical",
        tier = 3,
        description = "Chelation therapy kit for heavy metal poisoning.",
        cures = {"Heavy Metal Poisoning"},
        treatmentTime = "48 hours (FAST)",
        effects = {"Removes heavy metals from the bloodstream"},
        sideEffects = {"Headache", "Fatigue", "Nausea"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.AlbendazoleInjection"] = {
        category = "Clinical",
        tier = 3,
        description = "Injectable Albendazole antiparasitic.",
        cures = {"Severe Trichinosis"},
        treatmentTime = "72 hours (FAST)",
        effects = {"FAST CURE for severe parasitic infections"},
        sideEffects = {"Abdominal Pain", "Dizziness"},
        requirements = {"Syringe"},
    },
    ["ExtensiveHealth.IVCiprofloxacin"] = {
        category = "Clinical",
        tier = 3,
        description = "IV Ciprofloxacin fluoroquinolone antibiotic.",
        cures = {"Gastroenteritis", "Dysentery", "Pneumonia", "Bacterial infections"},
        treatmentTime = "12 hours (FAST)",
        effects = {"FAST CURE for GI and respiratory bacterial infections"},
        sideEffects = {"Tendon Weakness", "Dizziness"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.TetanusImmunoglobulin"] = {
        category = "Clinical",
        tier = 3,
        description = "Tetanus immunoglobulin - immediate protection.",
        cures = {"Tetanus"},
        treatmentTime = "48 hours (FAST)",
        effects = {"FAST CURE for tetanus"},
        sideEffects = {"Injection Pain", "Fever"},
        requirements = {"Syringe"},
    },
    ["ExtensiveHealth.RifampicinComboPack"] = {
        category = "Clinical",
        tier = 3,
        description = "Rifampicin combination therapy for TB.",
        cures = {"Tuberculosis"},
        treatmentTime = "14 days (vs 21 for standard)",
        effects = {"FAST CURE for TB (7 days faster!)"},
        sideEffects = {"Orange Urine", "Liver Stress", "Fatigue"},
    },
    ["ExtensiveHealth.IVVancomycin"] = {
        category = "Clinical",
        tier = 3,
        description = "IV Vancomycin - last resort antibiotic.",
        cures = {"Resistant infections", "Severe Sepsis"},
        treatmentTime = "48 hours (FAST)",
        effects = {"FAST CURE for resistant infections"},
        sideEffects = {"Red Man Syndrome", "Kidney Stress"},
        requirements = {"IV Kit"},
    },
    ["ExtensiveHealth.EmergencySepsisKit"] = {
        category = "Clinical",
        tier = 3,
        description = "Emergency sepsis treatment kit.",
        cures = {"Sepsis"},
        treatmentTime = "24 hours (FASTEST)",
        effects = {"FASTEST CURE for sepsis"},
        sideEffects = {"Severe Fatigue", "Nausea", "Fever"},
        requirements = {"IV Kit"},
    },

    -- =========================================
    -- KNOX VIRUS TREATMENTS
    -- Experimental ultra-rare military items
    -- =========================================
    ["ExtensiveHealth.GeneTherapyKit"] = {
        category = "Experimental",
        tier = 4,
        description = "Experimental gene therapy for Knox Virus.",
        effects = {
            "EXTREMELY RARE - Military research item",
            "Success depends on blood type compatibility",
            "Use an Antibody Test first to check your odds",
        },
        cures = {"Knox Virus Infection"},
        requirements = {"Syringe"},
        warning = "Compatibility odds are hidden without an Antibody Test",
        successText = "SUCCESS: Permanent immunity",
        failureText = "FAILURE: Instant death",
    },
    ["ExtensiveHealth.PhalanxPills"] = {
        category = "Experimental",
        tier = 4,
        description = "Knox Virus suppressant medication.",
        effects = {
            "DOES NOT CURE - Resets infection progress",
            "Diminishing returns with each use:",
            "1st: Full reset | 2nd: Reset to 25%",
            "3rd: Reset to 50% | 4th: Reset to 75%",
            "5th+: No effect (body adapted)",
        },
        sideEffects = {"Extreme nausea (6h)", "Fever (12h)", "Weakened immunity (48h)"},
        warning = "Does NOT cure Knox Virus - only delays progression",
    },
    ["ExtensiveHealth.AntibodyTestKit"] = {
        category = "Experimental",
        tier = 4,
        description = "Blood compatibility test for Gene Therapy.",
        effects = {
            "Tests your survival odds before using Gene Therapy",
            "Results based on blood type:",
            "- High Compatibility (75%+)",
            "- Moderate Compatibility (50-74%)",
            "- Low Compatibility (25-49%)",
            "- Critical Risk (<25%)",
            "Single use - consumed on use",
        },
    },
    ["ExtensiveHealth.ImmunoboosterShot"] = {
        category = "Experimental",
        tier = 4,
        description = "Pre-exposure Knox Virus prophylaxis.",
        effects = {
            "Grants 24 hours of Knox immunity",
            "Must be taken BEFORE getting bitten!",
            "Does NOT help if already infected",
            "7-day cooldown between uses",
        },
        sideEffects = {"Mild nausea", "Reduced stamina regen", "Occasional tremors"},
        requirements = {"Syringe"},
        warning = "Preventative only - useless after infection!",
    },
}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Get tooltip data for an item
function EHR.Tooltips.GetData(itemFullType)
    return EHR.Tooltips.Data[itemFullType]
end

-- Get tier color
function EHR.Tooltips.GetTierColor(tier)
    if tier == 0 then
        return {r=0.7, g=0.7, b=0.7} -- Gray - Basic
    elseif tier == 1 then
        return {r=0.3, g=0.8, b=0.3} -- Green - OTC
    elseif tier == 2 then
        return {r=0.3, g=0.6, b=1.0} -- Blue - Prescription
    elseif tier == 3 then
        return {r=0.8, g=0.3, b=0.8} -- Purple - Clinical
    elseif tier == 4 then
        return {r=1.0, g=0.3, b=0.3} -- Red - Experimental (Knox items)
    else
        return {r=1, g=1, b=1} -- White - Unknown
    end
end

-- Get tier name
function EHR.Tooltips.GetTierName(tier)
    if tier == 0 then return EHR.Locale.Text("Tooltip_EHR_Tier_Basic", "Basic")
    elseif tier == 1 then return EHR.Locale.Text("Tooltip_EHR_Tier_OTC", "OTC (Tier 1)")
    elseif tier == 2 then return EHR.Locale.Text("Tooltip_EHR_Tier_Prescription", "Prescription (Tier 2)")
    elseif tier == 3 then return EHR.Locale.Text("Tooltip_EHR_Tier_Clinical", "Clinical (Tier 3)")
    elseif tier == 4 then return EHR.Locale.Text("Tooltip_EHR_Tier_Experimental", "Experimental (Tier 4)")
    else return EHR.Locale.Text("Tooltip_EHR_Tier_Unknown", "Unknown")
    end
end

-- Get category color
function EHR.Tooltips.GetCategoryColor(category)
    local colors = {
        ["Blood Product"] = {r=0.8, g=0.2, b=0.2},
        ["IV Supply"] = {r=0.2, g=0.7, b=0.9},
        ["Medical Supply"] = {r=0.6, g=0.6, b=0.6},
        ["Emergency"] = {r=1.0, g=0.3, b=0.1},
        ["Stimulant"] = {r=1.0, g=0.65, b=0.2},
        ["Military Stimulant"] = {r=1.0, g=0.65, b=0.2},
        ["OTC Medication"] = {r=0.3, g=0.8, b=0.3},
        ["Prescription"] = {r=0.3, g=0.6, b=1.0},
        ["Clinical"] = {r=0.8, g=0.3, b=0.8},
        ["Experimental"] = {r=1.0, g=0.3, b=0.3},  -- Red/Orange for Knox items
    }
    return colors[category] or {r=1, g=1, b=1}
end

EHR.Log("EHR_TooltipData.lua loaded - Tooltip data defined")
