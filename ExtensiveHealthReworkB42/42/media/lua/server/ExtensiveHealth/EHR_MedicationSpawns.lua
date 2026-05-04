--[[
    Extensive Health Rework B42
    Medication Spawn Randomization Module

    - Full bottles spawn in pharmacies/medical locations
    - Partially used bottles spawn everywhere else (houses, etc.)
    - Slightly reduced overall spawn rates for medications
]]--

EHR = EHR or {}
EHR.MedicationSpawns = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.MedicationSpawns.Config = {
    -- Minimum remaining in non-pharmacy locations (0.2 = at least 20% left)
    minRemainingElsewhere = 0.15,
    -- Maximum remaining in non-pharmacy locations (0.85 = up to 85% left)
    maxRemainingElsewhere = 0.85,

    -- Chance for a pharmacy item to still be full (0.9 = 90% chance full)
    pharmacyFullChance = 0.90,

    -- If not full in pharmacy, minimum remaining
    pharmacyMinRemaining = 0.7,
}

-- Medication item types that should be randomized
-- Maps full item type to whether it's drainable
EHR.MedicationSpawns.DrainableMeds = {
    -- Vanilla medications
    ["Base.Pills"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.PillsVitamins"] = true,
    ["Base.Antibiotics"] = true,

    -- EHR Tier 1 - OTC
    ["ExtensiveHealth.ColdFluTablets"] = true,
    ["ExtensiveHealth.CoughSyrup"] = true,
    ["ExtensiveHealth.ElectrolytePowder"] = true,
    ["ExtensiveHealth.BronchodilatorInhaler"] = true,
    ["ExtensiveHealth.AntiNauseaTablets"] = true,
    ["ExtensiveHealth.AntiInflammatory"] = true,
    ["ExtensiveHealth.AntiDiarrheal"] = true,
    ["ExtensiveHealth.MuscleRelaxants"] = true,
    ["ExtensiveHealth.CoughSuppressant"] = true,
    ["ExtensiveHealth.AntisepticCream"] = true,

    -- EHR Tier 2 - Prescription
    ["ExtensiveHealth.AntiviralCapsules"] = true,
    ["ExtensiveHealth.PrescriptionAntibiotics"] = true,
    ["ExtensiveHealth.AntifungalTablets"] = true,
    ["ExtensiveHealth.ActivatedCharcoal"] = true,
    ["ExtensiveHealth.AntiparasiticPills"] = true,
    ["ExtensiveHealth.OralRehydrationKit"] = true,
    ["ExtensiveHealth.TBAntibiotics"] = true,
    ["ExtensiveHealth.AntibioticOintment"] = true,
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = true,

    -- EHR Tier 3 - Clinical (drainable ones)
    ["ExtensiveHealth.RifampicinComboPack"] = true,

    -- EHR Supplies
    ["ExtensiveHealth.IVKit"] = true,
    ["ExtensiveHealth.Syringe"] = true,
}

-- Room types considered "pharmacy/medical" (items spawn full here)
EHR.MedicationSpawns.MedicalRooms = {
    ["pharmacy"] = true,
    ["drugstore"] = true,
    ["medical"] = true,
    ["medclinic"] = true,
    ["hospital"] = true,
    ["emergencyroom"] = true,
    ["nursingstation"] = true,
    ["medicalstorage"] = true,
    ["ambulance"] = true,
    ["doctorsoffice"] = true,
    ["dentaloffice"] = true,
    ["optometrist"] = true,
    ["vetclinic"] = true,
}

-- ============================================
-- SPAWN RANDOMIZATION
-- ============================================

--[[
    Check if a room type is a medical/pharmacy location
    @param roomType (string)
    @return boolean
]]--
function EHR.MedicationSpawns.IsMedicalRoom(roomType)
    if not roomType then return false end
    local roomLower = string.lower(roomType)

    -- Direct match
    if EHR.MedicationSpawns.MedicalRooms[roomLower] then
        return true
    end

    -- Partial match for variations
    if string.find(roomLower, "pharm") then return true end
    if string.find(roomLower, "medic") then return true end
    if string.find(roomLower, "hospital") then return true end
    if string.find(roomLower, "clinic") then return true end
    if string.find(roomLower, "doctor") then return true end

    return false
end

--[[
    Randomize the UsedDelta of a drainable medication item.
    @param item (InventoryItem)
    @param isMedicalLocation (boolean)
]]--
function EHR.MedicationSpawns.RandomizeItemUses(item, isMedicalLocation)
    if not item then return end

    -- Check if this is a drainable item
    local useDelta = item:getUseDelta()
    if not useDelta or useDelta <= 0 then return end

    local config = EHR.MedicationSpawns.Config

    if isMedicalLocation then
        -- Pharmacy/medical: high chance of full, otherwise mostly full
        if ZombRand(100) < (config.pharmacyFullChance * 100) then
            item:setUsedDelta(0)  -- Full
        else
            -- Slightly used (someone grabbed a few before the apocalypse)
            local remaining = config.pharmacyMinRemaining + (ZombRand(30) / 100)
            remaining = math.min(remaining, 1.0)
            item:setUsedDelta(1.0 - remaining)
        end
    else
        -- Residential/other: random partial use
        local minRemain = config.minRemainingElsewhere
        local maxRemain = config.maxRemainingElsewhere
        local range = maxRemain - minRemain

        -- Random remaining amount between min and max
        local remaining = minRemain + (ZombRand(math.floor(range * 100)) / 100)
        item:setUsedDelta(1.0 - remaining)
    end
end

--[[
    Called when items are added to a container during world generation.
    @param roomType (string)
    @param containerType (string)
    @param container (ItemContainer)
]]--
function EHR.MedicationSpawns.OnFillContainer(roomType, containerType, container)
    if not container then return end

    -- B42 safety: Check if container has getItems method (ItemPickerContainer doesn't)
    if not container.getItems then return end

    local isMedical = EHR.MedicationSpawns.IsMedicalRoom(roomType)

    -- Iterate through items in container
    local items = container:getItems()
    if not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if EHR.MedicationSpawns.DrainableMeds[fullType] then
                EHR.MedicationSpawns.RandomizeItemUses(item, isMedical)
            end
        end
    end
end

-- ============================================
-- EVENT HOOKS
-- ============================================

-- Hook into container fill event
if Events.OnFillContainer then
    Events.OnFillContainer.Add(EHR.MedicationSpawns.OnFillContainer)
end

-- Log module load
if EHR.Log then
    EHR.Log("MedicationSpawns module loaded - pharmacy full, elsewhere randomized")
else
    print("[EHR] MedicationSpawns module loaded")
end
