-- Extensive Health Rework B42
-- Lightweight wound suturing minigame.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISStitch"
require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Disease" end)
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.StitchMinigame = EHR.StitchMinigame or {}
EHR.StitchMinigame.RemoteValidBodyParts = EHR.StitchMinigame.RemoteValidBodyParts or {}
EHR.StitchMinigame.CELLULITIS_ROUGH_RISK = 0.40

local C = {
    bg = { r = 0.018, g = 0.016, b = 0.016, a = 0.97 },
    panel = { r = 0.055, g = 0.030, b = 0.030, a = 0.92 },
    panelSoft = { r = 0.08, g = 0.020, b = 0.020, a = 0.72 },
    skin = { r = 0.24, g = 0.13, b = 0.10, a = 0.56 },
    skinDark = { r = 0.12, g = 0.045, b = 0.035, a = 0.64 },
    wound = { r = 0.52, g = 0.018, b = 0.014, a = 0.82 },
    woundDark = { r = 0.10, g = 0.005, b = 0.004, a = 0.76 },
    thread = { r = 0.86, g = 0.80, b = 0.68, a = 0.96 },
    threadDim = { r = 0.50, g = 0.46, b = 0.38, a = 0.55 },
    threadLive = { r = 1.00, g = 0.66, b = 0.18, a = 0.72 },
    red = { r = 0.90, g = 0.045, b = 0.040, a = 1.0 },
    redDim = { r = 0.42, g = 0.020, b = 0.018, a = 1.0 },
    gold = { r = 1.00, g = 0.66, b = 0.18, a = 1.0 },
    green = { r = 0.20, g = 0.90, b = 0.30, a = 1.0 },
    cyan = { r = 0.20, g = 0.82, b = 1.00, a = 1.0 },
    text = { r = 0.92, g = 0.90, b = 0.84, a = 1.0 },
    dim = { r = 0.60, g = 0.58, b = 0.56, a = 1.0 },
    bad = { r = 1.00, g = 0.28, b = 0.12, a = 1.0 },
}

local function L(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_StitchMinigame_" .. tostring(key), fallback)
    end
    local fullKey = "UI_EHR_StitchMinigame_" .. tostring(key)
    local ok, value = pcall(getText, fullKey)
    if ok and value and value ~= fullKey then return value end
    return fallback
end

local TextureCache = {}
local function stitchTexture(path)
    if not path or not getTexture then return nil end
    if TextureCache[path] == nil then
        TextureCache[path] = getTexture(path) or false
    end
    if TextureCache[path] == false then return nil end
    return TextureCache[path]
end

local function getDoctorLevel(player)
    if not player or not player.getPerkLevel or not Perks or not Perks.Doctor then
        return 0
    end
    local ok, level = pcall(function() return player:getPerkLevel(Perks.Doctor) end)
    if ok then return tonumber(level) or 0 end
    return 0
end

local function hasInventoryItem(player, item)
    if not player or not item or not player.getInventory then
        return false
    end
    local inv = player:getInventory()
    if not inv then return false end
    if isClient() and item.getID and inv.containsID then
        return inv:containsID(item:getID())
    end
    return inv:contains(item)
end

local function bodyPartName(bodyPart)
    if not bodyPart then return L("UnknownPart", "Unknown body part") end
    local ok, partType = pcall(function() return bodyPart:getType() end)
    if ok and BodyPartType and BodyPartType.getDisplayName then
        local okName, name = pcall(function() return BodyPartType.getDisplayName(partType) end)
        if okName and name then return tostring(name) end
    end
    return tostring(partType or L("UnknownPart", "Unknown body part"))
end

local function bodyPartKey(bodyPart)
    if not bodyPart then return nil end

    local ok, partType = pcall(function() return bodyPart:getType() end)
    if ok and BodyPartType and BodyPartType.ToString then
        local okName, name = pcall(function() return BodyPartType.ToString(partType) end)
        if okName and name then return tostring(name) end
    end

    if ok and partType ~= nil then
        return tostring(partType)
    end

    return bodyPartName(bodyPart)
end

local function playerIdentifiers(player)
    local data = {}
    if not player then return data end

    pcall(function()
        if player.getUsername then data.targetUsername = player:getUsername() end
    end)
    pcall(function()
        if player.getOnlineID then data.targetOnlineID = tostring(player:getOnlineID()) end
    end)
    pcall(function()
        if player.getDisplayName then data.targetDisplayName = tostring(player:getDisplayName()) end
    end)

    return data
end

local function markCellulitisSource(player, sourceBodyPart, quality, misses)
    if not player or not EHR or not EHR.Disease then return end

    local diseaseData = EHR.Disease.GetDiseaseData and EHR.Disease.GetDiseaseData(player) or nil
    local cellulitis = diseaseData and diseaseData.active and diseaseData.active.cellulitis or nil
    if not cellulitis then return end

    cellulitis.source = "rough_stitch"
    cellulitis.sourceBodyPart = sourceBodyPart
    cellulitis.stitchQuality = quality
    cellulitis.stitchMisses = misses
end

function EHR.StitchMinigame.TryCellulitisRisk(action, chance)
    if not action or not action.bodyPart then return false end

    chance = tonumber(chance) or 0
    if chance <= 0 then return false end

    local patient = action.otherPlayer or action.character
    if not patient then return false end

    local sourceBodyPart = bodyPartKey(action.bodyPart)
    local quality = tonumber(action._ehrStitchMinigameQuality) or 0.75
    local misses = tonumber(action._ehrStitchMinigameMisses) or 0

    if isClient and isClient() and sendClientCommand then
        local args = playerIdentifiers(patient)
        args.sourceBodyPart = sourceBodyPart
        args.chance = chance
        args.quality = quality
        args.misses = misses
        sendClientCommand(action.character or getPlayer(), "EHR", "StitchCellulitisRisk", args)
        return true
    end

    if not ZombRand or ZombRand(100) >= math.floor(chance * 100) then
        return false
    end

    if EHR.Disease and EHR.Disease.InitializePlayer then
        pcall(function() EHR.Disease.InitializePlayer(patient) end)
    end
    if EHR.Disease and EHR.Disease.Contract then
        pcall(function() EHR.Disease.Contract(patient, "cellulitis") end)
        markCellulitisSource(patient, sourceBodyPart, quality, misses)
        return true
    end

    return false
end

local function isBodyPartStillValid(bodyPart)
    if not bodyPart then return false end
    local remoteValidUntil = EHR.StitchMinigame.RemoteValidBodyParts and EHR.StitchMinigame.RemoteValidBodyParts[bodyPart] or nil
    if remoteValidUntil and getTimestampMs and getTimestampMs() <= remoteValidUntil then
        return true
    end

    local okDeep, deep = pcall(function()
        if bodyPart.deepWounded then
            return bodyPart:deepWounded()
        end
        return bodyPart:isDeepWounded()
    end)
    local okGlass, glass = pcall(function() return bodyPart:haveGlass() end)
    local okStitched, stitched = pcall(function() return bodyPart:stitched() end)
    return okDeep and deep == true and (not okGlass or glass ~= true) and (not okStitched or stitched ~= true)
end

function EHR.StitchMinigame.AllowRemoteBodyPart(bodyPart, milliseconds)
    if not bodyPart or not getTimestampMs then return end
    EHR.StitchMinigame.RemoteValidBodyParts = EHR.StitchMinigame.RemoteValidBodyParts or {}
EHR.StitchMinigame.CELLULITIS_ROUGH_RISK = 0.40
    EHR.StitchMinigame.RemoteValidBodyParts[bodyPart] = getTimestampMs() + (tonumber(milliseconds) or 180000)
end

function EHR.StitchMinigame.IsEnabled()
    local options = SandboxVars and SandboxVars.ExtensiveHealthRework
    if options and options.StitchMinigameEnabled == false then
        return false
    end
    return true
end

function EHR.StitchMinigame.ShouldIntercept(character, otherPlayer, item, bodyPart, doIt)
    if EHR.StitchMinigame._bypass then return false end
    if not EHR.StitchMinigame.IsEnabled() then return false end
    if doIt ~= true then return false end
    if not character or not otherPlayer or not item or not bodyPart then return false end
    if not isBodyPartStillValid(bodyPart) then return false end
    if not hasInventoryItem(character, item) then return false end
    return true
end

function EHR.StitchMinigame.CreateVanillaAction(character, otherPlayer, item, bodyPart, quality, misses)
    local originalNew = EHR.StitchMinigame._originalNew
    if not originalNew then return nil end

    EHR.StitchMinigame._bypass = true
    local action = originalNew(ISStitch, character, otherPlayer, item, bodyPart, true)
    EHR.StitchMinigame._bypass = false

    if action then
        action._ehrStitchMinigameQuality = quality or 0.75
        action._ehrStitchMinigameMisses = misses or 0
        action._ehrWasInfectedBefore = false
        pcall(function()
            action._ehrWasInfectedBefore = bodyPart:isInfectedWound()
        end)
    end
    return action
end

function EHR.StitchMinigame.ApplyQuality(action)
    if not action or not action.bodyPart or not action._ehrStitchMinigameQuality then
        return
    end

    local bodyPart = action.bodyPart
    local quality = tonumber(action._ehrStitchMinigameQuality) or 0.75
    local extraPain = 0

    if quality >= 0.90 then
        pcall(function()
            bodyPart:setAdditionalPain(math.max(0, bodyPart:getAdditionalPain() - 5))
        end)
        if action._ehrWasInfectedBefore ~= true then
            pcall(function()
                if bodyPart:isInfectedWound() and ZombRand(100) < 65 then
                    bodyPart:setInfectedWound(false)
                    bodyPart:setWoundInfectionLevel(-1)
                end
            end)
        end
    elseif quality < 0.55 then
        extraPain = 12
        pcall(function()
            if action._ehrWasInfectedBefore ~= true and ZombRand(100) < 30 then
                bodyPart:setInfectedWound(true)
            end
        end)
        EHR.StitchMinigame.TryCellulitisRisk(action, EHR.StitchMinigame.CELLULITIS_ROUGH_RISK)
    elseif quality < 0.72 then
        extraPain = 5
        EHR.StitchMinigame.TryCellulitisRisk(action, EHR.StitchMinigame.CELLULITIS_ROUGH_RISK)
    end

    if extraPain > 0 then
        pcall(function()
            bodyPart:setAdditionalPain(bodyPart:getAdditionalPain() + extraPain)
        end)
    end

    pcall(function() syncBodyPart(bodyPart, 0x00570188) end)
end

EHR_StitchMinigameAction = ISBaseTimedAction:derive("EHR_StitchMinigameAction")

function EHR_StitchMinigameAction:isValid()
    return self.character and self.otherPlayer and hasInventoryItem(self.character, self.item) and isBodyPartStillValid(self.bodyPart)
end

function EHR_StitchMinigameAction:start()
    self.maxTime = 1
end

function EHR_StitchMinigameAction:perform()
    EHR.StitchMinigame.Open(self.character, self.otherPlayer, self.item, self.bodyPart)
    ISBaseTimedAction.perform(self)
end

function EHR_StitchMinigameAction:new(character, otherPlayer, item, bodyPart)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.otherPlayer = otherPlayer
    o.item = item
    o.bodyPart = bodyPart
    o.maxTime = 1
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    return o
end

EHR_StitchMinigameUI = ISPanel:derive("EHR_StitchMinigameUI")
EHR_StitchMinigameUI.instance = nil

function EHR_StitchMinigameUI:new(x, y, width, height, character, otherPlayer, item, bodyPart)
    local o = ISPanel.new(self, x, y, width, height)
    o.character = character
    o.otherPlayer = otherPlayer
    o.item = item
    o.bodyPart = bodyPart
    o.moveWithMouse = false
    o.dragging = false
    o.background = false
    o.borderColor = C.redDim
    o.currentIndex = 1
    o.misses = 0
    o.finished = false
    o.flash = 0
    o.boardX = 24
    o.boardY = 126
    o.boardW = width - 48
    o.boardH = height - 206
    o.points = {}
    o.doctorLevel = getDoctorLevel(character)
    local skill = math.min(8, math.max(0, o.doctorLevel or 0))
    local skillFactor = skill / 8
    o.maxMisses = 4 + math.floor(o.doctorLevel / 4)
    if o.maxMisses > 6 then o.maxMisses = 6 end
    o.pointSize = 4 + math.floor(skillFactor * 4 + 0.5)
    o.hitPointSize = 4 + math.floor(skillFactor * 3 + 0.5)
    o.activePointSize = 6 + math.floor(skillFactor * 9 + 0.5)
    o.tolerance = 7 + math.floor(skillFactor * 9 + 0.5)
    o.motionTick = 0
    o.motionAmplitude = 34 - math.floor(skillFactor * 12 + 0.5)
    o.motionSpeed = 0.150 - (skillFactor * 0.080)
    local roll = ZombRand and ZombRand(2) or math.random(0, 1)
    o.orientation = roll == 0 and "vertical" or "horizontal"
    o.doctorStartX = character and character.getX and character:getX() or 0
    o.doctorStartY = character and character.getY and character:getY() or 0
    o.patientStartX = otherPlayer and otherPlayer.getX and otherPlayer:getX() or 0
    o.patientStartY = otherPlayer and otherPlayer.getY and otherPlayer:getY() or 0
    o:generatePoints()
    return o
end

function EHR_StitchMinigameUI:initialise()
    ISPanel.initialise(self)
end

function EHR_StitchMinigameUI:createChildren()
    ISPanel.createChildren(self)
    self.cancelButton = ISButton:new(self.width - 88, 8, 72, 26, L("Cancel", "Cancel"), self, EHR_StitchMinigameUI.onCancel)
    self.cancelButton:initialise()
    self.cancelButton:instantiate()
    self:addChild(self.cancelButton)
end

function EHR_StitchMinigameUI:generatePoints()
    self.points = {}
    local count = 12

    for i = 1, count do
        local side = (i % 2 == 1) and -1 or 1
        local phase = ((ZombRand and ZombRand(628)) or math.random(0, 628)) / 100
        local x
        local y
        local moveAxis

        if self.orientation == "horizontal" then
            local cy = self.boardY + math.floor(self.boardH / 2)
            local spread = 56
            local left = self.boardX + 56
            local step = (self.boardW - 112) / math.max(1, count - 1)
            x = left + math.floor((i - 1) * step)
            y = cy + side * spread
            moveAxis = "y"
        else
            local cx = self.boardX + math.floor(self.boardW / 2)
            local spread = 68
            local top = self.boardY + 32
            local step = (self.boardH - 64) / math.max(1, count - 1)
            x = cx + side * spread
            y = top + math.floor((i - 1) * step)
            moveAxis = "x"
        end

        table.insert(self.points, {
            x = x,
            y = y,
            baseX = x,
            baseY = y,
            phase = phase,
            moveAxis = moveAxis,
            hit = false,
        })
    end
end

function EHR_StitchMinigameUI:getPointPosition(point, index)
    if not point then return 0, 0 end
    if point.hit then
        return point.hitX or point.x or point.baseX or 0, point.hitY or point.y or point.baseY or 0
    end

    local x = point.baseX or point.x or 0
    local y = point.baseY or point.y or 0
    if index == self.currentIndex then
        local tick = (self.motionTick or 0) * (self.motionSpeed or 0.06)
        local phase = point.phase or 0
        local primaryOffset = math.sin(tick + phase) * (self.motionAmplitude or 14)
        local secondaryOffset = math.cos((tick * 1.37) + phase + 1.7) * ((self.motionAmplitude or 14) * 0.42)
        if point.moveAxis == "y" then
            y = y + primaryOffset
            x = x + secondaryOffset
        else
            x = x + primaryOffset
            y = y + secondaryOffset
        end
    end
    return x, y
end

function EHR_StitchMinigameUI:updatePointMotion()
    for i, point in ipairs(self.points or {}) do
        local x, y = self:getPointPosition(point, i)
        point.x = x
        point.y = y
    end
end

function EHR_StitchMinigameUI:quality()
    local quality = 1.0 - (self.misses * 0.13)
    if quality < 0.35 then quality = 0.35 end
    return quality
end

function EHR_StitchMinigameUI:qualityText()
    local quality = self:quality()
    if quality >= 0.90 then return L("Excellent", "Excellent"), C.green end
    if quality >= 0.72 then return L("Stable", "Stable"), C.cyan end
    if quality >= 0.55 then return L("Rough", "Rough"), C.gold end
    return L("Poor", "Poor"), C.bad
end

function EHR_StitchMinigameUI:close()
    if EHR_StitchMinigameUI.instance == self then
        EHR_StitchMinigameUI.instance = nil
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

function EHR_StitchMinigameUI:applyDirtyAttemptRisk(reason)
    if self._ehrDirtyAttemptRiskApplied then return end

    local started = (tonumber(self.misses) or 0) > 0 or (tonumber(self.currentIndex) or 1) > 1
    if not started then return end

    local quality = self:quality()
    if quality >= 0.72 then return end

    self._ehrDirtyAttemptRiskApplied = true
    EHR.StitchMinigame.TryCellulitisRisk({
        character = self.character,
        otherPlayer = self.otherPlayer,
        bodyPart = self.bodyPart,
        _ehrStitchMinigameQuality = quality,
        _ehrStitchMinigameMisses = self.misses,
        _ehrStitchMinigameAbortReason = reason,
    }, EHR.StitchMinigame.CELLULITIS_ROUGH_RISK)
end

function EHR_StitchMinigameUI:onCancel()
    self.finished = true
    self:applyDirtyAttemptRisk("cancel")
    self:close()
end

function EHR_StitchMinigameUI:finishSuccess()
    if self.finished then return end
    self.finished = true
    local quality = self:quality()
    local action = EHR.StitchMinigame.CreateVanillaAction(self.character, self.otherPlayer, self.item, self.bodyPart, quality, self.misses)
    self:close()
    if action then
        ISTimedActionQueue.add(action)
    end
end

function EHR_StitchMinigameUI:finishFailure()
    if self.finished then return end
    self.finished = true
    self:applyDirtyAttemptRisk("failure")
    pcall(function()
        self.bodyPart:setAdditionalPain(self.bodyPart:getAdditionalPain() + 10)
        syncBodyPart(self.bodyPart, 0x00570188)
    end)
    if EHR and EHR.Locale and EHR.Locale.Say then
        EHR.Locale.Say(self.character, L("FailLine", "I can't keep the needle steady."))
    end
    self:close()
end

function EHR_StitchMinigameUI:update()
    ISPanel.update(self)
    if self.flash > 0 then self.flash = self.flash - 1 end
    self.motionTick = (self.motionTick or 0) + 1
    self:updatePointMotion()

    if self.finished then return end
    if not hasInventoryItem(self.character, self.item) or not isBodyPartStillValid(self.bodyPart) then
        self:close()
        return
    end
    if self.character and self.character.getX and
            (math.abs(self.character:getX() - self.doctorStartX) > 0.15 or math.abs(self.character:getY() - self.doctorStartY) > 0.15) then
        self:applyDirtyAttemptRisk("doctor_moved")
        self:close()
        return
    end
    if self.character ~= self.otherPlayer and ISHealthPanel and ISHealthPanel.DidPatientMove then
        local moved = false
        pcall(function()
            moved = ISHealthPanel.DidPatientMove(self.character, self.otherPlayer, self.patientStartX, self.patientStartY)
        end)
        if moved then
            self:applyDirtyAttemptRisk("patient_moved")
            self:close()
        end
    end
end

function EHR_StitchMinigameUI:onMouseDown(x, y)
    if self.finished then return true end
    if y <= 42 and x < self.width - 100 then
        self.dragging = true
        self.dragStartX = self:getX()
        self.dragStartY = self:getY()
        self.dragMouseStartX = getMouseX()
        self.dragMouseStartY = getMouseY()
        self:bringToTop()
        return true
    end

    if x < self.boardX or x > self.boardX + self.boardW or y < self.boardY or y > self.boardY + self.boardH then
        return true
    end

    local point = self.points[self.currentIndex]
    if not point then return true end

    local pointX, pointY = self:getPointPosition(point, self.currentIndex)
    local dx = x - pointX
    local dy = y - pointY
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= self.tolerance then
        point.hit = true
        point.hitX = pointX
        point.hitY = pointY
        point.x = pointX
        point.y = pointY
        self.currentIndex = self.currentIndex + 1
        self.flash = 8
        if self.currentIndex > #self.points then
            self:finishSuccess()
        end
    else
        self.misses = self.misses + 1
        self.flash = -10
        if self.misses >= self.maxMisses then
            self:finishFailure()
        end
    end
    return true
end

function EHR_StitchMinigameUI:onMouseMove(dx, dy)
    if self.dragging then
        local mouseX = getMouseX()
        local mouseY = getMouseY()
        local newX = self.dragStartX + (mouseX - self.dragMouseStartX)
        local newY = self.dragStartY + (mouseY - self.dragMouseStartY)

        local core = getCore and getCore()
        if core then
            newX = math.max(0, math.min(newX, core:getScreenWidth() - self.width))
            newY = math.max(0, math.min(newY, core:getScreenHeight() - self.height))
        end

        self:setX(newX)
        self:setY(newY)
        return true
    end
    return ISPanel.onMouseMove(self, dx, dy)
end

function EHR_StitchMinigameUI:onMouseMoveOutside(dx, dy)
    if self.dragging then
        return self:onMouseMove(dx, dy)
    end
    if ISPanel.onMouseMoveOutside then
        return ISPanel.onMouseMoveOutside(self, dx, dy)
    end
    return false
end

function EHR_StitchMinigameUI:onMouseUp(x, y)
    self.dragging = false
    return ISPanel.onMouseUp(self, x, y)
end

function EHR_StitchMinigameUI:onMouseUpOutside(x, y)
    self.dragging = false
    if ISPanel.onMouseUpOutside then
        return ISPanel.onMouseUpOutside(self, x, y)
    end
    return true
end

function EHR_StitchMinigameUI:drawTextureSafe(path, x, y, w, h, alpha)
    local texture = stitchTexture(path)
    if texture and self.drawTextureScaled then
        self:drawTextureScaled(texture, x, y, w, h, alpha or 1.0, 1.0, 1.0, 1.0)
        return true
    end
    return false
end

function EHR_StitchMinigameUI:drawThreadLine(x1, y1, x2, y2, color, alpha, width)
    color = color or C.thread
    alpha = alpha or color.a or 1.0
    width = math.max(1, math.floor(width or 1))

    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end

    -- drawLine2 can escape this panel on some B42 UI paths, so draw the
    -- thread as dense local rect segments instead.
    local step = math.max(1.5, width * 0.55)
    local steps = math.max(1, math.ceil(len / step))
    local half = math.floor(width / 2)
    for i = 0, steps do
        local t = i / steps
        local x = x1 + dx * t
        local y = y1 + dy * t
        self:drawRect(math.floor(x - half), math.floor(y - half), width, width, alpha, color.r, color.g, color.b)
    end
end

function EHR_StitchMinigameUI:drawStitchMark(point, color, alpha)
    if not point then return end
    local x = point.hitX or point.x
    local y = point.hitY or point.y
    if not x or not y then return end

    local size = 7
    local angleX = 0.72
    local angleY = self.orientation == "horizontal" and 0.42 or -0.42
    self:drawThreadLine(x - size * angleX, y - size * angleY, x + size * angleX, y + size * angleY, color or C.thread, alpha or 0.85, 2)
end

function EHR_StitchMinigameUI:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, self.width, self.height, C.bg.a, C.bg.r, C.bg.g, C.bg.b)
    self:drawTextureSafe("media/textures/EHR_Stitch_PanelGrime.png", 0, 42, self.width, self.height - 42, 0.42)
    self:drawRectBorder(0, 0, self.width, self.height, 0.95, C.red.r, C.red.g, C.red.b)
    self:drawRect(0, 0, self.width, 42, 0.96, 0.07, 0.01, 0.01)
    self:drawText(L("Title", "Suture Wound"), 16, 8, C.text.r, C.text.g, C.text.b, C.text.a, UIFont.Medium)
end

function EHR_StitchMinigameUI:render()
    ISPanel.render(self)
    self:updatePointMotion()

    local partName = bodyPartName(self.bodyPart)
    self:drawText(L("Target", "Target") .. ": " .. partName, 24, 54, C.text.r, C.text.g, C.text.b, C.text.a, UIFont.Small)
    self:drawText(L("Hint", "Click each glowing stitch point in order."), 24, 78, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)

    local qualityText, qualityColor = self:qualityText()
    self:drawText(L("Quality", "Quality") .. ": " .. qualityText, self.width - 190, 54, qualityColor.r, qualityColor.g, qualityColor.b, qualityColor.a, UIFont.Small)
    self:drawText(L("Misses", "Misses") .. ": " .. tostring(self.misses) .. "/" .. tostring(self.maxMisses), self.width - 190, 96, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)

    self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, C.panel.a, C.panel.r, C.panel.g, C.panel.b)
    self:drawRectBorder(self.boardX, self.boardY, self.boardW, self.boardH, 0.72, C.redDim.r, C.redDim.g, C.redDim.b)

    local woundPath = self.orientation == "horizontal"
        and "media/textures/EHR_Stitch_WoundHorizontal.png"
        or "media/textures/EHR_Stitch_WoundVertical.png"
    local hasWoundTexture = self:drawTextureSafe(woundPath, self.boardX + 2, self.boardY + 2, self.boardW - 4, self.boardH - 4, 0.98)

    if not hasWoundTexture and self.orientation == "horizontal" then
        local cy = self.boardY + math.floor(self.boardH / 2)
        self:drawRect(self.boardX + 34, cy - 4, self.boardW - 68, 8, 0.70, C.red.r, C.red.g, C.red.b)
        self:drawRect(self.boardX + 52, cy - 18, self.boardW - 104, 36, 0.18, 0.95, 0.05, 0.05)
    elseif not hasWoundTexture then
        local cx = self.boardX + math.floor(self.boardW / 2)
        self:drawRect(cx - 4, self.boardY + 22, 8, self.boardH - 44, 0.70, C.red.r, C.red.g, C.red.b)
        self:drawRect(cx - 18, self.boardY + 34, 36, self.boardH - 68, 0.18, 0.95, 0.05, 0.05)
    end

    for i = 1, #self.points - 1 do
        if self.points[i].hit and self.points[i + 1].hit then
            local a = self.points[i]
            local b = self.points[i + 1]
            self:drawThreadLine(a.hitX or a.x, a.hitY or a.y, b.hitX or b.x, b.hitY or b.y, C.woundDark, 0.52, 5)
            self:drawThreadLine(a.hitX or a.x, a.hitY or a.y, b.hitX or b.x, b.hitY or b.y, C.thread, 0.95, 3)
        end
    end

    if self.currentIndex > 1 and self.currentIndex <= #self.points then
        local prev = self.points[self.currentIndex - 1]
        local current = self.points[self.currentIndex]
        local cx, cy = self:getPointPosition(current, self.currentIndex)
        self:drawThreadLine(prev.hitX or prev.x, prev.hitY or prev.y, cx, cy, C.threadLive, 0.50, 1)
    end

    for i, point in ipairs(self.points) do
        local color = C.dim
        local size = self.pointSize or 10
        local path = "media/textures/EHR_Stitch_PointIdle.png"
        if point.hit then
            color = C.green
            size = self.hitPointSize or 9
            path = "media/textures/EHR_Stitch_PointDone.png"
            self:drawStitchMark(point, C.thread, 0.86)
        elseif i == self.currentIndex then
            color = self.flash < 0 and C.bad or C.gold
            size = self.activePointSize or 18
            path = "media/textures/EHR_Stitch_PointActive.png"
            self:drawRectBorder(point.x - size, point.y - size, size * 2, size * 2, 0.35, color.r, color.g, color.b)
        end
        local textureSize = size + (i == self.currentIndex and 16 or 10)
        local usedTexture = self:drawTextureSafe(path, point.x - math.floor(textureSize / 2), point.y - math.floor(textureSize / 2), textureSize, textureSize, 1.0)
        if not usedTexture then
            self:drawRect(point.x - math.floor(size / 2), point.y - math.floor(size / 2), size, size, color.a, color.r, color.g, color.b)
            self:drawRectBorder(point.x - math.floor(size / 2), point.y - math.floor(size / 2), size, size, 0.85, C.text.r, C.text.g, C.text.b)
        end
    end

    self:drawText(L("Steady", "Steady hand reduces pain and infection risk."), 24, self.height - 34, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
end

function EHR.StitchMinigame.Open(character, otherPlayer, item, bodyPart)
    if EHR_StitchMinigameUI.instance then
        EHR_StitchMinigameUI.instance:close()
    end

    local width = 560
    local height = 450
    local x = math.floor((getCore():getScreenWidth() - width) / 2)
    local y = math.floor((getCore():getScreenHeight() - height) / 2)
    local ui = EHR_StitchMinigameUI:new(x, y, width, height, character, otherPlayer, item, bodyPart)
    ui:initialise()
    ui:instantiate()
    ui:addToUIManager()
    ui:bringToTop()
    EHR_StitchMinigameUI.instance = ui
end

local function installHook()
    if not ISStitch or not ISStitch.new or EHR.StitchMinigame._installed then
        return
    end

    EHR.StitchMinigame._installed = true
    EHR.StitchMinigame._originalNew = ISStitch.new
    EHR.StitchMinigame._originalComplete = ISStitch.complete

    function ISStitch:new(character, otherPlayer, item, bodyPart, doIt)
        if EHR.StitchMinigame.ShouldIntercept(character, otherPlayer, item, bodyPart, doIt) then
            return EHR_StitchMinigameAction:new(character, otherPlayer, item, bodyPart)
        end
        return EHR.StitchMinigame._originalNew(self, character, otherPlayer, item, bodyPart, doIt)
    end

    function ISStitch:complete()
        local result = EHR.StitchMinigame._originalComplete(self)
        if result then
            EHR.StitchMinigame.ApplyQuality(self)
        end
        return result
    end
end

installHook()
