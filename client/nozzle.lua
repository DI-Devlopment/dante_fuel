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

local function takeControl(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    if NetworkHasControlOfEntity(entity) then return true end
    NetworkRequestControlOfEntity(entity)
    local untilAt = GetGameTimer() + 1200
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < untilAt do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end
    return NetworkHasControlOfEntity(entity)
end

local function attachToHand(data)
    if data.holder ~= GetPlayerServerId(PlayerId()) then return end
    local obj = entityFrom(data.nozzleNet)
    if not obj or not takeControl(obj) then return end
    local ped = PlayerPedId()
    local bone = GetPedBoneIndex(ped, 28422)
    if IsEntityAttached(obj) then DetachEntity(obj, true, true) end
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, ped, bone, 0.13, 0.05, 0.02, -80.0, 0.0, 15.0, false, false, false, false, 2, true)
end

local function attachToVehicle(data)
    local obj, vehicle = entityFrom(data.nozzleNet), entityFrom(data.vehicle)
    if not obj or not vehicle or not takeControl(obj) then return end
    if IsEntityAttached(obj) then DetachEntity(obj, true, true) end
    SetEntityCollision(obj, false, false)
    local off = data.offset or { x=0.0, y=0.0, z=0.0 }
    AttachEntityToEntity(obj, vehicle, 0, off.x, off.y, off.z, -25.0, 0.0, 180.0, false, false, false, false, 2, true)
end

local function dropToGround(data)
    local obj = entityFrom(data.nozzleNet)
    if not obj or not takeControl(obj) then return end
    if IsEntityAttached(obj) then DetachEntity(obj, true, true) end
    local p = data.ground
    if p then SetEntityCoords(obj, p.x, p.y, p.z, false, false, false, false) end
    SetEntityCollision(obj, true, true)
    SetEntityDynamic(obj, true)
    ActivatePhysics(obj)
end

local function deleteNetworkNozzle(data)
    local obj = entityFrom(data.nozzleNet)
    if obj and takeControl(obj) then DeleteEntity(obj) end
end

local function wakeTornPump(data)
    if not data.torn or not data.pumpNet then return end
    local copy = entityFrom(data.pumpNet)
    if copy and takeControl(copy) then
        SetEntityDynamic(copy, true)
        FreezeEntityPosition(copy, false)
        ActivatePhysics(copy)
    end
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
    if data.torn and not data.pumpNet then return end
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
            wakeTornPump(data)
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
        deleteNetworkNozzle(data)
        restorePump(data.key)
        setHolster(data, true)
        if nozzle.heldKey == data.key then nozzle.heldKey = nil end
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'thanks')
        return
    end
    if not data.torn then restorePump(data.key) else wakeTornPump(data) end
    setHolster(data, false)
    if data.state == 'hand' then
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'nozzle_out')
    elseif data.state == 'ground' then
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'return_nozzle')
    end
    if data.state == 'hand' and data.holder == me then nozzle.heldKey = data.key end
    if data.state == 'hand' then attachToHand(data)
    elseif data.state == 'car' then attachToVehicle(data)
    elseif data.state == 'ground' then dropToGround(data) end
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
            if p and p ~= 0 and o and (not data.torn or data.pumpNet) then
                ropeEnds(data)
                return
            end
            Wait(100)
        end
    end)
end

RegisterNetEvent('dante_fuel:createTornPump', function(key, pump, model, heading)
    if type(key) ~= 'string' or type(pump) ~= 'table' or type(model) ~= 'number' then return end
    local data = nozzle.states[key]
    if not data or not data.torn or data.tornOwner ~= GetPlayerServerId(PlayerId()) or data.pumpNet then return end
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local obj = CreateObjectNoOffset(model, pump.x, pump.y, pump.z, true, true, false)
    SetModelAsNoLongerNeeded(model)
    if not obj or obj == 0 then return end
    SetEntityAsMissionEntity(obj, true, true)
    SetEntityHeading(obj, heading or 0.0)
    FreezeEntityPosition(obj, true)
    local netId = NetworkGetNetworkIdFromEntity(obj)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('dante_fuel:tornPumpCreated', key, netId)
end)

RegisterNetEvent('dante_fuel:nozzleState', apply)
RegisterNetEvent('dante_fuel:nozzleDenied', function(netId)
    local obj = entityFrom(netId)
    if obj and takeControl(obj) then DeleteEntity(obj) end
end)
RegisterNetEvent('dante_fuel:forceDropNozzle', function(key, ground)
    local data = nozzle.states[key]
    if data then data.ground = ground; dropToGround(data) end
end)
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
    local key = ('%d:%d:%d:%s'):format(math.floor(coords.x*10+0.5), math.floor(coords.y*10+0.5), math.floor(coords.z*10+0.5), side)
    local existing = nozzle.states[key]
    local obj = existing and existing.state == 'ground' and entityFrom(existing.nozzleNet)
    if not obj then
        obj = CreateObjectNoOffset(NOZZLE, coords.x, coords.y, coords.z + 0.7, true, true, false)
    end
    if not obj or obj == 0 then
        return lib.notify({ type = 'error', description = 'Could not create the fuel nozzle.' })
    end
    SetEntityAsMissionEntity(obj, true, true)
    if not takeControl(obj) then
        if not existing then DeleteEntity(obj) end
        return lib.notify({ type = 'error', description = 'Could not take control of the fuel nozzle.' })
    end
    if IsEntityAttached(obj) then DetachEntity(obj, true, true) end
    SetEntityCollision(obj, false, false)
    AttachEntityToEntity(obj, cache.ped, GetPedBoneIndex(cache.ped, 28422),
        0.13, 0.05, 0.02, -80.0, 0.0, 15.0, false, false, false, false, 2, true)
    local netId = NetworkGetNetworkIdFromEntity(obj)
    SetNetworkIdCanMigrate(netId, true)
    TriggerServerEvent('dante_fuel:takeNozzle',
        { x=coords.x, y=coords.y, z=coords.z, heading=GetEntityHeading(pump) },
        GetEntityModel(pump), side, netId)
end
function nozzle.returnAt(pump)
    if not pump or pump == 0 then return end
    if nozzle.heldKey then
        TriggerServerEvent('dante_fuel:returnNozzle', nozzle.heldKey)
        return
    end
    local coords = GetEntityCoords(pump)
    local side = sideFor(pump)
    for key, active in pairs(nozzle.states) do
        if active.state == 'ground'
            and #(vec3(active.pump.x, active.pump.y, active.pump.z) - coords) <= 1.5 then
            side = active.side
            break
        end
    end
    local key = ('%d:%d:%d:%s'):format(math.floor(coords.x*10+0.5), math.floor(coords.y*10+0.5), math.floor(coords.z*10+0.5), side)
    TriggerServerEvent('dante_fuel:returnNozzle', key)
end
function nozzle.insert(vehicle)
    if not vehicle or vehicle == 0 then return end
    local bone = GetEntityBoneIndexByName(vehicle, 'petrolcap')
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, 'petroltank_l') end
    if bone == -1 then bone = GetEntityBoneIndexByName(vehicle, 'petroltank') end
    if bone == -1 then
        return lib.notify({ type = 'error', description = 'This vehicle has no usable fuel-cap attachment point.' })
    end
    local p = GetWorldPositionOfEntityBone(vehicle, bone)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, p.x, p.y, p.z)
    TriggerServerEvent('dante_fuel:insertNozzle', NetworkGetNetworkIdFromEntity(vehicle),
        { x=offset.x, y=offset.y, z=offset.z })
end
function nozzle.remove(vehicle)
    if not vehicle or vehicle == 0 then return end
    TriggerServerEvent('dante_fuel:removeNozzle', NetworkGetNetworkIdFromEntity(vehicle), GetPedBoneIndex(cache.ped, 28422))
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
    if nozzle.isHeld() then
        local ped = PlayerPedId()
        local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, -0.8)
        TriggerServerEvent('dante_fuel:dropNozzle', { x=p.x, y=p.y, z=p.z })
    end
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
