--[[
    Extensive Health Rework B42
    Food Temperature Effects Module

    Food and drink temperatures affect body temperature over time:
    - Hot foods/drinks (soup, coffee) provide warming effects
    - Cold foods/drinks (ice cream, cold water) provide cooling effects
    - Effects are gradual and decay over 15-60 minutes
    - Liquids act faster, solids act slower but longer

    Integration: Modifies EHR.BodyTemp.CalculateTargetTemp results

    v1.0.0 - Initial implementation
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_BodyTemperature"

EHR = EHR or {}
EHR.FoodTemp = {}

-- ============================================
-- CONFIGURATION
-- ============================================

EHR.FoodTemp.Config = {
    -- Effect strength scaling (how much 1°C food temp difference affects body)
    -- At maxEffect, a 50°C difference (hot soup at 70°C vs body at 37°C) = 0.3°C shift
    effectStrengthFactor = 0.006,  -- Per degree difference

    -- Maximum effect magnitude (prevents extreme shifts)
    maxEffectMagnitude = 0.4,  -- °C

    -- Duration ranges (game hours)
    liquidDurationMin = 0.25,   -- 15 minutes
    liquidDurationMax = 0.5,    -- 30 minutes
    solidDurationMin = 0.5,     -- 30 minutes
    solidDurationMax = 1.0,     -- 60 minutes

    -- Stacking diminishing returns
    maxStackedEffect = 0.6,     -- Maximum total effect from all foods
    stackingFalloff = 0.7,      -- Each additional effect is 70% as strong

    -- Temperature thresholds for categorization
    frozenTemp = 0,             -- Below this = frozen
    coldTemp = 10,              -- Below this = cold
    coolTemp = 20,              -- Below this = cool
    warmTemp = 30,              -- Above this = warm (no effect zone: 20-30)
    hotTemp = 50,               -- Above this = hot
    scaldingTemp = 70,          -- Above this = scalding

    -- Body reference temperature
    bodyTemp = 37.0,
}

-- Food categories that are considered "liquid" (faster effect, shorter duration)
EHR.FoodTemp.LiquidCategories = {
    ["Water"] = true,
    ["WaterBottle"] = true,
    ["Pop"] = true,
    ["Juice"] = true,
    ["Tea"] = true,
    ["Coffee"] = true,
    ["Soup"] = true,
    ["Stew"] = true,
    ["Wine"] = true,
    ["Beer"] = true,
    ["Whiskey"] = true,
    ["Milk"] = true,
}

-- Items explicitly treated as liquid by name pattern
EHR.FoodTemp.LiquidPatterns = {
    "Water",
    "Pop",
    "Juice",
    "Tea",
    "Coffee",
    "Soup",
    "Stew",
    "Broth",
    "Milk",
    "Wine",
    "Beer",
    "Whiskey",
    "Bourbon",
    "Vodka",
}

-- Items explicitly treated as frozen (ice cream, popsicles, etc.)
EHR.FoodTemp.FrozenItems = {
    ["IceCream"] = true,
    ["Popsicle"] = true,
    ["IcePop"] = true,
}

-- ============================================
-- DATA MANAGEMENT
-- ============================================

local FOOD_TEMP_DATA_KEY = "EHR_FoodTempEffects"

--[[
    Initialize food temperature tracking for a player.
    @param player (IsoPlayer)
]]--
function EHR.FoodTemp.InitializePlayer(player)
    if not player then return end

    local modData = player:getModData()
    if not modData then return end

    if not modData[FOOD_TEMP_DATA_KEY] then
        modData[FOOD_TEMP_DATA_KEY] = {
            activeEffects = {},  -- List of {magnitude, remainingHours, isLiquid, sourceName}
            lastUpdateHour = getGameTime():getWorldAgeHours(),
        }
    end

    return modData[FOOD_TEMP_DATA_KEY]
end

--[[
    Get food temperature data for a player.
    @param player (IsoPlayer)
    @return table or nil
]]--
function EHR.FoodTemp.GetFoodTempData(player)
    if not player then return nil end

    local modData = player:getModData()
    if not modData then return nil end

    return modData[FOOD_TEMP_DATA_KEY]
end

-- ============================================
-- FOOD ANALYSIS
-- ============================================

--[[
    Check if an item is a liquid (drinks, soups, etc.)
    @param item (InventoryItem)
    @return boolean
]]--
function EHR.FoodTemp.IsLiquid(item)
    if not item then return false end

    -- Check display category
    local category = item:getDisplayCategory()
    if category and EHR.FoodTemp.LiquidCategories[category] then
        return true
    end

    -- Check item name patterns
    local itemName = item:getName() or ""
    local fullType = item:getFullType() or ""

    for _, pattern in ipairs(EHR.FoodTemp.LiquidPatterns) do
        if string.find(itemName, pattern) or string.find(fullType, pattern) then
            return true
        end
    end

    -- Check if it's a water container
    if item:isWaterSource() then
        return true
    end

    return false
end

--[[
    Check if an item is explicitly frozen (like ice cream)
    @param item (InventoryItem)
    @return boolean
]]--
function EHR.FoodTemp.IsFrozenItem(item)
    if not item then return false end

    local itemName = item:getName() or ""
    local fullType = item:getFullType() or ""

    -- Check explicit list
    for frozenName, _ in pairs(EHR.FoodTemp.FrozenItems) do
        if string.find(itemName, frozenName) or string.find(fullType, frozenName) then
            return true
        end
    end

    -- Check if item name contains "ice" or "frozen"
    local lowerName = string.lower(itemName)
    if string.find(lowerName, "ice") or string.find(lowerName, "frozen") or string.find(lowerName, "popsicle") then
        return true
    end

    return false
end

--[[
    Get the effective temperature of a food item.
    @param item (InventoryItem)
    @return number - Temperature in Celsius
]]--
function EHR.FoodTemp.GetFoodTemperature(item)
    if not item then return 20 end  -- Room temp default

    -- Try to get actual item temperature
    local temp = 20  -- Default room temperature

    local success, result = pcall(function()
        if item.getTemperature then
            return item:getTemperature()
        end
        return nil
    end)

    if success and result then
        temp = result
    end

    -- Override for explicitly frozen items (they should be very cold)
    if EHR.FoodTemp.IsFrozenItem(item) then
        temp = math.min(temp, -5)  -- At least -5°C
    end

    return temp
end

--[[
    Calculate the effect of consuming a food item.
    @param item (InventoryItem)
    @param hungerReduction (number) - How much hunger the food satisfied (0-1)
    @return table - {magnitude, durationHours, isLiquid}
]]--
function EHR.FoodTemp.CalculateFoodEffect(item, hungerReduction)
    if not item then return nil end

    local cfg = EHR.FoodTemp.Config
    local foodTemp = EHR.FoodTemp.GetFoodTemperature(item)
    local isLiquid = EHR.FoodTemp.IsLiquid(item)

    -- Calculate temperature difference from body
    local tempDiff = foodTemp - cfg.bodyTemp

    -- No effect for room-temperature food (20-30°C range)
    if foodTemp >= cfg.coolTemp and foodTemp <= cfg.warmTemp then
        return nil
    end

    -- Calculate base magnitude (positive = warming, negative = cooling)
    local magnitude = tempDiff * cfg.effectStrengthFactor

    -- Scale by portion size (hunger reduction as proxy)
    -- Larger meals = stronger effect
    local portionMultiplier = 0.5 + (hungerReduction or 0.3) * 1.0  -- 0.5 to 1.5x
    magnitude = magnitude * portionMultiplier

    -- Clamp magnitude
    magnitude = math.max(-cfg.maxEffectMagnitude, math.min(cfg.maxEffectMagnitude, magnitude))

    -- If magnitude is negligible, skip
    if math.abs(magnitude) < 0.02 then
        return nil
    end

    -- Calculate duration
    local durationHours
    if isLiquid then
        -- Liquids: faster onset, shorter duration
        local durationRange = cfg.liquidDurationMax - cfg.liquidDurationMin
        durationHours = cfg.liquidDurationMin + (math.abs(magnitude) / cfg.maxEffectMagnitude) * durationRange
    else
        -- Solids: slower onset, longer duration
        local durationRange = cfg.solidDurationMax - cfg.solidDurationMin
        durationHours = cfg.solidDurationMin + (math.abs(magnitude) / cfg.maxEffectMagnitude) * durationRange
    end

    return {
        magnitude = magnitude,
        durationHours = durationHours,
        isLiquid = isLiquid,
        sourceName = item:getName() or "Food",
        sourceTemp = foodTemp,
    }
end

-- ============================================
-- EFFECT APPLICATION
-- ============================================

--[[
    Add a food temperature effect for a player.
    @param player (IsoPlayer)
    @param effect (table) - From CalculateFoodEffect
]]--
function EHR.FoodTemp.AddEffect(player, effect)
    if not player or not effect then return end

    local data = EHR.FoodTemp.GetFoodTempData(player)
    if not data then
        data = EHR.FoodTemp.InitializePlayer(player)
    end
    if not data then return end

    -- Apply stacking diminishing returns
    local existingCount = #data.activeEffects
    local stackingMult = math.pow(EHR.FoodTemp.Config.stackingFalloff, existingCount)

    local adjustedEffect = {
        magnitude = effect.magnitude * stackingMult,
        remainingHours = effect.durationHours,
        initialDuration = effect.durationHours,
        isLiquid = effect.isLiquid,
        sourceName = effect.sourceName,
        sourceTemp = effect.sourceTemp,
    }

    table.insert(data.activeEffects, adjustedEffect)

    if EHR.DEBUG then
        local tempType = effect.magnitude > 0 and "warming" or "cooling"
        EHR.Log(string.format("FoodTemp: Added %s effect from %s (%.1f°C food): %+.2f°C for %.1f min",
            tempType, effect.sourceName, effect.sourceTemp,
            adjustedEffect.magnitude, adjustedEffect.remainingHours * 60))
    end
end

--[[
    Update active food effects (decay over time).
    @param player (IsoPlayer)
    @param deltaHours (number) - Game hours elapsed
]]--
function EHR.FoodTemp.UpdateEffects(player, deltaHours)
    if not player or deltaHours <= 0 then return end

    local data = EHR.FoodTemp.GetFoodTempData(player)
    if not data or not data.activeEffects then return end

    -- Update each effect
    local newEffects = {}
    for _, effect in ipairs(data.activeEffects) do
        effect.remainingHours = effect.remainingHours - deltaHours

        -- Keep if still active
        if effect.remainingHours > 0 then
            table.insert(newEffects, effect)
        elseif EHR.DEBUG then
            EHR.Log(string.format("FoodTemp: Effect from %s expired", effect.sourceName))
        end
    end

    data.activeEffects = newEffects
end

--[[
    Get the total temperature modifier from all active food effects.
    Effects decay linearly over their duration.
    @param player (IsoPlayer)
    @return number - Temperature modifier in °C
]]--
function EHR.FoodTemp.GetTotalModifier(player)
    if not player then return 0 end

    local data = EHR.FoodTemp.GetFoodTempData(player)
    if not data or not data.activeEffects then return 0 end

    local total = 0
    local cfg = EHR.FoodTemp.Config

    for _, effect in ipairs(data.activeEffects) do
        -- Calculate current strength (linear decay)
        local progress = effect.remainingHours / effect.initialDuration
        local currentMagnitude = effect.magnitude * progress

        total = total + currentMagnitude
    end

    -- Clamp total effect
    total = math.max(-cfg.maxStackedEffect, math.min(cfg.maxStackedEffect, total))

    return total
end

--[[
    Get active effects summary for UI display.
    @param player (IsoPlayer)
    @return table - {warming = number, cooling = number, effects = {}}
]]--
function EHR.FoodTemp.GetEffectsSummary(player)
    if not player then return {warming = 0, cooling = 0, effects = {}} end

    local data = EHR.FoodTemp.GetFoodTempData(player)
    if not data or not data.activeEffects then
        return {warming = 0, cooling = 0, effects = {}}
    end

    local warming = 0
    local cooling = 0
    local effects = {}

    for _, effect in ipairs(data.activeEffects) do
        local progress = effect.remainingHours / effect.initialDuration
        local currentMagnitude = effect.magnitude * progress

        if currentMagnitude > 0 then
            warming = warming + currentMagnitude
        else
            cooling = cooling + math.abs(currentMagnitude)
        end

        table.insert(effects, {
            name = effect.sourceName,
            magnitude = currentMagnitude,
            remainingMinutes = effect.remainingHours * 60,
            isLiquid = effect.isLiquid,
        })
    end

    return {
        warming = warming,
        cooling = cooling,
        effects = effects,
    }
end

-- ============================================
-- INTEGRATION WITH BODY TEMPERATURE
-- ============================================

-- Store original function for hooking
local originalCalculateTargetTemp = EHR.BodyTemp.CalculateTargetTemp

--[[
    Enhanced CalculateTargetTemp that includes food temperature effects.
    Wraps the original function and adds food modifier.
]]--
function EHR.BodyTemp.CalculateTargetTemp(player)
    -- Call original calculation
    local targetTemp = originalCalculateTargetTemp(player)

    -- Add food temperature modifier
    local foodModifier = EHR.FoodTemp.GetTotalModifier(player)
    if foodModifier ~= 0 then
        targetTemp = targetTemp + foodModifier

        if EHR.DEBUG and math.abs(foodModifier) > 0.01 then
            EHR.Log(string.format("FoodTemp: Applied modifier %+.2f°C to target temp", foodModifier))
        end
    end

    -- Clamp to survivable range
    local cfg = EHR.BodyTemp.Config
    return math.max(cfg.minBodyTemp, math.min(cfg.maxBodyTemp, targetTemp))
end

-- ============================================
-- FOOD CONSUMPTION HOOK
-- ============================================

-- Track last hunger value to detect eating
local lastHungerValues = {}

--[[
    Called when a player eats food.
    @param player (IsoPlayer)
    @param item (InventoryItem) - The food item consumed
    @param hungerReduction (number) - Hunger reduced (0-1 scale)
]]--
function EHR.FoodTemp.OnFoodConsumed(player, item, hungerReduction)
    if not player or not item then return end

    -- Calculate effect
    local effect = EHR.FoodTemp.CalculateFoodEffect(item, hungerReduction)

    if effect then
        EHR.FoodTemp.AddEffect(player, effect)

        -- Optional: Show feedback dialogue for significant effects
        if math.abs(effect.magnitude) >= 0.15 then
            local text
            if effect.magnitude > 0 then
                if effect.sourceTemp >= EHR.FoodTemp.Config.scaldingTemp then
                    text = getText("UI_EHR_Food_Scalding") or "*The hot food warms me from the inside*"
                else
                    text = getText("UI_EHR_Food_Warming") or "*That warmed me up a bit*"
                end
            else
                if effect.sourceTemp <= EHR.FoodTemp.Config.frozenTemp then
                    text = getText("UI_EHR_Food_Frozen") or "*Brr, that's cold!*"
                else
                    text = getText("UI_EHR_Food_Cooling") or "*That cooled me down*"
                end
            end

            if EHR.Dialogue and EHR.Dialogue.SayPeriodic then
                EHR.Dialogue.SayPeriodic(player, text, 0.5)  -- 50% chance
            end
        end
    end
end

--[[
    Hook into the eating action completion.
    B42 uses ISEatFoodAction or similar.
]]--
local originalEatPerform = nil

local function hookEatAction()
    -- Try to hook ISEatFoodAction
    if ISEatFoodAction and ISEatFoodAction.perform then
        originalEatPerform = ISEatFoodAction.perform

        ISEatFoodAction.perform = function(self)
            -- Store hunger before eating
            local player = self.character
            local hungerBefore = 0
            if player then
                local stats = player:getStats()
                if stats and CharacterStat and CharacterStat.HUNGER then
                    local success, val = pcall(function() return stats:get(CharacterStat.HUNGER) end)
                    if success and val then hungerBefore = val end
                end
            end

            -- Call original
            originalEatPerform(self)

            -- Calculate hunger reduction and trigger our hook
            if player and self.item then
                local hungerAfter = 0
                local stats = player:getStats()
                if stats and CharacterStat and CharacterStat.HUNGER then
                    local success, val = pcall(function() return stats:get(CharacterStat.HUNGER) end)
                    if success and val then hungerAfter = val end
                end

                local hungerReduction = hungerBefore - hungerAfter
                if hungerReduction < 0 then hungerReduction = 0.2 end  -- Default if calculation fails

                EHR.FoodTemp.OnFoodConsumed(player, self.item, hungerReduction)
            end
        end

        if EHR.DEBUG then
            EHR.Log("FoodTemp: Hooked ISEatFoodAction.perform")
        end
    end
end

-- ============================================
-- DRINK ACTION HOOK
-- ============================================

local originalDrinkPerform = nil

local function hookDrinkAction()
    -- Try to hook ISTakePillAction (also handles drinks in some cases)
    -- and ISInventoryPaneContextMenu water drinking

    -- Hook drink action if available
    if ISDrinkFromBottle and ISDrinkFromBottle.perform then
        local origDrink = ISDrinkFromBottle.perform

        ISDrinkFromBottle.perform = function(self)
            local player = self.character
            local thirstBefore = 0
            if player then
                local stats = player:getStats()
                if stats and CharacterStat and CharacterStat.THIRST then
                    local success, val = pcall(function() return stats:get(CharacterStat.THIRST) end)
                    if success and val then thirstBefore = val end
                end
            end

            origDrink(self)

            if player and self.item then
                -- Estimate "portion" from thirst reduction
                local thirstAfter = 0
                local stats = player:getStats()
                if stats and CharacterStat and CharacterStat.THIRST then
                    local success, val = pcall(function() return stats:get(CharacterStat.THIRST) end)
                    if success and val then thirstAfter = val end
                end

                local thirstReduction = thirstBefore - thirstAfter
                if thirstReduction < 0 then thirstReduction = 0.15 end

                EHR.FoodTemp.OnFoodConsumed(player, self.item, thirstReduction)
            end
        end

        if EHR.DEBUG then
            EHR.Log("FoodTemp: Hooked ISDrinkFromBottle.perform")
        end
    end
end

-- ============================================
-- TICK UPDATE
-- ============================================

local foodTempTickCounter = 0
local FOOD_TEMP_TICK_INTERVAL = 60  -- Same interval as body temp

function EHR.FoodTemp.OnTick()
    local player = getSpecificPlayer(0)
    if not player then return end
    if not player:isAlive() then return end

    -- Throttled updates
    foodTempTickCounter = foodTempTickCounter + 1
    if foodTempTickCounter < FOOD_TEMP_TICK_INTERVAL then return end
    foodTempTickCounter = 0

    -- Initialize if needed
    local data = EHR.FoodTemp.GetFoodTempData(player)
    if not data then
        data = EHR.FoodTemp.InitializePlayer(player)
    end
    if not data then return end

    -- Calculate delta time
    local currentHour = getGameTime():getWorldAgeHours()
    local deltaHours = currentHour - (data.lastUpdateHour or currentHour)

    -- Sanity check
    if deltaHours > 1 or deltaHours < 0 then
        deltaHours = 0.05
    end
    data.lastUpdateHour = currentHour

    -- Update effects (decay)
    EHR.FoodTemp.UpdateEffects(player, deltaHours)
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

local function onGameStart()
    -- Hook eating actions after game loads
    hookEatAction()
    hookDrinkAction()

    if EHR.DEBUG then
        EHR.Log("FoodTemp: Game start hooks initialized")
    end
end

if Events then
    if Events.OnTick then
        Events.OnTick.Add(EHR.FoodTemp.OnTick)
    end

    if Events.OnGameStart then
        Events.OnGameStart.Add(onGameStart)
    end
end

EHR.Log("Food Temperature module loaded v1.0.0")
