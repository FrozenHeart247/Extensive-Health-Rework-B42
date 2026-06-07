require "TimedActions/ISBaseTimedAction"

EHR = EHR or {}
EHR.WashHands = EHR.WashHands or {}

local TARGET_PARTS = {
    "Hand_L", "Hand_R",
    "ForeArm_L", "ForeArm_R",
    "UpperArm_L", "UpperArm_R",
}

local WATER_PER_PART = 0.25
local WATER_PER_PART_WITH_SOAP = 0.15
local MIN_WATER = 0.1

local function text(key, fallback)
    if getText then
        local ok, value = pcall(getText, key)
        if ok and value and value ~= key then return value end
    end
    return fallback
end

local function getSpriteName(object)
    if not (object and object.getSprite) then return nil end
    local sprite = object:getSprite()
    if not (sprite and sprite.getName) then return nil end
    return sprite:getName()
end

local function isPuddleObject(object)
    if not (object and object.getProperties) then return false end
    local props = object:getProperties()
    if not props then return false end

    local hasWaterFlag = props:has(IsoFlagType.water)
    local spriteName = getSpriteName(object) or ""
    local isLakeOrRiver = luautils and luautils.stringStarts
        and luautils.stringStarts(spriteName, "blends_natural_02")
    local isInventoryItem = instanceof and instanceof(object, "IsoWorldInventoryObject")

    return not isInventoryItem
        and not hasWaterFlag
        and not isLakeOrRiver
        and props:has(IsoFlagType.solidfloor)
end

local function isUsableWaterSource(object)
    if not object or isPuddleObject(object) then return false end

    if object.getFluidAmount then
        local ok, amount = pcall(function() return object:getFluidAmount() end)
        if ok and tonumber(amount) and amount > 0 then return true end
    end

    if object.hasWater then
        local ok, hasWater = pcall(function() return object:hasWater() end)
        if ok and hasWater then return true end
    end

    return false
end

local function findWaterSource(worldObjects)
    if not worldObjects then return nil end

    local seenSquares = {}

    for _, object in ipairs(worldObjects) do
        if isUsableWaterSource(object) then return object end

        if object and object.getSquare then
            local square = object:getSquare()
            if square and not seenSquares[square] then
                seenSquares[square] = true
                local objects = square:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local squareObject = objects:get(i)
                        if isUsableWaterSource(squareObject) then return squareObject end
                    end
                end
            end
        end
    end

    return nil
end

local function getBloodBodyPart(partName)
    if not BloodBodyPartType then return nil end

    if partName == "Hand_L" then return BloodBodyPartType.Hand_L end
    if partName == "Hand_R" then return BloodBodyPartType.Hand_R end
    if partName == "ForeArm_L" then return BloodBodyPartType.ForeArm_L end
    if partName == "ForeArm_R" then return BloodBodyPartType.ForeArm_R end
    if partName == "UpperArm_L" then return BloodBodyPartType.UpperArm_L end
    if partName == "UpperArm_R" then return BloodBodyPartType.UpperArm_R end

    return nil
end

local function getHumanVisual(character)
    if not (character and character.getHumanVisual) then return nil end
    local ok, visual = pcall(function() return character:getHumanVisual() end)
    if ok then return visual end
    return nil
end

local function getPartSoil(visual, part)
    if not (visual and part) then return 0, 0 end
    local blood, dirt = 0, 0

    if visual.getBlood then
        local ok, value = pcall(function() return visual:getBlood(part) end)
        if ok and tonumber(value) then blood = value end
    end
    if visual.getDirt then
        local ok, value = pcall(function() return visual:getDirt(part) end)
        if ok and tonumber(value) then dirt = value end
    end

    return blood, dirt
end

local function getSoapList(character)
    local inventory = character and character.getInventory and character:getInventory() or nil
    if inventory and inventory.getSoapList then
        local ok, soaps = pcall(function() return inventory:getSoapList(nil, false) end)
        if ok then return soaps end
    end
    return nil
end

local function hasSoap(character)
    local soaps = getSoapList(character)
    if not (soaps and soaps.size) then return false end

    for i = 0, soaps:size() - 1 do
        local soap = soaps:get(i)
        if instanceof and instanceof(soap, "DrainableComboItem") and soap.getCurrentUses and soap:getCurrentUses() > 0 then
            return true
        end
    end

    return false
end

function EHR.WashHands.GetDirtyPartCount(character)
    local visual = getHumanVisual(character)
    if not visual then return 0, false end

    local count = 0
    local hasBlood = false

    for _, partName in ipairs(TARGET_PARTS) do
        local part = getBloodBodyPart(partName)
        local blood, dirt = getPartSoil(visual, part)
        if blood + dirt > 0 then
            count = count + 1
            if blood > 0 then hasBlood = true end
        end
    end

    return count, hasBlood
end

function EHR.WashHands.GetRequiredWater(character)
    local dirtyParts = EHR.WashHands.GetDirtyPartCount(character)
    if dirtyParts <= 0 then return 0 end

    local perPart = hasSoap(character) and WATER_PER_PART_WITH_SOAP or WATER_PER_PART
    return math.max(MIN_WATER, dirtyParts * perPart)
end

local EHRWashHandsAction = ISBaseTimedAction:derive("EHRWashHandsAction")

function EHRWashHandsAction:isValid()
    if self.didWashHands then return true end
    return self.character
        and self.sink
        and isUsableWaterSource(self.sink)
        and EHR.WashHands.GetDirtyPartCount(self.character) > 0
        and self.sink.getFluidAmount
        and self.sink:getFluidAmount() >= math.min(MIN_WATER, self.waterRequired or MIN_WATER)
end

function EHRWashHandsAction:update()
    if self.character.faceThisObjectAlt then
        self.character:faceThisObjectAlt(self.sink)
    elseif self.character.faceThisObject then
        self.character:faceThisObject(self.sink)
    end

    if self.character.setMetabolicTarget and Metabolics then
        self.character:setMetabolicTarget(Metabolics.LightDomestic)
    end
end

function EHRWashHandsAction:start()
    self:setActionAnim("WashFace")
    self:setOverrideHandModels(nil, nil)
    self.character:reportEvent("EventWashClothing")
end

function EHRWashHandsAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function EHRWashHandsAction:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function EHRWashHandsAction:animEvent(event, parameter)
    if event == "PlayWashSound" then
        self:stopSound()
        self.sound = self.character:playSound("WashYourself")
    end
end

function EHRWashHandsAction:consumeSoapOnce()
    if not self.useSoap then return end

    local soaps = getSoapList(self.character)
    if not (soaps and soaps.size) then return end

    for i = 0, soaps:size() - 1 do
        local soap = soaps:get(i)
        if instanceof and instanceof(soap, "DrainableComboItem") and soap.getCurrentUses and soap:getCurrentUses() > 0 then
            soap:UseAndSync()
            return
        end
    end
end

function EHRWashHandsAction:complete()
    if self.didWashHands then return true end

    local visual = getHumanVisual(self.character)
    if not visual then
        self.didWashHands = true
        return true
    end

    local cleaned = 0
    local cleanedBlood = false

    for _, partName in ipairs(TARGET_PARTS) do
        local part = getBloodBodyPart(partName)
        local blood, dirt = getPartSoil(visual, part)
        if blood + dirt > 0 then
            if blood > 0 then cleanedBlood = true end
            if visual.setBlood then pcall(function() visual:setBlood(part, 0) end) end
            if visual.setDirt then pcall(function() visual:setDirt(part, 0) end) end
            cleaned = cleaned + 1
        end
    end

    if cleaned <= 0 then
        self.didWashHands = true
        return true
    end

    if cleanedBlood then self:consumeSoapOnce() end

    if sendHumanVisual then pcall(function() sendHumanVisual(self.character) end) end
    if self.character.resetModelNextFrame then pcall(function() self.character:resetModelNextFrame() end) end

    local waterUsed = math.min(self.waterRequired or MIN_WATER, self.sink:getFluidAmount())
    if self.sink.useFluid then
        local ok, used = pcall(function() return self.sink:useFluid(waterUsed) end)
        if ok and used and used > 0 and self.sink.transmitModData then
            pcall(function() self.sink:transmitModData() end)
        end
    end

    if self.useSoap and self.character.getStats then
        pcall(function() self.character:getStats():remove(CharacterStat.UNHAPPINESS, 1) end)
    end

    self.didWashHands = true
    return true
end

function EHRWashHandsAction:perform()
    self:stopSound()
    ISBaseTimedAction.perform(self)
end

function EHRWashHandsAction:new(character, sink)
    local o = ISBaseTimedAction.new(self, character)
    o.sink = sink
    o.waterRequired = EHR.WashHands.GetRequiredWater(character)
    o.useSoap = hasSoap(character)
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = false
    o.forceProgressBar = true
    o.didWashHands = false
    o.maxTime = character:isTimedActionInstant() and 1 or math.max(80, o.waterRequired * (o.useSoap and 90 or 145))
    return o
end

function EHR.WashHands.OnWashHands(player, sink)
    if not (player and sink) then return end
    if luautils and luautils.walkAdjObject and not luautils.walkAdjObject(player, sink, true, true) then return end
    ISTimedActionQueue.add(EHRWashHandsAction:new(player, sink))
end

function EHR.WashHands.OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end

    local sink = findWaterSource(worldObjects)
    if not sink then return end

    local requiredWater = EHR.WashHands.GetRequiredWater(player)
    local handsAreClean = requiredWater <= 0
    local hasEnoughWater = true
    if not handsAreClean and sink.getFluidAmount and sink:getFluidAmount() < requiredWater then
        hasEnoughWater = false
    end

    local optionText = text("UI_EHR_Context_WashHands", "Wash hands")
    local option
    if handsAreClean or not hasEnoughWater then
        option = context.addOptionOnTop and context:addOptionOnTop(optionText)
            or context:addOption(optionText)
        if option then option.notAvailable = true end
    else
        option = context.addOptionOnTop and context:addOptionOnTop(optionText, player, EHR.WashHands.OnWashHands, sink)
            or context:addOption(optionText, player, EHR.WashHands.OnWashHands, sink)
    end
    if option and getTexture then option.iconTexture = getTexture("media/textures/EHR_WashHands.png") end

    local tooltip = ISWorldObjectContextMenu and ISWorldObjectContextMenu.addToolTip and ISWorldObjectContextMenu.addToolTip() or nil
    if tooltip then
        tooltip:setName(optionText)
        if handsAreClean then
            tooltip.description = text("UI_EHR_Context_WashHandsClean", "Hands are already clean.")
        elseif not hasEnoughWater then
            tooltip.description = text("UI_EHR_Context_WashHandsNoWater", "Not enough water.")
        else
            tooltip.description = text("UI_EHR_Context_WashHandsDesc", "Clean blood and dirt from hands and arms using a small amount of water.")
        end
        if not handsAreClean and hasEnoughWater and hasSoap(player) then
            tooltip.description = tooltip.description .. " <LINE> " .. text("UI_EHR_Context_WashHandsSoap", "Soap reduces water use.")
        end
        option.toolTip = tooltip
    end
end

if not EHR.WashHands._registered then
    EHR.WashHands._registered = true
    Events.OnFillWorldObjectContextMenu.Add(EHR.WashHands.OnFillWorldObjectContextMenu)
end
