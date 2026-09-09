--[[
    Extensive Health Rework B42
    Custom professions and profession traits.

    B42 uses script-defined CharacterProfession/CharacterTrait objects; this file
    only handles runtime effects that script definitions cannot express.
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.Professions = EHR.Professions or {}

local EHR_MEDICAL_PROFESSIONS = {
    ehrdoctor = true,
    ehrsurgeon = true,
}

local SCALPEL_FULL_TYPE = "Base.Scalpel"
local SCALPEL_CONDITION_MULTIPLIER = 100
local SCALPEL_DAMAGE_MULTIPLIER = 9
local INVENTORY_RESTORE_SCAN_TICKS = 120

local playerTickState = {}
local scalpelScriptTagsPatched = false

local function safeCall(obj, methodName, ...)
    if not obj then return false, nil end
    local method = obj[methodName]
    if type(method) ~= "function" then return false, nil end
    return pcall(method, obj, ...)
end

local function safeNumber(obj, methodName, fallback)
    local ok, value = safeCall(obj, methodName)
    if not ok then return fallback end
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function getPlayerKey(player)
    if not player then return "unknown" end

    local ok, username = safeCall(player, "getUsername")
    if ok and username then return tostring(username) end

    ok, username = safeCall(player, "getOnlineID")
    if ok and username then return tostring(username) end

    return tostring(player)
end

local function getItemKey(item)
    if not item then return "nil" end

    local ok, id = safeCall(item, "getID")
    if ok and id ~= nil then return tostring(id) end

    return tostring(item)
end

local function getModData(item)
    local ok, data = safeCall(item, "getModData")
    if ok and data then return data end
    return nil
end

local function hasCharacterTrait(player, registryKey)
    if not player or not registryKey then return false end

    local traitToken = EHRCharacterTraits and EHRCharacterTraits[registryKey]
    if traitToken and type(traitToken) ~= "string" then
        local ok, result = safeCall(player, "hasTrait", traitToken)
        if ok and result == true then return true end

        local traitsOk, traits = safeCall(player, "getCharacterTraits")
        if traitsOk and traits then
            local containsOk, contains = safeCall(traits, "contains", traitToken)
            if containsOk and contains == true then return true end
        end
    end

    return false
end

local function isPatientZeroTraitEnabled()
    if EHR.KnoxCure and EHR.KnoxCure.IsPatientZeroTraitEnabled then
        return EHR.KnoxCure.IsPatientZeroTraitEnabled()
    end
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.PatientZeroTraitDisabled ~= nil then
        return options.PatientZeroTraitDisabled ~= true
    end
    return true
end
local function isEHRMedicalProfession(player)
    if not player then return false, nil end

    local ok, desc = safeCall(player, "getDescriptor")
    if not ok or not desc then return false, nil end

    for professionKey, _ in pairs(EHR_MEDICAL_PROFESSIONS) do
        local token = EHRCharacterProfessions and EHRCharacterProfessions[professionKey]
        if token then
            local profOk, hasProfession = safeCall(desc, "isCharacterProfession", token)
            if profOk and hasProfession == true then
                return true, professionKey
            end
        end
    end

    local profOk, profession = safeCall(desc, "getCharacterProfession")
    if not profOk or not profession then return false, nil end

    local name = nil
    local nameOk, rawName = safeCall(profession, "getName")
    if nameOk and rawName then
        name = tostring(rawName)
    else
        name = tostring(profession)
    end

    name = name:lower()
    if name == "ehrdoctor" or name == "extensivehealth:ehrdoctor" then
        return true, "ehrdoctor"
    end
    if name == "ehrsurgeon" or name == "extensivehealth:ehrsurgeon" then
        return true, "ehrsurgeon"
    end

    return false, nil
end

local fallbackDiseaseKnowledgeIds = {
    ahtr = true,
    blood_types = true,
    common_cold = true,
    concussion = true,
    delirium = true,
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
}

-- Keep this list in step with EHR_Recipes.txt, EHR_SupplyRecipes.txt and GrantedRecipes in the two
-- profession definitions. Runtime learning also covers characters in old saves;
-- it only grants knowledge, leaving recipe skills, ingredients and tests intact.
local medicalCraftRecipes = {
    "MakePlantBasedAntibiotics",
    "MakeHomemadeActivatedCharcoal",
    "MakeHomemadeAntisepticCream",
    "MakeHomemadeAntibioticOintment",
    "MakeHomemadeTopicalPermethrin",
    "MakeHomemadeCoughSyrup",
    "MakeHomemadeMuscleRelaxant",
    "MakeHomemadePainkillers",
    "MakeHomemadeSleepingPills",
    "MakeCommonColdTea",
    "MakeAntipyreticTea",
    "MakeRelaxantTea",
    "MakeSpiderwebBandage",
    "MakeHoneyFromHoneycomb",
    "MakeSutureNeedleFromSpiderweb",
    "PrepareTallowMixture",
    "StrainRenderedTallow",
    "MakeHomemadeSyringes",
    "CutPlasticStripsSmall",
    "CutPlasticStripsBottle",
    "CutPlasticStripsLarge",
    "CutPlasticStripsHeavy",
    "PrepareHomemadeBloodBag",
    "MakeHomemadeIVKit",
}

function EHR.Professions.GrantAllCraftRecipeKnowledge(player)
    if not isEHRMedicalProfession(player) then return false end
    if isClient and isClient() and not (isServer and isServer()) then
        local ok, localPlayer = safeCall(player, "isLocalPlayer")
        if not ok or localPlayer ~= true then return false end
    end

    local changed = false
    for _, recipeName in ipairs(medicalCraftRecipes) do
        local ok, learned = safeCall(player, "learnRecipe", recipeName)
        if ok and learned == true then changed = true end
    end
    return changed
end

function EHR.Professions.GrantAllDiseaseKnowledge(player)
    local isMedicalProfession, professionKey = isEHRMedicalProfession(player)
    if not isMedicalProfession then return false end

    local modData = player:getModData()
    if not modData then return false end
    if modData.EHR_ProfessionDiseaseKnowledge == professionKey then return false end

    local now = 0
    if getGameTime then
        local gameTime = getGameTime()
        if gameTime and gameTime.getWorldAgeHours then
            now = gameTime:getWorldAgeHours()
        end
    end

    modData.EHR_KnownDiseases = modData.EHR_KnownDiseases or {}
    modData.EHR_MedicalJournal = modData.EHR_MedicalJournal or { entries = {}, discoveries = {} }
    modData.EHR_MedicalJournal.discoveries = modData.EHR_MedicalJournal.discoveries or {}

    local knowledgeIds = fallbackDiseaseKnowledgeIds
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.Config and EHR.DiseaseFlyers.Config.KNOWLEDGE_IDS then
        knowledgeIds = EHR.DiseaseFlyers.Config.KNOWLEDGE_IDS
    end

    for diseaseId, _ in pairs(knowledgeIds) do
        local isKnox = EHR.DiseaseFlyers
            and EHR.DiseaseFlyers.IsKnoxDiseaseId
            and EHR.DiseaseFlyers.IsKnoxDiseaseId(diseaseId)
        if not isKnox then
            modData.EHR_KnownDiseases[diseaseId] = true
            modData.EHR_MedicalJournal.discoveries[diseaseId] = modData.EHR_MedicalJournal.discoveries[diseaseId] or now
        end
    end

    modData.EHR_MedicalJournal.lastUpdated = now
    modData.EHR_ProfessionDiseaseKnowledge = professionKey

    if EHR and EHR.SafeTransmitModData then
        EHR.SafeTransmitModData(player)
    end

    if EHR.Log then
        EHR.Log("Profession disease knowledge granted: " .. tostring(professionKey))
    end

    return true
end

local function getKnoxData(player)
    if not player then return nil end

    if EHR.KnoxCure and EHR.KnoxCure.GetData then
        local ok, data = pcall(EHR.KnoxCure.GetData, player)
        if ok and data then return data end
    end

    local modData = player:getModData()
    if not modData then return nil end
    modData.EHR_KnoxCure = modData.EHR_KnoxCure or {}
    return modData.EHR_KnoxCure
end

function EHR.Professions.ApplyPatientZeroTrait(player)
    if not player then return false end

    local hasPatientZero = hasCharacterTrait(player, "patientzero")
    local data = getKnoxData(player)
    if not data then return false end

    if not isPatientZeroTraitEnabled() then
        if data.patientZeroTraitSource == true then
            data.geneTherapyImmune = false
            data.immunityTraitGranted = false
            data.patientZeroTraitSource = false
            if EHR and EHR.SafeTransmitModData then
                EHR.SafeTransmitModData(player)
            end
        end
        return false
    end

    if hasPatientZero then
        if data.geneTherapyImmune ~= true or data.patientZeroTraitSource ~= true then
            data.geneTherapyImmune = true
            data.immunityTraitGranted = true
            data.patientZeroTraitSource = true
            if EHR and EHR.SafeTransmitModData then
                EHR.SafeTransmitModData(player)
            end
            if EHR.Log then EHR.Log("Patient Zero trait activated Knox immunity") end
        end
        return true
    end

    if data.patientZeroTraitSource and not data.geneTherapySurvivor then
        data.geneTherapyImmune = false
        data.immunityTraitGranted = false
        data.patientZeroTraitSource = false
        if EHR and EHR.SafeTransmitModData then
            EHR.SafeTransmitModData(player)
        end
    end

    return false
end

local function isScalpel(item)
    if not item then return false end

    local ok, fullType = safeCall(item, "getFullType")
    if ok and tostring(fullType) == SCALPEL_FULL_TYPE then return true end

    ok, fullType = safeCall(item, "getType")
    return ok and tostring(fullType) == "Scalpel"
end

local function getNoMaintenanceXpTag()
    if ItemTag and ItemTag.NO_MAINTENANCE_XP then
        return ItemTag.NO_MAINTENANCE_XP
    end
    if ItemTag and ItemTag.get and ResourceLocation and ResourceLocation.of then
        local ok, tag = pcall(function()
            return ItemTag.get(ResourceLocation.of("base:nomaintenancexp"))
        end)
        if ok then return tag end
    end
    return nil
end

local function removeTagFromSet(tags, tag)
    if not tags or not tag then return false end

    local changed = false
    local ok, contains = safeCall(tags, "contains", tag)
    if ok and contains == true then
        local removeOk = safeCall(tags, "remove", tag)
        changed = removeOk == true
    else
        local removeOk, removed = safeCall(tags, "remove", tag)
        changed = removeOk == true and removed == true
    end

    return changed
end

local function stripNoMaintenanceXpTag(obj)
    local tag = getNoMaintenanceXpTag()
    if not tag or not obj then return false end

    local ok, tags = safeCall(obj, "getTags")
    if not ok or not tags then return false end

    return removeTagFromSet(tags, tag)
end

function EHR.Professions.PatchScalpelScriptTags()
    if scalpelScriptTagsPatched then return false end

    local scriptItem = nil
    if getScriptManager then
        local manager = getScriptManager()
        if manager then
            local ok, item = safeCall(manager, "FindItem", SCALPEL_FULL_TYPE)
            if ok and item then
                scriptItem = item
            end
        end
    end
    if not scriptItem and ScriptManager and ScriptManager.instance then
        local ok, item = safeCall(ScriptManager.instance, "getItem", SCALPEL_FULL_TYPE)
        if ok and item then
            scriptItem = item
        end
    end

    if not scriptItem then return false end

    scalpelScriptTagsPatched = stripNoMaintenanceXpTag(scriptItem)
    return scalpelScriptTagsPatched
end

function EHR.Professions.EnableScalpelMaintenanceXp(item)
    if not isScalpel(item) then return false end

    EHR.Professions.PatchScalpelScriptTags()

    local changed = stripNoMaintenanceXpTag(item)
    local ok, scriptItem = safeCall(item, "getScriptItem")
    if ok and scriptItem then
        changed = stripNoMaintenanceXpTag(scriptItem) or changed
    end

    return changed
end

local function boostScalpel(item)
    if not isScalpel(item) then return false end
    EHR.Professions.EnableScalpelMaintenanceXp(item)

    local modData = getModData(item)
    if not modData then return false end
    if modData.EHR_ScalpelMasterBoosted then
        local original = modData.EHR_ScalpelMaster or {}
        local originalMinDamage = tonumber(original.minDamage)
        local originalMaxDamage = tonumber(original.maxDamage)
        if modData.EHR_ScalpelMasterDamageMultiplier ~= SCALPEL_DAMAGE_MULTIPLIER
            and originalMinDamage
            and originalMaxDamage then
            safeCall(item, "setMinDamage", originalMinDamage * SCALPEL_DAMAGE_MULTIPLIER)
            safeCall(item, "setMaxDamage", originalMaxDamage * SCALPEL_DAMAGE_MULTIPLIER)
            modData.EHR_ScalpelMasterDamageMultiplier = SCALPEL_DAMAGE_MULTIPLIER
        end
        return true
    end

    local conditionMax = safeNumber(item, "getConditionMax", 0)
    local condition = safeNumber(item, "getCondition", conditionMax)
    local minDamage = safeNumber(item, "getMinDamage", nil)
    local maxDamage = safeNumber(item, "getMaxDamage", nil)
    if conditionMax <= 0 or minDamage == nil or maxDamage == nil then return false end

    local boostedConditionMax = math.max(1, math.floor(conditionMax * SCALPEL_CONDITION_MULTIPLIER + 0.5))
    local ratio = 1
    if conditionMax > 0 then
        ratio = math.max(0, math.min(1, condition / conditionMax))
    end

    modData.EHR_ScalpelMaster = {
        conditionMax = conditionMax,
        condition = condition,
        minDamage = minDamage,
        maxDamage = maxDamage,
    }
    modData.EHR_ScalpelMasterBoosted = true
    modData.EHR_ScalpelMasterDamageMultiplier = SCALPEL_DAMAGE_MULTIPLIER

    safeCall(item, "setConditionMax", boostedConditionMax)
    safeCall(item, "setCondition", math.max(0, math.floor(boostedConditionMax * ratio + 0.5)))
    safeCall(item, "setMinDamage", minDamage * SCALPEL_DAMAGE_MULTIPLIER)
    safeCall(item, "setMaxDamage", maxDamage * SCALPEL_DAMAGE_MULTIPLIER)

    return true
end

local function restoreScalpel(item)
    if not item then return false end

    local modData = getModData(item)
    if not modData or not modData.EHR_ScalpelMasterBoosted then return false end

    local original = modData.EHR_ScalpelMaster or {}
    local originalConditionMax = tonumber(original.conditionMax)
    local originalMinDamage = tonumber(original.minDamage)
    local originalMaxDamage = tonumber(original.maxDamage)

    if originalConditionMax and originalConditionMax > 0 then
        local currentMax = safeNumber(item, "getConditionMax", originalConditionMax)
        local currentCondition = safeNumber(item, "getCondition", currentMax)
        local ratio = 1
        if currentMax > 0 then
            ratio = math.max(0, math.min(1, currentCondition / currentMax))
        end

        safeCall(item, "setConditionMax", originalConditionMax)
        safeCall(item, "setCondition", math.max(0, math.floor(originalConditionMax * ratio + 0.5)))
    end

    if originalMinDamage then
        safeCall(item, "setMinDamage", originalMinDamage)
    end
    if originalMaxDamage then
        safeCall(item, "setMaxDamage", originalMaxDamage)
    end

    modData.EHR_ScalpelMaster = nil
    modData.EHR_ScalpelMasterBoosted = nil
    modData.EHR_ScalpelMasterDamageMultiplier = nil

    return true
end

local function scanContainer(container, callback, depth)
    if not container or not callback then return end
    depth = depth or 0
    if depth > 2 then return end

    local ok, items = safeCall(container, "getItems")
    if not ok or not items then return end

    local sizeOk, size = pcall(function() return items:size() end)
    if not sizeOk or not size then return end

    for i = 0, size - 1 do
        local item = items:get(i)
        if item then
            callback(item)

            local invOk, nested = safeCall(item, "getInventory")
            if invOk and nested and nested ~= container then
                scanContainer(nested, callback, depth + 1)
            end
        end
    end
end

function EHR.Professions.UpdateScalpelMaster(player, scanInventory)
    if not player then return end

    local hasScalpelMaster = hasCharacterTrait(player, "scalpelmaster")
    local heldItems = {}

    local ok, primary = safeCall(player, "getPrimaryHandItem")
    if ok and primary then
        heldItems[getItemKey(primary)] = true
        EHR.Professions.EnableScalpelMaintenanceXp(primary)
        if hasScalpelMaster then
            boostScalpel(primary)
        else
            restoreScalpel(primary)
        end
    end

    ok, secondary = safeCall(player, "getSecondaryHandItem")
    if ok and secondary then
        heldItems[getItemKey(secondary)] = true
        EHR.Professions.EnableScalpelMaintenanceXp(secondary)
        if hasScalpelMaster then
            boostScalpel(secondary)
        else
            restoreScalpel(secondary)
        end
    end

    if not scanInventory then return end

    local invOk, inventory = safeCall(player, "getInventory")
    if not invOk or not inventory then return end

    scanContainer(inventory, function(item)
        if not isScalpel(item) then return end

        EHR.Professions.EnableScalpelMaintenanceXp(item)
        local itemKey = getItemKey(item)
        if not hasScalpelMaster or not heldItems[itemKey] then
            restoreScalpel(item)
        end
    end)
end

function EHR.Professions.OnCreatePlayer(playerIndex, player)
    if player then playerTickState[getPlayerKey(player)] = nil end
    EHR.Professions.PatchScalpelScriptTags()
    EHR.Professions.GrantAllDiseaseKnowledge(player)
    EHR.Professions.GrantAllCraftRecipeKnowledge(player)
    EHR.Professions.ApplyPatientZeroTrait(player)
    EHR.Professions.UpdateScalpelMaster(player, true)
end

function EHR.Professions.OnPlayerUpdate(player)
    if not player then return end

    local key = getPlayerKey(player)
    local state = playerTickState[key]
    if not state or state.player ~= player then
        state = { ticks = 0, player = player }
    end
    playerTickState[key] = state
    state.ticks = state.ticks + 1

    -- One check per player instance also covers dedicated-server players, where
    -- OnCreatePlayer is not the local character-creation event.
    if not state.recipeKnowledgeChecked then
        EHR.Professions.GrantAllCraftRecipeKnowledge(player)
        state.recipeKnowledgeChecked = true
    end

    EHR.Professions.ApplyPatientZeroTrait(player)

    local scanInventory = (state.ticks % INVENTORY_RESTORE_SCAN_TICKS) == 0
    EHR.Professions.UpdateScalpelMaster(player, scanInventory)
end

if Events then
    if Events.OnGameStart then
        Events.OnGameStart.Add(EHR.Professions.PatchScalpelScriptTags)
    end
    if Events.OnCreatePlayer then
        Events.OnCreatePlayer.Add(EHR.Professions.OnCreatePlayer)
    end
    if Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Add(EHR.Professions.OnPlayerUpdate)
    end
end

EHR.Professions.PatchScalpelScriptTags()

if EHR.Log then
    EHR.Log("EHR_Professions.lua loaded")
end
