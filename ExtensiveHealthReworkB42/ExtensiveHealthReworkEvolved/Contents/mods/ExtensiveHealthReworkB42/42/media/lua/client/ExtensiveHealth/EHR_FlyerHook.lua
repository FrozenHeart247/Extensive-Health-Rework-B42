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
        ["ExtensiveHealth.DiseaseFlyer_Cellulitis"] = "cellulitis",
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

local function markFlyerReadProgress(character, item, itemId)
    if not character or not item or not itemId then return end

    local pages = 1
    if item.getNumberOfPages then
        local okPages, value = pcall(function() return item:getNumberOfPages() end)
        if okPages and tonumber(value) and tonumber(value) > 0 then
            pages = tonumber(value)
        end
    end

    pcall(function() item:setAlreadyReadPages(pages) end)
    pcall(function() character:setAlreadyReadPages(itemId, pages) end)

    if sendSyncPlayerFields then
        pcall(function() sendSyncPlayerFields(character, 0x00000007) end)
    end

    if syncItemFields then
        pcall(function() syncItemFields(character, item) end)
    end
end

local function isMedicalWildPlantsFlyer(item)
    if not item or not item.getFullType then return false end
    return item:getFullType() == "ExtensiveHealth.MedicalWildPlants"
end

local function unlockMedicalWildPlants(character, item)
    if not character or not item then return false end
    local data = character:getModData()
    if not data then return false end

    local newlyLearned = data.EHR_MedicalWildPlantsKnown ~= true
    data.EHR_MedicalWildPlantsKnown = true
    data.EHR_MedicalWildPlantsReadHour = getGameTime():getWorldAgeHours()

    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(character)
    end
    if isClient and isClient() and sendClientCommand then
        sendClientCommand(character, "EHR_HerbalSearch", "UnlockKnowledge", {})
    end

    if newlyLearned then
        if EHR and EHR.SkillXP and EHR.SkillXP.AwardXP then
            pcall(function() EHR.SkillXP.AwardXP(character, 50, "medical_wild_plants_flyer", nil) end)
        end
        if EHR and EHR.Locale and EHR.Locale.Say then
            EHR.Locale.Say(character, EHR.Locale.Text("UI_EHR_HerbalSearch_KnowledgeLearned", "Medical wild plant knowledge acquired."))
        elseif character.Say then
            character:Say("Medical wild plant knowledge acquired.")
        end
    else
        if EHR and EHR.Locale and EHR.Locale.Say then
            EHR.Locale.Say(character, EHR.Locale.Text("UI_EHR_HerbalSearch_KnowledgeAlreadyKnown", "I already know how to identify medicinal wild plants."))
        elseif character.Say then
            character:Say("I already know how to identify medicinal wild plants.")
        end
    end

    return newlyLearned
end

local function isFlyerItem(item)
    if not item or not item.getFullType then
        return false
    end
    return EHR.DiseaseFlyers.Config.FLYER_ITEMS[item:getFullType()] ~= nil or isMedicalWildPlantsFlyer(item)
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

    -- B42's ItemCodeOnCreate stores print-media data in modData.printMedia.
    -- Depending on how the item was generated, Kahlua may expose that value as
    -- either a Lua table or a Java-backed object, so type(media) is unreliable.
    appendMaybeTranslated(values, media)
    for _, fieldName in ipairs({ "id", "title", "info", "text", "name", "guid" }) do
        local ok, fieldValue = pcall(function()
            return media[fieldName]
        end)
        if ok then
            appendMaybeTranslated(values, fieldValue)
        end
    end
end

local function isKentuckyHeraldJuly16(item)
    if not item then return false end

    local fullType = item.getFullType and item:getFullType() or ""
    local itemType = item.getType and item:getType() or ""

    local modData = item.getModData and item:getModData() or nil
    local values = {}
    -- Newspaper_Recent and other regional newspaper items can receive a
    -- Kentucky Herald issue through vanilla ItemCodeOnCreate. The embedded
    -- print-media identity is authoritative; the base item type is not.
    appendMaybeTranslated(values, fullType)
    appendMaybeTranslated(values, itemType)
    if item.getName then
        local okName, name = pcall(function() return item:getName() end)
        if okName then appendMaybeTranslated(values, name) end
    end
    if item.getDisplayName then
        local okDisplayName, displayName = pcall(function() return item:getDisplayName() end)
        if okDisplayName then appendMaybeTranslated(values, displayName) end
    end
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
        appendMediaStrings(values, modData.literatureTitle)
        appendMediaStrings(values, modData.literatureInfo)
        appendMediaStrings(values, modData.literatureText)
        appendMediaStrings(values, modData.literatureID)
        appendMediaStrings(values, modData.literatureId)
        appendMediaStrings(values, modData.title)
        appendMediaStrings(values, modData.info)
        appendMediaStrings(values, modData.text)
    end

    for _, raw in ipairs(values) do
        local value = tostring(raw):lower()
        local compact = value:gsub("[%s_%-%p]", "")
        local hasHerald = value:find("kentucky herald", 1, true) ~= nil or compact:find("kentuckyherald", 1, true) ~= nil
        local hasJuly16 = value:find("july 16", 1, true) ~= nil or compact:find("july16", 1, true) ~= nil
        local hasHeraldJuly16Id = compact:find("printmediakentuckyheraldjuly16", 1, true) ~= nil
            or compact:find("printtextkentuckyheraldjuly16", 1, true) ~= nil
            or compact:find("kentuckyheraldjuly16", 1, true) ~= nil
        if (hasHerald and hasJuly16) or hasHeraldJuly16Id then
            return true
        end
    end

    return false
end

EHR.DiseaseFlyers.IsKentuckyHeraldJuly16 = isKentuckyHeraldJuly16

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

    if isMedicalWildPlantsFlyer(item) then
        unlockMedicalWildPlants(character, item)
        markFlyerReadProgress(character, item, itemId)
        return
    end

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

    -- Disease flyers are one-shot reads, so mark the whole item complete
    -- and let vanilla draw the inventory checkmark.
    markFlyerReadProgress(character, item, itemId)
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
    if self.character and self.item and self.item.getFullType then
        markFlyerReadProgress(self.character, self.item, self.item:getFullType())
    end
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
        -- Real B42 newspapers must stay on the vanilla ISReadABook path so
        -- perform() can display their embedded print-media page. The Herald
        -- hook above unlocks Knox knowledge after that vanilla action finishes.
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
