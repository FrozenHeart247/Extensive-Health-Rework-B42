--[[
    Extensive Health Rework B42
    Consolidated Item Distribution

    Adds EHR items to appropriate loot containers:
    - Blood bags and saline (medical facilities)
    - Medications by tier (OTC, Prescription, Clinical)
    - Disease flyers (medical locations)
    - Syringes and IV kits

    Spawn Locations by Tier:
    - Tier 1: OTC - Pharmacies, Bathrooms, Stores, First Aid Kits
    - Tier 2: Prescription - Clinics, Pharmacies, Hospitals
    - Tier 3: Clinical - Large Hospitals, Military Medical, Ambulances

    Note: Knox Cure items are handled separately in EHR_KnoxDistribution.lua
    (location-specific spawns using OnFillContainer)
]]--

require "Items/SuburbsDistributions"
require "Items/ProceduralDistributions"

local function isEHRDebug()
    if EHR and EHR.IsDebugMode then
        return EHR.IsDebugMode()
    end
    if getDebug then
        return getDebug()
    end
    return false
end

local function log(msg)
    if isEHRDebug() then
        print(msg)
    end
end

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

local distributionAliases = {
    -- B42.17 renamed or removed several B41/B42.13 procedural lists.
    -- Resolve old targets to nearby lists that still exist instead of dropping the item.
    PharmacyShelfMeds = {"MedicalStorageDrugs", "MedicalClinicDrugs"},
    MedicalCabinetDrugs = {"MedicalStorageDrugs", "MedicalClinicDrugs"},
    DrugStoreMagazines = {"MedicalStorageDrugs", "MedicalClinicDrugs"},
    MedicineCabinet = {"BedroomSidetable", "BedroomDresser"},
    ArmySurplusMedical = {"ArmyStorageMedical", "MedicalStorageOutfit"},
    FirstAidKit = {"AmbulanceMedical", "MedicalStorageDrugs"},
    Sidetable = {"BedroomSidetable", "BedroomDresser"},
    Dresser = {"BedroomDresser"},
    WardrobeMan = {"BedroomDresser"},
    WardrobeWoman = {"BedroomDresser"},
    ShelvesGeneric = {"LivingRoomShelf", "DeskGeneric"},
    FilingCabinet = {"DeskGeneric", "LivingRoomShelf"},
}

local function resolveDistribution(listName)
    if not ProceduralDistributions or not ProceduralDistributions.list then
        return nil
    end

    local dist = ProceduralDistributions.list[listName]
    if dist and dist.items then
        return dist, listName
    end

    local aliases = distributionAliases[listName]
    if aliases then
        for _, alias in ipairs(aliases) do
            dist = ProceduralDistributions.list[alias]
            if dist and dist.items then
                log("[EHR] Distribution alias: " .. listName .. " -> " .. alias)
                return dist, alias
            end
        end
    end

    return nil
end

local function addItemToDistribution(listName, itemName, chance)
    local dist = resolveDistribution(listName)
    if dist then
        table.insert(dist.items, itemName)
        table.insert(dist.items, chance)
        return true
    end
    return false
end

-- ============================================
-- MAIN DISTRIBUTION FUNCTION
-- ============================================

local function EHR_InitDistributions()
    if not ProceduralDistributions or not ProceduralDistributions.list then
        print("[EHR] ERROR: ProceduralDistributions not available")
        return
    end

    local added = 0
    local failed = 0
    local failedTables = {}

    local function tryAdd(listName, itemName, chance)
        if addItemToDistribution(listName, itemName, chance) then
            added = added + 1
        else
            failed = failed + 1
            if not failedTables[listName] then
                failedTables[listName] = true
            end
        end
    end

    -- =========================================
    -- BLOOD BAGS (based on real-world blood type distribution)
    -- O+ is most common, AB- is rarest
    -- =========================================

    local bloodBagRarity = {
        ["ExtensiveHealth.BloodBagOPos"] = 8,   -- 36% of population
        ["ExtensiveHealth.BloodBagAPos"] = 7,   -- 34%
        ["ExtensiveHealth.BloodBagBPos"] = 3,   -- 9%
        ["ExtensiveHealth.BloodBagONeg"] = 2,   -- 7%
        ["ExtensiveHealth.BloodBagANeg"] = 2,   -- 6%
        ["ExtensiveHealth.BloodBagBNeg"] = 1,   -- 2%
        ["ExtensiveHealth.BloodBagABPos"] = 1,  -- 5%
        ["ExtensiveHealth.BloodBagABNeg"] = 0.5, -- 1%
    }

    -- Medical Storage Blood (hospitals)
    if ProceduralDistributions.list["MedicalStorageBlood"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("MedicalStorageBlood", item, chance)
        end
        tryAdd("MedicalStorageBlood", "ExtensiveHealth.SalineBag", 6)
        tryAdd("MedicalStorageBlood", "ExtensiveHealth.EmptyBloodBag", 8)
    end

    -- Medical Clinic (smaller locations)
    if ProceduralDistributions.list["MedicalClinicDrugs"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("MedicalClinicDrugs", item, chance * 0.3)
        end
        tryAdd("MedicalClinicDrugs", "ExtensiveHealth.SalineBag", 3)
        tryAdd("MedicalClinicDrugs", "ExtensiveHealth.EmptyBloodBag", 4)
    end

    -- Ambulance
    if ProceduralDistributions.list["AmbulanceMedical"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("AmbulanceMedical", item, chance * 0.5)
        end
        tryAdd("AmbulanceMedical", "ExtensiveHealth.SalineBag", 4)
        tryAdd("AmbulanceMedical", "ExtensiveHealth.EmptyBloodBag", 5)
    end

    -- Medical cabinets
    if ProceduralDistributions.list["MedicalCabinetDrugs"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("MedicalCabinetDrugs", item, chance * 0.2)
        end
        tryAdd("MedicalCabinetDrugs", "ExtensiveHealth.SalineBag", 2)
        tryAdd("MedicalCabinetDrugs", "ExtensiveHealth.EmptyBloodBag", 3)
    end

    -- Pharmacy shelves (saline only, no blood bags)
    tryAdd("PharmacyShelfMeds", "ExtensiveHealth.SalineBag", 1)

    -- Military medical
    if ProceduralDistributions.list["ArmyStorageMedical"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("ArmyStorageMedical", item, chance * 0.7)
        end
        tryAdd("ArmyStorageMedical", "ExtensiveHealth.SalineBag", 5)
        tryAdd("ArmyStorageMedical", "ExtensiveHealth.EmptyBloodBag", 6)
    end

    -- Medical Storage Drugs (additional blood bag spawns)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.BloodBagONeg", 1)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.BloodBagOPos", 2)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.BloodBagAPos", 2)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.BloodBagBPos", 1)

    -- Medical Storage Outfit (hospital storage - additional blood bags)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagONeg", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagOPos", 3)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagANeg", 1)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagAPos", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagBNeg", 1)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagBPos", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagABNeg", 0.5)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.BloodBagABPos", 1)

    -- =========================================
    -- DISEASE FLYERS
    -- =========================================

    local flyerRarity = {
        ["ExtensiveHealth.DiseaseFlyer_CommonCold"] = 4,
        ["ExtensiveHealth.DiseaseFlyer_Flu"] = 3,
        ["ExtensiveHealth.DiseaseFlyer_FoodPoisoning"] = 3,
        ["ExtensiveHealth.DiseaseFlyer_Hypothermia"] = 2,
        ["ExtensiveHealth.DiseaseFlyer_HeatExhaustion"] = 2,
        ["ExtensiveHealth.DiseaseFlyer_Pneumonia"] = 1.5,
        ["ExtensiveHealth.DiseaseFlyer_Sepsis"] = 0.8,
        ["ExtensiveHealth.DiseaseFlyer_CorpseSickness"] = 1.5,
        ["ExtensiveHealth.DiseaseFlyer_Tuberculosis"] = 0.5,
    }

    for item, chance in pairs(flyerRarity) do
        tryAdd("MedicalStorageDrugs", item, chance)
        tryAdd("MedicalClinicDrugs", item, chance * 0.7)
        tryAdd("MedicalCabinetDrugs", item, chance * 0.4)
        tryAdd("PharmacyShelfMeds", item, chance * 0.3)
        tryAdd("DrugStoreMagazines", item, chance * 0.3)
    end

    -- =========================================
    -- TIER 1 - OTC (OVER THE COUNTER)
    -- Common locations
    -- =========================================

    -- Pharmacy/Drug Store Shelves
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.ColdFluTablets", 8)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.CoughSyrup", 7)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.AntiNauseaTablets", 7)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.AntiDiarrheal", 7)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.AntiInflammatory", 8)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.CoughSuppressant", 6)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.AntisepticCream", 8)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.MuscleRelaxants", 5)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.ElectrolytePowder", 6)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.BronchodilatorInhaler", 3)

    -- Medicine Cabinets (bathroom)
    tryAdd("MedicineCabinet", "ExtensiveHealth.ColdFluTablets", 4)
    tryAdd("MedicineCabinet", "ExtensiveHealth.CoughSyrup", 3)
    tryAdd("MedicineCabinet", "ExtensiveHealth.AntiNauseaTablets", 3)
    tryAdd("MedicineCabinet", "ExtensiveHealth.AntiDiarrheal", 3)
    tryAdd("MedicineCabinet", "ExtensiveHealth.AntisepticCream", 4)
    tryAdd("MedicineCabinet", "ExtensiveHealth.AntiInflammatory", 3)

    -- Medical Storage / Clinic (OTC items)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.ColdFluTablets", 7)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.CoughSyrup", 6)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.ElectrolytePowder", 6)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.BronchodilatorInhaler", 4)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.AntiNauseaTablets", 6)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.AntiInflammatory", 7)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.MuscleRelaxants", 5)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.Syringe", 10)

    -- =========================================
    -- TIER 2 - PRESCRIPTION MEDICATION
    -- Medical facilities
    -- =========================================

    -- Medical Clinic
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.PrescriptionAntibiotics", 7)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.AntiviralCapsules", 5)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.AntifungalTablets", 3)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.OralRehydrationKit", 5)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.AntibioticOintment", 6)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.Syringe", 8)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.SalineBag", 4)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.BroadSpectrumAntibiotics", 5)

    -- Medical Storage Drugs (Tier 2)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.PrescriptionAntibiotics", 6)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.AntiviralCapsules", 5)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.ActivatedCharcoal", 5)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.AntiparasiticPills", 2)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.TetanusAntitoxin", 3)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.TBAntibiotics", 2)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.AntibioticOintment", 5)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.BroadSpectrumAntibiotics", 4)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.IVKit", 5)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.SalineBag", 6)

    -- =========================================
    -- TIER 3 - CLINICAL GRADE
    -- Rare - Large Hospitals, Military Medical
    -- =========================================

    -- Medical Storage Outfit (hospital storage)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.IVAntibiotics", 3)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.IVMetronidazole", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.IVAmphotericin", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.IVCiprofloxacin", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.IVVancomycin", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.EmergencySepsisKit", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.CorticosteroidInjection", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.ChelationKit", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.AlbendazoleInjection", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.TetanusImmunoglobulin", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.RifampicinComboPack", 2)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.Epinephrine", 3)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.IVKit", 7)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.Syringe", 10)
    tryAdd("MedicalStorageOutfit", "ExtensiveHealth.SalineBag", 7)

    -- Army Surplus / Military
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.IVAntibiotics", 5)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.IVCiprofloxacin", 3)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.EmergencySepsisKit", 2)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.CorticosteroidInjection", 2)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.TetanusImmunoglobulin", 2)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.Epinephrine", 5)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.IVKit", 6)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.Syringe", 8)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.SalineBag", 7)
    tryAdd("ArmySurplusMedical", "ExtensiveHealth.BroadSpectrumAntibiotics", 6)

    -- First Aid Kits (basic supplies)
    tryAdd("FirstAidKit", "ExtensiveHealth.AntisepticCream", 7)
    tryAdd("FirstAidKit", "ExtensiveHealth.AntiInflammatory", 5)
    tryAdd("FirstAidKit", "ExtensiveHealth.Syringe", 3)

    -- =========================================
    -- HOUSEHOLD SPAWNS (Very Rare)
    -- Tier 1 & 2 only - people keep meds at home
    -- =========================================

    -- Household container types
    local householdContainers = {
        "Sidetable",           -- Bedside tables
        "BedroomDresser",      -- Bedroom furniture
        "BedroomSidetable",    -- Bedroom side tables
        "Dresser",             -- Dressers
        "WardrobeMan",         -- Wardrobes
        "WardrobeWoman",
        "ShelvesGeneric",      -- Generic shelves
        "LivingRoomShelf",     -- Living room
        "DeskGeneric",         -- Desks
        "FilingCabinet",       -- Home office
    }

    -- Tier 1 OTC - Very low chance (someone might keep cold meds in nightstand)
    local tier1Household = {
        ["ExtensiveHealth.ColdFluTablets"] = 0.3,
        ["ExtensiveHealth.CoughSyrup"] = 0.2,
        ["ExtensiveHealth.AntiNauseaTablets"] = 0.2,
        ["ExtensiveHealth.AntiDiarrheal"] = 0.2,
        ["ExtensiveHealth.AntiInflammatory"] = 0.3,
        ["ExtensiveHealth.AntisepticCream"] = 0.2,
        ["ExtensiveHealth.MuscleRelaxants"] = 0.1,
    }

    -- Tier 2 Prescription - Even lower (leftover prescriptions)
    local tier2Household = {
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 0.1,
        ["ExtensiveHealth.AntibioticOintment"] = 0.15,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 0.05,
        ["ExtensiveHealth.AntiviralCapsules"] = 0.05,
        ["ExtensiveHealth.ActivatedCharcoal"] = 0.1,
    }

    for _, container in ipairs(householdContainers) do
        -- Tier 1
        for item, chance in pairs(tier1Household) do
            tryAdd(container, item, chance)
        end
        -- Tier 2
        for item, chance in pairs(tier2Household) do
            tryAdd(container, item, chance)
        end
    end

    -- =========================================
    -- SUMMARY
    -- =========================================

    local failedTableCount = 0
    local failedTableList = {}
    for tableName, _ in pairs(failedTables) do
        failedTableCount = failedTableCount + 1
        table.insert(failedTableList, tableName)
    end

    print("[EHR] Distributions loaded - Added: " .. added .. ", Failed: " .. failed)
    if failedTableCount > 0 then
        print("[EHR] Missing distribution tables (" .. failedTableCount .. "): " .. table.concat(failedTableList, ", "))
        print("[EHR] Note: Some B42 distribution tables may have different names from B41")
    end

    log("[EHR] Loot distribution initialized for blood bags, medications, and flyers")
end

-- Register with distribution system
Events.OnPreDistributionMerge.Add(EHR_InitDistributions)
