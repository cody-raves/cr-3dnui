-- cr-3dnui/client/focus/focus.lua
-- Focus + keyboard capture helper (raycast/UV based)
-- Cursor-mode / direct mouse forwarding will be added later as a separate interaction mode.

CR3D = CR3D or {}

local function _clamp01(x)
  if x < 0.0 then return 0.0 end
  if x > 1.0 then return 1.0 end
  return x
end

local function _cursorNorm()
  local rx, ry = GetActiveScreenResolution()
  if not rx or not ry or rx <= 0 or ry <= 0 then return 0.5, 0.5 end
  local cx, cy = GetNuiCursorPosition()
  return _clamp01((tonumber(cx or 0) or 0) / rx), _clamp01((tonumber(cy or 0) or 0) / ry)
end

local function _raycastPanelNativeCursor(panel, maxDist, frameCam)
  local sx, sy = _cursorNorm()
  local ok, worldPos, worldDir = GetWorldCoordFromScreenCoord(sx, sy)
  if ok ~= true or not worldPos then return nil end

  local camPos = frameCam and frameCam.pos or GetGameplayCamCoord()
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

  if panel.frontOnly and ((CR3D.CONFIG and CR3D.CONFIG.enableFrontCull) ~= false) then
    local toCam = CR3D.vecNorm(CR3D.vecSub(camPos, center))
    local dot = CR3D.vecDot(toCam, normal)
    local minDot = tonumber(panel.frontDotMin) or 0.0
    if dot < minDot then return nil end
  end

  local function _rayHit(origin, dir)
    if not origin or not dir then return nil end
    local denom = CR3D.vecDot(dir, normal)
    if math.abs(denom) < 0.0001 then return nil end
    local t = CR3D.vecDot(CR3D.vecSub(center, origin), normal) / denom
    if t < 0.0 then return nil end
    if maxDist and t > maxDist then return nil end
    local hitPos = CR3D.vecAdd(origin, CR3D.vecMul(dir, t))
    local rel = CR3D.vecSub(hitPos, center)
    local localX = CR3D.vecDot(rel, right) / halfW
    local localY = CR3D.vecDot(rel, upWall) / halfH
    if math.abs(localX) > 1.0 or math.abs(localY) > 1.0 then return nil end
    local u = (localX + 1.0) * 0.5
    local v = (localY + 1.0) * 0.5
    return hitPos, u, v, t
  end

  local dirFromWorldPos = CR3D.vecNorm(CR3D.vecSub(worldPos, camPos))
  local dirA = dirFromWorldPos
  local dirB = nil
  if worldDir and type(worldDir) == "vector3" then
    -- Some runtimes return a normalized direction vector; others return another world-space point.
    local len = CR3D.vecLen(worldDir)
    if len and len > 0.7 and len < 1.3 then
      dirB = CR3D.vecNorm(worldDir)
    else
      dirB = CR3D.vecNorm(CR3D.vecSub(worldDir, camPos))
    end
  end

  -- Try camera-origin ray first (stable with maxDist), then fallback to near-plane origin.
  local hitPos, u, v, t = _rayHit(camPos, dirA)
  if not hitPos and dirB then
    hitPos, u, v, t = _rayHit(camPos, dirB)
  end
  if not hitPos then
    hitPos, u, v, t = _rayHit(worldPos, dirA)
  end
  if not hitPos and dirB then
    hitPos, u, v, t = _rayHit(worldPos, dirB)
  end
  return hitPos, u, v, t
end

function CR3D.BeginFocus(panelId, opts)
  if not panelId then return false end
  if not CR3D.PANELS[tostring(panelId)] then return false end
  CR3D.FOCUS.enabled = true
  CR3D.FOCUS.panelId = panelId
  CR3D.FOCUS.opts = opts or {}
  CR3D.FOCUS.lastHit = false
  CR3D.FOCUS.missSince = 0
  CR3D.FOCUS.hasHit = false
  CR3D.FOCUS.u = nil
  CR3D.FOCUS.v = nil
  CR3D.FOCUS.hitPos = nil
  return true
end

function CR3D.EndFocus()
  if CR3D.FOCUS.enabled and CR3D.FOCUS.opts and CR3D.FOCUS.opts.sendFocusMessages and CR3D.FOCUS.panelId then
    exports["cr-3dnui"]:SendMessage(CR3D.FOCUS.panelId, { type = "focus", state = false })
  end
  CR3D.FOCUS.enabled = false
  CR3D.FOCUS.panelId = nil
  CR3D.FOCUS.opts = {}
  CR3D.FOCUS.lastHit = false
  CR3D.FOCUS.missSince = 0
  CR3D.FOCUS.hasHit = false
  CR3D.FOCUS.u = nil
  CR3D.FOCUS.v = nil
  CR3D.FOCUS.hitPos = nil
  return true
end

function CR3D.IsFocused()
  return CR3D.FOCUS.enabled == true, CR3D.FOCUS.panelId
end

function CR3D.SetFocusKeymap(keymap)
  CR3D.FOCUS.keymap = keymap or {}
  return true
end

-- FocusTick() -> focusedHit, u, v
function CR3D.FocusTick()
  if not CR3D.FOCUS.enabled or not CR3D.FOCUS.panelId then return false end
  local panel = CR3D.PANELS[tostring(CR3D.FOCUS.panelId)]
  if not panel then return false end

  -- Interaction modes:
  -- - uv: camera-centered raycast
  -- - native_mouse: screen-cursor raycast
  local mode = panel.interactionMode or panel.interaction or 'uv'

  local opts = CR3D.FOCUS.opts or {}
  local maxDist = opts.maxDist or 7.0
  local frameCam = CR3D.getFrameCamData and CR3D.getFrameCamData() or nil
  local hitPos, u, v, t = nil, nil, nil, nil
  if mode == 'native_mouse' then
    hitPos, u, v, t = _raycastPanelNativeCursor(panel, maxDist, frameCam)
  elseif mode == 'uv' then
    hitPos, u, v, t = CR3D.raycastPanelUV(panel, maxDist, frameCam)
  else
    return false
  end

  local hit = hitPos ~= nil
  local tNow = CR3D.nowMs()

  if not hit then
    CR3D.FOCUS.hasHit = false
    CR3D.FOCUS.u = nil
    CR3D.FOCUS.v = nil
    CR3D.FOCUS.hitPos = nil
    if CR3D.FOCUS.lastHit then
      CR3D.FOCUS.lastHit = false
      if opts.sendFocusMessages then
        exports["cr-3dnui"]:SendMessage(CR3D.FOCUS.panelId, { type = "focus", state = false })
      end
      CR3D.FOCUS.missSince = tNow
    end

    if (opts.autoExitOnMiss ~= false) then
      local grace = opts.missGraceMs or 250
      if CR3D.FOCUS.missSince ~= 0 and (tNow - CR3D.FOCUS.missSince) >= grace then
        exports["cr-3dnui"]:EndFocus()
      end
    end

    return false
  end

  -- hit
  CR3D.FOCUS.hasHit = true
  CR3D.FOCUS.u = u
  CR3D.FOCUS.v = v
  CR3D.FOCUS.hitPos = hitPos
  if not CR3D.FOCUS.lastHit then
    CR3D.FOCUS.lastHit = true
    CR3D.FOCUS.missSince = 0
    if opts.sendFocusMessages then
      exports["cr-3dnui"]:SendMessage(CR3D.FOCUS.panelId, { type = "focus", state = true })
    end
  end

  if opts.drawCursor then
    exports["cr-3dnui"]:DrawCursor(0.5, 0.5, true)
  end

  if opts.strict then
    DisableAllControlActions(0)
  end

  if opts.allowLook ~= false then
    EnableControlAction(0, 1, true) -- LOOK_LR
    EnableControlAction(0, 2, true) -- LOOK_UD
  end

  if opts.allowPause ~= false then
    local exits = opts.exitControls or {200, 177}
    for _, cid in ipairs(exits) do
      EnableControlAction(0, cid, true)
      if IsDisabledControlJustPressed(0, cid) or IsControlJustPressed(0, cid) then
        exports["cr-3dnui"]:EndFocus()
        return false
      end
    end
  end

  -- forward key presses (press-only)
  for _, k in ipairs(CR3D.FOCUS.keymap or {}) do
    if IsDisabledControlJustPressed(0, k.id) or IsControlJustPressed(0, k.id) then
      exports["cr-3dnui"]:SendMessage(CR3D.FOCUS.panelId, { type = "key", key = k.key, code = k.id })
    end
  end

  return true, u, v
end
