--[[
    Extensive Health Rework B42
    Multiplayer Examination Module

    Allows players to examine the health status of nearby players.
    Adds "Examine Health" context menu option when right-clicking on another player.

    Features:
    - Proximity detection (5 tile radius)
    - Opens Medical Monitor for target player
    - Supports multiple monitors (one per examined player)
    - Auto-closes monitor when player moves out of range

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
require "ExtensiveHealth/EHR_MedicalMonitorUI"
pcall(function() require "ExtensiveHealth/EHR_HealthPanelUI" end)
pcall(function() require "TimedActions/ISMedicalCheckAction" end)
pcall(function() require "XpSystem/ISUI/ISHealthPanel" end)

EHR = EHR or {}
EHR.MPExamination = {}

local examinePlayerIcon = nil
local examinePlayerIconLoaded = false

local function getExaminePlayerIcon()
    if examinePlayerIconLoaded then
        return examinePlayerIcon
    end

    examinePlayerIconLoaded = true
    if getTexture then
        examinePlayerIcon = getTexture("media/textures/EHR_ExaminePlayer.png")
    end

    return examinePlayerIcon
end

local function EHR_GetMedicalCheckIntentPlayerKey(player)
    if not player then return nil end

    local username = nil
    if player.getUsername then
        pcall(function() username = player:getUsername() end)
    end
    if username and username ~= "" then
        return "user_" .. tostring(username)
    end

    local onlineID = nil
    if player.getOnlineID then
        pcall(function() onlineID = player:getOnlineID() end)
    end
    if onlineID ~= nil then
        return "online_" .. tostring(onlineID)
    end

    local playerNum = nil
    if player.getPlayerNum then
        pcall(function() playerNum = player:getPlayerNum() end)
    end
    if playerNum ~= nil then
        return "player_" .. tostring(playerNum)
    end

    return tostring(player)
end

local function EHR_GetMedicalCheckIntentKey(doctor, patient)
    local doctorKey = EHR_GetMedicalCheckIntentPlayerKey(doctor)
    local patientKey = EHR_GetMedicalCheckIntentPlayerKey(patient)
    if not doctorKey or not patientKey then return nil end
    return doctorKey .. "->" .. patientKey
end

local function EHR_MarkEHRMedicalCheckIntent(doctor, patient)
    local key = EHR_GetMedicalCheckIntentKey(doctor, patient)
    if not key then return end

    EHR.MPExamination.PendingEHRMedicalChecks = EHR.MPExamination.PendingEHRMedicalChecks or {}
    EHR.MPExamination.PendingEHRMedicalChecks[key] = getTimestampMs and getTimestampMs() or 0
end

local function EHR_ConsumeEHRMedicalCheckIntent(doctor, patient)
    local key = EHR_GetMedicalCheckIntentKey(doctor, patient)
    if not key then return false end

    local pending = EHR.MPExamination.PendingEHRMedicalChecks
    local startedAt = pending and pending[key] or nil
    if not startedAt then return false end

    pending[key] = nil
    if getTimestampMs and tonumber(startedAt) then
        return (getTimestampMs() - startedAt) <= 30000
    end
    return true
end

-- Vanilla B42 can re-wrap an already open remote health panel when "Check Health"
-- is performed again. EHR only takes over checks started from its own context
-- menu entry; regular vanilla Medical Check stays vanilla.
local function EHR_PrepareRemoteHealthWindow(window, patient)
    if not window or window.ehrRemoteHealthPrepared then return end
    window.ehrRemoteHealthPrepared = true
    window.ehrRemotePatient = patient

    local originalRemoveFromUIManager = window.removeFromUIManager
    window.removeFromUIManager = function(win, ...)
        if ISMedicalCheckAction and ISMedicalCheckAction.HealthWindows and win.ehrRemotePatient then
            if ISMedicalCheckAction.HealthWindows[win.ehrRemotePatient] == win then
                ISMedicalCheckAction.HealthWindows[win.ehrRemotePatient] = nil
            end
        end
        if originalRemoveFromUIManager then
            return originalRemoveFromUIManager(win, ...)
        end
    end

    local originalClose = window.close
    if originalClose then
        window.close = function(win, ...)
            if ISMedicalCheckAction and ISMedicalCheckAction.HealthWindows and win.ehrRemotePatient then
                if ISMedicalCheckAction.HealthWindows[win.ehrRemotePatient] == win then
                    ISMedicalCheckAction.HealthWindows[win.ehrRemotePatient] = nil
                end
            end
            return originalClose(win, ...)
        end
    end
end

local function EHR_ClearVanillaRemoteHealthWindow(patient)
    if not patient or not ISMedicalCheckAction or not ISMedicalCheckAction.HealthWindows then return end
    local window = ISMedicalCheckAction.HealthWindows[patient]
    if not window then return end

    pcall(function()
        if window.setVisible then
            window:setVisible(false)
        end
    end)
    pcall(function()
        if window.removeFromUIManager then
            window:removeFromUIManager()
        end
    end)
    ISMedicalCheckAction.HealthWindows[patient] = nil
end

local function EHR_PatchVanillaMedicalCheck()
    if not ISMedicalCheckAction or ISMedicalCheckAction.ehrRemoteHealthReusePatch then return end
    if not ISBaseTimedAction or not ISHealthPanel then return end

    local originalPerform = ISMedicalCheckAction.perform
    if not originalPerform then return end

    ISMedicalCheckAction.ehrRemoteHealthReusePatch = true
    ISMedicalCheckAction.perform = function(actionSelf)
        local doctor = actionSelf and actionSelf.character
        local patient = actionSelf and actionSelf.otherPlayer
        if doctor and patient and EHR_ConsumeEHRMedicalCheckIntent(doctor, patient) and EHR and EHR.UI and EHR.UI.ShowRemoteHealthPanel then
            EHR_ClearVanillaRemoteHealthWindow(patient)

            local panel = EHR.UI.ShowRemoteHealthPanel(doctor, patient)
            if panel then
                if EHR.MPExamination and EHR.MPExamination.RequestExamData and isClient and isClient() then
                    EHR.MPExamination.RequestExamData(doctor, patient)
                end

                local playerNum = doctor:getPlayerNum()
                if JoypadState and JoypadState.players and JoypadState.players[playerNum + 1] then
                    if setJoypadFocus then
                        setJoypadFocus(playerNum, panel)
                    elseif updateJoypadFocus then
                        JoypadState.players[playerNum + 1].focus = panel
                        updateJoypadFocus(JoypadState.players[playerNum + 1])
                    end
                end

                ISBaseTimedAction.perform(actionSelf)
                return
            end
        end

        if doctor and patient and ISMedicalCheckAction.HealthWindows then
            local window = ISMedicalCheckAction.HealthWindows[patient]
            local panel = window and window.nested or nil
            if window and panel and panel.character == patient then
                panel.doctorLevel = doctor:getPerkLevel(Perks.Doctor)
                if panel.setOtherPlayer then
                    panel:setOtherPlayer(doctor)
                end
                if panel.updateBodyPartList then
                    pcall(function() panel:updateBodyPartList() end)
                end

                window.visibleTarget = actionSelf
                EHR_PrepareRemoteHealthWindow(window, patient)

                local wasVisible = false
                pcall(function()
                    wasVisible = window.isVisible and window:isVisible()
                end)
                if window.setVisible then
                    pcall(function() window:setVisible(true) end)
                end
                if not wasVisible and window.addToUIManager then
                    pcall(function() window:addToUIManager() end)
                end
                if window.bringToTop then
                    pcall(function() window:bringToTop() end)
                end

                local playerNum = doctor:getPlayerNum()
                if JoypadState and JoypadState.players and JoypadState.players[playerNum + 1] then
                    if setJoypadFocus then
                        setJoypadFocus(playerNum, panel)
                    elseif updateJoypadFocus then
                        JoypadState.players[playerNum + 1].focus = panel
                        updateJoypadFocus(JoypadState.players[playerNum + 1])
                    end
                end

                if doctor.startReceivingBodyDamageUpdates then
                    pcall(function() doctor:startReceivingBodyDamageUpdates(patient) end)
                end

                ISBaseTimedAction.perform(actionSelf)
                return
            elseif window then
                pcall(function()
                    if window.removeFromUIManager then
                        window:removeFromUIManager()
                    end
                end)
                ISMedicalCheckAction.HealthWindows[patient] = nil
            end
        end

        local result = originalPerform(actionSelf)
        if patient and ISMedicalCheckAction and ISMedicalCheckAction.HealthWindows then
            EHR_PrepareRemoteHealthWindow(ISMedicalCheckAction.HealthWindows[patient], patient)
        end
        return result
    end
end

EHR_PatchVanillaMedicalCheck()

-- ============================================
-- CONFIGURATION
-- ============================================

-- Maximum distance (in tiles) to examine another player
EHR.MPExamination.EXAMINE_RANGE = 5

-- Distance at which the monitor auto-closes (tiles)
EHR.MPExamination.AUTO_CLOSE_RANGE = 10

-- ============================================
-- STATE
-- ============================================

-- Table of monitors keyed by target player ID
EHR.MPExamination.ActiveMonitors = {}

-- Cached exam data from server (keyed by username)
EHR.MPExamination.ExamDataCache = {}

-- Pending exam requests (username -> {localPlayer, targetPlayer, timestamp})
EHR.MPExamination.PendingRequests = {}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

--[[
    Get distance between two players in tiles
    @param player1 - First player
    @param player2 - Second player
    @return number - Distance in tiles, or -1 if unable to calculate
]]--
function EHR.MPExamination.GetDistance(player1, player2)
    if not player1 or not player2 then return -1 end

    local sq1 = player1:getSquare()
    local sq2 = player2:getSquare()

    if not sq1 or not sq2 then return -1 end

    local x1, y1 = sq1:getX(), sq1:getY()
    local x2, y2 = sq2:getX(), sq2:getY()

    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

--[[
    Check if target player is within examination range
    @param localPlayer - The examining player
    @param targetPlayer - The player to examine
    @return boolean
]]--
function EHR.MPExamination.IsInRange(localPlayer, targetPlayer)
    local distance = EHR.MPExamination.GetDistance(localPlayer, targetPlayer)
    return distance >= 0 and distance <= EHR.MPExamination.EXAMINE_RANGE
end

function EHR.MPExamination.CanRequestMedicalCheck(localPlayer, targetPlayer)
    if not localPlayer or not targetPlayer then return false end
    if localPlayer == targetPlayer then return true end

    if ISHealthPanel and ISHealthPanel.canPerformMedicalCheck then
        local ok, canCheck = pcall(function()
            return ISHealthPanel.canPerformMedicalCheck(targetPlayer, localPlayer)
        end)
        if ok then return canCheck == true end
    end

    return EHR.MPExamination.IsInRange(localPlayer, targetPlayer)
end

function EHR.MPExamination.RequestMedicalCheck(localPlayer, targetPlayer)
    if not localPlayer or not targetPlayer then return false end
    if localPlayer == targetPlayer then
        EHR.MPExamination.ExaminePlayer(localPlayer, targetPlayer)
        return true
    end

    if not EHR.MPExamination.CanRequestMedicalCheck(localPlayer, targetPlayer) then
        return false
    end

    if requestMedicalCheck then
        EHR_MarkEHRMedicalCheckIntent(localPlayer, targetPlayer)
        requestMedicalCheck(targetPlayer, localPlayer)
        return true
    end

    -- Fallback for unusual local/debug contexts without the vanilla request hook.
    EHR.MPExamination.ExaminePlayer(localPlayer, targetPlayer)
    return true
end

--[[
    Get a unique identifier for a player
    @param player - The player
    @return string - Player identifier
]]--
function EHR.MPExamination.GetPlayerID(player)
    if not player then return nil end

    -- Try to get username first (most reliable in MP)
    local username = nil
    pcall(function() username = player:getUsername() end)
    if username and username ~= "" then
        return "user_" .. username
    end

    -- Fall back to player number
    local playerNum = player:getPlayerNum()
    return "player_" .. tostring(playerNum)
end

local function getPlayerUsername(player)
    local username = nil
    if player and player.getUsername then
        pcall(function() username = player:getUsername() end)
    end
    if username and username ~= "" then return tostring(username) end
    return nil
end

local function getPlayerOnlineID(player)
    local onlineID = nil
    if player and player.getOnlineID then
        pcall(function() onlineID = player:getOnlineID() end)
    end
    if onlineID ~= nil then return tostring(onlineID) end
    return nil
end

local function getPlayerDisplayName(player)
    local displayName = nil
    if player and player.getDisplayName then
        pcall(function() displayName = player:getDisplayName() end)
    end
    if (not displayName or displayName == "") and player and player.getDisguisedDisplayName then
        pcall(function() displayName = player:getDisguisedDisplayName() end)
    end
    if displayName and displayName ~= "" then return tostring(displayName) end
    return nil
end

local function getExamRequestKey(player)
    local username = getPlayerUsername(player)
    if username then return username end

    local onlineID = getPlayerOnlineID(player)
    if onlineID then return "online_" .. onlineID end

    return EHR.MPExamination.GetPlayerID(player)
end

local function addCandidate(candidates, seen, player)
    if not player then return end
    local key = EHR.MPExamination.GetPlayerID(player)
    if not key or seen[key] then return end
    seen[key] = true
    table.insert(candidates, player)
end

local function collectPlayersFromSquare(candidates, seen, square)
    if not square or not square.getMovingObjects then return end
    local moving = nil
    pcall(function() moving = square:getMovingObjects() end)
    if not moving then return end

    for i = 0, moving:size() - 1 do
        local obj = moving:get(i)
        if obj and instanceof(obj, "IsoPlayer") then
            addCandidate(candidates, seen, obj)
        end
    end
end

function EHR.MPExamination.GetContextPlayerCandidates(localPlayer, worldObjects)
    local candidates = {}
    local seen = {}

    if worldObjects then
        for _, obj in ipairs(worldObjects) do
            if obj then
                if instanceof(obj, "IsoPlayer") then
                    addCandidate(candidates, seen, obj)
                end

                if obj.getSquare then
                    local square = nil
                    pcall(function() square = obj:getSquare() end)
                    collectPlayersFromSquare(candidates, seen, square)
                end
            end
        end
    end

    -- B42 sometimes does not include the remote IsoPlayer in worldObjects on
    -- clients. Add nearby online players as a fallback so MP examination is
    -- symmetrical for host/client and client/client interactions.
    local onlinePlayers = nil
    if getOnlinePlayers then
        pcall(function() onlinePlayers = getOnlinePlayers() end)
    end
    if onlinePlayers then
        for i = 0, onlinePlayers:size() - 1 do
            local p = onlinePlayers:get(i)
            if p and p ~= localPlayer and EHR.MPExamination.IsInRange(localPlayer, p) then
                addCandidate(candidates, seen, p)
            end
        end
    end

    return candidates
end

-- ============================================
-- MONITOR MANAGEMENT
-- ============================================

--[[
    Open or show the Medical Monitor for a target player
    @param localPlayer - The player doing the examining
    @param targetPlayer - The player being examined
]]--
function EHR.MPExamination.ExaminePlayer(localPlayer, targetPlayer)
    if not localPlayer or not targetPlayer then return end

    -- Don't examine yourself - use the regular monitor
    if targetPlayer == localPlayer then
        if EHR.UI and EHR.UI.ToggleHealthPanel then
            EHR.UI.ToggleHealthPanel(localPlayer)
        elseif EHR.UI and EHR.UI.ToggleMonitor then
            EHR.UI.ToggleMonitor(localPlayer)
        end
        return
    end

    -- Check range
    if not EHR.MPExamination.IsInRange(localPlayer, targetPlayer) then
        EHR.Log("MPExamination: Target player out of range")
        return
    end

    local targetID = EHR.MPExamination.GetPlayerID(targetPlayer)
    if not targetID then return end

    -- Get target player name
    local targetName = getExamRequestKey(targetPlayer) or "Unknown"

    local cachedData = nil
    local cached = EHR.MPExamination.ExamDataCache[targetName]
    if cached then
        cachedData = cached.data
    end

    -- Show the EHR panel immediately, then refresh server-side EHR data.
    EHR.MPExamination.OpenMonitorForPlayer(localPlayer, targetPlayer, cachedData)

    if isClient() then
        EHR.MPExamination.RequestExamData(localPlayer, targetPlayer)
    else
        EHR.Log("MPExamination: Opened local examination for " .. targetID)
    end
end

--[[
    Request examination data from the server
    @param localPlayer - The player requesting the examination
    @param targetPlayer - The player to examine
]]--
function EHR.MPExamination.RequestExamData(localPlayer, targetPlayer, silent, force)
    if not localPlayer or not targetPlayer then return end

    local targetName = getPlayerUsername(targetPlayer)
    local targetOnlineID = getPlayerOnlineID(targetPlayer)
    local targetDisplayName = getPlayerDisplayName(targetPlayer)
    local requestKey = getExamRequestKey(targetPlayer)

    if not requestKey then
        EHR.Log("MPExamination: Cannot request exam data - target has no stable identifier")
        return
    end

    -- Check if we already have a pending request
    if not force and EHR.MPExamination.PendingRequests[requestKey] then
        local pending = EHR.MPExamination.PendingRequests[requestKey]
        local elapsed = getTimestampMs() - pending.timestamp
        if elapsed < 5000 then  -- Wait at least 5 seconds before re-requesting
            EHR.Log("MPExamination: Request already pending for " .. requestKey)
            return
        end
    end

    -- Store pending request
    EHR.MPExamination.PendingRequests[requestKey] = {
        localPlayer = localPlayer,
        targetPlayer = targetPlayer,
        timestamp = getTimestampMs(),
        silent = silent == true,
    }

    -- Send request to server
    sendClientCommand(localPlayer, "EHR", "RequestExamData", {
        targetUsername = targetName,
        targetOnlineID = targetOnlineID,
        targetDisplayName = targetDisplayName,
        targetKey = requestKey,
    })

    EHR.Log("MPExamination: Requested exam data for " .. requestKey)

    -- Show loading feedback to player
    if not silent then
        EHR.Locale.Say(localPlayer, getText("UI_EHR_Exam_Requesting") or "Examining...")
    end
end

--[[
    Callback when exam data is received from server
    @param targetUsername - Username of examined player
    @param data - EHR data from server
]]--
function EHR.MPExamination.OnExamDataReceived(targetUsername, data)
    EHR.Log("MPExamination: Received exam data for " .. targetUsername)

    -- Store in cache
    EHR.MPExamination.ExamDataCache[targetUsername] = {
        data = data,
        timestamp = getTimestampMs(),
    }
    if data and data.targetActualUsername and data.targetActualUsername ~= targetUsername then
        EHR.MPExamination.ExamDataCache[data.targetActualUsername] = {
            data = data,
            timestamp = getTimestampMs(),
        }
    end

    -- Get pending request
    local pending = EHR.MPExamination.PendingRequests[targetUsername]
    if not pending and data and data.targetActualUsername then
        pending = EHR.MPExamination.PendingRequests[data.targetActualUsername]
    end

    if EHR.UI and EHR.UI.UpdateRemoteHealthPanelData then
        local updated = EHR.UI.UpdateRemoteHealthPanelData(targetUsername, data)
        if not updated and pending and pending.targetPlayer then
            local panel = EHR.UI.GetRemoteHealthPanelForPatient and EHR.UI.GetRemoteHealthPanelForPatient(pending.targetPlayer) or nil
            if panel then
                panel.remoteExamData = data
                panel.cachedData = {}
            end
        end
    end

    if not pending then
        EHR.Log("MPExamination: No pending request for " .. targetUsername)
        return
    end

    -- Clear pending request
    EHR.MPExamination.PendingRequests[targetUsername] = nil
    if data and data.targetActualUsername then
        EHR.MPExamination.PendingRequests[data.targetActualUsername] = nil
    end

    if pending.silent then
        return
    end

    -- Open the monitor
    EHR.MPExamination.OpenMonitorForPlayer(pending.localPlayer, pending.targetPlayer, data)
end

--[[
    Callback when exam data request fails
    @param targetUsername - Username of examined player
    @param error - Error message
]]--
function EHR.MPExamination.OnExamDataFailed(targetUsername, error)
    EHR.Log("MPExamination: Exam data request failed for " .. targetUsername .. ": " .. tostring(error))

    -- Get pending request
    local pending = EHR.MPExamination.PendingRequests[targetUsername]
    if pending and pending.localPlayer then
        EHR.Locale.Say(pending.localPlayer, getText("UI_EHR_Exam_Failed") or "Cannot examine that player")
    end

    -- Clear pending request
    EHR.MPExamination.PendingRequests[targetUsername] = nil
end

--[[
    Open the Medical Monitor for a target player (internal)
    @param localPlayer - The player doing the examining
    @param targetPlayer - The player being examined
    @param examData - Optional EHR data from server (for dedicated server)
]]--
function EHR.MPExamination.OpenMonitorForPlayer(localPlayer, targetPlayer, examData)
    if not localPlayer or not targetPlayer then return end

    local targetID = EHR.MPExamination.GetPlayerID(targetPlayer)
    if not targetID then return end

    if EHR.UI and EHR.UI.ShowRemoteHealthPanel then
        local monitor = EHR.UI.ShowRemoteHealthPanel(localPlayer, targetPlayer, examData)
        if monitor then
            EHR.MPExamination.ActiveMonitors[targetID] = {
                monitor = monitor,
                targetPlayer = targetPlayer,
                localPlayer = localPlayer,
            }

            local targetName = "Unknown"
            pcall(function() targetName = targetPlayer:getUsername() or ("Player " .. targetPlayer:getPlayerNum()) end)
            EHR.Log("MPExamination: Opened EHR health panel for " .. targetName .. " (" .. targetID .. ")")
            return
        end
    end

    -- Check if monitor already exists
    local existingMonitor = EHR.MPExamination.ActiveMonitors[targetID]
    if existingMonitor and existingMonitor.monitor then
        -- Update existing monitor with new data
        if examData then
            existingMonitor.monitor.remoteExamData = examData
        end
        existingMonitor.monitor:setVisible(true)
        existingMonitor.monitor:bringToTop()
        return
    end

    -- Create new monitor for target player
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    -- Position new monitors with offset to avoid stacking
    local monitorCount = 0
    for _ in pairs(EHR.MPExamination.ActiveMonitors) do
        monitorCount = monitorCount + 1
    end

    local xOffset = (monitorCount % 3) * 30
    local yOffset = (monitorCount % 3) * 40

    local monitor = EHR_MedicalMonitorUI:new(
        screenW - 370 - xOffset,
        100 + yOffset,
        targetPlayer
    )

    if monitor then
        monitor:initialise()
        monitor:instantiate()
        monitor:addToUIManager()
        monitor:setVisible(true)

        -- Mark as remote examination
        monitor.isRemoteExamination = true
        monitor.examiningPlayer = localPlayer

        -- Store server data if provided (for dedicated server)
        if examData then
            monitor.remoteExamData = examData
        end

        -- Get target player name for display
        local targetName = "Unknown"
        pcall(function() targetName = targetPlayer:getUsername() or ("Player " .. targetPlayer:getPlayerNum()) end)
        monitor.targetPlayerName = targetName

        -- Store reference
        EHR.MPExamination.ActiveMonitors[targetID] = {
            monitor = monitor,
            targetPlayer = targetPlayer,
            localPlayer = localPlayer,
        }

        EHR.Log("MPExamination: Created monitor for " .. targetName .. " (" .. targetID .. ")")
    end
end

--[[
    Close the monitor for a target player
    @param targetPlayer - The player whose monitor to close
]]--
function EHR.MPExamination.CloseMonitor(targetPlayer)
    if not targetPlayer then return end

    local targetID = EHR.MPExamination.GetPlayerID(targetPlayer)
    if not targetID then return end

    local entry = EHR.MPExamination.ActiveMonitors[targetID]
    if entry and entry.monitor then
        if entry.monitor.isRemoteHealthPanel and EHR.UI and EHR.UI.DestroyRemoteHealthPanel then
            EHR.UI.DestroyRemoteHealthPanel(targetPlayer)
        else
            entry.monitor:setVisible(false)
            entry.monitor:removeFromUIManager()
        end
        EHR.MPExamination.ActiveMonitors[targetID] = nil
        EHR.Log("MPExamination: Closed monitor for " .. targetID)
    end
end

--[[
    Close all remote examination monitors
]]--
function EHR.MPExamination.CloseAllMonitors()
    for targetID, entry in pairs(EHR.MPExamination.ActiveMonitors) do
        if entry.monitor then
            if entry.monitor.isRemoteHealthPanel and EHR.UI and EHR.UI.DestroyRemoteHealthPanel then
                EHR.UI.DestroyRemoteHealthPanel(entry.targetPlayer or targetID)
            else
                entry.monitor:setVisible(false)
                entry.monitor:removeFromUIManager()
            end
        end
    end
    EHR.MPExamination.ActiveMonitors = {}
    EHR.Log("MPExamination: Closed all monitors")
end

-- ============================================
-- DISTANCE CHECK UPDATE
-- ============================================

--[[
    Check all active monitors and close those where target is out of range
    Called periodically via OnTick
]]--
function EHR.MPExamination.UpdateDistanceCheck()
    local localPlayer = getPlayer()
    if not localPlayer then return end

    local toClose = {}

    for targetID, entry in pairs(EHR.MPExamination.ActiveMonitors) do
        if entry.targetPlayer and entry.monitor then
            local distance = EHR.MPExamination.GetDistance(localPlayer, entry.targetPlayer)

            -- Check if target has moved out of auto-close range
            if distance < 0 or distance > EHR.MPExamination.AUTO_CLOSE_RANGE then
                table.insert(toClose, targetID)
            end
        else
            -- Invalid entry - mark for cleanup
            table.insert(toClose, targetID)
        end
    end

    -- Close monitors for out-of-range players
    for _, targetID in ipairs(toClose) do
        local entry = EHR.MPExamination.ActiveMonitors[targetID]
        if entry then
            if entry.monitor then
                if entry.monitor.isRemoteHealthPanel and EHR.UI and EHR.UI.DestroyRemoteHealthPanel then
                    EHR.UI.DestroyRemoteHealthPanel(entry.targetPlayer or targetID)
                else
                    entry.monitor:setVisible(false)
                    entry.monitor:removeFromUIManager()
                end
            end
            EHR.MPExamination.ActiveMonitors[targetID] = nil
            EHR.Log("MPExamination: Auto-closed monitor (out of range): " .. targetID)
        end
    end
end

-- ============================================
-- CONTEXT MENU INTEGRATION
-- ============================================

--[[
    Add "Examine Health" option to player context menu
    Called when right-clicking on another player
]]--
function EHR.MPExamination.OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    -- Only show in MP (getNumActivePlayers is split-screen count in B42)
    if not isClient() then return end

    local localPlayer = getSpecificPlayer(playerNum)
    if not localPlayer then return end

    local candidates = EHR.MPExamination.GetContextPlayerCandidates(localPlayer, worldObjects)
    if test and #candidates > 0 then
        ISWorldObjectContextMenu.setTest()
        return
    end

    -- Look for players in the clicked objects, clicked square, or nearby MP fallback.
    for _, targetPlayer in ipairs(candidates) do
        local isSelf = (targetPlayer == localPlayer)

        -- Allow self to open monitor
        if isSelf then
            local optionText = getText("UI_EHR_Context_OpenMonitor") or "Open Medical Monitor"
            local option = context:addOption(optionText, localPlayer, function(player)
                if EHR.UI and EHR.UI.ToggleHealthPanel then
                    EHR.UI.ToggleHealthPanel(player)
                elseif EHR.UI and EHR.UI.ToggleMonitor then
                    EHR.UI.ToggleMonitor(player)
                end
            end)
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip:setName(optionText)
            tooltip.description = getText("UI_EHR_ExamineButton_tt") or "Examine your current health condition"
            option.toolTip = tooltip
        else
            local targetName = getPlayerDisplayName(targetPlayer) or getPlayerUsername(targetPlayer) or getExamRequestKey(targetPlayer) or "Unknown"
            local canRequest = EHR.MPExamination.CanRequestMedicalCheck(localPlayer, targetPlayer)

            -- Add context menu option
            local optionText = getText("UI_EHR_Context_ExamineHealth") or "Examine Health"
            optionText = optionText .. " (" .. targetName .. ")"

            local option = context:addOption(optionText, localPlayer, EHR.MPExamination.OnExamineClick, targetPlayer)
            local icon = getExaminePlayerIcon()
            if icon then
                option.iconTexture = icon
            end

            -- Gray out if the vanilla consent flow cannot be started from here.
            if not canRequest then
                option.notAvailable = true
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(getText("UI_EHR_Context_TooFar") or "Too Far Away")
                tooltip.description = string.format(
                    getText("UI_EHR_Context_TooFarDesc") or "You need to be within %d tiles to examine this player.",
                    EHR.MPExamination.EXAMINE_RANGE
                )
                option.toolTip = tooltip
            else
                -- Add tooltip with health hint
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(getText("UI_EHR_Context_ExamineHealth") or "Examine Health")
                tooltip.description = getText("UI_EHR_Context_ExamineHealthDesc") or "View this player's health status, diseases, and medications."
                option.toolTip = tooltip
            end
        end
    end
end

--[[
    Context menu callback - examine the clicked player
]]--
function EHR.MPExamination.OnExamineClick(localPlayer, targetPlayer)
    EHR.MPExamination.RequestMedicalCheck(localPlayer, targetPlayer)
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

-- Tick counter for periodic distance check
local tickCounter = 0
local CHECK_INTERVAL = 60  -- Check every ~1 second (60 ticks)

local function OnTick()
    tickCounter = tickCounter + 1
    if tickCounter >= CHECK_INTERVAL then
        tickCounter = 0
        EHR.MPExamination.UpdateDistanceCheck()
    end
end

local function OnPlayerDeath(player)
    -- Close any monitors examining this player
    EHR.MPExamination.CloseMonitor(player)
end

-- Register events
if Events then
    Events.OnFillWorldObjectContextMenu.Add(EHR.MPExamination.OnFillWorldObjectContextMenu)
    Events.OnTick.Add(OnTick)
    Events.OnPlayerDeath.Add(OnPlayerDeath)
    EHR.Log("MPExamination module loaded")
end
