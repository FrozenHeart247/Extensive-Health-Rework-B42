pcall(function() require "ExtensiveHealth/EHR_Localization" end)
--[[
    Extensive Health Rework B42
    Knox Cure Context Menu Integration

    Adds right-click options for Knox cure items:
    - Gene Therapy Injector
    - Phalanx Suppressant Pills
    - Antibody Test Kit
    - Immunobooster Shot

    v1.0.0
]]--

require "ExtensiveHealth/EHR_KnoxCure"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferAction"

EHR = EHR or {}
EHR.KnoxCureMenu = {}

local function knoxMenuText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_KnoxCure_" .. tostring(key), fallback)
    end
    local fullKey = "UI_EHR_KnoxCure_" .. tostring(key)
    local ok, value = pcall(getText, fullKey)
    if ok and value and value ~= fullKey then return value end
    return fallback
end

local function knoxMenuFormat(key, fallback, ...)
    if EHR and EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format("UI_EHR_KnoxCure_" .. tostring(key), fallback, ...)
    end

    local text = knoxMenuText(key, fallback)
    local args = {...}
    for i, value in ipairs(args) do
        local replacement = tostring(value)
        text = tostring(text):gsub("%%" .. tostring(i) .. "%$[%a]", function() return replacement end)
        text = tostring(text):gsub("%%" .. tostring(i), function() return replacement end)
    end
    return text
end

local function knoxRatingText(rating)
    local ratingKeys = {
        ["High Compatibility"] = "Rating_High",
        ["Moderate Compatibility"] = "Rating_Moderate",
        ["Low Compatibility"] = "Rating_Low",
        ["Critical Risk"] = "Rating_Critical",
    }
    local key = ratingKeys[tostring(rating or "")]
    if not key then return tostring(rating or "") end
    return knoxMenuText(key, tostring(rating))
end

local function useKnoxCureItem(player, item, action)
    if not player or not item then return end

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR", "UseKnoxCureItem", {
            action = action,
            itemID = item:getID(),
            itemFullType = item:getFullType(),
        })
        return
    end

    if action == "geneTherapy" then
        EHR.KnoxCure.UseGeneTherapy(player, item)
    elseif action == "phalanx" then
        EHR.KnoxCure.UsePhalanx(player, item)
    elseif action == "antibodyTest" then
        EHR.KnoxCure.UseAntibodyTest(player, item)
    elseif action == "immunobooster" then
        EHR.KnoxCure.UseImmunobooster(player, item)
    end
end

-- ============================================
-- CONTEXT MENU HANDLERS
-- ============================================

--[[
    Add Knox Cure options to inventory context menu
]]--
function EHR.KnoxCureMenu.OnFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    -- Get the actual item from the context menu items
    local item = nil
    if items then
        for _, v in ipairs(items) do
            if type(v) == "table" and v.items then
                item = v.items[1]
            elseif not instanceof(v, "InventoryItem") then
                -- Skip
            else
                item = v
            end
            if item then break end
        end
    end

    if not item then return end

    local itemType = item:getType()
    local fullType = item:getFullType()

    -- Gene Therapy Injector
    if itemType == "GeneTherapyKit" or string.find(fullType, "GeneTherapyKit") then
        EHR.KnoxCureMenu.AddGeneTherapyOption(context, player, item)
    end

    -- Phalanx Suppressant Pills
    if itemType == "PhalanxPills" or string.find(fullType, "PhalanxPills") then
        EHR.KnoxCureMenu.AddPhalanxOption(context, player, item)
    end

    -- Antibody Test Kit
    if itemType == "AntibodyTestKit" or string.find(fullType, "AntibodyTestKit") then
        EHR.KnoxCureMenu.AddAntibodyTestOption(context, player, item)
    end

    -- Immunobooster Shot
    if itemType == "ImmunoboosterShot" or string.find(fullType, "ImmunoboosterShot") then
        EHR.KnoxCureMenu.AddImmunoboosterOption(context, player, item)
    end
end

-- ============================================
-- GENE THERAPY INJECTOR
-- ============================================

function EHR.KnoxCureMenu.AddGeneTherapyOption(context, player, item)
    local data = EHR.KnoxCure.GetData(player)

    -- Check if already immune
    if data and EHR.KnoxCure.HasPermanentKnoxImmunity and EHR.KnoxCure.HasPermanentKnoxImmunity(player, data) then
        local option = context:addOption(knoxMenuText("GeneTherapyAlreadyImmuneOption", "Gene Therapy (Already Immune)"), nil, nil)
        option.notAvailable = true
        if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip:setName(knoxMenuText("AlreadyImmuneTitle", "Already Immune"))
        option.toolTip.description = knoxMenuText("AlreadyImmuneDescription", "You survived Gene Therapy and are permanently immune to the Knox Virus.")
        return
    end

    -- Check if infected
    local isInfected = EHR.KnoxCure.IsInfected(player)

    -- Create option
    local optionText = knoxMenuText("UseGeneTherapy", "Use Gene Therapy Injector")
    local option = context:addOption(optionText, player, EHR.KnoxCureMenu.OnUseGeneTherapy, item)
    if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName(knoxMenuText("GeneTherapyTitle", "Gene Therapy Injector"))

    local desc = knoxMenuText("GeneTherapyDescription", "Experimental gene therapy that can cure Knox Virus infection.\n\n")
    desc = desc .. knoxMenuText("GeneTherapyCompatibility", "Success depends on blood type compatibility.\n")
    desc = desc .. knoxMenuText("GeneTherapyTestAdvice", "Use an Antibody Test first to check your odds.\n\n")

    if isInfected then
        desc = desc .. knoxMenuText("GeneTherapyInfectedWarning", "<RGB:1,0.5,0.5> WARNING: You are infected. This is a gamble between cure and death.")
    else
        desc = desc .. knoxMenuText("GeneTherapyNotInfected", "<RGB:0.5,0.5,1> You are not infected. Using this would be wasteful.")
        option.notAvailable = true
    end

    if EHR.KnoxCure.IsPatientZeroTraitEnabled and not EHR.KnoxCure.IsPatientZeroTraitEnabled() then
        desc = desc .. knoxMenuText("GeneTherapySuccessNoImmunity", "\n\n<RGB:0.7,0.7,0.7> If successful: current Knox infection cured. Patient Zero immunity is disabled by sandbox.")
    else
        desc = desc .. knoxMenuText("GeneTherapySuccessImmunity", "\n\n<RGB:0.7,0.7,0.7> If successful: Permanent immunity")
    end

    option.toolTip.description = desc
end

function EHR.KnoxCureMenu.OnUseGeneTherapy(player, item)
    -- Confirmation dialog for such a risky action
    local modal = ISModalDialog:new(
        getCore():getScreenWidth() / 2 - 150,
        getCore():getScreenHeight() / 2 - 50,
        300, 100,
        knoxMenuText("GeneTherapyConfirmation", "Use Gene Therapy?\nSuccess depends on blood type compatibility.\nFailure is fatal."),
        true, nil,
        EHR.KnoxCureMenu.OnGeneTherapyConfirm,
        player:getPlayerNum(),
        player, item
    )
    modal:initialise()
    modal:addToUIManager()
end

function EHR.KnoxCureMenu.OnGeneTherapyConfirm(this, button, player, item)
    if button.internal == "YES" then
        useKnoxCureItem(player, item, "geneTherapy")
    end
end

-- ============================================
-- PHALANX SUPPRESSANT PILLS
-- ============================================

function EHR.KnoxCureMenu.AddPhalanxOption(context, player, item)
    local data = EHR.KnoxCure.GetData(player)

    -- Check if immune
    if data and EHR.KnoxCure.HasPermanentKnoxImmunity and EHR.KnoxCure.HasPermanentKnoxImmunity(player, data) then
        local option = context:addOption(knoxMenuText("PhalanxAlreadyImmuneOption", "Take Phalanx (Already Immune)"), nil, nil)
        option.notAvailable = true
        if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end
        return
    end

    -- Check effectiveness
    local resetTo = EHR.KnoxCure.GetPhalanxEffectiveness(player)
    local usageCount = data and data.phalanxUsageCount or 0
    local isInfected = EHR.KnoxCure.IsInfected(player)

    -- Create option text
    local optionText
    if resetTo >= 100 then
        optionText = knoxMenuText("PhalanxNoEffectOption", "Take Phalanx (Body Adapted - No Effect)")
    elseif resetTo > 0 then
        optionText = knoxMenuFormat("PhalanxResetToOption", "Take Phalanx (Reset to %1)", tostring(resetTo) .. "%")
    else
        optionText = knoxMenuText("PhalanxFullResetOption", "Take Phalanx (Full Reset)")
    end

    local option = context:addOption(optionText, player, EHR.KnoxCureMenu.OnUsePhalanx, item)
    if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

    -- Disable if ineffective or not infected
    if resetTo >= 100 then
        option.notAvailable = true
    elseif not isInfected then
        option.notAvailable = true
    end

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName(knoxMenuText("PhalanxTitle", "Phalanx Suppressant"))

    local desc = knoxMenuText("PhalanxDescription", "Resets Knox Virus infection progress. Does NOT cure - only buys time.\n\n")
    desc = desc .. knoxMenuFormat("PhalanxTimesUsed", "Times Used: %1/%2\n", usageCount, 4)

    if resetTo < 100 then
        if resetTo == 0 then
            desc = desc .. knoxMenuFormat("PhalanxNextFullReset", "Next Use: Full reset (%1)\n", "0%")
        else
            desc = desc .. knoxMenuFormat("PhalanxNextResetTo", "Next Use: Reset to %1\n", tostring(resetTo) .. "%")
        end
    else
        desc = desc .. knoxMenuText("PhalanxBodyAdapted", "<RGB:1,0.5,0.5> Body has adapted - pills no longer effective\n")
    end

    desc = desc .. knoxMenuText("SideEffectsHeading", "\nSide Effects:\n")
    desc = desc .. knoxMenuText("PhalanxSideEffectNausea", "- Extreme nausea (6 hours)\n")
    desc = desc .. knoxMenuText("PhalanxSideEffectFever", "- Fever (12 hours)\n")
    desc = desc .. knoxMenuText("PhalanxSideEffectImmunity", "- Weakened immune system (48 hours)")

    if not isInfected then
        desc = desc .. knoxMenuText("NotInfected", "\n\n<RGB:0.5,0.5,1> You are not infected.")
    end

    option.toolTip.description = desc
end

function EHR.KnoxCureMenu.OnUsePhalanx(player, item)
    useKnoxCureItem(player, item, "phalanx")
end

-- ============================================
-- ANTIBODY TEST KIT
-- ============================================

function EHR.KnoxCureMenu.AddAntibodyTestOption(context, player, item)
    local data = EHR.KnoxCure.GetData(player)

    local option = context:addOption(knoxMenuText("UseAntibodyTest", "Use Antibody Test"), player, EHR.KnoxCureMenu.OnUseAntibodyTest, item)
    if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName(knoxMenuText("AntibodyTestTitle", "Antibody Compatibility Test"))

    local desc = knoxMenuText("AntibodyTestDescription", "Tests your compatibility with Gene Therapy treatment.\n\n")
    desc = desc .. knoxMenuText("AntibodyTestChance", "Shows your survival chance before risking the injector.\n\n")
    desc = desc .. knoxMenuText("AntibodyTestSingleUse", "Single use - test kit is consumed.")

    -- Show cached result if available
    if data and data.lastTestResult then
        local result = data.lastTestResult
        desc = desc .. knoxMenuFormat(
            "AntibodyLastResult",
            "\n\n<RGB:0.7,0.7,0.7> Last Result: %1 (%2 survival)",
            knoxRatingText(result.rating),
            tostring(result.chance) .. "%"
        )
    end

    option.toolTip.description = desc
end

function EHR.KnoxCureMenu.OnUseAntibodyTest(player, item)
    -- Transfer first so timed action validation and server-side consumption work
    -- the same from backpacks, belt slots, and the main inventory.
    if item and item.getContainer and item:getContainer() ~= player:getInventory() then
        ISTimedActionQueue.add(ISInventoryTransferAction:new(player, item, item:getContainer(), player:getInventory()))
    end

    -- Start a timed action for the test
    ISTimedActionQueue.add(ISEHRAntibodyTestAction:new(player, item, 200))  -- ~6.6 seconds
end

-- ============================================
-- IMMUNOBOOSTER SHOT
-- ============================================

function EHR.KnoxCureMenu.AddImmunoboosterOption(context, player, item)
    local data = EHR.KnoxCure.GetData(player)

    -- Check if already immune
    if data and EHR.KnoxCure.HasPermanentKnoxImmunity and EHR.KnoxCure.HasPermanentKnoxImmunity(player, data) then
        local option = context:addOption(knoxMenuText("ImmunoboosterAlreadyImmuneOption", "Use Immunobooster (Already Immune)"), nil, nil)
        option.notAvailable = true
        if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end
        return
    end

    -- Check various states
    local isActive = EHR.KnoxCure.IsImmunoboosterActive(player)
    local isOnCooldown = EHR.KnoxCure.IsImmunoboosterOnCooldown(player)
    local isInfected = EHR.KnoxCure.IsInfected(player)
    local hasBites = EHR.KnoxCure.HasBites and EHR.KnoxCure.HasBites(player) or false
    local remaining = EHR.KnoxCure.GetImmunoboosterRemaining(player)
    local cooldownRemaining = EHR.KnoxCure.GetImmunoboosterCooldownRemaining
        and EHR.KnoxCure.GetImmunoboosterCooldownRemaining(player)
        or 0

    -- Create option
    local optionText
    if isActive then
        optionText = knoxMenuFormat("ImmunoboosterActiveOption", "Immunobooster (Active - %1h left)", string.format("%.0f", remaining))
    elseif isOnCooldown then
        optionText = knoxMenuFormat("ImmunoboosterCooldownOption", "Use Immunobooster (Cooldown %1h)", string.format("%.0f", cooldownRemaining))
    elseif isInfected then
        optionText = knoxMenuText("ImmunoboosterAlreadyInfectedOption", "Use Immunobooster (Already Infected)")
    elseif hasBites then
        optionText = knoxMenuText("ImmunoboosterAlreadyBittenOption", "Use Immunobooster (Already Bitten)")
    else
        optionText = knoxMenuText("UseImmunobooster", "Use Immunobooster (24h Protection)")
    end

    local option = context:addOption(optionText, player, EHR.KnoxCureMenu.OnUseImmunobooster, item)
    if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end

    -- Disable if not usable
    if isActive or isOnCooldown or isInfected or hasBites then
        option.notAvailable = true
    end

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName(knoxMenuText("ImmunoboosterTitle", "Immunobooster Shot"))

    local desc = knoxMenuText("ImmunoboosterDescription", "Pre-exposure prophylaxis. Grants 24 hours of Knox Virus immunity.\n\n")
    desc = desc .. knoxMenuText("ImmunoboosterTiming", "Must be taken BEFORE infection - does not help if already infected.\n\n")

    if isActive then
        desc = desc .. knoxMenuFormat("ImmunoboosterCurrentlyActive", "<RGB:0.2,0.8,0.2> Currently Active: %1 hours remaining\n", string.format("%.1f", remaining))
    elseif isOnCooldown then
        desc = desc .. knoxMenuFormat("ImmunoboosterOnCooldown", "<RGB:1,0.5,0.5> On Cooldown: %1 hours remaining\n", string.format("%.1f", cooldownRemaining))
    elseif isInfected then
        desc = desc .. knoxMenuText("ImmunoboosterAlreadyInfected", "<RGB:1,0.5,0.5> Already Infected: Too late for prevention\n")
    elseif hasBites then
        desc = desc .. knoxMenuText("ImmunoboosterAlreadyBitten", "<RGB:1,0.5,0.5> Already Bitten: this must be used before exposure\n")
    else
        desc = desc .. knoxMenuText("ImmunoboosterReady", "<RGB:0.5,1,0.5> Ready to use\n")
    end

    desc = desc .. knoxMenuText("ImmunoboosterSideEffectsHeading", "\nSide Effects (while active):\n")
    desc = desc .. knoxMenuText("ImmunoboosterSideEffectNausea", "- Mild nausea\n")
    desc = desc .. knoxMenuText("ImmunoboosterSideEffectStamina", "- Reduced stamina regeneration\n")
    desc = desc .. knoxMenuText("ImmunoboosterSideEffectTremors", "- Occasional tremors")

    option.toolTip.description = desc
end

function EHR.KnoxCureMenu.OnUseImmunobooster(player, item)
    useKnoxCureItem(player, item, "immunobooster")
end

-- ============================================
-- TIMED ACTION: Antibody Test
-- ============================================

ISEHRAntibodyTestAction = ISBaseTimedAction:derive("ISEHRAntibodyTestAction")

function ISEHRAntibodyTestAction:new(player, item, time)
    local o = ISBaseTimedAction.new(self, player)
    o.item = item
    o.maxTime = time
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function ISEHRAntibodyTestAction:isValid()
    if not self.item or not self.character or not self.character:isAlive() then return false end
    local inventory = self.character:getInventory()
    return inventory and inventory:contains(self.item)
end

function ISEHRAntibodyTestAction:start()
    if self.character.Say then
        EHR.Locale.Say(self.character, knoxMenuText("RunningTest", "Running the test..."))
    end
end

function ISEHRAntibodyTestAction:update()
    -- Progress update
end

function ISEHRAntibodyTestAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISEHRAntibodyTestAction:perform()
    useKnoxCureItem(self.character, self.item, "antibodyTest")
    ISBaseTimedAction.perform(self)
end

-- ============================================
-- EVENT REGISTRATION
-- ============================================

if not EHR.KnoxCureMenu._registered then
    EHR.KnoxCureMenu._registered = true
    Events.OnFillInventoryObjectContextMenu.Add(EHR.KnoxCureMenu.OnFillInventoryObjectContextMenu)
    EHR.Log("KnoxCureMenu: Context menu hooks registered")
end
