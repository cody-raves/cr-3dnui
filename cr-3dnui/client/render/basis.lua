-- cr-3dnui/client/render/basis.lua
-- Panel basis builder (center, normal, right, up, half extents)
-- Includes helpers:
--   - depthCompensation = "screen"
--   - frontOnly (disables faceCamera flipping when enabled)

CR3D = CR3D or {}

local function orientationLockEnabled()
  local cfg = CR3D.CONFIG or {}
  return cfg.orientationLock ~= false
end

function CR3D.makePanelBasis(pos, normal, width, height, zOffset, faceCamera, frontOnly, depthCompensation, panelUp, camPos, camRot, camForward, camRight, panel)
  local useOrientationLock = orientationLockEnabled() and (not panelUp)
  local isDynamic = (faceCamera and not frontOnly) or useOrientationLock

  if panel and not isDynamic and not panel._geomDirty and panel._basisCache then
    local c = panel._basisCache
    if c.pos == pos and c.normalIn == normal and c.upIn == panelUp and c.width == width and c.height == height
      and c.zOffset == zOffset and c.depthCompensation == depthCompensation and c.frontOnly == frontOnly then
      return c
    end
  end

  local planeNormal = CR3D.vecNorm(normal)

  -- If faceCamera is enabled, flip the normal toward the camera so the panel always faces you.
  -- NOTE: This breaks stable "front" vs "back", so we skip it when frontOnly is enabled.
  if faceCamera and not frontOnly then
    local cPos = camPos or GetGameplayCamCoord()
    local toCam = CR3D.vecNorm(CR3D.vecSub(cPos, pos))
    if CR3D.vecDot(toCam, planeNormal) < 0.0 then
      planeNormal = CR3D.vecMul(planeNormal, -1.0)
    end
  end

  -- Depth bias / zOffset:
  local bias
  if zOffset ~= nil then
    bias = zOffset
  else
    bias = (depthCompensation == "screen") and 0.004 or 0.002
  end

  if depthCompensation == "screen" then
    local tilt = math.min(0.35, math.abs(planeNormal.z))
    bias = bias + (tilt * 0.002)
  end

  local center = CR3D.vecAdd(pos, CR3D.vecMul(planeNormal, bias))

  -- Use panel-provided up axis if available (enables true roll). Otherwise world-up.
  local upRef = panelUp and CR3D.vecNorm(panelUp) or vector3(0.0, 0.0, 1.0)

  -- RIGHT-HANDED BASIS (fixes backface culling / invisible panels)
  local right = CR3D.vecCross(planeNormal, upRef)

  -- Fallback if upRef is parallel to normal
  if math.abs(right.x) < 0.001 and math.abs(right.y) < 0.001 and math.abs(right.z) < 0.001 then
    upRef = vector3(0.0, 1.0, 0.0)
    right = CR3D.vecCross(planeNormal, upRef)
  end

  right = CR3D.vecNorm(right)
  local upWall = CR3D.vecNorm(CR3D.vecCross(right, planeNormal))

  -- Orientation lock (optional): keep in-plane orientation stable when no panelUp is provided.
  if useOrientationLock then
    local cRot = camRot or GetGameplayCamRot(2)
    local camF = camForward or CR3D.rotationToDirection(cRot)
    local camR = camRight or CR3D.vecNorm(CR3D.vecCross(camF, vector3(0.0, 0.0, 1.0)))

    -- project camR onto the panel plane
    local proj = CR3D.vecSub(camR, CR3D.vecMul(planeNormal, CR3D.vecDot(camR, planeNormal)))

    local projLen = CR3D.vecLen(proj)
    if projLen > 0.001 then
      proj = CR3D.vecMul(proj, 1.0 / projLen)
      if CR3D.vecDot(right, proj) < 0.0 then
        right  = CR3D.vecMul(right,  -1.0)
        upWall = CR3D.vecMul(upWall, -1.0)
      end
    end
  end

  -- If a panelUp was provided, enforce hemisphere alignment while keeping handedness.
  if panelUp then
    local desiredUp = CR3D.vecNorm(panelUp)
    if CR3D.vecDot(upWall, desiredUp) < 0.0 then
      upWall = CR3D.vecMul(upWall, -1.0)
      right  = CR3D.vecMul(right,  -1.0)
    end
  end

  local basis = {
    center = center,
    normal = planeNormal,
    right  = right,
    up     = upWall,
    halfW  = (width * 0.5),
    halfH  = (height * 0.5)
  }

  if panel and not isDynamic then
    local c = basis
    local cx, cy, cz = c.center.x, c.center.y, c.center.z
    local rx, ry, rz = c.right.x, c.right.y, c.right.z
    local ux, uy, uz = c.up.x, c.up.y, c.up.z
    local hw, hh = c.halfW, c.halfH

    c.v1x = cx - (rx * hw) + (ux * hh)
    c.v1y = cy - (ry * hw) + (uy * hh)
    c.v1z = cz - (rz * hw) + (uz * hh)
    c.v2x = cx + (rx * hw) + (ux * hh)
    c.v2y = cy + (ry * hw) + (uy * hh)
    c.v2z = cz + (rz * hw) + (uz * hh)
    c.v3x = cx + (rx * hw) - (ux * hh)
    c.v3y = cy + (ry * hw) - (uy * hh)
    c.v3z = cz + (rz * hw) - (uz * hh)
    c.v4x = cx - (rx * hw) - (ux * hh)
    c.v4y = cy - (ry * hw) - (uy * hh)
    c.v4z = cz - (rz * hw) - (uz * hh)

    c.pos = pos
    c.normalIn = normal
    c.upIn = panelUp
    c.width = width
    c.height = height
    c.zOffset = zOffset
    c.depthCompensation = depthCompensation
    c.frontOnly = frontOnly

    panel._basisCache = c
    panel._geomDirty = false
  end

  return basis
end
