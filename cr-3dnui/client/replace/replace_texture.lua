-- cr-3dnui/client/replace/replace_texture.lua
-- Alternative render mode: draw a DUI onto an existing model material via AddReplaceTexture.
-- Ideal for props/vehicles that already have a "screen" texture (ATM, laptop, kiosk, etc).
--
-- Public exports are declared in client/main.lua:
--   CreateReplaceTexture(opts) -> id
--   SetReplaceTextureUrl(id, url, resW, resH)
--   DestroyReplaceTexture(id)

CR3D = CR3D or {}

local REPLACES = CR3D.REPLACES or {}
CR3D.REPLACES = REPLACES

-------------------------------------------------------------
-- Internal helpers
-------------------------------------------------------------
local function _assertNonEmptyStr(v, name)
  if type(v) ~= "string" or v == "" then
    error(("[cr-3dnui] %s must be a non-empty string"):format(name or "value"))
  end
end

local function _destroyDui(entry)
  if entry and entry.dui then
    DestroyDui(entry.dui)
    entry.dui = nil
  end
end

local function _createOrUpdateRuntimeTex(entry)
  _assertNonEmptyStr(entry.url, "opts.url")

  entry.dui = CreateDui(entry.url, entry.resW or 1024, entry.resH or 1024)
  local handle = GetDuiHandle(entry.dui)

  local txd = CreateRuntimeTxd(entry.rtTxdName)
  CreateRuntimeTextureFromDuiHandle(txd, entry.rtTexName, handle)
end

-------------------------------------------------------------
-- Internal API used by client/main.lua exports
-------------------------------------------------------------
function CR3D.createReplaceTextureInternal(opts, ownerOverride)
  opts = opts or {}

  _assertNonEmptyStr(opts.origTxd, "opts.origTxd")
  _assertNonEmptyStr(opts.origTxn, "opts.origTxn")
  _assertNonEmptyStr(opts.url, "opts.url")

  local id = opts.id or CR3D.NEXT_REPLACE_ID or 1
  CR3D.NEXT_REPLACE_ID = (type(id) == "number") and (id + 1) or ((CR3D.NEXT_REPLACE_ID or 1) + 1)

  local key = tostring(id)
  if REPLACES[key] then
    -- If caller reuses an ID, cleanly replace it.
    CR3D.destroyReplaceTextureInternal(id)
  end

  local entry = {
    id = id,
    owner = ownerOverride or "unknown",

    origTxd = opts.origTxd,
    origTxn = opts.origTxn,

    url = opts.url,
    resW = opts.resW or 1024,
    resH = opts.resH or 1024,

    rtTxdName = opts.runtimeTxdName or ("cr3dnui_rttxd_%s"):format(id),
    rtTexName = opts.runtimeTexName or ("cr3dnui_rttex_%s"):format(id),

    dui = nil,
  }

  _createOrUpdateRuntimeTex(entry)

  -- Apply the runtime texture to the target material/texture.
  AddReplaceTexture(entry.origTxd, entry.origTxn, entry.rtTxdName, entry.rtTexName)

  REPLACES[key] = entry
  return id
end

function CR3D.setReplaceTextureUrlInternal(replaceId, url, resW, resH)
  local key = tostring(replaceId)
  local entry = REPLACES[key]
  if not entry then return false end

  _assertNonEmptyStr(url, "url")

  -- Keep the same runtime txd/tex; just update the DUI backing it.
  _destroyDui(entry)
  entry.url = url
  if resW then entry.resW = resW end
  if resH then entry.resH = resH end
  _createOrUpdateRuntimeTex(entry)
  return true
end

function CR3D.destroyReplaceTextureInternal(replaceId)
  local key = tostring(replaceId)
  local entry = REPLACES[key]
  if not entry then return false end

  -- Restore original texture/material.
  RemoveReplaceTexture(entry.origTxd, entry.origTxn)

  _destroyDui(entry)
  REPLACES[key] = nil
  return true
end

-- Cleanup helpers used by client/main.lua
function CR3D.destroyAllReplaces()
  for id, _ in pairs(REPLACES) do
    CR3D.destroyReplaceTextureInternal(id)
  end
end

function CR3D.destroyReplacesByOwner(owner)
  if not owner then return end
  local toDestroy = {}
  for id, entry in pairs(REPLACES) do
    if entry and entry.owner == owner then
      toDestroy[#toDestroy + 1] = id
    end
  end
  for _, id in ipairs(toDestroy) do
    CR3D.destroyReplaceTextureInternal(id)
  end
end


-------------------------------------------------------------
-- ReplaceTexture: input helpers (mouse / wheel / keys)
-------------------------------------------------------------

function CR3D.sendReplaceMessageInternal(replaceId, tbl)
  local r = CR3D.REPLACES[tostring(replaceId)]
  if not r or not r.dui then return false end
  SendDuiMessage(r.dui, json.encode(tbl or {}))
  return true
end

function CR3D.sendReplaceMouseMoveInternal(replaceId, u, v, opts)
  local r = CR3D.REPLACES[tostring(replaceId)]
  if not r or not r.dui then return false end
  opts = opts or {}
  local resW = r.resW or 1024
  local resH = r.resH or 1024
  local x = math.floor((u or 0.0) * resW)
  local y = math.floor((v or 0.0) * resH)
  if opts.flipY == true then y = (resH - 1) - y end
  if x < 0 then x = 0 elseif x > resW - 1 then x = resW - 1 end
  if y < 0 then y = 0 elseif y > resH - 1 then y = resH - 1 end
  SendDuiMouseMove(r.dui, x, y)
  return true
end

function CR3D.sendReplaceMouseDownInternal(replaceId, button)
  local r = CR3D.REPLACES[tostring(replaceId)]
  if not r or not r.dui then return false end
  local btn = (button == 'right' and 'right') or (button == 'middle' and 'middle') or 'left'
  SendDuiMouseDown(r.dui, btn)
  return true
end

function CR3D.sendReplaceMouseUpInternal(replaceId, button)
  local r = CR3D.REPLACES[tostring(replaceId)]
  if not r or not r.dui then return false end
  local btn = (button == 'right' and 'right') or (button == 'middle' and 'middle') or 'left'
  SendDuiMouseUp(r.dui, btn)
  return true
end

function CR3D.sendReplaceMouseWheelInternal(replaceId, delta)
  local r = CR3D.REPLACES[tostring(replaceId)]
  if not r or not r.dui then return false end
  SendDuiMouseWheel(r.dui, delta or 0)
  return true
end

function CR3D.destroyReplacesByOwnerInternal(owner)
  local toDestroy = {}
  for id, r in pairs(CR3D.REPLACES) do
    if r and r.owner == owner then
      toDestroy[#toDestroy+1] = id
    end
  end
  for _, id in ipairs(toDestroy) do
    CR3D.destroyReplaceTextureInternal(id)
  end
end
