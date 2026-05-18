--[[
    EHR Universal Substance Scanner

    Scans player ModData for active substances from other mods.
    Uses known prefixes to minimize false positives.

    Supported mod prefixes:
    - HC_ (Hydrocraft)
    - Drug_ (Generic drug mods)
    - Med_ (Medical mods)

    Display format: Friendly (cleans up key names)

    Author: ExtensiveHealthRework Team
    Version: 2.8.0
]]--

EHR = EHR or {}
EHR.SubstanceScanner = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.SubstanceScanner.Config = {
    -- Known mod prefixes to scan for
    KNOWN_PREFIXES = {
        "HC_",       -- Hydrocraft
        "Drug_",     -- Generic drug mods
        "Med_",      -- Medical mods
    },

    -- Suffixes that indicate active substances
    ACTIVE_SUFFIXES = {
        "Effect",    -- FooEffect = level of effect
        "Amount",    -- FooAmount = accumulated amount
        "Level",     -- FooLevel = intensity level
        "Active",    -- FooActive = boolean active
        "Duration",  -- FooDuration = time remaining
    },

    -- Keys to explicitly ignore (false positives)
    IGNORE_KEYS = {
    },

    -- Pre-mapped display names for known substances
    DISPLAY_NAMES = {
    },

    -- Categories for known substances
    CATEGORIES = {
    },

    -- Cache settings
    CACHE_DURATION_MS = 1000,  -- 1 second cache
}

-- ============================================
-- CACHING
-- ============================================

EHR.SubstanceScanner._cache = {}
EHR.SubstanceScanner._cacheTime = 0

-- ============================================
-- SCANNING
-- ============================================

--[[
    Check if a key matches any known prefix.
    @param key (string) - ModData key to check
    @return string|nil - Matched prefix or nil
]]--
function EHR.SubstanceScanner.MatchesKnownPrefix(key)
    if not key or type(key) ~= "string" then return nil end

    for _, prefix in ipairs(EHR.SubstanceScanner.Config.KNOWN_PREFIXES) do
        if key:sub(1, #prefix) == prefix then
            return prefix
        end
    end

    return nil
end

--[[
    Check if a key ends with an active suffix.
    @param key (string) - ModData key to check
    @return string|nil - Matched suffix or nil
]]--
function EHR.SubstanceScanner.MatchesActiveSuffix(key)
    if not key or type(key) ~= "string" then return nil end

    for _, suffix in ipairs(EHR.SubstanceScanner.Config.ACTIVE_SUFFIXES) do
        if key:sub(-#suffix) == suffix then
            return suffix
        end
    end

    return nil
end

--[[
    Check if a key should be ignored.
    @param key (string) - ModData key to check
    @return boolean
]]--
function EHR.SubstanceScanner.ShouldIgnore(key)
    if not key then return true end

    for _, ignorePattern in ipairs(EHR.SubstanceScanner.Config.IGNORE_KEYS) do
        if key:find(ignorePattern) then
            return true
        end
    end

    return false
end

--[[
    Convert a ModData key to a friendly display name.
    @param key (string) - ModData key
    @return string - Friendly display name
]]--
function EHR.SubstanceScanner.GetFriendlyName(key)
    if not key then return "Unknown" end

    -- Check pre-mapped names first
    local mapped = EHR.SubstanceScanner.Config.DISPLAY_NAMES[key]
    if mapped then
        return mapped
    end

    -- Auto-generate friendly name
    local name = key

    -- Remove known prefixes
    for _, prefix in ipairs(EHR.SubstanceScanner.Config.KNOWN_PREFIXES) do
        if name:sub(1, #prefix) == prefix then
            name = name:sub(#prefix + 1)
            break
        end
    end

    -- Remove known suffixes
    for _, suffix in ipairs(EHR.SubstanceScanner.Config.ACTIVE_SUFFIXES) do
        if name:sub(-#suffix) == suffix then
            name = name:sub(1, -#suffix - 1)
            break
        end
    end

    -- Add spaces before capital letters (CamelCase to Title Case)
    name = name:gsub("(%l)(%u)", "%1 %2")

    -- Clean up underscores
    name = name:gsub("_", " ")

    -- Trim whitespace
    name = name:match("^%s*(.-)%s*$")

    return name ~= "" and name or key
end

--[[
    Get the category for a substance.
    @param key (string) - ModData key
    @return string - Category name
]]--
function EHR.SubstanceScanner.GetCategory(key)
    if not key then return "unknown" end

    local mapped = EHR.SubstanceScanner.Config.CATEGORIES[key]
    if mapped then
        return mapped
    end

    -- Try to infer from name
    local lowerKey = key:lower()
    if lowerKey:find("coke") or lowerKey:find("meth") or lowerKey:find("stim") then
        return "stimulant"
    elseif lowerKey:find("opioid") or lowerKey:find("morphine") or lowerKey:find("heroin") then
        return "opioid"
    elseif lowerKey:find("benzo") or lowerKey:find("alcohol") then
        return "depressant"
    elseif lowerKey:find("weed") or lowerKey:find("cannabis") or lowerKey:find("thc") then
        return "cannabis"
    end

    return "unknown"
end

--[[
    Scan player ModData for active substances.
    @param player (IsoPlayer) - The player to scan
    @return table - Array of detected substances
]]--
function EHR.SubstanceScanner.Scan(player)
    if not player then return {} end

    -- Check cache
    local currentTime = getTimestampMs and getTimestampMs() or (os.clock() * 1000)
    if currentTime - EHR.SubstanceScanner._cacheTime < EHR.SubstanceScanner.Config.CACHE_DURATION_MS then
        return EHR.SubstanceScanner._cache
    end

    local modData = player:getModData()
    if not modData then return {} end

    local detected = {}

    -- Scan all ModData keys
    for key, value in pairs(modData) do
        -- Skip EHR's own keys
        if type(key) == "string" and not key:find("^EHR_") then
            -- Check if matches known prefix
            local prefix = EHR.SubstanceScanner.MatchesKnownPrefix(key)
            if prefix then
                -- Check if matches active suffix
                local suffix = EHR.SubstanceScanner.MatchesActiveSuffix(key)
                if suffix then
                    -- Check if should ignore
                    if not EHR.SubstanceScanner.ShouldIgnore(key) then
                        -- Check if value is "active" (non-zero, non-false)
                        local isActive = false
                        if type(value) == "number" and value > 0 then
                            isActive = true
                        elseif type(value) == "boolean" and value then
                            isActive = true
                        end

                        if isActive then
                            table.insert(detected, {
                                key = key,
                                value = value,
                                prefix = prefix,
                                suffix = suffix,
                                displayName = EHR.SubstanceScanner.GetFriendlyName(key),
                                category = EHR.SubstanceScanner.GetCategory(key),
                            })
                        end
                    end
                end
            end
        end
    end

    -- Sort by category then by name
    table.sort(detected, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end
        return a.displayName < b.displayName
    end)

    -- Update cache
    EHR.SubstanceScanner._cache = detected
    EHR.SubstanceScanner._cacheTime = currentTime

    return detected
end

--[[
    Get a formatted string representation of a substance value.
    @param substance (table) - Substance data from Scan()
    @return string - Formatted value string
]]--
function EHR.SubstanceScanner.FormatValue(substance)
    if not substance then return "" end

    local value = substance.value
    local suffix = substance.suffix

    if type(value) == "boolean" then
        return value and "Active" or "Inactive"
    elseif type(value) == "number" then
        if suffix == "Duration" then
            -- Format as time
            if value > 60 then
                return string.format("%.1fh", value / 60)
            else
                return string.format("%.0fm", value)
            end
        elseif suffix == "Effect" or suffix == "Level" then
            -- Format as percentage or level
            if value <= 1 then
                return string.format("%.0f%%", value * 100)
            else
                return string.format("%.0f", value)
            end
        else
            return string.format("%.0f", value)
        end
    end

    return tostring(value)
end

--[[
    Clear the scan cache (call when player changes or dies).
]]--
function EHR.SubstanceScanner.ClearCache()
    EHR.SubstanceScanner._cache = {}
    EHR.SubstanceScanner._cacheTime = 0
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log = EHR.Log or function(msg) print("[EHR] " .. tostring(msg)) end
EHR.Log("EHR_SubstanceScanner.lua loaded")
