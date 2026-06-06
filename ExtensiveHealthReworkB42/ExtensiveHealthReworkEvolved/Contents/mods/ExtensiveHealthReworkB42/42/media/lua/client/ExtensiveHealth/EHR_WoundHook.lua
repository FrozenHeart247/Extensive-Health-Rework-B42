--[[
    Extensive Health Rework B42
    Wound Treatment Hook Module

    Hooks into vanilla medical actions to integrate with wound infection system:
    - Disinfectant application (alcohol wipes, disinfectant)
    - Antibiotics (pills) for wound infection
    - IV antibiotics for sepsis (context menu on IV bag)

    v1.0.0

    B42 API Notes:
    - ISApplyBandage handles bandaging and disinfecting
    - ISTakePill handles pill consumption
    - Use item:getFullType() for item identification
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_WoundInfection"
require "ExtensiveHealth/EHR_Sepsis"
require "ExtensiveHealth/EHR_Medication"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.WoundHook = {}

local function woundHookText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_WoundHook_" .. tostring(key), fallback)
    end
    local fullKey = "UI_EHR_WoundHook_" .. tostring(key)
    local ok, value = pcall(getText, fullKey)
    if ok and value and value ~= fullKey then return value end
    return fallback
end

local function woundHookFormat(key, fallback, ...)
    if EHR and EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format("UI_EHR_WoundHook_" .. tostring(key), fallback, ...)
    end
    local text = woundHookText(key, fallback)
    local args = {...}
    for i, value in ipairs(args) do
        text = tostring(text):gsub("%%" .. tostring(i), tostring(value))
    end
    return text
end


-- Track initialization
EHR.WoundHook.initialized = false

-- ============================================
-- ITEM IDENTIFICATION
-- ============================================

-- Disinfectant items (trigger OnDisinfect)
EHR.WoundHook.DisinfectantItems = {
    ["Base.AlcoholWipes"] = true,
    ["Base.Disinfectant"] = true,
    ["Base.AlcoholBandage"] = true,
    ["ExtensiveHealth.AlchoholicBandage"] = true,
    ["Base.Alcohol"] = true,  -- Bourbon/whiskey used as disinfectant
    ["Base.Whiskey"] = true,
    ["Base.WhiskeyFull"] = true,
}

-- Antibiotic items (treat wound infection)
EHR.WoundHook.AntibioticItems = {
    ["Base.Antibiotics"] = true,
    ["Base.PillsAntibiotics"] = true,
}

-- IV Antibiotic items (treat sepsis) - custom or modded
EHR.WoundHook.IVAntibioticItems = {
    ["ExtensiveHealth.IVAntibiotics"] = true,
    ["Base.IVAntibiotics"] = true,  -- In case vanilla adds it
}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

--[[
    Check if item is a disinfectant
]]--
function EHR.WoundHook.IsDisinfectant(item)
    if not item then return false end
    local fullType = item:getFullType()
    return EHR.WoundHook.DisinfectantItems[fullType] == true
end

--[[
    Check if item is antibiotics
]]--
function EHR.WoundHook.IsAntibiotics(item)
    if not item then return false end
    local fullType = item:getFullType()
    return EHR.WoundHook.AntibioticItems[fullType] == true
end

--[[
    Check if item is IV antibiotics
]]--
function EHR.WoundHook.IsIVAntibiotics(item)
    if not item then return false end
    local fullType = item:getFullType()
    return EHR.WoundHook.IVAntibioticItems[fullType] == true
end

local function getContextOptions(context)
    if not context then return {} end

    if context.getOptions then
        local ok, options = pcall(function()
            return context:getOptions()
        end)
        if ok and type(options) == "table" then
            return options
        end
    end

    if type(context.options) == "table" then
        return context.options
    end

    return {}
end

function EHR.WoundHook.HasTreatableWoundInfection(player)
    if not player or not EHR.WoundInfection or not EHR.WoundInfection.GetData then
        return false
    end

    local data = EHR.WoundInfection.GetData(player)
    if not data then return false end
    if data.parts then
        for _, partData in pairs(data.parts) do
            if partData and (tonumber(partData.stage) or 0) > 0 then
                return true
            end
        end
    end
    return (tonumber(data.worstStage) or 0) > 0
end

-- ============================================
-- BANDAGE/DISINFECT HOOK
-- ============================================

--[[
    Hook into ISApplyBandage to detect disinfectant use
]]--
function EHR.WoundHook.HookBandageAction()
    -- Try to require the bandage action
    local success = pcall(function()
        require "TimedActions/ISApplyBandage"
    end)

    if not success or not ISApplyBandage then
        EHR.Log("WoundHook: ISApplyBandage not found, trying alternative")
        return false
    end

    -- Store original perform
    local originalPerform = ISApplyBandage.perform

    -- Override perform
    ISApplyBandage.perform = function(self)
        -- Call original first
        originalPerform(self)

        -- Check if this was a disinfect action
        local player = self.character
        local item = self.item or self.bandage
        local bodyPart = self.bodyPart

        local patient = self.otherPlayer or self.character
        if player and patient == player and player == getSpecificPlayer(0) then
            -- Check if used disinfectant
            if item and EHR.WoundHook.IsDisinfectant(item) then
                EHR.Log("WoundHook: Disinfectant applied to " .. tostring(bodyPart))

                -- Get body part type
                local bodyPartType = nil
                if bodyPart then
                    -- bodyPart might be a BodyPart object, get its type
                    if bodyPart.getType then
                        local success2, partType = pcall(function() return bodyPart:getType() end)
                        if success2 then bodyPartType = partType end
                    else
                        -- Might already be a BodyPartType
                        bodyPartType = bodyPart
                    end
                end

                if bodyPartType and EHR.WoundInfection and EHR.WoundInfection.OnDisinfect then
                    EHR.WoundInfection.OnDisinfect(player, bodyPartType)
                end
            end

            -- Also check if bandaging (updates our tracking)
            if bodyPart and EHR.WoundInfection then
                -- Bandage was applied - our system will detect this on next scan
                -- via the wounds.isBandaged check
                if EHR.DEBUG then
                    EHR.Log("WoundHook: Bandage applied, system will detect on next scan")
                end
            end
        end
    end

    EHR.Log("WoundHook: ISApplyBandage.perform hooked")
    return true
end

-- ============================================
-- PILL/ANTIBIOTICS HOOK
-- ============================================

--[[
    Hook into ISTakePill to detect antibiotic consumption
]]--
function EHR.WoundHook.HookPillAction()
    -- Try to require the pill action
    local success = pcall(function()
        require "TimedActions/ISTakePill"
    end)

    if not success or not ISTakePill then
        EHR.Log("WoundHook: ISTakePill not found")
        return false
    end

    -- Store original perform
    local originalPerform = ISTakePill.perform

    -- Override perform
    ISTakePill.perform = function(self)
        -- Capture item before original (might be consumed)
        local item = self.item
        local player = self.character
        local isAntibiotics = item and EHR.WoundHook.IsAntibiotics(item)

        -- Call original
        originalPerform(self)

        -- Process antibiotics
        if player and player == getSpecificPlayer(0) and isAntibiotics then
            EHR.Log("WoundHook: Player took antibiotics")

            -- First check if player has sepsis - antibiotics help but IV needed
            if EHR.Sepsis and EHR.Sepsis.HasSepsis and EHR.Sepsis.HasSepsis(player) then
                -- Pills slow sepsis but don't cure it
                local data = EHR.Sepsis.GetData(player)
                if data then
                    -- Reset stage timer (buys time)
                    local gameTime = getGameTime()
                    data.stageStartTime = gameTime:getWorldAgeHours()
                    EHR.Locale.Say(player, "The antibiotics might slow this down... but I need IV treatment.")
                    EHR.Log("WoundHook: Antibiotics slowed sepsis progression")
                end
            end

            -- Treat wound infections
            if EHR.WoundInfection and EHR.WoundInfection.OnTakeAntibiotics then
                EHR.WoundInfection.OnTakeAntibiotics(player)
            end
        end
    end

    EHR.Log("WoundHook: ISTakePill.perform hooked")
    return true
end

-- ============================================
-- ALTERNATIVE: Hook ISEatFoodAction for pills
-- Some versions use eating action for pills
-- ============================================

function EHR.WoundHook.HookEatAction()
    -- Try to require eat action
    local success = pcall(function()
        require "TimedActions/ISEatFoodAction"
    end)

    if not success or not ISEatFoodAction then
        return false
    end

    -- Check if already hooked by FoodHook
    if EHR.FoodHook and EHR.FoodHook.initialized then
        -- Extend the existing hook instead
        local existingPerform = ISEatFoodAction.perform

        ISEatFoodAction.perform = function(self)
            -- Capture item info before calling original
            local item = self.item
            local player = self.character
            local isAntibiotics = item and EHR.WoundHook.IsAntibiotics(item)

            -- Call whatever was there before (includes FoodHook's override)
            existingPerform(self)

            -- Process antibiotics if eaten
            if player and player == getSpecificPlayer(0) and isAntibiotics then
                EHR.Log("WoundHook: Player ate antibiotics (via eat action)")

                -- Treat sepsis (pills slow but don't cure)
                if EHR.Sepsis and EHR.Sepsis.HasSepsis and EHR.Sepsis.HasSepsis(player) then
                    local data = EHR.Sepsis.GetData(player)
                    if data then
                        local gameTime = getGameTime()
                        data.stageStartTime = gameTime:getWorldAgeHours()
                        EHR.Locale.Say(player, "The antibiotics might slow this down... but I need IV treatment.")
                    end
                end

                -- Treat wound infections
                if EHR.WoundInfection and EHR.WoundInfection.OnTakeAntibiotics then
                    EHR.WoundInfection.OnTakeAntibiotics(player)
                end
            end
        end

        EHR.Log("WoundHook: Extended ISEatFoodAction for antibiotics")
        return true
    end

    return false
end

-- ============================================
-- DISINFECT ACTION HOOK (Alternative)
-- Some versions have separate ISDisinfect
-- ============================================

function EHR.WoundHook.HookDisinfectAction()
    -- Try to require disinfect action
    local success = pcall(function()
        require "TimedActions/ISDisinfect"
    end)

    if not success or not ISDisinfect then
        EHR.Log("WoundHook: ISDisinfect not found (using ISApplyBandage)")
        return false
    end

    -- Store original perform
    local originalPerform = ISDisinfect.perform

    -- Override perform
    ISDisinfect.perform = function(self)
        -- Call original first
        originalPerform(self)

        local player = self.character
        local bodyPart = self.bodyPart

        local patient = self.otherPlayer or self.character
        if player and patient == player and player == getSpecificPlayer(0) and bodyPart then
            EHR.Log("WoundHook: ISDisinfect performed")

            local bodyPartType = nil
            if bodyPart.getType then
                local success2, partType = pcall(function() return bodyPart:getType() end)
                if success2 then bodyPartType = partType end
            else
                bodyPartType = bodyPart
            end

            if bodyPartType and EHR.WoundInfection and EHR.WoundInfection.OnDisinfect then
                EHR.WoundInfection.OnDisinfect(player, bodyPartType)
            end
        end
    end

    EHR.Log("WoundHook: ISDisinfect.perform hooked")
    return true
end

-- ============================================
-- CONTEXT MENU FOR IV ANTIBIOTICS
-- ============================================

--[[
    Add context menu option for IV antibiotics
]]--
function EHR.WoundHook.OnFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    -- Check each item
    for i = 1, #items do
        local item = items[i]

        -- Handle item stacks
        if not instanceof(item, "InventoryItem") then
            if item.items then
                item = item.items[1]
            end
        end

        if item and EHR.WoundHook.IsIVAntibiotics(item) then
            local hasSepsis = EHR.Sepsis and EHR.Sepsis.HasSepsis and EHR.Sepsis.HasSepsis(player)
            local hasWoundInfection = EHR.WoundHook.HasTreatableWoundInfection(player)
            local hasTreatableCondition = hasSepsis or hasWoundInfection
            local inventory = player:getInventory()
            local hasIVKit = inventory and inventory:containsTypeRecurse("ExtensiveHealth.IVKit")

            if hasTreatableCondition and hasIVKit then
                -- Add "Administer IV Antibiotics" option
                local option = context:addOption(
                    woundHookText("AdministerIVAntibiotics", "Administer IV Antibiotics"),
                    player,
                    EHR.WoundHook.OnAdministerIVAntibiotics,
                    item
                )
                if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

                -- Add tooltip
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(woundHookText("IVAntibiotics", "IV Antibiotics"))

                local targetText = hasSepsis and woundHookText("Sepsis", "sepsis") or woundHookText("WoundInfection", "wound infection")
                tooltip.description = woundHookFormat("StartsIVTreatment", "Starts IV antibiotic treatment for %1.", targetText)
                option.toolTip = tooltip
            elseif hasTreatableCondition then
                local option = context:addOption(woundHookText("AdministerIVRequiresKit", "Administer IV Antibiotics (Requires IV Kit)"), player)
                option.notAvailable = true
                if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(woundHookText("IVAntibiotics", "IV Antibiotics"))
                tooltip.description = woundHookText("RequiresIVKit", "Requires an IV Administration Kit.")
                option.toolTip = tooltip
            else
                local option = context:addOption(woundHookText("AdministerIVNoInfection", "Administer IV Antibiotics (No Infection)"), player)
                option.notAvailable = true
                if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(woundHookText("IVAntibiotics", "IV Antibiotics"))
                tooltip.description = woundHookText("NoInfectionToTreat", "No sepsis or wound infection to treat.")
                option.toolTip = tooltip
            end
        end

        -- Also add option for regular antibiotics if player has wound infection
        if item and EHR.WoundHook.IsAntibiotics(item) then
            local hasInfection = false
            if EHR.WoundInfection and EHR.WoundInfection.GetData then
                local data = EHR.WoundInfection.GetData(player)
                if data and data.worstStage and data.worstStage >= 2 then
                    hasInfection = true
                end
            end

            if hasInfection then
                -- Show infection status in tooltip
                local existingOptions = getContextOptions(context)
                for _, opt in ipairs(existingOptions) do
                    if opt.name and string.find(opt.name, "Antibiotics") then
                        local tooltip = ISWorldObjectContextMenu.addToolTip()
                        tooltip:setName(woundHookText("Antibiotics", "Antibiotics"))
                        tooltip.description = woundHookText("AntibioticsHelpWound", "Will help treat your wound infection.")
                        opt.toolTip = tooltip
                        if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(opt, item) end
                        break
                    end
                end
            end
        end
    end
end

--[[
    Administer IV antibiotics callback
]]--
function EHR.WoundHook.OnAdministerIVAntibiotics(player, item)
    if not player or not item then return end

    EHR.Log("WoundHook: Administering IV antibiotics")

    local inventory = player:getInventory()
    if not inventory then return end

    if not inventory:containsTypeRecurse("ExtensiveHealth.IVKit") then
        if player:isLocalPlayer() then
            EHR.Locale.Say(player, "I need an IV administration kit.")
        end
        return
    end

    if EHR.Medication and EHR.Medication.Database and EHR.Medication.Database[item:getFullType()]
        and EHR.Medication.UseMedication then
        EHR.Medication.UseMedication(player, item)
        return
    end

    -- Legacy fallback for non-database IV antibiotic items.
    local consumed = false
    if EHR.Sepsis and EHR.Sepsis.OnTakeIVAntibiotics then
        consumed = EHR.Sepsis.OnTakeIVAntibiotics(player)
    end

    -- Remove item from inventory if consumed (with MP sync)
    if consumed then
        local ivKit = inventory:getFirstTypeRecurse("ExtensiveHealth.IVKit")
        if ivKit and EHR.Medication and EHR.Medication.ConsumeOneDose then
            EHR.Medication.ConsumeOneDose(player, ivKit, inventory)
        end

        if EHR.Medication and EHR.Medication.ConsumeOneDose then
            EHR.Medication.ConsumeOneDose(player, item, inventory)
        else
            if isClient() then
                sendClientCommand(player, "EHR", "RemoveItem", {itemID = item:getID()})
            end
            inventory:Remove(item)
        end
    end
end

-- ============================================
-- INITIALIZATION
-- ============================================

function EHR.WoundHook.Initialize()
    if EHR.WoundHook.initialized then return end

    EHR.Log("WoundHook: Initializing treatment hooks...")

    -- Hook bandage/disinfect action
    EHR.WoundHook.HookBandageAction()

    -- Try alternative disinfect hook
    EHR.WoundHook.HookDisinfectAction()

    -- Hook pill action
    local pillHooked = EHR.WoundHook.HookPillAction()

    -- If pill hook failed, try eating action
    if not pillHooked then
        EHR.WoundHook.HookEatAction()
    end

    EHR.WoundHook.initialized = true
    EHR.Log("WoundHook: Initialization complete")
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

function EHR.WoundHook.OnGameStart()
    EHR.WoundHook.Initialize()
end

if Events then
    Events.OnGameStart.Add(EHR.WoundHook.OnGameStart)

    -- Context menu hook for IV antibiotics
    Events.OnFillInventoryObjectContextMenu.Add(EHR.WoundHook.OnFillInventoryObjectContextMenu)

    EHR.Log("WoundHook module loaded")
end

-- ============================================
-- DEATH/RESPAWN RESET
-- ============================================

-- Reset handler for death/respawn
function EHR.WoundHook.Reset()
    EHR.WoundHook.initialized = false
    EHR.Log("WoundHook: Reset - will re-hook on next game start")
end

-- Register death handler
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(player)
        -- Reset on any player death
        EHR.WoundHook.Reset()
    end)
end
