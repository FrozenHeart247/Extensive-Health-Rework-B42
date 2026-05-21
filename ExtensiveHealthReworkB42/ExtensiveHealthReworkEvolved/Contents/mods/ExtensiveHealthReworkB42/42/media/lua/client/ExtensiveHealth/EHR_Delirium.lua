--[[
    Extensive Health Rework B42
    Delirium / madness runtime module

    A permanent stress-collapse condition. The disease record is stored in the
    normal EHR disease table; this client module handles hallucination episodes,
    visual tinting, and unsafe impulses.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Disease"
require "ISUI/ISPanel"
require "TimedActions/ISSmashWindow"
require "TimedActions/ISWalkToTimedAction"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.Delirium = EHR.Delirium or {}
EHR.Delirium.Runtime = EHR.Delirium.Runtime or {}

EHR.Delirium.Config = {
    STRESS_THRESHOLD = 0.98,
    HOURS_AT_MAX_STRESS_TO_TRIGGER = 12,
    CHECK_INTERVAL_HOURS = 1 / 60,

    FIRST_EPISODE_MIN_MINUTES = 4,
    FIRST_EPISODE_MAX_MINUTES = 8,
    EPISODE_MIN_MINUTES = 30,
    EPISODE_MAX_MINUTES = 60,

    OVERLAY_MIN_MINUTES = 4,
    OVERLAY_MAX_MINUTES = 8,
    OVERLAY_ALPHA_MIN = 0.08,
    OVERLAY_ALPHA_MAX = 0.16,

    WINDOW_SEARCH_RADIUS = 2,
    WINDOW_IMPULSE_CHANCE = 1.0,

    LINE_DURATION_TICKS = 600,
}

EHR.Delirium.Sounds = {
    "EHRDeliriumAliensSound",
    "EHRDeliriumBigBell",
    "EHRDeliriumCantSleepVoices",
    "EHRDeliriumChicken",
    "EHRDeliriumClownBackground",
    "EHRDeliriumClownJingle",
    "EHRDeliriumClownLaugh",
    "EHRDeliriumComicLaugh",
    "EHRDeliriumCreepyLaugh",
    "EHRDeliriumCreepyVoicesWhisper",
    "EHRDeliriumDevilishVoice",
    "EHRDeliriumHideClownSound",
    "EHRDeliriumSchoolBell",
    "EHRDeliriumStrangeWhispers",
    "EHRDeliriumTheyKnowNothingVoices",
    "EHRDeliriumWhisperVoicesA",
    "EHRDeliriumWhisperVoicesB",
}

EHR.Delirium.Lines = {
    "Ahahaha! Why my left sock telling me to grow a car???",
    "No No No you pink elephant.. I wont eat that mushrooom he he he",
    "Pu pi pi tapi pu pipipi tapi??? Pu pi pi tapi pu pipipi tapi!!!",
    "Wait what if I'm the zombie?? Oh no.. that's not good right? I wanna be a cute cattito!",
    "Hm? Yea I think the same! That stew the other day was top notch! Except that strange eye . I throw it out. ",
    "I.. I forgot how to breath.. I need a bowl of nails right now!!!",
    "Shish! I can't concentrate you idiot. Whait.. Wha was I doing?",
    "Haha haaaa! What a cute squirel. But it's kinda big! Is this a super rare one? I need to talk to it",
    "I wonder why all of my cars always complaining... Can't you guys keep your mouth shut?",
    "I wanna fly! Oh oh right. I need to find a garbage bag and use it as parachute!",
    "The floor.. Was it always made from noodles?",
}

EHR.Delirium.OverlayColors = {
    { r = 0.90, g = 0.05, b = 0.04 },
    { r = 0.12, g = 0.80, b = 0.26 },
    { r = 0.18, g = 0.42, b = 1.00 },
    { r = 0.72, g = 0.20, b = 0.95 },
    { r = 1.00, g = 0.72, b = 0.08 },
    { r = 0.12, g = 0.82, b = 0.85 },
}

local function worldHour()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime then
        local ok, hour = pcall(function() return gameTime:getWorldAgeHours() end)
        if ok and hour then return hour end
    end
    return 0
end

local function randomMinutes(minMinutes, maxMinutes)
    minMinutes = tonumber(minMinutes) or 0
    maxMinutes = tonumber(maxMinutes) or minMinutes
    if maxMinutes <= minMinutes then return minMinutes / 60 end
    return (minMinutes + ZombRand((maxMinutes - minMinutes) + 1)) / 60
end

local function randomFloat(minValue, maxValue)
    minValue = tonumber(minValue) or 0
    maxValue = tonumber(maxValue) or minValue
    if maxValue <= minValue then return minValue end
    return minValue + (ZombRand(1000) / 1000) * (maxValue - minValue)
end

local function getLocalPlayerCount()
    if getNumActivePlayers then
        local ok, count = pcall(getNumActivePlayers)
        if ok and count and count > 0 then return count end
    end
    return 1
end

local function getPlayerIndex(player, fallback)
    if player and player.getPlayerNum then
        local ok, index = pcall(function() return player:getPlayerNum() end)
        if ok and index ~= nil then return index end
    end
    return fallback or 0
end

local function isPlayerValid(player)
    if not player then return false end
    local okDead, dead = pcall(function()
        if player.isDead then return player:isDead() end
        return false
    end)
    if okDead and dead == true then return false end
    return true
end

local function isPlayerBusyForEpisode(player)
    if not isPlayerValid(player) then return true end

    local okAsleep, asleep = pcall(function()
        if player.isAsleep then return player:isAsleep() end
        return false
    end)
    if okAsleep and asleep == true then return true end

    local okVehicle, vehicle = pcall(function()
        if player.getVehicle then return player:getVehicle() end
        return nil
    end)
    if okVehicle and vehicle then return true end

    return false
end

local function getStress(player)
    local stats = player and player.getStats and player:getStats() or nil
    if not stats then return 0 end

    if CharacterStat and CharacterStat.STRESS and stats.get then
        local ok, value = pcall(function() return stats:get(CharacterStat.STRESS) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end

    if stats.getStress then
        local ok, value = pcall(function() return stats:getStress() end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end

    return 0
end

local function getPlayerDiseaseData(player)
    if not player then return nil end
    if EHR.Disease and EHR.Disease.InitializePlayer then
        pcall(EHR.Disease.InitializePlayer, player)
    end
    if EHR.Disease and EHR.Disease.GetDiseaseData then
        return EHR.Disease.GetDiseaseData(player)
    end
    return nil
end

local function getState(player)
    local modData = player and player.getModData and player:getModData() or nil
    if not modData then return nil end
    modData.EHR_Delirium = modData.EHR_Delirium or {}
    return modData.EHR_Delirium
end

function EHR.Delirium.GetRuntime(playerIndex)
    EHR.Delirium.Runtime[playerIndex] = EHR.Delirium.Runtime[playerIndex] or {}
    return EHR.Delirium.Runtime[playerIndex]
end

function EHR.Delirium.HasActive(player)
    local data = getPlayerDiseaseData(player)
    return data and data.active and type(data.active.delirium) == "table"
end

function EHR.Delirium.Contract(player, currentHour)
    if not isPlayerValid(player) or EHR.Delirium.HasActive(player) then return false end

    if EHR.Disease and EHR.Disease.Contract then
        pcall(EHR.Disease.Contract, player, "delirium")
    end

    local data = getPlayerDiseaseData(player)
    if not data or not data.active or not data.active.delirium then return false end

    currentHour = currentHour or worldHour()
    local disease = data.active.delirium
    disease.startTime = currentHour
    disease.incubationEnd = currentHour
    disease.peakTime = currentHour
    disease.endTime = currentHour + 999999
    disease.stage = 1
    disease.stageCount = 1
    disease.progress = 0
    disease.severity = tonumber(disease.severity) or 0.85
    disease.permanent = true
    disease.noCure = false
    disease.mental = true

    local state = getState(player)
    if state then
        state.highStressSince = nil
        state.triggeredAt = currentHour
    end

    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end

    EHR.Log("Delirium triggered by prolonged maximum stress")
    return true
end

function EHR.Delirium.ScheduleNextEpisode(runtime, currentHour, first)
    local cfg = EHR.Delirium.Config
    if first then
        runtime.nextEpisodeHour = currentHour + randomMinutes(cfg.FIRST_EPISODE_MIN_MINUTES, cfg.FIRST_EPISODE_MAX_MINUTES)
    else
        runtime.nextEpisodeHour = currentHour + randomMinutes(cfg.EPISODE_MIN_MINUTES, cfg.EPISODE_MAX_MINUTES)
    end
end

EHRDeliriumOverlay = EHRDeliriumOverlay or ISPanel:derive("EHRDeliriumOverlay")

function EHRDeliriumOverlay:new(playerIndex)
    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()
    local o = ISPanel.new(self, 0, 0, width, height)
    o.playerIndex = playerIndex or 0
    o.background = false
    o.border = false
    return o
end

function EHRDeliriumOverlay:initialise()
    ISPanel.initialise(self)
    if self.javaObject and self.javaObject.setConsumeMouseEvents then
        self.javaObject:setConsumeMouseEvents(false)
    end
    if self.setAlwaysOnTop then
        self:setAlwaysOnTop(true)
    end
end

function EHRDeliriumOverlay:onMouseDown(x, y) return false end
function EHRDeliriumOverlay:onMouseUp(x, y) return false end
function EHRDeliriumOverlay:onRightMouseDown(x, y) return false end
function EHRDeliriumOverlay:onRightMouseUp(x, y) return false end
function EHRDeliriumOverlay:onMouseMove(dx, dy) return false end
function EHRDeliriumOverlay:onMouseMoveOutside(dx, dy) return false end
function EHRDeliriumOverlay:onMouseWheel(del) return false end

function EHRDeliriumOverlay:prerender()
    self:setX(0)
    self:setY(0)
    self:setWidth(getCore():getScreenWidth())
    self:setHeight(getCore():getScreenHeight())
end

function EHRDeliriumOverlay:render()
    local runtime = EHR.Delirium.GetRuntime(self.playerIndex or 0)
    local untilHour = tonumber(runtime.overlayUntilHour) or 0
    local startHour = tonumber(runtime.overlayStartHour) or 0
    local now = worldHour()
    if now >= untilHour or untilHour <= startHour then return end

    local color = runtime.overlayColor or EHR.Delirium.OverlayColors[1]
    local duration = math.max(0.001, untilHour - startHour)
    local remaining = math.max(0, untilHour - now)
    local elapsed = math.max(0, now - startHour)
    local fade = math.min(1, remaining / math.min(duration, 1 / 60), elapsed / math.min(duration, 1 / 60))
    local pulse = 0.78 + math.sin(now * 320) * 0.22
    local alpha = (tonumber(runtime.overlayAlpha) or 0.10) * math.max(0, fade) * pulse

    self:drawRect(0, 0, self.width, self.height, alpha, color.r, color.g, color.b)
end

function EHR.Delirium.EnsureOverlay(playerIndex)
    local runtime = EHR.Delirium.GetRuntime(playerIndex)
    if runtime.overlay and runtime.overlay.getIsVisible and runtime.overlay:getIsVisible() then
        if runtime.overlay.javaObject and runtime.overlay.javaObject.setConsumeMouseEvents then
            runtime.overlay.javaObject:setConsumeMouseEvents(false)
        end
        return runtime.overlay
    end

    local overlay = EHRDeliriumOverlay:new(playerIndex)
    overlay:initialise()
    overlay:instantiate()
    if overlay.javaObject and overlay.javaObject.setConsumeMouseEvents then
        overlay.javaObject:setConsumeMouseEvents(false)
    end
    overlay:addToUIManager()
    if overlay.javaObject and overlay.javaObject.setConsumeMouseEvents then
        overlay.javaObject:setConsumeMouseEvents(false)
    end
    if overlay.setAlwaysOnTop then
        overlay:setAlwaysOnTop(true)
    end
    runtime.overlay = overlay
    return overlay
end

function EHR.Delirium.RemoveOverlay(playerIndex)
    local runtime = EHR.Delirium.GetRuntime(playerIndex)
    if runtime.overlay and runtime.overlay.removeFromUIManager then
        pcall(function() runtime.overlay:removeFromUIManager() end)
    end
    runtime.overlay = nil
    runtime.overlayStartHour = nil
    runtime.overlayUntilHour = nil
    runtime.overlayAlpha = nil
    runtime.overlayColor = nil
end

function EHR.Delirium.UpdateOverlay(playerIndex, currentHour)
    local runtime = EHR.Delirium.GetRuntime(playerIndex)
    if not runtime.overlay then return end

    if runtime.overlay.javaObject and runtime.overlay.javaObject.setConsumeMouseEvents then
        runtime.overlay.javaObject:setConsumeMouseEvents(false)
    end

    local untilHour = tonumber(runtime.overlayUntilHour) or 0
    if untilHour <= 0 or currentHour >= untilHour then
        EHR.Delirium.RemoveOverlay(playerIndex)
    end
end

function EHR.Delirium.StartOverlay(playerIndex, currentHour)
    local runtime = EHR.Delirium.GetRuntime(playerIndex)
    local cfg = EHR.Delirium.Config
    local colors = EHR.Delirium.OverlayColors

    runtime.overlayStartHour = currentHour
    runtime.overlayUntilHour = currentHour + randomMinutes(cfg.OVERLAY_MIN_MINUTES, cfg.OVERLAY_MAX_MINUTES)
    runtime.overlayAlpha = randomFloat(cfg.OVERLAY_ALPHA_MIN, cfg.OVERLAY_ALPHA_MAX)
    runtime.overlayColor = colors[ZombRand(#colors) + 1]

    EHR.Delirium.EnsureOverlay(playerIndex)
end

local function getObjects(square)
    if not square or not square.getObjects then return nil end
    local ok, objects = pcall(function() return square:getObjects() end)
    if ok then return objects end
    return nil
end

local function isIntactWindow(object)
    if not object then return false end
    if instanceof and not instanceof(object, "IsoWindow") then return false end

    local okDestroyed, destroyed = pcall(function()
        if object.isDestroyed then return object:isDestroyed() end
        return false
    end)
    if okDestroyed and destroyed == true then return false end

    local okSmashed, smashed = pcall(function()
        if object.isSmashed then return object:isSmashed() end
        return false
    end)
    if okSmashed and smashed == true then return false end

    return true
end

function EHR.Delirium.FindNearbyWindow(player)
    local square = player and player.getCurrentSquare and player:getCurrentSquare() or nil
    if not square then return nil end

    local cell = getCell and getCell() or nil
    if not cell then return nil end

    local radius = EHR.Delirium.Config.WINDOW_SEARCH_RADIUS
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local z = math.floor(player:getZ())

    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(px + dx, py + dy, z)
            local objects = getObjects(sq)
            if objects then
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    if isIntactWindow(object) then
                        return object
                    end
                end
            end
        end
    end

    return nil
end

function EHR.Delirium.TrySmashNearbyWindow(player)
    if not isPlayerValid(player) then return false end
    if ZombRand(100) >= math.floor((EHR.Delirium.Config.WINDOW_IMPULSE_CHANCE or 0) * 100) then return false end

    local window = EHR.Delirium.FindNearbyWindow(player)
    if not window then return false end

    local ok = pcall(function()
        if luautils and luautils.walkAdjWindowOrDoor and window.getSquare and luautils.walkAdjWindowOrDoor(player, window:getSquare(), window) then
            ISTimedActionQueue.add(ISSmashWindow:new(player, window))
        elseif ISSmashWindow and ISTimedActionQueue then
            ISTimedActionQueue.add(ISSmashWindow:new(player, window))
        end
    end)

    if ok then
        EHR.Log("Delirium impulse: queued nearby window smash")
    end
    return ok
end

local function sayRandomLine(player, runtime)
    local lines = EHR.Delirium.Lines
    if not lines or #lines == 0 or not player or not player.Say then return end

    local index = ZombRand(#lines) + 1
    if #lines > 1 and runtime.lastLineIndex == index then
        index = (index % #lines) + 1
    end
    runtime.lastLineIndex = index
    local line = lines[index]
    local usedHaloNote = false
    if player.setHaloNote then
        usedHaloNote = pcall(function()
            player:setHaloNote(line, 255, 230, 185, EHR.Delirium.Config.LINE_DURATION_TICKS)
        end)
    end
    if not usedHaloNote then
        pcall(function() EHR.Locale.Say(player, line) end)
    end
end

local function playRandomSound(player, runtime)
    local sounds = EHR.Delirium.Sounds
    if not sounds or #sounds == 0 or not player then return end

    local index = ZombRand(#sounds) + 1
    if #sounds > 1 and runtime.lastSoundIndex == index then
        index = (index % #sounds) + 1
    end
    runtime.lastSoundIndex = index
    pcall(function() player:playSound(sounds[index]) end)
end

function EHR.Delirium.StartEpisode(player, playerIndex, currentHour)
    if isPlayerBusyForEpisode(player) then return end

    local runtime = EHR.Delirium.GetRuntime(playerIndex)
    playRandomSound(player, runtime)
    sayRandomLine(player, runtime)
    EHR.Delirium.StartOverlay(playerIndex, currentHour)
    EHR.Delirium.TrySmashNearbyWindow(player)
    EHR.Delirium.ScheduleNextEpisode(runtime, currentHour, false)
end

function EHR.Delirium.UpdateStressTrigger(player, currentHour)
    if not isPlayerValid(player) then return end
    if EHR.Delirium.HasActive(player) then return end

    local state = getState(player)
    if not state then return end

    local stress = getStress(player)
    if stress >= EHR.Delirium.Config.STRESS_THRESHOLD then
        state.highStressSince = tonumber(state.highStressSince) or currentHour
        if (currentHour - state.highStressSince) >= EHR.Delirium.Config.HOURS_AT_MAX_STRESS_TO_TRIGGER then
            EHR.Delirium.Contract(player, currentHour)
        end
    else
        state.highStressSince = nil
    end
end

function EHR.Delirium.UpdateEpisodes(player, playerIndex, currentHour)
    local runtime = EHR.Delirium.GetRuntime(playerIndex)

    if not EHR.Delirium.HasActive(player) then
        runtime.nextEpisodeHour = nil
        EHR.Delirium.RemoveOverlay(playerIndex)
        return
    end

    if not runtime.nextEpisodeHour then
        EHR.Delirium.ScheduleNextEpisode(runtime, currentHour, true)
    end

    if currentHour >= runtime.nextEpisodeHour then
        EHR.Delirium.StartEpisode(player, playerIndex, currentHour)
    end
end

function EHR.Delirium.OnTick()
    local currentHour = worldHour()
    if currentHour < (EHR.Delirium.NextCheckHour or 0) then return end

    EHR.Delirium.NextCheckHour = currentHour + EHR.Delirium.Config.CHECK_INTERVAL_HOURS

    for i = 0, getLocalPlayerCount() - 1 do
        local player = getSpecificPlayer and getSpecificPlayer(i) or nil
        local playerIndex = getPlayerIndex(player, i)
        EHR.Delirium.UpdateOverlay(playerIndex, currentHour)
        EHR.Delirium.UpdateStressTrigger(player, currentHour)
        EHR.Delirium.UpdateEpisodes(player, playerIndex, currentHour)
    end
end

function EHR.Delirium.OnPlayerDeath(player)
    local playerIndex = getPlayerIndex(player, 0)
    EHR.Delirium.RemoveOverlay(playerIndex)
    EHR.Delirium.Runtime[playerIndex] = nil
end

if Events then
    Events.OnTick.Add(EHR.Delirium.OnTick)
    if Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(EHR.Delirium.OnPlayerDeath)
    end
end

EHR.Log("Delirium module loaded")
