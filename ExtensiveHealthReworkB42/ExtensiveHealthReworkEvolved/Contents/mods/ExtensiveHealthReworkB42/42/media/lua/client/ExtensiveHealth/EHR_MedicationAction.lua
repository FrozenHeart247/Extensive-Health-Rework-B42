--[[
    Extensive Health Rework B42
    Medication Timed Action Module

    Adds progress bars and tooltips to medication usage.
    Replaces the instant medication use with realistic timed actions.
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
require "ExtensiveHealth/EHR_Medication"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferAction"

EHR = EHR or {}
EHR.MedicationAction = {}

local function medActionText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_MedAction_" .. tostring(key), fallback)
    end
    local ok, value = pcall(getText, "UI_EHR_MedAction_" .. tostring(key))
    if ok and value and value ~= "UI_EHR_MedAction_" .. tostring(key) then return value end
    return fallback
end

local function medActionFormat(key, fallback, ...)
    if EHR and EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format("UI_EHR_MedAction_" .. tostring(key), fallback, ...)
    end
    local text = medActionText(key, fallback)
    local args = {...}
    for i, value in ipairs(args) do
        local replacement = tostring(value)
        text = tostring(text):gsub("%%" .. tostring(i) .. "%$[%a]", function() return replacement end)
        text = tostring(text):gsub("%%" .. tostring(i), function() return replacement end)
    end
    return text
end

local function medActionDiseaseName(id)
    if EHR and EHR.DiseaseFlyers and EHR.DiseaseFlyers.GetDiseaseFriendlyName then
        return EHR.DiseaseFlyers.GetDiseaseFriendlyName(id)
    end
    return tostring(id or "")
end

local function medActionAdminType(adminType)
    adminType = tostring(adminType or "default")
    return medActionText("AdminType_" .. adminType, adminType)
end


-- Time multipliers based on medication administration type (in ticks, ~30 ticks = 1 second)
EHR.MedicationAction.Times = {
    pill = 90,           -- ~3 seconds - swallowing pills
    tablet = 90,         -- ~3 seconds
    capsule = 90,        -- ~3 seconds
    liquid = 120,        -- ~4 seconds - drinking liquid medicine
    cream = 150,         -- ~5 seconds - applying topical
    ointment = 150,      -- ~5 seconds
    inhaler = 60,        -- ~2 seconds - quick inhale
    injection = 180,     -- ~6 seconds - syringe injection
    iv = 300,            -- ~10 seconds - IV setup and administration
    emergency = 60,      -- ~2 seconds - auto-injector (epinephrine)
    default = 120,       -- ~4 seconds default
}

-- Determine administration type from medication data
function EHR.MedicationAction.GetAdminType(medData)
    if not medData then return "default" end
    if medData.adminType and EHR.MedicationAction.Times[medData.adminType] then
        return medData.adminType
    end

    -- Check for IV medications
    if medData.requiresIVKit then
        return "iv"
    end

    -- Check for injection medications
    if medData.requiresSyringe then
        if medData.isEmergency then
            return "emergency"
        end
        return "injection"
    end

    -- Check display name for clues
    local name = string.lower(medData.displayName or "")
    if string.find(name, "inhaler") then return "inhaler" end
    if string.find(name, "cream") or string.find(name, "ointment") then return "cream" end
    if string.find(name, "syrup") or string.find(name, "liquid") then return "liquid" end
    if string.find(name, "capsule") then return "capsule" end
    if string.find(name, "tablet") or string.find(name, "pill") then return "pill" end

    -- Default based on tier
    if medData.tier == 0 then return "pill" end  -- Basic = pills
    if medData.tier == 1 then return "pill" end  -- OTC = pills/tablets
    if medData.tier == 2 then return "pill" end  -- Prescription = pills
    if medData.tier == 3 then return "iv" end    -- Clinical = usually IV

    return "default"
end

local function EHRMedicationActionHasItem(character, item)
    if not character or not item then return false end
    local inventory = character:getInventory()
    if not inventory then return false end

    if isClient and isClient() and inventory.containsID and item.getID then
        return inventory:containsID(item:getID())
    end

    if inventory:contains(item) then return true end
    if inventory.containsRecursive and inventory:containsRecursive(item) then return true end

    return false
end

function EHR.MedicationAction.QueueUseMedication(playerObj, item, medData)
    if not playerObj or not item then return end

    local inventory = playerObj:getInventory()
    local container = item:getContainer()

    if inventory and container and container ~= inventory then
        ISTimedActionQueue.add(ISInventoryTransferAction:new(playerObj, item, container, inventory))
    end

    ISTimedActionQueue.add(EHRMedicationAction:new(playerObj, item, medData))
end

-- ============================================
-- TIMED ACTION CLASS
-- ============================================

EHRMedicationAction = ISBaseTimedAction:derive("EHRMedicationAction")

function EHRMedicationAction:isValid()
    -- Check player is alive and has the item
    if not self.character:isAlive() then return false end
    if not EHRMedicationActionHasItem(self.character, self.item) then return false end

    -- Re-check if medication can still be used
    local canUse, _ = EHR.Medication.CanUseMedication(self.character, self.item)
    return canUse
end

function EHRMedicationAction:update()
    if self.item and self.item.setJobDelta then
        self.item:setJobDelta(self:getJobDelta())
    end

    if self.usesPillAnimation then
        -- Use the same animation as vanilla ISTakePillAction.
        self:setActionAnim(CharacterActionAnims.TakePills)
    end
end

function EHRMedicationAction:start()
    -- Inventory transfers in MP may replace the client-side item reference.
    -- Resolve the authoritative local object by ID just like vanilla does.
    if isClient and isClient() and self.item and self.item.getID then
        local inventory = self.character:getInventory()
        local resolved = inventory and inventory.getItemById
            and inventory:getItemById(self.item:getID()) or nil
        if resolved then self.item = resolved end
    end

    -- Set animation based on admin type
    if self.adminType == "iv" or self.adminType == "injection" then
        self.character:setMetabolicTarget(Metabolics.HeavyWork)
    else
        self.character:setMetabolicTarget(Metabolics.LightWork)
    end

    if self.item then
        if self.usesPillAnimation and self.item.setJobType then
            self.item:setJobType(getText("ContextMenu_Take_pills"))
        end
        if self.item.setJobDelta then self.item:setJobDelta(0.0) end
        if self.usesPillAnimation then
            self:setOverrideHandModels(nil, self.item)
        end
    end

    -- Play start sound if applicable
    if self.adminType == "inhaler" then
        -- Could add inhaler sound
    end
end

function EHRMedicationAction:stop()
    if self.item and self.item.setJobDelta then self.item:setJobDelta(0.0) end
    ISBaseTimedAction.stop(self)
end

function EHRMedicationAction:perform()
    -- A network timed action can be relaunched. Only one completed action may
    -- issue the server-authoritative medication request.
    if not self.ehrUseRequested then
        self.ehrUseRequested = true
        EHR.Medication.UseMedication(self.character, self.item)
    end

    if self.item then
        local container = self.item.getContainer and self.item:getContainer() or nil
        if container and container.setDrawDirty then container:setDrawDirty(true) end
        if self.item.setJobDelta then self.item:setJobDelta(0.0) end
    end

    -- Complete the action
    ISBaseTimedAction.perform(self)
end

function EHRMedicationAction:new(character, item, medData)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.medData = medData
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true

    -- Determine admin type and time
    o.adminType = EHR.MedicationAction.GetAdminType(medData)
    o.maxTime = EHR.MedicationAction.Times[o.adminType] or EHR.MedicationAction.Times.default
    o.usesPillAnimation = o.adminType == "pill"
        or o.adminType == "tablet"
        or o.adminType == "capsule"
    o.isEating = o.usesPillAnimation
    o.ehrUseRequested = false

    return o
end


-- ============================================
-- CONTEXT MENU WITH TOOLTIPS
-- ============================================

-- Remove the old context menu handler and replace with our enhanced one
local function OnMedicationContextMenuEnhanced(player, context, items)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then
            if v.items and v.items[1] then
                item = v.items[1]
            end
        end

        if item and instanceof(item, "InventoryItem") then
            local itemFullType = item:getFullType()
            local medData = EHR.Medication.Database[itemFullType]

            if medData and not medData.useVanillaActionOnly then
                local canUse, reason = EHR.Medication.CanUseMedication(playerObj, item)
                local tierName = ""
                if medData.tier == 0 then tierName = " (Basic)"
                elseif medData.tier == 1 then tierName = " (OTC)"
                elseif medData.tier == 2 then tierName = " (Prescription)"
                elseif medData.tier == 3 then tierName = " (Clinical)"
                end

                local optionName = "Use " .. medData.displayName .. tierName

                -- Use timed action instead of direct call
                local option = context:addOption(optionName, playerObj, function(plr)
                    EHR.MedicationAction.QueueUseMedication(plr, item, medData)
                end)
                if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

                -- Always add tooltip with medication info
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(medData.displayName)

                -- Build tooltip description
                local desc = ""

                -- What it treats
                if medData.treats and #medData.treats > 0 then
                    local treatNames = {}
                    for _, treatId in ipairs(medData.treats) do table.insert(treatNames, medActionDiseaseName(treatId)) end
                    local treatsList = table.concat(treatNames, ", ")
                    desc = desc .. medActionFormat("Treats", "Treats: %1", treatsList) .. " <LINE> "
                else
                    desc = desc .. medActionText("SymptomReliefEmergency", "Symptom relief / Emergency use") .. " <LINE> "
                end

                -- Administration type and time
                local adminType = EHR.MedicationAction.GetAdminType(medData)
                local timeSeconds = math.floor((EHR.MedicationAction.Times[adminType] or 120) / 30)
                desc = desc .. medActionFormat("Administration", "Administration: %1 (~%2s)", medActionAdminType(adminType), timeSeconds) .. " <LINE> "

                -- Remaining package doses
                local hasPackageDoses = false
                if EHR.Medication.GetItemDoseInfo then
                    local doseInfo = EHR.Medication.GetItemDoseInfo(item)
                    if doseInfo and doseInfo.maxDoses and doseInfo.maxDoses > 1 then
                        desc = desc .. medActionFormat("Remaining", "Remaining: %1/%2", tostring(doseInfo.remainingDoses or 0), tostring(doseInfo.maxDoses)) .. " <LINE> "
                        hasPackageDoses = true
                    end
                end
                if not hasPackageDoses then
                    desc = desc .. medActionText("SingleUse", "Single use") .. " <LINE> "
                end

                -- Cure time if applicable
                local treatmentTimeText = EHR.Medication.GetTreatmentTimeText and EHR.Medication.GetTreatmentTimeText(medData) or nil
                if treatmentTimeText then
                    desc = desc .. medActionFormat("TreatmentTime", "Treatment time: %1", treatmentTimeText) .. " <LINE> "
                end

                -- Requirements
                if medData.requiresIVKit then
                    desc = desc .. "<RGB:0.7,0.7,1> " .. medActionText("RequiresIVKit", "Requires: IV Kit") .. " <LINE> "
                end
                if medData.requiresSyringe then
                    desc = desc .. "<RGB:0.7,0.7,1> " .. medActionText("RequiresSyringe", "Requires: Syringe") .. " <LINE> "
                end

                -- Side effects warning
                if medData.sideEffects and #medData.sideEffects > 0 then
                    local sideEffectNames = {}
                    for _, effectId in ipairs(medData.sideEffects) do
                        local effectDef = EHR.Medication.SideEffects and EHR.Medication.SideEffects[effectId]
                        if effectDef then
                            table.insert(sideEffectNames, (EHR.Locale and EHR.Locale.SideEffectName and EHR.Locale.SideEffectName(effectDef.displayName or effectId)) or (effectDef.displayName or effectId))
                        else
                            table.insert(sideEffectNames, effectId)
                        end
                    end
                    desc = desc .. "<RGB:1,0.5,0> " .. medActionFormat("SideEffects", "Side effects: %1", table.concat(sideEffectNames, ", "))
                end

                -- If can't use, show why
                if not canUse then
                    option.notAvailable = true
                    desc = desc .. " <LINE> <RGB:1,0,0> " .. (reason or "Cannot use")
                end

                tooltip.description = desc
                option.toolTip = tooltip
            end
        end
    end
end

-- ============================================
-- REPLACE OLD CONTEXT MENU
-- ============================================

-- We need to add our enhanced version
-- The original OnMedicationContextMenu in shared file will still run,
-- but we override by removing its context options and adding our own

-- Actually, let's just add our handler - it will add duplicate options
-- Instead, we'll set a flag that the shared code checks

EHR.MedicationAction.Enabled = true

-- Override the UseMedication call to not consume item (we do it in perform)
-- Actually no - UseMedication already handles consumption

Events.OnFillInventoryObjectContextMenu.Add(OnMedicationContextMenuEnhanced)

EHR.Log("Medication Action module loaded - timed actions enabled")
