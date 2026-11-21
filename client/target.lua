
local config = require 'config'
local state = require 'client.state'
local utils = require 'client.utils'
local fuel = require 'client.fuel'

local pumpOptions = {
    {
        name = 'ox_fuel:startFueling',
        label = locale('start_fueling'),
        icon = 'fa-solid fa-gas-pump',

        canInteract = function()
            if state.isFueling or cache.vehicle or lib.progressActive() then
                return false
            end

            local vehicle = state.lastVehicle

            return vehicle
                and DoesEntityExist(vehicle)
                and DoesVehicleUseFuel(vehicle)
                and #(GetEntityCoords(vehicle) - GetEntityCoords(cache.ped)) <= 3.0
        end,

        onSelect = function(data)
            local vehicle = state.lastVehicle

            if not vehicle or not DoesEntityExist(vehicle) then return end

            if utils.getMoney() < config.priceTick then
                return lib.notify({
                    type = 'error',
                    description = locale('refuel_cannot_afford')
                })
            end

            if GetVehicleFuelLevel(vehicle) >= 100 then
                return lib.notify({
                    type = 'error',
                    description = locale('vehicle_full')
                })
            end

            fuel.startFueling(vehicle, true, GetEntityCoords(data.entity))
        end,
    },
}

if config.petrolCan.enabled then
    pumpOptions[#pumpOptions + 1] = {
        name = 'ox_fuel:petrolCan',
        label = locale('petrolcan_buy_or_refill'),
        icon = 'fa-solid fa-faucet',

        onSelect = function(data)
            local petrolCan = GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`
            local money = utils.getMoney()

            local price = petrolCan
                and config.petrolCan.refillPrice
                or config.petrolCan.price

            if money < price then
                return lib.notify({
                    type = 'error',
                    description = locale('petrolcan_cannot_afford')
                })
            end

            fuel.getPetrolCan(GetEntityCoords(data.entity), petrolCan)
        end,
    }
end

exports['sd-interact']:addModel(config.pumpModels, {
    interactDistance = 2.0,
    options = pumpOptions,
})

if config.petrolCan.enabled then
    exports['sd-interact']:addGlobalVehicle({
        name = 'ox_fuel:vehiclePetrolCan',
        interactDistance = 2.0,

        options = {
            {
                name = 'ox_fuel:vehiclePetrolCan',
                label = locale('start_fueling'),
                icon = 'fa-solid fa-gas-pump',

                canInteract = function(entity)
                    if state.isFueling or cache.vehicle or lib.progressActive() then
                        return false
                    end

                    return state.petrolCan
                        and DoesVehicleUseFuel(entity)
                        and state.petrolCan.metadata.ammo > config.durabilityTick
                end,

                onSelect = function(data)
                    fuel.startFueling(data.entity, false)
                end,
            },
        },
    })
end
