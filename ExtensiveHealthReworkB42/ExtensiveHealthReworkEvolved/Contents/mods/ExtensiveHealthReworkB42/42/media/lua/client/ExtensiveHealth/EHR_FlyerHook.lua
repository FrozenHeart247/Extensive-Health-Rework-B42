--[[
    Extensive Health Rework B42
    Disease Flyer Reading Hook (Client-Side)

    Hooks into ISReadABook:complete() to detect when disease flyers are read.
    Must be client-side because ISReadABook is a client-only timed action.
]]--

require "TimedActions/ISReadABook"
require "ExtensiveHealth/EHR_DiseaseFlyers"

EHR = EHR or {}
EHR.DiseaseFlyers = EHR.DiseaseFlyers or {}

-- Ensure config exists (loaded from shared file)
EHR.DiseaseFlyers.Config = EHR.DiseaseFlyers.Config or {
    FLYER_ITEMS = {
        ["ExtensiveHealth.DiseaseFlyer_CommonCold"] = "common_cold",
        ["ExtensiveHealth.DiseaseFlyer_Flu"] = "flu",
        ["ExtensiveHealth.DiseaseFlyer_Pneumonia"] = "pneumonia",
        ["ExtensiveHealth.DiseaseFlyer_FoodPoisoning"] = "food_poisoning",
        ["ExtensiveHealth.DiseaseFlyer_Hypothermia"] = "hypothermia",
        ["ExtensiveHealth.DiseaseFlyer_HeatExhaustion"] = "heat_exhaustion",
        ["ExtensiveHealth.DiseaseFlyer_Sepsis"] = "sepsis",
        ["ExtensiveHealth.DiseaseFlyer_CorpseSickness"] = "corpse_sickness",
        ["ExtensiveHealth.DiseaseFlyer_Tuberculosis"] = "tuberculosis",
    },
}

local function log(msg)
    if EHR and EHR.Log then
        EHR.Log(msg)
    else
        print("[EHR FlyerHook] " .. tostring(msg))
    end
end

local function clearFlyerReadProgress(character, item, itemId)
    if not character or not item or not itemId then return end

    pcall(function() item:setAlreadyReadPages(0) end)
    pcall(function() character:setAlreadyReadPages(itemId, 0) end)

    if sendSyncPlayerFields then
        pcall(sendSyncPlayerFields, character, 0x00000007)
    end

    if syncItemFields then
        pcall(syncItemFields, character, item)
    end
end

-- Hook into ISReadABook:complete() to detect when flyers are read
local function hookISReadABook()
    if not ISReadABook then
        log("ERROR: ISReadABook not found!")
        return false
    end

    if EHR.DiseaseFlyers.clientHooked then
        log("ISReadABook already hooked")
        return true
    end

    local originalComplete = ISReadABook.complete
    if not originalComplete then
        log("ERROR: ISReadABook.complete not found!")
        return false
    end

    ISReadABook.complete = function(self)
        -- Call original first
        local result = originalComplete(self)

        -- Then check if this was an EHR disease flyer
        if self.character and self.item then
            local itemId = self.item:getFullType()
            log("ISReadABook:complete() - item: " .. tostring(itemId))

            local diseaseId = EHR.DiseaseFlyers.Config.FLYER_ITEMS[itemId]
            if diseaseId then
                log("Detected EHR disease flyer! Disease: " .. tostring(diseaseId))

                -- Call the OnFlyerRead function from shared file
                if EHR.DiseaseFlyers.OnFlyerRead then
                    EHR.DiseaseFlyers.OnFlyerRead(self.character, self.item)
                else
                    -- Fallback: handle directly here
                    log("OnFlyerRead not found, handling directly")
                    local player = self.character
                    local modData = player:getModData()
                    if modData then
                        modData.EHR_KnownDiseases = modData.EHR_KnownDiseases or {}
                        if not modData.EHR_KnownDiseases[diseaseId] then
                            modData.EHR_KnownDiseases[diseaseId] = true
                            log("Disease knowledge unlocked: " .. diseaseId)

                            -- Say notification
                            local names = {
                                common_cold = "Common Cold",
                                flu = "Influenza",
                                pneumonia = "Pneumonia",
                                food_poisoning = "Food Poisoning",
                                hypothermia = "Hypothermia",
                                heat_exhaustion = "Heat Exhaustion",
                                sepsis = "Sepsis",
                                corpse_sickness = "Corpse Exposure Illness",
                                tuberculosis = "Tuberculosis",
                            }
                            local name = names[diseaseId] or diseaseId
                            player:Say("Disease knowledge acquired: " .. name)
                        else
                            player:Say("You already know about this disease.")
                        end

                        -- MP sync: send to server
                        if isClient() and sendClientCommand then
                            sendClientCommand(player, "EHR_Flyers", "UnlockDisease", { diseaseId = diseaseId })
                            log("Sent UnlockDisease command to server")
                        end
                    end
                end

                -- Disease flyers use the read action, but should not behave like
                -- skill books with persistent percentage progress.
                clearFlyerReadProgress(self.character, self.item, itemId)
            end
        end

        return result
    end

    EHR.DiseaseFlyers.clientHooked = true
    log("Successfully hooked ISReadABook:complete() for disease flyer detection")
    return true
end

-- Hook on game start to ensure ISReadABook is fully loaded
local function onGameStart()
    log("OnGameStart - attempting to hook ISReadABook")
    hookISReadABook()
end

-- Register the hook
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(onGameStart)
    log("Registered OnGameStart hook for flyer detection")
end

-- Also try immediate hook (might work if ISReadABook is already loaded)
if ISReadABook then
    hookISReadABook()
end

log("EHR_FlyerHook.lua loaded (client-side)")
