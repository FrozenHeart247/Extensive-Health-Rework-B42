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

local function WoundHookIsLocalDoctor(doctor)
    if not doctor then return false end

    if getSpecificPlayer then
        local localPlayer = getSpecificPlayer(0)
        if localPlayer and doctor == localPlayer then return true end
    end

    if getPlayer then
        local localPlayer = getPlayer()
        if localPlayer and doctor == localPlayer then return true end
    end

    return false
end

local function WoundHookGetBodyPartType(bodyPart)
    if not bodyPart then return nil end
    if bodyPart.getType then
        local success, partType = pcall(function() return bodyPart:getType() end)
        if success then return partType end
    end
    return bodyPart
end

local function WoundHookDisinfectDebug(message)
    if not EHR or EHR.DISINFECT_DEBUG ~= true then return end
    print("[EHR][DisinfectDebug][Hook] " .. tostring(message))
end

local function WoundHookPlayerName(player)
    if not player then return "nil" end
    local name = nil
    pcall(function()
        if player.getUsername then name = player:getUsername() end
    end)
    if name and name ~= "" then return tostring(name) end
    pcall(function()
        if player.getDescriptor and player:getDescriptor() and player:getDescriptor().getForename then
            name = player:getDescriptor():getForename()
        end
    end)
    return tostring(name or player)
end

local function WoundHookItemName(item)
    if not item then return "nil" end
    local name = nil
    pcall(function()
        if item.getFullType then name = item:getFullType() end
    end)
    if name and name ~= "" then return tostring(name) end
    pcall(function()
        if item.getType then name = item:getType() end
    end)
    return tostring(name or item)
end

local function WoundHookBodyPartState(bodyPart)
    if not bodyPart then return "bodyPart=nil" end
    local infected, level, alcohol, partType = nil, nil, nil, nil
    pcall(function() if bodyPart.isInfectedWound then infected = bodyPart:isInfectedWound() end end)
    pcall(function() if bodyPart.getWoundInfectionLevel then level = bodyPart:getWoundInfectionLevel() end end)
    pcall(function() if bodyPart.getAlcoholLevel then alcohol = bodyPart:getAlcoholLevel() end end)
    pcall(function() partType = WoundHookGetBodyPartType(bodyPart) end)
    return string.format("part=%s infected=%s level=%s alcohol=%s",
        tostring(partType), tostring(infected), tostring(level), tostring(alcohol))
end

local function WoundHookClearVanillaInfectionMarker(bodyPart)
    if not bodyPart then return end

    WoundHookDisinfectDebug("clear-marker before " .. WoundHookBodyPartState(bodyPart))
    local okLevel, errLevel = pcall(function() bodyPart:setWoundInfectionLevel(-1) end)
    local okFlag, errFlag = pcall(function() bodyPart:setInfectedWound(false) end)
    local okSync, errSync = pcall(function()
        if syncBodyPart then
            syncBodyPart(bodyPart, 0x00608200)
        end
    end)
    WoundHookDisinfectDebug(string.format("clear-marker calls level=%s/%s flag=%s/%s sync=%s/%s",
        tostring(okLevel), tostring(errLevel), tostring(okFlag), tostring(errFlag), tostring(okSync), tostring(errSync)))
    WoundHookDisinfectDebug("clear-marker after " .. WoundHookBodyPartState(bodyPart))
end

local function WoundHookProcessDisinfect(action, source)
    if not action then
        WoundHookDisinfectDebug("skip source=" .. tostring(source) .. " action=nil")
        return
    end
    if action._ehrDisinfectProcessed then
        WoundHookDisinfectDebug("skip source=" .. tostring(source) .. " already-processed")
        return
    end

    local doctor = action.character
    local patient = action.otherPlayer or action.character
    local bodyPart = action.bodyPart
    WoundHookDisinfectDebug(string.format("process source=%s doctor=%s patient=%s localDoctor=%s %s",
        tostring(source), WoundHookPlayerName(doctor), WoundHookPlayerName(patient),
        tostring(WoundHookIsLocalDoctor(doctor)), WoundHookBodyPartState(bodyPart)))

    if not WoundHookIsLocalDoctor(doctor) or not patient or not bodyPart then
        WoundHookDisinfectDebug("skip source=" .. tostring(source) .. " invalid doctor/patient/bodyPart")
        return
    end

    action._ehrDisinfectProcessed = true
    EHR.Log("WoundHook: ISDisinfect processed")

    local bodyPartType = WoundHookGetBodyPartType(bodyPart)
    if bodyPartType and EHR.WoundInfection and EHR.WoundInfection.OnDisinfect then
        WoundHookDisinfectDebug("calling OnDisinfect partType=" .. tostring(bodyPartType))
        EHR.WoundInfection.OnDisinfect(patient, bodyPartType)
    else
        WoundHookDisinfectDebug("OnDisinfect unavailable bodyPartType=" .. tostring(bodyPartType))
    end

    -- WoundInfection.OnDisinfect is the single source of truth for clearing the
    -- vanilla infection marker. Keeping the direct client-side clear disabled
    -- avoids racing vanilla/server state and makes disinfect diagnostics sane.
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
        WoundHookDisinfectDebug("ISApplyBandage require failed success=" .. tostring(success))
        return false
    end

    -- Store original action functions
    local originalStart = ISApplyBandage.start
    local originalPerform = ISApplyBandage.perform

    if originalStart then
        ISApplyBandage.start = function(self)
            local item = self and (self.item or self.bandage)
            WoundHookDisinfectDebug(string.format("ISApplyBandage.start before vanilla item=%s %s",
                WoundHookItemName(item), WoundHookBodyPartState(self and self.bodyPart)))
            originalStart(self)
            WoundHookDisinfectDebug(string.format("ISApplyBandage.start after vanilla item=%s %s",
                WoundHookItemName(item), WoundHookBodyPartState(self and self.bodyPart)))
        end
    end

    -- Override perform
    ISApplyBandage.perform = function(self)
        local doctor = self and self.character
        local patient = (self and self.otherPlayer) or doctor
        local item = self and (self.item or self.bandage)
        local bodyPart = self and self.bodyPart
        local isDisinfectant = item and EHR.WoundHook.IsDisinfectant(item)

        WoundHookDisinfectDebug(string.format("ISApplyBandage.perform before vanilla item=%s disinfectant=%s doctor=%s patient=%s localDoctor=%s %s",
            WoundHookItemName(item), tostring(isDisinfectant), WoundHookPlayerName(doctor),
            WoundHookPlayerName(patient), tostring(WoundHookIsLocalDoctor(doctor)), WoundHookBodyPartState(bodyPart)))

        -- Call original first
        originalPerform(self)

        WoundHookDisinfectDebug(string.format("ISApplyBandage.perform after vanilla item=%s disinfectant=%s %s",
            WoundHookItemName(item), tostring(isDisinfectant), WoundHookBodyPartState(bodyPart)))

<<<<<<< Updated upstream
        local patient = self.otherPlayer or self.character
        if player and patient == player and player == getSpecificPlayer(0) then
=======
        if WoundHookIsLocalDoctor(doctor) then
>>>>>>> Stashed changes
            -- Check if used disinfectant
            if isDisinfectant then
                EHR.Log("WoundHook: Disinfectant applied to " .. tostring(bodyPart))

                -- Get body part type
                local bodyPartType = WoundHookGetBodyPartType(bodyPart)

                if bodyPartType and EHR.WoundInfection and EHR.WoundInfection.OnDisinfect then
                    WoundHookDisinfectDebug("ISApplyBandage calling OnDisinfect partType=" .. tostring(bodyPartType))
                    EHR.WoundInfection.OnDisinfect(patient, bodyPartType)
                else
                    WoundHookDisinfectDebug("ISApplyBandage OnDisinfect unavailable bodyPartType=" .. tostring(bodyPartType))
                end

                -- See WoundHookProcessDisinfect: direct marker clearing happens
                -- only through EHR.WoundInfection.OnDisinfect.
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
    WoundHookDisinfectDebug("ISApplyBandage.perform hooked")
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

    local originalComplete = ISDisinfect.complete
    local originalPerform = ISDisinfect.perform
    local originalStart = ISDisinfect.start
    if originalStart then
        ISDisinfect.start = function(self)
            WoundHookDisinfectDebug("ISDisinfect.start before vanilla " .. WoundHookBodyPartState(self and self.bodyPart))
            originalStart(self)
            WoundHookDisinfectDebug("ISDisinfect.start after vanilla " .. WoundHookBodyPartState(self and self.bodyPart))
        end
    end

    if originalComplete then
        ISDisinfect.complete = function(self)
            WoundHookDisinfectDebug("complete before vanilla " .. WoundHookBodyPartState(self and self.bodyPart))
            local result = originalComplete(self)
            WoundHookDisinfectDebug("complete after vanilla result=" .. tostring(result) .. " " .. WoundHookBodyPartState(self and self.bodyPart))
            if result ~= false then
                WoundHookProcessDisinfect(self, "complete")
            end
            return result
        end
    end

    -- Override perform
    ISDisinfect.perform = function(self)
        -- Call original first
        originalPerform(self)

<<<<<<< Updated upstream
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
=======
        -- Fallback for action variants that do not call complete().
        WoundHookDisinfectDebug("perform fallback after vanilla " .. WoundHookBodyPartState(self and self.bodyPart))
        WoundHookProcessDisinfect(self, "perform")
>>>>>>> Stashed changes
    end

    EHR.Log("WoundHook: ISDisinfect complete/perform hooked")
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
    WoundHookDisinfectDebug("Initialize start")

    -- Hook bandage/disinfect action
    local bandageHooked = EHR.WoundHook.HookBandageAction()

    -- Try alternative disinfect hook
    local disinfectHooked = EHR.WoundHook.HookDisinfectAction()

    -- Hook pill action
    local pillHooked = EHR.WoundHook.HookPillAction()

    -- If pill hook failed, try eating action
    local eatHooked = false
    if not pillHooked then
        eatHooked = EHR.WoundHook.HookEatAction()
    end

    EHR.WoundHook.initialized = true
    EHR.Log("WoundHook: Initialization complete")
    WoundHookDisinfectDebug(string.format("Initialize complete bandage=%s disinfect=%s pill=%s eat=%s",
        tostring(bandageHooked), tostring(disinfectHooked), tostring(pillHooked), tostring(eatHooked)))
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
    WoundHookDisinfectDebug("module loaded")
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
