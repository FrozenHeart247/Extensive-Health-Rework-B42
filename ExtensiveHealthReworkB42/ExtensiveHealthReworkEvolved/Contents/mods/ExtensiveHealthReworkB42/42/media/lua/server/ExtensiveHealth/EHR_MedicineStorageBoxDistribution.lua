--[[
    Extensive Health Rework B42
    Medicine Storage Box loot distribution

    The box has its own nested-container distribution: three prescription
    rolls plus one clinical roll. Spawn injection is additive and does not
    replace any vanilla or third-party distribution table.
]]--

require "Items/SuburbsDistributions"
require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"

EHR = EHR or {}
EHR.MedicineStorageBox = EHR.MedicineStorageBox or {}

local MedicineStorageBox = EHR.MedicineStorageBox
local BOX_ITEM = "ExtensiveHealth.MedicineStorageBox"
local BOX_CONTAINER_TYPE = "MedicineStorageBox"

local prescriptionItems = {
    "ExtensiveHealth.PrescriptionAntibiotics", 16,
    "ExtensiveHealth.BroadSpectrumAntibiotics", 12,
    "ExtensiveHealth.AntibioticOintment", 10,
    "ExtensiveHealth.AntiviralCapsules", 8,
    "ExtensiveHealth.ActivatedCharcoal", 7,
    "ExtensiveHealth.AntifungalTablets", 6,
    "ExtensiveHealth.OralRehydrationKit", 6,
    "ExtensiveHealth.TopicalPermethrin", 5,
    "ExtensiveHealth.AntiparasiticPills", 4,
    "ExtensiveHealth.Furosemide", 4,
    "ExtensiveHealth.Antipsychotics", 4,
    "ExtensiveHealth.DualOrexinReceptor", 4,
    "ExtensiveHealth.Buprenorphine", 4,
    "ExtensiveHealth.TetanusAntitoxin", 3,
    "ExtensiveHealth.TBAntibiotics", 3,
}

local clinicalItems = {
    "ExtensiveHealth.IVFluids", 8,
    "ExtensiveHealth.IVAntibiotics", 6,
    "ExtensiveHealth.CorticosteroidInjection", 5,
    "ExtensiveHealth.RespiratorySupportKit", 4,
    "ExtensiveHealth.IVCiprofloxacin", 3,
    "ExtensiveHealth.IVMetronidazole", 3,
    "ExtensiveHealth.IVVancomycin", 2.5,
    "ExtensiveHealth.EmergencySepsisKit", 2,
    "ExtensiveHealth.TetanusImmunoglobulin", 2,
    "ExtensiveHealth.IVAmphotericin", 1.5,
    "ExtensiveHealth.ChelationKit", 1.5,
    "ExtensiveHealth.AlbendazoleInjection", 1.5,
    "ExtensiveHealth.LastChanceEpinephrine", 1.0,
}

local medicalSpawns = {
    MedicalStorageDrugs = 20,
    MedicalClinicDrugs = 16,
    MedicalStorageOutfit = 14,
    MedicalClinicTools = 12,
    HospitalRoomShelves = 16,
    HospitalRoomCounter = 12,
    MedicalOfficeCounter = 12,
    MedicalOfficeDesk = 7,
    MedicalCabinet = 12,
    ArmyBunkerMedical = 12,
    AmbulanceMedical = 8,
}

local ambulanceSpawns = {
    AmbulanceTruckBed = 7,
    AmbulanceSeatFront = 1.5,
    AmbulanceGloveBox = 1,
}

local bathroomSpawns = {
    BathroomCabinet = 0.08,
    BathroomCounter = 0.03,
    BathroomShelf = 0.03,
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

local function getMedicationLootMultiplier()
    local sandbox = getSandbox()
    local value = sandbox and tonumber(sandbox.MedicationLootMultiplier) or nil
    return clamp(value or 1.0, 0.0, 2.0)
end

local function isHouseholdPrescriptionLootEnabled()
    local sandbox = getSandbox()
    if sandbox and sandbox.HouseholdPrescriptionLoot ~= nil then
        return sandbox.HouseholdPrescriptionLoot == true
    end
    return true
end

local function containsItem(items, itemType)
    if not items then return false end
    for index = 1, #items, 2 do
        if items[index] == itemType then
            return true
        end
    end
    return false
end

local function addToDistribution(distribution, itemType, weight)
    if not distribution or not distribution.items or weight <= 0 then
        return false
    end
    if containsItem(distribution.items, itemType) then
        return false
    end
    table.insert(distribution.items, itemType)
    table.insert(distribution.items, weight)
    return true
end

local function defineBoxContents()
    SuburbsDistributions[BOX_CONTAINER_TYPE] = {
        rolls = 3,
        items = prescriptionItems,
        -- ItemPicker always processes this secondary pool. Using it for one
        -- clinical roll guarantees that every naturally filled box contains
        -- both tiers without introducing non-medication filler.
        junk = {
            rolls = 1,
            items = clinicalItems,
        },
    }
end

function MedicineStorageBox.InitDistributions()
    defineBoxContents()

    local multiplier = getMedicationLootMultiplier()
    if multiplier <= 0 then
        print("[EHR] Medicine Storage Box distribution disabled by MedicationLootMultiplier")
        return
    end

    local added = 0
    local missing = {}

    for distributionName, weight in pairs(medicalSpawns) do
        local distribution = ProceduralDistributions
            and ProceduralDistributions.list
            and ProceduralDistributions.list[distributionName]
        if addToDistribution(distribution, BOX_ITEM, weight * multiplier) then
            added = added + 1
        elseif not distribution then
            table.insert(missing, distributionName)
        end
    end

    for distributionName, weight in pairs(ambulanceSpawns) do
        local distribution = VehicleDistributions and VehicleDistributions[distributionName]
        if addToDistribution(distribution, BOX_ITEM, weight * multiplier) then
            added = added + 1
        elseif not distribution then
            table.insert(missing, distributionName)
        end
    end

    if isHouseholdPrescriptionLootEnabled() then
        for distributionName, weight in pairs(bathroomSpawns) do
            local distribution = ProceduralDistributions
                and ProceduralDistributions.list
                and ProceduralDistributions.list[distributionName]
            if addToDistribution(distribution, BOX_ITEM, weight * multiplier) then
                added = added + 1
            elseif not distribution then
                table.insert(missing, distributionName)
            end
        end
    end

    print("[EHR] Medicine Storage Box distributions loaded - Added: " .. tostring(added)
        .. ", MedicationLootMultiplier: " .. tostring(multiplier))
    if #missing > 0 then
        print("[EHR] Medicine Storage Box missing distribution tables: " .. table.concat(missing, ", "))
    end
end

Events.OnPreDistributionMerge.Add(MedicineStorageBox.InitDistributions)

