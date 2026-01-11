-- cr-3dnui/client/focus/focus.lua
-- Focus + keyboard capture helper (raycast/UV based)
-- Cursor-mode / direct mouse forwarding will be added later as a separate interaction mode.

CR3D = CR3D or {}

function CR3D.BeginFocus(panelId, opts)
  if not panelId then return false end
  if not CR3D.PANELS[tostring(panelId)] then return false end
  CR3D.FOCUS.enabled = true
  CR3D.FOCUS.panelId = panelId
  CR3D.FOCUS.opts = opts or {}
  CR3D.FOCUS.lastHit = false
  CR3D.FOCUS.missSince = 0
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

  -- Interaction mode gate: current focus tick path supports UV (raycast + UV) only.
  local mode = panel.interactionMode or panel.interaction or 'uv'
  if mode ~= 'uv' then return false end

  local opts = CR3D.FOCUS.opts or {}
  local maxDist = opts.maxDist or 7.0
  local hitPos, u, v, t = CR3D.raycastPanelUV(panel, maxDist)

  local hit = hitPos ~= nil
  local tNow = CR3D.nowMs()

  if not hit then
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
