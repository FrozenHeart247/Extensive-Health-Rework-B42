--[[
    EHR Lifestyle & Hobbies Mod Compatibility
    READ-ONLY Integration - Does NOT modify Lifestyle data

    This module reads Lifestyle and Hobbies mod data to apply
    healing bonuses in EHR. It does NOT interfere with Lifestyle's
    normal functionality.

    Lifestyle Data Read:
    - hygieneNeed (0-100, lower = cleaner)
    - IsDoingShower (boolean)
    - LSMoodles.HygieneGood/HygieneBad
    - IsSitting (from sitting system)
    - Yoga skill level

    Healing Bonuses Applied:
    - Good hygiene (hygieneNeed < 40): +10-25% healing
    - Showering: +5% healing while showering
    - Sitting comfortably: +5-15% healing
    - Yoga skill: +1-10% healing based on level
    - Bad hygiene (hygieneNeed > 70): -10-25% healing penalty

    v2.0.0 - Complete rewrite for read-only integration
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.LifestyleCompat = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.LifestyleCompat.Config = {
    -- Hygiene thresholds (Lifestyle uses 0-100, lower = cleaner)
    -- Only two bonus tiers: Very Clean and Clean
    HYGIENE_EXCELLENT = 15,   -- Very clean
    HYGIENE_GOOD = 35,        -- Clean
    HYGIENE_DIRTY = 65,       -- Dirty (penalty)
    HYGIENE_FILTHY = 85,      -- Very dirty (penalty)

    -- Hysteresis buffer to prevent flickering
    HYSTERESIS = 5,

    -- Healing bonus multipliers
    BONUS_HYGIENE_EXCELLENT = 0.25,  -- +25% healing
    BONUS_HYGIENE_GOOD = 0.15,       -- +15% healing
    BONUS_SHOWERING = 0.05,          -- +5% while actively showering
    BONUS_SITTING_COMFORTABLE = 0.10, -- +10% for comfortable seating
    BONUS_SITTING_BASIC = 0.05,      -- +5% for basic seating
    BONUS_YOGA_PER_LEVEL = 0.01,     -- +1% per yoga level (max +10%)

    -- Healing penalty multipliers
    PENALTY_DIRTY = -0.10,           -- -10% healing
    PENALTY_FILTHY = -0.25,          -- -25% healing
}

-- Cache for current hygiene state to prevent flickering
local currentHygieneState = nil  -- "excellent", "good", "fresh", "neutral", "dirty", "filthy"

-- Cache for mod detection (checked once)
local modLoadedCache = nil
local lastModCheckTime = 0

-- ============================================
-- MOD DETECTION
-- ============================================

--[[
    Check if Lifestyle and Hobbies mod is loaded.
    Caches the result for performance.
    @return boolean - True if mod is loaded and functional
]]--
function EHR.LifestyleCompat.IsModLoaded()
    -- Check cache (refresh every 60 seconds in case of late loading)
    local currentTime = getGameTime and getGameTime():getWorldAgeHours() or 0
    if modLoadedCache ~= nil and (currentTime - lastModCheckTime) < 1 then
        return modLoadedCache
    end

    local detected = false
    local detectionMethod = "none"

    -- Method 1: Check for global Lifestyle functions (B41 style)
    if AdjustHygieneNeed and type(AdjustHygieneNeed) == "function" then
        detected = true
        detectionMethod = "AdjustHygieneNeed"
    end

    -- Method 2: Check for Lifestyle's ModData
    if not detected then
        local lsData = ModData and ModData.get and ModData.get("LSDATA")
        if lsData then
            detected = true
            detectionMethod = "LSDATA"
        end
    end

    -- Method 3: Check for HiddenSkills (Lifestyle's skill system)
    if not detected and HiddenSkills and type(HiddenSkills) == "table" then
        detected = true
        detectionMethod = "HiddenSkills"
    end

    -- Method 4: Check for LifestyleAndHobbies global table (B42 style)
    if not detected and LifestyleAndHobbies and type(LifestyleAndHobbies) == "table" then
        detected = true
        detectionMethod = "LifestyleAndHobbies"
    end

    -- Method 5: Check for LSHygiene global (alternative B42)
    if not detected and LSHygiene and type(LSHygiene) == "table" then
        detected = true
        detectionMethod = "LSHygiene"
    end

    -- Method 6: Check player modData for Lifestyle markers
    if not detected then
        local player = getPlayer and getPlayer()
        if player then
            local modData = player:getModData()
            if modData then
                -- Check various Lifestyle modData keys
                if modData.hygieneNeed ~= nil or
                   modData.LSHygiene ~= nil or
                   modData.IsDoingShower ~= nil or
                   modData.LSMoodles ~= nil then
                    detected = true
                    detectionMethod = "playerModData"
                end
            end
        end
    end

    -- Log detection result (only when cache changes)
    if modLoadedCache ~= detected then
        if detected then
            EHR.Log("LifestyleCompat: Lifestyle mod DETECTED via " .. detectionMethod)
        else
            EHR.Log("LifestyleCompat: Lifestyle mod NOT detected (checked all methods)")
        end
    end

    modLoadedCache = detected
    lastModCheckTime = currentTime
    return detected
end

-- ============================================
-- DATA READING (Read-Only)
-- ============================================

--[[
    Get player's Lifestyle mod data safely.
    Does NOT modify any data.
    @param player (IsoPlayer) - The player
    @return table or nil - Lifestyle player data
]]--
function EHR.LifestyleCompat.GetLifestyleData(player)
    if not player then return nil end
    if not EHR.LifestyleCompat.IsModLoaded() then return nil end

    local modData = player:getModData()
    if not modData then return nil end

    -- Lifestyle stores data directly in modData
    return modData
end

--[[
    Get player's hygiene need value.
    Checks multiple possible Lifestyle key names.
    @param player (IsoPlayer) - The player
    @return number - Hygiene need (0-100, lower = cleaner), or 50 if unavailable
]]--
function EHR.LifestyleCompat.GetHygieneNeed(player)
    local data = EHR.LifestyleCompat.GetLifestyleData(player)
    if not data then return 50 end  -- Neutral default

    -- Check various possible Lifestyle keys for hygiene
    if data.hygieneNeed ~= nil then return data.hygieneNeed end
    if data.HygieneNeed ~= nil then return data.HygieneNeed end
    if data.LSHygiene ~= nil then return data.LSHygiene end
    if data.hygiene ~= nil then return data.hygiene end
    if data.Hygiene ~= nil then return data.Hygiene end
    if data.dirtiness ~= nil then return data.dirtiness end
    if data.Dirtiness ~= nil then return data.Dirtiness end

    return 50  -- Neutral default
end

--[[
    Check if player is currently showering/bathing.
    Checks multiple possible Lifestyle keys.
    @param player (IsoPlayer) - The player
    @return boolean - True if showering/bathing
]]--
function EHR.LifestyleCompat.IsShowering(player)
    local data = EHR.LifestyleCompat.GetLifestyleData(player)
    if not data then return false end

    -- Check various possible Lifestyle keys for showering/bathing
    if data.IsDoingShower == true then return true end
    if data.isDoingShower == true then return true end
    if data.IsBathing == true then return true end
    if data.isBathing == true then return true end
    if data.LSBathing == true then return true end
    if data.LSShowering == true then return true end
    if data.takingBath == true then return true end
    if data.TakingBath == true then return true end

    return false
end

--[[
    Track hygiene changes to detect when player bathed.
    Call this periodically to update bath bonus tracking.
    @param player (IsoPlayer) - The player
]]--
function EHR.LifestyleCompat.TrackHygieneChange(player)
    if not player then return end
    local modData = player:getModData()
    if not modData then return end

    local currentHygiene = EHR.LifestyleCompat.GetHygieneNeed(player)
    local lastHygiene = modData.EHR_LastHygieneNeed or currentHygiene
    local currentHour = getGameTime():getWorldAgeHours()

    -- If hygiene improved by 30+ points suddenly, player likely bathed
    local improvement = lastHygiene - currentHygiene
    if improvement >= 30 then
        modData.EHR_LastBathTime = currentHour
        EHR.Log("LifestyleCompat: Detected bath via hygiene improvement (" .. math.floor(improvement) .. " points)")
    end

    modData.EHR_LastHygieneNeed = currentHygiene
end

--[[
    Check if player is sitting (from Lifestyle's sitting system).
    @param player (IsoPlayer) - The player
    @return boolean, number - isSitting, comfortLevel (0-1)
]]--
function EHR.LifestyleCompat.GetSittingState(player)
    local data = EHR.LifestyleCompat.GetLifestyleData(player)
    if not data then return false, 0 end

    -- Check various sitting indicators Lifestyle might use
    local isSitting = data.IsSitting or data.isSitting or data.LSIsSitting or false
    local comfort = data.seatComfort or data.SeatComfort or data.LSComfort or 0

    -- Fallback: check if player is using vanilla sit on ground
    if not isSitting and player.isSitOnGround and player:isSitOnGround() then
        isSitting = true
        comfort = 0.2  -- Basic comfort for ground sitting
    end

    return isSitting, comfort
end

--[[
    Get player's Yoga skill level (Lifestyle hidden skill).
    @param player (IsoPlayer) - The player
    @return number - Yoga level (0-10)
]]--
function EHR.LifestyleCompat.GetYogaLevel(player)
    if not player then return 0 end
    if not EHR.LifestyleCompat.IsModLoaded() then return 0 end

    -- Use Lifestyle's HiddenSkills API if available
    if HiddenSkills and HiddenSkills.getLevel then
        local success, level = pcall(HiddenSkills.getLevel, player, "Yoga")
        if success and level then
            return level
        end
    end

    -- Fallback: read directly from modData
    local modData = player:getModData()
    if modData and modData.LSHiddenSkills and modData.LSHiddenSkills.Yoga then
        return modData.LSHiddenSkills.Yoga[1] or 0  -- [1] is level
    end

    return 0
end

--[[
    Get hygiene moodle state.
    @param player (IsoPlayer) - The player
    @return string, number - "good", "bad", or "neutral", and intensity (0-1)
]]--
function EHR.LifestyleCompat.GetHygieneMoodle(player)
    local data = EHR.LifestyleCompat.GetLifestyleData(player)
    if not data or not data.LSMoodles then return "neutral", 0 end

    local goodMoodle = data.LSMoodles.HygieneGood
    local badMoodle = data.LSMoodles.HygieneBad

    if goodMoodle and goodMoodle.Value and goodMoodle.Value > 0 then
        return "good", goodMoodle.Value
    elseif badMoodle and badMoodle.Value and badMoodle.Value > 0 then
        return "bad", badMoodle.Value
    end

    return "neutral", 0
end

-- ============================================
-- HEALING BONUS CALCULATION
-- ============================================

--[[
    Calculate total healing bonus multiplier from Lifestyle activities.
    Returns a multiplier to apply to healing rate (1.0 = no change).

    Bonuses:
    - Recent bath (showered within last 2 hours): +5% (decays over time)
    - Comfortable sitting: +5-10%
    - Yoga skill: +1% per level

    Penalties:
    - Dirty: -10%
    - Filthy: -25%

    @param player (IsoPlayer) - The player
    @return number - Healing multiplier (e.g., 1.25 for +25% healing)
]]--
function EHR.LifestyleCompat.GetHealingMultiplier(player)
    if not player then return 1.0 end
    if not EHR.LifestyleCompat.IsModLoaded() then return 1.0 end

    local config = EHR.LifestyleCompat.Config
    local modData = player:getModData()
    local totalBonus = 0

    -- =====================================
    -- Bath Bonus - from active showering or recent bath
    -- =====================================
    local isShowering = EHR.LifestyleCompat.IsShowering(player)
    local recentBathTime = modData.EHR_LastBathTime or 0
    local currentHour = getGameTime():getWorldAgeHours()

    if isShowering then
        -- Currently showering - full bonus
        modData.EHR_LastBathTime = currentHour
        totalBonus = totalBonus + config.BONUS_SHOWERING
    elseif recentBathTime > 0 then
        -- Recent bath bonus (decays over 2 hours)
        local timeSinceBath = currentHour - recentBathTime
        local bathDuration = 2.0

        if timeSinceBath < bathDuration then
            local remaining = bathDuration - timeSinceBath
            local decayedBonus = config.BONUS_SHOWERING * (remaining / bathDuration)
            totalBonus = totalBonus + decayedBonus
        else
            modData.EHR_LastBathTime = 0  -- Clear expired
        end
    end

    -- =====================================
    -- Hygiene Bonus/Penalty
    -- Only very clean/clean give bonus, dirty/filthy give penalty
    -- =====================================
    local hygieneNeed = EHR.LifestyleCompat.GetHygieneNeed(player)

    if hygieneNeed < config.HYGIENE_EXCELLENT then
        totalBonus = totalBonus + config.BONUS_HYGIENE_EXCELLENT
    elseif hygieneNeed < config.HYGIENE_GOOD then
        totalBonus = totalBonus + config.BONUS_HYGIENE_GOOD
    elseif hygieneNeed > config.HYGIENE_FILTHY then
        totalBonus = totalBonus + config.PENALTY_FILTHY
    elseif hygieneNeed > config.HYGIENE_DIRTY then
        totalBonus = totalBonus + config.PENALTY_DIRTY
    end
    -- Neutral hygiene (35-65) = no modifier

    -- =====================================
    -- Sitting/Comfort Bonus
    -- =====================================
    local isSitting, comfort = EHR.LifestyleCompat.GetSittingState(player)
    if isSitting then
        if comfort >= 0.5 then
            totalBonus = totalBonus + config.BONUS_SITTING_COMFORTABLE
        else
            totalBonus = totalBonus + config.BONUS_SITTING_BASIC
        end
    end

    -- =====================================
    -- Yoga Skill Bonus
    -- =====================================
    local yogaLevel = EHR.LifestyleCompat.GetYogaLevel(player)
    if yogaLevel > 0 then
        totalBonus = totalBonus + (yogaLevel * config.BONUS_YOGA_PER_LEVEL)
    end

    -- Convert bonus to multiplier (0.25 bonus = 1.25 multiplier)
    return 1.0 + totalBonus
end

--[[
    Get detailed breakdown of healing bonuses for UI display.
    Returns structure expected by EHR_MedicalMonitorUI.

    IMPORTANT: Bath bonus only triggers from ACTIVE showering, not passive hygiene.
    Hygiene affects healing rate but doesn't show as "bath bonus" in UI.

    @param player (IsoPlayer) - The player
    @return table - {isActive, bathBonus, bathTimeLeft, comfortBonus, totalBonus, details[]}
]]--
function EHR.LifestyleCompat.GetBonusDetails(player)
    local result = {
        isActive = false,
        bathBonus = 0,
        bathTimeLeft = 0,
        comfortBonus = 0,
        totalBonus = 0,
        hygieneBonus = 0,
        hygienePenalty = 0,
        yogaBonus = 0,
        details = {},  -- Array of {name, bonus, active} for extended display
    }

    if not player then return result end
    if not EHR.LifestyleCompat.IsModLoaded() then return result end

    local config = EHR.LifestyleCompat.Config
    local modData = player:getModData()

    -- Track hygiene changes to detect baths
    EHR.LifestyleCompat.TrackHygieneChange(player)

    -- =====================================
    -- Bath Bonus - from showering or detected bath
    -- Uses Lifestyle's shower tracking + hygiene change detection
    -- =====================================
    local isShowering = EHR.LifestyleCompat.IsShowering(player)
    local recentBathTime = modData.EHR_LastBathTime or 0
    local currentHour = getGameTime():getWorldAgeHours()

    -- Track when player showers for "recent bath" bonus
    if isShowering then
        modData.EHR_LastBathTime = currentHour
        result.bathBonus = config.BONUS_SHOWERING
        result.bathTimeLeft = 2.0  -- Will last 2 hours after shower
        table.insert(result.details, {name = "Showering", bonus = config.BONUS_SHOWERING, active = true})
    elseif recentBathTime > 0 then
        -- Recent bath bonus (lasts 2 hours after shower)
        local timeSinceBath = currentHour - recentBathTime
        local bathDuration = 2.0  -- Hours the bonus lasts

        if timeSinceBath < bathDuration then
            -- Bonus decays linearly over 2 hours
            local remaining = bathDuration - timeSinceBath
            local decayedBonus = config.BONUS_SHOWERING * (remaining / bathDuration)
            result.bathBonus = decayedBonus
            result.bathTimeLeft = remaining
            table.insert(result.details, {name = "Recent Bath", bonus = decayedBonus, active = true})
        else
            -- Bonus expired, clear the tracking
            modData.EHR_LastBathTime = 0
        end
    end

    -- =====================================
    -- Hygiene Bonus/Penalty with Hysteresis
    -- Uses state tracking to prevent flickering at thresholds
    -- =====================================
    local hygieneNeed = EHR.LifestyleCompat.GetHygieneNeed(player)
    local hyst = config.HYSTERESIS

    -- Determine new state with hysteresis
    -- States: excellent, good, neutral, dirty, filthy (no "fresh")
    local newState = currentHygieneState or "neutral"

    -- State transitions with hysteresis buffer
    if currentHygieneState == "excellent" then
        if hygieneNeed > config.HYGIENE_EXCELLENT + hyst then newState = "good" end
    elseif currentHygieneState == "good" then
        if hygieneNeed < config.HYGIENE_EXCELLENT - hyst then newState = "excellent"
        elseif hygieneNeed > config.HYGIENE_GOOD + hyst then newState = "neutral" end
    elseif currentHygieneState == "neutral" then
        if hygieneNeed < config.HYGIENE_GOOD - hyst then newState = "good"
        elseif hygieneNeed > config.HYGIENE_DIRTY + hyst then newState = "dirty" end
    elseif currentHygieneState == "dirty" then
        if hygieneNeed < config.HYGIENE_DIRTY - hyst then newState = "neutral"
        elseif hygieneNeed > config.HYGIENE_FILTHY + hyst then newState = "filthy" end
    elseif currentHygieneState == "filthy" then
        if hygieneNeed < config.HYGIENE_FILTHY - hyst then newState = "dirty" end
    else
        -- Initial state determination (no hysteresis on first check)
        if hygieneNeed < config.HYGIENE_EXCELLENT then newState = "excellent"
        elseif hygieneNeed < config.HYGIENE_GOOD then newState = "good"
        elseif hygieneNeed > config.HYGIENE_FILTHY then newState = "filthy"
        elseif hygieneNeed > config.HYGIENE_DIRTY then newState = "dirty"
        else newState = "neutral" end
    end

    currentHygieneState = newState

    -- Apply bonus/penalty based on state (only excellent/good give bonus, dirty/filthy give penalty)
    if newState == "excellent" then
        result.hygieneBonus = config.BONUS_HYGIENE_EXCELLENT
        result.comfortBonus = result.comfortBonus + config.BONUS_HYGIENE_EXCELLENT
        table.insert(result.details, {name = "Very Clean", bonus = config.BONUS_HYGIENE_EXCELLENT, active = true})
    elseif newState == "good" then
        result.hygieneBonus = config.BONUS_HYGIENE_GOOD
        result.comfortBonus = result.comfortBonus + config.BONUS_HYGIENE_GOOD
        table.insert(result.details, {name = "Clean", bonus = config.BONUS_HYGIENE_GOOD, active = true})
    elseif newState == "filthy" then
        result.hygienePenalty = config.PENALTY_FILTHY
        result.comfortBonus = result.comfortBonus + config.PENALTY_FILTHY
        table.insert(result.details, {name = "Filthy", bonus = config.PENALTY_FILTHY, active = true})
    elseif newState == "dirty" then
        result.hygienePenalty = config.PENALTY_DIRTY
        result.comfortBonus = result.comfortBonus + config.PENALTY_DIRTY
        table.insert(result.details, {name = "Dirty", bonus = config.PENALTY_DIRTY, active = true})
    end
    -- "neutral" state = no bonus or penalty

    -- =====================================
    -- Comfort/Sitting Bonus
    -- =====================================
    local isSitting, comfort = EHR.LifestyleCompat.GetSittingState(player)
    if isSitting then
        local sittingBonus = comfort >= 0.5 and config.BONUS_SITTING_COMFORTABLE or config.BONUS_SITTING_BASIC
        result.comfortBonus = result.comfortBonus + sittingBonus
        local sittingName = comfort >= 0.5 and "Comfortable Seating" or "Resting"
        table.insert(result.details, {name = sittingName, bonus = sittingBonus, active = true})
    end

    -- =====================================
    -- Yoga Skill Bonus
    -- =====================================
    local yogaLevel = EHR.LifestyleCompat.GetYogaLevel(player)
    if yogaLevel > 0 then
        local yogaBonus = yogaLevel * config.BONUS_YOGA_PER_LEVEL
        result.yogaBonus = yogaBonus
        result.comfortBonus = result.comfortBonus + yogaBonus
        table.insert(result.details, {name = "Yoga (Lv." .. yogaLevel .. ")", bonus = yogaBonus, active = true})
    end

    -- =====================================
    -- Calculate Total and Active State
    -- =====================================
    result.totalBonus = result.bathBonus + result.comfortBonus
    result.isActive = result.bathBonus > 0 or result.comfortBonus ~= 0

    return result
end

--[[
    Get healing multiplier for a specific disease.
    Some diseases might benefit more from certain activities.
    @param player (IsoPlayer) - The player
    @param diseaseId (string) - Disease ID
    @return number - Healing multiplier
]]--
function EHR.LifestyleCompat.GetDiseaseHealingMultiplier(player, diseaseId)
    -- Base multiplier from general Lifestyle bonuses
    local baseMultiplier = EHR.LifestyleCompat.GetHealingMultiplier(player)

    -- Disease-specific adjustments
    if not diseaseId then return baseMultiplier end

    local config = EHR.LifestyleCompat.Config

    -- Wound infections: hygiene matters more
    -- Recent bath gives extra bonus, being dirty gives extra penalty
    if diseaseId == "wound_infection" or diseaseId == "cellulitis" then
        local hygieneNeed = EHR.LifestyleCompat.GetHygieneNeed(player)

        -- Extra penalty when dirty (wounds get infected easier)
        if hygieneNeed > config.HYGIENE_FILTHY then
            baseMultiplier = baseMultiplier - 0.10  -- Extra -10%
        elseif hygieneNeed > config.HYGIENE_DIRTY then
            baseMultiplier = baseMultiplier - 0.05  -- Extra -5%
        end

        -- Bonus from recent bath is already in base, but being very clean helps wounds
        local modData = player:getModData()
        local recentBathTime = modData.EHR_LastBathTime or 0
        local currentHour = getGameTime():getWorldAgeHours()
        if recentBathTime > 0 and (currentHour - recentBathTime) < 2.0 then
            -- Recent bath gives extra wound healing bonus
            baseMultiplier = baseMultiplier + 0.05
        end
    end

    -- Respiratory diseases don't benefit as much from sitting
    if diseaseId == "pneumonia" or diseaseId == "common_cold" then
        local isSitting, _ = EHR.LifestyleCompat.GetSittingState(player)
        if isSitting then
            baseMultiplier = baseMultiplier - 0.05
        end
    end

    return math.max(0.5, baseMultiplier)  -- Never go below 50% healing
end

--[[
    Check if a disease type can benefit from Lifestyle bonuses.
    @param diseaseId (string) - Disease ID
    @return boolean - True if disease can get bonuses
]]--
function EHR.LifestyleCompat.DiseaseSupportsBonus(diseaseId)
    if not diseaseId then return false end

    -- Most diseases support bonuses
    local unsupportedDiseases = {
        ["knox_infection"] = true,  -- Knox virus isn't affected by hygiene
    }

    return not unsupportedDiseases[diseaseId]
end

-- ============================================
-- INITIALIZATION
-- ============================================

function EHR.LifestyleCompat.Initialize()
    -- Force detection check
    modLoadedCache = nil
    lastModCheckTime = 0

    if EHR.LifestyleCompat.IsModLoaded() then
        EHR.Log("LifestyleCompat: Lifestyle and Hobbies mod detected - healing bonuses enabled")
    else
        EHR.Log("LifestyleCompat: Lifestyle and Hobbies mod not detected - no bonuses applied")
    end
end

function EHR.LifestyleCompat.ResetState()
    modLoadedCache = nil
    lastModCheckTime = 0
    EHR.Log("LifestyleCompat: Detection cache reset")
end

--[[
    Debug function to print all detection info.
    Call via: EHR.LifestyleCompat.DebugDetection()
]]--
function EHR.LifestyleCompat.DebugDetection()
    print("=== EHR Lifestyle Compatibility Debug ===")

    -- Check global functions/tables
    print("")
    print("[GLOBAL DETECTION METHODS]")
    print("  AdjustHygieneNeed: " .. tostring(AdjustHygieneNeed ~= nil))
    print("  HiddenSkills: " .. tostring(HiddenSkills ~= nil))
    print("  LifestyleAndHobbies: " .. tostring(LifestyleAndHobbies ~= nil))
    print("  LSHygiene: " .. tostring(LSHygiene ~= nil))

    -- Check ModData
    local lsData = ModData and ModData.get and ModData.get("LSDATA")
    print("  LSDATA ModData: " .. tostring(lsData ~= nil))

    -- Check player modData
    local player = getPlayer and getPlayer()
    if player then
        local modData = player:getModData()
        if modData then
            print("")
            print("[PLAYER MODDATA]")
            print("  hygieneNeed: " .. tostring(modData.hygieneNeed))
            print("  LSHygiene: " .. tostring(modData.LSHygiene ~= nil))
            print("  IsDoingShower: " .. tostring(modData.IsDoingShower))
            print("  LSMoodles: " .. tostring(modData.LSMoodles ~= nil))
            print("  IsSitting: " .. tostring(modData.IsSitting))
            print("  EHR_LastBathTime: " .. tostring(modData.EHR_LastBathTime))

            -- List all potentially Lifestyle-related keys
            print("")
            print("[ALL LIFESTYLE-RELATED KEYS]")
            local foundLSKeys = false
            for k, v in pairs(modData) do
                if type(k) == "string" then
                    local kLower = k:lower()
                    if kLower:find("ls") or kLower:find("hygiene") or kLower:find("shower") or
                       kLower:find("bath") or kLower:find("dirty") or kLower:find("clean") or
                       kLower:find("sitting") or kLower:find("yoga") or kLower:find("wellness") then
                        local valStr = tostring(v)
                        if type(v) == "table" then valStr = "(table)" end
                        print("  " .. k .. " = " .. valStr)
                        foundLSKeys = true
                    end
                end
            end
            if not foundLSKeys then
                print("  (none found - Lifestyle may not be storing data yet)")
            end
        else
            print("Player modData: nil")
        end

        -- Test bonus calculation
        print("")
        print("[BONUS CALCULATION TEST]")
        modLoadedCache = nil  -- Force fresh detection
        local detected = EHR.LifestyleCompat.IsModLoaded()
        print("  Detection result: " .. tostring(detected))

        -- Show actual hygiene value being read
        local hygieneValue = EHR.LifestyleCompat.GetHygieneNeed(player)
        print("  Hygiene value read: " .. tostring(hygieneValue) .. " (0=very clean, 100=filthy)")

        if detected then
            local bonuses = EHR.LifestyleCompat.GetBonusDetails(player)
            print("  isActive: " .. tostring(bonuses.isActive))
            print("  hygieneBonus: " .. tostring(bonuses.hygieneBonus))
            print("  bathBonus: " .. tostring(bonuses.bathBonus))
            print("  bathTimeLeft: " .. tostring(bonuses.bathTimeLeft))
            print("  comfortBonus: " .. tostring(bonuses.comfortBonus))
            print("  hygienePenalty: " .. tostring(bonuses.hygienePenalty))
            print("  yogaBonus: " .. tostring(bonuses.yogaBonus))
            print("  totalBonus: " .. tostring(bonuses.totalBonus))
            print("  details:")
            for i, d in ipairs(bonuses.details) do
                print("    " .. i .. ": " .. d.name .. " = " .. tostring(d.bonus))
            end
        else
            print("  (Lifestyle not detected - bonuses disabled)")
        end
    else
        print("Player: nil (not in game)")
    end

    print("")
    print("==========================================")
    print("TIP: If Lifestyle is installed but not detected,")
    print("     try: EHR.LifestyleCompat.ForceEnable()")
    print("==========================================")

    return modLoadedCache
end

--[[
    Force enable Lifestyle compatibility even if detection fails.
    Use this if you know Lifestyle is installed but detection isn't working.
    Call via: EHR.LifestyleCompat.ForceEnable()
]]--
function EHR.LifestyleCompat.ForceEnable()
    modLoadedCache = true
    lastModCheckTime = 999999  -- Prevent cache refresh
    EHR.Log("LifestyleCompat: FORCED ENABLED - detection bypassed")
    print("[EHR] Lifestyle compatibility FORCE ENABLED")
end

-- Initialize on game start
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(EHR.LifestyleCompat.Initialize)
end

EHR.Log = EHR.Log or function(msg) print("[EHR] " .. tostring(msg)) end
EHR.Log("EHR_LifestyleCompat.lua loaded (read-only integration v2.0.0)")

return EHR.LifestyleCompat
