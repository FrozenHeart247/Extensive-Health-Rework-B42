--[[
    Extensive Health Rework B42
    Medical Journal Data Module

    Tracks player diagnosis history, accuracy statistics, and treatment records.
    Data is stored in player ModData for persistence across saves.

    Features:
        - Diagnosis history with timestamps
        - Correct/incorrect diagnosis tracking
        - Treatment effectiveness records
        - Accuracy statistics and percentages
        - Per-disease breakdown

    v1.0.0
]]--

require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.MedicalJournal = {}

-- ============================================
-- CONSTANTS
-- ============================================

EHR.MedicalJournal.MAX_ENTRIES = 100  -- Maximum entries to keep
EHR.MedicalJournal.MODDATA_KEY = "EHR_MedicalJournal"

-- ============================================
-- INITIALIZATION
-- ============================================

--[[
    Initialize the Medical Journal for a player.
    Creates the data structure in ModData if it doesn't exist.

    @param player (IsoPlayer)
    @return table - The journal data
]]--
function EHR.MedicalJournal.Init(player)
    if not player then return nil end

    local modData = player:getModData()
    if not modData then return nil end

    if not modData[EHR.MedicalJournal.MODDATA_KEY] then
        modData[EHR.MedicalJournal.MODDATA_KEY] = {
            -- Diagnosis entries (array)
            entries = {},

            -- Treatment records (array)
            treatments = {},

            -- Aggregate statistics
            statistics = {
                totalDiagnoses = 0,
                correctDiagnoses = 0,
                wrongDiagnoses = 0,

                -- Per-disease tracking
                diseasesContracted = {},  -- {diseaseId = count}
                diseasesCured = {},       -- {diseaseId = count}

                -- Treatment tracking
                treatmentsApplied = {},   -- {treatmentId = {total, effective}}
            },

            -- Settings
            settings = {
                showNotifications = true,
                trackHistory = true,
            },

            -- Metadata
            createdTime = getGameTime():getWorldAgeHours(),
            lastUpdated = getGameTime():getWorldAgeHours(),
        }
    end

    return modData[EHR.MedicalJournal.MODDATA_KEY]
end

--[[
    Get the journal data for a player.
    @param player (IsoPlayer)
    @return table or nil
]]--
function EHR.MedicalJournal.GetJournal(player)
    if not player then return nil end

    local modData = player:getModData()
    if not modData then return nil end

    -- Auto-initialize if needed
    if not modData[EHR.MedicalJournal.MODDATA_KEY] then
        return EHR.MedicalJournal.Init(player)
    end

    return modData[EHR.MedicalJournal.MODDATA_KEY]
end

-- ============================================
-- DIAGNOSIS RECORDING
-- ============================================

--[[
    Record a diagnosis event.

    @param player (IsoPlayer)
    @param actualDisease (string) - The real disease ID
    @param stage (number) - Disease stage (1-4)
    @param diagnosedAs (string) - What the player diagnosed it as
    @param isCorrect (boolean) - Whether the diagnosis was correct
    @return boolean - True if recorded successfully
]]--
function EHR.MedicalJournal.RecordDiagnosis(player, actualDisease, stage, diagnosedAs, isCorrect)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal then return false end

    -- Check if tracking is enabled
    if not journal.settings.trackHistory then
        -- Still update statistics even if not tracking history
        EHR.MedicalJournal.UpdateStatistics(journal, actualDisease, isCorrect)
        return true
    end

    -- Get player skill info
    local effectiveSkill = 0
    local baseSkill = 0

    if EHR.MedicalSkill then
        effectiveSkill = EHR.MedicalSkill.GetEffectiveSkill(player, "disease")
        if player.getPerkLevel then
            local success, level = pcall(function()
                return player:getPerkLevel(Perks.Doctor)
            end)
            if success then
                baseSkill = level or 0
            end
        end
    end

    -- Create entry
    local entry = {
        -- Timing
        timestamp = getGameTime():getWorldAgeHours(),
        gameDay = getGameTime():getNightsSurvived() + 1,

        -- Disease info
        actualDisease = actualDisease,
        stage = stage,
        diagnosedAs = diagnosedAs,
        isCorrect = isCorrect,

        -- Player skill at time of diagnosis
        playerSkill = baseSkill,
        effectiveSkill = effectiveSkill,

        -- Entry type
        entryType = "diagnosis",
    }

    -- Add to entries (newest first)
    table.insert(journal.entries, 1, entry)

    -- Trim old entries if over limit
    while #journal.entries > EHR.MedicalJournal.MAX_ENTRIES do
        table.remove(journal.entries)
    end

    -- Update statistics
    EHR.MedicalJournal.UpdateStatistics(journal, actualDisease, isCorrect)

    -- Update timestamp
    journal.lastUpdated = getGameTime():getWorldAgeHours()

    if EHR.DEBUG then
        EHR.Log(string.format("Journal: Recorded diagnosis - %s (correct: %s)",
            diagnosedAs, tostring(isCorrect)))
    end

    -- Award First Aid XP for correct diagnosis
    if isCorrect and EHR.SkillXP and EHR.SkillXP.OnDiagnosis then
        EHR.SkillXP.OnDiagnosis(player, true)
    end

    return true
end

--[[
    Update aggregate statistics after a diagnosis.

    @param journal (table) - Journal data
    @param disease (string) - Disease ID
    @param isCorrect (boolean)
]]--
function EHR.MedicalJournal.UpdateStatistics(journal, disease, isCorrect)
    if not journal or not journal.statistics then return end

    local stats = journal.statistics

    -- Update totals
    stats.totalDiagnoses = (stats.totalDiagnoses or 0) + 1

    if isCorrect then
        stats.correctDiagnoses = (stats.correctDiagnoses or 0) + 1
    else
        stats.wrongDiagnoses = (stats.wrongDiagnoses or 0) + 1
    end

    -- Update per-disease tracking
    if not stats.diseasesContracted then
        stats.diseasesContracted = {}
    end

    if not stats.diseasesContracted[disease] then
        stats.diseasesContracted[disease] = 0
    end
    stats.diseasesContracted[disease] = stats.diseasesContracted[disease] + 1
end

-- ============================================
-- TREATMENT RECORDING
-- ============================================

--[[
    Record a treatment applied.

    @param player (IsoPlayer)
    @param disease (string) - Disease being treated
    @param treatment (string) - Treatment/medication used
    @param wasEffective (boolean) - Whether treatment was appropriate
    @return boolean
]]--
function EHR.MedicalJournal.RecordTreatment(player, disease, treatment, wasEffective)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal then return false end

    -- Create treatment record
    local record = {
        timestamp = getGameTime():getWorldAgeHours(),
        gameDay = getGameTime():getNightsSurvived() + 1,
        disease = disease,
        treatment = treatment,
        wasEffective = wasEffective,
        entryType = "treatment",
    }

    -- Add to treatments
    if not journal.treatments then
        journal.treatments = {}
    end
    table.insert(journal.treatments, 1, record)

    -- Trim old entries
    while #journal.treatments > EHR.MedicalJournal.MAX_ENTRIES do
        table.remove(journal.treatments)
    end

    -- Update treatment statistics
    local stats = journal.statistics
    if not stats.treatmentsApplied then
        stats.treatmentsApplied = {}
    end

    if not stats.treatmentsApplied[treatment] then
        stats.treatmentsApplied[treatment] = {total = 0, effective = 0}
    end

    stats.treatmentsApplied[treatment].total = stats.treatmentsApplied[treatment].total + 1
    if wasEffective then
        stats.treatmentsApplied[treatment].effective = stats.treatmentsApplied[treatment].effective + 1
    end

    -- Update timestamp
    journal.lastUpdated = getGameTime():getWorldAgeHours()

    return true
end

--[[
    Record a disease cure.

    @param player (IsoPlayer)
    @param disease (string) - Disease that was cured
]]--
function EHR.MedicalJournal.RecordCure(player, disease)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal then return end

    if type(journal.statistics) ~= "table" then
        journal.statistics = {}
    end
    local stats = journal.statistics

    if type(stats.diseasesCured) ~= "table" then
        stats.diseasesCured = {}
    end

    if not stats.diseasesCured[disease] then
        stats.diseasesCured[disease] = 0
    end
    stats.diseasesCured[disease] = stats.diseasesCured[disease] + 1

    journal.lastUpdated = getGameTime():getWorldAgeHours()
end

-- ============================================
-- DATA RETRIEVAL
-- ============================================

--[[
    Get all journal entries for a player.

    @param player (IsoPlayer)
    @param filter (table, optional) - Filter options:
        - disease (string): Filter by disease
        - correct (boolean): Filter by correct/incorrect
        - entryType (string): "diagnosis" or "treatment"
        - limit (number): Max entries to return
    @return table - Array of entries
]]--
function EHR.MedicalJournal.GetEntries(player, filter)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal or not journal.entries then
        return {}
    end

    if not filter then
        return journal.entries
    end

    -- Apply filters
    local filtered = {}
    for _, entry in ipairs(journal.entries) do
        local include = true

        -- Filter by disease
        if filter.disease and entry.actualDisease ~= filter.disease then
            include = false
        end

        -- Filter by correct/incorrect
        if filter.correct ~= nil and entry.isCorrect ~= filter.correct then
            include = false
        end

        -- Filter by entry type
        if filter.entryType and entry.entryType ~= filter.entryType then
            include = false
        end

        if include then
            table.insert(filtered, entry)
        end

        -- Check limit
        if filter.limit and #filtered >= filter.limit then
            break
        end
    end

    return filtered
end

--[[
    Get statistics for a player.
    @param player (IsoPlayer)
    @return table - Statistics data
]]--
function EHR.MedicalJournal.GetStatistics(player)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal or not journal.statistics then
        return {
            totalDiagnoses = 0,
            correctDiagnoses = 0,
            wrongDiagnoses = 0,
            diseasesContracted = {},
            diseasesCured = {},
            treatmentsApplied = {},
        }
    end

    return journal.statistics
end

--[[
    Calculate diagnosis accuracy percentage.
    @param player (IsoPlayer)
    @return number - Percentage (0-100)
]]--
function EHR.MedicalJournal.GetAccuracyPercent(player)
    local stats = EHR.MedicalJournal.GetStatistics(player)

    if stats.totalDiagnoses == 0 then
        return 0
    end

    return math.floor((stats.correctDiagnoses / stats.totalDiagnoses) * 100)
end

--[[
    Get summary data for UI display.
    @param player (IsoPlayer)
    @return table - Summary with key metrics
]]--
function EHR.MedicalJournal.GetSummary(player)
    local stats = EHR.MedicalJournal.GetStatistics(player)
    local journal = EHR.MedicalJournal.GetJournal(player)

    local totalDiseases = 0
    local totalCures = 0

    for _, count in pairs(stats.diseasesContracted or {}) do
        totalDiseases = totalDiseases + count
    end

    for _, count in pairs(stats.diseasesCured or {}) do
        totalCures = totalCures + count
    end

    return {
        totalDiagnoses = stats.totalDiagnoses or 0,
        correctDiagnoses = stats.correctDiagnoses or 0,
        wrongDiagnoses = stats.wrongDiagnoses or 0,
        accuracyPercent = EHR.MedicalJournal.GetAccuracyPercent(player),
        totalDiseases = totalDiseases,
        totalCures = totalCures,
        entryCount = journal and journal.entries and #journal.entries or 0,
        lastUpdated = journal and journal.lastUpdated or 0,
    }
end

-- ============================================
-- SETTINGS
-- ============================================

--[[
    Update journal settings.
    @param player (IsoPlayer)
    @param settingKey (string)
    @param value (any)
]]--
function EHR.MedicalJournal.SetSetting(player, settingKey, value)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal or not journal.settings then return end

    journal.settings[settingKey] = value
end

--[[
    Get a journal setting.
    @param player (IsoPlayer)
    @param settingKey (string)
    @return any
]]--
function EHR.MedicalJournal.GetSetting(player, settingKey)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal or not journal.settings then return nil end

    return journal.settings[settingKey]
end

-- ============================================
-- UTILITY
-- ============================================

--[[
    Clear all journal data for a player.
    Use with caution!

    @param player (IsoPlayer)
]]--
function EHR.MedicalJournal.ClearJournal(player)
    if not player then return end

    local modData = player:getModData()
    if modData then
        modData[EHR.MedicalJournal.MODDATA_KEY] = nil
        EHR.MedicalJournal.Init(player)
    end
end

--[[
    Export journal data to string (for debug/backup).
    @param player (IsoPlayer)
    @return string - JSON-like string representation
]]--
function EHR.MedicalJournal.ExportData(player)
    local journal = EHR.MedicalJournal.GetJournal(player)
    if not journal then return "{}" end

    -- Simple serialization (not true JSON but readable)
    local lines = {"{"}

    table.insert(lines, string.format('  "totalDiagnoses": %d,', journal.statistics.totalDiagnoses or 0))
    table.insert(lines, string.format('  "correctDiagnoses": %d,', journal.statistics.correctDiagnoses or 0))
    table.insert(lines, string.format('  "wrongDiagnoses": %d,', journal.statistics.wrongDiagnoses or 0))
    table.insert(lines, string.format('  "accuracyPercent": %d,', EHR.MedicalJournal.GetAccuracyPercent(player)))
    table.insert(lines, string.format('  "entryCount": %d', #journal.entries))

    table.insert(lines, "}")

    return table.concat(lines, "\n")
end

--[[
    Get the most recent entry.
    @param player (IsoPlayer)
    @return table or nil
]]--
function EHR.MedicalJournal.GetMostRecentEntry(player)
    local entries = EHR.MedicalJournal.GetEntries(player)
    if entries and #entries > 0 then
        return entries[1]
    end
    return nil
end

--[[
    Check if player has any journal entries.
    @param player (IsoPlayer)
    @return boolean
]]--
function EHR.MedicalJournal.HasEntries(player)
    local journal = EHR.MedicalJournal.GetJournal(player)
    return journal and journal.entries and #journal.entries > 0
end

-- ============================================
-- INITIALIZATION
-- ============================================

EHR.Log("MedicalJournal module loaded (diagnosis tracking)")
