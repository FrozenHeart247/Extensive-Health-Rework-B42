--[[
    EHR <-> Realistic Temperature compatibility bridge.

    RT remains responsible for environmental temperature whenever EHR has no
    active fever source. While an EHR fever disease is active, RT still computes
    its own environmental core temperature, but the persistent temperature and
    cold/sickness outcome that reaches the player is rewritten to EHR state.
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
    return hasEHRFeverSource(player)
end

local function getEHRFeverTemp(player)
    if not hasEHRFeverSource(player) then return nil end

    local cfg = EHR.BodyTemp and EHR.BodyTemp.Config or {}
    local normalTemp = cfg.normalTemp or 37.0
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

function Compat.BuildOutcome(player, outcome, source)
    if type(outcome) ~= "table" then return outcome end

    local rec = getRTRecord(player)
    local feverTemp = getEHRFeverTemp(player)
    if not feverTemp then
        restoreRTBaseTemperature(player)
        return outcome
    end

    local patched = nil
    local function ensurePatched()
        if not patched then patched = cloneOutcome(outcome) end
        return patched
    end

    if rec and outcome.temperature ~= nil then
        rec._ehrRtBaseCore = tonumber(outcome.temperature) or rec._ehrRtBaseCore
        rec._ehrDiseaseFeverCore = feverTemp
        rec._ehrFeverOverrideActive = true
    end

    if outcome.temperature ~= nil then
        ensurePatched().temperature = feverTemp
    end

    if source == "cold_sickness" then
        local coldStrength = getCommonColdStrength(player)
        local nextOutcome = ensurePatched()
        if coldStrength then
            nextOutcome.hasCold = true
            nextOutcome.coldStrength = coldStrength
            nextOutcome.catchACold = 0.0
        else
            nextOutcome.hasCold = false
            nextOutcome.coldStrength = 0.0
            nextOutcome.catchACold = 0.0
        end
    end

    return patched or outcome
end

local function patchThermalAuthority(rt, authority)
    if not authority or authority._ehrApplyPersistentOutcome then return false end
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

local function patchBodyUpdate(rt)
    if not rt or rt._ehrUpdatePlayerBodyTemperature then return false end
    if type(rt.updatePlayerBodyTemperature) ~= "function" then return false end

    local original = rt.updatePlayerBodyTemperature
    rt._ehrUpdatePlayerBodyTemperature = original
    rt.updatePlayerBodyTemperature = function(player)
        if not hasEHRFeverSource(player) then
            restoreRTBaseTemperature(player)
            return original(player)
        end

        local rec = getRTRecord(player)
        local savedCore = rec and rec.core or nil
        local baseCore = rec and tonumber(rec._ehrRtBaseCore) or nil
        if rec and baseCore then
            rec.core = baseCore
        end

        local oldColdMult = rt.COLD_SICKNESS_MULT
        rt.COLD_SICKNESS_MULT = 0.0

        local ok, result = pcall(original, player)

        rt.COLD_SICKNESS_MULT = oldColdMult
        if not ok then
            if rec and savedCore ~= nil then
                rec.core = savedCore
            end
            error(tostring(result))
        end

        return result
    end

    return true
end

function Compat.Install()
    if Compat.installed then return true end
    if not compatModeAllowsBridge() then return false end

    local rt = getRTModule()
    if not rt then return false end

    local authority = getThermalAuthority(rt)
    local authorityPatched = patchThermalAuthority(rt, authority)
    local updatePatched = patchBodyUpdate(rt)

    local authorityReady = authority and authority._ehrApplyPersistentOutcome ~= nil
    local updateReady = rt and rt._ehrUpdatePlayerBodyTemperature ~= nil
    if authorityReady and updateReady then
        Compat.installed = true
        if EHR and EHR.Log then
            EHR.Log("Realistic Temperature compatibility bridge installed")
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
