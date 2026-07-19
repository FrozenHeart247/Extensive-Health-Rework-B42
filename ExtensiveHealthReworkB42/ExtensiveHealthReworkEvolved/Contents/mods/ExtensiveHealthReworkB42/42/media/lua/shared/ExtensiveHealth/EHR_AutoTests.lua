--[[
    Extensive Health Rework B42
    Read-only runtime validation for disease, medication, and immunity registries.
]]

EHR = EHR or {}
EHR.AutoTests = EHR.AutoTests or {}

local AutoTests = EHR.AutoTests

AutoTests.VERSION = 3

local KNOWN_MODULE_DISEASES = {
    ahtr = true,
    cellulitis = true,
    influenza = true,
    sepsis = true,
    wound_infection = true,
}

local STATUS_PRIORITY = {
    FAIL = 1,
    WARN = 2,
    PASS = 3,
}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function approxEqual(left, right, tolerance)
    return math.abs((tonumber(left) or 0) - (tonumber(right) or 0)) <= (tolerance or 0.0001)
end

local function startsWith(value, prefix)
    value = tostring(value or "")
    prefix = tostring(prefix or "")
    return string.sub(value, 1, string.len(prefix)) == prefix
end

local function join(values, separator)
    local parts = {}
    for _, value in ipairs(values or {}) do
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, separator or "; ")
end

local function sortedKeys(source)
    local keys = {}
    for key in pairs(source or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function countEntries(source)
    local count = 0
    for _ in pairs(source or {}) do
        count = count + 1
    end
    return count
end

local function cloneValue(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, entry in pairs(value) do
        copy[cloneValue(key, seen)] = cloneValue(entry, seen)
    end
    return copy
end

local function readMethod(target, methodName)
    if not target then return false, nil end
    local found = false
    local ok, value = pcall(function()
        local method = target[methodName]
        if not method then return nil end
        found = true
        return method(target)
    end)
    return ok and found, value
end

local function writeMethod(target, methodName, value)
    if not target then return false end
    local found = false
    local ok = pcall(function()
        local method = target[methodName]
        if not method then return end
        found = true
        method(target, value)
    end)
    return ok and found
end

local function writeMethodIfChanged(target, getterName, setterName, value)
    local hasCurrent, current = readMethod(target, getterName)
    if hasCurrent then
        if type(value) == "number" and type(current) == "number" then
            if approxEqual(current, value) then return true end
        elseif current == value then
            return true
        end
    end
    return writeMethod(target, setterName, value)
end

local LIVE_STAT_NAMES = {
    "BOREDOM",
    "DISCOMFORT",
    "ENDURANCE",
    "FATIGUE",
    "FOOD_SICKNESS",
    "HUNGER",
    "PAIN",
    "PANIC",
    "POISON",
    "SICKNESS",
    "STRESS",
    "THIRST",
    "UNHAPPINESS",
}

local function capturePlayerSnapshot(player)
    local snapshot = {
        ehrModData = {},
        stats = {},
        bodyParts = {},
    }

    local modData = player and player.getModData and player:getModData() or nil
    if modData then
        for key, value in pairs(modData) do
            if type(key) == "string" and string.sub(string.upper(key), 1, 3) == "EHR" then
                snapshot.ehrModData[key] = cloneValue(value)
            end
        end
    end

    local stats = player and player.getStats and player:getStats() or nil
    if stats and CharacterStat then
        for _, statName in ipairs(LIVE_STAT_NAMES) do
            local stat = CharacterStat[statName]
            if stat then
                local ok, value = pcall(function() return stats:get(stat) end)
                if ok and value ~= nil then snapshot.stats[statName] = value end
            end
        end
    end

    local okLegacySickness, legacySickness = readMethod(stats, "getSickness")
    if okLegacySickness then snapshot.legacySickness = legacySickness end

    local okPlayerHealth, playerHealth = readMethod(player, "getHealth")
    if okPlayerHealth then snapshot.playerHealth = playerHealth end
    local okTemperature, temperature = readMethod(player, "getTemperature")
    if okTemperature then snapshot.temperature = temperature end

    local bodyDamage = player and player.getBodyDamage and player:getBodyDamage() or nil
    local okOverallHealth, overallHealth = readMethod(bodyDamage, "getOverallBodyHealth")
    if okOverallHealth then snapshot.overallHealth = overallHealth end
    local okColdStrength, coldStrength = readMethod(bodyDamage, "getColdStrength")
    if okColdStrength then snapshot.coldStrength = coldStrength end

    if bodyDamage and BodyPartType and BodyPartType.ToIndex and BodyPartType.FromIndex and BodyPartType.MAX then
        local maxParts = BodyPartType.ToIndex(BodyPartType.MAX)
        for index = 0, maxParts - 1 do
            local part = bodyDamage:getBodyPart(BodyPartType.FromIndex(index))
            if part then
                local partSnapshot = {}
                local okHealth, health = readMethod(part, "getHealth")
                local okPain, pain = readMethod(part, "getAdditionalPain")
                local okStiffness, stiffness = readMethod(part, "getStiffness")
                local okInfection, infection = readMethod(part, "getWoundInfectionLevel")
                local okInfected, infected = readMethod(part, "isInfectedWound")
                local okScratchTime, scratchTime = readMethod(part, "getScratchTime")
                local okCutTime, cutTime = readMethod(part, "getCutTime")
                local okDeepWoundTime, deepWoundTime = readMethod(part, "getDeepWoundTime")
                local okBleedingTime, bleedingTime = readMethod(part, "getBleedingTime")
                local okBurnTime, burnTime = readMethod(part, "getBurnTime")
                local okFractureTime, fractureTime = readMethod(part, "getFractureTime")
                local okCut, cut = readMethod(part, "isCut")
                local okDeepWounded, deepWounded = readMethod(part, "isDeepWounded")
                local okGlass, glass = readMethod(part, "haveGlass")
                local okBitten, bitten = readMethod(part, "bitten")
                local okStitched, stitched = readMethod(part, "stitched")
                if okHealth then partSnapshot.health = health end
                if okPain then partSnapshot.additionalPain = pain end
                if okStiffness then partSnapshot.stiffness = stiffness end
                if okInfection then partSnapshot.infectionLevel = infection end
                if okInfected then partSnapshot.infectedWound = infected end
                if okScratchTime then partSnapshot.scratchTime = scratchTime end
                if okCutTime then partSnapshot.cutTime = cutTime end
                if okDeepWoundTime then partSnapshot.deepWoundTime = deepWoundTime end
                if okBleedingTime then partSnapshot.bleedingTime = bleedingTime end
                if okBurnTime then partSnapshot.burnTime = burnTime end
                if okFractureTime then partSnapshot.fractureTime = fractureTime end
                if okCut then partSnapshot.cut = cut end
                if okDeepWounded then partSnapshot.deepWounded = deepWounded end
                if okGlass then partSnapshot.haveGlass = glass end
                if okBitten then partSnapshot.bitten = bitten end
                if okStitched then partSnapshot.stitched = stitched end
                snapshot.bodyParts[index] = partSnapshot
            end
        end
    end

    return snapshot
end

local function restorePlayerSnapshot(player, snapshot)
    local failures = {}
    if not player or type(snapshot) ~= "table" then
        return false, { "snapshot or player missing" }
    end

    local modData = player.getModData and player:getModData() or nil
    if modData then
        local removeKeys = {}
        for key in pairs(modData) do
            if type(key) == "string" and string.sub(string.upper(key), 1, 3) == "EHR" then
                removeKeys[#removeKeys + 1] = key
            end
        end
        for _, key in ipairs(removeKeys) do modData[key] = nil end
        for key, value in pairs(snapshot.ehrModData or {}) do
            modData[key] = cloneValue(value)
        end
    else
        failures[#failures + 1] = "modData unavailable"
    end

    local stats = player.getStats and player:getStats() or nil
    if stats and CharacterStat then
        for statName, value in pairs(snapshot.stats or {}) do
            local stat = CharacterStat[statName]
            if stat then
                local ok = pcall(function() stats:set(stat, value) end)
                if not ok then failures[#failures + 1] = "stat " .. statName end
            end
        end
    end

    if snapshot.legacySickness ~= nil and not writeMethod(stats, "setSickness", snapshot.legacySickness) then
        failures[#failures + 1] = "legacy sickness"
    end
    if snapshot.temperature ~= nil and not writeMethod(player, "setTemperature", snapshot.temperature) then
        failures[#failures + 1] = "temperature"
    end

    local bodyDamage = player.getBodyDamage and player:getBodyDamage() or nil
    if snapshot.coldStrength ~= nil and not writeMethod(bodyDamage, "setColdStrength", snapshot.coldStrength) then
        failures[#failures + 1] = "cold strength"
    end

    if bodyDamage and BodyPartType and BodyPartType.FromIndex then
        for index, partSnapshot in pairs(snapshot.bodyParts or {}) do
            local part = bodyDamage:getBodyPart(BodyPartType.FromIndex(index))
            if part then
                if partSnapshot.scratchTime ~= nil then
                    local hasScratchTime, currentScratchTime = readMethod(part, "getScratchTime")
                    if not hasScratchTime or not approxEqual(currentScratchTime, partSnapshot.scratchTime) then
                        pcall(function()
                            if part.setScratched then
                                part:setScratched((tonumber(partSnapshot.scratchTime) or 0) > 0, false)
                            elseif part.SetScratched then
                                part:SetScratched((tonumber(partSnapshot.scratchTime) or 0) > 0, false)
                            end
                        end)
                        writeMethod(part, "setScratchTime", partSnapshot.scratchTime)
                    end
                end
                if partSnapshot.cut ~= nil then
                    writeMethodIfChanged(part, "isCut", "setCut", partSnapshot.cut)
                end
                if partSnapshot.cutTime ~= nil then
                    writeMethodIfChanged(part, "getCutTime", "setCutTime", partSnapshot.cutTime)
                end
                if partSnapshot.deepWounded ~= nil then
                    writeMethodIfChanged(part, "isDeepWounded", "setDeepWounded", partSnapshot.deepWounded)
                end
                if partSnapshot.deepWoundTime ~= nil then
                    writeMethodIfChanged(part, "getDeepWoundTime", "setDeepWoundTime", partSnapshot.deepWoundTime)
                end
                if partSnapshot.bleedingTime ~= nil then
                    writeMethodIfChanged(part, "getBleedingTime", "setBleedingTime", partSnapshot.bleedingTime)
                end
                if partSnapshot.burnTime ~= nil then
                    writeMethodIfChanged(part, "getBurnTime", "setBurnTime", partSnapshot.burnTime)
                end
                if partSnapshot.fractureTime ~= nil then
                    writeMethodIfChanged(part, "getFractureTime", "setFractureTime", partSnapshot.fractureTime)
                end
                if partSnapshot.haveGlass ~= nil then
                    writeMethodIfChanged(part, "haveGlass", "setHaveGlass", partSnapshot.haveGlass)
                end
                if partSnapshot.bitten ~= nil then
                    writeMethodIfChanged(part, "bitten", "SetBitten", partSnapshot.bitten)
                end
                if partSnapshot.stitched ~= nil then
                    writeMethodIfChanged(part, "stitched", "setStitched", partSnapshot.stitched)
                end
                if partSnapshot.health ~= nil then writeMethod(part, "setHealth", partSnapshot.health) end
                if partSnapshot.additionalPain ~= nil then
                    writeMethod(part, "setAdditionalPain", partSnapshot.additionalPain)
                end
                if partSnapshot.stiffness ~= nil then writeMethod(part, "setStiffness", partSnapshot.stiffness) end
                if partSnapshot.infectionLevel ~= nil then
                    writeMethod(part, "setWoundInfectionLevel", partSnapshot.infectionLevel)
                end
                if partSnapshot.infectedWound ~= nil then
                    writeMethod(part, "setInfectedWound", partSnapshot.infectedWound)
                end
            end
        end
    end

    if snapshot.overallHealth ~= nil
            and not writeMethod(bodyDamage, "setOverallBodyHealth", snapshot.overallHealth) then
        failures[#failures + 1] = "overall health"
    end
    if snapshot.playerHealth ~= nil and not writeMethod(player, "setHealth", snapshot.playerHealth) then
        failures[#failures + 1] = "player health"
    end

    return #failures == 0, failures
end

local function addResult(report, category, name, status, detail)
    status = STATUS_PRIORITY[status] and status or "FAIL"
    local result = {
        category = category,
        name = name,
        status = status,
        detail = detail,
        passed = status ~= "FAIL",
    }
    report.results[#report.results + 1] = result
    report.counts[status] = (report.counts[status] or 0) + 1
    report.total = report.total + 1
    return result
end

local function addValidationResult(report, category, name, errors, warnings, successDetail)
    if #errors > 0 then
        return addResult(report, category, name, "FAIL", join(errors))
    end
    if #warnings > 0 then
        return addResult(report, category, name, "WARN", join(warnings))
    end
    return addResult(report, category, name, "PASS", successDetail)
end

local function knownDisease(diseases, diseaseId)
    if type(diseaseId) ~= "string" or diseaseId == "" then return false end
    if diseases[diseaseId] then return true end
    if diseaseId == "knox_infection" and diseases.Knox_Infection then return true end
    if diseaseId == "Knox_Infection" and diseases.knox_infection then return true end
    return KNOWN_MODULE_DISEASES[diseaseId] == true
end

local function validateMinMax(errors, label, minimum, maximum, required)
    local minNumber = tonumber(minimum)
    local maxNumber = tonumber(maximum)
    if minNumber == nil or maxNumber == nil then
        if required then
            errors[#errors + 1] = label .. " min/max missing"
        end
        return
    end
    if minNumber < 0 or maxNumber < 0 then
        errors[#errors + 1] = label .. " cannot be negative"
    elseif minNumber > maxNumber then
        errors[#errors + 1] = label .. " min exceeds max"
    end
end

local function getScriptItem(fullType)
    if not ScriptManager or not ScriptManager.instance or not ScriptManager.instance.getItem then
        return nil, "ScriptManager unavailable"
    end

    local ok, item = pcall(function()
        return ScriptManager.instance:getItem(fullType)
    end)
    if not ok then
        return nil, tostring(item)
    end
    return item, nil
end

local function validateDiseaseIcon(diseaseId, warnings, errors)
    local panelClass = rawget(_G, "EHR_HealthPanelUI")
    local iconPaths = panelClass and panelClass.DiseaseIconPaths
    if type(iconPaths) ~= "table" then return end

    local iconKey = string.lower(tostring(diseaseId))
    local path = iconPaths[iconKey]
    if not path then
        warnings[#warnings + 1] = "health-panel icon mapping missing"
        return
    end

    if getTexture then
        local ok, texture = pcall(getTexture, path)
        if not ok or not texture then
            errors[#errors + 1] = "icon texture missing: " .. tostring(path)
        end
    end
end

local function runCoreTests(report, player)
    local modules = {
        { name = "Disease registry", value = EHR.Disease and EHR.Disease.Diseases },
        { name = "Medication registry", value = EHR.Medication and EHR.Medication.Database },
        { name = "Immunity API", value = EHR.Immunity },
    }

    for _, moduleDef in ipairs(modules) do
        local valid = type(moduleDef.value) == "table"
        addResult(
            report,
            "Core",
            moduleDef.name,
            valid and "PASS" or "FAIL",
            valid and "loaded" or "module is unavailable"
        )
    end

    local diseases = EHR.Disease and EHR.Disease.Diseases or {}
    local medications = EHR.Medication and EHR.Medication.Database or {}
    addResult(
        report,
        "Core",
        "Registry population",
        countEntries(diseases) > 0 and countEntries(medications) > 0 and "PASS" or "FAIL",
        string.format("%d diseases, %d medications", countEntries(diseases), countEntries(medications))
    )

    if player and player.getModData then
        addResult(report, "Core", "Player context", "PASS", "available; tests remain read-only")
    else
        addResult(report, "Core", "Player context", "WARN", "unavailable; registry tests still valid")
    end

    if ScriptManager and ScriptManager.instance then
        addResult(report, "Core", "ScriptManager", "PASS", "available")
    else
        addResult(report, "Core", "ScriptManager", "WARN", "item existence checks skipped")
    end
end

local function runDiseaseTests(report)
    local diseases = EHR.Disease and EHR.Disease.Diseases
    local medications = EHR.Medication and EHR.Medication.Database or {}
    if type(diseases) ~= "table" then
        addResult(report, "Diseases", "Disease registry", "FAIL", "registry is unavailable")
        return
    end

    for _, diseaseId in ipairs(sortedKeys(diseases)) do
        local def = diseases[diseaseId]
        local errors = {}
        local warnings = {}
        local stageCount = nil

        if type(def) ~= "table" then
            errors[#errors + 1] = "definition is not a table"
        else
            if type(def.name) ~= "string" or def.name == "" then
                errors[#errors + 1] = "display name missing"
            end

            stageCount = tonumber(def.stageCount)
            if not stageCount or stageCount < 1 or stageCount ~= math.floor(stageCount) then
                errors[#errors + 1] = "stageCount must be a positive integer"
            elseif stageCount > 10 then
                warnings[#warnings + 1] = "unusually high stageCount"
            end

            validateMinMax(errors, "incubation", def.incubationMin, def.incubationMax, true)
            validateMinMax(errors, "duration", def.durationMin, def.durationMax, true)

            local severity = tonumber(def.baseSeverity)
            if severity == nil then
                errors[#errors + 1] = "baseSeverity missing"
            elseif severity < 0 or severity > 1.5 then
                errors[#errors + 1] = "baseSeverity outside 0..1.5"
            end

            if type(def.stageDurations) == "table" and stageCount then
                local sum = 0
                for stage = 1, stageCount do
                    local duration = tonumber(def.stageDurations[stage])
                    if duration == nil or duration < 0 then
                        errors[#errors + 1] = "invalid stage duration #" .. tostring(stage)
                    else
                        sum = sum + duration
                    end
                end
                if not approxEqual(sum, 1, 0.02) then
                    errors[#errors + 1] = string.format("stage durations sum to %.3f", sum)
                end
            end

            if type(def.effects) == "table" and stageCount then
                for stage in pairs(def.effects) do
                    if type(stage) == "number" and (stage < 1 or stage > stageCount) then
                        errors[#errors + 1] = "effect references invalid stage " .. tostring(stage)
                    end
                end
            end

            local progressTarget = type(def.progressTo) == "string" and def.progressTo
                or (type(def.canProgress) == "string" and def.canProgress or nil)
            if progressTarget and not knownDisease(diseases, progressTarget) then
                errors[#errors + 1] = "unknown progression target " .. progressTarget
            end

            if type(def.treatments) == "table" then
                for tierId, treatmentIds in pairs(def.treatments) do
                    if type(treatmentIds) ~= "table" then
                        errors[#errors + 1] = tostring(tierId) .. " treatments are not a table"
                    else
                        for _, medicationId in ipairs(treatmentIds) do
                            if startsWith(medicationId, "ExtensiveHealth.") and not medications[medicationId] then
                                errors[#errors + 1] = "unknown treatment " .. tostring(medicationId)
                            end
                        end
                    end
                end
            end

            validateDiseaseIcon(diseaseId, warnings, errors)
        end

        addValidationResult(
            report,
            "Diseases",
            tostring(diseaseId),
            errors,
            warnings,
            stageCount and tostring(stageCount) .. " stages" or nil
        )
    end
end

local function validateSideEffectReferences(medData, sideEffects, errors)
    if type(medData.sideEffects) ~= "table" then return end
    for key, value in pairs(medData.sideEffects) do
        local effectId = type(value) == "string" and value or (type(key) == "string" and key or nil)
        if effectId and not sideEffects[effectId] then
            errors[#errors + 1] = "unknown side effect " .. tostring(effectId)
        end
    end
end

local function runMedicationTests(report)
    local medication = EHR.Medication
    local database = medication and medication.Database
    local diseases = EHR.Disease and EHR.Disease.Diseases or {}
    local schedules = medication and medication.DosingSchedules or {}
    local sideEffects = medication and medication.SideEffects or {}

    if type(database) ~= "table" then
        addResult(report, "Medications", "Medication registry", "FAIL", "registry is unavailable")
        return
    end

    for _, medicationId in ipairs(sortedKeys(database)) do
        local medData = database[medicationId]
        local errors = {}
        local warnings = {}

        if type(medData) ~= "table" then
            errors[#errors + 1] = "definition is not a table"
        else
            local tier = tonumber(medData.tier)
            if tier == nil or tier < 0 or tier > 3 or tier ~= math.floor(tier) then
                errors[#errors + 1] = "tier must be an integer from 0 to 3"
            elseif not medication.TierEffectiveness[tier] then
                errors[#errors + 1] = "tier effectiveness missing"
            end

            if type(medData.displayName) ~= "string" or medData.displayName == "" then
                errors[#errors + 1] = "display name missing"
            end

            if medData.treats ~= nil and type(medData.treats) ~= "table" then
                errors[#errors + 1] = "treats must be a table"
            elseif type(medData.treats) == "table" then
                for _, diseaseId in ipairs(medData.treats) do
                    if not knownDisease(diseases, diseaseId) then
                        errors[#errors + 1] = "unknown disease target " .. tostring(diseaseId)
                    end
                end
            end

            if type(medData.diseaseCureTimeHours) == "table" then
                local targetSet = {}
                for _, diseaseId in ipairs(medData.treats or {}) do
                    targetSet[diseaseId] = true
                end
                for diseaseId, hours in pairs(medData.diseaseCureTimeHours) do
                    if not targetSet[diseaseId] then
                        errors[#errors + 1] = "cure time target absent from treats: " .. tostring(diseaseId)
                    end
                    if not tonumber(hours) or tonumber(hours) <= 0 then
                        errors[#errors + 1] = "invalid cure time for " .. tostring(diseaseId)
                    end
                end
            end

            if medData.cureTimeHours ~= nil and (not tonumber(medData.cureTimeHours) or tonumber(medData.cureTimeHours) <= 0) then
                errors[#errors + 1] = "cureTimeHours must be positive"
            end
            if medData.effectDurationHours ~= nil
                    and (not tonumber(medData.effectDurationHours) or tonumber(medData.effectDurationHours) <= 0) then
                errors[#errors + 1] = "effectDurationHours must be positive"
            end

            validateSideEffectReferences(medData, sideEffects, errors)

            local schedule = schedules[medicationId]
            if schedule then
                local interval = tonumber(schedule.doseInterval)
                local doses = tonumber(schedule.dosesRequired)
                if interval == nil or interval < 0 then
                    errors[#errors + 1] = "invalid dose interval"
                end
                if doses == nil or doses < 1 or doses ~= math.floor(doses) then
                    errors[#errors + 1] = "invalid required dose count"
                end
            elseif not startsWith(medicationId, "TheyKnew.") then
                warnings[#warnings + 1] = "uses default dosing schedule"
            end

            if medication.GetDoseTiming and tier and medication.TierEffectiveness[tier] then
                local ok, timing = pcall(
                    medication.GetDoseTiming,
                    medData,
                    medicationId,
                    medication.TierEffectiveness[tier]
                )
                if not ok or type(timing) ~= "table" then
                    errors[#errors + 1] = "dose timing calculation failed"
                elseif (tonumber(timing.dosesRequired) or 0) < 1
                        or (tonumber(timing.doseInterval) or -1) < 0
                        or (tonumber(timing.activeHours) or -1) < 0 then
                    errors[#errors + 1] = "dose timing returned invalid values"
                elseif medData.blockWhileDoseActive == true and (tonumber(timing.activeHours) or 0) <= 0 then
                    errors[#errors + 1] = "active-dose block has no active duration"
                end
            end

            if startsWith(medicationId, "Base.") or startsWith(medicationId, "ExtensiveHealth.") then
                local scriptItem, scriptError = getScriptItem(medicationId)
                if ScriptManager and ScriptManager.instance and not scriptItem then
                    errors[#errors + 1] = "script item missing"
                        .. (scriptError and ": " .. scriptError or "")
                end
            end
        end

        addValidationResult(
            report,
            "Medications",
            tostring(medicationId),
            errors,
            warnings,
            medData and ("tier " .. tostring(medData.tier)) or nil
        )
    end

    for _, medicationId in ipairs(sortedKeys(schedules)) do
        if not database[medicationId] then
            addResult(
                report,
                "Medications",
                "Schedule: " .. tostring(medicationId),
                startsWith(medicationId, "TheyKnew.") and "WARN" or "FAIL",
                "dosing schedule has no medication definition"
            )
        end
    end

    for _, effectId in ipairs(sortedKeys(sideEffects)) do
        local effectData = sideEffects[effectId]
        local errors = {}
        local warnings = {}
        if type(effectData) ~= "table" then
            errors[#errors + 1] = "definition is not a table"
        else
            if type(effectData.displayName) ~= "string" or effectData.displayName == "" then
                errors[#errors + 1] = "display name missing"
            end
            local duration = tonumber(effectData.duration)
            if duration == nil or duration <= 0 then
                errors[#errors + 1] = "duration must be positive"
            end
            if effectData.effects ~= nil and type(effectData.effects) ~= "function" then
                errors[#errors + 1] = "effects handler is not a function"
            end
        end
        addValidationResult(report, "Medications", "Side effect: " .. tostring(effectId), errors, warnings, "valid")
    end

    for medicationId in pairs(medication.OverdoseRiskMedications or {}) do
        if not database[medicationId] then
            addResult(
                report,
                "Medications",
                "Overdose: " .. tostring(medicationId),
                "FAIL",
                "overdose entry has no medication definition"
            )
        end
    end
end

local function runImmunityTests(report)
    local immunity = EHR.Immunity
    if type(immunity) ~= "table" then
        addResult(report, "Immunity", "Immunity module", "FAIL", "module is unavailable")
        return
    end

    local requiredFunctions = {
        "GetDiseaseSensitivity",
        "GetRiskMultiplierForScore",
        "ModifyDiseaseChance",
        "GetWoundContainmentChance",
        "CalculateWoundContainmentChance",
        "GetScore",
        "GetStatusId",
    }
    local missing = {}
    for _, functionName in ipairs(requiredFunctions) do
        if type(immunity[functionName]) ~= "function" then
            missing[#missing + 1] = functionName
        end
    end
    addResult(
        report,
        "Immunity",
        "Public API",
        #missing == 0 and "PASS" or "FAIL",
        #missing == 0 and "all required functions available" or ("missing: " .. join(missing, ", "))
    )
    if #missing > 0 then return end

    local expectedCurve = {
        [0] = 1.50,
        [20] = 1.30,
        [40] = 1.10,
        [50] = 1.00,
        [60] = 0.93,
        [80] = 0.79,
        [100] = 0.65,
    }
    local curveErrors = {}
    for _, score in ipairs({0, 20, 40, 50, 60, 80, 100}) do
        local actual = immunity.GetRiskMultiplierForScore(score, 1, 1)
        if not approxEqual(actual, expectedCurve[score], 0.0001) then
            curveErrors[#curveErrors + 1] = string.format("%d=%.3f", score, actual)
        end
    end
    addResult(
        report,
        "Immunity",
        "Risk curve anchors",
        #curveErrors == 0 and "PASS" or "FAIL",
        #curveErrors == 0 and "0:+50%, 50:neutral, 100:-35%" or join(curveErrors)
    )

    local monotonic = true
    local previous = math.huge
    for score = 0, 100 do
        local current = immunity.GetRiskMultiplierForScore(score, 1, 1)
        if current > previous + 0.000001 then
            monotonic = false
            break
        end
        previous = current
    end
    addResult(
        report,
        "Immunity",
        "Risk curve monotonicity",
        monotonic and "PASS" or "FAIL",
        monotonic and "risk never rises as immunity improves" or "curve reverses direction"
    )

    local diseases = EHR.Disease and EHR.Disease.Diseases or {}
    for _, diseaseId in ipairs(sortedKeys(immunity.DISEASE_SENSITIVITY or {})) do
        local sensitivity = immunity.GetDiseaseSensitivity(diseaseId)
        local errors = {}
        if sensitivity <= 0 or sensitivity > 1 then
            errors[#errors + 1] = "sensitivity outside (0, 1]"
        end
        if not knownDisease(diseases, diseaseId) then
            errors[#errors + 1] = "unknown disease"
        end
        local lowRisk = immunity.GetRiskMultiplierForScore(0, sensitivity, 1)
        local highRisk = immunity.GetRiskMultiplierForScore(100, sensitivity, 1)
        if lowRisk <= 1 or highRisk >= 1 then
            errors[#errors + 1] = "risk direction is invalid"
        end
        addResult(
            report,
            "Immunity",
            "Sensitivity: " .. tostring(diseaseId),
            #errors == 0 and "PASS" or "FAIL",
            #errors == 0 and string.format("%.2f", sensitivity) or join(errors)
        )
    end

    local unsupported = immunity.GetDiseaseSensitivity("concussion") == 0
    addResult(
        report,
        "Immunity",
        "Unsupported disease bypass",
        unsupported and "PASS" or "FAIL",
        unsupported and "concussion remains unaffected" or "unsupported disease received sensitivity"
    )

    local woundCases = {
        { name = "Wound containment at 20", current = 20, detected = 20, strength = 1, expected = 0 },
        { name = "Wound containment at 60", current = 60, detected = 60, strength = 1, expected = 0.225 },
        { name = "Wound containment at 100", current = 100, detected = 100, strength = 1, expected = 0.45 },
        { name = "Wound containment hard cap", current = 100, detected = 100, strength = 2, expected = 0.65 },
    }
    for _, case in ipairs(woundCases) do
        local chance = immunity.CalculateWoundContainmentChance(
            case.current,
            case.detected,
            case.strength,
            true
        )
        local passed = approxEqual(chance, case.expected, 0.0001)
        addResult(
            report,
            "Immunity",
            case.name,
            passed and "PASS" or "FAIL",
            string.format("expected %.3f, got %.3f", case.expected, chance)
        )
    end

    local disabledChance = immunity.CalculateWoundContainmentChance(100, 100, 1, false)
    addResult(
        report,
        "Immunity",
        "Gameplay effects bypass",
        disabledChance == 0 and "PASS" or "FAIL",
        disabledChance == 0 and "disabled gameplay gives no containment bonus" or "disabled result was non-zero"
    )

    local statusExpected = {
        { 0, "suppressed" },
        { 20, "compromised" },
        { 40, "strained" },
        { 60, "stable" },
        { 80, "strong" },
    }
    local statusErrors = {}
    for _, entry in ipairs(statusExpected) do
        local actual = immunity.GetStatusId(entry[1])
        if actual ~= entry[2] then
            statusErrors[#statusErrors + 1] = tostring(entry[1]) .. "=" .. tostring(actual)
        end
    end
    addResult(
        report,
        "Immunity",
        "Status thresholds",
        #statusErrors == 0 and "PASS" or "FAIL",
        #statusErrors == 0 and "all five bands valid" or join(statusErrors)
    )

    if type(immunity.ApplyAntibioticCap) ~= "function"
            or type(immunity.ApplyAntibioticDecline) ~= "function" then
        addResult(report, "Immunity", "Antibiotic immune decline", "FAIL", "decline API is unavailable")
    else
        local target = immunity.ApplyAntibioticCap(90, true)
        local weak = immunity.ApplyAntibioticCap(30, true)
        local inactive = immunity.ApplyAntibioticCap(90, false)
        local oneTick = immunity.ApplyAntibioticDecline(90, 1, 1)
        local floor = immunity.ApplyAntibioticDecline(36, 1, 1)
        local passed = target == 35 and weak == 30 and inactive == 90
            and oneTick == 86 and floor == 35
        addResult(
            report,
            "Immunity",
            "Antibiotic immune decline",
            passed and "PASS" or "FAIL",
            string.format("target %.1f, tick 90->%.1f, floor %.1f", target, oneTick, floor)
        )
    end
end

local function isKnoxDisease(diseaseId)
    local normalized = string.lower(tostring(diseaseId or ""))
    normalized = string.gsub(normalized, "_", "")
    return normalized == "knoxinfection"
end

local function runLiveCase(report, category, name, player, callback)
    local snapshot = capturePlayerSnapshot(player)
    local ok, status, detail = pcall(callback)
    if not ok then
        detail = tostring(status)
        status = "FAIL"
    end

    status = STATUS_PRIORITY[status] and status or "PASS"
    local restored, restoreFailures = restorePlayerSnapshot(player, snapshot)
    if not restored then
        status = "FAIL"
        local restoreDetail = "rollback failed: " .. join(restoreFailures)
        detail = detail and (tostring(detail) .. "; " .. restoreDetail) or restoreDetail
    end

    return addResult(report, category, name, status, detail or "completed and rolled back")
end

local function initializeIsolatedDiseaseState(player)
    EHR.Disease.InitializePlayer(player)
    local data = EHR.Disease.GetDiseaseData(player)
    if not data then return nil end
    data.active = {}
    return data
end

local function runLiveDiseaseTests(report, player)
    local diseaseApi = EHR.Disease
    local diseases = diseaseApi and diseaseApi.Diseases
    if type(diseases) ~= "table" then
        addResult(report, "Live Diseases", "Disease registry", "FAIL", "registry is unavailable")
        return
    end
    if type(diseaseApi.Contract) ~= "function"
            or type(diseaseApi.SetStage) ~= "function"
            or type(diseaseApi.Cure) ~= "function" then
        addResult(report, "Live Diseases", "Lifecycle API", "FAIL", "Contract, SetStage, or Cure is unavailable")
        return
    end

    for _, diseaseId in ipairs(sortedKeys(diseases)) do
        local def = diseases[diseaseId]
        if isKnoxDisease(diseaseId) then
            addResult(
                report,
                "Live Diseases",
                tostring(diseaseId),
                "WARN",
                "vanilla-owned Knox lifecycle intentionally skipped"
            )
        else
            runLiveCase(report, "Live Diseases", tostring(diseaseId), player, function()
                if diseaseApi.IsDiseaseEnabled and not diseaseApi.IsDiseaseEnabled(diseaseId) then
                    return "WARN", "disabled by sandbox; lifecycle skipped"
                end

                local data = initializeIsolatedDiseaseState(player)
                if not data then return "FAIL", "disease player state could not initialize" end

                diseaseApi.Contract(player, diseaseId)
                local instance = data.active and data.active[diseaseId]
                if not instance then return "FAIL", "Contract did not create an active disease" end

                local stageCount = math.max(1, tonumber(def and def.stageCount) or 1)
                for stage = 1, stageCount do
                    local changed = diseaseApi.SetStage(player, diseaseId, stage)
                    local actual = data.active[diseaseId] and tonumber(data.active[diseaseId].stage)
                    if changed ~= true or actual ~= stage then
                        return "FAIL", string.format("stage %d transition returned %s, actual %s", stage, tostring(changed), tostring(actual))
                    end
                end

                local cured = diseaseApi.Cure(player, diseaseId)
                if cured ~= true or (data.active and data.active[diseaseId] ~= nil) then
                    return "FAIL", "Cure did not remove the active disease"
                end

                return "PASS", string.format("contract -> %d stages -> cure", stageCount)
            end)
        end
    end

    runLiveCase(report, "Live Diseases", "Stage 1 effect dispatcher", player, function()
        local diseaseId = diseases.food_poisoning and "food_poisoning"
            or (diseases.common_cold and "common_cold" or nil)
        if not diseaseId then return "WARN", "no safe smoke-test disease is registered" end
        if diseaseApi.IsDiseaseEnabled and not diseaseApi.IsDiseaseEnabled(diseaseId) then
            return "WARN", tostring(diseaseId) .. " is disabled by sandbox"
        end

        local data = initializeIsolatedDiseaseState(player)
        diseaseApi.Contract(player, diseaseId)
        local instance = data and data.active and data.active[diseaseId]
        if not instance then return "FAIL", "smoke-test disease did not contract" end

        diseaseApi.SetStage(player, diseaseId, 1)
        local now = getGameTime and getGameTime():getWorldAgeHours() or 0
        instance.incubationEnd = now - 0.01
        diseaseApi.ApplyEffects(player, diseaseId, instance, diseases[diseaseId])
        return "PASS", tostring(diseaseId) .. " stage 1 handler executed"
    end)
end

local function chooseMedicationTarget(medData, diseases)
    local fallback = nil
    for _, diseaseId in ipairs(medData.treats or {}) do
        if not isKnoxDisease(diseaseId) then
            fallback = fallback or diseaseId
            if diseases[diseaseId] then return diseaseId, true end
        end
    end
    return fallback, false
end

local function runLiveMedicationTests(report, player)
    local medication = EHR.Medication
    local database = medication and medication.Database
    local diseases = EHR.Disease and EHR.Disease.Diseases or {}
    if type(database) ~= "table" then
        addResult(report, "Live Medications", "Medication registry", "FAIL", "registry is unavailable")
        return
    end
    if type(medication.GetMedicationData) ~= "function"
            or type(medication.TrackDoseOnly) ~= "function"
            or type(medication.ApplyTreatment) ~= "function" then
        addResult(report, "Live Medications", "Medication API", "FAIL", "tracking or treatment API is unavailable")
        return
    end

    for _, medicationId in ipairs(sortedKeys(database)) do
        local medData = database[medicationId]
        runLiveCase(report, "Live Medications", tostring(medicationId), player, function()
            if type(medData) ~= "table" then return "FAIL", "definition is not a table" end

            local modData = player:getModData()
            modData.EHR_Medication = nil
            local diseaseData = initializeIsolatedDiseaseState(player)
            if not diseaseData then return "FAIL", "disease player state could not initialize" end

            local target, registeredTarget = chooseMedicationTarget(medData, diseases)
            local path = "dose tracking"
            if target then
                local now = getGameTime and getGameTime():getWorldAgeHours() or 0
                if registeredTarget
                        and (not EHR.Disease.IsDiseaseEnabled or EHR.Disease.IsDiseaseEnabled(target)) then
                    EHR.Disease.Contract(player, target)
                end
                if not diseaseData.active[target] then
                    diseaseData.active[target] = {
                        startTime = now,
                        incubationEnd = now,
                        endTime = now + 24,
                        peakTime = now + 12,
                        stage = 1,
                        severity = 0.5,
                    }
                    path = "treatment with isolated disease fixture"
                else
                    path = "contract + treatment"
                end

                local tier = tonumber(medData.tier) or 0
                local tierEffects = medication.TierEffectiveness and medication.TierEffectiveness[tier]
                if type(tierEffects) ~= "table" then return "FAIL", "tier effectiveness is unavailable" end
                medication.ApplyTreatment(player, target, medData, tierEffects, medicationId)
            else
                medication.TrackDoseOnly(player, medData, medicationId)
            end

            local tracking = medication.GetMedicationData(player)
            local dose = tracking and tracking.activeDoses and tracking.activeDoses[medicationId]
            if type(dose) ~= "table" or (tonumber(dose.doseCount) or 0) < 1 then
                return "FAIL", "real medication path did not create a dose record"
            end
            if target and dose.treatingDisease ~= target then
                return "FAIL", "dose target mismatch: " .. tostring(dose.treatingDisease)
            end
            return "PASS", path .. "; inventory untouched"
        end)
    end
end

local function runLiveImmunityTests(report, player)
    local immunity = EHR.Immunity
    if type(immunity) ~= "table"
            or type(immunity.InitializePlayer) ~= "function"
            or type(immunity.UpdatePlayer) ~= "function" then
        addResult(report, "Live Immunity", "Immunity API", "FAIL", "runtime API is unavailable")
        return
    end

    runLiveCase(report, "Live Immunity", "Player factor update", player, function()
        local state = immunity.InitializePlayer(player)
        if type(state) ~= "table" then return "FAIL", "InitializePlayer returned no state" end
        state.lastUpdateHour = (getGameTime and getGameTime():getWorldAgeHours() or 0) - 1
        state = immunity.UpdatePlayer(player, true)
        if type(state) ~= "table" or type(state.factors) ~= "table" then
            return "FAIL", "UpdatePlayer did not calculate factors"
        end
        local score = tonumber(state.score)
        local target = tonumber(state.target)
        if not score or not target or score < 0 or score > 100 or target < 0 or target > 100 then
            return "FAIL", "score or target is outside 0..100"
        end
        return "PASS", string.format("score %.1f, target %.1f", score, target)
    end)

    runLiveCase(report, "Live Immunity", "Active antibiotic gradually suppresses immunity", player, function()
        local medication = EHR.Medication
        if type(medication) ~= "table"
                or type(medication.GetMedicationData) ~= "function"
                or type(medication.HasActiveAntibiotic) ~= "function" then
            return "FAIL", "antibiotic activity API is unavailable"
        end

        local now = getGameTime and getGameTime():getWorldAgeHours() or 0
        local tracking = medication.GetMedicationData(player)
        tracking.activeDoses["Base.Antibiotics"] = {
            lastDoseTime = now,
            doseCount = 1,
            totalDosesNeeded = 6,
            intervalHours = 4,
            activeHours = 4,
            medicationName = "Antibiotics",
            tier = 0,
        }

        local state = immunity.InitializePlayer(player)
        state.score = 90
        state.target = 90
        state.lastUpdateHour = now - 1
        state.antibioticSuppressed = false
        state.activeAntibiotic = nil
        state.antibioticCap = nil
        state.lastAntibioticTickHour = nil
        state = immunity.UpdatePlayer(player, true)

        local score = tonumber(state and state.score)
        local target = tonumber(state and state.target)
        if state.antibioticSuppressed ~= true then
            return "FAIL", "active dose was not detected"
        end
        if not score or not target or score ~= 90 or target ~= 35 then
            return "FAIL", string.format("initial state failed: score %s, target %s", tostring(score), tostring(target))
        end

        state.lastAntibioticTickHour = now - 0.25
        state.lastUpdateHour = now - 0.25
        state = immunity.UpdatePlayer(player, true)
        score = tonumber(state and state.score)
        if score ~= 86 then
            return "FAIL", "15-minute decline expected 86, got " .. tostring(score)
        end
        return "PASS", string.format("score 90.0 -> %.1f, target %.1f", score, target)
    end)

    runLiveCase(report, "Live Immunity", "Disease chance integration", player, function()
        local state = immunity.InitializePlayer(player)
        local diseaseId = nil
        for _, candidate in ipairs(sortedKeys(immunity.DISEASE_SENSITIVITY or {})) do
            if immunity.GetDiseaseSensitivity(candidate) > 0 then
                diseaseId = candidate
                break
            end
        end
        if not diseaseId then return "FAIL", "no immunity-sensitive disease is registered" end
        if not immunity.IsGameplayEnabled() or immunity.GetEffectStrength() <= 0 then
            return "WARN", "immunity gameplay effects are disabled by sandbox"
        end

        local baseChance = 0.25
        state.score = 0
        local lowChance = immunity.ModifyDiseaseChance(player, diseaseId, baseChance)
        state.score = 100
        local highChance = immunity.ModifyDiseaseChance(player, diseaseId, baseChance)
        if not (lowChance > baseChance and highChance < baseChance and lowChance > highChance) then
            return "FAIL", string.format("expected low > %.3f > high; got %.3f / %.3f", baseChance, lowChance, highChance)
        end
        return "PASS", string.format("%s: %.3f -> %.3f", diseaseId, lowChance, highChance)
    end)
end

local sortReportResults

local function isFiniteNumber(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function validateDeepPhysiology(player)
    local errors = {}
    local snapshot = capturePlayerSnapshot(player)

    for statName, value in pairs(snapshot.stats or {}) do
        if not isFiniteNumber(value) then
            errors[#errors + 1] = tostring(statName) .. " is not finite"
        end
    end

    local healthValues = {
        { "player health", snapshot.playerHealth },
        { "overall health", snapshot.overallHealth },
    }
    for _, entry in ipairs(healthValues) do
        if entry[2] ~= nil then
            if not isFiniteNumber(entry[2]) then
                errors[#errors + 1] = entry[1] .. " is not finite"
            elseif entry[2] < -0.01 or entry[2] > 100.01 then
                errors[#errors + 1] = string.format("%s outside 0..100: %.3f", entry[1], entry[2])
            end
        end
    end

    if snapshot.temperature ~= nil then
        if not isFiniteNumber(snapshot.temperature) then
            errors[#errors + 1] = "temperature is not finite"
        elseif snapshot.temperature < 20 or snapshot.temperature > 50 then
            errors[#errors + 1] = string.format("implausible temperature: %.3f", snapshot.temperature)
        end
    end

    for index, part in pairs(snapshot.bodyParts or {}) do
        if part.health ~= nil and (not isFiniteNumber(part.health) or part.health < -0.01 or part.health > 100.01) then
            errors[#errors + 1] = "body part " .. tostring(index) .. " has invalid health"
        end
        if part.additionalPain ~= nil and not isFiniteNumber(part.additionalPain) then
            errors[#errors + 1] = "body part " .. tostring(index) .. " has invalid pain"
        end
        if part.stiffness ~= nil and not isFiniteNumber(part.stiffness) then
            errors[#errors + 1] = "body part " .. tostring(index) .. " has invalid stiffness"
        end
    end

    local dead = false
    if player and player.isDead then
        local ok, value = pcall(function() return player:isDead() end)
        dead = ok and value == true
    end
    if dead then errors[#errors + 1] = "effect killed the test character" end

    return errors
end

local function deepRestore(player, snapshot)
    local restored, failures = restorePlayerSnapshot(player, snapshot)
    if restored then return true, nil end
    return false, "rollback failed: " .. join(failures)
end

local function prepareDeepSafeHealth(player)
    if not player then return end
    writeMethod(player, "setHealth", 100)
    local bodyDamage = player.getBodyDamage and player:getBodyDamage() or nil
    writeMethod(bodyDamage, "setOverallBodyHealth", 100)
end

local function deepDiseaseLifecycle(player, diseaseId, def, baseline)
    local diseaseApi = EHR.Disease
    if isKnoxDisease(diseaseId) then
        return "WARN", "vanilla-owned Knox lifecycle intentionally skipped"
    end
    if diseaseApi.IsDiseaseEnabled and not diseaseApi.IsDiseaseEnabled(diseaseId) then
        return "WARN", "disabled by sandbox; deep lifecycle skipped"
    end

    local stageCount = math.max(1, tonumber(def and def.stageCount) or 1)
    local checkedStages = 0
    for stage = 1, stageCount do
        local restored, restoreError = deepRestore(player, baseline)
        if not restored then return "FAIL", restoreError end

        local data = initializeIsolatedDiseaseState(player)
        if not data then return "FAIL", "disease player state could not initialize" end
        diseaseApi.Contract(player, diseaseId)
        local instance = data.active and data.active[diseaseId]
        if not instance then return "FAIL", "Contract did not create an active disease" end

        local changed = diseaseApi.SetStage(player, diseaseId, stage)
        instance = data.active and data.active[diseaseId]
        local actual = instance and tonumber(instance.stage)
        if changed ~= true or actual ~= stage then
            return "FAIL", string.format(
                "stage %d transition returned %s, actual %s",
                stage,
                tostring(changed),
                tostring(actual)
            )
        end

        prepareDeepSafeHealth(player)
        diseaseApi.ApplyEffects(player, diseaseId, instance, def)
        local physiologyErrors = validateDeepPhysiology(player)
        if #physiologyErrors > 0 then
            return "FAIL", "stage " .. tostring(stage) .. ": " .. join(physiologyErrors)
        end
        checkedStages = checkedStages + 1
    end

    local restored, restoreError = deepRestore(player, baseline)
    if not restored then return "FAIL", restoreError end
    local data = initializeIsolatedDiseaseState(player)
    diseaseApi.Contract(player, diseaseId)
    if not data or not data.active or not data.active[diseaseId] then
        return "FAIL", "final cure fixture could not contract"
    end
    local cured = diseaseApi.Cure(player, diseaseId)
    if cured ~= true or data.active[diseaseId] ~= nil then
        return "FAIL", "Cure did not remove the active disease"
    end

    return "PASS", string.format("%d stage effects + cure; isolated rollback", checkedStages)
end

local function findForwardTimelineDisease(diseases)
    local preferred = { "food_poisoning", "common_cold", "pneumonia" }
    for _, diseaseId in ipairs(preferred) do
        local def = diseases[diseaseId]
        if def
                and not def.permanent
                and not def.manualProgression
                and not def.reverseProgression
                and not def.stageDrivenByBodyTemperature
                and not def.noNaturalRecovery then
            return diseaseId, def
        end
    end
    for _, diseaseId in ipairs(sortedKeys(diseases)) do
        local def = diseases[diseaseId]
        if not isKnoxDisease(diseaseId)
                and not def.permanent
                and not def.manualProgression
                and not def.reverseProgression
                and not def.stageDrivenByBodyTemperature
                and not def.noNaturalRecovery then
            return diseaseId, def
        end
    end
    return nil, nil
end

local function prepareTimelineDisease(player, diseaseId, baseline)
    local restored, restoreError = deepRestore(player, baseline)
    if not restored then return nil, nil, restoreError end
    local data = initializeIsolatedDiseaseState(player)
    EHR.Disease.Contract(player, diseaseId)
    local instance = data and data.active and data.active[diseaseId]
    if not instance then return nil, nil, "timeline fixture could not contract" end
    return data, instance, nil
end

local function deepForwardTimeline(player, diseases, baseline)
    local diseaseId = findForwardTimelineDisease(diseases)
    if not diseaseId then return "WARN", "no natural forward-progression disease is available" end

    local now = getGameTime and getGameTime():getWorldAgeHours() or 0
    local fixtures = {
        { stage = 1, startTime = now, incubationEnd = now + 1, peakTime = now + 2, endTime = now + 4 },
        { stage = 2, startTime = now - 2, incubationEnd = now - 1, peakTime = now + 1, endTime = now + 3 },
        { stage = 3, startTime = now - 4, incubationEnd = now - 3, peakTime = now - 1, endTime = now + 2 },
        { stage = 4, startTime = now - 6, incubationEnd = now - 5, peakTime = now - 3, endTime = now + 1 },
    }

    for _, fixture in ipairs(fixtures) do
        local data, instance, fixtureError = prepareTimelineDisease(player, diseaseId, baseline)
        if not instance then return "FAIL", fixtureError end
        instance.startTime = fixture.startTime
        instance.incubationEnd = fixture.incubationEnd
        instance.peakTime = fixture.peakTime
        instance.endTime = fixture.endTime
        instance.stage = 1
        prepareDeepSafeHealth(player)
        EHR.Disease.UpdateProgression(player, player:getModData())
        instance = data.active and data.active[diseaseId]
        if not instance or tonumber(instance.stage) ~= fixture.stage then
            return "FAIL", string.format(
                "%s expected stage %d, got %s",
                diseaseId,
                fixture.stage,
                tostring(instance and instance.stage or "removed")
            )
        end
        local physiologyErrors = validateDeepPhysiology(player)
        if #physiologyErrors > 0 then
            return "FAIL", "timeline stage " .. tostring(fixture.stage) .. ": " .. join(physiologyErrors)
        end
    end

    local data, instance, fixtureError = prepareTimelineDisease(player, diseaseId, baseline)
    if not instance then return "FAIL", fixtureError end
    instance.startTime = now - 5
    instance.incubationEnd = now - 4
    instance.peakTime = now - 3
    instance.endTime = now - 0.01
    EHR.Disease.UpdateProgression(player, player:getModData())
    if data.active and data.active[diseaseId] ~= nil then
        return "FAIL", diseaseId .. " did not naturally recover after endTime"
    end

    return "PASS", diseaseId .. " resolved stages 1 -> 4 and natural recovery through UpdateProgression"
end

local function deepReverseTimeline(player, diseases, baseline)
    local diseaseId = nil
    for _, candidate in ipairs(sortedKeys(diseases)) do
        if diseases[candidate] and diseases[candidate].reverseProgression then
            diseaseId = candidate
            break
        end
    end
    if not diseaseId then return "WARN", "no reverse-progression disease is registered" end

    local def = diseases[diseaseId]
    local stageCount = math.max(2, tonumber(def.stageCount) or 3)
    local now = getGameTime and getGameTime():getWorldAgeHours() or 0
    local duration = 48
    local checks = {
        { progress = 0.05, expected = stageCount },
        { progress = 0.40, expected = math.max(1, stageCount - 1) },
        { progress = 0.75, expected = 1 },
    }

    for _, check in ipairs(checks) do
        local data, instance, fixtureError = prepareTimelineDisease(player, diseaseId, baseline)
        if not instance then return "FAIL", fixtureError end
        instance.startTime = now - (duration * check.progress)
        instance.incubationEnd = instance.startTime
        instance.peakTime = instance.startTime
        instance.endTime = instance.startTime + duration
        instance.stage = stageCount
        prepareDeepSafeHealth(player)
        EHR.Disease.UpdateProgression(player, player:getModData())
        instance = data.active and data.active[diseaseId]
        if not instance or tonumber(instance.stage) ~= check.expected then
            return "FAIL", string.format(
                "%s expected reverse stage %d, got %s",
                diseaseId,
                check.expected,
                tostring(instance and instance.stage or "removed")
            )
        end
    end

    local data, instance, fixtureError = prepareTimelineDisease(player, diseaseId, baseline)
    if not instance then return "FAIL", fixtureError end
    instance.startTime = now - duration - 1
    instance.incubationEnd = instance.startTime
    instance.peakTime = instance.startTime
    instance.endTime = now - 0.01
    EHR.Disease.UpdateProgression(player, player:getModData())
    if data.active and data.active[diseaseId] ~= nil then
        return "FAIL", diseaseId .. " did not finish reverse recovery"
    end

    return "PASS", diseaseId .. " resolved reverse stages and recovery through UpdateProgression"
end

local function deepMedicationLifecycle(player, medicationId, medData, diseases)
    local medication = EHR.Medication
    if type(medData) ~= "table" then return "FAIL", "definition is not a table" end
    prepareDeepSafeHealth(player)

    local modData = player:getModData()
    modData.EHR_Medication = nil
    local diseaseData = initializeIsolatedDiseaseState(player)
    if not diseaseData then return "FAIL", "disease player state could not initialize" end

    local target, registeredTarget = chooseMedicationTarget(medData, diseases)
    if target then
        local now = getGameTime and getGameTime():getWorldAgeHours() or 0
        if registeredTarget
                and (not EHR.Disease.IsDiseaseEnabled or EHR.Disease.IsDiseaseEnabled(target)) then
            EHR.Disease.Contract(player, target)
        end
        if not diseaseData.active[target] then
            diseaseData.active[target] = {
                startTime = now,
                incubationEnd = now,
                endTime = now + 48,
                peakTime = now + 24,
                stage = 2,
                stageCount = 4,
                severity = 0.5,
            }
        end

        local tier = tonumber(medData.tier) or 0
        local tierEffects = medication.TierEffectiveness and medication.TierEffectiveness[tier]
        if type(tierEffects) ~= "table" then return "FAIL", "tier effectiveness is unavailable" end
        medication.ApplyTreatment(player, target, medData, tierEffects, medicationId)
    else
        medication.TrackDoseOnly(player, medData, medicationId)
    end

    local tracking = medication.GetMedicationData(player)
    local dose = tracking and tracking.activeDoses and tracking.activeDoses[medicationId]
    if type(dose) ~= "table" or (tonumber(dose.doseCount) or 0) < 1 then
        return "FAIL", "real medication path did not create a dose record"
    end

    local initialStatus = medication.GetDoseStatus and medication.GetDoseStatus(player, medicationId)
    if type(initialStatus) ~= "table" then return "FAIL", "GetDoseStatus returned no active record" end

    local treatment = target and tracking.activeTreatments and tracking.activeTreatments[target] or nil
    if type(treatment) == "table" then
        local totalDoses = math.max(1, tonumber(initialStatus.totalDosesNeeded) or 1)
        local interval = math.max(0, tonumber(initialStatus.intervalHours) or 0)
        local tier = tonumber(medData.tier) or 0
        local tierEffects = medication.TierEffectiveness[tier]

        for _ = 2, totalDoses do
            dose.lastDoseTime = (getGameTime and getGameTime():getWorldAgeHours() or 0) - interval
            medication.ApplyTreatment(player, target, medData, tierEffects, medicationId)
            dose = tracking.activeDoses[medicationId]
        end

        local complete = medication.IsTreatmentCourseComplete
            and medication.IsTreatmentCourseComplete(player, treatment)
        if complete ~= true then
            return "FAIL", string.format(
                "course incomplete after %d doses (actual %s)",
                totalDoses,
                tostring(dose and dose.doseCount)
            )
        end

        local completionHours = medication.GetTreatmentCompletionHours
            and medication.GetTreatmentCompletionHours(player, treatment)
            or tonumber(treatment.cureTimeHours)
            or 0
        treatment.startTime = (getGameTime and getGameTime():getWorldAgeHours() or 0)
            - math.max(0, completionHours)
            - 0.1
        medication.Update(player)
        if tracking.activeTreatments[target] ~= nil then
            return "FAIL", "Medication.Update did not finish the completed treatment course"
        end

        local physiologyErrors = validateDeepPhysiology(player)
        if #physiologyErrors > 0 then return "FAIL", join(physiologyErrors) end
        return "PASS", string.format("dose status -> %d-dose course -> treatment expiry", totalDoses)
    end

    dose.doseCount = math.max(1, tonumber(initialStatus.totalDosesNeeded) or 1)
    local expireHours = math.max(
        1,
        tonumber(initialStatus.activeHours) or 0,
        tonumber(initialStatus.intervalHours) or 0
    )
    dose.lastDoseTime = (getGameTime and getGameTime():getWorldAgeHours() or 0) - expireHours - 0.1
    medication.Update(player)
    local expiredStatus = medication.GetDoseStatus and medication.GetDoseStatus(player, medicationId)
    if expiredStatus and expiredStatus.isDoseActive then
        return "FAIL", "symptom/support dose remained active after simulated expiry"
    end

    local physiologyErrors = validateDeepPhysiology(player)
    if #physiologyErrors > 0 then return "FAIL", join(physiologyErrors) end
    return "PASS", "dose status -> support/symptom expiry through Medication.Update"
end

local function deepSideEffectLifecycle(player, effectId)
    local medication = EHR.Medication
    local def = medication.SideEffects and medication.SideEffects[effectId]
    if type(def) ~= "table" then return "FAIL", "side-effect definition is unavailable" end
    prepareDeepSafeHealth(player)

    local tracking = medication.GetMedicationData(player)
    local applied = medication.ApplySideEffect(player, effectId, { force = true })
    local active = tracking.activeSideEffects and tracking.activeSideEffects[effectId]
    if applied ~= true or type(active) ~= "table" then
        return "FAIL", "ApplySideEffect did not create active state"
    end

    local duration = math.max(0, tonumber(active.duration) or tonumber(def.duration) or 0)
    active.startTime = (getGameTime and getGameTime():getWorldAgeHours() or 0) - duration - 0.1
    medication.Update(player)
    if effectId == "dizziness"
            and EHR.ToxinVision
            and EHR.ToxinVision.StopEpisode then
        pcall(function()
            local playerIndex = player.getPlayerNum and player:getPlayerNum() or 0
            local currentHour = getGameTime and getGameTime():getWorldAgeHours() or 0
            EHR.ToxinVision.StopEpisode(playerIndex, currentHour, false)
        end)
    end
    if tracking.activeSideEffects and tracking.activeSideEffects[effectId] ~= nil then
        return "FAIL", "side effect remained active after duration"
    end

    local physiologyErrors = validateDeepPhysiology(player)
    if #physiologyErrors > 0 then return "FAIL", join(physiologyErrors) end
    return "PASS", string.format("applied -> %.1fh expiry -> onEnd", duration)
end

local function deepImmunityRuntime(player)
    local immunity = EHR.Immunity
    local state = immunity.InitializePlayer(player)
    if type(state) ~= "table" then return "FAIL", "InitializePlayer returned no state" end

    local now = getGameTime and getGameTime():getWorldAgeHours() or 0
    state.lastUpdateHour = now - 1
    local first = immunity.UpdatePlayer(player, true)
    if type(first) ~= "table" or type(first.factors) ~= "table" then
        return "FAIL", "first forced update did not calculate factors"
    end
    state.lastUpdateHour = now - 1
    local second = immunity.UpdatePlayer(player, true)
    if type(second) ~= "table" or not isFiniteNumber(second.score) or not isFiniteNumber(second.target) then
        return "FAIL", "second forced update produced invalid score or target"
    end
    if second.score < 0 or second.score > 100 or second.target < 0 or second.target > 100 then
        return "FAIL", "score or target is outside 0..100"
    end
    return "PASS", string.format("two forced factor updates; score %.1f, target %.1f", second.score, second.target)
end

local function deepImmunityRisk(player)
    local immunity = EHR.Immunity
    local state = immunity.InitializePlayer(player)
    local diseaseId = nil
    for _, candidate in ipairs(sortedKeys(immunity.DISEASE_SENSITIVITY or {})) do
        if immunity.GetDiseaseSensitivity(candidate) > 0 then
            diseaseId = candidate
            break
        end
    end
    if not diseaseId then return "FAIL", "no immunity-sensitive disease is registered" end
    if not immunity.IsGameplayEnabled() or immunity.GetEffectStrength() <= 0 then
        return "WARN", "immunity gameplay effects are disabled by sandbox"
    end

    local baseChance = 0.25
    state.score = 0
    local lowChance = immunity.ModifyDiseaseChance(player, diseaseId, baseChance)
    state.score = 100
    local highChance = immunity.ModifyDiseaseChance(player, diseaseId, baseChance)
    if not isFiniteNumber(lowChance) or not isFiniteNumber(highChance)
            or not (lowChance > baseChance and highChance < baseChance and lowChance > highChance) then
        return "FAIL", string.format(
            "expected low > %.3f > high; got %s / %s",
            baseChance,
            tostring(lowChance),
            tostring(highChance)
        )
    end
    return "PASS", string.format("%s risk %.3f -> %.3f", diseaseId, lowChance, highChance)
end

local function deepImmunityContainment(player)
    local immunity = EHR.Immunity
    if type(immunity.CalculateWoundContainmentChance) ~= "function" then
        return "FAIL", "wound containment calculator is unavailable"
    end
    local strength = immunity.GetEffectStrength and immunity.GetEffectStrength() or 1
    local low = immunity.CalculateWoundContainmentChance(0, 0, strength, true)
    local mid = immunity.CalculateWoundContainmentChance(50, 50, strength, true)
    local high = immunity.CalculateWoundContainmentChance(100, 100, strength, true)
    if not isFiniteNumber(low) or not isFiniteNumber(mid) or not isFiniteNumber(high) then
        return "FAIL", "containment calculator returned a non-finite value"
    end
    if not (low <= mid and mid <= high and high > low) then
        return "FAIL", string.format("expected low <= mid <= high, got %.3f / %.3f / %.3f", low, mid, high)
    end
    return "PASS", string.format("wound containment %.1f%% -> %.1f%%", low * 100, high * 100)
end

local function addDeepStep(steps, category, name, callback)
    steps[#steps + 1] = {
        category = category,
        name = name,
        run = callback,
    }
end

local function buildDeepSteps(scope, player, suiteSnapshot)
    local steps = {}
    local diseases = EHR.Disease and EHR.Disease.Diseases or {}
    local medication = EHR.Medication

    addDeepStep(steps, "Deep Core", "Runtime update APIs", function()
        local missing = {}
        if not EHR.Disease or type(EHR.Disease.UpdateProgression) ~= "function" then
            missing[#missing + 1] = "Disease.UpdateProgression"
        end
        if not medication or type(medication.Update) ~= "function" then
            missing[#missing + 1] = "Medication.Update"
        end
        if not EHR.Immunity or type(EHR.Immunity.UpdatePlayer) ~= "function" then
            missing[#missing + 1] = "Immunity.UpdatePlayer"
        end
        if #missing > 0 then return "FAIL", "missing: " .. join(missing) end
        return "PASS", "disease, medication, and immunity update paths are callable"
    end)

    if scope == "all" or scope == "diseases" then
        for _, diseaseId in ipairs(sortedKeys(diseases)) do
            local capturedId = diseaseId
            local capturedDef = diseases[diseaseId]
            addDeepStep(steps, "Deep Diseases", tostring(capturedId), function(testPlayer)
                return deepDiseaseLifecycle(testPlayer, capturedId, capturedDef, suiteSnapshot)
            end)
        end
        addDeepStep(steps, "Deep Diseases", "Forward timeline", function(testPlayer)
            return deepForwardTimeline(testPlayer, diseases, suiteSnapshot)
        end)
        addDeepStep(steps, "Deep Diseases", "Reverse timeline", function(testPlayer)
            return deepReverseTimeline(testPlayer, diseases, suiteSnapshot)
        end)
    end

    if scope == "all" or scope == "medications" then
        for _, medicationId in ipairs(sortedKeys(medication and medication.Database or {})) do
            local capturedId = medicationId
            local capturedData = medication.Database[medicationId]
            addDeepStep(steps, "Deep Medications", tostring(capturedId), function(testPlayer)
                return deepMedicationLifecycle(testPlayer, capturedId, capturedData, diseases)
            end)
        end
        for _, effectId in ipairs(sortedKeys(medication and medication.SideEffects or {})) do
            local capturedEffect = effectId
            addDeepStep(steps, "Deep Side Effects", tostring(capturedEffect), function(testPlayer)
                return deepSideEffectLifecycle(testPlayer, capturedEffect)
            end)
        end
    end

    if scope == "all" or scope == "immunity" then
        addDeepStep(steps, "Deep Immunity", "Repeated factor updates", deepImmunityRuntime)
        addDeepStep(steps, "Deep Immunity", "Disease risk integration", deepImmunityRisk)
        addDeepStep(steps, "Deep Immunity", "Wound containment curve", deepImmunityContainment)
    end

    return steps
end

local function makeDeepReport(scope)
    return {
        version = AutoTests.VERSION,
        scope = scope,
        results = {},
        counts = { PASS = 0, WARN = 0, FAIL = 0 },
        total = 0,
        readOnly = false,
        live = true,
        deep = true,
        asynchronous = true,
        rollbackAttempted = false,
    }
end

function AutoTests.CreateDeepSession(scope, player)
    scope = string.lower(tostring(scope or "all"))
    if scope ~= "all" and scope ~= "diseases" and scope ~= "medications" and scope ~= "immunity" then
        scope = "all"
    end

    local report = makeDeepReport(scope)
    local session = {
        player = player,
        report = report,
        steps = {},
        current = 0,
        total = 0,
        done = false,
        aborted = false,
    }

    local invalidReason = nil
    if not player then
        invalidReason = "current player is unavailable"
    elseif isClient and isClient() then
        invalidReason = "deep tests are single-player only; MP authority is intentionally untouched"
    else
        local dead = false
        if player.isDead then
            local ok, value = pcall(function() return player:isDead() end)
            dead = ok and value == true
        end
        if dead then invalidReason = "current player is dead" end
    end

    if invalidReason then
        addResult(report, "Deep Core", "Player context", "FAIL", invalidReason)
        report.passed = false
        session.done = true
        return session
    end

    session.suiteSnapshot = capturePlayerSnapshot(player)
    addResult(
        report,
        "Deep Core",
        "Safety snapshot",
        "PASS",
        "EHR state, stats, health, temperature, and body-part state captured"
    )
    session.steps = buildDeepSteps(scope, player, session.suiteSnapshot)
    session.total = #session.steps

    function session:Finish(wasAborted)
        if self.done then return self.report end
        self.report.rollbackAttempted = true
        local restored, failures = restorePlayerSnapshot(self.player, self.suiteSnapshot)
        addResult(
            self.report,
            "Deep Core",
            "Final rollback",
            restored and "PASS" or "FAIL",
            restored and "original player state restored" or ("failed fields: " .. join(failures))
        )
        if wasAborted then
            self.aborted = true
            self.report.aborted = true
            addResult(self.report, "Deep Core", "Session", "WARN", "aborted by user; rollback completed")
        end
        sortReportResults(self.report)
        self.report.passed = self.report.counts.FAIL == 0
        self.done = true
        return self.report
    end

    function session:Abort()
        return self:Finish(true)
    end

    function session:Step()
        if self.done then return false, self.report end
        if self.current >= self.total then
            return false, self:Finish(false)
        end

        self.current = self.current + 1
        local step = self.steps[self.current]
        local restoredBefore, beforeFailures = restorePlayerSnapshot(self.player, self.suiteSnapshot)
        if not restoredBefore then
            addResult(
                self.report,
                step.category,
                step.name,
                "FAIL",
                "pre-step rollback failed: " .. join(beforeFailures)
            )
            return false, self:Finish(false)
        end

        local ok, status, detail = pcall(step.run, self.player)
        if not ok then
            detail = tostring(status)
            status = "FAIL"
        end
        status = STATUS_PRIORITY[status] and status or "PASS"

        local restoredAfter, afterFailures = restorePlayerSnapshot(self.player, self.suiteSnapshot)
        if not restoredAfter then
            status = "FAIL"
            local rollbackDetail = "post-step rollback failed: " .. join(afterFailures)
            detail = detail and (tostring(detail) .. "; " .. rollbackDetail) or rollbackDetail
        end
        addResult(self.report, step.category, step.name, status, detail or "completed")

        if self.current >= self.total then
            return false, self:Finish(false)
        end
        return true, self.report
    end

    return session
end

sortReportResults = function(report)
    table.sort(report.results, function(left, right)
        local leftPriority = STATUS_PRIORITY[left.status] or 99
        local rightPriority = STATUS_PRIORITY[right.status] or 99
        if leftPriority ~= rightPriority then
            return leftPriority < rightPriority
        end
        if left.category ~= right.category then
            return tostring(left.category) < tostring(right.category)
        end
        return tostring(left.name) < tostring(right.name)
    end)
end

local function runGuarded(report, category, callback)
    local ok, errorMessage = pcall(callback, report)
    if not ok then
        addResult(report, category, category .. " runner", "FAIL", tostring(errorMessage))
    end
end

function AutoTests.Run(scope, player)
    scope = string.lower(tostring(scope or "all"))
    if scope ~= "all" and scope ~= "diseases" and scope ~= "medications" and scope ~= "immunity" then
        scope = "all"
    end

    local report = {
        version = AutoTests.VERSION,
        scope = scope,
        results = {},
        counts = { PASS = 0, WARN = 0, FAIL = 0 },
        total = 0,
        readOnly = true,
    }

    runGuarded(report, "Core", function()
        runCoreTests(report, player)
    end)
    if scope == "all" or scope == "diseases" then
        runGuarded(report, "Diseases", runDiseaseTests)
    end
    if scope == "all" or scope == "medications" then
        runGuarded(report, "Medications", runMedicationTests)
    end
    if scope == "all" or scope == "immunity" then
        runGuarded(report, "Immunity", runImmunityTests)
    end

    table.sort(report.results, function(left, right)
        local leftPriority = STATUS_PRIORITY[left.status] or 99
        local rightPriority = STATUS_PRIORITY[right.status] or 99
        if leftPriority ~= rightPriority then
            return leftPriority < rightPriority
        end
        if left.category ~= right.category then
            return tostring(left.category) < tostring(right.category)
        end
        return tostring(left.name) < tostring(right.name)
    end)

    report.passed = report.counts.FAIL == 0
    return report
end

function AutoTests.RunLive(scope, player)
    scope = string.lower(tostring(scope or "all"))
    if scope ~= "all" and scope ~= "diseases" and scope ~= "medications" and scope ~= "immunity" then
        scope = "all"
    end

    local report = {
        version = AutoTests.VERSION,
        scope = scope,
        results = {},
        counts = { PASS = 0, WARN = 0, FAIL = 0 },
        total = 0,
        readOnly = false,
        live = true,
        rollbackAttempted = false,
    }

    if not player then
        addResult(report, "Live Core", "Player context", "FAIL", "current player is unavailable")
        report.passed = false
        return report
    end
    if isClient and isClient() then
        addResult(
            report,
            "Live Core",
            "Execution mode",
            "FAIL",
            "live integration tests are single-player only; MP authority is intentionally untouched"
        )
        report.passed = false
        return report
    end

    local dead = false
    if player.isDead then pcall(function() dead = player:isDead() end) end
    if dead then
        addResult(report, "Live Core", "Player context", "FAIL", "current player is dead")
        report.passed = false
        return report
    end

    local suiteSnapshot = capturePlayerSnapshot(player)
    addResult(report, "Live Core", "Safety snapshot", "PASS", "EHR state, stats, health, temperature, and body-part pain captured")

    if scope == "all" or scope == "diseases" then
        runGuarded(report, "Live Diseases", function()
            runLiveDiseaseTests(report, player)
        end)
    end
    if scope == "all" or scope == "medications" then
        runGuarded(report, "Live Medications", function()
            runLiveMedicationTests(report, player)
        end)
    end
    if scope == "all" or scope == "immunity" then
        runGuarded(report, "Live Immunity", function()
            runLiveImmunityTests(report, player)
        end)
    end

    report.rollbackAttempted = true
    local restored, restoreFailures = restorePlayerSnapshot(player, suiteSnapshot)
    addResult(
        report,
        "Live Core",
        "Final rollback",
        restored and "PASS" or "FAIL",
        restored and "original player state restored" or ("failed fields: " .. join(restoreFailures))
    )

    sortReportResults(report)
    report.passed = report.counts.FAIL == 0
    return report
end

function AutoTests.FormatSummary(report)
    if type(report) ~= "table" then return "No report" end
    local counts = report.counts or {}
    return string.format(
        "PASS %d | WARN %d | FAIL %d | TOTAL %d",
        tonumber(counts.PASS) or 0,
        tonumber(counts.WARN) or 0,
        tonumber(counts.FAIL) or 0,
        tonumber(report.total) or 0
    )
end

return AutoTests
