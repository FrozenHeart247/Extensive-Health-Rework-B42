-- Extensive Health Rework B42
-- Tree hive and spiderweb gathering mini-game.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/WalkToTimedAction"
require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)

EHR = EHR or {}
EHR.HiveWebSearch = EHR.HiveWebSearch or {}

local C = {
    bg = { r = 0.018, g = 0.012, b = 0.008, a = 0.97 },
    panel = { r = 0.035, g = 0.023, b = 0.015, a = 0.94 },
    trunk = { r = 0.24, g = 0.13, b = 0.055, a = 1.0 },
    trunkDark = { r = 0.11, g = 0.055, b = 0.025, a = 1.0 },
    red = { r = 0.88, g = 0.055, b = 0.04, a = 1.0 },
    gold = { r = 1.0, g = 0.66, b = 0.16, a = 1.0 },
    green = { r = 0.26, g = 0.9, b = 0.28, a = 1.0 },
    text = { r = 0.92, g = 0.90, b = 0.84, a = 1.0 },
    dim = { r = 0.64, g = 0.62, b = 0.57, a = 1.0 },
}

local HAND_W = 32
local HAND_H = 32
local HAND_HIT_W = 24
local HAND_HIT_H = 24

local TextureCache = {}
local function tex(path)
    if not path or not getTexture then return nil end
    if TextureCache[path] == nil then TextureCache[path] = getTexture(path) or false end
    if TextureCache[path] == false then return nil end
    return TextureCache[path]
end

local function L(key, fallback)
    local fullKey = "UI_EHR_HiveWebSearch_" .. tostring(key)
    if EHR and EHR.Locale and EHR.Locale.Text then return EHR.Locale.Text(fullKey, fallback) end
    if getText then
        local ok, value = pcall(getText, fullKey)
        if ok and value and value ~= fullKey then return value end
    end
    return fallback
end

local function say(player, key, fallback)
    if not player then return end
    local msg = L(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Say then EHR.Locale.Say(player, msg)
    elseif player.Say then player:Say(msg) end
end

local function rand(max)
    max = tonumber(max) or 0
    if max <= 0 then return 0 end
    if ZombRand then return ZombRand(max) end
    return math.random(0, max - 1)
end

local function playerNumOf(player)
    local playerNum = 0
    pcall(function()
        if player and player.getPlayerNum then playerNum = tonumber(player:getPlayerNum()) or 0 end
    end)
    return playerNum
end

local function squareDistance(player, square)
    if not player or not square then return 999 end
    local dx = (player:getX() or 0) - ((square.getX and square:getX()) or 0)
    local dy = (player:getY() or 0) - ((square.getY and square:getY()) or 0)
    return math.sqrt(dx * dx + dy * dy)
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

local function spriteName(obj)
    if not obj then return nil end
    local sprite = nil
    pcall(function() sprite = obj:getSprite() end)
    if not sprite then return nil end
    local name = nil
    pcall(function() name = sprite:getName() end)
    return name and tostring(name):lower() or nil
end

local function isTreeObject(obj)
    if not obj then return false end
    if instanceof then
        local ok, result = pcall(function() return instanceof(obj, "IsoTree") end)
        if ok and result == true then return true end
    end
    if IsoObjectType and IsoObjectType.tree and obj.getType then
        local ok, result = pcall(function() return obj:getType() == IsoObjectType.tree end)
        if ok and result == true then return true end
    end
    return false
end

local function spriteLooksTree(name)
    if not name then return false end
    if name:find("vegetation_trees", 1, true) ~= nil then return true end
    if name:find("jumbo_tree", 1, true) ~= nil then return true end
    if name:match("^trees?[_%-]") then return true end
    if name:match("[_%-]trees?[_%-]") then return true end
    return false
end

local function objectLooksTree(obj)
    if isTreeObject(obj) then return true end
    local name = spriteName(obj)
    if not name then return false end
    return spriteLooksTree(name)
end

local function squareLooksTree(square)
    if not square then return false end
    if not square.getObjects then return false end
    local room = nil
    if square.getRoom then
        room = square:getRoom()
    end
    if room then return false end
    local objects = square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            if objectLooksTree(objects:get(i)) then return true end
        end
    end
    return false
end

local function findTreeSquare(worldObjects)
    if not worldObjects then return nil end
    for _, obj in ipairs(worldObjects) do
        local objSquare = nil
        pcall(function() if obj and obj.getSquare then objSquare = obj:getSquare() end end)
        if objSquare and squareLooksTree(objSquare) then return objSquare end
        if objectLooksTree(obj) then
            local square = nil
            pcall(function() square = obj:getSquare() end)
            if square and squareLooksTree(square) then return square end
        end
    end
    return nil
end

local function queueSearchAction(player, square, config)
    if not player or not square then return end
    if squareDistance(player, square) > 1.8 and ISWalkToTimedAction then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, square))
    end
    ISTimedActionQueue.add(EHR_HiveWebSearchAction:new(player, square, config))
end

EHR_HiveWebSearchAction = ISBaseTimedAction:derive("EHR_HiveWebSearchAction")

function EHR_HiveWebSearchAction:isValid()
    return self.character and self.square and squareDistance(self.character, self.square) <= 4.5
end

function EHR_HiveWebSearchAction:start()
    if self.character and self.character.faceLocationF then
        pcall(function() self.character:faceLocationF(self.square:getX(), self.square:getY()) end)
    end
end

function EHR_HiveWebSearchAction:perform()
    ISBaseTimedAction.perform(self)
    EHR.HiveWebSearch.Open(self.character, self.square, self.config)
end

function EHR_HiveWebSearchAction:new(character, square, config)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.square = square
    o.config = config or {}
    o.maxTime = 22
    if character and character.isTimedActionInstant and character:isTimedActionInstant() then o.maxTime = 1 end
    return o
end

EHR_HiveWebSearchUI = ISPanel:derive("EHR_HiveWebSearchUI")
EHR_HiveWebSearchUI.instance = nil

function EHR_HiveWebSearchUI:new(x, y, width, height, character, square, config)
    local o = ISPanel.new(self, x, y, width, height)
    o.character = character
    o.square = square
    o.config = config or {}
    o.background = false
    o.borderColor = C.gold
    o.boardX = 24
    o.boardY = 112
    o.boardW = width - 48
    o.boardH = height - 170
    o.treeRect = { x = o.boardX + math.floor(o.boardW * 0.43), y = o.boardY + 44, w = 110, h = o.boardH - 56 }
    o.hive = nil
    o.webs = {}
    o.bees = {}
    o.spiders = {}
    o.handActive = false
    o.finished = false
    o.flash = 0
    o.startX = character and character.getX and character:getX() or 0
    o.startY = character and character.getY and character:getY() or 0
    o.lastMs = getTimestampMs and getTimestampMs() or 0
    o.startedAt = o.lastMs
    o.durationMs = 48000
    o:generateScene()
    return o
end

function EHR_HiveWebSearchUI:createChildren()
    ISPanel.createChildren(self)
    self.cancelButton = ISButton:new(self.width - 88, 8, 72, 26, L("Cancel", "Cancel"), self, EHR_HiveWebSearchUI.onCancel)
    self.cancelButton:initialise()
    self.cancelButton:instantiate()
    self:addChild(self.cancelButton)
end

function EHR_HiveWebSearchUI:generateScene()
    if self.config.hive == true or tostring(self.config.hive) == "true" then
        self.hive = { kind = "hive", x = self.boardX + math.floor(self.boardW * 0.5) - 55, y = self.boardY + 14, w = 110, h = 80 }
        for i = 1, 9 do
            local zone = { x = self.hive.x - 84, y = self.hive.y - 18, w = self.hive.w + 168, h = 150 }
            local speed = 150 + rand(55)
            local angle = (rand(628) / 100)
            local x = zone.x + rand(zone.w)
            local y = zone.y + rand(zone.h)
            for _ = 1, 8 do
                local candidateX = zone.x + rand(zone.w)
                local candidateY = zone.y + rand(zone.h)
                local clear = true
                for _, bee in ipairs(self.bees) do
                    local dx = candidateX - bee.x
                    local dy = candidateY - bee.y
                    if dx * dx + dy * dy < 900 then clear = false; break end
                end
                if clear then x = candidateX; y = candidateY; break end
            end
            self.bees[#self.bees + 1] = {
                x = x, y = y,
                vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
                w = 22, h = 18, zone = zone,
            }
        end
    end

    local webCount = tonumber(self.config.webs) or 0
    if webCount < 0 then webCount = 0 end
    if webCount > 3 then webCount = 3 end
    local webSlots = {
        { x = self.treeRect.x - 54, y = self.treeRect.y + 72 },
        { x = self.treeRect.x + self.treeRect.w - 10, y = self.treeRect.y + math.floor(self.treeRect.h * 0.45) },
        { x = self.treeRect.x - 48, y = self.treeRect.y + math.floor(self.treeRect.h * 0.70) },
    }
    for i = 1, webCount do
        self.webs[#self.webs + 1] = { kind = "web", x = webSlots[i].x, y = webSlots[i].y, w = 58, h = 58 }
    end

    local spiderCount = math.max(1, webCount + (self.hive and 1 or 0))
    if webCount <= 0 then spiderCount = 0 end
    for i = 1, spiderCount do
        local speed = 118 + rand(42)
        local dir = rand(2) == 0 and -1 or 1
        self.spiders[#self.spiders + 1] = {
            x = self.treeRect.x + 12 + rand(math.max(1, self.treeRect.w - 34)),
            y = self.treeRect.y + 16 + rand(math.max(1, self.treeRect.h - 42)),
            vx = dir * (speed * 0.35),
            vy = (rand(2) == 0 and -speed or speed),
            w = 28, h = 24,
        }
    end
end

function EHR_HiveWebSearchUI:close()
    if EHR_HiveWebSearchUI.instance == self then EHR_HiveWebSearchUI.instance = nil end
    self:setVisible(false)
    self:removeFromUIManager()
end

function EHR_HiveWebSearchUI:onCancel()
    self.finished = true
    self:close()
end

function EHR_HiveWebSearchUI:startZone()
    return { x = self.boardX + 34, y = self.boardY + self.boardH - 42, w = self.boardW - 68, h = 30 }
end

function EHR_HiveWebSearchUI:mouseLocal()
    return (getMouseX() or 0) - self:getAbsoluteX(), (getMouseY() or 0) - self:getAbsoluteY()
end

function EHR_HiveWebSearchUI:handRect()
    local mx, my = self:handPoint()
    return { x = mx - HAND_HIT_W / 2, y = my - HAND_HIT_H / 2, w = HAND_HIT_W, h = HAND_HIT_H }
end

local function rectsOverlap(a, b)
    return a and b and a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

local function pointInRect(x, y, r)
    return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function clamp(value, low, high)
    if low > high then low, high = high, low end
    if value < low then return low end
    if value > high then return high end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * clamp(t, 0, 1)
end

function EHR_HiveWebSearchUI:pathBoundsForY(y)
    local tr = self.treeRect
    local left = tr.x + HAND_W / 2
    local right = tr.x + tr.w - HAND_W / 2

    if self.hive then
        local h = self.hive
        local expandStart = tr.y + 132
        local expandEnd = h.y + h.h * 0.45
        local t = clamp((expandStart - y) / math.max(1, expandStart - expandEnd), 0, 1)
        left = lerp(left, h.x + HAND_W / 2, t)
        right = lerp(right, h.x + h.w - HAND_W / 2, t)
    end

    for _, web in ipairs(self.webs or {}) do
        local centerY = web.y + web.h / 2
        local t = 1 - clamp(math.abs(y - centerY) / 54, 0, 1)
        if t > 0 then
            left = math.min(left, lerp(left, web.x + HAND_W / 2, t))
            right = math.max(right, lerp(right, web.x + web.w - HAND_W / 2, t))
        end
    end

    return left, right
end

function EHR_HiveWebSearchUI:constrainHandPoint(x, y)
    local start = self:startZone()
    local top = self.treeRect.y + HAND_H / 2
    if self.hive then top = math.min(top, self.hive.y + HAND_H / 2) end
    local bottom = start.y + start.h / 2
    local cy = clamp(y, top, bottom)
    local left, right = self:pathBoundsForY(cy)
    local cx = clamp(x, left, right)
    return cx, cy
end

function EHR_HiveWebSearchUI:handPoint()
    local mx, my = self:mouseLocal()
    if self.handActive then return self:constrainHandPoint(mx, my) end
    return mx, my
end

function EHR_HiveWebSearchUI:remainingSeconds()
    if getTimestampMs then
        local elapsed = getTimestampMs() - (self.startedAt or getTimestampMs())
        return math.max(0, math.ceil(((self.durationMs or 48000) - elapsed) / 1000))
    end
    return 45
end

function EHR_HiveWebSearchUI:sendResult(command, args)
    if not self.character or not self.square then return end
    args = args or {}
    args.x = self.square:getX()
    args.y = self.square:getY()
    args.z = self.square:getZ()
    if isClient and isClient() and sendClientCommand then
        sendClientCommand(self.character, "EHR_HiveWebSearch", command, args)
    elseif EHR.HiveWebSearchServer and EHR.HiveWebSearchServer[command] then
        EHR.HiveWebSearchServer[command](self.character, args)
    end
end

function EHR_HiveWebSearchUI:fail(kind)
    if self.finished then return end
    self.finished = true
    self:sendResult("Hazard", { kind = kind or "insect" })
    say(self.character, "HazardLine", "Ow! Something got my hand.")
    self:close()
end

function EHR_HiveWebSearchUI:finish(target)
    if self.finished or not target then return end
    self:sendResult("Complete", { target = target.kind })
    if target.kind == "hive" then
        self.hive = nil
    elseif target.kind == "web" then
        for i = #self.webs, 1, -1 do
            if self.webs[i] == target then
                table.remove(self.webs, i)
                break
            end
        end
    end
    self.flash = 8
    if not self.hive and #self.webs <= 0 then
        self.finished = true
        self:close()
    end
end

function EHR_HiveWebSearchUI:updateMover(mover, dt, zone)
    mover.x = mover.x + (mover.vx or 0) * dt
    mover.y = mover.y + (mover.vy or 0) * dt
    local z = zone or { x = self.treeRect.x, y = self.treeRect.y, w = self.treeRect.w, h = self.treeRect.h }
    if mover.x < z.x then mover.x = z.x; mover.vx = math.abs(mover.vx or 0) end
    if mover.y < z.y then mover.y = z.y; mover.vy = math.abs(mover.vy or 0) end
    if mover.x + mover.w > z.x + z.w then mover.x = z.x + z.w - mover.w; mover.vx = -math.abs(mover.vx or 0) end
    if mover.y + mover.h > z.y + z.h then mover.y = z.y + z.h - mover.h; mover.vy = -math.abs(mover.vy or 0) end
end

function EHR_HiveWebSearchUI:update()
    ISPanel.update(self)
    if self.finished then return end
    if self.flash > 0 then self.flash = self.flash - 1 end
    if not self.character or not self.square or squareDistance(self.character, self.square) > 4.5 then self:close(); return end
    if self.character.getX and (math.abs(self.character:getX() - self.startX) > 0.75 or math.abs(self.character:getY() - self.startY) > 0.75) then self:close(); return end

    local now = getTimestampMs and getTimestampMs() or (self.lastMs + 16)
    local dt = math.max(0.006, math.min(0.055, (now - (self.lastMs or now)) / 1000))
    self.lastMs = now
    for _, bee in ipairs(self.bees or {}) do self:updateMover(bee, dt, bee.zone) end
    for _, spider in ipairs(self.spiders or {}) do self:updateMover(spider, dt, self.treeRect) end

    if self.handActive then
        local hand = self:handRect()
        for _, bee in ipairs(self.bees or {}) do
            if rectsOverlap(hand, bee) then self:fail("bee"); return end
        end
        for _, spider in ipairs(self.spiders or {}) do
            if rectsOverlap(hand, spider) then self:fail("spider"); return end
        end
    end

    if self:remainingSeconds() <= 0 then self:close() end
end

function EHR_HiveWebSearchUI:onMouseDown(x, y)
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

    if pointInRect(x, y, self:startZone()) then
        self.handActive = true
        self.flash = 8
        say(self.character, "StartLine", "Easy... keep the hand steady.")
        return true
    end

    if not self.handActive then
        self.flash = 10
        say(self.character, "NeedStartLine", "I need to reach in from below.")
        return true
    end

    local hand = self:handRect()
    if self.hive and rectsOverlap(hand, self.hive) then self:finish(self.hive); return true end
    for _, web in ipairs(self.webs or {}) do
        if rectsOverlap(hand, web) then self:finish(web); return true end
    end
    return true
end

function EHR_HiveWebSearchUI:onMouseMove(dx, dy)
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

function EHR_HiveWebSearchUI:onMouseMoveOutside(dx, dy)
    if self.dragging then return self:onMouseMove(dx, dy) end
    if ISPanel.onMouseMoveOutside then return ISPanel.onMouseMoveOutside(self, dx, dy) end
    return false
end

function EHR_HiveWebSearchUI:onMouseUp(x, y)
    self.dragging = false
    return ISPanel.onMouseUp(self, x, y)
end

function EHR_HiveWebSearchUI:onMouseUpOutside(x, y)
    self.dragging = false
    if ISPanel.onMouseUpOutside then return ISPanel.onMouseUpOutside(self, x, y) end
    return true
end

function EHR_HiveWebSearchUI:drawTextureSafe(path, x, y, w, h, alpha)
    local texture = tex(path)
    if texture and self.drawTextureScaled then
        self:drawTextureScaled(texture, x, y, w, h, alpha or 1.0, 1.0, 1.0, 1.0)
        return true
    end
    return false
end

function EHR_HiveWebSearchUI:prerender()
    ISPanel.prerender(self)
    self:drawRect(0, 0, self.width, self.height, C.bg.a, C.bg.r, C.bg.g, C.bg.b)
    self:drawRectBorder(0, 0, self.width, self.height, 0.95, C.gold.r, C.gold.g * 0.65, C.gold.b * 0.35)
    self:drawRect(0, 0, self.width, 42, 0.96, 0.055, 0.020, 0.010)
    self:drawText(L("Title", "Hive and Web Harvest"), 16, 8, C.text.r, C.text.g, C.text.b, C.text.a, UIFont.Medium)
end

function EHR_HiveWebSearchUI:drawTrunk()
    local tr = self.treeRect
    self:drawRect(tr.x, tr.y, tr.w, tr.h, 1.0, C.trunk.r, C.trunk.g, C.trunk.b)
    self:drawRect(tr.x + 12, tr.y, 18, tr.h, 0.32, C.trunkDark.r, C.trunkDark.g, C.trunkDark.b)
    self:drawRect(tr.x + tr.w - 25, tr.y, 13, tr.h, 0.24, C.trunkDark.r, C.trunkDark.g, C.trunkDark.b)
    for i = 0, 7 do
        local y = tr.y + 16 + i * 33
        self:drawRect(tr.x + 8, y, tr.w - 18, 2, 0.18, 0.58, 0.34, 0.14)
    end
end

function EHR_HiveWebSearchUI:render()
    ISPanel.render(self)
    self:drawText(L("HintLine1", "Start from the safe zone below."), 24, 54, C.text.r, C.text.g, C.text.b, C.text.a, UIFont.Small)
    self:drawText(L("HintLine2", "Guide your hand to the hive or web without touching insects."), 24, 78, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)
    self:drawText(L("Time", "Time") .. ": " .. tostring(self:remainingSeconds()) .. "s", self.width - 130, 58, C.dim.r, C.dim.g, C.dim.b, C.dim.a, UIFont.Small)

    self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, C.panel.a, C.panel.r, C.panel.g, C.panel.b)
    self:drawRectBorder(self.boardX, self.boardY, self.boardW, self.boardH, 0.85, C.gold.r * 0.75, C.gold.g * 0.45, C.gold.b * 0.25)
    self:drawTrunk()

    if self.hive then
        local h = self.hive
        if not self:drawTextureSafe("media/textures/EHR_Honeycomb.png", h.x, h.y, h.w, h.h, 0.96) then
            self:drawRect(h.x, h.y, h.w, h.h, 0.92, 0.74, 0.44, 0.08)
        end
        self:drawRectBorder(h.x, h.y, h.w, h.h, 0.7, C.gold.r, C.gold.g, C.gold.b)
    end

    for _, web in ipairs(self.webs or {}) do
        if not self:drawTextureSafe("media/textures/EHR_Spiderweb.png", web.x, web.y, web.w, web.h, 0.95) then
            self:drawRect(web.x, web.y, web.w, web.h, 0.42, 0.86, 0.86, 0.80)
        end
        self:drawRectBorder(web.x, web.y, web.w, web.h, 0.55, 0.75, 0.75, 0.70)
    end

    for _, bee in ipairs(self.bees or {}) do
        if not self:drawTextureSafe("media/textures/EHR_Honeybee.png", bee.x, bee.y, bee.w, bee.h, 1.0) then
            self:drawRect(bee.x, bee.y, bee.w, bee.h, 1.0, 0.95, 0.78, 0.08)
        end
    end
    for _, spider in ipairs(self.spiders or {}) do
        if not self:drawTextureSafe("media/textures/EHR_Spider.png", spider.x, spider.y, spider.w, spider.h, 1.0) then
            self:drawRect(spider.x, spider.y, spider.w, spider.h, 1.0, 0.08, 0.06, 0.05)
        end
    end

    local start = self:startZone()
    local a = self.handActive and 0.30 or 0.58
    self:drawRect(start.x, start.y, start.w, start.h, a, 0.08, 0.28, 0.10)
    self:drawRectBorder(start.x, start.y, start.w, start.h, 0.9, C.green.r, C.green.g, C.green.b)
    self:drawTextCentre(self.handActive and L("HandActive", "Hand active") or L("StartZone", "Start here"), start.x + start.w / 2, start.y + 7, C.green.r, C.green.g, C.green.b, C.green.a, UIFont.Small)

    if self.flash > 0 then self:drawRect(self.boardX, self.boardY, self.boardW, self.boardH, 0.08, C.gold.r, C.gold.g, C.gold.b) end

    if self.handActive then
        local mx, my = self:handPoint()
        if not self:drawTextureSafe("media/textures/EHR_GrabbingHand.png", mx - HAND_W / 2, my - HAND_H / 2, HAND_W, HAND_H, 0.96) then
            self:drawRect(mx - HAND_HIT_W / 2, my - HAND_HIT_H / 2, HAND_HIT_W, HAND_HIT_H, 0.34, 1.0, 0.92, 0.72)
        end
    end
end

function EHR.HiveWebSearch.Open(player, square, config)
    if EHR_HiveWebSearchUI.instance then EHR_HiveWebSearchUI.instance:close() end
    local core = getCore and getCore()
    local sw = core and core:getScreenWidth() or 1280
    local sh = core and core:getScreenHeight() or 720
    local w, h = 660, 560
    local ui = EHR_HiveWebSearchUI:new(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, player, square, config or {})
    ui:initialise()
    ui:addToUIManager()
    EHR_HiveWebSearchUI.instance = ui
end

function EHR.HiveWebSearch.OnSearch(player, square)
    if not player or not square then return end
    if isClient and isClient() and sendClientCommand then
        local args = squareArgs(square)
        if not args then return end
        args.playerNum = playerNumOf(player)
        sendClientCommand(player, "EHR_HiveWebSearch", "RequestStart", args)
        return
    end
    if EHR.HiveWebSearchServer and EHR.HiveWebSearchServer.GetStartConfig then
        local ok, result = EHR.HiveWebSearchServer.GetStartConfig(player, squareArgs(square) or {})
        if ok and result then
            queueSearchAction(player, square, { hive = result.hive == true, webs = tonumber(result.webs) or 0 })
        elseif result == "Depleted" then
            say(player, "Depleted", "This tree has already been harvested recently.")
        else
            say(player, "None", "There is nothing useful here.")
        end
    end
end

function EHR.HiveWebSearch.OnServerCommand(module, command, args)
    if module ~= "EHR_HiveWebSearch" then return end
    local playerNum = tonumber(args and args.playerNum) or 0
    local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
    if not player and getPlayer then player = getPlayer() end
    if not player then return end

    if command == "StartDenied" then
        local reason = tostring(args and args.reason or "None")
        if reason == "Depleted" then
            say(player, "Depleted", "This tree has already been harvested recently.")
        else
            say(player, "None", "There is nothing useful here.")
        end
        return
    end
    if command ~= "StartApproved" then return end
    local square = squareFromArgs(args)
    queueSearchAction(player, square, { hive = args.hive == true or tostring(args.hive) == "true", webs = tonumber(args.webs) or 0 })
end

function EHR.HiveWebSearch.OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    local square = findTreeSquare(worldObjects)
    if not square then return end
    local optionText = L("Context", "Harvest hive or web")
    local option = context.addOptionOnTop and context:addOptionOnTop(optionText, player, EHR.HiveWebSearch.OnSearch, square)
        or context:addOption(optionText, player, EHR.HiveWebSearch.OnSearch, square)
    if option and getTexture then option.iconTexture = getTexture("media/textures/EHR_SearchHoneyWeb.png") end
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(optionText)
    tooltip.description = L("ContextDesc", "Search this tree for honeycomb or spiderwebs. Move carefully.")
    option.toolTip = tooltip
end

if not EHR.HiveWebSearch._registered then
    EHR.HiveWebSearch._registered = true
    Events.OnFillWorldObjectContextMenu.Add(EHR.HiveWebSearch.OnFillWorldObjectContextMenu)
    if Events.OnServerCommand then Events.OnServerCommand.Add(EHR.HiveWebSearch.OnServerCommand) end
    if EHR and EHR.Log then EHR.Log("HiveWebSearch: context menu registered") end
end
