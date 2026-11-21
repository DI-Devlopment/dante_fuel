---@class State
---@field petrolCan SlotWithItem?
---@field isFueling boolean
local state = { isFueling = false }

local function setPetrolCan(data)
    state.petrolCan = data and data.name == 'WEAPON_PETROLCAN' and data or nil
end

setPetrolCan(exports.ox_inventory:getCurrentWeapon())
AddEventHandler('ox_inventory:currentWeapon', setPetrolCan)

return state
