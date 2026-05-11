--[[
    Extensive Health Rework B42
    Disease Handbook UI

    Replaces the old diagnosis-history journal with a compact disease codex.
    The data journal still exists for persistence/statistics, but J opens this UI.
]]--

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_DiseaseFlyers"

EHR_MedicalJournalUI = ISPanel:derive("EHR_MedicalJournalUI")
EHR_MedicalJournalUI.instance = nil

local WINDOW_WIDTH = 900
local WINDOW_HEIGHT = 640
local PADDING = 14
local HEADER_HEIGHT = 42
local LIST_WIDTH = 326

local Colors = {
    bg = { r = 0.015, g = 0.014, b = 0.014, a = 0.96 },
    panel = { r = 0.035, g = 0.035, b = 0.038, a = 0.88 },
    panelSoft = { r = 0.075, g = 0.025, b = 0.025, a = 0.62 },
    header = { r = 0.09, g = 0.012, b = 0.012, a = 0.96 },
    red = { r = 0.95, g = 0.08, b = 0.07, a = 1.0 },
    redDark = { r = 0.34, g = 0.015, b = 0.015, a = 1.0 },
    orange = { r = 1.0, g = 0.38, b = 0.12, a = 1.0 },
    green = { r = 0.18, g = 0.92, b = 0.32, a = 1.0 },
    cyan = { r = 0.22, g = 0.82, b = 1.0, a = 1.0 },
    yellow = { r = 1.0, g = 0.78, b = 0.12, a = 1.0 },
    text = { r = 0.90, g = 0.88, b = 0.82, a = 1.0 },
    textDim = { r = 0.62, g = 0.60, b = 0.58, a = 1.0 },
    border = { r = 0.78, g = 0.05, b = 0.04, a = 0.88 },
    borderDim = { r = 0.42, g = 0.04, b = 0.035, a = 0.74 },
}

local DiseaseIcons = {
    unknown = "media/textures/EHR_Disease_Unknown.png",
    cadaveric_aspergillosis = "media/textures/EHR_Disease_CadavericAspergillosis.png",
    cellulitis = "media/textures/EHR_Disease_Wound_Infection.png",
    common_cold = "media/textures/EHR_Disease_CommonCold.png",
    corpse_sickness = "media/textures/EHR_Disease_CorpseSickness.png",
    dysentery = "media/textures/EHR_Disease_Dysentery.png",
    food_poisoning = "media/textures/EHR_Disease_FoodPoisoning.png",
    gastroenteritis = "media/textures/EHR_Disease_Gastroenteritis.png",
    heat_exhaustion = "media/textures/EHR_Disease_HeatExhaustion.png",
    heat_stroke = "media/textures/EHR_Disease_HeatStroke.png",
    hypothermia = "media/textures/EHR_Disease_Hypotermia.png",
    pneumonia = "media/textures/EHR_Disease_Pneumonia.png",
    sepsis = "media/textures/EHR_Disease_Sepsis.png",
    tetanus = "media/textures/EHR_Disease_Tetanus.png",
    toxin_poisoning = "media/textures/EHR_Disease_ToxinPoisoning.png",
    trichinosis = "media/textures/EHR_Disease_Trichinosis.png",
    tuberculosis = "media/textures/EHR_Disease_Tuberculosis.png",
    wound_infection = "media/textures/EHR_Disease_Wound_Infection.png",
}

local CategoryNames = {
    food = "Food-borne",
    environmental = "Environmental",
    wound = "Wound / trauma",
    corpse = "Corpse exposure",
    infection = "Infection",
}

local CategoryUnknownNames = {
    food = "Unknown Food-borne Illness",
    environmental = "Unknown Environmental Illness",
    wound = "Unknown Wound Illness",
    corpse = "Unknown Corpse-related Illness",
    infection = "Unknown Infection",
}

local CatalogOrder = {
    "food_poisoning",
    "gastroenteritis",
    "trichinosis",
    "toxin_poisoning",
    "dysentery",
    "common_cold",
    "pneumonia",
    "hypothermia",
    "heat_exhaustion",
    "heat_stroke",
    "corpse_sickness",
    "cadaveric_aspergillosis",
    "tuberculosis",
    "wound_infection",
    "cellulitis",
    "sepsis",
    "tetanus",
    "knox_infection",
}

local CodexInfo = {
    food_poisoning = {
        category = "food",
        cause = "Rotten food, burned food, or stale food.",
        symptoms = "Nausea, vomiting, endurance drain, increased hunger and thirst.",
        prevention = "Eat fresh food and avoid food that has spoiled, burned badly, or gone stale.",
        treatment = "Anti-nausea tablets, electrolyte powder, and activated charcoal. Activated charcoal can cure it over time.",
    },
    gastroenteritis = {
        category = "food",
        cause = "Eating with bloody or dirty hands.",
        symptoms = "Severe nausea, vomiting, dehydration, stomach pain, and fatigue.",
        prevention = "Wash hands before eating. Soap and clean water are best.",
        treatment = "Anti-diarrheal medicine, electrolyte powder, antiviral capsules, or IV ciprofloxacin for severe bacterial cases.",
    },
    trichinosis = {
        category = "food",
        cause = "Raw or undercooked wild game and unsafe raw meat.",
        symptoms = "Intense muscle pain, fever, weakness, and dangerous health loss in severe stages.",
        prevention = "Cook meat thoroughly, especially wild game.",
        treatment = "Muscle relaxants and anti-inflammatory medicine for symptoms; antiparasitic pills or albendazole injection to cure.",
    },
    toxin_poisoning = {
        category = "food",
        cause = "Poisonous berries, poisonous mushrooms, or other toxic food.",
        symptoms = "Violent nausea, vomiting, dizziness, blurred vision, weakness, and dangerous systemic poisoning.",
        prevention = "Avoid unidentified wild food unless you can verify it is safe.",
        treatment = "Activated charcoal is the main treatment. Anti-nausea tablets and electrolytes help symptoms.",
    },
    dysentery = {
        category = "environmental",
        cause = "Tainted water or severe gastrointestinal contamination.",
        symptoms = "Severe diarrhea, vomiting, dehydration, fever, weakness, and possible blood loss.",
        prevention = "Drink clean or boiled water and avoid unsafe water sources.",
        treatment = "Electrolytes and anti-diarrheal medicine for symptoms; IV ciprofloxacin for severe bacterial infection.",
    },
    common_cold = {
        category = "environmental",
        cause = "Cold, wet, or prolonged exposure while exhausted.",
        symptoms = "Coughing, sneezing, mild fever, fatigue, and reduced stamina.",
        prevention = "Stay warm, dry, rested, and protected from bad weather.",
        treatment = "Rest, fluids, cough medicine, antipyretics for fever, and time.",
    },
    pneumonia = {
        category = "environmental",
        cause = "Severe or untreated respiratory illness, cold exposure, or weakened health.",
        symptoms = "Severe cough, fever, chest tightness, endurance loss, and weakness.",
        prevention = "Treat respiratory illness early and avoid prolonged cold exposure.",
        treatment = "Antibiotics for infection, bronchodilator inhaler for breathing support, antipyretics for fever.",
    },
    hypothermia = {
        category = "environmental",
        cause = "Low body temperature from cold, wet clothing, wind, or exposure.",
        symptoms = "Shivering, weakness, confusion, fatigue, and dangerous temperature drop.",
        prevention = "Wear insulation, stay dry, and get indoors during severe cold.",
        treatment = "Warm up, change into dry clothes, rest, and use external heat sources.",
    },
    heat_exhaustion = {
        category = "environmental",
        cause = "Heat exposure, dehydration, heavy clothing, or exertion in hot weather.",
        symptoms = "Dizziness, nausea, weakness, thirst, fatigue, and overheating.",
        prevention = "Hydrate, rest in shade, wear lighter clothing, and avoid overexertion in heat.",
        treatment = "Cool down, rest, drink water, and use electrolyte powder.",
    },
    heat_stroke = {
        category = "environmental",
        name = "Heat Stroke",
        incubation = "Can develop from untreated heat exhaustion.",
        duration = "Critical until body temperature is controlled.",
        cause = "Extreme heat exposure or severe dehydration.",
        symptoms = "Extreme body temperature, delirium, confusion, vomiting, collapse/blackouts, dehydration, and life-threatening health loss.",
        prevention = "Avoid extreme heat, hydrate aggressively, and treat heat exhaustion early.",
        treatment = "Immediate cooling. Instant ice packs can cure heat stroke with a 4-dose cooling course; fluids and electrolytes help dehydration.",
    },
    corpse_sickness = {
        category = "corpse",
        cause = "Prolonged exposure to decomposing corpses, especially in enclosed spaces.",
        symptoms = "Eye irritation, nausea, dizziness, weakness, coughing, and possible collapse at high exposure.",
        prevention = "Ventilate corpse-filled spaces and wear effective face protection.",
        treatment = "Fresh air immediately. Anti-nausea tablets help symptoms; respiratory support kit or corticosteroids can treat severe cases.",
    },
    cadaveric_aspergillosis = {
        category = "corpse",
        cause = "Fungal spores from decomposing corpses in damp, wet, or cold conditions.",
        symptoms = "Respiratory irritation, fever, coughing, wheezing, endurance loss, and weakness.",
        prevention = "Wear face protection near damp corpse-filled areas and avoid breathing contaminated air.",
        treatment = "Bronchodilator inhaler and antipyretics for symptoms; antifungal tablets or IV amphotericin to cure.",
    },
    tuberculosis = {
        category = "corpse",
        cause = "Long-term respiratory exposure in contaminated corpse-heavy environments.",
        symptoms = "Persistent cough, fever, fatigue, weight loss, night sweats, and coughing blood in severe cases.",
        prevention = "Avoid prolonged corpse exposure and wear respiratory protection.",
        treatment = "TB antibiotics or rifampicin combo pack. Cough suppressants and antipyretics only reduce symptoms.",
    },
    wound_infection = {
        category = "wound",
        cause = "Dirty wounds, poor bandaging, or untreated injury contamination.",
        symptoms = "Pain, swelling, redness, pus, fever, and worsening wound condition.",
        prevention = "Clean wounds, use sterile bandages, and change dirty bandages quickly.",
        treatment = "Disinfect wounds, use antibiotic ointment, and escalate to antibiotics if infection spreads.",
    },
    cellulitis = {
        category = "wound",
        name = "Cellulitis (WIP)",
        cause = "WIP: not currently triggered by gameplay. Planned as a spreading bacterial infection through damaged skin or untreated wounds.",
        symptoms = "WIP: planned symptoms are hot red skin, swelling, pain, fever, and reduced limb function.",
        prevention = "WIP: treat wound infections early and keep injured skin clean. Full gameplay mechanics are not active yet.",
        treatment = "WIP: planned treatment is antibiotic ointment for mild cases; antibiotics or clinical antibiotics for severe infection.",
    },
    sepsis = {
        category = "wound",
        cause = "Untreated severe infection entering the bloodstream.",
        symptoms = "High fever, extreme weakness, confusion, rapid decline, and life-threatening systemic illness.",
        prevention = "Treat wound infections and cellulitis before they spread.",
        treatment = "IV antibiotics and aggressive medical support. This is an emergency condition.",
    },
    tetanus = {
        category = "wound",
        cause = "Deep contaminated puncture wounds, rusty metal injuries, or severe dirty wounds.",
        symptoms = "Jaw stiffness, muscle spasms, pain, fever, and dangerous neuromuscular failure.",
        prevention = "Clean deep wounds quickly and use tetanus prophylaxis when possible.",
        treatment = "Muscle relaxants for symptoms; tetanus antitoxin or tetanus immunoglobulin with a syringe to cure.",
    },
    knox_infection = {
        category = "infection",
        name = "Knox Infection",
        incubation = "Unknown.",
        duration = "Progressive and fatal.",
        cause = "Transmission after infected wounds.",
        symptoms = "Fever, nausea, weakness, pale skin, and terminal systemic infection.",
        prevention = "Avoid bites and infected wounds.",
        treatment = "No known cure.",
    },
}

local function safeText(key, fallback)
    local text = nil
    if getText then
        text = getText(key)
    end
    if not text or text == key then
        return fallback
    end
    return text
end

local function normalizeDiseaseId(id)
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.NormalizeDiseaseId then
        return EHR.DiseaseFlyers.NormalizeDiseaseId(id)
    end
    return id
end

local function getDiseaseDefinition(id)
    local normalized = normalizeDiseaseId(id)
    local diseases = EHR.Disease and EHR.Disease.Diseases or nil
    return diseases and (diseases[normalized] or diseases[id]) or nil
end

local function hoursToText(hours)
    hours = tonumber(hours)
    if not hours then return nil end
    if hours >= 24 then
        local days = hours / 24
        if math.floor(days) == days then
            return tostring(days) .. "d"
        end
        return string.format("%.1fd", days)
    end
    return tostring(hours) .. "h"
end

local function rangeHoursToText(minHours, maxHours)
    local minText = hoursToText(minHours)
    local maxText = hoursToText(maxHours)
    if not minText and not maxText then return "Unknown" end
    if minText == maxText then return minText end
    return tostring(minText or "?") .. " - " .. tostring(maxText or "?")
end

local function measureText(font, text)
    if getTextManager then
        local ok, width = pcall(function()
            return getTextManager():MeasureStringX(font, tostring(text or ""))
        end)
        if ok and width then return width end
    end
    return string.len(tostring(text or "")) * 8
end

local function truncateText(text, maxWidth, font)
    text = tostring(text or "")
    if measureText(font, text) <= maxWidth then return text end
    local suffix = "..."
    local suffixW = measureText(font, suffix)
    while #text > 0 and measureText(font, text) + suffixW > maxWidth do
        text = text:sub(1, #text - 1)
    end
    return text .. suffix
end

local function categoryName(category)
    return CategoryNames[category] or tostring(category or "Unknown")
end

function EHR_MedicalJournalUI:new(x, y, width, height, player)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.backgroundColor = Colors.bg
    o.borderColor = Colors.border
    o.moveWithMouse = true
    o.textureCache = {}
    return o
end

function EHR_MedicalJournalUI:initialise()
    ISPanel.initialise(self)
end

function EHR_MedicalJournalUI:createChildren()
    ISPanel.createChildren(self)

    self.closeBtn = ISButton:new(self.width - 34, 9, 24, 24, "X", self, EHR_MedicalJournalUI.onClose)
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = Colors.border
    self.closeBtn.backgroundColor = { r = 0.02, g = 0.02, b = 0.02, a = 0.9 }
    self.closeBtn.backgroundColorMouseOver = { r = 0.45, g = 0.02, b = 0.02, a = 0.95 }
    self.closeBtn:setAnchorRight(true)
    self:addChild(self.closeBtn)

    self.diseaseList = ISScrollingListBox:new(PADDING, HEADER_HEIGHT + PADDING + 36, LIST_WIDTH, self.height - HEADER_HEIGHT - PADDING * 2 - 40)
    self.diseaseList:initialise()
    self.diseaseList:instantiate()
    self.diseaseList.itemheight = 76
    self.diseaseList.font = UIFont.Small
    self.diseaseList.doDrawItem = EHR_MedicalJournalUI.drawDiseaseItem
    self.diseaseList.drawBorder = false
    self.diseaseList.parentUI = self
    self.diseaseList:setAnchorBottom(true)
    self:addChild(self.diseaseList)

    self:refreshEntries()
end

function EHR_MedicalJournalUI:getTexture(path)
    if not path then return nil end
    if self.textureCache[path] ~= nil then
        return self.textureCache[path] or nil
    end
    local texture = nil
    if getTexture then
        local ok, result = pcall(getTexture, path)
        if ok then texture = result end
    end
    self.textureCache[path] = texture or false
    return texture
end

function EHR_MedicalJournalUI:getDiseaseIcon(diseaseId, known)
    local id = normalizeDiseaseId(diseaseId)
    local path = known and DiseaseIcons[id] or DiseaseIcons.unknown
    return self:getTexture(path or DiseaseIcons.unknown)
end

function EHR_MedicalJournalUI:getFirstAidLevel()
    if self.player and Perks and Perks.Doctor and self.player.getPerkLevel then
        local ok, level = pcall(function() return self.player:getPerkLevel(Perks.Doctor) end)
        if ok then return tonumber(level) or 0 end
    end
    return 0
end

function EHR_MedicalJournalUI:knowsDisease(diseaseId)
    local level = self:getFirstAidLevel()
    if level >= 8 then return true end
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.CanIdentifyDisease then
        return EHR.DiseaseFlyers.CanIdentifyDisease(self.player, diseaseId) == true
    end
    return false
end

function EHR_MedicalJournalUI:getCatalogEntry(diseaseId)
    local id = normalizeDiseaseId(diseaseId)
    local def = getDiseaseDefinition(id)
    local info = CodexInfo[id] or {}
    local category = info.category or (def and def.category) or "infection"
    local known = self:knowsDisease(id)
    local realName = info.name or (def and def.name) or (EHR.DiseaseFlyers and EHR.DiseaseFlyers.GetDiseaseFriendlyName and EHR.DiseaseFlyers.GetDiseaseFriendlyName(id)) or id
    local displayName = known and realName or (CategoryUnknownNames[category] or "Unknown Illness")

    return {
        id = id,
        definition = def,
        info = info,
        category = category,
        known = known,
        realName = realName,
        displayName = displayName,
        incubation = info.incubation or rangeHoursToText(def and def.incubationMin, def and def.incubationMax),
        duration = info.duration or rangeHoursToText(def and def.durationMin, def and def.durationMax),
        canKill = (def and def.canKill == true) or info.canKill == true,
    }
end

function EHR_MedicalJournalUI:getCatalogEntries()
    local entries = {}
    for _, diseaseId in ipairs(CatalogOrder) do
        table.insert(entries, self:getCatalogEntry(diseaseId))
    end
    return entries
end

function EHR_MedicalJournalUI:refreshEntries()
    if not self.diseaseList then return end
    self.diseaseList:clear()
    self.catalogEntries = self:getCatalogEntries()
    local knownCount = 0
    for _, entry in ipairs(self.catalogEntries) do
        if entry.known then knownCount = knownCount + 1 end
        self.diseaseList:addItem(entry.displayName, entry)
    end
    self.knownCount = knownCount
    if #self.catalogEntries > 0 and (not self.diseaseList.selected or self.diseaseList.selected <= 0) then
        self.diseaseList.selected = 1
    end
end

function EHR_MedicalJournalUI:getSelectedEntry()
    if not self.diseaseList or not self.diseaseList.items then return nil end
    local selected = self.diseaseList.selected or 1
    local item = self.diseaseList.items[selected]
    return item and item.item or nil
end

function EHR_MedicalJournalUI:drawPanelFrame(x, y, w, h, title)
    local c = Colors
    self:drawRect(x, y, w, h, c.panel.a, c.panel.r, c.panel.g, c.panel.b)
    self:drawRectBorder(x, y, w, h, c.borderDim.a, c.borderDim.r, c.borderDim.g, c.borderDim.b)
    if title then
        self:drawRect(x + 1, y + 1, w - 2, 30, c.header.a, c.header.r, c.header.g, c.header.b)
        self:drawText(title, x + 10, y - 5, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Medium)
        self:drawRect(x + 10, y + 29, w - 20, 1, 0.75, c.border.r, c.border.g, c.border.b)
    end
end

function EHR_MedicalJournalUI:drawWrappedText(text, x, y, w, color, font, lineHeight)
    text = tostring(text or "")
    color = color or Colors.text
    font = font or UIFont.Small
    lineHeight = lineHeight or 19

    local line = ""
    for word in text:gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if measureText(font, candidate) <= w then
            line = candidate
        else
            if line ~= "" then
                self:drawText(line, x, y, color.r, color.g, color.b, color.a or 1, font)
                y = y + lineHeight
            end
            line = word
        end
    end
    if line ~= "" then
        self:drawText(line, x, y, color.r, color.g, color.b, color.a or 1, font)
        y = y + lineHeight
    end
    return y
end

function EHR_MedicalJournalUI:drawInfoSection(label, value, x, y, w)
    local c = Colors
    self:drawText(label, x, y, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Medium)
    y = y + 24
    return self:drawWrappedText(value, x + 8, y, w - 16, c.text, UIFont.Small, 19) + 10
end

function EHR_MedicalJournalUI:prerender()
    ISPanel.prerender(self)
    local c = Colors
    self:drawRect(0, 0, self.width, self.height, c.bg.a, c.bg.r, c.bg.g, c.bg.b)
    self:drawRectBorder(0, 0, self.width, self.height, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRect(0, 0, self.width, HEADER_HEIGHT, 0.82, 0.02, 0.02, 0.02)
    self:drawText("EHR DISEASE HANDBOOK", 16, 8, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Large)

    local total = #CatalogOrder
    local known = tonumber(self.knownCount) or 0
    local progress = string.format("%d/%d known", known, total)
    local progressW = measureText(UIFont.Medium, progress)
    self:drawText(progress, self.width - progressW - 50, 11, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Medium)

    self:drawPanelFrame(PADDING, HEADER_HEIGHT + PADDING, LIST_WIDTH, self.height - HEADER_HEIGHT - PADDING * 2, "DISEASE INDEX")

    local detailX = PADDING + LIST_WIDTH + 12
    local detailY = HEADER_HEIGHT + PADDING
    local detailW = self.width - detailX - PADDING
    local detailH = self.height - detailY - PADDING
    self:drawPanelFrame(detailX, detailY, detailW, detailH, "ENTRY DETAILS")
end

function EHR_MedicalJournalUI:render()
    ISPanel.render(self)

    local detailX = PADDING + LIST_WIDTH + 12
    local detailY = HEADER_HEIGHT + PADDING
    local detailW = self.width - detailX - PADDING
    local detailH = self.height - detailY - PADDING

    local entry = self:getSelectedEntry()
    if entry then
        self:drawDiseaseDetails(entry, detailX + 18, detailY + 46, detailW - 36, detailH - 58)
    end
end

function EHR_MedicalJournalUI:drawDiseaseDetails(entry, x, y, w, h)
    local c = Colors
    local iconSize = 86
    local icon = self:getDiseaseIcon(entry.id, entry.known)
    if icon and self.drawTextureScaled then
        self:drawTextureScaled(icon, x, y, iconSize, iconSize, 1, 1, 1, 1)
    else
        self:drawRectBorder(x, y, iconSize, iconSize, c.border.a, c.border.r, c.border.g, c.border.b)
        self:drawText("?", x + 32, y + 22, c.cyan.r, c.cyan.g, c.cyan.b, 1, UIFont.Large)
    end

    local titleX = x + iconSize + 18
    self:drawText(entry.displayName, titleX, y + 4, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Large)
    self:drawText(categoryName(entry.category), titleX, y + 34, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
    local badge = entry.known and "KNOWN" or "LOCKED"
    local badgeColor = entry.known and c.green or c.yellow
    self:drawText(badge, titleX, y + 60, badgeColor.r, badgeColor.g, badgeColor.b, badgeColor.a, UIFont.Medium)

    if entry.canKill then
        local lethal = "LETHAL RISK"
        local lethalW = measureText(UIFont.Medium, lethal)
        self:drawText(lethal, x + w - lethalW, y + 60, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Medium)
    end

    y = y + iconSize + 18
    self:drawRect(x, y, w, 1, 0.76, c.border.r, c.border.g, c.border.b)
    y = y + 16

    if not entry.known then
        self:drawText("Knowledge unavailable", x, y, c.red.r, c.red.g, c.red.b, c.red.a, UIFont.Medium)
        y = y + 28
        self:drawWrappedText(
            "Read the matching disease flyer or reach First Aid level 8 to unlock symptoms, causes, prevention, and treatment notes.",
            x + 8, y, w - 16, c.textDim, UIFont.Small, 19
        )
        return
    end

    local info = entry.info or {}
    y = self:drawInfoSection("Cause", info.cause or "Unknown.", x, y, w)
    y = self:drawInfoSection("Symptoms", info.symptoms or "No symptom notes available.", x, y, w)
    y = self:drawInfoSection("Timing", "Incubation: " .. tostring(entry.incubation or "Unknown") .. ". Duration: " .. tostring(entry.duration or "Unknown") .. ".", x, y, w)
    y = self:drawInfoSection("Prevention", info.prevention or "No prevention notes available.", x, y, w)
    self:drawInfoSection("Treatment", info.treatment or "No treatment notes available.", x, y, w)
end

function EHR_MedicalJournalUI.drawDiseaseItem(self, y, item, alt)
    local parent = self.parentUI
    local entry = item and item.item or nil
    if not parent or not entry then return y + self.itemheight end

    local c = Colors
    local selected = (self.selected == item.index) or (self.items and self.items[self.selected] == item)
    local rowAlpha = selected and 0.82 or (alt and 0.38 or 0.24)
    local rowR = selected and c.redDark.r or c.panel.r
    local rowG = selected and c.redDark.g or c.panel.g
    local rowB = selected and c.redDark.b or c.panel.b
    self:drawRect(4, y + 4, self:getWidth() - 12, self.itemheight - 8, rowAlpha, rowR, rowG, rowB)
    self:drawRectBorder(4, y + 4, self:getWidth() - 12, self.itemheight - 8, selected and c.border.a or c.borderDim.a, c.border.r, c.border.g, c.border.b)

    local icon = parent:getDiseaseIcon(entry.id, entry.known)
    if icon and self.drawTextureScaled then
        self:drawTextureScaled(icon, 14, y + 12, 52, 52, entry.known and 1 or 0.72, 1, 1, 1)
    else
        self:drawText("?", 32, y + 22, c.cyan.r, c.cyan.g, c.cyan.b, 1, UIFont.Medium)
    end

    local nameColor = entry.known and c.text or c.textDim
    local name = truncateText(entry.displayName, self:getWidth() - 90, UIFont.Medium)
    self:drawText(name, 76, y + 14, nameColor.r, nameColor.g, nameColor.b, nameColor.a, UIFont.Medium)

    local category = truncateText(categoryName(entry.category), self:getWidth() - 118, UIFont.Small)
    self:drawText(category, 76, y + 42, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)

    local status = entry.known and "Known" or "Locked"
    local statusColor = entry.known and c.green or c.yellow
    local statusW = measureText(UIFont.Small, status)
    self:drawText(status, self:getWidth() - statusW - 18, y + 42, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Small)

    return y + self.itemheight
end

function EHR_MedicalJournalUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    EHR_MedicalJournalUI.instance = nil
end

function EHR_MedicalJournalUI.Toggle(player)
    player = player or getSpecificPlayer(0)
    if not player then return end

    if EHR_MedicalJournalUI.instance and EHR_MedicalJournalUI.instance:isVisible() then
        EHR_MedicalJournalUI.instance:onClose()
        return
    end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local x = math.floor((screenW - WINDOW_WIDTH) / 2)
    local y = math.floor((screenH - WINDOW_HEIGHT) / 2)

    EHR_MedicalJournalUI.instance = EHR_MedicalJournalUI:new(x, y, WINDOW_WIDTH, WINDOW_HEIGHT, player)
    EHR_MedicalJournalUI.instance:initialise()
    EHR_MedicalJournalUI.instance:instantiate()
    EHR_MedicalJournalUI.instance:addToUIManager()
    EHR_MedicalJournalUI.instance:setVisible(true)
    EHR_MedicalJournalUI.instance:bringToTop()
end

function EHR_MedicalJournalUI.IsOpen()
    return EHR_MedicalJournalUI.instance ~= nil and EHR_MedicalJournalUI.instance:isVisible()
end

EHR = EHR or {}
EHR.UI = EHR.UI or {}
EHR.UI.ToggleJournal = EHR_MedicalJournalUI.Toggle

if EHR and EHR.Log then
    EHR.Log("DiseaseHandbookUI module loaded")
end
