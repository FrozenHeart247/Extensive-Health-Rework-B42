--[[
    Extensive Health Rework - multiplayer medication administration

    The doctor selects a medication from the EHR remote health panel. The
    patient approves that exact dose, the doctor performs a timed action, and
    the server owns the final validation, item consumption and EHR effects.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "TimedActions/ISBaseTimedAction"
require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Medication"
pcall(function() require "ExtensiveHealth/EHR_Blood" end)
pcall(function() require "ExtensiveHealth/EHR_Transfusion" end)
pcall(function() require "ExtensiveHealth/EHR_MedicationAction" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.MPMedication = EHR.MPMedication or {}

EHR_AdministerMedicationUI = ISPanel:derive("EHR_AdministerMedicationUI")
EHR_AdministerMedicationAction = ISBaseTimedAction:derive("EHR_AdministerMedicationAction")

local WINDOW_W = 560
local WINDOW_H = 500
local PADDING = 14
local HEADER_H = 42
local FOOTER_H = 82

local Colors = {
    background = { r = 0.025, g = 0.025, b = 0.028, a = 0.98 },
    panel = { r = 0.055, g = 0.055, b = 0.060, a = 0.96 },
    panelAlt = { r = 0.085, g = 0.045, b = 0.045, a = 0.88 },
    border = { r = 0.66, g = 0.10, b = 0.08, a = 1.0 },
    text = { r = 0.92, g = 0.91, b = 0.86, a = 1.0 },
    textDim = { r = 0.64, g = 0.64, b = 0.64, a = 1.0 },
    green = { r = 0.22, g = 0.88, b = 0.30, a = 1.0 },
    yellow = { r = 0.95, g = 0.74, b = 0.18, a = 1.0 },
    red = { r = 0.90, g = 0.08, b = 0.06, a = 1.0 },
}

local function mpMedText(key, fallback)
    local fullKey = "UI_EHR_MPMedication_" .. tostring(key)
    if EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text(fullKey, fallback)
    end
    if getText then
        local ok, value = pcall(getText, fullKey)
        if ok and value and value ~= fullKey then return value end
    end
    return fallback
end

local function mpMedFormat(key, fallback, ...)
    local fullKey = "UI_EHR_MPMedication_" .. tostring(key)
    if EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format(fullKey, fallback, ...)
    end
    local text = mpMedText(key, fallback)
    local values = {...}
    for i, value in ipairs(values) do
        local replacement = tostring(value)
        text = tostring(text):gsub("%%" .. tostring(i) .. "%$[%a]", function() return replacement end)
        text = tostring(text):gsub("%%" .. tostring(i), function() return replacement end)
    end
    return text
end

local function getPlayerUsernameSafe(player)
    if not player then return nil end
    local value = nil
    pcall(function() value = player:getUsername() end)
    return value and tostring(value) or nil
end

local function getPlayerDisplayNameSafe(player)
    if not player then return mpMedText("UnknownPlayer", "Unknown player") end
    local value = nil
    pcall(function() value = player:getDisplayName() end)
    if value and tostring(value) ~= "" then return tostring(value) end
    return getPlayerUsernameSafe(player) or mpMedText("UnknownPlayer", "Unknown player")
end

local function getPlayerOnlineIDSafe(player)
    if not player then return nil end
    local value = nil
    pcall(function() value = player:getOnlineID() end)
    return value
end

local function playersAreClose(doctor, patient)
    if not doctor or not patient then return false end
    if doctor == patient then return true end

    local ok, close = pcall(function()
        if doctor.getVehicle and patient.getVehicle then
            local vehicle = doctor:getVehicle()
            if vehicle and vehicle == patient:getVehicle() then return true end
        end
        if math.abs((doctor:getZ() or 0) - (patient:getZ() or 0)) > 0.1 then return false end
        local dx = (doctor:getX() or 0) - (patient:getX() or 0)
        local dy = (doctor:getY() or 0) - (patient:getY() or 0)
        return (dx * dx + dy * dy) <= 9
    end)
    return ok and close == true
end

local function visitInventory(container, callback, visited)
    if not container or not container.getItems then return end
    visited = visited or {}
    if visited[container] then return end
    visited[container] = true

    local items = container:getItems()
    if not items or not items.size then return end
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            callback(item)
            if item.getInventory then
                local ok, nested = pcall(function() return item:getInventory() end)
                if ok and nested then visitInventory(nested, callback, visited) end
            end
        end
    end
end

local function findInventoryItemByID(player, itemID)
    if not player or itemID == nil then return nil end
    local found = nil
    visitInventory(player:getInventory(), function(item)
        if found or not item.getID then return end
        local ok, currentID = pcall(function() return item:getID() end)
        if ok and tostring(currentID) == tostring(itemID) then found = item end
    end)
    return found
end

local function localizedText(fullKey, fallback)
    if EHR.Locale and EHR.Locale.Text then
        local ok, value = pcall(EHR.Locale.Text, fullKey, fallback)
        if ok and value then return tostring(value) end
    end
    if getText then
        local ok, value = pcall(getText, fullKey)
        if ok and value and value ~= fullKey then return tostring(value) end
    end
    return fallback
end

local function getItemDisplayName(item, fallback)
    local displayName = nil
    if item and item.getDisplayName then
        pcall(function() displayName = item:getDisplayName() end)
    end
    return tostring(displayName or fallback or "Unknown item")
end

local function isBloodBagFullType(fullType)
    return fullType ~= nil
        and EHR.Blood ~= nil
        and EHR.Blood.BloodBagTypes ~= nil
        and EHR.Blood.BloodBagTypes[fullType] ~= nil
end

local function getBloodBagSpoilageState(item)
    if not item then return "rotten" end
    if EHR.Transfusion and EHR.Transfusion.GetSpoilageState then
        local ok, state = pcall(EHR.Transfusion.GetSpoilageState, item)
        if ok and (state == "fresh" or state == "stale" or state == "rotten") then
            return state
        end
    end
    return "fresh"
end

local BLOOD_SPOILAGE_RANK = { fresh = 1, stale = 2, rotten = 3 }

local function getMoreSevereBloodSpoilageState(first, second)
    local firstRank = BLOOD_SPOILAGE_RANK[first] or 0
    local secondRank = BLOOD_SPOILAGE_RANK[second] or 0
    if secondRank > firstRank then return second end
    if firstRank > 0 then return first end
    return second
end

local function updateBloodBagEntryState(entry, item)
    local state = getBloodBagSpoilageState(item or (entry and entry.item))
    if not entry then return state end

    entry.spoilageState = state
    entry.unavailableReason = nil
    local baseName = tostring(entry.baseName or entry.name or entry.fullType)
    if state == "stale" then
        entry.name = baseName .. " - "
            .. localizedText("UI_EHR_Transfusion_StaleSuffix", "STALE!")
    elseif state == "rotten" then
        entry.name = baseName .. " - "
            .. localizedText("UI_EHR_Transfusion_Unusable", "UNUSABLE")
        entry.unavailableReason = localizedText(
            "UI_EHR_Transfusion_BloodSpoiledDesc",
            "This blood bag has completely spoiled and cannot be used."
        )
    else
        entry.name = baseName
    end
    return state
end

local function getMedicationDisplayName(fullType, medData, item)
    if EHR.Medication and EHR.Medication.GetDisplayName then
        local ok, value = pcall(EHR.Medication.GetDisplayName, fullType, medData)
        if ok and value then return tostring(value) end
    end
    local displayName = medData and medData.displayName or nil
    if not displayName and item and item.getDisplayName then
        pcall(function() displayName = item:getDisplayName() end)
    end
    return tostring(displayName or fullType)
end

local function getAdminType(medData)
    if EHR.MedicationAction and EHR.MedicationAction.GetAdminType then
        local ok, result = pcall(EHR.MedicationAction.GetAdminType, medData)
        if ok and result then return tostring(result) end
    end
    if medData and medData.requiresIVKit then return "iv" end
    if medData and medData.isEmergency then return "emergency" end
    if medData and medData.requiresSyringe then return "injection" end
    if medData and medData.isTopical then return "cream" end
    return "pill"
end

local function getAdminTypeLabel(adminType)
    local labels = {
        pill = "Oral",
        tablet = "Oral",
        capsule = "Oral",
        liquid = "Oral liquid",
        cream = "Topical",
        ointment = "Topical",
        inhaler = "Inhaled",
        injection = "Injection",
        iv = "IV",
        emergency = "Emergency",
        default = "Other",
    }
    return mpMedText("Route_" .. tostring(adminType), labels[adminType] or labels.default)
end

local function getItemDoseCount(item)
    if EHR.Medication and EHR.Medication.GetItemDoseInfo then
        local ok, info = pcall(EHR.Medication.GetItemDoseInfo, item)
        if ok and info then return math.max(0, tonumber(info.remainingDoses) or 0) end
    end
    return 1
end

local function getRequestTargetArgs(patient)
    return {
        targetUsername = getPlayerUsernameSafe(patient),
        targetOnlineID = getPlayerOnlineIDSafe(patient),
    }
end

function EHR.MPMedication.GetInventoryMedications(doctor)
    local grouped = {}
    local bloodEntries = {}
    local inventory = doctor and doctor:getInventory() or nil
    if not inventory or not EHR.Medication or not EHR.Medication.Database then return {} end

    visitInventory(inventory, function(item)
        local fullType = item.getFullType and item:getFullType() or nil
        if isBloodBagFullType(fullType) then
            local baseName = getItemDisplayName(item, fullType)
            local entry = {
                fullType = fullType,
                item = item,
                itemID = item:getID(),
                baseName = baseName,
                name = baseName,
                adminType = "iv",
                treatmentKind = "blood_transfusion",
                requiresIVKit = true,
                doses = 1,
            }
            updateBloodBagEntryState(entry, item)
            table.insert(bloodEntries, entry)
            return
        end

        local medData = fullType and EHR.Medication.Database[fullType] or nil
        if not medData or medData.remoteAdministration == false then return end

        local doses = getItemDoseCount(item)
        if doses <= 0 then return end

        local entry = grouped[fullType]
        if not entry then
            entry = {
                fullType = fullType,
                medData = medData,
                item = item,
                itemID = item:getID(),
                name = getMedicationDisplayName(fullType, medData, item),
                adminType = getAdminType(medData),
                treatmentKind = "medication",
                doses = 0,
            }
            grouped[fullType] = entry
        end
        entry.doses = entry.doses + doses
    end)

    local entries = {}
    for _, entry in pairs(grouped) do table.insert(entries, entry) end
    for _, entry in ipairs(bloodEntries) do table.insert(entries, entry) end
    table.sort(entries, function(a, b)
        local aName = string.lower(tostring(a.name or a.fullType))
        local bName = string.lower(tostring(b.name or b.fullType))
        if aName == bName then
            local aType = tostring(a.fullType)
            local bType = tostring(b.fullType)
            if aType == bType then return tostring(a.itemID or "") < tostring(b.itemID or "") end
            return aType < bType
        end
        return aName < bName
    end)
    return entries
end

function EHR_AdministerMedicationUI:new(x, y, doctor, patient, ownerPanel)
    local o = ISPanel:new(x, y, WINDOW_W, WINDOW_H)
    setmetatable(o, self)
    self.__index = self
    o.doctor = doctor
    o.patient = patient
    o.ownerPanel = ownerPanel
    o.backgroundColor = Colors.background
    o.borderColor = Colors.border
    o.moveWithMouse = true
    o.pendingRequestId = nil
    o.statusText = ""
    return o
end

function EHR_AdministerMedicationUI:initialise()
    ISPanel.initialise(self)
end

function EHR_AdministerMedicationUI:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = ISButton:new(self.width - 34, 9, 24, 24, "X", self, EHR_AdministerMedicationUI.onClose)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton.borderColor = Colors.border
    self:addChild(self.closeButton)

    self.medicationList = ISScrollingListBox:new(PADDING, HEADER_H + 38, self.width - PADDING * 2, self.height - HEADER_H - FOOTER_H - 46)
    self.medicationList:initialise()
    self.medicationList:instantiate()
    self.medicationList.itemheight = 48
    self.medicationList.font = UIFont.Small
    self.medicationList.doDrawItem = EHR_AdministerMedicationUI.drawMedicationItem
    self.medicationList.drawBorder = true
    self.medicationList.parentUI = self
    self:addChild(self.medicationList)

    self.administerButton = ISButton:new(self.width - PADDING - 190, self.height - 48, 190, 32,
        mpMedText("Administer", "Administer Medication"), self, EHR_AdministerMedicationUI.onAdminister)
    self.administerButton:initialise()
    self.administerButton:instantiate()
    self.administerButton.borderColor = Colors.border
    self:addChild(self.administerButton)

    self.cancelButton = ISButton:new(PADDING, self.height - 48, 112, 32,
        mpMedText("Cancel", "Cancel"), self, EHR_AdministerMedicationUI.onClose)
    self.cancelButton:initialise()
    self.cancelButton:instantiate()
    self.cancelButton.borderColor = Colors.border
    self:addChild(self.cancelButton)

    self:refreshMedications()
end

function EHR_AdministerMedicationUI:refreshMedications()
    if not self.medicationList then return end
    self.medicationList:clear()
    self.entries = EHR.MPMedication.GetInventoryMedications(self.doctor)
    for _, entry in ipairs(self.entries) do
        self.medicationList:addItem(entry.name, entry)
    end
    if #self.entries > 0 then
        self.medicationList.selected = math.max(1, math.min(self.medicationList.selected or 1, #self.entries))
        self.statusText = ""
    else
        self.statusText = mpMedText("NoMedication", "No recognized medications in your inventory.")
    end
    self:updateAdministerButton()
end

function EHR_AdministerMedicationUI:getSelectedMedication()
    if not self.medicationList or not self.medicationList.items then return nil end
    local selected = tonumber(self.medicationList.selected) or 0
    local row = self.medicationList.items[selected]
    return row and row.item or nil
end

function EHR_AdministerMedicationUI:getSelectedRequirementFailure(entry)
    if not entry then return nil end

    if entry.treatmentKind == "blood_transfusion" then
        local currentItem = findInventoryItemByID(self.doctor, entry.itemID)
        if not currentItem or not currentItem.getFullType or currentItem:getFullType() ~= entry.fullType then
            return mpMedText("ItemMissing", "Medication or patient is no longer available.")
        end
        entry.item = currentItem
        updateBloodBagEntryState(entry, currentItem)
        if entry.unavailableReason then return entry.unavailableReason end
    elseif entry.unavailableReason then
        return entry.unavailableReason
    end

    local medData = entry.medData
    if (entry.requiresIVKit or (medData and medData.requiresIVKit))
            and not EHR.Medication.FindMedicalSupply(self.doctor, "IVKit") then
        return mpMedText("RequiresIVKit", "Requires IV Administration Kit")
    end
    if medData and medData.requiresSyringe
            and not EHR.Medication.FindMedicalSupply(self.doctor, "Syringe") then
        return mpMedText("RequiresSyringe", "Requires a syringe (sterile or homemade)")
    end
    return nil
end

function EHR_AdministerMedicationUI:updateAdministerButton()
    if not self.administerButton then return end
    local selected = self:getSelectedMedication()
    local requirementFailure = self:getSelectedRequirementFailure(selected)
    local available = selected ~= nil and self.pendingRequestId == nil and requirementFailure == nil
    self.administerButton:setEnable(available)
end

function EHR_AdministerMedicationUI:drawMedicationItem(y, item, alt)
    local entry = item and item.item or nil
    local selected = self.selected == item.index
    local color = selected and Colors.panelAlt or Colors.panel
    self:drawRect(0, y, self:getWidth(), self.itemheight - 1, color.a, color.r, color.g, color.b)
    if selected then
        self:drawRectBorder(0, y, self:getWidth(), self.itemheight - 1, Colors.border.a, Colors.border.r, Colors.border.g, Colors.border.b)
    end

    if entry then
        self:drawText(tostring(entry.name), 10, y + 5, Colors.text.r, Colors.text.g, Colors.text.b, Colors.text.a, UIFont.Medium)
        local detail = mpMedFormat("ListDetail", "Route: %1  |  Doses: %2",
            getAdminTypeLabel(entry.adminType), tostring(entry.doses or 0))
        self:drawText(detail, 12, y + 27, Colors.textDim.r, Colors.textDim.g, Colors.textDim.b, Colors.textDim.a, UIFont.Small)
    end
    return y + self.itemheight
end

function EHR_AdministerMedicationUI:prerender()
    ISPanel.prerender(self)

    if self.pendingRequestId and self.pendingStartedMs and getTimestampMs
            and (getTimestampMs() - self.pendingStartedMs) > 50000 then
        local expiredRequestId = self.pendingRequestId
        local args = getRequestTargetArgs(self.patient)
        args.requestId = expiredRequestId
        sendClientCommand(self.doctor, "EHR", "CancelAdministerMedicationRequest", args)
        if EHR.MPMedication.PendingDoctorRequests then
            EHR.MPMedication.PendingDoctorRequests[expiredRequestId] = nil
        end
        self.pendingRequestId = nil
        self.pendingStartedMs = nil
        self.statusText = mpMedText("ConsentExpired", "Medication consent request expired.")
    end
    self:updateAdministerButton()

    self:drawRect(0, 0, self.width, self.height, Colors.background.a, Colors.background.r, Colors.background.g, Colors.background.b)
    self:drawRectBorder(0, 0, self.width, self.height, Colors.border.a, Colors.border.r, Colors.border.g, Colors.border.b)
    self:drawRect(0, 0, self.width, HEADER_H, 0.95, 0.035, 0.035, 0.038)
    self:drawText(mpMedText("Title", "ADMINISTER MEDICATION"), 14, 8,
        Colors.text.r, Colors.text.g, Colors.text.b, Colors.text.a, UIFont.Large)

    local patientText = mpMedFormat("Patient", "Patient: %1", getPlayerDisplayNameSafe(self.patient))
    self:drawText(patientText, PADDING, HEADER_H + 8,
        Colors.textDim.r, Colors.textDim.g, Colors.textDim.b, Colors.textDim.a, UIFont.Small)

    local selected = self:getSelectedMedication()
    local requirementFailure = self:getSelectedRequirementFailure(selected)
    local footerText = self.statusText
    local footerColor = Colors.yellow
    if self.pendingRequestId then
        footerText = mpMedText("WaitingConsent", "Waiting for patient approval...")
    elseif requirementFailure then
        footerText = requirementFailure
        footerColor = Colors.red
    elseif footerText and footerText ~= "" then
        footerColor = Colors.yellow
    elseif selected then
        footerText = mpMedFormat("Selected", "Selected: %1", selected.name)
        footerColor = Colors.textDim
    end
    if footerText and footerText ~= "" then
        self:drawText(footerText, PADDING, self.height - 74,
            footerColor.r, footerColor.g, footerColor.b, footerColor.a, UIFont.Small)
    end
end

function EHR_AdministerMedicationUI:onAdminister()
    if self.pendingRequestId then return end
    local entry = self:getSelectedMedication()
    if not entry then return end

    local requirementFailure = self:getSelectedRequirementFailure(entry)
    if requirementFailure then
        self.statusText = requirementFailure
        self:updateAdministerButton()
        return
    end
    if not playersAreClose(self.doctor, self.patient) then
        self.statusText = mpMedText("TooFar", "Patient is too far away.")
        return
    end

    EHR.MPMedication.NextRequestId = ((tonumber(EHR.MPMedication.NextRequestId) or 0) % 1000000000) + 1
    local requestId = EHR.MPMedication.NextRequestId
    local args = getRequestTargetArgs(self.patient)
    args.requestId = requestId
    args.itemID = entry.itemID
    args.itemFullType = entry.fullType
    args.treatmentKind = entry.treatmentKind or "medication"
    args.spoilageState = entry.treatmentKind == "blood_transfusion"
        and getBloodBagSpoilageState(entry.item) or nil

    self.pendingRequestId = requestId
    self.pendingStartedMs = getTimestampMs and getTimestampMs() or nil
    EHR.MPMedication.PendingDoctorRequests = EHR.MPMedication.PendingDoctorRequests or {}
    EHR.MPMedication.PendingDoctorRequests[requestId] = {
        window = self,
        doctor = self.doctor,
        patient = self.patient,
        itemID = entry.itemID,
        itemFullType = entry.fullType,
        treatmentKind = args.treatmentKind,
        spoilageState = args.spoilageState,
    }
    self.statusText = mpMedText("WaitingConsent", "Waiting for patient approval...")
    self:updateAdministerButton()

    sendClientCommand(self.doctor, "EHR", "RequestAdministerMedication", args)
end

function EHR_AdministerMedicationUI:onClose()
    if self.pendingRequestId then
        local requestId = self.pendingRequestId
        local args = getRequestTargetArgs(self.patient)
        args.requestId = requestId
        sendClientCommand(self.doctor, "EHR", "CancelAdministerMedicationRequest", args)
        if EHR.MPMedication.PendingDoctorRequests then
            EHR.MPMedication.PendingDoctorRequests[requestId] = nil
        end
        self.pendingRequestId = nil
        self.pendingStartedMs = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if EHR.MPMedication.ActiveWindow == self then EHR.MPMedication.ActiveWindow = nil end
end

function EHR.MPMedication.Open(ownerPanel, doctor, patient)
    if not doctor or not patient then return nil end
    if EHR.MPMedication.ActiveWindow then
        pcall(function() EHR.MPMedication.ActiveWindow:onClose() end)
    end

    local core = getCore and getCore()
    local screenW = core and core:getScreenWidth() or 1280
    local screenH = core and core:getScreenHeight() or 720
    local window = EHR_AdministerMedicationUI:new(
        math.max(0, math.floor((screenW - WINDOW_W) / 2)),
        math.max(0, math.floor((screenH - WINDOW_H) / 2)),
        doctor, patient, ownerPanel
    )
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    window:bringToTop()
    EHR.MPMedication.ActiveWindow = window
    return window
end

function EHR.MPMedication.CloseForPanel(ownerPanel)
    local window = EHR.MPMedication.ActiveWindow
    if not window or window.ownerPanel ~= ownerPanel then return end
    pcall(function() window:onClose() end)
end

function EHR_AdministerMedicationAction:isValid()
    if not self.character or not self.patient or not self.item then return false end
    if self.character.isAlive and not self.character:isAlive() then return false end
    if self.patient.isAlive and not self.patient:isAlive() then return false end
    if not playersAreClose(self.character, self.patient) then return false end
    local item = findInventoryItemByID(self.character, self.itemID)
    if not item or not item.getFullType or item:getFullType() ~= self.itemFullType then return false end
    if self.treatmentKind == "blood_transfusion" then
        if not EHR.Medication.FindMedicalSupply(self.character, "IVKit") then return false end
        if getBloodBagSpoilageState(item) == "rotten" then return false end
    end
    self.item = item
    return true
end

function EHR_AdministerMedicationAction:update()
    if self.item and self.item.setJobDelta then self.item:setJobDelta(self:getJobDelta()) end
    if self.character.faceThisObject then pcall(function() self.character:faceThisObject(self.patient) end) end
end

function EHR_AdministerMedicationAction:start()
    local resolved = findInventoryItemByID(self.character, self.itemID)
    if resolved then self.item = resolved end
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Mid")
    self.character:reportEvent("EventLootItem")
    self:setOverrideHandModels(nil, nil)
    if self.item and self.item.setJobType then
        self.item:setJobType(mpMedFormat("Job", "Administering %1", self.medicationName))
    end
    if self.item and self.item.setJobDelta then self.item:setJobDelta(0.0) end
    if self.adminType == "iv" or self.adminType == "injection" then
        self.character:setMetabolicTarget(Metabolics.HeavyWork)
    else
        self.character:setMetabolicTarget(Metabolics.LightWork)
    end
end

function EHR_AdministerMedicationAction:stop()
    if self.item and self.item.setJobDelta then self.item:setJobDelta(0.0) end
    if not self.completionRequested and isClient and isClient() then
        sendClientCommand(self.character, "EHR", "CancelAdministerMedication", { actionId = self.actionId })
    end
    ISBaseTimedAction.stop(self)
end

function EHR_AdministerMedicationAction:perform()
    if self.item and self.item.setJobDelta then self.item:setJobDelta(0.0) end
    if not self.completionRequested then
        self.completionRequested = true
        local spoilageState = self.spoilageState
        if self.treatmentKind == "blood_transfusion" then
            spoilageState = getMoreSevereBloodSpoilageState(
                spoilageState,
                getBloodBagSpoilageState(self.item)
            )
        end
        sendClientCommand(self.character, "EHR", "CompleteAdministerMedication", {
            actionId = self.actionId,
            itemID = self.itemID,
            itemFullType = self.itemFullType,
            treatmentKind = self.treatmentKind,
            spoilageState = spoilageState,
        })
    end
    ISBaseTimedAction.perform(self)
end

function EHR_AdministerMedicationAction:new(doctor, patient, item, args)
    local o = ISBaseTimedAction.new(self, doctor)
    o.character = doctor
    o.patient = patient
    o.item = item
    o.itemID = args.itemID
    o.itemFullType = args.itemFullType
    o.actionId = args.actionId
    o.medicationName = args.medicationName or args.itemFullType
    o.adminType = tostring(args.adminType or "default")
    o.treatmentKind = tostring(args.treatmentKind or "medication")
    o.spoilageState = args.spoilageState
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    local times = EHR.MedicationAction and EHR.MedicationAction.Times or nil
    o.maxTime = times and (times[o.adminType] or times.default) or 120
    o.completionRequested = false
    return o
end

local function resolveOnlinePlayer(onlineID, username)
    local player = nil
    if onlineID ~= nil and getPlayerByOnlineID then
        pcall(function() player = getPlayerByOnlineID(tonumber(onlineID)) end)
    end
    if player then return player end
    if getOnlinePlayers then
        local online = getOnlinePlayers()
        if online then
            for i = 0, online:size() - 1 do
                local candidate = online:get(i)
                if candidate and getPlayerUsernameSafe(candidate) == tostring(username) then return candidate end
            end
        end
    end
    return nil
end

function EHR.MPMedication.OnConsentModal(_, button, request)
    if not request then return end
    local patient = getPlayer and getPlayer() or nil
    if not patient then return end
    local accepted = button and button.internal == "YES"
    sendClientCommand(patient, "EHR", "RespondAdministerMedicationConsent", {
        requestId = request.requestId,
        doctorOnlineID = request.doctorOnlineID,
        doctorUsername = request.doctorUsername,
        itemID = request.itemID,
        itemFullType = request.itemFullType,
        treatmentKind = request.treatmentKind,
        spoilageState = request.spoilageState,
        accepted = accepted,
    })
    EHR.MPMedication.ActiveConsentModal = nil
end

function EHR.MPMedication.OnConsentRequest(args)
    if type(args) ~= "table" or args.requestId == nil then return end
    local patient = getPlayer and getPlayer() or nil
    if not patient then return end

    if EHR.MPMedication.ActiveConsentModal then
        pcall(function()
            local modal = EHR.MPMedication.ActiveConsentModal
            if modal.destroy then
                modal:destroy()
            else
                modal:setVisible(false)
                modal:removeFromUIManager()
            end
        end)
        EHR.MPMedication.ActiveConsentModal = nil
    end

    local doctorName = tostring(args.doctorDisplayName or args.doctorUsername or mpMedText("UnknownPlayer", "Unknown player"))
    local medicationName = tostring(args.medicationName or args.itemFullType or mpMedText("UnknownMedication", "Unknown medication"))
    local message = nil
    if args.treatmentKind == "blood_transfusion" then
        message = mpMedFormat("ConsentPromptProcedure", "%1 wants to perform:\n%2\n\nAllow this procedure?", doctorName, medicationName)
    else
        message = mpMedFormat("ConsentPrompt", "%1 wants to administer:\n%2\n\nAllow this dose?", doctorName, medicationName)
    end
    local core = getCore()
    local modal = ISModalDialog:new(
        math.floor(core:getScreenWidth() / 2 - 190),
        math.floor(core:getScreenHeight() / 2 - 75),
        380, 150, message, true, nil,
        EHR.MPMedication.OnConsentModal,
        patient:getPlayerNum(), args
    )
    modal:initialise()
    modal:addToUIManager()
    modal.ehrMedicationRequestId = tonumber(args.requestId)
    EHR.MPMedication.ActiveConsentModal = modal
end

function EHR.MPMedication.OnConsentCancelled(args)
    local modal = EHR.MPMedication.ActiveConsentModal
    if not modal then return end
    if args and args.requestId and tonumber(args.requestId) ~= tonumber(modal.ehrMedicationRequestId) then return end
    pcall(function()
        if modal.destroy then
            modal:destroy()
        else
            modal:setVisible(false)
            modal:removeFromUIManager()
        end
    end)
    EHR.MPMedication.ActiveConsentModal = nil
end

function EHR.MPMedication.OnConsentGranted(args)
    if type(args) ~= "table" then return end
    local doctor = getPlayer and getPlayer() or nil
    if not doctor then return end
    local pending = EHR.MPMedication.PendingDoctorRequests and EHR.MPMedication.PendingDoctorRequests[tonumber(args.requestId)] or nil
    if not pending then return end

    local itemID = args.itemID or pending.itemID
    local itemFullType = args.itemFullType or pending.itemFullType
    local treatmentKind = tostring(args.treatmentKind or pending.treatmentKind or "medication")
    local exactGrant = tostring(itemID) == tostring(pending.itemID)
        and tostring(itemFullType) == tostring(pending.itemFullType)
        and treatmentKind == tostring(pending.treatmentKind or "medication")
    local item = exactGrant and findInventoryItemByID(doctor, itemID) or nil
    local patient = resolveOnlinePlayer(args.targetOnlineID, args.targetUsername) or pending.patient
    local actualFullType = item and item.getFullType and item:getFullType() or nil
    if not item or actualFullType ~= itemFullType or not patient then
        if pending.window then
            pending.window.statusText = mpMedText("ItemMissing", "Medication or patient is no longer available.")
            pending.window.pendingRequestId = nil
            pending.window.pendingStartedMs = nil
        end
        EHR.MPMedication.PendingDoctorRequests[tonumber(args.requestId)] = nil
        return
    end

    args.itemID = itemID
    args.itemFullType = itemFullType
    args.treatmentKind = treatmentKind
    if treatmentKind == "blood_transfusion" then
        args.spoilageState = getMoreSevereBloodSpoilageState(
            args.spoilageState or pending.spoilageState,
            getBloodBagSpoilageState(item)
        )
    end

    if pending.window then
        pending.window.pendingRequestId = nil
        pending.window.pendingStartedMs = nil
        pending.window.statusText = mpMedText("ConsentGranted", "Patient approved the dose. Administration started.")
        pending.window:updateAdministerButton()
    end
    EHR.MPMedication.PendingDoctorRequests[tonumber(args.requestId)] = nil
    ISTimedActionQueue.add(EHR_AdministerMedicationAction:new(doctor, patient, item, args))
end

function EHR.MPMedication.OnRequestRejected(args)
    if type(args) ~= "table" then return end
    local requestId = tonumber(args.requestId)
    local pending = requestId and EHR.MPMedication.PendingDoctorRequests and EHR.MPMedication.PendingDoctorRequests[requestId] or nil
    if pending and pending.window then
        pending.window.pendingRequestId = nil
        pending.window.pendingStartedMs = nil
        pending.window:refreshMedications()
        pending.window.statusText = tostring(args.reason or mpMedText("Rejected", "Administration request rejected."))
    end
    if requestId and EHR.MPMedication.PendingDoctorRequests then
        EHR.MPMedication.PendingDoctorRequests[requestId] = nil
    end
end

function EHR.MPMedication.OnAdministerResult(args)
    if type(args) ~= "table" then return end
    local player = getPlayer and getPlayer() or nil
    if not player then return end

    local message = tostring(args.message or (args.success
        and mpMedText("Success", "Medication administered.")
        or mpMedText("Failed", "Medication administration failed.")))
    if EHR.Locale and EHR.Locale.Say then
        EHR.Locale.Say(player, message)
    elseif player.Say then
        player:Say(message)
    end

    local window = EHR.MPMedication.ActiveWindow
    if window and window.doctor == player then
        window.pendingRequestId = nil
        window.pendingStartedMs = nil
        window:refreshMedications()
        window.statusText = message
    end

    if args.success and args.role == "doctor" and EHR.MPExamination and EHR.MPExamination.RequestExamData then
        local patient = resolveOnlinePlayer(args.targetOnlineID, args.targetUsername)
        if patient then EHR.MPExamination.RequestExamData(player, patient, true, true) end
    end
end

local function OnServerCommand(module, command, args)
    if module ~= "EHR_Exam" then return end
    if command == "MedicationConsentRequest" then
        EHR.MPMedication.OnConsentRequest(args)
    elseif command == "MedicationConsentGranted" then
        EHR.MPMedication.OnConsentGranted(args)
    elseif command == "MedicationRequestRejected" or command == "MedicationConsentDenied" then
        EHR.MPMedication.OnRequestRejected(args)
    elseif command == "MedicationConsentCancelled" then
        EHR.MPMedication.OnConsentCancelled(args)
    elseif command == "MedicationAdministerResult" then
        EHR.MPMedication.OnAdministerResult(args)
    end
end

if Events and Events.OnServerCommand and not EHR.MPMedication._serverCommandRegistered then
    EHR.MPMedication._serverCommandRegistered = true
    Events.OnServerCommand.Add(OnServerCommand)
end
