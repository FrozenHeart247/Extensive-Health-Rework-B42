--[[
    Extensive Health Rework B42
    Custom radio interaction effects for The Last Prescription.

    EHX+N grants exact First Aid XP through EHR's XP layer.
    EHK=disease_id unlocks disease knowledge through the flyer/journal layer.
]]--

require "ExtensiveHealth/EHR_Main"
require "ExtensiveHealth/EHR_DiseaseFlyers"
require "ExtensiveHealth/EHR_SkillXP"

EHR = EHR or {}
EHR.RadioInteractions = EHR.RadioInteractions or {}

local RADIO_DATA_KEY = "EHR_Radio"

local function log(message)
    if EHR and EHR.Log then
        EHR.Log("[RadioInteractions] " .. tostring(message))
    end
end

local function splitCodes(codes)
    local result = {}
    if not codes or codes == "" then
        return result
    end

    tostring(codes):gsub("([^,]+)", function(code)
        result[#result + 1] = code
    end)

    return result
end

local function playerInRange(player, x, y, z)
    if not player then return false end
    if x == -1 and y == -1 and z == -1 then return true end

    if math.floor(player:getZ()) ~= math.floor(z) then
        return false
    end

    local square = player:getSquare()
    local source = getCell() and getCell():getGridSquare(x, y, z) or nil
    if source and square and source:isOutside() ~= square:isOutside() then
        return false
    end

    return player:getX() >= x - 5
        and player:getX() <= x + 5
        and player:getY() >= y - 5
        and player:getY() <= y + 5
end

local function getRadioData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData then return nil end

    modData[RADIO_DATA_KEY] = modData[RADIO_DATA_KEY] or {
        heardEffects = {},
    }
    modData[RADIO_DATA_KEY].heardEffects = modData[RADIO_DATA_KEY].heardEffects or {}

    return modData[RADIO_DATA_KEY]
end

local function alreadyHandled(player, effectKey)
    local data = getRadioData(player)
    if not data then return true end

    if data.heardEffects[effectKey] then
        return true
    end

    data.heardEffects[effectKey] = true
    return false
end

local function getCurrentBroadcastKey(code)
    local gameTime = getGameTime()
    local day = 0
    local hour = 0
    if gameTime then
        day = (gameTime:getNightsSurvived() or 0) + 1
        hour = gameTime:getHour() or 0
    end
    return tostring(day) .. ":" .. tostring(hour) .. ":" .. tostring(code)
end

local function addHalo(player, text)
    if player and HaloTextHelper and HaloTextHelper.addGoodText then
        pcall(function() HaloTextHelper.addGoodText(player, text) end)
    end
end

local function handleXP(player, token)
    local op = token:sub(4, 4)
    local amount = tonumber(token:sub(5))
    if not amount then return end
    if op == "-" then amount = amount * -1 end
    if amount <= 0 then return end

    local effectKey = getCurrentBroadcastKey("XP:" .. tostring(amount))
    if alreadyHandled(player, effectKey) then
        return
    end

    if EHR.SkillXP and EHR.SkillXP.AwardXP then
        local awarded = EHR.SkillXP.AwardXP(player, amount, "radio_medical_tip", nil)
        if awarded then
            addHalo(player, "First Aid +" .. tostring(math.floor(amount)) .. " XP")
        end
    end
end

local function handleKnowledge(player, token)
    local diseaseId = token:sub(5)
    if not diseaseId or diseaseId == "" then return end

    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.NormalizeDiseaseId then
        diseaseId = EHR.DiseaseFlyers.NormalizeDiseaseId(diseaseId)
    end

    local effectKey = getCurrentBroadcastKey("KNOW:" .. tostring(diseaseId))
    if alreadyHandled(player, effectKey) then
        return
    end

    local newlyLearned = false
    if EHR.DiseaseFlyers and EHR.DiseaseFlyers.UnlockDiseaseKnowledge then
        newlyLearned = EHR.DiseaseFlyers.UnlockDiseaseKnowledge(player, diseaseId) == true
    end

    if newlyLearned and isClient and isClient() and sendClientCommand then
        sendClientCommand(player, "EHR_Flyers", "UnlockDisease", { diseaseId = diseaseId })
    end

    if newlyLearned then
        log("Radio knowledge unlocked: " .. tostring(diseaseId))
    end
end

local function handlePlayer(player, codes, x, y, z)
    if not player or player:isDead() or player:isAsleep() then return end
    if not playerInRange(player, x, y, z) then return end

    local tokens = splitCodes(codes)
    for i = 1, #tokens do
        local token = tokens[i]
        if token:sub(1, 3) == "EHX" then
            handleXP(player, token)
        elseif token:sub(1, 4) == "EHK=" then
            handleKnowledge(player, token)
        end
    end
end

local function onDeviceText(_guid, interactCodes, x, y, z, _line)
    if not interactCodes or interactCodes == "" then
        return
    end

    local codes = tostring(interactCodes)
    if not codes:find("EHX", 1, true) and not codes:find("EHK=", 1, true) then
        return
    end

    x = tonumber(x) or -1
    y = tonumber(y) or -1
    z = tonumber(z) or -1

    if isServer and isServer() then
        local players = getOnlinePlayers and getOnlinePlayers() or nil
        if not players then return end
        for i = 0, players:size() - 1 do
            handlePlayer(players:get(i), codes, x, y, z)
        end
        return
    end

    for playerNum = 0, 3 do
        local player = getSpecificPlayer and getSpecificPlayer(playerNum) or nil
        handlePlayer(player, codes, x, y, z)
    end
end

function EHR.RadioInteractions.Initialize()
    if EHR.RadioInteractions.initialized then
        return
    end

    if Events and Events.OnDeviceText then
        Events.OnDeviceText.Add(onDeviceText)
        EHR.RadioInteractions.initialized = true
        log("Custom radio interactions initialized")
    end
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(EHR.RadioInteractions.Initialize)
elseif Events and Events.OnGameStart then
    Events.OnGameStart.Add(EHR.RadioInteractions.Initialize)
end

EHR.RadioInteractions.Initialize()
