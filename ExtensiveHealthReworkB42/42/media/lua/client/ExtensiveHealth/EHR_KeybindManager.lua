--[[
    Extensive Health Rework B42
    Keybind Manager Module

    Handles registration and management of EHR custom keybinds.
    Uses PZAPI.ModOptions for Options menu integration (B42+).

    Keybinds appear in: Options → Mods → Extensive Health Rework

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.Keybinds = {}

-- ============================================
-- CONSTANTS
-- ============================================

local MOD_OPTIONS_ID = "ExtensiveHealthRework"
local MOD_NAME = "Extensive Health Rework"

-- Keybind IDs
EHR.Keybinds.IDs = {
    TOGGLE_MONITOR = "ToggleMedicalMonitor",
    TOGGLE_DEBUG = "ToggleDebugMenu",
    TOGGLE_JOURNAL = "ToggleMedicalJournal",
}

-- Default keycodes (Keyboard.KEY_*)
local DEFAULT_KEYS = {
    [EHR.Keybinds.IDs.TOGGLE_MONITOR] = 35,  -- Keyboard.KEY_H
    [EHR.Keybinds.IDs.TOGGLE_DEBUG] = 34,    -- Keyboard.KEY_G (for debug)
    [EHR.Keybinds.IDs.TOGGLE_JOURNAL] = 36,  -- Keyboard.KEY_J
}

-- ============================================
-- STATE
-- ============================================

EHR.Keybinds.initialized = false
EHR.Keybinds.modOptions = nil

-- ============================================
-- INITIALIZATION
-- ============================================

--[[
    Initialize EHR keybinds in PZAPI system.
    Called during mod initialization after game loads.
]]--
function EHR.Keybinds.Initialize()
    if EHR.Keybinds.initialized then return end

    -- Check if PZAPI.ModOptions exists (B42+)
    if not PZAPI or not PZAPI.ModOptions then
        EHR.Log("Keybinds: PZAPI.ModOptions not available - using fallback keybinds")
        EHR.Keybinds.useFallback = true
        EHR.Keybinds.initialized = true
        return
    end

    -- Check if our options already exist
    EHR.Keybinds.modOptions = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)

    if not EHR.Keybinds.modOptions then
        -- Create mod options group
        EHR.Keybinds.modOptions = PZAPI.ModOptions:create(MOD_OPTIONS_ID, MOD_NAME)

        -- Add keybind options
        -- Toggle Medical Monitor (default: M key)
        EHR.Keybinds.modOptions:addKeyBind(
            EHR.Keybinds.IDs.TOGGLE_MONITOR,
            getText("UI_EHR_ToggleMedicalMonitor") or "Toggle Medical Monitor",
            DEFAULT_KEYS[EHR.Keybinds.IDs.TOGGLE_MONITOR],
            getText("UI_EHR_ToggleMedicalMonitor_tt") or "Opens/closes the Medical Monitor panel"
        )

        -- Toggle Debug Menu (default: G key, admin only display)
        EHR.Keybinds.modOptions:addKeyBind(
            EHR.Keybinds.IDs.TOGGLE_DEBUG,
            getText("UI_EHR_ToggleDebugMenu") or "Toggle Debug Menu",
            DEFAULT_KEYS[EHR.Keybinds.IDs.TOGGLE_DEBUG],
            getText("UI_EHR_ToggleDebugMenu_tt") or "Opens/closes the EHR Debug Menu (requires debug mode)"
        )

        -- Toggle Medical Journal (default: J key)
        EHR.Keybinds.modOptions:addKeyBind(
            EHR.Keybinds.IDs.TOGGLE_JOURNAL,
            getText("UI_EHR_ToggleMedicalJournal") or "Toggle Medical Journal",
            DEFAULT_KEYS[EHR.Keybinds.IDs.TOGGLE_JOURNAL],
            getText("UI_EHR_ToggleMedicalJournal_tt") or "Opens/closes the Medical Journal (diagnosis history)"
        )

        EHR.Log("Keybinds: Registered via PZAPI.ModOptions")
    else
        EHR.Log("Keybinds: Using existing PZAPI.ModOptions")
    end

    EHR.Keybinds.initialized = true
    EHR.Log("Keybinds: Initialization complete")
end

-- ============================================
-- KEYBIND RETRIEVAL
-- ============================================

--[[
    Get the current keybind code for a specific keybind ID.
    @param keybindId (string) - The keybind ID from EHR.Keybinds.IDs
    @return keyCode (integer) - Keyboard code, or 0 if unbound
]]--
function EHR.Keybinds.GetKey(keybindId)
    -- Fallback mode uses defaults
    if EHR.Keybinds.useFallback then
        return DEFAULT_KEYS[keybindId] or 0
    end

    -- Get from PZAPI
    if EHR.Keybinds.modOptions then
        local keybindOption = EHR.Keybinds.modOptions:getOption(keybindId)
        if keybindOption and keybindOption.key then
            return tonumber(keybindOption.key) or 0
        end
    end

    -- Return default if option not found
    return DEFAULT_KEYS[keybindId] or 0
end

--[[
    Get the Toggle Medical Monitor keybind code.
    @return keyCode (integer)
]]--
function EHR.Keybinds.GetToggleMonitorKey()
    return EHR.Keybinds.GetKey(EHR.Keybinds.IDs.TOGGLE_MONITOR)
end

--[[
    Get the Toggle Debug Menu keybind code.
    @return keyCode (integer)
]]--
function EHR.Keybinds.GetToggleDebugKey()
    return EHR.Keybinds.GetKey(EHR.Keybinds.IDs.TOGGLE_DEBUG)
end

--[[
    Get the Toggle Medical Journal keybind code.
    @return keyCode (integer)
]]--
function EHR.Keybinds.GetToggleJournalKey()
    return EHR.Keybinds.GetKey(EHR.Keybinds.IDs.TOGGLE_JOURNAL)
end

--[[
    Get human-readable name for a keybind.
    @param keybindId (string) - The keybind ID
    @return string - Key name like "M" or "Not bound"
]]--
function EHR.Keybinds.GetKeyName(keybindId)
    local keyCode = EHR.Keybinds.GetKey(keybindId)
    if keyCode and keyCode > 0 then
        -- Use vanilla getKeyName function
        if getKeyName then
            return getKeyName(keyCode)
        else
            return tostring(keyCode)
        end
    end
    return getText("UI_EHR_NotBound") or "Not bound"
end

-- ============================================
-- KEYBIND CHECKING
-- ============================================

--[[
    Check if a pressed key matches the Toggle Monitor keybind.
    @param key (integer) - Key code from event
    @return boolean - True if this is the toggle monitor key
]]--
function EHR.Keybinds.IsToggleMonitorKey(key)
    local boundKey = EHR.Keybinds.GetToggleMonitorKey()
    return boundKey and boundKey > 0 and boundKey == key
end

--[[
    Check if a pressed key matches the Toggle Debug keybind.
    @param key (integer) - Key code from event
    @return boolean - True if this is the toggle debug key
]]--
function EHR.Keybinds.IsToggleDebugKey(key)
    local boundKey = EHR.Keybinds.GetToggleDebugKey()
    return boundKey and boundKey > 0 and boundKey == key
end

--[[
    Check if a pressed key matches the Toggle Journal keybind.
    @param key (integer) - Key code from event
    @return boolean - True if this is the toggle journal key
]]--
function EHR.Keybinds.IsToggleJournalKey(key)
    local boundKey = EHR.Keybinds.GetToggleJournalKey()
    return boundKey and boundKey > 0 and boundKey == key
end

--[[
    Generic keybind check.
    @param keybindId (string) - The keybind ID to check
    @param key (integer) - Key code from event
    @return boolean
]]--
function EHR.Keybinds.IsKey(keybindId, key)
    local boundKey = EHR.Keybinds.GetKey(keybindId)
    return boundKey and boundKey > 0 and boundKey == key
end

-- ============================================
-- KEYBIND EVENT HANDLER
-- ============================================

--[[
    Global key event handler for EHR keybinds.
    Called from OnKeyPressed event.
]]--
function EHR.Keybinds.OnKeyPressed(key)
    local player = getSpecificPlayer(0)
    if not player then return end

    -- Don't process keybinds during text input
    if MainScreen and MainScreen.instance and MainScreen.instance.inGame == false then
        return
    end

    -- Check if any UI panel is capturing input (with nil safety)
    -- B42 FIX: getGameUI() may not exist, use pcall
    local core = getCore()
    if core then
        local success, ui = pcall(function()
            if core.getGameUI then
                return core:getGameUI()
            end
            return nil
        end)
        if success and ui and ui.isChatWindowOpen and ui:isChatWindowOpen() then
            return
        end
    end

    -- Toggle Medical Monitor
    if EHR.Keybinds.IsToggleMonitorKey(key) then
        if EHR.UI and EHR.UI.ToggleMonitor then
            EHR.UI.ToggleMonitor(player)
        end
        return
    end

    -- Toggle Debug Menu (requires sandbox DebugMode option)
    if EHR.Keybinds.IsToggleDebugKey(key) then
        -- Use IsDebugAllowed() which checks sandbox setting + admin for MP
        if EHR.DebugV2 and EHR.DebugV2.IsDebugAllowed and EHR.DebugV2.IsDebugAllowed() then
            if EHR.DebugV2.Toggle then
                EHR.DebugV2.Toggle()
            end
        elseif EHR.DebugMenu and EHR.DebugMenu.Toggle then
            -- Fallback to old debug menu (also respects sandbox)
            EHR.DebugMenu.Toggle()
        end
        return
    end

    -- Toggle Medical Journal
    if EHR.Keybinds.IsToggleJournalKey(key) then
        if EHR_MedicalJournalUI and EHR_MedicalJournalUI.Toggle then
            EHR_MedicalJournalUI.Toggle(player)
        end
        return
    end
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

local function OnKeyPressed(key)
    -- Route to keybind handler
    EHR.Keybinds.OnKeyPressed(key)
end

-- Register key press event
if Events then
    Events.OnKeyPressed.Add(OnKeyPressed)
end

-- Initialize ModOptions IMMEDIATELY at file load (not OnGameStart!)
-- This is required for options to appear in the Mods tab before game starts
EHR.Keybinds.Initialize()
EHR.Log("KeybindManager module loaded")
