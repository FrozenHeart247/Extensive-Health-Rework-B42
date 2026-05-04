--[[
    Extensive Health Rework B42
    Medication Timed Action Module

    Adds progress bars and tooltips to medication usage.
    Replaces the instant medication use with realistic timed actions.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Medication"
require "TimedActions/ISBaseTimedAction"

EHR = EHR or {}
EHR.MedicationAction = {}

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

-- ============================================
-- TIMED ACTION CLASS
-- ============================================

EHRMedicationAction = ISBaseTimedAction:derive("EHRMedicationAction")

function EHRMedicationAction:isValid()
    -- Check player is alive and has the item
    if not self.character:isAlive() then return false end
    if not self.character:getInventory():contains(self.item) then return false end

    -- Re-check if medication can still be used
    local canUse, _ = EHR.Medication.CanUseMedication(self.character, self.item)
    return canUse
end

function EHRMedicationAction:update()
    -- Animation updates if needed
    self.character:faceThisObject(self.character)
end

function EHRMedicationAction:start()
    -- Set animation based on admin type
    if self.adminType == "iv" or self.adminType == "injection" then
        self.character:setMetabolicTarget(Metabolics.HeavyWork)
    else
        self.character:setMetabolicTarget(Metabolics.LightWork)
    end

    -- Play start sound if applicable
    if self.adminType == "inhaler" then
        -- Could add inhaler sound
    end
end

function EHRMedicationAction:stop()
    ISBaseTimedAction.stop(self)
end

function EHRMedicationAction:perform()
    -- Apply the medication effects
    EHR.Medication.UseMedication(self.character, self.item)

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

            if medData then
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
                    ISTimedActionQueue.add(EHRMedicationAction:new(plr, item, medData))
                end)

                -- Always add tooltip with medication info
                local tooltip = ISWorldObjectContextMenu.addToolTip()
                tooltip:setName(medData.displayName)

                -- Build tooltip description
                local desc = ""

                -- What it treats
                if medData.treats and #medData.treats > 0 then
                    local treatsList = table.concat(medData.treats, ", ")
                    desc = desc .. "Treats: " .. treatsList .. " <LINE> "
                else
                    desc = desc .. "Symptom relief / Emergency use <LINE> "
                end

                -- Administration type and time
                local adminType = EHR.MedicationAction.GetAdminType(medData)
                local timeSeconds = math.floor((EHR.MedicationAction.Times[adminType] or 120) / 30)
                desc = desc .. "Administration: " .. adminType .. " (~" .. timeSeconds .. "s) <LINE> "

                -- Cure time if applicable
                local treatmentTimeText = EHR.Medication.GetTreatmentTimeText and EHR.Medication.GetTreatmentTimeText(medData) or nil
                if treatmentTimeText then
                    desc = desc .. "Treatment time: " .. treatmentTimeText .. " <LINE> "
                end

                -- Requirements
                if medData.requiresIVKit then
                    desc = desc .. "<RGB:0.7,0.7,1> Requires: IV Kit <LINE> "
                end
                if medData.requiresSyringe then
                    desc = desc .. "<RGB:0.7,0.7,1> Requires: Syringe <LINE> "
                end

                -- Side effects warning
                if medData.sideEffects and #medData.sideEffects > 0 then
                    local sideEffectNames = {}
                    for _, effectId in ipairs(medData.sideEffects) do
                        local effectDef = EHR.Medication.SideEffects and EHR.Medication.SideEffects[effectId]
                        if effectDef then
                            table.insert(sideEffectNames, effectDef.displayName or effectId)
                        else
                            table.insert(sideEffectNames, effectId)
                        end
                    end
                    desc = desc .. "<RGB:1,0.5,0> Side effects: " .. table.concat(sideEffectNames, ", ")
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
