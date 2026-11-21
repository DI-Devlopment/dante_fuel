local utils = {}

function utils.createBlip(coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 361)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 6)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('ox_fuel_station')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function defaultMoneyCheck()
    return exports.ox_inventory:GetItemCount('money')
end

utils.getMoney = defaultMoneyCheck

exports('setMoneyCheck', function(fn)
    utils.getMoney = fn or defaultMoneyCheck
end)

return utils
