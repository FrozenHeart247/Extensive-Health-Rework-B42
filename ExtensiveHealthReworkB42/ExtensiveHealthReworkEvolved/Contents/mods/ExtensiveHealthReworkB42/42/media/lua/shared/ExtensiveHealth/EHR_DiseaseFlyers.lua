--[[
    Extensive Health Rework B42
    Disease Information Flyers

    Reading a flyer unlocks permanent disease identification.
    MP-safe: client sends unlock to server, server persists and syncs.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_SkillXP"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

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
        ["ExtensiveHealth.DiseaseFlyer_Gastroenteritis"] = "gastroenteritis",
        ["ExtensiveHealth.DiseaseFlyer_Dysentery"] = "dysentery",
        ["ExtensiveHealth.DiseaseFlyer_Trichinosis"] = "trichinosis",
        ["ExtensiveHealth.DiseaseFlyer_HyperkeratoticScabies"] = "hyperkeratotic_scabies",
        ["ExtensiveHealth.DiseaseFlyer_ToxinPoisoning"] = "toxin_poisoning",
        ["ExtensiveHealth.DiseaseFlyer_HeatStroke"] = "heat_stroke",
        ["ExtensiveHealth.DiseaseFlyer_CadavericAspergillosis"] = "cadaveric_aspergillosis",
        ["ExtensiveHealth.DiseaseFlyer_Tetanus"] = "tetanus",
        ["ExtensiveHealth.DiseaseFlyer_WoundInfection"] = "wound_infection",
        ["ExtensiveHealth.DiseaseFlyer_KnoxInfection"] = "knox_infection",
        ["ExtensiveHealth.DiseaseFlyer_AHTR"] = "ahtr",
        ["ExtensiveHealth.DiseaseFlyer_BloodType"] = "blood_types",
    },
    KNOWLEDGE_IDS = {
        ahtr = true,
        blood_types = true,
        common_cold = true,
        concussion = true,
        delirium = true,
        insomnia = true,
        flu = true,
        pneumonia = true,
        food_poisoning = true,
        gastroenteritis = true,
        dysentery = true,
        trichinosis = true,
        hyperkeratotic_scabies = true,
        toxin_poisoning = true,
        hypothermia = true,
        heat_exhaustion = true,
        heat_stroke = true,
        sepsis = true,
        corpse_sickness = true,
        cadaveric_aspergillosis = true,
        tuberculosis = true,
        tetanus = true,
        wound_infection = true,
        cellulitis = true,
        knox_infection = true,
    },
    SELF_EVIDENT = {
        food_poisoning = true,
        hypothermia = true,
        heat_exhaustion = true,
        heat_stroke = true,
        concussion = true,
        delirium = true,
        insomnia = true,
    },
}

local diseaseAliases = {
    AHTR = "ahtr",
    AcuteHemolyticTransfusionReaction = "ahtr",
    Acute_Hemolytic_Transfusion_Reaction = "ahtr",
    BloodType = "blood_types",
    BloodTypes = "blood_types",
    Blood_Type = "blood_types",
    Blood_Types = "blood_types",
    CommonCold = "common_cold",
    Cold = "common_cold",
    Concussion = "concussion",
    Delirium = "delirium",
    Madness = "delirium",
    Insomnia = "insomnia",
    Flu = "flu",
    Influenza = "flu",
    Pneumonia = "pneumonia",
    FoodPoisoning = "food_poisoning",
    Gastroenteritis = "gastroenteritis",
    Dysentery = "dysentery",
    Trichinosis = "trichinosis",
    HyperkeratoticScabies = "hyperkeratotic_scabies",
    Hyperkeratotic_Scabies = "hyperkeratotic_scabies",
    Scabies = "hyperkeratotic_scabies",
    ToxinPoisoning = "toxin_poisoning",
    Toxin_Poisoning = "toxin_poisoning",
    Hypothermia = "hypothermia",
    HeatExhaustion = "heat_exhaustion",
    HeatStroke = "heat_stroke",
    Sepsis = "sepsis",
    CorpseDisease = "corpse_sickness",
    CorpseSickness = "corpse_sickness",
    CorpseExposureIllness = "corpse_sickness",
    CadavericAspergillosis = "cadaveric_aspergillosis",
    Cadaveric_Aspergillosis = "cadaveric_aspergillosis",
    TuberculosisCavitary = "tuberculosis",
    TuberculosisMilliary = "tuberculosis",
    Tuberculosis = "tuberculosis",
    Tetanus = "tetanus",
    WoundInfection = "wound_infection",
    Wound_Infection = "wound_infection",
    Cellulitis = "cellulitis",
    KnoxInfection = "knox_infection",
    Knox_Infection = "knox_infection",
}

local compactDiseaseAliases = {
    ahtr = "ahtr",
    acutehemolytictransfusionreaction = "ahtr",
    bloodtype = "blood_types",
    bloodtypes = "blood_types",
    commoncold = "common_cold",
    cold = "common_cold",
    concussion = "concussion",
    delirium = "delirium",
    madness = "delirium",
    insomnia = "insomnia",
    flu = "flu",
    influenza = "flu",
    pneumonia = "pneumonia",
    foodpoisoning = "food_poisoning",
    gastroenteritis = "gastroenteritis",
    dysentery = "dysentery",
    trichinosis = "trichinosis",
    hyperkeratoticscabies = "hyperkeratotic_scabies",
    scabies = "hyperkeratotic_scabies",
    toxinpoisoning = "toxin_poisoning",
    hypothermia = "hypothermia",
    heatexhaustion = "heat_exhaustion",
    heatstroke = "heat_stroke",
    sepsis = "sepsis",
    corpsedisease = "corpse_sickness",
    corpsesickness = "corpse_sickness",
    corpseexposureillness = "corpse_sickness",
    cadavericaspergillosis = "cadaveric_aspergillosis",
    tuberculosis = "tuberculosis",
    tuberculosiscavitary = "tuberculosis",
    tuberculosismilliary = "tuberculosis",
    tetanus = "tetanus",
    woundinfection = "wound_infection",
    cellulitis = "cellulitis",
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
        ahtr = { "UI_EHR_Disease_AHTR", "AHTR" },
        blood_types = { "UI_EHR_Disease_BloodTypes", "Blood Types" },
        common_cold = { "UI_EHR_Disease_CommonCold", "Common Cold" },
        concussion = { "UI_EHR_Disease_Concussion", "Concussion" },
        delirium = { "UI_EHR_Disease_Delirium", "Delirium" },
        flu = { "UI_EHR_Disease_Influenza", "Influenza" },
        pneumonia = { "UI_EHR_Disease_Pneumonia", "Pneumonia" },
        food_poisoning = { "UI_EHR_Disease_FoodPoisoning", "Food Poisoning" },
        gastroenteritis = { "UI_EHR_Disease_Gastroenteritis", "Gastroenteritis" },
        dysentery = { "UI_EHR_Disease_Dysentery", "Dysentery" },
        trichinosis = { "UI_EHR_Disease_Trichinosis", "Trichinosis" },
        hyperkeratotic_scabies = { "UI_EHR_Disease_HyperkeratoticScabies", "Hyperkeratotic Scabies" },
        toxin_poisoning = { "UI_EHR_Disease_ToxinPoisoning", "Toxin Poisoning" },
        hypothermia = { "UI_EHR_Disease_Hypothermia", "Hypothermia" },
        heat_exhaustion = { "UI_EHR_Disease_HeatExhaustion", "Heat Exhaustion" },
        heat_stroke = { "UI_EHR_Disease_HeatStroke", "Heat Stroke" },
        sepsis = { "UI_EHR_Disease_Sepsis", "Sepsis" },
        corpse_sickness = { "UI_EHR_Disease_CorpseSickness", "Corpse Exposure Illness" },
        cadaveric_aspergillosis = { "UI_EHR_Disease_CadavericAspergillosis", "Cadaveric Aspergillosis" },
        tuberculosis = { "UI_EHR_Disease_Tuberculosis", "Tuberculosis" },
        tetanus = { "UI_EHR_Disease_Tetanus", "Tetanus" },
        wound_infection = { "UI_EHR_Disease_WoundInfection", "Wound Infection" },
        cellulitis = { "UI_EHR_Disease_Cellulitis", "Cellulitis" },
        knox_infection = { "UI_EHR_Disease_KnoxInfection", "Knox Infection" },
    }
    local entry = names[diseaseId]
    if type(entry) == "table" then
        return EHR.Locale.Text(entry[1], entry[2])
    end
    return diseaseId
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
        EHR.Locale.Say(player, flyerText("UI_EHR_FlyerLearned", "Disease knowledge acquired: %1", name))
    end

    EHR.Log("Player learned disease: " .. tostring(diseaseId))
    return true
end

function EHR.DiseaseFlyers.GetFirstAidLevel(player)
    if player and Perks and Perks.Doctor and player.getPerkLevel then
        local ok, level = pcall(function()
            return player:getPerkLevel(Perks.Doctor)
        end)
        if ok then
            return tonumber(level) or 0
        end
    end
    return 0
end

function EHR.DiseaseFlyers.HasMedicalKnowledge(player, knowledgeId, requiredFirstAidLevel)
    if not player or not knowledgeId then return false end

    local normalized = normalizeDiseaseId(knowledgeId)
    if EHR.DiseaseFlyers.KnowsDisease(player, normalized) then
        return true
    end

    local requiredLevel = requiredFirstAidLevel or 8
    return EHR.DiseaseFlyers.GetFirstAidLevel(player) >= requiredLevel
end

function EHR.DiseaseFlyers.CanIdentifyDisease(player, diseaseId)
    if not player or not diseaseId then return false end

    local normalized = normalizeDiseaseId(diseaseId)
    if not EHR.DiseaseFlyers.Config.KNOWLEDGE_IDS[normalized] then
        return true
    end

    if EHR.DiseaseFlyers.HasMedicalKnowledge(player, normalized, 8) then
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
        ahtr = { displayName = "Unknown Transfusion Reaction", description = "Your lower back aches after the transfusion and your body feels dangerously wrong." },
        common_cold = { displayName = "Unknown Respiratory Illness", description = "You feel unwell with respiratory symptoms." },
        concussion = { displayName = "Head Trauma", description = "Your head pounds after the impact and your vision will not stay steady." },
        delirium = { displayName = "Mental Breakdown", description = "Your thoughts feel broken and the world keeps changing around you." },
        flu = { displayName = "Unknown Respiratory Illness", description = "You feel very unwell with fever and body aches." },
        pneumonia = { displayName = "Severe Respiratory Illness", description = "Your lungs feel inflamed. This seems serious." },
        gastroenteritis = { displayName = "Unknown Gastrointestinal Illness", description = "Your stomach and gut feel badly disturbed." },
        dysentery = { displayName = "Severe Gastrointestinal Illness", description = "You feel dehydrated and violently ill." },
        trichinosis = { displayName = "Unknown Parasitic Illness", description = "Your muscles ache and something feels deeply wrong." },
        hyperkeratotic_scabies = { displayName = "Unknown Skin Infestation", description = "Your skin itches painfully and the scratches keep spreading." },
        toxin_poisoning = { displayName = "Unknown Toxic Reaction", description = "You feel poisoned and dangerously unwell." },
        sepsis = { displayName = "Systemic Illness", description = "Your whole body feels wrong. This is very serious." },
        corpse_sickness = { displayName = "Unknown Illness", description = "You feel nauseous and unwell." },
        cadaveric_aspergillosis = { displayName = "Unknown Respiratory Illness", description = "Your breathing feels irritated and feverish." },
        tuberculosis = { displayName = "Chronic Respiratory Illness", description = "A persistent illness affecting your lungs." },
        tetanus = { displayName = "Severe Neuromuscular Illness", description = "Your muscles feel tight and painful." },
        wound_infection = { displayName = "Unknown Wound Illness", description = "An injury looks and feels unhealthy." },
        cellulitis = { displayName = "Unknown Skin Infection", description = "Your skin feels inflamed and infected." },
        knox_infection = { displayName = "Unknown Infection", description = "Something is very wrong after the injury." },
    }

    local unknownName = getText and getText("UI_EHR_DiseaseUnknown") or nil
    if unknownName == "UI_EHR_DiseaseUnknown" then
        unknownName = nil
    end
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
            EHR.Locale.Say(player, flyerText("UI_EHR_FlyerAlreadyKnown", "You already know about this disease."))
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
        EHR.Locale.Say(player, flyerText("UI_EHR_FlyerAlreadyKnown", "You already know about this disease."))
    end
end

-- NOTE: The actual hook into ISReadABook:complete() is in the client-side file
-- EHR_FlyerHook.lua because ISReadABook is a client-only timed action class.
-- This shared file only contains the data functions used by both client and server.

EHR.Log("EHR_DiseaseFlyers.lua loaded")
