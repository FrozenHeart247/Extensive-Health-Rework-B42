-- Extensive Health Rework B42
-- Clean bandage pack support.

require "ExtensiveHealth/EHR_Main"
pcall(function() require "ExtensiveHealth/EHR_Localization" end)
require "ExtensiveHealth/EHR_Medication"
pcall(function() require "TimedActions/ISBaseTimedAction" end)

EHR = EHR or {}
EHR.BandagePack = EHR.BandagePack or {}

local function bandagePackText(key, fallback)
    if EHR and EHR.Locale and EHR.Locale.Text then
        return EHR.Locale.Text("UI_EHR_BandagePack_" .. tostring(key), fallback)
    end
    local fullKey = "UI_EHR_BandagePack_" .. tostring(key)
    local ok, value = pcall(getText, fullKey)
    if ok and value and value ~= fullKey then return value end
    return fallback
end

local function bandagePackFormat(key, fallback, ...)
    if EHR and EHR.Locale and EHR.Locale.Format then
        return EHR.Locale.Format("UI_EHR_BandagePack_" .. tostring(key), fallback, ...)
    end
    local text = bandagePackText(key, fallback)
    local args = {...}
    for i, value in ipairs(args) do
        text = tostring(text):gsub("%%" .. tostring(i), tostring(value))
    end
    return text
end


local PACK_TYPE = "ExtensiveHealth.SterilizedBandages"
local CLEAN_BANDAGE_TYPE = "Base.Bandage"

local function isInventoryItem(item)
    return item and instanceof and instanceof(item, "InventoryItem")
end

local function unwrapContextItem(value)
    if isInventoryItem(value) then
        return value
    end
    if value and value.items then
        for i = 1, #value.items do
            if isInventoryItem(value.items[i]) then
                return value.items[i]
            end
        end
    end
    return nil
end

local function getDoseInfo(item)
    if not item or not EHR.Medication or not EHR.Medication.GetItemDoseInfo then
        return nil
    end

    local ok, info = pcall(function()
        return EHR.Medication.GetItemDoseInfo(item)
    end)

    if ok then
        return info
    end
    return nil
end

local function setRemainingDoses(player, item, remaining)
    local info = getDoseInfo(item)
    if not info or not item.setUsedDelta then
        return false
    end

    local maxDoses = info.maxDoses or 1
    local useDelta = info.useDelta or item:getUseDelta()
    remaining = math.max(0, math.min(maxDoses, math.floor(remaining + 0.0001)))

    local usedDelta = remaining * useDelta
    if remaining >= maxDoses then
        usedDelta = 1.0
    end
    usedDelta = math.max(0, math.min(1.0, usedDelta))

    local ok = pcall(function()
        item:setUsedDelta(usedDelta)
    end)

    if ok and isClient() and player and item.getID then
        sendClientCommand(player, "EHR", "UpdateItemDelta", {
            itemID = item:getID(),
            usedDelta = usedDelta,
        })
    end

    return ok
end

local function getRemainingDoses(item)
    local info = getDoseInfo(item)
    return info and (info.remainingDoses or 0) or 0
end

EHR.BandagePack.GetRemainingDoses = getRemainingDoses

local function getMaxDoses(item)
    local info = getDoseInfo(item)
    return info and (info.maxDoses or 1) or 1
end

function EHR.BandagePack.IsPack(item)
    return item and item.getFullType and item:getFullType() == PACK_TYPE
end

function EHR.BandagePack.IsCleanBandage(item)
    return item and item.getFullType and item:getFullType() == CLEAN_BANDAGE_TYPE
end

local function inventoryItems(inventory)
    local items = {}
    if not inventory or not inventory.getItems then
        return items
    end

    local list = inventory:getItems()
    if not list then
        return items
    end

    for i = 0, list:size() - 1 do
        table.insert(items, list:get(i))
    end

    return items
end

function EHR.BandagePack.FindPackWithSpace(inventory)
    for _, item in ipairs(inventoryItems(inventory)) do
        if EHR.BandagePack.IsPack(item) and getRemainingDoses(item) < getMaxDoses(item) then
            return item
        end
    end
    return nil
end

function EHR.BandagePack.FindCleanBandage(inventory)
    for _, item in ipairs(inventoryItems(inventory)) do
        if EHR.BandagePack.IsCleanBandage(item) then
            return item
        end
    end
    return nil
end

local function removeInventoryItem(player, item)
    if not item then return false end

    local container = item:getContainer()
    if isClient() and player and item.getID then
        sendClientCommand(player, "EHR", "RemoveItem", { itemID = item:getID() })
    end

    if container and container.Remove then
        container:Remove(item)
        return true
    end

    local inventory = player and player:getInventory()
    if inventory then
        inventory:Remove(item)
        return true
    end

    return false
end

local function markInventoryDirty(inventory)
    if inventory and inventory.setDrawDirty then
        inventory:setDrawDirty(true)
    end
end


local function getDamagedBodyParts(playerNum, player)
    pcall(function() require "ISUI/ISInventoryPaneContextMenu" end)
    if ISInventoryPaneContextMenu and ISInventoryPaneContextMenu.haveDamagePart then
        local ok, parts = pcall(ISInventoryPaneContextMenu.haveDamagePart, playerNum)
        if ok and type(parts) == "table" then
            return parts
        end
    end

    local result = {}
    local bodyDamage = player and player.getBodyDamage and player:getBodyDamage() or nil
    local bodyParts = bodyDamage and bodyDamage.getBodyParts and bodyDamage:getBodyParts() or nil
    if not bodyParts or not BodyPartType or not BodyPartType.ToIndex or not BodyPartType.MAX then
        return result
    end

    for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
        local bodyPart = bodyParts:get(i)
        if bodyPart and ((bodyPart.scratched and bodyPart:scratched())
                or (bodyPart.deepWounded and bodyPart:deepWounded())
                or (bodyPart.bitten and bodyPart:bitten())
                or (bodyPart.stitched and bodyPart:stitched())
                or (bodyPart.bleeding and bodyPart:bleeding())
                or ((bodyPart.isBurnt and bodyPart:isBurnt()) and not (bodyPart.bandaged and bodyPart:bandaged()))) then
            table.insert(result, bodyPart)
        end
    end

    return result
end

local function getItemID(item)
    if not item or not item.getID then return nil end
    local ok, id = pcall(function() return item:getID() end)
    if ok then return id end
    return nil
end

local function findInventoryItemByID(inventory, itemID, seen)
    if not inventory or itemID == nil then return nil end
    if inventory.getItemById then
        local ok, item = pcall(function() return inventory:getItemById(itemID) end)
        if ok and item then return item end
    end

    local items = inventory.getItems and inventory:getItems() or nil
    if not items or not items.size then return nil end

    seen = seen or {}
    if seen[inventory] then return nil end
    seen[inventory] = true

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if getItemID(item) == itemID then
                return item
            end
            if item.IsInventoryContainer and item:IsInventoryContainer() and item.getInventory then
                local found = findInventoryItemByID(item:getInventory(), itemID, seen)
                if found then return found end
            end
        end
    end

    return nil
end

function EHR.BandagePack.FindPackByID(player, itemID)
    local inventory = player and player.getInventory and player:getInventory() or nil
    local pack = findInventoryItemByID(inventory, itemID)
    if EHR.BandagePack.IsPack(pack) then return pack end
    return nil
end

local function markTemporaryBandage(singleBandage, pack)
    if not singleBandage or not singleBandage.getModData then return end
    local packID = getItemID(pack)
    if packID ~= nil then
        singleBandage:getModData().EHR_BandagePackSourceID = packID
    end
end

local function clearTemporaryBandageMark(singleBandage)
    if singleBandage and singleBandage.getModData then
        singleBandage:getModData().EHR_BandagePackSourceID = nil
    end
end

local function getPackSourceFromBandage(player, singleBandage)
    if not singleBandage or not singleBandage.getModData then return nil end
    local packID = singleBandage:getModData().EHR_BandagePackSourceID
    if packID == nil then return nil end
    return EHR.BandagePack.FindPackByID(player, packID)
end

local function removeTempBandageIfPresent(player, singleBandage)
    local inventory = player and player.getInventory and player:getInventory() or nil
    if not inventory or not singleBandage then return end
    pcall(function()
        if inventory:contains(singleBandage) then
            inventory:Remove(singleBandage)
        end
    end)
end

function EHR.BandagePack.CreateActionBandage(player, pack)
    if not player or not EHR.BandagePack.IsPack(pack) then return nil end
    if getRemainingDoses(pack) <= 0 then return nil end

    local inventory = player:getInventory()
    if not inventory then return nil end

    local singleBandage = inventory:AddItem(CLEAN_BANDAGE_TYPE)
    if not singleBandage then return nil end

    markTemporaryBandage(singleBandage, pack)
    markInventoryDirty(inventory)
    return singleBandage
end

function EHR.BandagePack.TakeBandageFromPack(player, pack)
    local singleBandage = EHR.BandagePack.CreateActionBandage(player, pack)
    if not singleBandage then return nil end

    if not EHR.BandagePack.ConsumePackDose(player, pack) then
        removeTempBandageIfPresent(player, singleBandage)
        return nil
    end

    clearTemporaryBandageMark(singleBandage)
    markInventoryDirty(player:getInventory())
    return singleBandage
end

local function callBodyPartBoolean(bodyPart, methodName)
    if not bodyPart or not methodName or not bodyPart[methodName] then return false end
    local ok, result = pcall(function() return bodyPart[methodName](bodyPart) end)
    return ok and result == true
end

local function bodyPartCanReceiveCleanBandage(bodyPart)
    if not bodyPart then return false end
    if callBodyPartBoolean(bodyPart, "bandaged") then return false end
    if callBodyPartBoolean(bodyPart, "HasInjury") then return true end
    if callBodyPartBoolean(bodyPart, "bleeding") then return true end
    if callBodyPartBoolean(bodyPart, "scratched") then return true end
    if callBodyPartBoolean(bodyPart, "deepWounded") then return true end
    if callBodyPartBoolean(bodyPart, "bitten") then return true end
    if callBodyPartBoolean(bodyPart, "isCut") then return true end
    if callBodyPartBoolean(bodyPart, "isBurnt") then return true end
    local okBurn, burnTime = pcall(function() return bodyPart:getBurnTime() end)
    return okBurn and (tonumber(burnTime) or 0) > 0
end

function EHR.BandagePack.ApplyCleanBandageFromPack(doctor, patient, pack, bodyPart, consumeDose)
    if not doctor or not patient or not EHR.BandagePack.IsPack(pack) or not bodyPartCanReceiveCleanBandage(bodyPart) then
        return false
    end
    if getRemainingDoses(pack) <= 0 then return false end

    local bodyDamage = patient.getBodyDamage and patient:getBodyDamage() or nil
    if not bodyDamage or not bodyDamage.SetBandaged then return false end

    local doctorLevel = 0
    if doctor.getPerkLevel and Perks and Perks.Doctor then
        local okLevel, level = pcall(function() return doctor:getPerkLevel(Perks.Doctor) end)
        if okLevel then doctorLevel = tonumber(level) or 0 end
    end
    if doctor.isTimedActionInstant and doctor:isTimedActionInstant() then
        doctorLevel = 10
    end

    local randomBonus = (doctorLevel + 1) * 0.75
    if ZombRandFloat then
        local okRand, value = pcall(function()
            return ZombRandFloat((doctorLevel + 1) * 0.5, (doctorLevel + 1) * 1.0)
        end)
        if okRand and value then randomBonus = value end
    end

    local bandageLife = randomBonus + 4.0
    if bodyPart.isGetBandageXp and bodyPart:isGetBandageXp() and bandageLife > 0 and addXp and Perks and Perks.Doctor then
        pcall(function() addXp(doctor, Perks.Doctor, 5) end)
    end

    pcall(function()
        bodyDamage:SetBandaged(bodyPart:getIndex(), true, bandageLife, false, CLEAN_BANDAGE_TYPE)
    end)

    if consumeDose ~= false then
        EHR.BandagePack.ConsumePackDose(doctor, pack)
    end

    if syncBodyPart then
        pcall(function() syncBodyPart(bodyPart, 0xc001966b8e) end)
    end
    return true
end

EHR_ApplyBandagePackAction = ISBaseTimedAction and ISBaseTimedAction:derive("EHR_ApplyBandagePackAction") or nil

if EHR_ApplyBandagePackAction then
    function EHR_ApplyBandagePackAction:isValid()
        if ISHealthPanel and ISHealthPanel.DidPatientMove and ISHealthPanel.DidPatientMove(self.character, self.otherPlayer, self.bandagedPlayerX, self.bandagedPlayerY) then
            return false
        end
        if not bodyPartCanReceiveCleanBandage(self.bodyPart) then return false end
        return self.packWasPresent == true
                and self.pack
                and EHR.BandagePack.IsPack(self.pack)
                and getRemainingDoses(self.pack) > 0
    end

    function EHR_ApplyBandagePackAction:waitToStart()
        if self.character == self.otherPlayer or self.character:isSeatedInVehicle() then
            return false
        end
        self.character:faceThisObject(self.otherPlayer)
        return self.character:shouldBeTurning()
    end

    function EHR_ApplyBandagePackAction:update()
        if self.character ~= self.otherPlayer then
            self.character:faceThisObject(self.otherPlayer)
        end
        if self.pack then
            self.pack:setJobDelta(self:getJobDelta())
        end
        if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
            ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, self, getText("ContextMenu_Bandage"), { bandage = true })
        end
        if self.character.setMetabolicTarget and Metabolics and Metabolics.LightDomestic then
            self.character:setMetabolicTarget(Metabolics.LightDomestic)
        end
    end

    function EHR_ApplyBandagePackAction:start()
        if isClient and isClient() and self.pack and self.pack.getID and self.character and self.character.getInventory then
            self.pack = self.character:getInventory():getItemById(self.pack:getID()) or self.pack
        end
        if self.character == self.otherPlayer then
            self:setActionAnim(CharacterActionAnims.Bandage)
            if ISHealthPanel and ISHealthPanel.getBandageType then
                self:setAnimVariable("BandageType", ISHealthPanel.getBandageType(self.bodyPart))
            end
            self.character:reportEvent("EventBandage")
        else
            self:setActionAnim("Loot")
            self.character:SetVariable("LootPosition", "Mid")
            self.character:reportEvent("EventLootItem")
        end
        self:setOverrideHandModels(nil, nil)
        if self.pack then
            self.pack:setJobType(getText("ContextMenu_Apply_Bandage"))
            self.pack:setJobDelta(0.0)
        end
        self.sound = self.character:playSound("FirstAidApplyBandage")
        if self.bodyPart and (self.bodyPart.HasInjury and self.bodyPart:HasInjury()) and self.otherPlayer and self.otherPlayer.playerVoiceSound then
            self.sound2 = self.otherPlayer:playerVoiceSound("ApplyBandage")
        end
    end

    function EHR_ApplyBandagePackAction:stopSound()
        if self.sound and self.character and self.character.getEmitter and self.character:getEmitter():isPlaying(self.sound) then
            self.character:stopOrTriggerSound(self.sound)
        end
        if self.sound2 and self.otherPlayer and self.otherPlayer.getEmitter and self.otherPlayer:getEmitter():isPlaying(self.sound2) then
            self.otherPlayer:stopOrTriggerSound(self.sound2)
        end
    end

    function EHR_ApplyBandagePackAction:stop()
        self:stopSound()
        if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
            ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, nil, nil, nil)
        end
        if self.pack then self.pack:setJobDelta(0.0) end
        if self.bodyPart then self.bodyPart:setManipulatingUsername(nil) end
        ISBaseTimedAction.stop(self)
    end

    function EHR_ApplyBandagePackAction:perform()
        self:stopSound()
        if self.pack then self.pack:setJobDelta(0.0) end
        if ISHealthPanel and ISHealthPanel.setBodyPartActionForPlayer then
            ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, nil, nil, nil)
        end
        if self.bodyPart then self.bodyPart:setManipulatingUsername(nil) end
        ISBaseTimedAction.perform(self)
    end

    function EHR_ApplyBandagePackAction:complete()
        if self.didApplyPack then return true end
        self.didApplyPack = true

        if isClient and isClient() then
            if self.character and self.pack and self.pack.getID and sendClientCommand then
                local args = {
                    packID = self.pack:getID(),
                    bodyPartIndex = self.bodyPart and self.bodyPart.getIndex and self.bodyPart:getIndex() or nil,
                }
                if self.otherPlayer and self.otherPlayer ~= self.character and self.otherPlayer.getOnlineID then
                    args.targetOnlineID = self.otherPlayer:getOnlineID()
                end
                pcall(function() sendClientCommand(self.character, "EHR", "ApplyBandagePack", args) end)
            end
        else
            pcall(function()
                EHR.BandagePack.ApplyCleanBandageFromPack(self.character, self.otherPlayer, self.pack, self.bodyPart, true)
            end)
        end

        return true
    end
    function EHR_ApplyBandagePackAction:getDuration()
        if self.character:isTimedActionInstant() then return 1 end
        return math.max(20, 120 - (self.doctorLevel * 4))
    end

    function EHR_ApplyBandagePackAction:new(character, otherPlayer, pack, bodyPart)
        local o = ISBaseTimedAction.new(self, character)
        o.character = character
        o.otherPlayer = otherPlayer or character
        o.doctorLevel = character:getPerkLevel(Perks.Doctor)
        o.pack = pack
        o.bodyPart = bodyPart
        o.stopOnWalk = bodyPart and bodyPart.getIndex and bodyPart:getIndex() > BodyPartType.ToIndex(BodyPartType.Groin) or true
        o.stopOnRun = true
        o.bandagedPlayerX = o.otherPlayer:getX()
        o.bandagedPlayerY = o.otherPlayer:getY()
        o.maxTime = o:getDuration()
        o.packWasPresent = pack ~= nil
        if character:isTimedActionInstant() then
            o.doctorLevel = 10
        end
        return o
    end
end

function EHR.BandagePack.CreateApplyAction(doctor, patient, pack, bodyPart)
    -- Kept for compatibility with older call sites. Pack application no longer uses a custom
    -- timed action because it can leave Project Zomboid's medical action state stuck.
    return nil
end

function EHR.BandagePack.ApplyPackBandageForPlayer(doctor, patient, pack, bodyPart)
    if not doctor or not EHR.BandagePack.IsPack(pack) or getRemainingDoses(pack) <= 0 then
        return false
    end

    local isRemotePatient = patient and patient ~= doctor
    if not (isClient and isClient() and isRemotePatient) and not bodyPartCanReceiveCleanBandage(bodyPart) then
        return false
    end

    if isClient and isClient() then
        if not pack.getID or not sendClientCommand then return false end
        local args = {
            packID = pack:getID(),
            bodyPartIndex = bodyPart and bodyPart.getIndex and bodyPart:getIndex() or nil,
        }
        if patient and patient ~= doctor then
            pcall(function()
                if patient.getOnlineID then args.targetOnlineID = patient:getOnlineID() end
            end)
            pcall(function()
                if patient.getUsername then args.targetUsername = patient:getUsername() end
            end)
            pcall(function()
                if patient.getDisplayName then args.targetDisplayName = patient:getDisplayName() end
            end)
        end
        if args.bodyPartIndex == nil then return false end
        sendClientCommand(doctor, "EHR", "ApplyBandagePack", args)
        return true
    end

    return EHR.BandagePack.ApplyCleanBandageFromPack(doctor, patient or doctor, pack, bodyPart, true)
end

function EHR.BandagePack.ApplyPackBandage(playerNum, pack, bodyPart)
    local player = getSpecificPlayer and getSpecificPlayer(playerNum or 0) or nil
    return EHR.BandagePack.ApplyPackBandageForPlayer(player, player, pack, bodyPart)
end

function EHR.BandagePack.AddBandageToPack(player, bandage, pack)
    if not player or not EHR.BandagePack.IsCleanBandage(bandage) then
        return false
    end

    local inventory = player:getInventory()
    if not inventory then
        return false
    end

    pack = pack or EHR.BandagePack.FindPackWithSpace(inventory)
    if not pack then
        pack = inventory:AddItem(PACK_TYPE)
        if not pack then return false end
        setRemainingDoses(player, pack, 0)
    end

    if not EHR.BandagePack.IsPack(pack) then
        return false
    end

    local remaining = getRemainingDoses(pack)
    local maxDoses = getMaxDoses(pack)
    if remaining >= maxDoses then
        return false
    end

    if not removeInventoryItem(player, bandage) then
        return false
    end

    setRemainingDoses(player, pack, remaining + 1)
    markInventoryDirty(inventory)

    return true
end

function EHR.BandagePack.UnpackBandage(player, pack)
    if not player or not EHR.BandagePack.IsPack(pack) then return false end
    if isClient and isClient() then
        local packID = getItemID(pack)
        if packID == nil then return false end
        sendClientCommand(player, "EHR", "UnpackCleanBandage", { packID = packID })
        return true
    end
    return EHR.BandagePack.TakeBandageFromPack(player, pack) ~= nil
end

function EHR.BandagePack.ConsumePackDose(player, pack)
    if not player or not EHR.BandagePack.IsPack(pack) then
        return false
    end
    if getRemainingDoses(pack) <= 0 then return false end

    if pack.UseAndSync then
        local ok = pcall(function() pack:UseAndSync() end)
        if ok then
            markInventoryDirty(player:getInventory())
            return true
        end
    end

    if pack.Use then
        local ok = pcall(function() pack:Use() end)
        if ok then
            markInventoryDirty(player:getInventory())
            return true
        end
    end

    local remaining = getRemainingDoses(pack)
    if remaining > 1 then
        return setRemainingDoses(player, pack, remaining - 1)
    end

    return removeInventoryItem(player, pack)
end
function EHR.BandagePack.HookApplyBandage()
    -- No global ISApplyBandage patching here. Keeping vanilla bandage actions untouched is safer,
    -- especially in multiplayer. Pack usage is handled through UnpackCleanBandage.
end

function EHR.BandagePack.OnFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local inventory = player:getInventory()
    if not inventory then return end

    for _, value in ipairs(items) do
        local item = unwrapContextItem(value)
        if item then
            if EHR.BandagePack.IsCleanBandage(item) then
                local pack = EHR.BandagePack.FindPackWithSpace(inventory)
                local label = pack and bandagePackText("AddToPack", "Add to Clean Bandages Pack") or bandagePackText("CreatePack", "Create Clean Bandages Pack")
                local option = context:addOption(label, player, function(plr, bandageItem, targetPack)
                    EHR.BandagePack.AddBandageToPack(plr, bandageItem, targetPack)
                end, item, pack)
                if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, pack or item) end
            elseif EHR.BandagePack.IsPack(item) then
                if getRemainingDoses(item) > 0 then
                    local option = context:addOption(bandagePackText("Unpack", "Unpack Clean Bandage"), player, function(plr, packItem)
                        EHR.BandagePack.UnpackBandage(plr, packItem)
                    end, item)
                    if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, item) end
                end

                if getRemainingDoses(item) < getMaxDoses(item) then
                    local bandage = EHR.BandagePack.FindCleanBandage(inventory)
                    if bandage then
                        local option = context:addOption(bandagePackText("AddSingle", "Add Clean Bandage to Pack"), player, function(plr, bandageItem, packItem)
                            EHR.BandagePack.AddBandageToPack(plr, bandageItem, packItem)
                        end, bandage, item)
                        if EHR.SetContextOptionIcon then EHR.SetContextOptionIcon(option, bandage) end
                    end
                end
            end
        end
    end
end

if Events and not EHR.BandagePack.EventsRegistered then
    EHR.BandagePack.HookApplyBandage()
    Events.OnGameStart.Add(EHR.BandagePack.HookApplyBandage)
    Events.OnFillInventoryObjectContextMenu.Add(EHR.BandagePack.OnFillInventoryObjectContextMenu)
    EHR.BandagePack.EventsRegistered = true
    EHR.Log("BandagePack module loaded")
end


