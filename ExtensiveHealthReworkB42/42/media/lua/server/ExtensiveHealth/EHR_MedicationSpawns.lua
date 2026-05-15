--[[
    Extensive Health Rework B42
    Medication Spawn Randomization Module

    - Pharmacies can occasionally spawn full packages
    - Other locations are capped below full and randomized by sandbox profile
    - Remaining uses are rounded to whole doses
]]--

EHR = EHR or {}
EHR.MedicationSpawns = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.MedicationSpawns.Config = {
    DefaultFillProfile = 3,

    -- Fill ranges are percentages of max doses left. Non-pharmacy locations cap at 70%.
    FillProfiles = {
        -- Scarce
        [1] = {
            pharmacyFullChance = 0.08,
            ranges = {
                pharmacy = {0.25, 0.65},
                medical = {0.15, 0.45},
                ambulance = {0.10, 0.40},
                household = {0.02, 0.25},
                military = {0.20, 0.50},
                default = {0.02, 0.30},
            },
        },
        -- Low
        [2] = {
            pharmacyFullChance = 0.15,
            ranges = {
                pharmacy = {0.35, 0.80},
                medical = {0.25, 0.60},
                ambulance = {0.18, 0.55},
                household = {0.04, 0.35},
                military = {0.30, 0.60},
                default = {0.05, 0.40},
            },
        },
        -- Normal
        [3] = {
            pharmacyFullChance = 0.25,
            ranges = {
                pharmacy = {0.45, 0.90},
                medical = {0.35, 0.70},
                ambulance = {0.25, 0.70},
                household = {0.05, 0.45},
                military = {0.40, 0.70},
                default = {0.10, 0.50},
            },
        },
        -- Generous
        [4] = {
            pharmacyFullChance = 0.35,
            ranges = {
                pharmacy = {0.60, 0.95},
                medical = {0.45, 0.70},
                ambulance = {0.35, 0.70},
                household = {0.10, 0.60},
                military = {0.50, 0.70},
                default = {0.15, 0.60},
            },
        },
    },
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
    ["ExtensiveHealth.AntipyreticTablets"] = true,
    ["ExtensiveHealth.CoughSyrup"] = true,
    ["ExtensiveHealth.ElectrolytePowder"] = true,
    ["ExtensiveHealth.BronchodilatorInhaler"] = true,
    ["ExtensiveHealth.AntiNauseaTablets"] = true,
    ["ExtensiveHealth.AntiInflammatory"] = true,
    ["ExtensiveHealth.AntiDiarrheal"] = true,
    ["ExtensiveHealth.MuscleRelaxants"] = true,
    ["ExtensiveHealth.NitricOxideBooster"] = true,
    ["ExtensiveHealth.CoughSuppressant"] = true,
    ["ExtensiveHealth.AntisepticCream"] = true,

    -- EHR Tier 2 - Prescription
    ["ExtensiveHealth.AntiviralCapsules"] = true,
    ["ExtensiveHealth.PrescriptionAntibiotics"] = true,
    ["ExtensiveHealth.AntifungalTablets"] = true,
    ["ExtensiveHealth.ActivatedCharcoal"] = true,
    ["ExtensiveHealth.AntiparasiticPills"] = true,
    ["ExtensiveHealth.TopicalPermethrin"] = true,
    ["ExtensiveHealth.OralRehydrationKit"] = true,
    ["ExtensiveHealth.InstantIcePack"] = true,
    ["ExtensiveHealth.Furosemide"] = true,
    ["ExtensiveHealth.Antipsychotics"] = true,
    ["ExtensiveHealth.TBAntibiotics"] = true,
    ["ExtensiveHealth.AntibioticOintment"] = true,
    ["ExtensiveHealth.BroadSpectrumAntibiotics"] = true,
    ["ExtensiveHealth.PlantBasedAntibiotics"] = true,

    -- EHR Tier 3 - Clinical (drainable ones)
    ["ExtensiveHealth.RifampicinComboPack"] = true,
    ["ExtensiveHealth.RespiratorySupportKit"] = true,

    -- EHR Supplies
    ["ExtensiveHealth.IVKit"] = true,
    ["ExtensiveHealth.Syringe"] = true,
    ["ExtensiveHealth.SterilizedBandages"] = true,

    -- Knox treatment
    ["ExtensiveHealth.PhalanxPills"] = true,
}

-- ============================================
-- SPAWN RANDOMIZATION
-- ============================================

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getSandbox()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        return SandboxVars.ExtensiveHealthRework
    end
    return nil
end

function EHR.MedicationSpawns.GetFillProfile()
    local sandbox = getSandbox()
    local profileIndex = EHR.MedicationSpawns.Config.DefaultFillProfile

    if sandbox and sandbox.MedicationPackageFill then
        profileIndex = tonumber(sandbox.MedicationPackageFill) or profileIndex
    end

    profileIndex = clamp(math.floor(profileIndex), 1, 4)
    return EHR.MedicationSpawns.Config.FillProfiles[profileIndex]
end

function EHR.MedicationSpawns.AllowFullPharmacyPackages()
    local sandbox = getSandbox()
    if sandbox and sandbox.AllowFullPharmacyPackages ~= nil then
        return sandbox.AllowFullPharmacyPackages == true
    end
    return true
end

function EHR.MedicationSpawns.GetLocationType(roomType, containerType)
    local text = string.lower(tostring(roomType or "") .. " " .. tostring(containerType or ""))

    if string.find(text, "pharm") or string.find(text, "drugstore") then
        return "pharmacy"
    end
    if string.find(text, "ambulance") then
        return "ambulance"
    end
    if string.find(text, "army") or string.find(text, "military") then
        return "military"
    end
    if string.find(text, "medical") or string.find(text, "medic")
        or string.find(text, "hospital") or string.find(text, "clinic")
        or string.find(text, "doctor") or string.find(text, "nursing")
        or string.find(text, "emergency") or string.find(text, "vetclinic") then
        return "medical"
    end
    if string.find(text, "bathroom") or string.find(text, "bedroom")
        or string.find(text, "sidetable") or string.find(text, "dresser")
        or string.find(text, "wardrobe") or string.find(text, "livingroom")
        or string.find(text, "shelf") or string.find(text, "desk")
        or string.find(text, "filing") then
        return "household"
    end

    return "default"
end

--[[
    Check if a room type is a medical/pharmacy location
    @param roomType (string)
    @return boolean
]]--
function EHR.MedicationSpawns.IsMedicalRoom(roomType)
    local locationType = EHR.MedicationSpawns.GetLocationType(roomType, nil)
    return locationType == "pharmacy"
        or locationType == "medical"
        or locationType == "ambulance"
        or locationType == "military"
end

function EHR.MedicationSpawns.GetDoseCapacity(item, useDelta)
    if not item or not useDelta or useDelta <= 0 then return 1 end
    return math.max(1, math.floor((1.0 / useDelta) + 0.5))
end

function EHR.MedicationSpawns.PickDoseCount(maxDoses, minRemaining, maxRemaining)
    maxDoses = math.max(1, maxDoses or 1)
    minRemaining = clamp(minRemaining or 0.05, 0.0, 1.0)
    maxRemaining = clamp(maxRemaining or minRemaining, minRemaining, 1.0)

    local minDoses = math.max(1, math.ceil(maxDoses * minRemaining))
    local maxAllowed = math.max(minDoses, math.floor(maxDoses * maxRemaining))
    maxAllowed = math.min(maxAllowed, maxDoses)

    if maxAllowed <= minDoses then
        return minDoses
    end

    return minDoses + ZombRand((maxAllowed - minDoses) + 1)
end

--[[
    Randomize the UsedDelta of a drainable medication item.
    @param item (InventoryItem)
    @param locationType (string)
]]--
function EHR.MedicationSpawns.RandomizeItemUses(item, locationType)
    if not item then return end
    if not item.getUseDelta or not item.setUsedDelta then return end

    -- Check if this is a drainable item
    local useDelta = item:getUseDelta()
    if not useDelta or useDelta <= 0 then return end

    local profile = EHR.MedicationSpawns.GetFillProfile()
    local location = locationType or "default"

    if location == "pharmacy" and EHR.MedicationSpawns.AllowFullPharmacyPackages() then
        if ZombRand(100) < ((profile.pharmacyFullChance or 0) * 100) then
            item:setUsedDelta(1.0)
            return
        end
    end

    local range = (profile.ranges and profile.ranges[location]) or profile.ranges.default
    local minRemaining = range[1] or 0.05
    local maxRemaining = range[2] or minRemaining
    local maxDoses = EHR.MedicationSpawns.GetDoseCapacity(item, useDelta)
    local dosesLeft = EHR.MedicationSpawns.PickDoseCount(maxDoses, minRemaining, maxRemaining)

    local usedDelta = dosesLeft * useDelta
    if dosesLeft >= maxDoses then
        usedDelta = 1.0
    end
    usedDelta = clamp(usedDelta, useDelta, 1.0)

    item:setUsedDelta(usedDelta)
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

    local locationType = EHR.MedicationSpawns.GetLocationType(roomType, containerType)

    -- Iterate through items in container
    local items = container:getItems()
    if not items then return end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if EHR.MedicationSpawns.DrainableMeds[fullType] then
                EHR.MedicationSpawns.RandomizeItemUses(item, locationType)
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
    EHR.Log("MedicationSpawns module loaded - sandbox fill profiles active")
else
    print("[EHR] MedicationSpawns module loaded")
end
