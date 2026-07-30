-- Extensive Health Rework B42
-- Medicinal plant search mini-game.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/WalkToTimedAction"
require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.HerbalSearch = EHR.HerbalSearch or {}

local COOLDOWN_HOURS = 48

local C = {
    bg = { r = 0.014, g = 0.012, b = 0.010, a = 0.97 },
    panel = { r = 0.032, g = 0.045, b = 0.030, a = 0.92 },
    green = { r = 0.20, g = 0.90, b = 0.30, a = 1.0 },
    greenDim = { r = 0.08, g = 0.35, b = 0.12, a = 1.0 },
    red = { r = 0.86, g = 0.055, b = 0.045, a = 1.0 },
    gold = { r = 1.00, g = 0.68, b = 0.20, a = 1.0 },
    cyan = { r = 0.22, g = 0.84, b = 1.00, a = 1.0 },
    text = { r = 0.92, g = 0.90, b = 0.84, a = 1.0 },
    dim = { r = 0.62, g = 0.60, b = 0.56, a = 1.0 },
    bad = { r = 1.00, g = 0.28, b = 0.12, a = 1.0 },
}

local TextureCache = {}
local function tex(path)
    if not path or not getTexture then return nil end
    if TextureCache[path] == nil then TextureCache[path] = getTexture(path) or false end
    if TextureCache[path] == false then return nil end
    return TextureCache[path]
end

local function L(key, fallback)
    local fullKey = "UI_EHR_HerbalSearch_" .. tostring(key)
    if EHR and EHR.Locale and EHR.Locale.Text then return EHR.Locale.Text(fullKey, fallback) end
    if getText then
        local ok, value = pcall(getText, fullKey)
        if ok and value and value ~= fullKey then return value end
    end
    return fallback
end

local function say(player, key, fallback)
    if not player then return end
    local text = L(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Say then EHR.Locale.Say(player, text)
    elseif player.Say then player:Say(text) end
end

local function rand(max)
    max = tonumber(max) or 0
    if max <= 0 then return 0 end
    if ZombRand then return ZombRand(max) end
    return math.random(0, max - 1)
end

local function getPerkLevel(player, perk)
    if not player or not perk or not player.getPerkLevel then return 0 end
    local ok, level = pcall(function() return player:getPerkLevel(perk) end)
    if ok then return tonumber(level) or 0 end
    return 0
end

local function isHandWearLocation(location)
    local loc = tostring(location or ""):lower()
    return loc == "hands" or loc == "base:hands" or loc == "handsleft" or loc == "handsright"
end

local function isBrokenOrHoled(item)
    if not item then return true end
    local holes = 0
    pcall(function()
        if item.getHolesNumber then holes = tonumber(item:getHolesNumber()) or 0 end
    end)
    if holes > 0 then return true end

    local condition, conditionMax = nil, nil
    pcall(function() if item.getCondition then condition = tonumber(item:getCondition()) end end)
    pcall(function() if item.getConditionMax then conditionMax = tonumber(item:getConditionMax()) end end)
    if condition and condition <= 0 then return true end
    if condition and conditionMax and conditionMax > 0 and (condition / conditionMax) <= 0.05 then return true end
    return false
end

function EHR.HerbalSearch.HasIntactGloves(player)
    if not player then return false end

    if player.getWornItem and ItemBodyLocation then
        local locations = { ItemBodyLocation.HANDS, ItemBodyLocation.HANDS_LEFT, ItemBodyLocation.HANDS_RIGHT }
        for _, location in ipairs(locations) do
            local item = nil
            pcall(function() if location then item = player:getWornItem(location) end end)
            if item and not isBrokenOrHoled(item) then return true end
        end
    end

    if not player.getWornItems then return false end
    local wornItems = player:getWornItems()
    if not wornItems then return false end
    for i = 0, wornItems:size() - 1 do
        local item = wornItems:getItemByIndex(i)
        if item then
            local location = nil
            pcall(function() if item.getBodyLocation then location = item:getBodyLocation() end end)
            if not location then pcall(function() if item.getLocation then location = item:getLocation() end end) end
            if isHandWearLocation(location) and not isBrokenOrHoled(item) then return true end
        end
    end
    return false
end

function EHR.HerbalSearch.HasWildPlantsKnowledge(player)
    if not player then return false end
    local data = player.getModData and player:getModData() or nil
    if data and data.EHR_MedicalWildPlantsKnown == true then return true end
    return getPerkLevel(player, Perks and Perks.Doctor) >= 4
        and getPerkLevel(player, Perks and Perks.PlantScavenging) >= 4
end

local function squareDistance(player, square)
    if not player or not square then return 999 end
    local dx = (player:getX() or 0) - ((square.getX and square:getX()) or 0)
    local dy = (player:getY() or 0) - ((square.getY and square:getY()) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function cooldownRemaining(square)
    if not square or not square.getModData then return 0 end
    local data = square:getModData()
    if not data then return 0 end
    local last = tonumber(data.EHR_HerbalSearchLastHour)
    if not last then return 0 end
    local now = 0
    pcall(function() now = getGameTime():getWorldAgeHours() end)
    local remaining = COOLDOWN_HOURS - (now - last)
    if remaining > 0 then return remaining end
    return 0
end

local function isDepleted(square)
    return cooldownRemaining(square) > 0
end

local function squareArgs(square)
    if not square then return nil end
    local args = {}
    pcall(function() args.x = square:getX(); args.y = square:getY(); args.z = square:getZ() end)
    if args.x == nil or args.y == nil then return nil end
    args.z = args.z or 0
    return args
end

local function squareFromArgs(args)
    if not args then return nil end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 0
    if not x or not y then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    return ok and square or nil
end

local function playerNumOf(player)
    local playerNum = 0
    pcall(function()
        if player and player.getPlayerNum then playerNum = tonumber(player:getPlayerNum()) or 0 end
    end)
    return playerNum
end

local function queueSearchAction(player, square)
    if not player or not square then return end
    if isDepleted(square) then
        say(player, "Depleted", "This patch has already been searched recently.")
        return
    end
    if squareDistance(player, square) > 1.8 and ISWalkToTimedAction then ISTimedActionQueue.add(ISWalkToTimedAction:new(player, square)) end
    ISTimedActionQueue.add(EHR_HerbalSearchAction:new(player, square))
end

local function spriteName(obj)
    if not obj then return nil end
    local sprite = nil
    pcall(function() sprite = obj:getSprite() end)
    if not sprite then return nil end
    local name = nil
    pcall(function() name = sprite:getName() end)
    return name and tostring(name):lower() or nil
end

local function spriteLooksSearchableNature(name)
    if not name then return false end
    if name:match("^location[_%-]") then return false end
    if name:match("^street[_%-]") then return false end
    if name:match("^fixtures[_%-]") then return false end
    if name:match("^furniture[_%-]") then return false end
    if name:match("^appliances[_%-]") then return false end
    if name:match("^crafted[_%-]") then return false end
    if name:match("^industry[_%-]") then return false end
    if name:match("^trash[_%-]") then return false end

    return name:match("^vegetation[_%-]") ~= nil
        or name:match("^blends_natural[_%-]") ~= nil
        or name:match("^d_floorblends[_%-]") ~= nil
end

local function objectLooksNatural(obj)
    local name = spriteName(obj)
    if not name then return false end
    return spriteLooksSearchableNature(name)
end

local function squareLooksNatural(square)
    if not square then return false end
    local room = nil
    pcall(function() room = square:getRoom() end)
    if room then return false end
    local objects = nil
    pcall(function() objects = square:getObjects() end)
    if objects then
        for i = 0, objects:size() - 1 do
            if objectLooksNatural(objects:get(i)) then return true end
        end
    end
    return false
end

local function getZoneType(square)
    local zone = nil
    pcall(function() zone = square and square:getZone() or nil end)
    if not zone then return "" end
    local zoneType = nil
    pcall(function() zoneType = zone:getType() end)
    return tostring(zoneType or "")
end

local function hashSquare(square)
    if not square then return 0 end
    local x = square.getX and square:getX() or 0
    local y = square.getY and square:getY() or 0
    local z = square.getZ and square:getZ() or 0
    local h = (x * 73856093 + y * 19349663 + z * 83492791) % 10000
    if h < 0 then h = -h end
    return h
end

local function menuDensity(square)
    local zone = getZoneType(square):lower()
    if zone:find("deepforest", 1, true) then return 68 end
    if zone:find("forest", 1, true) then return 56 end
    if zone:find("vegetation", 1, true) or zone:find("vegitation", 1, true) then return 46 end
    if zone:find("farm", 1, true) or zone:find("garden", 1, true) then return 34 end
    return 24
end

local function isSearchPatch(square)
    return squareLooksNatural(square) and (hashSquare(square) % 100) < menuDensity(square)
end

local function findSearchSquare(worldObjects)
    if not worldObjects then return nil end
    for _, obj in ipairs(worldObjects) do
        local square = nil
        pcall(function() square = obj:getSquare() end)
        if square and isSearchPatch(square) then return square end
    end
    return nil
end

EHR_HerbalSearchAction = ISBaseTimedAction:derive("EHR_HerbalSearchAction")

function EHR_HerbalSearchAction:isValid()
    return self.character ~= nil and self.square ~= nil and squareDistance(self.character, self.square) <= 3.8
end

function EHR_HerbalSearchAction:start()
    self.maxTime = 24
    pcall(function() self:setActionAnim("Forage") end)
end

function EHR_HerbalSearchAction:perform()
    if isDepleted(self.square) then
        say(self.character, "Depleted", "This patch has already been searched recently.")
        ISBaseTimedAction.perform(self)
        return
    end
    EHR.HerbalSearch.Open(self.character, self.square)
    ISBaseTimedAction.perform(self)
end

function EHR_HerbalSearchAction:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.square = square
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = 24
    return o
end

EHR_HerbalSearchUI = ISPanel:derive("EHR_HerbalSearchUI")
EHR_HerbalSearchUI.instance = nil

function EHR_HerbalSearchUI:new(x, y, width, height, character, square)
    local o = ISPanel.new(self, x, y, width, height)
    o.character = character
    o.square = square
    o.background = false
    o.borderColor = C.greenDim
    o.boardX = 24
    o.boardY = 130
    o.boardW = width - 48
    o.boardH = height - 204
    o.points = {}
    o.selected = 0
    o.hits = 0
    o.misses = 0
    o.hazards = 0
    o.finished = false
    o.flash = 0
    o.firstAid = getPerkLevel(character, Perks and Perks.Doctor)
    o.foraging = getPerkLevel(character, Perks and Perks.PlantScavenging)
    o.requiredHits = 3
    o.maxPicks = math.min(10, 8 + math.floor((o.foraging or 0) / 4))
    o.startX = character and character.getX and character:getX() or 0
    o.startY = character and character.getY and character:getY() or 0
    o.startedAt = getTimestampMs and getTimestampMs() or 0
    o.durationMs = 42000
    o.tickAge = 0
    o:generatePoints()
    return o
end

function EHR_HerbalSearchUI:createChildren()
    ISPanel.createChildren(self)
    self.cancelButton = ISButton:new(self.width - 88, 8, 72, 26, L("Cancel", "Cancel"), self, EHR_HerbalSearchUI.onCancel)
    self.cancelButton:initialise()
    self.cancelButton:instantiate()
    self:addChild(self.cancelButton)
end

function EHR_HerbalSearchUI:shuffle(list)
    for i = #list, 2, -1 do
        local j = rand(i) + 1
        list[i], list[j] = list[j], list[i]
    end
end

function EHR_HerbalSearchUI:generatePoints()
    local types = {}
    for _ = 1, 5 do types[#types + 1] = "target" end
    for _ = 1, 2 do types[#types + 1] = "hazard" end
    for _ = 1, 9 do types[#types + 1] = "decoy" end
    self:shuffle(types)

    local cols, rows = 4, 4
    local cellW = self.boardW / cols
    local cellH = self.boardH / rows
    for i, pointType in ipairs(types) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = self.boardX + math.floor(col * cellW + cellW * 0.5) + rand(math.floor(cellW * 0.46)) - math.floor(cellW * 0.23)
        local y = self.boardY + math.floor(row * cellH + cellH * 0.5) + rand(math.floor(cellH * 0.46)) - math.floor(cellH * 0.23)
        self.points[#self.points + 1] = { kind = pointType, x = x, y = y, size = pointType == "hazard" and 28 or 25, selected = false }
    end
end

function EHR_HerbalSearchUI:close()
    if EHR_HerbalSearchUI.instance == self then EHR_HerbalSearchUI.instance = nil end
    self:setVisible(false)
    self:removeFromUIManager()
end

function EHR_HerbalSearchUI:onCancel()
    self.finished = true
    self:close()
end

function EHR_HerbalSearchUI:rawQuality()
    local skillFactor = math.min(1, ((self.firstAid or 0) + (self.foraging or 0)) / 16)
    local q = 0.18 + ((self.hits or 0) / math.max(1, self.requiredHits)) * 0.58 + skillFactor * 0.14
    q = q - (self.misses or 0) * 0.08 - (self.hazards or 0) * 0.12
    if q < 0.05 then q = 0.05 end
    if q > 1.0 then q = 1.0 end
    return q
end

function EHR_HerbalSearchUI:quality()
    local q = self:rawQuality()
    if not self.bestQuality or q > self.bestQuality then
        self.bestQuality = q
    end
    return self.bestQuality
end

function EHR_HerbalSearchUI:qualityText()
    local q = self:quality()
    if q >= 0.82 then return L("QualityExcellent", "Excellent"), C.green end
    if q >= 0.60 then return L("QualityGood", "Good"), C.cyan end
    if q >= 0.38 then return L("QualityRough", "Rough"), C.gold end
    return L("QualityPoor", "Poor"), C.bad
end

function EHR_HerbalSearchUI:remainingSeconds()
    if getTimestampMs then
        local elapsed = getTimestampMs() - (self.startedAt or getTimestampMs())
        return math.max(0, math.ceil(((self.durationMs or 42000) - elapsed) / 1000))
    end
    return math.max(0, math.ceil((2500 - (self.tickAge or 0)) / 60))
end

function EHR_HerbalSearchUI:reportHazard()
    if not self.character or not self.square then return end
    local args = { x = self.square:getX(), y = self.square:getY(), z = self.square:getZ() }
    if isClient and isClient() and sendClientCommand then
        sendClientCommand(self.character, "EHR_HerbalSearch", "Hazard", args)
    elseif EHR.HerbalSearchServer and EHR.HerbalSearchServer.Hazard then
        EHR.HerbalSearchServer.Hazard(self.character, args)
    end
end

function EHR_HerbalSearchUI:finish()
    if self.finished then return end
    self.finished = true
    local args = {
        x = self.square:getX(), y = self.square:getY(), z = self.square:getZ(),
        hits = self.hits or 0, misses = self.misses or 0, hazards = self.hazards or 0,
        quality = self:quality(), firstAid = self.firstAid or 0, foraging = self.foraging or 0,
    }
    if isClient and isClient() and sendClientCommand then
        sendClientCommand(self.character, "EHR_HerbalSearch", "Complete", args)
    elseif EHR.HerbalSearchServer and EHR.HerbalSearchServer.Complete then
        EHR.HerbalSearchServer.Complete(self.character, args)
    end
    self:close()
end

function EHR_HerbalSearchUI:update()
    ISPanel.update(self)
    self.tickAge = (self.tickAge or 0) + 1
    if self.flash > 0 then self.flash = self.flash - 1 end
    if self.flash < 0 then self.flash = self.flash + 1 end
    if self.finished then return end
    if not self.character or not self.square or squareDistance(self.character, self.square) > 4.2 then self:close(); return end
    if self.character.getX and (math.abs(self.character:getX() - self.startX) > 0.6 or math.abs(self.character:getY() - self.startY) > 0.6) then self:close(); return end
    if self:remainingSeconds() <= 0 then self:finish() end
end

function EHR_HerbalSearchUI:onMouseDown(x, y)
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
    if x < self.boardX or x > self.boardX + self.boardW or y < self.boardY or y > self.boardY + self.boardH then return true end

    local clicked, clickedDistance = nil, 999
    for _, point in ipairs(self.points or {}) do
        if not point.selected then
            local dx, dy = x - point.x, y - point.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < clickedDistance and d <= (point.size or 24) * 0.72 then clicked, clickedDistance = point, d end
        end
    end
    self.selected = self.selected + 1
    if clicked then
        clicked.selected = true
        if clicked.kind == "target" then self.hits = self.hits + 1; self.flash = 9
        elseif clicked.kind == "hazard" then
            self.hazards = self.hazards + 1
            self.flash = -13
            if EHR.HerbalSearch.HasIntactGloves(self.character) then
                say(self.character, "GlovesLine", "The glove catches the thorn.")
            else
                say(self.character, "HazardLine", "Ow. Something scratched me.")
            end
            self:reportHazard()
        else self.misses = self.misses + 1; self.flash = -8 end
    else
        self.misses = self.misses + 1
        self.flash = -8
    end
    if self.hits >= self.requiredHits or self.selected >= self.maxPicks then self:finish() end
    return true
end

function EHR_HerbalSearchUI:onMouseMove(dx, dy)
    if self.dragging then
        local newX = self.dragStartX + (getMouseX() - self.dragMouseStartX)
        local newY = self.dragStartY + (getMouseY() - self.dragMouseStartY)
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

function EHR_HerbalSearchUI:onMouseMoveOutside(dx, dy)
    if self.dragging then return self:onMouseMove(dx, dy) end
    if ISPanel.onMouseMoveOutside then return ISPanel.onMouseMoveOutside(self, dx, dy) end
    return false
end

function EHR_HerbalSearchUI:onMouseUp(x, y)
    self.dragging = false
    return ISPanel.onMouseUp(self, x, y)
end

function EHR_HerbalSearchUI:onMouseUpOutside(x, y)
    self.dragging = false
    if ISPanel.onMouseUpOutside then return ISPanel.onMouseUpOutside(self, x, y) end
    return true
end

function EHR_HerbalSearchUI:drawTextureSafe(path, x, y, w, h, alpha)
    local texture = tex(path)
    if texture and self.drawTextureScaled then
        self:drawTextureScaled(texture, x, y, w, h, alpha or 1.0, 1.0, 1.0, 1.0)
        return true
    end
    return false
end

function EHR_HerbalSearchUI:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, self.width, self.height, C.bg.a, C.bg.r, C.bg.g, C.bg.b)
    self:drawRectBorder(0, 0, self.width, self.height, 0.95, C.greenDim.r, C.greenDim.g, C.greenDim.b)
    self:drawRect(0, 0, self.width, 42, 0.96, 0.018, 0.05, 0.020)
    self:drawText(L("Title", "Medicinal Plant Search"), 16, 8, C.text.r, C.text.g, C.text.b, C.text.a, UIFont.Medium)
end

function EHR_HerbalSearchUI:render()
    ISPanel.render(self)
    self:drawText(L("Target", "Find promising plants"), 24, 54, C.text.r, C.text.g, C.text.b, C.text.a, UIFont.Small)
    local qText, qColor = self:qualityText()
    self:drawText(L("Quality", "Search Rating") .. ": " .. qText, self.width - 230, 54, qColor.r, qColor.g, qColor.b, qColor.a, UIFont.Small)
    self:drawText(L("Samples", "Samples") .. ": " .. tostring(self.hits) .. "/" .. tostring(self.requiredHits), self.width - 230, 78, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
    self:drawText(L("Time", "Time") .. ": " .. tostring(self:remainingSeconds()) .. "s", self.width - 230, 100, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
    self:drawText(L("HintLine1", "Inspect covered plant signs."), 24, 82, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
    self:drawText(L("HintLine2", "Some hide thorns or dead growth."), 24, 104, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
    self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, C.panel.a, C.panel.r, C.panel.g, C.panel.b)
    if not self:drawTextureSafe("media/textures/EHR_HerbalSearch_Background.png", self.boardX, self.boardY, self.boardW, self.boardH, 0.88) then
        self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, 0.44, 0.04, 0.07, 0.04)
    end
    self:drawRectBorder(self.boardX, self.boardY, self.boardW, self.boardH, 0.85, C.greenDim.r, C.greenDim.g, C.greenDim.b)
    if self.flash > 0 then self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, 0.09, 0.1, 1.0, 0.18)
    elseif self.flash < 0 then self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, 0.13, 1.0, 0.08, 0.04) end
    for _, point in ipairs(self.points or {}) do
        local size = point.size or 24
        local path = "media/textures/EHR_HerbalSearch_Marker.png"
        local alpha = 0.92
        if point.selected then
            path = "media/textures/EHR_HerbalSearch_Decoy.png"
            alpha = 0.96
            if point.kind == "target" then path = "media/textures/EHR_HerbalSearch_Leaf.png" end
            if point.kind == "hazard" then path = "media/textures/EHR_HerbalSearch_Thorn.png" end
        end
        if not self:drawTextureSafe(path, point.x - size / 2, point.y - size / 2, size, size, alpha) then
            local c = C.dim
            if point.selected then c = point.kind == "target" and C.green or (point.kind == "hazard" and C.red or C.dim) end
            self:drawRect(point.x - size / 2, point.y - size / 2, size, size, alpha, c.r, c.g, c.b)
        end
        if point.selected then self:drawRectBorder(point.x - size / 2 - 2, point.y - size / 2 - 2, size + 4, size + 4, 0.9, C.gold.r, C.gold.g, C.gold.b) end
    end
    self:drawText(L("FinishHint", "Careful hands improve the chance of a useful find."), 24, self.height - 34, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
    self:drawText(L("Picks", "Picks") .. ": " .. tostring(self.selected) .. "/" .. tostring(self.maxPicks), self.width - 112, self.height - 34, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
end

function EHR.HerbalSearch.Open(player, square)
    if EHR_HerbalSearchUI.instance then EHR_HerbalSearchUI.instance:close() end
    local core = getCore and getCore()
    local sw = core and core:getScreenWidth() or 1280
    local sh = core and core:getScreenHeight() or 720
    local w, h = 620, 450
    local ui = EHR_HerbalSearchUI:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, player, square)
    ui:initialise()
    ui:addToUIManager()
    EHR_HerbalSearchUI.instance = ui
end

function EHR.HerbalSearch.OnSearch(player, square)
    if not player or not square then return end
    if isDepleted(square) then
        say(player, "Depleted", "This patch has already been searched recently.")
        return
    end
    if isClient and isClient() and sendClientCommand then
        local args = squareArgs(square)
        if not args then return end
        args.playerNum = playerNumOf(player)
        sendClientCommand(player, "EHR_HerbalSearch", "RequestStart", args)
        return
    end
    queueSearchAction(player, square)
end

function EHR.HerbalSearch.OnServerCommand(module, command, args)
    if module ~= "EHR_HerbalSearch" then return end
    if command ~= "StartApproved" and command ~= "StartDenied" then return end

    local playerNum = tonumber(args and args.playerNum) or 0
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player and getPlayer then player = getPlayer() end
    if not player then return end

    local square = squareFromArgs(args)
    if command == "StartDenied" then
        if square and square.getModData and args and args.lastHour ~= nil then
            local md = square:getModData()
            if md then md.EHR_HerbalSearchLastHour = tonumber(args.lastHour) end
        end
        say(player, "Depleted", "This patch has already been searched recently.")
        return
    end

    queueSearchAction(player, square)
end

function EHR.HerbalSearch.OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    if not EHR.HerbalSearch.HasWildPlantsKnowledge(player) then return end
    local square = findSearchSquare(worldObjects)
    if not square then return end
    local optionText = L("Context", "Search medicinal plants")
    local option = context.addOptionOnTop and context:addOptionOnTop(optionText, player, EHR.HerbalSearch.OnSearch, square)
        or context:addOption(optionText, player, EHR.HerbalSearch.OnSearch, square)
    if option and getTexture then option.iconTexture = getTexture("media/textures/EHR_SearchPlants.png") end
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(optionText)
    tooltip.description = L("ContextDesc", "Search nearby vegetation for medicinal herbs. Not every patch has anything useful.")
    option.toolTip = tooltip
end

if not EHR.HerbalSearch._registered then
    EHR.HerbalSearch._registered = true
    Events.OnFillWorldObjectContextMenu.Add(EHR.HerbalSearch.OnFillWorldObjectContextMenu)
    if Events.OnServerCommand then Events.OnServerCommand.Add(EHR.HerbalSearch.OnServerCommand) end
    if EHR and EHR.Log then EHR.Log("HerbalSearch: context menu registered") end
end
