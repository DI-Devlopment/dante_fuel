-- Server-authoritative live pump fueling.
-- No money is reserved at session start. Only accepted fuel ticks are charged once at close.
local config = require 'config'
local sessions = {}
local serial = 0

local function getEntity(netId)
    if type(netId) ~= 'number' or netId <= 0 then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity == 0 or not DoesEntityExist(entity) then return 0 end
    return entity
end

local function validSessionPlayer(source, session)
    local ped = GetPlayerPed(source)
    local vehicle = getEntity(session.netId)
    if ped == 0 or vehicle == 0 or GetEntityType(vehicle) ~= 2 then return false end

    if not exports[GetCurrentResourceName()]:hasNozzleForVehicle(
        source, session.netId,
        { x = session.pump.x, y = session.pump.y, z = session.pump.z }
    ) then return false end

    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(vehicle)
    return #(playerCoords - vehicleCoords) <= 5.0
        and #(playerCoords - session.pump) <= 8.0
        and #(vehicleCoords - session.pump) <= 12.0
end

local function closeSession(source, session)
    if not session or sessions[source] ~= session then return false, 'invalid_session' end
    sessions[source] = nil

    local ticks = session.consumed
    local charge = ticks * config.priceTick
    if ticks == 0 then return true, nil, session.startFuel end

    -- Uses the ox_fuel payment hook, so custom bank/framework payment methods still work.
    if not exports[GetCurrentResourceName()]:chargeFuel(source, charge) then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = locale('refuel_cannot_afford')
        })
        return false, 'payment_failed'
    end

    local vehicle = getEntity(session.netId)
    local finalFuel = math.min(100.0, session.startFuel + ticks * config.refillValue)
    if vehicle ~= 0 and GetEntityType(vehicle) == 2 then
        Entity(vehicle).state:set('fuel', finalFuel, true)
    end

    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success',
        description = locale('fuel_success', math.floor(finalFuel), charge)
    })

    return true, nil, finalFuel
end

lib.callback.register('dante_fuel:beginLiveFuel', function(source, netId, pumpCoords, maxTicks)
    if sessions[source] then return false, 'session_active' end
    if type(netId) ~= 'number' or type(maxTicks) ~= 'number' or maxTicks < 1
        or type(pumpCoords) ~= 'table'
        or type(pumpCoords.x) ~= 'number' or type(pumpCoords.y) ~= 'number'
        or type(pumpCoords.z) ~= 'number' then
        return false, 'invalid_request'
    end

    maxTicks = math.floor(math.min(maxTicks, 500))
    local ped = GetPlayerPed(source)
    local vehicle = getEntity(netId)
    if ped == 0 or vehicle == 0 or GetEntityType(vehicle) ~= 2 then return false, 'vehicle_missing' end

    local pump = vector3(pumpCoords.x, pumpCoords.y, pumpCoords.z)
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 5.0
        or #(GetEntityCoords(ped) - pump) > 8.0
        or #(GetEntityCoords(vehicle) - pump) > 12.0 then
        return false, 'pump_too_far'
    end

    if not exports[GetCurrentResourceName()]:hasNozzleForVehicle(source, netId, pumpCoords) then
        return false, 'nozzle_required'
    end

    local startFuel = tonumber(Entity(vehicle).state.fuel) or GetVehicleFuelLevel(vehicle)
    serial = serial + 1
    local session = {
        id = ('%s:%s:%s'):format(source, GetGameTimer(), serial),
        netId = netId,
        pump = pump,
        startFuel = math.max(0.0, math.min(100.0, startFuel)),
        allowedTicks = maxTicks,
        consumed = 0,
        lastTick = GetGameTimer() - config.refillTick,
    }
    sessions[source] = session

    return { id = session.id, allowedTicks = maxTicks }
end)

lib.callback.register('dante_fuel:acceptLiveFuelTick', function(source, sessionId)
    local session = sessions[source]
    if not session or session.id ~= sessionId or session.consumed >= session.allowedTicks then return false end

    local now = GetGameTimer()
    if now - session.lastTick < math.floor(config.refillTick * 0.9) then return false end
    if not validSessionPlayer(source, session) then return false end

    session.consumed = session.consumed + 1
    session.lastTick = now
    return true, session.consumed
end)

lib.callback.register('dante_fuel:finishLiveFuel', function(source, sessionId)
    local session = sessions[source]
    if not session or session.id ~= sessionId then return false, 'invalid_session' end
    return closeSession(source, session)
end)

CreateThread(function()
    while true do
        local now = GetGameTimer()
        for playerId, session in pairs(sessions) do
            if now - session.lastTick > 30000 then
                closeSession(playerId, session)
                TriggerClientEvent('ox_lib:notify', playerId, {
                    type = 'inform',
                    description = 'Fueling stopped after inactivity. Accepted fuel was settled.'
                })
            end
        end
        Wait(5000)
    end
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    table.wipe(sessions)
end)
