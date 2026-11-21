-- One-shot pump payment sessions for Dante Fuel.
-- No money is removed or reserved when fueling starts. The player is charged once,
-- when fueling ends, for the accepted fuel ticks only.
local config = require 'config'
local inventory = exports.ox_inventory
local sessions = {}
local serial = 0

local function closeSession(source, session)
	if not session or sessions[source] ~= session then return false end
	sessions[source] = nil

	local charged = session.consumed * config.priceTick
	if charged > 0 and not exports[GetCurrentResourceName()]:chargeFuel(source, charged) then
		TriggerClientEvent('ox_lib:notify', source, {
			type = 'error',
			description = locale('refuel_cannot_afford')
		})
		return false
	end

	local vehicle = NetworkGetEntityFromNetworkId(session.netId)
	if vehicle ~= 0 and GetEntityType(vehicle) == 2 and session.consumed > 0 then
		local state = Entity(vehicle).state
		local finalFuel = math.min(100.0, session.startFuel + session.consumed * config.refillValue)
		state:set('fuel', finalFuel, true)
	end

	if charged > 0 then
		local finalFuel = math.floor(math.min(100.0, session.startFuel + session.consumed * config.refillValue))
		TriggerClientEvent('ox_lib:notify', source, {
			type = 'success',
			description = locale('fuel_success', finalFuel, charged)
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

	local startFuel = tonumber(Entity(vehicle).state.fuel) or GetVehicleFuelLevel(vehicle)
	local available = inventory:GetItemCount(source, 'money')
	local allowedTicks = math.min(maxTicks, math.floor(available / config.priceTick))
	if allowedTicks < 1 then return false, 'not_enough_money' end

	serial = serial + 1
	local session = {
		id = ('%s:%s:%s'):format(source, GetGameTimer(), serial),
		netId = netId,
		pump = pump,
		startFuel = startFuel,
		allowedTicks = allowedTicks,
		consumed = 0,
		lastTick = GetGameTimer(),
	}
	sessions[source] = session

	return { id = session.id, allowedTicks = allowedTicks }
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

lib.callback.register('dante_fuel:finishLiveFuel', function(source, sessionId)
	local session = sessions[source]
	if not session or session.id ~= sessionId then return false end
	return closeSession(source, session)
end)

CreateThread(function()
	while true do
		local now = GetGameTimer()
		for playerId, session in pairs(sessions) do
			if now - session.lastTick > 30000 then
				sessions[playerId] = nil
				TriggerClientEvent('ox_lib:notify', playerId, {
					type = 'error',
					description = 'Fueling session expired. No payment was taken.'
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
