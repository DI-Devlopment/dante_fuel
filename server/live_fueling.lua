-- Live pump payment reservations for Dante Fuel.
-- Funds are reserved at connection, consumed per accepted fuel tick, and unused funds are refunded on disconnect/stop.
local config = require 'config'
local inventory = exports.ox_inventory
local sessions = {}
local serial = 0

local function refund(source, session)
    if session and session.reserved > 0 then
        inventory:AddItem(source, 'money', session.reserved)
        session.reserved = 0
    end
end

local function closeSession(source, session, fuel)
    if not session or sessions[source] ~= session then return false end
    sessions[source] = nil

    local vehicle = NetworkGetEntityFromNetworkId(session.netId)
    if vehicle ~= 0 and GetEntityType(vehicle) == 2 then
        local state = Entity(vehicle).state
        local maxFuel = math.min(100.0, session.startFuel + session.consumed * config.refillValue)
        if type(fuel) == 'number' then
            state:set('fuel', math.min(maxFuel, math.max(session.startFuel, fuel)), true)
        end
    end

    local charged = session.consumed * config.priceTick
    local unused = math.max(0, session.reserved - charged)
    if unused > 0 then inventory:AddItem(source, 'money', unused) end
    session.reserved = 0

    if charged > 0 then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'success',
            description = locale('fuel_success', math.floor(session.startFuel + session.consumed * config.refillValue), charged)
        })
    end

    return true
end

lib.callback.register('dante_fuel:beginLiveFuel', function(source, netId, pumpCoords, maxTicks)
    if sessions[source] then return false, 'session_active' end
    if type(netId) ~= 'number' or type(maxTicks) ~= 'number' or maxTicks < 1 then return false, 'invalid_request' end
    maxTicks = math.floor(math.min(maxTicks, 500))

    local ped = GetPlayerPed(source)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if ped == 0 or vehicle == 0 or GetEntityType(vehicle) ~= 2 then return false, 'vehicle_missing' end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 5.0 then return false, 'vehicle_too_far' end

    if type(pumpCoords) ~= 'table' or type(pumpCoords.x) ~= 'number'
        or type(pumpCoords.y) ~= 'number' or type(pumpCoords.z) ~= 'number' then
        return false, 'invalid_pump'
    end

    local pump = vector3(pumpCoords.x, pumpCoords.y, pumpCoords.z)
    if #(GetEntityCoords(ped) - pump) > 7.0 or #(GetEntityCoords(vehicle) - pump) > 12.0 then
        return false, 'pump_too_far'
    end

    local startFuel = tonumber(Entity(vehicle).state.fuel) or 0.0
    local needed = maxTicks * config.priceTick
    local available = inventory:GetItemCount(source, 'money')
    local reserved = math.min(needed, available)
    local allowedTicks = math.floor(reserved / config.priceTick)

    if allowedTicks < 1 then return false, 'not_enough_money' end
    if not inventory:RemoveItem(source, 'money', reserved) then return false, 'payment_failed' end

    serial = serial + 1
    local session = {
        id = ('%s:%s:%s'):format(source, GetGameTimer(), serial),
        netId = netId,
        pump = pump,
        startFuel = startFuel,
        reserved = reserved,
        allowedTicks = allowedTicks,
        consumed = 0,
        lastTick = GetGameTimer(),
    }
    sessions[source] = session

    return { id = session.id, allowedTicks = allowedTicks, reserved = reserved }
end)

RegisterNetEvent('dante_fuel:liveFuelTick', function(sessionId)
    local source = source
    local session = sessions[source]
    if not session or session.id ~= sessionId or session.consumed >= session.allowedTicks then return end

    local now = GetGameTimer()
    if now - session.lastTick < math.floor(config.refillTick * 0.65) then return end

    local ped = GetPlayerPed(source)
    local vehicle = NetworkGetEntityFromNetworkId(session.netId)
    if ped == 0 or vehicle == 0 or GetEntityType(vehicle) ~= 2
        or #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > 5.0
        or #(GetEntityCoords(vehicle) - session.pump) > 12.0 then
        return
    end

    session.consumed = session.consumed + 1
    session.lastTick = now
end)

lib.callback.register('dante_fuel:finishLiveFuel', function(source, sessionId, fuel)
    local session = sessions[source]
    if not session or session.id ~= sessionId then return false end
    closeSession(source, session, fuel)
    return true
end)

CreateThread(function()
    while true do
        local now = GetGameTimer()
        for source, session in pairs(sessions) do
            if now - session.lastTick > 30000 then
                refund(source, session)
                sessions[source] = nil
                TriggerClientEvent('ox_lib:notify', source, {
                    type = 'error',
                    description = 'Fueling session expired. Reserved money was returned.'
                })
            end
        end
        Wait(5000)
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    local session = sessions[source]
    if session then
        refund(source, session)
        sessions[source] = nil
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for source, session in pairs(sessions) do
        refund(source, session)
        sessions[source] = nil
    end
end)
