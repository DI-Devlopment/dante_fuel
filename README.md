# Dante Fuel

Dante Fuel is a standalone FiveM fuel resource based on the **ox_fuel 1.5.4** foundation. It keeps the familiar ox_fuel vehicle fuel state, consumption, petrol-can, inventory and payment integration while adding a custom pump display and a physical pump-nozzle workflow.

## Features

- Vehicle fuel levels and consumption using replicated vehicle state.
- Existing ox_inventory petrol-can purchase, refill and use behavior.
- Live pump fueling: the server counts accepted fuel ticks and charges once when the session ends, only for the fuel actually delivered. No upfront debit or money hold.
- Native FiveM DUI pump LCDs rendered with native world-space textured polygons.
- Pump and vehicle interactions through sd-interact.
- Physical fuel nozzles that come out of their pump holsters, attach to the player's hand, and insert into a vehicle's fuel-cap area.
- Native FiveM rope hoses that follow the held or vehicle-mounted nozzle.
- A held nozzle drops if the player walks more than 5 metres from its pump and returns to its holster after 30 seconds on the ground.
- Modern pump models (1a/1b/1c/1d) create a loose pump body when driven away with the nozzle inserted. Older pump models snap the hose instead.
- Press **G** to drop a nozzle being carried. Use the pump interaction to take or return it, and the vehicle interaction to insert, fuel, or remove it.

## Dependencies

- [ox_lib](https://github.com/overextended/ox_lib) 3.22.0 or newer
- [ox_inventory](https://github.com/overextended/ox_inventory) 2.30.0 or newer
- [sd-interact](https://docs.samueldev.shop/resources/interact)

No dependency on ox_target, whip_core, whip_fuel, whip_rope, or WorldQuad is required. Hose rendering uses FiveM's native rope functions.

## Installation

1. Install the dependencies above and ensure they start before Dante Fuel.
2. Place this resource in your server resources folder.
3. Ensure ox_lib, ox_inventory and sd-interact before Dante Fuel.
4. Add `ensure dante_fuel` to your server configuration (use the actual resource folder name if different).
5. Restart the resource or server.

## Configuration

Edit `config.lua` to configure:

- `sd_interact`: enables the sd-interact interaction backend.
- `showBlips`: `0` hides station blips, `1` shows the nearest station, and `2` shows all stations.
- `refillValue` and `refillTick`: control refuelling speed.
- `priceTick`: cost charged per accepted live-fueling tick.
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

The resource retains the upstream `setPaymentMethod` and `setMoneyCheck` integration points. Pump fueling uses the server-side `chargeFuel` entry point so custom payment handlers registered through `setPaymentMethod` continue to work.

## Project origins and third-party notices

Dante Fuel is an independent integration project. Its fuel system is based on the Overextended ox_fuel project. Pump LCD assets and presentation concepts are adapted from Whip Fuel; the physical nozzle workflow is independently integrated with native FiveM entities and ropes. Upstream notices and license texts remain in the repository.

- **ox_fuel:** https://github.com/overextended/ox_fuel
- **Whip Fuel:** https://github.com/WHIPFX/whip_fuel
- **sd-interact:** https://docs.samueldev.shop/resources/interact

Dante Fuel is not an official release of or endorsed by those upstream projects. Review the included license files before redistributing modified versions.

## Testing

This source integration has not been exercised in a live FiveM server in this session. In-game validation is still required for rope attachment/physics across clients, vehicle filler alignment across vehicle models, pump-copy network ownership and drag behavior, and the sd-interact option flow. Static code inspection is not a substitute for those runtime tests.
