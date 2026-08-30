--[[
    Extensive Health Rework B42
    Pain Sound System Module

    Plays pain vocalizations when player is injured/in pain.
    Pain sounds attract zombies via addSound().
    Painkillers suppress pain sounds entirely.

    Features:
        - Sound categories by wound type and pain level
        - Zombie attraction (30-50 tiles based on pain level)
        - Cooldown system (5+ minutes between sounds)
        - Painkiller suppression
        - Text dialogue accompaniment

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Dialogue"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.PainSounds = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.PainSounds.Config = {
    -- Cooldown between pain sounds (in game hours)
    MinCooldownHours = 0.083,  -- ~5 minutes (5/60)
    MaxCooldownHours = 0.167,  -- ~10 minutes (10/60)

    -- Zombie attraction radius (in tiles)
    BaseAttractionRadius = 40,
    MinAttractionRadius = 20,
    MaxAttractionRadius = 60,

    -- Pain level scaling for attraction
    -- Level 1 = 50% radius, Level 2 = 75%, Level 3 = 100%
    AttractionScale = {
        [1] = 0.5,
        [2] = 0.75,
        [3] = 1.0,
    },

    -- Painkiller suppression
    PainkillerSuppression = true,

    -- Pain threshold for triggering sounds (0-1 scale)
    PainThreshold = 0.15,  -- At least 15% pain to trigger
}

-- ============================================
-- SOUND CATEGORIES
-- ============================================

-- Vanilla PZ sound names for pain
-- These are the sound event names from the game's sound banks
EHR.PainSounds.VanillaSounds = {
    -- Male pain sounds
    male = {
        [1] = {"MaleHurtLight1", "MaleHurtLight2"},  -- Minor pain
        [2] = {"MaleHurt", "MaleHurt2"},              -- Moderate pain
        [3] = {"MaleHurtHeavy", "MaleScream"},        -- Severe pain
    },
    -- Female pain sounds
    female = {
        [1] = {"FemaleHurtLight1", "FemaleHurtLight2"},
        [2] = {"FemaleHurt", "FemaleHurt2"},
        [3] = {"FemaleHurtHeavy", "FemaleScream"},
    },
}

-- Sound categories by wound type
EHR.PainSounds.WoundSounds = {
    -- Laceration/cuts
    laceration = {
        [1] = {"PainHiss", "PainGrunt"},
        [2] = {"PainGroan", "PainYell"},
        [3] = {"PainScream", "PainAgony"},
    },
    -- Burns
    burn = {
        [1] = {"PainHiss", "PainWhimper"},
        [2] = {"PainYell", "PainGroan"},
        [3] = {"PainScream", "PainAgony"},
    },
    -- Fractures
    fracture = {
        [1] = {"PainGrunt", "PainGroan"},
        [2] = {"PainYell", "PainScream"},
        [3] = {"PainScream", "PainAgony"},
    },
    -- Bite wounds
    bite = {
        [1] = {"PainGrunt", "PainHiss"},
        [2] = {"PainGroan", "PainYell"},
        [3] = {"PainScream", "PainAgony"},
    },
    -- Generic/other
    generic = {
        [1] = {"PainGrunt"},
        [2] = {"PainGroan"},
        [3] = {"PainYell"},
    },
}

-- ============================================
-- DIALOGUE FOR PAIN
-- Translation keys for pain vocalizations
-- ============================================

EHR.PainSounds.PainDialogue = {
    -- Minor pain (level 1)
    [1] = {
        "EHR_Pain_Minor_1",   -- "Ow..."
        "EHR_Pain_Minor_2",   -- "That stings..."
        "EHR_Pain_Minor_3",   -- "Ouch..."
        "EHR_Pain_Minor_4",   -- "*winces*"
        "EHR_Pain_Minor_5",   -- "Ah..."
    },
    -- Moderate pain (level 2)
    [2] = {
        "EHR_Pain_Moderate_1",  -- "God that hurts!"
        "EHR_Pain_Moderate_2",  -- "Damn it!"
        "EHR_Pain_Moderate_3",  -- "*groans in pain*"
        "EHR_Pain_Moderate_4",  -- "Argh!"
        "EHR_Pain_Moderate_5",  -- "This really hurts..."
    },
    -- Severe pain (level 3)
    [3] = {
        "EHR_Pain_Severe_1",   -- "*screams*"
        "EHR_Pain_Severe_2",   -- "AAAGH!"
        "EHR_Pain_Severe_3",   -- "Make it stop!"
        "EHR_Pain_Severe_4",   -- "*cries out in agony*"
        "EHR_Pain_Severe_5",   -- "I can't take this!"
    },
}

-- ============================================
-- STATE TRACKING
-- ============================================

EHR.PainSounds.LastSoundTime = {}  -- Per-player cooldown tracking

-- ============================================
-- SANDBOX SETTINGS
-- ============================================

--[[
    Check if pain sounds are enabled in sandbox settings.
    @return boolean
]]--
function EHR.PainSounds.IsEnabled()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local enabled = SandboxVars.ExtensiveHealthRework.PainSoundsEnabled
        if enabled ~= nil then
            return enabled == true
        end
    end
    return true  -- Default to enabled
end

--[[
    Get the configured zombie attraction radius.
    @return number - Radius in tiles
]]--
function EHR.PainSounds.GetAttractionRadius()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local radius = SandboxVars.ExtensiveHealthRework.ZombieAttractionRadius
        if radius and type(radius) == "number" then
            return math.max(10, math.min(100, radius))
        end
    end
    return EHR.PainSounds.Config.BaseAttractionRadius
end

--[[
    Get the configured cooldown in game hours.
    @return number - Cooldown in hours
]]--
function EHR.PainSounds.GetCooldownHours()
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local cooldown = SandboxVars.ExtensiveHealthRework.PainSoundCooldown
        if cooldown and type(cooldown) == "number" then
            -- Convert seconds to hours
            return cooldown / 3600
        end
    end
    return EHR.PainSounds.Config.MinCooldownHours
end

-- ============================================
-- PAINKILLER CHECK
-- ============================================

--[[
    Check if player is under painkiller effect.
    @param player (IsoPlayer)
    @return boolean - True if painkillers are active
]]--
function EHR.PainSounds.IsPainkillerActive(player)
    if not player then return false end

    if EHR.Medication and EHR.Medication.IsAnalgesicActive then
        local ok, active = pcall(EHR.Medication.IsAnalgesicActive, player)
        if ok and active == true then return true end
    end

    -- Keep both the current and legacy ModData flags as lightweight fallbacks.
    local modData = player:getModData()
    if modData and (modData.EHR_AnalgesicActive or modData.EHR_PainkillerActive) then
        return true
    end

    -- Check vanilla pain stat (if very low despite injuries, likely on painkillers)
    local stats = player:getStats()
    if stats then
        local success, pain = pcall(function()
            return stats:get(CharacterStat.PAIN)
        end)
        if success then
            -- Check if player has injuries but low pain (painkiller effect)
            local bodyDamage = player:getBodyDamage()
            if bodyDamage then
                local overallHealth = bodyDamage:getOverallBodyHealth()
                -- If health is damaged but pain is very low, painkillers are likely active
                if overallHealth < 90 and pain < 0.1 then
                    return true
                end
            end
        end
    end

    return false
end

-- ============================================
-- COOLDOWN MANAGEMENT
-- ============================================

--[[
    Check if pain sound is on cooldown for a player.
    @param player (IsoPlayer)
    @return boolean - True if on cooldown
]]--
function EHR.PainSounds.IsOnCooldown(player)
    if not player then return true end

    local playerID = tostring(player:getOnlineID()) or "sp"
    local lastTime = EHR.PainSounds.LastSoundTime[playerID]

    if not lastTime then
        return false  -- Never played, not on cooldown
    end

    local currentTime = getGameTime():getWorldAgeHours()
    local cooldownHours = EHR.PainSounds.GetCooldownHours()

    return (currentTime - lastTime) < cooldownHours
end

--[[
    Set cooldown for a player after playing a pain sound.
    @param player (IsoPlayer)
]]--
function EHR.PainSounds.SetCooldown(player)
    if not player then return end

    local playerID = tostring(player:getOnlineID()) or "sp"
    EHR.PainSounds.LastSoundTime[playerID] = getGameTime():getWorldAgeHours()
end

-- ============================================
-- PAIN LEVEL CALCULATION
-- ============================================

--[[
    Calculate pain level (1-3) from player stats.
    @param player (IsoPlayer)
    @return number - Pain level 1 (minor), 2 (moderate), or 3 (severe)
]]--
function EHR.PainSounds.GetPainLevel(player)
    if not player then return 1 end

    local stats = player:getStats()
    if not stats then return 1 end

    local success, pain = pcall(function()
        return stats:get(CharacterStat.PAIN)
    end)

    if not success or not pain then
        return 1
    end

    -- Map pain (0-1) to levels (1-3)
    if pain > 0.7 then
        return 3  -- Severe
    elseif pain > 0.4 then
        return 2  -- Moderate
    else
        return 1  -- Minor
    end
end

--[[
    Check if player's pain level meets threshold for sound.
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.PainSounds.MeetsPainThreshold(player)
    if not player then return false end

    local stats = player:getStats()
    if not stats then return false end

    local success, pain = pcall(function()
        return stats:get(CharacterStat.PAIN)
    end)

    if success and pain then
        return pain >= EHR.PainSounds.Config.PainThreshold
    end

    return false
end

-- ============================================
-- CORE FUNCTIONS
-- ============================================

--[[
    Check if a pain sound should be played.
    Checks all conditions: enabled, cooldown, painkillers, threshold.

    @param player (IsoPlayer)
    @return boolean - True if sound should play
]]--
function EHR.PainSounds.ShouldPlayPainSound(player)
    -- Check if system is enabled
    if not EHR.PainSounds.IsEnabled() then
        return false
    end

    -- Check painkiller suppression
    if EHR.PainSounds.Config.PainkillerSuppression then
        if EHR.PainSounds.IsPainkillerActive(player) then
            return false
        end
    end

    -- Check cooldown
    if EHR.PainSounds.IsOnCooldown(player) then
        return false
    end

    -- Check pain threshold
    if not EHR.PainSounds.MeetsPainThreshold(player) then
        return false
    end

    return true
end

--[[
    Play a pain sound with zombie attraction.

    @param player (IsoPlayer)
    @param woundType (string, optional) - Type of wound ("laceration", "burn", "fracture", "bite", "generic")
    @param forcePainLevel (number, optional) - Override calculated pain level
    @return boolean - True if sound was played
]]--
function EHR.PainSounds.PlayPainSound(player, woundType, forcePainLevel)
    if not player then return false end

    -- Check all conditions
    if not EHR.PainSounds.ShouldPlayPainSound(player) then
        return false
    end

    -- Get pain level
    local painLevel = forcePainLevel or EHR.PainSounds.GetPainLevel(player)
    painLevel = math.max(1, math.min(3, painLevel))

    -- Determine player gender for sound selection
    local isFemale = player:isFemale()
    local genderKey = isFemale and "female" or "male"

    -- Try to play vanilla pain sound
    local vanillaSounds = EHR.PainSounds.VanillaSounds[genderKey]
    if vanillaSounds and vanillaSounds[painLevel] then
        local sounds = vanillaSounds[painLevel]
        local soundName = sounds[ZombRand(#sounds) + 1]
        -- Use pcall in case sound doesn't exist
        pcall(function()
            player:playSound(soundName)
        end)
    end

    -- Say pain dialogue
    EHR.PainSounds.SayPainDialogue(player, painLevel)

    -- Attract zombies
    EHR.PainSounds.AttractZombies(player, painLevel)

    -- Set cooldown
    EHR.PainSounds.SetCooldown(player)

    -- Debug log
    if EHR.DEBUG then
        EHR.Log(string.format("Pain sound played: level %d, wound type: %s", painLevel, woundType or "generic"))
    end

    return true
end

--[[
    Say pain dialogue text.
    @param player (IsoPlayer)
    @param painLevel (number) - 1-3
]]--
function EHR.PainSounds.SayPainDialogue(player, painLevel)
    if not player or not player.Say then return end

    local dialogueOptions = EHR.PainSounds.PainDialogue[painLevel]
    if not dialogueOptions or #dialogueOptions == 0 then
        return
    end

    -- Pick random dialogue
    local dialogueKey = dialogueOptions[ZombRand(#dialogueOptions) + 1]
    local text = getText(dialogueKey)

    -- Fallback text if translation not found (PZ returns "?" for missing keys)
    if not text or text == dialogueKey or text == "?" or text == "" then
        local fallbacks = {
            [1] = "Ow...",
            [2] = "Argh!",
            [3] = "*screams*",
        }
        text = fallbacks[painLevel] or "..."
    end

    -- Use dialogue system if available, otherwise direct Say
    if EHR.Dialogue and EHR.Dialogue.SayCritical then
        EHR.Dialogue.SayCritical(player, text)
    else
        EHR.Locale.Say(player, text)
    end
end

--[[
    Attract zombies with addSound.
    @param player (IsoPlayer)
    @param painLevel (number) - 1-3
]]--
function EHR.PainSounds.AttractZombies(player, painLevel)
    if not player then return end

    -- Get base radius from config
    local baseRadius = EHR.PainSounds.GetAttractionRadius()

    -- Scale by pain level
    local scale = EHR.PainSounds.Config.AttractionScale[painLevel] or 0.5
    local scaledRadius = math.floor(baseRadius * scale)

    -- Clamp to min/max
    scaledRadius = math.max(
        EHR.PainSounds.Config.MinAttractionRadius,
        math.min(EHR.PainSounds.Config.MaxAttractionRadius, scaledRadius)
    )

    -- Use PZ's addSound for zombie attraction
    -- addSound(source, x, y, z, radius, volume)
    local x = player:getX()
    local y = player:getY()
    local z = player:getZ()

    addSound(player, x, y, z, scaledRadius, 1)

    if EHR.DEBUG then
        EHR.Log(string.format("Zombie attraction: radius %d tiles at (%d, %d)", scaledRadius, math.floor(x), math.floor(y)))
    end
end

-- ============================================
-- EVENT HOOKS
-- ============================================

--[[
    Hook for wound-related pain events.
    Called when player receives a new wound or wound worsens.

    @param player (IsoPlayer)
    @param bodyPart (BodyPart)
    @param woundType (string)
]]--
function EHR.PainSounds.OnWoundPain(player, bodyPart, woundType)
    -- Random chance to trigger (not every wound causes vocalization)
    if ZombRand(3) < 2 then  -- 66% chance
        EHR.PainSounds.PlayPainSound(player, woundType)
    end
end

--[[
    Periodic check for pain-induced sounds.
    Called from main update loop.

    @param player (IsoPlayer)
]]--
function EHR.PainSounds.OnPainCheck(player)
    -- Only check periodically and with high pain
    local painLevel = EHR.PainSounds.GetPainLevel(player)

    if painLevel >= 2 then
        -- Higher pain = higher chance of vocalization
        local chance = painLevel == 3 and 200 or 400  -- 1 in 200 or 1 in 400
        if ZombRand(chance) < 1 then
            EHR.PainSounds.PlayPainSound(player, "generic")
        end
    end
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

--[[
    Set painkiller active state for a player.
    Called by medication system when painkillers are taken.

    @param player (IsoPlayer)
    @param active (boolean)
]]--
function EHR.PainSounds.SetPainkillerActive(player, active)
    if not player then return end

    local modData = player:getModData()
    if modData then
        modData.EHR_PainkillerActive = active
    end
end

--[[
    Get remaining cooldown time in seconds.
    @param player (IsoPlayer)
    @return number - Seconds remaining, or 0 if not on cooldown
]]--
function EHR.PainSounds.GetCooldownRemaining(player)
    if not player then return 0 end

    local playerID = tostring(player:getOnlineID()) or "sp"
    local lastTime = EHR.PainSounds.LastSoundTime[playerID]

    if not lastTime then
        return 0
    end

    local currentTime = getGameTime():getWorldAgeHours()
    local cooldownHours = EHR.PainSounds.GetCooldownHours()
    local elapsed = currentTime - lastTime

    if elapsed >= cooldownHours then
        return 0
    end

    -- Convert remaining hours to seconds
    return math.floor((cooldownHours - elapsed) * 3600)
end

--[[
    Force a pain sound (bypass cooldown, for testing/debug).
    @param player (IsoPlayer)
    @param painLevel (number) - 1-3
]]--
function EHR.PainSounds.ForcePainSound(player, painLevel)
    if not player then return end

    -- Bypass all checks except enabled
    if not EHR.PainSounds.IsEnabled() then
        return
    end

    painLevel = painLevel or EHR.PainSounds.GetPainLevel(player)
    painLevel = math.max(1, math.min(3, painLevel))

    -- Play sound directly
    local isFemale = player:isFemale()
    local genderKey = isFemale and "female" or "male"
    local vanillaSounds = EHR.PainSounds.VanillaSounds[genderKey]

    if vanillaSounds and vanillaSounds[painLevel] then
        local sounds = vanillaSounds[painLevel]
        local soundName = sounds[ZombRand(#sounds) + 1]
        pcall(function()
            player:playSound(soundName)
        end)
    end

    EHR.PainSounds.SayPainDialogue(player, painLevel)
    EHR.PainSounds.AttractZombies(player, painLevel)

    -- Don't set cooldown for forced sounds
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log("PainSounds module loaded (zombie attraction system)")
