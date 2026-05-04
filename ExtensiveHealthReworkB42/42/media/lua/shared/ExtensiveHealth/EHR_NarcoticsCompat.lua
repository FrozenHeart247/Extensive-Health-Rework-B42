--[[
    Extensive Health Rework B42
    N&C Narcotics Compatibility Module

    Integrates EHR systems with N&C's Narcotics mod:
    - Stimulants cause increased blood loss (blood pressure spike)
    - Overdose triggers EHR disease system
    - Withdrawal blocks wound healing
    - Opioids slow wound infection progression

    Requires: N&C's Narcotics mod (Workshop ID: 3404956403)

    v1.0.0 - Initial implementation
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.Narcotics = {}

-- ============================================
-- CONFIGURATION
-- ============================================

-- Stimulant effect thresholds (from N&C's TraitEffects.lua)
EHR.Narcotics.StimulantEffectRange = {
    cocaine = { min = 3, max = 18 },
    meth = { min = 3, max = 62 },
}

-- Opioid effect thresholds
EHR.Narcotics.OpioidEffectRange = {
    min = 3,
    max = 62,
}

-- Overdose thresholds (from N&C's TraitEffects.lua)
EHR.Narcotics.OverdoseThresholds = {
    benzo = 1420,
    cocaine = 1410,
    meth = 1420,
    mdma = 1420,
    opioid = 1410,
}

-- Withdrawal detection: addiction trait + days since last use
EHR.Narcotics.WithdrawalThresholds = {
    benzo = 432,     -- 3 days (6 ticks/hour * 24h * 3d)
    cocaine = 144,   -- 1 day
    meth = 144,      -- 1 day
    mdma = 432,      -- 3 days
    opioid = 144,    -- 1 day
}

-- Effect multipliers (configurable)
EHR.Narcotics.Effects = {
    -- Stimulants increase blood loss rate
    stimulantBloodLossMultiplier = 1.5,  -- 50% more blood loss

    -- Opioids slow infection progression
    opioidInfectionMultiplier = 0.5,     -- 50% slower infection

    -- Overdose disease severity (0-1)
    overdoseDiseaseSeverity = 0.8,

    -- Withdrawal completely blocks healing
    withdrawalBlocksHealing = true,
}

-- ============================================
-- DETECTION FUNCTIONS
-- ============================================

--[[
    Check if N&C Narcotics mod is loaded
]]--
function EHR.Narcotics.IsModLoaded()
    -- Check for NnC global table or modData fields
    if NnC then return true end

    local player = getSpecificPlayer(0)
    if player then
        local md = player:getModData()
        -- Check for any N&C modData field
        if md.NnCCokeEffect ~= nil or md.NnCMethEffect ~= nil or md.NnCOpioidEffect ~= nil then
            return true
        end
    end

    return false
end

--[[
    Get N&C modData safely
]]--
function EHR.Narcotics.GetNnCData(player)
    if not player then return nil end
    local md = player:getModData()
    if not md then return nil end

    -- Return a normalized structure
    return {
        -- Effect levels (how high the player is)
        cokeEffect = md.NnCCokeEffect or 0,
        methEffect = md.NnCMethEffect or 0,
        opioidEffect = md.NnCOpioidEffect or 0,
        benzoEffect = md.NnCBenzoEffect or 0,
        mdmaEffect = md.NnCMDMAEffect or 0,
        weedEffect = md.NnCWeeeeedEffect or 0,

        -- Accumulated amounts (for overdose)
        cokeAmount = md.NnCCokeAmount or 0,
        methAmount = md.NnCMethAmount or 0,
        opioidAmount = md.NnCOpioidAmount or 0,
        benzoAmount = md.NnCBenzoAmount or 0,
        mdmaAmount = md.NnCMDMAAmount or 0,

        -- Addiction timers (positive = days since last use, negative = active use)
        cokeTimer = md.NnCTenMinutesCokeHead or 0,
        methTimer = md.NnCTenMinutesMethHead or 0,
        opioidTimer = md.NnCTenMinutesOpioidAddict or 0,
        benzoTimer = md.NnCTenMinutesBenzoAddict or 0,
        mdmaTimer = md.NnCTenMinutesMDMAAddict or 0,
    }
end

--[[
    Check if player is on stimulants (cocaine or meth)
]]--
function EHR.Narcotics.IsOnStimulants(player)
    local data = EHR.Narcotics.GetNnCData(player)
    if not data then return false end

    local cokeRange = EHR.Narcotics.StimulantEffectRange.cocaine
    local methRange = EHR.Narcotics.StimulantEffectRange.meth

    local onCoke = data.cokeEffect >= cokeRange.min and data.cokeEffect <= cokeRange.max
    local onMeth = data.methEffect >= methRange.min and data.methEffect <= methRange.max

    return onCoke or onMeth
end

--[[
    Check if player is on opioids
]]--
function EHR.Narcotics.IsOnOpioids(player)
    local data = EHR.Narcotics.GetNnCData(player)
    if not data then return false end

    local range = EHR.Narcotics.OpioidEffectRange
    return data.opioidEffect >= range.min and data.opioidEffect <= range.max
end

--[[
    Check if player is overdosing on any drug
    Returns: isOD (bool), drugType (string or nil)
]]--
function EHR.Narcotics.IsOverdosing(player)
    local data = EHR.Narcotics.GetNnCData(player)
    if not data then return false, nil end

    local thresholds = EHR.Narcotics.OverdoseThresholds

    if data.benzoAmount > thresholds.benzo then return true, "benzo" end
    if data.cokeAmount > thresholds.cocaine then return true, "cocaine" end
    if data.methAmount > thresholds.meth then return true, "meth" end
    if data.mdmaAmount > thresholds.mdma then return true, "mdma" end
    if data.opioidAmount > thresholds.opioid then return true, "opioid" end

    return false, nil
end

--[[
    Check if player is in withdrawal
    Returns: isWithdrawing (bool), drugType (string or nil)
]]--
function EHR.Narcotics.IsInWithdrawal(player)
    local data = EHR.Narcotics.GetNnCData(player)
    if not data then return false, nil end

    local thresholds = EHR.Narcotics.WithdrawalThresholds

    -- Check if player has addiction trait AND timer is above threshold
    -- Positive timer = days since last use

    -- Check for NnCReg traits (addiction traits)
    local hasTrait = function(traitName)
        if not player.hasTrait then return false end
        -- Try both NnCReg and direct trait check
        if NnCReg and NnCReg[traitName] then
            return player:hasTrait(NnCReg[traitName])
        end
        -- Fallback: check by string
        local traits = player:getCharacterTraits()
        if traits then
            return traits:contains("NnC:" .. traitName)
        end
        return false
    end

    -- Check each drug type
    if hasTrait("CokeHead") and data.cokeTimer >= thresholds.cocaine then
        return true, "cocaine"
    end
    if hasTrait("MethHead") and data.methTimer >= thresholds.meth then
        return true, "meth"
    end
    if hasTrait("OpioidAddict") and data.opioidTimer >= thresholds.opioid then
        return true, "opioid"
    end
    if hasTrait("BenzoAddict") and data.benzoTimer >= thresholds.benzo then
        return true, "benzo"
    end
    if hasTrait("MDMAAddict") and data.mdmaTimer >= thresholds.mdma then
        return true, "mdma"
    end

    return false, nil
end

-- ============================================
-- EFFECT: STIMULANT BLOOD PRESSURE SPIKE
-- ============================================

-- Store original blood loss multiplier
local originalBloodLossMultiplier = nil

--[[
    Apply stimulant blood pressure effect
    Called from EHR.Blood.Update (hooked)
]]--
function EHR.Narcotics.ApplyStimulantEffect(player)
    if not EHR.Narcotics.IsModLoaded() then return end

    local isOnStims = EHR.Narcotics.IsOnStimulants(player)

    -- Get player modData for tracking
    local modData = player:getModData()
    modData.EHR_NnC_StimulantActive = isOnStims

    -- The actual blood loss modification is done by overriding GetLossMultiplier
end

--[[
    Reset state for a player (called on death/respawn)
    Clears any cached N&C data for the specified player
]]--
function EHR.Narcotics.ResetState(playerID)
    if not playerID then return end

    -- Clear OD tracking for this player
    if lastODState then
        lastODState[playerID] = nil
    end

    EHR.Log("Narcotics: Reset state for player " .. tostring(playerID))
end

-- ============================================
-- EFFECT: OVERDOSE TRIGGERS DISEASE
-- ============================================

-- Track OD state to avoid repeated triggers
local lastODState = {}

--[[
    Check and trigger overdose disease
]]--
function EHR.Narcotics.CheckOverdose(player)
    if not EHR.Narcotics.IsModLoaded() then return end
    if not EHR.Disease then return end

    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    local isOD, drugType = EHR.Narcotics.IsOverdosing(player)

    -- Check if this is a new OD (not already triggered)
    local wasOD = lastODState[playerID]
    lastODState[playerID] = isOD

    if isOD and not wasOD then
        -- New overdose - trigger EHR disease
        EHR.Log(string.format("N&C Overdose detected (%s) - triggering EHR disease", drugType))

        -- Initialize disease if needed
        if EHR.Disease.InitializePlayer then
            EHR.Disease.InitializePlayer(player)
        end

        local modData = player:getModData()
        if modData.EHR_Disease then
            -- Set disease state based on drug type
            local severity = EHR.Narcotics.Effects.overdoseDiseaseSeverity

            -- Different drugs cause different effects
            if drugType == "opioid" then
                -- Opioid OD: respiratory depression (fatigue-heavy)
                modData.EHR_Disease.stage = 3  -- Start at moderate stage
                modData.EHR_Disease.progression = severity
                modData.EHR_Disease.source = "opioid_overdose"
            elseif drugType == "cocaine" or drugType == "meth" then
                -- Stimulant OD: cardiac stress
                modData.EHR_Disease.stage = 3
                modData.EHR_Disease.progression = severity
                modData.EHR_Disease.source = "stimulant_overdose"
            else
                -- Other OD: general toxicity
                modData.EHR_Disease.stage = 2
                modData.EHR_Disease.progression = severity * 0.8
                modData.EHR_Disease.source = drugType .. "_overdose"
            end

            if player.Say then
                player:Say("*groans* I think I took too much...")
            end
        end
    end
end

-- ============================================
-- EFFECT: WITHDRAWAL BLOCKS HEALING
-- ============================================

--[[
    Check if withdrawal should block healing
    This is called by the CanHeal hook
]]--
function EHR.Narcotics.ShouldBlockHealing(player)
    if not EHR.Narcotics.IsModLoaded() then return false, nil end
    if not EHR.Narcotics.Effects.withdrawalBlocksHealing then return false, nil end

    local isWithdrawing, drugType = EHR.Narcotics.IsInWithdrawal(player)

    if isWithdrawing then
        return true, drugType .. " withdrawal"
    end

    return false, nil
end

-- ============================================
-- EFFECT: OPIOIDS SLOW INFECTION
-- ============================================

--[[
    Get infection speed modifier based on opioid use
    Returns multiplier (1.0 = normal, 0.5 = half speed)
]]--
function EHR.Narcotics.GetInfectionSpeedModifier(player)
    if not EHR.Narcotics.IsModLoaded() then return 1.0 end

    if EHR.Narcotics.IsOnOpioids(player) then
        return EHR.Narcotics.Effects.opioidInfectionMultiplier
    end

    return 1.0
end

-- ============================================
-- HOOK: BLOOD MODULE
-- ============================================

-- Hook into EHR.Blood.GetLossMultiplier
local originalGetLossMultiplier = nil

function EHR.Narcotics.HookBloodModule()
    if not EHR.Blood then
        EHR.Log("Narcotics: Blood module not loaded, skipping hook")
        return
    end

    -- Store original function
    originalGetLossMultiplier = EHR.Blood.GetLossMultiplier

    -- Override with our version
    EHR.Blood.GetLossMultiplier = function()
        local base = originalGetLossMultiplier()

        local player = getSpecificPlayer(0)
        if player and EHR.Narcotics.IsOnStimulants(player) then
            local modified = base * EHR.Narcotics.Effects.stimulantBloodLossMultiplier
            if EHR.DEBUG then
                EHR.Log(string.format("Stimulant blood loss: %.2f -> %.2f", base, modified))
            end
            return modified
        end

        return base
    end

    EHR.Log("Narcotics: Hooked Blood module")
end

-- ============================================
-- HOOK: HEALING CONTROL
-- ============================================

-- Hook into EHR.Blood.CanHeal
local originalCanHeal = nil

function EHR.Narcotics.HookHealingControl()
    if not EHR.Blood then
        EHR.Log("Narcotics: Blood module not loaded, skipping healing hook")
        return
    end

    -- Store original function
    originalCanHeal = EHR.Blood.CanHeal

    -- Override with our version
    EHR.Blood.CanHeal = function(player)
        -- Check withdrawal first
        local blocked, reason = EHR.Narcotics.ShouldBlockHealing(player)
        if blocked then
            return false, reason
        end

        -- Then check original conditions
        return originalCanHeal(player)
    end

    EHR.Log("Narcotics: Hooked healing control")
end

-- ============================================
-- HOOK: WOUND INFECTION
-- ============================================

-- Hook into EHR.WoundInfection.CalculateRisk
local originalCalculateRisk = nil

function EHR.Narcotics.HookWoundInfection()
    if not EHR.WoundInfection then
        EHR.Log("Narcotics: WoundInfection module not loaded, skipping hook")
        return
    end

    -- Store original function
    originalCalculateRisk = EHR.WoundInfection.CalculateRisk

    -- Override with our version
    EHR.WoundInfection.CalculateRisk = function(player, partData, wounds, hoursElapsed)
        -- Get original risk
        local risk = originalCalculateRisk(player, partData, wounds, hoursElapsed)

        -- Apply opioid modifier
        local modifier = EHR.Narcotics.GetInfectionSpeedModifier(player)
        if modifier ~= 1.0 then
            local modified = risk * modifier
            if EHR.DEBUG then
                EHR.Log(string.format("Opioid infection modifier: %.3f -> %.3f", risk, modified))
            end
            return modified
        end

        return risk
    end

    EHR.Log("Narcotics: Hooked WoundInfection module")
end

-- ============================================
-- UI DISPLAY FUNCTIONS
-- Returns active substance data for Medical Monitor display
-- ============================================

--[[
    Get active substances for UI display
    Returns a table of active drugs with their effect levels and status
    Used by EHR_MedicalMonitorUI to show N&C drug status
]]--
function EHR.Narcotics.GetActiveSubstances(player)
    if not EHR.Narcotics.IsModLoaded() then return {} end

    local data = EHR.Narcotics.GetNnCData(player)
    if not data then return {} end

    local substances = {}

    -- Check each drug type and add if active
    local cokeRange = EHR.Narcotics.StimulantEffectRange.cocaine
    local methRange = EHR.Narcotics.StimulantEffectRange.meth
    local opioidRange = EHR.Narcotics.OpioidEffectRange

    -- Cocaine
    if data.cokeEffect >= cokeRange.min then
        local intensity = math.min(1, data.cokeEffect / cokeRange.max)
        local isOD = data.cokeAmount > EHR.Narcotics.OverdoseThresholds.cocaine
        table.insert(substances, {
            name = "Cocaine",
            category = "stimulant",
            effectLevel = data.cokeEffect,
            intensity = intensity, -- 0-1 scale for UI bar
            isOverdose = isOD,
            status = isOD and "OVERDOSE!" or (intensity > 0.7 and "HIGH" or (intensity > 0.3 and "MODERATE" or "LOW")),
            color = isOD and "critical" or "stimulant",
        })
    end

    -- Methamphetamine
    if data.methEffect >= methRange.min then
        local intensity = math.min(1, data.methEffect / methRange.max)
        local isOD = data.methAmount > EHR.Narcotics.OverdoseThresholds.meth
        table.insert(substances, {
            name = "Methamphetamine",
            category = "stimulant",
            effectLevel = data.methEffect,
            intensity = intensity,
            isOverdose = isOD,
            status = isOD and "OVERDOSE!" or (intensity > 0.7 and "HIGH" or (intensity > 0.3 and "MODERATE" or "LOW")),
            color = isOD and "critical" or "stimulant",
        })
    end

    -- Opioids
    if data.opioidEffect >= opioidRange.min then
        local intensity = math.min(1, data.opioidEffect / opioidRange.max)
        local isOD = data.opioidAmount > EHR.Narcotics.OverdoseThresholds.opioid
        table.insert(substances, {
            name = "Opioids",
            category = "opioid",
            effectLevel = data.opioidEffect,
            intensity = intensity,
            isOverdose = isOD,
            status = isOD and "OVERDOSE!" or (intensity > 0.7 and "HIGH" or (intensity > 0.3 and "MODERATE" or "LOW")),
            color = isOD and "critical" or "opioid",
        })
    end

    -- Benzodiazepines
    if data.benzoEffect > 0 then
        local intensity = math.min(1, data.benzoEffect / 30) -- Approximate max
        local isOD = data.benzoAmount > EHR.Narcotics.OverdoseThresholds.benzo
        table.insert(substances, {
            name = "Benzodiazepines",
            category = "depressant",
            effectLevel = data.benzoEffect,
            intensity = intensity,
            isOverdose = isOD,
            status = isOD and "OVERDOSE!" or (intensity > 0.7 and "HIGH" or (intensity > 0.3 and "MODERATE" or "LOW")),
            color = isOD and "critical" or "depressant",
        })
    end

    -- MDMA
    if data.mdmaEffect > 0 then
        local intensity = math.min(1, data.mdmaEffect / 30) -- Approximate max
        local isOD = data.mdmaAmount > EHR.Narcotics.OverdoseThresholds.mdma
        table.insert(substances, {
            name = "MDMA",
            category = "stimulant",
            effectLevel = data.mdmaEffect,
            intensity = intensity,
            isOverdose = isOD,
            status = isOD and "OVERDOSE!" or (intensity > 0.7 and "HIGH" or (intensity > 0.3 and "MODERATE" or "LOW")),
            color = isOD and "critical" or "stimulant",
        })
    end

    -- Cannabis (non-dangerous, just for display)
    if data.weedEffect > 0 then
        local intensity = math.min(1, data.weedEffect / 20)
        table.insert(substances, {
            name = "Cannabis",
            category = "cannabis",
            effectLevel = data.weedEffect,
            intensity = intensity,
            isOverdose = false,
            status = intensity > 0.5 and "HIGH" or "LOW",
            color = "cannabis",
        })
    end

    return substances
end

--[[
    Get withdrawal status for UI display
    Returns table with withdrawal info if player is withdrawing
]]--
function EHR.Narcotics.GetWithdrawalStatus(player)
    if not EHR.Narcotics.IsModLoaded() then return nil end

    local isWithdrawing, drugType = EHR.Narcotics.IsInWithdrawal(player)
    if not isWithdrawing then return nil end

    local drugNames = {
        cocaine = "Cocaine",
        meth = "Methamphetamine",
        opioid = "Opioids",
        benzo = "Benzodiazepines",
        mdma = "MDMA",
    }

    return {
        drugType = drugType,
        drugName = drugNames[drugType] or drugType,
        blocksHealing = EHR.Narcotics.Effects.withdrawalBlocksHealing,
    }
end

-- ============================================
-- MAIN UPDATE
-- ============================================

local UPDATE_INTERVAL = 300  -- Every ~10 seconds

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

local function processPlayerTick(player)
    if not player then return end
    if not player:isAlive() then return end

    -- Check if N&C mod is loaded
    if not EHR.Narcotics.IsModLoaded() then return end

    local state = getTickState(player)
    state.tick = state.tick + 1
    if state.tick < UPDATE_INTERVAL then return end
    state.tick = 0

    -- Update stimulant tracking
    EHR.Narcotics.ApplyStimulantEffect(player)

    -- Check for overdose
    EHR.Narcotics.CheckOverdose(player)
end

function EHR.Narcotics.OnTick()
    -- MP: server-authoritative processing
    if isClient and isClient() and not (isServer and isServer()) then return end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

function EHR.Narcotics.Initialize()
    EHR.Log("Initializing N&C Narcotics compatibility module...")

    -- Check if N&C is loaded
    if not EHR.Narcotics.IsModLoaded() then
        EHR.Log("N&C Narcotics mod not detected - compatibility module inactive")
        return
    end

    EHR.Log("N&C Narcotics mod detected - activating compatibility")

    -- Hook into EHR modules
    EHR.Narcotics.HookBloodModule()
    EHR.Narcotics.HookHealingControl()
    EHR.Narcotics.HookWoundInfection()

    EHR.Log("N&C Narcotics compatibility initialized")
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if Events then
    Events.OnTick.Add(EHR.Narcotics.OnTick)
    Events.OnGameStart.Add(EHR.Narcotics.Initialize)

    EHR.Log("Narcotics compatibility module events registered")
end

EHR.Log("Narcotics compatibility module loaded v1.0.0")
