--[[
    Extensive Health Rework B42
    Transfusion Module

    Blood bags and saline IV for restoring blood volume.
    Blood type compatibility matters!
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Blood"
require "TimedActions/ISBaseTimedAction"
pcall(function() require "ExtensiveHealth/EHR_DiseaseFlyers" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.Transfusion = {}

local function transfusionText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_Transfusion_" .. tostring(key), fallback)
    end
    local fullKey = "UI_EHR_Transfusion_" .. tostring(key)
    local ok, value = pcall(getText, fullKey)
    if ok and value and value ~= fullKey then return value end
    return fallback
end

local function transfusionFormat(key, fallback, ...)
    if EHR and EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format("UI_EHR_Transfusion_" .. tostring(key), fallback, ...)
    end
    local text = transfusionText(key, fallback)
    local args = {...}
    for i, value in ipairs(args) do
        text = tostring(text):gsub("%%" .. tostring(i), tostring(value))
    end
    return text
end


-- Amount restored by each item type
EHR.Transfusion.BloodBagAmount = 500   -- mL
EHR.Transfusion.SalineAmount = 250     -- mL
EHR.Transfusion.DrawBloodAmount = 500  -- mL taken when drawing blood
EHR.Transfusion.BLOOD_BAG_FRESH_HOURS = 1.0
EHR.Transfusion.BLOOD_BAG_SPOIL_HOURS = 2.0

-- Time to administer (in game ticks, ~30 ticks = 1 second)
EHR.Transfusion.TransfusionTime = 300  -- ~10 seconds
EHR.Transfusion.DrawBloodTime = 400    -- ~13 seconds (drawing blood takes longer)

-- Minimum blood percentage required to safely draw blood
EHR.Transfusion.MinBloodToDrawPercent = 0.80  -- 80% - need healthy blood levels

-- Blood bag types now consolidated in EHR_Blood.lua (EHR.Blood.BloodBagTypes)

function EHR.Transfusion.HasBloodTypeKnowledge(player)
    if not player then return false end

    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.HasMedicalKnowledge then
        return EHR.DiseaseFlyers.HasMedicalKnowledge(player, "blood_types", 8)
    end

    if Perks and Perks.Doctor and player.getPerkLevel then
        local ok, level = pcall(function()
            return player:getPerkLevel(Perks.Doctor)
        end)
        return ok and (tonumber(level) or 0) >= 8
    end

    return false
end

--[[
    Check if an item is a blood bag
]]--
function EHR.Transfusion.IsBloodBag(item)
    if not item then return false end
    local fullType = item:getFullType()
    return EHR.Blood.BloodBagTypes[fullType] ~= nil
end

--[[
    Check if an item is a saline bag
]]--
function EHR.Transfusion.IsSalineBag(item)
    if not item then return false end
    return item:getFullType() == "ExtensiveHealth.SalineBag"
end

--[[
    Check if blood/saline is spoiled (not fresh but not completely rotten)
    Returns: "fresh", "stale", or "rotten"
]]--
function EHR.Transfusion.GetGameHour()
    local gameTime = getGameTime()
    if gameTime and gameTime.getWorldAgeHours then
        return gameTime:getWorldAgeHours()
    end
    return 0
end

function EHR.Transfusion.GetVanillaSpoilageState(item)
    if not item then return "rotten" end

    -- Check if item has spoilage properties
    local age = item:getAge() or 0
    local offAge = item:getOffAge() or 0
    local offAgeMax = item:getOffAgeMax() or 0

    -- If no spoilage defined, treat as fresh
    if offAgeMax <= 0 then return "fresh" end

    -- Check freshness state
    if age < offAge then
        return "fresh"
    elseif age < offAgeMax then
        return "stale"  -- Not fresh, but not completely rotten
    else
        return "rotten"
    end
end

function EHR.Transfusion.IsItemFrozen(item)
    if not item then return false end

    local ok, result = pcall(function()
        if item.isFrozen and item:isFrozen() then
            return true
        end
        if item.getFreezingTime then
            local freezingTime = item:getFreezingTime() or 0
            return freezingTime >= 100
        end
        return false
    end)

    return ok and result == true
end

function EHR.Transfusion.IsBloodBagFrozenOrStored(item)
    if not item then return false end
    if EHR.Transfusion.IsItemFrozen(item) then return true end
    if EHR.Transfusion.IsInFreezer then
        local ok, result = pcall(function()
            return EHR.Transfusion.IsInFreezer(item)
        end)
        if ok and result then return true end
    end
    return false
end

function EHR.Transfusion.GetBloodBagSpoilageData(item)
    if not item then return nil end

    local modData = item:getModData()
    if not modData then return nil end

    local now = EHR.Transfusion.GetGameHour()
    modData.EHR_BloodSpoilage = modData.EHR_BloodSpoilage or {
        createdHour = now,
        lastCheckHour = now,
        warmElapsed = 0,
        stale = false,
        rotten = false,
        isFrozen = false,
    }

    local data = modData.EHR_BloodSpoilage
    data.createdHour = data.createdHour or now
    data.lastCheckHour = data.lastCheckHour or now
    data.warmElapsed = data.warmElapsed or 0
    data.stale = data.stale or false
    data.rotten = data.rotten or false
    data.isFrozen = data.isFrozen or false

    return data
end

function EHR.Transfusion.UpdateBloodBagSpoilage(item)
    if not item or not EHR.Transfusion.IsBloodBag(item) then return nil end

    local data = EHR.Transfusion.GetBloodBagSpoilageData(item)
    if not data then return nil end

    local currentHour = EHR.Transfusion.GetGameHour()
    local lastCheckHour = data.lastCheckHour or currentHour
    local elapsed = currentHour - lastCheckHour
    if elapsed < 0 then elapsed = 0 end
    if elapsed > 24 then elapsed = 24 end

    data.isFrozen = EHR.Transfusion.IsBloodBagFrozenOrStored(item)

    if not data.isFrozen and not data.rotten then
        data.warmElapsed = (data.warmElapsed or 0) + elapsed
    end
    data.lastCheckHour = currentHour

    local vanillaState = EHR.Transfusion.GetVanillaSpoilageState(item)
    if vanillaState == "rotten" then
        data.rotten = true
    elseif vanillaState == "stale" then
        data.warmElapsed = math.max(data.warmElapsed or 0, EHR.Transfusion.BLOOD_BAG_FRESH_HOURS)
    end

    if (data.warmElapsed or 0) >= EHR.Transfusion.BLOOD_BAG_SPOIL_HOURS then
        data.rotten = true
    elseif (data.warmElapsed or 0) >= EHR.Transfusion.BLOOD_BAG_FRESH_HOURS then
        data.stale = true
    else
        data.stale = false
    end

    if data.rotten then
        pcall(function()
            local offAgeMax = item:getOffAgeMax() or 0
            if offAgeMax > 0 then
                item:setAge(offAgeMax + 1)
            end
        end)
    elseif data.isFrozen then
        -- Keep vanilla food aging from advancing while the bag is frozen/preserved.
        pcall(function() item:setAge(0) end)
    end

    return data
end

function EHR.Transfusion.GetBloodBagSpoilageInfo(item)
    if not item or not EHR.Transfusion.IsBloodBag(item) then return nil end

    local data = EHR.Transfusion.UpdateBloodBagSpoilage(item)
    if not data then return nil end

    local warmElapsed = data.warmElapsed or 0
    local state = "fresh"
    if data.rotten then
        state = "rotten"
    elseif warmElapsed >= EHR.Transfusion.BLOOD_BAG_FRESH_HOURS then
        state = "stale"
    end

    return {
        state = state,
        warmElapsed = warmElapsed,
        isFrozen = data.isFrozen == true,
        hoursUntilStale = math.max(0, EHR.Transfusion.BLOOD_BAG_FRESH_HOURS - warmElapsed),
        hoursUntilRotten = math.max(0, EHR.Transfusion.BLOOD_BAG_SPOIL_HOURS - warmElapsed),
    }
end

function EHR.Transfusion.GetSpoilageState(item)
    if EHR.Transfusion.IsBloodBag(item) then
        local info = EHR.Transfusion.GetBloodBagSpoilageInfo(item)
        if info and info.state then
            return info.state
        end
    end

    return EHR.Transfusion.GetVanillaSpoilageState(item)
end

--[[
    Apply severe reaction from using spoiled blood
    Much worse than incompatible blood!
]]--
function EHR.Transfusion.ApplySpoiledBloodReaction(player, data, spoilageState)
    local bodyDamage = player:getBodyDamage()
    local stats = player:getStats()

    EHR.Log("SPOILED BLOOD REACTION: State = " .. spoilageState)

    -- Stale blood: moderate illness
    -- Rotten blood: severe sepsis-like reaction

    local severityMult = spoilageState == "rotten" and 2.0 or 1.0

    -- 1. Heavy sickness (sepsis from bacteria in degraded blood)
    if stats and CharacterStat and CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            stats:set(CharacterStat.SICKNESS, math.min(1, current + 0.6 * severityMult))
        end)
    end

    -- 2. Food sickness (vomiting, nausea)
    if stats and CharacterStat and CharacterStat.FOOD_SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            stats:set(CharacterStat.FOOD_SICKNESS, math.min(1, current + 0.7 * severityMult))
        end)
    end

    -- 3. Fever/temperature increase
    if bodyDamage then
        pcall(function()
            local currentTemp = bodyDamage:getTemperature() or 37
            bodyDamage:setTemperature(math.min(41, currentTemp + 2 * severityMult))
        end)
    end

    -- 4. Severe pain
    if stats and CharacterStat and CharacterStat.PAIN then
        pcall(function()
            local pain = stats:get(CharacterStat.PAIN) or 0
            stats:set(CharacterStat.PAIN, math.min(1, pain + 0.5 * severityMult))
        end)
    end

    -- 5. Panic
    if stats and CharacterStat and CharacterStat.PANIC then
        pcall(function()
            local panic = stats:get(CharacterStat.PANIC) or 0
            stats:set(CharacterStat.PANIC, math.min(1, panic + 0.4 * severityMult))
        end)
    end

    -- 6. Damage to internal organs (random body parts)
    if bodyDamage and BodyPartType then
        local numParts = math.floor(4 * severityMult)
        for i = 1, numParts do
            local partIndex = ZombRand(BodyPartType.ToIndex(BodyPartType.MAX))
            local partType = BodyPartType.FromIndex(partIndex)
            if partType then
                local part = bodyDamage:getBodyPart(partType)
                if part and part.ReduceHealth then
                    pcall(function() part:ReduceHealth(ZombRand(10, 25) * severityMult) end)
                end
            end
        end
    end

    -- 7. Some blood volume lost (body rejecting transfusion)
    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, -150 * severityMult)
    else
        data.EHR_Blood.currentVolume = math.max(0, (data.EHR_Blood.currentVolume or 5000) - 150 * severityMult)
    end

    EHR.Locale.Say(player, spoilageState == "rotten" and "Oh god... that blood was rotten!" or "That blood tasted off...")
    EHR.Log("SpoiledBloodReaction: Applied severe sepsis-like reaction (severity: " .. severityMult .. ")")
end

--[[
    Get blood type from a blood bag item
]]--
function EHR.Transfusion.GetBagBloodType(item)
    if not item then return nil end
    return EHR.Blood.BloodBagTypes[item:getFullType()]
end

--[[
    Apply blood transfusion effects
]]--
function EHR.Transfusion.ApplyBloodTransfusion(player, item)
    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then
        EHR.Log("Transfusion: Player data not found!")
        return
    end

    local bagType = EHR.Transfusion.GetBagBloodType(item)
    local playerType = data.EHR_Blood.bloodType

    EHR.Log(string.format("Transfusion: Bag=%s, Player=%s", bagType, playerType))

    -- Check compatibility
    if EHR.Blood.IsCompatible(bagType, playerType) then
        -- Compatible - restore blood
        EHR.Transfusion.RestoreBlood(player, data, EHR.Transfusion.BloodBagAmount)
        EHR.Locale.Say(player, "That should help...")
        EHR.Log("Transfusion: Compatible! Restored " .. EHR.Transfusion.BloodBagAmount .. " mL")
    else
        -- Incompatible - bad reaction!
        EHR.Transfusion.ApplyBadReaction(player, data)
        EHR.Locale.Say(player, "Something's wrong... I feel terrible!")
        EHR.Log("Transfusion: INCOMPATIBLE! Bad reaction!")
    end
end

--[[
    Apply saline IV effects (always safe, but watch for hemodilution!)
    v2.7.0+: Uses new blood APIs - saline ADDS to volume and tracks separately
]]--
function EHR.Transfusion.ApplySaline(player, item)
    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then
        if EHR.DEBUG then print("[EHR SALINE DEBUG] Player data not found!") end
        return
    end

    -- Debug: Log blood volume BEFORE saline
    local volumeBefore = data.EHR_Blood.currentVolume or 0
    if EHR.DEBUG then
        print("[EHR SALINE DEBUG] === SALINE APPLICATION START ===")
        print("[EHR SALINE DEBUG] Blood volume BEFORE: " .. volumeBefore .. " mL")
    end

    -- v2.7.0+: Use proper saline function from EHR_Blood.lua if available
    if EHR.Blood and EHR.Blood.UseSalineBag then
        if EHR.DEBUG then print("[EHR SALINE DEBUG] Using EHR.Blood.UseSalineBag (new API)") end
        -- UseSalineBag handles volume addition AND hemodilution tracking
        EHR.Blood.UseSalineBag(player, item)

        -- Debug: Log blood volume AFTER saline
        local volumeAfter = data.EHR_Blood.currentVolume or 0
        if EHR.DEBUG then
            print("[EHR SALINE DEBUG] Blood volume AFTER: " .. volumeAfter .. " mL")
            print("[EHR SALINE DEBUG] Change: " .. (volumeAfter - volumeBefore) .. " mL")
            print("[EHR SALINE DEBUG] === SALINE APPLICATION END ===")
        end
        return
    end

    if EHR.DEBUG then print("[EHR SALINE DEBUG] FALLBACK: UseSalineBag not found, using legacy code") end

    -- Fallback: Direct saline handling (legacy support)
    -- Add to blood volume
    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        if EHR.DEBUG then print("[EHR SALINE DEBUG] Using ModifyBloodVolume with delta: " .. EHR.Transfusion.SalineAmount) end
        EHR.Blood.ModifyBloodVolume(player, EHR.Transfusion.SalineAmount)
    else
        if EHR.DEBUG then print("[EHR SALINE DEBUG] Using direct currentVolume modification") end
        local current = data.EHR_Blood.currentVolume or 0
        local max = data.EHR_Blood.maxVolume or 5000
        data.EHR_Blood.currentVolume = math.min(current + EHR.Transfusion.SalineAmount, max)
    end

    -- Track saline for hemodilution
    data.EHR_Blood.transfusedSaline = (data.EHR_Blood.transfusedSaline or 0) + EHR.Transfusion.SalineAmount

    -- Debug: Log blood volume AFTER saline
    local volumeAfter = data.EHR_Blood.currentVolume or 0
    if EHR.DEBUG then
        print("[EHR SALINE DEBUG] Blood volume AFTER: " .. volumeAfter .. " mL")
        print("[EHR SALINE DEBUG] Change: " .. (volumeAfter - volumeBefore) .. " mL")
        print("[EHR SALINE DEBUG] === SALINE APPLICATION END ===")
    end

    EHR.Locale.Say(player, "Feeling a bit better...")
    EHR.Log("Saline: Added " .. EHR.Transfusion.SalineAmount .. " mL (total saline: " .. (data.EHR_Blood.transfusedSaline or 0) .. " mL)")
end

--[[
    Restore blood volume (for blood transfusions, NOT saline)
    v2.7.0+: Uses new ModifyBloodVolume API, no longer needs body part healing hack
]]--
function EHR.Transfusion.RestoreBlood(player, data, amount)
    -- v2.7.0+: Use new API (cumulative tracking means we just add to volume)
    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, amount)
        -- Track transfused blood for compatibility checks
        data.EHR_Blood.transfusedBlood = (data.EHR_Blood.transfusedBlood or 0) + amount
        EHR.Log(string.format("RestoreBlood: Added %d mL via API", amount))
        return
    end

    -- Fallback: Direct volume modification (legacy support)
    local current = data.EHR_Blood.currentVolume or 0
    local max = data.EHR_Blood.maxVolume or 5000
    local newVolume = math.min(current + amount, max)
    data.EHR_Blood.currentVolume = newVolume

    -- NOTE: Body part healing hack removed in v2.7.0+
    -- With cumulative blood tracking, blood volume persists without needing to heal wounds

    EHR.Log(string.format("RestoreBlood: %d -> %d mL (legacy)", current, newVolume))
end

--[[
    Apply bad reaction from incompatible blood.
    The immediate stat shock is intentionally brief; the serious gameplay is
    handled by the AHTR disease module so it can progress, be monitored, and be treated.
]]--
function EHR.Transfusion.ApplyBadReaction(player, data)
    local stats = player:getStats()

    if stats and CharacterStat and CharacterStat.FOOD_SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.FOOD_SICKNESS) or 0
            stats:set(CharacterStat.FOOD_SICKNESS, math.min(1, current + 0.12))
        end)
    end

    if stats and CharacterStat and CharacterStat.SICKNESS then
        pcall(function()
            local current = stats:get(CharacterStat.SICKNESS) or 0
            stats:set(CharacterStat.SICKNESS, math.min(1, current + 0.18))
        end)
    end

    if stats and CharacterStat and CharacterStat.PANIC then
        pcall(function()
            local panic = stats:get(CharacterStat.PANIC) or 0
            stats:set(CharacterStat.PANIC, math.min(1, panic + 0.35))
        end)
    end

    if stats and CharacterStat and CharacterStat.PAIN then
        pcall(function()
            local pain = stats:get(CharacterStat.PAIN) or 0
            stats:set(CharacterStat.PAIN, math.min(1, pain + 0.12))
        end)
    end

    if EHR.Disease and EHR.Disease.Contract then
        local diseaseData = EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
        local active = diseaseData and diseaseData.active and diseaseData.active.ahtr or nil
        if active then
            active.severity = math.min(1.25, (tonumber(active.severity) or 0.95) + 0.25)
            active.endTime = math.max(tonumber(active.endTime) or 0, getGameTime():getWorldAgeHours() + 72)
            active.incompatibleTransfusion = true
        else
            EHR.Disease.Contract(player, "ahtr")
            diseaseData = EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or diseaseData
            active = diseaseData and diseaseData.active and diseaseData.active.ahtr or nil
            if active then
                active.severity = math.max(tonumber(active.severity) or 0.95, 0.95)
                active.incompatibleTransfusion = true
            end
        end
    end

    if EHR.Blood and EHR.Blood.ModifyBloodVolume then
        EHR.Blood.ModifyBloodVolume(player, -150)
    else
        data.EHR_Blood.currentVolume = math.max(0, (data.EHR_Blood.currentVolume or 5000) - 150)
    end

    EHR.Log("BadReaction: Started AHTR from incompatible transfusion")
end


-- ============================================
-- TIMED ACTION FOR TRANSFUSION
-- ============================================

EHRTransfusionAction = ISBaseTimedAction:derive("EHRTransfusionAction")

function EHRTransfusionAction:isValid()
    -- Check player is alive and has the item
    return self.character:isAlive() and self.character:getInventory():contains(self.item)
end

function EHRTransfusionAction:update()
    -- Could add animation updates here
end

function EHRTransfusionAction:start()
    -- Start animation (sitting/medical)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function EHRTransfusionAction:stop()
    ISBaseTimedAction.stop(self)
end

function EHRTransfusionAction:perform()
    if isClient and isClient() and sendClientCommand then
        sendClientCommand(self.character, "EHR", "UseTransfusion", {
            itemID = self.item:getID(),
            itemFullType = self.item:getFullType(),
            spoilageState = EHR.Transfusion.GetSpoilageState(self.item),
        })
        ISBaseTimedAction.perform(self)
        return
    end

    -- Remove the item with MP sync
    if isClient() then
        sendClientCommand(self.character, "EHR", "RemoveItem", {itemID = self.item:getID()})
    end
    self.character:getInventory():Remove(self.item)

    -- Check spoilage state
    local spoilageState = EHR.Transfusion.GetSpoilageState(self.item)

    -- Apply effects based on item type
    if EHR.Transfusion.IsBloodBag(self.item) then
        -- Check for spoiled blood
        if spoilageState == "stale" then
            -- Stale blood: still do transfusion but add illness
            local data = EHR.GetPlayerData(self.character)
            if data and data.EHR_Blood then
                EHR.Transfusion.ApplySpoiledBloodReaction(self.character, data, spoilageState)
            end
            -- Still apply some blood (reduced effectiveness)
            EHR.Transfusion.ApplyBloodTransfusion(self.character, self.item)
        elseif spoilageState == "rotten" then
            -- Rotten blood should not reach here (blocked in menu) but just in case
            local data = EHR.GetPlayerData(self.character)
            if data and data.EHR_Blood then
                EHR.Transfusion.ApplySpoiledBloodReaction(self.character, data, spoilageState)
            end
            EHR.Locale.Say(self.character, "That blood was completely rotten!")
        else
            -- Fresh blood - normal transfusion
            EHR.Transfusion.ApplyBloodTransfusion(self.character, self.item)
        end
    elseif EHR.Transfusion.IsSalineBag(self.item) then
        -- Check for contaminated saline
        if spoilageState == "stale" then
            -- Stale saline: still works but may cause minor illness
            EHR.Transfusion.ApplySaline(self.character, self.item)
            -- Minor sickness from contaminated saline
            local stats = self.character:getStats()
            if stats and CharacterStat and CharacterStat.SICKNESS then
                pcall(function()
                    local current = stats:get(CharacterStat.SICKNESS) or 0
                    stats:set(CharacterStat.SICKNESS, math.min(1, current + 0.15))
                end)
            end
            EHR.Locale.Say(self.character, "That saline tasted a bit off...")
        elseif spoilageState == "rotten" then
            -- Rotten saline should not reach here
            EHR.Locale.Say(self.character, "That saline was contaminated!")
        else
            -- Fresh saline - normal use
            EHR.Transfusion.ApplySaline(self.character, self.item)
        end
    end

    -- MP: Trigger server sync after transfusion
    if isClient() then
        sendClientCommand(self.character, "EHR", "RequestSync", {})
    end

    -- Complete the action
    ISBaseTimedAction.perform(self)
end

function EHRTransfusionAction:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = EHR.Transfusion.TransfusionTime
    return o
end


-- ============================================
-- TIMED ACTION FOR DRAWING BLOOD
-- ============================================

EHRDrawBloodAction = ISBaseTimedAction:derive("EHRDrawBloodAction")

function EHRDrawBloodAction:isValid()
    -- Check player is alive and has the empty blood bag
    if not self.character:isAlive() then return false end
    if not self.emptyBag then return false end
    if not self.character:getInventory():contains(self.emptyBag) then return false end

    -- Check player still has enough blood
    local data = EHR.GetPlayerData(self.character)
    if not data or not data.EHR_Blood then return false end

    local bloodPercent = data.EHR_Blood.currentVolume / data.EHR_Blood.maxVolume
    return bloodPercent >= EHR.Transfusion.MinBloodToDrawPercent
end

function EHRDrawBloodAction:update()
    -- Could add animation updates here
end

function EHRDrawBloodAction:start()
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function EHRDrawBloodAction:stop()
    ISBaseTimedAction.stop(self)
end

function EHRDrawBloodAction:perform()
    if isClient and isClient() and sendClientCommand then
        sendClientCommand(self.character, "EHR", "DrawBlood", {
            itemID = self.emptyBag:getID(),
            itemFullType = self.emptyBag:getFullType(),
        })
        ISBaseTimedAction.perform(self)
        return
    end

    local data = EHR.GetPlayerData(self.character)
    if not data or not data.EHR_Blood then
        ISBaseTimedAction.perform(self)
        return
    end

    -- Get player's blood type
    local playerType = EHR.Blood.GetPlayerBloodType(self.character)

    -- Map blood type to item type
    local bloodBagItems = {
        ["O-"]  = "ExtensiveHealth.BloodBagONeg",
        ["O+"]  = "ExtensiveHealth.BloodBagOPos",
        ["A-"]  = "ExtensiveHealth.BloodBagANeg",
        ["A+"]  = "ExtensiveHealth.BloodBagAPos",
        ["B-"]  = "ExtensiveHealth.BloodBagBNeg",
        ["B+"]  = "ExtensiveHealth.BloodBagBPos",
        ["AB-"] = "ExtensiveHealth.BloodBagABNeg",
        ["AB+"] = "ExtensiveHealth.BloodBagABPos",
    }

    local filledBagType = bloodBagItems[playerType]
    if not filledBagType then
        EHR.Locale.Say(self.character, "Something went wrong...")
        EHR.Log("DrawBlood: Unknown blood type: " .. tostring(playerType))
        ISBaseTimedAction.perform(self)
        return
    end

    local inventory = self.character:getInventory()
    if not inventory then
        EHR.Locale.Say(self.character, "Something went wrong...")
        EHR.Log("DrawBlood: No inventory available")
        ISBaseTimedAction.perform(self)
        return
    end

    -- Create the filled bag first, so a script/item error cannot consume blood or the empty bag.
    local ok, filledBag = pcall(function()
        return inventory:AddItem(filledBagType)
    end)

    if not ok or not filledBag then
        EHR.Locale.Say(self.character, "Something went wrong...")
        EHR.Log("DrawBlood: Failed to create " .. tostring(filledBagType) .. ": " .. tostring(filledBag))
        ISBaseTimedAction.perform(self)
        return
    end

    pcall(function()
        filledBag:setAge(0)
    end)
    pcall(function()
        local now = EHR.Transfusion.GetGameHour()
        local modData = filledBag:getModData()
        modData.EHR_BloodSpoilage = {
            createdHour = now,
            lastCheckHour = now,
            warmElapsed = 0,
            stale = false,
            rotten = false,
            isFrozen = EHR.Transfusion.IsBloodBagFrozenOrStored(filledBag),
        }
        modData.EHR_DonorBloodType = playerType
    end)

    -- Remove blood from player
    EHR.Blood.ModifyBloodVolume(self.character, -EHR.Transfusion.DrawBloodAmount)

    -- Remove the empty blood bag
    if isClient() then
        sendClientCommand(self.character, "EHR", "RemoveItem", {itemID = self.emptyBag:getID()})
    end
    inventory:Remove(self.emptyBag)

    EHR.Log("DrawBlood: Created " .. filledBagType .. " from player's blood")

    -- Apply effects from blood loss
    EHR.Locale.Say(self.character, getText("UI_EHR_DrawBlood_Complete") or "That made me lightheaded...")

    -- Small chance of minor fatigue/dizziness
    local stats = self.character:getStats()
    if stats and CharacterStat then
        if CharacterStat.FATIGUE then
            pcall(function()
                local current = stats:get(CharacterStat.FATIGUE) or 0
                stats:set(CharacterStat.FATIGUE, math.min(0.7, current + 0.15))
            end)
        end
        if CharacterStat.ENDURANCE then
            pcall(function()
                local current = stats:get(CharacterStat.ENDURANCE) or 1
                stats:set(CharacterStat.ENDURANCE, math.max(0.3, current - 0.2))
            end)
        end
    end

    -- Award First Aid XP
    if EHR.SkillXP and EHR.SkillXP.OnTransfusion then
        EHR.SkillXP.OnTransfusion(self.character, true)
    end

    -- MP: Trigger server sync after drawing blood
    if isClient() then
        sendClientCommand(self.character, "EHR", "RequestSync", {})
    end

    ISBaseTimedAction.perform(self)
end

function EHRDrawBloodAction:new(character, emptyBag)
    local o = ISBaseTimedAction.new(self, character)
    o.emptyBag = emptyBag
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = EHR.Transfusion.DrawBloodTime
    return o
end

--[[
    Check if an item is an empty blood bag
]]--
function EHR.Transfusion.IsEmptyBloodBag(item)
    if not item then return false end
    return item:getFullType() == "ExtensiveHealth.EmptyBloodBag"
end

--[[
    Check if player can safely draw blood
    Returns: canDraw, reason
]]--
function EHR.Transfusion.CanDrawBlood(player)
    local data = EHR.GetPlayerData(player)
    if not data or not data.EHR_Blood then
        return false, transfusionText("BloodSystemNotInitialized", "Blood system not initialized")
    end

    local bloodPercent = data.EHR_Blood.currentVolume / data.EHR_Blood.maxVolume

    if bloodPercent < EHR.Transfusion.MinBloodToDrawPercent then
        return false, transfusionFormat("NeedAtLeastBloodCurrently", "Need at least %1% blood (currently %2%)",
            math.floor(EHR.Transfusion.MinBloodToDrawPercent * 100),
            math.floor(bloodPercent * 100))
    end

    return true, transfusionText("Ok", "ok")
end


-- ============================================
-- CONTEXT MENU
-- ============================================

function EHR.Transfusion.OnFillInventoryContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    -- Get the actual item(s) from the selection
    local item = nil
    for _, v in ipairs(items) do
        if type(v) == "table" then
            item = v.items[1]
        else
            item = v
        end
        break
    end

    if not item then return end

    -- Check if it's a blood bag or saline
    if EHR.Transfusion.IsBloodBag(item) then
        local bagType = EHR.Transfusion.GetBagBloodType(item)
        local data = EHR.GetPlayerData(player)
        local playerType = data and data.EHR_Blood and data.EHR_Blood.bloodType or "?"

        -- Check spoilage state
        local spoilageState = EHR.Transfusion.GetSpoilageState(item)

        -- Don't allow using completely rotten blood
        if spoilageState == "rotten" then
            local option = context:addOption(transfusionText("UseBloodBagRotten", "Use Blood Bag (ROTTEN)"), player, nil)
            option.notAvailable = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip:setName(transfusionText("Unusable", "UNUSABLE"))
            tooltip.description = "<RGB:1,0,0> " .. transfusionText("BloodSpoiledDesc", "This blood bag has completely spoiled and cannot be used.") .. " <LINE> " .. transfusionText("DisposeSafely", "Dispose of it safely.")
            option.toolTip = tooltip
            return
        end

        -- Show compatibility info only after the player learns blood typing.
        local knowsBloodTypes = EHR.Transfusion.HasBloodTypeKnowledge(player)
        local compatible = data and EHR.Blood.IsCompatible(bagType, playerType)
        local compatText = ""
        if knowsBloodTypes then
            compatText = compatible and " " .. transfusionText("CompatibleSuffix", "(Compatible)") or " " .. transfusionText("IncompatibleSuffix", "(INCOMPATIBLE!)")
        end

        -- Add spoilage warning to text
        if spoilageState == "stale" then
            compatText = compatText .. " - " .. transfusionText("StaleSuffix", "STALE!")
        end

        local option = context:addOption(transfusionText("UseBloodBag", "Use Blood Bag") .. compatText, player, EHR.Transfusion.OnUseTransfusion, item)

        -- Build tooltip
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        local warningParts = {}

        if knowsBloodTypes and not compatible then
            tooltip:setName(transfusionText("Warning", "WARNING"))
            table.insert(warningParts, "<RGB:1,0.3,0.3> " .. transfusionFormat("IncompatibleDesc", "This blood type is NOT compatible with yours (%1)!", playerType))
            table.insert(warningParts, transfusionText("SevereReaction", "Using it will cause a severe reaction."))
        elseif not knowsBloodTypes then
            tooltip:setName(transfusionText("BloodCompatibilityUnknown", "Blood Compatibility Unknown"))
            table.insert(warningParts, "<RGB:0.7,0.7,0.7> " .. transfusionText("ReadBloodTypes", "Read the Blood Types flyer or reach First Aid level 8 to assess compatibility."))
        end

        if spoilageState == "stale" then
            if not tooltip.name or tooltip.name == "" then
                tooltip:setName(transfusionText("Caution", "CAUTION"))
            end
            table.insert(warningParts, "<LINE> <RGB:1,0.5,0> " .. transfusionText("BloodStaleDesc", "This blood is past its prime!"))
            table.insert(warningParts, transfusionText("SpoiledBloodRisk", "Using spoiled blood may cause infection and illness."))
        end

        if #warningParts > 0 then
            tooltip.description = table.concat(warningParts, " <LINE> ")
            option.toolTip = tooltip
        end

    elseif EHR.Transfusion.IsSalineBag(item) then
        -- Check saline spoilage
        local spoilageState = EHR.Transfusion.GetSpoilageState(item)

        if spoilageState == "rotten" then
            local option = context:addOption(transfusionText("UseSalineContaminated", "Use Saline IV (CONTAMINATED)"), player, nil)
            option.notAvailable = true
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip:setName(transfusionText("Unusable", "UNUSABLE"))
            tooltip.description = "<RGB:1,0,0> " .. transfusionText("SalineContaminatedDesc", "This saline bag has become contaminated and cannot be used.")
            option.toolTip = tooltip
            return
        end
        local option = context:addOption(transfusionText("UseSaline", "Use Saline IV"), player, EHR.Transfusion.OnUseTransfusion, item)

        -- Calculate current saline ratio for tooltip
        local data = EHR.GetPlayerData(player)
        local currentSaline = 0
        local currentVolume = 5000
        local salineRatio = 0
        if data and data.EHR_Blood then
            currentSaline = data.EHR_Blood.transfusedSaline or 0
            currentVolume = data.EHR_Blood.currentVolume or 5000
            if currentVolume > 0 then
                salineRatio = currentSaline / currentVolume
            end
        end

        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip:setName(transfusionText("SalineInfusion", "Saline Infusion"))

        local warningText = ""
        if EHR.Blood and EHR.Blood.HEMODILUTION_WARNING and salineRatio >= EHR.Blood.HEMODILUTION_WARNING then
            warningText = "<LINE> <RGB:1,0.5,0> " .. transfusionText("HighSalineWarning", "WARNING: High saline! Risk of hemodilution!")
        end
        if EHR.Blood and EHR.Blood.HEMODILUTION_THRESHOLD and salineRatio >= EHR.Blood.HEMODILUTION_THRESHOLD * 0.9 then
            warningText = "<LINE> <RGB:1,0,0> " .. transfusionText("NearLethalSaline", "DANGER: Near lethal saline! DO NOT USE!")
        end

        local salineAmount = EHR.Transfusion.SalineAmount or 250
        tooltip.description = transfusionText("SalineRestores", "Restores fluid volume without blood type matching.") .. " <LINE> " ..
                              transfusionFormat("SalineAdds", "Adds %1mL to blood volume.", salineAmount) .. " <LINE> " ..
                              transfusionFormat("CurrentSaline", "Current saline: %1mL (%2%)", math.floor(currentSaline), math.floor(salineRatio * 100)) ..
                              warningText .. "<LINE> <LINE> " ..
                              "<RGB:1,0.5,0> " .. transfusionText("SalineDeathCaution", "CAUTION: >60% saline causes brain oxygen deprivation and DEATH. Use blood bags when possible.")
        option.toolTip = tooltip

    elseif EHR.Transfusion.IsEmptyBloodBag(item) then
        -- Empty blood bag - option to draw blood from self
        local data = EHR.GetPlayerData(player)
        local playerType = data and data.EHR_Blood and data.EHR_Blood.bloodType or "?"
        local canDraw, drawReason = EHR.Transfusion.CanDrawBlood(player)

        local optionText = transfusionText("DrawBloodOption", "Draw Blood")
        local option = context:addOption(optionText, player, EHR.Transfusion.OnDrawBlood, item)

        -- Build tooltip
        local tooltip = ISWorldObjectContextMenu.addToolTip()
        tooltip:setName(transfusionText("BloodDonation", "Blood Donation"))

        local currentBlood = 0
        local maxBlood = 5000
        local bloodPercent = 100
        if data and data.EHR_Blood then
            currentBlood = data.EHR_Blood.currentVolume or 5000
            maxBlood = data.EHR_Blood.maxVolume or 5000
            bloodPercent = math.floor((currentBlood / maxBlood) * 100)
        end

        local drawAmount = EHR.Transfusion.DrawBloodAmount or 500
        local minPercent = math.floor(EHR.Transfusion.MinBloodToDrawPercent * 100)

        if canDraw then
            tooltip.description = (getText("UI_EHR_DrawBlood_Desc") or transfusionText("DrawBloodDesc", "Draw your own blood to store for later use.")) .. " <LINE> " ..
                                  "<LINE> " .. transfusionFormat("YourBloodType", "Your blood type: %1", "<RGB:0.5,1,0.5>" .. playerType) .. " <LINE> " ..
                                  "<RGB:1,1,1>" .. transfusionFormat("CurrentBlood", "Current blood: %1mL (%2%)", math.floor(currentBlood), bloodPercent) .. " <LINE> " ..
                                  transfusionFormat("WillRemove", "Will remove: %1mL", drawAmount) .. " <LINE> " ..
                                  "<LINE> <RGB:1,0.8,0.5>" .. transfusionText("AfterDonationDizzy", "After donation you may feel dizzy.")
        else
            option.notAvailable = true
            tooltip.description = "<RGB:1,0.3,0.3>" .. drawReason .. " <LINE> " ..
                                  "<LINE> <RGB:1,1,1>" .. transfusionFormat("NeedBlood", "You need at least %1% blood to safely donate.", minPercent) .. " <LINE> " ..
                                  transfusionFormat("CurrentBloodPercent", "Current blood: %1%", bloodPercent)
        end
        option.toolTip = tooltip
    end
end

function EHR.Transfusion.OnUseTransfusion(player, item)
    -- Transfer item to player's inventory if needed
    if item:getContainer() ~= player:getInventory() then
        ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, item:getContainer(), player:getInventory()))
    end
    -- Queue the timed action
    ISTimedActionQueue.add(EHRTransfusionAction:new(player, item))
end

function EHR.Transfusion.OnDrawBlood(player, emptyBag)
    -- Verify player can still draw blood
    local canDraw, reason = EHR.Transfusion.CanDrawBlood(player)
    if not canDraw then
        EHR.Locale.Say(player, reason)
        return
    end

    -- Transfer item to player's inventory if needed
    if emptyBag:getContainer() ~= player:getInventory() then
        ISTimedActionQueue.add(ISInventoryTransferAction:new(player, emptyBag, emptyBag:getContainer(), player:getInventory()))
    end

    -- Queue the draw blood timed action
    ISTimedActionQueue.add(EHRDrawBloodAction:new(player, emptyBag))
end


-- ============================================
-- BLOOD BAG FREEZING SYSTEM
-- Blood bags can be frozen indefinitely. Outside frozen
-- storage they become stale after 1 hour and spoil after 2 hours.
-- ============================================

EHR.Transfusion.FREEZE_GRACE_PERIOD = EHR.Transfusion.BLOOD_BAG_SPOIL_HOURS

-- Check if a container is a freezer (temperature below 0)
function EHR.Transfusion.IsInFreezer(item)
    local success, result = pcall(function()
        if not item then return false end

        local container = item:getContainer()
        if not container then return false end

        -- Check if container is part of a fridge/freezer
        local parent = container:getParent()
        if not parent then return false end

        -- Check if it's an IsoObject with fridge properties
        if parent.getModData then
            local modData = parent:getModData()
            -- Some freezers use modData to track temperature
            if modData and modData.freezerTemperature then
                return modData.freezerTemperature < 0
            end
        end

        -- Check container type name for freezer indicators
        local containerType = container:getType()
        if containerType then
            local typeLower = string.lower(containerType)
            if string.find(typeLower, "freezer") then
                return true
            end
        end

        -- Check if parent object is a freezer via sprite or name
        if parent.getSprite then
            local sprite = parent:getSprite()
            if sprite and sprite.getName then
                local spriteName = sprite:getName()
                if spriteName and string.find(string.lower(spriteName), "freezer") then
                    return true
                end
            end
        end

        -- Check object name
        if parent.getName then
            local name = parent:getName()
            if name and string.find(string.lower(name), "freezer") then
                return true
            end
        end

        -- B42: Check if the container has freezer temperature
        if container.getItemContainer then
            local ic = container:getItemContainer()
            if ic and ic.getTemperature then
                local temp = ic:getTemperature()
                if temp and temp < 0 then
                    return true
                end
            end
        end

        return false
    end)

    if success then
        return result
    else
        return false
    end
end

-- Get or create frozen tracking data for an item
function EHR.Transfusion.GetFrozenData(item)
    if not item then return nil end
    local modData = item:getModData()
    if not modData.EHR_Frozen then
        modData.EHR_Frozen = {
            wasFrozen = false,
            lastFreezerTime = nil,  -- Game time when last in freezer
        }
    end
    return modData.EHR_Frozen
end

-- Process a single blood bag for freezing logic
function EHR.Transfusion.ProcessBloodBagFreezing(item)
    if not item then return end
    if not EHR.Transfusion.IsBloodBag(item) then return end

    local spoilageData = EHR.Transfusion.UpdateBloodBagSpoilage(item)
    if EHR.DEBUG and spoilageData and spoilageData.rotten then
        print("[EHR Blood Storage] Blood bag spoiled after " ..
              string.format("%.1f", spoilageData.warmElapsed or 0) .. " warm hours")
    end
end

-- Scan all containers near player for blood bags
function EHR.Transfusion.ProcessNearbyBloodBags(player)
    if not player then return end

    -- Process player inventory
    local inventory = player:getInventory()
    if inventory then
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and EHR.Transfusion.IsBloodBag(item) then
                EHR.Transfusion.ProcessBloodBagFreezing(item)
            end
        end
    end

    -- Process equipped bags (backpack, etc.)
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    if containers and type(containers) == "table" then
        for _, container in ipairs(containers) do
            if container then
                local items = container:getItems()
                for i = 0, items:size() - 1 do
                    local item = items:get(i)
                    if item and EHR.Transfusion.IsBloodBag(item) then
                        EHR.Transfusion.ProcessBloodBagFreezing(item)
                    end
                end
            end
        end
    end
end

-- Tick counter for freezing checks
local freezeTickCounter = 0
local FREEZE_CHECK_INTERVAL = 300  -- Check every ~10 seconds

function EHR.Transfusion.OnTickFreezing()
    freezeTickCounter = freezeTickCounter + 1
    if freezeTickCounter < FREEZE_CHECK_INTERVAL then return end
    freezeTickCounter = 0

    local player = getSpecificPlayer(0)
    if not player or not player:isAlive() then return end

    EHR.Transfusion.ProcessNearbyBloodBags(player)
end


-- ============================================
-- REGISTER EVENTS
-- ============================================

Events.OnFillInventoryObjectContextMenu.Add(EHR.Transfusion.OnFillInventoryContextMenu)
Events.OnTick.Add(EHR.Transfusion.OnTickFreezing)

EHR.Log("Transfusion module loaded (with freezing system)")
