-- Complete EHR snapshots must distinguish an absent section from a partial
-- update. Lua nil values are omitted by the network table serializer.
EHR = EHR or {}
EHR.MedicalStateSync = EHR.MedicalStateSync or {}

local fields = {
    EHR_Sepsis = { "EHR_Sepsis_Initialized" },
    EHR_Disease = { "EHR_Disease_Initialized" },
    EHR_Blood = { "EHR_Blood_Initialized" },
    EHR_WoundInfection = { "EHR_WoundInfection_V2_Initialized", "EHR_WoundInfection_V2_Migrated" },
    EHR_WoundInfections = { "EHR_WoundInfections_Initialized" },
    EHR_Medication = { "EHR_Medication_Initialized" },
    EHR_MedicalJournal = false,
    EHR_Temperature = {},
    EHR_KnownDiseases = false,
    EHR_KnoxHeraldRead = false,
    EHR_KnoxKnowledgeSource = false,
    EHR_CorpseSickness = {},
    EHR_KnoxCure = {},
    EHR_Immunity = {},
    EHR_OfflineProgression = {},
}

function EHR.MedicalStateSync.Build(data, player)
    if type(data) ~= "table" then return nil end
    -- RequestSync can arrive before server initialization. An empty joining
    -- player's table must not clear the client's save or acknowledge its init.
    if player and data.EHR_Initialized ~= true then return nil end
    if player and isServer and isServer() and EHR.OfflineProgression then
        if EHR.OfflineProgression.EnsureSessionPrepared
                and not EHR.OfflineProgression.EnsureSessionPrepared(player) then return nil end
        if EHR.OfflineProgression.TouchPlayer then
            EHR.OfflineProgression.TouchPlayer(player)
        end
    end
    local packet = { EHR_FullSnapshot = true, EHR_ClearedFields = {} }
    for key in pairs(fields) do
        if data[key] ~= nil then
            packet[key] = data[key]
        elseif fields[key] then
            packet.EHR_ClearedFields[#packet.EHR_ClearedFields + 1] = key
        end
    end
    return packet
end

function EHR.MedicalStateSync.ApplyClearedFields(data, packet, inDebugGrace)
    if type(data) ~= "table" or type(packet) ~= "table"
            or type(packet.EHR_ClearedFields) ~= "table" then return end
    for _, key in ipairs(packet.EHR_ClearedFields) do
        local flags = fields[key]
        local preserveDebug = inDebugGrace and
            (key == "EHR_Disease" or key == "EHR_WoundInfection" or key == "EHR_Sepsis")
        if flags and packet[key] == nil and not preserveDebug then
            data[key] = nil
            for _, flag in ipairs(flags) do data[flag] = nil end
        end
    end
end
