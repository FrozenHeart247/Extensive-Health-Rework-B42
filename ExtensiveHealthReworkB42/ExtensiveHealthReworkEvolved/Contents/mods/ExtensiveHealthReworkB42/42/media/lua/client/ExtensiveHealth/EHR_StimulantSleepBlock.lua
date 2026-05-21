-- Blocks normal sleep while EHR stimulant effects are active.

require "ExtensiveHealth/EHR_Medication"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISSleepDialog"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.Stimulants = EHR.Stimulants or {}

local function EHR_StimulantSleepText()
    if getText then
        local key = "UI_EHR_Caffeine_NoSleep"
        local text = getText(key)
        if text and text ~= key then
            return text
        end
    end
    return "The caffeine is still burning through me. I can't sleep."
end

local function EHR_StimulantSleepBlocked(player)
    if not player or not EHR.Medication or not EHR.Medication.IsCaffeineAwake then
        return false
    end

    if not EHR.Medication.IsCaffeineAwake(player) then
        return false
    end

    local text = EHR_StimulantSleepText()
    if HaloTextHelper and HaloTextHelper.addBadText then
        pcall(function() HaloTextHelper.addBadText(player, text) end)
    elseif player.Say then
        pcall(function() EHR.Locale.Say(player, text) end)
    end

    return true
end

function EHR.Stimulants.HookSleep()
    if EHR.Stimulants.sleepHooked then return end

    local hooked = false

    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.onSleepWalkToComplete then
        local originalSleepWalkToComplete = ISWorldObjectContextMenu.onSleepWalkToComplete
        ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerNum, bed)
            local playerObj = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
            if EHR_StimulantSleepBlocked(playerObj) then
                return
            end
            return originalSleepWalkToComplete(playerNum, bed)
        end
        hooked = true
    end

    if ISSleepDialog and ISSleepDialog.onClick then
        local originalSleepDialogClick = ISSleepDialog.onClick
        ISSleepDialog.onClick = function(self, button)
            if button and button.internal == "YES" and EHR_StimulantSleepBlocked(self and self.player) then
                if self and self.destroy then
                    self:destroy()
                end
                return
            end
            return originalSleepDialogClick(self, button)
        end
        hooked = true
    end

    if not hooked then
        return false
    end

    EHR.Stimulants.sleepHooked = true
    return true
end

if not EHR.Stimulants.HookSleep() and Events and Events.OnGameStart then
    Events.OnGameStart.Add(EHR.Stimulants.HookSleep)
end
