--[[
    Extensive Health Rework
    Shared localization helpers.

    Use this for EHR-owned UI and dialogue strings that need a safe English
    fallback when translators have not provided a value yet.
]]--

EHR = EHR or {}
EHR.Locale = EHR.Locale or {}

local function missing(value, key)
    return value == nil or value == "" or value == "?" or value == key
end

function EHR.Locale.Text(key, fallback)
    if not key or key == "" then
        return fallback or ""
    end

    local value = nil
    if getText then
        local ok, result = pcall(getText, key)
        if ok then
            value = result
        end
    end

    if missing(value, key) then
        return fallback or key
    end
    return value
end

function EHR.Locale.Format(key, fallback, ...)
    local text = EHR.Locale.Text(key, fallback)
    local values = { ... }

    for i, value in ipairs(values) do
        local replacement = tostring(value)
        text = string.gsub(text, "%%" .. tostring(i) .. "%$[%a]", function() return replacement end)
        text = string.gsub(text, "%%" .. tostring(i), function() return replacement end)
    end

    if string.find(text, "%%[cdeEfgGiouqsxX]") then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then
            return formatted
        end
    end

    return text
end

function EHR.Locale.RawKey(text)
    text = tostring(text or "")
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + string.byte(text, i)) % 4294967296
    end
    return string.format("UI_EHR_Line_%08X", hash)
end

function EHR.Locale.TextForLine(text)
    if not text or text == "" then
        return text
    end

    text = tostring(text)
    if string.match(text, "^[A-Za-z0-9_]+$") then
        local byKey = EHR.Locale.Text(text, nil)
        if byKey and byKey ~= text then
            return byKey
        end
    end

    local rawKey = EHR.Locale.RawKey(text)
    return EHR.Locale.Text(rawKey, text)
end

function EHR.Locale.Say(player, text)
    if not player or not player.Say then
        return false
    end
    if not text or text == "" then
        return false
    end
    player:Say(EHR.Locale.TextForLine(text))
    return true
end

function EHR.Locale.SideEffectName(name)
    if not name or name == "" then
        return ""
    end
    local key = "UI_SideEffect_" .. tostring(name):gsub("%s+", ""):gsub("[^A-Za-z0-9_]", "")
    return EHR.Locale.Text(key, tostring(name))
end
