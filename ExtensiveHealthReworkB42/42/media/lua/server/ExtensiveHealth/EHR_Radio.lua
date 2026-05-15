--[[
    Extensive Health Rework B42
    The Last Prescription dynamic radio station.
]]--

if isClient() and not isServer() then return end

require "ExtensiveHealth/EHR_Main"

local RadioMessages = require "ExtensiveHealth/EHR_RadioMessages"

EHR = EHR or {}
EHR.Radio = EHR.Radio or {}

local RADIO = {
    NAME = "The Last Prescription",
    UUID = "EHR-LAST-PRESCRIPTION-1470",
    FREQUENCY = 147000,
    CATEGORY = "Emergency",
    HOURS = {
        MORNING = 9,
        AFTERNOON = 15,
        EVENING = 21,
    },
}

local initialized = false

local function isEnabled()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        return SandboxVars.ExtensiveHealthRework.TheLastPrescriptionEnabled ~= false
    end
    return true
end

local function log(message)
    if EHR and EHR.Log then
        EHR.Log("[Radio] " .. tostring(message))
    end
end

local function getChannelCategory()
    if not ChannelCategory then return nil end
    return ChannelCategory[RADIO.CATEGORY] or ChannelCategory.Other
end

local function ensureLiveChannel(scriptManager)
    if not scriptManager or not DynamicRadioChannel then
        return
    end

    DynamicRadio.cache = DynamicRadio.cache or {}
    if DynamicRadio.cache[RADIO.UUID] then
        return
    end

    local category = getChannelCategory()
    if not category then
        return
    end

    local dynamicChannel = DynamicRadioChannel.new(RADIO.NAME, RADIO.FREQUENCY, category, RADIO.UUID)
    if not dynamicChannel then
        return
    end

    dynamicChannel:setAirCounterMultiplier(1.35)
    scriptManager:AddChannel(dynamicChannel, false)
    DynamicRadio.cache[RADIO.UUID] = dynamicChannel
end

local function registerChannel(scriptManager)
    if not DynamicRadio then
        return
    end

    DynamicRadio.channels = DynamicRadio.channels or {}

    for i = 1, #DynamicRadio.channels do
        local channel = DynamicRadio.channels[i]
        if channel and channel.uuid == RADIO.UUID then
            ensureLiveChannel(scriptManager)
            return
        end
    end

    table.insert(DynamicRadio.channels, {
        name = RADIO.NAME,
        freq = RADIO.FREQUENCY,
        category = RADIO.CATEGORY,
        uuid = RADIO.UUID,
        register = true,
        airCounterMultiplier = 1.35,
    })

    ensureLiveChannel(scriptManager)
end

registerChannel()

local function getRadioChannel()
    if DynamicRadio and DynamicRadio.cache then
        return DynamicRadio.cache[RADIO.UUID]
    end
    return nil
end

local function createRadioBroadcast(lines)
    if not lines or #lines == 0 then
        return nil
    end

    if not RadioBroadCast or not RadioLine then
        log("RadioBroadCast/RadioLine API is not available")
        return nil
    end

    local broadcast = RadioBroadCast.new(RADIO.UUID, -1, -1)
    for i = 1, #lines do
        local entry = lines[i]
        if entry and entry.text then
            local r = entry.r or 0.75
            local g = entry.g or 0.75
            local b = entry.b or 0.75
            local fx = entry.fx

            if fx and fx ~= "" then
                broadcast:AddRadioLine(RadioLine.new(entry.text, r, g, b, fx))
            else
                broadcast:AddRadioLine(RadioLine.new(entry.text, r, g, b))
            end
        end
    end

    return broadcast
end

local function getState()
    local state = ModData.getOrCreate("EHR_Radio")
    state.lastBroadcastDay = state.lastBroadcastDay or -1
    state.lastBroadcastHour = state.lastBroadcastHour or -1
    return state
end

local function buildBroadcast(day, hour)
    if hour == RADIO.HOURS.MORNING then
        return RadioMessages.BuildMorningTip(day), "morning tip"
    elseif hour == RADIO.HOURS.AFTERNOON then
        return RadioMessages.BuildAfternoonTalk(day), "afternoon talk"
    elseif hour == RADIO.HOURS.EVENING then
        return RadioMessages.BuildEveningDisease(day), "evening disease file"
    end

    return nil, nil
end

local function onEveryHour()
    if not isEnabled() then
        return
    end

    local gameTime = getGameTime()
    if not gameTime then return end

    local hour = gameTime:getHour()
    if hour ~= RADIO.HOURS.MORNING and hour ~= RADIO.HOURS.AFTERNOON and hour ~= RADIO.HOURS.EVENING then
        return
    end

    local day = (gameTime:getNightsSurvived() or 0) + 1
    local state = getState()
    if state.lastBroadcastDay == day and state.lastBroadcastHour == hour then
        return
    end

    local lines, kind = buildBroadcast(day, hour)
    if not lines then
        return
    end

    local channel = getRadioChannel()
    if not channel then
        log("Could not find DynamicRadio channel cache for " .. RADIO.NAME)
        return
    end

    local broadcast = createRadioBroadcast(lines)
    if not broadcast then
        return
    end

    channel:setAiringBroadcast(broadcast)
    state.lastBroadcastDay = day
    state.lastBroadcastHour = hour

    if ModData and ModData.transmit then
        pcall(function() ModData.transmit("EHR_Radio") end)
    end

    log(string.format("%s aired at %02d:00 on day %d", kind or "broadcast", hour, day))
end

function EHR.Radio.Initialize()
    if initialized then
        return
    end

    registerChannel()
    initialized = true

    if Events and Events.EveryHours then
        Events.EveryHours.Add(onEveryHour)
    end

    log(RADIO.NAME .. " initialized at 147.0")
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(EHR.Radio.Initialize)
end

if Events and Events.OnLoadRadioScripts then
    Events.OnLoadRadioScripts.Add(registerChannel)
end

return EHR.Radio
