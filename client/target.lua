local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local fuel = require 'client.fuel'
local nozzle = require 'client.nozzle'

local pumpOptions = {
    {
        name = 'dante_fuel:take_nozzle',
        label = 'Take fuel nozzle',
        icon = 'fa-solid fa-gas-pump',
        canInteract = function(entity)
            return not state.isFueling and not nozzle.isHeld() and not cache.vehicle
                and not nozzle.hasNozzleAt(entity)
        end,
        onSelect = function(data) nozzle.take(data.entity) end,
    },
    {
        name = 'dante_fuel:return_nozzle',
        label = 'Return fuel nozzle',
        icon = 'fa-solid fa-rotate-left',
        canInteract = function(entity)
            return nozzle.isHeldAt(entity) and not cache.vehicle
        end,
        onSelect = function(data) nozzle.returnAt(data.entity) end,
    },
    {
        name = 'dante_fuel:petrol_can',
        label = locale('petrolcan_buy_or_refill'),
        icon = 'fa-solid fa-faucet',
        canInteract = function()
            return config.petrolCan.enabled and not state.isFueling and not cache.vehicle
        end,
        onSelect = function(data)
            local hasCan = GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`
            local price = hasCan and config.petrolCan.refillPrice or config.petrolCan.price
            if utils.getMoney() < price then
                return lib.notify({ type = 'error', description = locale('petrolcan_cannot_afford') })
            end
            fuel.getPetrolCan(GetEntityCoords(data.entity), hasCan)
        end,
    },
}

exports['sd-interact']:addModel(config.pumpModels, {
    interactDistance = 2.0,
    options = pumpOptions,
})

exports['sd-interact']:addGlobalVehicle({
    name = 'dante_fuel:vehicle_nozzle',
    interactDistance = 2.5,
    options = {
        {
            name = 'dante_fuel:insert_nozzle',
            label = 'Insert fuel nozzle',
            icon = 'fa-solid fa-gas-pump',
            canInteract = function(entity)
                return nozzle.isHeld() and not cache.vehicle and not state.isFueling
                    and DoesVehicleUseFuel(entity)
            end,
            onSelect = function(data) nozzle.insert(data.entity) end,
        },
        {
            name = 'dante_fuel:start_live_fueling',
            label = locale('start_fueling'),
            icon = 'fa-solid fa-gas-pump',
            canInteract = function(entity)
                local key, data = nozzle.forVehicle(entity)
                return key ~= nil and not data.torn and not data.snapped
                    and not state.isFueling and not cache.vehicle and not lib.progressActive()
            end,
            onSelect = function(data)
                local pumpCoords = nozzle.pumpCoordsForVehicle(data.entity)
                if pumpCoords then fuel.startFueling(data.entity, true, pumpCoords) end
            end,
        },
        {
            name = 'dante_fuel:remove_nozzle',
            label = 'Remove fuel nozzle',
            icon = 'fa-solid fa-hand',
            canInteract = function(entity)
                local key = nozzle.forVehicle(entity)
                return key ~= nil and not cache.vehicle and not state.isFueling
            end,
            onSelect = function(data) nozzle.remove(data.entity) end,
        },
    },
})

if config.petrolCan.enabled then
    exports['sd-interact']:addGlobalVehicle({
        name = 'dante_fuel:vehicle_petrol_can',
        interactDistance = 2.0,
        options = {{
            name = 'dante_fuel:vehiclePetrolCan',
            label = locale('start_fueling'),
            icon = 'fa-solid fa-gas-pump',
            canInteract = function(entity)
                return not state.isFueling and not cache.vehicle and not lib.progressActive()
                    and state.petrolCan and DoesVehicleUseFuel(entity)
                    and state.petrolCan.metadata.ammo > config.durabilityTick
            end,
            onSelect = function(data) fuel.startFueling(data.entity, false) end,
        }},
    })
end
