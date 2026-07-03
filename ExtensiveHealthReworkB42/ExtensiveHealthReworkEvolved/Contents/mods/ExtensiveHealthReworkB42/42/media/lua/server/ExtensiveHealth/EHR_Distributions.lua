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
require "Vehicles/VehicleDistributions"

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
    if EHR and EHR.ShouldLog and EHR.ShouldLog(msg) then
        print(msg)
    end
end

local function getEHRSandbox()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        return SandboxVars.ExtensiveHealthRework
    end
    return nil
end

local function clampNumber(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getMedicationLootMultiplier()
    local sandbox = getEHRSandbox()
    if sandbox and sandbox.MedicationLootMultiplier ~= nil then
        local value = tonumber(sandbox.MedicationLootMultiplier)
        if value then
            return clampNumber(value, 0.0, 2.0)
        end
    end
    return 1.0
end

local function getMedicalWatchLootMultiplier()
    local sandbox = getEHRSandbox()
    if sandbox and sandbox.MedicalWatchLootMultiplier ~= nil then
        local value = tonumber(sandbox.MedicalWatchLootMultiplier)
        if value then
            return clampNumber(value, 0.0, 1.0)
        end
    end
    return 1.0
end

local function isHouseholdPrescriptionLootEnabled()
    local sandbox = getEHRSandbox()
    if sandbox and sandbox.HouseholdPrescriptionLoot ~= nil then
        return sandbox.HouseholdPrescriptionLoot == true
    end
    return true
end

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

local distributionAliases = {
    -- B42.17 renamed or removed several B41/B42.13 procedural lists.
    -- Resolve old targets to nearby lists that still exist instead of dropping the item.
    PharmacyShelfMeds = {"MedicalStorageDrugs", "MedicalClinicDrugs"},
    MedicalCabinetDrugs = {"MedicalStorageDrugs", "MedicalClinicDrugs"},
    MedicalCabinet = {"MedicalClinicDrugs", "MedicalStorageDrugs"},
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

local function addItemToRawDistribution(dist, itemName, chance)
    if dist and dist.items then
        table.insert(dist.items, itemName)
        table.insert(dist.items, chance)
        return true
    end
    return false
end

local function addItemToBagDistribution(bagName, itemName, chance)
    local dist = SuburbsDistributions and SuburbsDistributions[bagName]
    if not dist then
        local all = SuburbsDistributions and SuburbsDistributions["all"]
        dist = all and all[bagName]
    end
    return addItemToRawDistribution(dist, itemName, chance)
end

local function procListContains(procList, procName)
    if not procList or not procName then return false end
    for _, entry in ipairs(procList) do
        if entry and entry.name == procName then
            return true
        end
    end
    return false
end

local function addProcListToRoomContainer(roomName, containerName, procName, minValue, maxValue, weightChance)
    if not SuburbsDistributions then return false end

    local room = SuburbsDistributions[roomName]
    if not room then return false end

    local dist = room[containerName]
    if not dist then
        dist = {
            procedural = true,
            procList = {},
        }
        room[containerName] = dist
    end

    if not dist.procedural or not dist.procList then
        if dist.items and #dist.items > 0 then
            return false
        end
        dist.procedural = true
        dist.procList = {}
        dist.items = nil
        dist.rolls = nil
        dist.junk = nil
    end

    if procListContains(dist.procList, procName) then
        return false
    end

    table.insert(dist.procList, {
        name = procName,
        min = minValue or 0,
        max = maxValue or 99,
        weightChance = weightChance,
    })
    return true
end

local function setRawDistributionMinRolls(dist, minRolls)
    if dist and dist.rolls and dist.rolls < minRolls then
        dist.rolls = minRolls
        return true
    end
    return false
end

local function setBagDistributionMinRolls(bagName, minRolls)
    local dist = SuburbsDistributions and SuburbsDistributions[bagName]
    if not dist then
        local all = SuburbsDistributions and SuburbsDistributions["all"]
        dist = all and all[bagName]
    end
    return setRawDistributionMinRolls(dist, minRolls)
end

local function setVehicleDistributionMinRolls(distributionName, minRolls)
    local dist = VehicleDistributions and VehicleDistributions[distributionName]
    return setRawDistributionMinRolls(dist, minRolls)
end

local function addItemToVehicleDistribution(distributionName, itemName, chance)
    local dist = VehicleDistributions and VehicleDistributions[distributionName]
    return addItemToRawDistribution(dist, itemName, chance)
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
    local medicationLootMultiplier = getMedicationLootMultiplier()
    local householdPrescriptionLoot = isHouseholdPrescriptionLootEnabled()

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

    local function tryAddMed(listName, itemName, chance)
        if medicationLootMultiplier <= 0 then return end
        tryAdd(listName, itemName, chance * medicationLootMultiplier)
    end

    local function tryAddBag(bagName, itemName, chance)
        if addItemToBagDistribution(bagName, itemName, chance) then
            added = added + 1
        else
            failed = failed + 1
            if not failedTables[bagName] then
                failedTables[bagName] = true
            end
        end
    end

    local function tryAddBagMed(bagName, itemName, chance)
        if medicationLootMultiplier <= 0 then return end
        tryAddBag(bagName, itemName, chance * medicationLootMultiplier)
    end

    local function tryAddVehicle(distributionName, itemName, chance)
        if addItemToVehicleDistribution(distributionName, itemName, chance) then
            added = added + 1
        else
            failed = failed + 1
            if not failedTables[distributionName] then
                failedTables[distributionName] = true
            end
        end
    end

    local function tryAddVehicleMed(distributionName, itemName, chance)
        if medicationLootMultiplier <= 0 then return end
        tryAddVehicle(distributionName, itemName, chance * medicationLootMultiplier)
    end

    local function tryAddRoomProc(roomName, containerName, procName, minValue, maxValue, weightChance)
        if addProcListToRoomContainer(roomName, containerName, procName, minValue, maxValue, weightChance) then
            added = added + 1
        else
            failed = failed + 1
            local tableName = tostring(roomName) .. "." .. tostring(containerName)
            if not failedTables[tableName] then
                failedTables[tableName] = true
            end
        end
    end

    local function itemListContains(items, itemName)
        if not items or not itemName then return false end
        for i = 1, #items, 2 do
            if items[i] == itemName then
                return true
            end
        end
        return false
    end

    local function copyMedicalWatchDistribution()
        local watchLootMultiplier = getMedicalWatchLootMultiplier()
        local sourceToTarget = {
            WristWatch_Left_DigitalRed = "ExtensiveHealth.EHRMedicalWatch_Left",
            ["Base.WristWatch_Left_DigitalRed"] = "ExtensiveHealth.EHRMedicalWatch_Left",
            WristWatch_Right_DigitalRed = "ExtensiveHealth.EHRMedicalWatch_Right",
            ["Base.WristWatch_Right_DigitalRed"] = "ExtensiveHealth.EHRMedicalWatch_Right",
        }
        local ehrWatchItems = {
            ["ExtensiveHealth.EHRMedicalWatch_Left"] = true,
            ["ExtensiveHealth.EHRMedicalWatch_Right"] = true,
            EHRMedicalWatch_Left = true,
            EHRMedicalWatch_Right = true,
        }

        for _, dist in pairs(ProceduralDistributions.list) do
            local items = dist and dist.items
            if items then
                for i = #items - 1, 1, -2 do
                    if ehrWatchItems[items[i]] then
                        table.remove(items, i + 1)
                        table.remove(items, i)
                    end
                end
            end
        end

        if watchLootMultiplier <= 0 then
            return
        end

        for _, dist in pairs(ProceduralDistributions.list) do
            local items = dist and dist.items
            if items then
                for i = 1, #items - 1, 2 do
                    local target = sourceToTarget[items[i]]
                    local chance = tonumber(items[i + 1])
                    if target and chance and chance > 0 and not itemListContains(items, target) then
                        table.insert(items, target)
                        table.insert(items, chance * watchLootMultiplier)
                        added = added + 1
                    end
                end
            end
        end
    end

    copyMedicalWatchDistribution()

    -- B42 medical furniture sometimes uses raw room/container pairs instead of the
    -- procedural medical drug tables. Keep these room-specific so household
    -- medicine cabinets stay on their normal loot balance.
    tryAddRoomProc("medical", "medicine", "MedicalClinicDrugs", 0, 99, 100)
    tryAddRoomProc("medical", "medicine", "MedicalClinicTools", 0, 1, 25)
    tryAddRoomProc("medical", "sidetable", "MedicalClinicDrugs", 0, 2, 35)
    tryAddRoomProc("medicalstorage", "medicine", "MedicalStorageDrugs", 0, 99, 100)
    tryAddRoomProc("medicalstorage", "medicine", "MedicalClinicTools", 0, 2, 40)
    tryAddRoomProc("medicalstorage", "sidetable", "MedicalStorageDrugs", 0, 2, 80)
    tryAddRoomProc("medicalstorage", "sidetable", "MedicalClinicDrugs", 0, 2, 45)
    tryAddRoomProc("oldmedical", "medicine", "MedicalStorageDrugs", 0, 2, 45)
    tryAddRoomProc("oldmedical", "medicine", "MedicalClinicTools", 0, 1, 35)

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
        tryAddMed("MedicalStorageBlood", "ExtensiveHealth.IVFluids", 5)
        tryAdd("MedicalStorageBlood", "ExtensiveHealth.EmptyBloodBag", 8)
    end

    -- Medical Clinic (smaller locations)
    if ProceduralDistributions.list["MedicalClinicDrugs"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("MedicalClinicDrugs", item, chance * 0.3)
        end
        tryAdd("MedicalClinicDrugs", "ExtensiveHealth.SalineBag", 3)
        tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.IVFluids", 2)
        tryAdd("MedicalClinicDrugs", "ExtensiveHealth.EmptyBloodBag", 4)
    end

    -- Ambulance
    if ProceduralDistributions.list["AmbulanceMedical"] then
        for item, chance in pairs(bloodBagRarity) do
            tryAdd("AmbulanceMedical", item, chance * 0.5)
        end
        tryAdd("AmbulanceMedical", "ExtensiveHealth.SalineBag", 4)
        tryAddMed("AmbulanceMedical", "ExtensiveHealth.IVFluids", 3)
        tryAdd("AmbulanceMedical", "ExtensiveHealth.EmptyBloodBag", 5)
        tryAddMed("AmbulanceMedical", "ExtensiveHealth.Furosemide", 2)
        tryAddMed("AmbulanceMedical", "ExtensiveHealth.SterilizedBandages", 5)
        tryAddMed("AmbulanceMedical", "ExtensiveHealth.AlchoholicBandage", 3)
        tryAddMed("AmbulanceMedical", "ExtensiveHealth.InstantIcePack", 4)
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
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.SterilizedBandages", 4)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.AlchoholicBandage", 2)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.InstantIcePack", 2)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.Furosemide", 1)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.Antipsychotics", 2)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.DualOrexinReceptor", 1.5)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.NitricOxideBooster", 2)
    tryAddMed("PharmacyShelfMeds", "ExtensiveHealth.TopicalPermethrin", 2)

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
        ["ExtensiveHealth.DiseaseFlyer_FoodPoisoning"] = 3,
        ["ExtensiveHealth.DiseaseFlyer_Hypothermia"] = 2,
        ["ExtensiveHealth.DiseaseFlyer_HeatExhaustion"] = 2,
        ["ExtensiveHealth.DiseaseFlyer_Pneumonia"] = 1.5,
        ["ExtensiveHealth.DiseaseFlyer_Sepsis"] = 0.8,
        ["ExtensiveHealth.DiseaseFlyer_CorpseSickness"] = 1.5,
        ["ExtensiveHealth.DiseaseFlyer_Tuberculosis"] = 0.5,
        ["ExtensiveHealth.DiseaseFlyer_Gastroenteritis"] = 2,
        ["ExtensiveHealth.DiseaseFlyer_Dysentery"] = 1.2,
        ["ExtensiveHealth.DiseaseFlyer_Trichinosis"] = 1.2,
        ["ExtensiveHealth.DiseaseFlyer_HyperkeratoticScabies"] = 0.8,
        ["ExtensiveHealth.DiseaseFlyer_ToxinPoisoning"] = 1,
        ["ExtensiveHealth.DiseaseFlyer_HeatStroke"] = 1,
        ["ExtensiveHealth.DiseaseFlyer_CadavericAspergillosis"] = 0.8,
        ["ExtensiveHealth.DiseaseFlyer_Tetanus"] = 0.8,
        ["ExtensiveHealth.DiseaseFlyer_WoundInfection"] = 2,
        ["ExtensiveHealth.DiseaseFlyer_Cellulitis"] = 1.2,
        ["ExtensiveHealth.DiseaseFlyer_AHTR"] = 0.5,
        ["ExtensiveHealth.DiseaseFlyer_BloodType"] = 1.5,
        ["ExtensiveHealth.MedicalWildPlants"] = 1.2,
    }

    for item, chance in pairs(flyerRarity) do
        tryAdd("MedicalStorageDrugs", item, chance)
        tryAdd("MedicalClinicDrugs", item, chance * 0.7)
        tryAdd("MedicalCabinetDrugs", item, chance * 0.4)
        tryAdd("PharmacyShelfMeds", item, chance * 0.3)
        tryAdd("DrugStoreMagazines", item, chance * 0.3)
    end

    -- Medicine recipes
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.8)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.6)
    tryAdd("MedicalCabinetDrugs", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.25)
    tryAdd("PharmacyShelfMeds", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.25)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.8)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.35)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.25)
    tryAdd("MedicalCabinetDrugs", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.08)
    tryAdd("PharmacyShelfMeds", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.08)
    tryAdd("DrugStoreMagazines", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.35)

    -- =========================================
    -- TIER 1 - OTC (OVER THE COUNTER)
    -- Common locations
    -- =========================================

    -- Pharmacy/Drug Store Shelves
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.ColdFluTablets", 8)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.AntipyreticTablets", 7)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.CoughSyrup", 7)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.AntiNauseaTablets", 7)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.AntiDiarrheal", 7)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.AntiInflammatory", 8)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.CoughSuppressant", 6)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.AntisepticCream", 8)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.MuscleRelaxants", 5)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.ElectrolytePowder", 6)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.BronchodilatorInhaler", 3)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.InstantIcePack", 4)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.Antipsychotics", 3)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.DualOrexinReceptor", 2)
    tryAddMed("DrugStoreMagazines", "ExtensiveHealth.TopicalPermethrin", 3)

    -- Supermarket / general store medical shelves. These are intentionally lighter
    -- than pharmacies: OTC meds and basic supplies only.
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.ColdFluTablets", 3)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntipyreticTablets", 3)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.CoughSyrup", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.CoughSuppressant", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntiNauseaTablets", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntiDiarrheal", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntiInflammatory", 3)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.ElectrolytePowder", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntisepticCream", 3)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.SterilizedBandages", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AlchoholicBandage", 1)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.InstantIcePack", 1)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.TopicalPermethrin", 1)

    -- GigaMart/Grocery shelves use toiletries instead of StoreShelfMedical in B42.
    tryAddMed("GigamartToiletries", "ExtensiveHealth.ColdFluTablets", 1.5)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.AntipyreticTablets", 1.5)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.CoughSyrup", 1)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.CoughSuppressant", 0.8)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.AntiNauseaTablets", 1)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.AntiDiarrheal", 1)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.AntiInflammatory", 1.5)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.ElectrolytePowder", 1)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.AntisepticCream", 1.5)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.SterilizedBandages", 1)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.InstantIcePack", 0.5)
    tryAddMed("GigamartToiletries", "ExtensiveHealth.TopicalPermethrin", 0.5)

    -- Medical cabinets in clinics, waiting rooms, and institutional medical areas.
    tryAddMed("MedicalCabinet", "ExtensiveHealth.ColdFluTablets", 3)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.AntipyreticTablets", 3)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.CoughSyrup", 2)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.AntiNauseaTablets", 2)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.AntiDiarrheal", 2)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.AntiInflammatory", 3)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.ElectrolytePowder", 2)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.AntisepticCream", 3)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.SterilizedBandages", 2)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.AlchoholicBandage", 1)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.InstantIcePack", 1)
    tryAddMed("MedicalCabinet", "ExtensiveHealth.TopicalPermethrin", 1)

    -- Household medicine cabinets / bedroom fallback.
    tryAddMed("MedicineCabinet", "ExtensiveHealth.ColdFluTablets", 4)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.AntipyreticTablets", 4)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.CoughSyrup", 3)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.AntiNauseaTablets", 3)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.AntiDiarrheal", 3)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.AntisepticCream", 4)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.AntiInflammatory", 3)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.NitricOxideBooster", 1)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.SterilizedBandages", 2)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.AlchoholicBandage", 1)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.InstantIcePack", 1)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.Antipsychotics", 1)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.DualOrexinReceptor", 0.8)
    tryAddMed("MedicineCabinet", "ExtensiveHealth.TopicalPermethrin", 1)

    -- Medical Storage / Clinic (OTC items)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.ColdFluTablets", 7)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntipyreticTablets", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.CoughSyrup", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.ElectrolytePowder", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.BronchodilatorInhaler", 4)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntiNauseaTablets", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntiInflammatory", 7)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.MuscleRelaxants", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.NitricOxideBooster", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.Syringe", 10)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.SterilizedBandages", 8)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AlchoholicBandage", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.InstantIcePack", 5)

    -- =========================================
    -- TIER 2 - PRESCRIPTION MEDICATION
    -- Medical facilities
    -- =========================================

    -- Medical Clinic
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.PrescriptionAntibiotics", 7)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.AntiviralCapsules", 5)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.AntifungalTablets", 3)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.OralRehydrationKit", 5)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.InstantIcePack", 5)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.Furosemide", 3)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.Antipsychotics", 4)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.DualOrexinReceptor", 4)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.AntibioticOintment", 6)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.Syringe", 8)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.SalineBag", 4)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.BroadSpectrumAntibiotics", 5)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.SterilizedBandages", 6)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.AlchoholicBandage", 4)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.TopicalPermethrin", 4)

    -- Medical Storage Drugs (Tier 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.PrescriptionAntibiotics", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntiviralCapsules", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.ActivatedCharcoal", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntiparasiticPills", 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.Furosemide", 4)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.Antipsychotics", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.DualOrexinReceptor", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.TetanusAntitoxin", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.TBAntibiotics", 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntibioticOintment", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.BroadSpectrumAntibiotics", 4)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.IVKit", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.IVFluids", 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.SalineBag", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.TopicalPermethrin", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.IVAntibiotics", 0.8)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.IVCiprofloxacin", 0.5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.CorticosteroidInjection", 0.6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.RespiratorySupportKit", 0.6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.EmergencySepsisKit", 0.35)

    -- =========================================
    -- TIER 3 - CLINICAL GRADE
    -- Rare - Large Hospitals, Military Medical
    -- =========================================

    -- Medical Storage Outfit (hospital storage)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVAntibiotics", 3.6)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVMetronidazole", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVAmphotericin", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVCiprofloxacin", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVVancomycin", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVFluids", 4.8)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.EmergencySepsisKit", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.CorticosteroidInjection", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.RespiratorySupportKit", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.ChelationKit", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.AlbendazoleInjection", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.TetanusImmunoglobulin", 2.4)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.Furosemide", 3)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.Antipsychotics", 2)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.DualOrexinReceptor", 2)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.IVKit", 7)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.Syringe", 10)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.SalineBag", 7)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.SterilizedBandages", 8)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.AlchoholicBandage", 5)
    tryAddMed("MedicalStorageOutfit", "ExtensiveHealth.InstantIcePack", 4)

    -- Army Surplus / Military
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.IVAntibiotics", 5)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.IVCiprofloxacin", 3)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.IVFluids", 3)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.EmergencySepsisKit", 2)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.CorticosteroidInjection", 2)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.RespiratorySupportKit", 2)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.TetanusImmunoglobulin", 2)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.IVKit", 6)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.Syringe", 8)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.SalineBag", 7)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.BroadSpectrumAntibiotics", 6)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.Furosemide", 2)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.SterilizedBandages", 6)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.AlchoholicBandage", 4)
    tryAddMed("ArmySurplusMedical", "ExtensiveHealth.InstantIcePack", 3)

    -- Combat stimulants are restricted tactical supplies.
    -- Keep them out of normal medical pools so they remain rare, military/police-flavored loot.
    local combatStimulant = "ExtensiveHealth.CombatStimulants"
    local combatStimulantWeaponStore = {
        GunStoreAccessories = 1.2,
        GunStoreCases = 1.0,
        GunStoreBodyArmor = 0.9,
        GunStoreAmmunition = 0.7,
        GunStoreKnives = 0.5,
    }
    for container, chance in pairs(combatStimulantWeaponStore) do
        tryAddMed(container, combatStimulant, chance)
    end

    local combatStimulantMilitary = {
        ArmyStorageMedical = 3.0,
        ArmyStorageOutfit = 2.0,
        ArmyStorageGuns = 1.5,
        ArmyStorageAmmunition = 1.5,
    }
    for container, chance in pairs(combatStimulantMilitary) do
        tryAddMed(container, combatStimulant, chance)
    end

    local combatStimulantPoliceStation = {
        PoliceStorageGuns = 0.8,
        PoliceEvidence = 0.6,
        PoliceCaptainCabinet = 0.4,
        PoliceDesk = 0.3,
    }
    for container, chance in pairs(combatStimulantPoliceStation) do
        tryAddMed(container, combatStimulant, chance)
    end

    tryAddBagMed("Bag_Police", combatStimulant, 0.6)
    tryAddVehicleMed("PoliceGloveBox", combatStimulant, 0.25)
    tryAddVehicleMed("PoliceSeatFront", combatStimulant, 0.25)
    tryAddVehicleMed("PoliceTruckBed", combatStimulant, 0.4)
    tryAddVehicleMed("PoliceSWATGloveBox", combatStimulant, 0.8)
    tryAddVehicleMed("PoliceSWATSeatFront", combatStimulant, 0.8)
    tryAddVehicleMed("PoliceSWATTruckBed", combatStimulant, 1.2)

    -- First Aid Kits (basic supplies)
    tryAddMed("FirstAidKit", "ExtensiveHealth.AntisepticCream", 7)
    tryAddMed("FirstAidKit", "ExtensiveHealth.AntiInflammatory", 5)
    tryAddMed("FirstAidKit", "ExtensiveHealth.AntipyreticTablets", 4)
    tryAddMed("FirstAidKit", "ExtensiveHealth.NitricOxideBooster", 1)
    tryAddMed("FirstAidKit", "ExtensiveHealth.Syringe", 3)
    tryAddMed("FirstAidKit", "ExtensiveHealth.SterilizedBandages", 7)
    tryAddMed("FirstAidKit", "ExtensiveHealth.AlchoholicBandage", 3)
    tryAddMed("FirstAidKit", "ExtensiveHealth.InstantIcePack", 3)
    tryAddMed("FirstAidKit", "ExtensiveHealth.TopicalPermethrin", 1)

    -- Ambulance vehicle containers. These are the actual van loot tables, separate from
    -- procedural "AmbulanceMedical" storage used by buildings/outfits.
    local ambulanceGloveBoxMeds = {
        ["ExtensiveHealth.SterilizedBandages"] = 4,
        ["ExtensiveHealth.AlchoholicBandage"] = 2,
        ["ExtensiveHealth.AntisepticCream"] = 3,
        ["ExtensiveHealth.AntiInflammatory"] = 3,
        ["ExtensiveHealth.AntipyreticTablets"] = 3,
        ["ExtensiveHealth.AntiNauseaTablets"] = 2.5,
        ["ExtensiveHealth.ElectrolytePowder"] = 2,
        ["ExtensiveHealth.BronchodilatorInhaler"] = 1.5,
        ["ExtensiveHealth.InstantIcePack"] = 1.5,
        ["ExtensiveHealth.AntibioticOintment"] = 1.5,
        ["ExtensiveHealth.ActivatedCharcoal"] = 1,
    }

    local ambulanceSeatMeds = {
        ["ExtensiveHealth.SterilizedBandages"] = 5,
        ["ExtensiveHealth.AlchoholicBandage"] = 2.5,
        ["ExtensiveHealth.AntisepticCream"] = 4,
        ["ExtensiveHealth.AntiInflammatory"] = 3,
        ["ExtensiveHealth.AntipyreticTablets"] = 3,
        ["ExtensiveHealth.AntiNauseaTablets"] = 2.5,
        ["ExtensiveHealth.ElectrolytePowder"] = 2.5,
        ["ExtensiveHealth.BronchodilatorInhaler"] = 2,
        ["ExtensiveHealth.InstantIcePack"] = 2,
        ["ExtensiveHealth.AntibioticOintment"] = 2,
        ["ExtensiveHealth.ActivatedCharcoal"] = 1.2,
    }

    local ambulanceTruckMeds = {
        ["ExtensiveHealth.SterilizedBandages"] = 14,
        ["ExtensiveHealth.AlchoholicBandage"] = 9,
        ["ExtensiveHealth.AntisepticCream"] = 10,
        ["ExtensiveHealth.AntiInflammatory"] = 8,
        ["ExtensiveHealth.AntipyreticTablets"] = 8,
        ["ExtensiveHealth.AntiNauseaTablets"] = 7,
        ["ExtensiveHealth.AntiDiarrheal"] = 5,
        ["ExtensiveHealth.ElectrolytePowder"] = 8,
        ["ExtensiveHealth.BronchodilatorInhaler"] = 5,
        ["ExtensiveHealth.CoughSyrup"] = 4,
        ["ExtensiveHealth.CoughSuppressant"] = 4,
        ["ExtensiveHealth.InstantIcePack"] = 8,
        ["ExtensiveHealth.AntibioticOintment"] = 6,
        ["ExtensiveHealth.ActivatedCharcoal"] = 4,
        ["ExtensiveHealth.OralRehydrationKit"] = 4,
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 3,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 3,
        ["ExtensiveHealth.IVKit"] = 8,
        ["ExtensiveHealth.Syringe"] = 10,
        ["ExtensiveHealth.SalineBag"] = 10,
        ["ExtensiveHealth.IVFluids"] = 8,
        ["ExtensiveHealth.Furosemide"] = 4,
        ["ExtensiveHealth.RespiratorySupportKit"] = 3,
        ["ExtensiveHealth.CorticosteroidInjection"] = 2.5,
        ["ExtensiveHealth.EmergencySepsisKit"] = 1.5,
        ["ExtensiveHealth.IVCiprofloxacin"] = 2,
        ["ExtensiveHealth.IVAntibiotics"] = 1.2,
        ["ExtensiveHealth.IVMetronidazole"] = 0.8,
        ["ExtensiveHealth.IVVancomycin"] = 0.8,
        ["ExtensiveHealth.TetanusImmunoglobulin"] = 1.5,
        ["ExtensiveHealth.AlbendazoleInjection"] = 0.4,
        ["ExtensiveHealth.IVAmphotericin"] = 0.3,
    }

    for item, chance in pairs(ambulanceGloveBoxMeds) do
        tryAddVehicleMed("AmbulanceGloveBox", item, chance)
    end
    for item, chance in pairs(ambulanceSeatMeds) do
        tryAddVehicleMed("AmbulanceSeatFront", item, chance)
    end
    for item, chance in pairs(ambulanceTruckMeds) do
        tryAddVehicleMed("AmbulanceTruckBed", item, chance)
    end
    setVehicleDistributionMinRolls("AmbulanceGloveBox", 2)
    setVehicleDistributionMinRolls("AmbulanceSeatFront", 2)
    setVehicleDistributionMinRolls("AmbulanceTruckBed", 6)

    -- Medical backpacks/satchels. Slightly richer than a generic first-aid kit,
    -- but still below clinics and pharmacies.
    local medicalBagMeds = {
        ["ExtensiveHealth.SterilizedBandages"] = 18,
        ["ExtensiveHealth.AlchoholicBandage"] = 9,
        ["ExtensiveHealth.AntisepticCream"] = 14,
        ["ExtensiveHealth.AntiInflammatory"] = 10,
        ["ExtensiveHealth.AntipyreticTablets"] = 10,
        ["ExtensiveHealth.AntiNauseaTablets"] = 8,
        ["ExtensiveHealth.AntiDiarrheal"] = 7,
        ["ExtensiveHealth.ElectrolytePowder"] = 8,
        ["ExtensiveHealth.BronchodilatorInhaler"] = 5,
        ["ExtensiveHealth.InstantIcePack"] = 7,
        ["ExtensiveHealth.AntibioticOintment"] = 6,
        ["ExtensiveHealth.Syringe"] = 4,
        ["ExtensiveHealth.ActivatedCharcoal"] = 4,
        ["ExtensiveHealth.OralRehydrationKit"] = 3,
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 3,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 1.5,
        ["ExtensiveHealth.AntiviralCapsules"] = 1.5,
        ["ExtensiveHealth.AntifungalTablets"] = 1,
        ["ExtensiveHealth.AntiparasiticPills"] = 0.8,
        ["ExtensiveHealth.SalineBag"] = 3,
        ["ExtensiveHealth.IVFluids"] = 1.5,
        ["ExtensiveHealth.IVKit"] = 1.5,
        ["ExtensiveHealth.RespiratorySupportKit"] = 0.8,
        ["ExtensiveHealth.CorticosteroidInjection"] = 0.5,
        ["ExtensiveHealth.EmergencySepsisKit"] = 0.35,
        ["ExtensiveHealth.IVCiprofloxacin"] = 0.25,
    }

    for item, chance in pairs(medicalBagMeds) do
        tryAddBagMed("Bag_MedicalBag", item, chance)
        tryAddBagMed("Bag_Satchel_Medical", item, chance * 0.75)
    end
    setBagDistributionMinRolls("Bag_MedicalBag", 4)
    setBagDistributionMinRolls("Bag_Satchel_Medical", 3)

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
        ["ExtensiveHealth.AntipyreticTablets"] = 0.3,
        ["ExtensiveHealth.CoughSyrup"] = 0.2,
        ["ExtensiveHealth.AntiNauseaTablets"] = 0.2,
        ["ExtensiveHealth.AntiDiarrheal"] = 0.2,
        ["ExtensiveHealth.AntiInflammatory"] = 0.3,
        ["ExtensiveHealth.AntisepticCream"] = 0.2,
        ["ExtensiveHealth.MuscleRelaxants"] = 0.1,
        ["ExtensiveHealth.NitricOxideBooster"] = 0.1,
    }

    -- Tier 2 Prescription - Even lower (leftover prescriptions)
    local tier2Household = {
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 0.1,
        ["ExtensiveHealth.AntibioticOintment"] = 0.15,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 0.05,
        ["ExtensiveHealth.AntiviralCapsules"] = 0.05,
        ["ExtensiveHealth.ActivatedCharcoal"] = 0.1,
        ["ExtensiveHealth.InstantIcePack"] = 0.1,
        ["ExtensiveHealth.Antipsychotics"] = 0.05,
        ["ExtensiveHealth.TopicalPermethrin"] = 0.08,
    }

    for _, container in ipairs(householdContainers) do
        -- Tier 1
        for item, chance in pairs(tier1Household) do
            tryAddMed(container, item, chance)
        end
        -- Tier 2
        if householdPrescriptionLoot then
            for item, chance in pairs(tier2Household) do
                tryAddMed(container, item, chance)
            end
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
