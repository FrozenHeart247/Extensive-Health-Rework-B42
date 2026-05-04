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

--[[
    Override ISEatFoodAction:perform to detect food consumption
    This is called when the eat action completes
]]--
function EHR.FoodHook.Initialize()
    if EHR.FoodHook.initialized then return end

    -- Store original perform function
    local originalPerform = ISEatFoodAction.perform

    -- Override with our version
    ISEatFoodAction.perform = function(self)
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
    EHR.FoodHook.initialized = false
    EHR.Log("FoodHook: Reset - will re-hook on next game start")
end

-- Register death handler
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(player)
        -- Reset on any player death (hooks are global, not per-player)
        EHR.FoodHook.Reset()
    end)
end
