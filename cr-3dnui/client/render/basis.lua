-- cr-3dnui/client/render/basis.lua
-- Panel basis builder (center, normal, right, up, half extents)
-- Includes helpers:
--   - depthCompensation = "screen"
--   - frontOnly (disables faceCamera flipping when enabled)

CR3D = CR3D or {}

function CR3D.makePanelBasis(pos, normal, width, height, zOffset, faceCamera, frontOnly, depthCompensation, panelUp)
  local planeNormal = CR3D.vecNorm(normal)

  -- If faceCamera is enabled, flip the normal toward the camera so the panel always faces you.
  -- NOTE: This breaks stable "front" vs "back", so we skip it when frontOnly is enabled.
  if faceCamera and not frontOnly then
    local camPos = GetGameplayCamCoord()
    local toCam = CR3D.vecNorm(CR3D.vecSub(camPos, pos))
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

  -- ============================================================
  -- ORIENTATION LOCK (prevents 180° in-plane flips / upside-down UI)
  -- Prefer to align panel "right" with the camera's right vector projected onto the plane.
  -- This yields a consistent screen orientation for demos (snake/whiteboard) without requiring panelUp.
  -- ============================================================
  if not panelUp then
    do
    local camRot = GetGameplayCamRot(2)
    local camF = CR3D.rotationToDirection(camRot)
    local camR = CR3D.vecNorm(CR3D.vecCross(camF, vector3(0.0, 0.0, 1.0)))

    -- project camR onto the panel plane
    local proj = CR3D.vecSub(camR, CR3D.vecMul(planeNormal, CR3D.vecDot(camR, planeNormal)))

    -- Only use if projection is valid
    local projLen = CR3D.vecLen(proj)
    if projLen > 0.001 then
      proj = CR3D.vecMul(proj, 1.0 / projLen)
      if CR3D.vecDot(right, proj) < 0.0 then
        -- Flip both right & up to rotate 180° in-plane (fixes upside-down + backwards at once)
        right  = CR3D.vecMul(right,  -1.0)
        upWall = CR3D.vecMul(upWall, -1.0)
      end
    end
    end
  end

  -- ============================================================
  -- If a panelUp was provided, enforce that computed upWall points
  -- in the same hemisphere as panelUp (and keep basis handedness).
  -- ============================================================
  if panelUp then
    local desiredUp = CR3D.vecNorm(panelUp)
    if CR3D.vecDot(upWall, desiredUp) < 0.0 then
      upWall = CR3D.vecMul(upWall, -1.0)
      right  = CR3D.vecMul(right,  -1.0)
    end
  end

  return {
    center = center,
    normal = planeNormal,
    right  = right,
    up     = upWall,
    halfW  = (width * 0.5),
    halfH  = (height * 0.5)
  }
end
