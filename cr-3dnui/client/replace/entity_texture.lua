-- cr-3dnui/client/replace/entity_texture.lua
-- Per-entity "texture replacement" using DUI-backed DrawSpritePoly overlays.
--
-- Unlike AddReplaceTexture (which is global per TXD/TXN and affects ALL entities
-- sharing that material), this creates a unique DUI + panel per entity instance.
-- Each entity gets its own browser / URL / content — perfect for ATMs, laptops,
-- monitors, kiosks, TVs, etc.
--
-- Under the hood this uses the existing Panel + AttachPanelToEntity system,
-- but provides a simplified "texture-like" API with built-in model presets.
--
-- Public exports (declared in client/main.lua):
--   CreateEntityTexture(opts) -> id
--   SetEntityTextureUrl(id, url, resW, resH)
--   DestroyEntityTexture(id)
--   SendEntityTextureMessage(id, tbl)
--   SendEntityTextureMouseMove(id, u, v, opts)
--   SendEntityTextureMouseDown(id, button)
--   SendEntityTextureMouseUp(id, button)
--   SendEntityTextureMouseWheel(id, delta)
--   GetEntityTextureInfo(id) -> table|nil

CR3D = CR3D or {}

-------------------------------------------------------------
-- Entity texture instances: [tostring(id)] = entry
-------------------------------------------------------------
local ENTITY_TEXTURES = CR3D.ENTITY_TEXTURES or {}
CR3D.ENTITY_TEXTURES = ENTITY_TEXTURES

CR3D.NEXT_ENTITY_TEX_ID = CR3D.NEXT_ENTITY_TEX_ID or 1

-------------------------------------------------------------
-- MODEL PRESETS
-- Pre-measured screen surface definitions for common GTA V props.
-- Each preset defines where the "screen" is relative to the prop origin.
--
-- Keys are joaat model hashes (use backtick syntax: `prop_name`)
-- or string model names. Lookup checks both.
--
-- Fields:
--   localOffset  - vec3: center of the screen in prop-local space
--   localNormal  - vec3: direction the screen faces (outward from surface)
--   localUp      - vec3: "up" direction of the screen content
--   width        - number: screen width in meters
--   height       - number: screen height in meters
--   zOffset      - number: (optional) depth bias to prevent z-fighting
--   frontDotMin  - number: (optional) minimum dot product for front-only rendering
-------------------------------------------------------------
CR3D.MODEL_PRESETS = CR3D.MODEL_PRESETS or {}

-- Helper to register presets with both hash and string keys
local function registerPreset(modelName, preset)
  -- Store by string name (lowercase)
  local nameKey = string.lower(modelName)
  CR3D.MODEL_PRESETS[nameKey] = preset

  -- Store by joaat hash
  local ok, hash = pcall(function() return GetHashKey(modelName) end)
  if ok and hash then
    CR3D.MODEL_PRESETS[hash] = preset
  end
end

-------------------------------------------------------------
-- BUILT-IN PRESETS (common props)
-- These are approximate measurements. Users can override or
-- add their own via exports['cr-3dnui']:RegisterModelPreset()
-------------------------------------------------------------

-- ATMs
registerPreset("prop_atm_01", {
  localOffset  = vector3(0.0, -0.245, 1.01),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.28,
  height       = 0.32,
  zOffset      = 0.003,
  frontDotMin  = 0.05,
})

registerPreset("prop_atm_02", {
  localOffset  = vector3(0.0, -0.245, 1.01),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.28,
  height       = 0.32,
  zOffset      = 0.003,
  frontDotMin  = 0.05,
})

registerPreset("prop_atm_03", {
  localOffset  = vector3(0.0, -0.245, 1.01),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.28,
  height       = 0.32,
  zOffset      = 0.003,
  frontDotMin  = 0.05,
})

-- Laptops
registerPreset("prop_laptop_lester", {
  localOffset  = vector3(-0.24, 0.0, 0.085),
  localNormal  = vector3(-1.0, 0.0, 0.15),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.33,
  height       = 0.21,
  zOffset      = 0.002,
  frontDotMin  = 0.0,
})

registerPreset("prop_laptop_01a", {
  localOffset  = vector3(0.0, 0.0, 0.28),
  localNormal  = vector3(0.0, -0.95, 0.31),
  localUp      = vector3(0.0, 0.31, 0.95),
  width        = 0.30,
  height       = 0.19,
  zOffset      = 0.002,
  frontDotMin  = 0.0,
})

-- Monitors
registerPreset("prop_monitor_01a", {
  localOffset  = vector3(0.0, -0.065, 0.312),
  localNormal  = vector3(0.0, -1.0, 0.06),
  localUp      = vector3(0.0, 0.06, 1.0),
  width        = 0.43,
  height       = 0.31,
  zOffset      = 0.002,
  frontDotMin  = 0.0,
})

registerPreset("prop_monitor_02", {
  localOffset  = vector3(0.0, -0.04, 0.30),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.38,
  height       = 0.28,
  zOffset      = 0.002,
  frontDotMin  = 0.0,
})

-- TVs
registerPreset("prop_tv_flat_01", {
  localOffset  = vector3(0.0, -0.04, 0.0),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 1.10,
  height       = 0.62,
  zOffset      = 0.003,
  frontDotMin  = 0.0,
})

registerPreset("prop_tv_flat_02", {
  localOffset  = vector3(0.0, -0.035, 0.0),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.85,
  height       = 0.48,
  zOffset      = 0.003,
  frontDotMin  = 0.0,
})

registerPreset("prop_tv_flat_03", {
  localOffset  = vector3(0.0, -0.035, 0.0),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.65,
  height       = 0.37,
  zOffset      = 0.003,
  frontDotMin  = 0.0,
})

registerPreset("prop_tv_03", {
  localOffset  = vector3(0.0, -0.08, 0.0),
  localNormal  = vector3(0.0, -1.0, 0.0),
  localUp      = vector3(0.0, 0.0, 1.0),
  width        = 0.48,
  height       = 0.36,
  zOffset      = 0.003,
  frontDotMin  = 0.0,
})

-- Tablet / phone
registerPreset("prop_cs_tablet", {
  localOffset  = vector3(0.0, 0.0, 0.005),
  localNormal  = vector3(0.0, 0.0, 1.0),
  localUp      = vector3(0.0, 1.0, 0.0),
  width        = 0.18,
  height       = 0.13,
  zOffset      = 0.002,
  frontDotMin  = 0.0,
})

-------------------------------------------------------------
-- Preset lookup
-------------------------------------------------------------
local function lookupPreset(modelOrHash)
  if not modelOrHash then return nil end

  -- Direct hash lookup
  if type(modelOrHash) == "number" then
    return CR3D.MODEL_PRESETS[modelOrHash]
  end

  -- String lookup (lowercase)
  if type(modelOrHash) == "string" then
    local lower = string.lower(modelOrHash)
    local preset = CR3D.MODEL_PRESETS[lower]
    if preset then return preset end

    -- Try hash conversion
    local ok, hash = pcall(function() return GetHashKey(modelOrHash) end)
    if ok and hash then
      return CR3D.MODEL_PRESETS[hash]
    end
  end

  return nil
end

-------------------------------------------------------------
-- Internal: Create entity texture overlay
-------------------------------------------------------------
function CR3D.createEntityTextureInternal(opts, ownerOverride)
  opts = opts or {}

  local ent = opts.entity
  if not ent or ent == 0 or not DoesEntityExist(ent) then
    error("[cr-3dnui] CreateEntityTexture requires a valid entity")
  end

  if not opts.url or opts.url == "" then
    error("[cr-3dnui] CreateEntityTexture requires opts.url")
  end

  -- Determine screen surface from model preset or manual overrides
  local preset = nil
  if opts.model then
    preset = lookupPreset(opts.model)
  end
  if not preset then
    -- Try to auto-detect from entity model hash
    local entityModel = GetEntityModel(ent)
    if entityModel then
      preset = lookupPreset(entityModel)
    end
  end

  -- Build final surface definition (manual overrides take priority over preset)
  local localOffset = opts.localOffset or opts.offset or (preset and preset.localOffset) or vector3(0.0, 0.0, 0.0)
  local localNormal = opts.localNormal or opts.normal or (preset and preset.localNormal) or vector3(0.0, -1.0, 0.0)
  local localUp     = opts.localUp or opts.up or (preset and preset.localUp) or vector3(0.0, 0.0, 1.0)
  local width       = opts.width or (preset and preset.width) or 0.5
  local height      = opts.height or (preset and preset.height) or 0.5
  local zOffset     = opts.zOffset or (preset and preset.zOffset) or 0.003
  local frontDotMin = opts.frontDotMin or (preset and preset.frontDotMin) or 0.0
  local frontOnly   = opts.frontOnly
  if frontOnly == nil then
    frontOnly = (preset and preset.frontOnly ~= nil) and preset.frontOnly or true
  end

  -- Generate unique ID
  local id = opts.id or CR3D.NEXT_ENTITY_TEX_ID
  CR3D.NEXT_ENTITY_TEX_ID = (type(id) == "number") and (id + 1) or (CR3D.NEXT_ENTITY_TEX_ID + 1)

  local owner = ownerOverride or "unknown"
  local key = tostring(id)

  -- If reusing ID, destroy old one
  if ENTITY_TEXTURES[key] then
    CR3D.destroyEntityTextureInternal(id)
  end

  -- Create panel + attach to entity using the existing system
  local panelId = nil

  -- Use AttachPanelToEntity from the existing API (internal call)
  local panelOpts = {
    entity = ent,
    url = opts.url,
    resW = opts.resW or 1024,
    resH = opts.resH or 1024,

    width = width,
    height = height,
    alpha = opts.alpha or 255,
    enabled = (opts.enabled == nil) and true or (opts.enabled == true),

    localOffset = localOffset,
    localNormal = localNormal,
    localUp = localUp,

    rotateNormal = true,
    faceCamera = false,
    frontOnly = frontOnly,
    frontDotMin = frontDotMin,
    zOffset = zOffset,
    depthCompensation = opts.depthCompensation or 'screen',

    updateInterval = opts.updateInterval or 0,
    updateMaxDistance = opts.updateMaxDistance or 50.0,
  }

  -- We need to use the internal panel creation + attachment (bypass exports to keep same owner)
  local PANELS = CR3D.PANELS
  local ATTACHMENTS = CR3D.ATTACHMENTS

  -- Create the panel directly
  local pId = opts._panelId or CR3D.NEXT_ID
  CR3D.NEXT_ID = (type(pId) == "number") and (pId + 1) or (CR3D.NEXT_ID + 1)

  local panel = {
    id = pId,
    owner = owner,

    url = panelOpts.url,
    resW = panelOpts.resW,
    resH = panelOpts.resH,

    pos = GetOffsetFromEntityInWorldCoords(ent, localOffset.x, localOffset.y, localOffset.z),
    normal = CR3D.vecNorm(localNormal),
    up = CR3D.vecNorm(localUp),

    inPlaneFlip = (opts.inPlaneFlip == true) or (opts.flip == true),
    width = width,
    height = height,

    alpha = panelOpts.alpha,
    enabled = panelOpts.enabled,
    interactionMode = 'uv',

    zOffset = zOffset,
    depthCompensation = panelOpts.depthCompensation,
    frontOnly = frontOnly,
    frontDotMin = frontDotMin,
    faceCamera = false,

    dui = nil,
    txdName = nil,
    texName = nil,
  }

  -- Create DUI for this panel
  panel.dui = CreateDui(panel.url, panel.resW, panel.resH)
  local handle = GetDuiHandle(panel.dui)
  panel.txdName = ("cr3dnui_etex_txd_%s"):format(pId)
  panel.texName = ("cr3dnui_etex_tex_%s"):format(pId)
  local txd = CreateRuntimeTxd(panel.txdName)
  CreateRuntimeTextureFromDuiHandle(txd, panel.texName, handle)

  PANELS[tostring(pId)] = panel

  -- Setup attachment driver (same as AttachPanelToEntity)
  local function localDirToWorld(e, dir)
    local right, forward, up, _ = GetEntityMatrix(e)
    if not right or not forward or not up then
      return CR3D.vecNorm(dir)
    end
    local w = CR3D.vecAdd(
      CR3D.vecMul(right, dir.x),
      CR3D.vecAdd(CR3D.vecMul(forward, dir.y), CR3D.vecMul(up, dir.z))
    )
    return CR3D.vecNorm(w)
  end

  -- Snap initial transform
  panel.pos = GetOffsetFromEntityInWorldCoords(ent, localOffset.x, localOffset.y, localOffset.z)
  panel.normal = localDirToWorld(ent, localNormal)
  panel.up = localDirToWorld(ent, localUp)

  local maxDist = panelOpts.updateMaxDistance or 50.0
  ATTACHMENTS[tostring(pId)] = {
    entity = ent,
    offset = localOffset,
    localNormal = localNormal,
    localUp = localUp,
    rotateNormal = true,
    updateInterval = panelOpts.updateInterval or 0,
    nextUpdate = 0,
    maxDistSq = maxDist * maxDist,
  }

  panelId = pId

  -- Store the entity texture entry
  local entry = {
    id = id,
    panelId = panelId,
    entity = ent,
    owner = owner,
    url = opts.url,
    resW = panelOpts.resW,
    resH = panelOpts.resH,
    model = opts.model,
    presetUsed = preset ~= nil,
  }

  ENTITY_TEXTURES[key] = entry
  return id
end

-------------------------------------------------------------
-- Internal: Set URL
-------------------------------------------------------------
function CR3D.setEntityTextureUrlInternal(etId, url, resW, resH)
  local key = tostring(etId)
  local entry = ENTITY_TEXTURES[key]
  if not entry then return false end

  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel then return false end

  -- Destroy old DUI, create new one
  if panel.dui then
    DestroyDui(panel.dui)
    panel.dui = nil
  end

  panel.url = url
  if resW then panel.resW = resW end
  if resH then panel.resH = resH end

  panel.dui = CreateDui(panel.url, panel.resW, panel.resH)
  local handle = GetDuiHandle(panel.dui)
  local txd = CreateRuntimeTxd(panel.txdName)
  CreateRuntimeTextureFromDuiHandle(txd, panel.texName, handle)

  entry.url = url
  if resW then entry.resW = resW end
  if resH then entry.resH = resH end

  return true
end

-------------------------------------------------------------
-- Internal: Destroy
-------------------------------------------------------------
function CR3D.destroyEntityTextureInternal(etId)
  local key = tostring(etId)
  local entry = ENTITY_TEXTURES[key]
  if not entry then return false end

  -- Destroy the backing panel (which also cleans up DUI + attachment)
  local panelKey = tostring(entry.panelId)
  local panel = CR3D.PANELS[panelKey]
  if panel then
    CR3D.ATTACHMENTS[panelKey] = nil
    if panel.dui then
      DestroyDui(panel.dui)
      panel.dui = nil
    end
    panel.txdName = nil
    panel.texName = nil
    CR3D.PANELS[panelKey] = nil
  end

  ENTITY_TEXTURES[key] = nil
  return true
end

-------------------------------------------------------------
-- Internal: Get info
-------------------------------------------------------------
function CR3D.getEntityTextureInfoInternal(etId)
  local key = tostring(etId)
  local entry = ENTITY_TEXTURES[key]
  if not entry then return nil end
  return {
    id = entry.id,
    panelId = entry.panelId,
    entity = entry.entity,
    owner = entry.owner,
    url = entry.url,
    resW = entry.resW,
    resH = entry.resH,
    model = entry.model,
    presetUsed = entry.presetUsed,
  }
end

-------------------------------------------------------------
-- Internal: Message forwarding
-------------------------------------------------------------
function CR3D.sendEntityTextureMessageInternal(etId, tbl)
  local entry = ENTITY_TEXTURES[tostring(etId)]
  if not entry then return false end
  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel or not panel.dui then return false end
  SendDuiMessage(panel.dui, json.encode(tbl or {}))
  return true
end

-------------------------------------------------------------
-- Internal: Mouse input forwarding
-------------------------------------------------------------
function CR3D.sendEntityTextureMouseMoveInternal(etId, u, v, opts)
  local entry = ENTITY_TEXTURES[tostring(etId)]
  if not entry then return false end
  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel or not panel.dui then return false end

  opts = opts or {}
  local resW = panel.resW or 1024
  local resH = panel.resH or 1024
  local x = math.floor((u or 0.0) * resW)
  local y = math.floor((v or 0.0) * resH)
  if opts.flipY == true then y = (resH - 1) - y end
  if x < 0 then x = 0 elseif x > resW - 1 then x = resW - 1 end
  if y < 0 then y = 0 elseif y > resH - 1 then y = resH - 1 end
  SendDuiMouseMove(panel.dui, x, y)
  return true
end

function CR3D.sendEntityTextureMouseDownInternal(etId, button)
  local entry = ENTITY_TEXTURES[tostring(etId)]
  if not entry then return false end
  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel or not panel.dui then return false end
  local btn = (button == 'right' and 'right') or (button == 'middle' and 'middle') or 'left'
  SendDuiMouseDown(panel.dui, btn)
  return true
end

function CR3D.sendEntityTextureMouseUpInternal(etId, button)
  local entry = ENTITY_TEXTURES[tostring(etId)]
  if not entry then return false end
  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel or not panel.dui then return false end
  local btn = (button == 'right' and 'right') or (button == 'middle' and 'middle') or 'left'
  SendDuiMouseUp(panel.dui, btn)
  return true
end

function CR3D.sendEntityTextureMouseWheelInternal(etId, delta)
  local entry = ENTITY_TEXTURES[tostring(etId)]
  if not entry then return false end
  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel or not panel.dui then return false end
  SendDuiMouseWheel(panel.dui, delta or 0)
  return true
end

-------------------------------------------------------------
-- Raycast helper: returns hitPos, u, v, t (uses underlying panel)
-------------------------------------------------------------
function CR3D.raycastEntityTextureInternal(etId, maxDist)
  local entry = ENTITY_TEXTURES[tostring(etId)]
  if not entry then return nil end
  local panel = CR3D.PANELS[tostring(entry.panelId)]
  if not panel then return nil end
  return CR3D.raycastPanelUV(panel, maxDist)
end

-------------------------------------------------------------
-- Cleanup helpers
-------------------------------------------------------------
function CR3D.destroyAllEntityTextures()
  local toDestroy = {}
  for id, _ in pairs(ENTITY_TEXTURES) do
    toDestroy[#toDestroy + 1] = id
  end
  for _, id in ipairs(toDestroy) do
    CR3D.destroyEntityTextureInternal(id)
  end
end

function CR3D.destroyEntityTexturesByOwner(owner)
  if not owner then return end
  local toDestroy = {}
  for id, entry in pairs(ENTITY_TEXTURES) do
    if entry and entry.owner == owner then
      toDestroy[#toDestroy + 1] = id
    end
  end
  for _, id in ipairs(toDestroy) do
    CR3D.destroyEntityTextureInternal(id)
  end
end

function CR3D.destroyEntityTexturesByEntity(ent)
  if not ent then return end
  local toDestroy = {}
  for id, entry in pairs(ENTITY_TEXTURES) do
    if entry and entry.entity == ent then
      toDestroy[#toDestroy + 1] = id
    end
  end
  for _, id in ipairs(toDestroy) do
    CR3D.destroyEntityTextureInternal(id)
  end
end
