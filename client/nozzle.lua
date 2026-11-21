-- Native FiveM nozzle props and rope hoses. The server replicates nozzle state; each client draws its own rope.
local screens = require 'client.screens'
local state = require 'client.state'
local nozzle = { states = {}, heldKey = nil }
local ropes, hoseSegments, holsters, hiddenPumps, groundTargets = {}, {}, {}, {}, {}
local HOSE_MODEL = joaat('whip_hose_seg')
local HOSE_MODEL_NS = joaat('whip_hose_seg_ns')
local HOSE_SEGMENT_LENGTH = 0.25

local function hoseModel()
    return IsModelInCdimage(HOSE_MODEL) and HOSE_MODEL or HOSE_MODEL_NS
end

local function createHoseSegments(key, count)
    if hoseSegments[key] then return end
    local model = hoseModel()
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local props = {}
    for i = 1, count do
        local prop = CreateObjectNoOffset(model, 0.0, 0.0, 0.0, false, false, false)
        if prop and prop ~= 0 then
            SetEntityCollision(prop, false, false)
            FreezeEntityPosition(prop, true)
            SetEntityLodDist(prop, 500)
            props[#props + 1] = prop
        end
    end
    SetModelAsNoLongerNeeded(model)
    hoseSegments[key] = props
end

local function removeHoseSegments(key)
    local props = hoseSegments[key]
    if not props then return end
    for i = 1, #props do
        if DoesEntityExist(props[i]) then DeleteEntity(props[i]) end
    end
    hoseSegments[key] = nil
end

local function updateHoseSegments(key, rope)
    local count = GetRopeVertexCount(rope)
    if not count or count < 2 then return end
    createHoseSegments(key, count - 1)
    local props = hoseSegments[key]
    if not props then return end
    for i = 1, math.min(#props, count - 1) do
        local a, b = GetRopeVertexCoord(rope, i - 1), GetRopeVertexCoord(rope, i)
        local dx, dy, dz = b.x-a.x, b.y-a.y, b.z-a.z
        local len = math.sqrt(dx*dx + dy*dy + dz*dz)
        if len > 0.0001 and DoesEntityExist(props[i]) then
            local fy, fx, fz = dx/len, -dy/len, 0.0
            local rightLen = math.sqrt(fx*fx + fy*fy)
            if rightLen < 0.0001 then fx, fy, rightLen = 1.0, 0.0, 1.0 end
            fx, fy = fx/rightLen, fy/rightLen
            local ux, uy, uz = fy*fz - 0.0*fy, 0.0*fx - fx*fz, fx*fy - fy*fx
            -- Build a stable frame with local +Y along the hose segment.
            local tx, ty, tz = dx/len, dy/len, dz/len
            local rx, ry, rz = ty, -tx, 0.0
            local rl = math.sqrt(rx*rx + ry*ry + rz*rz)
            if rl < 0.0001 then rx, ry, rz, rl = 1.0, 0.0, 0.0, 1.0 end
            rx, ry, rz = rx/rl, ry/rl, rz/rl
            local ux2, uy2, uz2 = ry*tz-rz*ty, rz*tx-rx*tz, rx*ty-ry*tx
            local scale = len / HOSE_SEGMENT_LENGTH
            SetEntityMatrix(props[i], tx*scale, ty*scale, tz*scale,
                rx, ry, rz, ux2, uy2, uz2,
                (a.x+b.x)*0.5, (a.y+b.y)*0.5, (a.z+b.z)*0.5)
        end
    end
end

CreateThread(function()
    while true do
        local active = false
        for key, rope in pairs(ropes) do
            if DoesRopeExist(rope) then
                active = true
                updateHoseSegments(key, rope)
            else
                removeHoseSegments(key)
            end
        end
        Wait(active and 0 or 500)
    end
end)
local NOZZLE = joaat('prop_cs_fuel_nozle')
local HOLSTER = {
    A = { pos = vec3(0.3447, -0.3744, 0.7044), rot = vec3(0.251, -0.076, 0.066) },
    B = { pos = vec3(-0.3447, 0.3655, 0.7044), rot = vec3(0.259, -0.077, -179.934) },
}
local function entityFrom(net)
    if not net or net == 0 then return nil end
    local e = NetworkGetEntityFromNetworkId(net)
    return e and e ~= 0 and DoesEntityExist(e) and e or nil
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
    -- Match Whip's held-prop placement and attachment flags exactly.
    AttachEntityToEntity(obj, ped, bone, 0.13, 0.05, 0.02, -80.0, 0.0, 15.0, true, true, false, true, 1, true)
end

local function attachToVehicle(data)
    local obj, vehicle = entityFrom(data.nozzleNet), entityFrom(data.vehicle)
    if not obj or not vehicle or not takeControl(obj) then return end
    if IsEntityAttached(obj) then DetachEntity(obj, true, true) end
    SetEntityCollision(obj, false, false)
    local off = data.offset or { x=0.0, y=0.0, z=0.0 }
    AttachEntityToEntity(obj, vehicle, 0, off.x, off.y, off.z, off.pitch or -25.0, 0.0, off.yaw or 180.0, false, false, false, false, 2, true)
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

local function removeGroundTarget(data)
    local obj = data and entityFrom(data.nozzleNet)
    if obj and groundTargets[obj] then
        exports['sd-interact']:removeLocalEntity(obj, 'dante_fuel:dropped_nozzle')
        groundTargets[obj] = nil
    end
end

local function addGroundTarget(data)
    if not data or data.state ~= 'ground' then return end
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        local obj
        repeat
            local current = nozzle.states[data.key]
            if not current or current.state ~= 'ground' or current.nozzleNet ~= data.nozzleNet then return end
            obj = entityFrom(data.nozzleNet)
            if not obj then Wait(100) end
        until obj or GetGameTimer() >= deadline
        if not obj or groundTargets[obj] then return end
        groundTargets[obj] = true
        exports['sd-interact']:addLocalEntity(obj, {
            name = 'dante_fuel:dropped_nozzle',
            interactDistance = 2.0,
            options = {{
                name = 'dante_fuel:pickup_dropped_nozzle',
                label = 'Pick up fuel nozzle',
                icon = 'fa-solid fa-hand',
                canInteract = function()
                    local current = nozzle.states[data.key]
                    return current ~= nil and current.state == 'ground'
                        and current.nozzleNet == data.nozzleNet and not nozzle.isHeld()
                        and not cache.vehicle and not state.isFueling
                end,
                onSelect = function()
                    TriggerServerEvent('dante_fuel:pickupDroppedNozzle', data.key)
                end,
            }},
        })
    end)
end

local function deleteNetworkNozzle(data)
    local obj = entityFrom(data.nozzleNet)
    if obj and takeControl(obj) then DeleteEntity(obj) end
end

local function wakeTornPump(data)
    if not data.torn or not data.pumpNet then return end
    local copy = entityFrom(data.pumpNet)
    if copy and takeControl(copy) then
        SetEntityCollision(copy, true, true)
        SetEntityHasGravity(copy, true)
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
    removeHoseSegments(key)
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
        local rope = AddRope(start.x, start.y, start.z, 0.0, 0.0, 0.0, 3.0, 4, 3.0, 0.1, 1.0, false, false, false, 1.0, false, 0)
        if rope and rope ~= 0 then
            AttachEntitiesToRope(rope, pump, obj, start.x, start.y, start.z,
                finish.x, finish.y, finish.z, 6.0, false, false, nil, nil)
            RopeForceLength(rope, 3.0)
            ropes[data.key] = rope
            CreateThread(function()
                local deadline = GetGameTimer() + 3000
                while GetGameTimer() < deadline and DoesRopeExist(rope) do
                    updateHoseSegments(data.key, rope)
                    if hoseSegments[data.key] then return end
                    Wait(100)
                end
            end)
            wakeTornPump(data)
        end
    end
end
local function apply(data)
    if type(data) ~= 'table' or not data.key then return end
    local old = nozzle.states[data.key]
    if old then removeGroundTarget(old) end
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
    if not data.torn then restorePump(data.key) end
    setHolster(data, false)
    if data.state == 'hand' then
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'nozzle_out')
    elseif data.state == 'ground' then
        screens.setPumpState(vec3(data.pump.x, data.pump.y, data.pump.z), 'return_nozzle')
        addGroundTarget(data)
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
    local networkDeadline = GetGameTimer() + 1500
    while (not NetworkGetEntityIsNetworked(obj) or netId == 0) and GetGameTimer() < networkDeadline do
        Wait(0)
        netId = NetworkGetNetworkIdFromEntity(obj)
    end
    if not NetworkGetEntityIsNetworked(obj) or netId == 0 then
        DeleteEntity(obj)
        return
    end
    SetNetworkIdCanMigrate(netId, true)
    Wait(100)
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
        0.13, 0.05, 0.02, -80.0, 0.0, 15.0, true, true, false, true, 1, true)
    local netId = NetworkGetNetworkIdFromEntity(obj)
    local networkDeadline = GetGameTimer() + 1500
    while (not NetworkGetEntityIsNetworked(obj) or netId == 0) and GetGameTimer() < networkDeadline do
        Wait(0)
        netId = NetworkGetNetworkIdFromEntity(obj)
    end
    if not NetworkGetEntityIsNetworked(obj) or netId == 0 then
        DeleteEntity(obj)
        return lib.notify({ type = 'error', description = 'The fuel nozzle could not be networked.' })
    end
    SetNetworkIdCanMigrate(netId, true)
    Wait(100)
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
local NOZZLE_SPOUT = vec3(0.002, 0.241, 0.160)
local NOZZLE_IN_PITCH = -25.0
local NOZZLE_IN_DEPTH = 0.04

local function turned(point, pitch, yaw)
    local p, a = math.rad(pitch), math.rad(yaw)
    local y1 = point.y * math.cos(p) - point.z * math.sin(p)
    local z1 = point.y * math.sin(p) + point.z * math.cos(p)
    return vec3(
        point.x * math.cos(a) - y1 * math.sin(a),
        point.x * math.sin(a) + y1 * math.cos(a),
        z1
    )
end

local function getFillerPoint(vehicle)
    local model = GetEntityModel(vehicle)
    local heading = GetEntityHeading(vehicle)

    -- Use the real cap bone whenever the vehicle has one.
    local cap = GetEntityBoneIndexByName(vehicle, 'petrolcap')
    if cap ~= -1 then
        local point = GetWorldPositionOfEntityBone(vehicle, cap)
        local localPoint = GetOffsetFromEntityGivenWorldCoords(vehicle, point.x, point.y, point.z)
        local side = localPoint.x < 0.0 and -1.0 or 1.0
        return point, heading + (side * 90.0)
    end

    -- Whip's fallback: find the filler above the rear wheel, at door-handle height,
    -- then ray from outside the vehicle toward its centre to land on the actual skin.
    local minDim, maxDim = GetModelDimensions(model)
    local leftTank = GetEntityBoneIndexByName(vehicle, 'petroltank_l') ~= -1
    local rightTank = GetEntityBoneIndexByName(vehicle, 'petroltank_r') ~= -1
    local side = leftTank ~= rightTank and (leftTank and -1.0 or 1.0)
        or ((model % 2 == 0) and -1.0 or 1.0)

    local handles = side < 0.0
        and { 'handle_dside_r', 'handle_dside_f' }
        or { 'handle_pside_r', 'handle_pside_f' }
    local height
    for i = 1, #handles do
        local bone = GetEntityBoneIndexByName(vehicle, handles[i])
        if bone ~= -1 then
            height = GetOffsetFromEntityGivenWorldCoords(
                vehicle,
                GetWorldPositionOfEntityBone(vehicle, bone).x,
                GetWorldPositionOfEntityBone(vehicle, bone).y,
                GetWorldPositionOfEntityBone(vehicle, bone).z
            ).z
            break
        end
    end
    if not height then
        height = minDim.z + math.min(1.0, (maxDim.z - minDim.z) * 0.5)
    end

    local wheelName = side < 0.0 and 'wheel_lr' or 'wheel_rr'
    local wheel = GetEntityBoneIndexByName(vehicle, wheelName)
    local y
    if wheel ~= -1 then
        local wheelPos = GetOffsetFromEntityGivenWorldCoords(
            vehicle,
            GetWorldPositionOfEntityBone(vehicle, wheel).x,
            GetWorldPositionOfEntityBone(vehicle, wheel).y,
            GetWorldPositionOfEntityBone(vehicle, wheel).z
        )
        y = wheelPos.y
    else
        y = minDim.y + (maxDim.y - minDim.y) * 0.25
    end

    local x = side < 0.0 and minDim.x or maxDim.x
    local outside = GetOffsetFromEntityInWorldCoords(vehicle, x + side, y, height)
    local inside = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, y, height)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        outside.x, outside.y, outside.z, inside.x, inside.y, inside.z, 2, cache.ped, 7
    )
    local _, hit, hitPosition, _, hitEntity = GetShapeTestResult(ray)
    local point
    if hit == 1 and hitEntity == vehicle then
        point = hitPosition
    else
        point = GetOffsetFromEntityInWorldCoords(vehicle, x, y, height)
    end

    return point, heading + (side < 0.0 and 90.0 or -90.0)
end

function nozzle.insert(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local held = nozzle.heldKey and nozzle.states[nozzle.heldKey]
    local obj = held and held.state == 'hand' and entityFrom(held.nozzleNet)
    if not obj then return end

    local point, heading = getFillerPoint(vehicle)
    local vehicleHeading = GetEntityHeading(vehicle)
    local r = math.rad(heading)
    -- Put the spout tip just through the filler opening, facing inward.
    local tipWorld = vec3(
        point.x + math.sin(r) * NOZZLE_IN_DEPTH,
        point.y - math.cos(r) * NOZZLE_IN_DEPTH,
        point.z
    )
    local tip = GetOffsetFromEntityGivenWorldCoords(vehicle, tipWorld.x, tipWorld.y, tipWorld.z)
    local yaw = (heading + 180.0 - vehicleHeading) % 360.0
    local offset = tip - turned(NOZZLE_SPOUT, NOZZLE_IN_PITCH, yaw)

    TriggerServerEvent('dante_fuel:insertNozzle', NetworkGetNetworkIdFromEntity(vehicle),
        { x=offset.x, y=offset.y, z=offset.z, pitch=NOZZLE_IN_PITCH, yaw=yaw })
end
function nozzle.remove(vehicle)
    if not vehicle or vehicle == 0 then return end
    TriggerServerEvent('dante_fuel:removeNozzle', NetworkGetNetworkIdFromEntity(vehicle), GetPedBoneIndex(cache.ped, 28422))
end
function nozzle.isHeld()
    local data = nozzle.heldKey and nozzle.states[nozzle.heldKey]
    return data ~= nil and data.state == 'hand'
        and data.holder == GetPlayerServerId(PlayerId())
end

local function samePump(data, pump)
    if not data or not data.pump or not pump or pump == 0 or not DoesEntityExist(pump) then return false end
    local p = GetEntityCoords(pump)
    return #(vec3(data.pump.x, data.pump.y, data.pump.z) - p) <= 1.5
end

-- A pump side is occupied whenever its nozzle is out, on the ground, or in a vehicle.
function nozzle.hasNozzleAt(pump)
    for _, data in pairs(nozzle.states) do
        if data.state ~= 'holstered' and samePump(data, pump) then return true end
    end
    return false
end

-- Return belongs only to the pump whose nozzle the player is actually holding.
function nozzle.isHeldAt(pump)
    local data = nozzle.heldKey and nozzle.states[nozzle.heldKey]
    return nozzle.isHeld() and samePump(data, pump)
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
    for obj in pairs(groundTargets) do
        if DoesEntityExist(obj) then exports['sd-interact']:removeLocalEntity(obj, 'dante_fuel:dropped_nozzle') end
    end
    groundTargets = {}
    for key in pairs(hiddenPumps) do restorePump(key) end
end)
return nozzle
