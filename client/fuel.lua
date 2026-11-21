local config = require 'config'
local state = require 'client.state'
local screens = require 'client.screens'
local fuel = {}

---@param vehState StateBag
---@param vehicle integer
---@param amount number
---@param replicate? boolean
function fuel.setFuel(vehState, vehicle, amount, replicate)
    if DoesEntityExist(vehicle) then
        amount = math.clamp(amount, 0, 100)
        SetVehicleFuelLevel(vehicle, amount)
        vehState.fuel = amount
        if replicate and NetworkGetEntityIsNetworked(vehicle) then
            TriggerServerEvent('ox_fuel:setFuel', amount)
        end
    end
end

function fuel.getPetrolCan(coords, refuel)
    TaskTurnPedToFaceCoord(cache.ped, coords.x, coords.y, coords.z, config.petrolCan.duration)
    Wait(500)

    if lib.progressCircle({
        duration = config.petrolCan.duration,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = {
            dict = 'timetable@gardener@filling_can',
            clip = 'gar_ig_5_filling_can',
            flags = 49,
        }
    }) then
        if refuel and exports.ox_inventory:GetItemCount('WEAPON_PETROLCAN') then
            TriggerServerEvent('ox_fuel:fuelCan', true, config.petrolCan.refillPrice)
        else
            TriggerServerEvent('ox_fuel:fuelCan', false, config.petrolCan.price)
        end
    end

    ClearPedTasks(cache.ped)
end

local function paymentError(reason)
    local messages = {
        not_enough_money = locale('refuel_cannot_afford'),
        vehicle_too_far = locale('vehicle_far'),
        pump_too_far = locale('vehicle_far'),
        nozzle_required = 'Insert the pump nozzle into the vehicle first.',
    }
    lib.notify({ type = 'error', description = messages[reason] or locale('refuel_cannot_afford') })
end

function fuel.startFueling(vehicle, isPump, pumpCoords)
    if not DoesEntityExist(vehicle) then return end

    local vehState = Entity(vehicle).state
    local fuelAmount = tonumber(vehState.fuel) or GetVehicleFuelLevel(vehicle)
    local maxTicks = math.ceil((100 - fuelAmount) / config.refillValue)
    local durability = 0

    if maxTicks < 1 then
        return lib.notify({ type = 'error', description = locale('tank_full') })
    end

    if isPump then
        pumpCoords = pumpCoords or state.nearestPump
        if not pumpCoords then return end

        local reservation, reason = lib.callback.await('dante_fuel:beginLiveFuel', false,
            NetworkGetNetworkIdFromEntity(vehicle),
            { x = pumpCoords.x, y = pumpCoords.y, z = pumpCoords.z },
            maxTicks
        )

        if type(reservation) ~= 'table' or not reservation.id then
            return paymentError(reason)
        end

        maxTicks = math.min(maxTicks, reservation.allowedTicks)
        state.liveFuelSession = reservation.id
    elseif not state.petrolCan then
        return lib.notify({ type = 'error', description = locale('petrolcan_not_equipped') })
    elseif state.petrolCan.metadata.ammo <= config.durabilityTick then
        return lib.notify({ type = 'error', description = locale('petrolcan_not_enough_fuel') })
    end

    local duration = maxTicks * config.refillTick
    state.isFueling = true

    if isPump then
        screens.setPumpState(pumpCoords, 'fueling', { progress = fuelAmount / 100 })
    end

    TaskTurnPedToFaceEntity(cache.ped, vehicle, duration)
    Wait(250)

    local progressFinished = false
    CreateThread(function()
        lib.progressCircle({
            duration = duration,
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = isPump and 'timetable@gardener@filling_can' or 'weapon@w_sp_jerrycan',
                clip = isPump and 'gar_ig_5_filling_can' or 'fire',
            },
        })
        progressFinished = true
        state.isFueling = false
    end)

    local ticks = 0
    while state.isFueling and ticks < maxTicks do
        if isPump then
            if not DoesEntityExist(vehicle)
                or #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) > 5.0 then
                lib.cancelProgress()
                break
            end
        elseif state.petrolCan then
            durability = math.min(durability + config.durabilityTick, state.petrolCan.metadata.ammo)
            if durability >= state.petrolCan.metadata.ammo then
                lib.cancelProgress()
            end
        else
            break
        end

        fuelAmount = math.min(100.0, fuelAmount + config.refillValue)
        ticks = ticks + 1

        if isPump then
            TriggerServerEvent('dante_fuel:liveFuelTick', state.liveFuelSession)
            screens.setPumpState(pumpCoords, 'fueling', { progress = math.min(fuelAmount / 100, 1.0) })
        end

        if fuelAmount >= 100.0 or ticks >= maxTicks then
            state.isFueling = false
        end

        Wait(config.refillTick)
    end

    if not progressFinished then lib.cancelProgress() end
    state.isFueling = false
    ClearPedTasks(cache.ped)

    if isPump then
        lib.callback.await('dante_fuel:finishLiveFuel', false, state.liveFuelSession, fuelAmount)
        state.liveFuelSession = nil
        if pumpCoords then
            screens.setPumpState(pumpCoords, fuelAmount >= 100 and 'thanks' or 'return_nozzle')
        end
    else
        TriggerServerEvent('ox_fuel:updateFuelCan', durability, NetworkGetNetworkIdFromEntity(vehicle), fuelAmount)
    end
end

return fuel
