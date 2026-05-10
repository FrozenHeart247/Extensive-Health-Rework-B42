--[[
    Extensive Health Rework B42
    Food Hook Module

    Hooks into the eating system to detect when player eats risky food.
    Uses ISEatFoodAction override as fallback if OnEat event doesn't exist.

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_EnvironmentalDiseases"
require "TimedActions/ISEatFoodAction"

EHR = EHR or {}
EHR.FoodHook = {}

-- Track if we've already hooked
EHR.FoodHook.initialized = false
EHR.FoodHook.drinkInitialized = false

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

        return originalComplete(self)
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

        -- Now check for disease risk
        if self.item and self.character then
            local player = self.character

            -- Only process for local player
            if player == getSpecificPlayer(0) then
                EHR.Log("FoodHook: Player ate " .. (self.item:getDisplayName() or "unknown"))

                -- Check disease risk
                if EHR.Disease and EHR.Disease.CheckFoodRisk then
                    EHR.Disease.CheckFoodRisk(player, self.item)
                end
            end
        end
    end

    EHR.FoodHook.initialized = true
    EHR.Log("FoodHook: ISEatFoodAction.perform hooked successfully")
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

    local originalDrinkPerform = ISDrinkFromBottle.perform

    ISDrinkFromBottle.perform = function(self)
        -- Call original first
        originalDrinkPerform(self)

        -- Check water source
        if self.item and self.character then
            local player = self.character

            if player == getSpecificPlayer(0) then
                -- Check if water is tainted/not boiled (safely)
                local item = self.item
                local isTainted = false

                -- Try multiple methods for tainted water check
                if item.isTaintedWater then
                    local success, result = pcall(function() return item:isTaintedWater() end)
                    if success then isTainted = result end
                elseif item.getTaintedWater then
                    local success, result = pcall(function() return item:getTaintedWater() end)
                    if success then isTainted = result end
                end

                if isTainted then
                    EHR.Log("FoodHook: Player drank tainted water!")
                    -- Use Environmental module for proper dysentery risk calculation
                    if EHR.Environmental and EHR.Environmental.OnDrink then
                        EHR.Environmental.OnDrink(player, item, "tainted")
                    elseif EHR.Disease and EHR.Disease.TryContract then
                        -- Fallback to food poisoning if Environmental not loaded
                        EHR.Disease.TryContract(player, "food_poisoning", 0.25)
                    end
                end
            end
        end
    end

    EHR.Log("FoodHook: ISDrinkFromBottle.perform hooked successfully")
    EHR.FoodHook.drinkInitialized = true
end

-- Initialize on game start
function EHR.FoodHook.OnGameStart()
    EHR.FoodHook.Initialize()

    -- Try to hook drinking (may fail if class doesn't exist)
    pcall(function()
        require "TimedActions/ISDrinkFromBottle"
        EHR.FoodHook.InitializeDrink()
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
    EHR.Log("FoodHook: Reset - global hook remains installed")
end

-- Register death handler
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(player)
        -- Reset on any player death (hooks are global, not per-player)
        EHR.FoodHook.Reset()
    end)
end
