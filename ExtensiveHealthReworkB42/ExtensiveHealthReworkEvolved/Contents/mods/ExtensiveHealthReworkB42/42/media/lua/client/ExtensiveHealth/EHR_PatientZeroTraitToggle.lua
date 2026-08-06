-- Hide and block the optional Patient Zero creation trait when sandbox disables it.
require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_KnoxCure" end)
pcall(function() require "OptionScreens/CharacterCreationProfession" end)
pcall(function() require "OptionScreens/SandboxOptions" end)

EHR = EHR or {}
EHR.PatientZeroTraitToggle = EHR.PatientZeroTraitToggle or {}

local function currentPatientZeroDisabledOption()
    -- During new-world character creation SandboxVars may still contain the
    -- defaults. getSandboxOptions() already contains the values selected on
    -- the sandbox screen, so it must take priority in this frontend context.
    if getSandboxOptions then
        local ok, options = pcall(getSandboxOptions)
        if ok and options and options.getOptionByName then
            local optionOk, option = pcall(function()
                return options:getOptionByName("ExtensiveHealthRework.PatientZeroTraitDisabled")
            end)
            if optionOk and option and option.getValue then
                local valueOk, value = pcall(function() return option:getValue() end)
                if valueOk and value ~= nil then
                    return value == true
                end
            end
        end
    end
    return nil
end

local function isPatientZeroDisabled()
    local currentOption = currentPatientZeroDisabledOption()
    if currentOption ~= nil then
        return currentOption
    end

    if EHR.KnoxCure and EHR.KnoxCure.IsPatientZeroTraitEnabled then
        return not EHR.KnoxCure.IsPatientZeroTraitEnabled()
    end
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.PatientZeroTraitDisabled ~= nil then
        return options.PatientZeroTraitDisabled == true
    end
    return false
end

local function isPatientZeroTrait(trait)
    if not trait then return false end

    local traitType = nil
    if trait.getType then
        local ok, value = pcall(function() return trait:getType() end)
        if ok then traitType = value end
    end

    if EHRCharacterTraits and EHRCharacterTraits.patientzero and traitType == EHRCharacterTraits.patientzero then
        return true
    end

    local raw = string.lower(tostring(traitType or ""))
    if string.find(raw, "patientzero", 1, true) then return true end
    if string.find(raw, "patient zero", 1, true) then return true end

    if trait.getLabel then
        local ok, label = pcall(function() return trait:getLabel() end)
        if ok then
            label = string.lower(tostring(label or ""))
            if string.find(label, "patient zero", 1, true) then return true end
        end
    end

    return false
end

local function removeAvailablePatientZero(self)
    if not self or not isPatientZeroDisabled() then return end

    local function removeFrom(list)
        if not list or not list.items then return end
        for i = #list.items, 1, -1 do
            local entry = list.items[i]
            local trait = entry and entry.item
            if isPatientZeroTrait(trait) then
                local label = nil
                if trait and trait.getLabel then
                    local ok, value = pcall(function() return trait:getLabel() end)
                    if ok then label = value end
                end
                if label and list.removeMatchingItems then
                    list:removeMatchingItems(label)
                else
                    table.remove(list.items, i)
                end
            end
        end
    end

    removeFrom(self.listboxTrait)
    removeFrom(self.listboxBadTrait)
end

local function removeSelectedPatientZero(self)
    if not self or not self.listboxTraitSelected or not self.listboxTraitSelected.items then return end
    if not isPatientZeroDisabled() then return end

    for i = #self.listboxTraitSelected.items, 1, -1 do
        local entry = self.listboxTraitSelected.items[i]
        local trait = entry and entry.item
        if isPatientZeroTrait(trait) then
            local isFree = false
            if trait and trait.isFree then
                local ok, value = pcall(function() return trait:isFree() end)
                isFree = ok and value == true
            end
            if trait and trait.getCost and not isFree then
                local ok, cost = pcall(function() return trait:getCost() end)
                if ok and tonumber(cost) then
                    self.pointToSpend = self.pointToSpend + tonumber(cost)
                end
            end
            if trait and trait.getLabel then
                local ok, label = pcall(function() return trait:getLabel() end)
                if ok and label then
                    self.listboxTraitSelected:removeMatchingItems(label)
                end
            end
        end
    end
end

local function patchCharacterCreation()
    if not CharacterCreationProfession or EHR.PatientZeroTraitToggle.patched then return end
    EHR.PatientZeroTraitToggle.patched = true

    local originalIsTraitEnabled = CharacterCreationProfession.isTraitEnabled
    CharacterCreationProfession.isTraitEnabled = function(self, trait)
        if isPatientZeroDisabled() and isPatientZeroTrait(trait) then
            return false
        end
        if originalIsTraitEnabled then
            return originalIsTraitEnabled(self, trait)
        end
        return true
    end

    local originalAddTrait = CharacterCreationProfession.addTrait
    CharacterCreationProfession.addTrait = function(self, trait)
        if isPatientZeroDisabled() and isPatientZeroTrait(trait) then
            return
        end
        if originalAddTrait then
            return originalAddTrait(self, trait)
        end
    end

    local originalRepopulateTraitLists = CharacterCreationProfession.repopulateTraitLists
    CharacterCreationProfession.repopulateTraitLists = function(self)
        local result = originalRepopulateTraitLists(self)
        removeAvailablePatientZero(self)
        removeSelectedPatientZero(self)
        return result
    end

    local originalSetVisible = CharacterCreationProfession.setVisible
    CharacterCreationProfession.setVisible = function(self, visible, joypadData)
        local result = originalSetVisible(self, visible, joypadData)
        if visible then
            -- Re-check after the sandbox screen has committed its values.
            removeAvailablePatientZero(self)
            removeSelectedPatientZero(self)
        end
        return result
    end
end

local function patchSandboxCommit()
    if not SandboxOptionsScreen or EHR.PatientZeroTraitToggle.sandboxPatched then return end
    if not SandboxOptionsScreen.setSandboxVars then return end
    EHR.PatientZeroTraitToggle.sandboxPatched = true

    local originalSetSandboxVars = SandboxOptionsScreen.setSandboxVars
    SandboxOptionsScreen.setSandboxVars = function(self, ...)
        local result = originalSetSandboxVars(self, ...)

        -- Vanilla 42.20.1 opens CharacterCreationProfession immediately
        -- before calling setSandboxVars(). Refresh the already-visible lists
        -- now that the checkbox value has actually reached SandboxVars.
        local professionScreen = CharacterCreationProfession and CharacterCreationProfession.instance
        if not professionScreen and MainScreen and MainScreen.instance then
            professionScreen = MainScreen.instance.charCreationProfession
        end
        if professionScreen and professionScreen.repopulateTraitLists then
            professionScreen:repopulateTraitLists()
        end

        return result
    end
end

patchCharacterCreation()
patchSandboxCommit()
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(patchCharacterCreation)
    Events.OnGameBoot.Add(patchSandboxCommit)
end

if EHR.Log then EHR.Log("EHR_PatientZeroTraitToggle.lua loaded") end
