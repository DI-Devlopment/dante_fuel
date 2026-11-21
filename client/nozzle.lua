-- Native FiveM nozzle props and rope hoses. The server replicates nozzle state; each client draws its own rope.
local screens = require 'client.screens'
local nozzle = { states = {}, heldKey = nil }
local ropes, holsters, hiddenPumps = {}, {}, {}
local NOZZLE = joaat('prop_cs_fuel_nozle')
local HOLSTER = {
    A = { pos = vec3(0.3447, -0.3744, 0.7044), rot = vec3(0.251, -0.076, 0.066) },
    B = { pos = vec3(-0.3447, 0.3655, 0.7044), rot = vec3(0.259, -0.077, -179.934) },
}
local function entityFrom(net)
    if not net or net == 0 or not NetworkDoesNetworkIdExist(net) then return nil end
    local e = NetworkGetEntityFromNetworkId(net)
    return e ~= 0 and DoesEntityExist(e) and e or nil
end
local function findPump(data)
    local c = data.pump
    if data.torn and data.pumpNet then
        local copy = entityFrom(data.pumpNet)
        if copy then return copy end
    end
    return GetClosestObjectOfType(c.x, c.y, c.z, 2.0, data.model, false, false, false)
end
local function removeRope(key)
    local r = ropes[key]
    if r then
        if DoesRopeExist(r) then DeleteRope(r) end
        ropes[key] = nil
    end
end
local function restorePump(key)
    local p = hiddenPumps[key]
    if p and DoesEntityExist(p) then SetEntityVisible(p, true, false) end
    hiddenPumps[key] = nil
end
local function makeHolsters(pump, key)
    if not pump or pump == 0 or not DoesEntityExist(pump) or holsters[key] then return end
    local pair = {}
    for side, at in pairs(HOLSTER) do
        local obj = CreateObjectNoOffset(NOZZLE, 0.0, 0.0, 0.0, false, false, false)
        if obj and obj ~= 0 then
            SetEntityCollision(obj, false, false)
            AttachEntityToEntity(obj, pump, 0, at.pos.x, at.pos.y, at.pos.z,
                at.rot.x, at.rot.y, at.rot.z, false, false, false, false, 2, true)
            pair[side] = obj
        end
    end
    holsters[key] = pair
end
local function setHolster(data, visible)
    local prefix = data.key:sub(1, -3)
    local pump = findPump(data)
    if not pump or pump == 0 then return end
    makeHolsters(pump, prefix)
    local h = holsters[prefix]
    local obj = h and h[data.side]
    if obj and DoesEntityExist(obj) then SetEntityVisible(obj, visible, false) end
end
local function ropeEnds(data)
    if data.snapped then return end
    local pump = findPump(data)
    local obj = entityFrom(data.nozzleNet)
    if not pump or pump == 0 or not obj then return end
    if data.torn then
        local original = GetClosestObjectOfType(data.pump.x, data.pump.y, data.pump.z, 1.5, data.model, false, false, false)
        if original and original ~= 0 and DoesEntityExist(original) then
            SetEntityVisible(original, false, false)
            hiddenPumps[data.key] = original
        end
    end
    local at = HOLSTER[data.side].pos
    local start = GetOffsetFromEntityInWorldCoords(pump, at.x, at.y, at.z)
    local finish = GetOffsetFromEntityInWorldCoords(obj, 0.0, -0.027, -0.200)
    if not ropes[data.key] then
        if not RopeAreTexturesLoaded() then
            RopeLoadTextures()
            local deadline = GetGameTimer() + 2000
            while not RopeAreTexturesLoaded() and GetGameTimer() < deadline do Wait(0) end
        end
        local rope = AddRope(start.x, start.y, start.z, 0.0, 0.0, 0.0, 6.0, 4, 6.0, 0.1, 1.0, false, false, false, 1.0, false, 0)
        if rope and rope ~= 0 then
            AttachEntitiesToRope(rope, pump, obj, start.x, start.y, start.z,
                finish.x, finish.y, finish.z, 6.0, false, false, nil, nil)
            RopeForceLength(rope, 4.5)
            ropes[data.key] = rope
        end
    end
end
local function apply(data)
    if type(data) ~= 'table' or not data.key then return end
    local old = nozzle.states[data.key]
    nozzle.states[data.key] = data
    local me = GetPlayerServerId(PlayerId())
    if data.state == 'holstered' then
        removeRope(data.key)
        restorePump(data.key)
        setHolster(data, true)
        if nozzle.heldKey == data.key then nozzle.heldKey = nil end
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'thanks')
        return
    end
    if not data.torn then restorePump(data.key) end
    setHolster(data, false)
    if data.state == 'hand' then
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'nozzle_out')
    elseif data.state == 'ground' then
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'return_nozzle')
    end
    if data.state == 'hand' and data.holder == me then nozzle.heldKey = data.key end
    if nozzle.heldKey == data.key and (data.state ~= 'hand' or data.holder ~= me) then nozzle.heldKey = nil end
    if data.snapped then
        removeRope(data.key)
        restorePump(data.key)
        return
    end
    removeRope(data.key)
    CreateThread(function()
        local deadline = GetGameTimer() + 4000
        while GetGameTimer() < deadline do
            local p = findPump(data)
            local o = entityFrom(data.nozzleNet)
            if p and p ~= 0 and o then
                ropeEnds(data)
                return
            end
            Wait(100)
        end
    end)
end

RegisterNetEvent('dante_fuel:nozzleState', apply)
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1500)
    TriggerServerEvent('dante_fuel:clientReady')
end)

local function sideFor(pump)
    local p = GetEntityCoords(cache.ped)
    local localPos = GetOffsetFromEntityGivenWorldCoords(pump, p.x, p.y, p.z)
    return localPos.y < 0.0 and 'A' or 'B'
end
function nozzle.take(pump)
    if not pump or pump == 0 or not DoesEntityExist(pump) then return end
    local coords = GetEntityCoords(pump)
    local side = sideFor(pump)
    for _, active in pairs(nozzle.states) do
        if active.state == 'ground'
            and #(vec3(active.pump.x, active.pump.y, active.pump.z) - coords) <= 1.5 then
            side = active.side
            break
        end
    end
    TriggerServerEvent('dante_fuel:takeNozzle', { x=coords.x, y=coords.y, z=coords.z, heading=GetEntityHeading(pump) }, GetEntityModel(pump), side)
end
function nozzle.returnAt(pump)
    if not pump or pump == 0 then return end
    if nozzle.heldKey then
        TriggerServerEvent('dante_fuel:returnNozzle', nozzle.heldKey)
        return
    end
    local coords = GetEntityCoords(pump)
    local side = sideFor(pump)
    local key = ('%d:%d:%d:%s'):format(math.floor(coords.x*10+0.5), math.floor(coords.y*10+0.5), math.floor(coords.z*10+0.5), side)
    TriggerServerEvent('dante_fuel:returnNozzle', key)
end
function nozzle.insert(vehicle)
    if not vehicle or vehicle == 0 then return end
    TriggerServerEvent('dante_fuel:insertNozzle', NetworkGetNetworkIdFromEntity(vehicle))
end
function nozzle.remove()
    TriggerServerEvent('dante_fuel:removeNozzle')
end
function nozzle.isHeld()
    return nozzle.heldKey ~= nil
end
function nozzle.forVehicle(vehicle)
    local net = NetworkGetNetworkIdFromEntity(vehicle)
    for key, data in pairs(nozzle.states) do
        if data.state == 'car' and data.vehicle == net then return key, data end
    end
end
function nozzle.pumpCoordsForVehicle(vehicle)
    local _, data = nozzle.forVehicle(vehicle)
    if data then return vec3(data.pump.x, data.pump.y, data.pump.z) end
end
RegisterCommand('dante_fuel_dropnozzle', function()
    if nozzle.isHeld() then TriggerServerEvent('dante_fuel:dropNozzle') end
end, false)
RegisterKeyMapping('dante_fuel_dropnozzle', 'Drop fuel pump nozzle', 'keyboard', 'g')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for key in pairs(ropes) do removeRope(key) end
    for key in pairs(holsters) do
        for _, obj in pairs(holsters[key]) do if obj and DoesEntityExist(obj) then DeleteEntity(obj) end end
    end
    for key in pairs(hiddenPumps) do restorePump(key) end
end)
return nozzle
