-- cr-3dnui/client/input/raycast_uv.lua
-- Raycast camera -> hit on panel plane, returns UV coords (0..1)
-- This is the "world interaction" path used by current API.

CR3D = CR3D or {}

function CR3D.uvToPixels(panel, u, v, flipY)
  local resW = panel.resW or 1024
  local resH = panel.resH or 1024
  local uu = math.min(1.0, math.max(0.0, u or 0.0))
  local vv = math.min(1.0, math.max(0.0, v or 0.0))
  if flipY then vv = 1.0 - vv end
  local x = math.floor(uu * resW)
  local y = math.floor(vv * resH)
  return x, y
end

-- Returns: hitPos, u, v, t
function CR3D.raycastPanelUV(panel, maxDist, frameCam)
  if not panel or not panel.enabled then return nil end
  -- Interaction mode gate: UV raycast only applies to UV-interactable panels
  local mode = panel.interactionMode or panel.interaction or 'uv'
  if mode ~= 'uv' then return nil end

  local camPos = frameCam and frameCam.pos or nil
  local camRot = frameCam and frameCam.rot or nil
  local camForward = frameCam and frameCam.forward or nil
  local camRight = frameCam and frameCam.right or nil

  local basis = CR3D.makePanelBasis(
    panel.pos, panel.normal, panel.width, panel.height,
    panel.zOffset, panel.faceCamera, panel.frontOnly, panel.depthCompensation,
    panel.up, camPos, camRot, camForward, camRight, panel
  )

  local center, normal, right, upWall, halfW, halfH =
    basis.center, basis.normal, basis.right, basis.up, basis.halfW, basis.halfH

  local cPos = camPos or GetGameplayCamCoord()

  -- Optional: front-only interaction (matches render gating)
  if panel.frontOnly and ((CR3D.CONFIG and CR3D.CONFIG.enableFrontCull) ~= false) then
    local toCam = CR3D.vecNorm(CR3D.vecSub(cPos, center))
    local dot = CR3D.vecDot(toCam, normal)
    local minDot = tonumber(panel.frontDotMin) or 0.0
    if dot < minDot then return nil end
  end

  local dir = camForward or CR3D.rotationToDirection(camRot or GetGameplayCamRot(2))

  local denom = CR3D.vecDot(dir, normal)
  if math.abs(denom) < 0.0001 then return nil end

  local t = CR3D.vecDot(CR3D.vecSub(center, cPos), normal) / denom
  if t < 0.0 then return nil end
  if maxDist and t > maxDist then return nil end

  local hitPos = CR3D.vecAdd(cPos, CR3D.vecMul(dir, t))
  local rel = CR3D.vecSub(hitPos, center)

  local localX = CR3D.vecDot(rel, right) / halfW
  local localY = CR3D.vecDot(rel, upWall) / halfH
  if math.abs(localX) > 1.0 or math.abs(localY) > 1.0 then return nil end

  local u = (localX + 1.0) * 0.5
  local v = (localY + 1.0) * 0.5
  return hitPos, u, v, t
end
