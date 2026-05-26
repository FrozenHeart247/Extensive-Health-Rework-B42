pcall(function() require "ExtensiveHealth/EHR_Localization" end)
--[[
    Extensive Health Rework B42
    Knox Infection Cure Module

    Experimental treatments for the Knox Virus:
    - Gene Therapy Injector: Cure or death based on blood type compatibility
    - Phalanx Suppressant Pills: Reset infection with diminishing returns
    - Antibody Test Kit: Check Gene Therapy compatibility
    - Immunobooster Shot: 24h pre-exposure immunity

    Inspired by No More Room in Hell mechanics

    B42 API Compatibility (v1.1.0):
    - Uses bodyDamage:IsInfected() / setInfected() for boolean infection flag
    - Uses CharacterStat.ZOMBIE_INFECTION for infection progress (0-1 scale)
    - Uses CharacterStat.ZOMBIE_FEVER for zombie fever stat
    - Uses bodyPart:bitten() for bite detection while preserving visible bite wounds
    - Tick-based infection suppression for immune players

    v1.1.0 - B42 API fixes
]]--

EHR = EHR or {}
EHR.KnoxCure = {}

EHR.KnoxCure.ImmunityTrait = "ExtensiveHealth:patientzero"
EHR.KnoxCure.ImmunityTraitRegistryKey = "patientzero"

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.KnoxCure.Config = {
    -- Gene Therapy compatibility by blood type (cure chance %)
    -- O- is rarest IRL but best compatibility
    -- AB+ is most common but worst odds
    geneTherapyCompatibility = {
        ["O-"]  = 95,
        ["O+"]  = 85,
        ["A-"]  = 75,
        ["B-"]  = 75,
        ["A+"]  = 65,
        ["B+"]  = 65,
        ["AB-"] = 50,
        ["AB+"] = 40,
    },

    -- Phalanx diminishing returns (% infection reset to)
    phalanxEffectiveness = {
        [1] = 0,    -- 1st pill: Reset to 0%
        [2] = 25,   -- 2nd pill: Reset to 25%
        [3] = 50,   -- 3rd pill: Reset to 50%
        [4] = 75,   -- 4th pill: Reset to 75%
        -- 5th+: No effect
    },

    -- Phalanx side effects duration (hours)
    phalanxNauseaDuration = 6,
    phalanxFeverDuration = 12,
    phalanxImmuneDebuffDuration = 48,
    phalanxImmuneDebuffAmount = 0.2,  -- 20% more vulnerable

    -- Immunobooster settings
    immunoboosterDuration = 24,       -- Hours of immunity
    immunoboosterCooldown = 168,      -- 7 days (168 hours) before can use again

    -- Gene Therapy survivor effects
    geneTherapyHealthReduction = 0.10,  -- 10% max health reduction
    geneTherapyMigraineChance = 0.001,  -- Per tick chance of migraine
}

-- ============================================
-- PLAYER DATA MANAGEMENT
-- ============================================

--[[
    Initialize Knox cure tracking for a player
]]--
function EHR.KnoxCure.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if modData.EHR_KnoxCure then return end

    modData.EHR_KnoxCure = {
        -- Phalanx tracking
        phalanxUsageCount = 0,          -- How many times used (for diminishing returns)
        phalanxSideEffectsEnd = 0,      -- World hour when side effects end
        phalanxResetTarget = nil,       -- Target infection level after Phalanx (for suppression)
        phalanxResetTime = 0,           -- World hour when Phalanx was used

        -- Immunobooster tracking
        immunoboosterActiveUntil = 0,   -- World hour when immunity ends
        immunoboosterLastUsed = nil,    -- World hour when last used (for cooldown)
        immunoboosterHasBeenUsed = false,

        -- Gene Therapy tracking
        geneTherapySurvivor = false,    -- True if survived Gene Therapy
        geneTherapyImmune = false,      -- True = permanently immune to Knox

        -- Antibody test result (cached)
        lastTestResult = nil,
    }

    EHR.Log("KnoxCure: Initialized tracking for player")
end

function EHR.KnoxCure.NormalizeData(data)
    if not data then return nil end

    if data.immunoboosterActiveUntil == nil then
        data.immunoboosterActiveUntil = 0
    end

    local lastUsed = tonumber(data.immunoboosterLastUsed)
    if data.immunoboosterHasBeenUsed == nil then
        data.immunoboosterHasBeenUsed = lastUsed ~= nil and lastUsed > 0
    end

    -- Older saves initialized last-used to 0, which made brand new characters
    -- wait through the full cooldown before ever using the shot.
    if data.immunoboosterHasBeenUsed ~= true and lastUsed == 0 then
        data.immunoboosterLastUsed = nil
    end

    return data
end

--[[
    Get Knox cure data for a player
]]--
function EHR.KnoxCure.GetData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData.EHR_KnoxCure then
        EHR.KnoxCure.InitializePlayer(player)
    end
    return EHR.KnoxCure.NormalizeData(modData.EHR_KnoxCure)
end

local function EHRKnoxCallBool(target, methodNames)
    if not target then return false end
    for _, methodName in ipairs(methodNames) do
        local method = target[methodName]
        if type(method) == "function" then
            local ok, result = pcall(function()
                return method(target)
            end)
            if ok and result == true then
                return true
            end
        end
    end
    return false
end

local function EHRKnoxCallNumber(target, methodName, default)
    if not target then return default end
    local method = target[methodName]
    if type(method) ~= "function" then return default end

    local ok, result = pcall(function()
        return method(target)
    end)
    if ok and result ~= nil then
        return tonumber(result) or default
    end
    return default
end

local function EHRKnoxCallVoid(target, methodName, value)
    if not target then return false end
    local method = target[methodName]
    if type(method) ~= "function" then return false end

    local ok = false
    if value == nil then
        ok = pcall(function()
            method(target)
        end)
    else
        ok = pcall(function()
            method(target, value)
        end)
    end

    return ok == true
end

local function EHRKnoxGetZombieStat(player, stat)
    if not player or not stat then return 0 end
    local stats = player:getStats()
    if not stats then return 0 end

    local ok, result = pcall(function()
        return stats:get(stat)
    end)
    if ok and result then
        return tonumber(result) or 0
    end
    return 0
end

local function EHRKnoxSetZombieStat(player, stat, value)
    if not player or not stat then return false end
    local stats = player:getStats()
    if not stats then return false end

    local ok = pcall(function()
        stats:set(stat, value)
    end)
    return ok == true
end

local function EHRKnoxHasBodyPartPayload(bodyDamage)
    if not bodyDamage then return false end

    local parts = nil
    local ok = pcall(function()
        parts = bodyDamage:getBodyParts()
    end)
    if not ok or not parts then return false end

    local size = 0
    local sizeOk = pcall(function()
        size = parts:size()
    end)
    if not sizeOk or not size or size <= 0 then return false end

    for i = 0, size - 1 do
        local part = nil
        pcall(function()
            part = parts:get(i)
        end)
        if part and EHRKnoxCallBool(part, { "IsInfected", "isInfected" }) then
            return true
        end
    end

    return false
end

local function EHRKnoxTimerLooksActive(bodyDamage)
    if not bodyDamage then return false end

    local infectionTime = EHRKnoxCallNumber(bodyDamage, "getInfectionTime", -1)
    local mortalityDuration = EHRKnoxCallNumber(bodyDamage, "getInfectionMortalityDuration", -1)

    return infectionTime >= 0 and mortalityDuration > 0
end

function EHR.KnoxCure.ClearStaleExternalInfection(player)
    if not player then return false end

    local changed = false
    local bodyDamage = player:getBodyDamage()

    if bodyDamage then
        pcall(function() bodyDamage:setInfected(false) end)
        pcall(function() bodyDamage:setInfectionTime(-1.0) end)
        pcall(function() bodyDamage:setInfectionMortalityDuration(-1.0) end)
    end

    if CharacterStat then
        if CharacterStat.ZOMBIE_INFECTION and EHRKnoxGetZombieStat(player, CharacterStat.ZOMBIE_INFECTION) > 0 then
            changed = EHRKnoxSetZombieStat(player, CharacterStat.ZOMBIE_INFECTION, 0) or changed
        end
        if CharacterStat.ZOMBIE_FEVER and EHRKnoxGetZombieStat(player, CharacterStat.ZOMBIE_FEVER) > 0 then
            changed = EHRKnoxSetZombieStat(player, CharacterStat.ZOMBIE_FEVER, 0) or changed
        end
    end

    local modData = player:getModData()
    local diseaseData = modData and modData.EHR_Disease
    local active = diseaseData and diseaseData.active
    if type(active) == "table" then
        if active["Knox_Infection"] ~= nil then
            active["Knox_Infection"] = nil
            changed = true
        end
        if active["knox_infection"] ~= nil then
            active["knox_infection"] = nil
            changed = true
        end
    end

    if changed then
        if player.transmitModData then
            pcall(function() player:transmitModData() end)
        end
        if EHR.Log then
            EHR.Log("KnoxCure: cleared stale Knox state after external cure")
        end
    end

    return changed
end

-- ============================================
-- KNOX INFECTION DETECTION (B42 Compatible)
-- ============================================

--[[
    Check if player is infected with Knox virus (zombie infection)
    Returns: true if infected, false otherwise

    B42 API Reference:
    - bodyDamage:IsInfected() - Boolean flag for Knox virus infection
    - CharacterStat.ZOMBIE_INFECTION - Infection progress stat (0-1 scale)
    - CharacterStat.ZOMBIE_FEVER - Fever from zombie infection
]]--
function EHR.KnoxCure.IsInfected(player)
    if not player then return false end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return false end

    -- Method 1: Check boolean infection flag (primary B42 method).
    -- Some mods/versions use lowercase isInfected(), so support both.
    if EHRKnoxCallBool(bodyDamage, { "IsInfected", "isInfected" }) then
        return true
    end

    if EHRKnoxHasBodyPartPayload(bodyDamage) then
        return true
    end

    local timerActive = EHRKnoxTimerLooksActive(bodyDamage)

    -- Method 2: Check CharacterStat.ZOMBIE_INFECTION stat (B42 stat-based).
    -- Compatibility note: LGD Antibodies cures Knox by clearing BodyDamage and
    -- infection timers, but it may leave the B42 stat non-zero. Treat that as
    -- stale if every vanilla infection source is already gone.
    if CharacterStat and CharacterStat.ZOMBIE_INFECTION then
        local level = EHRKnoxGetZombieStat(player, CharacterStat.ZOMBIE_INFECTION)
        if level > 0 then
            if timerActive then
                return true
            end
            EHR.KnoxCure.ClearStaleExternalInfection(player)
            return false
        end
    end

    return false
end

function EHR.KnoxCure.IsVanillaInfectionPresent(player)
    if not player then return false end
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return false end

    if EHRKnoxCallBool(bodyDamage, { "IsInfected", "isInfected" }) then
        return true
    end
    if EHRKnoxHasBodyPartPayload(bodyDamage) then
        return true
    end
    if EHRKnoxTimerLooksActive(bodyDamage) then
        return true
    end
    if CharacterStat and CharacterStat.ZOMBIE_INFECTION then
        local level = EHRKnoxGetZombieStat(player, CharacterStat.ZOMBIE_INFECTION)
        if level > 0 then
            return true
        end
    end

    return false
end

--[[
    Add the visible Patient Zero trait to survivors of successful Gene Therapy.
    The actual immunity remains the geneTherapyImmune flag below; this trait is
    a UI-visible permanent marker for the character sheet.
]]--
function EHR.KnoxCure.GrantImmunityTrait(player, data)
    if not player then return false end

    data = data or EHR.KnoxCure.GetData(player)

    local traitToken = nil
    if EHRCharacterTraits then
        traitToken = EHRCharacterTraits[EHR.KnoxCure.ImmunityTraitRegistryKey]
    end

    traitToken = traitToken or EHR.KnoxCure.ImmunityTrait
    if not traitToken then
        return false
    end

    local traits = nil
    if player.getCharacterTraits then
        local ok, result = pcall(function() return player:getCharacterTraits() end)
        if ok then traits = result end
    end
    if not traits then return false end

    local hasTrait = false
    if player.hasTrait then
        hasTrait = player:hasTrait(traitToken) == true
    end
    if not hasTrait and traits.contains then
        hasTrait = traits:contains(traitToken) == true
    end

    if hasTrait then
        if data then data.immunityTraitGranted = true end
        return true
    end

    local added = pcall(function() traits:add(traitToken) end)
    if added ~= true then
        return false
    end
    if data then data.immunityTraitGranted = true end
    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end
    EHR.Log("KnoxCure: Granted Patient Zero trait")
    return true
end

--[[
    Get infection progress (0-1 scale)
    Uses CharacterStat.ZOMBIE_INFECTION in B42
]]--
function EHR.KnoxCure.GetInfectionProgress(player)
    if not player then return 0 end

    local stats = player:getStats()
    if not stats then return 0 end

    -- B42: Use CharacterStat.ZOMBIE_INFECTION (0-1 scale)
    if CharacterStat and CharacterStat.ZOMBIE_INFECTION then
        local success, level = pcall(function()
            return stats:get(CharacterStat.ZOMBIE_INFECTION)
        end)
        if success and level then
            return level
        end
    end

    return 0
end

--[[
    Set infection progress (0-1 scale)
    Uses CharacterStat.ZOMBIE_INFECTION in B42
]]--
function EHR.KnoxCure.SetInfectionProgress(player, progress)
    if not player then return end

    local stats = player:getStats()
    if not stats then return end

    progress = math.max(0, math.min(1, progress))

    -- B42: Use CharacterStat.ZOMBIE_INFECTION (0-1 scale)
    -- Only reset the infection progress stat - don't clear the infected flag
    -- This allows Phalanx to reset progress while keeping the bite active
    -- (infection will restart from 0% rather than being fully cured)
    if CharacterStat and CharacterStat.ZOMBIE_INFECTION then
        pcall(function()
            stats:set(CharacterStat.ZOMBIE_INFECTION, progress)
        end)
    end

    -- Also reset ZOMBIE_FEVER proportionally to clear the Sick moodle
    -- Fever should match infection progress (no infection = no fever)
    if CharacterStat and CharacterStat.ZOMBIE_FEVER then
        pcall(function()
            stats:set(CharacterStat.ZOMBIE_FEVER, progress)
        end)
    end
end

local function EHRKnoxForEachBodyPart(bodyDamage, callback)
    if not bodyDamage or not BodyPartType or not BodyPartType.FromIndex then return false end

    local maxIndex = nil
    if BodyPartType.MAX and BodyPartType.MAX.index then
        local ok, value = pcall(function() return BodyPartType.MAX:index() - 1 end)
        if ok then maxIndex = value end
    end
    if (not maxIndex or maxIndex < 0) and BodyPartType.ToIndex and BodyPartType.MAX then
        local ok, value = pcall(function() return BodyPartType.ToIndex(BodyPartType.MAX) - 1 end)
        if ok then maxIndex = value end
    end
    if not maxIndex or maxIndex < 0 then return false end

    local anyChanged = false
    for i = 0, maxIndex do
        local partType = BodyPartType.FromIndex(i)
        local bodyPart = partType and bodyDamage:getBodyPart(partType) or nil
        if bodyPart and callback(bodyPart, i) then
            anyChanged = true
        end
    end

    return anyChanged
end

local function EHRKnoxClearBiteSource(bodyPart)
    if not bodyPart then return false end

    local isBitten = false
    local okBitten, bitten = pcall(function() return bodyPart:bitten() end)
    if okBitten and bitten then
        isBitten = true
    end
    if not isBitten then return false end

    -- Keep the bite wound visible, but remove the Knox infection payload attached to it.
    -- Do not call SetBitten(false): immunity prevents Knox, it does not heal the wound.
    pcall(function() bodyPart:SetInfected(false) end)
    pcall(function() bodyPart:SetFakeInfected(false) end)

    return true
end

local function EHRKnoxClearBodyPartInfectionMarkers(bodyPart)
    if not bodyPart then return false end

    pcall(function() bodyPart:SetInfected(false) end)
    pcall(function() bodyPart:SetFakeInfected(false) end)

    return false
end

--[[
    Cure Knox infection completely
    Clears all vanilla zombie infection flags and stats
]]--
function EHR.KnoxCure.CureInfection(player)
    if not player then return end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    local stats = player:getStats()

    -- =====================================
    -- Step 1: Clear the boolean infection flag
    -- =====================================
    pcall(function() bodyDamage:setInfected(false) end)
    pcall(function() bodyDamage:setInfectionTime(-1.0) end)
    pcall(function() bodyDamage:setInfectionMortalityDuration(-1.0) end)

    -- =====================================
    -- Step 2: Clear CharacterStat.ZOMBIE_INFECTION (B42)
    -- =====================================
    if stats and CharacterStat then
        if CharacterStat.ZOMBIE_INFECTION then
            pcall(function() stats:set(CharacterStat.ZOMBIE_INFECTION, 0) end)
        end

        -- Also clear zombie fever
        if CharacterStat.ZOMBIE_FEVER then
            pcall(function() stats:set(CharacterStat.ZOMBIE_FEVER, 0) end)
        end
    end

    -- Step 3: Clear body-part Knox source flags without erasing visible bite wounds.
    EHRKnoxForEachBodyPart(bodyDamage, function(bodyPart)
        EHRKnoxClearBodyPartInfectionMarkers(bodyPart)
        return EHRKnoxClearBiteSource(bodyPart)
    end)

    if bodyDamage.DamageUpdate then
        pcall(function() bodyDamage:DamageUpdate() end)
    end

    EHR.Log("KnoxCure: Knox virus infection cured!")
end

--[[
    Check if player has any bitten body parts
    Useful for determining if infection source exists
]]--
function EHR.KnoxCure.HasBites(player)
    if not player then return false end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return false end

    local foundBite = false
    EHRKnoxForEachBodyPart(bodyDamage, function(bodyPart)
        local success, isBitten = pcall(function()
            return bodyPart:bitten()
        end)
        if success and isBitten then
            foundBite = true
        end
        return false
    end)

    return foundBite
end

-- ============================================
-- GENE THERAPY INJECTOR
-- ============================================

--[[
    Get Gene Therapy compatibility chance based on blood type
]]--
function EHR.KnoxCure.GetGeneTherapyChance(player)
    if not player then return 50 end

    -- Get blood type from EHR blood system
    local bloodType = "O+"  -- Default
    if EHR.Blood and EHR.Blood.GetPlayerBloodType then
        bloodType = EHR.Blood.GetPlayerBloodType(player) or "O+"
    end

    local config = EHR.KnoxCure.Config
    return config.geneTherapyCompatibility[bloodType] or 50
end

--[[
    Get compatibility rating string for display
]]--
function EHR.KnoxCure.GetCompatibilityRating(player)
    local chance = EHR.KnoxCure.GetGeneTherapyChance(player)

    if chance >= 75 then
        return "High Compatibility", {0.2, 0.8, 0.2}  -- Green
    elseif chance >= 50 then
        return "Moderate Compatibility", {0.8, 0.8, 0.2}  -- Yellow
    elseif chance >= 25 then
        return "Low Compatibility", {0.8, 0.5, 0.2}  -- Orange
    else
        return "Critical Risk", {0.8, 0.2, 0.2}  -- Red
    end
end

--[[
    Use Gene Therapy Injector
    Returns: "cured", "died", or "not_infected"
]]--
function EHR.KnoxCure.UseGeneTherapy(player, item)
    if not player then return "error" end

    local data = EHR.KnoxCure.GetData(player)
    if not data then return "error" end

    -- Check if already a Gene Therapy survivor (immune)
    if data.geneTherapyImmune then
        EHR.Dialogue.SayStageChange(player, "I'm already immune to the virus...")
        return "already_immune"
    end

    -- Check if actually infected
    if not EHR.KnoxCure.IsInfected(player) then
        EHR.Dialogue.SayStageChange(player, "I'm not infected... no need to risk this.")
        return "not_infected"
    end

    -- Get cure chance based on blood type
    local cureChance = EHR.KnoxCure.GetGeneTherapyChance(player)
    local roll = ZombRand(100)

    EHR.Log(string.format("KnoxCure: Gene Therapy used. Cure chance: %d%%, Roll: %d", cureChance, roll))

    -- Consume item
    if item then
        player:getInventory():Remove(item)
    end

    if roll < cureChance then
        -- SUCCESS - Cured!
        EHR.KnoxCure.CureInfection(player)

        -- Mark as Gene Therapy survivor
        data.geneTherapySurvivor = true
        data.geneTherapyImmune = true

        -- Visible permanent marker on the character sheet
        EHR.KnoxCure.GrantImmunityTrait(player, data)

        -- Apply permanent side effects (reduced max health)
        EHR.KnoxCure.ApplyGeneTherapySideEffects(player)

        -- Dialogue
        EHR.Dialogue.SayStageChange(player, "*gasps* It... it worked! I can feel it working!")

        EHR.Log("KnoxCure: Gene Therapy SUCCESS - player cured and now immune")
        return "cured"
    else
        -- FAILURE - Incompatible, death
        EHR.RecordDeathCause(player, "Gene Therapy Rejection - incompatible genetic markers caused fatal immune response")

        EHR.Dialogue.SayStageChange(player, "*choking* No... it's rejecting... can't breathe...")

        -- Kill player after short delay (let dialogue play)
        EHR.Log("KnoxCure: Gene Therapy FAILED - incompatible, player dies")

        if player.setHealth then
            pcall(function() player:setHealth(0) end)
        end

        return "died"
    end
end

--[[
    Apply permanent side effects from Gene Therapy survival
]]--
function EHR.KnoxCure.ApplyGeneTherapySideEffects(player)
    if not player then return end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    -- Reduce max health by 10%
    local currentMax = 100  -- Default max health
    local reduction = EHR.KnoxCure.Config.geneTherapyHealthReduction

    -- Store the reduction in modData for persistent application
    local data = EHR.KnoxCure.GetData(player)
    if data then
        data.healthReduction = reduction
    end

    EHR.Log(string.format("KnoxCure: Applied Gene Therapy side effects (%.0f%% health reduction)", reduction * 100))
end

-- ============================================
-- PHALANX SUPPRESSANT PILLS
-- ============================================

--[[
    Get current Phalanx effectiveness based on usage count
    Returns: reset percentage (0 = full reset, 100 = no effect)
]]--
function EHR.KnoxCure.GetPhalanxEffectiveness(player)
    local data = EHR.KnoxCure.GetData(player)
    if not data then return 100 end

    local usageCount = data.phalanxUsageCount or 0
    local nextUsage = usageCount + 1

    local config = EHR.KnoxCure.Config
    return config.phalanxEffectiveness[nextUsage] or 100  -- 100 = no effect
end

--[[
    Check if Phalanx will still work
]]--
function EHR.KnoxCure.IsPhalanxEffective(player)
    return EHR.KnoxCure.GetPhalanxEffectiveness(player) < 100
end

--[[
    Use Phalanx Suppressant Pill
    Returns: "reset", "diminished", "ineffective", or "not_infected"
]]--
function EHR.KnoxCure.UsePhalanx(player, item)
    if not player then return "error" end

    local data = EHR.KnoxCure.GetData(player)
    if not data then return "error" end

    -- Check if immune (Gene Therapy survivor)
    if data.geneTherapyImmune then
        EHR.Dialogue.SayStageChange(player, "I don't need this anymore... I'm immune.")
        return "immune"
    end

    -- Check if actually infected
    if not EHR.KnoxCure.IsInfected(player) then
        EHR.Dialogue.SayStageChange(player, "I'm not infected... saving this for later.")
        return "not_infected"
    end

    -- Check effectiveness
    local resetTo = EHR.KnoxCure.GetPhalanxEffectiveness(player)

    if resetTo >= 100 then
        EHR.Dialogue.SayStageChange(player, "*swallows pill* Nothing... my body's adapted to it.")
        -- Still consume the dose
        if item and item.Use then
            pcall(function() item:Use() end)
        end
        return "ineffective"
    end

    -- Consume dose (for drainable items)
    if item then
        if item.Use then
            pcall(function() item:Use() end)
        elseif item.setUsedDelta then
            local currentUsed = item:getUsedDelta() or 0
            local useDelta = item:getUseDelta() or 0.2
            item:setUsedDelta(currentUsed + useDelta)
        end
    end

    -- Get current infection level BEFORE incrementing usage
    local currentProgress = EHR.KnoxCure.GetInfectionProgress(player)
    local newProgress = resetTo / 100

    -- Only reset if it would actually lower the infection (never raise it)
    if newProgress >= currentProgress then
        EHR.Dialogue.SayStageChange(player, "*swallows pill* No effect... infection is already lower than what this would do.")
        -- Still consume the dose
        if item and item.Use then
            pcall(function() item:Use() end)
        end
        return "too_early"
    end

    -- Increment usage count (only if actually effective)
    data.phalanxUsageCount = (data.phalanxUsageCount or 0) + 1

    -- Reset infection to the appropriate level
    EHR.KnoxCure.SetInfectionProgress(player, newProgress)

    -- Apply side effects
    EHR.KnoxCure.ApplyPhalanxSideEffects(player)

    -- Dialogue based on effectiveness
    local usageCount = data.phalanxUsageCount
    if usageCount == 1 then
        EHR.Dialogue.SayStageChange(player, "*swallows pill* Ugh... that's rough. But I feel... clearer.")
    elseif usageCount == 2 then
        EHR.Dialogue.SayStageChange(player, "*grimaces* It's working... but not as well as before.")
    elseif usageCount == 3 then
        EHR.Dialogue.SayStageChange(player, "*groans* Barely felt anything... body's building resistance.")
    else
        EHR.Dialogue.SayStageChange(player, "*coughs* This is the last time this'll work...")
    end

    EHR.Log(string.format("KnoxCure: Phalanx used (#%d). Infection reset from %.0f%% to %.0f%%",
        usageCount, currentProgress * 100, newProgress * 100))

    return resetTo == 0 and "reset" or "diminished"
end

--[[
    Apply Phalanx temporary side effects
]]--
function EHR.KnoxCure.ApplyPhalanxSideEffects(player)
    if not player then return end

    local stats = player:getStats()
    if not stats then return end

    local config = EHR.KnoxCure.Config
    local currentHour = getGameTime():getWorldAgeHours()

    -- Record when side effects should end
    local data = EHR.KnoxCure.GetData(player)
    if data then
        data.phalanxSideEffectsEnd = currentHour + config.phalanxImmuneDebuffDuration
    end

    -- Immediate nausea
    if CharacterStat and CharacterStat.FOOD_SICKNESS then
        pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0.6) end)
    end

    -- Fever (via temperature)
    if CharacterStat and CharacterStat.TEMPERATURE then
        pcall(function() stats:set(CharacterStat.TEMPERATURE, 38.5) end)  -- Mild fever
    end

    EHR.Log("KnoxCure: Applied Phalanx side effects")
end

-- ============================================
-- ANTIBODY TEST KIT
-- ============================================

--[[
    Use Antibody Test Kit to check Gene Therapy compatibility
]]--
function EHR.KnoxCure.UseAntibodyTest(player, item)
    if not player then return end

    local data = EHR.KnoxCure.GetData(player)
    if not data then return end

    -- Get compatibility rating
    local rating, color = EHR.KnoxCure.GetCompatibilityRating(player)
    local chance = EHR.KnoxCure.GetGeneTherapyChance(player)

    -- Get blood type
    local bloodType = "Unknown"
    if EHR.Blood and EHR.Blood.GetPlayerBloodType then
        bloodType = EHR.Blood.GetPlayerBloodType(player) or "Unknown"
    end

    -- Cache result
    data.lastTestResult = {
        rating = rating,
        chance = chance,
        bloodType = bloodType,
        testTime = getGameTime():getWorldAgeHours(),
    }

    -- Consume item
    if item then
        player:getInventory():Remove(item)
    end

    -- Show result via dialogue
    local resultText = string.format("Test complete... Blood type %s. %s - %d%% survival chance.",
        bloodType, rating, chance)
    EHR.Dialogue.SayStageChange(player, resultText)

    -- Also show as HUD message if available
    if player.Say then
        EHR.Locale.Say(player, resultText)
    end

    EHR.Log(string.format("KnoxCure: Antibody test - Blood: %s, Rating: %s, Chance: %d%%",
        bloodType, rating, chance))

    return rating, chance
end

-- ============================================
-- IMMUNOBOOSTER SHOT
-- ============================================

--[[
    Check if Immunobooster is currently active
]]--
function EHR.KnoxCure.IsImmunoboosterActive(player)
    local data = EHR.KnoxCure.GetData(player)
    if not data then return false end

    local currentHour = getGameTime():getWorldAgeHours()
    local activeUntil = tonumber(data.immunoboosterActiveUntil) or 0
    return activeUntil > currentHour
end

--[[
    Get remaining Immunobooster time in hours
]]--
function EHR.KnoxCure.GetImmunoboosterRemaining(player)
    local data = EHR.KnoxCure.GetData(player)
    if not data then return 0 end

    local currentHour = getGameTime():getWorldAgeHours()
    local activeUntil = tonumber(data.immunoboosterActiveUntil) or 0
    return math.max(0, activeUntil - currentHour)
end

--[[
    Check if Immunobooster is on cooldown
]]--
function EHR.KnoxCure.IsImmunoboosterOnCooldown(player)
    local data = EHR.KnoxCure.GetData(player)
    if not data then return false end

    local currentHour = getGameTime():getWorldAgeHours()
    local config = EHR.KnoxCure.Config
    local lastUsed = tonumber(data.immunoboosterLastUsed)
    if data.immunoboosterHasBeenUsed ~= true and not (lastUsed and lastUsed > 0) then
        return false
    end
    if not lastUsed then return false end

    return (currentHour - lastUsed) < config.immunoboosterCooldown
end

function EHR.KnoxCure.GetImmunoboosterCooldownRemaining(player)
    local data = EHR.KnoxCure.GetData(player)
    if not data then return 0 end

    local lastUsed = tonumber(data.immunoboosterLastUsed)
    if data.immunoboosterHasBeenUsed ~= true and not (lastUsed and lastUsed > 0) then
        return 0
    end
    if not lastUsed then return 0 end

    local currentHour = getGameTime():getWorldAgeHours()
    local config = EHR.KnoxCure.Config
    return math.max(0, config.immunoboosterCooldown - (currentHour - lastUsed))
end

--[[
    Use Immunobooster Shot
]]--
function EHR.KnoxCure.UseImmunobooster(player, item)
    if not player then return "error" end

    local data = EHR.KnoxCure.GetData(player)
    if not data then return "error" end

    -- Check if already immune (Gene Therapy survivor)
    if data.geneTherapyImmune then
        EHR.Dialogue.SayStageChange(player, "I'm already permanently immune...")
        return "already_immune"
    end

    -- Check if already active
    if EHR.KnoxCure.IsImmunoboosterActive(player) then
        local remaining = EHR.KnoxCure.GetImmunoboosterRemaining(player)
        EHR.Dialogue.SayStageChange(player, string.format("Already protected for %.0f more hours.", remaining))
        return "already_active"
    end

    -- Check cooldown
    if EHR.KnoxCure.IsImmunoboosterOnCooldown(player) then
        EHR.Dialogue.SayStageChange(player, "My body hasn't recovered from the last shot...")
        return "on_cooldown"
    end

    -- Check if already infected (doesn't help)
    if EHR.KnoxCure.IsInfected(player) then
        EHR.Dialogue.SayStageChange(player, "Too late... I'm already infected. This won't help now.")
        return "already_infected"
    end
    if EHR.KnoxCure.HasBites and EHR.KnoxCure.HasBites(player) then
        EHR.Dialogue.SayStageChange(player, "Too late... I needed this before the bite.")
        return "already_bitten"
    end

    -- Consume item
    if item then
        player:getInventory():Remove(item)
    end

    local currentHour = getGameTime():getWorldAgeHours()
    local config = EHR.KnoxCure.Config

    -- Activate immunity
    data.immunoboosterActiveUntil = currentHour + config.immunoboosterDuration
    data.immunoboosterLastUsed = currentHour
    data.immunoboosterHasBeenUsed = true

    -- Apply side effects
    EHR.KnoxCure.ApplyImmunoboosterSideEffects(player)

    EHR.Dialogue.SayStageChange(player, "*injects* Ugh... 24 hours of protection. Worth the side effects.")

    EHR.Log(string.format("KnoxCure: Immunobooster activated for %d hours", config.immunoboosterDuration))

    return "activated"
end

--[[
    Apply Immunobooster side effects (active during immunity window)
]]--
function EHR.KnoxCure.ApplyImmunoboosterSideEffects(player)
    if not player then return end

    local stats = player:getStats()
    if not stats then return end

    -- Mild nausea
    if CharacterStat and CharacterStat.FOOD_SICKNESS then
        local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
        pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, math.min(0.4, current + 0.2)) end)
    end

    EHR.Log("KnoxCure: Applied Immunobooster side effects")
end

-- ============================================
-- INFECTION BLOCKING (Immunobooster)
-- ============================================

--[[
    Block infection if Immunobooster is active
    Should be called when player would normally get infected
    Returns: true if infection was blocked
]]--
function EHR.KnoxCure.TryBlockInfection(player)
    if not player then return false end

    local data = EHR.KnoxCure.GetData(player)
    if not data then return false end

    -- Check for permanent immunity (Gene Therapy survivor)
    if data.geneTherapyImmune then
        EHR.Log("KnoxCure: Infection blocked - Gene Therapy immunity")
        return true
    end

    -- Check for Immunobooster
    if EHR.KnoxCure.IsImmunoboosterActive(player) then
        EHR.Log("KnoxCure: Infection blocked - Immunobooster active")
        EHR.Dialogue.SayRandom(player, "That was close... good thing I took that booster.", 10)
        return true
    end

    return false
end

-- ============================================
-- TICK HANDLER (Immunity Enforcement, Side Effects & Migraines)
-- ============================================

local KNOX_TICK_INTERVAL = 60  -- Every ~2 seconds

-- MP: per-player tick state (avoid shared counters across players)
local tickStateByPlayer = {}

local function getPlayerId(player)
    if not player then return nil end
    local onlineId = nil
    pcall(function() onlineId = player:getOnlineID() end)
    if onlineId and onlineId >= 0 then
        return tostring(onlineId)
    end
    local username = nil
    pcall(function() username = player:getUsername() end)
    if username and username ~= "" then
        return username
    end
    local num = nil
    pcall(function() num = player:getPlayerNum() end)
    return tostring(num or "0")
end

local function getTickState(player)
    local id = getPlayerId(player) or "0"
    local state = tickStateByPlayer[id]
    if not state then
        state = { tick = 0 }
        tickStateByPlayer[id] = state
    end
    return state
end

local function getActivePlayers()
    local players = {}
    if isServer and isServer() and getOnlinePlayers then
        local online = getOnlinePlayers()
        if online then
            for i = 0, online:size() - 1 do
                local p = online:get(i)
                if p then
                    table.insert(players, p)
                end
            end
        end
    end

    if #players == 0 then
        local player = getSpecificPlayer(0)
        if player then
            table.insert(players, player)
        end
    end

    return players
end
local suppressionLoggedThisSession = false  -- Prevent log spam

--[[
    Suppress vanilla zombie infection for immune players
    Must run every tick to prevent vanilla from setting infection
]]--
local function SuppressVanillaInfection(player, data)
    if not player or not data then return end

    local bodyDamage = player:getBodyDamage()
    local stats = player:getStats()
    if not bodyDamage or not stats then return end

    -- Check if player should be immune
    local isImmune = data.geneTherapyImmune or EHR.KnoxCure.IsImmunoboosterActive(player)
    if not isImmune then
        suppressionLoggedThisSession = false  -- Reset when no longer immune
        data.knoxImmuneBlockedExposure = nil
        return
    end

    -- =====================================
    -- Suppress infection if immune player gets bitten
    -- =====================================

    -- Clear the boolean infection flag
    local wasInfected = false
    local success, infected = pcall(function() return bodyDamage:IsInfected() end)
    if success and infected then
        wasInfected = true
        pcall(function() bodyDamage:setInfected(false) end)
        pcall(function() bodyDamage:setInfectionTime(-1.0) end)
        pcall(function() bodyDamage:setInfectionMortalityDuration(-1.0) end)
    end

    -- Clear ZOMBIE_INFECTION stat
    if CharacterStat and CharacterStat.ZOMBIE_INFECTION then
        local statSuccess, level = pcall(function()
            return stats:get(CharacterStat.ZOMBIE_INFECTION)
        end)
        if statSuccess and level and level > 0 then
            wasInfected = true
            pcall(function() stats:set(CharacterStat.ZOMBIE_INFECTION, 0) end)
            pcall(function() bodyDamage:setInfectionTime(-1.0) end)
            pcall(function() bodyDamage:setInfectionMortalityDuration(-1.0) end)
        end
    end

    -- Clear ZOMBIE_FEVER stat
    if CharacterStat and CharacterStat.ZOMBIE_FEVER then
        local statSuccess, level = pcall(function()
            return stats:get(CharacterStat.ZOMBIE_FEVER)
        end)
        if statSuccess and level and level > 0 then
            pcall(function() stats:set(CharacterStat.ZOMBIE_FEVER, 0) end)
        end
    end

    if wasInfected then
        EHRKnoxForEachBodyPart(bodyDamage, function(bodyPart)
            EHRKnoxClearBodyPartInfectionMarkers(bodyPart)
            return false
        end)
    end

    -- Immunobooster must remove the Knox payload attached to bites, not the visible
    -- bite wound itself. Otherwise vanilla can restart Knox after the booster expires.
    local clearedBiteSource = EHRKnoxForEachBodyPart(bodyDamage, function(bodyPart)
        return EHRKnoxClearBiteSource(bodyPart)
    end)
    if clearedBiteSource then
        local firstBlockedExposure = data.knoxImmuneBlockedExposure ~= true
        data.knoxImmuneBlockedExposure = true
        if firstBlockedExposure then
            wasInfected = true
        end
        if firstBlockedExposure and bodyDamage.DamageUpdate then
            pcall(function() bodyDamage:DamageUpdate() end)
        end
    end

    -- Log ONCE when we first start blocking infection (prevents spam)
    if wasInfected and not suppressionLoggedThisSession then
        local immuneSource = data.geneTherapyImmune and "Gene Therapy immunity" or "Immunobooster"
        EHR.Log("KnoxCure: Blocking vanilla infection - " .. immuneSource .. " (this message will not repeat)")
        suppressionLoggedThisSession = true
    end
end

local function processPlayerTick(player)
    if not player then return end
    if not player:isAlive() then return end

    local data = EHR.KnoxCure.GetData(player)
    if not data then return end

    -- =====================================
    -- CRITICAL: Suppress infection EVERY TICK for immune players
    -- This must run before throttle to catch all infection attempts
    -- =====================================
    SuppressVanillaInfection(player, data)

    if data.geneTherapyImmune and not data.immunityTraitGranted then
        EHR.KnoxCure.GrantImmunityTrait(player, data)
    end

    -- Throttle for non-critical updates
    local state = getTickState(player)
    state.tick = state.tick + 1
    if state.tick < KNOX_TICK_INTERVAL then return end
    state.tick = 0

    -- Keeps EHR in sync with external Knox cure mods that clear vanilla infection
    -- state without touching EHR's cached disease/monitor data.
    EHR.KnoxCure.IsInfected(player)

    local currentHour = getGameTime():getWorldAgeHours()
    local stats = player:getStats()

    -- Gene Therapy survivor: random migraines
    if data.geneTherapySurvivor and stats then
        local config = EHR.KnoxCure.Config
        if ZombRand(1000) / 1000 < config.geneTherapyMigraineChance then
            if CharacterStat and CharacterStat.PAIN then
                local current = stats:get(CharacterStat.PAIN) or 0
                pcall(function() stats:set(CharacterStat.PAIN, math.min(0.7, current + 0.2)) end)
            end
            EHR.Dialogue.SayRandom(player, "*winces* Another migraine...", 20)
        end
    end

    -- Immunobooster active: maintain side effects
    if EHR.KnoxCure.IsImmunoboosterActive(player) and stats then
        -- Reduced stamina regen (simulated by slight endurance drain)
        if CharacterStat and CharacterStat.ENDURANCE then
            local current = stats:get(CharacterStat.ENDURANCE) or 1
            if current > 0.3 then
                pcall(function() stats:set(CharacterStat.ENDURANCE, current - 0.001) end)
            end
        end

        -- Mild persistent nausea
        if CharacterStat and CharacterStat.FOOD_SICKNESS then
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            if current < 0.2 then
                pcall(function() stats:set(CharacterStat.FOOD_SICKNESS, 0.2) end)
            end
        end
    end

    -- Check if immunity just wore off
    if data.immunoboosterActiveUntil > 0 and currentHour > data.immunoboosterActiveUntil then
        if data.immunoboosterActiveUntil > currentHour - 0.1 then  -- Just expired
            EHR.Dialogue.SayStageChange(player, "The booster's wearing off... I'm vulnerable again.")
        end
    end
end

function EHR.KnoxCure.OnTick()
    -- MP: server-authoritative processing, client-only suppression
    if isClient and isClient() and not (isServer and isServer()) then
        local player = getSpecificPlayer(0)
        if player and player:isAlive() then
            local data = EHR.KnoxCure.GetData(player)
            if data then
                SuppressVanillaInfection(player, data)
            end
        end
        return
    end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function EHR.KnoxCure.OnGameStart()
    EHR.Log("KnoxCure: Module started")

    local player = getSpecificPlayer(0)
    if player then
        EHR.KnoxCure.InitializePlayer(player)
    end
end

function EHR.KnoxCure.OnCreatePlayer(playerIndex, player)
    EHR.KnoxCure.InitializePlayer(player)
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events and not EHR.KnoxCure._eventsRegistered then
    EHR.KnoxCure._eventsRegistered = true

    Events.OnTick.Add(EHR.KnoxCure.OnTick)
    Events.OnGameStart.Add(EHR.KnoxCure.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.KnoxCure.OnCreatePlayer)

    EHR.Log("KnoxCure: Events registered")
end

EHR.Log("Knox Cure module loaded v1.1.0 (B42 compatible)")
