-- cr-3dnui/client/state.lua
-- Shared runtime state for the library

CR3D = CR3D or {}

-- Panel interaction modes:
--   'uv'      = world-space raycast + UV mapping (default)
--   'key2dui'  = (planned) focused interaction mode (no UV math)

CR3D.PANELS = CR3D.PANELS or {}

-- Panels may optionally include `up` (second orientation axis) for true roll support.

CR3D.NEXT_ID = CR3D.NEXT_ID or 1

-- TXD/Texture Pooling System
-- Solves the memory leak from constantly creating runtime TXDs that cannot be reliably deleted via natives.
CR3D.TxdPool = CR3D.TxdPool or {
  free = {},
  nextId = 1,
}

function CR3D.AcquireTxd()
  if #CR3D.TxdPool.free > 0 then
    return table.remove(CR3D.TxdPool.free)
  end
  local id = CR3D.TxdPool.nextId
  CR3D.TxdPool.nextId = id + 1
  local txdName = "cr3dnui_pool_txd_" .. id
  local texName = "cr3dnui_pool_tex_" .. id
  local txd = CreateRuntimeTxd(txdName)
  return { txdName = txdName, texName = texName, txd = txd }
end

function CR3D.ReleaseTxd(poolObj)
  if not poolObj then return end
  table.insert(CR3D.TxdPool.free, poolObj)
end

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
  hasHit = false,
  u = nil,
  v = nil,
  hitPos = nil,
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
