--[[
    Extensive Health Rework B42
    Disease Information Flyers

    Reading a flyer unlocks permanent disease identification.
    MP-safe: client sends unlock to server, server persists and syncs.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_SkillXP"

EHR = EHR or {}
EHR.DiseaseFlyers = EHR.DiseaseFlyers or {}

EHR.DiseaseFlyers.Config = {
    KNOWLEDGE_XP = 50,
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

local diseaseAliases = {
    CommonCold = "common_cold",
    Cold = "common_cold",
    Flu = "flu",
    Influenza = "flu",
    Pneumonia = "pneumonia",
    FoodPoisoning = "food_poisoning",
    Hypothermia = "hypothermia",
    HeatExhaustion = "heat_exhaustion",
    HeatStroke = "heat_stroke",
    Sepsis = "sepsis",
    CorpseDisease = "corpse_sickness",
    CorpseSickness = "corpse_sickness",
    CorpseExposureIllness = "corpse_sickness",
    TuberculosisCavitary = "tuberculosis",
    TuberculosisMilliary = "tuberculosis",
    Tuberculosis = "tuberculosis",
    WoundInfection = "wound_infection",
    Wound_Infection = "wound_infection",
    KnoxInfection = "knox_infection",
    Knox_Infection = "knox_infection",
}

local compactDiseaseAliases = {
    commoncold = "common_cold",
    cold = "common_cold",
    flu = "flu",
    influenza = "flu",
    pneumonia = "pneumonia",
    foodpoisoning = "food_poisoning",
    hypothermia = "hypothermia",
    heatexhaustion = "heat_exhaustion",
    heatstroke = "heat_stroke",
    sepsis = "sepsis",
    corpsedisease = "corpse_sickness",
    corpsesickness = "corpse_sickness",
    corpseexposureillness = "corpse_sickness",
    tuberculosis = "tuberculosis",
    tuberculosiscavitary = "tuberculosis",
    tuberculosismilliary = "tuberculosis",
    woundinfection = "wound_infection",
    knoxinfection = "knox_infection",
}

local function normalizeDiseaseId(diseaseId)
    if not diseaseId then return diseaseId end

    local rawId = tostring(diseaseId)
    if EHR.DiseaseFlyers.Config.KNOWLEDGE_IDS[rawId] or EHR.DiseaseFlyers.Config.SELF_EVIDENT[rawId] then
        return rawId
    end

    if diseaseAliases[rawId] then
        return diseaseAliases[rawId]
    end

    local compact = rawId:gsub("[%s_%-%(%)]", ""):lower()
    return compactDiseaseAliases[compact] or rawId
end

EHR.DiseaseFlyers.NormalizeDiseaseId = normalizeDiseaseId

local function flyerText(key, fallback, ...)
    local text = nil
    if getText then
        text = getText(key)
    end
    if not text or text == key then
        text = fallback
    end

    local args = { ... }
    for i, value in ipairs(args) do
        local safeValue = tostring(value or "")
        text = text:gsub("%%" .. tostring(i), safeValue)
        if i == 1 then
            text = text:gsub("%%s", safeValue)
            text = text:gsub("{0}", safeValue)
        end
    end

    return text
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
    diseaseId = normalizeDiseaseId(diseaseId)
    local known = EHR.DiseaseFlyers.GetKnownDiseases(player)
    return known[diseaseId] == true
end

function EHR.DiseaseFlyers.GetDiseaseFriendlyName(diseaseId)
    diseaseId = normalizeDiseaseId(diseaseId)

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
        wound_infection = "Wound Infection",
        knox_infection = "Knox Infection",
    }
    return names[diseaseId] or diseaseId
end

function EHR.DiseaseFlyers.AwardKnowledgeXP(player, diseaseId)
    if not player or not EHR.SkillXP or not EHR.SkillXP.AwardXP then return false end

    local amount = EHR.DiseaseFlyers.Config.KNOWLEDGE_XP or 50
    local awarded = EHR.SkillXP.AwardXP(player, amount, "disease_flyer_read", nil)

    if awarded and EHR.DEBUG then
        EHR.Log("Disease flyer XP awarded for: " .. tostring(diseaseId))
    end

    return awarded
end

function EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId)
    if not player or not diseaseId then return false end
    diseaseId = normalizeDiseaseId(diseaseId)

    local modData = player:getModData()
    if not modData then return false end

    modData.EHR_KnownDiseases = modData.EHR_KnownDiseases or {}
    if modData.EHR_KnownDiseases[diseaseId] then
        return false
    end

    modData.EHR_KnownDiseases[diseaseId] = true
    modData.EHR_MedicalJournal = modData.EHR_MedicalJournal or { entries = {}, discoveries = {} }
    modData.EHR_MedicalJournal.discoveries = modData.EHR_MedicalJournal.discoveries or {}
    modData.EHR_MedicalJournal.discoveries[diseaseId] = getGameTime():getWorldAgeHours()
    modData.EHR_MedicalJournal.lastUpdated = getGameTime():getWorldAgeHours()

    if player.transmitModData then
        pcall(function() player:transmitModData() end)
    end

    local name = EHR.DiseaseFlyers.GetDiseaseFriendlyName(diseaseId)
    if player.Say then
        player:Say(flyerText("UI_EHR_FlyerLearned", "Disease knowledge acquired: %1", name))
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
        if newlyLearned then
            EHR.DiseaseFlyers.AwardKnowledgeXP(player, diseaseId)
        end
        if not newlyLearned and player.Say then
            player:Say(flyerText("UI_EHR_FlyerAlreadyKnown", "You already know about this disease."))
        end
        if sendClientCommand then
            sendClientCommand(player, "EHR_Flyers", "UnlockDisease", { diseaseId = normalizeDiseaseId(diseaseId) })
        end
        return
    end

    local newlyLearned = EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId)
    if newlyLearned then
        EHR.DiseaseFlyers.AwardKnowledgeXP(player, diseaseId)
    end
    if not newlyLearned and player.Say then
        player:Say(flyerText("UI_EHR_FlyerAlreadyKnown", "You already know about this disease."))
    end
end

-- NOTE: The actual hook into ISReadABook:complete() is in the client-side file
-- EHR_FlyerHook.lua because ISReadABook is a client-only timed action class.
-- This shared file only contains the data functions used by both client and server.

EHR.Log("EHR_DiseaseFlyers.lua loaded")
