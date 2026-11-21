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

	-- Gas pump models recognized by the resource
	pumpModels = {
		`prop_gas_pump_old2`,
		`prop_gas_pump_1a`,
		`prop_vintage_pump`,
		`prop_gas_pump_old3`,
		`prop_gas_pump_1c`,
		`prop_gas_pump_1b`,
		`prop_gas_pump_1d`,
	}
}
