-- Snake demo that uses NEW cr-3dnui focus + keyboard exports

local placingMode = false
local previewPanelId = nil
local placedPanelId = nil
local panelScale = 1.0

local PREVIEW_DIST = 7.0

local function log(msg)
  print(("^2[cr-3dnui_snake_demo_api]^7 %s"):format(msg))
end

local function panelUrl()
  return ("nui://%s/html/panel.html"):format(GetCurrentResourceName())
end

local function baseSize()
  return 1.35, 0.75
end

local function rotToDir(rot)
  local z = math.rad(rot.z)
  local x = math.rad(rot.x)
  local num = math.abs(math.cos(x))
  return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function raycastFromCamera(dist)
  local camPos = GetGameplayCamCoord()
  local rot = GetGameplayCamRot(2)
  local dir = rotToDir(rot)
  local dest = camPos + dir * dist
  local ray = StartShapeTestRay(camPos.x, camPos.y, camPos.z, dest.x, dest.y, dest.z, 1, PlayerPedId(), 0)
  local _, hit, endCoords, surfaceNormal, _ = GetShapeTestResult(ray)
  return hit == 1, endCoords, surfaceNormal
end

-- Placement preview
RegisterCommand("snake_api_preview", function()
  placingMode = not placingMode

  if placingMode then
    if previewPanelId then
      exports["cr-3dnui"]:DestroyPanel(previewPanelId)
      previewPanelId = nil
    end

    local w, h = baseSize()
    previewPanelId = exports["cr-3dnui"]:CreatePanel({
      url = panelUrl(),
      pos = GetEntityCoords(PlayerPedId()),
      normal = vector3(0.0, 0.0, 1.0),
      width = w * panelScale,
      height = h * panelScale,
      alpha = 255,
      resW = 1024,
      resH = 512,
      faceCamera = true
    })

    log("Preview ON (scroll scale, E place)")
  else
    if previewPanelId then exports["cr-3dnui"]:DestroyPanel(previewPanelId) end
    previewPanelId = nil
    log("Preview OFF")
  end
end)
RegisterKeyMapping("snake_api_preview", "Snake API demo: toggle preview", "keyboard", "F7")

-- Place
RegisterCommand("snake_api_place", function()
  if not placingMode or not previewPanelId then return end

  local hit, hitPos, hitNormal = raycastFromCamera(PREVIEW_DIST)
  if not hit then log("No surface hit.") return end

  if placedPanelId then
    exports["cr-3dnui"]:DestroyPanel(placedPanelId)
    placedPanelId = nil
  end

  local w, h = baseSize()
  placedPanelId = exports["cr-3dnui"]:CreatePanel({
    url = panelUrl(),
    pos = hitPos,
    normal = hitNormal,
    width = w * panelScale,
    height = h * panelScale,
    alpha = 255,
    resW = 1024,
    resH = 512,
    faceCamera = true
  })

  exports["cr-3dnui"]:DestroyPanel(previewPanelId)
  previewPanelId = nil
  placingMode = false

  -- Configure keymap for focus capture (press-only)
  exports["cr-3dnui"]:SetFocusKeymap({
    { id = 32,  key = "W" },
    { id = 33,  key = "S" },
    { id = 34,  key = "A" },
    { id = 35,  key = "D" },
    { id = 22,  key = "SPACE" },
    { id = 45,  key = "R" },
    { id = 172, key = "UP" },
    { id = 173, key = "DOWN" },
    { id = 174, key = "LEFT" },
    { id = 175, key = "RIGHT" },
  })

  log("Placed. Press G to focus. ESC exits focus. (Focus auto-exits if you look away).")
end)
RegisterKeyMapping("snake_api_place", "Snake API demo: place panel", "keyboard", "E")

-- Focus toggle
RegisterCommand("snake_api_focus", function()
  if not placedPanelId then
    log("No panel placed.")
    return
  end

  local isFocused = exports["cr-3dnui"]:IsFocused()
  if isFocused then
    exports["cr-3dnui"]:EndFocus()
    log("Focus OFF")
  else
    exports["cr-3dnui"]:BeginFocus(placedPanelId, {
      maxDist = 7.0,
      strict = true,
      drawCursor = true,
      autoExitOnMiss = true,
      missGraceMs = 250,
      exitControls = {200, 177},
      allowLook = true,
      allowPause = true,
      sendFocusMessages = true
    })
    log("Focus ON")
  end
end)
RegisterKeyMapping("snake_api_focus", "Snake API demo: focus panel", "keyboard", "G")

-- Preview scaling follow
CreateThread(function()
  while true do
    Wait(0)
    if placingMode and previewPanelId then
      local hit, hitPos, hitNormal = raycastFromCamera(PREVIEW_DIST)
      if hit then
        exports["cr-3dnui"]:SetPanelTransform(previewPanelId, hitPos, hitNormal)
        local w, h = baseSize()
        exports["cr-3dnui"]:SetPanelSize(previewPanelId, w * panelScale, h * panelScale)
      end

      if IsControlJustPressed(0, 15) then panelScale = math.min(2.5, panelScale + 0.05) end
      if IsControlJustPressed(0, 14) then panelScale = math.max(0.25, panelScale - 0.05) end
    end
  end
end)

AddEventHandler("onResourceStop", function(res)
  if res ~= GetCurrentResourceName() then return end
  if previewPanelId then exports["cr-3dnui"]:DestroyPanel(previewPanelId) end
  if placedPanelId then exports["cr-3dnui"]:DestroyPanel(placedPanelId) end
  exports["cr-3dnui"]:EndFocus()
end)
