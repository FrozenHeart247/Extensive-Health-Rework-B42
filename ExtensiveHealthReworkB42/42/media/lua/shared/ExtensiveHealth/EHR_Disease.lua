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
    - CharacterStat.POISON: Raw food can spike this, but true PoisonPower food must remain dangerous
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
            tier2 = {"ExtensiveHealth.ActivatedCharcoal"},  -- Cures in 6h
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
            tier3 = {"ExtensiveHealth.IVCiprofloxacin"},  -- Severe bacterial GI infection
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

    ["toxin_poisoning"] = {
        name = "Toxin Poisoning",
        category = "food",
        incubationMin = 1,
        incubationMax = 4,
        durationMin = 24,
        durationMax = 96,
        baseSeverity = 0.65,
        canKill = true,
        stageCount = 4,
        treatments = {
            tier0 = {},
            tier1 = {"ExtensiveHealth.AntiNauseaTablets", "ExtensiveHealth.ElectrolytePowder"},
            tier2 = {"ExtensiveHealth.ActivatedCharcoal"},
            tier3 = {},
        },
        stageEntryDialogue = {
            [1] = "That tasted wrong...",
            [2] = "My stomach is turning... I think that was poisonous...",
            [3] = "*retches* Something is badly wrong...",
            [4] = "The poison is finally passing...",
        },
        dialogue = {
            [1] = {"My mouth feels bitter...", "That was a mistake..."},
            [2] = {"I feel poisoned...", "My stomach is burning...", "I'm getting dizzy..."},
            [3] = {"*vomits*", "I need help...", "My body feels like it's shutting down..."},
            [4] = {"Still shaky...", "I think I'm recovering..."},
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
            tier2 = {},
            tier3 = {"ExtensiveHealth.CorticosteroidInjection", "ExtensiveHealth.RespiratorySupportKit"},
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
    burned = 0.05,          -- 5% chance from burned food
    stale = 0.10,           -- 10% chance from stale food
    dangerousUncooked = 0.35,
    rawWildGameHigh = 0.70,
    rawWildGameMedium = 0.70,
    rawWildGameLow = 0.70,
    rawMeatLow = 0.70,
}

-- Food poisoning is not a one-frame lottery: repeated risky bites stack up.
EHR.Disease.FoodRiskAccumulation = {
    decayPerHour = 0.20,
    maxChance = 0.95,
    guaranteedThreshold = 0.80,
    pendingSicknessScale = 45,
    pendingSicknessMax = 24,
}

EHR.Disease.FoodRiskMemory = EHR.Disease.FoodRiskMemory or {}

-- ============================================
-- TICK MANAGEMENT
-- ============================================

local DISEASE_TICK_INTERVAL = 60  -- Update every 60 ticks (~2 seconds)
local EHR_DiseaseEffectTimeScale = 1

local function EHR_DiseaseGetRuntimeTimeScale()
    local scale = 1
    local gameTime = getGameTime and getGameTime() or nil

    if gameTime then
        local okTrue, trueMultiplier = pcall(function()
            if gameTime.getTrueMultiplier then
                return gameTime:getTrueMultiplier()
            end
            return nil
        end)
        if okTrue and type(trueMultiplier) == "number" and trueMultiplier > 0 then
            scale = trueMultiplier
        else
            local okMult, multiplier = pcall(function()
                if gameTime.getMultiplier then
                    return gameTime:getMultiplier()
                end
                return nil
            end)
            if okMult and type(multiplier) == "number" and multiplier > 0 then
                scale = multiplier / 1.6
            end
        end
    end

    return math.max(1, math.min(40, scale))
end

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
    if diseaseId == "food_poisoning" then
        immunity = 1.0
        specificImmunity = 0
        data.immunity[diseaseId] = 0
    end

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

    -- Record food exposure in history
    if diseaseId == "food_poisoning" or def.category == "food" then
        data.history.lastBadFood = currentHour
        data.history.lastFoodRiskDiseaseId = diseaseId
        if EHR.Disease.ClearAccumulatedFoodRisk then
            EHR.Disease.ClearAccumulatedFoodRisk(data.history, diseaseId)
        else
            data.history.foodRiskAccumulated = 0
            data.history.foodRiskLastTime = nil
            data.history.lastFoodAccumulatedRisk = nil
        end
        if EHR.Disease.ClearFoodRiskMemory then
            EHR.Disease.ClearFoodRiskMemory(player, diseaseId)
        end
    end
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
                    local effectScale = EHR_DiseaseGetRuntimeTimeScale()
                    local previousEffectScale = EHR_DiseaseEffectTimeScale
                    EHR_DiseaseEffectTimeScale = effectScale
                    local okEffects, effectErr = pcall(EHR.Disease.ApplyEffects, player, diseaseId, disease, def)
                    EHR_DiseaseEffectTimeScale = previousEffectScale
                    if not okEffects then
                        error(effectErr)
                    end
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

    -- Build specific immunity for non-food-poisoning diseases.
    -- Food poisoning should stay fully risk-based on each bad meal.
    if diseaseId == "food_poisoning" then
        data.immunity[diseaseId] = 0
    elseif diseaseId == "toxin_poisoning" then
        data.immunity[diseaseId] = 0
    else
        data.immunity[diseaseId] = math.min(0.8, (data.immunity[diseaseId] or 0) + 0.5)
    end

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

    if diseaseId == "toxin_poisoning" and EHR.Disease.ClearVanillaPoison then
        EHR.Disease.ClearVanillaPoison(player)
    end

    if diseaseId == "corpse_sickness" and EHR.CorpseSickness and EHR.CorpseSickness.ResetAfterCure then
        EHR.CorpseSickness.ResetAfterCure(player)
    elseif def and def.category == "food" and EHR.Disease.ResetFoodSicknessAfterCure then
        EHR.Disease.ResetFoodSicknessAfterCure(player, diseaseId)
    end
end

-- ============================================
-- DISEASE EFFECTS
-- ============================================

--[[
    Apply disease effects based on stage and severity
]]--
local function EHR_DiseaseDrainEndurance(stats, amount, floor)
    if not stats or not amount or amount <= 0 then return end
    amount = amount * (EHR_DiseaseEffectTimeScale or 1)
    floor = floor or 0.35

    if CharacterStat and CharacterStat.ENDURANCE then
        local okGet, current = pcall(function()
            return stats:get(CharacterStat.ENDURANCE)
        end)

        if okGet then
            current = current or 1
            if current <= floor then return end

            local okSet = pcall(function()
                stats:set(CharacterStat.ENDURANCE, math.max(floor, current - amount))
            end)

            if okSet then return end
        end
    end

    -- B42 can expose endurance only through CharacterStat. If that is unavailable,
    -- convert a tiny part of the drain into fatigue instead of calling missing APIs.
    if CharacterStat and CharacterStat.FATIGUE then
        pcall(function()
            local current = stats:get(CharacterStat.FATIGUE) or 0
            stats:set(CharacterStat.FATIGUE, math.min(1, math.max(0, current + (amount * 0.02))))
        end)
    end
end

local function EHR_DiseaseAddStat(stats, stat, amount)
    if not stats or not stat or not amount or amount == 0 then return end
    amount = amount * (EHR_DiseaseEffectTimeScale or 1)

    pcall(function()
        local current = stats:get(stat) or 0
        stats:set(stat, math.min(1, math.max(0, current + amount)))
    end)
end

local function EHR_DiseaseReduceStat(stats, stat, amount)
    if not stats or not stat or not amount or amount <= 0 then return end
    amount = amount * (EHR_DiseaseEffectTimeScale or 1)

    pcall(function()
        local current = stats:get(stat) or 0
        stats:set(stat, math.max(0, current - amount))
    end)
end

local function EHR_DiseaseRaiseStatToward(stats, stat, target, step, maxValue)
    if not stats or not stat or not target or not step or step <= 0 then return end
    step = step * (EHR_DiseaseEffectTimeScale or 1)
    maxValue = maxValue or 1

    pcall(function()
        local current = stats:get(stat) or 0
        if current >= target then return end

        local nextValue = math.min(target, math.min(current + step, maxValue))
        stats:set(stat, math.max(0, nextValue))
    end)
end

local function EHR_DiseaseLowerStatToward(stats, stat, target, step, minValue)
    if not stats or not stat or not target or not step or step <= 0 then return end
    step = step * (EHR_DiseaseEffectTimeScale or 1)
    minValue = minValue or 0

    pcall(function()
        local current = stats:get(stat) or 0
        if current <= target then return end

        local nextValue = math.max(target, math.max(current - step, minValue))
        stats:set(stat, math.min(1, nextValue))
    end)
end

local function EHR_DiseaseClampSicknessStat(stats, maxAllowed)
    if not stats or not maxAllowed then return false end

    local changed = false
    maxAllowed = math.max(0, math.min(1, maxAllowed))

    if CharacterStat and CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            if current > maxAllowed then
                stats:set(CharacterStat.SICKNESS, maxAllowed)
                changed = true
            end
        end)
    end

    if stats.getSickness and stats.setSickness then
        pcall(function()
            local current = stats:getSickness() or 0
            if current > maxAllowed then
                stats:setSickness(maxAllowed)
                changed = true
            end
        end)
    end

    return changed
end

local function EHR_DiseaseRaisePainToward(stats, target, step)
    if not stats or not target or not step or step <= 0 then return end
    step = step * (EHR_DiseaseEffectTimeScale or 1)
    target = math.min(1, math.max(0, target))

    if stats.getPain and stats.setPain then
        local okGet, current = pcall(function()
            return stats:getPain()
        end)

        if okGet then
            current = current or 0
            if current < target then
                local okSet = pcall(function()
                    stats:setPain(math.min(target, current + step))
                end)
                if okSet then return end
            else
                return
            end
        end
    end

    if CharacterStat and CharacterStat.PAIN then
        pcall(function()
            local current = stats:get(CharacterStat.PAIN) or 0
            if current < target then
                stats:set(CharacterStat.PAIN, math.min(target, math.min(current + step, 1)))
            end
        end)
    end
end

local function EHR_DiseaseRoll(chance)
    if not chance or chance <= 0 then return false end
    if chance >= 1 then return true end
    if not ZombRand then return false end

    return (ZombRand(1000000) / 1000000) < chance
end

local function EHR_DiseaseCanTriggerSymptom(disease, key, cooldownHours)
    if not disease or not key then return true end

    local now = 0
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime then
        local ok, hours = pcall(function() return gameTime:getWorldAgeHours() end)
        if ok and hours then
            now = hours
        end
    end

    disease.symptomCooldowns = disease.symptomCooldowns or {}
    if (disease.symptomCooldowns[key] or 0) > now then
        return false
    end

    disease.symptomCooldowns[key] = now + (cooldownHours or 0.10)
    return true
end

local function EHR_DiseaseSay(player, lines)
    if not player or not player.Say or not lines or #lines == 0 then return end

    local index = 1
    if ZombRand then
        index = ZombRand(#lines) + 1
    end

    player:Say(lines[index])
end

local function EHR_DiseaseTriggerVomit(player)
    if EHR.Environmental and EHR.Environmental.TriggerVomit then
        local ok = pcall(function() EHR.Environmental.TriggerVomit(player) end)
        if ok then return end
    end

    EHR_DiseaseSay(player, {"*vomits*", "*retches*", "*throws up*"})
end

local function EHR_DiseaseTriggerCough(player, severe)
    if EHR.Environmental and EHR.Environmental.TriggerCough then
        local ok = pcall(function() EHR.Environmental.TriggerCough(player, severe) end)
        if ok then return end
    end

    if severe then
        EHR_DiseaseSay(player, {"*coughing fit*", "*coughs hard*", "*can't stop coughing*"})
    else
        EHR_DiseaseSay(player, {"*coughs*", "*cough*", "*clears throat*"})
    end
end

local function EHR_DiseaseTriggerDizziness(player)
    local isLocalPlayer = false
    if player then
        pcall(function() isLocalPlayer = player:isLocalPlayer() end)
    end

    if isLocalPlayer and EHR.ToxinVision and EHR.ToxinVision.StartSymptomEpisode then
        pcall(function() EHR.ToxinVision.StartSymptomEpisode(player) end)
    end

    if EHR.Environmental and EHR.Environmental.TriggerDizziness then
        local ok = pcall(function() EHR.Environmental.TriggerDizziness(player) end)
        if ok then return end
    end

    EHR_DiseaseSay(player, {"*dizzy*", "*stumbles*", "*sways*"})
end

local function EHR_DiseaseTriggerCollapse(player)
    if EHR.Environmental and EHR.Environmental.TriggerCollapse then
        local ok = pcall(function() EHR.Environmental.TriggerCollapse(player) end)
        if ok then return end
    end

    EHR_DiseaseSay(player, {"*collapses*", "*legs give out*", "*falls down*"})
end

local function EHR_DiseaseTriggerCramp(player)
    if EHR.Environmental and EHR.Environmental.TriggerCramp then
        local ok = pcall(function() EHR.Environmental.TriggerCramp(player) end)
        if ok then return end
    end

    EHR_DiseaseSay(player, {"*muscle cramp*", "*winces in pain*", "*muscles seize up*"})
end

local function EHR_DiseaseKillPlayer(player, cause)
    if not player then return end

    if EHR.RecordDeathCause then
        EHR.RecordDeathCause(player, cause or "Severe disease complications")
    end

    if player.Say then
        player:Say("*collapses*")
    end

    pcall(function()
        if player.setHealth then
            player:setHealth(0)
        end
    end)

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if bodyDamage then
        pcall(function() bodyDamage:setOverallBodyHealth(0) end)
    end
end

local function EHR_DiseaseApplyBodyHealthDamage(player, amount, cause)
    if not player or not amount or amount <= 0 then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return nil end

    local okHealth, currentHealth = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)
    if not okHealth or not currentHealth then return nil end

    local reducedByBodyDamage = false
    if bodyDamage.ReduceGeneralHealth then
        reducedByBodyDamage = pcall(function()
            bodyDamage:ReduceGeneralHealth(amount)
        end)
    end

    if reducedByBodyDamage then
        local okAfter, afterHealth = pcall(function()
            return bodyDamage:getOverallBodyHealth()
        end)
        if okAfter and afterHealth then
            if afterHealth <= 0 then
                EHR_DiseaseKillPlayer(player, cause)
                return 0
            end
            if afterHealth < currentHealth then
                return afterHealth
            end
        end
    end

    local newHealth = math.max(0, currentHealth - amount)
    if newHealth <= 0 then
        EHR_DiseaseKillPlayer(player, cause)
        return 0
    end

    local okSet = pcall(function()
        bodyDamage:setOverallBodyHealth(newHealth)
    end)

    -- Some UI paths read character health more visibly than BodyDamage overall health.
    if not okSet then
        pcall(function()
            if player.getHealth and player.setHealth then
                local current = player:getHealth() or newHealth
                player:setHealth(math.max(0, current - amount))
            end
        end)
    end

    return newHealth
end

local function EHR_DiseaseClampBodyHealth(player, maxHealth)
    if not player or not maxHealth then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return nil end

    local okHealth, currentHealth = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)
    if not okHealth or not currentHealth then return nil end

    local healthCap = math.max(1, math.min(100, maxHealth))
    if currentHealth > healthCap then
        local clamped = false
        if bodyDamage.ReduceGeneralHealth then
            clamped = pcall(function()
                bodyDamage:ReduceGeneralHealth(currentHealth - healthCap)
            end)
        end

        if clamped then
            local okAfter, afterHealth = pcall(function()
                return bodyDamage:getOverallBodyHealth()
            end)
            if not okAfter or not afterHealth or afterHealth > healthCap then
                clamped = false
            end
        end

        if not clamped then
            pcall(function()
                bodyDamage:setOverallBodyHealth(healthCap)
            end)
        end
    end

    return math.min(currentHealth, healthCap)
end

local function EHR_DiseaseGetBodyHealth(player)
    if not player then return nil end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return nil end

    local okHealth, currentHealth = pcall(function()
        return bodyDamage:getOverallBodyHealth()
    end)

    if okHealth then
        return currentHealth
    end

    return nil
end

local function EHR_DiseaseGetActiveCurativeTreatment(player, diseaseId)
    if not player or not diseaseId then return nil end

    local modData = player:getModData()
    local medTracking = modData and modData.EHR_Medication
    local treatments = medTracking and medTracking.activeTreatments
    local treatment = treatments and treatments[diseaseId]
    if not treatment then return nil end

    if treatment.tier and treatment.tier < 2 then return nil end

    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and treatment.startTime and treatment.cureTimeHours then
        local currentHour = gameTime:getWorldAgeHours()
        if (currentHour - treatment.startTime) >= treatment.cureTimeHours then
            return nil
        end
    end

    return treatment
end

local function EHR_DiseaseGetActiveSymptomMultiplier(player, diseaseId, disease)
    if not player or not diseaseId or not disease then return 1.0 end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local multiplier = 1.0

    if disease.symptomReliefUntil and disease.symptomReliefUntil > currentHour then
        multiplier = math.min(multiplier, disease.symptomSeverity or 1.0)
    elseif disease.symptomReliefUntil then
        disease.symptomReliefUntil = nil
        disease.symptomReliefMedKey = nil
        disease.symptomSeverity = 1.0
    end

    local modData = player:getModData()
    local medTracking = modData and modData.EHR_Medication
    local activeDoses = medTracking and medTracking.activeDoses
    if activeDoses and EHR.Medication and EHR.Medication.TierEffectiveness then
        for medKey, doseData in pairs(activeDoses) do
            if type(doseData) == "table" and doseData.treatingDisease == diseaseId and doseData.lastDoseTime and doseData.intervalHours then
                local effectActive = false
                if EHR.Medication.GetDoseStatus then
                    local status = EHR.Medication.GetDoseStatus(player, medKey)
                    effectActive = status and status.isDoseActive and status.treatingDisease == diseaseId
                else
                    local elapsed = currentHour - doseData.lastDoseTime
                    effectActive = elapsed >= 0 and elapsed <= doseData.intervalHours
                end

                if effectActive then
                    local tier = doseData.tier
                    local medData = EHR.Medication.Database and EHR.Medication.Database[medKey] or nil
                    if not tier and medData then tier = medData.tier end

                    local tierEffects = EHR.Medication.TierEffectiveness[tier or 0]
                    if tierEffects and tierEffects.symptomRelief and tierEffects.symptomRelief > 0 then
                        multiplier = math.min(multiplier, 1 - tierEffects.symptomRelief)
                    end
                end
            end
        end
    end

    return math.max(0.20, math.min(1.0, multiplier))
end

local function EHR_DiseaseGetActiveSymptomReduction(player, diseaseId, reductionKey)
    if not player or not diseaseId or not reductionKey then return 0 end
    if not EHR.Medication or not EHR.Medication.Database then return 0 end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
    local modData = player:getModData()
    local medTracking = modData and modData.EHR_Medication
    local activeDoses = medTracking and medTracking.activeDoses
    if not activeDoses then return 0 end

    local activeReduction = 0
    for medKey, doseData in pairs(activeDoses) do
        if type(doseData) == "table" and doseData.treatingDisease == diseaseId and doseData.lastDoseTime and doseData.intervalHours then
            local effectActive = false
            if EHR.Medication.GetDoseStatus then
                local status = EHR.Medication.GetDoseStatus(player, medKey)
                effectActive = status and status.isDoseActive and status.treatingDisease == diseaseId
            else
                local elapsed = currentHour - doseData.lastDoseTime
                effectActive = elapsed >= 0 and elapsed <= doseData.intervalHours
            end

            if effectActive then
                local medData = EHR.Medication.Database[medKey]
                local reductions = medData and medData.symptomReduction
                local reduction = reductions and reductions[reductionKey] or 0
                if reduction > activeReduction then
                    activeReduction = reduction
                end
            end
        end
    end

    return math.max(0, math.min(1, activeReduction))
end

local function EHR_DiseaseIsMusclePart(partType, part)
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

local function EHR_DiseaseApplyMuscleStrain(player, targetStiffness, step)
    if not player or not targetStiffness or targetStiffness <= 0 then return end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return end

    targetStiffness = math.min(100, math.max(0, targetStiffness))
    step = math.min(6, math.max(0.1, step or 0.5))
    local changed = false

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil

        if part and EHR_DiseaseIsMusclePart(partType, part) then
            local okCurrent, currentStiffness = pcall(function()
                return part:getStiffness()
            end)

            currentStiffness = (okCurrent and currentStiffness) or 0
            if currentStiffness < targetStiffness then
                local amount = math.min(step, targetStiffness - currentStiffness)
                local okAdd = false

                if player.addStiffness then
                    okAdd = pcall(function()
                        player:addStiffness(partType, amount)
                    end)
                end

                if not okAdd and bodyDamage.addStiffness then
                    okAdd = pcall(function()
                        bodyDamage:addStiffness(partType, amount)
                    end)
                end

                if not okAdd and part.addStiffness then
                    okAdd = pcall(function()
                        part:addStiffness(amount)
                    end)
                end

                if not okAdd and part.setStiffness then
                    okAdd = pcall(function()
                        part:setStiffness(math.min(targetStiffness, currentStiffness + amount))
                    end)
                end

                if okAdd then
                    changed = true
                end
            end
        end
    end

    if changed and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end

    -- These character-level helpers make the B42 fitness/muscle-strain UI notice systemic stiffness.
    local systemicAmount = math.min(2.0, step * 0.35)
    if changed and targetStiffness >= 25 then
        if player.addBackMuscleStrain then
            pcall(function() player:addBackMuscleStrain(systemicAmount) end)
        end
        if player.addBothArmMuscleStrain then
            pcall(function() player:addBothArmMuscleStrain(systemicAmount) end)
        end
        if player.addRightLegMuscleStrain then
            pcall(function() player:addRightLegMuscleStrain(systemicAmount) end)
        end
    end
end

local function EHR_DiseaseReduceMuscleStrainToward(player, targetStiffness, step)
    if not player or targetStiffness == nil then return end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return end

    targetStiffness = math.min(100, math.max(0, targetStiffness))
    step = math.min(5, math.max(0.05, step or 0.5))
    local changed = false

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil

        if part and EHR_DiseaseIsMusclePart(partType, part) then
            local okCurrent, currentStiffness = pcall(function()
                return part:getStiffness()
            end)

            currentStiffness = (okCurrent and currentStiffness) or 0
            if currentStiffness > targetStiffness and part.setStiffness then
                local newStiffness = math.max(targetStiffness, currentStiffness - step)
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
                    part:setAdditionalPain(math.max(0, currentPain - (step * 1.5)))
                end)
            end
        end
    end

    if changed and bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end
end

function EHR.Disease.ApplyEffects(player, diseaseId, disease, def)
    local stats = player:getStats()
    if not stats then return end

    local severity = disease.severity or (def and def.baseSeverity) or 0.5
    local stage = disease.stage or 1
    local stageMult = 0.0

    if stage == 2 then
        stageMult = 0.45
    elseif stage == 3 then
        stageMult = 1.0
    elseif stage == 4 then
        stageMult = 0.25
    end

    local function trySymptom(key, chance, cooldownHours, callback)
        chance = (chance or 0) * (EHR_DiseaseEffectTimeScale or 1)
        if EHR_DiseaseRoll(chance) and EHR_DiseaseCanTriggerSymptom(disease, key, cooldownHours) then
            pcall(callback)
        end
    end

    -- Food Poisoning specific effects
    if diseaseId == "food_poisoning" then
        local symptomMult = EHR_DiseaseGetActiveSymptomMultiplier(player, "food_poisoning", disease)
        local nauseaRelief = EHR_DiseaseGetActiveSymptomReduction(player, "food_poisoning", "nausea")
        local vomitingRelief = EHR_DiseaseGetActiveSymptomReduction(player, "food_poisoning", "vomiting")
        local dehydrationRelief = EHR_DiseaseGetActiveSymptomReduction(player, "food_poisoning", "dehydration")
        local weaknessRelief = EHR_DiseaseGetActiveSymptomReduction(player, "food_poisoning", "weakness")
        local vomitMult = math.max(0.08, symptomMult * (1 - math.max(vomitingRelief, nauseaRelief * 0.5)))
        local hydrationMult = math.max(0.15, symptomMult * (1 - dehydrationRelief))
        local weaknessMult = math.max(0.20, symptomMult * (1 - weaknessRelief))

        -- Stage 2: Early symptoms
        if stage == 2 then
            EHR_DiseaseDrainEndurance(stats, 0.006 * severity * weaknessMult, 0.75)

        -- Stage 3: Peak symptoms
        elseif stage == 3 then
            EHR_DiseaseDrainEndurance(stats, 0.018 * severity * weaknessMult, 0.55)

            -- Increase hunger (vomiting loses food) - reduced by 50%
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.HUNGER, 0.0005 * severity * vomitMult)

            -- Increase thirst (dehydration from vomiting) - reduced by 50%
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.001 * severity * hydrationMult)

        -- Stage 4: Recovery
        elseif stage == 4 then
            EHR_DiseaseDrainEndurance(stats, 0.002 * severity * weaknessMult, 0.85)
        end

        local vomitChance = (stage == 3 and 0.004 or stage == 2 and 0.0015 or 0.0004) * severity * vomitMult
        trySymptom("vomit", vomitChance, 0.20, function()
            EHR_DiseaseTriggerVomit(player)
        end)

    elseif diseaseId == "gastroenteritis" then
        -- Dirty-hands illness: nausea, vomiting, dehydration and weakness.
        local symptomMult = EHR_DiseaseGetActiveSymptomMultiplier(player, "gastroenteritis", disease)
        local nauseaRelief = EHR_DiseaseGetActiveSymptomReduction(player, "gastroenteritis", "nausea")
        local vomitingRelief = EHR_DiseaseGetActiveSymptomReduction(player, "gastroenteritis", "vomiting")
        local dehydrationRelief = EHR_DiseaseGetActiveSymptomReduction(player, "gastroenteritis", "dehydration")
        local weaknessRelief = EHR_DiseaseGetActiveSymptomReduction(player, "gastroenteritis", "weakness")
        local vomitMult = math.max(0.08, symptomMult * (1 - math.max(vomitingRelief, nauseaRelief * 0.5)))
        local hydrationMult = math.max(0.15, symptomMult * (1 - dehydrationRelief))
        local weaknessMult = math.max(0.20, symptomMult * (1 - weaknessRelief))

        EHR_DiseaseDrainEndurance(stats, 0.003 * severity * stageMult * weaknessMult, 0.30)
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.0011 * severity * stageMult * hydrationMult)
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.HUNGER, 0.00045 * severity * stageMult * vomitMult)

        local vomitChance = (stage == 3 and 0.006 or stage == 2 and 0.002 or 0.0006) * severity * vomitMult
        trySymptom("vomit", vomitChance, 0.18, function()
            EHR_DiseaseTriggerVomit(player)
        end)

    elseif diseaseId == "toxin_poisoning" then
        local toxinType = disease.toxinType or "toxin"
        local isMushroom = toxinType == "mushroom"
        local isBerry = toxinType == "berry"
        local curativeTreatment = EHR_DiseaseGetActiveCurativeTreatment(player, "toxin_poisoning")
        local symptomMult = EHR_DiseaseGetActiveSymptomMultiplier(player, "toxin_poisoning", disease)
        local nauseaRelief = EHR_DiseaseGetActiveSymptomReduction(player, "toxin_poisoning", "nausea")
        local vomitingRelief = EHR_DiseaseGetActiveSymptomReduction(player, "toxin_poisoning", "vomiting")
        local dehydrationRelief = EHR_DiseaseGetActiveSymptomReduction(player, "toxin_poisoning", "dehydration")
        local weaknessRelief = EHR_DiseaseGetActiveSymptomReduction(player, "toxin_poisoning", "weakness")
        local toxinMult = isMushroom and 1.20 or isBerry and 0.75 or 0.95
        local vomitMult = math.max(0.08, symptomMult * (1 - math.max(vomitingRelief, nauseaRelief * 0.5)))
        local hydrationMult = math.max(0.15, symptomMult * (1 - dehydrationRelief))
        local weaknessMult = math.max(0.20, symptomMult * (1 - weaknessRelief))
        local painMult = 1.0
        local stage2EnduranceFloor = 0.70
        local stage3EnduranceFloor = isMushroom and 0.35 or 0.50
        local stage4EnduranceFloor = 0.82

        if curativeTreatment then
            disease.toxinHealthCap = nil
            toxinMult = toxinMult * 0.45
            vomitMult = math.max(0.03, vomitMult * 0.35)
            hydrationMult = math.max(0.06, hydrationMult * 0.45)
            weaknessMult = math.max(0.08, weaknessMult * 0.35)
            painMult = 0.35
            stage2EnduranceFloor = 0.86
            stage3EnduranceFloor = isMushroom and 0.62 or 0.72
            stage4EnduranceFloor = 0.90

            if CharacterStat and CharacterStat.POISON then
                pcall(function() stats:set(CharacterStat.POISON, 0) end)
            end
            EHR_DiseaseReduceStat(stats, CharacterStat and CharacterStat.SICKNESS, 0.006 * severity)
            EHR_DiseaseReduceStat(stats, CharacterStat and CharacterStat.FOOD_SICKNESS, 0.006 * severity)
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.ENDURANCE, 0.003 * severity)
        end

        if stage == 2 then
            EHR_DiseaseDrainEndurance(stats, 0.007 * severity * toxinMult * weaknessMult, stage2EnduranceFloor)
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.0009 * severity * toxinMult * hydrationMult)
            EHR_DiseaseRaiseStatToward(stats, CharacterStat and CharacterStat.FATIGUE, 0.22 * severity * toxinMult, 0.0025 * severity, 1)
        elseif stage == 3 then
            EHR_DiseaseDrainEndurance(stats, 0.017 * severity * toxinMult * weaknessMult, stage3EnduranceFloor)
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.0018 * severity * toxinMult * hydrationMult)
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.HUNGER, 0.0006 * severity * vomitMult)
            EHR_DiseaseRaiseStatToward(stats, CharacterStat and CharacterStat.FATIGUE, (isMushroom and 0.55 or 0.38) * severity, 0.004 * severity, 1)
            EHR_DiseaseRaisePainToward(stats, (isMushroom and 0.22 or 0.12) * severity * painMult, 0.006 * severity * painMult)
        elseif stage == 4 then
            EHR_DiseaseDrainEndurance(stats, 0.003 * severity * weaknessMult, stage4EnduranceFloor)
            EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.00035 * severity * hydrationMult)
        end

        local vomitChance = (stage == 3 and 0.007 or stage == 2 and 0.0025 or 0.0007) * severity * toxinMult * vomitMult
        trySymptom("toxin_vomit", vomitChance, 0.16, function()
            EHR_DiseaseTriggerVomit(player)
        end)

        local dizzyChance = (stage == 3 and 0.005 or stage == 2 and 0.002 or 0.0005) * severity * toxinMult * weaknessMult
        trySymptom("toxin_dizzy", dizzyChance, 0.20, function()
            EHR_DiseaseTriggerDizziness(player)
        end)

        if isMushroom and stage == 3 and not curativeTreatment then
            if not disease.toxinHealthCap then
                disease.toxinHealthCap = EHR_DiseaseGetBodyHealth(player)
            end
            EHR_DiseaseClampBodyHealth(player, disease.toxinHealthCap)

            if EHR_DiseaseCanTriggerSymptom(disease, "toxin_health_damage", 0.35) then
                local damage = 0.45 + (1.10 * severity)
                local newHealth = EHR_DiseaseApplyBodyHealthDamage(
                    player,
                    damage,
                    "Toxin poisoning - untreated poisonous mushroom caused systemic poisoning"
                )

                if newHealth then
                    disease.toxinHealthCap = math.min(disease.toxinHealthCap or 100, newHealth)
                    EHR_DiseaseClampBodyHealth(player, disease.toxinHealthCap)
                end

                if newHealth and newHealth <= 15 and EHR_DiseaseRoll(0.012 * severity) then
                    EHR_DiseaseKillPlayer(
                        player,
                        "Toxin poisoning - severe poisonous mushroom ingestion became fatal"
                    )
                end
            end
        elseif not isMushroom then
            disease.toxinHealthCap = nil
        end

    elseif diseaseId == "trichinosis" then
        -- Parasite infection: muscle pain, feverish fatigue and weakness.
        local curativeTreatment = EHR_DiseaseGetActiveCurativeTreatment(player, "trichinosis")
        local symptomMult = EHR_DiseaseGetActiveSymptomMultiplier(player, "trichinosis", disease)
        local muscleRelief = EHR_DiseaseGetActiveSymptomReduction(player, "trichinosis", "muscleSpasms")
        local painRelief = EHR_DiseaseGetActiveSymptomReduction(player, "trichinosis", "pain")
        local enduranceDrain = 0.002 * severity
        local enduranceFloor = 0.80
        local fatigueTarget = 0.18 * severity
        local feverTarget = 0.18 * severity
        local painTarget = 0.08 * severity
        local strainTarget = math.max(10, 20 * severity)
        local strainStep = 0.25 * severity

        if stage == 2 then
            enduranceDrain = 0.007 * severity
            enduranceFloor = 0.70
            fatigueTarget = 0.35 * severity
            feverTarget = 0.35 * severity
            painTarget = 0.36 * severity
            strainTarget = math.max(25, 45 * severity)
            strainStep = 0.90 * severity
        elseif stage == 3 then
            enduranceDrain = 0.016 * severity
            enduranceFloor = 0.40
            fatigueTarget = 0.72 * severity
            feverTarget = 0.70 * severity
            painTarget = 0.86 * severity
            strainTarget = math.max(55, 90 * severity)
            strainStep = 1.80 * severity
        elseif stage == 4 then
            enduranceDrain = 0.003 * severity
            enduranceFloor = 0.82
            fatigueTarget = 0.22 * severity
            feverTarget = 0.16 * severity
            painTarget = 0.16 * severity
            strainTarget = math.max(8, 20 * severity)
            strainStep = 0.20 * severity
        end

        if symptomMult < 1.0 then
            painTarget = painTarget * symptomMult
            if muscleRelief <= 0 then
                strainTarget = math.max(4, strainTarget * symptomMult)
                strainStep = math.max(0.05, strainStep * symptomMult)
            end
        end

        if muscleRelief > 0 then
            local muscleMult = math.max(0.12, 1 - (muscleRelief * 2.0))
            strainTarget = math.min(4.5, math.max(2, strainTarget * muscleMult))
            strainStep = math.max(0.02, strainStep * 0.10)
        end

        if painRelief > 0 then
            painTarget = painTarget * math.max(0.25, 1 - (painRelief * 1.5))
        end

        EHR_DiseaseDrainEndurance(stats, enduranceDrain, enduranceFloor)
        EHR_DiseaseRaiseStatToward(stats, CharacterStat and CharacterStat.FATIGUE, fatigueTarget, 0.0035 * severity, 1)
        EHR_DiseaseRaiseStatToward(stats, CharacterStat and CharacterStat.SICKNESS, feverTarget, 0.004 * severity, 1)
        EHR_DiseaseRaisePainToward(stats, painTarget, 0.018 * severity)
        EHR_DiseaseApplyMuscleStrain(player, strainTarget, strainStep)
        if muscleRelief > 0 then
            local reliefStep = math.max(1.0, (1.2 + stageMult * 1.8) * (0.5 + severity) * muscleRelief)
            EHR_DiseaseReduceMuscleStrainToward(player, strainTarget, reliefStep)
        end
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.00055 * severity * stageMult)

        local crampChance = (stage == 3 and 0.009 or stage == 2 and 0.003 or 0.0005) * severity
        if muscleRelief > 0 then
            crampChance = crampChance * math.max(0.10, 1 - (muscleRelief * 2.0))
        end
        trySymptom("cramp", crampChance, 0.25, function()
            EHR_DiseaseTriggerCramp(player)
        end)

        if stage >= 2 then
            trySymptom("fever", (stage == 3 and 0.004 or 0.0015) * severity, 0.25, function()
                EHR_DiseaseSay(player, {"I'm burning up...", "This fever is getting bad...", "I'm so weak..."})
            end)
        end

        if curativeTreatment then
            disease.trichinosisHealthCap = nil
        elseif stage == 3 then
            if not disease.trichinosisHealthCap then
                disease.trichinosisHealthCap = EHR_DiseaseGetBodyHealth(player)
            end
            EHR_DiseaseClampBodyHealth(player, disease.trichinosisHealthCap)
        elseif stage ~= 3 then
            disease.trichinosisHealthCap = nil
        end

        if stage == 3 and not curativeTreatment and EHR_DiseaseCanTriggerSymptom(disease, "trichinosis_health_damage", 0.25) then
            local damage = 1.1 + (2.2 * severity)
            local newHealth = EHR_DiseaseApplyBodyHealthDamage(
                player,
                damage,
                "Trichinosis complications - untreated parasitic infection caused fever, weakness, and organ failure"
            )

            if newHealth then
                disease.trichinosisHealthCap = math.min(disease.trichinosisHealthCap or 100, newHealth)
                EHR_DiseaseClampBodyHealth(player, disease.trichinosisHealthCap)
            end

            if newHealth and newHealth <= 20 and EHR_DiseaseRoll(0.02 * severity) then
                EHR_DiseaseKillPlayer(
                    player,
                    "Trichinosis complications - severe untreated parasitic infection became fatal"
                )
            end
        end

    elseif diseaseId == "corpse_sickness" then
        -- Current active corpse illness covers old putrefaction gas symptoms and mild spore irritation.
        local gameTime = getGameTime and getGameTime() or nil
        local currentHour = gameTime and gameTime:getWorldAgeHours() or 0
        local symptomMult = EHR_DiseaseGetActiveSymptomMultiplier(player, "corpse_sickness", disease)
        local nauseaRelief = EHR_DiseaseGetActiveSymptomReduction(player, "corpse_sickness", "nausea")
        if disease.corpseSicknessNauseaReliefUntil and disease.corpseSicknessNauseaReliefUntil > currentHour then
            nauseaRelief = math.max(nauseaRelief, disease.corpseSicknessNauseaRelief or 0)
        elseif disease.corpseSicknessNauseaReliefUntil then
            disease.corpseSicknessNauseaRelief = nil
            disease.corpseSicknessNauseaReliefUntil = nil
        end
        local dizzinessRelief = EHR_DiseaseGetActiveSymptomReduction(player, "corpse_sickness", "dizziness")
        local breathingRelief = EHR_DiseaseGetActiveSymptomReduction(player, "corpse_sickness", "breathingDifficulty")
        local weaknessRelief = EHR_DiseaseGetActiveSymptomReduction(player, "corpse_sickness", "weakness")
        local nauseaMult = math.max(0.12, symptomMult * (1 - nauseaRelief))
        local dizzinessMult = math.max(0.12, symptomMult * (1 - dizzinessRelief))
        local breathingMult = math.max(0.15, symptomMult * (1 - breathingRelief))
        local weaknessMult = math.max(0.18, symptomMult * (1 - weaknessRelief))

        local sicknessTarget = 0.18
        local discomfortTarget = 0.16
        local enduranceDrain = 0.003
        local enduranceFloor = 0.68
        if stage == 2 then
            sicknessTarget = 0.36
            discomfortTarget = 0.32
            enduranceDrain = 0.006
            enduranceFloor = 0.58
        elseif stage == 3 then
            sicknessTarget = 0.58
            discomfortTarget = 0.55
            enduranceDrain = 0.011
            enduranceFloor = 0.42
        elseif stage == 4 then
            sicknessTarget = 0.20
            discomfortTarget = 0.18
            enduranceDrain = 0.002
            enduranceFloor = 0.78
        end

        local treatedSicknessTarget = sicknessTarget * nauseaMult
        if nauseaRelief > 0 then
            local nauseaFloor = stage == 3 and 0.36 or stage == 2 and 0.20 or stage == 4 and 0.12 or 0.10
            treatedSicknessTarget = math.max(nauseaFloor, treatedSicknessTarget)
        end

        if nauseaRelief > 0 then
            disease.corpseSicknessSymptomTarget = treatedSicknessTarget
            disease.corpseSicknessSymptomTargetUntil = currentHour + 0.25
        else
            disease.corpseSicknessSymptomTarget = nil
            disease.corpseSicknessSymptomTargetUntil = nil
        end

        EHR_DiseaseDrainEndurance(stats, enduranceDrain * severity * weaknessMult, enduranceFloor)
        EHR_DiseaseRaiseStatToward(stats, CharacterStat and CharacterStat.SICKNESS, treatedSicknessTarget, 0.0035 * severity, 1)
        if nauseaRelief > 0 then
            EHR_DiseaseLowerStatToward(stats, CharacterStat and CharacterStat.SICKNESS, treatedSicknessTarget, (0.006 + 0.010 * nauseaRelief) * severity, 0)
            EHR_DiseaseClampSicknessStat(stats, treatedSicknessTarget + 0.015)
        end
        EHR_DiseaseRaiseStatToward(stats, CharacterStat and CharacterStat.DISCOMFORT, discomfortTarget * breathingMult, 0.003 * severity, 1)
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.PAIN, 0.0010 * severity * stageMult * breathingMult)
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.PANIC, 0.0008 * severity * stageMult * dizzinessMult)
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.THIRST, 0.00045 * severity * stageMult)

        local dizzyChance = (stage == 3 and 0.018 or stage == 2 and 0.007 or 0.0012) * severity * dizzinessMult
        trySymptom("dizzy", dizzyChance, 0.18, function()
            EHR_DiseaseTriggerDizziness(player)
        end)

        local coughChance = (stage == 3 and 0.007 or stage == 2 and 0.0025 or 0.0005) * severity * breathingMult
        trySymptom("cough", coughChance, 0.16, function()
            EHR_DiseaseTriggerCough(player, stage == 3)
        end)

        if stage == 2 then
            trySymptom("eye_irritation", 0.006 * severity * breathingMult, 0.22, function()
                EHR_DiseaseSay(player, {"My eyes are burning...", "My eyes sting...", "Need fresh air..."})
            end)
        elseif stage == 3 then
            trySymptom("eye_irritation", 0.008 * severity * breathingMult, 0.22, function()
                EHR_DiseaseSay(player, {"My eyes are burning...", "My eyes sting...", "Need fresh air..."})
            end)
            trySymptom("collapse", 0.004 * severity * weaknessMult, 0.50, function()
                EHR_DiseaseTriggerCollapse(player)
            end)
        end

    elseif diseaseId == "tuberculosis" then
        EHR_DiseaseDrainEndurance(stats, 0.0015 * severity * stageMult, 0.35)
        EHR_DiseaseAddStat(stats, CharacterStat and CharacterStat.FATIGUE, 0.0006 * severity * stageMult)

        local coughChance = (stage == 3 and 0.006 or stage == 2 and 0.003 or 0.001) * severity
        trySymptom("tb_cough", coughChance, 0.12, function()
            EHR_DiseaseTriggerCough(player, stage == 3)
        end)
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

local function EHR_DiseaseEnforceHealthCaps(player, modData)
    if not player or not modData or not modData.EHR_Disease or not modData.EHR_Disease.active then return end

    local trichinosis = modData.EHR_Disease.active.trichinosis
    if not trichinosis then return end

    if EHR_DiseaseGetActiveCurativeTreatment(player, "trichinosis") then
        trichinosis.trichinosisHealthCap = nil
        return
    end

    if trichinosis.stage == 3 and trichinosis.trichinosisHealthCap then
        EHR_DiseaseClampBodyHealth(player, trichinosis.trichinosisHealthCap)
    elseif trichinosis.stage ~= 3 then
        trichinosis.trichinosisHealthCap = nil
    end
end

-- ============================================
-- FOOD TRANSMISSION HOOK
-- ============================================

function EHR.Disease.ClearFoodRiskHistory(history)
    if not history then return end

    history.lastBadFood = nil
    history.lastFoodRiskReason = nil
    history.lastFoodRiskChance = nil
    history.lastFoodAccumulatedRisk = nil
    history.lastFoodRiskDiseaseId = nil
    history.foodRiskAccumulated = nil
    history.foodRiskLastTime = nil
    history.foodRiskAccumulatedByDisease = nil
    history.foodRiskLastTimeByDisease = nil
end

function EHR.Disease.GetFoodRiskMemory(player)
    if not player then return nil end

    local id = getPlayerId(player) or "0"
    EHR.Disease.FoodRiskMemory = EHR.Disease.FoodRiskMemory or {}

    local memory = EHR.Disease.FoodRiskMemory[id]
    if not memory then
        memory = {
            accumulatedByDisease = {},
            lastTimeByDisease = {},
        }
        EHR.Disease.FoodRiskMemory[id] = memory
    end

    memory.accumulatedByDisease = memory.accumulatedByDisease or {}
    memory.lastTimeByDisease = memory.lastTimeByDisease or {}
    return memory
end

function EHR.Disease.ClearFoodRiskMemory(player, diseaseId)
    local memory = EHR.Disease.GetFoodRiskMemory(player)
    if not memory then return end

    if diseaseId then
        if memory.accumulatedByDisease then
            memory.accumulatedByDisease[diseaseId] = nil
        end
        if memory.lastTimeByDisease then
            memory.lastTimeByDisease[diseaseId] = nil
        end
        if memory.lastDiseaseId == diseaseId then
            memory.accumulated = nil
            memory.lastTime = nil
            memory.lastReason = nil
            memory.lastChance = nil
            memory.lastDiseaseId = nil
            memory.lastBadFood = nil
        end
        return
    end

    memory.accumulatedByDisease = {}
    memory.lastTimeByDisease = {}
    memory.accumulated = nil
    memory.lastTime = nil
    memory.lastReason = nil
    memory.lastChance = nil
    memory.lastDiseaseId = nil
    memory.lastBadFood = nil
end

function EHR.Disease.ClearAccumulatedFoodRisk(history, diseaseId)
    if not history then return end

    if diseaseId and history.foodRiskAccumulatedByDisease then
        history.foodRiskAccumulatedByDisease[diseaseId] = nil
    end
    if diseaseId and history.foodRiskLastTimeByDisease then
        history.foodRiskLastTimeByDisease[diseaseId] = nil
    end

    if not diseaseId or history.lastFoodRiskDiseaseId == diseaseId then
        history.foodRiskAccumulated = nil
        history.foodRiskLastTime = nil
        history.lastFoodAccumulatedRisk = nil
    end
end

function EHR.Disease.GetAccumulatedFoodRisk(player, addedRisk, riskReason, diseaseId)
    local data = EHR.Disease.GetDiseaseData(player)
    local history = data and data.history
    local memory = EHR.Disease.GetFoodRiskMemory(player)
    if not history and not memory then return addedRisk or 0 end

    diseaseId = diseaseId or "food_poisoning"
    local cfg = EHR.Disease.FoodRiskAccumulation or {}
    local now = getGameTime():getWorldAgeHours()
    if history then
        history.foodRiskAccumulatedByDisease = history.foodRiskAccumulatedByDisease or {}
        history.foodRiskLastTimeByDisease = history.foodRiskLastTimeByDisease or {}
    end

    local previous = memory and memory.accumulatedByDisease and memory.accumulatedByDisease[diseaseId] or nil
    if previous == nil and memory and memory.lastDiseaseId == diseaseId then
        previous = memory.accumulated
    end
    if previous == nil and history then
        previous = history.foodRiskAccumulatedByDisease[diseaseId]
        if previous == nil and history.lastFoodRiskDiseaseId == diseaseId then
            previous = history.foodRiskAccumulated
        end
    end
    previous = previous or 0

    local lastTime = memory and memory.lastTimeByDisease and memory.lastTimeByDisease[diseaseId] or nil
    if lastTime == nil and memory and memory.lastDiseaseId == diseaseId then
        lastTime = memory.lastTime
    end
    if lastTime == nil and history then
        lastTime = history.foodRiskLastTimeByDisease[diseaseId]
        if lastTime == nil and history.lastFoodRiskDiseaseId == diseaseId then
            lastTime = history.foodRiskLastTime
        end
    end
    lastTime = lastTime or now

    local elapsed = math.max(0, now - lastTime)
    local decayed = math.max(0, previous - ((cfg.decayPerHour or 0.20) * elapsed))
    local accumulated = math.min(1.0, decayed + (addedRisk or 0))

    if memory then
        memory.accumulatedByDisease[diseaseId] = accumulated
        memory.lastTimeByDisease[diseaseId] = now
        memory.accumulated = accumulated
        memory.lastTime = now
        memory.lastDiseaseId = diseaseId
        memory.lastReason = riskReason or memory.lastReason
        memory.lastChance = addedRisk or memory.lastChance
        memory.lastBadFood = now
    end

    if history then
        history.foodRiskAccumulatedByDisease[diseaseId] = accumulated
        history.foodRiskLastTimeByDisease[diseaseId] = now
        history.foodRiskAccumulated = accumulated
        history.foodRiskLastTime = now
        history.lastFoodRiskDiseaseId = diseaseId
        history.lastFoodRiskReason = riskReason or history.lastFoodRiskReason
        history.lastFoodRiskChance = addedRisk or history.lastFoodRiskChance
        history.lastFoodAccumulatedRisk = accumulated
    end

    return accumulated
end

function EHR.Disease.GetPendingFoodRiskSickness(player)
    local data = EHR.Disease.GetDiseaseData(player)
    local history = data and data.history
    local memory = EHR.Disease.GetFoodRiskMemory(player)
    local lastBadFood = (history and history.lastBadFood) or (memory and memory.lastBadFood)
    if not lastBadFood then return 0 end
    if data and data.active then
        for activeId, _ in pairs(data.active) do
            local def = EHR.Disease.Diseases[activeId]
            if activeId == "food_poisoning" or (def and def.category == "food") then
                return 0
            end
        end
    end

    local cfg = EHR.Disease.FoodRiskAccumulation or {}
    local now = getGameTime():getWorldAgeHours()
    local diseaseId = (memory and memory.lastDiseaseId)
        or (history and history.lastFoodRiskDiseaseId)
        or "food_poisoning"
    local memoryAccumulatedByDisease = (memory and memory.accumulatedByDisease) or {}
    local memoryLastTimeByDisease = (memory and memory.lastTimeByDisease) or {}
    local historyAccumulatedByDisease = (history and history.foodRiskAccumulatedByDisease) or {}
    local historyLastTimeByDisease = (history and history.foodRiskLastTimeByDisease) or {}
    local lastTime = memoryLastTimeByDisease[diseaseId]
        or (memory and memory.lastTime)
        or historyLastTimeByDisease[diseaseId]
        or (history and history.foodRiskLastTime)
        or lastBadFood
    local elapsed = math.max(0, now - lastTime)
    local previous = memoryAccumulatedByDisease[diseaseId]
        or (memory and memory.accumulated)
        or historyAccumulatedByDisease[diseaseId]
        or (history and history.foodRiskAccumulated)
        or 0
    local accumulated = math.max(0, previous - ((cfg.decayPerHour or 0.20) * elapsed))

    if accumulated <= 0 then
        if history then
            EHR.Disease.ClearAccumulatedFoodRisk(history, diseaseId)
        end
        EHR.Disease.ClearFoodRiskMemory(player, diseaseId)
        return 0
    end

    if memory then
        memory.accumulatedByDisease[diseaseId] = accumulated
        memory.lastDiseaseId = diseaseId
        memory.accumulated = accumulated
    end
    if history and history.foodRiskAccumulatedByDisease then
        history.foodRiskAccumulatedByDisease[diseaseId] = accumulated
    end
    if history then
        history.lastFoodAccumulatedRisk = accumulated
    end
    return math.min(cfg.pendingSicknessMax or 24, accumulated * (cfg.pendingSicknessScale or 45))
end

function EHR.Disease.GetPoisonSeverity(poisonPower, toxinType)
    local power = math.max(0, tonumber(poisonPower) or 0)
    local powerBonus = math.min(0.30, power * 0.08)
    local severity = 0.55 + powerBonus

    if toxinType == "mushroom" then
        severity = 0.72 + math.min(0.28, power * 0.08)
    elseif toxinType == "berry" then
        severity = 0.38 + math.min(0.22, power * 0.06)
    end

    return math.max(0.25, math.min(1.0, severity))
end

function EHR.Disease.ApplyVanillaPoisonDisease(player, itemName, poisonPower, toxinType)
    if not player then return end
    toxinType = toxinType or "toxin"

    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return end

    local now = getGameTime():getWorldAgeHours()
    local severity = EHR.Disease.GetPoisonSeverity(poisonPower, toxinType)
    local active = data.active["toxin_poisoning"]
    if not active then
        EHR.Disease.Contract(player, "toxin_poisoning")
        data = EHR.Disease.GetDiseaseData(player)
        active = data and data.active and data.active["toxin_poisoning"]
    end

    if not active then return end

    local function rand(max)
        if ZombRand and max and max > 0 then return ZombRand(max) end
        return 0
    end

    active.severity = math.max(active.severity or 0, severity)
    active.toxinType = toxinType
    active.toxinSource = itemName or active.toxinSource or "unknown"
    active.poisonPower = math.max(active.poisonPower or 0, tonumber(poisonPower) or 0)

    local incubationHours = toxinType == "mushroom" and (2 + rand(4)) or (1 + rand(2))
    local durationHours = 36 + rand(25)
    if toxinType == "mushroom" then
        durationHours = 72 + rand(49)
    elseif toxinType == "berry" then
        durationHours = 24 + rand(25)
    end

    active.startTime = math.min(active.startTime or now, now)
    active.incubationEnd = math.min(active.incubationEnd or (now + incubationHours), now + incubationHours)
    active.endTime = math.max(active.endTime or (now + durationHours), now + durationHours)
    active.peakTime = math.min(active.peakTime or (now + incubationHours + (durationHours * 0.30)),
        now + incubationHours + (durationHours * 0.30))

    if EHR.DEBUG then
        EHR.Log(string.format("Applied toxin poisoning from %s (%s, power=%.2f, severity=%.2f)",
            itemName or "unknown", toxinType, tonumber(poisonPower) or 0, active.severity or severity))
    end
end

function EHR.Disease.ClearVanillaPoison(player)
    local data = EHR.Disease.GetDiseaseData(player)
    if data and data.history then
        data.history.vanillaPoison = nil
        data.history.suppressExternalFoodSicknessUntil = getGameTime():getWorldAgeHours() + 24
    end

    local stats = player and player:getStats() or nil
    if stats and CharacterStat and CharacterStat.POISON then
        pcall(function() stats:set(CharacterStat.POISON, 0) end)
    end

    if player and player.transmitModData then
        pcall(function() player:transmitModData() end)
    end
end

function EHR.Disease.ShouldSuppressExternalFoodSickness(player)
    local data = EHR.Disease.GetDiseaseData(player)
    local history = data and data.history
    if not history then return false end
    if history.vanillaPoison then return false end

    local suppressUntil = tonumber(history.suppressExternalFoodSicknessUntil)
    if not suppressUntil then return false end

    local now = getGameTime():getWorldAgeHours()
    if now > suppressUntil then
        history.suppressExternalFoodSicknessUntil = nil
        return false
    end

    local active = data and data.active or {}
    if active["corpse_sickness"] then return false end

    local modData = player and player:getModData() or nil
    local corpseData = modData and modData.EHR_CorpseSickness
    if corpseData and (corpseData.currentExposure or 0) > 0.01 then return false end

    return true
end

function EHR.Disease.MarkVanillaPoisonFood(player, itemName, poisonPower, poisonDetectionLevel, toxinType)
    local data = EHR.Disease.GetDiseaseData(player)
    local history = data and data.history
    if not history then return end

    local now = getGameTime():getWorldAgeHours()
    history.suppressExternalFoodSicknessUntil = nil
    history.vanillaPoison = {
        source = itemName or "unknown",
        poisonPower = poisonPower or 0,
        poisonDetectionLevel = poisonDetectionLevel or 0,
        toxinType = toxinType or "toxin",
        startTime = now,
        graceUntil = now + 24,
    }

    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end

    if EHR.DEBUG then
        EHR.Log(string.format("Vanilla poison food consumed: %s (power=%.2f, detect=%s)",
            itemName or "unknown", poisonPower or 0, tostring(poisonDetectionLevel)))
    end
end

function EHR.Disease.ShouldPreserveVanillaPoison(player, currentPoison)
    local data = EHR.Disease.GetDiseaseData(player)
    local history = data and data.history
    local poisonData = history and history.vanillaPoison
    if not poisonData then return false end

    local now = getGameTime():getWorldAgeHours()
    local poisonLevel = currentPoison or 0

    if EHR_DiseaseGetActiveCurativeTreatment(player, "toxin_poisoning") then
        poisonData.absorbedByTreatment = true
        poisonData.graceUntil = now
        return false
    end

    if poisonLevel > 0.01 then
        poisonData.lastPoisonTime = now
        poisonData.graceUntil = now + 12
        return true
    end

    if now <= (poisonData.graceUntil or 0) then
        return true
    end

    history.vanillaPoison = nil
    return false
end

local function EHR_DiseaseSafeItemMethod(target, methodName)
    if not target or not methodName or not target[methodName] then return nil end

    local ok, result = pcall(function()
        return target[methodName](target)
    end)

    if ok then return result end
    return nil
end

local function EHR_DiseaseGetScriptItemFlag(item, methodNames)
    local scriptItem = EHR_DiseaseSafeItemMethod(item, "getScriptItem")
    if not scriptItem then return false end

    for _, methodName in ipairs(methodNames) do
        local value = EHR_DiseaseSafeItemMethod(scriptItem, methodName)
        if value ~= nil then return value == true end
    end

    return false
end

local function EHR_DiseaseGetItemFlag(item, methodNames)
    for _, methodName in ipairs(methodNames) do
        local value = EHR_DiseaseSafeItemMethod(item, methodName)
        if value ~= nil then return value == true end
    end

    return EHR_DiseaseGetScriptItemFlag(item, methodNames)
end

function EHR.Disease.GetTrichinosisRisk(item, isCooked, nameLower, isBurnt)
    if not item or isCooked == true or isBurnt == true then return 0, nil end

    if EHR.Food and EHR.Food.CheckTrichinosisRisk then
        local ok, risk = pcall(function() return EHR.Food.CheckTrichinosisRisk(item) end)
        if ok and risk and risk > 0 then
            return risk, "uncooked wild game"
        end
    end

    nameLower = nameLower or ""
    local foodTypeLower = string.lower(tostring(EHR_DiseaseSafeItemMethod(item, "getFoodType") or EHR_DiseaseSafeItemMethod(item, "getEatType") or ""))
    local dangerousUncooked = EHR_DiseaseGetItemFlag(item, {"isDangerousUncooked", "getDangerousUncooked"})

    local cookedPatterns = {"cooked", "grilled", "roasted", "fried", "boiled", "burnt", "burned", "charred"}
    for _, pattern in ipairs(cookedPatterns) do
        if string.find(nameLower, pattern) then
            return 0, nil
        end
    end

    local highRiskPatterns = {
        "dead rat", "deadrat", "rat meat", "ratmeat", " rat", "rat ", "^rat$",
        "dead mouse", "deadmouse", "mouse meat", "mousemeat", " mouse", "mouse ", "^mouse$",
        "rodent meat", "rodentmeat", "small animal meat", "smallanimalmeat", "small animal", "smallanimal",
        "wild boar", "boar meat", "boarmeat", "bear meat", "bearmeat",
    }
    for _, pattern in ipairs(highRiskPatterns) do
        if string.find(nameLower, pattern) then
            return EHR.Disease.FoodRisks.rawWildGameHigh or 0.40, "uncooked wild game"
        end
    end

    local mediumRiskPatterns = {
        "fox meat", "foxmeat", "raccoon meat", "raccoonmeat", "wolf meat", "wolfmeat",
        "dead rabbit", "deadrabbit", "rabbit meat", "rabbitmeat", " rabbit", "rabbit ", "^rabbit$",
        "squirrel meat", "squirrelmeat", "dead squirrel", "deadsquirrel",
        "frog meat", "frogmeat", " frog", "frog ", "^frog$",
        "small bird meat", "smallbirdmeat", "small bird", "smallbird", "bird meat",
        "venison", "deer meat", "deermeat",
    }
    for _, pattern in ipairs(mediumRiskPatterns) do
        if string.find(nameLower, pattern) then
            return EHR.Disease.FoodRisks.rawWildGameMedium or 0.25, "uncooked wild game"
        end
    end

    if foodTypeLower == "game" then
        return EHR.Disease.FoodRisks.rawWildGameMedium or 0.25, "uncooked wild game"
    end

    local lowRiskPatterns = {
        "chicken leg", "chicken wing", "chicken", "turkey",
        "pork chop", "porkchop", "pork", "bacon",
        "steak", "beef", "mutton", "lamb",
    }
    for _, pattern in ipairs(lowRiskPatterns) do
        if string.find(nameLower, pattern) then
            return EHR.Disease.FoodRisks.rawMeatLow or 0.15, "uncooked meat"
        end
    end

    local dangerousMeatTypes = {
        poultry = true,
        pork = true,
        beef = true,
        bacon = true,
        mutton = true,
        lamb = true,
        meat = true,
    }
    if dangerousUncooked and dangerousMeatTypes[foodTypeLower] then
        return EHR.Disease.FoodRisks.rawMeatLow or 0.15, "uncooked meat"
    end

    return 0, nil
end

function EHR.Disease.GetGastroenteritisRisk(player)
    if not player then return 0, nil end

    local risk = 0
    local hasBlood = false
    local hasDirt = false

    if EHR.Food and EHR.Food.GetContaminationRisk then
        local ok, handRisk = pcall(function() return EHR.Food.GetContaminationRisk(player) end)
        if ok and handRisk and handRisk > risk then
            risk = handRisk
        end
    end

    local okVisual, visual = pcall(function()
        if player.getHumanVisual then
            return player:getHumanVisual()
        end
        return nil
    end)

    if okVisual and visual and BloodBodyPartType and BloodBodyPartType.MAX and BloodBodyPartType.FromIndex then
        local bloodLevel = 0
        local dirtLevel = 0
        local handParts = 0

        for i = 1, BloodBodyPartType.MAX:index() do
            local part = BloodBodyPartType.FromIndex(i - 1)
            local partName = string.lower(tostring(part))
            if string.find(partName, "hand") then
                handParts = handParts + 1
                local okBlood, blood = pcall(function() return visual:getBlood(part) end)
                local okDirt, dirt = pcall(function() return visual:getDirt(part) end)
                bloodLevel = bloodLevel + (okBlood and blood or 0)
                dirtLevel = dirtLevel + (okDirt and dirt or 0)
            end
        end

        if handParts > 0 then
            bloodLevel = math.min(1, bloodLevel / handParts)
            dirtLevel = math.min(1, dirtLevel / handParts)
            hasBlood = bloodLevel > 0.10
            hasDirt = dirtLevel > 0.10
            risk = math.max(risk, (bloodLevel * 0.15) + (dirtLevel * 0.08))
        end
    end

    if risk <= 0.05 then return 0, nil end
    if hasBlood and hasDirt then return math.min(1, risk), "bloody and dirty hands" end
    if hasBlood then return math.min(1, risk), "bloody hands" end
    if hasDirt then return math.min(1, risk), "dirty hands" end
    return math.min(1, risk), "contaminated hands"
end

function EHR.Disease.ApplyFoodDiseaseRisk(player, itemName, diseaseId, riskReason, risk)
    if not player or not diseaseId or not risk or risk <= 0 then return false end

    local diseaseData = EHR.Disease.GetDiseaseData(player)
    local now = getGameTime():getWorldAgeHours()
    if diseaseData and diseaseData.history then
        diseaseData.history.lastBadFood = now
        diseaseData.history.lastFoodRiskReason = riskReason
        diseaseData.history.lastFoodRiskChance = risk
        diseaseData.history.lastFoodRiskDiseaseId = diseaseId
    end

    local def = EHR.Disease.Diseases[diseaseId]
    local diseaseName = (def and def.name) or diseaseId

    if diseaseData and diseaseData.active and diseaseData.active[diseaseId] then
        EHR.Log(string.format("Risky food consumed: %s (%s -> %s) - %.0f%% base risk (already active)",
            itemName or "unknown", riskReason or "unknown", diseaseName, risk * 100))
        return false
    end

    local accumulatedRisk = EHR.Disease.GetAccumulatedFoodRisk(player, risk, riskReason, diseaseId)
    local cfg = EHR.Disease.FoodRiskAccumulation or {}
    local contractChance = math.min(cfg.maxChance or 0.95, accumulatedRisk)
    local contracted = false

    EHR.Log(string.format("Risky food consumed: %s (%s -> %s) - %.0f%% base risk, %.0f%% accumulated risk",
        itemName or "unknown", riskReason or "unknown", diseaseName, risk * 100, contractChance * 100))

    if accumulatedRisk >= (cfg.guaranteedThreshold or 0.80) then
        EHR.Disease.Contract(player, diseaseId)
        diseaseData = EHR.Disease.GetDiseaseData(player)
        contracted = diseaseData and diseaseData.active and diseaseData.active[diseaseId] ~= nil
    else
        contracted = EHR.Disease.TryContract(player, diseaseId, contractChance)
    end

    if contracted then
        diseaseData = EHR.Disease.GetDiseaseData(player)
        if diseaseData and diseaseData.history then
            EHR.Disease.ClearAccumulatedFoodRisk(diseaseData.history, diseaseId)
        end
        EHR.Disease.ClearFoodRiskMemory(player, diseaseId)
    end

    return contracted
end

--[[
    Check food item for disease risk
    Called when player eats food

    B42 API Note: Many item methods changed, using pcall for safety
]]--
function EHR.Disease.CheckFoodRisk(player, item)
    if not player or not item then return end

    -- Ensure disease data is initialized before checking
    EHR.Disease.InitializePlayer(player)

    local risks = {}

    local function addRisk(diseaseId, riskReason, chance)
        if diseaseId and riskReason and chance and chance > 0 then
            table.insert(risks, {
                diseaseId = diseaseId,
                reason = riskReason,
                chance = chance,
            })
        end
    end

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
    local itemName = safeCall("getDisplayName") or safeCall("getName") or "unknown"
    local itemFullType = safeCall("getFullType") or ""
    local foodType = safeCall("getFoodType") or safeCall("getEatType") or ""
    local herbalistType = safeCall("getHerbalistType") or ""
    local nameLower = string.lower(itemName .. " " .. itemFullType .. " " .. tostring(foodType) .. " " .. tostring(herbalistType))
    local poisonPower = tonumber(safeCall("getPoisonPower")) or 0
    local poisonDetectionLevel = tonumber(safeCall("getPoisonDetectionLevel")) or 0

    if poisonPower > 0 then
        local toxinType = "toxin"
        local herbalistLower = string.lower(tostring(herbalistType or ""))
        if herbalistLower == "mushroom" or string.find(nameLower, "mushroom", 1, true) then
            toxinType = "mushroom"
        elseif herbalistLower == "berry" or string.find(nameLower, "berry", 1, true) or string.find(nameLower, "berries", 1, true) then
            toxinType = "berry"
        end

        EHR.Disease.MarkVanillaPoisonFood(player, itemName, poisonPower, poisonDetectionLevel, toxinType)
        EHR.Disease.ApplyVanillaPoisonDisease(player, itemName, poisonPower, toxinType)
    end

    -- B42 alternative: check if item has "Rotten" in name or category
    if isRotten == nil then
        local name = safeCall("getDisplayName") or safeCall("getName") or ""
        if string.find(string.lower(name), "rotten") then
            isRotten = true
        end
    end

    -- Determine risk
    if isRotten == true then
        addRisk("food_poisoning", "rotten", EHR.Disease.FoodRisks.rotten)
    elseif isBurnt == true then
        addRisk("food_poisoning", "burned", EHR.Disease.FoodRisks.burned)
    end

    -- Raw or undercooked meat causes trichinosis risk, not generic food poisoning.
    local trichinosisRisk, trichinosisReason = EHR.Disease.GetTrichinosisRisk(item, isCooked, nameLower, isBurnt)
    if trichinosisRisk > 0 then
        addRisk("trichinosis", trichinosisReason, trichinosisRisk)
    end

    -- DangerousUncooked non-meat food causes food poisoning. Meat/game is handled above.
    local dangerousUncooked = EHR_DiseaseGetItemFlag(item, {"isDangerousUncooked", "getDangerousUncooked"})
    if trichinosisRisk <= 0
        and dangerousUncooked == true
        and isRotten ~= true
        and isBurnt ~= true
        and isCooked ~= true then
        addRisk("food_poisoning", "dangerous uncooked", EHR.Disease.FoodRisks.dangerousUncooked)
    end

    -- Stale food check (age-based, with B42 freshness fallback)
    if isRotten ~= true and isBurnt ~= true and age and offAge then
        if age > offAge * 0.8 then  -- More than 80% to spoilage
            addRisk("food_poisoning", "stale", EHR.Disease.FoodRisks.stale)
        end
    elseif isRotten ~= true and isBurnt ~= true and isFresh == false then
        addRisk("food_poisoning", "stale", EHR.Disease.FoodRisks.stale)
    end

    local gastroRisk, gastroReason = EHR.Disease.GetGastroenteritisRisk(player)
    if gastroRisk > 0 then
        addRisk("gastroenteritis", gastroReason, gastroRisk)
    end

    -- Debug: Log what we found
    if EHR.DEBUG then
        EHR.Log(string.format("CheckFoodRisk: rotten=%s, burnt=%s, cooked=%s, age=%.2f/%.2f",
            tostring(isRotten), tostring(isBurnt), tostring(isCooked),
            age or 0, offAge or 0))
    end

    for _, foodRisk in ipairs(risks) do
        EHR.Disease.ApplyFoodDiseaseRisk(
            player,
            itemName,
            foodRisk.diseaseId,
            foodRisk.reason,
            foodRisk.chance
        )
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

        if diseaseId == "toxin_poisoning" and EHR.Disease.ClearVanillaPoison then

            EHR.Disease.ClearVanillaPoison(player)

        end

        if diseaseId == "corpse_sickness" and EHR.CorpseSickness and EHR.CorpseSickness.ResetAfterCure then

            EHR.CorpseSickness.ResetAfterCure(player)

        else
            local def = EHR.Disease.Diseases[diseaseId]
            if def and def.category == "food" and EHR.Disease.ResetFoodSicknessAfterCure then

                EHR.Disease.ResetFoodSicknessAfterCure(player, diseaseId)

            end
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
    local curedToxinPoisoning = false

    for diseaseId, _ in pairs(data.active) do

        if diseaseId == "toxin_poisoning" then

            curedToxinPoisoning = true

        end

        if diseaseId == "corpse_sickness" then

            curedCorpseSickness = true

        else
            local def = EHR.Disease.Diseases[diseaseId]
            if def and def.category == "food" then

                curedFoodSickness = true

            end

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

    if curedToxinPoisoning and EHR.Disease.ClearVanillaPoison then

        EHR.Disease.ClearVanillaPoison(player)

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

local function EHR_DiseaseGetGastroSicknessFloor(player, ignoreDiseaseId)
    if not player or ignoreDiseaseId == "gastroenteritis" then return nil end

    local data = EHR.Disease.GetDiseaseData(player)
    local disease = data and data.active and data.active["gastroenteritis"]
    if not disease then return nil end

    local stage = disease.stage or 0
    local floor = nil
    if stage == 2 then floor = 31 end -- Stay clearly above Queasy threshold.
    if stage == 3 then floor = 56 end -- Stay clearly above Nauseous threshold.
    if stage == 4 then floor = 18 end -- Recovery fades below Queasy.

    if not floor then return nil end

    local nauseaRelief = EHR_DiseaseGetActiveSymptomReduction(player, "gastroenteritis", "nausea")
    local sicknessRelief = EHR_DiseaseGetActiveSymptomReduction(player, "gastroenteritis", "sickness")
    local targetedRelief = math.max(nauseaRelief * 0.65, sicknessRelief)
    if targetedRelief > 0 then
        local minimumFloor = stage == 3 and 35 or 12
        floor = math.max(minimumFloor, floor * math.max(0.50, 1 - targetedRelief))
    end

    return floor
end

--[[
    Get what vanilla sickness level should be based on our disease state
]]--
function EHR.Disease.GetTargetVanillaSickness(player, ignoreDiseaseId)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data or not data.active then return 0 end

    -- Find the worst active food-related disease
    local worstStage = 0
    local worstSeverity = 0
    local worstDiseaseId = nil
    local worstDisease = nil

    for diseaseId, disease in pairs(data.active) do
        local def = EHR.Disease.Diseases[diseaseId]
        local isFoodDisease = diseaseId == "food_poisoning" or (def and def.category == "food")
        if isFoodDisease and diseaseId ~= ignoreDiseaseId then
            if disease.stage > worstStage then
                worstStage = disease.stage
                worstSeverity = disease.severity or 0.5
                worstDiseaseId = diseaseId
                worstDisease = disease
            end
        end
    end

    if worstStage == 0 then
        if ignoreDiseaseId ~= "food_poisoning" and EHR.Disease.GetPendingFoodRiskSickness then
            return EHR.Disease.GetPendingFoodRiskSickness(player)
        end
        return 0
    end

    -- Get base level for this stage
    local baseLevel = EHR.Disease.VanillaSicknessLevels[worstStage] or 0

    -- Adjust by severity (0.5 severity = base, 1.0 = +50%, 0.0 = -50%)
    local adjustedLevel = baseLevel * (0.5 + worstSeverity)
    if worstDiseaseId and worstDisease then
        adjustedLevel = adjustedLevel * EHR_DiseaseGetActiveSymptomMultiplier(player, worstDiseaseId, worstDisease)
        local nauseaRelief = EHR_DiseaseGetActiveSymptomReduction(player, worstDiseaseId, "nausea")
        local sicknessRelief = EHR_DiseaseGetActiveSymptomReduction(player, worstDiseaseId, "sickness")
        local targetedRelief = math.max(nauseaRelief * 0.75, sicknessRelief)
        if targetedRelief > 0 then
            adjustedLevel = adjustedLevel * math.max(0.45, 1 - targetedRelief)
        end
    end

    if worstDiseaseId == "toxin_poisoning" and EHR_DiseaseGetActiveCurativeTreatment(player, "toxin_poisoning") then
        adjustedLevel = adjustedLevel * 0.45
    end

    if worstDiseaseId == "gastroenteritis" then
        local gastroFloor = EHR_DiseaseGetGastroSicknessFloor(player, ignoreDiseaseId)
        if gastroFloor then
            adjustedLevel = math.max(adjustedLevel, gastroFloor)
        end
    end

    -- Cap at safe level
    return math.min(adjustedLevel, EHR.Disease.VANILLA_SICKNESS_CAP)
end

function EHR.Disease.ResetFoodSicknessAfterCure(player, curedDiseaseId)
    if not player then return end

    local data = EHR.Disease.GetDiseaseData(player)
    if data and data.history then
        EHR.Disease.ClearFoodRiskHistory(data.history)
        data.history.lastFoodCuredTime = getGameTime():getWorldAgeHours()
    end
    EHR.Disease.ClearFoodRiskMemory(player, curedDiseaseId)

    local stats = player:getStats()
    if not stats or not CharacterStat then return end

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
        local currentPoison = 0
        local ok, value = pcall(function() return stats:get(CharacterStat.POISON) end)
        if ok and value then currentPoison = value end
        if not EHR.Disease.ShouldPreserveVanillaPoison(player, currentPoison) then
            pcall(function() stats:set(CharacterStat.POISON, 0) end)
        end
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

    -- CRITICAL: Suppress POISON IMMEDIATELY on every call unless it is a real
    -- vanilla poisonous item (berries/mushrooms/tainted food with PoisonPower).
    -- Raw food can still spike POISON to 14+ and cause frame-perfect deaths.
    if CharacterStat and CharacterStat.POISON then
        local success, poisonVal = pcall(function() return stats:get(CharacterStat.POISON) end)
        if success and poisonVal and poisonVal > 0.05 then
            if EHR.Disease.ShouldPreserveVanillaPoison(player, poisonVal) then
                if EHR.DEBUG then
                    EHR.Log(string.format("SyncVanilla: Preserving vanilla POISON %.3f", poisonVal))
                end
                return
            end
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

    local corpseShouldSuppressFood = EHR.CorpseSickness
            and EHR.CorpseSickness.ShouldSuppressFoodSickness
            and EHR.CorpseSickness.ShouldSuppressFoodSickness(player)

    local activeCorpseIllness = false
    local activeCorpseDisease = nil
    local diseaseData = EHR.Disease.GetDiseaseData(player)
    if diseaseData and diseaseData.active and diseaseData.active.corpse_sickness then
        activeCorpseIllness = true
        activeCorpseDisease = diseaseData.active.corpse_sickness
    end

    local corpseSicknessSignal = false
    if EHR.CorpseSickness then
        local modData = player:getModData()
        local corpseData = modData and modData.EHR_CorpseSickness
        if corpseData then
            local currentHour = getGameTime():getWorldAgeHours()
            corpseSicknessSignal = (corpseData.currentExposure or 0) > 0
                    or (corpseData.vanillaCorpseExposure or 0) > 0
                    or (corpseData.suppressFoodSicknessUntil or 0) > currentHour
        end
    end

    -- Corpse exposure owns CharacterStat.SICKNESS directly. If no food disease is
    -- active, keep the food component suppressed without zeroing the corpse moodle.
    if targetLevel == 0 and (activeCorpseIllness or corpseShouldSuppressFood or (corpseSicknessSignal and currentVanilla <= 0.01)) then
        if CharacterStat.FOOD_SICKNESS then
            pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0) end)
        end
        if EHR.CorpseSickness and EHR.CorpseSickness.SuppressFoodSicknessComponent then
            EHR.CorpseSickness.SuppressFoodSicknessComponent(player)
        end
        if activeCorpseIllness and activeCorpseDisease and CharacterStat.SICKNESS then
            local symptomTarget = activeCorpseDisease.corpseSicknessSymptomTarget
            local symptomTargetUntil = activeCorpseDisease.corpseSicknessSymptomTargetUntil
            local currentHour = getGameTime():getWorldAgeHours()
            if symptomTarget and symptomTargetUntil and symptomTargetUntil > currentHour then
                local maxAllowed = symptomTarget + 0.015
                EHR_DiseaseClampSicknessStat(stats, maxAllowed)
            end
        end
        return
    end

    if targetLevel == 0 and currentVanilla > 0.01 then
        if EHR.Disease.ShouldSuppressExternalFoodSickness and EHR.Disease.ShouldSuppressExternalFoodSickness(player) then
            if CharacterStat.FOOD_SICKNESS then
                pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0) end)
            end
            if CharacterStat.SICKNESS then
                pcall(function() stats:set(CharacterStat.SICKNESS, 0) end)
            end
            if CharacterStat.POISON then
                pcall(function() stats:set(CharacterStat.POISON, 0) end)
            end

            local playerID = player:getUsername() or "default"
            cachedSicknessTargets[playerID] = {target = 0, lastSetTime = getGameTime():getWorldAgeHours()}

            if EHR.DEBUG then
                EHR.Log(string.format("SyncVanilla: Cleared post-cure FOOD_SICKNESS residue %.3f", currentVanilla))
            end
            return
        end

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
    local preserveVanillaPoison = EHR.Disease.ShouldPreserveVanillaPoison(player, currentPoison)

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
        local targetIsLower = targetB42 < cached.target - 0.01

        -- Only change target if:
        -- 1. Target differs by more than 15% (major stage change), OR
        -- 2. At least 0.25 game hours (15 min) have passed
        -- 3. The new target is lower (active symptom relief should be felt immediately)
        if targetDiff < 0.15 and timeSinceSet < 0.25 and not targetIsLower then
            targetB42 = cached.target  -- Keep old target
        else
            cachedSicknessTargets[playerID] = {target = targetB42, lastSetTime = currentHour}
        end
    else
        cachedSicknessTargets[playerID] = {target = targetB42, lastSetTime = currentHour}
    end

    local gastroFloor = EHR_DiseaseGetGastroSicknessFloor(player)
    if gastroFloor and targetB42 < gastroFloor / 100 then
        targetB42 = gastroFloor / 100
        cachedSicknessTargets[playerID] = {target = targetB42, lastSetTime = currentHour}
    end

    -- Update if sickness significantly different OR poison is active
    -- BUG-014 FIX: Increase dead zone to 0.12 (12%) to prevent oscillation
    -- BUG-021 FIX: ALWAYS suppress if vanilla is ABOVE our target (prevents moodle flash)
    -- The dead zone only applies when vanilla is below target (we don't want to boost it)
    local difference = math.abs(currentVanilla - targetB42)
    local vanillaAboveTarget = currentVanilla > targetB42 + 0.02  -- Small margin for floating point
    local currentSickness = 0
    if CharacterStat.SICKNESS then
        local ok, value = pcall(function() return stats:get(CharacterStat.SICKNESS) end)
        if ok and value then currentSickness = value end
    end
    local sicknessDifference = math.abs(currentSickness - targetB42)
    local sicknessBelowTarget = targetB42 > 0 and currentSickness < targetB42 - 0.02
    local needsUpdate = vanillaAboveTarget or difference > 0.12 or sicknessDifference > 0.08 or sicknessBelowTarget or (currentPoison > 0.1 and not preserveVanillaPoison)

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

        -- CRITICAL: Suppress raw-food POISON spikes, but preserve real vanilla
        -- poison from poisonous berries/mushrooms and intentionally tainted food.
        local successPoison = false
        if currentPoison > 0.1 and CharacterStat.POISON and not preserveVanillaPoison then
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

    EHR_DiseaseEnforceHealthCaps(player, modData)

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
        EHR_DiseaseEnforceHealthCaps(player, modData)
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
