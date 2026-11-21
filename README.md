# ox_fuel

Basic fuel resource and alternative to LegacyFuel, meant for use with ox_inventory.

## Get vehicle fuel level

This is an incredibly complicated task for some people, and they often ask for exports to do it.
You use the native function [GetVehicleFuelLevel](https://docs.fivem.net/natives/?_0x5F739BB8), or you can use a statebag.

```lua
Entity(entity).state.fuel
```

## Set vehicle fuel level

```lua
Entity(entity).state.fuel = fuelAmount
```

## setPaymentMethod (server)

Replaces the standard payment method using "money" as an item.

```lua
exports.ox_fuel:setPaymentMethod(function(playerId, amount)
    local xPlayer = ESX.GetPlayerFromId(playerId)
	local bankAmount = xPlayer.getAccount('bank').money

	if bankAmount >= amount then
		xPlayer.removeAccountMoney('bank', amount)
		return true
	end

	TriggerClientEvent('ox_lib:notify', source, {
		type = 'error',
		description = locale('not_enough_money', amount - bankAmount)
	})
end)
```

## setMoneyCheck (client)

Replaces the standard inventory search for "money".

```lua
exports.ox_fuel:setMoneyCheck(function()
	local accounts = ESX.GetPlayerData().accounts

	for i = 1, #accounts do
		if accounts[i].name == 'bank' then
		    return accounts[i].money
		end
	end

	return 0
end)
```

---

# Whip pump LCD integration

This build adds Whip Fuel's modern pump models and LCD artwork to the supplied ox_fuel 1.5.4 resource.

## Included changes

- ox_fuel remains responsible for vehicle fuel, fuel consumption, money checks, petrol cans, payments, and refuelling progress.
- Whip Fuel's modern pump replacements (`prop_gas_pump_1a`, `1b`, `1c`, and `1d`) are included.
- Whip Fuel's original `pump_lcd.html` interface is reused.
- The LCD browser is created with FiveM DUI natives and drawn in 3D with FiveM’s native `DrawTexturedPoly`.
- One shared DUI atlas is used for both faces of the active pump and released after an idle period.

## Dependencies

- `ox_lib` 3.22.0 or newer
- `ox_inventory` 2.30.0 or newer
- `ox_target` only if `config.ox_target = true`

There is no dependency on `whip_core`, `whip_fuel`, or `WorldQuad`.

## Installation

1. Back up or stop your existing `ox_fuel` resource.
2. Replace it with this resource folder, keeping the resource folder name `ox_fuel`.
3. Ensure `ox_lib` and `ox_inventory` start before `ox_fuel`.
4. Do not start `whip_fuel` alongside this resource.
5. Restart the server or run `refresh` and `ensure ox_fuel`.

The four modern Whip pump models replace the matching vanilla pump models when this resource is streamed. The older pump models (`prop_gas_pump_old2`, `prop_gas_pump_old3`, and `prop_vintage_pump`) remain vanilla in this first integration; Whip's LCD geometry is designed for the modern 1a–1d models.

## LCD behaviour

- The screens activate when ox_fuel starts a pump refuel.
- Both faces display the Whip LCD interface and refuelling progress.
- A completed fill shows the thank-you screen; an interrupted fill shows the return-nozzle screen.
- The shared DUI is destroyed after 15 seconds without an active pump screen.

## Validation

The embedded JavaScript and locale JSON files passed syntax checks. The Lua integration and model placement still require an in-game FiveM test; this environment cannot launch a FiveM client. Verify the LCD placement and orientation in-game.

Whip Fuel's notice and LGPL/GPL license texts are included as `WHIP-NOTICE.md`, `WHIP-COPYING.LESSER`, and `WHIP-COPYING`.
