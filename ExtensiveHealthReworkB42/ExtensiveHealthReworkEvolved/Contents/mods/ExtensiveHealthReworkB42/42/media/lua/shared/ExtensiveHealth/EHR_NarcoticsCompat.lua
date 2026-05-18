--[[
    Extensive Health Rework B42
    Narcotics compatibility stub

    The old third-party narcotics integration was removed for B42 stability.
    Keep this file as a no-op compatibility layer so older EHR code paths that
    check EHR.Narcotics do not crash.
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.Narcotics = EHR.Narcotics or {}
EHR.Narcotics.Disabled = true

function EHR.Narcotics.IsModLoaded() return false end
function EHR.Narcotics.IsOnStimulants() return false end
function EHR.Narcotics.IsOnOpioids() return false end
function EHR.Narcotics.IsOverdosing() return false, nil end
function EHR.Narcotics.IsInWithdrawal() return false, nil end

function EHR.Narcotics.ApplyStimulantEffect() end
function EHR.Narcotics.CheckOverdose() end
function EHR.Narcotics.ResetState() end

function EHR.Narcotics.ShouldBlockHealing() return false, nil end
function EHR.Narcotics.GetInfectionSpeedModifier() return 1.0 end

function EHR.Narcotics.HookBloodModule() end
function EHR.Narcotics.HookHealingControl() end
function EHR.Narcotics.HookWoundInfection() end

function EHR.Narcotics.GetActiveSubstances() return {} end
function EHR.Narcotics.GetWithdrawalStatus() return nil end

function EHR.Narcotics.OnTick() end
function EHR.Narcotics.Initialize() end

EHR.Log("Narcotics compatibility disabled")
