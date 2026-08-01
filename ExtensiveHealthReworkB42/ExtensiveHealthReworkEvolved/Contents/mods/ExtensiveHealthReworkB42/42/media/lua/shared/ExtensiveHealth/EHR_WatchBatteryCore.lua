-- Extensive Health Rework B42
-- Battery state shared by the Medical Monitor Watch client and server logic.

EHR = EHR or {}
EHR.WatchBattery = EHR.WatchBattery or {}

local WatchBattery = EHR.WatchBattery

WatchBattery.LIFETIME_HOURS = 24 * 7
WatchBattery.TEN_MINUTE_HOURS = 10 / 60
WatchBattery.BATTERY_TYPE = "Base.Battery"
WatchBattery.WATCH_TYPES = WatchBattery.WATCH_TYPES or {
    ["ExtensiveHealth.EHRMedicalWatch_Left"] = true,
    ["ExtensiveHealth.EHRMedicalWatch_Right"] = true,
    EHRMedicalWatch_Left = true,
    EHRMedicalWatch_Right = true,
}

local function clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function WatchBattery.IsMedicalWatch(item)
    if not item then return false end

    local fullType = nil
    local itemType = nil
    pcall(function()
        if item.getFullType then fullType = item:getFullType() end
    end)
    pcall(function()
        if item.getType then itemType = item:getType() end
    end)

    return (fullType and WatchBattery.WATCH_TYPES[fullType] == true)
            or (itemType and WatchBattery.WATCH_TYPES[itemType] == true)
            or false
end

function WatchBattery.GetState(item)
    if not WatchBattery.IsMedicalWatch(item) or not item.getModData then return nil end

    local modData = item:getModData()
    if not modData then return nil end

    -- Migration policy: watches that predate the battery system, as well as newly
    -- generated watches, start with one full battery so an update never disables
    -- an already-owned Medical Monitor Watch without warning.
    if type(modData.EHR_WatchBattery) ~= "table" then
        modData.EHR_WatchBattery = {
            version = 1,
            installed = true,
            charge = 1.0,
        }
    end

    local state = modData.EHR_WatchBattery
    state.version = 1
    if state.installed == nil then state.installed = true end
    state.installed = state.installed == true
    state.charge = clamp01(state.charge == nil and 1.0 or state.charge)
    if not state.installed then state.charge = 0 end
    return state
end

function WatchBattery.SetState(item, installed, charge)
    local state = WatchBattery.GetState(item)
    if not state then return false end

    state.installed = installed == true
    state.charge = state.installed and clamp01(charge) or 0
    return true
end

function WatchBattery.IsPowered(item)
    local state = WatchBattery.GetState(item)
    return state ~= nil and state.installed == true and state.charge > 0.000001
end

function WatchBattery.GetCharge(item)
    local state = WatchBattery.GetState(item)
    return state and state.charge or 0
end

function WatchBattery.Drain(item, elapsedHours)
    local state = WatchBattery.GetState(item)
    if not state or not state.installed or state.charge <= 0 then return false, false end

    local drain = math.max(0, tonumber(elapsedHours) or 0) / WatchBattery.LIFETIME_HOURS
    if drain <= 0 then return false, false end

    local oldCharge = state.charge
    state.charge = clamp01(oldCharge - drain)
    local depleted = oldCharge > 0 and state.charge <= 0
    return state.charge ~= oldCharge, depleted
end

function WatchBattery.GetWornMedicalWatches(player)
    local result = {}
    if not player or not player.getWornItems then return result end

    local wornItems = player:getWornItems()
    if not wornItems or not wornItems.size then return result end

    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if WatchBattery.IsMedicalWatch(item) then
            result[#result + 1] = item
        end
    end
    return result
end

function WatchBattery.PlayerHasPoweredWatch(player)
    for _, item in ipairs(WatchBattery.GetWornMedicalWatches(player)) do
        if WatchBattery.IsPowered(item) then return true end
    end
    return false
end

function WatchBattery.DisableAlarm(item)
    if not item then return end
    pcall(function()
        if item.setAlarmSet then item:setAlarmSet(false) end
    end)
    pcall(function()
        if item.stopRinging then item:stopRinging() end
    end)
end

return WatchBattery
