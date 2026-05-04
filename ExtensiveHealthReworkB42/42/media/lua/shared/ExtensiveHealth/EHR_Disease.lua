--[[
    Extensive Health Rework B42
    Disease Module - Phase 1

    Adds realistic disease system with:
    - Food Poisoning (Phase 1)
    - Multi-day progression with incubation
    - Player dialogue hints
    - Integration with Blood Panel UI

    v1.0.1 - Cleanup: removed API discovery debug code (~325 lines)

    B42 API Notes (preserved from discovery):
    - CharacterStat.FOOD_SICKNESS: Component stat for food sickness (0-1 scale)
    - CharacterStat.SICKNESS: Aggregate stat that drives moodles (thresholds: 25%/50%/75%/90%)
    - CharacterStat.POISON: Raw food triggers this (values up to 14+), causes rapid death - must suppress
    - Moodles are READ-ONLY from Lua (no setMoodleLevel), driven by underlying stats
    - Old B41 methods like getFoodSicknessLevel()/setFoodSicknessLevel() DO NOT EXIST in B42
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Dialogue"
require "ExtensiveHealth/EHR_LifestyleCompat"
require "ExtensiveHealth/EHR_DiseaseFlyers"

EHR = EHR or {}
EHR.Disease = {}

-- ============================================
-- MP FIX: Debug Menu Grace Period
-- ============================================
-- Tracks when debug menu sets data to prevent server sync overwrites
EHR.Disease.DebugGracePeriod = {}
EHR.Disease.GRACE_PERIOD_SECONDS = 30  -- Extended for MP sync reliability

function EHR.Disease.MarkDebugSet(player)
    if not player then return end
    local username = player:getUsername() or tostring(player:getPlayerNum())
    EHR.Disease.DebugGracePeriod[username] = os.time()
    print("[EHR Disease] Debug grace period started for " .. username)
end

function EHR.Disease.IsInDebugGracePeriod(player)
    if not player then return false end
    local username = player:getUsername() or tostring(player:getPlayerNum())
    local setTime = EHR.Disease.DebugGracePeriod[username]
    if not setTime then return false end

    local elapsed = os.time() - setTime
    if elapsed < EHR.Disease.GRACE_PERIOD_SECONDS then
        return true
    else
        EHR.Disease.DebugGracePeriod[username] = nil
        return false
    end
end

-- Helper to get sandbox settings with defaults
function EHR.Disease.GetSetting(name, default)
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local value = SandboxVars.ExtensiveHealthRework[name]
        if value ~= nil then
            return value
        end
    end
    return default
end

-- Check if disease system is enabled
function EHR.Disease.IsEnabled()
    return EHR.Disease.GetSetting("DiseaseEnabled", true)
end

-- Get disease speed multiplier
function EHR.Disease.GetSpeedMultiplier()
    return EHR.Disease.GetSetting("DiseaseSpeed", 1.0)
end

-- Helper: Convert snake_case to CamelCase (used for sandbox option lookups)
local function toCamelCase(str)
    return str:gsub("_(%l)", function(c) return c:upper() end):gsub("^%l", string.upper)
end

-- ============================================
-- DISEASE DEFINITIONS
-- Each disease has treatment tier mappings for medication system
-- Tier 0 = Vanilla items, Tier 1 = OTC, Tier 2 = Prescription, Tier 3 = Clinical
-- ============================================

EHR.Disease.Diseases = {
    -- =========================================
    -- FOOD-BORNE DISEASES
    -- =========================================

    ["food_poisoning"] = {
        name = "Food Poisoning",
        category = "food",
        incubationMin = 2,
        incubationMax = 12,
        durationMin = 24,
        durationMax = 72,
        baseSeverity = 0.5,
        canKill = false,
        stageCount = 4,
        -- Treatment tiers - which medications work at which effectiveness
        treatments = {
            tier0 = {"Base.PillsVitamins"},  -- 15% symptom relief
            tier1 = {"ExtensiveHealth.AntiNauseaTablets", "ExtensiveHealth.AntiDiarrheal", "ExtensiveHealth.ElectrolytePowder"},  -- 40% relief
            tier2 = {"ExtensiveHealth.ActivatedCharcoal"},  -- Cures in 24h
            tier3 = {},  -- No clinical treatment needed
        },
        stageEntryDialogue = {
            [1] = "Ugh... something I ate doesn't sit right...",
            [2] = "Oh no... I think I'm getting food poisoning...",
            [3] = "*groans* This is bad... I can barely stand...",
            [4] = "*exhales* I think the worst is over...",
        },
        dialogue = {
            [1] = {"Something feels off...", "My stomach feels weird...", "I don't feel so good..."},
            [2] = {"I think I'm going to be sick...", "My stomach is churning...", "I feel nauseous..."},
            [3] = {"*retches*", "I need to sit down...", "Everything hurts...", "I can barely stand..."},
            [4] = {"I think I'm getting better...", "The worst seems to be over..."},
        },
    },

    ["gastroenteritis"] = {
        name = "Gastroenteritis",
        category = "food",
        incubationMin = 6,
        incubationMax = 24,
        durationMin = 48,
        durationMax = 96,
        baseSeverity = 0.6,
        canKill = false,
        stageCount = 4,
        treatments = {
            tier0 = {"Base.PillsVitamins"},
            tier1 = {"ExtensiveHealth.AntiNauseaTablets", "ExtensiveHealth.AntiDiarrheal", "ExtensiveHealth.ElectrolytePowder"},
            tier2 = {"ExtensiveHealth.AntiviralCapsules"},  -- Cures in 48h
            tier3 = {"ExtensiveHealth.IVCiprofloxacin"},  -- Fast cure 24h
        },
        stageEntryDialogue = {
            [1] = "My stomach doesn't feel right...",
            [2] = "This stomach bug is getting worse...",
            [3] = "*groans* I can't keep anything down...",
            [4] = "I think my stomach is finally settling...",
        },
        dialogue = {
            [1] = {"Ugh, I shouldn't have eaten with dirty hands...", "Something feels wrong..."},
            [2] = {"I feel terrible...", "My gut is on fire..."},
            [3] = {"*vomits*", "I can't stand up straight...", "Make it stop..."},
            [4] = {"Getting better slowly...", "At least I can eat again..."},
        },
    },

    ["trichinosis"] = {
        name = "Trichinosis",
        category = "food",
        incubationMin = 24,
        incubationMax = 72,
        durationMin = 168,  -- 7 days
        durationMax = 336,  -- 14 days
        baseSeverity = 0.75,
        canKill = true,
        stageCount = 4,
        treatments = {
            tier0 = {},
            tier1 = {"ExtensiveHealth.AntiInflammatory", "ExtensiveHealth.MuscleRelaxants"},  -- Symptom relief only
            tier2 = {"ExtensiveHealth.AntiparasiticPills"},  -- Cures in 7 days
            tier3 = {"ExtensiveHealth.AlbendazoleInjection"},  -- Fast cure 72h
        },
        stageEntryDialogue = {
            [1] = "Something I ate is really disagreeing with me...",
            [2] = "My muscles are starting to ache badly...",
            [3] = "*gasps in pain* Every muscle is on fire!",
            [4] = "The pain is finally subsiding...",
        },
        dialogue = {
            [1] = {"Should have cooked that meat longer...", "Feeling weak..."},
            [2] = {"My muscles hurt so much...", "I can barely move..."},
            [3] = {"*screams in pain*", "It feels like parasites are in my muscles!", "I might die from this..."},
            [4] = {"Slowly getting better...", "Never eating raw meat again..."},
        },
    },

    -- =========================================
    -- ENVIRONMENTAL DISEASES
    -- =========================================

    ["common_cold"] = {
        name = "Common Cold",
        category = "environmental",
        incubationMin = 12,
        incubationMax = 48,
        durationMin = 72,  -- 3 days
        durationMax = 168,  -- 7 days
        baseSeverity = 0.3,
        canKill = false,
        stageCount = 4,
        canProgress = "pneumonia",  -- Can progress to pneumonia if untreated
        treatments = {
            tier0 = {"Base.Pills"},
            tier1 = {"ExtensiveHealth.ColdFluTablets", "ExtensiveHealth.CoughSyrup", "ExtensiveHealth.CoughSuppressant"},
            tier2 = {"ExtensiveHealth.AntiviralCapsules"},  -- Cures in 48h
            tier3 = {},
        },
        stageEntryDialogue = {
            [1] = "I feel a little off...",
            [2] = "Great, I'm getting a cold...",
            [3] = "*sneezes* This cold is really hitting me hard...",
            [4] = "I think I'm getting over this cold...",
        },
        dialogue = {
            [1] = {"A bit chilly...", "My nose is running..."},
            [2] = {"*coughs*", "I hate being sick...", "*sniffles*"},
            [3] = {"*violent coughing fit*", "I can barely breathe...", "My throat is killing me..."},
            [4] = {"Feeling better...", "Almost over it..."},
        },
    },

    ["pneumonia"] = {
        name = "Pneumonia",
        category = "environmental",
        incubationMin = 24,
        incubationMax = 72,
        durationMin = 168,  -- 7 days
        durationMax = 336,  -- 14 days
        baseSeverity = 0.8,
        canKill = true,
        stageCount = 4,
        treatments = {
            tier0 = {"Base.Pills", "Base.Antibiotics"},
            tier1 = {"ExtensiveHealth.CoughSyrup", "ExtensiveHealth.BronchodilatorInhaler", "ExtensiveHealth.CoughSuppressant"},
            tier2 = {"ExtensiveHealth.PrescriptionAntibiotics"},  -- Cures in 72h
            tier3 = {"ExtensiveHealth.CorticosteroidInjection"},  -- Fast cure 24h
        },
        stageEntryDialogue = {
            [1] = "This cold is getting worse...",
            [2] = "I think this is more than a cold... my chest hurts...",
            [3] = "*hacking cough* I can barely breathe... this might be pneumonia!",
            [4] = "My breathing is getting easier...",
        },
        dialogue = {
            [1] = {"My lungs feel heavy...", "This isn't just a cold..."},
            [2] = {"*wet cough*", "I need antibiotics...", "Chest pain..."},
            [3] = {"*coughing blood*", "I'm drowning in my own lungs...", "I need a hospital!"},
            [4] = {"Breathing easier now...", "Thank god for medicine..."},
        },
    },

    ["dysentery"] = {
        name = "Dysentery",
        category = "environmental",
        incubationMin = 12,
        incubationMax = 48,
        durationMin = 72,
        durationMax = 168,
        baseSeverity = 0.7,
        canKill = true,  -- Through dehydration
        stageCount = 4,
        treatments = {
            tier0 = {},
            tier1 = {"ExtensiveHealth.ElectrolytePowder", "ExtensiveHealth.AntiDiarrheal"},
            tier2 = {"ExtensiveHealth.OralRehydrationKit"},  -- Cures in 48h
            tier3 = {"ExtensiveHealth.IVMetronidazole", "ExtensiveHealth.IVCiprofloxacin"},  -- Fast cure 24h
        },
        stageEntryDialogue = {
            [1] = "That water tasted funny...",
            [2] = "Oh no... I shouldn't have drunk that water...",
            [3] = "*gripping stomach* The cramps are unbearable!",
            [4] = "I think the worst is passing...",
        },
        dialogue = {
            [1] = {"My stomach is rumbling...", "Something isn't right..."},
            [2] = {"*runs to bushes*", "I can't stop going...", "I'm losing so much fluid..."},
            [3] = {"*bloody stool*", "I'm dying of thirst...", "I can't take this anymore..."},
            [4] = {"Slowly recovering...", "Need to stay hydrated..."},
        },
    },

    ["hypothermia"] = {
        name = "Hypothermia",
        category = "environmental",
        incubationMin = 1,
        incubationMax = 4,
        durationMin = 12,
        durationMax = 48,
        baseSeverity = 0.8,
        canKill = true,  -- Cardiac arrest
        stageCount = 4,
        treatments = {
            tier0 = {"Base.PillsBeta"},
            tier1 = {},  -- Warmth is the treatment
            tier2 = {},
            tier3 = {},
        },
        stageEntryDialogue = {
            [1] = "I'm getting really cold...",
            [2] = "I can't stop shivering...",
            [3] = "*slurred speech* So... cold... can't think...",
            [4] = "Warmth... finally getting warm...",
        },
        dialogue = {
            [1] = {"Need to find warmth...", "My fingers are numb..."},
            [2] = {"*violent shivering*", "I can't feel my toes...", "So cold..."},
            [3] = {"*confused mumbling*", "Just want to sleep...", "Heart... racing..."},
            [4] = {"Getting warmer...", "That was close..."},
        },
    },

    ["heat_exhaustion"] = {
        name = "Heat Exhaustion",
        category = "environmental",
        incubationMin = 1,
        incubationMax = 6,
        durationMin = 8,
        durationMax = 24,
        baseSeverity = 0.6,
        canKill = true,  -- Heat stroke
        stageCount = 4,
        canProgress = "heat_stroke",
        treatments = {
            tier0 = {"Base.Pills", "Base.PillsBeta"},
            tier1 = {"ExtensiveHealth.ElectrolytePowder"},
            tier2 = {"ExtensiveHealth.OralRehydrationKit"},  -- Cures in 48h
            tier3 = {},
        },
        stageEntryDialogue = {
            [1] = "I'm sweating a lot...",
            [2] = "Getting lightheaded from the heat...",
            [3] = "*panting* I'm overheating... need water and shade!",
            [4] = "Cooling down now...",
        },
        dialogue = {
            [1] = {"So hot...", "I need water..."},
            [2] = {"*heavy sweating*", "Dizzy...", "Need to rest..."},
            [3] = {"*stops sweating*", "This is bad... heat stroke coming...", "I might pass out..."},
            [4] = {"Feeling cooler...", "That was dangerous..."},
        },
    },

    -- =========================================
    -- CORPSE/INFECTION DISEASES
    -- =========================================

    ["wound_infection"] = {
        name = "Wound Infection",
        category = "wound",
        incubationMin = 12,
        incubationMax = 48,
        durationMin = 72,
        durationMax = 168,
        baseSeverity = 0.5,
        canKill = false,
        canProgress = "sepsis",
        stageCount = 4,
        treatments = {
            tier0 = {"Base.Antibiotics"},
            tier1 = {"ExtensiveHealth.AntisepticCream", "ExtensiveHealth.AntiInflammatory"},
            tier2 = {"ExtensiveHealth.PrescriptionAntibiotics", "ExtensiveHealth.AntibioticOintment", "ExtensiveHealth.BroadSpectrumAntibiotics"},
            tier3 = {"ExtensiveHealth.IVAntibiotics"},  -- Fast cure 36h
        },
        stageEntryDialogue = {
            [1] = "This wound feels warm...",
            [2] = "The wound is getting red and swollen...",
            [3] = "*winces* The infection is spreading!",
            [4] = "The infection seems to be clearing...",
        },
        dialogue = {
            [1] = {"Should have cleaned this better...", "It's a bit tender..."},
            [2] = {"*checks wound* It's infected...", "Getting worse...", "Need antibiotics..."},
            [3] = {"*pus oozing*", "The infection is bad...", "I might get sepsis..."},
            [4] = {"Looking better...", "Antibiotics are working..."},
        },
    },

    ["sepsis"] = {
        name = "Sepsis",
        category = "wound",
        incubationMin = 6,
        incubationMax = 24,
        durationMin = 48,
        durationMax = 96,
        baseSeverity = 0.95,
        canKill = true,
        stageCount = 4,
        treatments = {
            tier0 = {"Base.Antibiotics"},  -- Minimal help
            tier1 = {},  -- OTC won't help
            tier2 = {"ExtensiveHealth.BroadSpectrumAntibiotics"},  -- Cures in 72h
            tier3 = {"ExtensiveHealth.IVAntibiotics", "ExtensiveHealth.IVVancomycin", "ExtensiveHealth.EmergencySepsisKit"},  -- Fast cure 24-48h
        },
        stageEntryDialogue = {
            [1] = "I feel feverish and weak...",
            [2] = "Something is very wrong... my whole body aches...",
            [3] = "*delirious* The infection is in my blood! I'm dying!",
            [4] = "The fever is breaking...",
        },
        dialogue = {
            [1] = {"Fever coming on...", "Feel terrible..."},
            [2] = {"*shaking*", "Blood poisoning...", "Need hospital-grade antibiotics..."},
            [3] = {"*organ failure starting*", "Can't think straight...", "This is it..."},
            [4] = {"Pulling through...", "That was close to death..."},
        },
    },

    ["cellulitis"] = {
        name = "Cellulitis",
        category = "wound",
        incubationMin = 12,
        incubationMax = 36,
        durationMin = 72,
        durationMax = 144,
        baseSeverity = 0.6,
        canKill = false,
        canProgress = "sepsis",
        stageCount = 4,
        treatments = {
            tier0 = {"Base.Antibiotics"},
            tier1 = {"ExtensiveHealth.AntiInflammatory"},
            tier2 = {"ExtensiveHealth.PrescriptionAntibiotics", "ExtensiveHealth.AntibioticOintment", "ExtensiveHealth.BroadSpectrumAntibiotics"},
            tier3 = {"ExtensiveHealth.IVAntibiotics", "ExtensiveHealth.IVVancomycin"},
        },
        stageEntryDialogue = {
            [1] = "The skin around the wound looks red...",
            [2] = "The redness is spreading...",
            [3] = "*hot to touch* The cellulitis is getting severe!",
            [4] = "The swelling is going down...",
        },
        dialogue = {
            [1] = {"Skin looks inflamed...", "A bit swollen..."},
            [2] = {"The redness is spreading fast...", "It's hot to touch...", "Need antibiotics..."},
            [3] = {"*swollen limb*", "Can barely move this limb...", "It could turn to sepsis..."},
            [4] = {"Swelling reducing...", "Treatment is working..."},
        },
    },

    ["corpse_sickness"] = {
        name = "Corpse Exposure Illness",
        category = "corpse",
        incubationMin = 6,
        incubationMax = 18,
        durationMin = 24,
        durationMax = 72,
        baseSeverity = 0.6,
        canKill = false,
        stageCount = 4,
        treatments = {
            tier0 = {},
            tier1 = {"ExtensiveHealth.AntiNauseaTablets"},
            tier2 = {"ExtensiveHealth.ActivatedCharcoal", "ExtensiveHealth.AntifungalTablets"},
            tier3 = {"ExtensiveHealth.ChelationKit"},
        },
        stageEntryDialogue = {
            [1] = "That smell is getting to me...",
            [2] = "I feel nauseous and weak...",
            [3] = "*coughs* I need fresh air... now...",
            [4] = "I think I'm finally recovering...",
        },
        dialogue = {
            [1] = {"Ugh... the stench...", "Something's rotting nearby..."},
            [2] = {"*gagging*", "My stomach is turning...", "I feel sick..."},
            [3] = {"*coughs*", "Head is pounding...", "I need to get away from these bodies..."},
            [4] = {"Breathing easier now...", "Never staying near corpses again..."},
        },
    },

    ["tuberculosis"] = {
        name = "Tuberculosis",
        category = "corpse",
        incubationMin = 504,  -- 21 days
        incubationMax = 1008, -- 42 days
        durationMin = 2016,   -- 84 days (3 months) if untreated
        durationMax = 4032,   -- 168 days (6 months)
        baseSeverity = 0.85,
        canKill = true,
        stageCount = 4,
        treatments = {
            tier0 = {},  -- Vanilla antibiotics don't work
            tier1 = {"ExtensiveHealth.CoughSuppressant"},  -- Symptom relief only
            tier2 = {"ExtensiveHealth.TBAntibiotics"},  -- Cures in 21 days
            tier3 = {"ExtensiveHealth.RifampicinComboPack"},  -- Fast cure 14 days
        },
        stageEntryDialogue = {
            [1] = "I've been around corpses too long...",
            [2] = "I have a persistent cough that won't go away...",
            [3] = "*coughing blood* I have tuberculosis! I need sustained treatment!",
            [4] = "After weeks of treatment, I'm finally improving...",
        },
        dialogue = {
            [1] = {"Feeling fatigued lately...", "Been exposed to too many corpses..."},
            [2] = {"*bloody cough*", "Losing weight...", "Night sweats..."},
            [3] = {"*hemoptysis*", "Classic TB symptoms...", "Need months of antibiotics..."},
            [4] = {"Treatment is working...", "Still need to complete the course..."},
        },
    },

    ["tetanus"] = {
        name = "Tetanus",
        category = "wound",
        incubationMin = 72,  -- 3 days
        incubationMax = 168, -- 7 days
        durationMin = 168,   -- 7 days
        durationMax = 336,   -- 14 days
        baseSeverity = 0.9,
        canKill = true,
        stageCount = 4,
        treatments = {
            tier0 = {},  -- No vanilla treatment
            tier1 = {"ExtensiveHealth.MuscleRelaxants", "ExtensiveHealth.AntiInflammatory"},  -- Symptom relief
            tier2 = {"ExtensiveHealth.TetanusAntitoxin"},  -- Cures in 5 days
            tier3 = {"ExtensiveHealth.TetanusImmunoglobulin"},  -- Fast cure 48h
        },
        stageEntryDialogue = {
            [1] = "That deep wound from the rusty metal is worrying me...",
            [2] = "My jaw feels stiff... lockjaw starting?",
            [3] = "*muscle spasms* The tetanus is severe! I can't open my mouth!",
            [4] = "The spasms are reducing...",
        },
        dialogue = {
            [1] = {"Should have cleaned that rusty cut...", "Feeling odd..."},
            [2] = {"*jaw stiffness*", "Hard to swallow...", "Is this lockjaw?"},
            [3] = {"*violent spasms*", "Can't eat... can't breathe...", "Dying from tetanus..."},
            [4] = {"Finally able to eat again...", "The antitoxin is working..."},
        },
    },
}

-- ============================================
-- TRANSMISSION CHANCES
-- ============================================

EHR.Disease.FoodRisks = {
    rotten = 0.70,          -- 70% chance from rotten food
    uncooked = 0.40,        -- 40% chance from raw meat
    burned = 0.05,          -- 5% chance from burned food
    stale = 0.10,           -- 10% chance from stale food
    -- These stack with immunity modifiers
}

-- ============================================
-- TICK MANAGEMENT
-- ============================================

local DISEASE_TICK_INTERVAL = 60  -- Update every 60 ticks (~2 seconds)

local DIALOGUE_TICK_INTERVAL = 1800  -- Check dialogue every 1800 ticks (~1 minute)

-- MP: per-player tick state (avoid shared counters across players)
local tickStateByPlayer = {}
local SYNC_TICK_INTERVAL = 300  -- ~10 seconds

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
        state = { vanilla = 0, disease = 0, dialogue = 0, sync = 0 }
        tickStateByPlayer[id] = state
    end
    return state
end

-- ============================================
-- INITIALIZATION
-- ============================================

--[[
    Initialize disease data for a player
]]--
function EHR.Disease.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if modData.EHR_Disease_Initialized then
        return
    end

    -- Preserve existing disease data on relog / load
    if type(modData.EHR_Disease) == "table" then
        modData.EHR_Disease.active = modData.EHR_Disease.active or {}
        modData.EHR_Disease.immunity = modData.EHR_Disease.immunity or {
            general = 1.0,
            food_poisoning = 0.0,
        }
        modData.EHR_Disease.history = modData.EHR_Disease.history or {
            lastBadFood = nil,
            recoveries = {},
        }
        modData.EHR_Disease_Initialized = true
        EHR.Log("Disease module reinitialized (preserved existing data)")
        return
    end

    -- MP FIX: Don't overwrite during debug grace period
    if EHR.Disease.IsInDebugGracePeriod(player) then
        print("[EHR Disease] In debug grace period, skipping initialization")
        -- If debug data exists with active diseases, mark as initialized
        if modData.EHR_Disease and modData.EHR_Disease.active then
            local hasActive = false
            for _ in pairs(modData.EHR_Disease.active) do
                hasActive = true
                break
            end
            if hasActive then
                modData.EHR_Disease_Initialized = true
            end
        end
        return
    end

    EHR.Log("Initializing disease data...")

    modData.EHR_Disease = {
        -- Active diseases (keyed by disease ID)
        active = {},

        -- Immunity system
        immunity = {
            general = 1.0,          -- Base immunity multiplier
            food_poisoning = 0.0,   -- Specific immunity (builds after recovery)
        },

        -- History for tracking exposure
        history = {
            lastBadFood = nil,      -- Game time of last risky food
            recoveries = {},        -- Diseases recovered from (for immunity)
        },
    }

    modData.EHR_Disease_Initialized = true
    EHR.Log("Disease module initialized for player")
end

-- ============================================
-- IMMUNITY CALCULATION
-- ============================================

--[[
    Calculate current immunity multiplier
    Higher = more resistant to disease
    Returns 0.1 to 2.0
]]--
function EHR.Disease.CalculateImmunity(player)
    local base = 1.0
    local stats = player:getStats()
    if not stats then return base end

    -- Try B42 CharacterStat API
    if CharacterStat then
        local hunger, thirst, fatigue, stress

        -- Get stats safely
        if CharacterStat.HUNGER then
            local success, result = pcall(function() return stats:get(CharacterStat.HUNGER) end)
            if success then hunger = result end
        end
        if CharacterStat.THIRST then
            local success, result = pcall(function() return stats:get(CharacterStat.THIRST) end)
            if success then thirst = result end
        end
        if CharacterStat.FATIGUE then
            local success, result = pcall(function() return stats:get(CharacterStat.FATIGUE) end)
            if success then fatigue = result end
        end
        if CharacterStat.STRESS then
            local success, result = pcall(function() return stats:get(CharacterStat.STRESS) end)
            if success then stress = result end
        end

        -- Well-fed bonus
        if hunger and hunger < 0.2 then
            base = base + 0.2
        elseif hunger and hunger > 0.7 then
            base = base - 0.2  -- Hungry = weaker immune system
        end

        -- Well-hydrated bonus
        if thirst and thirst < 0.2 then
            base = base + 0.2
        elseif thirst and thirst > 0.7 then
            base = base - 0.2
        end

        -- Rested bonus
        if fatigue and fatigue < 0.3 then
            base = base + 0.15
        elseif fatigue and fatigue > 0.7 then
            base = base - 0.25
        end

        -- Low stress bonus
        if stress and stress < 0.3 then
            base = base + 0.1
        elseif stress and stress > 0.7 then
            base = base - 0.15
        end
    end

    -- Blood level modifier (integration with Blood module)
    if EHR.Blood and EHR.Blood.GetPercent then
        local bloodPercent = EHR.Blood.GetPercent(player)
        if bloodPercent > 80 then
            base = base + 0.15
        elseif bloodPercent < 50 then
            base = base - 0.3
        end
    end

    -- Active disease penalty
    local data = EHR.Disease.GetDiseaseData(player)
    if data then
        local activeCount = EHR.Disease.GetActiveCount(player)
        base = base - (activeCount * 0.2)
    end

    -- Clamp to reasonable range
    return math.max(0.1, math.min(2.0, base))
end

-- ============================================
-- DISEASE CONTRACTION
-- ============================================

--[[
    Attempt to contract a disease
    Returns true if disease was contracted
]]--
function EHR.Disease.TryContract(player, diseaseId, baseChance)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data then
        EHR.Log("TryContract: No disease data for player!")
        return false
    end

    -- Check sandbox setting for this specific disease
    local sandboxKey = toCamelCase(diseaseId) .. "Enabled"
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options[sandboxKey] == false then
        EHR.Log("TryContract: " .. diseaseId .. " disabled by sandbox option " .. sandboxKey)
        return false
    end

    -- Already have this disease?
    if data.active[diseaseId] then
        EHR.Log("TryContract: Already have " .. diseaseId)
        return false
    end

    -- Get disease definition
    local def = EHR.Disease.Diseases[diseaseId]
    if not def then
        EHR.Log("Unknown disease: " .. diseaseId)
        return false
    end

    -- Calculate actual chance with immunity
    local immunity = EHR.Disease.CalculateImmunity(player)
    local specificImmunity = data.immunity[diseaseId] or 0

    -- Higher immunity = lower chance
    local actualChance = baseChance / immunity
    -- Specific immunity reduces chance further
    actualChance = actualChance * (1 - specificImmunity)

    -- Roll for contraction
    local roll = ZombRand(100) / 100

    if EHR.DEBUG then
        EHR.Log(string.format("Disease roll: %s - base=%.0f%%, immunity=%.2f, specific=%.2f, actual=%.0f%%, roll=%.2f",
            diseaseId, baseChance * 100, immunity, specificImmunity, actualChance * 100, roll))
    end

    if roll < actualChance then
        EHR.Disease.Contract(player, diseaseId)
        return true
    end

    return false
end

--[[
    Contract a disease (guaranteed)
]]--
function EHR.Disease.Contract(player, diseaseId)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data then return end

    local def = EHR.Disease.Diseases[diseaseId]
    if not def then return end

    -- Check sandbox setting for this specific disease
    local sandboxKey = toCamelCase(diseaseId) .. "Enabled"
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options[sandboxKey] == false then
        if EHR.DEBUG then
            EHR.Log("Contract: " .. diseaseId .. " disabled by sandbox option " .. sandboxKey)
        end
        return
    end

    -- Get speed multiplier from sandbox (higher = faster progression = shorter duration)
    local speedMult = EHR.Disease.GetSpeedMultiplier()

    -- Calculate random incubation and duration (adjusted by speed multiplier)
    local incubation = def.incubationMin + ZombRand(def.incubationMax - def.incubationMin + 1)
    local duration = def.durationMin + ZombRand(def.durationMax - def.durationMin + 1)

    -- Apply speed multiplier (faster = shorter times)
    if speedMult > 0 then
        incubation = math.max(1, incubation / speedMult)
        duration = math.max(1, duration / speedMult)
    end

    -- Get current game time
    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()

    -- Create disease instance
    data.active[diseaseId] = {
        startTime = currentHour,
        incubationEnd = currentHour + incubation,
        endTime = currentHour + incubation + duration,
        stage = 1,  -- Start in incubation
        severity = def.baseSeverity + (ZombRand(30) / 100 - 0.15),  -- +/- 15% variance
        diagnosed = false,
        peakTime = currentHour + incubation + (duration * 0.4),  -- Peak at 40% through
    }

    EHR.Log(string.format("Contracted %s! Incubation: %dh, Duration: %dh, Severity: %.2f",
        def.name, incubation, duration, data.active[diseaseId].severity))

    -- Say stage 1 entry dialogue (stage changes always say unless dialogue off)
    if def.stageEntryDialogue and def.stageEntryDialogue[1] then
        EHR.Dialogue.SayStageChange(player, def.stageEntryDialogue[1])
    end

    -- Record in history
    data.history.lastBadFood = currentHour
end

-- ============================================
-- DISEASE PROGRESSION
-- ============================================

--[[
    Apply Lifestyle & Hobbies healing bonuses to diseases.
    Reduces remaining disease duration based on comfort/bath bonuses.
    Called before regular progression update.

    @param player (IsoPlayer)
    @param data (table) - Player's modData
]]--
function EHR.Disease.ApplyHealingBonuses(player, data)
    if not data.EHR_Disease then return end
    if not EHR.LifestyleCompat then return end
    if not EHR.LifestyleCompat.IsModLoaded() then return end

    local currentHour = getGameTime():getWorldAgeHours()

    for diseaseId, disease in pairs(data.EHR_Disease.active) do
        -- Only apply to diseases in recovery stage (stage 4) or symptomatic stages
        if disease.stage and disease.stage >= 2 then
            -- Check if this disease supports Lifestyle bonuses
            if EHR.LifestyleCompat.DiseaseSupportsBonus(diseaseId) then
                local multiplier = EHR.LifestyleCompat.GetDiseaseHealingMultiplier(player, diseaseId)

                -- Only apply if there's a bonus (multiplier > 1)
                if multiplier > 1.0 then
                    -- Calculate time reduction
                    -- Bonus of 40% means 1.4x speed, so reduce remaining time
                    local bonusRate = multiplier - 1.0  -- e.g., 0.4 for 40% bonus

                    -- Reduce endTime by bonus amount (scaled by tick interval)
                    -- DISEASE_TICK_INTERVAL is ~2 seconds = 1/1800 of an hour
                    local tickHours = 2 / 3600  -- ~0.00055 hours per tick
                    local reduction = tickHours * bonusRate

                    if disease.endTime and disease.endTime > currentHour then
                        disease.endTime = disease.endTime - reduction

                        -- Also adjust peakTime to maintain proportions
                        if disease.peakTime and disease.peakTime > currentHour then
                            disease.peakTime = disease.peakTime - (reduction * 0.5)
                        end
                    end
                end
            end
        end
    end
end

--[[
    Update disease progression - called every DISEASE_TICK_INTERVAL
]]--
function EHR.Disease.UpdateProgression(player, data)
    if not data.EHR_Disease then return end

    local gameTime = getGameTime()
    local currentHour = gameTime:getWorldAgeHours()
    local toRemove = {}

    for diseaseId, disease in pairs(data.EHR_Disease.active) do
        local def = EHR.Disease.Diseases[diseaseId]
        if not def then
            table.insert(toRemove, diseaseId)
        else
            -- HIGH FIX: Validate disease has required fields (handles old/malformed data)
            -- Also validates stage and severity which were previously not checked
            if not disease.endTime or not disease.startTime or not disease.incubationEnd or not disease.peakTime then
                EHR.Log(string.format("WARNING: Disease %s missing required fields - repairing", diseaseId))
                -- Repair missing fields with sensible defaults
                local duration = def.durationMax or 72
                local incubation = def.incubationMax or 12
                disease.startTime = disease.startTime or (currentHour - 1)
                disease.incubationEnd = disease.incubationEnd or (disease.startTime + incubation)
                disease.peakTime = disease.peakTime or (disease.startTime + incubation + (duration * 0.4))
                disease.endTime = disease.endTime or (disease.startTime + incubation + duration)
            end
            -- HIGH FIX: Also validate stage and severity (prevent nil access errors)
            if disease.stage == nil then
                disease.stage = 2  -- Default to early stage
                EHR.Log(string.format("WARNING: Disease %s missing stage - defaulted to 2", diseaseId))
            end
            if disease.severity == nil then
                disease.severity = def.baseSeverity or 0.5  -- Default severity from definition
                EHR.Log(string.format("WARNING: Disease %s missing severity - defaulted to %.2f", diseaseId, disease.severity))
            end

            -- BUG FIX: Sanity check for stuck diseases
            -- If disease has been running for more than double its max duration, force end it
            local maxExpectedDuration = (def.incubationMax or 24) + (def.durationMax or 72)
            local actualDuration = currentHour - (disease.startTime or 0)

            if actualDuration > (maxExpectedDuration * 2) then
                -- Disease is stuck - force recovery
                EHR.Log(string.format("WARNING: Disease %s stuck (%.0fh / max %.0fh) - forcing recovery",
                    diseaseId, actualDuration, maxExpectedDuration))
                table.insert(toRemove, diseaseId)
                EHR.Disease.OnRecovery(player, diseaseId)
            else
                -- Update stage based on time
                local oldStage = disease.stage

                -- BUG FIX: Use >= comparison to handle floating point precision issues
                if currentHour >= disease.endTime then
                    -- Disease has run its course
                    table.insert(toRemove, diseaseId)
                    EHR.Disease.OnRecovery(player, diseaseId)
                elseif currentHour < disease.incubationEnd then
                    disease.stage = 1  -- Incubation
                elseif currentHour < disease.peakTime then
                    disease.stage = 2  -- Early symptoms
                elseif currentHour < disease.endTime - ((disease.endTime - disease.peakTime) * 0.5) then
                    disease.stage = 3  -- Peak symptoms
                else
                    -- BUG-016 FIX: Check for warmth-blocked diseases (hypothermia)
                    -- If warmthBlocked is set, player must get warm before recovery
                    if disease.warmthBlocked then
                        disease.stage = 3  -- Stay at peak until warm
                        if EHR.DEBUG then
                            EHR.Log(string.format("%s: Recovery blocked - warmthBlocked=true", diseaseId))
                        end
                    else
                        disease.stage = 4  -- Recovery
                    end
                end

                -- Handle stage changes
                if oldStage ~= disease.stage then
                    if EHR.DEBUG then
                        EHR.Log(string.format("%s progressed to stage %d", def.name, disease.stage))
                    end

                    -- Say dialogue when entering a new stage (stage changes always say unless dialogue off)
                    if def.stageEntryDialogue and def.stageEntryDialogue[disease.stage] then
                        EHR.Dialogue.SayStageChange(player, def.stageEntryDialogue[disease.stage])
                    end
                end

                -- Apply effects based on stage
                if disease.stage > 1 then  -- Not in incubation
                    EHR.Disease.ApplyEffects(player, diseaseId, disease, def)
                end
            end  -- End of stuck-check else block
        end
    end

    -- Remove completed diseases
    for _, diseaseId in ipairs(toRemove) do
        data.EHR_Disease.active[diseaseId] = nil
    end
end

--[[
    Handle disease recovery
]]--
function EHR.Disease.OnRecovery(player, diseaseId)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data then return end

    local def = EHR.Disease.Diseases[diseaseId]
    local name = def and def.name or diseaseId

    EHR.Log("Recovered from " .. name)

    -- Build specific immunity (lasts ~30 in-game days worth)
    -- Immunity decays over time but starts at 0.5 (50% resistance)
    data.immunity[diseaseId] = math.min(0.8, (data.immunity[diseaseId] or 0) + 0.5)

    -- Record recovery
    local gameTime = getGameTime()
    data.history.recoveries[diseaseId] = gameTime:getWorldAgeHours()

    -- Player announcement (stage change - recovery is significant)
    EHR.Dialogue.SayStageChange(player, "I think I'm finally over it...")

    -- Award First Aid XP for curing a disease
    if EHR.SkillXP and EHR.SkillXP.OnDiseaseCured then
        EHR.SkillXP.OnDiseaseCured(player, diseaseId)
    end

    -- Record cure in Medical Journal
    if EHR.MedicalJournal and EHR.MedicalJournal.RecordCure then
        EHR.MedicalJournal.RecordCure(player, diseaseId)
    end

    if diseaseId == "corpse_sickness" and EHR.CorpseSickness and EHR.CorpseSickness.ResetAfterCure then
        EHR.CorpseSickness.ResetAfterCure(player)
    elseif diseaseId == "food_poisoning" and EHR.Disease.ResetFoodSicknessAfterCure then
        EHR.Disease.ResetFoodSicknessAfterCure(player, diseaseId)
    end
end

-- ============================================
-- DISEASE EFFECTS
-- ============================================

--[[
    Apply disease effects based on stage and severity
]]--
function EHR.Disease.ApplyEffects(player, diseaseId, disease, def)
    local stats = player:getStats()
    if not stats then return end

    local severity = disease.severity
    local stage = disease.stage

    -- Food Poisoning specific effects
    if diseaseId == "food_poisoning" then
        -- Stage 2: Early symptoms
        if stage == 2 then
            -- Mild endurance drain
            if stats.setEndurance then
                local current = stats:getEndurance() or 1
                stats:setEndurance(math.max(0, current - (0.02 * severity)))
            end

        -- Stage 3: Peak symptoms
        elseif stage == 3 then
            -- Severe endurance drain
            if stats.setEndurance then
                local current = stats:getEndurance() or 1
                stats:setEndurance(math.max(0, current - (0.08 * severity)))
            end

            -- Increase hunger (vomiting loses food) - reduced by 50%
            if CharacterStat and CharacterStat.HUNGER then
                local hunger = stats:get(CharacterStat.HUNGER) or 0
                -- Slowly increase hunger
                pcall(function()
                    stats:set(CharacterStat.HUNGER, math.min(1, hunger + (0.0005 * severity)))
                end)
            end

            -- Increase thirst (dehydration from vomiting) - reduced by 50%
            if CharacterStat and CharacterStat.THIRST then
                local thirst = stats:get(CharacterStat.THIRST) or 0
                pcall(function()
                    stats:set(CharacterStat.THIRST, math.min(1, thirst + (0.001 * severity)))
                end)
            end

        -- Stage 4: Recovery
        elseif stage == 4 then
            -- Mild effects, fading
            if stats.setEndurance then
                local current = stats:getEndurance() or 1
                stats:setEndurance(math.max(0, current - (0.01 * severity)))
            end
        end
    end
end

-- ============================================
-- PLAYER DIALOGUE
-- ============================================

--[[
    Check if player should say something about their illness
]]--
function EHR.Disease.CheckDialogue(player, data)
    if not data.EHR_Disease then return end
    if not player.Say then return end

    for diseaseId, disease in pairs(data.EHR_Disease.active) do
        local def = EHR.Disease.Diseases[diseaseId]
        if def and def.dialogue then
            -- BUG-020 FIX: Skip hypothermia dialogue when player is warm
            -- Player was getting "so cold..." messages while in a 22C room
            local skipDialogue = false
            if diseaseId == "hypothermia" and EHR.Environmental and EHR.Environmental.IsWarmEnoughForRecovery then
                local isWarm = EHR.Environmental.IsWarmEnoughForRecovery(player)
                if isWarm then
                    -- Skip cold dialogue when warm - player is recovering, not suffering
                    skipDialogue = true
                    if EHR.DEBUG then
                        EHR.Log("Skipping hypothermia dialogue - player is warm")
                    end
                end
            end

            if not skipDialogue then
                local stageDialogue = def.dialogue[disease.stage]
                if stageDialogue and #stageDialogue > 0 then
                    -- Random chance to speak (lower in incubation)
                    -- Base chance: 5% incubation, 15% otherwise (converted to 1-in-X format)
                    local baseChance = disease.stage == 1 and 20 or 7  -- 1 in 20 = 5%, 1 in 7 approx 15%

                    if EHR.Dialogue.ShouldSayRandom(baseChance) then
                        local line = stageDialogue[ZombRand(#stageDialogue) + 1]
                        EHR.Dialogue.SayStageChange(player, line)  -- Use stage change since it's symptom dialogue
                        return  -- Only one line per check
                    end
                end
            end
        end
    end
end

-- ============================================
-- FOOD TRANSMISSION HOOK
-- ============================================

--[[
    Check food item for disease risk
    Called when player eats food

    B42 API Note: Many item methods changed, using pcall for safety
]]--
function EHR.Disease.CheckFoodRisk(player, item)
    if not player or not item then return end

    -- Ensure disease data is initialized before checking
    EHR.Disease.InitializePlayer(player)

    local risk = 0
    local riskReason = nil

    -- Helper to safely call item methods
    local function safeCall(method)
        if item[method] then
            local success, result = pcall(function() return item[method](item) end)
            if success then return result end
        end
        return nil
    end

    -- Check food status using safe calls
    local isRotten = safeCall("isRotten")
    local isBurnt = safeCall("isBurnt") or safeCall("isBurned")
    local isCooked = safeCall("isCooked")
    local isFresh = safeCall("isFresh")
    local age = safeCall("getAge")
    local offAge = safeCall("getOffAge") or safeCall("getOffAgeMax")

    -- B42 alternative: check if item has "Rotten" in name or category
    if isRotten == nil then
        local name = safeCall("getDisplayName") or safeCall("getName") or ""
        if string.find(string.lower(name), "rotten") then
            isRotten = true
        end
    end

    -- Determine risk
    if isRotten == true then
        risk = EHR.Disease.FoodRisks.rotten
        riskReason = "rotten"
    elseif isBurnt == true then
        risk = EHR.Disease.FoodRisks.burned
        riskReason = "burned"
    end

    -- Check for raw/uncooked meat (isCooked == false OR nil means not cooked)
    if risk == 0 and isCooked ~= true then
        -- Check if it's meat by food type or item name
        local foodType = safeCall("getFoodType") or safeCall("getEatType") or ""
        local itemName = safeCall("getDisplayName") or safeCall("getName") or ""
        local itemFullType = safeCall("getFullType") or ""

        local isMeat = false
        -- Check food type
        if type(foodType) == "string" and string.find(string.lower(foodType), "meat") then
            isMeat = true
        end
        -- Check item name for common raw meat indicators
        local nameLower = string.lower(itemName .. " " .. itemFullType)

        -- BUG-006 FIX: Check for preserved/processed meats first (safe without cooking)
        local isPreservedMeat = false
        local preservedMeatPatterns = {"ham", "bacon", "sausage", "salami", "pepperoni", "jerky", "cured", "smoked"}
        for _, pattern in ipairs(preservedMeatPatterns) do
            if string.find(nameLower, pattern) then
                isPreservedMeat = true
                break
            end
        end

        -- Only check raw meat patterns if NOT a preserved meat
        if not isPreservedMeat then
            if string.find(nameLower, "mouse") or
               string.find(nameLower, "rat") or
               string.find(nameLower, "bird") or
               string.find(nameLower, "rabbit") or
               string.find(nameLower, "squirrel") or
               string.find(nameLower, "fish") or
               string.find(nameLower, "frog") or
               string.find(nameLower, "meat") or
               string.find(nameLower, "steak") or
               string.find(nameLower, "chicken") or
               string.find(nameLower, "pork") or
               string.find(nameLower, "venison") then
                isMeat = true
            end
        end

        if isMeat then
            risk = EHR.Disease.FoodRisks.uncooked
            riskReason = "uncooked"
        end
    end

    -- Stale food check (age-based)
    if risk == 0 and age and offAge then
        if age > offAge * 0.8 then  -- More than 80% to spoilage
            risk = EHR.Disease.FoodRisks.stale
            riskReason = "stale"
        end
    end

    -- Debug: Log what we found
    if EHR.DEBUG then
        EHR.Log(string.format("CheckFoodRisk: rotten=%s, burnt=%s, cooked=%s, age=%.2f/%.2f",
            tostring(isRotten), tostring(isBurnt), tostring(isCooked),
            age or 0, offAge or 0))
    end

    if risk > 0 then
        local itemName = safeCall("getDisplayName") or safeCall("getName") or "unknown"
        EHR.Log(string.format("Risky food consumed: %s (%s) - %.0f%% base risk",
            itemName, riskReason, risk * 100))
        EHR.Disease.TryContract(player, "food_poisoning", risk)
    end
end

--[[
    OnEat event handler
]]--
function EHR.Disease.OnEatFood(player, item, amount)
    -- Ensure player has disease data
    EHR.Disease.InitializePlayer(player)

    -- Check the food for disease risk
    EHR.Disease.CheckFoodRisk(player, item)
end

-- ============================================
-- HELPER FUNCTIONS (for UI and Blood integration)
-- ============================================

--[[
    Get disease data for a player
]]--
function EHR.Disease.GetDiseaseData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData or not modData.EHR_Disease then return nil end
    return modData.EHR_Disease
end

--[[
    Get count of active diseases
]]--
function EHR.Disease.GetActiveCount(player)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return 0 end

    local count = 0
    for _ in pairs(data.active) do
        count = count + 1
    end
    return count
end

--[[
    Cure a specific disease (Debug/Cheat function)
]]--
function EHR.Disease.Cure(player, diseaseId)
    if not player or not diseaseId then return false end

    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return false end

    if data.active[diseaseId] then

        data.active[diseaseId] = nil

        if diseaseId == "corpse_sickness" and EHR.CorpseSickness and EHR.CorpseSickness.ResetAfterCure then

            EHR.CorpseSickness.ResetAfterCure(player)

        elseif diseaseId == "food_poisoning" and EHR.Disease.ResetFoodSicknessAfterCure then

            EHR.Disease.ResetFoodSicknessAfterCure(player)

        end

        EHR.Log("Cured disease: " .. tostring(diseaseId))

        -- MP: Trigger server sync after disease cure
        if isClient() then
            sendClientCommand(player, "EHR", "RequestSync", {})
        end

        return true
    end

    return false
end

--[[
    Cure all diseases (Debug/Cheat function)
]]--
function EHR.Disease.CureAll(player)
    if not player then return false end

    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return false end

    local count = 0

    local curedCorpseSickness = false
    local curedFoodSickness = false

    for diseaseId, _ in pairs(data.active) do

        if diseaseId == "corpse_sickness" then

            curedCorpseSickness = true

        elseif diseaseId == "food_poisoning" then

            curedFoodSickness = true

        end

        data.active[diseaseId] = nil

        count = count + 1

    end


    if curedCorpseSickness and EHR.CorpseSickness and EHR.CorpseSickness.ResetAfterCure then

        EHR.CorpseSickness.ResetAfterCure(player)

    end

    if curedFoodSickness and EHR.Disease.ResetFoodSicknessAfterCure then

        EHR.Disease.ResetFoodSicknessAfterCure(player)

    end


    if count > 0 then
        EHR.Log("Cured all diseases: " .. count .. " removed")

        -- MP: Trigger server sync after curing all diseases
        if isClient() then
            sendClientCommand(player, "EHR", "RequestSync", {})
        end
    end

    return count > 0
end

--[[
    Set disease stage (Debug function)
]]--
function EHR.Disease.SetStage(player, diseaseId, stage)
    if not player or not diseaseId or not stage then return false end

    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return false end

    if data.active[diseaseId] then
        data.active[diseaseId].stage = stage
        data.active[diseaseId].stageProgress = 0
        EHR.Log("Set " .. tostring(diseaseId) .. " to stage " .. tostring(stage))
        return true
    end

    return false
end

--[[
    Check if any disease blocks healing
    Returns: canHeal (bool), reason (string)
]]--
function EHR.Disease.BlocksHealing(player)
    -- Check sepsis module (blocks ALL healing)
    if EHR.Sepsis and EHR.Sepsis.HasSepsis and EHR.Sepsis.HasSepsis(player) then
        return false, "sepsis"
    end

    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return true, "ok" end

    for diseaseId, disease in pairs(data.active) do
        -- Severe food poisoning (stage 3) slows healing significantly
        if diseaseId == "food_poisoning" and disease.stage == 3 then
            -- Don't block, but could be used for reduced healing rate
        end
    end

    return true, "ok"
end

--[[
    Check if player has sepsis (for blood loss acceleration)
    Now delegates to EHR.Sepsis module
]]--
function EHR.Disease.HasSepsis(player)
    -- Use new Sepsis module if available
    if EHR.Sepsis and EHR.Sepsis.HasSepsis then
        return EHR.Sepsis.HasSepsis(player)
    end
    return false
end

--[[
    Get status text for UI display
]]--
function EHR.Disease.GetStatusText(player)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return "" end

    local texts = {}
    for diseaseId, disease in pairs(data.active) do
        local def = EHR.Disease.Diseases[diseaseId]
        if def then
            local stageName = ""
            if disease.stage == 1 then
                stageName = "Incubating"
            elseif disease.stage == 2 then
                stageName = "Early"
            elseif disease.stage == 3 then
                stageName = "Severe"
            elseif disease.stage == 4 then
                stageName = "Recovering"
            end

            -- Show name if diagnosed, otherwise vague
            if disease.diagnosed or disease.stage >= 3 then
                table.insert(texts, string.format("%s (%s)", def.name, stageName))
            else
                table.insert(texts, string.format("Unwell (%s)", stageName))
            end
        end
    end

    if #texts == 0 then return "" end
    return table.concat(texts, ", ")
end

--[[
    Get color for disease status (for UI)
]]--
function EHR.Disease.GetStatusColor(player)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then
        return {r = 0.5, g = 0.5, b = 0.5}  -- Gray (healthy)
    end

    local worstStage = 0
    for _, disease in pairs(data.active) do
        if disease.stage > worstStage then
            worstStage = disease.stage
        end
    end

    if worstStage == 0 then
        return {r = 0.5, g = 0.5, b = 0.5}  -- Gray
    elseif worstStage == 1 then
        return {r = 0.8, g = 0.8, b = 0.4}  -- Yellow (incubating)
    elseif worstStage == 2 then
        return {r = 0.9, g = 0.6, b = 0.2}  -- Orange (early)
    elseif worstStage == 3 then
        return {r = 0.9, g = 0.2, b = 0.2}  -- Red (severe)
    else
        return {r = 0.6, g = 0.8, b = 0.4}  -- Light green (recovering)
    end
end

-- ============================================
-- VANILLA SICKNESS SYNC
-- ============================================

-- Counter for vanilla sickness check
-- CRITICAL: Must run every tick - POISON can spike to 14+ in a single frame and cause instant death
local VANILLA_SICKNESS_INTERVAL = 1  -- Check EVERY tick - POISON spikes rapidly

-- Sickness level mapping: Our stage -> Vanilla level
EHR.Disease.VanillaSicknessLevels = {
    [0] = 0,      -- No disease
    [1] = 10,     -- Incubating: subtle, no moodle
    [2] = 35,     -- Early: Queasy moodle
    [3] = 60,     -- Peak: Nauseous moodle (capped below lethal 75+)
    [4] = 20,     -- Recovery: mild Queasy, fading
}

-- Max vanilla sickness we allow (prevents lethal health drain)
EHR.Disease.VANILLA_SICKNESS_CAP = 65

-- Flag to track if we found the vanilla API
EHR.Disease.vanillaAPIFound = false
EHR.Disease.vanillaAPIChecked = false

-- Cache for sickness level to prevent flickering (per-player)
local cachedSicknessTargets = {}  -- playerID -> {target, lastSetTime}

--[[
    Get what vanilla sickness level should be based on our disease state
]]--
function EHR.Disease.GetTargetVanillaSickness(player, ignoreDiseaseId)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return 0 end

    -- Find the worst active food-related disease
    local worstStage = 0
    local worstSeverity = 0

    for diseaseId, disease in pairs(data.active) do
        local def = EHR.Disease.Diseases[diseaseId]
        local isFoodDisease = diseaseId == "food_poisoning" or (def and def.category == "food")
        if isFoodDisease and diseaseId ~= ignoreDiseaseId then
            if disease.stage > worstStage then
                worstStage = disease.stage
                worstSeverity = disease.severity or 0.5
            end
        end
    end

    if worstStage == 0 then return 0 end

    -- Get base level for this stage
    local baseLevel = EHR.Disease.VanillaSicknessLevels[worstStage] or 0

    -- Adjust by severity (0.5 severity = base, 1.0 = +50%, 0.0 = -50%)
    local adjustedLevel = baseLevel * (0.5 + worstSeverity)

    -- Cap at safe level
    return math.min(adjustedLevel, EHR.Disease.VANILLA_SICKNESS_CAP)
end

function EHR.Disease.ResetFoodSicknessAfterCure(player, curedDiseaseId)
    if not player then return end

    local stats = player:getStats()
    if not stats or not CharacterStat then return end

    local data = EHR.Disease.GetDiseaseData(player)
    local active = data and data.active or {}
    if active["corpse_sickness"] then return end

    local targetB42 = EHR.Disease.GetTargetVanillaSickness(player, curedDiseaseId) / 100

    if EHR.CorpseSickness and EHR.CorpseSickness.GetVanillaSicknessTarget then
        local modData = player:getModData()
        local corpseData = modData and modData.EHR_CorpseSickness
        local exposure = corpseData and (corpseData.currentExposure or 0) or 0
        if exposure > 0 then
            targetB42 = math.max(targetB42, EHR.CorpseSickness.GetVanillaSicknessTarget(exposure))
        end
    end

    if CharacterStat.FOOD_SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            if current > targetB42 then
                stats:set(CharacterStat.FOOD_SICKNESS, targetB42)
            end
        end)
    end

    if CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            if current > targetB42 then
                stats:set(CharacterStat.SICKNESS, targetB42)
            end
        end)
    end

    if CharacterStat.POISON then
        pcall(function() stats:set(CharacterStat.POISON, 0) end)
    end

    local playerID = player:getUsername() or "default"
    cachedSicknessTargets[playerID] = { target = targetB42, lastSetTime = getGameTime():getWorldAgeHours() }

    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end

    EHR.Log("Food sickness reset after cure")
end

--[[
    Sync our disease state to vanilla food sickness
    - If vanilla spikes (player ate bad food), we already contracted our disease via FoodHook
    - We set vanilla to match our disease stage for moodles
    - Cap vanilla to prevent lethal health drain
]]--
function EHR.Disease.SyncVanillaFoodSickness(player)
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then
        EHR.Log("SyncVanilla: No bodyDamage!")
        return
    end

    -- B42 uses CharacterStat.FOOD_SICKNESS through Stats API
    local stats = player:getStats()
    if not stats then
        EHR.Log("SyncVanilla: No stats object!")
        return
    end

    -- CRITICAL: Suppress POISON IMMEDIATELY on every call
    -- POISON values spike to 14+ from raw food and cause rapid death
    -- Must be done BEFORE any other processing to prevent frame-perfect deaths
    if CharacterStat and CharacterStat.POISON then
        local success, poisonVal = pcall(function() return stats:get(CharacterStat.POISON) end)
        if success and poisonVal and poisonVal > 0.05 then
            pcall(function() stats:set(CharacterStat.POISON, 0) end)
            if EHR.DEBUG then
                EHR.Log(string.format("SyncVanilla: Suppressed POISON immediately: %.3f -> 0", poisonVal))
            end
        end
    end

    local currentVanilla = nil

    -- Try to get food sickness via CharacterStat enum
    if CharacterStat and CharacterStat.FOOD_SICKNESS then
        local success, result = pcall(function() return stats:get(CharacterStat.FOOD_SICKNESS) end)
        if success and result ~= nil then
            currentVanilla = result
            EHR.Disease.vanillaAPIFound = true
        end
    end

    EHR.Disease.vanillaAPIChecked = true

    if currentVanilla == nil then
        EHR.Log("SyncVanilla: Could not read CharacterStat.FOOD_SICKNESS")
        EHR.Disease.vanillaAPIFound = false
        return
    end

    -- Debug: Log vanilla sickness if significant
    if EHR.DEBUG and currentVanilla > 0.05 then
        EHR.Log(string.format("SyncVanilla: FOOD_SICKNESS = %.3f", currentVanilla))
    end

    -- Get our target level based on disease state (returns 0-100)
    local targetLevel = EHR.Disease.GetTargetVanillaSickness(player)

    if targetLevel == 0 and currentVanilla > 0.01 then
        if EHR.CorpseSickness and EHR.CorpseSickness.ShouldSuppressFoodSickness and EHR.CorpseSickness.ShouldSuppressFoodSickness(player) then
            if CharacterStat.FOOD_SICKNESS then
                pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0) end)
            end
            if EHR.CorpseSickness.SuppressFoodSicknessComponent then
                EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
            end
            return
        end

        local vanillaCap01 = EHR.Disease.VANILLA_SICKNESS_CAP / 100
        if currentVanilla > vanillaCap01 and CharacterStat.FOOD_SICKNESS then
            pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, vanillaCap01) end)
        end
        if CharacterStat.SICKNESS then
            local currentSickness = 0
            local ok, value = pcall(function() return stats:get(CharacterStat.SICKNESS) end)
            if ok and value then currentSickness = value end
            if currentSickness > vanillaCap01 then
                pcall(function() stats:set(CharacterStat.SICKNESS, vanillaCap01) end)
            elseif currentSickness < currentVanilla then
                pcall(function() stats:set(CharacterStat.SICKNESS, math.min(currentVanilla, vanillaCap01)) end)
            end
        end
        if EHR.DEBUG then
            EHR.Log(string.format("SyncVanilla: Preserved external FOOD_SICKNESS %.3f", currentVanilla))
        end
        return
    end

    -- If vanilla is way higher than our target, player might have eaten something
    -- that we didn't catch (corpse sickness, etc). Cap it but don't zero it.
    -- Note: currentVanilla is 0-1 scale, VANILLA_SICKNESS_CAP is 0-100
    local vanillaCap01 = EHR.Disease.VANILLA_SICKNESS_CAP / 100
    if currentVanilla > vanillaCap01 then
        -- Cap at safe level to prevent death, but keep some for moodles
        targetLevel = math.max(targetLevel, EHR.Disease.VANILLA_SICKNESS_CAP)
    end

    -- B42 uses 0-1 scale, not 0-100 like old API
    -- Convert our target (0-100) to B42 scale (0-1)
    local targetB42 = targetLevel / 100

    -- Check for POISON stat (raw food triggers this, causes rapid death)
    local currentPoison = 0
    if CharacterStat.POISON then
        local success, val = pcall(function() return stats:get(CharacterStat.POISON) end)
        if success and val then
            currentPoison = val
        end
    end

    -- BUG-014 FIX: Snap values away from moodle thresholds to prevent flicker
    -- Moodle thresholds: 0.25 (Queasy), 0.50 (Nauseous), 0.75 (Sick), 0.90 (Fever)
    local moodleThresholds = {0.25, 0.50, 0.75, 0.90}
    for _, threshold in ipairs(moodleThresholds) do
        if math.abs(targetB42 - threshold) < 0.05 then
            -- Snap to clearly above or below threshold (increased from 0.03 to 0.05)
            if targetB42 < threshold then
                targetB42 = threshold - 0.06
            else
                targetB42 = threshold + 0.06
            end
            break
        end
    end

    -- Hysteresis: Only change target if it's significantly different from cached
    local playerID = player:getUsername() or "default"
    local cached = cachedSicknessTargets[playerID]
    local currentHour = getGameTime():getWorldAgeHours()

    if cached then
        local targetDiff = math.abs(cached.target - targetB42)
        local timeSinceSet = currentHour - cached.lastSetTime

        -- Only change target if:
        -- 1. Target differs by more than 15% (major stage change), OR
        -- 2. At least 0.25 game hours (15 min) have passed
        if targetDiff < 0.15 and timeSinceSet < 0.25 then
            targetB42 = cached.target  -- Keep old target
        else
            cachedSicknessTargets[playerID] = {target = targetB42, lastSetTime = currentHour}
        end
    else
        cachedSicknessTargets[playerID] = {target = targetB42, lastSetTime = currentHour}
    end

    -- Update if sickness significantly different OR poison is active
    -- BUG-014 FIX: Increase dead zone to 0.12 (12%) to prevent oscillation
    -- BUG-021 FIX: ALWAYS suppress if vanilla is ABOVE our target (prevents moodle flash)
    -- The dead zone only applies when vanilla is below target (we don't want to boost it)
    local difference = math.abs(currentVanilla - targetB42)
    local vanillaAboveTarget = currentVanilla > targetB42 + 0.02  -- Small margin for floating point
    local needsUpdate = vanillaAboveTarget or difference > 0.12 or currentPoison > 0.1

    if needsUpdate then
        local successFood = pcall(function()
            stats:set(CharacterStat.FOOD_SICKNESS, targetB42)
        end)

        -- CRITICAL: Also set CharacterStat.SICKNESS to trigger moodles!
        -- Moodles are driven by SICKNESS (aggregate), not FOOD_SICKNESS (component)
        local successSick = false
        if CharacterStat.SICKNESS then
            successSick = pcall(function()
                stats:set(CharacterStat.SICKNESS, targetB42)
            end)
        end

        -- CRITICAL: Suppress POISON stat - raw food triggers POISON which causes rapid death!
        -- POISON values can go to 14+ and cause instant death. Zero it out.
        local successPoison = false
        if currentPoison > 0.1 and CharacterStat.POISON then
            successPoison = pcall(function()
                stats:set(CharacterStat.POISON, 0)
            end)
        end

        -- Force moodle recalculation after changing stats
        if successFood or successSick then
            local moodles = player:getMoodles()
            if moodles and moodles.Update then
                pcall(function() moodles:Update() end)
            end
        end

        if EHR.DEBUG then
            if successPoison then
                EHR.Log(string.format("Suppressed POISON: %.3f -> 0", currentPoison))
            end
            if successFood or successSick then
                EHR.Log(string.format("Synced vanilla sickness: %.3f -> %.3f (FOOD_SICKNESS=%s, SICKNESS=%s)",
                    currentVanilla, targetB42, tostring(successFood), tostring(successSick)))
            end
        end

        if not successFood and not successSick and not successPoison then
            EHR.Log("SyncVanilla: Failed to set any stats")
        end
    end
end

-- ============================================
-- MAIN TICK HANDLER
-- ============================================

local function processPlayerTick(player)
    if not player then return end
    if not player:isAlive() then return end

    -- Get player mod data
    local modData = player:getModData()
    if not modData then return end

    local state = getTickState(player)

    -- MP FIX: Don't initialize during debug grace period
    if EHR.Disease.IsInDebugGracePeriod(player) then
        -- During grace period, trust whatever data exists and mark initialized
        if modData.EHR_Disease and modData.EHR_Disease.active then
            modData.EHR_Disease_Initialized = true
            -- Count actual diseases (only log once per second to reduce spam)
            local diseaseCount = 0
            for _ in pairs(modData.EHR_Disease.active) do
                diseaseCount = diseaseCount + 1
            end
            -- Only print every ~60 ticks to reduce spam
            if not EHR.Disease._graceLogCounter then EHR.Disease._graceLogCounter = 0 end
            EHR.Disease._graceLogCounter = EHR.Disease._graceLogCounter + 1
            if EHR.Disease._graceLogCounter >= 60 then
                EHR.Disease._graceLogCounter = 0
                print("[EHR Disease] Grace period: " .. diseaseCount .. " active diseases preserved")
            end
        end
        return  -- Skip normal processing during grace period
    end

    -- Initialize if needed
    if not modData.EHR_Disease_Initialized then
        -- Preserve existing data if present
        if type(modData.EHR_Disease) == "table" then
            modData.EHR_Disease_Initialized = true
            EHR.Log("Disease module: Found existing data, marking initialized")
        else
            EHR.Disease.InitializePlayer(player)
        end
        return
    end

    -- Sync our disease state to vanilla food sickness (suppresses vanilla death)
    state.vanilla = state.vanilla + 1
    if state.vanilla >= VANILLA_SICKNESS_INTERVAL then
        state.vanilla = 0
        EHR.Disease.SyncVanillaFoodSickness(player)
    end

    -- Disease progression (every ~2 seconds)
    state.disease = state.disease + 1
    if state.disease >= DISEASE_TICK_INTERVAL then
        state.disease = 0
        -- Apply Lifestyle & Hobbies healing bonuses before progression
        EHR.Disease.ApplyHealingBonuses(player, modData)
        EHR.Disease.UpdateProgression(player, modData)
    end

    -- Dialogue checks (every ~1 minute)
    state.dialogue = state.dialogue + 1
    if state.dialogue >= DIALOGUE_TICK_INTERVAL then
        state.dialogue = 0
        EHR.Disease.CheckDialogue(player, modData)
    end

    -- MP: sync ModData periodically from server
    if isServer and isServer() then
        state.sync = state.sync + 1
        if state.sync >= SYNC_TICK_INTERVAL then
            state.sync = 0
            if player.transmitModData then
                pcall(function() player:transmitModData() end)
            end
        end
    end
    -- CRITICAL FIX: Removed dead code block (lines 1772-1795) that referenced
    -- undefined variables (diseaseId, stats, stage, severity) outside their scope.
    -- This was a copy-paste error that could never execute successfully.
end

function EHR.Disease.OnTick()
    -- Check if disease system is enabled via sandbox
    if not EHR.Disease.IsEnabled() then return end
    -- MP: server-authoritative processing
    if isClient and isClient() and not (isServer and isServer()) then return end

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

    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function EHR.Disease.OnGameStart()
    EHR.Log("Disease module OnGameStart")

    local player = getSpecificPlayer(0)
    if player then
        EHR.Disease.InitializePlayer(player)
    end
end

function EHR.Disease.OnCreatePlayer(playerIndex, player)
    EHR.Log("Disease module OnCreatePlayer: " .. playerIndex)
    EHR.Disease.InitializePlayer(player)
end

function EHR.Disease.OnPlayerDeath(player)
    EHR.Log("Disease module: Player died, clearing disease data")
    -- Data will be cleared with player, no action needed
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events then
    Events.OnTick.Add(EHR.Disease.OnTick)
    Events.OnGameStart.Add(EHR.Disease.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.Disease.OnCreatePlayer)
    Events.OnPlayerDeath.Add(EHR.Disease.OnPlayerDeath)

    -- Food eating hook
    if Events.OnEat then
        Events.OnEat.Add(EHR.Disease.OnEatFood)
        EHR.Log("Disease: Hooked OnEat event")
    else
        EHR.Log("Disease: OnEat event not available - will use alternative method")
    end

    EHR.Log("Disease module events registered")
end

EHR.Log("Disease module loaded v1.0.1")

