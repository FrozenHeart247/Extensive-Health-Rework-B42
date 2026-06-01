-- Guards vanilla joypad focus logging from stale or non-UI context-menu origins.
-- B42's ISContextMenu reuses menu instances and does not always clear origin.

EHR = EHR or {}
EHR.JoypadFocusCompat = EHR.JoypadFocusCompat or {}

local Compat = EHR.JoypadFocusCompat

local function hasSafeToString(control)
    if control == nil then return true end
    local ok, fn = pcall(function()
        return control.toString
    end)
    return ok and type(fn) == "function"
end

local function makeFallbackToString(control)
    if control == nil then return nil end
    if hasSafeToString(control) then return control end

    if type(control) == "table" then
        control.toString = function(self)
            local label = rawget(self, "Type")
                or rawget(self, "type")
                or rawget(self, "name")
                or rawget(self, "title")
                or "EHR_JoypadFocus"
            return tostring(label)
        end
        return control
    end

    return nil
end

local function patchSetJoypadFocus()
    if Compat.setJoypadFocusPatched then return true end
    if type(setJoypadFocus) ~= "function" then return false end

    local original = setJoypadFocus
    Compat.originalSetJoypadFocus = Compat.originalSetJoypadFocus or original

    setJoypadFocus = function(playerID, control)
        return original(playerID, makeFallbackToString(control))
    end

    Compat.setJoypadFocusPatched = true
    return true
end

local function patchContextMenuGet()
    if Compat.contextMenuGetPatched then return true end
    if not ISContextMenu or type(ISContextMenu.get) ~= "function" then return false end

    local original = ISContextMenu.get
    Compat.originalContextMenuGet = Compat.originalContextMenuGet or original

    ISContextMenu.get = function(player, x, y)
        local context = original(player, x, y)
        if context then
            context.origin = nil
        end
        return context
    end

    Compat.contextMenuGetPatched = true
    return true
end

function Compat.Install()
    local focusOk = patchSetJoypadFocus()
    local menuOk = patchContextMenuGet()
    return focusOk or menuOk
end

local function tryInstall()
    Compat.Install()
end

tryInstall()

if Events and not Compat.eventsRegistered then
    Compat.eventsRegistered = true
    if Events.OnGameStart then Events.OnGameStart.Add(tryInstall) end
    if Events.OnLoad then Events.OnLoad.Add(tryInstall) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(tryInstall) end
end
