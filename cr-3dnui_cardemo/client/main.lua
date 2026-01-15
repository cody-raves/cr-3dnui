-- cr-3dnui cardemo
--
-- Commands:
--   /nuiroof   -> attach panel directly to your current/nearby vehicle (roof)
--   /nuidash   -> spawn a monitor prop, attach it to vehicle dash area, then attach panel to that prop
--   /nuikey    -> toggle key2dui cursor (mouse inside DUI) + click forwarding
--   /nuioff    -> cleanup
--   /nuipage <all|spd|gear|eng> -> change UI page (optional; can also click buttons)
--
-- Notes:
-- - This demo is framework-agnostic.
-- - Requires cr-3dnui to be started.- Dash mount values below are tuned for *Elegy2 + prop_monitor_01a* only; retune for other cars/props.


local PANEL_ID = nil
local ATTACHED_VEH = nil
local ATTACHED_PROP = nil
local STATUS_THREAD = nil
local CURRENT_ATTACH_MODE = nil -- 'roof' | 'dashprop' | 'dashstable'

-- ============================================================
-- MODE A: Panel attached directly to the vehicle
-- ============================================================
local ROOF_OFFSET = vector3(0.0, 0.10, 1.70)
local ROOF_NORMAL = vector3(1.0, 0.0, 0.0)
local ROOF_UP     = vector3(0.0, 0.0, 1.0)
local ROOF_W, ROOF_H = 1.65, 0.45

-- ============================================================
-- MODE B: Prop mounted to vehicle dash + panel attached to prop
-- ============================================================
local DASH_PROP_MODEL = `prop_monitor_01a`

-- Where the prop is mounted relative to the vehicle (bone-space).
-- You WILL want to tweak this per vehicle (that's the point of the demo).
-- ⚠️ TUNED VALUES (DEMO-SPECIFIC)
-- These offsets/rotations were tuned for:
--   - Vehicle: Elegy2 (spawn name: elegy2)
--   - Prop:    prop_monitor_01a
-- Every vehicle has different interior bone positions, and every prop has different model origin/rotation.
-- If you change the vehicle OR the prop model, you MUST retune using the built-in dash tuner:
--   /nuidashprop (jitter reference) -> /dashtune -> /dashprint
local DASH_BONE = 'seat_dside_f'
local DASH_PROP_OFFSET = vector3(0.4500, 0.5350, 0.1850)  -- right, forward, up
local DASH_PROP_ROT    = vector3(2.3500, -0.5000, -34.9000)      -- pitch, roll, yaw

-- Panel placement on prop_monitor_01a (from the alignment work)
local MONITOR_LOCAL_OFFSET = vector3(0.0000, -0.0650, 0.3120)
local MONITOR_LOCAL_NORMAL = vector3(-0.9982, 0.0000, 0.0600)
local MONITOR_LOCAL_UP_BASE = vector3(0.0, 1.0, 0.0) -- panel 'top' direction in prop-local space

-- Extra local rotation for the panel (relative to the prop), in degrees.
local PANEL_LOCAL_ROT = vector3(0.0000, 0.0000, 0.0000)
local MONITOR_NORMAL_BASE = MONITOR_LOCAL_NORMAL
local MONITOR_W, MONITOR_H = 0.43, 0.31

-- Pre-baked STABLE values (vehicle-local) for Elegy2 + prop_monitor_01a using the tuned settings above.
-- These are only used as a fallback when the prop entity isn't available to bake from.
-- In normal use (/nuidash), we spawn+attach the prop first and bake from the actual prop transform.
local DASH_BAKED_OFFSET_DEFAULT = vector3(-0.0286, 0.2505, 0.6777)
local DASH_BAKED_NORMAL_DEFAULT = vector3(-0.8197, -0.5725, 0.0190)
local DASH_BAKED_UP_DEFAULT     = vector3(-0.0206, -0.0037, -0.9998)

-- ============================================================
-- Shared
-- ============================================================
local UPDATE_MAX_DISTANCE = 110.0
local UPDATE_INTERVAL_MS = 0

local KEY2DUI_ACTIVE = false
local CUR_U, CUR_V = 0.5, 0.5
local CUR_SPEED = 0.020 -- cursor speed per frame from look-axis input
local CURSOR_VISIBLE = false

local function notify(msg)
  TriggerEvent('chat:addMessage', {
    color = { 120, 200, 255 },
    multiline = true,
    args = { '3D-NUI Demo', msg }
  })
end

local function clamp01(v)
  if v < 0.0 then return 0.0 end
  if v > 1.0 then return 1.0 end
  return v
end

-- ============================================================
-- Dash "roof-style" stability helpers
-- Panel attaches to VEHICLE (like /nuiroof) for zero jitter.
-- Prop stays bone-attached for visuals.
-- ============================================================
local function deg2rad(d) return d * 0.017453292519943295 end

local function rotVecZYX(v, rotDeg)
  local rx = deg2rad(rotDeg.x)
  local ry = deg2rad(rotDeg.y)
  local rz = deg2rad(rotDeg.z)

  local x, y, z = v.x, v.y, v.z

  -- Z (yaw)
  local cz, sz = math.cos(rz), math.sin(rz)
  x, y = (x * cz - y * sz), (x * sz + y * cz)

  -- Y (roll)
  local cy, sy = math.cos(ry), math.sin(ry)
  x, z = (x * cy + z * sy), (-x * sy + z * cy)

  -- X (pitch)
  local cx, sx = math.cos(rx), math.sin(rx)
  y, z = (y * cx - z * sx), (y * sx + z * cx)

  return vector3(x, y, z)
end

-- Simple 2D text helper
local function fmt4(n) return string.format('%.4f', n) end
local function fmtVec3(v) return ('(%s, %s, %s)'):format(fmt4(v.x), fmt4(v.y), fmt4(v.z)) end

local function drawTxt(x, y, scale, text)
  SetTextFont(0)
  SetTextProportional(1)
  SetTextScale(scale, scale)
  SetTextColour(255, 255, 255, 215)
  SetTextOutline()
  SetTextDropShadow(1, 0, 0, 0, 255)
  SetTextEntry('STRING')
  AddTextComponentString(text)
  DrawText(x, y)
end

local function vNormalize(v)
  local mag = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
  if mag <= 0.000001 then return vector3(0.0, 1.0, 0.0) end
  return vector3(v.x/mag, v.y/mag, v.z/mag)
end

local function vNeg(v)
  return vector3(-v.x, -v.y, -v.z)
end


-- Build a stable "up" vector that is guaranteed to be perpendicular to the given normal.
-- This prevents 90°/sideways rotations when the supplied up has any component along the normal.
local function vDot(a, b)
  return a.x*b.x + a.y*b.y + a.z*b.z
end

local function vCross(a, b)
  return vector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )
end

local function vScale(v, s)
  return vector3(v.x*s, v.y*s, v.z*s)
end

local function vSub(a, b)
  return vector3(a.x-b.x, a.y-b.y, a.z-b.z)
end

local function makeOrthoUp(normal, preferredUp)
  normal = vNormalize(normal)
  preferredUp = vNormalize(preferredUp)

  -- project preferredUp onto plane orthogonal to normal
  local proj = vSub(preferredUp, vScale(normal, vDot(normal, preferredUp)))
  local len = math.sqrt(proj.x*proj.x + proj.y*proj.y + proj.z*proj.z)

  if len < 0.0001 then
    -- fallback axis that isn't parallel to normal
    local fallback = (math.abs(normal.z) < 0.99) and vector3(0.0, 0.0, 1.0) or vector3(0.0, 1.0, 0.0)
    proj = vSub(fallback, vScale(normal, vDot(normal, fallback)))
  end

  return vNormalize(proj)
end


local function getPanelLocalNormal()
  return vNormalize(rotVecZYX(MONITOR_NORMAL_BASE, PANEL_LOCAL_ROT))
end


local function getPanelLocalUp()
  -- Preferred "up" in prop-local space (after PANEL_LOCAL_ROT), then orthogonalize
  -- against the panel normal so the UI doesn't end up sideways.
  local preferredUp = vNormalize(rotVecZYX(MONITOR_LOCAL_UP_BASE, PANEL_LOCAL_ROT))
  local n = getPanelLocalNormal()

  local up = makeOrthoUp(n, preferredUp)

  -- If the UI is rotated 90° in-plane (top points right), rotate Up 90° around the normal.
  -- This is equivalent to swapping "up" with the panel's "right" axis.
  -- If you ever need the opposite direction, change this to vNeg(vCross(n, up)).
  up = vNormalize(vCross(n, up))

  return up
end



local function computeDashStableTransform()
  -- Bake from the ACTUAL prop entity transform (bone space -> vehicle space),
  -- so /nuidash matches /nuidashprop 1:1 even though the prop is bone-attached.
  -- Returns: vehicleLocalOffset, vehicleLocalNormal, vehicleLocalUp
  if ATTACHED_VEH and ATTACHED_PROP and DoesEntityExist(ATTACHED_VEH) and DoesEntityExist(ATTACHED_PROP) then
    -- Panel position: prop-local -> world -> vehicle-local
    local wx, wy, wz = table.unpack(GetOffsetFromEntityInWorldCoords(
      ATTACHED_PROP,
      MONITOR_LOCAL_OFFSET.x, MONITOR_LOCAL_OFFSET.y, MONITOR_LOCAL_OFFSET.z
    ))
    local localOffset = GetOffsetFromEntityGivenWorldCoords(ATTACHED_VEH, wx, wy, wz)

    -- Panel axes in PROP local space (includes PANEL_LOCAL_ROT from the tuner)
    local propLocalNormal = getPanelLocalNormal()
    local propLocalUp     = getPanelLocalUp()

    -- Convert prop-local directions -> world directions
    local pr, pf, pu, _pp = GetEntityMatrix(ATTACHED_PROP) -- right, forward, up, pos (each is vector3)

    local worldNormal = vector3(
      pr.x * propLocalNormal.x + pf.x * propLocalNormal.y + pu.x * propLocalNormal.z,
      pr.y * propLocalNormal.x + pf.y * propLocalNormal.y + pu.y * propLocalNormal.z,
      pr.z * propLocalNormal.x + pf.z * propLocalNormal.y + pu.z * propLocalNormal.z
    )

    local worldUp = vector3(
      pr.x * propLocalUp.x + pf.x * propLocalUp.y + pu.x * propLocalUp.z,
      pr.y * propLocalUp.x + pf.y * propLocalUp.y + pu.y * propLocalUp.z,
      pr.z * propLocalUp.x + pf.z * propLocalUp.y + pu.z * propLocalUp.z
    )

    -- Convert world directions -> VEHICLE local directions
    local vr, vf, vu, _vp = GetEntityMatrix(ATTACHED_VEH)

    local localNormal = vector3(
      (worldNormal.x * vr.x + worldNormal.y * vr.y + worldNormal.z * vr.z),
      (worldNormal.x * vf.x + worldNormal.y * vf.y + worldNormal.z * vf.z),
      (worldNormal.x * vu.x + worldNormal.y * vu.y + worldNormal.z * vu.z)
    )
    localNormal = vNormalize(localNormal)

    local localUp = vector3(
      (worldUp.x * vr.x + worldUp.y * vr.y + worldUp.z * vr.z),
      (worldUp.x * vf.x + worldUp.y * vf.y + worldUp.z * vf.z),
      (worldUp.x * vu.x + worldUp.y * vu.y + worldUp.z * vu.z)
    )
    localUp = vNormalize(localUp)
    localUp = makeOrthoUp(localNormal, localUp)

    return localOffset, localNormal, localUp
  end

  -- FALLBACK: use the pre-baked defaults (vehicle-local) for this demo setup.
  -- If you change vehicle or prop, retune and rely on the prop-bake path above.
  return DASH_BAKED_OFFSET_DEFAULT, vNormalize(DASH_BAKED_NORMAL_DEFAULT), vNormalize(DASH_BAKED_UP_DEFAULT)
end


local function reqModel(model)
  if not IsModelInCdimage(model) then return false end
  RequestModel(model)
  local t = GetGameTimer() + 5000
  while not HasModelLoaded(model) do
    Wait(0)
    if GetGameTimer() > t then return false end
  end
  return true
end

local function getTargetVehicle()
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh ~= 0 then return veh end

  local p = GetEntityCoords(ped)
  local closest = GetClosestVehicle(p.x, p.y, p.z, 6.0, 0, 70)
  if closest ~= 0 then return closest end
  return 0
end

local function getUiUrl()
  local resName = GetCurrentResourceName()
  return ('nui://%s/ui/index.html'):format(resName)
end

local function cleanup()
  KEY2DUI_ACTIVE = false
  CURSOR_VISIBLE = false

  if PANEL_ID then
    exports['cr-3dnui']:DestroyPanel(PANEL_ID)
  end

  PANEL_ID = nil
  ATTACHED_VEH = nil

  if ATTACHED_PROP and DoesEntityExist(ATTACHED_PROP) then
    DeleteEntity(ATTACHED_PROP)
  end
  ATTACHED_PROP = nil

  STATUS_THREAD = nil
end

local function sendCursor(show)
  if not PANEL_ID then return end
  if show == nil then show = CURSOR_VISIBLE end
  exports['cr-3dnui']:SendMessage(PANEL_ID, {
    type = 'dui_cursor',
    show = show and true or false,
    u = CUR_U,
    v = CUR_V,
  })
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
        engine = eng and true or false,
      })

      Wait(250)
    end
  end)
end

-- ============================================================
-- Attach mode A: direct to vehicle
-- ============================================================
local function attachPanelToVehicle(veh)
  cleanup()

  local url = getUiUrl()

  PANEL_ID = exports['cr-3dnui']:AttachPanelToEntity({
    entity = veh,
    url = url,

    resW = 1024,
    resH = 512,

    width = ROOF_W,
    height = ROOF_H,
    alpha = 255,
    enabled = true,

    localOffset = ROOF_OFFSET,
    localNormal = ROOF_NORMAL,
    localUp     = vector3(-(ROOF_UP).x, -(ROOF_UP).y, -(ROOF_UP).z),

    rotateNormal = true,

    faceCamera = false,

    frontOnly  = false,
    zOffset    = 0.01,
    updateInterval = UPDATE_INTERVAL_MS,
    updateMaxDistance = UPDATE_MAX_DISTANCE,
  })

  if not PANEL_ID then
    notify('AttachPanelToEntity() failed (ensure cr-3dnui is started + updated).')
    cleanup()
    return false
  end

  ATTACHED_VEH = veh
  CURRENT_ATTACH_MODE = 'roof'

  exports['cr-3dnui']:SendMessage(PANEL_ID, {
    type = 'hello',
    mode = 'roof'
  })

  startStatusLoop()

  notify(('Attached panel %s to vehicle %s (roof)'):format(tostring(PANEL_ID), tostring(veh)))
  return true
end

-- ============================================================
-- Attach mode B: prop to dash + panel to prop
-- ============================================================
local function spawnAndAttachProp(veh)
  if not reqModel(DASH_PROP_MODEL) then
    notify('Failed to load prop model for dash mount.')
    return 0
  end

  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)

  local prop = CreateObjectNoOffset(DASH_PROP_MODEL, p.x, p.y, p.z, true, false, false)

  local boneIndex = GetEntityBoneIndexByName(veh, DASH_BONE)
  if boneIndex == -1 then
    boneIndex = GetEntityBoneIndexByName(veh, 'chassis')
    DASH_BONE = 'chassis'
  end

  -- Attach in bone space
  AttachEntityToEntity(
    prop,
    veh,
    boneIndex,
    DASH_PROP_OFFSET.x, DASH_PROP_OFFSET.y, DASH_PROP_OFFSET.z,
    DASH_PROP_ROT.x, DASH_PROP_ROT.y, DASH_PROP_ROT.z,
    true,  -- p9 useSoftPinning
    true,  -- collision
    false, -- isPed
    true,  -- fixedRot
    2,     -- vertexIndex
    true   -- usePhys
  )

  SetModelAsNoLongerNeeded(DASH_PROP_MODEL)
  return prop
end

local function attachPanelToDashProp(veh)
  cleanup()

  ATTACHED_PROP = spawnAndAttachProp(veh)
  if ATTACHED_PROP == 0 or not DoesEntityExist(ATTACHED_PROP) then
    notify('Failed to spawn/attach dash prop.')
    cleanup()
    return false
  end

  local url = getUiUrl()

  local n = vNeg(getPanelLocalNormal())
  local u = makeOrthoUp(n, getPanelLocalUp())

  PANEL_ID = exports['cr-3dnui']:AttachPanelToEntity({
    entity = ATTACHED_PROP,
    url = url,

    resW = 1024,
    resH = 768,

    width = MONITOR_W,
    height = MONITOR_H,
    alpha = 255,
    enabled = true,

    localOffset = MONITOR_LOCAL_OFFSET,
    localNormal = n,
    localUp     = u,

    rotateNormal = true,
    faceCamera = false,

    -- Helpers from the library update:
    depthCompensation = 'screen',
    zOffset    = -0.01,
    frontOnly = false,
    frontDotMin = 0.0,
    updateInterval = UPDATE_INTERVAL_MS,
    updateMaxDistance = UPDATE_MAX_DISTANCE,
  })


  if not PANEL_ID then
    notify('AttachPanelToEntity() failed on prop (ensure cr-3dnui is started + updated).')
    cleanup()
    return false
  end

  ATTACHED_VEH = veh

  exports['cr-3dnui']:SendMessage(PANEL_ID, {
    type = 'hello',
    mode = 'dashprop'
  })

  startStatusLoop()

  notify(('Mounted prop + panel %s to vehicle %s (bone=%s)'):format(tostring(PANEL_ID), tostring(veh), DASH_BONE))
  return true
end

-- ============================================================
-- Dash stable mode:
--   - PROP is attached to the dash bone (visual only)
--   - PANEL is attached to the VEHICLE (roof-style stable) using baked offset/normal
-- ============================================================
local function attachPanelToDashStable(veh)
  cleanup()

  -- Spawn prop for visuals (bone-attached)
  ATTACHED_PROP = spawnAndAttachProp(veh)
  if ATTACHED_PROP == 0 or not DoesEntityExist(ATTACHED_PROP) then
    notify('Failed to spawn/attach dash prop (visual).')
    cleanup()
    return false
  end

  local url = getUiUrl()
  local bakedOffset, bakedNormal, bakedUp = computeDashStableTransform()

  -- Convert the /nuidashprop (prop-attached) pose into a VEHICLE-local pose,
  -- then push the panel slightly out along its facing normal so it doesn't sit inside the prop mesh.
  local n = vNeg(bakedNormal)
  local u = makeOrthoUp(n, bakedUp)
  local SURFACE_EPSILON = -0.0054
  local bakedOffsetOut = bakedOffset + vScale(n, SURFACE_EPSILON)

  PANEL_ID = exports['cr-3dnui']:AttachPanelToEntity({
    entity = veh,
    url = url,

    resW = 1024,
    resH = 768,

    width = MONITOR_W,
    height = MONITOR_H,
    alpha = 255,
    enabled = true,

    -- IMPORTANT: attach like roof (vehicle-root), but positioned to line up with the prop
    localOffset = bakedOffsetOut,
    localNormal = n,
    localUp     = u,

    rotateNormal = true,
    faceCamera = false,

    frontOnly  = false,
    zOffset    = 0.0,

    updateMaxDistance = UPDATE_MAX_DISTANCE,
    updateInterval = UPDATE_INTERVAL_MS
  })


  if not PANEL_ID then
    notify('AttachPanelToEntity() failed (dash stable mode).')
    cleanup()
    return false
  end

  ATTACHED_VEH = veh
  CURRENT_ATTACH_MODE = 'dashstable'

  exports['cr-3dnui']:SendMessage(PANEL_ID, {
    type = 'hello',
    mode = 'dash_stable'
  })

  startStatusLoop()

  notify(('Mounted STABLE dash panel %s to vehicle %s (roof-style, no jitter)'):format(tostring(PANEL_ID), tostring(veh)))
  return true
end



-- ============================================================
-- KEY2DUI: mouse cursor inside DUI (no UV/raycast)
-- ============================================================
local function key2duiTick()
  -- Lock camera look so mouse deltas are "ours", but keep driving controls.
  DisableControlAction(0, 1, true)   -- LOOK_LR
  DisableControlAction(0, 2, true)   -- LOOK_UD
  DisableControlAction(0, 24, true)  -- ATTACK
  DisableControlAction(0, 25, true)  -- AIM
  DisableControlAction(0, 257, true) -- ATTACK2
  DisableControlAction(0, 263, true) -- MELEE

  local dx = GetDisabledControlNormal(0, 1)
  local dy = GetDisabledControlNormal(0, 2)

  -- Map look deltas -> cursor movement (normalized)
  CUR_U = clamp01(CUR_U + (dx * CUR_SPEED))
  CUR_V = clamp01(CUR_V + (dy * CUR_SPEED))

  -- Forward movement into DUI + render cursor inside the page
  exports['cr-3dnui']:SendMouseMove(PANEL_ID, CUR_U, CUR_V, { flipY = false })
  sendCursor(true)

  -- Clicks
  if IsDisabledControlJustPressed(0, 24) then
    exports['cr-3dnui']:SendMouseDown(PANEL_ID, 'left')
  end
  if IsDisabledControlJustReleased(0, 24) then
    exports['cr-3dnui']:SendMouseUp(PANEL_ID, 'left')
  end

  -- Exit hotkeys
  if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 177) then -- ESC / BACKSPACE
    KEY2DUI_ACTIVE = false
    CURSOR_VISIBLE = false
    sendCursor(false)
    notify('Key2DUI ended.')
  end
end

CreateThread(function()
  while true do
    if KEY2DUI_ACTIVE and PANEL_ID then
      key2duiTick()
      Wait(0)
    else
      Wait(100)
    end
  end
end)

-- ============================================================
-- Commands
-- ============================================================
RegisterCommand('nuiroof', function()
  local veh = getTargetVehicle()
  if veh == 0 or not DoesEntityExist(veh) then
    notify('No vehicle found. Get in a vehicle or stand near one, then run /nuiroof.')
    return
  end
  attachPanelToVehicle(veh)
end, false)

RegisterCommand('nuidash', function()
  local veh = getTargetVehicle()
  if veh == 0 or not DoesEntityExist(veh) then
    notify('No vehicle found. Get in a vehicle or stand near one, then run /nuidash.')
    return
  end
  attachPanelToDashStable(veh)
end, false)

-- Jitter reference mode (panel is attached to the PROP; use for visual tuning)
RegisterCommand('nuidashprop', function()
  local veh = getTargetVehicle()
  if veh == 0 or not DoesEntityExist(veh) then
    notify('No vehicle found. Get in a vehicle or stand near one, then run /nuidashprop.')
    return
  end
  attachPanelToDashProp(veh)
end, false)


-- ============================================================
-- Interactive Dash Tune Tool (mouse wheel)
--   /dashtune          toggle
--   /dashtarget prop|panel
--   /dashaxis   x|y|z|rx|ry|rz
--   /dashstep   <number>
--   /dashprint  (prints to F8 console)
-- ============================================================
local DASH_TUNE_ON = false
local DASH_TUNE_TARGET = 'prop'
local DASH_TUNE_AXIS = 'x'
local DASH_TUNE_POS_STEP = 0.005
local DASH_TUNE_ROT_STEP = 0.5

local function dashReapply()
  if not (ATTACHED_VEH and DoesEntityExist(ATTACHED_VEH)) then return end
  if CURRENT_ATTACH_MODE == 'dashprop' then
    attachPanelToDashProp(ATTACHED_VEH)
  elseif CURRENT_ATTACH_MODE == 'dashstable' then
    attachPanelToDashStable(ATTACHED_VEH)
  end
end

local function dashTuneDelta(step)
  if DASH_TUNE_TARGET == 'prop' then
    if DASH_TUNE_AXIS == 'x' then
      DASH_PROP_OFFSET = vector3(DASH_PROP_OFFSET.x + step, DASH_PROP_OFFSET.y, DASH_PROP_OFFSET.z)
    elseif DASH_TUNE_AXIS == 'y' then
      DASH_PROP_OFFSET = vector3(DASH_PROP_OFFSET.x, DASH_PROP_OFFSET.y + step, DASH_PROP_OFFSET.z)
    elseif DASH_TUNE_AXIS == 'z' then
      DASH_PROP_OFFSET = vector3(DASH_PROP_OFFSET.x, DASH_PROP_OFFSET.y, DASH_PROP_OFFSET.z + step)
    elseif DASH_TUNE_AXIS == 'rx' then
      DASH_PROP_ROT = vector3(DASH_PROP_ROT.x + step, DASH_PROP_ROT.y, DASH_PROP_ROT.z)
    elseif DASH_TUNE_AXIS == 'ry' then
      DASH_PROP_ROT = vector3(DASH_PROP_ROT.x, DASH_PROP_ROT.y + step, DASH_PROP_ROT.z)
    elseif DASH_TUNE_AXIS == 'rz' then
      DASH_PROP_ROT = vector3(DASH_PROP_ROT.x, DASH_PROP_ROT.y, DASH_PROP_ROT.z + step)
    end
  else
    if DASH_TUNE_AXIS == 'x' then
      MONITOR_LOCAL_OFFSET = vector3(MONITOR_LOCAL_OFFSET.x + step, MONITOR_LOCAL_OFFSET.y, MONITOR_LOCAL_OFFSET.z)
    elseif DASH_TUNE_AXIS == 'y' then
      MONITOR_LOCAL_OFFSET = vector3(MONITOR_LOCAL_OFFSET.x, MONITOR_LOCAL_OFFSET.y + step, MONITOR_LOCAL_OFFSET.z)
    elseif DASH_TUNE_AXIS == 'z' then
      MONITOR_LOCAL_OFFSET = vector3(MONITOR_LOCAL_OFFSET.x, MONITOR_LOCAL_OFFSET.y, MONITOR_LOCAL_OFFSET.z + step)
    elseif DASH_TUNE_AXIS == 'rx' then
      PANEL_LOCAL_ROT = vector3(PANEL_LOCAL_ROT.x + step, PANEL_LOCAL_ROT.y, PANEL_LOCAL_ROT.z)
    elseif DASH_TUNE_AXIS == 'ry' then
      PANEL_LOCAL_ROT = vector3(PANEL_LOCAL_ROT.x, PANEL_LOCAL_ROT.y + step, PANEL_LOCAL_ROT.z)
    elseif DASH_TUNE_AXIS == 'rz' then
      PANEL_LOCAL_ROT = vector3(PANEL_LOCAL_ROT.x, PANEL_LOCAL_ROT.y, PANEL_LOCAL_ROT.z + step)
    end
  end

  dashReapply()
end

CreateThread(function()
  while true do
    if DASH_TUNE_ON then
      local step = (DASH_TUNE_AXIS == 'x' or DASH_TUNE_AXIS == 'y' or DASH_TUNE_AXIS == 'z') and DASH_TUNE_POS_STEP or DASH_TUNE_ROT_STEP
      if IsControlPressed(0, 21) then step = step * 10.0 end  -- SHIFT coarse
      if IsControlPressed(0, 36) then step = step * 0.1 end   -- CTRL fine

      if IsControlJustPressed(0, 241) then
        dashTuneDelta(step)
      elseif IsControlJustPressed(0, 242) then
        dashTuneDelta(-step)
      end

      drawTxt(0.015, 0.70, 0.35, ('DASH TUNE: ON  target=%s  axis=%s  step=%s'):format(DASH_TUNE_TARGET, DASH_TUNE_AXIS, tostring(step)))
      drawTxt(0.015, 0.73, 0.30, ('PROP  offset=%s  rot=%s'):format(fmtVec3(DASH_PROP_OFFSET), fmtVec3(DASH_PROP_ROT)))
      drawTxt(0.015, 0.755, 0.30, ('PANEL offset=%s  rot=%s  normal=%s'):format(fmtVec3(MONITOR_LOCAL_OFFSET), fmtVec3(PANEL_LOCAL_ROT), fmtVec3(getPanelLocalNormal())))
      drawTxt(0.015, 0.78, 0.28, 'Scroll=adjust | SHIFT=coarse | CTRL=fine | /dashprint')
      Wait(0)
    else
      Wait(200)
    end
  end
end)

RegisterCommand('dashtune', function()
  DASH_TUNE_ON = not DASH_TUNE_ON
  notify(('Dash tune: %s'):format(DASH_TUNE_ON and 'ON' or 'OFF'))
end, false)

RegisterCommand('dashtarget', function(_, args)
  local t = args[1] and string.lower(args[1]) or ''
  if t ~= 'prop' and t ~= 'panel' then
    notify('Usage: /dashtarget prop|panel')
    return
  end
  DASH_TUNE_TARGET = t
  notify(('Dash tune target = %s'):format(DASH_TUNE_TARGET))
end, false)

RegisterCommand('dashaxis', function(_, args)
  local a = args[1] and string.lower(args[1]) or ''
  if a ~= 'x' and a ~= 'y' and a ~= 'z' and a ~= 'rx' and a ~= 'ry' and a ~= 'rz' then
    notify('Usage: /dashaxis x|y|z|rx|ry|rz')
    return
  end
  DASH_TUNE_AXIS = a
  notify(('Dash tune axis = %s'):format(DASH_TUNE_AXIS))
end, false)

RegisterCommand('dashstep', function(_, args)
  local v = tonumber(args[1] or '')
  if not v then
    notify('Usage: /dashstep <number>')
    return
  end
  if DASH_TUNE_AXIS == 'x' or DASH_TUNE_AXIS == 'y' or DASH_TUNE_AXIS == 'z' then
    DASH_TUNE_POS_STEP = v
    notify(('Dash pos step = %s'):format(tostring(DASH_TUNE_POS_STEP)))
  else
    DASH_TUNE_ROT_STEP = v
    notify(('Dash rot step = %s'):format(tostring(DASH_TUNE_ROT_STEP)))
  end
end, false)

RegisterCommand('dashprint', function()
  -- NOTE: These are LIVE values (what the tuner is using right now).
  -- They are demo-specific and will differ per vehicle + per prop.
  local livePanelNormal = getPanelLocalNormal()
  local bakedOffset, bakedNormal, bakedUp = computeDashStableTransform()

  print('================ DASH TUNE VALUES ================')
  print(('DASH_PROP_OFFSET         = vector3(%s, %s, %s)'):format(fmt4(DASH_PROP_OFFSET.x), fmt4(DASH_PROP_OFFSET.y), fmt4(DASH_PROP_OFFSET.z)))
  print(('DASH_PROP_ROT            = vector3(%s, %s, %s)'):format(fmt4(DASH_PROP_ROT.x), fmt4(DASH_PROP_ROT.y), fmt4(DASH_PROP_ROT.z)))

  print(('MONITOR_LOCAL_OFFSET     = vector3(%s, %s, %s)'):format(fmt4(MONITOR_LOCAL_OFFSET.x), fmt4(MONITOR_LOCAL_OFFSET.y), fmt4(MONITOR_LOCAL_OFFSET.z)))
  print(('PANEL_LOCAL_ROT          = vector3(%s, %s, %s)'):format(fmt4(PANEL_LOCAL_ROT.x), fmt4(PANEL_LOCAL_ROT.y), fmt4(PANEL_LOCAL_ROT.z)))
  print(('PANEL_LOCAL_NORMAL (live)= vector3(%s, %s, %s)'):format(fmt4(livePanelNormal.x), fmt4(livePanelNormal.y), fmt4(livePanelNormal.z)))

  print('---------------- STABLE /nuidash (baked to VEH) ----------------')
  print(('DASH_BAKED_OFFSET        = vector3(%s, %s, %s)'):format(fmt4(bakedOffset.x), fmt4(bakedOffset.y), fmt4(bakedOffset.z)))
  print(('DASH_BAKED_NORMAL        = vector3(%s, %s, %s)'):format(fmt4(bakedNormal.x), fmt4(bakedNormal.y), fmt4(bakedNormal.z)))
  print(('DASH_BAKED_UP            = vector3(%s, %s, %s)'):format(fmt4(bakedUp.x), fmt4(bakedUp.y), fmt4(bakedUp.z)))
  print('==============================================================')
  notify('Printed LIVE dash tune values (including panel normal + baked stable values) to F8 console.')
end, false)

RegisterCommand('nuioff', function()
  cleanup()
  notify('Panel removed.')
end, false)

RegisterCommand('nuikey', function()
  if not PANEL_ID then
    notify('No panel yet. Run /nuiroof or /nuidash first.')
    return
  end

  KEY2DUI_ACTIVE = not KEY2DUI_ACTIVE
  if KEY2DUI_ACTIVE then
    CUR_U, CUR_V = 0.5, 0.5
    CURSOR_VISIBLE = true
    sendCursor(true)
    notify('Key2DUI started. Mouse controls DUI cursor; click = interact; ESC/BACKSPACE to exit.')
  else
    CURSOR_VISIBLE = false
    sendCursor(false)
    notify('Key2DUI ended.')
  end
end, false)

RegisterCommand('nuipage', function(_, args)
  if not PANEL_ID then return end
  local page = (args[1] or ''):lower()
  if page ~= 'all' and page ~= 'spd' and page ~= 'gear' and page ~= 'eng' then
    notify('Usage: /nuipage <all|spd|gear|eng>')
    return
  end
  exports['cr-3dnui']:SendMessage(PANEL_ID, { type = 'page', page = page })
end, false)

-- Optional helpers for tweaking dash mount quickly
RegisterCommand('nuidashpos', function(_, args)
  local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if not (x and y and z) then
    notify('Usage: /nuidashpos <x> <y> <z>')
    return
  end
  DASH_PROP_OFFSET = vector3(x, y, z)
  if ATTACHED_VEH and DoesEntityExist(ATTACHED_VEH) then
    if CURRENT_ATTACH_MODE == 'dashprop' then
      attachPanelToDashProp(ATTACHED_VEH)
    else
      attachPanelToDashStable(ATTACHED_VEH)
    end
  end
end, false)

RegisterCommand('nuidashrot', function(_, args)
  local rx, ry, rz = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if not (rx and ry and rz) then
    notify('Usage: /nuidashrot <rx> <ry> <rz>')
    return
  end
  DASH_PROP_ROT = vector3(rx, ry, rz)
  if ATTACHED_VEH and DoesEntityExist(ATTACHED_VEH) then
    if CURRENT_ATTACH_MODE == 'dashprop' then
      attachPanelToDashProp(ATTACHED_VEH)
    else
      attachPanelToDashStable(ATTACHED_VEH)
    end
  end
end, false)

-- Panel tuning (relative to prop)
RegisterCommand('nuidashpanelpos', function(_, args)
  local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if not (x and y and z) then
    notify('Usage: /nuidashpanelpos <x> <y> <z>')
    return
  end
  MONITOR_LOCAL_OFFSET = vector3(x, y, z)
  if ATTACHED_VEH and DoesEntityExist(ATTACHED_VEH) then
    if CURRENT_ATTACH_MODE == 'dashprop' then
      attachPanelToDashProp(ATTACHED_VEH)
    else
      attachPanelToDashStable(ATTACHED_VEH)
    end
  end
end, false)

RegisterCommand('nuidashpanelrot', function(_, args)
  local rx, ry, rz = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if not (rx and ry and rz) then
    notify('Usage: /nuidashpanelrot <rx> <ry> <rz>')
    return
  end
  PANEL_LOCAL_ROT = vector3(rx, ry, rz)
  if ATTACHED_VEH and DoesEntityExist(ATTACHED_VEH) then
    if CURRENT_ATTACH_MODE == 'dashprop' then
      attachPanelToDashProp(ATTACHED_VEH)
    else
      attachPanelToDashStable(ATTACHED_VEH)
    end
  end
end, false)


AddEventHandler('onResourceStop', function(resName)
  if resName ~= GetCurrentResourceName() then return end
  cleanup()
end)
