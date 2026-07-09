--[[
    EHR <-> Realistic Temperature compatibility bridge.

    Realistic Temperature is allowed to own environmental body temperature and
    body heat generation. EHR owns disease fever and disease logic. The bridge
    filters RT cold/sickness/damage outcomes so RT can calculate heat without
    duplicating EHR diseases.
]]--

require "ExtensiveHealth/EHR_BodyTemperature"
require "ExtensiveHealth/EHR_EnvironmentalDiseases"
require "ExtensiveHealth/EHR_DiseaseDefinitions"

EHR = EHR or {}
EHR.RealisticTemperatureCompat = EHR.RealisticTemperatureCompat or {}

local Compat = EHR.RealisticTemperatureCompat

Compat.installed = Compat.installed or false
Compat.installAttempted = Compat.installAttempted or false

local function compatModeAllowsBridge()
    if not EHR.BodyTemp or not EHR.BodyTemp.IsRealisticTemperatureActive then
        return false
    end
    return EHR.BodyTemp.IsRealisticTemperatureActive()
end

local function getRTModule()
    if _G and _G.RC_TempSim then
        return _G.RC_TempSim
    end

    local ok, module = pcall(require, "RC_TempSimModule")
    if ok and module then
        return module
    end

    return nil
end

local function getThermalAuthority(rt)
    if rt and rt.ThermalAuthorityClient then
        return rt.ThermalAuthorityClient
    end

    local ok, authority = pcall(require, "RC_TempSim/events/RC_ThermalAuthorityClient")
    if ok and authority then
        if rt then
            rt.ThermalAuthorityClient = authority
        end
        return authority
    end

    return nil
end

local function getRTRecord(player)
    if not player or not player.getModData then return nil end
    local modData = nil
    pcall(function() modData = player:getModData() end)
    local rec = modData and modData.RC_TempSimBodyTemp or nil
    if type(rec) ~= "table" then return nil end
    return rec
end

local function getNormalTemp()
    local cfg = EHR.BodyTemp and EHR.BodyTemp.Config or {}
    return cfg.normalTemp or 36.6
end

local function getCurrentEHRBodyTemp(player)
    local cfg = EHR.BodyTemp and EHR.BodyTemp.Config or {}
    local normalTemp = getNormalTemp()
    local tempData = EHR.BodyTemp and EHR.BodyTemp.GetTemperatureData and EHR.BodyTemp.GetTemperatureData(player) or nil
    local bodyTemp = tonumber(tempData and tempData.bodyTemp) or normalTemp
    return math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, bodyTemp))
end

local function syncRTRecordToEHR(player)
    local rec = getRTRecord(player)
    if not rec then return false end

    rec._ehrBodyTemperatureDisabled = false
    return true
end

local function hasEHRFeverSource(player)
    if not compatModeAllowsBridge() then return false end
    if not player then return false end
    if EHR.BodyTemp and EHR.BodyTemp.HasActiveDiseaseFeverSource then
        local ok, result = pcall(EHR.BodyTemp.HasActiveDiseaseFeverSource, player)
        return ok and result == true
    end
    return false
end

function Compat.ShouldOwnFever(player)
    return compatModeAllowsBridge()
end

local function getEHRFeverTemp(player)
    if not hasEHRFeverSource(player) then return nil end

    local cfg = EHR.BodyTemp and EHR.BodyTemp.Config or {}
    local normalTemp = getNormalTemp()
    local tempData = EHR.BodyTemp.GetTemperatureData and EHR.BodyTemp.GetTemperatureData(player) or nil
    local current = tempData and tonumber(tempData.bodyTemp) or nil
    local target = EHR.BodyTemp.GetActiveDiseaseFeverTarget and EHR.BodyTemp.GetActiveDiseaseFeverTarget(player) or nil

    if current and target then
        if target >= normalTemp and current < normalTemp then
            current = normalTemp
        end
        return math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, current))
    end

    if target then
        return math.max(cfg.minBodyTemp or 28.0, math.min(cfg.maxBodyTemp or 42.0, target))
    end

    return current
end

local function getCommonColdStrength(player)
    if not player or not player.getModData then return nil end

    local modData = player:getModData()
    local active = modData and modData.EHR_Disease and modData.EHR_Disease.active
    local disease = active and active.common_cold
    if not disease then return nil end

    local stage = tonumber(disease.stage) or 1
    local def = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases.common_cold
    local effects = def and def.effects and def.effects[stage]
    local strength = tonumber(effects and effects.coldStrength) or 0
    if strength <= 0 then return nil end
    return strength
end

local function cloneOutcome(outcome)
    local cloned = {}
    if type(outcome) == "table" then
        for k, v in pairs(outcome) do
            cloned[k] = v
        end
    end
    return cloned
end

local function restoreRTBaseTemperature(player)
    local rec = getRTRecord(player)
    if not rec or not rec._ehrFeverOverrideActive then return false end

    local baseCore = tonumber(rec._ehrRtBaseCore)
    if baseCore then
        rec.core = baseCore
        rec._bodyTempDirty = true
    end

    rec._ehrFeverOverrideActive = false
    rec._ehrDiseaseFeverCore = nil
    rec._ehrRtBaseCore = nil
    return baseCore ~= nil
end

local bodyOutcomeFields = {
    sickness = true,
    hasCold = true,
    coldStrength = true,
    catchACold = true,
    hypothermiaDamage = true,
}

local function stripRTBodyOutcome(outcome)
    local patched = nil
    local function ensurePatched()
        if not patched then patched = cloneOutcome(outcome) end
        return patched
    end

    for field in pairs(bodyOutcomeFields) do
        if outcome[field] ~= nil then
            ensurePatched()[field] = nil
        end
    end

    return patched or outcome
end

function Compat.BuildOutcome(player, outcome, source)
    if type(outcome) ~= "table" then return outcome end
    if not compatModeAllowsBridge() then return outcome end

    local patched = stripRTBodyOutcome(outcome)
    local feverTemp = getEHRFeverTemp(player)
    local rec = getRTRecord(player)

    if feverTemp then
        if rec then
            if outcome.temperature ~= nil then
                rec._ehrRtBaseCore = tonumber(outcome.temperature) or rec._ehrRtBaseCore
            elseif rec._ehrRtBaseCore == nil and type(rec.core) == "number" then
                rec._ehrRtBaseCore = rec.core
            end
            rec._ehrFeverOverrideActive = true
            rec._ehrDiseaseFeverCore = feverTemp
        end

        if patched == outcome then
            patched = cloneOutcome(outcome)
        end
        patched.temperature = feverTemp
        return patched
    end

    if rec then
        rec._ehrFeverOverrideActive = false
        rec._ehrDiseaseFeverCore = nil
        rec._ehrRtBaseCore = nil
    end

    return patched
end

local function patchThermalAuthority(rt, authority)
    if not authority then return false end
    if authority._ehrApplyPersistentOutcome then return true end
    if type(authority.applyPersistentOutcome) ~= "function" then return false end

    local original = authority.applyPersistentOutcome
    authority._ehrApplyPersistentOutcome = original
    authority.applyPersistentOutcome = function(playerObj, outcome, source)
        local patchedOutcome = outcome
        local ok, result = pcall(Compat.BuildOutcome, playerObj, outcome, source)
        if ok and result then
            patchedOutcome = result
        elseif not ok and EHR and EHR.Log then
            EHR.Log("RT compat: outcome patch failed: " .. tostring(result))
        end
        return original(playerObj, patchedOutcome, source)
    end

    if rt then
        rt.ThermalAuthorityClient = authority
    end

    return true
end

local function patchRTBodyFlags(rt)
    if not rt then return false end

    rt.DEBUG_BODYTEMP_DISABLE_SIMULATION = false
    rt.DEBUG_DISABLE_BODYTEMP_ENFORCE = false
    rt._ehrBodyTemperatureDisabled = false

    local normalTemp = getNormalTemp()
    if type(rt.BODY_TEMP_NORMAL_C) == "number" then
        rt.BODY_TEMP_NORMAL_C = normalTemp
    end
    if type(rt.WARM_RECOVERY_TARGET_C) == "number" then
        rt.WARM_RECOVERY_TARGET_C = normalTemp
    end

    return true
end

local function patchBodyUpdate(rt)
    if not rt then return false end

    if type(rt._ehrUpdatePlayerBodyTemperature) == "function" then
        rt.updatePlayerBodyTemperature = rt._ehrUpdatePlayerBodyTemperature
        rt._ehrUpdatePlayerBodyTemperature = nil
    end

    return type(rt.updatePlayerBodyTemperature) == "function"
end

local function patchBodyEnforcement(rt)
    if not rt then return false end

    if type(rt._ehrEnforceBodyTemperatures) == "function" then
        local original = rt._ehrEnforceBodyTemperatures
        local current = rt.enforceBodyTemperatures
        if Events and Events.OnTick and Events.OnTick.Remove then
            if current and current ~= original then
                pcall(function() Events.OnTick.Remove(current) end)
            end
            pcall(function() Events.OnTick.Remove(original) end)
        end
        rt.enforceBodyTemperatures = original
        rt._ehrEnforceBodyTemperatures = nil
        if Events and Events.OnTick and Events.OnTick.Add then
            pcall(function() Events.OnTick.Add(original) end)
        end
    end

    return type(rt.enforceBodyTemperatures) == "function"
end

function Compat.Install()
    if Compat.installed then return true end
    if not compatModeAllowsBridge() then return false end

    local rt = getRTModule()
    if not rt then return false end

    local flagsPatched = patchRTBodyFlags(rt)
    local authority = getThermalAuthority(rt)
    local authorityPatched = patchThermalAuthority(rt, authority)
    local updatePatched = patchBodyUpdate(rt)
    local enforcePatched = patchBodyEnforcement(rt)

    local authorityReady = authority and authority._ehrApplyPersistentOutcome ~= nil
    local updateReady = rt and type(rt.updatePlayerBodyTemperature) == "function"
    local enforceReady = rt and type(rt.enforceBodyTemperatures) == "function"
    if flagsPatched and authorityReady and updateReady and enforceReady then
        Compat.installed = true
        if EHR and EHR.Log then
            EHR.Log("Realistic Temperature compatibility installed")
        end
        return true
    end

    return false
end

function Compat.IsInstalled()
    return Compat.installed == true
end

function Compat.TryInstall()
    if Compat.installed then return true end
    Compat.installAttempted = true
    return Compat.Install()
end

local function onGameStart()
    Compat.TryInstall()
end

local function onCreatePlayer()
    Compat.TryInstall()
end

if Events and not Compat.eventsRegistered then
    Compat.eventsRegistered = true
    if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
    if Events.OnLoad then Events.OnLoad.Add(onGameStart) end
    if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
end

Compat.TryInstall()
