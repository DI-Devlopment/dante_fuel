if not lib.checkDependency('ox_lib', '3.22.0', true) then return end
if not lib.checkDependency('ox_inventory', '2.30.0', true) then return end

return {
	-- Get notified when a new version releases
	versionCheck = true,

	-- Use sd-interact for pump and vehicle interactions
	sd_interact = true,

	-- Show or hide gas station blips:
	-- 0 = hide all, 1 = show nearest, 2 = show all
	showBlips = 2,

	-- Refuelling amount added per tick
	refillValue = 0.50,

	-- Refuelling tick interval in milliseconds
	refillTick = 250,

	-- Fuel cost per accepted pump tick
	priceTick = 5,

	-- Petrol-can durability loss per tick
	durabilityTick = 1.3,

	-- Petrol-can settings
	petrolCan = {
		enabled = true,
		duration = 5000,
		price = 1000,
		refillPrice = 800,
	},

	-- Vehicle fuel consumption multiplier
	globalFuelConsumptionRate = 10.0,

	-- Loose pump bodies used when a modern pump is torn from its island.
	tornPumpModels = {
		[`prop_gas_pump_1a`] = `whip_pump_torn_1a`,
		[`prop_gas_pump_1b`] = `whip_pump_torn_1b`,
		[`prop_gas_pump_1c`] = `whip_pump_torn`,
		[`prop_gas_pump_1d`] = `whip_pump_torn_1d`,
	},

	-- Fuel spill duration after a modern pump tears away. The spill leaves a trail
	-- behind the vehicle and can ignite into script fire.
	spillDuration = 20,
	spillIgnitionDelay = 2.5,

	-- Modern GTA pump models used by Whip's physical nozzle and LCD layout.
	-- Legacy/vintage pumps do not have the matching screen and hose attachment positions.
	pumpModels = {
		`prop_gas_pump_1a`,
		`prop_gas_pump_1b`,
		`prop_gas_pump_1c`,
		`prop_gas_pump_1d`,
	}
}
