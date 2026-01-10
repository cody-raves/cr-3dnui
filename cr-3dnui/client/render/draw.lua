-- cr-3dnui/client/render/draw.lua
-- Panel rendering

CR3D = CR3D or {}

function CR3D.drawPanel(panel)
  if not panel.enabled then return end
  if not panel.dui then return end
  if not panel.txdName or not panel.texName then return end

  local basis = CR3D.makePanelBasis(
    panel.pos, panel.normal, panel.width, panel.height,
    panel.zOffset, panel.faceCamera, panel.frontOnly, panel.depthCompensation
  )

  -- Optional: front-only rendering (prevents backside clipping and weird interaction)
  if panel.frontOnly then
    local camPos = GetGameplayCamCoord()
    local toCam = CR3D.vecNorm(CR3D.vecSub(camPos, basis.center))
    local dot = CR3D.vecDot(toCam, basis.normal)
    local minDot = tonumber(panel.frontDotMin) or 0.0
    if dot < minDot then
      return
    end
  end

  local center, right, upWall, halfW, halfH = basis.center, basis.right, basis.up, basis.halfW, basis.halfH

  local v1 = CR3D.vecAdd(center, CR3D.vecAdd(CR3D.vecMul(right, -halfW), CR3D.vecMul(upWall,  halfH))) -- TL
  local v2 = CR3D.vecAdd(center, CR3D.vecAdd(CR3D.vecMul(right,  halfW), CR3D.vecMul(upWall,  halfH))) -- TR
  local v3 = CR3D.vecAdd(center, CR3D.vecAdd(CR3D.vecMul(right,  halfW), CR3D.vecMul(upWall, -halfH))) -- BR
  local v4 = CR3D.vecAdd(center, CR3D.vecAdd(CR3D.vecMul(right, -halfW), CR3D.vecMul(upWall, -halfH))) -- BL

  local r, g, b, a = 255, 255, 255, panel.alpha or 255

  -- U flipped so text is not mirrored
  DrawSpritePoly(v1.x,v1.y,v1.z, v2.x,v2.y,v2.z, v3.x,v3.y,v3.z,
    r,g,b,a, panel.txdName, panel.texName,
    0.0,1.0,1.0,  1.0,1.0,1.0,  1.0,0.0,1.0
  )
  DrawSpritePoly(v1.x,v1.y,v1.z, v3.x,v3.y,v3.z, v4.x,v4.y,v4.z,
    r,g,b,a, panel.txdName, panel.texName,
    0.0,1.0,1.0,  1.0,0.0,1.0,  0.0,0.0,1.0
  )
end
