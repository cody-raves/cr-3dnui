local PANEL_ID = nil
local ATTACHED_VEH = nil
local STATUS_THREAD = nil

-- ============================================================
-- FIXED / UNIVERSAL DEMO SETTINGS
-- ============================================================

-- Local (entity-space) placement:
-- X: right (+) / left (-)
-- Y: forward (+) / back (-)
-- Z: up (+) / down (-)
local LOCAL_OFFSET = vector3(0.0, 0.10, 1.70) -- roof center-ish

-- UNIVERSAL FACING:
-- hard-lock localNormal to "left".
local LOCAL_NORMAL = vector3(-1.0, 0.0, 0.0)

-- World panel size (world units)
local PANEL_W = 1.65
local PANEL_H = 0.45

-- Distance-based update culling (transform updates only)
local UPDATE_MAX_DISTANCE = 110.0

-- HARD LOCK: Highest refresh (per-frame) for smooth attachment
local UPDATE_INTERVAL_MS = 0

-- ============================================================

local function notify(msg)
    TriggerEvent('chat:addMessage', {
        color = { 120, 200, 255 },
        multiline = true,
        args = { '3D-NUI Demo', msg }
    })
end

local function getTargetVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh end

    -- Fallback: closest vehicle within 6m
    local p = GetEntityCoords(ped)
    local closest = GetClosestVehicle(p.x, p.y, p.z, 6.0, 0, 70)
    if closest ~= 0 then return closest end
    return 0
end

local function getUiUrl()
    -- Works no matter what your resource folder is named.
    local resName = GetCurrentResourceName()
    return ("nui://%s/ui/index.html"):format(resName)
end

local function cleanup()
    if PANEL_ID then
        exports['cr-3dnui']:EndFocus()
        exports['cr-3dnui']:DestroyPanel(PANEL_ID)
    end
    PANEL_ID = nil
    ATTACHED_VEH = nil
    STATUS_THREAD = nil
end

local function startStatusLoop()
    if STATUS_THREAD then return end
    STATUS_THREAD = true

    CreateThread(function()
        while STATUS_THREAD and PANEL_ID and ATTACHED_VEH and DoesEntityExist(ATTACHED_VEH) do
            local mph = (GetEntitySpeed(ATTACHED_VEH) * 2.236936)
            local gear = GetVehicleCurrentGear(ATTACHED_VEH)
            local eng = GetIsVehicleEngineRunning(ATTACHED_VEH)

            exports['cr-3dnui']:SendMessage(PANEL_ID, {
                type = 'status',
                speed = math.floor(mph + 0.5),
                gear = gear,
                engine = eng,
                interval = UPDATE_INTERVAL_MS
            })

            -- UI updates don't need to be 0ms; transform is already per-frame.
            Wait(250)
        end
    end)
end

local function attachToVehicle(veh)
    cleanup()

    local url = getUiUrl()

    print(("^2[cr-3dnui-demo]^7 attaching url=^3%s^7 offset=(%.2f %.2f %.2f) normal=(%.2f %.2f %.2f) interval=%dms"):format(
        url,
        LOCAL_OFFSET.x, LOCAL_OFFSET.y, LOCAL_OFFSET.z,
        LOCAL_NORMAL.x, LOCAL_NORMAL.y, LOCAL_NORMAL.z,
        UPDATE_INTERVAL_MS
    ))

    PANEL_ID = exports['cr-3dnui']:AttachPanelToEntity({
        entity = veh,
        url = url,

        resW = 1024,
        resH = 512,

        width = PANEL_W,
        height = PANEL_H,
        alpha = 255,
        enabled = true,

        localOffset = LOCAL_OFFSET,
        localNormal = LOCAL_NORMAL,

        -- Rotate the local normal into world space with the vehicle transform
        rotateNormal = true,

        -- HARD LOCK: per-frame attachment updates
        updateInterval = UPDATE_INTERVAL_MS,
        updateMaxDistance = UPDATE_MAX_DISTANCE
    })

    if not PANEL_ID then
        notify('AttachPanelToEntity() failed (ensure cr-3dnui is started + updated).')
        cleanup()
        return false
    end

    ATTACHED_VEH = veh

    exports['cr-3dnui']:SendMessage(PANEL_ID, { type = 'hello' })
    startStatusLoop()

    notify(('Attached panel %s to vehicle %s | refresh=%dms (locked)'):format(
        tostring(PANEL_ID), tostring(veh), UPDATE_INTERVAL_MS
    ))

    return true
end

-- ============================================================
-- COMMANDS
-- ============================================================

-- No args, no options: always best refresh
RegisterCommand('nuiroof', function()
    local veh = getTargetVehicle()
    if veh == 0 or not DoesEntityExist(veh) then
        notify('No vehicle found. Get in a vehicle or stand near one, then run /nuiroof.')
        return
    end

    attachToVehicle(veh)
end, false)

RegisterCommand('nuioff', function()
    if not PANEL_ID then
        notify('Nothing to remove.')
        return
    end
    cleanup()
    notify('Panel removed.')
end, false)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    cleanup()
end)

-- Optional: quick focus toggle so you can test input forwarding if you want.
RegisterCommand('nuifocus', function()
    if not PANEL_ID then
        notify('No panel yet. Run /nuiroof first.')
        return
    end

    if exports['cr-3dnui']:IsFocused() then
        exports['cr-3dnui']:EndFocus()
        notify('Focus ended.')
        return
    end

    exports['cr-3dnui']:BeginFocus(PANEL_ID, {
        allowLook = true,
        exitOnEsc = true,
        exitOnBack = true,
        disableControls = true
    })

    CreateThread(function()
        while exports['cr-3dnui']:IsFocused() do
            exports['cr-3dnui']:FocusTick()
            Wait(0)
        end
    end)

    notify('Focus started. Press ESC/BACKSPACE to exit focus. (/nuifocus toggles)')
end, false)
