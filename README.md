# Dante Fuel

A standalone FiveM fuel resource built on the **ox_fuel 1.5.4** foundation. Dante Fuel retains the original fuel-state, consumption, petrol-can, inventory and payment flow while providing a custom pump presentation and interaction layer.

## Features

- Vehicle fuel levels and consumption using replicated vehicle state.
- Refuelling and petrol-can purchases through ox_inventory.
- Pump fueling calculates the cost from accepted fuel ticks and makes one payment when the session ends. No money is reserved or removed at the start.
- Native FiveM DUI pump displays using the included LCD page.
- World-space LCD rendering using FiveM native drawing functions.
- Pump and vehicle interactions through sd-interact.
- Vanilla GTA pump support and the included modern pump display integration.

## Dependencies

- [ox_lib](https://github.com/overextended/ox_lib) 3.22.0 or newer
- [ox_inventory](https://github.com/overextended/ox_inventory) 2.30.0 or newer
- [sd-interact](https://docs.samueldev.shop/resources/interact)

The current integration does not require ox_target, whip_core, whip_fuel, whip_rope or WorldQuad.

## Installation

1. Install the dependencies above and ensure they start before Dante Fuel.
2. Place the resource in your server resources folder.
3. Ensure ox_lib, ox_inventory and sd-interact before this resource.
4. Add `ensure dante_fuel` to your server configuration (use the actual resource folder name if different).
5. Restart the resource or server.

## Configuration

Edit `config.lua` to configure:

- `sd_interact`: enables the sd-interact interaction backend.
- `showBlips`: `0` hides station blips, `1` shows the nearest station, and `2` shows all stations.
- `refillValue` and `refillTick`: control refuelling speed.
- `priceTick`: cost charged per refuelling tick.
- `petrolCan`: enables and configures petrol-can purchases and refills.
- `globalFuelConsumptionRate`: adjusts the vehicle fuel consumption multiplier.
- `pumpModels`: pump models recognized by the resource.

## Fuel state and exports

Read a vehicle's fuel level with the GTA native `GetVehicleFuelLevel` or its replicated state bag:

```lua
local fuel = Entity(vehicle).state.fuel
```

Set a fuel level through the state bag:

```lua
Entity(vehicle).state.fuel = 75.0
```

The resource retains the upstream `setPaymentMethod` and `setMoneyCheck` integration points. Pump fueling charges once when the session ends, based only on the fuel ticks accepted by the server.

## Project origins and third-party notices

Dante Fuel is an independent integration project. Its fuel system is based on the Overextended ox_fuel project. The pump LCD page and associated pump presentation assets are incorporated from Whip Fuel where identified by the accompanying notices and license files.

- **ox_fuel:** https://github.com/overextended/ox_fuel
- **Whip Fuel:** https://github.com/WHIPFX/whip_fuel
- **sd-interact:** https://docs.samueldev.shop/resources/interact

Third-party notices and license texts are retained in this repository. Review the included license files before redistributing modified versions. Dante Fuel is not an official release of or endorsed by the upstream projects.

## Validation

Source changes must be tested in a running FiveM server. Verify pump interactions, payment flow, vehicle fuel-state synchronization, and LCD placement with the maps and assets used by your server. Static source inspection is not a substitute for an in-game test.
