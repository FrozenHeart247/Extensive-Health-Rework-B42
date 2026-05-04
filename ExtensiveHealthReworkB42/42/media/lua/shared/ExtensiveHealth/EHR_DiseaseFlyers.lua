--[[
    Extensive Health Rework B42
    Disease Information Flyers

    Reading a flyer unlocks permanent disease identification.
    MP-safe: client sends unlock to server, server persists and syncs.
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.DiseaseFlyers = EHR.DiseaseFlyers or {}

EHR.DiseaseFlyers.Config = {
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
    KNOWLEDGE_IDS = {
        common_cold = true,
        flu = true,
        pneumonia = true,
        food_poisoning = true,
        hypothermia = true,
        heat_exhaustion = true,
        sepsis = true,
        corpse_sickness = true,
        tuberculosis = true,
    },
    SELF_EVIDENT = {
        food_poisoning = true,
        hypothermia = true,
        heat_exhaustion = true,
        heat_stroke = true,
    },
}

local function normalizeDiseaseId(diseaseId)
    if diseaseId == "Sepsis" then
        return "sepsis"
    end
    return diseaseId
end

function EHR.DiseaseFlyers.GetKnownDiseases(player)
    if not player then return {} end
    local modData = player:getModData()
    if not modData then return {} end
    modData.EHR_KnownDiseases = modData.EHR_KnownDiseases or {}
    return modData.EHR_KnownDiseases
end

function EHR.DiseaseFlyers.KnowsDisease(player, diseaseId)
    if not player or not diseaseId then return false end
    local known = EHR.DiseaseFlyers.GetKnownDiseases(player)
    return known[diseaseId] == true
end

function EHR.DiseaseFlyers.GetDiseaseFriendlyName(diseaseId)
    local names = {
        common_cold = "Common Cold",
        flu = "Influenza",
        pneumonia = "Pneumonia",
        food_poisoning = "Food Poisoning",
        hypothermia = "Hypothermia",
        heat_exhaustion = "Heat Exhaustion",
        heat_stroke = "Heat Stroke",
        sepsis = "Sepsis",
        corpse_sickness = "Corpse Exposure Illness",
        tuberculosis = "Tuberculosis",
    }
    return names[diseaseId] or diseaseId
end

function EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId)
    if not player or not diseaseId then return false end

    local modData = player:getModData()
    if not modData then return false end

    modData.EHR_KnownDiseases = modData.EHR_KnownDiseases or {}
    if modData.EHR_KnownDiseases[diseaseId] then
        return false
    end

    modData.EHR_KnownDiseases[diseaseId] = true

    local name = EHR.DiseaseFlyers.GetDiseaseFriendlyName(diseaseId)
    if player.Say then
        local learnedText = getText and getText("UI_EHR_FlyerLearned", name) or nil
        player:Say(learnedText or ("Disease knowledge acquired: " .. name))
    end

    EHR.Log("Player learned disease: " .. tostring(diseaseId))
    return true
end

function EHR.DiseaseFlyers.CanIdentifyDisease(player, diseaseId)
    if not player or not diseaseId then return false end

    local normalized = normalizeDiseaseId(diseaseId)
    if not EHR.DiseaseFlyers.Config.KNOWLEDGE_IDS[normalized] then
        return true
    end

    if EHR.DiseaseFlyers.KnowsDisease(player, normalized) then
        return true
    end

    if EHR.DiseaseFlyers.Config.SELF_EVIDENT[normalized] then
        return true
    end

    return false
end

function EHR.DiseaseFlyers.GetUnknownDiseaseDisplay(diseaseId)
    local normalized = normalizeDiseaseId(diseaseId)
    local categories = {
        common_cold = { displayName = "Unknown Respiratory Illness", description = "You feel unwell with respiratory symptoms." },
        flu = { displayName = "Unknown Respiratory Illness", description = "You feel very unwell with fever and body aches." },
        pneumonia = { displayName = "Severe Respiratory Illness", description = "Your lungs feel inflamed. This seems serious." },
        sepsis = { displayName = "Systemic Illness", description = "Your whole body feels wrong. This is very serious." },
        corpse_sickness = { displayName = "Unknown Illness", description = "You feel nauseous and unwell." },
        tuberculosis = { displayName = "Chronic Respiratory Illness", description = "A persistent illness affecting your lungs." },
    }

    local unknownName = getText and getText("UI_EHR_DiseaseUnknown") or nil
    return categories[normalized] or { displayName = unknownName or "Unknown Illness", description = "You feel unwell." }
end

function EHR.DiseaseFlyers.OnFlyerRead(player, item)
    if not player or not item then return end

    local itemId = item.getFullType and item:getFullType() or nil
    if not itemId then return end

    local diseaseId = EHR.DiseaseFlyers.Config.FLYER_ITEMS[itemId]
    if not diseaseId then return end

    EHR.Log("OnFlyerRead triggered for: " .. tostring(itemId) .. " -> disease: " .. tostring(diseaseId))

    if isClient and isClient() then
        local newlyLearned = EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId)
        if not newlyLearned and player.Say then
            local alreadyText = getText and getText("UI_EHR_FlyerAlreadyKnown") or nil
            player:Say(alreadyText or "You already know about this disease.")
        end
        if sendClientCommand then
            sendClientCommand(player, "EHR_Flyers", "UnlockDisease", { diseaseId = diseaseId })
        end
        return
    end

    local newlyLearned = EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId)
    if not newlyLearned and player.Say then
        local alreadyText = getText and getText("UI_EHR_FlyerAlreadyKnown") or nil
        player:Say(alreadyText or "You already know about this disease.")
    end
end

-- NOTE: The actual hook into ISReadABook:complete() is in the client-side file
-- EHR_FlyerHook.lua because ISReadABook is a client-only timed action class.
-- This shared file only contains the data functions used by both client and server.

EHR.Log("EHR_DiseaseFlyers.lua loaded")
