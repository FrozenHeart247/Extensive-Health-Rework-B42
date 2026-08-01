-- Extensive Health Rework B42
-- Medical Monitor Watch battery actions, local SP drain and vanilla clock gating.

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_WatchBatteryCore"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.WatchBatteryClient = EHR.WatchBatteryClient or {}

local Client = EHR.WatchBatteryClient
local WatchBattery = EHR.WatchBattery
local clockWasSuppressed = false
local clockWasVisibleBeforeSuppression = nil
local luaDigitalWatchApi = nil
local luaClockWasSuppressed = false

local function watchText(key, fallback)
    local fullKey = "UI_EHR_WatchBattery_" .. tostring(key)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text(fullKey, fallback)
    end
    if getText then
        local ok, value = pcall(getText, fullKey)
        if ok and value and value ~= fullKey then return value end
    end
    return fallback
end

local function watchFormat(key, fallback, ...)
    local fullKey = "UI_EHR_WatchBattery_" .. tostring(key)
    local textValue = nil
    if EHR and EHR.Locale and EHR.Locale.Format then
        textValue = EHR.Locale.Format(fullKey, fallback, ...)
    else
        textValue = watchText(key, fallback)
        for i, value in ipairs({...}) do
            textValue = tostring(textValue):gsub("%%" .. tostring(i), tostring(value))
        end
    end

    -- Some translation loaders preserve an escaped literal percent as "%%".
    -- Context-menu labels are already fully formatted here, so collapse it.
    return tostring(textValue):gsub("%%+", function() return "%" end)
end

local function isInventoryItem(item)
    return item and instanceof and instanceof(item, "InventoryItem")
end

local function unwrapContextItem(value)
    if isInventoryItem(value) then return value end
    if value and value.items then
        for i = 1, #value.items do
            if isInventoryItem(value.items[i]) then return value.items[i] end
        end
    end
    return nil
end

local function getItemID(item)
    if not item or not item.getID then return nil end
    local ok, value = pcall(function() return item:getID() end)
    return ok and value or nil
end

local function getBatteryCharge(item)
    if not item or not item.getFullType or item:getFullType() ~= WatchBattery.BATTERY_TYPE then return 0 end
    -- Build 42.20 removed getUsedDelta() from the public Battery API.  The
    -- remaining charge is now exposed through getCurrentUsesFloat().
    local ok, value = pcall(function() return item:getCurrentUsesFloat() end)
    return ok and math.max(0, math.min(1, tonumber(value) or 0)) or 0
end

local function visitContainer(container, callback, visited)
    if not container or not container.getItems then return nil end
    visited = visited or {}
    if visited[container] then return nil end
    visited[container] = true

    local items = container:getItems()
    if not items or not items.size then return nil end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local result = callback(item)
            if result then return result end

            if item.getInventory then
                local ok, nested = pcall(function() return item:getInventory() end)
                if ok and nested then
                    result = visitContainer(nested, callback, visited)
                    if result then return result end
                end
            end
        end
    end
    return nil
end

local function findItemByID(player, itemID)
    if not player or itemID == nil then return nil end
    return visitContainer(player:getInventory(), function(item)
        local currentID = getItemID(item)
        if currentID ~= nil and tostring(currentID) == tostring(itemID) then return item end
        return nil
    end)
end

local function findUsableBattery(player)
    if not player then return nil end
    local bestBattery = nil
    local bestCharge = 0
    visitContainer(player:getInventory(), function(item)
        local charge = getBatteryCharge(item)
        if charge > bestCharge then
            bestBattery = item
            bestCharge = charge
        end
        return nil
    end)
    return bestBattery
end

local function markInventoryDirty(inventory)
    if inventory and inventory.setDrawDirty then
        pcall(function() inventory:setDrawDirty(true) end)
    end
end

local function removeLocalItem(item)
    if not item or not item.getContainer then return false end
    local container = item:getContainer()
    if not container then return false end
    local ok = pcall(function() container:Remove(item) end)
    if ok then markInventoryDirty(container) end
    return ok
end

local function refreshClock()
    if UIManager and UIManager.getClock then
        local clock = UIManager.getClock()
        if clock and clock.resize then pcall(function() clock:resize() end) end
    end
end

function Client.InsertBattery(player, watch, battery)
    if not player or not WatchBattery.IsMedicalWatch(watch) then return false end
    local state = WatchBattery.GetState(watch)
    if not state or state.installed then return false end

    battery = battery or findUsableBattery(player)
    local charge = getBatteryCharge(battery)
    if charge <= 0 then return false end

    if isClient and isClient() then
        local watchID = getItemID(watch)
        local batteryID = getItemID(battery)
        if watchID == nil or batteryID == nil then return false end
        sendClientCommand(player, "EHR", "InsertWatchBattery", {
            watchID = watchID,
            batteryID = batteryID,
        })
        return true
    end

    if not removeLocalItem(battery) then return false end
    WatchBattery.SetState(watch, true, charge)
    markInventoryDirty(player:getInventory())
    refreshClock()
    return true
end

function Client.RemoveBattery(player, watch)
    if not player or not WatchBattery.IsMedicalWatch(watch) then return false end
    local state = WatchBattery.GetState(watch)
    if not state or not state.installed then return false end

    if isClient and isClient() then
        local watchID = getItemID(watch)
        if watchID == nil then return false end
        sendClientCommand(player, "EHR", "RemoveWatchBattery", { watchID = watchID })
        return true
    end

    local charge = state.charge
    WatchBattery.SetState(watch, false, 0)
    WatchBattery.DisableAlarm(watch)

    local inventory = player:getInventory()
    local battery = inventory and inventory:AddItem(WatchBattery.BATTERY_TYPE) or nil
    if battery and battery.setUsedDelta then
        pcall(function() battery:setUsedDelta(charge) end)
    end
    markInventoryDirty(inventory)
    refreshClock()
    return battery ~= nil
end

local function addContextOption(context, label, target, callback, ...)
    local option = context:addOption(label, target, callback, ...)
    if option and EHR.SetContextOptionIcon then
        pcall(function() EHR.SetContextOptionIcon(option, target) end)
    end
    return option
end

function Client.OnFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local seen = {}
    for _, value in ipairs(items) do
        local watch = unwrapContextItem(value)
        local watchID = getItemID(watch)
        if WatchBattery.IsMedicalWatch(watch) and not seen[tostring(watchID)] then
            seen[tostring(watchID)] = true
            local state = WatchBattery.GetState(watch)
            if state and state.installed then
                local percent = math.floor((state.charge * 100) + 0.5)
                addContextOption(
                    context,
                    watchFormat("Remove", "Remove Battery (%1%)", percent),
                    watch,
                    function(targetWatch, targetPlayer)
                        Client.RemoveBattery(targetPlayer, targetWatch)
                    end,
                    player
                )
            elseif state then
                local battery = findUsableBattery(player)
                if battery then
                    local percent = math.floor((getBatteryCharge(battery) * 100) + 0.5)
                    addContextOption(
                        context,
                        watchFormat("Insert", "Insert Battery (%1%)", percent),
                        watch,
                        function(targetWatch, targetPlayer, targetBattery)
                            Client.InsertBattery(targetPlayer, targetWatch, targetBattery)
                        end,
                        player,
                        battery
                    )
                end
            end
        end
    end
end

local function isClockItem(item)
    if not item or not instanceof then return false end
    return instanceof(item, "AlarmClock") or instanceof(item, "AlarmClockClothing")
end

local function playerClockState(player)
    if not player or (player.isDead and player:isDead()) then return false, false end

    local hasFunctionalClock = false
    local hasUnpoweredMedicalWatch = false

    local function inspectActiveItem(item)
        if not isClockItem(item) then return end
        if WatchBattery.IsMedicalWatch(item) then
            if WatchBattery.IsPowered(item) then
                hasFunctionalClock = true
            else
                hasUnpoweredMedicalWatch = true
            end
        else
            hasFunctionalClock = true
        end
    end

    local wornItems = player.getWornItems and player:getWornItems() or nil
    if wornItems and wornItems.size then
        for i = 0, wornItems:size() - 1 do
            inspectActiveItem(wornItems:getItemByIndex(i))
        end
    end

    local inventory = player.getInventory and player:getInventory() or nil
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if items and items.size then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if isClockItem(item) then
                local worn = false
                local equipped = false
                pcall(function() worn = item:isWorn() == true end)
                pcall(function() equipped = item:isEquipped() == true end)
                if worn or equipped then inspectActiveItem(item) end
            end
        end
    end
    return hasFunctionalClock, hasUnpoweredMedicalWatch
end

local function isLuaDigitalWatchActive()
    if not getActivatedMods then return false end
    local ok, activeMods = pcall(getActivatedMods)
    return ok
        and activeMods
        and activeMods.contains
        and activeMods:contains("LuaDigitalWatchUI")
end

local function getLuaDigitalWatchApi()
    if luaDigitalWatchApi then return luaDigitalWatchApi end
    if not isLuaDigitalWatchActive() then return nil end

    local ok, api = pcall(require, "LuaDigitalWatch/LuaDigitalWatch")
    if not ok or type(api) ~= "table" or type(api.setOverride) ~= "function" then
        return nil
    end
    if type(api.init) == "function" then pcall(api.init) end
    luaDigitalWatchApi = api
    return luaDigitalWatchApi
end

local function suppressLuaDigitalWatch(shouldSuppress)
    local api = getLuaDigitalWatchApi()
    if not api then return end

    if shouldSuppress and not luaClockWasSuppressed then
        api.setOverride("visible", false)
        luaClockWasSuppressed = true
    elseif not shouldSuppress and luaClockWasSuppressed then
        if type(api.clearOverride) == "function" then
            api.clearOverride("visible")
        else
            api.setOverride("visible", nil)
        end
        luaClockWasSuppressed = false
    end
end

function Client.UpdateVanillaClockVisibility()
    local hasFunctionalClock = false
    local hasUnpoweredMedicalWatch = false
    local playerCount = getNumActivePlayers and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, playerCount - 1) do
        local player = getSpecificPlayer(playerNum)
        local functional, unpoweredMedical = playerClockState(player)
        hasFunctionalClock = hasFunctionalClock or functional
        hasUnpoweredMedicalWatch = hasUnpoweredMedicalWatch or unpoweredMedical
    end

    local shouldSuppress = hasUnpoweredMedicalWatch and not hasFunctionalClock
    suppressLuaDigitalWatch(shouldSuppress)

    local clock = UIManager and UIManager.getClock and UIManager.getClock() or nil
    if clock then
        if shouldSuppress then
            if not clockWasSuppressed then
                if clock.isVisible then
                    local ok, value = pcall(function() return clock:isVisible() end)
                    clockWasVisibleBeforeSuppression = ok and value == true or nil
                end
                clockWasSuppressed = true
            end
            if clock.setVisible then pcall(function() clock:setVisible(false) end) end
        elseif clockWasSuppressed then
            if clockWasVisibleBeforeSuppression ~= false and clock.setVisible then
                pcall(function() clock:setVisible(true) end)
            end
            if clock.resize then pcall(function() clock:resize() end) end
            clockWasSuppressed = false
            clockWasVisibleBeforeSuppression = nil
        end
    end

end

local function drainSinglePlayerWatches()
    if isClient and isClient() then return end
    local playerCount = getNumActivePlayers and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, playerCount - 1) do
        local player = getSpecificPlayer(playerNum)
        for _, watch in ipairs(WatchBattery.GetWornMedicalWatches(player)) do
            local changed, depleted = WatchBattery.Drain(watch, WatchBattery.TEN_MINUTE_HOURS)
            if changed and depleted then WatchBattery.DisableAlarm(watch) end
        end
    end
end

local function applyServerState(args)
    if not args or args.itemID == nil then return end
    local playerCount = getNumActivePlayers and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, playerCount - 1) do
        local player = getSpecificPlayer(playerNum)
        local watch = findItemByID(player, args.itemID)
        if WatchBattery.IsMedicalWatch(watch) then
            WatchBattery.SetState(watch, args.installed == true, tonumber(args.charge) or 0)
            if not WatchBattery.IsPowered(watch) then WatchBattery.DisableAlarm(watch) end
            markInventoryDirty(player:getInventory())
            refreshClock()
            return
        end
    end
end

function Client.OnServerCommand(module, command, args)
    if module == "EHR_WatchBattery" and command == "Sync" then
        applyServerState(args)
    end
end

local function requestServerState()
    if not (isClient and isClient()) then return end
    local playerCount = getNumActivePlayers and getNumActivePlayers() or 1
    for playerNum = 0, math.max(0, playerCount - 1) do
        local player = getSpecificPlayer(playerNum)
        if player then sendClientCommand(player, "EHR", "RequestWatchBatterySync", {}) end
    end
end

local function resetWatchUIIntegration()
    if luaClockWasSuppressed and luaDigitalWatchApi then
        if type(luaDigitalWatchApi.clearOverride) == "function" then
            pcall(luaDigitalWatchApi.clearOverride, "visible")
        else
            pcall(luaDigitalWatchApi.setOverride, "visible", nil)
        end
    end
    luaClockWasSuppressed = false
    luaDigitalWatchApi = nil

    local clock = UIManager and UIManager.getClock and UIManager.getClock() or nil
    if clockWasSuppressed and clock then
        if clockWasVisibleBeforeSuppression ~= false and clock.setVisible then
            pcall(function() clock:setVisible(true) end)
        end
        if clock.resize then pcall(function() clock:resize() end) end
    end
    clockWasSuppressed = false
    clockWasVisibleBeforeSuppression = nil

end

if Events and not Client.EventsRegistered then
    Events.OnFillInventoryObjectContextMenu.Add(Client.OnFillInventoryObjectContextMenu)
    Events.OnPreUIDraw.Add(Client.UpdateVanillaClockVisibility)
    Events.EveryTenMinutes.Add(drainSinglePlayerWatches)
    Events.OnServerCommand.Add(Client.OnServerCommand)
    Events.OnGameStart.Add(requestServerState)
    Events.OnCreateUI.Add(resetWatchUIIntegration)
    Events.OnDisconnect.Add(resetWatchUIIntegration)
    Events.OnMainMenuEnter.Add(resetWatchUIIntegration)
    Client.EventsRegistered = true
end

return Client
