local placingMode = false
local interactMode = false

local previewBoard = nil
local previewPanelId = nil

local boards = {} -- { {ent=, panelId=} }

-- =========================================================
-- PERF TUNING (scales better with many boards)
-- =========================================================
-- These are defaults; you can override in config.lua
local PERF = {
  renderDistance      = Config.RenderDistance or 25.0,    -- meters
  nearbyCacheInterval = Config.NearbyCacheInterval or 250,-- ms
  playerPosInterval   = Config.PlayerPosInterval or 500,  -- ms
  raycastThrottle     = Config.RaycastThrottle or 50,     -- ms between raycasts when not drawing
  idleWait            = Config.IdleWait or 100,           -- ms when idle / nothing to do
  placeIdleWait       = Config.PlaceIdleWait or 200,      -- ms when placement mode is off
}

-- Cached player position (updated on a timer to avoid GetEntityCoords every frame)
local cachedPed = 0
local cachedPos = vector3(0.0, 0.0, 0.0)

-- Force-refresh cached player coords immediately (used on mode toggles)
local function RefreshCachedPos()
  cachedPed = PlayerPedId()
  cachedPos = GetEntityCoords(cachedPed)
end

-- Nearby boards cache (updated on a timer, distance filtered)
local nearbyBoards = {} -- array of board entries from `boards`
local lastNearbyRefresh = 0

-- Raycast throttle timer (prevents raycasting every frame when idle)
local lastRaycastAt = 0

-- Squared distance helper (avoids sqrt)
local function vecDistSq(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

local function RefreshNearbyBoards()
  local now = GetGameTimer()
  if (now - lastNearbyRefresh) < PERF.nearbyCacheInterval then return end
  lastNearbyRefresh = now

  nearbyBoards = {}
  local maxSq = PERF.renderDistance * PERF.renderDistance

  for i = 1, #boards do
    local b = boards[i]
    if b and b.ent and DoesEntityExist(b.ent) then
      local p = GetEntityCoords(b.ent)
      if vecDistSq(cachedPos, p) <= maxSq then
        nearbyBoards[#nearbyBoards + 1] = b
      end
    end
  end
end


local panelScale = 1.0


local mouseDown = false

-- Interaction mode (uv or key2dui)
local inputMode = tostring(Config.InteractionMode or 'uv'):lower()
if inputMode ~= 'uv' and inputMode ~= 'key2dui' then inputMode = 'uv' end

-- key2dui state (locked cursor)
local key2d = {
  active = false,
  panelId = nil,
  u = 0.5,
  v = 0.5,
  speed = tonumber(Config.Key2DUICursorSpeed) or 0.010,
  flipY = (Config.Key2DUIFlipY == true),

  -- internal: throttle cursor visual updates to the DUI (avoid spamming)
  _lastSendU = -1.0,
  _lastSendV = -1.0,
  _lastSendAt = 0,
  _sendEveryMs = 33, -- ~30fps
}

local function clamp01(x)
  if x < 0.0 then return 0.0 end
  if x > 1.0 then return 1.0 end
  return x
end

-- KEY2DUI: draw the cursor *inside* the DUI so clicks visually line up
local function sendDuiCursor(panelId, u, v, show)
  if not panelId then return end
  if show == false then
    exports['cr-3dnui']:SendMessage(panelId, { type = 'wb_cursor_hide' })
    key2d._lastSendU = -1.0
    key2d._lastSendV = -1.0
    key2d._lastSendAt = GetGameTimer()
    return
  end

  local now = GetGameTimer()
  -- send if moved a bit OR a little time passed (keeps it smooth without spamming)
  if (math.abs((u or 0.5) - key2d._lastSendU) > 0.002) or
     (math.abs((v or 0.5) - key2d._lastSendV) > 0.002) or
     (now - key2d._lastSendAt) >= key2d._sendEveryMs then

    exports['cr-3dnui']:SendMessage(panelId, {
      type = 'wb_cursor',
      u = u,
      v = v,
      show = true
    })

    key2d._lastSendU = u
    key2d._lastSendV = v
    key2d._lastSendAt = now
  end
end
-- =========================================================
-- TEXT TOOL / KEYBOARD SUPPORT (POC)
-- =========================================================
local lastHoveredPanel = nil

local textEntry = {
  active = false,
  prompting = false,
  panelId = nil,
  x = 0.0,
  y = 0.0,
  color = "#000000",
  size = 24,
  font = "system-ui,Segoe UI,Roboto,Arial"
}

local function notify(msg)
  print(("^2[cr-3dnui_whiteboarddemo]^7 %s"):format(msg))
end

local function getPanelUrl()
  local res = GetCurrentResourceName()
  return ("nui://%s/html/index.html?res=%s"):format(res, res)
end

-- NUI callback from the DUI page (index.html/app.js)
RegisterNUICallback("wb_text_request", function(data, cb)
  if not interactMode then
    cb({ ok = false, err = "not_interacting" })
    return
  end

  local panelId = lastHoveredPanel
  if not panelId then
    cb({ ok = false, err = "no_panel" })
    return
  end

  if textEntry.active then
    cb({ ok = false, err = "busy" })
    return
  end

  textEntry.active = true
  textEntry.prompting = false
  textEntry.panelId = panelId
  textEntry.x = tonumber(data.x) or 0.0
  textEntry.y = tonumber(data.y) or 0.0
  textEntry.color = tostring(data.color or "#000000")
  textEntry.size = tonumber(data.size) or 24
  textEntry.font = tostring(data.font or "system-ui,Segoe UI,Roboto,Arial")

  cb({ ok = true })
end)

-------------------------------------------------------------
-- small vec helpers (for face selection)
-------------------------------------------------------------
local function v3(x,y,z) return vector3(x,y,z) end
local function vAdd(a,b) return v3(a.x+b.x,a.y+b.y,a.z+b.z) end
local function vSub(a,b) return v3(a.x-b.x,a.y-b.y,a.z-b.z) end
local function vMul(a,s) return v3(a.x*s,a.y*s,a.z*s) end
local function vDot(a,b) return a.x*b.x + a.y*b.y + a.z*b.z end
local function vLen(a) return math.sqrt(a.x*a.x + a.y*a.y + a.z*a.z) end
local function vNorm(a)
  local l = vLen(a)
  if l < 0.00001 then return v3(0.0,0.0,0.0) end
  return v3(a.x/l,a.y/l,a.z/l)
end

local function DesiredFaceDir(boardEnt)
  -- Choose the board face that points toward the camera (so UI is on the "front" side you are looking at).
  local fwd = GetEntityForwardVector(boardEnt)
  local camPos = GetGameplayCamCoord()
  local c = GetEntityCoords(boardEnt)
  local toCam = vNorm(vSub(camPos, c))
  if vDot(toCam, fwd) >= 0.0 then
    return fwd
  else
    return vMul(fwd, -1.0)
  end
end
-------------------------------------------------------------
-- Crosshair + hit marker (interact mode)
-------------------------------------------------------------
local function DrawCrosshairAndHitMarker(isHit)
  DrawRect(0.5, 0.5, 0.0020, 0.0200, 255, 255, 255, 210)
  DrawRect(0.5, 0.5, 0.0200, 0.0020, 255, 255, 255, 210)
  if isHit then
    DrawRect(0.5, 0.5, 0.0100, 0.0100, 0, 255, 0, 170)
  else
    DrawRect(0.5, 0.5, 0.0060, 0.0060, 255, 255, 255, 80)
  end
end

-------------------------------------------------------------
-- Cursor / aim indicator (uses API cursor if available)
-------------------------------------------------------------
-- Aim indicator for the demo.
--
-- UV mode benefits from a tiny on-screen aim marker.
-- KEY2DUI mode renders its own cursor *inside the DUI*, so we intentionally
-- do NOT draw a game-space crosshair (it feels "double" and can look offset).
local function DrawAimIndicator(isHit, drawCursor)
  if drawCursor == nil then drawCursor = true end

  if drawCursor then
    -- Prefer API cursor (so demos don't have to ship UI drawing code)
    local ok = pcall(function()
      exports["cr-3dnui"]:DrawCursor(0.5, 0.5, isHit)
    end)
    if not ok then
      -- Fallback (old crosshair) if someone runs this demo with an older API build
      DrawCrosshairAndHitMarker(isHit)
    end
  end
end

-------------------------------------------------------------
-- Raycast from camera to world
-------------------------------------------------------------
local function RotToDir(rot)
  local z = math.rad(rot.z)
  local x = math.rad(rot.x)
  local num = math.abs(math.cos(x))
  return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function RaycastFromCamera(dist)
  local camPos = GetGameplayCamCoord()
  local rot = GetGameplayCamRot(2)
  local dir = RotToDir(rot)
  local dest = camPos + dir * dist
  local ray = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1, PlayerPedId(), 0)
  local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)
  return hit == 1, endCoords, surfaceNormal, entityHit
end

local function EnsureModel(model)
  if not IsModelInCdimage(model) then return false end
  RequestModel(model)
  while not HasModelLoaded(model) do Wait(0) end
  return true
end

local function GetHeadingFromVec2(x, y)
  -- vector2 (x,y) -> heading (0 = north / +Y, 90 = +X)
  return math.deg(math.atan2(x, y))
end

-------------------------------------------------------------
-- Ground snap fix (prop feet clipping)
-- For floor placements: after PlaceObjectOnGroundProperly, ensure the model's
-- lowest point (min.z) is not below the actual ground hit at its XY.
-------------------------------------------------------------
local function GetGroundZBelow(x, y, z, ignoreEnt)
  local ray = StartShapeTestRay(x, y, z + 2.0, x, y, z - 6.0, 1, ignoreEnt or 0, 0)
  local _, hit, endCoords = GetShapeTestResult(ray)
  if hit == 1 then
    return endCoords.z
  end
  return nil
end

local function FixBoardFeetClipping(boardEnt)
  if not boardEnt or not DoesEntityExist(boardEnt) then return end

  local pos = GetEntityCoords(boardEnt)
  local groundZ = GetGroundZBelow(pos.x, pos.y, pos.z, boardEnt)
  if not groundZ then return end

  local minDim, _ = GetModelDimensions(GetEntityModel(boardEnt))
  local bottom = GetOffsetFromEntityInWorldCoords(boardEnt, 0.0, 0.0, minDim.z)

  local delta = groundZ - bottom.z
  if delta > 0.001 then
    SetEntityCoordsNoOffset(boardEnt, pos.x, pos.y, pos.z + delta, false, false, false)
  end
end

-------------------------------------------------------------
-- Raycast the board face at writing height so we don't get fooled by the feet/casters
-------------------------------------------------------------
local function RaycastBoardFace(boardEnt)
  local model = GetEntityModel(boardEnt)
  local minDim, maxDim = GetModelDimensions(model)
  local height = (maxDim.z - minDim.z)

  local zLocal = minDim.z + height * Config.SampleZFactor + Config.SampleZBias
  local sample = GetOffsetFromEntityInWorldCoords(boardEnt, 0.0, 0.0, zLocal)

  local fwd = GetEntityForwardVector(boardEnt)
  local want = DesiredFaceDir(boardEnt)

  local function cast(from, to)
    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, 1, boardEnt, 0)
    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)
    if hit == 1 and entityHit == boardEnt then
      return true, endCoords, surfaceNormal
    end
    return false, nil, nil
  end

  -- Try both sides (front/back). Keep whichever normal points closer to the desired face.
  local a_ok, a_pos, a_nrm = cast(sample + (fwd * 0.80), sample - (fwd * 0.80))
  local b_ok, b_pos, b_nrm = cast(sample - (fwd * 0.80), sample + (fwd * 0.80))

  if not a_ok and not b_ok then
    return false, nil, nil
  end

  local bestPos, bestNrm = nil, nil

  if a_ok and b_ok then
    local ad = vDot(a_nrm, want)
    local bd = vDot(b_nrm, want)
    if bd > ad then
      bestPos, bestNrm = b_pos, b_nrm
    else
      bestPos, bestNrm = a_pos, a_nrm
    end
  else
    bestPos, bestNrm = (a_ok and a_pos or b_pos), (a_ok and a_nrm or b_nrm)
  end

  -- Ensure normal faces the desired direction.
  if vDot(bestNrm, want) < 0.0 then
    bestNrm = vMul(bestNrm, -1.0)
  end

  -- Vertical fine-tune along board UP
  if Config.PanelUpOffset and Config.PanelUpOffset ~= 0.0 then
    local up = GetEntityUpVector(boardEnt)
    bestPos = bestPos + (up * Config.PanelUpOffset)
  end

  return true, bestPos, bestNrm
end

local function ComputePanelSize(boardEnt)
  local model = GetEntityModel(boardEnt)
  local minDim, maxDim = GetModelDimensions(model)
  local w = (maxDim.x - minDim.x) * Config.WidthFactor
  local h = (maxDim.z - minDim.z) * Config.HeightFactor
  return w * panelScale, h * panelScale
end

local function SetPreviewAlpha(ent, a)
  SetEntityAlpha(ent, a, false)
  SetEntityCollision(ent, false, false)
  FreezeEntityPosition(ent, true)
end

local function ClearPreview()
  if previewPanelId then
    exports["cr-3dnui"]:DestroyPanel(previewPanelId)
    previewPanelId = nil
  end
  if previewBoard and DoesEntityExist(previewBoard) then
    DeleteEntity(previewBoard)
    previewBoard = nil
  end
end

-------------------------------------------------------------
-- Placement mode toggle
-------------------------------------------------------------
RegisterCommand("wbmode", function()
  placingMode = not placingMode

  if placingMode then
    ClearPreview()

    if not EnsureModel(Config.BoardModel) then
      notify("Board model missing in CD image.")
      placingMode = false
      return
    end

    -- spawn preview board in front of player
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)

    previewBoard = CreateObject(Config.BoardModel, p.x, p.y, p.z, false, false, false)
    SetPreviewAlpha(previewBoard, Config.PreviewAlpha)

    local w, h = ComputePanelSize(previewBoard)
    previewPanelId = exports["cr-3dnui"]:CreatePanel({
      url = getPanelUrl(),
      pos = p,
      normal = DesiredFaceDir(previewBoard),
      width = w,
      height = h,
      alpha = 255,
      resW = Config.ResW,
      resH = Config.ResH,
      faceCamera = false,
      zOffset = 0.0,
    })

    notify("Whiteboard placement ON (scroll = scale, E = place)")
  else
    ClearPreview()
    notify("Whiteboard placement OFF")
  end
end)
RegisterKeyMapping("wbmode", "Toggle whiteboard placement mode", "keyboard", Config.KeyTogglePlace)

-------------------------------------------------------------
-- Place
-------------------------------------------------------------
RegisterCommand("wbplace", function()
  -- Determine if we're placing on floor (affects ground/feet snap)
  local _hit, _hp, _hn = RaycastFromCamera(Config.PlaceDistance)
  local placingOnFloor = (_hit and _hn and math.abs(_hn.z) > 0.75) or false

  if not placingMode or not previewBoard or not previewPanelId then return end

  -- finalize preview position/rotation into a real board
  local pos = GetEntityCoords(previewBoard)
  local rot = GetEntityRotation(previewBoard, 2)
  local heading = GetEntityHeading(previewBoard)

  ClearPreview()

  EnsureModel(Config.BoardModel)

  local board = CreateObject(Config.BoardModel, pos.x, pos.y, pos.z, true, true, false)
  SetEntityHeading(board, heading)
  SetEntityRotation(board, rot.x, rot.y, rot.z, 2, true)
  PlaceObjectOnGroundProperly(board)
  Wait(0)
  if placingOnFloor then
    FixBoardFeetClipping(board)
  end
  FreezeEntityPosition(board, true)

  local w, h = ComputePanelSize(board)

  local ok, facePos, faceNormal = RaycastBoardFace(board)
  if not ok then
    -- fallback: estimate from forward + center height
    local model = GetEntityModel(board)
    local minDim, maxDim = GetModelDimensions(model)
    local height = (maxDim.z - minDim.z)
    local zLocal = minDim.z + height * Config.SampleZFactor + Config.SampleZBias
    local want = DesiredFaceDir(board)
    faceNormal = want
    facePos = GetOffsetFromEntityInWorldCoords(board, 0.0, 0.0, zLocal)
  end

  local panelPos = facePos + (faceNormal * Config.FaceEpsilon)

  local panelId = exports["cr-3dnui"]:CreatePanel({
    url = getPanelUrl(),
    pos = panelPos,
    normal = faceNormal,
    width = w,
    height = h,
    alpha = 255,
    resW = Config.ResW,
    resH = Config.ResH,
    faceCamera = false,
    zOffset = 0.0,
  })

  table.insert(boards, { ent = board, panelId = panelId })

  placingMode = false
  notify(("Placed whiteboard (#%d). Press G to interact."):format(#boards))
end)
RegisterKeyMapping("wbplace", "Place whiteboard where aiming", "keyboard", Config.KeyPlace)

-------------------------------------------------------------
-- Interact mode toggle
-------------------------------------------------------------
RegisterCommand("wbuse", function()
  interactMode = not interactMode
  notify(interactMode and ("Interact mode ON ("..inputMode..")") or "Interact mode OFF")

  -- If someone toggles interact off mid-text, cancel safely.
  if not interactMode and textEntry.active then
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if textEntry.panelId then
      exports["cr-3dnui"]:SendMessage(textEntry.panelId, { type = "wb_text_cancel" })
    end
    textEntry.active = false
    textEntry.prompting = false
    textEntry.panelId = nil
  end
end)
RegisterKeyMapping("wbuse", "Toggle whiteboard interaction mode", "keyboard", Config.KeyToggleInteract)


-------------------------------------------------------------
-- Input mode switch (uv | key2dui)
-------------------------------------------------------------
RegisterCommand("wbinput", function(_, args)
  local mode = tostring(args[1] or ""):lower()
  if mode ~= "uv" and mode ~= "key2dui" then
    notify(("Usage: /wbinput uv | key2dui  (current: %s)"):format(inputMode))
    return
  end
  if inputMode == mode then
    notify(("Input mode already '%s'"):format(inputMode))
    return
  end
  -- Exit any active key2dui session cleanly
  if key2d.active and key2d.panelId then
    if mouseDown then
      exports["cr-3dnui"]:SendMouseUp(key2d.panelId, "left")
    end
    mouseDown = false
    key2d.active = false
    key2d.panelId = nil
  end
  inputMode = mode
  notify(("Input mode set to '%s'"):format(inputMode))
end, false)

-------------------------------------------------------------
-- Delete / clear helpers
-------------------------------------------------------------
RegisterCommand("wbwipe", function()
  for _, b in ipairs(boards) do
    if b.panelId then exports["cr-3dnui"]:DestroyPanel(b.panelId) end
    if b.ent and DoesEntityExist(b.ent) then DeleteEntity(b.ent) end
  end
  boards = {}

  -- cancel any pending text entry
  if textEntry.active then
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    if textEntry.panelId then
      exports["cr-3dnui"]:SendMessage(textEntry.panelId, { type = "wb_text_cancel" })
    end
    textEntry.active = false
    textEntry.prompting = false
    textEntry.panelId = nil
  end

  notify("Deleted all placed whiteboards.")
end, false)


-------------------------------------------------------------
-- Player position cache (perf)
-------------------------------------------------------------
CreateThread(function()
  while true do
    cachedPed = PlayerPedId()
    cachedPos = GetEntityCoords(cachedPed)
    Wait(PERF.playerPosInterval)
  end
end)

-------------------------------------------------------------
-- Placement update loop (preview follows raycast)
-------------------------------------------------------------
CreateThread(function()
  while true do
    if not (placingMode and previewBoard and previewPanelId) then
      Wait(PERF.placeIdleWait)
    else
      Wait(0)

    if placingMode and previewBoard and previewPanelId then
      local hit, hitPos, hitNormal = RaycastFromCamera(Config.PlaceDistance)
      if hit then
        -- Position the preview board at hit point; orient it based on surface normal.
        SetEntityCoordsNoOffset(previewBoard, hitPos.x, hitPos.y, hitPos.z, false, false, false)

        -- If placing on a wall, use wall normal heading. If floor, face the camera.
        if math.abs(hitNormal.z) < 0.75 then
          local hdg = GetHeadingFromVec2(hitNormal.x, hitNormal.y)
          SetEntityHeading(previewBoard, hdg)
          SetEntityRotation(previewBoard, 0.0, 0.0, hdg, 2, true)
        else
          local camRot = GetGameplayCamRot(2)
          local hdg = camRot.z
          SetEntityHeading(previewBoard, hdg)
          SetEntityRotation(previewBoard, 0.0, 0.0, hdg, 2, true)
        end

        -- Preview panel: estimate face from forward + sample height (fast)
        local model = GetEntityModel(previewBoard)
        local minDim, maxDim = GetModelDimensions(model)
        local height = (maxDim.z - minDim.z)
        local zLocal = minDim.z + height * Config.SampleZFactor + Config.SampleZBias
        local want = DesiredFaceDir(previewBoard)
        local facePos = GetOffsetFromEntityInWorldCoords(previewBoard, 0.0, 0.0, zLocal)
        local panelPos = facePos + (want * Config.FaceEpsilon)

        exports["cr-3dnui"]:SetPanelTransform(previewPanelId, panelPos, want)

        local w, h = ComputePanelSize(previewBoard)
        exports["cr-3dnui"]:SetPanelSize(previewPanelId, w, h)
      end

      if IsControlJustPressed(0, 15) then panelScale = math.min(2.5, panelScale + 0.05) end
      if IsControlJustPressed(0, 14) then panelScale = math.max(0.4, panelScale - 0.05) end
    end
    end
  end
end)


-------------------------------------------------------------
-- Interaction loop (UV or Key2DUI)
--   UV: raycast -> u/v every tick (world-space interaction)
--   Key2DUI: aim once to select a panel, then use a locked 2D cursor
-------------------------------------------------------------
CreateThread(function()
  local activePanel = nil
  local lastBestPanel, lastBestU, lastBestV = nil, nil, nil
  local lastBestT = nil

  local function exitKey2DUI()
    if key2d.active and key2d.panelId then
      if mouseDown then
        exports["cr-3dnui"]:SendMouseUp(key2d.panelId, "left")
      end
    end
    mouseDown = false

    -- hide the cursor rendered inside the DUI when we leave KEY2D mode
    if key2d.panelId then
      sendDuiCursor(key2d.panelId, 0.5, 0.5, false)
    end

    -- reset throttle so the next entry shows immediately
    key2d._lastSendU = -1.0
    key2d._lastSendV = -1.0
    key2d._lastSendAt = 0

    key2d.active = false
    key2d.panelId = nil
  end

  while true do
    -- idle / reset state
    if (not interactMode) or (#boards == 0) then
      if mouseDown and activePanel then
        exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
      end
      mouseDown = false
      activePanel = nil
      lastBestPanel, lastBestU, lastBestV, lastBestT = nil, nil, nil, nil
      lastHoveredPanel = nil
      exitKey2DUI()
      Wait(PERF.idleWait)
    else
      -- keep caches fresh
      RefreshCachedPos()
      RefreshNearbyBoards()

      if #nearbyBoards == 0 then
        DrawAimIndicator(false)
        exitKey2DUI()
        Wait(0)
      else
        local bestPanel, bestU, bestV, bestT = nil, nil, nil, nil

        -- Throttle raycasts when not actively drawing / selecting.
        local now = GetGameTimer()
        local canRaycast = (inputMode == "uv" and mouseDown) or (not key2d.active) or ((now - lastRaycastAt) >= PERF.raycastThrottle)
        if canRaycast then
          lastRaycastAt = now

          for i = 1, #nearbyBoards do
            local b = nearbyBoards[i]
            if b and b.panelId then
              local hitPos, u, v, t = exports["cr-3dnui"]:RaycastPanel(b.panelId, Config.PlaceDistance)
              if hitPos and t then
                if (not bestT) or (t < bestT) then
                  bestPanel, bestU, bestV, bestT = b.panelId, u, v, t
                end
              end
            end
          end

          lastBestPanel, lastBestU, lastBestV, lastBestT = bestPanel, bestU, bestV, bestT
        else
          -- reuse last results between raycasts
          bestPanel, bestU, bestV, bestT = lastBestPanel, lastBestU, lastBestV, lastBestT
        end

        -- =========================
        -- MODE: UV (original)
        -- =========================
        if inputMode == "uv" then
          DrawAimIndicator(bestPanel ~= nil)

          if not bestPanel then
            lastHoveredPanel = nil
            if mouseDown and activePanel then
              exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
              mouseDown = false
            end
            activePanel = nil
            Wait(0)
          else
            activePanel = bestPanel
            lastHoveredPanel = bestPanel

            -- prevent weapon fire/aim
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 257, true)

            -- If text entry is active, do NOT keep drawing/dragging.
            if textEntry.active then
              if mouseDown and activePanel then
                exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
                mouseDown = false
              end
              Wait(0)
            else
              exports["cr-3dnui"]:SendMouseMove(activePanel, bestU, bestV, { flipY = false })

              if IsDisabledControlJustPressed(0, 24) then
                mouseDown = true
                exports["cr-3dnui"]:SendMouseDown(activePanel, "left")
              end

              if mouseDown and IsDisabledControlJustReleased(0, 24) then
                mouseDown = false
                exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
              end

              Wait(PERF.activeWait)
            end
          end

        -- =========================
        -- MODE: KEY2DUI
        -- =========================
        else
          -- If we haven't selected a panel yet, show aim indicator and allow select.
          if (not key2d.active) then
            -- KEY2DUI uses an in-DUI cursor, so we do NOT draw a game-space cursor.
            DrawAimIndicator(bestPanel ~= nil, false)
            lastHoveredPanel = bestPanel

            -- Auto-select the panel the moment you enter interact mode.
            -- This removes the extra "click once to start" step.
            if bestPanel then
              key2d.active = true
              key2d.panelId = bestPanel
              key2d.u = (type(bestU) == "number") and bestU or 0.5
              key2d.v = (type(bestV) == "number") and bestV or 0.5
	              -- show the cursor on the panel immediately
	              sendDuiCursor(bestPanel, key2d.u, key2d.v, true)
              mouseDown = false
              notify("[key2dui] focused panel. Move mouse to drive cursor. ESC/BACKSPACE to exit.")
            end

            -- no selection yet -> no per-frame work besides aim helper
            Wait(0)

          else
            -- Key2DUI active: cursor drives the DUI directly (no UV updates)
            local pid = key2d.panelId
            if not pid then
              exitKey2DUI()
              Wait(0)
            else
              -- optional: exit keys
              if IsControlJustPressed(0, 322) or IsControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) then
                exitKey2DUI()
                notify("[key2dui] exited.")
                Wait(0)
              else
                -- prevent camera + weapon actions while "using" the screen
                DisableControlAction(0, 1, true)   -- LookLeftRight
                DisableControlAction(0, 2, true)   -- LookUpDown
                DisableControlAction(0, 24, true)  -- Attack
                DisableControlAction(0, 25, true)  -- Aim
                DisableControlAction(0, 257, true) -- Attack2
                DisableControlAction(0, 44, true)  -- Cover (Q)
                DisableControlAction(0, 37, true)  -- WeaponWheel

                -- Update cursor from mouse deltas (camera input axes)
                local dx = GetDisabledControlNormal(0, 1)
                local dy = GetDisabledControlNormal(0, 2)

                -- Y axis: by default mouse down moves cursor down (UI-style). Set Config.Key2DUIFlipY=true to invert if needed
                if key2d.flipY then
                  key2d.u = clamp01(key2d.u + (dx * key2d.speed))
                  key2d.v = clamp01(key2d.v - (dy * key2d.speed))
                else
                  key2d.u = clamp01(key2d.u + (dx * key2d.speed))
                  key2d.v = clamp01(key2d.v + (dy * key2d.speed))
                end

                lastHoveredPanel = pid

                -- If text entry is active, do NOT keep drawing/dragging.
                if textEntry.active then
                  if mouseDown then
                    exports["cr-3dnui"]:SendMouseUp(pid, "left")
                    mouseDown = false
                  end
                  Wait(0)
                else
                  exports["cr-3dnui"]:SendMouseMove(pid, key2d.u, key2d.v, { flipY = false })
                  sendDuiCursor(pid, key2d.u, key2d.v, true)

                  if IsDisabledControlJustPressed(0, 24) then
                    mouseDown = true
                    exports["cr-3dnui"]:SendMouseDown(pid, "left")
                  end

                  if mouseDown and IsDisabledControlJustReleased(0, 24) then
                    mouseDown = false
                    exports["cr-3dnui"]:SendMouseUp(pid, "left")
                  end

                  Wait(0)
                end
              end
            end
          end
        end
      end
    end
  end
end)

-------------------------------------------------------------
-- TEXT ENTRY THREAD-------------------------------------------------------------
-- TEXT ENTRY THREAD (onscreen keyboard prompt)
-------------------------------------------------------------
CreateThread(function()
  while true do
    Wait(0)

    if textEntry.active and not textEntry.prompting then
      textEntry.prompting = true

      local ped = PlayerPedId()
      FreezeEntityPosition(ped, true)

      AddTextEntry("WB_TEXT_PROMPT", "Enter text")
      DisplayOnscreenKeyboard(1, "WB_TEXT_PROMPT", "", "", "", "", "", 64)

      while UpdateOnscreenKeyboard() == 0 do
        DisableAllControlActions(0)
        Wait(0)
      end

      local status = UpdateOnscreenKeyboard()
      local result = nil
      if status == 1 then
        result = GetOnscreenKeyboardResult()
      end

      FreezeEntityPosition(ped, false)

      if status == 1 and result and result ~= "" then
        exports["cr-3dnui"]:SendMessage(textEntry.panelId, {
          type = "wb_text_commit",
          x = textEntry.x,
          y = textEntry.y,
          text = result,
          color = textEntry.color,
          size = textEntry.size,
          font = textEntry.font
        })
      else
        exports["cr-3dnui"]:SendMessage(textEntry.panelId, { type = "wb_text_cancel" })
      end

      textEntry.active = false
      textEntry.prompting = false
      textEntry.panelId = nil
    end
  end
end)

-------------------------------------------------------------
-- Cleanup
-------------------------------------------------------------
AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  ClearPreview()
  for _, b in ipairs(boards) do
    if b.panelId then exports["cr-3dnui"]:DestroyPanel(b.panelId) end
    if b.ent and DoesEntityExist(b.ent) then DeleteEntity(b.ent) end
  end

  -- ensure player isn't frozen if stopped mid-entry
  if textEntry.active then
    FreezeEntityPosition(PlayerPedId(), false)
  end
end)