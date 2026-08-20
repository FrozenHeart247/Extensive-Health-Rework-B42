pcall(function() require "ExtensiveHealth/EHR_Medication" end)

if not EHR then EHR = {} end
EHR.LastChanceEpinephrineClient = EHR.LastChanceEpinephrineClient or {
    seenTokens = {},
    tokenOrder = {},
}

local Client = EHR.LastChanceEpinephrineClient
Client.pendingSpeedBoost = Client.pendingSpeedBoost or setmetatable({}, { __mode = "k" })
local speedVector = Vector2 and Vector2.new and Vector2.new(0, 0) or nil

function Client.ClaimToken(token)
    token = tostring(token or "")
    if token == "" or Client.seenTokens[token] then return false end

    -- Mark before applying: a duplicate network delivery cannot heal twice even
    -- if a local API call fails partway through the first attempt.
    Client.seenTokens[token] = true
    Client.tokenOrder[#Client.tokenOrder + 1] = token
    while #Client.tokenOrder > 64 do
        local expired = table.remove(Client.tokenOrder, 1)
        Client.seenTokens[expired] = nil
    end
    return true
end

function Client.GetLocalPlayer()
    local player = nil
    if getSpecificPlayer then player = getSpecificPlayer(0) end
    if not player and getPlayer then player = getPlayer() end
    return player
end

function Client.ApplyRescueVitals(args)
    if type(args) ~= "table" or not Client.ClaimToken(args.token) then return false end

    local player = Client.GetLocalPlayer()
    if not player or not EHR.Medication or not EHR.Medication.ApplyLastChanceRescueVitals then
        return false
    end

    local applied = EHR.Medication.ApplyLastChanceRescueVitals(
        player,
        tonumber(args.targetHealth) or 75,
        args.highRiskSurvivor == true,
        args.bodyPartHealth
    )
    if applied ~= true then return false end

    -- The authoritative medication snapshot follows this command. Keep a short
    -- grace window so network ordering cannot suppress the movement bonus before
    -- that snapshot arrives.
    Client.pendingSpeedBoost[player] = {
        ticks = 300,
        endTime = tonumber(args.boostEndTime),
        speedMod = tonumber(args.speedMod) or 1.20,
    }
    return true
end


function Client.ApplyMovementBoost(player, speedMod)
    if not speedVector or not player or not player.moveUnmodded or not player.getDeferredMovement then
        return false
    end

    local ok, moved = pcall(function()
        -- A few of these state helpers changed between B42 point releases.
        -- Keep the whole guard inside pcall so a missing helper simply disables
        -- the boost for that frame instead of flooding the Lua log.
        if player:getVehicle() or player:isDead() or player:isAsleep() or player:isOnFloor() then return false end
        if player:isClimbing() or player:isBumped() or player:isGrappling() or player:isBeingGrappled() then return false end
        local pathBehavior = player:getPathFindBehavior2()
        if pathBehavior and pathBehavior:isMovingUsingPathFind() then return false end
        if not (player:isWalking() or player:isRunning() or player:isSprinting()) then return false end
        if not player:isPlayerMoving() then return false end

        local extra = math.max(0, math.min(0.25, (tonumber(speedMod) or 1.20) - 1.0))
        if extra <= 0 then return false end

        player:getDeferredMovement(speedVector)
        local dx = tonumber(speedVector:getX()) or 0
        local dy = tonumber(speedVector:getY()) or 0
        if math.abs(dx) > 0.000001 or math.abs(dy) > 0.000001 then
            -- Vanilla already added the full animation delta earlier in this
            -- update. The extra delta is added before IsoMovingObject.postupdate,
            -- so normal collision resolution still owns the final position.
            player:moveUnmodded(dx * extra, dy * extra)
            return true
        end
        return false
    end)
    return ok and moved == true
end


function Client.UpdateSpeedBoost(player)
    if not player or (player.isLocalPlayer and not player:isLocalPlayer()) then return end

    local gameTime = getGameTime and getGameTime() or nil
    local currentHour = gameTime and tonumber(gameTime:getWorldAgeHours()) or 0
    local modData = player:getModData()
    local medication = modData and modData.EHR_Medication or nil
    local general = medication and medication.activeGeneralEffects or nil
    local effect = general and general.lastChanceEpinephrine or nil
    local endTime = type(effect) == "table" and tonumber(effect.endTime) or nil
    local active = endTime ~= nil and currentHour < endTime
    local speedMod = type(effect) == "table" and tonumber(effect.speedMod) or nil

    local pending = Client.pendingSpeedBoost[player]
    if active then
        Client.pendingSpeedBoost[player] = nil
    elseif type(pending) == "table" then
        pending.ticks = (tonumber(pending.ticks) or 0) - 1
        local pendingEnd = tonumber(pending.endTime)
        active = pending.ticks > 0 and (pendingEnd == nil or currentHour < pendingEnd)
        speedMod = tonumber(pending.speedMod) or speedMod
        if not active then Client.pendingSpeedBoost[player] = nil end
    end

    if active then
        Client.ApplyMovementBoost(player, speedMod or 1.20)
    end
end

function Client.ApplyCrashFatigue(args)
    if type(args) ~= "table" or not Client.ClaimToken(args.token) then return false end
    local player = Client.GetLocalPlayer()
    if not player or not player.getStats or not CharacterStat or not CharacterStat.FATIGUE then return false end

    local floor = math.max(0, math.min(1, tonumber(args.fatigueFloor) or 0.50))
    local ok = pcall(function()
        local stats = player:getStats()
        local current = stats and tonumber(stats:get(CharacterStat.FATIGUE)) or 0
        if stats and current < floor then stats:set(CharacterStat.FATIGUE, floor) end
    end)
    return ok
end

function Client.ApplyFatal(args)
    if type(args) ~= "table" or not Client.ClaimToken(args.token) then return false end
    local player = Client.GetLocalPlayer()
    if not player then return false end

    pcall(function()
        local bodyDamage = player:getBodyDamage()
        if bodyDamage and bodyDamage.setOverallBodyHealth then
            bodyDamage:setOverallBodyHealth(0)
        end
    end)
    if player.setHealth then pcall(function() player:setHealth(0) end) end
    return true
end

function Client.OnServerCommand(module, command, args)
    if module ~= "EHR_LastChanceEpinephrine" then return end
    if command == "ApplyRescueVitals" then
        Client.ApplyRescueVitals(args)
    elseif command == "ApplyCrashFatigue" then
        Client.ApplyCrashFatigue(args)
    elseif command == "ApplyFatal" then
        Client.ApplyFatal(args)
    end
end

if Events and Events.OnServerCommand and not Client.registered then
    Client.registered = true
    Events.OnServerCommand.Add(Client.OnServerCommand)
end


if Events and Events.OnPlayerUpdate and not Client.speedUpdateRegistered then
    Client.speedUpdateRegistered = true
    Events.OnPlayerUpdate.Add(Client.UpdateSpeedBoost)
end
