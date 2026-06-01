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
pcall(function() require "TimedActions/ISReadABook" end)

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

local function appendString(values, value)
    if value ~= nil then
        values[#values + 1] = tostring(value)
    end
end

local function appendMaybeTranslated(values, value)
    appendString(values, value)
    if value ~= nil and getText then
        local ok, translated = pcall(getText, tostring(value))
        if ok then appendString(values, translated) end
    end
end

local function appendMediaStrings(values, media)
    if media == nil then
        return
    end

    if type(media) == "table" then
        appendMaybeTranslated(values, media.id)
        appendMaybeTranslated(values, media.title)
        appendMaybeTranslated(values, media.info)
        appendMaybeTranslated(values, media.text)
        appendMaybeTranslated(values, media.name)
        appendMaybeTranslated(values, media.guid)
    else
        appendMaybeTranslated(values, media)
    end
end

local function isKentuckyHeraldJuly16(item)
    if not item then return false end

    local fullType = item.getFullType and item:getFullType() or ""
    local itemType = item.getType and item:getType() or ""
    if fullType ~= "Base.Newspaper_Herald_New" and itemType ~= "Newspaper_Herald_New" then
        return false
    end

    local modData = item.getModData and item:getModData() or nil
    local values = {}
    if modData then
        appendMediaStrings(values, modData.printMedia)
        appendMediaStrings(values, modData.printMediaID)
        appendMediaStrings(values, modData.printMediaId)
        appendMediaStrings(values, modData.media)
        appendMediaStrings(values, modData.mediaID)
        appendMediaStrings(values, modData.mediaId)
        appendMediaStrings(values, modData.printText)
        appendMediaStrings(values, modData.printTextID)
        appendMediaStrings(values, modData.printTextId)
        appendMediaStrings(values, modData.title)
        appendMediaStrings(values, modData.info)
        appendMediaStrings(values, modData.text)
    end

    for _, raw in ipairs(values) do
        local value = tostring(raw):lower()
        local compact = value:gsub("[%s_%-%p]", "")
        local hasHerald = value:find("kentucky herald", 1, true) ~= nil or compact:find("kentuckyherald", 1, true) ~= nil
        local hasJuly16 = value:find("july 16", 1, true) ~= nil or compact:find("july16", 1, true) ~= nil
        if hasHerald and hasJuly16 then
            return true
        end
    end

    return false
end

local function unlockKnoxFromHerald(character, item, source)
    if not character or not item or not isKentuckyHeraldJuly16(item) then
        return false
    end

    local unlockSource = EHR.DiseaseFlyers.KNOX_UNLOCK_SOURCE or "kentucky_herald_july16"
    local newlyLearned = EHR.DiseaseFlyers.UnlockDiseaseKnowledge(character, "knox_infection", {
        allowKnox = true,
        source = unlockSource,
    }) == true

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(character, "EHR_Flyers", "UnlockDisease", {
            diseaseId = "knox_infection",
            allowKnox = true,
            source = unlockSource,
        })
    end

    if newlyLearned then
        log("Knox disease knowledge unlocked via Kentucky Herald July 16 (" .. tostring(source) .. ")")
    end

    return newlyLearned
end

local function hookHeraldReadBook()
    if not ISReadABook then
        return false
    end

    local currentPerform = ISReadABook.perform
    if EHR.DiseaseFlyers.heraldHookedPerform and currentPerform == EHR.DiseaseFlyers.heraldHookedPerform then
        return true
    end

    local originalPerform = currentPerform
    local wrappedPerform = function(self, ...)
        local result = originalPerform(self, ...)
        pcall(function()
            unlockKnoxFromHerald(self.character, self.item, "ISReadABook.perform")
        end)
        return result
    end

    EHR.DiseaseFlyers.heraldOriginalPerform = originalPerform
    EHR.DiseaseFlyers.heraldHookedPerform = wrappedPerform
    ISReadABook.perform = wrappedPerform
    log("Hooked ISReadABook.perform for Kentucky Herald Knox knowledge")
    return true
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

ISEHRReadHeraldAction = ISBaseTimedAction:derive("ISEHRReadHeraldAction")

function ISEHRReadHeraldAction:isValid()
    return self.character ~= nil and self.item ~= nil and self.item:getContainer() ~= nil
end

function ISEHRReadHeraldAction:start()
    self.character:setReading(true)
    pcall(function() self.item:setJobType(getText("ContextMenu_Read")) end)
    pcall(function() self.item:setJobDelta(0.0) end)
    pcall(function() self:setActionAnim("Read") end)
end

function ISEHRReadHeraldAction:update()
    if self.item then
        pcall(function() self.item:setJobDelta(self:getJobDelta()) end)
    end
end

function ISEHRReadHeraldAction:stop()
    if self.character then
        self.character:setReading(false)
    end
    if self.item then
        pcall(function() self.item:setJobDelta(0.0) end)
    end
    ISBaseTimedAction.stop(self)
end

function ISEHRReadHeraldAction:perform()
    if self.character then
        self.character:setReading(false)
    end
    if self.item then
        pcall(function() self.item:setJobDelta(0.0) end)
    end
    unlockKnoxFromHerald(self.character, self.item, "EHRReadHeraldAction")
    ISBaseTimedAction.perform(self)
end

function ISEHRReadHeraldAction:new(character, item, time)
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
        if isFlyerItem(item) or isKentuckyHeraldJuly16(item) then
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
            if isKentuckyHeraldJuly16(item) then
                ISTimedActionQueue.add(ISEHRReadHeraldAction:new(playerObj, item, math.max(100, pages * 15)))
            else
                ISTimedActionQueue.add(ISEHRReadFlyerAction:new(playerObj, item, math.max(80, pages * 15)))
            end

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
    local flyerHooked = hookInventoryReadItem()
    local heraldHooked = hookHeraldReadBook()
    EHR.DiseaseFlyers.clientHooked = flyerHooked == true
    EHR.DiseaseFlyers.heraldClientHooked = heraldHooked == true
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
