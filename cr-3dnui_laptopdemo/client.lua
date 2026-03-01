-- cr-3dnui_laptopdemo/client.lua
-- Laptop demo using the NEW EntityTexture per-entity DUI overlay system.
--
-- WHAT'S NEW:
--   - Uses CreateEntityTexture instead of CreateReplaceTexture
--   - Each laptop gets its OWN unique DUI browser instance
--   - Multiple laptops can be open simultaneously, each showing different content
--   - No more global texture replacement (which affected ALL instances of the same model)
--
-- Commands:
--   /lapplace       -> Place a new closed laptop in front of player
--   /lapside        -> Flip screen side detection
--   /lapclose       -> Close the currently active laptop
--   /lapopenall     -> Open ALL placed laptops at once (each with unique DUI)
--   /lapcloseall    -> Close all open laptops
--
-- Walk up to a closed laptop and press E to open + focus.
-- ESC to close the focused laptop. Walking behind the screen also closes it.

local CR3D = CR3D

-- =============================
-- CONFIG
-- =============================
local CLOSED_MODEL = `prop_laptop_02_closed`
local OPEN_MODEL   = `prop_laptop_lester`

-- Mouse sensitivity for virtual cursor (bigger = faster)
local CURSOR_SENS = 0.030

-- Small delay after opening before entering focus
local OPEN_FOCUS_DELAY_MS = 200

-- Screen side detection: 1 or -1 (toggle with /lapside)
local SCREEN_SIDE = 1

-- =============================
-- STATE
-- =============================
-- Each laptop entry:
-- {
--   id          = number,
--   closedEnt   = entity (closed model),
--   openEnt     = entity or 0 (open model),
--   etId        = entity texture ID or nil (from CreateEntityTexture),
-- }
local laptops = {}
local nextLaptopId = 1

-- Currently focused laptop (only one at a time for input)
local activeLaptop = nil
local focused = false
local focusThread = nil

local cursorX, cursorY = 0.5, 0.5
local lmbDown = false

-- Forward declarations
local startLaptopCam, stopLaptopCam

-- =============================
-- HELPERS
-- =============================
local function notify(msg)
  BeginTextCommandThefeedPost('STRING')
  AddTextComponentSubstringPlayerName(msg)
  EndTextCommandThefeedPostTicker(false, false)
end

local function reqModel(model)
  if not IsModelInCdimage(model) then return false end
  RequestModel(model)
  local t0 = GetGameTimer()
  while not HasModelLoaded(model) do
    if GetGameTimer() - t0 > 5000 then return false end
    Wait(0)
  end
  return true
end

local function vNorm(v)
  local l = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
  if l < 0.000001 then return vector3(0.0, 0.0, 1.0) end
  return vector3(v.x/l, v.y/l, v.z/l)
end

local function vDot(a, b)
  return a.x*b.x + a.y*b.y + a.z*b.z
end

local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function safeDelete(ent)
  if ent and ent ~= 0 and DoesEntityExist(ent) then
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
  end
end

-- Player must be on the screen side of the laptop
local function isPlayerOnScreenSide(ent)
  if not DoesEntityExist(ent) then return false end
  local pPos = GetEntityCoords(PlayerPedId())
  local ePos = GetEntityCoords(ent)
  local toPlayer = vNorm(pPos - ePos)

  local right = select(1, GetEntityMatrix(ent))
  right = vNorm(right)
  local screenNormal = vNorm(vector3(-right.x, -right.y, -right.z)) * SCREEN_SIDE

  return vDot(screenNormal, toPlayer) > 0.05
end

-- =============================
-- ENTITY TEXTURE HELPERS
-- =============================
local function destroyEntityTexture(entry)
  if entry and entry.etId then
    pcall(function()
      exports['cr-3dnui']:DestroyEntityTexture(entry.etId)
    end)
    entry.etId = nil
  end
end

local function createEntityTexture(entry)
  if not entry or not DoesEntityExist(entry.openEnt) then return false end

  -- Destroy any existing entity texture for this laptop
  destroyEntityTexture(entry)

  -- Each laptop gets a unique URL with its ID, so each DUI shows different content
  local url = ('nui://%s/html/index.html?lap=%d'):format(GetCurrentResourceName(), entry.id)

  -- CreateEntityTexture auto-detects the model preset for prop_laptop_lester
  -- and creates a unique DUI + panel overlay for THIS specific entity
  entry.etId = exports['cr-3dnui']:CreateEntityTexture({
    entity = entry.openEnt,
    url = url,
    resW = 1024,
    resH = 512,

    -- Model preset auto-detection: the library has a built-in preset for prop_laptop_lester.
    -- You can also pass manual overrides:
    -- localOffset = vector3(-0.24, 0.0, 0.085),
    -- localNormal = vector3(-1.0, 0.0, 0.15),
    -- localUp = vector3(0.0, 0.0, 1.0),
    -- width = 0.33,
    -- height = 0.21,
  })

  if not entry.etId then
    notify(('Failed to create EntityTexture for laptop #%d'):format(entry.id))
    return false
  end

  return true
end

-- =============================
-- LAPTOP PLACE / OPEN / CLOSE
-- =============================
local function placeClosed()
  if not reqModel(CLOSED_MODEL) then
    notify('Failed to load closed laptop model')
    return
  end

  local ped = PlayerPedId()
  local p = GetEntityCoords(ped)
  local f = GetEntityForwardVector(ped)
  local pos = p + (f * 1.0) + vector3(0.0, 0.0, -0.05)
  local heading = GetEntityHeading(ped)

  local closed = CreateObject(CLOSED_MODEL, pos.x, pos.y, pos.z, true, true, false)
  SetEntityHeading(closed, heading)
  FreezeEntityPosition(closed, true)

  local id = nextLaptopId
  nextLaptopId = nextLaptopId + 1

  table.insert(laptops, {
    id = id,
    closedEnt = closed,
    openEnt = 0,
    etId = nil,
  })

  notify(('Placed closed laptop #%d. Walk up and press E.'):format(id))
end

local function openLaptop(entry)
  if not entry or not DoesEntityExist(entry.closedEnt) then
    notify('Invalid laptop.')
    return false
  end

  if not reqModel(OPEN_MODEL) then
    notify('Failed to load open laptop model')
    return false
  end

  local pos = GetEntityCoords(entry.closedEnt)
  local heading = GetEntityHeading(entry.closedEnt)

  -- Spawn open model at same transform
  safeDelete(entry.openEnt)
  entry.openEnt = CreateObject(OPEN_MODEL, pos.x, pos.y, pos.z, true, true, false)
  SetEntityHeading(entry.openEnt, heading)
  FreezeEntityPosition(entry.openEnt, true)

  -- Hide closed model
  SetEntityVisible(entry.closedEnt, false, false)
  SetEntityCollision(entry.closedEnt, false, false)

  -- Create per-entity DUI overlay (unique to THIS laptop)
  createEntityTexture(entry)

  return true
end

local function closeLaptop(entry)
  if not entry then return end

  -- Destroy the per-entity DUI overlay
  destroyEntityTexture(entry)

  safeDelete(entry.openEnt)
  entry.openEnt = 0

  if DoesEntityExist(entry.closedEnt) then
    SetEntityVisible(entry.closedEnt, true, false)
    SetEntityCollision(entry.closedEnt, true, true)
  end
end

-- =============================
-- CAMERA FOCUS
-- =============================
local focusCam = nil

startLaptopCam = function(ent)
  if focusCam then return end
  if not DoesEntityExist(ent) then return end

  local right, _, _, pos = GetEntityMatrix(ent)
  right = vNorm(right)

  local screenNormal = vNorm(vector3(-right.x, -right.y, -right.z)) * SCREEN_SIDE
  local camPos = pos + (screenNormal * 0.48) + vector3(0.0, 0.0, 0.20)

  focusCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
  SetCamCoord(focusCam, camPos.x, camPos.y, camPos.z)
  PointCamAtEntity(focusCam, ent, 0.0, 0.0, 0.16, true)
  SetCamFov(focusCam, 45.0)
  RenderScriptCams(true, true, 250, true, true)
end

stopLaptopCam = function()
  if focusCam then
    RenderScriptCams(false, true, 200, true, true)
    DestroyCam(focusCam, false)
    focusCam = nil
  end
end

-- =============================
-- FOCUS / INPUT FORWARD
-- =============================
local function closeActive()
  if focused then
    focused = false
  end

  if stopLaptopCam then stopLaptopCam() end
  focusThread = nil

  -- Release LMB if we had it down
  if activeLaptop and activeLaptop.etId and lmbDown then
    pcall(function() exports['cr-3dnui']:SendEntityTextureMouseUp(activeLaptop.etId, 'left') end)
  end
  lmbDown = false

  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)

  -- Close the active laptop model (but other laptops remain open with their own DUIs)
  if activeLaptop then
    closeLaptop(activeLaptop)
    activeLaptop = nil
  end
end

local function beginFocus(entry)
  if focused then return end
  if not entry or not DoesEntityExist(entry.openEnt) then
    notify('Laptop is not open.')
    return
  end

  if not entry.etId then
    notify('No EntityTexture on this laptop.')
    return
  end

  if not isPlayerOnScreenSide(entry.openEnt) then
    notify('Stand on the screen side to use it.')
    return
  end

  focused = true
  cursorX, cursorY = 0.5, 0.5
  lmbDown = false

  startLaptopCam(entry.openEnt)

  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(true)

  notify(('Laptop #%d focused. ESC to exit.'):format(entry.id))

  local etId = entry.etId

  focusThread = CreateThread(function()
    while focused and etId and activeLaptop == entry do
      Wait(0)

      DisableAllControlActions(0)
      DisableAllControlActions(1)
      DisableAllControlActions(2)
      DisableControlAction(0, 200, true)
      DisableControlAction(0, 199, true)
      DisableControlAction(0, 322, true)

      -- ESC exits + closes
      if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then
        closeActive()
        break
      end

      -- Mouse delta -> virtual cursor -> forward to EntityTexture DUI
      local dx = GetDisabledControlNormal(0, 1)
      local dy = GetDisabledControlNormal(0, 2)

      if dx ~= 0.0 or dy ~= 0.0 then
        cursorX = clamp(cursorX + (dx * CURSOR_SENS), 0.0, 1.0)
        cursorY = clamp(cursorY + (dy * CURSOR_SENS), 0.0, 1.0)
        pcall(function() exports['cr-3dnui']:SendEntityTextureMouseMove(etId, cursorX, cursorY) end)
      end

      -- Click
      if IsDisabledControlJustPressed(0, 24) then
        lmbDown = true
        pcall(function() exports['cr-3dnui']:SendEntityTextureMouseDown(etId, 'left') end)
      elseif IsDisabledControlJustReleased(0, 24) then
        lmbDown = false
        pcall(function() exports['cr-3dnui']:SendEntityTextureMouseUp(etId, 'left') end)
      end

      -- Scroll
      if IsDisabledControlJustPressed(0, 15) then
        pcall(function() exports['cr-3dnui']:SendEntityTextureMouseWheel(etId, 1) end)
      elseif IsDisabledControlJustPressed(0, 14) then
        pcall(function() exports['cr-3dnui']:SendEntityTextureMouseWheel(etId, -1) end)
      end

      -- If player walks behind, exit
      if not isPlayerOnScreenSide(entry.openEnt) then
        notify('Moved behind the screen. Closing.')
        closeActive()
        break
      end
    end
  end)
end

-- =============================
-- CONTROLS (proximity E to open)
-- =============================
CreateThread(function()
  while true do
    Wait(0)

    -- If focused but active laptop got deleted, clean up
    if focused and (not activeLaptop or not DoesEntityExist(activeLaptop.openEnt)) then
      closeActive()
    end

    if not focused then
      local ped = PlayerPedId()
      local p = GetEntityCoords(ped)

      -- Find nearest CLOSED laptop and allow E to open+focus
      for _, entry in ipairs(laptops) do
        if entry and DoesEntityExist(entry.closedEnt) and entry.openEnt == 0 then
          local e = GetEntityCoords(entry.closedEnt)
          if #(p - e) < 1.2 then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('Press ~INPUT_CONTEXT~ to open laptop #%d'):format(entry.id))
            EndTextCommandDisplayHelp(0, false, true, 1)

            if IsControlJustPressed(0, 38) then
              -- Close any currently focused laptop first
              if activeLaptop then
                closeActive()
              end

              -- Open this one
              if openLaptop(entry) then
                activeLaptop = entry
                Wait(OPEN_FOCUS_DELAY_MS)
                beginFocus(entry)
              end
            end
            break
          end
        end
      end
    end
  end
end)

-- =============================
-- COMMANDS
-- =============================
RegisterCommand('lapplace', function()
  placeClosed()
end)

RegisterCommand('lapside', function()
  SCREEN_SIDE = -SCREEN_SIDE
  notify(('SCREEN_SIDE flipped: %d'):format(SCREEN_SIDE))
end)

RegisterCommand('lapclose', function()
  closeActive()
end)

-- Open ALL placed laptops at once (demonstrates multiple unique DUIs)
RegisterCommand('lapopenall', function()
  local count = 0
  for _, entry in ipairs(laptops) do
    if entry and DoesEntityExist(entry.closedEnt) and entry.openEnt == 0 then
      if openLaptop(entry) then
        count = count + 1
      end
    end
  end
  notify(('Opened %d laptops — each with its own unique DUI!'):format(count))
end)

-- Close all open laptops
RegisterCommand('lapcloseall', function()
  -- If focused, unfocus first
  if focused then
    closeActive()
  end

  local count = 0
  for _, entry in ipairs(laptops) do
    if entry and entry.openEnt ~= 0 then
      closeLaptop(entry)
      count = count + 1
    end
  end
  activeLaptop = nil
  notify(('Closed %d laptops.'):format(count))
end)

-- =============================
-- CLEANUP
-- =============================
AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end

  if focused then
    focused = false
    stopLaptopCam()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
  end

  for _, entry in ipairs(laptops) do
    if entry then
      destroyEntityTexture(entry)
      safeDelete(entry.openEnt)
      safeDelete(entry.closedEnt)
    end
  end
  laptops = {}
end)

-- Auto place for convenience
CreateThread(function()
  Wait(500)
  placeClosed()
end)
