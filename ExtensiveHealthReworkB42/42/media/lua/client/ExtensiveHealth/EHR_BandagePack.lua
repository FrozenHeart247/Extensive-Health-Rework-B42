-- Extensive Health Rework B42
-- Clean bandage pack support.

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Medication"

EHR = EHR or {}
EHR.BandagePack = EHR.BandagePack or {}

local PACK_TYPE = "ExtensiveHealth.SterilizedBandages"
local CLEAN_BANDAGE_TYPE = "Base.Bandage"

local function isInventoryItem(item)
    return item and instanceof and instanceof(item, "InventoryItem")
end

local function unwrapContextItem(value)
    if isInventoryItem(value) then
        return value
    end
    if value and value.items then
        for i = 1, #value.items do
            if isInventoryItem(value.items[i]) then
                return value.items[i]
            end
        end
    end
    return nil
end

local function getDoseInfo(item)
    if not item or not EHR.Medication or not EHR.Medication.GetItemDoseInfo then
        return nil
    end

    local ok, info = pcall(function()
        return EHR.Medication.GetItemDoseInfo(item)
    end)

    if ok then
        return info
    end
    return nil
end

local function setRemainingDoses(player, item, remaining)
    local info = getDoseInfo(item)
    if not info or not item.setUsedDelta then
        return false
    end

    local maxDoses = info.maxDoses or 1
    local useDelta = info.useDelta or item:getUseDelta()
    remaining = math.max(0, math.min(maxDoses, math.floor(remaining + 0.0001)))

    local usedDelta = remaining * useDelta
    if remaining >= maxDoses then
        usedDelta = 1.0
    end
    usedDelta = math.max(0, math.min(1.0, usedDelta))

    local ok = pcall(function()
        item:setUsedDelta(usedDelta)
    end)

    if ok and isClient() and player and item.getID then
        sendClientCommand(player, "EHR", "UpdateItemDelta", {
            itemID = item:getID(),
            usedDelta = usedDelta,
        })
    end

    return ok
end

local function getRemainingDoses(item)
    local info = getDoseInfo(item)
    return info and (info.remainingDoses or 0) or 0
end

local function getMaxDoses(item)
    local info = getDoseInfo(item)
    return info and (info.maxDoses or 1) or 1
end

function EHR.BandagePack.IsPack(item)
    return item and item.getFullType and item:getFullType() == PACK_TYPE
end

function EHR.BandagePack.IsCleanBandage(item)
    return item and item.getFullType and item:getFullType() == CLEAN_BANDAGE_TYPE
end

local function inventoryItems(inventory)
    local items = {}
    if not inventory or not inventory.getItems then
        return items
    end

    local list = inventory:getItems()
    if not list then
        return items
    end

    for i = 0, list:size() - 1 do
        table.insert(items, list:get(i))
    end

    return items
end

function EHR.BandagePack.FindPackWithSpace(inventory)
    for _, item in ipairs(inventoryItems(inventory)) do
        if EHR.BandagePack.IsPack(item) and getRemainingDoses(item) < getMaxDoses(item) then
            return item
        end
    end
    return nil
end

function EHR.BandagePack.FindCleanBandage(inventory)
    for _, item in ipairs(inventoryItems(inventory)) do
        if EHR.BandagePack.IsCleanBandage(item) then
            return item
        end
    end
    return nil
end

local function removeInventoryItem(player, item)
    if not item then return false end

    local container = item:getContainer()
    if isClient() and player and item.getID then
        sendClientCommand(player, "EHR", "RemoveItem", { itemID = item:getID() })
    end

    if container and container.Remove then
        container:Remove(item)
        return true
    end

    local inventory = player and player:getInventory()
    if inventory then
        inventory:Remove(item)
        return true
    end

    return false
end

local function markInventoryDirty(inventory)
    if inventory and inventory.setDrawDirty then
        inventory:setDrawDirty(true)
    end
end

function EHR.BandagePack.AddBandageToPack(player, bandage, pack)
    if not player or not EHR.BandagePack.IsCleanBandage(bandage) then
        return false
    end

    local inventory = player:getInventory()
    if not inventory then
        return false
    end

    pack = pack or EHR.BandagePack.FindPackWithSpace(inventory)
    if not pack then
        pack = inventory:AddItem(PACK_TYPE)
        if not pack then return false end
        setRemainingDoses(player, pack, 0)
    end

    if not EHR.BandagePack.IsPack(pack) then
        return false
    end

    local remaining = getRemainingDoses(pack)
    local maxDoses = getMaxDoses(pack)
    if remaining >= maxDoses then
        return false
    end

    if not removeInventoryItem(player, bandage) then
        return false
    end

    setRemainingDoses(player, pack, remaining + 1)
    markInventoryDirty(inventory)

    return true
end

function EHR.BandagePack.UnpackBandage(player, pack)
    if not player or not EHR.BandagePack.IsPack(pack) then
        return false
    end

    local inventory = player:getInventory()
    if not inventory then
        return false
    end

    if getRemainingDoses(pack) <= 0 then
        return false
    end

    inventory:AddItem(CLEAN_BANDAGE_TYPE)
    EHR.BandagePack.ConsumePackDose(player, pack)

    markInventoryDirty(inventory)
    return true
end

function EHR.BandagePack.ConsumePackDose(player, pack)
    if not player or not EHR.BandagePack.IsPack(pack) then
        return false
    end

    local remaining = getRemainingDoses(pack)
    if remaining > 1 then
        return setRemainingDoses(player, pack, remaining - 1)
    end

    return removeInventoryItem(player, pack)
end

function EHR.BandagePack.HookApplyBandage()
    if not pcall(function() require "TimedActions/ISApplyBandage" end) then
        return
    end
    if not ISApplyBandage or ISApplyBandage.EHR_BandagePackHooked then
        return
    end

    local originalComplete = ISApplyBandage.complete
    ISApplyBandage.complete = function(self)
        local pack = self.item
        if self.doIt and EHR.BandagePack.IsPack(pack) then
            local inventory = self.character and self.character:getInventory()
            if not inventory then
                return originalComplete(self)
            end

            local singleBandage = inventory:AddItem(CLEAN_BANDAGE_TYPE)
            if not singleBandage then
                return originalComplete(self)
            end

            self.item = singleBandage

            local ok, result = pcall(originalComplete, self)
            self.item = pack

            if not ok then
                pcall(function()
                    if inventory:contains(singleBandage) then
                        inventory:Remove(singleBandage)
                    end
                end)
                error(result)
            end

            if result then
                EHR.BandagePack.ConsumePackDose(self.character, pack)
            else
                pcall(function()
                    if inventory:contains(singleBandage) then
                        inventory:Remove(singleBandage)
                    end
                end)
            end

            return result
        end

        return originalComplete(self)
    end

    ISApplyBandage.EHR_BandagePackHooked = true
    EHR.Log("BandagePack: ISApplyBandage.complete hooked")
end

function EHR.BandagePack.OnFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local inventory = player:getInventory()
    if not inventory then return end

    for _, value in ipairs(items) do
        local item = unwrapContextItem(value)
        if item then
            if EHR.BandagePack.IsCleanBandage(item) then
                local pack = EHR.BandagePack.FindPackWithSpace(inventory)
                local label = pack and "Add to Clean Bandages Pack" or "Create Clean Bandages Pack"
                context:addOption(label, player, function(plr, bandageItem, targetPack)
                    EHR.BandagePack.AddBandageToPack(plr, bandageItem, targetPack)
                end, item, pack)
            elseif EHR.BandagePack.IsPack(item) then
                if getRemainingDoses(item) > 0 then
                    context:addOption("Unpack Clean Bandage", player, function(plr, packItem)
                        EHR.BandagePack.UnpackBandage(plr, packItem)
                    end, item)
                end

                if getRemainingDoses(item) < getMaxDoses(item) then
                    local bandage = EHR.BandagePack.FindCleanBandage(inventory)
                    if bandage then
                        context:addOption("Add Clean Bandage to Pack", player, function(plr, bandageItem, packItem)
                            EHR.BandagePack.AddBandageToPack(plr, bandageItem, packItem)
                        end, bandage, item)
                    end
                end
            end
        end
    end
end

if Events then
    Events.OnGameStart.Add(EHR.BandagePack.HookApplyBandage)
    Events.OnFillInventoryObjectContextMenu.Add(EHR.BandagePack.OnFillInventoryObjectContextMenu)
    EHR.Log("BandagePack module loaded")
end
