--[[
    Extensive Health Rework B42
    Consolidated Item Distribution

    Adds EHR items to appropriate loot containers:
    - Blood bags and saline (medical facilities)
    - Medications by tier (OTC, Prescription, Clinical)
    - Disease flyers (medical literature, pharmacies, and rare household mail)
    - Syringes and IV kits

    Spawn Locations by Tier:
    - Tier 1: OTC - Pharmacies, Bathrooms, Stores, First Aid Kits
    - Tier 2: Prescription - Clinics, Pharmacies, Hospitals, rare household leftovers
    - Tier 3: Clinical - Hospitals, military/ambulance supplies, extremely rare home care

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
    MedicalCabinet = {"MedicalClinicDrugs", "MedicalStorageDrugs"},
    ArmySurplusMedical = {"ArmyStorageMedical", "MedicalStorageOutfit"},
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

local function addItemToRawDistributionFront(dist, itemName, chance)
    if dist and dist.items then
        table.insert(dist.items, 1, chance)
        table.insert(dist.items, 1, itemName)
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

local function addItemToBagDistributionFront(bagName, itemName, chance)
    local dist = SuburbsDistributions and SuburbsDistributions[bagName]
    if not dist then
        local all = SuburbsDistributions and SuburbsDistributions["all"]
        dist = all and all[bagName]
    end
    return addItemToRawDistributionFront(dist, itemName, chance)
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

    local function tryAddBagPriorityMed(bagName, itemName, chance)
        if medicationLootMultiplier <= 0 then return end
        if addItemToBagDistributionFront(bagName, itemName, chance * medicationLootMultiplier) then
            added = added + 1
        else
            failed = failed + 1
            if not failedTables[bagName] then
                failedTables[bagName] = true
            end
        end
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

    -- B42 pharmacies use StoreShelfMedical for public shelves and
    -- MedicalClinicDrugs for the counter/storage area.
    tryAdd("StoreShelfMedical", "ExtensiveHealth.SalineBag", 0.3)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.SterilizedBandages", 4)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AlchoholicBandage", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.InstantIcePack", 2)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.Furosemide", 1)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.Antipsychotics", 2)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.DualOrexinReceptor", 1.5)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.NitricOxideBooster", 2)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.TopicalPermethrin", 2)

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

    local flyerLiteratureTargets = {
        MedicalOfficeBooks = 0.25,
        HospitalMagazineRack = 0.20,
        BookstoreMedical = 0.12,
        LibraryMedical = 0.10,
        UniversityLibraryMedical = 0.15,
        UniversityDesk_Medical = 0.08,
    }

    for item, chance in pairs(flyerRarity) do
        tryAdd("MedicalStorageDrugs", item, chance)
        tryAdd("MedicalClinicDrugs", item, chance * 0.7)
        tryAdd("MedicalCabinet", item, chance * 0.4)
        tryAdd("StoreShelfMedical", item, chance * 0.15)
        tryAdd("MagazineRackMixed", item, chance * 0.12)

        for listName, multiplier in pairs(flyerLiteratureTargets) do
            tryAdd(listName, item, chance * multiplier)
        end

        -- Vanilla postboxes have two rolls. At 4% of the medical-location
        -- weight, the complete pool averages about one EHR leaflet per
        -- 35-40 mailboxes, not one per house.
        tryAddBag("postbox", item, chance * 0.04)
    end

    -- Medicine recipes
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.8)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.6)
    tryAdd("MedicalCabinet", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.25)
    tryAdd("StoreShelfMedical", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.15)
    tryAdd("MagazineRackMixed", "ExtensiveHealth.EhrRecipePlantBasedAntibiotics", 0.4)
    tryAdd("MedicalStorageDrugs", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.35)
    tryAdd("MedicalClinicDrugs", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.25)
    tryAdd("MedicalCabinet", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.08)
    tryAdd("StoreShelfMedical", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.05)
    tryAdd("MagazineRackMixed", "ExtensiveHealth.EhrRecipeUltimateCraftGuide", 0.18)

    -- =========================================
    -- TIER 1 - OTC (OVER THE COUNTER)
    -- Common locations
    -- =========================================

    -- Public pharmacy and general-store medical shelves. B42 shares this
    -- procedural list between pharmacies and the occasional supermarket aisle,
    -- so keep prescription-only items very rare here.
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.ColdFluTablets", 3.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntipyreticTablets", 3.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.CoughSyrup", 2.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.CoughSuppressant", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntiNauseaTablets", 2.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntiDiarrheal", 2.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntiInflammatory", 3.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.ElectrolytePowder", 2.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AntisepticCream", 3.5)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.MuscleRelaxants", 1.2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.BronchodilatorInhaler", 1)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.SterilizedBandages", 2)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.AlchoholicBandage", 1)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.InstantIcePack", 1)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.Antipsychotics", 0.4)
    tryAddMed("StoreShelfMedical", "ExtensiveHealth.DualOrexinReceptor", 0.35)
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
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.PrescriptionAntibiotics", 10)
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
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.BroadSpectrumAntibiotics", 8)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.SterilizedBandages", 6)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.AlchoholicBandage", 4)
    tryAddMed("MedicalClinicDrugs", "ExtensiveHealth.TopicalPermethrin", 4)

    -- Medical Storage Drugs (Tier 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.PrescriptionAntibiotics", 10)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntiviralCapsules", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.ActivatedCharcoal", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntiparasiticPills", 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.Furosemide", 4)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.Antipsychotics", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.DualOrexinReceptor", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.TetanusAntitoxin", 3)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.TBAntibiotics", 3.5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.AntibioticOintment", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.BroadSpectrumAntibiotics", 8)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.IVKit", 5)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.IVFluids", 2)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.SalineBag", 6)
    tryAddMed("MedicalStorageDrugs", "ExtensiveHealth.TopicalPermethrin", 3)

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

    -- B42 has several real medical lists that the old EHR table never touched.
    -- These cover doctor's offices, patient rooms, refrigerated supplies,
    -- military bunkers, and annotated medical safehouses.
    local secondaryMedicalTargets = {
        MedicalCabinet = 0.7,
        MedicalOfficeCounter = 0.9,
        MedicalOfficeDesk = 0.45,
        HospitalRoomCounter = 1.0,
        HospitalRoomShelves = 1.2,
    }
    local secondaryMedicalItems = {
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 4.0,
        ["ExtensiveHealth.AntiviralCapsules"] = 1.5,
        ["ExtensiveHealth.AntifungalTablets"] = 1.0,
        ["ExtensiveHealth.AntiparasiticPills"] = 0.7,
        ["ExtensiveHealth.AntibioticOintment"] = 2.0,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 3.0,
        ["ExtensiveHealth.OralRehydrationKit"] = 1.5,
        ["ExtensiveHealth.Furosemide"] = 1.0,
        ["ExtensiveHealth.Antipsychotics"] = 0.8,
        ["ExtensiveHealth.DualOrexinReceptor"] = 0.8,
        ["ExtensiveHealth.TetanusAntitoxin"] = 0.7,
        ["ExtensiveHealth.TBAntibiotics"] = 1.0,
        ["ExtensiveHealth.TopicalPermethrin"] = 1.0,
    }
    for listName, multiplier in pairs(secondaryMedicalTargets) do
        for item, chance in pairs(secondaryMedicalItems) do
            tryAddMed(listName, item, chance * multiplier)
        end
    end

    local clinicalMedicalTargets = {
        FridgeMedical = 1.8,
        MedicalClinicDrugs = 0.8,
        MedicalClinicTools = 0.35,
        MedicalStorageDrugs = 1.5,
        MedicalOfficeCounter = 0.5,
        MedicalOfficeDesk = 0.15,
        HospitalRoomShelves = 1.5,
        HospitalRoomCounter = 0.8,
        ArmyBunkerMedical = 0.8,
        SafehouseMedical = 0.6,
        SafehouseMedical_Mid = 0.3,
        SafehouseMedical_Late = 0.12,
    }
    local clinicalMedicalItems = {
        ["ExtensiveHealth.IVAntibiotics"] = 2.4,
        ["ExtensiveHealth.IVMetronidazole"] = 1.5,
        ["ExtensiveHealth.IVAmphotericin"] = 0.8,
        ["ExtensiveHealth.IVCiprofloxacin"] = 1.5,
        ["ExtensiveHealth.IVVancomycin"] = 1.2,
        ["ExtensiveHealth.IVFluids"] = 3.0,
        ["ExtensiveHealth.EmergencySepsisKit"] = 1.2,
        ["ExtensiveHealth.CorticosteroidInjection"] = 1.5,
        ["ExtensiveHealth.RespiratorySupportKit"] = 1.5,
        ["ExtensiveHealth.ChelationKit"] = 0.8,
        ["ExtensiveHealth.AlbendazoleInjection"] = 0.8,
        ["ExtensiveHealth.TetanusImmunoglobulin"] = 1.2,
        ["ExtensiveHealth.IVKit"] = 3.0,
        ["ExtensiveHealth.Syringe"] = 4.0,
        ["ExtensiveHealth.SalineBag"] = 3.0,
    }
    for listName, multiplier in pairs(clinicalMedicalTargets) do
        for item, chance in pairs(clinicalMedicalItems) do
            tryAddMed(listName, item, chance * multiplier)
        end
    end

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

    -- First-aid kits are inventory containers in B42, not procedural furniture.
    -- Populate every vanilla kit variant while preserving its native roll count.
    local firstAidKitProfiles = {
        FirstAidKit = 0.65,
        FirstAidKit_New = 1.0,
        FirstAidKit_Camping = 0.65,
        FirstAidKit_Camping_New = 0.85,
        FirstAidKit_Military = 1.0,
        FirstAidKit_Pro = 0.9,
        FirstAidKit_NewPro = 1.1,
    }
    local firstAidKitBasic = {
        ["ExtensiveHealth.AntisepticCream"] = 7,
        ["ExtensiveHealth.AntiInflammatory"] = 5,
        ["ExtensiveHealth.AntipyreticTablets"] = 4,
        ["ExtensiveHealth.ElectrolytePowder"] = 2,
        ["ExtensiveHealth.NitricOxideBooster"] = 1,
        ["ExtensiveHealth.Syringe"] = 1,
        ["ExtensiveHealth.SterilizedBandages"] = 7,
        ["ExtensiveHealth.AlchoholicBandage"] = 3,
        ["ExtensiveHealth.InstantIcePack"] = 3,
        ["ExtensiveHealth.TopicalPermethrin"] = 1,
    }
    for bagName, multiplier in pairs(firstAidKitProfiles) do
        for item, chance in pairs(firstAidKitBasic) do
            tryAddBagMed(bagName, item, chance * multiplier)
        end
    end

    -- Advanced kits can contain a small amount of prescription/emergency gear.
    local advancedFirstAidProfiles = {
        FirstAidKit_New = 0.25,
        FirstAidKit_Military = 1.0,
        FirstAidKit_Pro = 0.8,
        FirstAidKit_NewPro = 1.0,
    }
    local advancedFirstAidItems = {
        ["ExtensiveHealth.AntibioticOintment"] = 2,
        ["ExtensiveHealth.OralRehydrationKit"] = 1.5,
        ["ExtensiveHealth.BronchodilatorInhaler"] = 1.5,
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 0.8,
        ["ExtensiveHealth.IVKit"] = 0.5,
        ["ExtensiveHealth.CorticosteroidInjection"] = 0.3,
        ["ExtensiveHealth.RespiratorySupportKit"] = 0.3,
    }
    for bagName, multiplier in pairs(advancedFirstAidProfiles) do
        for item, chance in pairs(advancedFirstAidItems) do
            tryAddBagMed(bagName, item, chance * multiplier)
        end
    end

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
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 3,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 2,
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
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 8,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 8,
        ["ExtensiveHealth.TBAntibiotics"] = 1,
        ["ExtensiveHealth.IVKit"] = 18,
        ["ExtensiveHealth.Syringe"] = 22,
        ["ExtensiveHealth.SalineBag"] = 10,
        ["ExtensiveHealth.IVFluids"] = 12,
        ["ExtensiveHealth.Furosemide"] = 4,
        ["ExtensiveHealth.RespiratorySupportKit"] = 5,
        ["ExtensiveHealth.CorticosteroidInjection"] = 5,
        ["ExtensiveHealth.EmergencySepsisKit"] = 4,
        ["ExtensiveHealth.IVCiprofloxacin"] = 4,
        ["ExtensiveHealth.IVAntibiotics"] = 4,
        ["ExtensiveHealth.IVMetronidazole"] = 3,
        ["ExtensiveHealth.IVVancomycin"] = 3,
        ["ExtensiveHealth.TetanusImmunoglobulin"] = 3,
        ["ExtensiveHealth.ChelationKit"] = 2,
        ["ExtensiveHealth.AlbendazoleInjection"] = 1.5,
        ["ExtensiveHealth.IVAmphotericin"] = 1.5,
        ["ExtensiveHealth.EmptyBloodBag"] = 22,
    }

    -- A working ambulance should normally carry transfusion supplies. Filled
    -- bags retain the real-world blood-type ratios; empty bags are more common.
    for item, chance in pairs(bloodBagRarity) do
        ambulanceTruckMeds[item] = chance * 0.75
    end

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

    -- Medical backpacks/satchels. Common supplies stay in the normal pool.
    -- Capacity is limited, so emergency/clinical gear is inserted before the
    -- large vanilla pool below to prevent it being crowded out.
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
        ["ExtensiveHealth.ActivatedCharcoal"] = 4,
        ["ExtensiveHealth.OralRehydrationKit"] = 3,
        ["ExtensiveHealth.AntiviralCapsules"] = 1.5,
        ["ExtensiveHealth.AntifungalTablets"] = 1,
        ["ExtensiveHealth.AntiparasiticPills"] = 0.8,
    }

    for item, chance in pairs(medicalBagMeds) do
        tryAddBagMed("Bag_MedicalBag", item, chance)
        tryAddBagMed("Bag_Satchel_Medical", item, chance * 0.75)
    end

    local traumaBagEmergency = {
        ["ExtensiveHealth.IVKit"] = 18,
        ["ExtensiveHealth.Syringe"] = 24,
        ["ExtensiveHealth.SalineBag"] = 10,
        ["ExtensiveHealth.IVFluids"] = 8,
        ["ExtensiveHealth.EmptyBloodBag"] = 18,
        ["ExtensiveHealth.RespiratorySupportKit"] = 3,
        ["ExtensiveHealth.CorticosteroidInjection"] = 3,
        ["ExtensiveHealth.EmergencySepsisKit"] = 2.5,
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 8,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 6,
        ["ExtensiveHealth.TBAntibiotics"] = 1,
        ["ExtensiveHealth.IVCiprofloxacin"] = 2,
        ["ExtensiveHealth.IVAntibiotics"] = 2,
        ["ExtensiveHealth.IVMetronidazole"] = 1.5,
        ["ExtensiveHealth.IVVancomycin"] = 1.5,
        ["ExtensiveHealth.TetanusImmunoglobulin"] = 1.5,
        ["ExtensiveHealth.ChelationKit"] = 0.7,
        ["ExtensiveHealth.AlbendazoleInjection"] = 0.7,
        ["ExtensiveHealth.IVAmphotericin"] = 0.5,
    }
    for item, chance in pairs(bloodBagRarity) do
        traumaBagEmergency[item] = chance * 0.35
    end
    for item, chance in pairs(traumaBagEmergency) do
        tryAddBagPriorityMed("Bag_MedicalBag", item, chance)
        tryAddBagPriorityMed("Bag_Satchel_Medical", item, chance * 0.75)
    end
    setBagDistributionMinRolls("Bag_MedicalBag", 4)
    setBagDistributionMinRolls("Bag_Satchel_Medical", 3)

    -- =========================================
    -- HOUSEHOLD SPAWNS
    -- OTC is uncommon, prescriptions are rare, clinical home-care leftovers
    -- are extremely rare. Only real B42 household lists are used here.
    -- =========================================

    -- Reproduce the effective density of the previous loot table without
    -- depending on stacked B41 aliases. The former MedicineCabinet alias sent
    -- the full bathroom pool into BedroomSidetable; it now goes to real B42
    -- bathroom containers while the rest of the house keeps the old aggregate
    -- density. "common" controls OTC/prescription leftovers, "medicine" is a
    -- small fallback for houses without a bathroom cabinet, and "clinical"
    -- preserves the rarer clinical balance separately.
    local householdContainers = {
        BedroomSidetable = { common = 1.50, medicine = 0.20, clinical = 1.80 },
        BedroomSidetableClassy = { common = 1.50, medicine = 0.20, clinical = 1.80 },
        BedroomSidetableRedneck = { common = 1.50, medicine = 0.20, clinical = 1.80 },
        BedroomDresser = { common = 3.00, medicine = 0.10, clinical = 0.60 },
        BedroomDresserClassy = { common = 3.00, medicine = 0.10, clinical = 0.60 },
        BedroomDresserRedneck = { common = 3.00, medicine = 0.10, clinical = 0.60 },
        LivingRoomShelf = { common = 1.50, clinical = 0.35 },
        LivingRoomShelfClassy = { common = 1.50, clinical = 0.35 },
        LivingRoomShelfRedneck = { common = 1.50, clinical = 0.35 },
        DeskGeneric = { common = 1.50, clinical = 0.35 },
    }

    -- These are the old MedicineCabinet weights, now attached to the correct
    -- B42 containers. Part of the pool is reserved for common bedroom furniture
    -- so houses without a bathroom cabinet still have a useful medical cache.
    local bathroomContainers = {
        BathroomCabinet = { medicine = 0.65, clinical = 1.00 },
        BathroomCounter = { medicine = 0.20, clinical = 0.55 },
        BathroomShelf = { medicine = 0.20, clinical = 0.55 },
    }

    local bathroomMedicine = {
        ["ExtensiveHealth.ColdFluTablets"] = 4.0,
        ["ExtensiveHealth.AntipyreticTablets"] = 4.0,
        ["ExtensiveHealth.CoughSyrup"] = 3.0,
        ["ExtensiveHealth.AntiNauseaTablets"] = 3.0,
        ["ExtensiveHealth.AntiDiarrheal"] = 3.0,
        ["ExtensiveHealth.AntisepticCream"] = 4.0,
        ["ExtensiveHealth.AntiInflammatory"] = 3.0,
        ["ExtensiveHealth.NitricOxideBooster"] = 1.0,
        ["ExtensiveHealth.SterilizedBandages"] = 2.0,
        ["ExtensiveHealth.AlchoholicBandage"] = 1.0,
        ["ExtensiveHealth.InstantIcePack"] = 1.0,
        ["ExtensiveHealth.TopicalPermethrin"] = 1.0,
    }

    local bathroomPrescription = {
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 0.60,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 0.30,
        ["ExtensiveHealth.TBAntibiotics"] = 0.05,
        ["ExtensiveHealth.Antipsychotics"] = 1.0,
        ["ExtensiveHealth.DualOrexinReceptor"] = 0.8,
    }

    -- Tier 1 OTC - a modest chance in the bathroom, much lower elsewhere.
    local tier1Household = {
        ["ExtensiveHealth.ColdFluTablets"] = 0.3,
        ["ExtensiveHealth.AntipyreticTablets"] = 0.3,
        ["ExtensiveHealth.CoughSyrup"] = 0.2,
        ["ExtensiveHealth.CoughSuppressant"] = 0.15,
        ["ExtensiveHealth.AntiNauseaTablets"] = 0.2,
        ["ExtensiveHealth.AntiDiarrheal"] = 0.2,
        ["ExtensiveHealth.AntiInflammatory"] = 0.3,
        ["ExtensiveHealth.AntisepticCream"] = 0.2,
        ["ExtensiveHealth.MuscleRelaxants"] = 0.1,
        ["ExtensiveHealth.ElectrolytePowder"] = 0.15,
        ["ExtensiveHealth.BronchodilatorInhaler"] = 0.08,
        ["ExtensiveHealth.NitricOxideBooster"] = 0.1,
        ["ExtensiveHealth.SterilizedBandages"] = 0.15,
        ["ExtensiveHealth.InstantIcePack"] = 0.12,
    }

    -- Tier 2 Prescription - leftover personal prescriptions.
    local tier2Household = {
        ["ExtensiveHealth.PrescriptionAntibiotics"] = 0.30,
        ["ExtensiveHealth.AntibioticOintment"] = 0.15,
        ["ExtensiveHealth.BroadSpectrumAntibiotics"] = 0.15,
        ["ExtensiveHealth.AntiviralCapsules"] = 0.05,
        ["ExtensiveHealth.AntifungalTablets"] = 0.04,
        ["ExtensiveHealth.AntiparasiticPills"] = 0.03,
        ["ExtensiveHealth.ActivatedCharcoal"] = 0.08,
        ["ExtensiveHealth.OralRehydrationKit"] = 0.08,
        ["ExtensiveHealth.Furosemide"] = 0.04,
        ["ExtensiveHealth.Antipsychotics"] = 0.04,
        ["ExtensiveHealth.DualOrexinReceptor"] = 0.04,
        ["ExtensiveHealth.TopicalPermethrin"] = 0.06,
        ["ExtensiveHealth.TBAntibiotics"] = 0.03,
    }

    -- Tier 3 Clinical - uncommon home nursing/emergency remnants. Individual
    -- items remain rare; the complete pool is about 0.235 weight before the
    -- container multiplier is applied.
    local tier3Household = {
        ["ExtensiveHealth.CorticosteroidInjection"] = 0.060,
        ["ExtensiveHealth.RespiratorySupportKit"] = 0.050,
        ["ExtensiveHealth.IVFluids"] = 0.050,
        ["ExtensiveHealth.IVAntibiotics"] = 0.015,
        ["ExtensiveHealth.IVCiprofloxacin"] = 0.010,
        ["ExtensiveHealth.IVMetronidazole"] = 0.008,
        ["ExtensiveHealth.IVAmphotericin"] = 0.005,
        ["ExtensiveHealth.IVVancomycin"] = 0.008,
        ["ExtensiveHealth.ChelationKit"] = 0.005,
        ["ExtensiveHealth.AlbendazoleInjection"] = 0.008,
        ["ExtensiveHealth.TetanusImmunoglobulin"] = 0.008,
        ["ExtensiveHealth.EmergencySepsisKit"] = 0.008,
    }

    local function accumulateWeights(target, source, multiplier)
        if not multiplier or multiplier <= 0 then return end
        for item, chance in pairs(source) do
            target[item] = (target[item] or 0) + chance * multiplier
        end
    end

    for container, multipliers in pairs(householdContainers) do
        -- Merge overlapping pools before insertion so the fallback does not
        -- recreate the duplicate entries that existed in the old alias table.
        local commonWeights = {}
        accumulateWeights(commonWeights, tier1Household, multipliers.common)
        accumulateWeights(commonWeights, bathroomMedicine, multipliers.medicine)
        for item, chance in pairs(commonWeights) do
            tryAddMed(container, item, chance)
        end

        -- Tier 2 and 3 share the existing household prescription sandbox toggle.
        if householdPrescriptionLoot then
            local prescriptionWeights = {}
            accumulateWeights(prescriptionWeights, tier2Household, multipliers.common)
            accumulateWeights(prescriptionWeights, bathroomPrescription, multipliers.medicine)
            for item, chance in pairs(prescriptionWeights) do
                tryAddMed(container, item, chance)
            end
            for item, chance in pairs(tier3Household) do
                tryAddMed(container, item, chance * multipliers.clinical)
            end
        end
    end

    for container, multipliers in pairs(bathroomContainers) do
        for item, chance in pairs(bathroomMedicine) do
            tryAddMed(container, item, chance * multipliers.medicine)
        end
        if householdPrescriptionLoot then
            for item, chance in pairs(bathroomPrescription) do
                tryAddMed(container, item, chance * multipliers.medicine)
            end
            for item, chance in pairs(tier3Household) do
                tryAddMed(container, item, chance * multipliers.clinical)
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

    print("[EHR] Distributions loaded - Added: " .. added .. ", Failed: " .. failed
        .. ", MedicationLootMultiplier: " .. tostring(medicationLootMultiplier)
        .. ", HouseholdPrescriptionLoot: " .. tostring(householdPrescriptionLoot))
    if failedTableCount > 0 then
        print("[EHR] Missing distribution tables (" .. failedTableCount .. "): " .. table.concat(failedTableList, ", "))
        print("[EHR] Note: Some B42 distribution tables may have different names from B41")
    end

    log("[EHR] Loot distribution initialized for blood bags, medications, and flyers")
end

-- Register with distribution system
Events.OnPreDistributionMerge.Add(EHR_InitDistributions)
