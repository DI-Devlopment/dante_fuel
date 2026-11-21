-- Dante Fuel physical nozzle state. The server owns the nozzle object and validates every transition.
local config = require 'config'
local nozzles, serial = {}, 0
local NOZZLE = joaat('prop_cs_fuel_nozle')
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
    for i = 1, #config.pumpModels do
        if config.pumpModels[i] == model then return true end
    end
    return false
end

local function coordsOf(c)
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
end

local function send(n)
    TriggerClientEvent('dante_fuel:nozzleState', -1, {
        key = n.key, pump = n.pump, model = n.model, side = n.side, state = n.state,
        holder = n.holder, vehicle = n.vehicle, nozzleNet = n.nozzleNet,
        torn = n.torn, pumpNet = n.pumpNet, snapped = n.snapped,
    })
end

local function cleanupPumpCopy(n)
    if n.pumpNet then
        local e = NetworkGetEntityFromNetworkId(n.pumpNet)
        if e and e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
    end
    n.pumpNet, n.torn = nil, false
end

local function deleteNozzle(n)
    local e = n.nozzleNet and NetworkGetEntityFromNetworkId(n.nozzleNet)
    if e and e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
    n.nozzleNet = nil
end

local function reset(n, reason)
    cleanupPumpCopy(n)
    deleteNozzle(n)
    n.state, n.holder, n.vehicle, n.snapped = 'holstered', nil, nil, false
    n.changedAt = GetGameTimer()
    send(n)
    TriggerEvent('dante_fuel:nozzleReturned', n.key, reason)
end

local function makeGround(n, at)
    local obj = n.nozzleNet and NetworkGetEntityFromNetworkId(n.nozzleNet)
    if not obj or obj == 0 or not DoesEntityExist(obj) then
        obj = CreateObjectNoOffset(NOZZLE, at.x, at.y, at.z, true, true, false)
        if not obj or obj == 0 then return reset(n, 'object_failed') end
        n.nozzleNet = NetworkGetNetworkIdFromEntity(obj)
    end
    DetachEntity(obj, true, true)
    SetEntityCoords(obj, at.x, at.y, at.z, false, false, false, false)
    SetEntityCollision(obj, true, true)
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)
    n.state, n.holder, n.vehicle = 'ground', nil, nil
    n.changedAt = GetGameTimer()
    send(n)
end

RegisterNetEvent('dante_fuel:takeNozzle', function(pumpCoords, model, side)
    local src = source
    if type(pumpCoords) ~= 'table' or type(model) ~= 'number' or (side ~= 'A' and side ~= 'B') then return end
    if not validPump(model) then return end
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local pump = coordsOf(pumpCoords)
    if #(GetEntityCoords(ped) - pump) > 3.5 then return end
    local key = keyFor(pumpCoords, side)
    local n = nozzles[key]
    for _, active in pairs(nozzles) do
        if active.state == 'hand' and active.holder == src and active.key ~= key then return end
    end
    if n and n.state ~= 'holstered' and n.state ~= 'ground' then return end
    if n and n.state == 'ground' and #(GetEntityCoords(ped) - pump) > 3.0 then return end

    if not n then
        n = { key = key, pump = { x = pump.x, y = pump.y, z = pump.z }, model = model, side = side, heading = tonumber(pumpCoords.heading) or 0.0 }
        nozzles[key] = n
    end
    if not n.nozzleNet or not NetworkGetEntityFromNetworkId(n.nozzleNet) or NetworkGetEntityFromNetworkId(n.nozzleNet) == 0 then
        local obj = CreateObjectNoOffset(NOZZLE, pump.x, pump.y, pump.z + 0.7, true, true, false)
        if not obj or obj == 0 then return end
        n.nozzleNet = NetworkGetNetworkIdFromEntity(obj)
    end
    local obj = NetworkGetEntityFromNetworkId(n.nozzleNet)
    if not obj or obj == 0 then return end
    DetachEntity(obj, true, true)
    SetEntityCollision(obj, false, false)
    local bone = GetPedBoneIndex(ped, 28422)
    AttachEntityToEntity(obj, ped, bone, 0.13, 0.05, 0.02, -80.0, 0.0, 15.0, false, false, false, false, 2, true)
    n.state, n.holder, n.vehicle, n.changedAt = 'hand', src, nil, GetGameTimer()
    send(n)
end)

RegisterNetEvent('dante_fuel:dropNozzle', function()
    local src, found = source
    for _, n in pairs(nozzles) do
        if n.state == 'hand' and n.holder == src then found = n break end
    end
    if not found then return end
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local c = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, -0.8)
    makeGround(found, c)
end)

RegisterNetEvent('dante_fuel:insertNozzle', function(netId)
    local src = source
    local n
    for _, v in pairs(nozzles) do if v.state == 'hand' and v.holder == src then n = v break end end
    if not n or type(netId) ~= 'number' then return end
    local ped = GetPlayerPed(src)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or not vehicle or vehicle == 0 or GetEntityType(vehicle) ~= 2 then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 3.5 or #(GetEntityCoords(vehicle) - coordsOf(n.pump)) > 8.0 then return end
    local obj = n.nozzleNet and NetworkGetEntityFromNetworkId(n.nozzleNet)
    if not obj or obj == 0 then return end
    local bone = GetEntityBoneIndexByName(vehicle, 'petrolcap')
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, 'petroltank_l') end
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, 'petroltank') end
    if bone == -1 then return end
    local p = GetWorldPositionOfEntityBone(vehicle, bone)
    local off = GetOffsetFromEntityGivenWorldCoords(vehicle, p.x, p.y, p.z)
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, vehicle, bone, off.x, off.y, off.z, -25.0, 0.0, 180.0, false, false, false, false, 2, true)
    n.state, n.holder, n.vehicle, n.changedAt = 'car', nil, netId, GetGameTimer()
    send(n)
end)

RegisterNetEvent('dante_fuel:removeNozzle', function()
    local src = source
    for _, n in pairs(nozzles) do
        if n.state == 'car' and n.holder == nil then
            local vehicle = n.vehicle and NetworkGetEntityFromNetworkId(n.vehicle)
            local ped = GetPlayerPed(src)
            if ped ~= 0 and vehicle and vehicle ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) <= 3.0 then
                local obj = n.nozzleNet and NetworkGetEntityFromNetworkId(n.nozzleNet)
                if obj and obj ~= 0 then
                    DetachEntity(obj, true, true)
                    local bone = GetPedBoneIndex(ped, 28422)
                    AttachEntityToEntity(obj, ped, bone, 0.13, 0.05, 0.02, -80.0, 0.0, 15.0, false, false, false, false, 2, true)
                end
                n.state, n.holder, n.vehicle = 'hand', src, nil
                cleanupPumpCopy(n)
                send(n)
                return
            end
        end
    end
end)

RegisterNetEvent('dante_fuel:returnNozzle', function(key)
    local src = source
    local n = nozzles[key]
    if not n or #(GetEntityCoords(GetPlayerPed(src)) - coordsOf(n.pump)) > 3.5 then return end
    if n.state == 'hand' and n.holder ~= src then return end
    if n.state == 'car' then
        local vehicle = n.vehicle and NetworkGetEntityFromNetworkId(n.vehicle)
        if vehicle and vehicle ~= 0 and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(vehicle)) > 3.0 then return end
    end
    reset(n, 'returned')
end)

RegisterNetEvent('dante_fuel:clientReady', function()
    local src = source
    for _, n in pairs(nozzles) do
        if n.state ~= 'holstered' then
            TriggerClientEvent('dante_fuel:nozzleState', src, {
                key=n.key, pump=n.pump, model=n.model, side=n.side, state=n.state,
                holder=n.holder, vehicle=n.vehicle, nozzleNet=n.nozzleNet,
                torn=n.torn, pumpNet=n.pumpNet, snapped=n.snapped,
            })
        end
    end
end)

CreateThread(function()
    while true do
        local now = GetGameTimer()
        for _, n in pairs(nozzles) do
            if n.state == 'hand' then
                local ped = GetPlayerPed(n.holder)
                if ped == 0 then
                    reset(n, 'holder_left')
                elseif #(GetEntityCoords(ped) - coordsOf(n.pump)) > 5.0 then
                    makeGround(n, GetEntityCoords(ped))
                end
            elseif n.state == 'ground' and now - n.changedAt >= 30000 then
                reset(n, 'timeout')
            elseif n.state == 'car' and n.vehicle then
                local vehicle = NetworkGetEntityFromNetworkId(n.vehicle)
                if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
                    reset(n, 'vehicle_gone')
                elseif #(GetEntityCoords(vehicle) - coordsOf(n.pump)) > 5.0 and not n.snapped then
                    if MODERN[n.model] then
                        local copy = CreateObjectNoOffset(n.model, n.pump.x, n.pump.y, n.pump.z, true, true, false)
                        if copy and copy ~= 0 then
                            SetEntityHeading(copy, n.heading or 0.0)
                            SetEntityDynamic(copy, true)
                            FreezeEntityPosition(copy, false)
                            n.pumpNet = NetworkGetNetworkIdFromEntity(copy)
                            n.torn = true
                            n.changedAt = now
                            send(n)
                        else
                            n.snapped = true
                            send(n)
                        end
                    else
                        n.snapped = true
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
    for _, n in pairs(nozzles) do
        if n.holder == src then reset(n, 'holder_left') end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, n in pairs(nozzles) do cleanupPumpCopy(n); deleteNozzle(n) end
end)


-- The live-fueling server accepts pump sessions only when this vehicle has an inserted physical nozzle.
exports('hasNozzleForVehicle', function(playerId, netId, pumpCoords)
    if type(netId) ~= 'number' or type(pumpCoords) ~= 'table'
        or type(pumpCoords.x) ~= 'number' or type(pumpCoords.y) ~= 'number' or type(pumpCoords.z) ~= 'number' then return false end
    for _, n in pairs(nozzles) do
        if n.state == 'car' and n.vehicle == netId then
            local p = coordsOf(n.pump)
            local requested = coordsOf(pumpCoords)
            return #(p - requested) <= 1.5
        end
    end
    return false
end)
