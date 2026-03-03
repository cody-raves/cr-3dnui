-- cr-3dnui/client/render/draw.lua
-- Panel rendering

CR3D = CR3D or {}

function CR3D.drawPanel(panel, frameCam)
  if not panel.enabled then return end
  if not panel.dui then return end
  if not panel.txdName or not panel.texName then return end

  local camPos = frameCam and frameCam.pos or nil
  local camRot = frameCam and frameCam.rot or nil
  local camForward = frameCam and frameCam.forward or nil
  local camRight = frameCam and frameCam.right or nil

  local basis = CR3D.makePanelBasis(
    panel.pos, panel.normal, panel.width, panel.height,
    panel.zOffset, panel.faceCamera, panel.frontOnly, panel.depthCompensation,
    panel.up, camPos, camRot, camForward, camRight, panel
  )

  -- Stable in-plane orientation (optional)
  local right, upWall = basis.right, basis.up
  if panel.inPlaneFlip then
    right = CR3D.vecMul(right, -1.0)
    upWall = CR3D.vecMul(upWall, -1.0)
  end

  -- Optional: front-only rendering (prevents backside clipping and weird interaction)
  if panel.frontOnly and ((CR3D.CONFIG and CR3D.CONFIG.enableFrontCull) ~= false) then
    local cPos = camPos or GetGameplayCamCoord()
    local toCam = CR3D.vecNorm(CR3D.vecSub(cPos, basis.center))
    local dot = CR3D.vecDot(toCam, basis.normal)
    local minDot = tonumber(panel.frontDotMin) or 0.0
    if dot < minDot then
      return
    end
  end

  local v1x, v1y, v1z, v2x, v2y, v2z, v3x, v3y, v3z, v4x, v4y, v4z
  if (not panel.inPlaneFlip) and basis.v1x then
    v1x, v1y, v1z = basis.v1x, basis.v1y, basis.v1z
    v2x, v2y, v2z = basis.v2x, basis.v2y, basis.v2z
    v3x, v3y, v3z = basis.v3x, basis.v3y, basis.v3z
    v4x, v4y, v4z = basis.v4x, basis.v4y, basis.v4z
  else
    local center, halfW, halfH = basis.center, basis.halfW, basis.halfH
    local cx, cy, cz = center.x, center.y, center.z
    local rx, ry, rz = right.x, right.y, right.z
    local ux, uy, uz = upWall.x, upWall.y, upWall.z

    v1x = cx - (rx * halfW) + (ux * halfH)
    v1y = cy - (ry * halfW) + (uy * halfH)
    v1z = cz - (rz * halfW) + (uz * halfH)
    v2x = cx + (rx * halfW) + (ux * halfH)
    v2y = cy + (ry * halfW) + (uy * halfH)
    v2z = cz + (rz * halfW) + (uz * halfH)
    v3x = cx + (rx * halfW) - (ux * halfH)
    v3y = cy + (ry * halfW) - (uy * halfH)
    v3z = cz + (rz * halfW) - (uz * halfH)
    v4x = cx - (rx * halfW) - (ux * halfH)
    v4y = cy - (ry * halfW) - (uy * halfH)
    v4z = cz - (rz * halfW) - (uz * halfH)
  end

  local r, g, b, a = 255, 255, 255, panel.alpha or 255

  -- U flipped so text is not mirrored
  DrawSpritePoly(v1x,v1y,v1z, v2x,v2y,v2z, v3x,v3y,v3z,
    r,g,b,a, panel.txdName, panel.texName,
    0.0,1.0,1.0,  1.0,1.0,1.0,  1.0,0.0,1.0
  )
  DrawSpritePoly(v1x,v1y,v1z, v3x,v3y,v3z, v4x,v4y,v4z,
    r,g,b,a, panel.txdName, panel.texName,
    0.0,1.0,1.0,  1.0,0.0,1.0,  0.0,0.0,1.0
  )
end
