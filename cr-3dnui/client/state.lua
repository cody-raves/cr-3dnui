-- cr-3dnui/client/state.lua
-- Shared runtime state for the library

CR3D = CR3D or {}

CR3D.PANELS = CR3D.PANELS or {}
CR3D.NEXT_ID = CR3D.NEXT_ID or 1

-- Entity attachments driver: [tostring(panelId)] = attachmentData
CR3D.ATTACHMENTS = CR3D.ATTACHMENTS or {}
CR3D.ATTACH_MAX_WAIT = CR3D.ATTACH_MAX_WAIT or 250

-- Focus state (raycast/UV focus mode) - cursor-mode exports come later
CR3D.FOCUS = CR3D.FOCUS or {
  enabled = false,
  panelId = nil,
  opts = {},
  keymap = {},
  lastHit = false,
  missSince = 0,
}

-- Built-in HUD cursor (optional helper)
-- Consumers can call exports['cr-3dnui']:DrawCursor(...) or enable via BeginFocus({ drawCursor = true })
CR3D.CURSOR = CR3D.CURSOR or {
  txd = "cr3dnui_cursor_txd",
  tex = "cursor",
  ready = false
}

CreateThread(function()
  Wait(0)
  local txd = CreateRuntimeTxd(CR3D.CURSOR.txd)
  CreateRuntimeTextureFromImage(txd, CR3D.CURSOR.tex, "assets/cursor.png")
  CR3D.CURSOR.ready = true
end)
