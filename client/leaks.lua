-- Client-side visual spill and ignition after a modern pump tears away.
-- One spill is tracked per physical pump, not per nozzle side.
local config = require 'config'
local leaks = {}
local active = {}

local function stopFire(handle)
    if handle and handle ~= 0 then StopFire(handle) end
end

local function stopGroup(group)
    local spill = active[group]
    if not spill then return end
    spill.cancelled = true
    for i = 1, #spill.fires do stopFire(spill.fires[i]) end
    active[group] = nil
end

function leaks.stop(key)
    if type(key) ~= 'string' then return end
    stopGroup(key:sub(1, -3))
end

local function groundPoint(vehicle)
    local pos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local speed = GetEntitySpeed(vehicle)
    local behind = math.min(4.0, 1.6 + speed * 0.12)
    local point = vector3(pos.x - forward.x * behind, pos.y - forward.y * behind, pos.z - 0.65)
    local found, groundZ = GetGroundZFor_3dCoord(point.x, point.y, point.z + 2.0, false)
    if found then point = vector3(point.x, point.y, groundZ + 0.04) end
    return point
end

function leaks.start(data)
    if not data or not data.key or data.spillOwner == false or not data.vehicle then return end
    local group = data.key:sub(1, -3)
    local current = active[group]
    if current and current.vehicle == data.vehicle then return end
    if current then stopGroup(group) end

    local elapsed = math.max(0, tonumber(data.tornElapsed) or 0)
    local spill = {
        started = GetGameTimer() - elapsed,
        fires = {},
        cancelled = false,
        vehicle = data.vehicle,
    }
    active[group] = spill

    CreateThread(function()
        local duration = math.max(1, tonumber(config.spillDuration) or 20) * 1000
        local igniteAt = math.max(0, tonumber(config.spillIgnitionDelay) or 2.5) * 1000
        local asset = 'core'
        RequestNamedPtfxAsset(asset)
        local loadDeadline = GetGameTimer() + 3000
        while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < loadDeadline do Wait(25) end

        while not spill.cancelled and active[group] == spill
            and GetGameTimer() - spill.started < duration do
            local vehicle = NetworkGetEntityFromNetworkId(spill.vehicle)
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                local point = groundPoint(vehicle)
                if HasNamedPtfxAssetLoaded(asset) then
                    UseParticleFxAssetNextCall(asset)
                    StartParticleFxNonLoopedAtCoord('ent_sht_petrol',
                        point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.7, false, false, false)
                end

                local elapsed = GetGameTimer() - spill.started
                if elapsed >= igniteAt and (not spill.lastFire or GetGameTimer() - spill.lastFire >= 1100) then
                    local fire = StartScriptFire(point.x, point.y, point.z, 8, true)
                    if fire and fire ~= 0 then spill.fires[#spill.fires + 1] = fire end
                    spill.lastFire = GetGameTimer()
                end
            else
                break
            end
            Wait(350)
        end

        for i = 1, #spill.fires do stopFire(spill.fires[i]) end
        if active[group] == spill then active[group] = nil end
        if HasNamedPtfxAssetLoaded(asset) then RemoveNamedPtfxAsset(asset) end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for group in pairs(active) do stopGroup(group) end
end)

return leaks
