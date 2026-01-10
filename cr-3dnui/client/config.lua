-- cr-3dnui/client/config.lua
-- Central configuration (safe defaults; consumers can edit or override via exports later if desired)

CR3D = CR3D or {}

CR3D.CONFIG = {
  -- Maximum distance to render panels (meters)
  renderDistance = 50.0,

  -- How often to refresh cached player position (ms)
  renderCheckInterval = 500,

  -- Sleep when no panels are nearby (ms)
  idleWait = 100,

  -- Sleep when panels are being rendered (ms). Use 0 for full-frame rendering.
  activeWait = 0,

  -- Sleep for focus loop when focus is disabled (ms)
  focusIdleWait = 100,
}
