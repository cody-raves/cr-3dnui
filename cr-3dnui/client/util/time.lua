-- cr-3dnui/client/util/time.lua
-- Timing / caching helpers

CR3D = CR3D or {}

local _playerPos = vector3(0.0, 0.0, 0.0)
local _nextPosUpdate = 0

function CR3D.getPlayerPosCached()
  local now = GetGameTimer()
  local cfg = CR3D.CONFIG or {}
  local interval = cfg.renderCheckInterval or 500

  if now >= _nextPosUpdate then
    _playerPos = GetEntityCoords(PlayerPedId())
    _nextPosUpdate = now + interval
  end

  return _playerPos
end

function CR3D.nowMs()
  return GetGameTimer()
end
