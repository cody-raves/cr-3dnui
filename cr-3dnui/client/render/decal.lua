-- cr-3dnui/client/render/decal.lua
-- Third render mode: project a DUI onto world geometry as a persistent native
-- decal (PatchDecalDiffuseMap + AddDecal). Unlike panels there is no per-frame
-- draw cost: once projected, the decal is engine-managed world surface detail,
-- survives at long range, and many decals can share one DUI texture.
--
-- Ideal for: billboards, posters, murals, road markings, wall screens whose
-- content changes rarely (the DUI page can still animate; the decal samples
-- the live texture).
--
-- IMPORTANT - decal types are a global, scarce engine resource:
--   * PatchDecalDiffuseMap(type, txd, txn) rebinds that type EVERYWHERE.
--     Two resources patching the same type will overwrite each other.
--   * You must tell the library which native decal types it may lease via
--     ConfigureDecalTypes({...}). Pick level-loaded types nothing else uses.
--     A battle-tested set from the stock decals.dat is the 9100 series:
--       9100-9104, 9106-9108, 9110-9112, 9115-9119, 9123
--     Avoid 9120/9121/9122: their definitions set ROTATE_CAMERA and the
--     artwork visibly spins with the player camera.
--   * One cr-3dnui decal surface leases one type. The lease is returned on
--     DestroyDecal / resource stop.
--
-- Public exports are declared in client/main.lua:
--   ConfigureDecalTypes(types)            -> allowed pool (required once)
--   CreateDecal(opts)                     -> id
--   SetDecalUrl(id, url, resW, resH)      -> swap content (same type repatched)
--   DestroyDecal(id)                      -> remove + unpatch + release lease
--   GetDecalInfo(id)                      -> status table for debugging

CR3D = CR3D or {}

local DECALS = CR3D.DECALS or {}
CR3D.DECALS = DECALS

local typePool = nil          -- array of allowed native decal types
local typeLeases = {}         -- [decalType] = decal id

-- Some game builds return 1/0 from IsDecalAlive instead of true/false
-- (observed on b3095). Normalize both dialects; nil means unusable answer.
local function decalAliveResult(ok, result)
  if not ok then return nil end
  if result == true or result == 1 then return true end
  if result == false or result == 0 then return false end
  return nil
end

local function err(msg, ...)
  error(("[cr-3dnui] " .. msg):format(...), 0)
end

local function vec(v, name)
  if type(v) == "vector3" then return v end
  if type(v) == "table" and v.x and v.y and v.z then
    return vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0)
  end
  err("%s must be a vector3 or {x,y,z}", name)
end

local function normalize(v)
  local len = #(v)
  if len < 0.0001 then return nil end
  return v / len
end

-------------------------------------------------------------
-- Type pool
-------------------------------------------------------------
function CR3D.configureDecalTypesInternal(types)
  if type(types) ~= "table" or #types == 0 then
    err("ConfigureDecalTypes expects a non-empty array of native decal type ids")
  end
  local pool, seen = {}, {}
  for _, t in ipairs(types) do
    local n = math.floor(tonumber(t) or 0)
    if n > 0 and not seen[n] then
      seen[n] = true
      pool[#pool + 1] = n
    end
  end
  if #pool == 0 then err("ConfigureDecalTypes received no valid type ids") end
  typePool = pool
end

local function leaseType(id)
  if not typePool then
    err("call ConfigureDecalTypes({...}) before CreateDecal; decal types are a global engine resource the library must not guess")
  end
  for _, t in ipairs(typePool) do
    if not typeLeases[t] then
      typeLeases[t] = id
      return t
    end
  end
  err("no free decal type in the configured pool (%d in use); destroy a decal or configure more types", #typePool)
end

local function releaseType(decalType)
  if decalType then typeLeases[decalType] = nil end
end

-------------------------------------------------------------
-- Geometry: orthonormal projection basis
-------------------------------------------------------------
-- AddDecal becomes visually unstable (artwork appears to rotate or shear with
-- the camera) when its side vector carries any component along the projection
-- direction. Always hand it a strictly orthonormal basis.
local function projectionBasis(normal, up)
  local n = normalize(normal)
  if not n then err("opts.normal is degenerate") end
  local reference = up and normalize(up) or vector3(0.0, 0.0, 1.0)
  if not reference or math.abs(reference.x * n.x + reference.y * n.y + reference.z * n.z) > 0.999 then
    -- up (or world-up fallback) is parallel to the normal: pick another axis
    reference = vector3(0.0, 1.0, 0.0)
  end
  -- side = reference x n, then re-derive a clean in-plane up
  local side = normalize(vector3(
    reference.y * n.z - reference.z * n.y,
    reference.z * n.x - reference.x * n.z,
    reference.x * n.y - reference.y * n.x
  ))
  if not side then err("could not derive an orthonormal decal basis from normal/up") end
  return n, side
end

-------------------------------------------------------------
-- DUI + runtime texture (mirrors panel/replace conventions)
-------------------------------------------------------------
local function createDuiForDecal(entry)
  entry.dui = CreateDui(entry.url, entry.resW, entry.resH)
  local handle = GetDuiHandle(entry.dui)
  local txd = CreateRuntimeTxd(entry.txdName)
  CreateRuntimeTextureFromDuiHandle(txd, entry.texName, handle)
end

local function destroyDuiForDecal(entry)
  if entry.dui then
    DestroyDui(entry.dui)
    entry.dui = nil
  end
end

-------------------------------------------------------------
-- Native decal add/remove with the known build quirks handled
-------------------------------------------------------------
local function addNativeDecal(entry)
  local n, side = entry.direction, entry.side
  local origin = entry.pos + entry.outward * entry.surfaceOffset
  local ok, result = pcall(
    AddDecal,
    entry.decalType,
    origin.x, origin.y, origin.z,
    n.x, n.y, n.z,          -- projection direction: into the surface
    side.x, side.y, side.z,
    entry.width, entry.height,
    1.0, 1.0, 1.0,
    entry.alpha,
    -1.0,                   -- never time out; lifecycle is ours
    true,                   -- long range
    false,                  -- dynamic decals are culled far more aggressively
    false
  )
  entry.handle = ok and (tonumber(result) or 0) or 0
  if entry.handle == 0 then
    entry.lastError = ok and "AddDecal returned handle 0" or ("AddDecal failed: %s"):format(tostring(result))
    return false
  end
  entry.lastError = nil
  return true
end

local function removeNativeDecal(entry)
  local handle = entry.handle
  entry.handle = nil
  if not handle or handle == 0 then return end
  -- Same-frame removal of a freshly added decal silently fails on some
  -- builds; retry once on a later frame and verify with the normalized
  -- aliveness answer where the build gives a usable one.
  pcall(RemoveDecal, handle)
  SetTimeout(0, function()
    local okA, raw = pcall(IsDecalAlive, handle)
    if decalAliveResult(okA, raw) == true then
      pcall(RemoveDecal, handle)
    end
  end)
end

-------------------------------------------------------------
-- Internal API used by client/main.lua exports
-------------------------------------------------------------
function CR3D.createDecalInternal(opts, ownerOverride)
  opts = opts or {}
  if type(opts.url) ~= "string" or opts.url == "" then err("CreateDecal requires opts.url") end
  local width = tonumber(opts.width) or err("CreateDecal requires opts.width (metres)")
  local height = tonumber(opts.height) or err("CreateDecal requires opts.height (metres)")
  local pos = vec(opts.pos, "opts.pos")
  local outwardInput = vec(opts.normal, "opts.normal")

  local id = opts.id or CR3D.NEXT_DECAL_ID or 1
  CR3D.NEXT_DECAL_ID = (type(id) == "number") and (id + 1) or ((CR3D.NEXT_DECAL_ID or 1) + 1)
  local key = tostring(id)
  if DECALS[key] then CR3D.destroyDecalInternal(id) end

  local outward, side = projectionBasis(outwardInput, opts.up and vec(opts.up, "opts.up") or nil)

  local entry = {
    id = id,
    owner = ownerOverride or "unknown",
    url = opts.url,
    resW = tonumber(opts.resW) or 1024,
    resH = tonumber(opts.resH) or 1024,
    pos = pos,
    outward = outward,            -- faces the viewer
    direction = outward * -1.0,   -- AddDecal projects along this, into the surface
    side = side,
    width = width + 0.0,
    height = height + 0.0,
    alpha = math.min(1.0, math.max(0.0, tonumber(opts.alpha) or 1.0)),
    -- Starting the projector inside the surface's collision skin makes
    -- AddDecal reject it outright; 0.0666 m is a field-proven clearance.
    surfaceOffset = tonumber(opts.surfaceOffset) or 0.0666,
    txdName = ("cr3dnui_decal_txd_%s"):format(id),
    texName = ("cr3dnui_decal_tex_%s"):format(id),
    handle = nil,
    lastError = nil,
  }

  entry.decalType = leaseType(id)
  createDuiForDecal(entry)
  PatchDecalDiffuseMap(entry.decalType, entry.txdName, entry.texName)
  addNativeDecal(entry)

  DECALS[key] = entry
  return id
end

function CR3D.setDecalUrlInternal(id, url, resW, resH)
  local entry = DECALS[tostring(id)]
  if not entry then return false end
  if type(url) ~= "string" or url == "" then err("SetDecalUrl requires a non-empty url") end
  -- FiveM runtime texture names are effectively one-shot per client session:
  -- recreate the DUI under fresh names and repatch the same leased type.
  destroyDuiForDecal(entry)
  entry.generation = (entry.generation or 0) + 1
  entry.txdName = ("cr3dnui_decal_txd_%s_%d"):format(entry.id, entry.generation)
  entry.texName = ("cr3dnui_decal_tex_%s_%d"):format(entry.id, entry.generation)
  entry.url = url
  if resW then entry.resW = tonumber(resW) or entry.resW end
  if resH then entry.resH = tonumber(resH) or entry.resH end
  createDuiForDecal(entry)
  PatchDecalDiffuseMap(entry.decalType, entry.txdName, entry.texName)
  -- The existing projected decal keeps rendering and samples the newly
  -- patched texture; no re-AddDecal is needed for a pure content swap.
  if not entry.handle or entry.handle == 0 then addNativeDecal(entry) end
  return true
end

function CR3D.destroyDecalInternal(id)
  local key = tostring(id)
  local entry = DECALS[key]
  if not entry then return end
  removeNativeDecal(entry)
  pcall(UnpatchDecalDiffuseMap, entry.decalType)
  releaseType(entry.decalType)
  destroyDuiForDecal(entry)
  DECALS[key] = nil
end

function CR3D.getDecalInfoInternal(id)
  local entry = DECALS[tostring(id)]
  if not entry then return nil end
  local aliveOk, aliveRaw = entry.handle and pcall(IsDecalAlive, entry.handle)
  return {
    id = entry.id,
    owner = entry.owner,
    url = entry.url,
    decalType = entry.decalType,
    handle = entry.handle,
    alive = entry.handle and decalAliveResult(aliveOk, aliveRaw) or false,
    pos = entry.pos,
    width = entry.width,
    height = entry.height,
    lastError = entry.lastError,
  }
end

AddEventHandler("onResourceStop", function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  for key in pairs(DECALS) do
    CR3D.destroyDecalInternal(key)
  end
end)
