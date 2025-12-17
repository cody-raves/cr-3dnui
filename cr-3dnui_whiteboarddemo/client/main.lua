local placingMode = false
local interactMode = false

local previewBoard = nil
local previewPanelId = nil

local boards = {} -- { {ent=, panelId=} }

local panelScale = 1.0

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
local function DrawAimIndicator(isHit)
  -- Prefer API cursor (so demos don't have to ship UI drawing code)
  local ok = pcall(function()
    exports["cr-3dnui"]:DrawCursor(0.5, 0.5, isHit)
  end)
  if ok then return end

  -- Fallback (old crosshair) if someone runs this demo with an older API build
  DrawCrosshairAndHitMarker(isHit)
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
  notify(interactMode and "Interact mode ON (aim + hold left click to draw)" or "Interact mode OFF")

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
-- Placement update loop (preview follows raycast)
-------------------------------------------------------------
CreateThread(function()
  while true do
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
end)

-------------------------------------------------------------
-- Interaction loop: pick nearest hit among all panels
-------------------------------------------------------------
CreateThread(function()
  local mouseDown = false
  local activePanel = nil

  while true do
    Wait(0)

    if not interactMode or #boards == 0 then
      if mouseDown and activePanel then
        exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
      end
      mouseDown = false
      activePanel = nil
      lastHoveredPanel = nil
      goto continue
    end

    local best = nil
    local bestU, bestV, bestT = nil, nil, nil

    for _, b in ipairs(boards) do
      local hitPos, u, v, t = exports["cr-3dnui"]:RaycastPanel(b.panelId, Config.PlaceDistance)
      if hitPos and t then
        if not bestT or t < bestT then
          best = b.panelId
          bestU, bestV, bestT = u, v, t
        end
      end
    end

    DrawAimIndicator(best ~= nil)

    if not best then
      lastHoveredPanel = nil
      if mouseDown and activePanel then
        exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
        mouseDown = false
      end
      activePanel = nil
      goto continue
    end

    activePanel = best
    lastHoveredPanel = best

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
      goto continue
    end

    exports["cr-3dnui"]:SendMouseMove(activePanel, bestU, bestV, { flipY = false })

    if IsDisabledControlJustPressed(0, 24) then
      mouseDown = true
      exports["cr-3dnui"]:SendMouseDown(activePanel, "left")
    end

    if mouseDown and IsDisabledControlJustReleased(0, 24) then
      mouseDown = false
      exports["cr-3dnui"]:SendMouseUp(activePanel, "left")
    end

    ::continue::
  end
end)

-------------------------------------------------------------
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
