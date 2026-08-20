pcall(function() require "ExtensiveHealth/EHR_Localization" end)
--[[
    Extensive Health Rework B42
    Medication Consumption Hook (Client-Side)

    Hooks into vanilla medication actions to track ALL medical item usage:
    - ISTakePillAction:complete() for drainable pill bottles
    - ISEatFoodAction for food-type medications
    - Auto-detects any item with Medical=true tag

    This ensures vanilla medications and third-party mod items show up
    in the EHR Medical Monitor.
]]--

require "TimedActions/ISTakePillAction"
require "TimedActions/ISEatFoodAction"

EHR = EHR or {}
EHR.Medication = EHR.Medication or {}
EHR.MedicationHook = EHR.MedicationHook or {}

local function log(msg)
    if EHR and EHR.Log then
        EHR.Log("[MedHook] " .. msg)
    else
        print("[EHR MedicationHook] " .. tostring(msg))
    end
end

-- ============================================
-- AUTO-DETECTION: Track any Medical=true item
-- ============================================

-- Check if an item is a medical item
local function isMedicalItem(item)
    if not item then return false end
    -- Check for Medical=true property (primary method)
    if item.isMedical and item:isMedical() then
        return true
    end
    -- Check display category (fallback for B42 compatibility)
    local displayCat = item:getDisplayCategory()
    if displayCat and displayCat == "FirstAid" then
        return true
    end
    -- Check script item for Medical tag (B42 compatible approach)
    local scriptItem = item:getScriptItem()
    if scriptItem then
        local tags = scriptItem:getTags()
        if tags and tags:contains("Medical") then
            return true
        end
    end
    return false
end

-- Get or create a generic medication entry for unregistered items
local function getOrCreateMedData(itemFullType, item)
    -- First check if it's in the official database
    if EHR.Medication.Database and EHR.Medication.Database[itemFullType] then
        return EHR.Medication.Database[itemFullType]
    end

    -- Create a generic entry for this medical item
    local displayName = item:getDisplayName() or itemFullType
    return {
        tier = 0,  -- Generic tier
        treats = {},  -- No specific disease treatment
        displayName = displayName,
        usageMessage = "You use " .. displayName .. ".",
        isGeneric = true,  -- Flag as auto-detected
    }
end

-- Track a medication dose (generic tracking)
local function trackMedicationDose(character, item, medData, itemFullType)
    if not character or not item then return end
    if not character:isLocalPlayer() then return end

    if medData and medData.consumeViaFoodHook == true then
        log("Skipping food-hook medication in generic medication hook: " .. tostring(itemFullType))
        return
    end

    -- Vanilla ISTakePillAction owns the physical item consumption. In MP the
    -- EHR effect must be applied to the server copy of the player instead of
    -- being written to client modData and overwritten by the next sync.
    if isClient and isClient() and EHR.Medication.UseConsumedMedication then
        EHR.Medication.UseConsumedMedication(character, itemFullType)
        log("Requested server tracking for vanilla medication: " .. tostring(itemFullType))
        return
    end

    local modData = character:getModData()
    if not modData then return end

    -- Initialize medication tracking structure
    modData.EHR_Medication = modData.EHR_Medication or {}
    modData.EHR_Medication.activeDoses = modData.EHR_Medication.activeDoses or {}
    modData.EHR_Medication.activeTreatments = modData.EHR_Medication.activeTreatments or {}
    modData.EHR_Medication.activeSideEffects = modData.EHR_Medication.activeSideEffects or {}

    local gameTime = getGameTime()
    local currentHour = gameTime and gameTime:getWorldAgeHours() or 0

    local medKey = itemFullType
    local existingDose = modData.EHR_Medication.activeDoses[medKey]

    -- Prevent double-tracking (if same med used within 1 minute)
    if existingDose then
        local timeSinceLastDose = currentHour - (existingDose.lastDoseTime or 0)
        if timeSinceLastDose < 0.02 then  -- ~1 minute
            log("Skipping double-track for: " .. itemFullType)
            return
        end
    end

    local earlyDoseOverdose = nil
    if EHR.Medication.GetEarlyDoseOverdoseInfo then
        earlyDoseOverdose = EHR.Medication.GetEarlyDoseOverdoseInfo(character, medData, itemFullType)
    end

    local treatedDisease = false

    -- If the medication treats diseases and player has those diseases, apply treatment.
    -- ApplyTreatment owns activeDoses for real EHR treatments, so don't pre-write the dose here.
    if medData.treats and #medData.treats > 0 and EHR.Disease and EHR.Disease.GetDiseaseData then
        local diseaseData = EHR.Disease.GetDiseaseData(character)
        if diseaseData and diseaseData.active then
            for _, diseaseId in ipairs(medData.treats) do
                if diseaseData.active[diseaseId] then
                    -- Use the proper treatment system if available
                    if EHR.Medication.ApplyTreatment then
                        local tierEffects = EHR.Medication.TierEffectiveness and
                            EHR.Medication.TierEffectiveness[medData.tier] or
                            { symptomRelief = 0.15, cureRate = 0.0, canCure = false }
                        EHR.Medication.ApplyTreatment(character, diseaseId, medData, tierEffects, itemFullType)
                        treatedDisease = true
                        log("Applied treatment for: " .. diseaseId)
                    end
                end
            end
        end
    end

    if not treatedDisease then
        if EHR.Medication.TrackDoseOnly then
            EHR.Medication.TrackDoseOnly(character, medData, itemFullType)
        else
            local doseCount = existingDose and (existingDose.doseCount or 0) + 1 or 1
            modData.EHR_Medication.activeDoses[medKey] = {
                medKey = medKey,
                medicationName = medData.displayName,
                tier = medData.tier or 0,
                doseCount = doseCount,
                totalDosesNeeded = medData.totalDosesNeeded or 1,
                intervalHours = medData.intervalHours or 6,
                activeHours = medData.effectDurationHours or medData.symptomReliefHours or medData.intervalHours or 6,
                lastDoseTime = currentHour,
                startTime = existingDose and existingDose.startTime or currentHour,
                isGeneric = medData.isGeneric or false,
                symptomOnly = true,
            }
        end

        log("Tracked medication: " .. itemFullType)
    end

    if earlyDoseOverdose and EHR.Medication.ApplyEarlyDoseOverdose then
        EHR.Medication.ApplyEarlyDoseOverdose(character, earlyDoseOverdose)
    end

    -- Apply immediate effects (for emergency medications, Knox cures, etc.)
    if medData.immediateEffects then
        local success, err = pcall(medData.immediateEffects, character)
        if success then
            log("Applied immediate effects for: " .. itemFullType)
        else
            log("ERROR applying immediate effects for " .. itemFullType .. ": " .. tostring(err))
        end
    end

    -- Show usage message
    if medData.usageMessage and character.Say then
        EHR.Locale.Say(character, medData.usageMessage)
    end

    -- MP sync
    if isClient() and sendClientCommand then
        local trackedDose = modData.EHR_Medication.activeDoses[medKey] or {}
        sendClientCommand(character, "EHR", "TrackMedication", {
            medKey = medKey,
            medicationName = medData.displayName,
            tier = medData.tier or 0,
            doseCount = trackedDose.doseCount or 1,
            totalDosesNeeded = trackedDose.totalDosesNeeded or 1,
            intervalHours = trackedDose.intervalHours or 6,
            activeHours = trackedDose.activeHours or trackedDose.intervalHours or 6,
            lastDoseTime = currentHour,
            treatingDisease = trackedDose.treatingDisease,
            symptomOnly = trackedDose.symptomOnly == true,
            analgesicInitialPain = trackedDose.analgesicInitialPain,
        })
    end
end

-- ============================================
-- HOOK: ISTakePillAction completion
-- For drainable pill bottles (Base.Pills, etc.)
-- ============================================

local function trackCompletedPillAction(action, source)
    if not action or action.ehrMedicationTracked then return end
    if not action.character or not action.item then return end

    local ok, itemFullType = pcall(function()
        return action.item:getFullType()
    end)
    if not ok or not itemFullType then return end

    if not isMedicalItem(action.item) then return end

    -- B42 MP completes the client copy of the timed action through perform(),
    -- while complete() remains the reliable SP/server lifecycle point. Mark the
    -- action before dispatch so both callbacks can safely be hooked together.
    action.ehrMedicationTracked = true
    log("ISTakePillAction:" .. tostring(source) .. "() - " .. tostring(itemFullType))

    local medData = getOrCreateMedData(itemFullType, action.item)
    trackMedicationDose(action.character, action.item, medData, itemFullType)
end

local function safelyTrackCompletedPillAction(action, source)
    local ok, err = pcall(trackCompletedPillAction, action, source)
    if not ok then
        log("ERROR tracking ISTakePillAction:" .. tostring(source) .. "(): " .. tostring(err))
    end
end

local function hookTakePillAction()
    if not ISTakePillAction then
        log("ERROR: ISTakePillAction not found!")
        return false
    end

    local hookedAny = false

    -- Re-check the live method instead of trusting a boolean flag. Another mod
    -- may wrap or replace the action after this file's immediate initialization.
    if ISTakePillAction.complete
        and ISTakePillAction.complete ~= EHR.MedicationHook.pillCompleteWrapper then
        local originalComplete = ISTakePillAction.complete
        local completeWrapper = function(self)
            -- complete() is reached only after a successful timed action. Track
            -- before the live vanilla/third-party chain: if a later wrapper
            -- consumes the item and then errors, EHR must not silently lose the
            -- dose and its analgesic effect. The action flag keeps perform()
            -- and nested wrappers idempotent.
            safelyTrackCompletedPillAction(self, "complete")
            return originalComplete(self)
        end
        EHR.MedicationHook.pillCompleteWrapper = completeWrapper
        ISTakePillAction.complete = completeWrapper
        hookedAny = true
    end

    if ISTakePillAction.perform
        and ISTakePillAction.perform ~= EHR.MedicationHook.pillPerformWrapper then
        local originalPerform = ISTakePillAction.perform
        local performWrapper = function(self)
            safelyTrackCompletedPillAction(self, "perform")
            return originalPerform(self)
        end
        EHR.MedicationHook.pillPerformWrapper = performWrapper
        ISTakePillAction.perform = performWrapper
        hookedAny = true
    end

    if not ISTakePillAction.complete and not ISTakePillAction.perform then
        log("ERROR: ISTakePillAction completion methods not found!")
        return false
    end

    EHR.MedicationHook.pillActionHooked = true
    if hookedAny then
        log("Successfully hooked ISTakePillAction:perform()/complete()")
    end
    return true
end

-- ============================================
-- HOOK: ISEatFoodAction:complete()
-- For food-type medications (individual pills, etc.)
-- ============================================

local function hookEatFoodAction()
    if not ISEatFoodAction then
        log("ERROR: ISEatFoodAction not found!")
        return false
    end

    if EHR.MedicationHook.eatActionHooked then
        log("ISEatFoodAction already hooked")
        return true
    end

    local originalPerform = ISEatFoodAction.perform
    if not originalPerform then
        log("ERROR: ISEatFoodAction.perform not found!")
        return false
    end

    ISEatFoodAction.perform = function(self)
        -- Track BEFORE original (in case item is consumed)
        if self.character and self.item then
            local itemFullType = self.item:getFullType()

            -- Only track if it's a medical item
            if isMedicalItem(self.item) then
                log("ISEatFoodAction:perform() - Medical item: " .. tostring(itemFullType))
                local medData = getOrCreateMedData(itemFullType, self.item)
                trackMedicationDose(self.character, self.item, medData, itemFullType)
            end
        end

        -- Call original
        return originalPerform(self)
    end

    EHR.MedicationHook.eatActionHooked = true
    log("Successfully hooked ISEatFoodAction:perform()")
    return true
end

-- ============================================
-- INITIALIZATION
-- ============================================

local function initializeHooks()
    log("Initializing medication tracking hooks...")
    hookTakePillAction()
    hookEatFoodAction()
    log("Medication tracking hooks initialized")
end

-- Hook on game start
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(initializeHooks)
    log("Registered OnGameStart hook for medication tracking")
end

-- Some UI/medical mods replace ISTakePillAction during game initialization.
-- Re-check the live method once the player exists so load order cannot leave
-- vanilla painkillers consumed but absent from EHR tracking.
if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function()
        hookTakePillAction()
    end)
end

-- Also try immediate hook (might work if timed actions are already loaded)
if ISTakePillAction and ISEatFoodAction then
    initializeHooks()
end

log("EHR_MedicationHook.lua loaded (client-side)")
