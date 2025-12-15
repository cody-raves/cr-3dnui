-- cr-3dnui (API / library resource)
-- Renders DUI-backed HTML pages onto arbitrary world-space quads
-- and provides raycast -> UV helpers for interaction.
--
-- Designed to be USED via exports from other resources.

local PANELS = {}
local NEXT_ID = 1

-------------------------------------------------------------
-- vector helpers
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
-- camera rotation → forward direction
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

  -- fallback for near-horizontal surfaces
  if math.abs(right.x) < 0.001 and math.abs(right.y) < 0.001 and math.abs(right.z) < 0.001 then
    worldUp = vector3(0.0, 1.0, 0.0)
    right = vecCross(planeNormal, worldUp)
  end

  right = vecNorm(right)
  local upWall = vecNorm(vecCross(right, planeNormal))

  local halfW = (width or 1.0) * 0.5
  local halfH = (height or 1.0) * 0.5

  return {
    center = center,
    normal = planeNormal,
    right  = right,
    up     = upWall,
    halfW  = halfW,
    halfH  = halfH
  }
end

-------------------------------------------------------------
-- Draw a single panel quad (2 triangles)
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

  -- U flipped so text is not mirrored (matches your POC)
  DrawSpritePoly(
    v1.x, v1.y, v1.z,
    v2.x, v2.y, v2.z,
    v3.x, v3.y, v3.z,
    r, g, b, a,
    panel.txdName, panel.texName,
    0.0, 1.0, 1.0,
    1.0, 1.0, 1.0,
    1.0, 0.0, 1.0
  )

  DrawSpritePoly(
    v1.x, v1.y, v1.z,
    v3.x, v3.y, v3.z,
    v4.x, v4.y, v4.z,
    r, g, b, a,
    panel.txdName, panel.texName,
    0.0, 1.0, 1.0,
    1.0, 0.0, 1.0,
    0.0, 0.0, 1.0
  )
end

-------------------------------------------------------------
-- Raycast camera ray → hit on a panel (u,v in 0..1)
-- Returns: hitPos, u, v, t
-------------------------------------------------------------
local function raycastPanelUV(panel, maxDist)
  if not panel or not panel.enabled then return nil end

  local basis = makePanelBasis(panel.pos, panel.normal, panel.width, panel.height, panel.zOffset, panel.faceCamera)
  local center, normal, right, upWall, halfW, halfH =
    basis.center, basis.normal, basis.right, basis.up, basis.halfW, basis.halfH

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

  -- v is NOT flipped here; the flip is handled in DrawSpritePoly UVs
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
-- EXPORTS (client)
-------------------------------------------------------------

--- Create a panel.
--- opts = {
---   id = optional number/string,
---   url = "nui://some_resource/html/index.html",
---   pos = vector3(...),
---   normal = vector3(...),
---   width = 1.0, height = 0.6,
---   alpha = 255,
---   resW = 1024, resH = 1024,
---   zOffset = 0.002,
---   faceCamera = true/false,
---   enabled = true/false
--- }
exports("CreatePanel", function(opts)
  opts = opts or {}

  local id = opts.id or NEXT_ID
  if opts.id == nil then
    NEXT_ID = NEXT_ID + 1
  end

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

exports("SetPanelUrl", function(panelId, url, resW, resH)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end

  destroyDuiForPanel(panel)

  panel.url = url
  panel.resW = resW or panel.resW or 1024
  panel.resH = resH or panel.resH or 1024

  createDuiForPanel(panel)
end)

--- Send a Lua table as JSON to the panel's DUI page (window.postMessage → window.addEventListener("message"))
exports("SendMessage", function(panelId, messageTable)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end

  local payload = json.encode(messageTable or {})
  SendDuiMessage(panel.dui, payload)
  return true
end)

--- Raycast the camera onto the panel.
--- Returns hitPos, u, v, t (t = distance along ray)
exports("RaycastPanel", function(panelId, maxDist)
  local panel = PANELS[tostring(panelId)]
  if not panel then return nil end
  return raycastPanelUV(panel, maxDist)
end)

--- Convenience: compute UV (or accept them), then send {type="click", x=u, y=v}.
exports("SendClick", function(panelId, u, v, meta)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end

  if u == nil or v == nil then
    local _, uu, vv = raycastPanelUV(panel, meta and meta.maxDist or nil)
    if not uu then return false end
    u, v = uu, vv
  end

  SendDuiMessage(panel.dui, json.encode({
    type = "click",
    x = u,
    y = v,
    meta = meta or {}
  }))
  return true
end)

exports("GetPanelOwner", function(panelId)
  local panel = PANELS[tostring(panelId)]
  if not panel then return nil end
  return panel.owner
end)

-------------------------------------------------------------
-- Render loop (draw all panels)
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
-- Cleanup on resource stop (library stop OR owner stop)
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
