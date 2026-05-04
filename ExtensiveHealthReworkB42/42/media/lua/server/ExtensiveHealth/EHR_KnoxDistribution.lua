--[[
    Extensive Health Rework B42
    Knox Cure Item Distribution

    These ultra-rare items ONLY spawn in the Military Research Facility
    near Rosewood (X: 5564, Y: 12476) - specifically in the basements.

    Spawn Tiers by Depth:
    - Basement Level 1 (z=-1): Phalanx Pills, Antibody Test, Immunobooster
    - Basement Level 2+ (z<=-2): Gene Therapy Kit (rarest)

    v1.0.0
]]--

EHR = EHR or {}
EHR.KnoxDistribution = {}

-- ============================================
-- MILITARY RESEARCH FACILITY BOUNDS
-- ============================================

-- Facility location bounds (generous padding)
EHR.KnoxDistribution.FacilityBounds = {
    minX = 5480,
    maxX = 5660,
    minY = 12390,
    maxY = 12560,
}

-- ============================================
-- SPAWN CONFIGURATION
-- ============================================

-- Items that can spawn at basement level 1 (z = -1)
EHR.KnoxDistribution.Basement1Items = {
    { item = "ExtensiveHealth.PhalanxPills", chance = 3 },
    { item = "ExtensiveHealth.AntibodyTestKit", chance = 4 },
    { item = "ExtensiveHealth.ImmunoboosterShot", chance = 2 },
}

-- Items that can spawn at basement level 2+ (z <= -2)
EHR.KnoxDistribution.Basement2Items = {
    { item = "ExtensiveHealth.GeneTherapyKit", chance = 1 },  -- Ultra rare
    { item = "ExtensiveHealth.PhalanxPills", chance = 5 },
    { item = "ExtensiveHealth.AntibodyTestKit", chance = 6 },
    { item = "ExtensiveHealth.ImmunoboosterShot", chance = 4 },
}

-- Container types that can hold Knox items
EHR.KnoxDistribution.ValidContainers = {
    ["crate"] = true,
    ["metal_shelves"] = true,
    ["shelves"] = true,
    ["counter"] = true,
    ["desk"] = true,
    ["filingcabinet"] = true,
    ["locker"] = true,
    ["militarycrate"] = true,
    ["medicalcabinet"] = true,
    ["militarylocker"] = true,
    ["cardboardbox"] = true,
    ["bin"] = true,
    ["wardrobe"] = true,
    ["dresser"] = true,
}

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

--[[
    Check if coordinates are within the Military Research Facility
]]--
function EHR.KnoxDistribution.IsInFacility(x, y)
    local bounds = EHR.KnoxDistribution.FacilityBounds
    return x >= bounds.minX and x <= bounds.maxX and
           y >= bounds.minY and y <= bounds.maxY
end

--[[
    Check if a container type is valid for Knox item spawns
]]--
function EHR.KnoxDistribution.IsValidContainer(containerType)
    if not containerType then return false end
    local lowerType = string.lower(containerType)

    -- Check exact match
    if EHR.KnoxDistribution.ValidContainers[lowerType] then
        return true
    end

    -- Check partial match (for variations like "metal_shelves_2")
    for validType, _ in pairs(EHR.KnoxDistribution.ValidContainers) do
        if string.find(lowerType, validType) then
            return true
        end
    end

    return false
end

--[[
    Roll for item spawn based on chance (out of 100)
]]--
function EHR.KnoxDistribution.RollSpawn(chance)
    local roll = ZombRand(100) + 1
    return roll <= chance
end

-- ============================================
-- CONTAINER FILL HANDLER
-- ============================================

--[[
    Check if Knox Cure items are enabled in sandbox settings
]]--
function EHR.KnoxDistribution.IsEnabled()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        return SandboxVars.ExtensiveHealthRework.KnoxCureItemsEnabled ~= false
    end
    return true  -- Default enabled
end

--[[
    Called when a container is filled with loot
    Adds Knox cure items to containers in the Military Research Facility basements
]]--
function EHR.KnoxDistribution.OnFillContainer(roomName, containerType, container)
    -- Check if Knox items are enabled
    if not EHR.KnoxDistribution.IsEnabled() then return end

    -- Safety checks
    if not container then return end

    -- B42 safety: Check if container has getParent method (ItemPickerContainer doesn't)
    if not container.getParent then return end

    -- Get container position
    local parent = container:getParent()
    if not parent then return end

    -- Ensure parent has coordinate methods
    if not parent.getX then return end

    local x = parent:getX()
    local y = parent:getY()
    local z = parent:getZ()

    -- Must be in the facility
    if not EHR.KnoxDistribution.IsInFacility(x, y) then
        return
    end

    -- Must be in a basement (z < 0)
    if z >= 0 then
        return
    end

    -- Must be a valid container type
    if not EHR.KnoxDistribution.IsValidContainer(containerType) then
        return
    end

    -- Select item list based on depth
    local itemList
    if z <= -2 then
        -- Deep basement - all items including Gene Therapy
        itemList = EHR.KnoxDistribution.Basement2Items
    else
        -- First basement - common Knox items only
        itemList = EHR.KnoxDistribution.Basement1Items
    end

    -- Roll for each item
    for _, itemData in ipairs(itemList) do
        if EHR.KnoxDistribution.RollSpawn(itemData.chance) then
            container:AddItem(itemData.item)
        end
    end
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if not EHR.KnoxDistribution._registered then
    EHR.KnoxDistribution._registered = true

    -- Register container fill event
    Events.OnFillContainer.Add(EHR.KnoxDistribution.OnFillContainer)

    print("[EHR] Knox Cure distribution registered for Military Research Facility")
    print("[EHR] Knox items spawn location: X:5480-5660, Y:12390-12560 (basements)")
    print("[EHR] Knox items can be disabled via sandbox setting: EHR: Knox Virus Cure")
end
