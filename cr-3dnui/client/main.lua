-- cr-3dnui (library) - client/main.lua
-- Renders DUI-backed HTML pages on arbitrary world-space quads,
-- raycast -> UV helpers, optional native mouse injection,
-- focus + keyboard capture helpers, and entity attachment helper.

CR3D = CR3D or {}

local PANELS = CR3D.PANELS
local ATTACHMENTS = CR3D.ATTACHMENTS

-------------------------------------------------------------
-- Draw HUD cursor export
-------------------------------------------------------------
exports("DrawCursor", function(cx, cy, isHit, opts)
  if not (CR3D.CURSOR and CR3D.CURSOR.ready) then return false end
  opts = opts or {}

  local w = opts.w or 0.015
  local h = opts.h or 0.03

  local tipX = opts.tipX or 0.0
  local tipY = opts.tipY or 0.0

  local drawX = (cx or 0.5) + (w * (0.5 - tipX))
  local drawY = (cy or 0.5) + (h * (0.5 - tipY))

  local r, g, b, a = opts.r or 255, opts.g or 255, opts.b or 255, opts.a or 235
  if isHit then
    r, g, b, a = opts.hitR or 0, opts.hitG or 255, opts.hitB or 0, opts.hitA or 235
  end

  DrawSprite(CR3D.CURSOR.txd, CR3D.CURSOR.tex, drawX, drawY, w, h, 0.0, r, g, b, a)
  return true
end)

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
-- Internal create/destroy
-------------------------------------------------------------
local function createPanelInternal(opts, ownerOverride)
  opts = opts or {}

  local id = opts.id or CR3D.NEXT_ID
  CR3D.NEXT_ID = (type(id) == "number") and (id + 1) or (CR3D.NEXT_ID + 1)

  local owner = ownerOverride or "unknown"
  local panel = {
    id = id,
    owner = owner,

    url = opts.url,
    resW = opts.resW or 1024,
    resH = opts.resH or 1024,

    pos = opts.pos or vector3(0.0, 0.0, 0.0),
    normal = opts.normal or vector3(0.0, 0.0, 1.0),
    -- Optional: 'up' axis for full roll support (if nil, renderer falls back to world-up)
    up = opts.up or opts.localUp,


    -- Optional: stable 180° in-plane rotation to correct mirroring/upside-down without camera-based flipping
    inPlaneFlip = (opts.inPlaneFlip == true) or (opts.flip == true),
    width = opts.width or 1.0,
    height = opts.height or 1.0,

    alpha = opts.alpha or 255,
    enabled = (opts.enabled == nil) and true or (opts.enabled == true),
    -- Interaction model (defaults to UV/raycast)
    interactionMode = (opts.interactionMode or opts.interaction or 'uv'),

    -- Optional depth bias. If nil, makePanelBasis will pick a safe default.
    zOffset = opts.zOffset,

    -- Optional helpers for "screen-like" surfaces:
    -- depthCompensation = "screen" picks safer defaults for tilted monitor props.
    depthCompensation = opts.depthCompensation,

    -- Optional: render / interact only from the front side of the panel.
    frontOnly = (opts.frontOnly == true),
    frontDotMin = tonumber(opts.frontDotMin) or 0.0,

    -- If nil, default true (matches legacy behavior)
    faceCamera = (opts.faceCamera == nil) and true or (opts.faceCamera == true),

    dui = nil,
    txdName = nil,
    texName = nil,
  }

  createDuiForPanel(panel)
  PANELS[tostring(id)] = panel
  return id
end

local function destroyPanelInternal(panelId)
  local key = tostring(panelId)
  local panel = PANELS[key]
  if not panel then return end

  ATTACHMENTS[key] = nil
  destroyDuiForPanel(panel)
  PANELS[key] = nil
end

-------------------------------------------------------------
-- EXPORTS (client): Panel lifecycle
-------------------------------------------------------------
exports("CreatePanel", function(opts)
  return createPanelInternal(opts or {}, GetInvokingResource() or "unknown")
end)

exports("DestroyPanel", function(panelId)
  destroyPanelInternal(panelId)
end)

exports("SetPanelTransform", function(panelId, pos, normal, up)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  if pos then panel.pos = pos end
  if normal then panel.normal = normal end
  if up then panel.up = up end
end)

exports("SetPanelSize", function(panelId, width, height)
  local panel = PANELS[tostring(panelId)]
  if not panel then return end
  if width then panel.width = width end
  if height then panel.height = height end
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

-- NEW: Helpers
exports("SetPanelFacing", function(panelId, frontOnly, frontDotMin)
  local panel = PANELS[tostring(panelId)]
  if not panel then return false end
  panel.frontOnly = (frontOnly == true)
  if frontDotMin ~= nil then
    panel.frontDotMin = tonumber(frontDotMin) or (panel.frontDotMin or 0.0)
  end
  return true
end)

exports("SetPanelDepthCompensation", function(panelId, mode)
  local panel = PANELS[tostring(panelId)]
  if not panel then return false end
  panel.depthCompensation = mode -- nil | "screen"
  return true
end)

exports("SetPanelZOffset", function(panelId, zOffset)
  local panel = PANELS[tostring(panelId)]
  if not panel then return false end
  panel.zOffset = zOffset -- can be nil to use defaults from depthCompensation
  return true
end)

-------------------------------------------------------------
-- Attachment helper (transform driver)
-------------------------------------------------------------
local function asVec3(v, fallback)
  if v == nil then return fallback end
  if type(v) == "vector3" then return v end
  if type(v) == "table" and v.x ~= nil and v.y ~= nil and v.z ~= nil then
    return vector3(tonumber(v.x) or 0.0, tonumber(v.y) or 0.0, tonumber(v.z) or 0.0)
  end
  return fallback
end

local function localDirToWorld(ent, localDir)
  local right, forward, up, _ = GetEntityMatrix(ent)
  if not right or not forward or not up then
    return CR3D.vecNorm(localDir)
  end
  local w = CR3D.vecAdd(CR3D.vecMul(right, localDir.x), CR3D.vecAdd(CR3D.vecMul(forward, localDir.y), CR3D.vecMul(up, localDir.z)))
  return CR3D.vecNorm(w)
end


-- Convert an Euler rotation (degrees) to basis vectors (right/forward/up) in world space.
-- GTA/FiveM rotations use: x=pitch, y=roll, z=yaw (degrees).
local function rotToAxes(rot)
  local x = math.rad(rot.x or 0.0)
  local y = math.rad(rot.y or 0.0)
  local z = math.rad(rot.z or 0.0)

  local cosx, sinx = math.cos(x), math.sin(x)
  local cosy, siny = math.cos(y), math.sin(y)
  local cosz, sinz = math.cos(z), math.sin(z)

  -- Forward vector
  local forward = vector3(-sinz * cosx, cosz * cosx, sinx)
  -- Right vector
  local right = vector3(
    cosz * cosy + sinz * sinx * siny,
    sinz * cosy - cosz * sinx * siny,
    -cosx * siny
  )
  -- Up vector
  local up = vector3(
    cosz * siny - sinz * sinx * cosy,
    sinz * siny + cosz * sinx * cosy,
    cosx * cosy
  )

  return right, forward, up
end

local function axesLocalToWorld(right, forward, up, v)
  return CR3D.vecAdd(
    CR3D.vecAdd(CR3D.vecMul(right, v.x), CR3D.vecMul(forward, v.y)),
    CR3D.vecMul(up, v.z)
  )
end

local function getBoneWorldPos(ent, boneIndex)
  if GetWorldPositionOfEntityBone then
    return GetWorldPositionOfEntityBone(ent, boneIndex)
  end
  if _GET_ENTITY_BONE_POSITION_2 then
    return _GET_ENTITY_BONE_POSITION_2(ent, boneIndex)
  end
  if GetEntityBonePosition_2 then
    return GetEntityBonePosition_2(ent, boneIndex)
  end
  return nil
end

local function getBoneWorldRot(ent, boneIndex)
  if GetWorldRotationOfEntityBone then
    return GetWorldRotationOfEntityBone(ent, boneIndex)
  end
  if _GET_ENTITY_BONE_ROTATION then
    return _GET_ENTITY_BONE_ROTATION(ent, boneIndex)
  end
  if GetEntityBoneRotation then
    return GetEntityBoneRotation(ent, boneIndex)
  end
  return vector3(0.0, 0.0, 0.0)
end

exports("AttachPanelToEntity", function(opts)
  opts = opts or {}

  local ent = opts.entity
  if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end

  local owner = GetInvokingResource() or "unknown"

  -- Allow attaching an existing panel, or create + attach in one call.
  local panelId = opts.panelId
  if panelId then
    if not PANELS[tostring(panelId)] then return nil end
  else
    local offset = asVec3(opts.offset or opts.localOffset, vector3(0.0, 0.0, 0.0))
    local localNormal = asVec3(opts.localNormal, asVec3(opts.normal, vector3(0.0, 0.0, 1.0)))
    local localUp = asVec3(opts.localUp, asVec3(opts.up, nil))
    local rotateNormal = (opts.rotateNormal == nil) and true or (opts.rotateNormal == true)

    local posWorld = GetOffsetFromEntityInWorldCoords(ent, offset.x, offset.y, offset.z)
    local normalWorld = rotateNormal and localDirToWorld(ent, localNormal) or CR3D.vecNorm(localNormal)
    local upWorld = nil
    if localUp then
      upWorld = rotateNormal and localDirToWorld(ent, localUp) or CR3D.vecNorm(localUp)
    end

    panelId = createPanelInternal({
      id = opts.id,
      url = opts.url,
      resW = opts.resW,
      resH = opts.resH,
      pos = posWorld,
      normal = normalWorld,
      up = upWorld,
      width = opts.width,
      height = opts.height,
      alpha = opts.alpha,
      enabled = opts.enabled,

      zOffset = opts.zOffset,
      depthCompensation = opts.depthCompensation,
      frontOnly = opts.frontOnly,
      frontDotMin = opts.frontDotMin,
      faceCamera = opts.faceCamera,
    }, owner)
  end

  local key = tostring(panelId)

  local offset = asVec3(opts.offset or opts.localOffset, vector3(0.0, 0.0, 0.0))
  local localNormal = asVec3(opts.localNormal, asVec3(opts.normal, vector3(0.0, 0.0, 1.0)))
  local localUp = asVec3(opts.localUp, asVec3(opts.up, nil))
  local rotateNormal = (opts.rotateNormal == nil) and true or (opts.rotateNormal == true)

  local interval = tonumber(opts.updateInterval or opts.interval or 16) or 16
  if interval < 0 then interval = 0 end

  local updateMaxDist = tonumber(opts.updateMaxDistance or opts.maxUpdateDistance)
  local maxDistSq = updateMaxDist and (updateMaxDist * updateMaxDist) or nil

  ATTACHMENTS[key] = {
    entity = ent,
    offset = offset,
    localNormal = localNormal,
    localUp = localUp,
    rotateNormal = rotateNormal,
    updateInterval = interval,
    nextUpdate = 0,
    maxDistSq = maxDistSq,
  }

  -- Snap immediately.
  local panel = PANELS[key]
  if panel then
    -- Allow updating helper options on attach calls (handy for tuning).
    if opts.zOffset ~= nil then panel.zOffset = opts.zOffset end
    if opts.depthCompensation ~= nil then panel.depthCompensation = opts.depthCompensation end
    if opts.frontOnly ~= nil then panel.frontOnly = (opts.frontOnly == true) end
    if opts.frontDotMin ~= nil then panel.frontDotMin = tonumber(opts.frontDotMin) or (panel.frontDotMin or 0.0) end
    if opts.faceCamera ~= nil then panel.faceCamera = (opts.faceCamera == true) end

    panel.pos = GetOffsetFromEntityInWorldCoords(ent, offset.x, offset.y, offset.z)
    panel.normal = rotateNormal and localDirToWorld(ent, localNormal) or CR3D.vecNorm(localNormal)
    if localUp then
      panel.up = rotateNormal and localDirToWorld(ent, localUp) or CR3D.vecNorm(localUp)
    end
  end

  return panelId
end)


-- Attach a panel to a specific bone on an entity (vehicles, peds, props with bones).
-- Uses the bone transform as the attachment source.
exports("AttachPanelToBone", function(opts)
    if type(opts) ~= "table" then return nil end
    local ent = opts.entity
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end

    local boneIndex = opts.boneIndex
    local boneName = opts.boneName or opts.bone

    if not boneIndex then
        if type(boneName) == "string" and boneName ~= "" then
            boneIndex = GetEntityBoneIndexByName(ent, boneName)
        end
    end

    if not boneIndex or boneIndex == -1 then
        if boneName then
            print(('[cr-3dnui] AttachPanelToBone: bone not found (%s)'):format(tostring(boneName)))
        else
            print("[cr-3dnui] AttachPanelToBone: missing boneName/boneIndex")
        end
        return nil
    end

    local panelId = createPanelInternal(opts, GetCurrentResourceName())
    if not panelId then return nil end

    ATTACHMENTS[panelId] = {
        entity = ent,
        boneIndex = boneIndex,
        boneName = boneName,

        offset = opts.localOffset or vector3(0,0,0),
        localNormal = opts.localNormal or vector3(0,1,0),
        localUp = opts.localUp or opts.up,

        rotateNormal = (opts.rotateNormal ~= false),
        updateInterval = opts.updateInterval,

        -- Distance-based update culling (transform only)
        maxDistSq = opts.updateMaxDistance and (opts.updateMaxDistance * opts.updateMaxDistance) or nil,

        nextUpdate = 0
    }

    return panelId
end)

-------------------------------------------------------------
-- EXPORTS: Raycast helpers
-------------------------------------------------------------
exports("RaycastPanel", function(panelId, maxDist)
  local panel = PANELS[tostring(panelId)]
  if not panel then return nil end
  return CR3D.raycastPanelUV(panel, maxDist)
end)

exports("RaycastPanels", function(maxDist)
  local bestId, bestHit, bestU, bestV, bestT = nil, nil, nil, nil, nil
  for id, panel in pairs(PANELS) do
    local hitPos, u, v, t = CR3D.raycastPanelUV(panel, maxDist)
    if hitPos then
      if not bestT or t < bestT then
        bestId, bestHit, bestU, bestV, bestT = tonumber(id) or id, hitPos, u, v, t
      end
    end
  end
  if not bestId then return nil end
  return bestId, bestHit, bestU, bestV, bestT
end)

-------------------------------------------------------------
-- EXPORTS: Message + native mouse injection (UV path)
-------------------------------------------------------------
exports("SendClick", function(panelId, u, v, meta)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  local payload = { type = "click", x = u, y = v, meta = meta or {} }
  SendDuiMessage(panel.dui, json.encode(payload))
  return true
end)

exports("SendMessage", function(panelId, messageTable)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  SendDuiMessage(panel.dui, json.encode(messageTable or {}))
  return true
end)

exports("SendMouseMove", function(panelId, u, v, opts)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  opts = opts or {}
  local x, y = CR3D.uvToPixels(panel, u, v, opts.flipY == true)
  SendDuiMouseMove(panel.dui, x, y)
  return true
end)

exports("SendMouseDown", function(panelId, button)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  local btn = (button == "right" and "right") or (button == "middle" and "middle") or "left"
  SendDuiMouseDown(panel.dui, btn)
  return true
end)

exports("SendMouseUp", function(panelId, button)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  local btn = (button == "right" and "right") or (button == "middle" and "middle") or "left"
  SendDuiMouseUp(panel.dui, btn)
  return true
end)

exports("SendMouseWheel", function(panelId, delta)
  local panel = PANELS[tostring(panelId)]
  if not panel or not panel.dui then return false end
  SendDuiMouseWheel(panel.dui, delta or 0)
  return true
end)

exports("GetPanelOwner", function(panelId)
  local panel = PANELS[tostring(panelId)]
  if not panel then return nil end
  return panel.owner
end)

-------------------------------------------------------------
-- EXPORTS: Focus wrappers (raycast/UV focus)
-------------------------------------------------------------
exports("BeginFocus", function(panelId, opts)
  return CR3D.BeginFocus(panelId, opts)
end)

exports("EndFocus", function()
  return CR3D.EndFocus()
end)

exports("IsFocused", function()
  return CR3D.IsFocused()
end)

exports("SetFocusKeymap", function(keymap)
  return CR3D.SetFocusKeymap(keymap)
end)

exports("FocusTick", function()
  return CR3D.FocusTick()
end)

-------------------------------------------------------------
-- Attachment update loop (single driver for all entity-attached panels)
-------------------------------------------------------------
CreateThread(function()
  local ATTACH_MAX_WAIT = CR3D.ATTACH_MAX_WAIT or 250

  while true do
    if next(ATTACHMENTS) == nil then
      Wait(ATTACH_MAX_WAIT)
    else
      local now = GetGameTimer()
      local ppos = CR3D.getPlayerPosCached()
      local minWait = ATTACH_MAX_WAIT

      for key, a in pairs(ATTACHMENTS) do
        local panel = PANELS[key]
        if not panel then
          ATTACHMENTS[key] = nil
        else
          if not DoesEntityExist(a.entity) then
            destroyPanelInternal(key)
          else
            if now >= (a.nextUpdate or 0) then
              local doUpdate = true
              if a.maxDistSq then
                local epos = GetEntityCoords(a.entity)
                doUpdate = CR3D.vecDistSq(ppos, epos) <= a.maxDistSq
              end

              if doUpdate then
                panel.pos = GetOffsetFromEntityInWorldCoords(a.entity, a.offset.x, a.offset.y, a.offset.z)
                panel.normal = a.rotateNormal and localDirToWorld(a.entity, a.localNormal) or CR3D.vecNorm(a.localNormal)
                if a.localUp then
                  panel.up = a.rotateNormal and localDirToWorld(a.entity, a.localUp) or CR3D.vecNorm(a.localUp)
                end
              end

              local step = a.updateInterval or 16
              if step < 0 then step = 0 end
              a.nextUpdate = now + step
            end

            local due = (a.nextUpdate or 0) - now
            if due < minWait then minWait = due end
          end
        end
      end

      if minWait < 0 then minWait = 0 end
      if minWait > ATTACH_MAX_WAIT then minWait = ATTACH_MAX_WAIT end
      Wait(minWait)
    end
  end
end)

-------------------------------------------------------------
-- Render loop (distance culled + adaptive sleeps)
-------------------------------------------------------------
CreateThread(function()
  local maxDist = (CR3D.CONFIG and CR3D.CONFIG.renderDistance) or 50.0
  local maxDistSq = maxDist * maxDist

  while true do
    local waitMs = (CR3D.CONFIG and CR3D.CONFIG.idleWait) or 100
    local ppos = CR3D.getPlayerPosCached()
    local drewAny = false

    -- If user changes CONFIG.renderDistance at runtime, reflect it.
    local cfgDist = (CR3D.CONFIG and CR3D.CONFIG.renderDistance) or 50.0
    if cfgDist ~= maxDist then
      maxDist = cfgDist
      maxDistSq = maxDist * maxDist
    end

    for _, panel in pairs(PANELS) do
      if panel and panel.enabled and panel.dui then
        if CR3D.vecDistSq(ppos, panel.pos) <= maxDistSq then
          CR3D.drawPanel(panel)
          drewAny = true
        end
      end
    end

    if drewAny then
      waitMs = (CR3D.CONFIG and CR3D.CONFIG.activeWait) or 0
    end

    Wait(waitMs)
  end
end)

-------------------------------------------------------------
-- Focus loop (only runs at 0ms when focused)
-------------------------------------------------------------
CreateThread(function()
  while true do
    if CR3D.FOCUS and CR3D.FOCUS.enabled then
      Wait(0)
      exports["cr-3dnui"]:FocusTick()
    else
      Wait((CR3D.CONFIG and CR3D.CONFIG.focusIdleWait) or 100)
    end
  end
end)

-------------------------------------------------------------
-- Cleanup on resource stop
-------------------------------------------------------------
AddEventHandler("onResourceStop", function(resName)
  if resName == GetCurrentResourceName() then
    for _, panel in pairs(PANELS) do
      destroyDuiForPanel(panel)
    end
    CR3D.PANELS = {}
    if CR3D.REPLACES then CR3D.REPLACES = {} end
    CR3D.ATTACHMENTS = {}
    if CR3D.FOCUS then
      CR3D.FOCUS.enabled = false
      CR3D.FOCUS.panelId = nil
    end
    return
  end

  -- Collect first (avoid skipping entries while mutating PANELS during pairs)
  local toDestroy = {}
  for id, panel in pairs(PANELS) do
    if panel.owner == resName then
      toDestroy[#toDestroy + 1] = id
    end
  end

  for _, id in ipairs(toDestroy) do
    destroyPanelInternal(id)
  end

  if CR3D.destroyReplacesByOwnerInternal then
    CR3D.destroyReplacesByOwnerInternal(resName)
  end
end)


-------------------------------------------------------------
-- EXPORTS (client): ReplaceTexture (DUI -> material texture)
-------------------------------------------------------------

exports('CreateReplaceTexture', function(opts)
  return CR3D.createReplaceTextureInternal(opts or {}, GetInvokingResource() or 'unknown')
end)

exports('DestroyReplaceTexture', function(replaceId)
  return CR3D.destroyReplaceTextureInternal(replaceId)
end)

exports('SetReplaceTextureUrl', function(replaceId, url, resW, resH)
  return CR3D.setReplaceTextureUrlInternal(replaceId, url, resW, resH)
end)

exports('SendReplaceMessage', function(replaceId, messageTable)
  return CR3D.sendReplaceMessageInternal(replaceId, messageTable)
end)

exports('SendReplaceMouseMove', function(replaceId, u, v, opts)
  return CR3D.sendReplaceMouseMoveInternal(replaceId, u, v, opts)
end)

exports('SendReplaceMouseDown', function(replaceId, button)
  return CR3D.sendReplaceMouseDownInternal(replaceId, button)
end)

exports('SendReplaceMouseUp', function(replaceId, button)
  return CR3D.sendReplaceMouseUpInternal(replaceId, button)
end)

exports('SendReplaceMouseWheel', function(replaceId, delta)
  return CR3D.sendReplaceMouseWheelInternal(replaceId, delta)
end)
