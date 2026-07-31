--[[
    Extensive Health Rework B42
    Food Hook Module

    Hooks into the eating system to detect when player eats risky food.
    Uses ISEatFoodAction override as fallback if OnEat event doesn't exist.

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_EnvironmentalDiseases"
pcall(function() require "ExtensiveHealth/EHR_Medication" end)
require "TimedActions/ISEatFoodAction"

EHR = EHR or {}
EHR.FoodHook = EHR.FoodHook or {}

-- Track if we've already hooked
EHR.FoodHook.initialized = EHR.FoodHook.initialized or false
EHR.FoodHook.drinkInitialized = EHR.FoodHook.drinkInitialized or false
EHR.FoodHook.worldDrinkInitialized = EHR.FoodHook.worldDrinkInitialized or false
EHR.FoodHook.lastFoodRisk = EHR.FoodHook.lastFoodRisk or {}
EHR.FoodHook.lastDrinkRisk = EHR.FoodHook.lastDrinkRisk or {}
EHR.FoodHook.lastFoodRiskCleanupHour = EHR.FoodHook.lastFoodRiskCleanupHour or nil

local function shouldBlockEatingForTetanus(action)
    if not action or not action.character or not action.item then return false end
    if not EHR.Disease or not EHR.Disease.ShouldBlockEatingDueToTetanus then return false end

    local blocked = EHR.Disease.ShouldBlockEatingDueToTetanus(action.character, action.item)
    if blocked and EHR.Disease.WarnTetanusEatingBlocked then
        EHR.Disease.WarnTetanusEatingBlocked(action.character)
    end
    return blocked == true
end

local function markTetanusEatingBlocked(action)
    if not action then return end
    action.EHR_TetanusEatingBlocked = true
    if action.item and action.item.setJobDelta then
        pcall(function() action.item:setJobDelta(0.0) end)
    end
end

local function isTetanusEatingBlocked(action)
    if not action then return false end
    if action.EHR_TetanusEatingBlocked then return true end
    if shouldBlockEatingForTetanus(action) then
        markTetanusEatingBlocked(action)
        return true
    end
    return false
end

local function safeCall(obj, methodName)
    if not obj or not obj[methodName] then return nil end
    local success, result = pcall(function() return obj[methodName](obj) end)
    if success then return result end
    return nil
end

local function safeProperty(obj, key)
    local props = safeCall(obj, "getProperties")
    if not props then return nil end
    local success, result = pcall(function() return props:get(key) end)
    if success then return result end
    return nil
end

local function safeSpriteName(obj)
    local sprite = safeCall(obj, "getSprite")
    if not sprite then return nil end
    return safeCall(sprite, "getName")
end

local function startsWith(value, prefix)
    return type(value) == "string" and string.sub(value, 1, string.len(prefix)) == prefix
end

local function getLocalPlayerKey(player)
    local playerNum = 0
    if player and player.getPlayerNum then
        local success, result = pcall(function() return player:getPlayerNum() end)
        if success and result then playerNum = result end
    end
    return tostring(playerNum)
end

local function getActionItemKey(player, item, prefix)
    local itemId = safeCall(item, "getID") or tostring(item)
    local itemType = safeCall(item, "getFullType") or safeCall(item, "getType") or "unknown"
    return tostring(prefix or "item") .. ":" .. getLocalPlayerKey(player) .. ":" .. tostring(itemId) .. ":" .. tostring(itemType)
end

local function isTaintedWaterSource(source)
    if not source then return false end
    if source.isTaintedWater then
        local success, result = pcall(function() return source:isTaintedWater() end)
        if success then return result == true end
    end
    if source.getTaintedWater then
        local success, result = pcall(function() return source:getTaintedWater() end)
        if success then return result == true end
    end
    if source.getFluidContainer then
        local fluidContainer = safeCall(source, "getFluidContainer")
        if fluidContainer and fluidContainer.contains and Fluid and Fluid.TaintedWater then
            local success, result = pcall(function() return fluidContainer:contains(Fluid.TaintedWater) end)
            if success then return result == true end
        end
    end
    return false
end

local function getWorldWaterSourceType(waterObject)
    if not waterObject then return "unknown" end

    local customName = safeProperty(waterObject, "CustomName")
    local customNameLower = customName and string.lower(tostring(customName)) or ""
    if customNameLower:find("toilet", 1, true) then
        return "toilet"
    elseif customName == "Dispenser" then
        return "tap"
    end

    local spriteName = safeSpriteName(waterObject)
    if startsWith(spriteName, "blends_natural_02") then
        return "river"
    end

    local objectName = safeCall(waterObject, "getName")
    if objectName and string.find(string.lower(tostring(objectName)), "toilet", 1, true) then
        return "toilet"
    end
    if objectName and string.find(string.lower(tostring(objectName)), "rain collector", 1, true) then
        return "rainCollector"
    end

    if spriteName == "carpentry_02_52" or spriteName == "carpentry_02_53" or
            spriteName == "carpentry_02_54" or spriteName == "carpentry_02_55" then
        return "rainCollector"
    end

    if isTaintedWaterSource(waterObject) then
        return "tainted"
    end

    return "tap"
end

function EHR.FoodHook.HandleWaterDrink(player, waterSource, sourceType)
    if not player then return end
    if player ~= getSpecificPlayer(0) then return end

    sourceType = sourceType or "tainted"

    local currentHour = getGameTime():getWorldAgeHours()
    local playerKey = getLocalPlayerKey(player)
    local key = playerKey .. ":" .. tostring(sourceType)
    local lastHour = EHR.FoodHook.lastDrinkRisk[key]
    if lastHour and (currentHour - lastHour) < 0.001 then
        return
    end
    EHR.FoodHook.lastDrinkRisk[key] = currentHour

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR", "DrinkWaterRisk", {
            sourceType = tostring(sourceType),
        })
        return
    end

    if EHR.Environmental and EHR.Environmental.OnDrinkWater then
        EHR.Environmental.OnDrinkWater(player, waterSource, sourceType)
    elseif EHR.Disease and EHR.Disease.TryContract then
        EHR.Disease.TryContract(player, "food_poisoning", 0.25)
    end
end

local function isLocalFoodPlayer(player)
    if not player or not getSpecificPlayer then return false end

    local playerNum = safeCall(player, "getPlayerNum")
    if playerNum ~= nil then
        local ok, localPlayer = pcall(function() return getSpecificPlayer(playerNum) end)
        if ok and localPlayer == player then return true end
    end

    local ok, firstPlayer = pcall(function() return getSpecificPlayer(0) end)
    return ok and firstPlayer == player
end

function EHR.FoodHook.HandleFoodConsumption(player, item, amount)
    if not player or not item then return end
    if not isLocalFoodPlayer(player) then return end

    local currentHour = getGameTime():getWorldAgeHours()
    local lastCleanup = EHR.FoodHook.lastFoodRiskCleanupHour
    if not lastCleanup or currentHour < lastCleanup or (currentHour - lastCleanup) >= 0.10 then
        local cutoff = currentHour - 0.01
        for cachedKey, cachedHour in pairs(EHR.FoodHook.lastFoodRisk) do
            if type(cachedHour) ~= "number" or cachedHour < cutoff or cachedHour > currentHour then
                EHR.FoodHook.lastFoodRisk[cachedKey] = nil
            end
        end
        EHR.FoodHook.lastFoodRiskCleanupHour = currentHour
    end

    local key = getActionItemKey(player, item, "food")
    local lastHour = EHR.FoodHook.lastFoodRisk[key]
    if lastHour and (currentHour - lastHour) < 0.001 then
        return
    end
    EHR.FoodHook.lastFoodRisk[key] = currentHour

    if EHR.DEBUG then
        EHR.Log("FoodHook: Player ate " .. (safeCall(item, "getDisplayName") or safeCall(item, "getName") or "unknown"))
    end

    local itemFullType = safeCall(item, "getFullType")
    local medData = itemFullType and EHR.Medication and EHR.Medication.Database and EHR.Medication.Database[itemFullType] or nil
    if medData and medData.consumeViaFoodHook and EHR.Medication.UseConsumedMedication then
        EHR.Medication.UseConsumedMedication(player, itemFullType)
        return
    end

    if EHR.Disease and EHR.Disease.CheckFoodRisk then
        return EHR.Disease.CheckFoodRisk(player, item, amount)
    end
end

local function handleCompletedFoodAction(action)
    if not action or action.EHR_FoodRiskHandled then return end
    action.EHR_FoodRiskHandled = true
    if action.item and action.character then
        EHR.FoodHook.HandleFoodConsumption(action.character, action.item, action.percentage)
    end
end

--[[
    Override ISEatFoodAction:perform to detect food consumption
    This is called when the eat action completes
]]--
function EHR.FoodHook.Initialize()
    if EHR.FoodHook.initialized then return end

    -- Store original perform function
    local originalPerform = ISEatFoodAction.perform
    local originalIsValidStart = ISEatFoodAction.isValidStart
    local originalIsValid = ISEatFoodAction.isValid
    local originalComplete = ISEatFoodAction.complete
    local originalServerStop = ISEatFoodAction.serverStop
    local originalEat = ISEatFoodAction.eat

    ISEatFoodAction.isValidStart = function(self)
        if shouldBlockEatingForTetanus(self) then
            markTetanusEatingBlocked(self)
            return false
        end

        if originalIsValidStart then
            return originalIsValidStart(self)
        end
        return true
    end

    ISEatFoodAction.isValid = function(self)
        if originalIsValid and not originalIsValid(self) then
            return false
        end

        if shouldBlockEatingForTetanus(self) then
            markTetanusEatingBlocked(self)
            return false
        end

        return true
    end

    ISEatFoodAction.complete = function(self)
        if isTetanusEatingBlocked(self) then
            return false
        end

        local result = originalComplete(self)
        if result ~= false then
            handleCompletedFoodAction(self)
        end
        return result
    end

    ISEatFoodAction.serverStop = function(self)
        if isTetanusEatingBlocked(self) then
            if self.item and self.item.setJobDelta then
                pcall(function() self.item:setJobDelta(0.0) end)
            end
            return
        end

        return originalServerStop(self)
    end

    ISEatFoodAction.eat = function(self, food, percentage)
        if isTetanusEatingBlocked(self) then
            return
        end

        return originalEat(self, food, percentage)
    end

    -- Override with our version
    ISEatFoodAction.perform = function(self)
        if isTetanusEatingBlocked(self) then
            if self.item and self.item.setJobDelta then
                pcall(function() self.item:setJobDelta(0.0) end)
            end
            originalPerform(self)
            return
        end

        -- Call original first
        originalPerform(self)
        handleCompletedFoodAction(self)
    end

    EHR.FoodHook.initialized = true
    EHR.Log("FoodHook: ISEatFoodAction complete/perform hooked successfully")
end

--[[
    Also hook into drinking for contaminated water
]]--
function EHR.FoodHook.InitializeDrink()
    if EHR.FoodHook.drinkInitialized then return end

    -- Check if ISDrinkFromBottle exists
    if not ISDrinkFromBottle then
        EHR.Log("FoodHook: ISDrinkFromBottle not found, skipping drink hook")
        return
    end

    local originalDrinkComplete = ISDrinkFromBottle.complete
    local originalDrinkPerform = ISDrinkFromBottle.perform

    local function handleCompletedBottleDrinkAction(action)
        if not action or action.EHR_BottleWaterRiskHandled then return end
        action.EHR_BottleWaterRiskHandled = true
        if action.item and action.character then
            local player = action.character

            if player == getSpecificPlayer(0) and isTaintedWaterSource(action.item) then
                if EHR.DEBUG then
                    EHR.Log("FoodHook: Player drank tainted bottled water")
                end
                EHR.FoodHook.HandleWaterDrink(player, action.item, "tainted")
            end
        end
    end

    ISDrinkFromBottle.complete = function(self)
        local result = originalDrinkComplete(self)
        if result ~= false then
            handleCompletedBottleDrinkAction(self)
        end
        return result
    end

    ISDrinkFromBottle.perform = function(self)
        -- Call original first
        originalDrinkPerform(self)
        handleCompletedBottleDrinkAction(self)
    end

    EHR.Log("FoodHook: ISDrinkFromBottle complete/perform hooked successfully")
    EHR.FoodHook.drinkInitialized = true
end

function EHR.FoodHook.InitializeWorldDrink()
    if EHR.FoodHook.worldDrinkInitialized then return end

    if not ISTakeWaterAction then
        EHR.Log("FoodHook: ISTakeWaterAction not found, skipping world drink hook")
        return
    end

    local originalTakeWaterComplete = ISTakeWaterAction.complete
    local originalTakeWaterPerform = ISTakeWaterAction.perform

    local function handleCompletedWorldDrinkAction(action)
        -- item == nil means the player drank directly from the world object.
        -- Filling a bottle is handled later by ISDrinkFromBottle when that water is consumed.
        if not action or action.item ~= nil or not action.character or not action.waterObject then return end
        if action.EHR_WorldWaterRiskHandled then return end
        action.EHR_WorldWaterRiskHandled = true

        local player = action.character
        if player == getSpecificPlayer(0) then
            local sourceType = getWorldWaterSourceType(action.waterObject)
            if EHR.DEBUG then
                EHR.Log("FoodHook: Player drank from world water source: " .. tostring(sourceType))
            end
            EHR.FoodHook.HandleWaterDrink(player, action.waterObject, sourceType)
        end
    end

    ISTakeWaterAction.complete = function(self)
        local result = originalTakeWaterComplete(self)
        handleCompletedWorldDrinkAction(self)

        return result
    end

    ISTakeWaterAction.perform = function(self)
        originalTakeWaterPerform(self)
        -- In multiplayer, direct world-water drinking may only reach the
        -- client perform path. The duplicate guard in HandleWaterDrink keeps
        -- solo complete+perform from rolling twice.
        handleCompletedWorldDrinkAction(self)
    end

    EHR.Log("FoodHook: ISTakeWaterAction complete/perform hooked successfully")
    EHR.FoodHook.worldDrinkInitialized = true
end

-- Initialize on game start
function EHR.FoodHook.OnGameStart()
    EHR.FoodHook.Initialize()

    -- Try to hook drinking (may fail if class doesn't exist)
    pcall(function()
        require "TimedActions/ISDrinkFromBottle"
        EHR.FoodHook.InitializeDrink()
    end)

    pcall(function()
        require "TimedActions/ISTakeWaterAction"
        EHR.FoodHook.InitializeWorldDrink()
    end)
end

-- Register
if Events then
    Events.OnGameStart.Add(EHR.FoodHook.OnGameStart)
    EHR.Log("FoodHook module loaded")
end

-- ============================================
-- DEATH/RESPAWN RESET
-- ============================================

-- Reset handler for death/respawn
function EHR.FoodHook.Reset()
    -- The action hook is global. Reinstalling it after respawn stacks wrappers.
    EHR.FoodHook.lastFoodRisk = {}
    EHR.FoodHook.lastDrinkRisk = {}
    EHR.FoodHook.lastFoodRiskCleanupHour = nil
    EHR.Log("FoodHook: Reset - global hook remains installed")
end

-- Register death handler
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(player)
        -- Reset on any player death (hooks are global, not per-player)
        EHR.FoodHook.Reset()
    end)
end
