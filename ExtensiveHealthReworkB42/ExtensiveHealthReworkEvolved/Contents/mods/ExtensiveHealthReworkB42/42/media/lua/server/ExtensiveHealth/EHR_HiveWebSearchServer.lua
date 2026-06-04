-- Extensive Health Rework B42
-- Server-side validation for tree hive and spiderweb harvesting.

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.HiveWebSearchServer = EHR.HiveWebSearchServer or {}

local COOLDOWN_HOURS = 48
local EMPTY_COOLDOWN_HOURS = 48
local CONTENT_CHANCE_PERCENT = 40

local function rand(max)
    max = tonumber(max) or 0
    if max <= 0 then return 0 end
    if ZombRand then return ZombRand(max) end
    return math.random(0, max - 1)
end

local function text(key, fallback, a)
    local fullKey = "UI_EHR_HiveWebSearch_" .. tostring(key)
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

local function getSquare(args)
    if not args then return nil end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 0
    if not x or not y then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    return ok and square or nil
end

local function squareArgs(square, args)
    if not square then return nil end
    local out = { playerNum = tonumber(args and args.playerNum) or 0 }
    pcall(function() out.x = square:getX(); out.y = square:getY(); out.z = square:getZ() end)
    if out.x == nil or out.y == nil then return nil end
    out.z = out.z or 0
    return out
end

local function sendHiveCommand(player, command, args)
    if not player or not sendServerCommand then return end
    sendServerCommand(player, "EHR_HiveWebSearch", command, args or {})
end

local function distanceToSquare(player, square)
    if not player or not square then return 999 end
    local dx = (player:getX() or 0) - ((square.getX and square:getX()) or 0)
    local dy = (player:getY() or 0) - ((square.getY and square:getY()) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function spriteName(obj)
    if not obj then return nil end
    local sprite = nil
    pcall(function() sprite = obj:getSprite() end)
    if not sprite then return nil end
    local name = nil
    pcall(function() name = sprite:getName() end)
    return name and tostring(name):lower() or nil
end

local function isTreeObject(obj)
    if not obj then return false end
    if instanceof then
        local ok, result = pcall(function() return instanceof(obj, "IsoTree") end)
        if ok and result == true then return true end
    end
    if IsoObjectType and IsoObjectType.tree and obj.getType then
        local ok, result = pcall(function() return obj:getType() == IsoObjectType.tree end)
        if ok and result == true then return true end
    end
    return false
end

local function objectLooksTree(obj)
    if isTreeObject(obj) then return true end
    local name = spriteName(obj)
    if not name then return false end
    return name:find("tree", 1, true) ~= nil
        or name:find("vegetation_trees", 1, true) ~= nil
        or name:find("jumbo_tree", 1, true) ~= nil
end

local function squareLooksTree(square)
    if not square then return false end
    if not square.getObjects then return false end
    local room = nil
    if square.getRoom then
        room = square:getRoom()
    end
    if room then return false end
    local objects = square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            if objectLooksTree(objects:get(i)) then return true end
        end
    end
    return false
end

local function nowHours()
    local now = 0
    pcall(function() now = getGameTime():getWorldAgeHours() end)
    return tonumber(now) or 0
end

local function rollTreeContent(md)
    md.EHR_HiveWebKnown = true

    if rand(100) >= CONTENT_CHANCE_PERCENT then
        md.EHR_HiveWebHive = false
        md.EHR_HiveWebWebs = 0
        return
    end

    md.EHR_HiveWebHive = rand(100) < 32
    local roll = rand(100)
    if roll < 35 then md.EHR_HiveWebWebs = 0
    elseif roll < 65 then md.EHR_HiveWebWebs = 1
    elseif roll < 87 then md.EHR_HiveWebWebs = 2
    else md.EHR_HiveWebWebs = 3 end
    if md.EHR_HiveWebHive ~= true and (tonumber(md.EHR_HiveWebWebs) or 0) <= 0 then
        md.EHR_HiveWebWebs = 1
    end
end

local function getTreeContent(square)
    if not square or not square.getModData then return false, 0 end
    local md = square:getModData()
    local now = nowHours()
    local last = tonumber(md.EHR_HiveWebLastHour)
    local hive = md.EHR_HiveWebHive == true
    local webs = tonumber(md.EHR_HiveWebWebs) or 0
    if md.EHR_HiveWebKnown ~= true or ((not hive and webs <= 0) and (not last or now - last >= EMPTY_COOLDOWN_HOURS)) then
        rollTreeContent(md)
        hive = md.EHR_HiveWebHive == true
        webs = tonumber(md.EHR_HiveWebWebs) or 0
        if square.transmitModData then pcall(function() square:transmitModData() end) end
    end
    return hive, webs
end

local function hasCooldown(square)
    if not square or not square.getModData then return false end
    local md = square:getModData()
    local last = tonumber(md.EHR_HiveWebLastHour)
    if not last then return false end
    return (nowHours() - last) < COOLDOWN_HOURS
end

local function setCooldown(square)
    if not square or not square.getModData then return end
    local md = square:getModData()
    md.EHR_HiveWebLastHour = nowHours()
    if square.transmitModData then pcall(function() square:transmitModData() end) end
end

local function transmitSquare(square)
    if square and square.transmitModData then pcall(function() square:transmitModData() end) end
end

local function updateCooldownAfterCollect(square)
    if not square or not square.getModData then return end
    local md = square:getModData()
    local hive = md.EHR_HiveWebHive == true
    local webs = tonumber(md.EHR_HiveWebWebs) or 0
    if hive or webs > 0 then
        transmitSquare(square)
    else
        setCooldown(square)
    end
end

local function addItem(player, itemType)
    if not player or not itemType then return nil end
    local inventory = player:getInventory()
    if not inventory then return nil end
    local ok, item = pcall(function() return inventory:AddItem(itemType) end)
    if ok and item then
        if sendAddItemToContainer then pcall(function() sendAddItemToContainer(inventory, item) end) end
        if sendItemStats then pcall(function() sendItemStats(item) end) end
        return item
    end
    return nil
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

local function getIntactGloves(player)
    if not player then return nil end
    if player.getWornItem and ItemBodyLocation then
        local locations = { ItemBodyLocation.HANDS, ItemBodyLocation.HANDS_LEFT, ItemBodyLocation.HANDS_RIGHT }
        for _, location in ipairs(locations) do
            local item = nil
            pcall(function() if location then item = player:getWornItem(location) end end)
            if item and not isBrokenOrHoled(item) then return item end
        end
    end
    if not player.getWornItems then return nil end
    local wornItems = player:getWornItems()
    if not wornItems then return nil end
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item then
            local location = nil
            pcall(function() if item.getBodyLocation then location = item:getBodyLocation() end end)
            if not location then pcall(function() if item.getLocation then location = item:getLocation() end end) end
            if isHandWearLocation(location) and not isBrokenOrHoled(item) then return item end
        end
    end
    return nil
end

local function hasIntactGloves(player)
    return getIntactGloves(player) ~= nil
end

local function syncGloves(player, gloves)
    if not gloves then return end
    if gloves.syncItemFields then pcall(function() gloves:syncItemFields() end) end
    if syncItemFields then pcall(function() syncItemFields(player, gloves) end) end
    if sendItemStats then pcall(function() sendItemStats(gloves) end) end
    if gloves.transmitModData then pcall(function() gloves:transmitModData() end) end
    if player and player.resetModelNextFrame then pcall(function() player:resetModelNextFrame() end) end
    if player and syncVisuals then pcall(function() syncVisuals(player) end) end
    if player and sendHumanVisual then pcall(function() sendHumanVisual(player) end) end
end

local function getGloveCoveredHandPart(gloves)
    if gloves and gloves.getCoveredParts then
        local parts = nil
        pcall(function() parts = gloves:getCoveredParts() end)
        if parts then
            for i = 0, parts:size() - 1 do
                local part = parts:get(i)
                local name = tostring(part or "")
                if name:find("Hand", 1, true) then return part end
            end
            if parts:size() > 0 then return parts:get(0) end
        end
    end
    if BloodBodyPartType then
        if rand(2) == 0 and BloodBodyPartType.Hand_L then return BloodBodyPartType.Hand_L end
        if BloodBodyPartType.Hand_R then return BloodBodyPartType.Hand_R end
    end
    return nil
end

local function punctureGloves(player, gloves)
    if not gloves or isBrokenOrHoled(gloves) then return false end

    local part = getGloveCoveredHandPart(gloves)
    if part then
        pcall(function() if gloves.addHole then gloves:addHole(part) end end)
        if not isBrokenOrHoled(gloves) then
            pcall(function()
                local visual = gloves.getVisual and gloves:getVisual() or nil
                if visual and visual.setHole then visual:setHole(part, 1.0) end
            end)
        end
        if not isBrokenOrHoled(gloves) then
            pcall(function()
                local visual = gloves.getVisual and gloves:getVisual() or nil
                if visual and visual.setHole then visual:setHole(part) end
            end)
        end
    end

    if not isBrokenOrHoled(gloves) and gloves.getCondition and gloves.setCondition then
        pcall(function()
            local condition = tonumber(gloves:getCondition()) or 0
            local maxCondition = 0
            if gloves.getConditionMax then maxCondition = tonumber(gloves:getConditionMax()) or 0 end
            local puncturedCondition = 0
            if maxCondition > 0 then puncturedCondition = math.max(0, math.floor(maxCondition * 0.05)) end
            gloves:setCondition(math.min(math.max(0, condition - 1), puncturedCondition))
        end)
    end

    syncGloves(player, gloves)
    return true
end

local function callBool(target, methods)
    if not target then return false end
    for _, methodName in ipairs(methods) do
        local method = target[methodName]
        if type(method) == "function" then
            local ok, result = pcall(function() return method(target) end)
            if ok and result == true then return true end
        end
    end
    return false
end

local function callNumber(target, methodName, fallback)
    if not target then return fallback end
    local method = target[methodName]
    if type(method) ~= "function" then return fallback end
    local ok, result = pcall(function() return method(target) end)
    if ok and result ~= nil then return tonumber(result) or fallback end
    return fallback
end

local function callSet(target, methodName, value)
    if not target then return false end
    local method = target[methodName]
    if type(method) ~= "function" then return false end
    local ok = pcall(function() method(target, value) end)
    return ok == true
end

local function getZombieStat(player, stat)
    if not player or not stat then return 0 end
    local stats = player:getStats()
    if not stats or not stats.get then return 0 end
    local ok, value = pcall(function() return stats:get(stat) end)
    if ok then return tonumber(value) or 0 end
    return 0
end

local function setZombieStat(player, stat, value)
    if not player or not stat then return false end
    local stats = player:getStats()
    if not stats or not stats.set then return false end
    local ok = pcall(function() stats:set(stat, value) end)
    return ok == true
end

local function forEachBodyPart(bodyDamage, callback)
    if not bodyDamage or not BodyPartType or not BodyPartType.FromIndex then return false end
    local maxIndex = nil
    if BodyPartType.ToIndex and BodyPartType.MAX then
        local ok, value = pcall(function() return BodyPartType.ToIndex(BodyPartType.MAX) - 1 end)
        if ok then maxIndex = value end
    end
    if not maxIndex or maxIndex < 0 then return false end
    local changed = false
    for i = 0, maxIndex do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part and callback(part, i) then changed = true end
    end
    return changed
end

local function hasBodyPartKnoxPayload(bodyDamage)
    return forEachBodyPart(bodyDamage, function(part)
        return callBool(part, { "IsInfected", "isInfected" })
    end)
end

local function hasKnoxDiseaseEntry(player)
    local modData = player and player.getModData and player:getModData() or nil
    local diseaseData = modData and modData.EHR_Disease
    local active = diseaseData and diseaseData.active
    return type(active) == "table" and (active.Knox_Infection ~= nil or active.knox_infection ~= nil)
end

local function captureKnoxState(player)
    local bodyDamage = player and player.getBodyDamage and player:getBodyDamage() or nil
    if not bodyDamage then return { infected = false } end
    local infected = callBool(bodyDamage, { "IsInfected", "isInfected" })
    infected = infected or hasBodyPartKnoxPayload(bodyDamage)
    infected = infected or callNumber(bodyDamage, "getInfectionTime", -1) >= 0
    infected = infected or callNumber(bodyDamage, "getInfectionMortalityDuration", -1) > 0
    if CharacterStat then
        infected = infected or getZombieStat(player, CharacterStat.ZOMBIE_INFECTION) > 0
        infected = infected or getZombieStat(player, CharacterStat.ZOMBIE_FEVER) > 0
    end
    infected = infected or hasKnoxDiseaseEntry(player)
    return { infected = infected == true }
end

local function clearKnoxIfCreatedByHiveWeb(player, snapshot)
    if not player or (snapshot and snapshot.infected == true) then return end
    local bodyDamage = player:getBodyDamage()
    if bodyDamage then
        callSet(bodyDamage, "setInfected", false)
        callSet(bodyDamage, "setInfectionTime", -1.0)
        callSet(bodyDamage, "setInfectionMortalityDuration", -1.0)
        forEachBodyPart(bodyDamage, function(part)
            local changed = false
            changed = callSet(part, "SetInfected", false) or changed
            changed = callSet(part, "SetFakeInfected", false) or changed
            return changed
        end)
    end
    if CharacterStat then
        setZombieStat(player, CharacterStat.ZOMBIE_INFECTION, 0)
        setZombieStat(player, CharacterStat.ZOMBIE_FEVER, 0)
    end
    local modData = player:getModData()
    local diseaseData = modData and modData.EHR_Disease
    local active = diseaseData and diseaseData.active
    if type(active) == "table" then
        active.Knox_Infection = nil
        active.knox_infection = nil
    end
end

local function randomHandOrArmPart(player)
    if not player or not BodyPartType then return nil end
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return nil end
    local names = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R" }
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
    local gloves = getIntactGloves(player)
    if gloves then
        punctureGloves(player, gloves)
        say(player, "GlovesLine", "The glove takes the sting.")
        return false
    end
    local part = randomHandOrArmPart(player)
    if not part then return false end
    local knoxSnapshot = captureKnoxState(player)
    local changed = false
    if part.setScratched then changed = pcall(function() part:setScratched(true, false) end) or changed end
    if part.getScratchTime and part.setScratchTime then
        pcall(function()
            local current = tonumber(part:getScratchTime()) or 0
            if current < 9 then part:setScratchTime(9 + rand(7)); changed = true end
        end)
    end
    if part.getAdditionalPain and part.setAdditionalPain then
        pcall(function()
            local pain = tonumber(part:getAdditionalPain()) or 0
            if pain < 8 then part:setAdditionalPain(8); changed = true end
        end)
    end
    if changed then
        pcall(function() syncBodyPart(part, 0x00570188) end)
        local bd = player:getBodyDamage()
        if bd and bd.DamageUpdate then pcall(function() bd:DamageUpdate() end) end
        clearKnoxIfCreatedByHiveWeb(player, knoxSnapshot)
    end
    return changed
end

function EHR.HiveWebSearchServer.GetStartConfig(player, args)
    if not player or not args then return false, "Invalid" end
    local square = getSquare(args)
    local out = squareArgs(square, args)
    if not square or not out or distanceToSquare(player, square) > 4.5 or not squareLooksTree(square) then return false, "Invalid" end
    if hasCooldown(square) then
        return false, "Depleted"
    end
    local hive, webs = getTreeContent(square)
    if hive ~= true and (tonumber(webs) or 0) <= 0 then
        setCooldown(square)
        return false, "None"
    end
    out.hive = hive == true
    out.webs = tonumber(webs) or 0
    return true, out
end

function EHR.HiveWebSearchServer.RequestStart(player, args)
    local ok, result = EHR.HiveWebSearchServer.GetStartConfig(player, args)
    local playerNum = tonumber(args and args.playerNum) or 0
    if not ok then
        if result == "Depleted" then
            sendHiveCommand(player, "StartDenied", { playerNum = playerNum, reason = "Depleted" })
        elseif result == "None" then
            sendHiveCommand(player, "StartDenied", { playerNum = playerNum, reason = "None" })
        end
        return
    end
    sendHiveCommand(player, "StartApproved", result)
end

function EHR.HiveWebSearchServer.Hazard(player, args)
    local square = getSquare(args)
    if not player or not square or distanceToSquare(player, square) > 4.5 then return end
    applyScratch(player)
end

function EHR.HiveWebSearchServer.Complete(player, args)
    local square = getSquare(args)
    if not player or not square or distanceToSquare(player, square) > 4.5 or not squareLooksTree(square) then return end
    if hasCooldown(square) then return end
    local target = tostring(args and args.target or "")
    local md = square:getModData()
    local hive, webs = getTreeContent(square)
    if target == "hive" and hive == true then
        if addItem(player, "ExtensiveHealth.Honeycomb") then
            md.EHR_HiveWebHive = false
            say(player, "FoundHoneycomb", "Found: Honeycomb")
            updateCooldownAfterCollect(square)
        end
    elseif target == "web" and (tonumber(webs) or 0) > 0 then
        if addItem(player, "ExtensiveHealth.Spiderweb") then
            md.EHR_HiveWebWebs = math.max(0, (tonumber(webs) or 0) - 1)
            say(player, "FoundSpiderweb", "Found: Spiderweb")
            updateCooldownAfterCollect(square)
        end
    end
end

local function OnClientCommand(module, command, player, args)
    if module ~= "EHR_HiveWebSearch" then return end
    if command == "RequestStart" then EHR.HiveWebSearchServer.RequestStart(player, args)
    elseif command == "Hazard" then EHR.HiveWebSearchServer.Hazard(player, args)
    elseif command == "Complete" then EHR.HiveWebSearchServer.Complete(player, args) end
end

if Events and Events.OnClientCommand and not EHR.HiveWebSearchServer._registered then
    EHR.HiveWebSearchServer._registered = true
    Events.OnClientCommand.Add(OnClientCommand)
end
