-- Extensive Health Rework B42
-- Server-side validation and rewards for medicinal plant search.

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.HerbalSearchServer = EHR.HerbalSearchServer or {}

local COOLDOWN_HOURS = 24
local HERB_POOLS = {
    common = {
        "Base.Plantain", "Base.CommonMallow", "Base.Chamomile", "Base.Marigold",
        "Base.Lavender", "Base.WildGarlic2", "Base.BerryBlack", "Base.BerryBlue",
        "Base.BerryGeneric1", "Base.BerryGeneric2", "Base.BerryGeneric3",
        "Base.BerryGeneric4", "Base.BerryGeneric5",
    },
    rare = { "Base.BlackSage", "Base.Comfrey", "Base.Ginseng" },
}

local function log(msg)
    if EHR and EHR.Log then EHR.Log(tostring(msg)) else print("[EHR HerbalSearch] " .. tostring(msg)) end
end

local function rand(max)
    max = tonumber(max) or 0
    if max <= 0 then return 0 end
    if ZombRand then return ZombRand(max) end
    return math.random(0, max - 1)
end

local function text(key, fallback, a)
    local fullKey = "UI_EHR_HerbalSearch_" .. tostring(key)
    local value = fallback
    if EHR and EHR.Locale and EHR.Locale.Text then value = EHR.Locale.Text(fullKey, fallback)
    elseif getText then
        local ok, got = pcall(getText, fullKey)
        if ok and got and got ~= fullKey then value = got end
    end
    if a ~= nil then value = tostring(value):gsub("%%1", tostring(a)):gsub("%%s", tostring(a)) end
    return value
end

local function say(player, key, fallback, a)
    if not player then return end
    local msg = text(key, fallback, a)
    if EHR and EHR.Locale and EHR.Locale.Say then EHR.Locale.Say(player, msg)
    elseif player.Say then player:Say(msg) end
end

local function getPerkLevel(player, perk)
    if not player or not perk or not player.getPerkLevel then return 0 end
    local ok, level = pcall(function() return player:getPerkLevel(perk) end)
    if ok then return tonumber(level) or 0 end
    return 0
end

local function getSquare(args)
    if not args then return nil end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 0
    if not x or not y then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    return ok and square or nil
end

local function distanceToSquare(player, square)
    if not player or not square then return 999 end
    local dx = (player:getX() or 0) - ((square.getX and square:getX()) or 0)
    local dy = (player:getY() or 0) - ((square.getY and square:getY()) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function spriteName(obj)
    if not obj then return nil end
    local sprite, name = nil, nil
    pcall(function() sprite = obj:getSprite() end)
    if sprite then pcall(function() name = sprite:getName() end) end
    return name and tostring(name):lower() or nil
end

local function objectLooksNatural(obj)
    local name = spriteName(obj)
    if not name then return false end
    return name:find("vegetation", 1, true) ~= nil
        or name:find("bush", 1, true) ~= nil
        or name:find("shrub", 1, true) ~= nil
        or name:find("tree", 1, true) ~= nil
        or name:find("grass", 1, true) ~= nil
        or name:find("flower", 1, true) ~= nil
        or name:find("natural", 1, true) ~= nil
        or name:find("foliage", 1, true) ~= nil
        or name:find("blends_natural", 1, true) ~= nil
        or name:find("d_floorblends", 1, true) ~= nil
end

local function squareLooksNatural(square)
    if not square then return false end
    local room = nil
    pcall(function() room = square:getRoom() end)
    if room then return false end
    local objects = nil
    pcall(function() objects = square:getObjects() end)
    if objects then
        for i = 0, objects:size() - 1 do
            if objectLooksNatural(objects:get(i)) then return true end
        end
    end
    return false
end

local function getZoneType(square)
    local zone, zoneType = nil, nil
    pcall(function() zone = square and square:getZone() or nil end)
    if zone then pcall(function() zoneType = zone:getType() end) end
    return tostring(zoneType or "")
end

local function zoneBaseChance(square)
    local zone = getZoneType(square):lower()
    if zone:find("deepforest", 1, true) then return 46 end
    if zone:find("forest", 1, true) then return 37 end
    if zone:find("vegetation", 1, true) or zone:find("vegitation", 1, true) then return 30 end
    if zone:find("farm", 1, true) or zone:find("garden", 1, true) then return 24 end
    return 16
end

local function seasonMultiplier()
    local month = nil
    pcall(function() month = getGameTime():getMonth() end)
    month = tonumber(month)
    if month == nil then return 1.0 end
    if month == 11 or month == 0 or month == 1 then return 0.58 end
    if month >= 3 and month <= 7 then return 1.15 end
    return 0.92
end

local function itemExists(itemType)
    if not itemType then return false end
    local ok, item = pcall(function()
        if getScriptManager then return getScriptManager():FindItem(itemType) end
        if ScriptManager and ScriptManager.instance then return ScriptManager.instance:FindItem(itemType) end
        return nil
    end)
    return ok and item ~= nil
end

local function chooseExisting(pool)
    local candidates = {}
    for _, itemType in ipairs(pool or {}) do
        if itemExists(itemType) then candidates[#candidates + 1] = itemType end
    end
    if #candidates == 0 then return nil end
    return candidates[rand(#candidates) + 1]
end

local function syncAdded(container, item)
    if not item then return end
    if container and sendAddItemToContainer then pcall(function() sendAddItemToContainer(container, item) end) end
    if sendItemStats then pcall(function() sendItemStats(item) end) end
end

local function addItem(player, itemType)
    if not player or not itemType then return nil end
    local inventory = player:getInventory()
    if not inventory then return nil end
    local ok, item = pcall(function() return inventory:AddItem(itemType) end)
    if ok and item then syncAdded(inventory, item); return item end
    return nil
end

local function displayName(itemType)
    local scriptItem = nil
    pcall(function() if getScriptManager then scriptItem = getScriptManager():FindItem(itemType) end end)
    if scriptItem then
        local name = nil
        pcall(function() name = scriptItem:getDisplayName() end)
        if name and tostring(name) ~= "" then return tostring(name) end
    end
    return tostring(itemType or "")
end

local function isHandWearLocation(location)
    local loc = tostring(location or ""):lower()
    return loc == "hands" or loc == "base:hands" or loc == "handsleft" or loc == "handsright"
end

local function isBrokenOrHoled(item)
    if not item then return true end
    local holes = 0
    pcall(function()
        if item.getHolesNumber then holes = tonumber(item:getHolesNumber()) or 0 end
    end)
    if holes > 0 then return true end

    local condition, conditionMax = nil, nil
    pcall(function() if item.getCondition then condition = tonumber(item:getCondition()) end end)
    pcall(function() if item.getConditionMax then conditionMax = tonumber(item:getConditionMax()) end end)
    if condition and condition <= 0 then return true end
    if condition and conditionMax and conditionMax > 0 and (condition / conditionMax) <= 0.05 then return true end
    return false
end

local function hasIntactGloves(player)
    if not player then return false end

    if player.getWornItem and ItemBodyLocation then
        local locations = { ItemBodyLocation.HANDS, ItemBodyLocation.HANDS_LEFT, ItemBodyLocation.HANDS_RIGHT }
        for _, location in ipairs(locations) do
            local item = nil
            pcall(function() if location then item = player:getWornItem(location) end end)
            if item and not isBrokenOrHoled(item) then return true end
        end
    end

    if not player.getWornItems then return false end
    local wornItems = player:getWornItems()
    if not wornItems then return false end
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item then
            local location = nil
            pcall(function() if item.getBodyLocation then location = item:getBodyLocation() end end)
            if not location then pcall(function() if item.getLocation then location = item:getLocation() end end) end
            if isHandWearLocation(location) and not isBrokenOrHoled(item) then return true end
        end
    end
    return false
end

local function randomBodyPart(player)
    if not player or not BodyPartType then return nil end
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return nil end
    local names = {
        "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R", "Hand_L", "Hand_R",
    }
    for _ = 1, 12 do
        local partType = BodyPartType[names[rand(#names) + 1]]
        if partType then
            local ok, part = pcall(function() return bodyDamage:getBodyPart(partType) end)
            if ok and part then return part end
        end
    end
    return nil
end

local function applyScratch(player)
    if hasIntactGloves(player) then return false end
    local part = randomBodyPart(player)
    if not part then return false end
    local changed = false
    if part.setScratched then changed = pcall(function() part:setScratched(true, false) end) or changed end
    if part.getScratchTime and part.setScratchTime then
        pcall(function()
            local current = tonumber(part:getScratchTime()) or 0
            if current < 10 then part:setScratchTime(10 + rand(8)); changed = true end
        end)
    end
    if part.getAdditionalPain and part.setAdditionalPain then
        pcall(function()
            local pain = tonumber(part:getAdditionalPain()) or 0
            if pain < 7 then part:setAdditionalPain(7); changed = true end
        end)
    end
    if changed then
        pcall(function() syncBodyPart(part, 0x00570188) end)
        local bd = player:getBodyDamage()
        if bd and bd.DamageUpdate then pcall(function() bd:DamageUpdate() end) end
    end
    return changed
end

function EHR.HerbalSearchServer.UnlockKnowledge(player, args)
    if not player then return end
    local data = player:getModData()
    if not data then return end
    data.EHR_MedicalWildPlantsKnown = true
    data.EHR_MedicalWildPlantsReadHour = getGameTime():getWorldAgeHours()
    if EHR and EHR.SafeTransmitModData then EHR.SafeTransmitModData(player) end
end

function EHR.HerbalSearchServer.Hazard(player, args)
    local square = getSquare(args)
    if not player or not square or distanceToSquare(player, square) > 4.5 then return end
    applyScratch(player)
end

function EHR.HerbalSearchServer.Complete(player, args)
    if not player or not args then return end
    local square = getSquare(args)
    if not square or distanceToSquare(player, square) > 4.5 or not squareLooksNatural(square) then return end

    local md = square:getModData()
    local now = getGameTime():getWorldAgeHours()
    local last = tonumber(md.EHR_HerbalSearchLastHour)
    if last and now - last < COOLDOWN_HOURS then
        say(player, "Depleted", "This patch has already been searched recently.")
        return
    end
    md.EHR_HerbalSearchLastHour = now
    if square.transmitModData then pcall(function() square:transmitModData() end) end

    local firstAid = getPerkLevel(player, Perks and Perks.Doctor)
    local foraging = getPerkLevel(player, Perks and Perks.PlantScavenging)
    local quality = tonumber(args.quality) or 0.1
    if quality < 0 then quality = 0 end
    if quality > 1 then quality = 1 end

    local chance = zoneBaseChance(square) * seasonMultiplier()
    chance = chance * (0.42 + quality * 0.96) + math.min(12, (firstAid + foraging) * 0.75)
    if chance > 78 then chance = 78 end
    if chance < 4 then chance = 4 end

    if (rand(10000) / 100) > chance then
        say(player, "None", "There is nothing useful here.")
        return
    end

    local rareChance = 8 + math.floor(quality * 18) + math.floor(foraging * 1.2)
    local pool = (rand(100) < rareChance) and HERB_POOLS.rare or HERB_POOLS.common
    local itemType = chooseExisting(pool) or chooseExisting(HERB_POOLS.common)
    if not itemType then say(player, "None", "There is nothing useful here."); return end

    local item = addItem(player, itemType)
    if item then
        say(player, "Found", "Found: %1", displayName(itemType))
        if EHR and EHR.SkillXP and EHR.SkillXP.AwardXP then
            pcall(function() EHR.SkillXP.AwardXP(player, 2, "medical_plant_search", nil) end)
        end
    else
        say(player, "None", "There is nothing useful here.")
    end
end

local function OnClientCommand(module, command, player, args)
    if module ~= "EHR_HerbalSearch" then return end
    if command == "UnlockKnowledge" then EHR.HerbalSearchServer.UnlockKnowledge(player, args)
    elseif command == "Hazard" then EHR.HerbalSearchServer.Hazard(player, args)
    elseif command == "Complete" then EHR.HerbalSearchServer.Complete(player, args) end
end

if Events and Events.OnClientCommand and not EHR.HerbalSearchServer._registered then
    EHR.HerbalSearchServer._registered = true
    Events.OnClientCommand.Add(OnClientCommand)
    log("HerbalSearch server commands registered")
end
