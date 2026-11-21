local config = require 'config'
local utils = require 'client.utils'
local stations = lib.load 'data.stations'

if config.showBlips == 2 then
    for station in pairs(stations) do utils.createBlip(station) end
    return
end

if config.showBlips ~= 1 then return end

for station in pairs(stations) do
    local blip
    lib.points.new({
        coords = station,
        distance = 60,
        onEnter = function()
            if not blip then blip = utils.createBlip(station) end
        end,
        onExit = function()
            if blip then
                RemoveBlip(blip)
                blip = nil
            end
        end,
    })
end
