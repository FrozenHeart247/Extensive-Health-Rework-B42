--[[
    Extensive Health Rework - Health Panel UI prototype

    Replacement-style health overview opened from the EHR health hotkey.
    This is intentionally read-only: it presents EHR data without changing
    disease, medication, blood, or vanilla health mechanics.
]]

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/BodyParts/ISBodyPartPanel"
require "XpSystem/ISUI/ISHealthPanel"
require "XpSystem/ISUI/ISCharacterScreen"
require "XpSystem/ISUI/ISCharacterInfo"
require "XpSystem/ISUI/ISCharacterProtection"
require "XpSystem/ISUI/ISClothingInsPanel"
require "ExtensiveHealth/EHR_Main"

EHR = EHR or {}
EHR.UI = EHR.UI or {}

EHR_HealthPanelUI = ISPanel:derive("EHR_HealthPanelUI")
EHR_HealthBodyPartPanel = ISBodyPartPanel:derive("EHR_HealthBodyPartPanel")

EHR_HealthPanelUI.EXPANDED_WIDTH = 860
EHR_HealthPanelUI.COLLAPSED_WIDTH = 420
EHR_HealthPanelUI.HEIGHT = 620
EHR_HealthPanelUI.MIN_WIDTH = 420
EHR_HealthPanelUI.MIN_HEIGHT = 420
EHR_HealthPanelUI.RESIZE_SIZE = 18
EHR_HealthPanelUI.HEADER_HEIGHT = 34
EHR_HealthPanelUI.TAB_HEIGHT = 28
EHR_HealthPanelUI.LEFT_WIDTH = 380
EHR_HealthPanelUI.SCROLL_STEP = 32
EHR_HealthPanelUI.TEXT_DOCK_Y_BIAS = -2

EHR_HealthPanelUI.Colors = {
    background = { r = 0.07, g = 0.075, b = 0.085, a = 0.96 },
    panel = { r = 0.095, g = 0.10, b = 0.115, a = 0.92 },
    panelSoft = { r = 0.12, g = 0.13, b = 0.145, a = 0.75 },
    header = { r = 0.12, g = 0.19, b = 0.16, a = 0.98 },
    border = { r = 0.33, g = 0.55, b = 0.44, a = 1.0 },
    text = { r = 0.90, g = 0.92, b = 0.90, a = 1.0 },
    textDim = { r = 0.62, g = 0.62, b = 0.62, a = 1.0 },
    green = { r = 0.22, g = 0.86, b = 0.34, a = 1.0 },
    blue = { r = 0.20, g = 0.78, b = 1.0, a = 1.0 },
    yellow = { r = 0.95, g = 0.74, b = 0.18, a = 1.0 },
    orange = { r = 1.0, g = 0.36, b = 0.12, a = 1.0 },
    red = { r = 0.92, g = 0.08, b = 0.08, a = 1.0 },
    body = { r = 0.30, g = 0.36, b = 0.34, a = 0.55 },
    bodyHot = { r = 0.40, g = 0.62, b = 0.50, a = 0.82 },
}

local suppressVanillaTicks = 0

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function countTable(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _ in pairs(tbl) do
            count = count + 1
        end
    end
    return count
end

local function formatHours(hours)
    hours = tonumber(hours) or 0
    if hours >= 24 then
        return string.format("%.1fd", hours / 24)
    end
    return string.format("%.1fh", hours)
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime()
    if gameTime and gameTime.getWorldAgeHours then
        return gameTime:getWorldAgeHours()
    end
    return 0
end

local function hideWindow(instance)
    if not instance then return end
    local ok = pcall(function()
        if instance.isVisible and instance:isVisible() then
            instance:setVisible(false)
        end
    end)
    return ok
end

local function hideVanillaHealthWindow()
    if ISCharacterInfoWindow and ISCharacterInfoWindow.instance then
        hideWindow(ISCharacterInfoWindow.instance)
    end
    if ISHealthPanel and ISHealthPanel.instance then
        hideWindow(ISHealthPanel.instance)
    end
end

local function onTickHideVanilla()
    if suppressVanillaTicks <= 0 then return end
    suppressVanillaTicks = suppressVanillaTicks - 1
    hideVanillaHealthWindow()
end

local function suppressLegacyHealthUI(ticks)
    ticks = ticks or 12
    suppressVanillaTicks = math.max(suppressVanillaTicks, ticks)
    EHR.UI.SuppressLegacyMonitorTicks = math.max(tonumber(EHR.UI.SuppressLegacyMonitorTicks) or 0, ticks)
    hideVanillaHealthWindow()
    if EHR.UI.HideMonitor then
        EHR.UI.HideMonitor()
    end
end

local function tableValuesSortedByName(tbl, nameGetter)
    local values = {}
    if type(tbl) ~= "table" then return values end

    for key, value in pairs(tbl) do
        table.insert(values, { id = key, data = value, name = nameGetter(key, value) })
    end

    table.sort(values, function(a, b)
        return tostring(a.name or a.id) < tostring(b.name or b.id)
    end)

    return values
end

function EHR_HealthBodyPartPanel:onRightMouseUp(x, y)
    if UIManager and UIManager.getSpeedControls and UIManager.getSpeedControls():getCurrentGameSpeed() == 0 then
        if not getDebug() then return false end
    end

    local selected = self:getPartForCoordinate(x, y)
    if selected and selected.bodyPart then
        self:setSelected(x, y, true)
        if self.parent and self.parent.openBodyPartContextMenu then
            self.parent:openBodyPartContextMenu(selected.bodyPart, self:getX() + x, self:getY() + y)
            return true
        end
    end

    return ISBodyPartPanel.onRightMouseUp(self, x, y)
end

function EHR_HealthBodyPartPanel:onMouseUp(x, y)
    if self.selectedBp and ISMouseDrag and ISMouseDrag.dragging and ISInventoryPane and ISInventoryPane.getActualItems then
        local dragging = ISInventoryPane.getActualItems(ISMouseDrag.dragging)
        if dragging and #dragging > 0 and self.parent and self.parent.dropItemsOnBodyPart then
            self.parent:dropItemsOnBodyPart(self.selectedBp.bodyPart, dragging)
            return true
        end
    end
    return ISBodyPartPanel.onMouseUp(self, x, y)
end

function EHR_HealthPanelUI:new(x, y, player)
    local o = ISPanel:new(x, y, EHR_HealthPanelUI.EXPANDED_WIDTH, EHR_HealthPanelUI.HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.playerNum = player and player:getPlayerNum() or 0
    o.rightExpanded = true
    o.activeTab = "ehr"
    o.selectedZone = "overview"
    o.dragging = false
    o.dragStartX = 0
    o.dragStartY = 0
    o.dragMouseStartX = 0
    o.dragMouseStartY = 0
    o.resizing = false
    o.resizeStartW = 0
    o.resizeStartH = 0
    o.resizeMouseStartX = 0
    o.resizeMouseStartY = 0
    o.contentScrollY = 0
    o.contentHeight = 0
    o.markerBounds = {}
    o.tabBounds = {}
    o.embeddedTabs = {}
    o.cachedData = {}
    o.vanillaHealthAdapter = nil
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    o.anchorLeft = true
    o.anchorTop = true
    o.anchorRight = false
    o.anchorBottom = false

    return o
end

function EHR_HealthPanelUI:initialise()
    ISPanel.initialise(self)
end

function EHR_HealthPanelUI:createChildren()
    ISPanel.createChildren(self)

    self.closeButton = ISButton:new(self.width - 30, 6, 24, 22, "X", self, EHR_HealthPanelUI.onClose)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton.borderColor = { r = 0.55, g = 0.85, b = 0.68, a = 1 }
    self:addChild(self.closeButton)

    self.expandButton = ISButton:new(self.width - 60, 6, 24, 22, "-", self, EHR_HealthPanelUI.onToggleRight)
    self.expandButton:initialise()
    self.expandButton:instantiate()
    self.expandButton.borderColor = { r = 0.55, g = 0.85, b = 0.68, a = 1 }
    self:addChild(self.expandButton)

    self:ensureBodyPartPanel()
    self:createEmbeddedVanillaTabs()
    self:syncTabVisibility()
end

function EHR_HealthPanelUI:ensureBodyPartPanel()
    if self.bodyPartPanel and self.bodyPartPanel.player == self.player then
        return self.bodyPartPanel
    end

    if self.bodyPartPanel then
        self:removeChild(self.bodyPartPanel)
        self.bodyPartPanel = nil
    end

    if not self.player or not EHR_HealthBodyPartPanel then
        return nil
    end

    self.bodyPartPanel = EHR_HealthBodyPartPanel:new(self.player, 0, 0, self, nil)
    self.bodyPartPanel:initialise()
    self.bodyPartPanel:instantiate()
    self.bodyPartPanel:setAlphas(0.62, 1.0, 1.0, 0.38, 0.38)
    self.bodyPartPanel:setColorScheme({
        { val = 0.00, color = Color.new(0.76, 0.86, 0.80, 1) },
        { val = 0.35, color = Color.new(0.82, 0.70, 0.20, 1) },
        { val = 0.70, color = Color.new(0.95, 0.38, 0.12, 1) },
        { val = 1.00, color = Color.new(0.95, 0.08, 0.08, 1) },
    })
    self.bodyPartPanel:enableNodes("media/ui/BodyParts/bps_node_diamond", "media/ui/BodyParts/bps_node_diamond_outline")
    self:addChild(self.bodyPartPanel)

    return self.bodyPartPanel
end

function EHR_HealthPanelUI:getTabDefinitions()
    local vanillaText = xpSystemText or {}
    if self.width < 560 then
        return {
            { id = "ehr", label = "EHR" },
        }
    end

    local compact = self.width < 760
    return {
        { id = "ehr", label = compact and "EHR" or "EHR Monitor" },
        { id = "info", label = vanillaText.info or "Info" },
        { id = "skills", label = vanillaText.skills or "Skills" },
        { id = "health", label = vanillaText.health or "Health" },
        { id = "protection", label = compact and "Protect" or (vanillaText.protection or "Protection") },
        { id = "temperature", label = compact and "Temp" or "Temperature" },
    }
end

function EHR_HealthPanelUI:getContentTop()
    return self.HEADER_HEIGHT + self.TAB_HEIGHT + 10
end

function EHR_HealthPanelUI:getTabContentBounds()
    local y = self:getContentTop()
    return {
        x = 12,
        y = y,
        w = math.max(120, self.width - 24),
        h = math.max(120, self.height - y - 12),
    }
end

function EHR_HealthPanelUI:prepareEmbeddedVanillaView(view)
    if not view then return end
    if view.ehrPrepared then return end
    view.ehrPrepared = true

    view.anchorLeft = true
    view.anchorTop = true
    view.anchorRight = true
    view.anchorBottom = true

    view.setWidthAndParentWidth = function(viewSelf, width)
        local parent = viewSelf.parent
        local bounds = parent and parent.getTabContentBounds and parent:getTabContentBounds() or nil
        local maxWidth = bounds and bounds.w or width
        ISPanel.setWidth(viewSelf, math.max(100, maxWidth or width or viewSelf.width or 100))
    end

    view.setHeightAndParentHeight = function(viewSelf, height)
        local parent = viewSelf.parent
        local bounds = parent and parent.getTabContentBounds and parent:getTabContentBounds() or nil
        local maxHeight = bounds and bounds.h or height
        ISPanel.setHeight(viewSelf, math.max(100, maxHeight or height or viewSelf.height or 100))
    end

    local originalPrerender = view.prerender
    local originalRender = view.render
    view.prerender = function(viewSelf, ...)
        viewSelf:setStencilRect(0, 0, viewSelf.width, viewSelf.height)
        if originalPrerender then
            originalPrerender(viewSelf, ...)
        end
    end
    view.render = function(viewSelf, ...)
        if originalRender then
            originalRender(viewSelf, ...)
        end
        viewSelf:clearStencilRect()
    end
end

function EHR_HealthPanelUI:prepareInfoLiteratureButton(view)
    if not view or not view.literatureButton or view.ehrLiteratureButtonPrepared then return end
    view.ehrLiteratureButtonPrepared = true

    view.literatureButton.onclick = function(target, button, ...)
        ISCharacterScreen.onShowLiterature(target, button, ...)
        local ui = target and target.literatureUI or nil
        if not ui then return end

        if not ui.ehrOwnerCheckPatched then
            ui.ehrOwnerCheckPatched = true
            local originalPrerender = ui.prerender
            ui.prerender = function(uiSelf, ...)
                if ISCollapsableWindowJoypad and ISCollapsableWindowJoypad.prerender then
                    ISCollapsableWindowJoypad.prerender(uiSelf, ...)
                elseif originalPrerender then
                    local oldOwner = uiSelf.owner
                    local infoPanel = getPlayerInfoPanel and getPlayerInfoPanel(uiSelf.playerNum) or nil
                    if infoPanel and infoPanel.charScreen then
                        uiSelf.owner = infoPanel.charScreen
                    end
                    originalPrerender(uiSelf, ...)
                    uiSelf.owner = oldOwner
                end
            end
        end

        ui:setVisible(true)
        ui:addToUIManager()
        if ui.bringToTop then
            ui:bringToTop()
        end

        if Events and Events.OnTick then
            local reopened = false
            local function reopenLiterature()
                if reopened then
                    Events.OnTick.Remove(reopenLiterature)
                    return
                end
                reopened = true
                if target and target.literatureUI then
                    target.literatureUI:setVisible(true)
                    target.literatureUI:addToUIManager()
                    if target.literatureUI.bringToTop then
                        target.literatureUI:bringToTop()
                    end
                end
                Events.OnTick.Remove(reopenLiterature)
            end
            Events.OnTick.Add(reopenLiterature)
        end
    end
end

function EHR_HealthPanelUI:prepareTemperatureView(view)
    if not view or view.ehrTemperaturePrepared then return end
    view.ehrTemperaturePrepared = true
    view.ehrOwnerPanel = self

    local function isLocalButtonRowHit(viewSelf, button, x, y)
        if not viewSelf or not button then return false end
        if button.getIsVisible and not button:getIsVisible() then return false end
        if button.isVisible and not button:isVisible() then return false end

        local bx = button.getX and button:getX() or button.x or 0
        local by = button.getY and button:getY() or button.y or 0
        local bw = button.getWidth and button:getWidth() or button.width or 0
        local bh = button.getHeight and button:getHeight() or button.height or 0
        local rowLeft = math.max(0, math.min(bx, tonumber(viewSelf.coreRectangleX) or bx) - 10)
        local rowRight = math.min(viewSelf.width or (bx + bw), math.max(bx + bw, (viewSelf.width or bx + bw) - 10))

        return x >= rowLeft and x <= rowRight and y >= by and y <= by + bh
    end

    local function normalizeButton(button)
        if not button then return end
        if button.setBackgroundColorMouseOverRGBA then
            button:setBackgroundColorMouseOverRGBA(0, 0, 0, 1)
        else
            button.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 1 }
        end
        button.pressed = false
        button.mouseOver = false
    end

    if view.viewButtons then
        for _, group in pairs(view.viewButtons) do
            for _, button in ipairs(group) do
                normalizeButton(button)
                button.onclick = function(target, btn)
                    if target and btn and btn.customData and btn.customData.index and target.setViewIndex then
                        target:setViewIndex(btn.customData.index)
                    end
                    if target and target.ehrOwnerPanel then
                        target.ehrOwnerPanel:resetTemperatureButtonState(target)
                    end
                end
            end
        end
    end
    normalizeButton(view.toggleAdvBtn)

    local originalOnMouseUp = view.onMouseUp
    view.onMouseUp = function(viewSelf, x, y)
        local buttons = viewSelf.viewButtons and viewSelf.currentViewID and viewSelf.viewButtons[viewSelf.currentViewID] or nil
        if buttons then
            for _, button in ipairs(buttons) do
                if isLocalButtonRowHit(viewSelf, button, x, y) then
                    if button.customData and button.customData.index and viewSelf.setViewIndex then
                        viewSelf:setViewIndex(button.customData.index)
                    end
                    if viewSelf.ehrOwnerPanel then
                        viewSelf.ehrOwnerPanel:resetTemperatureButtonState(viewSelf)
                    end
                    return true
                end
            end
        end

        if isLocalButtonRowHit(viewSelf, viewSelf.toggleAdvBtn, x, y) then
            if ISClothingInsPanel and ISClothingInsPanel.onToggleViewStyle then
                ISClothingInsPanel.onToggleViewStyle(viewSelf, viewSelf.toggleAdvBtn)
            elseif viewSelf.onToggleViewStyle then
                viewSelf:onToggleViewStyle(viewSelf.toggleAdvBtn)
            end
            if viewSelf.ehrOwnerPanel then
                viewSelf.ehrOwnerPanel:resetTemperatureButtonState(viewSelf)
            end
            return true
        end

        if originalOnMouseUp then
            return originalOnMouseUp(viewSelf, x, y)
        end
        return false
    end
end

function EHR_HealthPanelUI:createEmbeddedVanillaTabs()
    if self.embeddedTabsCreated then return end
    self.embeddedTabsCreated = true
    self.embeddedTabs = self.embeddedTabs or {}

    if not self.player then return end

    local bounds = self:getTabContentBounds()
    local specs = {
        {
            id = "info",
            factory = function()
                return ISCharacterScreen:new(0, 0, bounds.w, bounds.h, self.playerNum)
            end,
        },
        {
            id = "skills",
            factory = function()
                return ISCharacterInfo:new(0, 0, bounds.w, bounds.h, self.playerNum)
            end,
        },
        {
            id = "health",
            factory = function()
                return ISHealthPanel:new(self.player, 0, 0, bounds.w, bounds.h)
            end,
        },
        {
            id = "protection",
            factory = function()
                return ISCharacterProtection:new(0, 0, bounds.w, bounds.h, self.playerNum)
            end,
        },
        {
            id = "temperature",
            factory = function()
                return ISClothingInsPanel:new(self.player, 0, 0, bounds.w, bounds.h)
            end,
        },
    }

    for _, spec in ipairs(specs) do
        local oldHealthInstance = ISHealthPanel and ISHealthPanel.instance or nil
        local oldCharacterInfoInstance = ISCharacterInfo and ISCharacterInfo.instance or nil
        local ok, view = pcall(spec.factory)
        if ISHealthPanel then
            ISHealthPanel.instance = oldHealthInstance
        end
        if ISCharacterInfo then
            ISCharacterInfo.instance = oldCharacterInfoInstance
        end
        if ok and view then
            self:prepareEmbeddedVanillaView(view)
            view:initialise()
            if not view.javaObject and view.instantiate then
                view:instantiate()
            end
            if spec.id == "info" then
                self:prepareInfoLiteratureButton(view)
            elseif spec.id == "temperature" then
                self:prepareTemperatureView(view)
            end
            view:setVisible(false)
            view.ehrVisible = false
            self:addChild(view)
            self.embeddedTabs[spec.id] = view
        end
    end
end

function EHR_HealthPanelUI:layoutEmbeddedVanillaTabs()
    if not self.embeddedTabs then return end

    local bounds = self:getTabContentBounds()
    for _, view in pairs(self.embeddedTabs) do
        view:setX(bounds.x)
        view:setY(bounds.y)
        view:setWidth(bounds.w)
        view:setHeight(bounds.h)
    end
end

function EHR_HealthPanelUI:syncTabVisibility()
    local isEHR = self.activeTab == "ehr"

    if self.bodyPartPanel then
        self.bodyPartPanel:setVisible(isEHR)
    end
    if self.expandButton then
        self.expandButton:setVisible(isEHR)
    end
    if self.embeddedTabs then
        for id, view in pairs(self.embeddedTabs) do
            local shouldShow = self.activeTab == id
            if view.ehrVisible ~= shouldShow then
                view.ehrVisible = shouldShow
                view:setVisible(shouldShow)
            end
        end
    end
end

function EHR_HealthPanelUI:setActiveTab(tabId)
    if not tabId or self.activeTab == tabId then return end

    self.activeTab = tabId
    self.contentScrollY = 0

    if tabId ~= "ehr" and not self.rightExpanded then
        self.rightExpanded = true
        self:setWidth(EHR_HealthPanelUI.EXPANDED_WIDTH)
    end

    self:repositionControls()
    self:syncTabVisibility()
    self:keepOnScreen()
end

function EHR_HealthPanelUI:repositionControls()
    if self.closeButton then
        self.closeButton:setX(self.width - 30)
        self.closeButton:setY(math.floor((self.HEADER_HEIGHT - self.closeButton.height) / 2))
    end
    if self.expandButton then
        self.expandButton:setX(self.width - 60)
        self.expandButton:setY(math.floor((self.HEADER_HEIGHT - self.expandButton.height) / 2))
        self.expandButton:setTitle(self.rightExpanded and "-" or "+")
    end
end

function EHR_HealthPanelUI:isInResizeHandle(x, y)
    local size = self.RESIZE_SIZE or 18
    return x >= self.width - size and y >= self.height - size
end

function EHR_HealthPanelUI:clampWindowSize(width, height)
    local core = getCore and getCore()
    local maxW = core and (core:getScreenWidth() - math.max(0, self.x) - 8) or width
    local maxH = core and (core:getScreenHeight() - math.max(0, self.y) - 8) or height
    local minW = self.MIN_WIDTH or 420
    local minH = self.MIN_HEIGHT or 420

    return clamp(width, minW, math.max(minW, maxW)), clamp(height, minH, math.max(minH, maxH))
end

function EHR_HealthPanelUI:keepOnScreen()
    local core = getCore and getCore()
    if not core then return end

    local screenW = core:getScreenWidth()
    local screenH = core:getScreenHeight()
    local x = self.x
    local y = self.y

    if x + self.width > screenW then x = screenW - self.width - 10 end
    if y + self.height > screenH then y = screenH - self.height - 10 end
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end

    self:setX(x)
    self:setY(y)
end

function EHR_HealthPanelUI:getTextWidth(text, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if getTextManager then
        local ok, width = pcall(function()
            return getTextManager():MeasureStringX(font, text)
        end)
        if ok and width then return width end
    end
    return string.len(text) * 8
end

function EHR_HealthPanelUI:getFontHeight(font)
    font = font or UIFont.Small
    if getTextManager then
        local ok, height = pcall(function()
            return getTextManager():getFontHeight(font)
        end)
        if ok and height then return height end
    end
    if font == UIFont.Medium then return 20 end
    return 16
end

function EHR_HealthPanelUI:getDockedTextY(y, h, font, bias)
    local fontH = self:getFontHeight(font)
    return y + math.floor((h - fontH) / 2) + (bias or self.TEXT_DOCK_Y_BIAS or 0)
end

function EHR_HealthPanelUI:drawTextRight(text, rightX, y, r, g, b, a, font)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), rightX - width, y, r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawTextCenter(text, x, w, y, r, g, b, a, font)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), x + math.floor((w - width) / 2), y, r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawDockedText(text, x, y, w, h, r, g, b, a, font, bias)
    self:drawText(tostring(text or ""), x, self:getDockedTextY(y, h, font, bias), r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawDockedTextRight(text, rightX, y, h, r, g, b, a, font, bias)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), rightX - width, self:getDockedTextY(y, h, font, bias), r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:drawDockedTextCenter(text, x, y, w, h, r, g, b, a, font, bias)
    local width = self:getTextWidth(text, font)
    self:drawText(tostring(text or ""), x + math.floor((w - width) / 2), self:getDockedTextY(y, h, font, bias), r, g, b, a, font or UIFont.Small)
end

function EHR_HealthPanelUI:truncateText(text, maxWidth, font)
    text = tostring(text or "")
    font = font or UIFont.Small
    if self:getTextWidth(text, font) <= maxWidth then return text end

    local ellipsis = "..."
    local result = text
    while string.len(result) > 1 and self:getTextWidth(result .. ellipsis, font) > maxWidth do
        result = string.sub(result, 1, string.len(result) - 1)
    end
    return result .. ellipsis
end

function EHR_HealthPanelUI:drawRoundIcon(x, y, size, fill, border, label, labelColor)
    fill = fill or EHR_HealthPanelUI.Colors.panelSoft
    border = border or EHR_HealthPanelUI.Colors.border
    labelColor = labelColor or EHR_HealthPanelUI.Colors.text

    local cut = math.floor(size * 0.22)
    self:drawRect(x + cut, y, size - cut * 2, size, fill.a, fill.r, fill.g, fill.b)
    self:drawRect(x, y + cut, size, size - cut * 2, fill.a, fill.r, fill.g, fill.b)
    self:drawRectBorder(x + cut, y, size - cut * 2, size, border.a, border.r, border.g, border.b)
    self:drawRectBorder(x, y + cut, size, size - cut * 2, border.a, border.r, border.g, border.b)

    if label then
        self:drawDockedTextCenter(label, x, y, size, size, labelColor.r, labelColor.g, labelColor.b, labelColor.a, UIFont.Small)
    end
end

function EHR_HealthPanelUI:drawSectionTitle(text, x, y, w)
    local c = EHR_HealthPanelUI.Colors
    self:drawRect(x, y, w, 24, 0.55, c.panelSoft.r, c.panelSoft.g, c.panelSoft.b)
    self:drawDockedText(text, x + 8, y, w - 16, 24, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
end

function EHR_HealthPanelUI:getDiseaseName(diseaseId, disease)
    if type(disease) == "table" and disease.displayName then
        return disease.displayName
    end
    local definition = EHR.Disease and EHR.Disease.Diseases and EHR.Disease.Diseases[diseaseId]
    if definition and definition.name then
        return definition.name
    end
    return tostring(diseaseId or "Unknown Disease")
end

function EHR_HealthPanelUI:getDiseaseProgress(disease)
    if type(disease) ~= "table" then return 0 end
    local progress = tonumber(disease.progress)
    if progress then
        if progress <= 1 then return progress * 100 end
        return progress
    end

    local started = tonumber(disease.startTime)
    local duration = tonumber(disease.duration)
    if started and duration and duration > 0 then
        return clamp(((getWorldAgeHours() - started) / duration) * 100, 0, 100)
    end

    return 0
end

function EHR_HealthPanelUI:isDiseaseTreated(diseaseId)
    local medication = self.cachedData.medication or {}
    local active = medication.activeTreatments or {}
    return active[diseaseId] ~= nil
end

function EHR_HealthPanelUI:updateCachedData()
    local player = getSpecificPlayer and getSpecificPlayer(self.playerNum or 0)
    if player then
        self.player = player
    end

    local data = nil
    if EHR.GetPlayerData and self.player then
        data = EHR.GetPlayerData(self.player)
    end
    if not data and self.player and self.player.getModData then
        data = self.player:getModData()
    end
    data = data or {}

    local diseaseData = nil
    if EHR.Disease and EHR.Disease.GetDiseaseData and self.player then
        diseaseData = EHR.Disease.GetDiseaseData(self.player)
    end
    diseaseData = diseaseData or data.EHR_Disease or {}

    local medicationData = {}
    if EHR.Medication and EHR.Medication.GetMedicationData and self.player then
        medicationData = EHR.Medication.GetMedicationData(self.player) or {}
    else
        medicationData = data.EHR_Medication or {}
    end

    local activeTreatments = {}
    if EHR.Medication and EHR.Medication.GetActiveTreatments and self.player then
        activeTreatments = EHR.Medication.GetActiveTreatments(self.player) or {}
    end

    local activeSideEffects = {}
    if EHR.Medication and EHR.Medication.GetActiveSideEffects and self.player then
        activeSideEffects = EHR.Medication.GetActiveSideEffects(self.player) or {}
    end

    self.cachedData = {
        blood = data.EHR_Blood or {},
        diseases = diseaseData.active or {},
        medication = medicationData,
        activeTreatments = activeTreatments,
        activeSideEffects = activeSideEffects,
    }
end

function EHR_HealthPanelUI:getBloodSummary()
    local blood = self.cachedData.blood or {}
    local maxVolume = tonumber(blood.maxVolume) or 5000
    local current = clamp(tonumber(blood.currentVolume) or maxVolume, 0, maxVolume)
    local saline = math.max(0, tonumber(blood.transfusedSaline) or 0)
    local salinePct = 0
    if current > 0 then
        salinePct = clamp((saline / current) * 100, 0, 100)
    end

    local bloodPct = clamp((current / maxVolume) * 100, 0, 100)
    return {
        current = current,
        max = maxVolume,
        bloodPct = bloodPct,
        saline = saline,
        salinePct = salinePct,
        bloodType = blood.bloodType or "O+",
        canHeal = blood.canHeal,
        healBlockReason = blood.healBlockReason,
    }
end

function EHR_HealthPanelUI:getBloodBagTexture(summary)
    if not getTexture then return nil end
    self.bloodBagTextures = self.bloodBagTextures or {}

    local bloodPct = tonumber(summary and summary.bloodPct) or 0
    if bloodPct <= 12 then
        if self.bloodBagTextures.empty == nil then
            self.bloodBagTextures.empty = getTexture("media/textures/Item_BloodBagEmpty.png") or false
        end
        if self.bloodBagTextures.empty then return self.bloodBagTextures.empty end
    end

    local bloodType = tostring(summary and summary.bloodType or ""):gsub("%+", "Pos"):gsub("%-", "Neg")
    if bloodType ~= "" then
        local key = "type_" .. bloodType
        if self.bloodBagTextures[key] == nil then
            self.bloodBagTextures[key] = getTexture("media/textures/Item_BloodBag" .. bloodType .. ".png") or false
        end
        if self.bloodBagTextures[key] then return self.bloodBagTextures[key] end
    end

    if self.bloodBagTextures.full == nil then
        self.bloodBagTextures.full = getTexture("media/textures/Item_BloodBag.png") or false
    end
    return self.bloodBagTextures.full or nil
end

function EHR_HealthPanelUI:drawBloodBagFallbackIcon(x, y, w, h, bloodPct)
    local c = EHR_HealthPanelUI.Colors
    local fillPct = clamp((tonumber(bloodPct) or 0) / 100, 0, 1)
    local bodyX = x + 2
    local bodyY = y + 4
    local bodyW = math.max(8, w - 4)
    local bodyH = math.max(10, h - 4)
    local fillH = math.floor((bodyH - 4) * fillPct)

    self:drawRect(bodyX + 4, y, math.max(4, bodyW - 8), 4, 0.95, 0.68, 0.68, 0.68)
    self:drawRect(bodyX, bodyY, bodyW, bodyH, 0.92, 0.06, 0.07, 0.075)
    self:drawRect(bodyX + 2, bodyY + 2, bodyW - 4, bodyH - 4, 0.58, 0.16, 0.16, 0.16)
    if fillH > 0 then
        self:drawRect(bodyX + 2, bodyY + bodyH - 2 - fillH, bodyW - 4, fillH, c.red.a, c.red.r, c.red.g, c.red.b)
    end
    self:drawRect(bodyX + 4, bodyY + 4, math.max(2, bodyW - 8), 2, 0.35, 1, 1, 1)
    self:drawRectBorder(bodyX, bodyY, bodyW, bodyH, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(bodyX + 4, y, math.max(4, bodyW - 8), 4, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:drawBloodBagIcon(x, y, w, h, summary)
    local c = EHR_HealthPanelUI.Colors
    local texture = self:getBloodBagTexture(summary)
    local bloodPct = tonumber(summary and summary.bloodPct) or 0

    if texture and self.drawTextureScaled then
        if bloodPct <= 12 then
            self:drawRect(x + 2, y + 2, w - 4, h - 4, 0.30, 0.54, 0.66, 0.66)
        end
        self:drawTextureScaled(texture, x, y, w, h, 1.0, 1.0, 1.0, 1.0)

        local gaugeX = x + math.floor(w * 0.27)
        local gaugeY = y + math.floor(h * 0.68)
        local gaugeW = math.max(6, math.floor(w * 0.48))
        local gaugeH = math.max(2, math.floor(h * 0.08))
        local fillW = math.floor(gaugeW * clamp(bloodPct / 100, 0, 1))
        self:drawRect(gaugeX, gaugeY, gaugeW, gaugeH, 0.82, 0.05, 0.05, 0.05)
        if fillW > 0 then
            self:drawRect(gaugeX, gaugeY, fillW, gaugeH, c.red.a, c.red.r, c.red.g, c.red.b)
        end
        self:drawRectBorder(gaugeX, gaugeY, gaugeW, gaugeH, 0.85, c.border.r, c.border.g, c.border.b)
        return
    end

    self:drawBloodBagFallbackIcon(x, y, w, h, bloodPct)
end

function EHR_HealthPanelUI:drawBloodBar(x, y, w, h, summary)
    local c = EHR_HealthPanelUI.Colors
    if w > 72 then
        local iconW = math.min(24, math.max(18, h + 8))
        self:drawBloodBagIcon(x, y - 4, iconW, h + 8, summary)
        x = x + iconW + 7
        w = math.max(20, w - iconW - 7)
    end

    local bloodW = math.floor(w * clamp(summary.bloodPct / 100, 0, 1))
    local salineW = math.floor(w * clamp(summary.salinePct / 100, 0, 1))

    self:drawRect(x, y, w, h, 1, 0.13, 0.13, 0.13)
    if bloodW > 0 then
        self:drawRect(x, y, bloodW, h, c.red.a, c.red.r, c.red.g, c.red.b)
    end
    if salineW > 0 then
        self:drawRect(x + math.max(0, bloodW - salineW), y, salineW, h, c.blue.a, c.blue.r, c.blue.g, c.blue.b)
    end
    self:drawRectBorder(x, y, w, h, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:drawHeader()
    local c = EHR_HealthPanelUI.Colors
    local summary = self:getBloodSummary()

    self:drawRect(0, 0, self.width, self.HEADER_HEIGHT, c.header.a, c.header.r, c.header.g, c.header.b)
    self:drawRectBorder(0, 0, self.width, self.height, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawDockedText(self:truncateText("EHR MEDICAL STATUS", math.max(90, self.width - 170), UIFont.Medium), 12, 0, math.max(90, self.width - 170), self.HEADER_HEIGHT, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
    self:drawDockedTextRight("[" .. tostring(summary.bloodType) .. "]", self.width - (self.activeTab == "ehr" and 82 or 50), 0, self.HEADER_HEIGHT, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Medium)
end

function EHR_HealthPanelUI:drawTabBar()
    local c = EHR_HealthPanelUI.Colors
    local y = self.HEADER_HEIGHT
    local x = 8
    local h = self.TAB_HEIGHT
    local maxRight = self.width - 78

    self.tabBounds = {}
    self:drawRect(0, y, self.width, h, 0.82, 0.035, 0.04, 0.045)
    self:drawRectBorder(0, y, self.width, h, 0.45, c.border.r, c.border.g, c.border.b)

    for _, tab in ipairs(self:getTabDefinitions()) do
        local label = tostring(tab.label or tab.id)
        local tabW = math.max(64, self:getTextWidth(label, UIFont.Small) + 22)
        if tab.id == "ehr" then
            tabW = math.max(tabW, self.width >= 760 and 122 or 68)
        end
        if x + tabW > maxRight then
            tabW = math.max(58, maxRight - x)
        end
        if tabW <= 48 then break end

        local active = self.activeTab == tab.id
        local bg = active and c.red or c.panelSoft
        local text = active and c.text or c.textDim

        self:drawRect(x, y + 4, tabW, h - 5, active and 0.92 or 0.55, bg.r, bg.g, bg.b)
        self:drawRectBorder(x, y + 4, tabW, h - 5, active and 0.95 or 0.45, c.border.r, c.border.g, c.border.b)
        self:drawDockedTextCenter(self:truncateText(label, tabW - 12, UIFont.Small), x, y + 4, tabW, h - 5, text.r, text.g, text.b, text.a, UIFont.Small)
        table.insert(self.tabBounds, { id = tab.id, x = x, y = y + 4, w = tabW, h = h - 5 })

        x = x + tabW + 4
        if x >= maxRight then break end
    end
end

function EHR_HealthPanelUI:drawEmbeddedTabFrame()
    local c = EHR_HealthPanelUI.Colors
    local bounds = self:getTabContentBounds()

    self:drawRect(bounds.x, bounds.y, bounds.w, bounds.h, c.panel.a, c.panel.r, c.panel.g, c.panel.b)
    self:drawRectBorder(bounds.x, bounds.y, bounds.w, bounds.h, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:drawResizeHandle()
    local c = EHR_HealthPanelUI.Colors
    local x = self.width - 16
    local y = self.height - 16

    self:drawRect(x + 10, y + 2, 2, 12, 0.70, c.border.r, c.border.g, c.border.b)
    self:drawRect(x + 6, y + 6, 2, 8, 0.55, c.border.r, c.border.g, c.border.b)
    self:drawRect(x + 2, y + 10, 2, 4, 0.40, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:addMarker(id, label, x, y)
    local c = EHR_HealthPanelUI.Colors
    local isSelected = self.selectedZone == id
    local fill = isSelected and c.bodyHot or c.panelSoft
    local textColor = isSelected and c.green or c.text

    table.insert(self.markerBounds, { id = id, x = x, y = y, w = 24, h = 24 })
    self:drawRoundIcon(x, y, 24, fill, c.border, "+", textColor)
    self:drawText(label, x + 32, y + 4, textColor.r, textColor.g, textColor.b, textColor.a, UIFont.Small)
end

function EHR_HealthPanelUI:drawBodyDiagram(x, y, w, h)
    local c = EHR_HealthPanelUI.Colors
    local cx = x + math.floor(w / 2)
    local top = y + 18

    self.markerBounds = {}

    self:drawRoundIcon(cx - 28, top, 56, c.body, c.border, nil)
    self:drawRect(cx - 42, top + 70, 84, 150, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRectBorder(cx - 42, top + 70, 84, 150, c.border.a, c.border.r, c.border.g, c.border.b)

    self:drawRect(cx - 112, top + 82, 52, 132, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRect(cx + 60, top + 82, 52, 132, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRect(cx - 48, top + 228, 38, 154, c.body.a, c.body.r, c.body.g, c.body.b)
    self:drawRect(cx + 10, top + 228, 38, 154, c.body.a, c.body.r, c.body.g, c.body.b)

    self:drawRectBorder(cx - 112, top + 82, 52, 132, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(cx + 60, top + 82, 52, 132, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(cx - 48, top + 228, 38, 154, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawRectBorder(cx + 10, top + 228, 38, 154, c.border.a, c.border.r, c.border.g, c.border.b)

    self:addMarker("head", "Head", x + 34, top + 15)
    self:addMarker("chest", "Chest", x + 34, top + 94)
    self:addMarker("abdomen", "Abdomen", x + 34, top + 166)
    self:addMarker("left_arm", "Left arm", x + w - 148, top + 104)
    self:addMarker("right_arm", "Right arm", x + w - 148, top + 150)
    self:addMarker("legs", "Legs", x + w - 148, top + 272)
end

function EHR_HealthPanelUI:getVanillaHealthAdapter()
    if not self.vanillaHealthAdapter then
        self.vanillaHealthAdapter = {
            owner = self,
            otherPlayer = nil,
            actions = {},
            blockingMessage = nil,
        }

        self.vanillaHealthAdapter.getAbsoluteX = function(adapter)
            return adapter.owner and adapter.owner:getAbsoluteX() or 0
        end
        self.vanillaHealthAdapter.getAbsoluteY = function(adapter)
            return adapter.owner and adapter.owner:getAbsoluteY() or 0
        end
        self.vanillaHealthAdapter.getDoctor = ISHealthPanel.getDoctor
        self.vanillaHealthAdapter.getPatient = ISHealthPanel.getPatient
        self.vanillaHealthAdapter.checkItems = ISHealthPanel.checkItems
        self.vanillaHealthAdapter.checkContainerItems = ISHealthPanel.checkContainerItems
        self.vanillaHealthAdapter.doBodyPartContextMenu = ISHealthPanel.doBodyPartContextMenu
        self.vanillaHealthAdapter.dropItemsOnBodyPart = ISHealthPanel.dropItemsOnBodyPart
        self.vanillaHealthAdapter.toPlayerInventory = ISHealthPanel.toPlayerInventory
    end

    self.vanillaHealthAdapter.owner = self
    self.vanillaHealthAdapter.character = self.player
    self.vanillaHealthAdapter.playerNum = self.player and self.player:getPlayerNum() or 0
    self.vanillaHealthAdapter.otherPlayer = nil
    self.vanillaHealthAdapter.blockingMessage = nil
    self.vanillaHealthAdapter.actions = self.vanillaHealthAdapter.actions or {}

    return self.vanillaHealthAdapter
end

function EHR_HealthPanelUI:openBodyPartContextMenu(bodyPart, x, y)
    if not bodyPart or not ISHealthPanel or not ISHealthPanel.doBodyPartContextMenu then return end
    local adapter = self:getVanillaHealthAdapter()
    if not adapter or not adapter.character then return end
    ISHealthPanel.doBodyPartContextMenu(adapter, bodyPart, x, y)
end

function EHR_HealthPanelUI:dropItemsOnBodyPart(bodyPart, items)
    if not bodyPart or not items or not ISHealthPanel or not ISHealthPanel.dropItemsOnBodyPart then return end
    local adapter = self:getVanillaHealthAdapter()
    if not adapter or not adapter.character then return end
    ISHealthPanel.dropItemsOnBodyPart(adapter, bodyPart, items)
end

function EHR_HealthPanelUI:updateVanillaBodyPartPanel()
    if not self.bodyPartPanel or not self.player then return end

    local bodyDamage = self.player:getBodyDamage()
    if not bodyDamage or not bodyDamage.getBodyParts then return end

    local bodyParts = bodyDamage:getBodyParts()
    if not bodyParts then return end

    for i = 0, bodyParts:size() - 1 do
        local bodyPart = bodyParts:get(i)
        if bodyPart and bodyPart.getType then
            local health = tonumber(bodyPart:getHealth()) or 100
            local value = clamp((100 - health) / 100, 0, 1)

            if bodyPart.bleeding and bodyPart:bleeding() then
                value = math.max(value, 0.90)
            elseif bodyPart.deepWounded and bodyPart:deepWounded() then
                value = math.max(value, 0.80)
            elseif bodyPart.bitten and bodyPart:bitten() then
                value = math.max(value, 0.72)
            elseif bodyPart.scratched and bodyPart:scratched() then
                value = math.max(value, 0.45)
            elseif bodyPart.bandaged and bodyPart:bandaged() then
                value = math.max(value, 0.25)
            elseif bodyPart.HasInjury and bodyPart:HasInjury() then
                value = math.max(value, 0.35)
            end

            local stiffness = 0
            if bodyPart.getStiffness then
                local ok, result = pcall(function() return bodyPart:getStiffness() end)
                stiffness = (ok and tonumber(result)) or 0
            end

            local additionalPain = 0
            if bodyPart.getAdditionalPain then
                local ok, result = pcall(function() return bodyPart:getAdditionalPain() end)
                additionalPain = (ok and tonumber(result)) or 0
            end

            if additionalPain > 50 then
                value = math.max(value, 0.72)
            elseif additionalPain > 10 then
                value = math.max(value, 0.45)
            elseif additionalPain >= 1 then
                value = math.max(value, 0.28)
            end

            if stiffness >= 20 then
                value = math.max(value, 0.62)
            elseif stiffness >= 5 then
                value = math.max(value, 0.35)
            elseif stiffness >= 1 then
                value = math.max(value, 0.28)
            end

            self.bodyPartPanel:setValue(bodyPart:getType(), value)
        end
    end
end

function EHR_HealthPanelUI:getSelectedBodyPartText()
    if self.bodyPartPanel and self.bodyPartPanel.selectedBp and self.bodyPartPanel.selectedBp.bodyPart then
        local bodyPart = self.bodyPartPanel.selectedBp.bodyPart
        if BodyPartType and BodyPartType.getDisplayName then
            return BodyPartType.getDisplayName(bodyPart:getType())
        end
        return tostring(bodyPart:getType())
    end
    return "None"
end

function EHR_HealthPanelUI:getSelectedBodyPartStatus()
    if not self.bodyPartPanel or not self.bodyPartPanel.selectedBp or not self.bodyPartPanel.selectedBp.bodyPart then
        return nil
    end

    local bodyPart = self.bodyPartPanel.selectedBp.bodyPart
    local c = EHR_HealthPanelUI.Colors
    local stiffness = 0
    local additionalPain = 0

    if bodyPart.getStiffness then
        local ok, result = pcall(function() return bodyPart:getStiffness() end)
        stiffness = (ok and tonumber(result)) or 0
    end

    if bodyPart.getAdditionalPain then
        local ok, result = pcall(function() return bodyPart:getAdditionalPain() end)
        additionalPain = (ok and tonumber(result)) or 0
    end

    if additionalPain > 50 then
        return "Heavy pain", c.red
    end
    if stiffness >= 20 then
        return "Muscle strain", c.orange
    end
    if additionalPain > 10 then
        return "Pain", c.orange
    end
    if stiffness >= 5 then
        return "Minor stiffness", c.yellow
    end
    if additionalPain >= 1 then
        return "Minor pain", c.yellow
    end
    if stiffness >= 1 then
        return "Slight stiffness", c.yellow
    end

    return nil
end

function EHR_HealthPanelUI:drawVanillaBodyPanelFrame(x, y, w, h)
    local c = EHR_HealthPanelUI.Colors
    self.markerBounds = {}

    self:drawRect(x, y, w, h, 0.35, c.panelSoft.r, c.panelSoft.g, c.panelSoft.b)
    self:drawRectBorder(x, y, w, h, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawText("BODY STATUS", x + 10, y + 8, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)

    local bodyPartPanel = self:ensureBodyPartPanel()
    if bodyPartPanel then
        self.bodyPartPanel:setVisible(true)
        self.bodyPartPanel:setX(x + math.floor((w - self.bodyPartPanel.width) / 2))
        self.bodyPartPanel:setY(y + 42)
        self:updateVanillaBodyPartPanel()
    else
        self:drawText("Body panel unavailable", x + 10, y + 48, c.orange.r, c.orange.g, c.orange.b, c.orange.a, UIFont.Small)
    end

    local selectedText = "Selected: " .. self:getSelectedBodyPartText()
    local statusText, statusColor = self:getSelectedBodyPartStatus()
    if statusText then
        selectedText = selectedText .. " - " .. statusText
        statusColor = statusColor or c.green
    else
        statusColor = c.green
    end
    self:drawText(selectedText, x + 10, y + h - 24, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Small)
end

function EHR_HealthPanelUI:drawLeftPanel()
    local c = EHR_HealthPanelUI.Colors
    local x = 12
    local y = self:getContentTop()
    local w = self.LEFT_WIDTH - 24
    local summary = self:getBloodSummary()
    local diseaseCount = countTable(self.cachedData.diseases)
    local medicationCount = countTable((self.cachedData.medication or {}).activeTreatments)

    self:drawRect(x, y, w, self.height - y - 12, c.panel.a, c.panel.r, c.panel.g, c.panel.b)
    self:drawRectBorder(x, y, w, self.height - y - 12, c.border.a, c.border.r, c.border.g, c.border.b)

    self:drawText("OVERVIEW", x + 10, y + 8, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
    self:drawBloodBar(x + 10, y + 36, w - 20, 18, summary)
    self:drawText(string.format("%d%% Blood", math.floor(summary.bloodPct + 0.5)), x + 10, y + 64, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
    self:drawTextRight(string.format("%d%% Saline", math.floor(summary.salinePct + 0.5)), x + w - 10, y + 64, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)

    self:drawText(tostring(diseaseCount) .. " Conditions", x + 10, y + 90, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
    self:drawTextRight(tostring(medicationCount) .. " Meds", x + w - 10, y + 90, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)

    local healingText = "Healing: Active"
    local healingColor = c.green
    if summary.canHeal == false then
        healingText = "Healing: Slowed"
        healingColor = c.orange
    end
    self:drawText(healingText, x + 10, y + 116, healingColor.r, healingColor.g, healingColor.b, healingColor.a, UIFont.Medium)

    if summary.healBlockReason and summary.canHeal == false then
        self:drawText("Reason: " .. tostring(summary.healBlockReason), x + 10, y + 140, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    end

    self:drawVanillaBodyPanelFrame(x + 10, y + 168, w - 20, self.height - y - 220)

    if not self.rightExpanded then
        self:drawTextCenter("[Click + to open details]", 0, self.width, self.height - 72, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
    end
end

function EHR_HealthPanelUI:getTreatmentName(treatment)
    if type(treatment) ~= "table" then return "Treatment" end
    return treatment.medicationName or treatment.medKey or "Treatment"
end

function EHR_HealthPanelUI:drawDiseaseRow(diseaseId, disease, x, y, w)
    local c = EHR_HealthPanelUI.Colors
    local name = self:getDiseaseName(diseaseId, disease)
    local stage = type(disease) == "table" and (tonumber(disease.stage) or 1) or 1
    local severity = type(disease) == "table" and (tonumber(disease.severity) or 0.5) or 0.5
    local progress = self:getDiseaseProgress(disease)
    local treated = self:isDiseaseTreated(diseaseId)
    local status = treated and "TREATING" or "UNTREATED"
    local statusColor = treated and c.green or c.orange
    local rowH = 88

    self:drawRect(x, y, w, rowH, 0.42, c.panelSoft.r, c.panelSoft.g, c.panelSoft.b)
    self:drawRoundIcon(x + 10, y + 12, 42, c.panel, c.border, "?", c.text)

    local textX = x + 62
    local textW = w - 170
    self:drawText(self:truncateText(name, textW, UIFont.Medium), textX, y + 8, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Medium)
    self:drawText(string.format("Stage %d   Severity %.1f/5", stage, severity), textX, y + 34, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Small)
    self:drawText(string.format("%d%%", math.floor(progress + 0.5)), textX, y + 56, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    self:drawTextRight(status, x + w - 10, y + 34, statusColor.r, statusColor.g, statusColor.b, statusColor.a, UIFont.Medium)

    local barX = textX
    local barY = y + 74
    local barW = w - 74
    local filled = math.floor(barW * clamp(progress / 100, 0, 1))
    self:drawRect(barX, barY, barW, 5, 1, 0.13, 0.13, 0.13)
    if filled > 0 then
        self:drawRect(barX, barY, filled, 5, c.green.a, c.green.r, c.green.g, c.green.b)
    end
    self:drawRectBorder(barX, barY, barW, 5, c.border.a, c.border.r, c.border.g, c.border.b)

    return rowH + 8
end

function EHR_HealthPanelUI:drawTreatmentRow(treatment, x, y, w)
    local c = EHR_HealthPanelUI.Colors
    local name = self:getTreatmentName(treatment)
    local remaining = type(treatment) == "table" and formatHours(treatment.hoursRemaining or 0) or "--"
    local dose = ""

    if type(treatment) == "table" and (treatment.totalDosesNeeded or 0) > 0 then
        dose = string.format("Remaining %d/%d", treatment.dosesRemaining or 0, treatment.totalDosesNeeded or 0)
    end

    self:drawText(self:truncateText(name, w - 135, UIFont.Small), x + 10, y, c.text.r, c.text.g, c.text.b, c.text.a, UIFont.Small)
    self:drawTextRight(remaining, x + w - 10, y, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
    if dose ~= "" then
        self:drawText(dose, x + 10, y + 18, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
        return 38
    end
    return 22
end

function EHR_HealthPanelUI:drawRightPanel()
    local c = EHR_HealthPanelUI.Colors
    local x = self.LEFT_WIDTH
    local y = self:getContentTop()
    local w = self.width - self.LEFT_WIDTH - 12
    local h = self.height - y - 12
    local clipY = y + 42
    local clipH = h - 54

    self:drawRect(x, y, w, h, c.panel.a, c.panel.r, c.panel.g, c.panel.b)
    self:drawRectBorder(x, y, w, h, c.border.a, c.border.r, c.border.g, c.border.b)
    self:drawSectionTitle("DETAILS", x, y, w)

    self:setStencilRect(x, clipY, w, clipH)

    local contentY = clipY + 8 - (self.contentScrollY or 0)
    local startY = contentY
    local diseases = tableValuesSortedByName(self.cachedData.diseases, function(id, disease)
        return self:getDiseaseName(id, disease)
    end)

    self:drawSectionTitle("ACTIVE CONDITIONS", x + 8, contentY, w - 16)
    contentY = contentY + 32

    if #diseases == 0 then
        self:drawText("No active conditions", x + 18, contentY, c.green.r, c.green.g, c.green.b, c.green.a, UIFont.Medium)
        contentY = contentY + 42
    else
        for _, item in ipairs(diseases) do
            contentY = contentY + self:drawDiseaseRow(item.id, item.data, x + 8, contentY, w - 16)
        end
    end

    local treatments = self.cachedData.activeTreatments or {}
    self:drawSectionTitle("ACTIVE MEDICATIONS", x + 8, contentY + 8, w - 16)
    contentY = contentY + 42

    if #treatments == 0 then
        self:drawText("No active medications", x + 18, contentY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
        contentY = contentY + 36
    else
        for _, treatment in ipairs(treatments) do
            contentY = contentY + self:drawTreatmentRow(treatment, x + 14, contentY, w - 28)
        end
    end

    local sideEffects = self.cachedData.activeSideEffects or {}
    self:drawSectionTitle("SIDE EFFECTS", x + 8, contentY + 8, w - 16)
    contentY = contentY + 42

    if #sideEffects == 0 then
        self:drawText("No active side effects", x + 18, contentY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Medium)
        contentY = contentY + 34
    else
        for _, effect in ipairs(sideEffects) do
            local name = effect.displayName or effect.effectId or "Side effect"
            local remaining = formatHours(effect.hoursRemaining or 0)
            self:drawText(self:truncateText(name, w - 120, UIFont.Small), x + 18, contentY, c.yellow.r, c.yellow.g, c.yellow.b, c.yellow.a, UIFont.Small)
            self:drawTextRight(remaining, x + w - 18, contentY, c.textDim.r, c.textDim.g, c.textDim.b, c.textDim.a, UIFont.Small)
            contentY = contentY + 22
        end
    end

    self.contentHeight = math.max(0, contentY - startY + 12)
    self:clearStencilRect()
    self:clampContentScroll()
    self:drawScrollBar(x + w - 10, clipY, 5, clipH)
end

function EHR_HealthPanelUI:getMaxContentScroll()
    local viewHeight = self.height - self:getContentTop() - 54
    return math.max(0, (self.contentHeight or 0) - viewHeight)
end

function EHR_HealthPanelUI:clampContentScroll()
    self.contentScrollY = clamp(self.contentScrollY or 0, 0, self:getMaxContentScroll())
end

function EHR_HealthPanelUI:drawScrollBar(x, y, w, h)
    local maxScroll = self:getMaxContentScroll()
    if maxScroll <= 0 then return end

    local c = EHR_HealthPanelUI.Colors
    local thumbH = math.max(32, math.floor(h * (h / math.max(h, self.contentHeight or h))))
    local thumbY = y + math.floor((self.contentScrollY / maxScroll) * (h - thumbH))

    self:drawRect(x, y, w, h, 0.45, 0.04, 0.04, 0.04)
    self:drawRect(x, thumbY, w, thumbH, c.border.a, c.border.r, c.border.g, c.border.b)
end

function EHR_HealthPanelUI:resetTemperatureButtonState(view)
    if not view then return end
    if view.viewButtons then
        for _, group in pairs(view.viewButtons) do
            for _, button in ipairs(group) do
                button.pressed = false
                button.mouseOver = false
            end
        end
    end
    if view.toggleAdvBtn then
        view.toggleAdvBtn.pressed = false
        view.toggleAdvBtn.mouseOver = false
    end
end

function EHR_HealthPanelUI:prerender()
    ISPanel.prerender(self)
    self:updateCachedData()
    self:layoutEmbeddedVanillaTabs()
    self:syncTabVisibility()

    local c = EHR_HealthPanelUI.Colors
    self:drawRect(0, 0, self.width, self.height, c.background.a, c.background.r, c.background.g, c.background.b)
    self:drawHeader()
    self:drawTabBar()

    if self.activeTab == "ehr" then
        self:drawLeftPanel()

        if self.rightExpanded then
            self:drawRightPanel()
        end
    else
        self:drawEmbeddedTabFrame()
    end
end

function EHR_HealthPanelUI:render()
    self:drawResizeHandle()
end

function EHR_HealthPanelUI:onMouseWheel(del)
    if self.activeTab ~= "ehr" then return false end
    if not self.rightExpanded then return false end
    local maxScroll = self:getMaxContentScroll()
    if maxScroll <= 0 then return false end

    self.contentScrollY = (self.contentScrollY or 0) + (del * self.SCROLL_STEP)
    self:clampContentScroll()
    return true
end

function EHR_HealthPanelUI:onMouseDown(x, y)
    if self:isInResizeHandle(x, y) then
        self.resizing = true
        self.resizeStartW = self.width
        self.resizeStartH = self.height
        self.resizeMouseStartX = getMouseX()
        self.resizeMouseStartY = getMouseY()
        self:bringToTop()
        return true
    end

    for _, tab in ipairs(self.tabBounds or {}) do
        if x >= tab.x and x <= tab.x + tab.w and y >= tab.y and y <= tab.y + tab.h then
            self:setActiveTab(tab.id)
            return true
        end
    end

    if self.activeTab == "ehr" then
        for _, marker in ipairs(self.markerBounds or {}) do
            if x >= marker.x and x <= marker.x + marker.w and y >= marker.y and y <= marker.y + marker.h then
                self.selectedZone = marker.id
                return true
            end
        end
    end

    if y <= self.HEADER_HEIGHT and x < self.width - 70 then
        self.dragging = true
        self.dragStartX = self:getX()
        self.dragStartY = self:getY()
        self.dragMouseStartX = getMouseX()
        self.dragMouseStartY = getMouseY()
        self:bringToTop()
        return true
    end

    return ISPanel.onMouseDown(self, x, y)
end

function EHR_HealthPanelUI:onMouseMove(dx, dy)
    if self.resizing then
        local mouseX = getMouseX()
        local mouseY = getMouseY()
        local newW = self.resizeStartW + (mouseX - self.resizeMouseStartX)
        local newH = self.resizeStartH + (mouseY - self.resizeMouseStartY)
        newW, newH = self:clampWindowSize(newW, newH)

        self:setWidth(newW)
        self:setHeight(newH)
        self:repositionControls()
        return true
    end

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

function EHR_HealthPanelUI:onMouseUp(x, y)
    self.dragging = false
    self.resizing = false
    self:keepOnScreen()
    return ISPanel.onMouseUp(self, x, y)
end

function EHR_HealthPanelUI:onClose()
    if EHR.UI and EHR.UI.HideHealthPanel then
        EHR.UI.HideHealthPanel()
        return
    end
    self:setVisible(false)
    EHR.UI.HealthPanelVisible = false
end

function EHR_HealthPanelUI:onToggleRight()
    self.rightExpanded = not self.rightExpanded
    if self.rightExpanded then
        self:setWidth(EHR_HealthPanelUI.EXPANDED_WIDTH)
    else
        self:setWidth(EHR_HealthPanelUI.COLLAPSED_WIDTH)
    end
    self:repositionControls()
    self:keepOnScreen()
end

function EHR.UI.ShowHealthPanel(player)
    player = player or (getSpecificPlayer and getSpecificPlayer(0)) or (getPlayer and getPlayer())
    if not player then return end

    suppressLegacyHealthUI(12)

    if not EHR.UI.HealthPanelInstance then
        local core = getCore and getCore()
        local screenW = core and core:getScreenWidth() or 1280
        local screenH = core and core:getScreenHeight() or 720
        local x = math.floor((screenW - EHR_HealthPanelUI.EXPANDED_WIDTH) / 2)
        local y = math.floor((screenH - EHR_HealthPanelUI.HEIGHT) / 2)

        local panel = EHR_HealthPanelUI:new(math.max(0, x), math.max(0, y), player)
        panel:initialise()
        panel:instantiate()
        panel:addToUIManager()
        EHR.UI.HealthPanelInstance = panel
    end

    EHR.UI.HealthPanelInstance.player = player
    EHR.UI.HealthPanelInstance.playerNum = player:getPlayerNum()
    EHR.UI.HealthPanelInstance.activeTab = "ehr"
    EHR.UI.HealthPanelInstance.contentScrollY = 0
    EHR.UI.HealthPanelInstance:syncTabVisibility()
    EHR.UI.HealthPanelInstance:setVisible(true)
    EHR.UI.HealthPanelInstance:bringToTop()
    EHR.UI.HealthPanelInstance:keepOnScreen()
    EHR.UI.HealthPanelVisible = true
end

function EHR.UI.HideHealthPanel()
    if EHR.UI.HealthPanelInstance then
        EHR.UI.HealthPanelInstance:setVisible(false)
    end
    EHR.UI.HealthPanelVisible = false
    suppressLegacyHealthUI(12)
end

function EHR.UI.ToggleHealthPanel(player)
    if EHR.UI.HealthPanelInstance and EHR.UI.HealthPanelInstance:isVisible() then
        EHR.UI.HideHealthPanel()
    else
        EHR.UI.ShowHealthPanel(player)
    end
end

if Events then
    Events.OnTick.Add(onTickHideVanilla)
end

EHR.Log("HealthPanelUI prototype loaded")
