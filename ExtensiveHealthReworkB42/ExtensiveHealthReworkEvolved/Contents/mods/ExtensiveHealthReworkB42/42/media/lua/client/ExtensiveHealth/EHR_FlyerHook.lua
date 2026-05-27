--[[
    Extensive Health Rework B42
    Disease Flyer Reading Hook (Client-Side)

    Routes EHR disease flyers through a small custom read timed action.
    This avoids the vanilla ISReadABook literature state in MP.
]]--

require "TimedActions/ISBaseTimedAction"
require "ExtensiveHealth/EHR_DiseaseFlyers"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
pcall(function() require "ISUI/ISInventoryPaneContextMenu" end)

EHR = EHR or {}
EHR.DiseaseFlyers = EHR.DiseaseFlyers or {}

-- Ensure config exists (loaded from shared file)
EHR.DiseaseFlyers.Config = EHR.DiseaseFlyers.Config or {
    FLYER_ITEMS = {
        ["ExtensiveHealth.DiseaseFlyer_CommonCold"] = "common_cold",
        ["ExtensiveHealth.DiseaseFlyer_Flu"] = "flu",
        ["ExtensiveHealth.DiseaseFlyer_Pneumonia"] = "pneumonia",
        ["ExtensiveHealth.DiseaseFlyer_FoodPoisoning"] = "food_poisoning",
        ["ExtensiveHealth.DiseaseFlyer_Hypothermia"] = "hypothermia",
        ["ExtensiveHealth.DiseaseFlyer_HeatExhaustion"] = "heat_exhaustion",
        ["ExtensiveHealth.DiseaseFlyer_Sepsis"] = "sepsis",
        ["ExtensiveHealth.DiseaseFlyer_CorpseSickness"] = "corpse_sickness",
        ["ExtensiveHealth.DiseaseFlyer_Tuberculosis"] = "tuberculosis",
    },
}

local function log(msg)
    if EHR and EHR.Log then
        EHR.Log(msg)
    else
        print("[EHR FlyerHook] " .. tostring(msg))
    end
end

local function clearFlyerReadProgress(character, item, itemId)
    if not character or not item or not itemId then return end

    pcall(function() item:setAlreadyReadPages(0) end)
    pcall(function() character:setAlreadyReadPages(itemId, 0) end)

    if sendSyncPlayerFields then
        pcall(sendSyncPlayerFields, character, 0x00000007)
    end

    if syncItemFields then
        pcall(syncItemFields, character, item)
    end
end

local function isFlyerItem(item)
    if not item or not item.getFullType then
        return false
    end
    return EHR.DiseaseFlyers.Config.FLYER_ITEMS[item:getFullType()] ~= nil
end

local function restoreOldReadBookHooks()
    if not ISReadABook or not EHR or not EHR.DiseaseFlyers then
        return
    end
    if EHR.DiseaseFlyers.original_complete and ISReadABook.complete == EHR.DiseaseFlyers.hooked_complete then
        ISReadABook.complete = EHR.DiseaseFlyers.original_complete
    end
    if EHR.DiseaseFlyers.original_perform and ISReadABook.perform == EHR.DiseaseFlyers.hooked_perform then
        ISReadABook.perform = EHR.DiseaseFlyers.original_perform
    end
    EHR.DiseaseFlyers.original_complete = nil
    EHR.DiseaseFlyers.original_perform = nil
    EHR.DiseaseFlyers.hooked_complete = nil
    EHR.DiseaseFlyers.hooked_perform = nil
end

local function handleFlyerRead(character, item, source)
    if not character or not item then
        return
    end

    local itemId = item:getFullType()
    log("EHR flyer read via " .. tostring(source) .. " - item: " .. tostring(itemId))

    local diseaseId = EHR.DiseaseFlyers.Config.FLYER_ITEMS[itemId]
    if not diseaseId then
        return
    end

    log("Detected EHR disease flyer! Disease: " .. tostring(diseaseId))

    if EHR.DiseaseFlyers.OnFlyerRead then
        EHR.DiseaseFlyers.OnFlyerRead(character, item)
    else
        log("OnFlyerRead not found, handling directly")
        local modData = character:getModData()
        if modData then
            modData.EHR_KnownDiseases = modData.EHR_KnownDiseases or {}
            if not modData.EHR_KnownDiseases[diseaseId] then
                modData.EHR_KnownDiseases[diseaseId] = true
                log("Disease knowledge unlocked: " .. diseaseId)
                EHR.Locale.Say(character, "Disease knowledge acquired: " .. diseaseId)
            else
                EHR.Locale.Say(character, "You already know about this disease.")
            end

            if isClient() and sendClientCommand then
                sendClientCommand(character, "EHR_Flyers", "UnlockDisease", { diseaseId = diseaseId })
                log("Sent UnlockDisease command to server")
            end
        end
    end

    -- Disease flyers use the read action, but should not behave like
    -- skill books with persistent percentage progress.
    clearFlyerReadProgress(character, item, itemId)
end

ISEHRReadFlyerAction = ISBaseTimedAction:derive("ISEHRReadFlyerAction")

function ISEHRReadFlyerAction:isValid()
    return self.character ~= nil and self.item ~= nil and self.item:getContainer() ~= nil
end

function ISEHRReadFlyerAction:start()
    self.character:setReading(true)
    pcall(function() self.item:setJobType(getText("ContextMenu_Read")) end)
    pcall(function() self.item:setJobDelta(0.0) end)
    pcall(function() self:setActionAnim("Read") end)
end

function ISEHRReadFlyerAction:update()
    if self.item then
        pcall(function() self.item:setJobDelta(self:getJobDelta()) end)
    end
end

function ISEHRReadFlyerAction:stop()
    if self.character then
        self.character:setReading(false)
    end
    if self.item then
        pcall(function() self.item:setJobDelta(0.0) end)
    end
    ISBaseTimedAction.stop(self)
end

function ISEHRReadFlyerAction:perform()
    if self.character then
        self.character:setReading(false)
    end
    if self.item then
        pcall(function() self.item:setJobDelta(0.0) end)
    end
    handleFlyerRead(self.character, self.item, "EHRReadFlyerAction")
    ISBaseTimedAction.perform(self)
end

function ISEHRReadFlyerAction:new(character, item, time)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.maxTime = time or 120
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.ignoreHandsWounds = true
    o.forceProgressBar = true
    return o
end

local function hookInventoryReadItem()
    if not ISInventoryPaneContextMenu or type(ISInventoryPaneContextMenu.readItem) ~= "function" then
        log("ERROR: ISInventoryPaneContextMenu.readItem not found!")
        return false
    end

    local currentReadItem = ISInventoryPaneContextMenu.readItem
    if EHR.DiseaseFlyers.original_readItem and currentReadItem == EHR.DiseaseFlyers.hooked_readItem then
        currentReadItem = EHR.DiseaseFlyers.original_readItem
        ISInventoryPaneContextMenu.readItem = currentReadItem
    end

    if EHR.DiseaseFlyers.hooked_readItem == currentReadItem then
        return true
    end

    local originalReadItem = currentReadItem
    local wrappedReadItem = function(item, player)
        if isFlyerItem(item) then
            local playerObj = getSpecificPlayer(player)
            if not playerObj or item:getContainer() == nil then
                return
            end

            if ISInventoryPaneContextMenu.transferIfNeeded then
                ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
            end

            local pages = 8
            if item.getNumberOfPages then
                local okPages, value = pcall(function() return item:getNumberOfPages() end)
                if okPages and tonumber(value) then pages = tonumber(value) end
            end
            ISTimedActionQueue.add(ISEHRReadFlyerAction:new(playerObj, item, math.max(80, pages * 15)))

            if ISCraftingUI and ISCraftingUI.ReturnItemToOriginalContainer then
                pcall(function() ISCraftingUI.ReturnItemToOriginalContainer(playerObj, item) end)
            end
            return
        end

        return originalReadItem(item, player)
    end

    EHR.DiseaseFlyers.original_readItem = originalReadItem
    EHR.DiseaseFlyers.hooked_readItem = wrappedReadItem
    ISInventoryPaneContextMenu.readItem = wrappedReadItem
    log("Hooked ISInventoryPaneContextMenu.readItem for disease flyers")
    return true
end

local function hookFlyerReading()
    restoreOldReadBookHooks()
    EHR.DiseaseFlyers.clientHooked = hookInventoryReadItem()
    return EHR.DiseaseFlyers.clientHooked == true
end

-- Hook on game start to ensure ISReadABook is fully loaded
local function onGameStart()
    log("OnGameStart - attempting to hook EHR flyer reading")
    hookFlyerReading()
end

-- Register the hook
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(onGameStart)
    log("Registered OnGameStart hook for flyer detection")
end

-- Also try immediate hook (might work if inventory context menu is already loaded)
hookFlyerReading()

log("EHR_FlyerHook.lua loaded (client-side)")
