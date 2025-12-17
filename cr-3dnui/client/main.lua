-- cr-3dnui (library)
-- Renders DUI-backed HTML pages on arbitrary world-space quads,
-- raycast -> UV helpers, and optional native mouse injection for drag.

local PANELS = {}
local NEXT_ID = 1

-------------------------------------------------------------
-- Built-in HUD cursor (optional helper)
-- NOTE: The API does NOT force-draw a cursor; consuming resources call DrawCursor().
-------------------------------------------------------------
local CURSOR = {
  txd = "cr3dnui_cursor_txd",
  tex = "cursor",
  ready = false
}

CreateThread(function()
  -- wait one frame so runtime txd creation is safe
  Wait(0)
  local txd = CreateRuntimeTxd(CURSOR.txd)
  -- cursor tip should be at top-left pixel (0,0) in the PNG
  CreateRuntimeTextureFromImage(txd, CURSOR.tex, "assets/cursor.png")
  CURSOR.ready = true
end)

--- Draw a mouse cursor sprite on the HUD.
--- cx, cy are screen coords (0..1). For center, use 0.5, 0.5.
--- isHit toggles hit coloring (defaults to green when true).
--- opts = { w,h, tipX, tipY, r,g,b,a, hitR,hitG,hitB,hitA }
exports("DrawCursor", function(cx, cy, isHit, opts)
  if not CURSOR.ready then return false end
  opts = opts or {}

  local w = opts.w or 0.015
  local h = opts.h or 0.03

  -- hotspot in normalized sprite space (0..1).
  -- for classic arrow cursor with tip at top-left: tipX=0, tipY=0
  local tipX = opts.tipX or 0.0
  local tipY = opts.tipY or 0.0

  -- DrawSprite is centered; offset so (cx,cy) lands on hotspot.
  local drawX = (cx or 0.5) + (w * (0.5 - tipX))
  local drawY = (cy or 0.5) + (h * (0.5 - tipY))

  local r, g, b, a = opts.r or 255, opts.g or 255, opts.b or 255, opts.a or 235
  if isHit then
    r, g, b, a = opts.hitR or 0, opts.hitG or 255, opts.hitB or 0, opts.hitA or 235
  end

  DrawSprite(CURSOR.txd, CURSOR.tex, drawX, drawY, w, h, 0.0, r, g, b, a)
  return true
end)

-------------------------------------------------------------
-- Small vector helpers
-------------------------------------------------------------
local function vecAdd(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
local function vecSub(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
local function vecMul(a, s) return vector3(a.x * s, a.y * s, a.z * s) end
local function vecDot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vecCross(a, b)
  return vector3(
    a.y * b.z - a.z * b.y,
    a.z * b.x - a.x * b.z,
    a.x * b.y - a.y * b.x
  )
end
local function vecLen(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vecNorm(a)
  local len = vecLen(a)
  if len < 0.0001 then return vector3(0.0, 0.0, 0.0) end
  return vector3(a.x / len, a.y / len, a.z / len)
end

-------------------------------------------------------------
-- camera → direction
-------------------------------------------------------------
local function rotationToDirection(rot)
  local radX = math.rad(rot.x)
  local radZ = math.rad(rot.z)
  local cosX = math.cos(radX)
  local sinX = math.sin(radX)
  local cosZ = math.cos(radZ)
  local sinZ = math.sin(radZ)
  return vector3(-sinZ * cosX, cosZ * cosX, sinX)
end

-------------------------------------------------------------
-- Panel basis (center, normal, right, up, half extents)
-------------------------------------------------------------
local function makePanelBasis(pos, normal, width, height, zOffset, faceCamera)
  local planeNormal = vecNorm(normal)

  if faceCamera then
    local camPos = GetGameplayCamCoord()
    local toCam = vecNorm(vecSub(camPos, pos))
    if vecDot(toCam, planeNormal) < 0.0 then
      planeNormal = vecMul(planeNormal, -1.0)
    end
  end

  local center = vecAdd(pos, vecMul(planeNormal, zOffset or 0.002))

  local worldUp = vector3(0.0, 0.0, 1.0)
  local right = vecCross(worldUp, planeNormal)

  if math.abs(right.x) < 0.001 and math.abs(right.y) < 0.001 and math.abs(right.z) < 0.001 then
    worldUp = vector3(0.0, 1.0, 0.0)
    right = vecCross(planeNormal, worldUp)
  end

  right = vecNorm(right)
  local upWall = vecNorm(vecCross(right, planeNormal))

  return {
    center = center,
    normal = planeNormal,
    right  = right,
    up     = upWall,
    halfW  = (width * 0.5),
    halfH  = (height * 0.5)
  }
end

-------------------------------------------------------------
-- Draw a single panel quad (2 tris)
-------------------------------------------------------------
local function drawPanel(panel)
  if not panel.enabled then return end
  if not panel.dui then return end
  if not panel.txdName or not panel.texName then return end

  local basis = makePanelBasis(panel.pos, panel.normal, panel.width, panel.height, panel.zOffset, panel.faceCamera)
  local center, right, upWall, halfW, halfH = basis.center, basis.right, basis.up, basis.halfW, basis.halfH

  local v1 = vecAdd(center, vecAdd(vecMul(right, -halfW), vecMul(upWall,  halfH))) -- TL
  local v2 = vecAdd(center, vecAdd(vecMul(right,  halfW), vecMul(upWall,  halfH))) -- TR
  local v3 = vecAdd(center, vecAdd(vecMul(right,  halfW), vecMul(upWall, -halfH))) -- BR
  local v4 = vecAdd(center, vecAdd(vecMul(right, -halfW), vecMul(upWall, -halfH))) -- BL

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

-------------------------------------------------------------
-- Raycast camera ray → hit on a panel (u,v in 0..1)
-- Returns: hitPos, u, v, t
-------------------------------------------------------------
local function raycastPanelUV(panel, maxDist)
  if not panel or not panel.enabled then return nil end

  local basis = makePanelBasis(panel.pos, panel.normal, panel.width, panel.height, panel.zOffset, panel.faceCamera)
  local center, normal, right, upWall, halfW, halfH = basis.center, basis.normal, basis.right, basis.up, basis.halfW, basis.halfH

  local camPos = GetGameplayCamCoord()
  local camRot = GetGameplayCamRot(2)
  local dir = rotationToDirection(camRot)

  local denom = vecDot(dir, normal)
  if math.abs(denom) < 0.0001 then return nil end

  local t = vecDot(vecSub(center, camPos), normal) / denom
  if t < 0.0 then return nil end
  if maxDist and t > maxDist then return nil end

  local hitPos = vecAdd(camPos, vecMul(dir, t))
  local rel = vecSub(hitPos, center)

  local localX = vecDot(rel, right) / halfW
  local localY = vecDot(rel, upWall) / halfH
  if math.abs(localX) > 1.0 or math.abs(localY) > 1.0 then return nil end

  local u = (localX + 1.0) * 0.5
  local v = (localY + 1.0) * 0.5
  return hitPos, u, v, t
end

-------------------------------------------------------------
-- DUI creation / teardown
-------------------------------------------------------------
local function createDuiForPanel(panel)
  if panel.dui then return end
  if not panel.url then error("[cr-3dnui] CreatePanel requires opts.url") end

  panel.dui = CreateDui(panel.url, panel.resW or 1024, panel.resH or 1024)
  local handle = GetDuiHandle(panel.dui)

  panel.txdName = ("cr3dnui_txd_%s"):format(panel.id)
  panel.texName = ("cr3dnui_tex_%s"):format(panel.id)

  local txd = CreateRuntimeTxd(panel.txdName)
  CreateRuntimeTextureFromDuiHandle(txd, panel.texName, handle)
end

local function destroyDuiForPanel(panel)
  if not panel then return end
  if panel.dui then
    DestroyDui(panel.dui)
    panel.dui = nil
  end
  panel.txdName = nil
  panel.texName = nil
end

-------------------------------------------------------------
-- Helpers: UV -> pixel coords for SendDuiMouse*
-------------------------------------------------------------
local function uvToPixels(panel, u, v, flipY)
  local resW = panel.resW or 1024
  local resH = panel.resH or 1024
  local uu = math.min(1.0, math.max(0.0, u or 0.0))
  local vv = math.min(1.0, math.max(0.0, v or 0.0))
  if flipY then vv = 1.0 - vv end
  local x = math.floor(uu * resW)
  local y = math.floor(vv * resH)
  return x, y
end

-------------------------------------------------------------
-- EXPORTS (client)
-------------------------------------------------------------
exports("CreatePanel", function(opts)
  opts = opts or {}

  local id = opts.id or NEXT_ID
  NEXT_ID = (type(id) == "number") and (id + 1) or (NEXT_ID + 1)

  local owner = GetInvokingResource() or "unknown"
  local panel = {
    id = id,
    owner = owner,
    url = opts.url,
    resW = opts.resW or 1024,
    resH = opts.resH or 1024,
    pos = opts.pos or vector3(0.0, 0.0, 0.0),
    normal = opts.normal or vector3(0.0, 0.0, 1.0),
    width = opts.width or 1.0,
    height = opts.height or 1.0,
    alpha = opts.alpha or 255,
    enabled = (opts.enabled == nil) and true or (opts.enabled == true),
    zOffset = opts.zOffset or 0.002,
    faceCamera = (opts.faceCamera == nil) and true or (opts.faceCamera == true),
    dui = nil,
    txdName = nil,
    texName = nil,
  }

  createDuiForPanel(panel)
  PANELS[tostring(id)] = panel
  return id
end)

exports("DestroyPanel", function(panelId)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  destroyDuiForPanel(panel)
  PANELS[tostring(panelId)] = nil
end)

exports("SetPanelTransform", function(panelId, pos, normal)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  if pos then panel.pos = pos end
  if normal then panel.normal = normal end
end)

exports("SetPanelSize", function(panelId, width, height)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  if width then panel.width = width end
  if height then panel.height = height end
end)

exports("SetPanelUrl", function(panelId, url, resW, resH)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  destroyDuiForPanel(panel)
  panel.url = url
  panel.resW = resW or panel.resW or 1024
  panel.resH = resH or panel.resH or 1024
  createDuiForPanel(panel)
end)

exports("SetPanelAlpha", function(panelId, alpha)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  panel.alpha = alpha or 255
end)

exports("SetPanelEnabled", function(panelId, enabled)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  panel.enabled = (enabled == true)
end)

exports("RaycastPanel", function(panelId, maxDist)
  local panel = PANELS[tostring(panelId)]
  if not panel then return nil end
  return raycastPanelUV(panel, maxDist)
end)

-- Original message-based click (good for menus)
exports("SendClick", function(panelId, u, v, meta)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  local payload = { type = "click", x = u, y = v, meta = meta or {} }
  SendDuiMessage(panel.dui, json.encode(payload))
  return true
end)

exports("SendMessage", function(panelId, messageTable)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  SendDuiMessage(panel.dui, json.encode(messageTable or {}))
  return true
end)

-- Native mouse injection (enables drag, hover, WebAudio gesture unlock, etc.)
exports("SendMouseMove", function(panelId, u, v, opts)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  opts = opts or {}
  local x, y = uvToPixels(panel, u, v, opts.flipY == true)
  SendDuiMouseMove(panel.dui, x, y)
  return true
end)

exports("SendMouseDown", function(panelId, button)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  local btn = (button == "right" and "right") or (button == "middle" and "middle") or "left"
  SendDuiMouseDown(panel.dui, btn)
  return true
end)

exports("SendMouseUp", function(panelId, button)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  local btn = (button == "right" and "right") or (button == "middle" and "middle") or "left"
  SendDuiMouseUp(panel.dui, btn)
  return true
end)

exports("SendMouseWheel", function(panelId, delta)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  SendDuiMouseWheel(panel.dui, delta or 0)
  return true
end)

exports("GetPanelOwner", function(panelId)
  local panel = PANELS[tostring(panelId)]
  if not panel then return nil end
  return panel.owner
end)

-------------------------------------------------------------
-- Render loop
-------------------------------------------------------------
CreateThread(function()
  while true do
    Wait(0)
    for _, panel in pairs(PANELS) do
      drawPanel(panel)
    end
  end
end)

-------------------------------------------------------------
-- Cleanup on resource stop
-------------------------------------------------------------
AddEventHandler("onResourceStop", function(resName)
  if resName == GetCurrentResourceName() then
    for _, panel in pairs(PANELS) do
      destroyDuiForPanel(panel)
    end
    PANELS = {}
    return
  end

  for id, panel in pairs(PANELS) do
    if panel.owner == resName then
      destroyDuiForPanel(panel)
      PANELS[id] = nil
    end
  end
end)
