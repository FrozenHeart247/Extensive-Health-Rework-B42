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
    local values = { ... }
    local text = nil

    -- Formatted translations must receive their arguments in the getText()
    -- call itself. Since 42.20.1 the Translator validates placeholders such
    -- as %1 immediately; fetching the value first through Locale.Text() made
    -- it report a MissingFormatArgumentException before the Lua replacement
    -- below had a chance to run.
    if key and key ~= "" and getText then
        local ok, result = pcall(getText, key, ...)
        if ok then
            text = result
        end
    end

    if missing(text, key) then
        text = fallback or key or ""
    end

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

    -- Antibody-test results contain runtime values, so hashing the completed
    -- English sentence would create a different, untranslatable key for every
    -- blood type/rating/chance combination. Localize the stable template and
    -- rating before falling back to the regular raw-line hash system.
    local bloodType, rating, chance = string.match(
        text,
        "^Test complete%.%.%. Blood type (.-)%. (.-) %- (%d+)%% survival chance%.$"
    )
    if bloodType and rating and chance then
        local ratingKeys = {
            ["High Compatibility"] = "UI_EHR_KnoxCure_Rating_High",
            ["Moderate Compatibility"] = "UI_EHR_KnoxCure_Rating_Moderate",
            ["Low Compatibility"] = "UI_EHR_KnoxCure_Rating_Low",
            ["Critical Risk"] = "UI_EHR_KnoxCure_Rating_Critical",
        }
        local ratingKey = ratingKeys[rating]
        local localizedRating = ratingKey and EHR.Locale.Text(ratingKey, rating) or rating
        return EHR.Locale.Format(
            "UI_EHR_KnoxCure_TestResult",
            "Test complete... Blood type %1. %2 - %3 survival chance.",
            bloodType,
            localizedRating,
            tostring(chance) .. "%"
        )
    end

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
    if not player then
        return false
    end
    if not text or text == "" then
        return false
    end

    local line = EHR.Locale.TextForLine(text)
    if isServer and isServer() and not (isClient and isClient()) and sendServerCommand then
        sendServerCommand(player, "EHR_Dialogue", "Say", { text = line })
        return true
    end

    if not player.Say then
        return false
    end
    player:Say(line)
    return true
end

function EHR.Locale.SideEffectName(name)
    if not name or name == "" then
        return ""
    end
    local key = "UI_SideEffect_" .. tostring(name):gsub("%s+", ""):gsub("[^A-Za-z0-9_]", "")
    return EHR.Locale.Text(key, tostring(name))
end
