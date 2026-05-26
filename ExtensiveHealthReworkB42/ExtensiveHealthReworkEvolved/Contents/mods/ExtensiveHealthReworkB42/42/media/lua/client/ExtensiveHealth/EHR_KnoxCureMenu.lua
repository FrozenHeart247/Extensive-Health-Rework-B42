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

EHR = EHR or {}
EHR.KnoxCureMenu = {}

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
    if data and data.geneTherapyImmune then
        local option = context:addOption("Gene Therapy (Already Immune)", nil, nil)
        option.notAvailable = true
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip:setName("Already Immune")
        option.toolTip.description = "You survived Gene Therapy and are permanently immune to the Knox Virus."
        return
    end

    -- Check if infected
    local isInfected = EHR.KnoxCure.IsInfected(player)

    -- Create option
    local optionText = "Use Gene Therapy Injector"
    local option = context:addOption(optionText, player, EHR.KnoxCureMenu.OnUseGeneTherapy, item)

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName("Gene Therapy Injector")

    local desc = "Experimental gene therapy that can cure Knox Virus infection.\n\n"
    desc = desc .. "Success depends on blood type compatibility.\n"
    desc = desc .. "Use an Antibody Test first to check your odds.\n\n"

    if isInfected then
        desc = desc .. "<RGB:1,0.5,0.5> WARNING: You are infected. This is a gamble between cure and death."
    else
        desc = desc .. "<RGB:0.5,0.5,1> You are not infected. Using this would be wasteful."
        option.notAvailable = true
    end

    desc = desc .. "\n\n<RGB:0.7,0.7,0.7> If successful: Permanent immunity"

    option.toolTip.description = desc
end

function EHR.KnoxCureMenu.OnUseGeneTherapy(player, item)
    -- Confirmation dialog for such a risky action
    local modal = ISModalDialog:new(
        getCore():getScreenWidth() / 2 - 150,
        getCore():getScreenHeight() / 2 - 50,
        300, 100,
        "Use Gene Therapy?\nSuccess depends on blood type compatibility.\nFailure is fatal.",
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
    if data and data.geneTherapyImmune then
        local option = context:addOption("Take Phalanx (Already Immune)", nil, nil)
        option.notAvailable = true
        return
    end

    -- Check effectiveness
    local resetTo = EHR.KnoxCure.GetPhalanxEffectiveness(player)
    local usageCount = data and data.phalanxUsageCount or 0
    local isInfected = EHR.KnoxCure.IsInfected(player)

    -- Create option text
    local optionText
    if resetTo >= 100 then
        optionText = "Take Phalanx (Body Adapted - No Effect)"
    elseif resetTo > 0 then
        optionText = string.format("Take Phalanx (Reset to %d%%)", resetTo)
    else
        optionText = "Take Phalanx (Full Reset)"
    end

    local option = context:addOption(optionText, player, EHR.KnoxCureMenu.OnUsePhalanx, item)

    -- Disable if ineffective or not infected
    if resetTo >= 100 then
        option.notAvailable = true
    elseif not isInfected then
        option.notAvailable = true
    end

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName("Phalanx Suppressant")

    local desc = "Resets Knox Virus infection progress. Does NOT cure - only buys time.\n\n"
    desc = desc .. "Times Used: " .. usageCount .. "/4\n"

    if resetTo < 100 then
        if resetTo == 0 then
            desc = desc .. "Next Use: Full reset (0%)\n"
        else
            desc = desc .. "Next Use: Reset to " .. resetTo .. "%\n"
        end
    else
        desc = desc .. "<RGB:1,0.5,0.5> Body has adapted - pills no longer effective\n"
    end

    desc = desc .. "\nSide Effects:\n"
    desc = desc .. "- Extreme nausea (6 hours)\n"
    desc = desc .. "- Fever (12 hours)\n"
    desc = desc .. "- Weakened immune system (48 hours)"

    if not isInfected then
        desc = desc .. "\n\n<RGB:0.5,0.5,1> You are not infected."
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

    local option = context:addOption("Use Antibody Test", player, EHR.KnoxCureMenu.OnUseAntibodyTest, item)

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName("Antibody Compatibility Test")

    local desc = "Tests your compatibility with Gene Therapy treatment.\n\n"
    desc = desc .. "Shows your survival chance before risking the injector.\n\n"
    desc = desc .. "Single use - test kit is consumed."

    -- Show cached result if available
    if data and data.lastTestResult then
        local result = data.lastTestResult
        desc = desc .. "\n\n<RGB:0.7,0.7,0.7> Last Result: " .. result.rating
        desc = desc .. " (" .. result.chance .. "% survival)"
    end

    option.toolTip.description = desc
end

function EHR.KnoxCureMenu.OnUseAntibodyTest(player, item)
    -- Start a timed action for the test
    ISTimedActionQueue.add(ISEHRAntibodyTestAction:new(player, item, 200))  -- ~6.6 seconds
end

-- ============================================
-- IMMUNOBOOSTER SHOT
-- ============================================

function EHR.KnoxCureMenu.AddImmunoboosterOption(context, player, item)
    local data = EHR.KnoxCure.GetData(player)

    -- Check if already immune
    if data and data.geneTherapyImmune then
        local option = context:addOption("Use Immunobooster (Already Immune)", nil, nil)
        option.notAvailable = true
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
        optionText = string.format("Immunobooster (Active - %.0fh left)", remaining)
    elseif isOnCooldown then
        optionText = string.format("Use Immunobooster (Cooldown %.0fh)", cooldownRemaining)
    elseif isInfected then
        optionText = "Use Immunobooster (Already Infected)"
    elseif hasBites then
        optionText = "Use Immunobooster (Already Bitten)"
    else
        optionText = "Use Immunobooster (24h Protection)"
    end

    local option = context:addOption(optionText, player, EHR.KnoxCureMenu.OnUseImmunobooster, item)

    -- Disable if not usable
    if isActive or isOnCooldown or isInfected or hasBites then
        option.notAvailable = true
    end

    -- Add tooltip
    option.toolTip = ISWorldObjectContextMenu.addToolTip()
    option.toolTip:setName("Immunobooster Shot")

    local desc = "Pre-exposure prophylaxis. Grants 24 hours of Knox Virus immunity.\n\n"
    desc = desc .. "Must be taken BEFORE infection - does not help if already infected.\n\n"

    if isActive then
        desc = desc .. "<RGB:0.2,0.8,0.2> Currently Active: " .. string.format("%.1f hours remaining", remaining) .. "\n"
    elseif isOnCooldown then
        desc = desc .. "<RGB:1,0.5,0.5> On Cooldown: " .. string.format("%.1f hours remaining", cooldownRemaining) .. "\n"
    elseif isInfected then
        desc = desc .. "<RGB:1,0.5,0.5> Already Infected: Too late for prevention\n"
    elseif hasBites then
        desc = desc .. "<RGB:1,0.5,0.5> Already Bitten: this must be used before exposure\n"
    else
        desc = desc .. "<RGB:0.5,1,0.5> Ready to use\n"
    end

    desc = desc .. "\nSide Effects (while active):\n"
    desc = desc .. "- Mild nausea\n"
    desc = desc .. "- Reduced stamina regeneration\n"
    desc = desc .. "- Occasional tremors"

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
    return self.item and self.character:getInventory():contains(self.item)
end

function ISEHRAntibodyTestAction:start()
    if self.character.Say then
        EHR.Locale.Say(self.character, "Running the test...")
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
