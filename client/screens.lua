-- Whip Fuel pump LCD renderer adapted for ox_fuel.
-- Uses FiveM DUI + DrawTexturedPoly directly; no whip_core / WorldQuad dependency.

local SCREEN_TXD, SCREEN_TEX = 'ox_fuel_pump_dui', 'screen'
local ATLAS_W, ATLAS_H = 1280, 1024
local SCREEN_W, SCREEN_H = 0.38, 0.304
local SCREEN_RANGE = 20.0
local SCREEN_THANKS_MS = 4000
local SCREEN_IDLE_MS = 15000
local SCREEN_RETRY_MS = 3000

local CELLS = { { 0, 0, 640, 512 } }
for i = 0, 3 do CELLS[#CELLS + 1] = { 640 + (i % 2) * 320, (i // 2) * 256, 320, 256 } end
for i = 0, 7 do CELLS[#CELLS + 1] = { (i % 4) * 320, 512 + (i // 4) * 256, 320, 256 } end
for _, cell in ipairs(CELLS) do
    cell.u0 = cell[1] / ATLAS_W
    cell.v0 = cell[2] / ATLAS_H
    cell.u1 = (cell[1] + cell[3]) / ATLAS_W
    cell.v1 = (cell[2] + cell[4]) / ATLAS_H
end

-- LCD offsets are shared by Whip's four modern pump variants (1a / 1b / 1c / 1d).
local SCREEN_AT = {
    A = { x = -0.2744, y = -0.2419, z = 1.249, right = 1.0 },
    B = { x = 0.2744, y = 0.2419, z = 1.249, right = -1.0 },
}

local PUMP_MODELS = {
    { name = 'prop_gas_pump_1a', hash = `prop_gas_pump_1a`, brand = 'RON' },
    { name = 'prop_gas_pump_1b', hash = `prop_gas_pump_1b`, brand = 'GLOBE OIL' },
    { name = 'prop_gas_pump_1c', hash = `prop_gas_pump_1c`, brand = 'LTD' },
    { name = 'prop_gas_pump_1d', hash = `prop_gas_pump_1d`, brand = 'XERO' },
}

local dui
local screenUp = false
local screenRefusedAt = -SCREEN_RETRY_MS
local screenWantedAt = 0
local runtimeTxd
local activePump
local activeBrand = 'RON'
local activeMessage = { state = 'idle' }
local thanksAt
local drawing = false

local function sendCell(cell, message)
    if not dui or not screenUp then return end
    message.cell = cell - 1
    SendDuiMessage(dui, json.encode(message))
end

local function sendCurrentState()
    if not screenUp or not activePump then return end
    local pos = GetEntityCoords(activePump)
    for cell, side in ipairs({ 'A', 'B' }) do
        local number = (math.floor(math.abs(pos.x) + math.abs(pos.y)) % 8 + 1) * 2 - (side == 'A' and 1 or 0)
        local message = {}
        for k, v in pairs(activeMessage) do message[k] = v end
        message.pump = number
        message.brand = activeBrand
        sendCell(cell, message)
    end
end

local function releaseDui()
    if dui then DestroyDui(dui) end
    dui = nil
    runtimeTxd = nil
    screenUp = false
end

local function ensureDui()
    if dui then return true end
    if GetGameTimer() - screenRefusedAt < SCREEN_RETRY_MS then return false end

    local cells = {}
    for i, cell in ipairs(CELLS) do
        cells[i] = ('%d,%d,%d,%d'):format(cell[1], cell[2], cell[3], cell[4])
    end

    local url = ('nui://%s/html/pump3d/pump_lcd.html?atlas=%dx%d&cells=%s'):format(
        GetCurrentResourceName(), ATLAS_W, ATLAS_H, table.concat(cells, ';'))
    local browser = CreateDui(url, ATLAS_W, ATLAS_H)
    if not browser or browser == 0 then
        screenRefusedAt = GetGameTimer()
        return false
    end

    dui = browser
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while dui == browser and not IsDuiAvailable(browser) and GetGameTimer() < deadline do
            Wait(50)
        end

        if dui ~= browser then return end
        if not IsDuiAvailable(browser) then
            screenRefusedAt = GetGameTimer()
            releaseDui()
            return
        end

        runtimeTxd = CreateRuntimeTxd(SCREEN_TXD)
        CreateRuntimeTextureFromDuiHandle(runtimeTxd, SCREEN_TEX, GetDuiHandle(browser))
        screenUp = true
        sendCurrentState()
    end)

    return true
end

local function findPump(coords)
    if not coords then return nil end

    for i = 1, #PUMP_MODELS do
        local model = PUMP_MODELS[i]
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, 1.25, model.hash, false, false, false)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            return entity, model.brand
        end
    end
end

local function screenQuad(pump, side)
    local at = SCREEN_AT[side]
    local forward, right, up, position = GetEntityMatrix(pump)

    local centre = vector3(
        position.x + right.x * at.x + forward.x * at.y + up.x * at.z,
        position.y + right.y * at.x + forward.y * at.y + up.y * at.z,
        position.z + right.z * at.x + forward.z * at.y + up.z * at.z
    )
    local across = vector3(right.x * at.right, right.y * at.right, right.z * at.right)
    local vertical = vector3(up.x, up.y, up.z)
    local halfW, halfH = SCREEN_W * 0.5, SCREEN_H * 0.5

    return {
        centre - across * halfW + vertical * halfH, -- top left
        centre + across * halfW + vertical * halfH, -- top right
        centre - across * halfW - vertical * halfH, -- bottom left
        centre + across * halfW - vertical * halfH, -- bottom right
    }
end

local function drawTriangle(a, b, c, u1, v1, u2, v2, u3, v3)
    DrawTexturedPoly(
        a.x, a.y, a.z,
        b.x, b.y, b.z,
        c.x, c.y, c.z,
        255, 255, 255, 255,
        SCREEN_TXD, SCREEN_TEX,
        u1, v1, 0.0, u2, v2, 0.0, u3, v3, 0.0
    )
end

local function drawScreen(pump, side, cellIndex)
    local cell = CELLS[cellIndex]
    local quad = screenQuad(pump, side)
    -- Reversed winding is required for the world-space texture to face outward.
    drawTriangle(quad[1], quad[3], quad[2], cell.u0, cell.v0, cell.u0, cell.v1, cell.u1, cell.v0)
    drawTriangle(quad[2], quad[3], quad[4], cell.u1, cell.v0, cell.u0, cell.v1, cell.u1, cell.v1)
end

local function startDrawLoop()
    if drawing then return end
    drawing = true

    CreateThread(function()
        while activePump do
            if not DoesEntityExist(activePump) then
                activePump = nil
                            break
            end

            local distance = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(activePump))
            if distance <= SCREEN_RANGE and screenUp then
                drawScreen(activePump, 'A', 1)
                drawScreen(activePump, 'B', 2)
                Wait(0)
            else
                Wait(200)
            end

            if thanksAt and GetGameTimer() - thanksAt >= SCREEN_THANKS_MS then
                activePump = nil
                            thanksAt = nil
                screenWantedAt = GetGameTimer()
                break
            end
        end
        drawing = false
    end)
end

local screens = {}

---@param pumpCoords vector3?
---@param state string
---@param data table?
function screens.setPumpState(pumpCoords, state, data)
    if state == 'off' then
        if screenUp then
            sendCell(1, { state = 'off' })
            sendCell(2, { state = 'off' })
        end
        activePump = nil
            thanksAt = nil
        screenWantedAt = GetGameTimer()
        return
    end

    local pump, brand
    if activePump and DoesEntityExist(activePump) and pumpCoords
        and #(GetEntityCoords(activePump) - pumpCoords) < 1.25 then
        pump, brand = activePump, activeBrand
    else
        pump, brand = findPump(pumpCoords)
    end
    if not pump then return false end

    activePump = pump
    activeBrand = brand or 'RON'
    activeMessage = { state = state }
    if data then
        for k, v in pairs(data) do activeMessage[k] = v end
    end

    if state == 'thanks' or state == 'return_nozzle' then
        thanksAt = GetGameTimer()
    else
        thanksAt = nil
    end

    screenWantedAt = GetGameTimer()
    ensureDui()
    sendCurrentState()
    startDrawLoop()
    return true
end

CreateThread(function()
    while true do
        if not activePump and dui and GetGameTimer() - screenWantedAt > SCREEN_IDLE_MS then
            releaseDui()
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    activePump = nil
    releaseDui()
end)

return screens
