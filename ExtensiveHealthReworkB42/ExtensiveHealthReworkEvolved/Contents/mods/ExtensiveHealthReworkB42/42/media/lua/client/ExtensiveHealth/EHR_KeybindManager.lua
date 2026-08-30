--[[
    Extensive Health Rework B42
    Keybind Manager Module

    Handles registration and management of EHR custom keybinds.
    Uses PZAPI.ModOptions for Options menu integration (B42+).

    Keybinds appear in: Options → Mods → Extensive Health Rework

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_HealthPanelUI"

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
    PRIMARY_HEALTH_PANEL = "PrimaryHealthPanel",
    OPEN_HEALTH_PANEL_COMPACT = "OpenHealthPanelCompact",
    SHOW_EHR_MOODLES = "ShowEHRMoodles",
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
EHR.Keybinds.ignoreNextPressedKey = nil

local function optionText(key, fallback)
    local text = nil
    if getText then
        text = getText(key)
    end
    if not text or text == key or text == "?" then
        return fallback
    end
    return text
end

local function ensureKeyBind(id, labelKey, fallbackLabel, defaultKey, tooltipKey, fallbackTooltip)
    if not EHR.Keybinds.modOptions then return end
    if EHR.Keybinds.modOptions:getOption(id) then return end

    EHR.Keybinds.modOptions:addKeyBind(
        id,
        optionText(labelKey, fallbackLabel),
        defaultKey,
        optionText(tooltipKey, fallbackTooltip)
    )
end

local function ensureTickBox(id, labelKey, fallbackLabel, defaultValue, tooltipKey, fallbackTooltip)
    if not EHR.Keybinds.modOptions then return end
    if EHR.Keybinds.modOptions:getOption(id) then return end

    EHR.Keybinds.modOptions:addTickBox(
        id,
        optionText(labelKey, fallbackLabel),
        defaultValue == true,
        optionText(tooltipKey, fallbackTooltip)
    )
end

-- ============================================
-- INITIALIZATION
-- ============================================

--[[
    Initialize EHR keybinds in PZAPI system.
    Called during mod initialization after game loads.
]]--
function EHR.Keybinds.Initialize(forceRefresh)
    if EHR.Keybinds.initialized and not forceRefresh then return end

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
        EHR.Log("Keybinds: Registered via PZAPI.ModOptions")
    else
        EHR.Log("Keybinds: Using existing PZAPI.ModOptions")
    end

    EHR.Keybinds.useFallback = false

    -- Add any missing options even when the player already has an older saved group.
    ensureKeyBind(
        EHR.Keybinds.IDs.TOGGLE_MONITOR,
        "UI_EHR_ToggleMedicalMonitor",
        "Toggle Medical Monitor",
        DEFAULT_KEYS[EHR.Keybinds.IDs.TOGGLE_MONITOR],
        "UI_EHR_ToggleMedicalMonitor_tt",
        "Opens/closes the selected primary health panel"
    )
    ensureKeyBind(
        EHR.Keybinds.IDs.TOGGLE_DEBUG,
        "UI_EHR_ToggleDebugMenu",
        "Toggle Debug Menu",
        DEFAULT_KEYS[EHR.Keybinds.IDs.TOGGLE_DEBUG],
        "UI_EHR_ToggleDebugMenu_tt",
        "Opens/closes the EHR Debug Menu (requires debug mode)"
    )
    ensureKeyBind(
        EHR.Keybinds.IDs.TOGGLE_JOURNAL,
        "UI_EHR_ToggleMedicalJournal",
        "Toggle Medical Journal",
        DEFAULT_KEYS[EHR.Keybinds.IDs.TOGGLE_JOURNAL],
        "UI_EHR_ToggleMedicalJournal_tt",
        "Opens/closes the Medical Journal (diagnosis history)"
    )
    ensureTickBox(
        EHR.Keybinds.IDs.PRIMARY_HEALTH_PANEL,
        "UI_EHR_PrimaryHealthPanel",
        "Use EHR as primary health panel",
        true,
        "UI_EHR_PrimaryHealthPanel_tt",
        "When enabled, the EHR hotkey opens the EHR panel and the heart button opens vanilla health. Disable to swap them."
    )
    ensureTickBox(
        EHR.Keybinds.IDs.OPEN_HEALTH_PANEL_COMPACT,
        "UI_EHR_OpenHealthPanelCompact",
        "Open EHR panels compact",
        true,
        "UI_EHR_OpenHealthPanelCompact_tt",
        "When enabled, EHR health panels open in compact mode. Disable to open them expanded."
    )
    ensureTickBox(
        EHR.Keybinds.IDs.SHOW_EHR_MOODLES,
        "UI_EHR_ShowMoodles",
        "Show EHR moodles",
        true,
        "UI_EHR_ShowMoodles_tt",
        "Show EHR condition and exposure moodles. Disable if another mod's moodles overlap; the EHR monitor and all mechanics remain active."
    )

    EHR.Keybinds.initialized = true
    EHR.Log("Keybinds: Initialization complete")
end

function EHR.Keybinds.EnsureModOptionsAvailable()
    if EHR.Keybinds.useFallback and PZAPI and PZAPI.ModOptions then
        EHR.Keybinds.Initialize(true)
    elseif not EHR.Keybinds.modOptions and PZAPI and PZAPI.ModOptions then
        EHR.Keybinds.modOptions = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    end
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
    EHR.Keybinds.EnsureModOptionsAvailable()

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

function EHR.Keybinds.GetOptionBoolean(optionId, defaultValue)
    EHR.Keybinds.EnsureModOptionsAvailable()

    if EHR.Keybinds.useFallback then
        return defaultValue == true
    end

    if EHR.Keybinds.modOptions then
        local option = EHR.Keybinds.modOptions:getOption(optionId)
        if option then
            local value = nil
            if option.getValue then
                local ok, result = pcall(function() return option:getValue() end)
                if ok then value = result end
            elseif option.value ~= nil then
                value = option.value
            end
            if value ~= nil then
                return value == true
            end
        end
    end

    return defaultValue == true
end

function EHR.Keybinds.IsEHRPrimaryHealthPanel()
    return EHR.Keybinds.GetOptionBoolean(EHR.Keybinds.IDs.PRIMARY_HEALTH_PANEL, true)
end

function EHR.Keybinds.ShouldOpenHealthPanelCompact()
    return EHR.Keybinds.GetOptionBoolean(EHR.Keybinds.IDs.OPEN_HEALTH_PANEL_COMPACT, true)
end

function EHR.Keybinds.ShouldShowMoodles()
    return EHR.Keybinds.GetOptionBoolean(EHR.Keybinds.IDs.SHOW_EHR_MOODLES, true)
end

function EHR.Keybinds.ShouldHotkeyOpenEHR()
    return EHR.Keybinds.IsEHRPrimaryHealthPanel()
end

function EHR.Keybinds.ShouldHeartButtonOpenEHR()
    return not EHR.Keybinds.IsEHRPrimaryHealthPanel()
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
    if EHR.Keybinds.ignoreNextPressedKey == key then
        EHR.Keybinds.ignoreNextPressedKey = nil
        return
    end

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

    -- Toggle Medical Monitor / Health Panel
    if EHR.Keybinds.IsToggleMonitorKey(key) then
        if EHR.Keybinds.ShouldHotkeyOpenEHR() and EHR.UI and EHR.UI.ToggleHealthPanel then
            EHR.UI.ToggleHealthPanel(player)
        elseif EHR.UI and EHR.UI.ToggleVanillaHealthPanel then
            local vanillaHealthKey = 0
            if core and core.getKey then
                vanillaHealthKey = tonumber(core:getKey("Toggle Health Panel")) or 0
            end
            if vanillaHealthKey > 0 and vanillaHealthKey == key then
                return
            end
            EHR.UI.ToggleVanillaHealthPanel(player)
        elseif EHR.UI and EHR.UI.ToggleMonitor then
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
        if EHR.UI and EHR.UI.SuppressLegacyHealthUI then
            EHR.UI.SuppressLegacyHealthUI(12)
        end
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
