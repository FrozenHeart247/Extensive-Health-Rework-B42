-- Hide and block the optional Patient Zero creation trait when sandbox disables it.
require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_KnoxCure" end)
pcall(function() require "OptionScreens/CharacterCreationProfession" end)

EHR = EHR or {}
EHR.PatientZeroTraitToggle = EHR.PatientZeroTraitToggle or {}

local function isPatientZeroDisabled()
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
        removeSelectedPatientZero(self)
        return result
    end
end

patchCharacterCreation()
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(patchCharacterCreation)
end

if EHR.Log then EHR.Log("EHR_PatientZeroTraitToggle.lua loaded") end