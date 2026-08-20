--[[
    Extensive Health Rework B42
    Blood Module

    Tracks blood volume based on body part damage.
    Average health of all body parts = blood percentage.

    I kept this as simple as possible - no fancy sync logic,
    just read the body parts and calculate blood from that.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Dialogue"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.Blood = {}

-- ============================================
-- EXTERNAL MOD API
-- Other mods can use these to interact with EHR
-- ============================================

-- Flag to temporarily allow all healing (for other mods curing Knox infection, etc.)
-- Set to true to bypass EHR's healing lock for one tick
EHR.Blood.AllowHealingOverride = false

-- Table of player IDs to skip healing control for (persistent)
-- Other mods can add player IDs here: EHR.Blood.SkipHealingControl["playerID"] = true
EHR.Blood.SkipHealingControl = {}

-- Check if Knox infection is disabled in sandbox settings
function EHR.Blood.IsKnoxInfectionDisabled()
    if SandboxVars and SandboxVars.ZombieLore then
        -- Transmission = 1 means "None" (no infection from bites/scratches)
        local transmission = SandboxVars.ZombieLore.Transmission
        if transmission == 1 then
            return true
        end
    end
    return false
end

-- Check if a body part has zombie infection (Knox virus)
function EHR.Blood.HasZombieInfection(bodyPart)
    if not bodyPart then return false end
    local success, result = pcall(function()
        return bodyPart:isInfectedWound()
    end)
    return success and result == true
end

-- Helper to safely get sandbox settings with fallback
function EHR.Blood.GetSetting(name, default)
    if SandboxVars and SandboxVars.ExtensiveHealthRework then
        local value = SandboxVars.ExtensiveHealthRework[name]
        if value ~= nil then
            return value
        end
    end
    return default
end

-- ============================================
-- WOUND TYPE BLOOD LOSS MULTIPLIERS
-- Realistic blood loss based on wound severity
-- ============================================

-- HIGH PRIORITY FIX: Cache body part max index to avoid recalculating every tick
-- This is computed once on first use and reused for ~10-15% performance improvement
local CACHED_BODY_PART_MAX = nil
local function getBodyPartMaxIndex()
    if CACHED_BODY_PART_MAX == nil then
        if BodyPartType and BodyPartType.ToIndex and BodyPartType.MAX then
            CACHED_BODY_PART_MAX = BodyPartType.ToIndex(BodyPartType.MAX) - 1
        else
            CACHED_BODY_PART_MAX = 0  -- Fallback
        end
    end
    return CACHED_BODY_PART_MAX
end

local function callBodyPartBoolean(part, methodName)
    if not part or not methodName or not part[methodName] then return false end
    local ok, value = pcall(function() return part[methodName](part) end)
    return ok and value == true
end

local function callBodyPartNumber(part, methodName, defaultValue)
    if not part or not methodName or not part[methodName] then return defaultValue or 0 end
    local ok, value = pcall(function() return part[methodName](part) end)
    if not ok then return defaultValue or 0 end
    return tonumber(value) or defaultValue or 0
end

function EHR.Blood.IsBodyPartBandaged(part)
    if not part then return false end
    if callBodyPartBoolean(part, "bandaged") then return true end
    if callBodyPartBoolean(part, "isBandaged") then return true end
    return callBodyPartNumber(part, "getBandageLife", 0) > 0
end

function EHR.Blood.IsBodyPartBleeding(part)
    if not part then return false end

    -- Vanilla can keep bleeding timers/flags alive after a bandage is applied.
    -- For EHR blood volume, a bandaged wound is no longer actively losing blood.
    if EHR.Blood.IsBodyPartBandaged(part) then
        return false
    end

    if callBodyPartBoolean(part, "bleeding") then
        return true
    end

    local bleedingTime = 0
    if part.getBleedingTime then
        pcall(function()
            bleedingTime = tonumber(part:getBleedingTime()) or 0
        end)
    end

    return bleedingTime > 0
end

-- Wound type determines how much blood is lost per damage point
-- Higher = more dangerous wound type
EHR.Blood.WoundTypeMultipliers = {
    scratch = 0.02,      -- Superficial, capillaries only (~10-20mL total)
    bite = 0.08,         -- Puncture wounds, moderate tissue damage
    cut = 0.12,          -- Clean laceration, controlled bleeding
    glass = 0.25,        -- Penetrating trauma, vessel damage
    bullet = 0.25,       -- Penetrating trauma, vessel damage
    deepWound = 0.40,    -- Major trauma, potential arterial damage
    bleeding = 0.15,     -- Generic bleeding flag (moderate)
    burn = 0.00,         -- Burns cauterize, no direct blood loss
}

-- Body part vascularity - how much blood flows through each area
-- Higher = more blood vessels = more blood loss
EHR.Blood.BodyPartMultipliers = {
    -- Critical areas (major arteries)
    ["Neck"] = 2.5,           -- Carotid/jugular
    ["Groin"] = 2.0,          -- Femoral artery proximity

    -- Torso (large vessels)
    ["Torso_Upper"] = 1.5,    -- Chest vessels
    ["Torso_Lower"] = 1.3,    -- Abdominal vessels

    -- Head (highly vascular scalp)
    ["Head"] = 1.4,

    -- Upper legs (femoral runs through)
    ["UpperLeg_L"] = 1.2,
    ["UpperLeg_R"] = 1.2,

    -- Arms (baseline)
    ["UpperArm_L"] = 1.0,
    ["UpperArm_R"] = 1.0,

    -- Forearms (smaller vessels)
    ["ForeArm_L"] = 0.7,
    ["ForeArm_R"] = 0.7,

    -- Lower legs (less vascular)
    ["LowerLeg_L"] = 0.6,
    ["LowerLeg_R"] = 0.6,

    -- Hands (small vessels, quick clotting)
    ["Hand_L"] = 0.4,
    ["Hand_R"] = 0.4,

    -- Feet (smallest vessels, furthest from heart)
    ["Foot_L"] = 0.3,
    ["Foot_R"] = 0.3,
}

-- Preserve the existing Neck value for scratches. More serious actively
-- bleeding neck wounds receive the same increase below and at the per-wound
-- cap, so the bonus is not silently erased by saturation.
local NECK_NON_SCRATCH_LOSS_SCALE = 1.4

-- Default multiplier for unknown body parts
EHR.Blood.DefaultBodyPartMultiplier = 0.8

--[[
    Get the wound type multiplier for a body part based on its wounds.
    Returns the HIGHEST multiplier (most severe wound type).
    @param part - BodyPart object
    @return number - Wound type multiplier (0.0 - 0.4)
]]--
function EHR.Blood.GetWoundTypeMultiplier(part)
    if not part then return 0 end

    local mult = EHR.Blood.WoundTypeMultipliers
    local highest = 0

    -- Check each wound type (most severe first for early exit optimization)
    local hasDeepWound = false
    local hasBullet = false
    local hasCut = false
    local hasBite = false
    local hasScratch = false
    local isBleeding = false
    local hasGlass = false
    local hasBurn = false

    -- Safely check wound types with pcall
    hasDeepWound = callBodyPartBoolean(part, "isDeepWounded") or callBodyPartBoolean(part, "deepWounded")
    hasBullet = callBodyPartBoolean(part, "haveBullet")
    hasCut = callBodyPartBoolean(part, "isCut")
    hasBite = callBodyPartBoolean(part, "bitten")
    hasScratch = callBodyPartBoolean(part, "scratched")
    isBleeding = EHR.Blood.IsBodyPartBleeding(part)
    hasGlass = callBodyPartBoolean(part, "haveGlass")
    hasBurn = callBodyPartBoolean(part, "isBurnt")

    -- Return highest applicable multiplier
    if hasDeepWound then
        highest = math.max(highest, mult.deepWound)
    end
    if hasBullet then
        highest = math.max(highest, mult.bullet)
    end
    if hasGlass then
        highest = math.max(highest, mult.glass)
    end
    if hasCut then
        highest = math.max(highest, mult.cut)
    end
    if hasBite then
        highest = math.max(highest, mult.bite)
    end
    if hasScratch then
        highest = math.max(highest, mult.scratch)
    end
    -- Generic bleeding flag as fallback (if bleeding but no specific wound type)
    if isBleeding and highest == 0 then
        highest = mult.bleeding
    end
    -- Burns don't cause blood loss (they cauterize)
    -- hasBurn is checked but contributes 0

    return highest
end

--[[
    Get the body part vascularity multiplier.
    @param partType - BodyPartType enum value
    @return number - Body part multiplier (0.3 - 2.5)
]]--
function EHR.Blood.GetBodyPartMultiplier(partType)
    if not partType then return EHR.Blood.DefaultBodyPartMultiplier end

    local partName = tostring(partType)
    return EHR.Blood.BodyPartMultipliers[partName] or EHR.Blood.DefaultBodyPartMultiplier
end

-- Blood type compatibility for transfusions
-- Standard ABO/Rh system
EHR.Blood.Compatibility = {
    ["O-"]  = {"O-"},
    ["O+"]  = {"O-", "O+"},
    ["A-"]  = {"O-", "A-"},
    ["A+"]  = {"O-", "O+", "A-", "A+"},
    ["B-"]  = {"O-", "B-"},
    ["B+"]  = {"O-", "O+", "B-", "B+"},
    ["AB-"] = {"O-", "A-", "B-", "AB-"},
    ["AB+"] = {"O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"},
}

-- Track how many times we've updated (for debug throttling)
local updateCount = 0

-- Blackout state tracking (not configurable)
EHR.Blood.blackoutData = {}

-- Blackout settings
EHR.Blood.BLACKOUT_SLEEP_HOURS = 1    -- Force sleep for 1 in-game hour
EHR.Blood.BLACKOUT_COOLDOWN_HOURS = 24  -- 24 in-game hours between blackouts

-- Blood transfusion constants
EHR.Blood.TRANSFUSION_AMOUNT = 500   -- mL per blood bag
EHR.Blood.SALINE_AMOUNT = 250        -- mL per saline bag
EHR.Blood.TRANSFUSION_DECAY_RATE = 0.5  -- mL lost per tick (transfused blood gets processed)
EHR.Blood.HEMODILUTION_THRESHOLD = 0.60  -- 60% saline = death from oxygen deprivation
EHR.Blood.HEMODILUTION_WARNING = 0.40    -- 40% saline = warning symptoms start

-- Map item types to blood types
EHR.Blood.BloodBagTypes = {
    ["ExtensiveHealth.BloodBagONeg"] = "O-",
    ["ExtensiveHealth.BloodBagOPos"] = "O+",
    ["ExtensiveHealth.BloodBagANeg"] = "A-",
    ["ExtensiveHealth.BloodBagAPos"] = "A+",
    ["ExtensiveHealth.BloodBagBNeg"] = "B-",
    ["ExtensiveHealth.BloodBagBPos"] = "B+",
    ["ExtensiveHealth.BloodBagABNeg"] = "AB-",
    ["ExtensiveHealth.BloodBagABPos"] = "AB+",
}

-- Get configurable values from sandbox (with defaults)
function EHR.Blood.GetLossMultiplier()
    return EHR.Blood.GetSetting("BloodLossMultiplier", 2.0)
end

function EHR.Blood.GetBlackoutCooldown()
    return EHR.Blood.GetSetting("BlackoutCooldownHours", 1.0)
end

function EHR.Blood.GetBlackoutChance()
    return EHR.Blood.GetSetting("BlackoutChance", 50)
end

function EHR.Blood.IsBlackoutEnabled()
    return EHR.Blood.GetSetting("BlackoutEnabled", true)
end

function EHR.Blood.GetThresholds()
    return {
        healthy = EHR.Blood.GetSetting("BloodThresholdHealthy", 85) / 100,
        mild = EHR.Blood.GetSetting("BloodThresholdMild", 80) / 100,
        moderate = EHR.Blood.GetSetting("BloodThresholdModerate", 70) / 100,
    }
end

-- Blood regeneration sandbox getters (v2.7.0+)
function EHR.Blood.IsRegenEnabled()
    return EHR.Blood.GetSetting("BloodRegenEnabled", true)
end

function EHR.Blood.GetRegenDelayHours()
    return EHR.Blood.GetSetting("BloodRegenDelayHours", 2.0)
end

function EHR.Blood.GetRegenRatePerHour()
    return EHR.Blood.GetSetting("BloodRegenRatePerHour", 50)
end

function EHR.Blood.GetRegenMinimumPercent()
    return EHR.Blood.GetSetting("BloodRegenMinimumPercent", 30) / 100
end

-- Get current in-game hour
function EHR.Blood.GetGameHour()
    local gameTime = getGameTime()
    if gameTime then
        return gameTime:getWorldAgeHours()
    end
    return 0
end

-- ============================================
-- v2.7.0+ CUMULATIVE BLOOD SYSTEM
-- Blood is now tracked cumulatively, not recalculated from wounds
-- ============================================

--[[
    Migrate old save data to v2.7.0+ format (CRIT-001 fix)
    @param data - Player modData
    @param player - Player object (needed to check actual wound state)
]]--
function EHR.Blood.MigrateData(data, player)
    if not data.EHR_Blood then return end

    -- Check if already migrated (lastBleedTime is a new v2.7.0 field)
    if data.EHR_Blood.lastBleedTime ~= nil then return end

    local currentHour = EHR.Blood.GetGameHour()

    -- Initialize with safe defaults (prevents instant regen exploit)
    data.EHR_Blood.lastBleedTime = currentHour
    data.EHR_Blood.lastRegenHour = currentHour
    data.EHR_Blood.lossAccumulator = 0

    -- Check actual bleeding state from body parts (CRIT-001 fix)
    local isAnyBleeding = false
    if player then
        local bodyDamage = player:getBodyDamage()
        if bodyDamage and BodyPartType and BodyPartType.ToIndex then
            for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
                local partType = BodyPartType.FromIndex(i)
                if partType then
                    local part = bodyDamage:getBodyPart(partType)
                    if part then
                        if EHR.Blood.IsBodyPartBleeding(part) then
                            isAnyBleeding = true
                            break
                        end
                    end
                end
            end
        end
    end
    data.EHR_Blood.isCurrentlyBleeding = isAnyBleeding

    EHR.Log("Blood: Migrated save data to v2.7.0 format (bleeding=" .. tostring(isAnyBleeding) .. ")")
end

--[[
    Set blood volume to exact value (API for debug, spawn, etc.)
    @param player - Player object
    @param newVolume - New blood volume in mL
    @return boolean - Success
]]--
function EHR.Blood.SetBloodVolume(player, newVolume)
    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then return false end

    local maxBlood = data.EHR_Blood.maxVolume or 5000
    data.EHR_Blood.currentVolume = math.max(0, math.min(maxBlood, newVolume))
    EHR.Log(string.format("Blood: SetBloodVolume to %.0f mL", data.EHR_Blood.currentVolume))
    return true
end

--[[
    Modify blood volume by delta (API for transfusions, diseases, etc.)
    @param player - Player object
    @param delta - Amount to add (positive) or remove (negative) in mL
    @return boolean - Success
]]--
function EHR.Blood.ModifyBloodVolume(player, delta)
    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then
        if EHR.DEBUG then print("[EHR BLOOD DEBUG] ModifyBloodVolume: No player data!") end
        return false
    end

    local maxBlood = data.EHR_Blood.maxVolume or 5000
    local oldVolume = data.EHR_Blood.currentVolume or 0
    local newVolume = oldVolume + delta
    data.EHR_Blood.currentVolume = math.max(0, math.min(maxBlood, newVolume))

    if EHR.DEBUG then
        print(string.format("[EHR BLOOD DEBUG] ModifyBloodVolume: %d + %d = %d (clamped to %d)",
            oldVolume, delta, newVolume, data.EHR_Blood.currentVolume))
    end
    EHR.Log(string.format("Blood: ModifyBloodVolume by %+.0f mL (now %.0f mL)", delta, data.EHR_Blood.currentVolume))
    return true
end

--[[
    Apply blood regeneration (CRIT-002 fix: uses elapsed in-game hours)
    Called from UpdateBloodVolume when conditions are met
    @param player - Player object
    @param data - Player modData
    @param currentHour - Current game hour
]]--
function EHR.Blood.ApplyBloodRegeneration(player, data, currentHour)
    -- Check if regen is enabled in sandbox
    if not EHR.Blood.IsRegenEnabled() then return end

    -- Can't regen if currently bleeding
    if data.EHR_Blood.isCurrentlyBleeding then return end

    local maxBlood = data.EHR_Blood.maxVolume or 5000
    local currentPercent = data.EHR_Blood.currentVolume / maxBlood

    -- Already at max?
    if data.EHR_Blood.currentVolume >= maxBlood then
        data.EHR_Blood.lastRegenHour = currentHour  -- Keep time updated
        return
    end

    -- Check minimum threshold (need transfusion first if too low)
    local minPercent = EHR.Blood.GetRegenMinimumPercent()
    if currentPercent < minPercent then
        return  -- Too low - body can't regenerate
    end

    -- Check delay (hours since last bleed)
    local delayHours = EHR.Blood.GetRegenDelayHours()
    local lastBleedTime = data.EHR_Blood.lastBleedTime or 0
    local hoursSinceBleed = currentHour - lastBleedTime
    if hoursSinceBleed < delayHours then return end

    -- Calculate elapsed in-game time since last regen (CRIT-002 fix)
    local lastRegenHour = data.EHR_Blood.lastRegenHour or currentHour
    local elapsedHours = currentHour - lastRegenHour

    -- Prevent negative time (game time reset, MP desync, etc.)
    if elapsedHours <= 0 then
        data.EHR_Blood.lastRegenHour = currentHour
        return
    end

    -- Cap elapsed time to prevent huge jumps (e.g., after long sleep)
    elapsedHours = math.min(elapsedHours, 1.0)  -- Max 1 hour per update

    -- Calculate regen amount based on elapsed in-game hours
    local baseRate = EHR.Blood.GetRegenRatePerHour()

    -- Bonus for being well-fed and hydrated
    local bonus = 1.0
    local canHeal, _ = EHR.Blood.CanHeal(player)
    if canHeal then
        bonus = 1.5  -- 50% faster when conditions are good
    end

    local regenAmount = baseRate * bonus * elapsedHours

    -- Apply regeneration
    local oldVolume = data.EHR_Blood.currentVolume
    data.EHR_Blood.currentVolume = math.min(maxBlood, oldVolume + regenAmount)

    -- Update last regen time
    data.EHR_Blood.lastRegenHour = currentHour

    if EHR.DEBUG and regenAmount > 0.1 then
        EHR.Log(string.format("Blood Regen: +%.1f mL (%.1f rate * %.2f bonus * %.3f hours)",
            regenAmount, baseRate, bonus, elapsedHours))
    end
end

--[[
    Process transfusion decay (MED-003 fix: works with cumulative model)
    Saline decay reduces the dilution marker; blood volume stays restored.
    @param player - Player object
    @param data - Player modData
]]--
function EHR.Blood.ProcessTransfusionDecay(player, data)
    if not data.EHR_Blood then return end

    -- Initialize trackers if needed
    if data.EHR_Blood.transfusedBlood == nil then
        data.EHR_Blood.transfusedBlood = 0
    end
    if data.EHR_Blood.transfusedSaline == nil then
        data.EHR_Blood.transfusedSaline = 0
    end

    -- Decay transfused blood marker (for compatibility tracking)
    if data.EHR_Blood.transfusedBlood > 0 then
        data.EHR_Blood.transfusedBlood = math.max(0,
            data.EHR_Blood.transfusedBlood - EHR.Blood.TRANSFUSION_DECAY_RATE)
    end

    -- Decay saline tracker only (for hemodilution ratio calculation)
    -- v2.7.1 FIX: Volume is NOT reduced - kidneys excrete excess fluid without reducing blood volume
    -- This makes saline therapeutically useful while still tracking dilution for hemodilution mechanic
    if data.EHR_Blood.transfusedSaline > 0 then
        local decayAmount = math.min(data.EHR_Blood.transfusedSaline, EHR.Blood.TRANSFUSION_DECAY_RATE)
        data.EHR_Blood.transfusedSaline = data.EHR_Blood.transfusedSaline - decayAmount
        -- NOTE: Volume intentionally NOT reduced here
        -- Saline provides lasting volume expansion (medically accurate)
        -- Hemodilution ratio still calculated correctly from transfusedSaline/currentVolume
    end

    -- Recalculate hemodilution ratio
    local currentVolume = data.EHR_Blood.currentVolume
    if currentVolume > 0 and data.EHR_Blood.transfusedSaline > 0 then
        data.EHR_Blood.salineRatio = data.EHR_Blood.transfusedSaline / currentVolume
    else
        data.EHR_Blood.salineRatio = 0
    end
end

--[[
    Update blood volume - called every ~1 second from EHR_Main

    v2.7.0+ CUMULATIVE TRACKING:
    Blood is now tracked cumulatively - we SUBTRACT loss from current volume
    instead of recalculating from wounds. This fixes:
    - Bandaging no longer "restores" blood
    - Debug changes persist
    - Transfusions work properly

    Blood regeneration happens naturally when:
    - No active bleeding for [delay] hours
    - Blood above [minimum] threshold
    - Rate increased when fed/hydrated
]]--
function EHR.Blood.UpdateBloodVolume(player, data)
    if not data.EHR_Blood then return end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then return end

    -- Migrate old saves to v2.7.0+ format (CRIT-001 fix: checks actual wound state)
    EHR.Blood.MigrateData(data, player)

    updateCount = updateCount + 1
    local currentHour = EHR.Blood.GetGameHour()
    local maxBlood = data.EHR_Blood.maxVolume or 5000

    -- ============================================
    -- CUMULATIVE BLOOD LOSS CALCULATION
    -- Only ACTIVELY BLEEDING wounds drain blood
    -- Blood loss is SUBTRACTED from current volume
    -- ============================================

    local bloodLossThisTick = 0  -- mL to subtract this tick
    local isAnyBleeding = false
    local bleedingParts = 0

    -- Loop through all body part types (HIGH PRIORITY FIX: use cached max index)
    local maxIndex = getBodyPartMaxIndex()
    if maxIndex > 0 then
        for i = 0, maxIndex do
            local partType = BodyPartType.FromIndex(i)
            if partType then
                local part = bodyDamage:getBodyPart(partType)
                if part then
                    -- Check if this part is ACTIVELY BLEEDING (MED-001 fix: proper nil guard)
                    if EHR.Blood.IsBodyPartBleeding(part) then
                        isAnyBleeding = true
                        bleedingParts = bleedingParts + 1

                        -- Get wound severity and body part vascularity
                        local health = 100
                        pcall(function() health = part:getHealth() or 100 end)
                        local damage = math.max(0, 100 - health)

                        local woundMultiplier = EHR.Blood.GetWoundTypeMultiplier(part)
                        local bodyPartMultiplier = EHR.Blood.GetBodyPartMultiplier(partType)
                        local maxLossPerWound = 5.0

                        -- GetWoundTypeMultiplier already resolves mixed wound flags
                        -- to the dominant (highest) type. A pure scratch therefore
                        -- stays at the original Neck multiplier, while a scratch plus
                        -- any more serious wound follows the non-scratch path.
                        local isNeckNonScratch = tostring(partType) == "Neck"
                            and woundMultiplier > EHR.Blood.WoundTypeMultipliers.scratch
                        if isNeckNonScratch then
                            bodyPartMultiplier = bodyPartMultiplier * NECK_NON_SCRATCH_LOSS_SCALE
                            maxLossPerWound = maxLossPerWound * NECK_NON_SCRATCH_LOSS_SCALE
                        end

                        -- Calculate blood loss for this part (mL per tick)
                        -- Scale factor: 0.5 for meaningful blood loss rates
                        -- Example: 50 damage deep wound on neck = 50 * 0.40 * 2.5 * 0.5 = 25 mL/tick
                        -- Example: 30 damage scratch on hand = 30 * 0.02 * 0.4 * 0.5 = 0.12 mL/tick
                        local partLoss = damage * woundMultiplier * bodyPartMultiplier * 0.5

                        -- v2.7.2: Cap per-wound blood loss to prevent extreme bleed rates
                        -- Base maximum is 5 mL per update; serious neck wounds use
                        -- the same 1.4 scale as their vascularity multiplier.
                        -- Medically realistic: even severe wounds have limited flow
                        if partLoss > maxLossPerWound then
                            partLoss = maxLossPerWound
                        end

                        bloodLossThisTick = bloodLossThisTick + partLoss

                        -- Debug logging for wound calculation
                        if EHR.DEBUG and updateCount % 30 == 0 then
                            EHR.Log(string.format("  %s: dmg=%.0f, wound=%.2f, body=%.1f, loss=%.2f mL/tick",
                                tostring(partType), damage, woundMultiplier, bodyPartMultiplier, partLoss))
                        end
                    end
                end
            end
        end
    end

    -- Apply sandbox multiplier
    local sandboxMultiplier = EHR.Blood.GetLossMultiplier()
    bloodLossThisTick = bloodLossThisTick * sandboxMultiplier

    -- Track bleeding state
    data.EHR_Blood.isCurrentlyBleeding = isAnyBleeding
    if isAnyBleeding then
        data.EHR_Blood.lastBleedTime = currentHour
    end

    -- Store old volume for loss rate display
    local oldVolume = data.EHR_Blood.currentVolume or maxBlood

    -- SUBTRACT blood loss from current volume (cumulative tracking!)
    if bloodLossThisTick > 0 then
        -- v2.7.2 FIX: When bleeding, also lose saline proportionally
        -- Saline is mixed in the blood, so blood loss includes some saline
        local currentSaline = data.EHR_Blood.transfusedSaline or 0
        local currentVol = data.EHR_Blood.currentVolume or 5000

        if currentSaline > 0 and currentVol > 0 then
            -- Calculate what fraction of current volume is saline
            local salineRatio = currentSaline / currentVol
            -- Lose saline proportionally to blood loss
            local salineLoss = bloodLossThisTick * salineRatio
            data.EHR_Blood.transfusedSaline = math.max(0, currentSaline - salineLoss)

            if EHR.DEBUG and updateCount % 30 == 0 then
                EHR.Log(string.format("Blood loss: %.2f mL total, %.2f mL saline (%.1f%% ratio)",
                    bloodLossThisTick, salineLoss, salineRatio * 100))
            end
        end

        data.EHR_Blood.currentVolume = math.max(0, data.EHR_Blood.currentVolume - bloodLossThisTick)
    end

    -- Process transfusion decay (MED-003 fix: works with cumulative model)
    EHR.Blood.ProcessTransfusionDecay(player, data)

    -- Check for hemodilution (too much saline dilutes blood)
    local currentVolume = data.EHR_Blood.currentVolume
    if currentVolume > 0 and data.EHR_Blood.transfusedSaline and data.EHR_Blood.transfusedSaline > 0 then
        local salineRatio = data.EHR_Blood.transfusedSaline / currentVolume
        data.EHR_Blood.salineRatio = salineRatio

        if salineRatio >= EHR.Blood.HEMODILUTION_THRESHOLD then
            EHR.Blood.ApplyHemodilutionDeath(player, salineRatio)
        elseif salineRatio >= EHR.Blood.HEMODILUTION_WARNING then
            EHR.Blood.ApplyHemodilutionWarning(player, salineRatio)
        end
    else
        data.EHR_Blood.salineRatio = 0
    end

    -- Apply blood regeneration (when conditions are met)
    EHR.Blood.ApplyBloodRegeneration(player, data, currentHour)

    -- Calculate loss rate for display (mL per minute, approximate)
    local newVolume = data.EHR_Blood.currentVolume
    if oldVolume ~= newVolume then
        data.EHR_Blood.lossRate = (oldVolume - newVolume) * 60  -- per minute estimate
    else
        data.EHR_Blood.lossRate = 0
    end

    -- Debug output every 5 updates (~5 seconds)
    if EHR.DEBUG and updateCount % 5 == 0 then
        local bloodPercent = (newVolume / maxBlood) * 100
        local status = isAnyBleeding and "BLEEDING" or "stable"
        EHR.Log(string.format("Blood: %.0f/%.0f mL (%.1f%%) - %s from %d parts, loss=%.2f mL/tick",
            newVolume, maxBlood, bloodPercent, status, bleedingParts, bloodLossThisTick))

        -- Show regen status if not bleeding
        if not isAnyBleeding and EHR.Blood.IsRegenEnabled() then
            local hoursSinceBleed = currentHour - (data.EHR_Blood.lastBleedTime or 0)
            local delayHours = EHR.Blood.GetRegenDelayHours()
            if hoursSinceBleed >= delayHours then
                EHR.Log(string.format("  Regen active (%.1f hrs since bleed)", hoursSinceBleed))
            else
                EHR.Log(string.format("  Regen waiting (%.1f/%.1f hrs)", hoursSinceBleed, delayHours))
            end
        end
    end
end

--[[
    Apply debuffs based on blood level

    Stages:
    - 85-100%: Healthy
    - 80-85%: Mild fatigue
    - 70-80%: Moderate fatigue, dizziness
    - <70%: Critical - blackouts, death imminent
]]--

-- Blood stage thresholds (values are constants, thresholds are configurable)
EHR.Blood.Stages = {
    HEALTHY = 4,
    MILD = 3,
    MODERATE = 2,
    CRITICAL = 1,
}

-- Dialogue for entering each stage (said once when crossing threshold)
-- Uses getText() for localization support
function EHR.Blood.GetStageDialogue(stage)
    local keys = {
        [3] = "UI_EHR_Dialogue_Blood_Stage3",
        [2] = "UI_EHR_Dialogue_Blood_Stage2",
        [1] = "UI_EHR_Dialogue_Blood_Stage1",
    }
    local key = keys[stage]
    if key then
        return getText(key)
    end
    return nil
end

-- Legacy table for compatibility (uses runtime getText)
EHR.Blood.StageDialogue = setmetatable({}, {
    __index = function(_, stage)
        return EHR.Blood.GetStageDialogue(stage)
    end
})

-- Get current blood stage from percentage (uses sandbox thresholds)
function EHR.Blood.GetStage(bloodPercent)
    local t = EHR.Blood.GetThresholds()
    if bloodPercent >= t.healthy then return EHR.Blood.Stages.HEALTHY end
    if bloodPercent >= t.mild then return EHR.Blood.Stages.MILD end
    if bloodPercent >= t.moderate then return EHR.Blood.Stages.MODERATE end
    return EHR.Blood.Stages.CRITICAL
end

-- Check if player can blackout (cooldown check)
function EHR.Blood.CanBlackout(player)
    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    EHR.Blood.blackoutData = EHR.Blood.blackoutData or {}
    local blackout = EHR.Blood.blackoutData[playerID] or {}

    if blackout.lastBlackoutHour then
        local currentHour = EHR.Blood.GetGameHour()
        local hoursSince = currentHour - blackout.lastBlackoutHour
        if hoursSince < EHR.Blood.BLACKOUT_COOLDOWN_HOURS then
            return false, hoursSince
        end
    end
    return true, 0
end

-- Trigger a blackout - forces player to sleep for 1 hour
function EHR.Blood.TriggerBlackout(player, data)
    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    EHR.Blood.blackoutData = EHR.Blood.blackoutData or {}
    EHR.Blood.blackoutData[playerID] = EHR.Blood.blackoutData[playerID] or {}

    local blackout = EHR.Blood.blackoutData[playerID]
    local currentHour = EHR.Blood.GetGameHour()

    -- Record blackout time for cooldown and track that we're in blackout sleep
    blackout.lastBlackoutHour = currentHour
    blackout.inBlackoutSleep = true
    EHR.Blood.blackoutData[playerID] = blackout

    -- Show message (critical - always say unless dialogue off)
    EHR.Dialogue.SayCritical(player, getText("UI_EHR_Dialogue_Blackout_Start"))

    -- Calculate wake up time (current time of day + sleep hours)
    local timeOfDay = GameTime.getInstance():getTimeOfDay()
    local wakeUpTime = timeOfDay + EHR.Blood.BLACKOUT_SLEEP_HOURS
    if wakeUpTime >= 24 then
        wakeUpTime = wakeUpTime - 24
    end

    -- Max out fatigue to ensure sleep happens
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.FATIGUE then
        pcall(function() stats:set(CharacterStat.FATIGUE, 1) end)
    end

    -- Use the proper sleep system (same as ISSleepDialog)
    player:setForceWakeUpTime(wakeUpTime)
    player:setAsleepTime(0.0)
    player:setAsleep(true)

    -- Trigger the sleeping event for time progression
    local sleepingEvent = getSleepingEvent()
    if sleepingEvent and sleepingEvent.setPlayerFallAsleep then
        sleepingEvent:setPlayerFallAsleep(player, EHR.Blood.BLACKOUT_SLEEP_HOURS)
    end

    -- Fade to black
    local playerNum = player:getPlayerNum()
    UIManager.setFadeBeforeUI(playerNum, true)
    UIManager.FadeOut(playerNum, 1)

    EHR.Log(string.format("BLACKOUT TRIGGERED - forced sleep for %d hour(s), wake at %.1f, next blackout possible in %d hours",
        EHR.Blood.BLACKOUT_SLEEP_HOURS, wakeUpTime, EHR.Blood.BLACKOUT_COOLDOWN_HOURS))
end

local function EHR_BloodIsBetaBlockerActive(player)
    if not player then return false end

    if EHR.Medication and EHR.Medication.IsBetaBlockerActive then
        local ok, active = pcall(EHR.Medication.IsBetaBlockerActive, player)
        if ok then return active == true end
    end

    local modData = player:getModData()
    return modData and modData.EHR_BetaBlockerActive == true
end

function EHR.Blood.ApplyEffects(player, data)
    -- Safety check: ensure blood data exists (can be nil after reset)
    if not data or not data.EHR_Blood then return end

    -- Check if player just woke up from blackout sleep
    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    EHR.Blood.blackoutData = EHR.Blood.blackoutData or {}
    local blackout = EHR.Blood.blackoutData[playerID]

    if blackout and blackout.inBlackoutSleep and not player:isAsleep() then
        -- Player just woke up from blackout - halve their fatigue
        blackout.inBlackoutSleep = false
        EHR.Blood.blackoutData[playerID] = blackout

        local stats = player:getStats()
        if stats and CharacterStat and CharacterStat.FATIGUE then
            local currentFatigue = stats:get(CharacterStat.FATIGUE) or 0
            local newFatigue = currentFatigue / 2
            stats:set(CharacterStat.FATIGUE, newFatigue)
            EHR.Log(string.format("Blackout wake-up: Fatigue halved from %.2f to %.2f", currentFatigue, newFatigue))
        end

        EHR.Dialogue.SayCritical(player, getText("UI_EHR_Dialogue_Blackout_Wake"))
    end

    local bloodPercent = data.EHR_Blood.currentVolume / data.EHR_Blood.maxVolume
    local betaBlockerActive = EHR_BloodIsBetaBlockerActive(player)
    local functionalBloodPercent = bloodPercent
    if betaBlockerActive and bloodPercent < 0.90 then
        -- Beta blockers do not make wounds bleed faster. They blunt the
        -- cardiovascular compensation for hypovolemia, so low blood volume
        -- produces weakness and blackout risk about five percentage points sooner.
        functionalBloodPercent = math.max(0, bloodPercent - 0.05)
    end
    local stats = player:getStats()

    if not stats then return end

    -- Get current stage
    local actualStage = EHR.Blood.GetStage(bloodPercent)
    local currentStage = EHR.Blood.GetStage(functionalBloodPercent)
    local betaStageShifted = betaBlockerActive and currentStage < actualStage
    if betaStageShifted then
        data.EHR_Blood.betaBlockerStageShifted = true
    elseif data.EHR_Blood.betaBlockerStageShifted then
        -- Restore the movement modifier when a temporary beta-blocker stage
        -- shift ends (including after a transfusion during the active dose).
        data.EHR_Blood.betaBlockerStageShifted = nil
        if player.setSpeedMod then
            if actualStage == EHR.Blood.Stages.CRITICAL then
                player:setSpeedMod(0.5)
            elseif actualStage == EHR.Blood.Stages.MODERATE then
                player:setSpeedMod(0.8)
            else
                player:setSpeedMod(1.0)
            end
        end
    end

    -- Check for stage transition (trigger dialogue once per stage)
    local lastStage = data.EHR_Blood.lastStage or EHR.Blood.Stages.HEALTHY
    if currentStage < lastStage then
        -- Blood dropped to a new stage - say dialogue
        local dialogue = EHR.Blood.StageDialogue[currentStage]
        if dialogue then
            EHR.Dialogue.SayStageChange(player, dialogue)
        end
        if betaBlockerActive then
            EHR.Log(string.format(
                "Blood stage changed: %d -> %d (actual %.1f%%, beta-blocked functional %.1f%%)",
                lastStage, currentStage, bloodPercent * 100, functionalBloodPercent * 100
            ))
        else
            EHR.Log(string.format("Blood stage changed: %d -> %d (%.1f%%)", lastStage, currentStage, bloodPercent * 100))
        end
    end
    data.EHR_Blood.lastStage = currentStage

    -- Stage 1: Healthy (85%+) - no effects
    -- (nothing to do here)

    -- Stage 2: Mild (80-85%)
    if currentStage == EHR.Blood.Stages.MILD then
        if stats.setEndurance then
            local current = stats:getEndurance() or 1
            stats:setEndurance(math.max(0, current - 0.1))
        end
    end

    -- Stage 3: Moderate (70-80%)
    if currentStage == EHR.Blood.Stages.MODERATE then
        if stats.setEndurance then
            local current = stats:getEndurance() or 1
            stats:setEndurance(math.max(0, current - 0.25))
        end
        -- Slow movement slightly
        if player.setSpeedMod then
            player:setSpeedMod(0.8)
        end
        -- Random dizzy message (affected by dialogue frequency)
        EHR.Dialogue.SayRandom(player, getText("UI_EHR_Dialogue_Blood_Lightheaded"), 400)
    end

    -- Stage 4: Critical (<70%) - blackouts, death imminent
    if currentStage == EHR.Blood.Stages.CRITICAL then
        if stats.setEndurance then
            stats:setEndurance(0)
        end
        -- Slow movement significantly
        if player.setSpeedMod then
            player:setSpeedMod(0.5)
        end

        -- Check if blackouts are enabled in sandbox
        if not EHR.Blood.IsBlackoutEnabled() then
            EHR.Dialogue.SayRandom(player, getText("UI_EHR_Dialogue_Blood_Unconscious"), 100)
            return
        end

        -- Check 24-hour cooldown
        local canBlackout, hoursSince = EHR.Blood.CanBlackout(player)

        -- Adrenaline can prevent a blackout unless beta blockade suppresses
        -- that compensatory cardiovascular response.
        if canBlackout and CharacterStat and not betaBlockerActive then
            local panic = 0
            local stress = 0
            if CharacterStat.PANIC then
                pcall(function() panic = stats:get(CharacterStat.PANIC) or 0 end)
            end
            if CharacterStat.STRESS then
                pcall(function() stress = stats:get(CharacterStat.STRESS) or 0 end)
            end
            if panic > 0.5 or stress > 0.5 then
                canBlackout = false
            end
        end

        if canBlackout then
            -- Random blackout chance (configurable)
            local blackoutChance = EHR.Blood.GetBlackoutChance()
            if ZombRand(blackoutChance) < 1 then
                -- Force sleep for 1 hour
                EHR.Blood.TriggerBlackout(player, data)
                return
            end
        end

        -- Dizzy messages when not blacking out (affected by dialogue frequency)
        EHR.Dialogue.SayRandom(player, getText("UI_EHR_Dialogue_Blood_Unconscious"), 100)
    end

    -- LETHAL blood loss checks (below 20%)
    if bloodPercent < 0.20 then
        local bodyDamage = player:getBodyDamage()
        if bodyDamage then
            if bloodPercent <= 0.05 then
                -- Below 5%: Immediate death (critical - always say)
                EHR.Dialogue.SayCritical(player, getText("UI_EHR_Dialogue_Blood_Collapse"))
                EHR.Log("DEATH: Blood volume critical (< 5%) - immediate death")
                if EHR.RecordDeathCause then
                    EHR.RecordDeathCause(player, "Exsanguination (total blood loss)")
                end
                bodyDamage:setOverallBodyHealth(0)
            else
                -- Below 20%: High death chance per tick (1 in 50)
                if ZombRand(50) < 1 then
                    EHR.Dialogue.SayCritical(player, getText("UI_EHR_Dialogue_Blood_HeartStops"))
                    EHR.Log("DEATH: Blood volume critical (< 20%) - cardiac arrest")
                    if EHR.RecordDeathCause then
                        EHR.RecordDeathCause(player, "Hypovolemic shock")
                    end
                    bodyDamage:setOverallBodyHealth(0)
                end
            end
        end
    end
end

--[[
    Check if blood types are compatible
]]--
function EHR.Blood.IsCompatible(donorType, recipientType)
    local compatible = EHR.Blood.Compatibility[recipientType]
    if not compatible then return false end

    for _, t in ipairs(compatible) do
        if t == donorType then
            return true
        end
    end
    return false
end

--[[
    Get blood percentage (0-100)
]]--
function EHR.Blood.GetPercent(player)
    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then return 100 end
    return (data.EHR_Blood.currentVolume / data.EHR_Blood.maxVolume) * 100
end

--[[
    Get player's blood type (assigned randomly on first call)
    MEDIUM FIX: Delegates to EHR.GenerateBloodType() to ensure consistent distribution
    WARNING: Do NOT change blood type distribution - this affects existing saves!
]]--
function EHR.Blood.GetPlayerBloodType(player)
    local data = EHR.GetPlayerData(player)
    if (not data or not data.EHR_Blood) and EHR.InitializePlayer then
        pcall(function() EHR.InitializePlayer(player) end)
        data = EHR.GetPlayerData(player)
    end

    if not data or not data.EHR_Blood then return nil end
    if data.EHR_Blood.bloodType == "PENDING" then return nil end

    -- Assign blood type if not set - use the centralized function for consistency
    if not data.EHR_Blood.bloodType then
        -- Use the main EHR.GenerateBloodType() for consistent distribution
        if EHR.GenerateBloodType then
            data.EHR_Blood.bloodType = EHR.GenerateBloodType()
        else
            return nil
        end
        EHR.Log("Assigned blood type: " .. data.EHR_Blood.bloodType)
    end

    return data.EHR_Blood.bloodType
end

--[[
    Use a blood bag - checks compatibility and adds blood
    Returns: success, message
]]--
function EHR.Blood.UseBloodBag(player, item)
    if not player or not item then return false, "Invalid parameters" end

    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then return false, "Blood system not initialized" end

    local itemFullType = item:getFullType()
    local donorType = EHR.Blood.BloodBagTypes[itemFullType]

    if not donorType then
        return false, "Not a valid blood bag"
    end

    local recipientType = EHR.Blood.GetPlayerBloodType(player)

    -- Check compatibility
    if not EHR.Blood.IsCompatible(donorType, recipientType) then
        -- Incompatible transfusion - causes transfusion reaction!
        EHR.Dialogue.SayStageChange(player, getText("UI_EHR_Dialogue_Transfusion_Bad"))
        EHR.Log("TRANSFUSION REACTION: " .. donorType .. " into " .. recipientType)

        -- Apply negative effects (transfusion reaction)
        local stats = player:getStats()
        if stats and CharacterStat then
            if CharacterStat.PAIN then
                stats:set(CharacterStat.PAIN, math.min(100, (stats:get(CharacterStat.PAIN) or 0) + 30))
            end
            if CharacterStat.SICKNESS then
                stats:set(CharacterStat.SICKNESS, math.min(1, (stats:get(CharacterStat.SICKNESS) or 0) + 0.5))
            end
        end

        -- Consume the item anyway (it's used) - MP sync
        if isClient() then
            sendClientCommand(player, "EHR", "RemoveItem", {itemID = item:getID()})
        end
        player:getInventory():Remove(item)
        return false, "Transfusion reaction! Blood type incompatible!"
    end

    -- Compatible - add blood (v2.7.0+: directly modify currentVolume)
    EHR.Blood.ModifyBloodVolume(player, EHR.Blood.TRANSFUSION_AMOUNT)
    -- Also track transfused amount for hemodilution calculations
    data.EHR_Blood.transfusedBlood = (data.EHR_Blood.transfusedBlood or 0) + EHR.Blood.TRANSFUSION_AMOUNT

    EHR.Dialogue.SayStageChange(player, getText("UI_EHR_Dialogue_Transfusion_Good"))
    EHR.Log("Blood transfusion successful: +" .. EHR.Blood.TRANSFUSION_AMOUNT .. "mL (" .. donorType .. ")")

    -- Consume the item - MP sync
    if isClient() then
        sendClientCommand(player, "EHR", "RemoveItem", {itemID = item:getID()})
    end
    player:getInventory():Remove(item)

    -- Award First Aid XP for blood transfusion
    if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
        EHR.SkillXP.OnTransfusion(player, true)  -- true = blood
    end

    return true, "Transfusion successful"
end

--[[
    Use a saline bag - no compatibility needed, adds fluid volume
    WARNING: Too much saline causes hemodilution (oxygen deprivation)
    Returns: success, message
]]--
function EHR.Blood.UseSalineBag(player, item)
    -- MEDIUM FIX: Reduced excessive debug logging (was 39 lines, now consolidated)
    if not player or not item then
        return false, "Invalid parameters"
    end

    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then
        return false, "Blood system not initialized"
    end

    -- Check current saline ratio before adding more
    local currentSaline = data.EHR_Blood.transfusedSaline or 0
    local currentVolume = data.EHR_Blood.currentVolume or 5000
    local newSaline = currentSaline + EHR.Blood.SALINE_AMOUNT
    local projectedRatio = newSaline / currentVolume

    -- Warn player if this will be dangerous
    if projectedRatio >= EHR.Blood.HEMODILUTION_WARNING then
        EHR.Dialogue.SayStageChange(player, getText("UI_EHR_Dialogue_Saline_Warning"))
    end

    -- Add saline to blood volume (v2.7.0+: directly modify currentVolume)
    local beforeModify = data.EHR_Blood.currentVolume
    EHR.Blood.ModifyBloodVolume(player, EHR.Blood.SALINE_AMOUNT)

    -- Track saline amount separately for hemodilution calculations
    data.EHR_Blood.transfusedSaline = newSaline

    -- Consolidated debug logging (single line instead of 6+ lines)
    if EHR.DEBUG then
        EHR.Log(string.format("Saline: %d->%d mL, saline tracked: %.0f mL, ratio: %.1f%%",
            beforeModify, data.EHR_Blood.currentVolume, newSaline, projectedRatio * 100))
    end

    EHR.Dialogue.SayStageChange(player, getText("UI_EHR_Dialogue_Saline_Good"))
    EHR.Log(string.format("Saline infusion: +%dmL (total saline: %.0fmL)", EHR.Blood.SALINE_AMOUNT, newSaline))

    -- Also helps with thirst slightly
    local stats = player:getStats()
    if stats and CharacterStat and CharacterStat.THIRST then
        local current = stats:get(CharacterStat.THIRST) or 0
        stats:set(CharacterStat.THIRST, math.max(0, current - 0.1))
    end

    -- NOTE: Item removal is handled by the timed action in EHR_Transfusion.lua
    -- Do NOT remove item here to avoid double-removal
    if EHR.DEBUG then print("[EHR SALINE DEBUG] UseSalineBag complete. Final volume: " .. (data.EHR_Blood.currentVolume or 0) .. " mL") end

    -- Award First Aid XP for saline infusion
    if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
        EHR.SkillXP.OnTransfusion(player, false)  -- false = saline
    end

    return true, "Saline infusion successful"
end

--[[
    Hemodilution warning - symptoms when saline is 40-60% of blood
]]--
function EHR.Blood.ApplyHemodilutionWarning(player, salineRatio)
    local stats = player:getStats()
    if not stats or not CharacterStat then return end

    -- Dizziness and weakness from reduced oxygen
    if CharacterStat.FATIGUE then
        local current = stats:get(CharacterStat.FATIGUE) or 0
        stats:set(CharacterStat.FATIGUE, math.min(0.8, current + 0.02))
    end

    if CharacterStat.ENDURANCE then
        local current = stats:get(CharacterStat.ENDURANCE) or 1
        stats:set(CharacterStat.ENDURANCE, math.max(0.3, current - 0.05))
    end

    -- Random warning messages
    if ZombRand(200) < 1 then
        local messages = {
            "I feel dizzy... something's wrong...",
            "My vision is getting blurry...",
            "I can't catch my breath...",
            "Everything feels... distant...",
        }
        EHR.Locale.Say(player, messages[ZombRand(#messages) + 1])
    end

    if EHR.DEBUG then
        EHR.Log(string.format("Hemodilution WARNING: %.1f%% saline ratio", salineRatio * 100))
    end
end

--[[
    Hemodilution death - brain oxygen deprivation when saline > 60%
]]--
function EHR.Blood.ApplyHemodilutionDeath(player, salineRatio)
    local stats = player:getStats()
    if not stats or not CharacterStat then return end

    -- Severe symptoms
    if CharacterStat.FATIGUE then
        stats:set(CharacterStat.FATIGUE, 1.0)  -- Max fatigue
    end

    if CharacterStat.ENDURANCE then
        stats:set(CharacterStat.ENDURANCE, 0)  -- No endurance
    end

    -- DEATH CAUSE TRACKING: Record cause before dealing fatal damage
    EHR.RecordDeathCause(player, string.format("Hemodilution (%.1f%% saline ratio) - brain oxygen deprivation from excess IV saline", salineRatio * 100))

    -- Apply health damage - this will kill the player
    local bodyDamage = player:getBodyDamage()
    if bodyDamage then
        -- Damage to head (brain oxygen deprivation)
        local head = bodyDamage:getBodyPart(BodyPartType.Head)
        if head then
            local currentHealth = head:getHealth() or 100
            head:SetHealth(math.max(0, currentHealth - 5))  -- Rapid damage
        end

        -- Also overall health reduction
        local overallHealth = bodyDamage:getOverallBodyHealth()
        bodyDamage:setOverallBodyHealth(math.max(0, overallHealth - 2))
    end

    -- Death messages
    if ZombRand(30) < 1 then
        local messages = {
            "I can't... breathe... the blood is too thin...",
            "My brain... it's not getting oxygen...",
            "Everything is going dark...",
            "Too much... saline... can't think...",
        }
        EHR.Locale.Say(player, messages[ZombRand(#messages) + 1])
    end

    EHR.Log(string.format("HEMODILUTION LETHAL: %.1f%% saline ratio - applying damage", salineRatio * 100))
end

--[[
    Context menu handler for blood bags

    NOTE (v2.7.0): Blood bag and saline context menus are now handled by
    EHR_Transfusion.lua which provides proper timed actions. This handler
    is DISABLED to prevent duplicate menu entries.

    The UseBloodBag function is still available for direct calls from
    other modules or the transfusion system.
]]--
-- REMOVED: Duplicate handler - EHR_Transfusion.lua handles blood bag context menus
-- Events.OnFillInventoryObjectContextMenu.Add(OnBloodContextMenu)

-- ============================================
-- HEALING CONTROL
-- Body parts only heal when conditions are met
-- ============================================

-- Store locked health values per player
local lockedHealth = {}

-- Expose reset function for central state management
EHR.ResetLockedHealth = function(playerID)
    if playerID then
        lockedHealth[playerID] = nil
        EHR.Log("lockedHealth cleared for player: " .. tostring(playerID))
    else
        -- Clear all if no playerID specified
        lockedHealth = {}
        EHR.Log("lockedHealth cleared for ALL players")
    end
end

-- Accept an explicit, authorized body-part health change as the new healing-lock
-- baseline. This does not alter wounds or bypass future ControlHealing checks; it
-- only prevents the next tick from mistaking an emergency treatment for vanilla
-- passive regeneration and rolling it back.
function EHR.Blood.AcceptCurrentHealth(player)
    if not player or not player.getBodyDamage then return false end

    local bodyDamage = nil
    local playerID = nil
    local ok = pcall(function()
        bodyDamage = player:getBodyDamage()
        playerID = tostring(player:getUsername() or player:getPlayerNum())
    end)
    if not ok or not bodyDamage or not playerID then return false end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return false end

    lockedHealth[playerID] = lockedHealth[playerID] or {}
    local locked = lockedHealth[playerID]
    local accepted = 0
    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local part = partType and bodyDamage:getBodyPart(partType) or nil
        if part and part.getHealth then
            local okHealth, currentHealth = pcall(function() return part:getHealth() end)
            if okHealth and tonumber(currentHealth) then
                locked[tostring(partType)] = tonumber(currentHealth)
                accepted = accepted + 1
            end
        end
    end

    if accepted > 0 then
        EHR.Log("Blood healing lock accepted authorized health baseline for " .. tostring(playerID))
    end
    return accepted > 0
end

-- Thresholds for allowing healing
-- Note: Most stats are 0-1, but PAIN is 0-100 in B42!
EHR.Blood.HealingRequirements = {
    maxHunger = 0.3,      -- 0-1 scale: Must be less than 30% hungry
    maxThirst = 0.3,      -- 0-1 scale: Must be less than 30% thirsty
    maxStress = 0.5,      -- 0-1 scale: Must be less than 50% stressed
    maxPain = 5,          -- 0-100 scale: Must have less than 5 pain (moodle shows ~5+)
    fatigueBypassCriticalHealth = 10, -- Emergency healing may continue at critical HP
}

-- Debug counter for CanHeal logging
local canHealDebugCounter = 0

local function EHR_BloodGetOverallBodyHealth(player)
    if not player or not player.getBodyDamage then return nil end

    local bodyDamage = nil
    local okBody = pcall(function()
        bodyDamage = player:getBodyDamage()
    end)
    if not okBody or not bodyDamage then return nil end

    local okHealth, health = pcall(function()
        if bodyDamage.getOverallBodyHealth then
            return bodyDamage:getOverallBodyHealth()
        end
        if bodyDamage.getOverallHealth then
            return bodyDamage:getOverallHealth()
        end
        return nil
    end)

    if okHealth then
        return tonumber(health)
    end
    return nil
end

--[[
    Check if conditions allow healing
    Returns true if player is fed, hydrated, calm, and not in pain

    B42 API uses: stats:get(CharacterStat.HUNGER) instead of stats:getHunger()
]]--
function EHR.Blood.CanHeal(player)
    local reqs = EHR.Blood.HealingRequirements

    -- Get stats object
    local stats = player:getStats()
    if not stats then return true, "ok" end

    -- B42 uses stats:get(CharacterStat.X) instead of stats:getX()
    -- CharacterStat is a Java enum exposed to Lua
    local hunger = nil
    local thirst = nil
    local stress = nil
    local fatigue = nil
    local pain = nil

    -- Try B42 API first (CharacterStat enum)
    if CharacterStat then
        local success, result

        -- Get hunger
        if CharacterStat.HUNGER then
            success, result = pcall(function() return stats:get(CharacterStat.HUNGER) end)
            if success then hunger = result end
        end

        -- Get thirst
        if CharacterStat.THIRST then
            success, result = pcall(function() return stats:get(CharacterStat.THIRST) end)
            if success then thirst = result end
        end

        -- Get stress
        if CharacterStat.STRESS then
            success, result = pcall(function() return stats:get(CharacterStat.STRESS) end)
            if success then stress = result end
        end

        -- Get fatigue
        if CharacterStat.FATIGUE then
            success, result = pcall(function() return stats:get(CharacterStat.FATIGUE) end)
            if success then fatigue = result end
        end

        -- Get pain
        if CharacterStat.PAIN then
            success, result = pcall(function() return stats:get(CharacterStat.PAIN) end)
            if success then pain = result end
        end
    end

    -- Debug output every ~5 seconds
    canHealDebugCounter = canHealDebugCounter + 1
    if EHR.DEBUG and canHealDebugCounter >= 150 then
        canHealDebugCounter = 0
        EHR.Log(string.format("CanHeal - hunger: %.2f, thirst: %.2f, stress: %.2f, fatigue: %.2f, pain: %.2f",
            hunger or 0, thirst or 0, stress or 0, fatigue or 0, pain or 0))
    end

    -- If we can't read any stats, allow healing by default
    if hunger == nil and thirst == nil and stress == nil and fatigue == nil then
        return true, "ok"
    end

    -- Check hunger (0 = full, 1 = starving) - if enabled in sandbox
    if EHR.Blood.GetSetting("HealingRequiresFed", true) then
        if hunger and hunger > reqs.maxHunger then
            return false, "hungry"
        end
    end

    -- Check thirst (0 = full, 1 = dehydrated) - if enabled in sandbox
    if EHR.Blood.GetSetting("HealingRequiresHydrated", true) then
        if thirst and thirst > reqs.maxThirst then
            return false, "thirsty"
        end
    end

    -- Check stress (0 = calm, 1 = max stress) - if enabled in sandbox
    if EHR.Blood.GetSetting("HealingRequiresCalm", true) then
        if stress and stress > reqs.maxStress then
            return false, "stressed"
        end
    end

    -- Check fatigue (0 = rested, 1 = exhausted) - if enabled in sandbox
    if EHR.Blood.GetSetting("HealingRequiresRested", true) then
        if fatigue and fatigue > 0.5 then
            local asleep = false
            if player.isAsleep then
                pcall(function()
                    asleep = player:isAsleep()
                end)
            end

            local overallHealth = EHR_BloodGetOverallBodyHealth(player)
            local criticalHealth = reqs.fatigueBypassCriticalHealth or 10
            if not asleep and (not overallHealth or overallHealth > criticalHealth) then
                return false, "tired"
            end
        end
    end

    -- Check pain (0 = no pain, 100 = max pain) - if enabled in sandbox
    if EHR.Blood.GetSetting("HealingRequiresNoPain", true) then
        if pain and pain > reqs.maxPain then
            return false, "in pain"
        end
    end

    return true, "ok"
end

-- Debug counter for ControlHealing
local controlHealDebugCounter = 0
local controlHealFirstRun = true

-- Expose debug counter reset
EHR.ResetBloodDebugCounters = function()
    controlHealFirstRun = true
    controlHealDebugCounter = 0
    canHealDebugCounter = 0
    updateCount = 0
end

--[[
    Control healing - called every tick
    Locks body part health when conditions aren't met
]]--
function EHR.Blood.ControlHealing(player, data)
    -- Log first run
    if controlHealFirstRun then
        controlHealFirstRun = false
        EHR.Log("ControlHealing: First run! v2.1.0")
    end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then
        EHR.Log("ControlHealing: No bodyDamage!")
        return
    end

    local playerID = tostring(player:getUsername() or player:getPlayerNum())

    -- Check if healing control should be skipped entirely (API for other mods)
    if EHR.Blood.AllowHealingOverride then
        EHR.Blood.AllowHealingOverride = false  -- Reset after use
        if data.EHR_Blood then
            data.EHR_Blood.canHeal = true
            data.EHR_Blood.healBlockReason = "ok"
        end
        return
    end

    -- Check if this player should be skipped (API for other mods)
    if EHR.Blood.SkipHealingControl[playerID] then
        if data.EHR_Blood then
            data.EHR_Blood.canHeal = true
            data.EHR_Blood.healBlockReason = "ok"
        end
        return
    end

    -- Initialize locked health storage for this player
    if not lockedHealth[playerID] then
        lockedHealth[playerID] = {}
        EHR.Log("ControlHealing: Initialized player " .. playerID)
    end

    local locked = lockedHealth[playerID]
    local canHeal, reason = EHR.Blood.CanHeal(player)

    -- Check if Knox infection is disabled - if so, always allow healing on infected wounds
    local knoxDisabled = EHR.Blood.IsKnoxInfectionDisabled()

    -- ALWAYS set heal status for UI, even if we return early
    if data.EHR_Blood then
        data.EHR_Blood.canHeal = canHeal
        data.EHR_Blood.healBlockReason = reason
    else
        EHR.Log("ControlHealing: data.EHR_Blood is nil!")
    end

    -- Debug log every ~3 seconds (90 ticks)
    controlHealDebugCounter = controlHealDebugCounter + 1
    if EHR.DEBUG and controlHealDebugCounter >= 90 then
        controlHealDebugCounter = 0
        EHR.Log(string.format("ControlHealing: canHeal=%s, reason=%s", tostring(canHeal), tostring(reason)))
    end

    -- Loop through all body parts
    if not BodyPartType or not BodyPartType.ToIndex then
        EHR.Log("ControlHealing: BodyPartType API missing!")
        return
    end

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        if partType then
            local part = bodyDamage:getBodyPart(partType)
            if part then
                local partName = tostring(partType)

                -- If Knox infection is disabled AND this part has zombie infection,
                -- skip healing control entirely - let the game/other mods cure it
                if knoxDisabled and EHR.Blood.HasZombieInfection(part) then
                    -- Clear stored health so we don't revert healing
                    locked[partName] = nil
                    -- Skip rest of loop body - don't interfere with Knox cure
                else
                    -- Normal healing control logic
                    -- Safely get current health
                    local currentHealth = nil
                    if part.getHealth then
                        local success, result = pcall(function() return part:getHealth() end)
                        if success then currentHealth = result end
                    end

                    -- Only process if we got valid health
                    if currentHealth ~= nil then
                        -- First time seeing this part - store current health
                        if locked[partName] == nil then
                            locked[partName] = currentHealth
                        end

                        local storedHealth = locked[partName]

                        -- v2.7.2: Tolerance threshold to reduce visual oscillation
                        -- Only revert healing if the difference is > 0.5 health points
                        local HEAL_TOLERANCE = 0.5

                        if canHeal then
                            -- Conditions good - allow healing, update stored value
                            if currentHealth > storedHealth then
                                locked[partName] = currentHealth
                            elseif currentHealth < storedHealth then
                                -- Took damage - update stored value
                                locked[partName] = currentHealth
                            end
                        else
                            -- Conditions bad - lock healing
                            local healthDiff = currentHealth - storedHealth
                            if healthDiff > HEAL_TOLERANCE then
                                -- Vanilla tried to heal significantly - revert it (SetHealth with capital S!)
                                if part.SetHealth then
                                    pcall(function() part:SetHealth(storedHealth) end)
                                end
                            elseif healthDiff < -HEAL_TOLERANCE then
                                -- Took significant damage - update stored value
                                locked[partName] = currentHealth
                            end
                            -- Small changes (< TOLERANCE) are ignored to prevent oscillation
                        end
                    end
                end
            end
        end
    end
    -- Heal status already set earlier in function
end

-- ============================================
-- DEATH/RESPAWN CLEANUP
-- ============================================

-- Player death handler - clear stale blood data
local function OnBloodPlayerDeath(player)
    if not player then return end

    local playerID = tostring(player:getUsername() or player:getPlayerNum())

    -- Clear blackout data for this player
    if EHR.Blood.blackoutData then
        EHR.Blood.blackoutData[playerID] = nil
        EHR.Log("Blood: Cleared blackoutData for player " .. playerID)
    end
end

if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(OnBloodPlayerDeath)
end

EHR.Log("Blood module loaded")
