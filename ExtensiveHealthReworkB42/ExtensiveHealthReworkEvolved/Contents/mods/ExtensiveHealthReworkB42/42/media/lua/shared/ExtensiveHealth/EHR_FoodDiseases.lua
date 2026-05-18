--[[
    Extensive Health Rework B42
    Food-Related Diseases Module

    Handles disease transmission from food consumption:
    - Trichinosis: Raw/undercooked wild game meat (parasitic)
    - Gastroenteritis: Eating with dirty/bloody hands

    Also handles:
    - Hand contamination tracking
    - Raw meat detection

    v1.0.0 - Initial implementation
]]--

require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_DiseaseDefinitions"

EHR = EHR or {}
EHR.Food = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.Food.Config = {
    -- Trichinosis risk by meat type (item type patterns)
    trichinosis = {
        -- High risk meats (carnivores/omnivores)
        highRisk = {
            ["DeadRat"] = 0.70,
            ["DeadMouse"] = 0.70,
            ["Rat"] = 0.70,
            ["Mouse"] = 0.70,
            ["RatMeat"] = 0.70,
            ["WildBoarMeat"] = 0.70,
            ["BoarMeat"] = 0.70,
            ["BearMeat"] = 0.70,
        },
        -- Medium risk (other carnivores)
        mediumRisk = {
            ["FoxMeat"] = 0.70,
            ["RaccoonMeat"] = 0.70,
            ["WolfMeat"] = 0.70,
        },
        -- Patterns to match
        rawPatterns = {"Raw", "Uncooked", "Dead"},
        -- Safe if properly cooked (item has "Cooked" or high temperature)
        cookedPatterns = {"Cooked", "Grilled", "Roasted", "Fried"},
        -- Improperly smoked/cured still has some risk
        improperlyPreserved = 0.10,
    },

    -- Gastroenteritis risk
    gastroenteritis = {
        bloodOnHandsRisk = 0.15,        -- 15% if blood on hands
        dirtyHandsRisk = 0.08,          -- 8% if dirty (outdoor activities)
        rawMeatHandlingRisk = 0.10,     -- 10% after handling raw meat
        -- Decay rate for hand contamination (per game hour)
        contaminationDecay = 0.05,
    },

    -- Hand washing effectiveness
    handWashing = {
        soapAndWater = 1.0,             -- Full clean
        waterOnly = 0.7,                -- 70% clean
        disinfectant = 1.0,             -- Full clean
        wetWipes = 0.9,                 -- 90% clean
    },
}

-- ============================================
-- HAND CONTAMINATION TRACKING
-- ============================================

EHR.Food.HandData = {}

--[[
    Initialize hand contamination tracking for a player
]]--
function EHR.Food.InitializePlayer(player)
    if not player then return end

    local playerID = tostring(player:getUsername() or player:getPlayerNum())

    if EHR.Food.HandData[playerID] then
        return
    end

    EHR.Food.HandData[playerID] = {
        bloodLevel = 0,             -- Blood contamination (0-1)
        dirtLevel = 0,              -- Dirt contamination (0-1)
        rawMeatLevel = 0,           -- Raw meat contamination (0-1)
        lastWashTime = 0,           -- Last time hands were washed
    }

    EHR.Log("Food diseases: Initialized hand tracking for player " .. playerID)
end

--[[
    Get hand contamination data for a player
]]--
function EHR.Food.GetHandData(player)
    if not player then return nil end
    local playerID = tostring(player:getUsername() or player:getPlayerNum())
    return EHR.Food.HandData[playerID]
end

--[[
    Add contamination to hands
    @param contaminationType - "blood", "dirt", or "rawMeat"
    @param amount - contamination amount (0-1)
]]--
function EHR.Food.ContaminateHands(player, contaminationType, amount)
    local handData = EHR.Food.GetHandData(player)
    if not handData then return end

    if contaminationType == "blood" then
        handData.bloodLevel = math.min(1, handData.bloodLevel + amount)
    elseif contaminationType == "dirt" then
        handData.dirtLevel = math.min(1, handData.dirtLevel + amount)
    elseif contaminationType == "rawMeat" then
        handData.rawMeatLevel = math.min(1, handData.rawMeatLevel + amount)
    end

    if EHR.DEBUG then
        EHR.Log(string.format("Hand contamination: %s +%.2f (blood=%.2f, dirt=%.2f, meat=%.2f)",
            contaminationType, amount,
            handData.bloodLevel, handData.dirtLevel, handData.rawMeatLevel))
    end
end

--[[
    Wash hands, reducing contamination
    @param method - "soapAndWater", "waterOnly", "disinfectant", "wetWipes"
]]--
function EHR.Food.WashHands(player, method)
    local handData = EHR.Food.GetHandData(player)
    if not handData then return end

    local effectiveness = EHR.Food.Config.handWashing[method] or 0.5
    local reduction = effectiveness

    handData.bloodLevel = math.max(0, handData.bloodLevel - reduction)
    handData.dirtLevel = math.max(0, handData.dirtLevel - reduction)
    handData.rawMeatLevel = math.max(0, handData.rawMeatLevel - reduction)
    handData.lastWashTime = getGameTime():getWorldAgeHours()

    EHR.Log(string.format("Hands washed (%s): effectiveness=%.0f%%", method, effectiveness * 100))

    if player.Say and handData.bloodLevel < 0.1 and handData.dirtLevel < 0.1 then
        player:Say("*washes hands* Much better.")
    end
end

--[[
    Get total hand contamination risk for eating
]]--
function EHR.Food.GetContaminationRisk(player)
    local handData = EHR.Food.GetHandData(player)
    if not handData then return 0 end

    local config = EHR.Food.Config.gastroenteritis

    local risk = 0

    if handData.bloodLevel > 0.1 then
        risk = risk + (config.bloodOnHandsRisk * handData.bloodLevel)
    end

    if handData.dirtLevel > 0.1 then
        risk = risk + (config.dirtyHandsRisk * handData.dirtLevel)
    end

    if handData.rawMeatLevel > 0.1 then
        risk = risk + (config.rawMeatHandlingRisk * handData.rawMeatLevel)
    end

    return math.min(1, risk)
end

-- ============================================
-- TRICHINOSIS DETECTION
-- ============================================

local function EHR_FoodSafeItemMethod(item, methodName)
    if not item or not methodName or not item[methodName] then return nil end

    local success, result = pcall(function()
        return item[methodName](item)
    end)

    if success then return result end
    return nil
end

local function EHR_FoodTextHasAny(text, patterns)
    text = string.lower(tostring(text or ""))
    for _, pattern in ipairs(patterns or {}) do
        if string.find(text, string.lower(tostring(pattern)), 1, true) then
            return true
        end
    end
    return false
end

local function EHR_FoodLooksPrepared(itemType, displayName)
    local text = tostring(itemType or "") .. " " .. tostring(displayName or "")
    return EHR_FoodTextHasAny(text, {
        "burger",
        "sandwich",
        "taco",
        "burrito",
        "wrap",
        "pizza",
        "soup",
        "stew",
        "pasta",
        "rice",
        "omelette",
        "omelet",
        "pie",
        "bread",
        "cake",
        "muffin",
        "pancake",
        "waffle",
        "dumpling",
        "kebab",
        "skewer",
        "salad",
        "recipe",
    })
end

local function EHR_FoodLooksRaw(item, itemType, displayName, rawPatterns)
    local text = tostring(itemType or "") .. " " .. tostring(displayName or "")
    if EHR_FoodTextHasAny(text, rawPatterns) then return true end

    local isCookable = EHR_FoodSafeItemMethod(item, "isCookable")
    local isCooked = EHR_FoodSafeItemMethod(item, "isCooked")
    local isBurnt = EHR_FoodSafeItemMethod(item, "isBurnt") or EHR_FoodSafeItemMethod(item, "isBurned")
    return isCookable == true and isCooked ~= true and isBurnt ~= true
end

local function EHR_FoodLooksExplicitRaw(item, itemType, displayName, rawPatterns)
    local text = tostring(itemType or "") .. " " .. tostring(displayName or "")
    if EHR_FoodTextHasAny(text, rawPatterns) then return true end

    local dangerousUncooked = EHR_FoodSafeItemMethod(item, "isDangerousUncooked")
        or EHR_FoodSafeItemMethod(item, "getDangerousUncooked")
    return dangerousUncooked == true
end

--[[
    Check if food item is risky for trichinosis
    Returns: riskLevel (0-1), or 0 if safe
]]--
function EHR.Food.CheckTrichinosisRisk(item)
    if not item then return 0 end

    local itemType = ""
    local displayName = ""

    if item.getType then
        local success, t = pcall(function() return item:getType() end)
        if success then itemType = tostring(t) end
    end

    if item.getDisplayName then
        local success, n = pcall(function() return item:getDisplayName() end)
        if success then displayName = tostring(n) end
    end

    local config = EHR.Food.Config.trichinosis

    local isCooked = EHR_FoodSafeItemMethod(item, "isCooked")
    local isBurnt = EHR_FoodSafeItemMethod(item, "isBurnt") or EHR_FoodSafeItemMethod(item, "isBurned")
    if isCooked == true or isBurnt == true then
        return 0
    end

    local itemText = tostring(itemType or "") .. " " .. tostring(displayName or "")

    -- Check if cooked (safe). Crafted foods often expose ingredient state in names,
    -- so this is a safety gate before any meat-name fallback.
    if EHR_FoodTextHasAny(itemText, config.cookedPatterns) then
        return 0
    end

    -- Prepared/crafted meals can include meat ingredient names in display text.
    -- Only treat them as trichinosis risks when the actual consumed item is still raw.
    if EHR_FoodLooksPrepared(itemType, displayName)
        and not EHR_FoodLooksExplicitRaw(item, itemType, displayName, config.rawPatterns) then
        return 0
    end

    -- Check if it's a high-risk raw item
    for itemPattern, risk in pairs(config.highRisk) do
        if EHR_FoodTextHasAny(itemText, {itemPattern}) then
            if EHR_FoodLooksRaw(item, itemType, displayName, config.rawPatterns) then
                return risk
            end
        end
    end

    -- Check medium risk
    for itemPattern, risk in pairs(config.mediumRisk) do
        if EHR_FoodTextHasAny(itemText, {itemPattern}) then
            if EHR_FoodLooksRaw(item, itemType, displayName, config.rawPatterns) then
                return risk
            end
        end
    end

    return 0
end

-- ============================================
-- SANDBOX OPTIONS
-- ============================================

function EHR.Food.IsTrichinosisEnabled()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not options then return true end
    if options.TrichinosisEnabled == nil then return true end
    return options.TrichinosisEnabled
end

function EHR.Food.IsGastroenteritisEnabled()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if not options then return true end
    if options.GastroenteritisEnabled == nil then return true end
    return options.GastroenteritisEnabled
end

-- ============================================
-- FOOD EATING HOOK
-- ============================================

--[[
    Called when player eats food
    This should be hooked into the existing EHR_FoodHook.lua
]]--
function EHR.Food.OnEatFood(player, item)
    if not player or not item then return end

    -- Initialize if needed
    EHR.Food.InitializePlayer(player)

    -- Check for trichinosis risk (raw meat)
    if EHR.Food.IsTrichinosisEnabled() then
        local trichinRisk = EHR.Food.CheckTrichinosisRisk(item)
        if trichinRisk > 0 then
            EHR.Log(string.format("Trichinosis risk detected: %.0f%%", trichinRisk * 100))

            if EHR.Disease and EHR.Disease.TryContract then
                if EHR.Disease.TryContract(player, "trichinosis", trichinRisk) then
                    EHR.Log("Player contracted trichinosis from raw meat!")
                end
            end
        end
    end

    -- Check for gastroenteritis risk (dirty hands)
    if EHR.Food.IsGastroenteritisEnabled() then
        local handRisk = EHR.Food.GetContaminationRisk(player)
        if handRisk > 0.05 then  -- Threshold to avoid constant checks
            EHR.Log(string.format("Gastroenteritis risk from dirty hands: %.0f%%", handRisk * 100))

            if EHR.Disease and EHR.Disease.TryContract then
                if EHR.Disease.TryContract(player, "gastroenteritis", handRisk) then
                    EHR.Log("Player contracted gastroenteritis from dirty hands!")
                end
            end
        end
    end
end

-- ============================================
-- COMBAT/ACTIVITY HOOKS
-- ============================================

--[[
    Called after killing a zombie or animal
]]--
function EHR.Food.OnKillZombie(player)
    -- Add blood contamination to hands
    EHR.Food.ContaminateHands(player, "blood", 0.3)
end

--[[
    Called after butchering/handling raw meat
]]--
function EHR.Food.OnHandleRawMeat(player)
    EHR.Food.ContaminateHands(player, "rawMeat", 0.4)
end

--[[
    Called after outdoor activities (gardening, foraging, etc.)
]]--
function EHR.Food.OnOutdoorActivity(player)
    EHR.Food.ContaminateHands(player, "dirt", 0.2)
end

-- ============================================
-- TETANUS SYSTEM
-- ============================================

local TETANUS_INITIAL_RISK = 0.40
local TETANUS_REROLL_INTERVAL_HOURS = 12
local TETANUS_RISK_STEP = 0.15
local TETANUS_MAX_RISK = 0.70

local function getWorldAgeHoursSafe()
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime then return 0 end

    local ok, hours = pcall(function()
        return gameTime:getWorldAgeHours()
    end)

    if ok and tonumber(hours) then
        return tonumber(hours)
    end

    return 0
end

local function getTrackedTetanusRisk(trackedWound, currentHour)
    if type(trackedWound) ~= "table" then
        return TETANUS_INITIAL_RISK
    end

    local firstSeen = tonumber(trackedWound.firstSeenHour) or currentHour
    local elapsed = math.max(0, currentHour - firstSeen)
    local intervals = math.floor(elapsed / TETANUS_REROLL_INTERVAL_HOURS)

    return math.min(TETANUS_MAX_RISK, TETANUS_INITIAL_RISK + (intervals * TETANUS_RISK_STEP))
end

local function playerAlreadyHasTetanus(player)
    if not EHR.Disease or not EHR.Disease.GetDiseaseData then return false end

    local data = EHR.Disease.GetDiseaseData(player)
    return data and data.active and data.active.tetanus ~= nil
end

--[[
    Check if a wound should trigger tetanus risk
    Called from wound system when deep puncture occurs
]]--
function EHR.Food.CheckTetanusRisk(player, woundType, woundSource, riskOverride)
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.TetanusEnabled == false then return false end

    local woundTypeText = tostring(woundType or ""):lower()
    local sourceText = tostring(woundSource or ""):lower()
    local isDeepWound = woundTypeText:find("deep", 1, true) ~= nil
        or woundTypeText:find("deepwound", 1, true) ~= nil

    if not isDeepWound then return false end

    -- B42 does not expose a reliable "rusty puncture" source, so EHR uses
    -- lodged glass in a deep wound as the concrete high-risk signal.
    local hasGlass = sourceText:find("glass", 1, true) ~= nil
        or sourceText:find("shard", 1, true) ~= nil
    if not hasGlass then return false end

    local baseRisk = math.max(0, math.min(1, tonumber(riskOverride) or TETANUS_INITIAL_RISK))

    if baseRisk > 0 then
        EHR.Log(string.format("Tetanus risk from deep wound with glass: %.0f%%", baseRisk * 100))

        if EHR.Disease and EHR.Disease.TryContract then
            -- Tetanus has delayed contraction (incubation is already long)
            if EHR.Disease.TryContract(player, "tetanus", baseRisk) then
                EHR.Log("Player at risk for tetanus! Incubation period starting...")

                if player.Say then
                    player:Say("That was a nasty wound... hope it doesn't get infected.")
                end

                return true
            end
        end
    end

    return false
end

-- ============================================
-- HAND CONTAMINATION DECAY
-- ============================================

local HAND_TICK_INTERVAL = 300  -- Every 300 ticks (~10 seconds)

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

local function getBodyPartDebugName(partType, fallback)
    if BodyPartType and BodyPartType.ToString and partType then
        local ok, name = pcall(function()
            return BodyPartType.ToString(partType)
        end)
        if ok and name and name ~= "" then return tostring(name) end
    end
    return tostring(fallback or partType or "Unknown")
end

local function bodyPartHasDeepWound(bodyPart)
    if not bodyPart then return false end

    local ok, value = pcall(function()
        return bodyPart:deepWounded()
    end)
    if ok and value == true then return true end

    ok, value = pcall(function()
        return bodyPart:isDeepWounded()
    end)
    if ok and value == true then return true end

    ok, value = pcall(function()
        return bodyPart:getDeepWoundTime()
    end)
    return ok and tonumber(value) and tonumber(value) > 0
end

local function bodyPartHasGlass(bodyPart)
    if not bodyPart then return false end

    local ok, value = pcall(function()
        return bodyPart:haveGlass()
    end)
    return ok and value == true
end

function EHR.Food.ScanTetanusWounds(player)
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.TetanusEnabled == false then return end
    if not player or not player.getBodyDamage then return end
    if not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.FromIndex then return end
    if playerAlreadyHasTetanus(player) then return end

    local bodyDamage = nil
    pcall(function() bodyDamage = player:getBodyDamage() end)
    if not bodyDamage then return end

    local modData = player:getModData()
    if not modData then return end

    modData.EHR_TetanusGlassWounds = modData.EHR_TetanusGlassWounds or {}
    local tracked = modData.EHR_TetanusGlassWounds
    local stillPresent = {}
    local currentHour = getWorldAgeHoursSafe()

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local partType = BodyPartType.FromIndex(i)
        local bodyPart = partType and bodyDamage:getBodyPart(partType) or nil
        if bodyPart and bodyPartHasDeepWound(bodyPart) and bodyPartHasGlass(bodyPart) then
            local partName = getBodyPartDebugName(partType, i)
            stillPresent[partName] = true

            if type(tracked[partName]) ~= "table" then
                tracked[partName] = {
                    firstSeenHour = currentHour,
                    lastRiskHour = nil,
                    attempts = 0,
                    logged = false,
                }
            end

            local woundState = tracked[partName]
            if not woundState.logged then
                EHR.Log("Tetanus scanner: deep wound with glass detected at " .. tostring(partName))
                woundState.logged = true
            end

            local lastRiskHour = tonumber(woundState.lastRiskHour)
            local shouldRoll = lastRiskHour == nil
                or (currentHour - lastRiskHour) >= TETANUS_REROLL_INTERVAL_HOURS

            if shouldRoll then
                woundState.lastRiskHour = currentHour
                woundState.attempts = (tonumber(woundState.attempts) or 0) + 1

                local risk = getTrackedTetanusRisk(woundState, currentHour)
                if EHR.Food.CheckTetanusRisk(player, "DeepWound", "Glass", risk) then
                    woundState.contracted = true
                    return
                end
            end
        end
    end

    for partName, _ in pairs(tracked) do
        if not stillPresent[partName] then
            tracked[partName] = nil
        end
    end
end

local function processPlayerTick(player)
    if not player then return end
    if not player:isAlive() then return end

    -- Initialize if needed
    EHR.Food.InitializePlayer(player)

    -- Throttle updates
    local state = getTickState(player)
    state.tick = state.tick + 1
    if state.tick < HAND_TICK_INTERVAL then
        return
    end
    state.tick = 0

    -- Update hand contamination decay
    EHR.Food.UpdateHandContamination(player)

    -- Check deep wounds with lodged glass once per hand tick.
    EHR.Food.ScanTetanusWounds(player)
end

function EHR.Food.UpdateHandContamination(player)
    local handData = EHR.Food.GetHandData(player)
    if not handData then return end

    local config = EHR.Food.Config.gastroenteritis
    local decayRate = config.contaminationDecay * 0.01  -- Per tick decay

    -- Slowly decay contamination over time
    handData.bloodLevel = math.max(0, handData.bloodLevel - decayRate)
    handData.dirtLevel = math.max(0, handData.dirtLevel - decayRate)
    handData.rawMeatLevel = math.max(0, handData.rawMeatLevel - decayRate)
end

-- ============================================
-- TICK HANDLER
-- ============================================

function EHR.Food.OnTick()
    -- Check if disease system is enabled
    if EHR.Disease and not EHR.Disease.IsEnabled() then return end

    -- MP: server-authoritative processing
    if isClient and isClient() and not (isServer and isServer()) then return end

    local players = getActivePlayers()
    for _, player in ipairs(players) do
        processPlayerTick(player)
    end
end

-- ============================================
-- EVENT HANDLERS
-- ============================================

function EHR.Food.OnGameStart()
    EHR.Log("Food diseases module OnGameStart")

    local player = getSpecificPlayer(0)
    if player then
        EHR.Food.InitializePlayer(player)
    end
end

function EHR.Food.OnCreatePlayer(playerIndex, player)
    EHR.Log("Food diseases module OnCreatePlayer: " .. playerIndex)
    EHR.Food.InitializePlayer(player)
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

-- Guard against double registration
if Events and not EHR.Food._eventsRegistered then
    EHR.Food._eventsRegistered = true

    Events.OnTick.Add(EHR.Food.OnTick)
    Events.OnGameStart.Add(EHR.Food.OnGameStart)
    Events.OnCreatePlayer.Add(EHR.Food.OnCreatePlayer)

    EHR.Log("Food diseases module events registered")
end

EHR.Log("Food diseases module loaded v1.0.0")
