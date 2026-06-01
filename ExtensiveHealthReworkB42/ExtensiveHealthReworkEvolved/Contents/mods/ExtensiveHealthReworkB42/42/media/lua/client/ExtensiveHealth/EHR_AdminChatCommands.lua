--[[
    EHR admin chat commands.

    Vanilla unknown slash commands go straight to the Java command handler, so
    EHR commands must be intercepted before ISChat forwards them.
]]--

if isServer() and not isClient() then
    return
end

pcall(function() require "Chat/ISChat" end)

EHR = EHR or {}
EHR.AdminChatCommands = EHR.AdminChatCommands or {}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function localAdminFeedback(text)
    local player = getPlayer and getPlayer() or nil
    if not player then return end
    if EHR and EHR.Locale and EHR.Locale.Say then
        EHR.Locale.Say(player, tostring(text))
    elseif player.Say then
        player:Say(tostring(text))
    end
end

local function parseFullHealCommand(command)
    local raw = trim(command)
    local lower = raw:lower()
    local prefix = "/ehrfullheal"
    if lower == prefix then
        return ""
    end
    if lower:sub(1, #prefix) == prefix and lower:sub(#prefix + 1, #prefix + 1):match("%s") then
        return trim(raw:sub(#prefix + 1))
    end
    return nil
end

local function finishChatCommand(chat, command)
    if chat and chat.unfocus then
        pcall(function() chat:unfocus() end)
    end
    if chat and chat.logChatCommand then
        pcall(function() chat:logChatCommand(command) end)
    end
    if doKeyPress then
        pcall(function() doKeyPress(false) end)
    end
    if chat then
        chat.timerTextEntry = 20
    end
end

local function hookAdminChatCommands()
    if not ISChat or type(ISChat.onCommandEntered) ~= "function" then
        return false
    end

    if EHR.AdminChatCommands.hookedOnCommandEntered == ISChat.onCommandEntered then
        if ISChat.instance and ISChat.instance.textEntry then
            ISChat.instance.textEntry.onCommandEntered = EHR.AdminChatCommands.hookedOnCommandEntered
        end
        return true
    end

    local original = EHR.AdminChatCommands.originalOnCommandEntered or ISChat.onCommandEntered
    local wrapped = function(self, ...)
        local chat = ISChat and ISChat.instance or nil
        local command = nil
        if chat and chat.textEntry and chat.textEntry.getText then
            command = chat.textEntry:getText()
        end

        local target = parseFullHealCommand(command)
        if target ~= nil then
            finishChatCommand(chat, command)
            if target == "" then
                localAdminFeedback("Usage: /ehrfullheal PlayerName")
                return
            end

            local player = getPlayer and getPlayer() or nil
            if player and sendClientCommand then
                sendClientCommand(player, "EHR_Debug", "FullHealTarget", { targetUsername = target })
            else
                localAdminFeedback("EHR: command unavailable here.")
            end
            return
        end

        return original(self, ...)
    end

    EHR.AdminChatCommands.originalOnCommandEntered = original
    EHR.AdminChatCommands.hookedOnCommandEntered = wrapped
    ISChat.onCommandEntered = wrapped
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = wrapped
    end
    return true
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(hookAdminChatCommands)
end
if Events and Events.OnChatWindowInit then
    Events.OnChatWindowInit.Add(hookAdminChatCommands)
end

hookAdminChatCommands()
