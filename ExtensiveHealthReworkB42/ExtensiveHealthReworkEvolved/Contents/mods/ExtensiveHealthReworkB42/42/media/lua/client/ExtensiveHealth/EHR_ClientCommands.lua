--[[
    Extensive Health Rework - Client Commands

    Handles server-to-client commands for MP data synchronization.
    Server sends updated EHR data via sendServerCommand, client receives here.
]]--

-- Only run on client
if isServer() and not isClient() then
    return
end

EHR = EHR or {}
EHR.ClientCommands = {}

local function isEHRDebug()
    if EHR and EHR.IsDebugMode then
        return EHR.IsDebugMode()
    end
    if getDebug then
        return getDebug()
    end
    return false
end

local function log(msg)
    if isEHRDebug() then
        print(msg)
    end
end

log("[EHR] EHR_ClientCommands.lua loading on client...")

-- ============================================
-- SERVER COMMAND HANDLER
-- ============================================

local function OnServerCommand(module, command, args)
    -- Debug: Log all incoming server commands
    log("[EHR Client] OnServerCommand received:")
    log("[EHR Client]   module = " .. tostring(module))
    log("[EHR Client]   command = " .. tostring(command))

    if module ~= "EHR_Sync" then
        return
    end

    local player = getPlayer()
    if not player then
        log("[EHR Client] No local player found!")
        return
    end

    local data = player:getModData()

    if command == "UpdateModData" then
        log("[EHR Client] Received UpdateModData from server")

        -- Update local ModData with server data
        if args then
            -- CRITICAL FIX: Check grace period ONCE at the start for all debug-sensitive data
            local inGracePeriod = false
            if EHR.Disease and EHR.Disease.IsInDebugGracePeriod then
                inGracePeriod = EHR.Disease.IsInDebugGracePeriod(player)
            end

            if args.EHR_Sepsis ~= nil then
                -- CRITICAL FIX: Respect grace period for sepsis data too
                if inGracePeriod and data.EHR_Sepsis and data.EHR_Sepsis.active then
                    -- During grace period, don't overwrite active sepsis that was set locally
                    log("[EHR Client] Grace period active - preserving local sepsis state")
                else
                    data.EHR_Sepsis = args.EHR_Sepsis
                    log("[EHR Client] Updated EHR_Sepsis: active=" .. tostring(args.EHR_Sepsis and args.EHR_Sepsis.active))
                end
            end

            if args.EHR_Disease ~= nil then
                -- MP FIX: Don't overwrite disease data during grace period
                -- The grace period protects locally-set debug data from being wiped
                if inGracePeriod then
                    -- During grace period, MERGE server diseases into local data
                    -- Don't replace - we want to keep locally-set diseases
                    log("[EHR Client] Grace period active - merging disease data instead of replacing")
                    if not data.EHR_Disease then
                        data.EHR_Disease = args.EHR_Disease
                    else
                        -- Merge: add server diseases that don't exist locally
                        data.EHR_Disease.active = data.EHR_Disease.active or {}
                        if args.EHR_Disease.active then
                            for diseaseId, diseaseInfo in pairs(args.EHR_Disease.active) do
                                if not data.EHR_Disease.active[diseaseId] then
                                    data.EHR_Disease.active[diseaseId] = diseaseInfo
                                    log("[EHR Client] Merged server disease: " .. diseaseId)
                                end
                            end
                        end
                    end
                else
                    -- Normal sync: replace with server data
                    data.EHR_Disease = args.EHR_Disease
                end

                local diseaseCount = 0
                if data.EHR_Disease and data.EHR_Disease.active then
                    for _ in pairs(data.EHR_Disease.active) do
                        diseaseCount = diseaseCount + 1
                    end
                end
                log("[EHR Client] EHR_Disease now has " .. diseaseCount .. " active diseases")
            end

            if args.EHR_Blood ~= nil then
                -- MP FIX: Server is AUTHORITATIVE for blood type
                -- Always accept server's blood type (it was generated server-side)
                local existingBloodType = data.EHR_Blood and data.EHR_Blood.bloodType
                local serverBloodType = args.EHR_Blood.bloodType

                log("[EHR Client] ====== Blood Data Sync ======")
                log("[EHR Client] Existing blood type: " .. tostring(existingBloodType))
                log("[EHR Client] Server blood type: " .. tostring(serverBloodType))

                -- Replace blood data with server data
                data.EHR_Blood = args.EHR_Blood

                -- Server is authoritative - always use server's blood type if provided
                if serverBloodType and serverBloodType ~= "PENDING" then
                    -- Server has valid blood type - use it
                    log("[EHR Client] SUCCESS! Blood type set to: " .. serverBloodType)
                elseif existingBloodType and existingBloodType ~= "PENDING" then
                    -- Server didn't send blood type but we have one - keep it (shouldn't happen)
                    data.EHR_Blood.bloodType = existingBloodType
                    log("[EHR Client] WARNING: Server sent no blood type, kept existing: " .. existingBloodType)
                else
                    log("[EHR Client] WARNING: No valid blood type received!")
                end
                log("[EHR Client] Final blood type: " .. tostring(data.EHR_Blood.bloodType))
                log("[EHR Client] ============================")
            end

            if args.EHR_WoundInfection ~= nil then
                -- CRITICAL FIX: Respect grace period for wound infection data
                if inGracePeriod and data.EHR_WoundInfection and data.EHR_WoundInfection.parts then
                    local hasLocalInfections = false
                    for _, partData in pairs(data.EHR_WoundInfection.parts) do
                        if partData.stage and partData.stage > 0 then
                            hasLocalInfections = true
                            break
                        end
                    end
                    if hasLocalInfections then
                        log("[EHR Client] Grace period active - preserving local wound infections")
                    else
                        data.EHR_WoundInfection = args.EHR_WoundInfection
                        log("[EHR Client] Updated EHR_WoundInfection")
                    end
                else
                    data.EHR_WoundInfection = args.EHR_WoundInfection
                    log("[EHR Client] Updated EHR_WoundInfection")
                end
            end

            if args.EHR_WoundInfections ~= nil then
                data.EHR_WoundInfections = args.EHR_WoundInfections
                log("[EHR Client] Updated EHR_WoundInfections (legacy)")
            end

            if args.EHR_Medication ~= nil then
                data.EHR_Medication = args.EHR_Medication
                log("[EHR Client] Updated EHR_Medication")
            end

            if args.EHR_MedicalJournal ~= nil then
                -- BUG FIX: Sync medical journal from server
                -- Merge with existing to preserve local entries until sync
                if data.EHR_MedicalJournal and data.EHR_MedicalJournal.entries then
                    -- Server data takes precedence, but preserve structure
                    data.EHR_MedicalJournal = args.EHR_MedicalJournal
                else
                    data.EHR_MedicalJournal = args.EHR_MedicalJournal
                end
                local entryCount = 0
                if data.EHR_MedicalJournal and data.EHR_MedicalJournal.entries then
                    for _ in pairs(data.EHR_MedicalJournal.entries) do
                        entryCount = entryCount + 1
                    end
                end
                log("[EHR Client] Updated EHR_MedicalJournal (" .. entryCount .. " entries)")
            end

            if args.EHR_Temperature ~= nil then
                -- MP FIX: Sync body temperature data from server
                data.EHR_Temperature = args.EHR_Temperature
                local bodyTemp = data.EHR_Temperature.bodyTemp or 37.0
                log("[EHR Client] Updated EHR_Temperature (body temp: " .. string.format("%.1f", bodyTemp) .. "°C)")
            end

            if args.EHR_KnownDiseases ~= nil then
                local mergedKnown = {}
                if type(data.EHR_KnownDiseases) == "table" then
                    for diseaseId, known in pairs(data.EHR_KnownDiseases) do
                        if known == true then
                            mergedKnown[diseaseId] = true
                        end
                    end
                end
                if type(args.EHR_KnownDiseases) == "table" then
                    for diseaseId, known in pairs(args.EHR_KnownDiseases) do
                        if known == true then
                            mergedKnown[diseaseId] = true
                        end
                    end
                end
                data.EHR_KnownDiseases = mergedKnown
                log("[EHR Client] Updated EHR_KnownDiseases")
            end

            if args.EHR_CorpseSickness ~= nil then
                data.EHR_CorpseSickness = args.EHR_CorpseSickness
                log("[EHR Client] Updated EHR_CorpseSickness")
            end

            if args.EHR_KnoxCure ~= nil then
                data.EHR_KnoxCure = args.EHR_KnoxCure
                log("[EHR Client] Updated EHR_KnoxCure")
            end
        end

        log("[EHR Client] ModData sync complete!")

    else
        log("[EHR Client] Unknown command: " .. tostring(command))
    end
end

-- ============================================
-- EXAMINATION DATA HANDLER
-- Receives other player's EHR data for examination
-- ============================================

local function OnExamServerCommand(module, command, args)
    if module ~= "EHR_Exam" then return end

    log("[EHR Client] Exam command received: " .. tostring(command))

    if command == "ExamDataResponse" then
        if not args then
            log("[EHR Client] ExamDataResponse: No args received")
            return
        end

        local targetUsername = args.targetUsername
        if not targetUsername then
            log("[EHR Client] ExamDataResponse: No targetUsername")
            return
        end

        if not args.success then
            -- Request failed
            log("[EHR Client] ExamDataResponse: Failed for " .. targetUsername .. " - " .. tostring(args.error))

            -- Notify MPExamination of failure
            if EHR.MPExamination and EHR.MPExamination.OnExamDataFailed then
                EHR.MPExamination.OnExamDataFailed(targetUsername, args.error)
            end
            return
        end

        -- Store exam data for display
        log("[EHR Client] ExamDataResponse: Received data for " .. targetUsername)

        -- Pass data to MPExamination module
        if EHR.MPExamination and EHR.MPExamination.OnExamDataReceived then
            EHR.MPExamination.OnExamDataReceived(targetUsername, args)
        else
            log("[EHR Client] WARNING: MPExamination.OnExamDataReceived not available")
        end
    end
end

-- Register handlers
log("[EHR Client] Registering OnServerCommand handlers...")
if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(OnServerCommand)
    Events.OnServerCommand.Add(OnExamServerCommand)
    log("[EHR Client] SUCCESS! Client commands registered!")
else
    log("[EHR Client] FAILED! Events.OnServerCommand not available!")
end
