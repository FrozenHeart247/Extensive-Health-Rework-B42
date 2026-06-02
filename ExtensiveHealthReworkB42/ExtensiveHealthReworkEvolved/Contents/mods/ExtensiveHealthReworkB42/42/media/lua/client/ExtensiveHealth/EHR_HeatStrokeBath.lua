--[[
    Extensive Health Rework B42
    Heat Stroke Cold Bath Treatment

    Adds a bathtub world-context action that stabilizes heat stroke symptoms
    during the action and cures Heat Stroke after 3 in-game hours.
]]--

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
require "ExtensiveHealth/EHR_Disease"
require "ExtensiveHealth/EHR_EnvironmentalDiseases"
require "ExtensiveHealth/EHR_BodyTemperature"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISWalkToTimedAction"

pcall(function() require "ExtensiveHealth/EHR_LifestyleCompat" end)

EHR = EHR or {}
EHR.HeatStrokeBath = EHR.HeatStrokeBath or {}

EHR.HeatStrokeBath.DurationHours = 3.0
EHR.HeatStrokeBath.WaterRequired = 8

local BATH_PARTS = {
    fixtures_bathroom_01_25 = { main = "fixtures_bathroom_01_25", sub = "fixtures_bathroom_01_24", dir = IsoDirections.S, facing = "S", isMain = true },
    fixtures_bathroom_01_24 = { main = "fixtures_bathroom_01_25", sub = "fixtures_bathroom_01_24", dir = IsoDirections.N, facing = "S", isMain = false },
    fixtures_bathroom_01_26 = { main = "fixtures_bathroom_01_26", sub = "fixtures_bathroom_01_27", dir = IsoDirections.E, facing = "E", isMain = true },
    fixtures_bathroom_01_27 = { main = "fixtures_bathroom_01_26", sub = "fixtures_bathroom_01_27", dir = IsoDirections.W, facing = "E", isMain = false },
    fixtures_bathroom_01_52 = { main = "fixtures_bathroom_01_52", sub = "fixtures_bathroom_01_53", dir = IsoDirections.N, facing = "N", isMain = true },
    fixtures_bathroom_01_53 = { main = "fixtures_bathroom_01_52", sub = "fixtures_bathroom_01_53", dir = IsoDirections.S, facing = "N", isMain = false },
    fixtures_bathroom_01_55 = { main = "fixtures_bathroom_01_55", sub = "fixtures_bathroom_01_54", dir = IsoDirections.W, facing = "W", isMain = true },
    fixtures_bathroom_01_54 = { main = "fixtures_bathroom_01_55", sub = "fixtures_bathroom_01_54", dir = IsoDirections.E, facing = "W", isMain = false },
}

local function EHR_HeatStrokeBathText(key, fallback)
    if getText then
        local ok, text = pcall(getText, key)
        if ok and text and text ~= key then return text end
    end
    return fallback
end

local function EHR_HeatStrokeBathCurrentHour()
    local gameTime = getGameTime and getGameTime() or nil
    return gameTime and gameTime:getWorldAgeHours() or 0
end

local function EHR_HeatStrokeBathGetSpriteName(object)
    if not object or not object.getSprite then return nil end
    local sprite = object:getSprite()
    if not sprite or not sprite.getName then return nil end
    return sprite:getName()
end

local function EHR_HeatStrokeBathFindSprite(square, spriteName)
    if not square or not spriteName or not square.getObjects then return nil end

    local objects = square:getObjects()
    if not objects then return nil end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if EHR_HeatStrokeBathGetSpriteName(object) == spriteName then
            return object
        end
    end

    return nil
end

function EHR.HeatStrokeBath.GetBathParts(object)
    local spriteName = EHR_HeatStrokeBathGetSpriteName(object)
    local part = spriteName and BATH_PARTS[spriteName] or nil
    if not part or not object or not object.getSquare then return nil end

    local square = object:getSquare()
    if not square then return nil end

    local connectedSquare = square:getAdjacentSquare(part.dir)
    if not connectedSquare then return nil end

    local connectedSprite = part.isMain and part.sub or part.main
    local connected = EHR_HeatStrokeBathFindSprite(connectedSquare, connectedSprite)
    if not connected then return nil end

    local main = part.isMain and object or connected
    local sub = part.isMain and connected or object

    return {
        main = main,
        sub = sub,
        mainSprite = part.main,
        subSprite = part.sub,
        facing = part.facing,
    }
end

local function EHR_HeatStrokeBathFindClickableBath(worldObjects)
    if not worldObjects then return nil end

    for _, object in ipairs(worldObjects) do
        local parts = EHR.HeatStrokeBath.GetBathParts(object)
        if parts then return parts end
    end

    return nil
end

local function EHR_HeatStrokeBathHasHeatStroke(player)
    if not (player and EHR.Disease and EHR.Disease.GetDiseaseData) then return false end
    local data = EHR.Disease.GetDiseaseData(player)
    return data and data.active and data.active.heat_stroke ~= nil
end

local function EHR_HeatStrokeBathHasEnoughWater(parts)
    local main = parts and parts.main
    if not main then return false end

    if main.hasWater and main.getFluidAmount then
        local ok, hasWater, amount = pcall(function()
            return main:hasWater(), main:getFluidAmount()
        end)
        if ok then
            return hasWater == true and (tonumber(amount) or 0) >= EHR.HeatStrokeBath.WaterRequired
        end
    end

    if main.hasWater then
        local ok, hasWater = pcall(function() return main:hasWater() end)
        if ok then return hasWater == true end
    end

    return true
end

local function EHR_HeatStrokeBathGetWalkSquare(player, main)
    if not player or not main or not main.getSquare then return nil end

    local square = main:getSquare()
    if not square then return nil end

    local spriteName = EHR_HeatStrokeBathGetSpriteName(main)
    local candidates = {}

    if spriteName == "fixtures_bathroom_01_25" or spriteName == "fixtures_bathroom_01_52" then
        candidates = { square:getE(), square:getW() }
    elseif spriteName == "fixtures_bathroom_01_26" or spriteName == "fixtures_bathroom_01_55" then
        candidates = { square:getS(), square:getN() }
    else
        candidates = { square:getE(), square:getW(), square:getS(), square:getN() }
    end

    local bestSquare = nil
    local bestDistance = nil
    for _, candidate in ipairs(candidates) do
        if candidate and AdjacentFreeTileFinder and AdjacentFreeTileFinder.privTrySquare(square, candidate) then
            local distance = math.abs(player:getX() - candidate:getX()) + math.abs(player:getY() - candidate:getY())
            if not bestDistance or distance < bestDistance then
                bestSquare = candidate
                bestDistance = distance
            end
        end
    end

    return bestSquare
end

local function EHR_HeatStrokeBathGetTubRestOffset(facing)
    if facing == "S" or facing == "W" then
        return 0.4, 0.35
    end
    return 0.35, 0.4
end

local function EHR_HeatStrokeBathCanUseLifestyleAnimation(player)
    if not (EHR.LifestyleCompat and EHR.LifestyleCompat.IsModLoaded) then return false end

    local ok, loaded = pcall(EHR.LifestyleCompat.IsModLoaded)
    return ok and loaded == true
end

local function EHR_HeatStrokeBathSetPlayerPosition(player, x, y)
    if not player or not x or not y then return end
    pcall(function() player:setX(x) end)
    pcall(function() player:setY(y) end)
    pcall(function() if player.setLx then player:setLx(x) end end)
    pcall(function() if player.setLy then player:setLy(y) end end)
end

local function EHR_HeatStrokeBathSetColdBathFlag(player, active, untilHour)
    local modData = player and player:getModData() or nil
    if not modData then return end

    if active then
        modData.EHR_HeatStrokeColdBathActive = true
        modData.EHR_HeatStrokeColdBathUntil = untilHour or (EHR_HeatStrokeBathCurrentHour() + EHR.HeatStrokeBath.DurationHours)
        return
    end

    modData.EHR_HeatStrokeColdBathActive = nil
    modData.EHR_HeatStrokeColdBathUntil = nil
end

local function EHR_HeatStrokeBathMarkLifestyleColdBath(player)
    if not EHR_HeatStrokeBathCanUseLifestyleAnimation(player) then return end

    local modData = player and player:getModData() or nil
    if not modData then return end

    modData.EHR_LastBathTime = EHR_HeatStrokeBathCurrentHour()
    modData.lastBath = player.getHoursSurvived and player:getHoursSurvived() or modData.lastBath
    if modData.LSMoodles then
        modData.LSMoodles.BathCold = modData.LSMoodles.BathCold or {}
        modData.LSMoodles.BathCold.Value = math.max(tonumber(modData.LSMoodles.BathCold.Value) or 0, 0.2)
    end
end

function EHR.HeatStrokeBath.ResetHeatAfterBath(player)
    local exposure = EHR.Environmental and EHR.Environmental.GetExposureData and EHR.Environmental.GetExposureData(player) or nil
    if exposure then
        exposure.heatExposure = 0
        exposure.heatStrokeExposure = 0
        exposure.lastHeatStrokeRiskCheck = EHR_HeatStrokeBathCurrentHour()
    end

    if EHR.BodyTemp then
        if EHR.BodyTemp.WriteDiseaseBodyTemperature then
            pcall(EHR.BodyTemp.WriteDiseaseBodyTemperature, player, 37.0)
        end

        if EHR.BodyTemp.GetTemperatureData then
            local tempData = EHR.BodyTemp.GetTemperatureData(player)
            if tempData then
                tempData.bodyTemp = 37.0
                tempData.diseaseTargetTemp = nil
                tempData.diseaseTargetTempUntil = nil
            end
        end

        if EHR.BodyTemp.ResetDiseaseFeverIfStale then
            pcall(EHR.BodyTemp.ResetDiseaseFeverIfStale, player, true)
        end
    end
end

EHRHeatStrokeColdBathAction = ISBaseTimedAction:derive("EHRHeatStrokeColdBathAction")

function EHRHeatStrokeColdBathAction:isValid()
    if not self.character or not self.character:isAlive() then return false end
    if not self.parts or not self.parts.main then return false end
    return EHR_HeatStrokeBathHasHeatStroke(self.character)
end

function EHRHeatStrokeColdBathAction:start()
    local now = EHR_HeatStrokeBathCurrentHour()
    self.startHour = now
    self.endHour = now + EHR.HeatStrokeBath.DurationHours
    self.useLifestyleAnim = EHR_HeatStrokeBathCanUseLifestyleAnimation(self.character)

    EHR_HeatStrokeBathSetColdBathFlag(self.character, true, self.endHour)

    if self.character.setMetabolicTarget and Metabolics then
        self.character:setMetabolicTarget(Metabolics.LightWork)
    end

    if self.character.Say then
        EHR.Locale.Say(self.character, EHR_HeatStrokeBathText("UI_EHR_ColdBath_Start", "Cold... but I need this."))
    end

    if self.useLifestyleAnim and self.parts and self.parts.main then
        self.startX = self.character:getX()
        self.startY = self.character:getY()

        local offsetX, offsetY = EHR_HeatStrokeBathGetTubRestOffset(self.parts.facing)
        EHR_HeatStrokeBathSetPlayerPosition(
            self.character,
            self.parts.main:getSquare():getX() + offsetX,
            self.parts.main:getSquare():getY() + offsetY
        )

        pcall(function() self:setActionAnim("Bob_Tub_Enter") end)
        pcall(function() self.character:getEmitter():playSound("Tub_Splash1") end)
    else
        pcall(function() self:setActionAnim("Loot") end)
    end
end

function EHRHeatStrokeColdBathAction:update()
    local now = EHR_HeatStrokeBathCurrentHour()
    local elapsed = math.max(0, now - (self.startHour or now))
    local progress = math.min(1, elapsed / EHR.HeatStrokeBath.DurationHours)

    EHR_HeatStrokeBathSetColdBathFlag(self.character, true, (self.endHour or now) + 0.1)

    if self.useLifestyleAnim then
        if progress > 0.08 and not self.baseAnimStarted then
            self.baseAnimStarted = true
            pcall(function() self:setActionAnim("Bob_Tub_Base") end)
        end
    elseif self.parts and self.parts.main and self.character.faceThisObject then
        pcall(function() self.character:faceThisObject(self.parts.main) end)
    end

    if self.setJobDelta then
        pcall(function() self:setJobDelta(progress) end)
    end

    if progress >= 1 and self.forceComplete then
        self:forceComplete()
    end
end

function EHRHeatStrokeColdBathAction:stop()
    EHR_HeatStrokeBathSetColdBathFlag(self.character, false)

    if self.useLifestyleAnim and self.startX and self.startY then
        EHR_HeatStrokeBathSetPlayerPosition(self.character, self.startX, self.startY)
    end

    ISBaseTimedAction.stop(self)
end

function EHRHeatStrokeColdBathAction:perform()
    EHR_HeatStrokeBathSetColdBathFlag(self.character, false)
    EHR_HeatStrokeBathMarkLifestyleColdBath(self.character)

    if EHR.Disease and EHR.Disease.Cure then
        EHR.Disease.Cure(self.character, "heat_stroke")
    end
    EHR.HeatStrokeBath.ResetHeatAfterBath(self.character)

    if self.useLifestyleAnim and self.startX and self.startY then
        EHR_HeatStrokeBathSetPlayerPosition(self.character, self.startX, self.startY)
        pcall(function() self.character:getEmitter():playSound("Tub_End") end)
    end

    if self.character.Say then
        EHR.Locale.Say(self.character, EHR_HeatStrokeBathText("UI_EHR_ColdBath_Complete", "The fever finally broke..."))
    end

    ISBaseTimedAction.perform(self)
end

function EHRHeatStrokeColdBathAction:new(character, parts)
    local o = ISBaseTimedAction.new(self, character)
    o.parts = parts
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.ignoreDynamicTime = true
    o.maxTime = -1
    o.startHour = 0
    o.endHour = 0
    o.useLifestyleAnim = false
    o.baseAnimStarted = false
    return o
end

function EHR.HeatStrokeBath.OnTakeColdBath(player, parts)
    if not player or not parts then return end

    local walkSquare = EHR_HeatStrokeBathGetWalkSquare(player, parts.main)
    if walkSquare then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, walkSquare))
    end

    ISTimedActionQueue.add(EHRHeatStrokeColdBathAction:new(player, parts))
end

function EHR.HeatStrokeBath.OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    if not EHR_HeatStrokeBathHasHeatStroke(player) then return end

    local parts = EHR_HeatStrokeBathFindClickableBath(worldObjects)
    if not parts then return end

    local optionText = EHR_HeatStrokeBathText("UI_EHR_Context_TakeColdBath", "Take Cold Bath")
    local option
    if context.addOptionOnTop then
        option = context:addOptionOnTop(optionText, player, EHR.HeatStrokeBath.OnTakeColdBath, parts)
    else
        option = context:addOption(optionText, player, EHR.HeatStrokeBath.OnTakeColdBath, parts)
    end

    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(optionText)
    tooltip.description = EHR_HeatStrokeBathText(
        "UI_EHR_Context_TakeColdBathDesc",
        "Spend 3 hours cooling down in a bathtub. Cures Heat Stroke if completed."
    )
    option.toolTip = tooltip

    if not EHR_HeatStrokeBathHasEnoughWater(parts) then
        option.notAvailable = true
        tooltip.description = EHR_HeatStrokeBathText("UI_EHR_Context_TakeColdBathNoWater", "The bathtub needs water.")
    end
end

if not EHR.HeatStrokeBath._registered then
    EHR.HeatStrokeBath._registered = true
    Events.OnFillWorldObjectContextMenu.Add(EHR.HeatStrokeBath.OnFillWorldObjectContextMenu)
    EHR.Log("HeatStrokeBath: Cold bath treatment context menu registered")
end
