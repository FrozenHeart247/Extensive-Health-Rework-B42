--[[
    Extensive Health Rework B42
    Optional zombie loot

    Uses the server-side OnZombieDead event so the normal zombie distribution
    has already been generated. This handler only appends one item and never
    edits, reparses, clears, or replaces vanilla/third-party loot tables.
]]--

EHR = EHR or {}
EHR.ZombieLoot = EHR.ZombieLoot or {}

local ZombieLoot = EHR.ZombieLoot
local DEFAULT_CHANCE_PERCENT = 5.0
local ROLL_PRECISION = 10000
local PROCESSED_MARKER = "EHR_ZombieLootRolled_v1"
local processedFallback = setmetatable({}, { __mode = "k" })

-- This is the natural-spawn catalog from EHR_Distributions.lua. Knox cure
-- items are managed by EHR_KnoxDistribution.lua and are intentionally absent.
-- Craft-only/homemade items and unfinished items are also intentionally absent.
ZombieLoot.ItemPool = {
    -- Blood and transfusion supplies
    "ExtensiveHealth.BloodBagONeg",
    "ExtensiveHealth.BloodBagOPos",
    "ExtensiveHealth.BloodBagANeg",
    "ExtensiveHealth.BloodBagAPos",
    "ExtensiveHealth.BloodBagBNeg",
    "ExtensiveHealth.BloodBagBPos",
    "ExtensiveHealth.BloodBagABNeg",
    "ExtensiveHealth.BloodBagABPos",
    "ExtensiveHealth.EmptyBloodBag",
    "ExtensiveHealth.SalineBag",
    "ExtensiveHealth.IVKit",
    "ExtensiveHealth.Syringe",
    "ExtensiveHealth.IVFluids",
    "ExtensiveHealth.MedicineStorageBox",

    -- Dressings and general medical supplies
    "ExtensiveHealth.SterilizedBandages",
    "ExtensiveHealth.AlchoholicBandage",
    "ExtensiveHealth.InstantIcePack",
    "ExtensiveHealth.WarmingPack",

    -- Over-the-counter medication
    "ExtensiveHealth.ColdFluTablets",
    "ExtensiveHealth.AntipyreticTablets",
    "ExtensiveHealth.CoughSyrup",
    "ExtensiveHealth.ElectrolytePowder",
    "ExtensiveHealth.BronchodilatorInhaler",
    "ExtensiveHealth.AntiNauseaTablets",
    "ExtensiveHealth.AntiInflammatory",
    "ExtensiveHealth.AntiDiarrheal",
    "ExtensiveHealth.MuscleRelaxants",
    "ExtensiveHealth.NitricOxideBooster",
    "ExtensiveHealth.CombatStimulants",
    "ExtensiveHealth.CoughSuppressant",
    "ExtensiveHealth.AntisepticCream",

    -- Prescription medication
    "ExtensiveHealth.AntiviralCapsules",
    "ExtensiveHealth.PrescriptionAntibiotics",
    "ExtensiveHealth.AntifungalTablets",
    "ExtensiveHealth.ActivatedCharcoal",
    "ExtensiveHealth.AntiparasiticPills",
    "ExtensiveHealth.TopicalPermethrin",
    "ExtensiveHealth.OralRehydrationKit",
    "ExtensiveHealth.Furosemide",
    "ExtensiveHealth.Antipsychotics",
    "ExtensiveHealth.DualOrexinReceptor",
    "ExtensiveHealth.Buprenorphine",
    "ExtensiveHealth.TetanusAntitoxin",
    "ExtensiveHealth.TBAntibiotics",
    "ExtensiveHealth.AntibioticOintment",
    "ExtensiveHealth.BroadSpectrumAntibiotics",

    -- Clinical medication and equipment
    "ExtensiveHealth.CorticosteroidInjection",
    "ExtensiveHealth.LastChanceEpinephrine",
    "ExtensiveHealth.RespiratorySupportKit",
    "ExtensiveHealth.IVAntibiotics",
    "ExtensiveHealth.IVMetronidazole",
    "ExtensiveHealth.IVAmphotericin",
    "ExtensiveHealth.ChelationKit",
    "ExtensiveHealth.AlbendazoleInjection",
    "ExtensiveHealth.IVCiprofloxacin",
    "ExtensiveHealth.TetanusImmunoglobulin",
    "ExtensiveHealth.IVVancomycin",
    "ExtensiveHealth.EmergencySepsisKit",

    -- Medical Monitor Watch
    "ExtensiveHealth.EHRMedicalWatch_Left",
    "ExtensiveHealth.EHRMedicalWatch_Right",

    -- Disease literature
    "ExtensiveHealth.DiseaseFlyer_CommonCold",
    "ExtensiveHealth.DiseaseFlyer_Pneumonia",
    "ExtensiveHealth.DiseaseFlyer_FoodPoisoning",
    "ExtensiveHealth.DiseaseFlyer_Hypothermia",
    "ExtensiveHealth.DiseaseFlyer_HeatExhaustion",
    "ExtensiveHealth.DiseaseFlyer_Sepsis",
    "ExtensiveHealth.DiseaseFlyer_CorpseSickness",
    "ExtensiveHealth.DiseaseFlyer_Tuberculosis",
    "ExtensiveHealth.DiseaseFlyer_Gastroenteritis",
    "ExtensiveHealth.DiseaseFlyer_Dysentery",
    "ExtensiveHealth.DiseaseFlyer_Trichinosis",
    "ExtensiveHealth.DiseaseFlyer_HyperkeratoticScabies",
    "ExtensiveHealth.DiseaseFlyer_ToxinPoisoning",
    "ExtensiveHealth.DiseaseFlyer_HeatStroke",
    "ExtensiveHealth.DiseaseFlyer_CadavericAspergillosis",
    "ExtensiveHealth.DiseaseFlyer_Tetanus",
    "ExtensiveHealth.DiseaseFlyer_WoundInfection",
    "ExtensiveHealth.DiseaseFlyer_Cellulitis",
    "ExtensiveHealth.DiseaseFlyer_AHTR",
    "ExtensiveHealth.DiseaseFlyer_BloodType",
    "ExtensiveHealth.MedicalWildPlants",
    "ExtensiveHealth.EhrRecipePlantBasedAntibiotics",
    "ExtensiveHealth.EhrRecipeUltimateCraftGuide",
}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function getSandbox()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        return SandboxVars.ExtensiveHealthRework
    end
    return nil
end

function ZombieLoot.IsEnabled()
    local sandbox = getSandbox()
    if sandbox and sandbox.ZombieLootEnabled ~= nil then
        return sandbox.ZombieLootEnabled == true
    end
    return true
end

function ZombieLoot.GetChancePercent()
    local sandbox = getSandbox()
    local chance = sandbox and tonumber(sandbox.ZombieLootChance) or nil
    return clamp(chance or DEFAULT_CHANCE_PERCENT, 0.0, 100.0)
end

local function claimZombie(zombie)
    local ok, modData = pcall(function()
        return zombie:getModData()
    end)

    if ok and modData then
        if modData[PROCESSED_MARKER] then
            return false
        end
        modData[PROCESSED_MARKER] = true
        return true
    end

    -- IsoZombie normally always has modData. Keep a weak in-memory fallback so
    -- an unusual zombie implementation still cannot receive duplicate rolls.
    if processedFallback[zombie] then
        return false
    end
    processedFallback[zombie] = true
    return true
end

local function scriptItemExists(fullType)
    if not ScriptManager or not ScriptManager.instance then
        return true
    end

    local ok, scriptItem = pcall(function()
        return ScriptManager.instance:FindItem(fullType)
    end)
    return ok and scriptItem ~= nil
end

local function applyMedicationFill(item)
    local medicationSpawns = EHR and EHR.MedicationSpawns
    if not item or not medicationSpawns or not medicationSpawns.RandomizeItemUses
        or not medicationSpawns.DrainableMeds then
        return
    end

    local ok, fullType = pcall(function()
        return item:getFullType()
    end)
    if not ok or not medicationSpawns.DrainableMeds[fullType] then
        return
    end

    pcall(function()
        medicationSpawns.RandomizeItemUses(item, "default")
    end)
end

local function addRandomPoolItem(inventory)
    local pool = ZombieLoot.ItemPool
    local count = #pool
    if count == 0 then return nil end

    -- Start at a random point and walk the pool only if an item was removed or
    -- renamed in a future version. One bad ID must never break zombie creation.
    local firstIndex = ZombRand(count) + 1
    for offset = 0, count - 1 do
        local index = ((firstIndex + offset - 1) % count) + 1
        local fullType = pool[index]
        if scriptItemExists(fullType) then
            local ok, item = pcall(function()
                return inventory:AddItem(fullType)
            end)
            if ok and item then
                applyMedicationFill(item)
                return item
            end
        end
    end

    return nil
end

function ZombieLoot.OnZombieDead(zombie)
    -- In MP this event is raised in both Lua environments, and the client may
    -- load this server script as part of a hosted session. Only the server may
    -- mutate corpse loot; a client-side AddItem creates an untransferable ghost.
    if isClient and isClient() then return end
    if not zombie or not ZombieLoot.IsEnabled() then return end
    if instanceof and not instanceof(zombie, "IsoZombie") then return end

    local chance = ZombieLoot.GetChancePercent()
    if chance <= 0 then return end
    if not claimZombie(zombie) then return end

    local rollMaximum = 100 * ROLL_PRECISION
    if chance < 100 and ZombRand(rollMaximum) >= chance * ROLL_PRECISION then
        return
    end

    local ok, inventory = pcall(function()
        return zombie:getInventory()
    end)
    if not ok or not inventory then return end

    -- The corpse inventory is replicated by the game's normal death/container
    -- sync. Sending this item again with sendAddItemToContainer creates a second
    -- client-side entry with the same server authority: a non-transferable
    -- "ghost" duplicate.
    local item = addRandomPoolItem(inventory)
    if item and EHR and EHR.IsDebugMode and EHR.IsDebugMode() then
        local okType, fullType = pcall(function() return item:getFullType() end)
        print("[EHR] Zombie loot added: " .. tostring(okType and fullType or item))
    end
end

if Events and Events.OnZombieDead then
    Events.OnZombieDead.Add(ZombieLoot.OnZombieDead)
end
