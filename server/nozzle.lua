-- Server-authoritative nozzle state. Physical entity operations are client-side only.
local config = require 'config'
local nozzles = {}
local MODERN = {
    [joaat('prop_gas_pump_1a')] = true,
    [joaat('prop_gas_pump_1b')] = true,
    [joaat('prop_gas_pump_1c')] = true,
    [joaat('prop_gas_pump_1d')] = true,
}

local function keyFor(c, side)
    return ('%d:%d:%d:%s'):format(math.floor(c.x * 10 + 0.5), math.floor(c.y * 10 + 0.5), math.floor(c.z * 10 + 0.5), side)
end
local function validPump(model)
    for i = 1, #config.pumpModels do if config.pumpModels[i] == model then return true end end
    return false
end
local function coordsOf(c) return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0) end
local function entityFrom(net)
    if type(net) ~= 'number' or net <= 0 then return 0 end
    -- NetworkDoesNetworkIdExist is not exposed in the server runtime.
    -- NetworkGetEntityFromNetworkId returns 0 when the ID is not currently known.
    local entity = NetworkGetEntityFromNetworkId(net)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end
    return entity
end
local function pumpGroup(key) return key and key:sub(1, -3) end
local function send(n, target)
    TriggerClientEvent('dante_fuel:nozzleState', target or -1, {
        key=n.key, pump=n.pump, model=n.model, side=n.side, state=n.state,
        holder=n.holder, vehicle=n.vehicle, offset=n.offset, nozzleNet=n.nozzleNet, ground=n.ground,
        torn=n.torn, tornOwner=n.tornOwner, tornModel=n.tornModel, spillOwner=n.spillOwner,
        tornElapsed=n.tornAt and math.max(0, GetGameTimer() - n.tornAt) or 0,
        pumpNet=n.pumpNet, snapped=n.snapped,
    })
end
local function cleanupPumpCopy(n)
    local sharedNet = n.pumpNet
    n.pumpNet, n.torn, n.tornOwner, n.tornModel, n.tornAt, n.spillOwner = nil, false, nil, nil, nil, nil
    if not sharedNet then return end

    -- Both sides of one physical pump share its torn replacement. Keep it alive
    -- while the opposite nozzle is still out, on the ground, or in a vehicle.
    for _, sibling in pairs(nozzles) do
        if sibling ~= n and pumpGroup(sibling.key) == pumpGroup(n.key)
            and sibling.state ~= 'holstered' and sibling.torn and sibling.pumpNet == sharedNet then
            return
        end
    end

    local entity = entityFrom(sharedNet)
    if entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end
local function shareTornPump(n, owner)
    local group = pumpGroup(n.key)
    for _, sibling in pairs(nozzles) do
        if sibling ~= n and pumpGroup(sibling.key) == group and sibling.state ~= 'holstered' then
            sibling.torn, sibling.tornOwner = true, owner
            sibling.tornModel, sibling.tornAt = n.tornModel, n.tornAt
            sibling.pumpNet, sibling.spillOwner = n.pumpNet, false
            sibling.changedAt = n.changedAt
            send(sibling)
        end
    end
end
local function reset(n, reason)
    cleanupPumpCopy(n)
    n.state, n.holder, n.vehicle, n.snapped = 'holstered', nil, nil, false
    n.changedAt = GetGameTimer()
    send(n)
    n.nozzleNet = nil
    n.ground = nil
    n.offset = nil
    TriggerEvent('dante_fuel:nozzleReturned', n.key, reason)
end
local function deny(src, netId)
    TriggerClientEvent('dante_fuel:nozzleDenied', src, netId)
end

-- Client creates and attaches the networked prop, then submits its network ID.
RegisterNetEvent('dante_fuel:takeNozzle', function(pumpCoords, model, side, netId)
    local src = source
    if type(pumpCoords) ~= 'table' or type(pumpCoords.x) ~= 'number' or type(pumpCoords.y) ~= 'number'
        or type(pumpCoords.z) ~= 'number' or type(model) ~= 'number' or (side ~= 'A' and side ~= 'B')
        or type(netId) ~= 'number' then return deny(src, netId) end
    if not validPump(model) then return deny(src, netId) end
    local ped = GetPlayerPed(src)
    local obj = entityFrom(netId)
    if ped == 0 or obj == 0 or GetEntityModel(obj) ~= joaat('prop_cs_fuel_nozle') then
        return deny(src, netId)
    end
    local pump = coordsOf(pumpCoords)
    if #(GetEntityCoords(ped) - pump) > 3.5 or #(GetEntityCoords(obj) - GetEntityCoords(ped)) > 3.0 then
        return deny(src, netId)
    end
    local key = keyFor(pumpCoords, side)
    local n = nozzles[key]
    for _, active in pairs(nozzles) do
        if active.state == 'hand' and active.holder == src and active.key ~= key then return deny(src, netId) end
    end
    if n and n.state ~= 'holstered' and n.state ~= 'ground' then return deny(src, netId) end
    if n and n.state == 'ground' and n.nozzleNet ~= netId then return deny(src, netId) end
    if not n then
        n = { key=key, pump={x=pump.x,y=pump.y,z=pump.z}, model=model, side=side,
            heading=tonumber(pumpCoords.heading) or 0.0 }
        nozzles[key] = n
    end
    n.nozzleNet, n.state, n.holder, n.vehicle, n.ground, n.offset = netId, 'hand', src, nil, nil, nil
    n.changedAt = GetGameTimer()
    send(n)
end)

RegisterNetEvent('dante_fuel:dropNozzle', function(at)
    local src, found = source
    for _, n in pairs(nozzles) do if n.state == 'hand' and n.holder == src then found = n break end end
    if not found then return end
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local p = GetEntityCoords(ped)
    local drop = type(at) == 'table' and type(at.x) == 'number' and type(at.y) == 'number'
        and type(at.z) == 'number' and coordsOf(at) or p
    if #(drop - p) > 3.0 then drop = p end
    found.state, found.holder, found.vehicle = 'ground', nil, nil
    found.ground = {x=drop.x,y=drop.y,z=drop.z}
    found.changedAt = GetGameTimer()
    send(found)
end)

RegisterNetEvent('dante_fuel:pickupDroppedNozzle', function(key)
    local src = source
    local n = nozzles[key]
    if not n or n.state ~= 'ground' or not n.ground then return end
    local ped = GetPlayerPed(src)
    local obj = entityFrom(n.nozzleNet)
    if ped == 0 or obj == 0 then return end
    local playerPos = GetEntityCoords(ped)
    if #(playerPos - coordsOf(n.ground)) > 2.5
        or #(GetEntityCoords(obj) - playerPos) > 3.0 then return end

    for _, active in pairs(nozzles) do
        if active.state == 'hand' and active.holder == src then return end
    end

    n.state, n.holder, n.vehicle, n.ground, n.offset = 'hand', src, nil, nil, nil
    n.changedAt = GetGameTimer()
    send(n)
end)

RegisterNetEvent('dante_fuel:insertNozzle', function(netId, offset)
    local src = source
    local n
    for _, v in pairs(nozzles) do if v.state == 'hand' and v.holder == src then n = v break end end
    if not n or type(netId) ~= 'number' or type(offset) ~= 'table'
        or type(offset.x) ~= 'number' or type(offset.y) ~= 'number' or type(offset.z) ~= 'number'
        or math.abs(offset.x) > 5.0 or math.abs(offset.y) > 5.0 or math.abs(offset.z) > 5.0
        or (offset.pitch ~= nil and type(offset.pitch) ~= 'number')
        or (offset.yaw ~= nil and type(offset.yaw) ~= 'number') then return end
    local ped = GetPlayerPed(src)
    local vehicle = entityFrom(netId)
    local obj = entityFrom(n.nozzleNet)
    if ped == 0 or vehicle == 0 or obj == 0 or GetEntityType(vehicle) ~= 2 then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 3.5
        or #(GetEntityCoords(vehicle) - coordsOf(n.pump)) > 8.0 then return end
    n.state, n.holder, n.vehicle, n.offset, n.ground = 'car', nil, netId, offset, nil
    n.changedAt = GetGameTimer()
    send(n)
end)

RegisterNetEvent('dante_fuel:removeNozzle', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end
    for _, n in pairs(nozzles) do
        if n.state == 'car' and n.vehicle == netId then
            local vehicle, ped = entityFrom(netId), GetPlayerPed(src)
            if ped ~= 0 and vehicle ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= 3.0 then
                n.state, n.holder, n.vehicle, n.offset = 'hand', src, nil, nil
                n.changedAt = GetGameTimer()
                cleanupPumpCopy(n)
                send(n)
                return
            end
        end
    end
end)

RegisterNetEvent('dante_fuel:returnNozzle', function(key)
    local src = source
    local n, ped = nozzles[key], GetPlayerPed(src)
    if ped == 0 or not n or #(GetEntityCoords(ped) - coordsOf(n.pump)) > 3.5 then return end
    if n.state == 'hand' and n.holder ~= src then return end
    if n.state == 'car' then
        local vehicle = entityFrom(n.vehicle)
        if vehicle ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 3.0 then return end
    end
    reset(n, 'returned')
end)

RegisterNetEvent('dante_fuel:tornPumpCreated', function(key, netId)
    local src = source
    local n = nozzles[key]
    if not n or not n.torn or n.tornOwner ~= src or type(netId) ~= 'number' then return end
    local copy = entityFrom(netId)
    local expectedModel = n.tornModel or config.tornPumpModels[n.model] or n.model
    if copy == 0 or GetEntityModel(copy) ~= expectedModel
        or #(GetEntityCoords(copy) - coordsOf(n.pump)) > 3.0 then return end
    n.pumpNet = netId
    n.spillOwner = true
    send(n)
    shareTornPump(n, src)
end)

RegisterNetEvent('dante_fuel:clientReady', function()
    local src = source
    for _, n in pairs(nozzles) do if n.state ~= 'holstered' then send(n, src) end end
end)

CreateThread(function()
    while true do
        local now = GetGameTimer()
        for _, n in pairs(nozzles) do
            if n.state == 'hand' then
                local ped = GetPlayerPed(n.holder)
                if ped == 0 then reset(n, 'holder_left')
                elseif #(GetEntityCoords(ped) - coordsOf(n.pump)) > 5.0 then
                    local p = GetEntityCoords(ped)
                    n.state, n.holder, n.vehicle = 'ground', nil, nil
                    n.ground = {x=p.x,y=p.y,z=p.z}
                    n.changedAt = now
                    send(n)
                    TriggerClientEvent('dante_fuel:forceDropNozzle', -1, n.key, n.ground)
                end
            elseif n.state == 'ground' and now - n.changedAt >= 30000 then
                reset(n, 'timeout')
            elseif n.state == 'car' and n.torn and not n.pumpNet and now - (n.changedAt or now) > 5000 then
                n.torn, n.tornOwner, n.tornModel, n.tornAt, n.spillOwner, n.snapped = false, nil, nil, nil, nil, true
                send(n)
            elseif n.state == 'car' and n.vehicle then
                local vehicle = entityFrom(n.vehicle)
                if vehicle == 0 then
                    reset(n, 'vehicle_gone')
                elseif #(GetEntityCoords(vehicle) - coordsOf(n.pump)) > 5.0 and not n.snapped and not n.torn then
                    -- Older pumps snap the hose. Modern pumps get a replicated loose pump copy.
                    if MODERN[n.model] then
                        local owner = NetworkGetEntityOwner(vehicle)
                        if owner and owner > 0 then
                            n.torn, n.tornOwner = true, owner
                            n.spillOwner = true
                            n.tornModel = config.tornPumpModels[n.model] or n.model
                            n.tornAt = now
                            shareTornPump(n, owner)
                            n.changedAt = now
                            send(n)
                            TriggerClientEvent('dante_fuel:createTornPump', owner, n.key, n.pump, n.tornModel, n.heading or 0.0)
                        else
                            n.snapped = true
                            n.changedAt = now
                            send(n)
                        end
                    else
                        n.snapped = true
                        n.changedAt = now
                        send(n)
                    end
                end
            end
        end
        Wait(500)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, n in pairs(nozzles) do if n.holder == src then reset(n, 'holder_left') end end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, n in pairs(nozzles) do
        cleanupPumpCopy(n)
        local obj = entityFrom(n.nozzleNet)
        if obj ~= 0 then DeleteEntity(obj) end
    end
end)

exports('hasNozzleForVehicle', function(playerId, netId, pumpCoords)
    if type(netId) ~= 'number' or type(pumpCoords) ~= 'table'
        or type(pumpCoords.x) ~= 'number' or type(pumpCoords.y) ~= 'number' or type(pumpCoords.z) ~= 'number' then return false end
    for _, n in pairs(nozzles) do
        if n.state == 'car' and n.vehicle == netId and not n.torn and not n.snapped then
            return #(coordsOf(n.pump) - coordsOf(pumpCoords)) <= 1.5
        end
    end
    return false
end)
