-- cr-3dnui_laptopdemo/client.lua
-- Laptop demo using ReplaceTexture render path + direct mouse forwarding (no raycast UV, no NUI overlay).
-- Multi-laptop placement + single-open enforcement:
--  - /lapplace places another CLOSED laptop (does not delete previous)
--  - Only ONE laptop may be OPEN (and interactive) at a time on this client
--  - When you stop interacting (ESC / walk away), the laptop closes back to CLOSED model

local CR3D = CR3D

-- =============================
-- CONFIG
-- =============================
local CLOSED_MODEL = `prop_laptop_02_closed`
local OPEN_MODEL   = `prop_laptop_lester`

-- The model's visible screen uses one of these texture slots.
-- If #1 doesn't work on your build, use /lapnext to cycle.
local REPLACE_CANDIDATES = {
  -- {txd, txn} pairs (from model dictionaries)
  {"prop_laptop_lester", "prop_lester_screen"},
  {"prop_laptop_lester", "prop_laptop_lester"},
  {"prop_laptop_lester", "prop_screen"},
  {"prop_laptop_lester", "screen"},
  {"prop_laptop_lester", "laptop_screen"},
  {"prop_laptop_02", "prop_laptop_02"},
  {"prop_laptop_02", "screen"},
  {"prop_laptop_02", "laptop_screen"},
  {"prop_laptop_02_closed", "prop_laptop_02_closed"},
  {"prop_laptop_02_closed", "screen"},
}

-- Mouse sensitivity for virtual cursor (bigger = faster)
local CURSOR_SENS = 0.030

-- Small delay after swapping models / creating DUI before entering focus
-- (helps avoid a 1-frame black RT while the DUI paints its first frame)
local OPEN_FOCUS_DELAY_MS = 200

-- Some models have forward vector pointing *away* from the screen.
-- If focus gate feels backwards, toggle with /lapside
local SCREEN_SIDE = 1 -- 1 or -1

-- =============================
-- STATE
-- =============================
-- Each laptop entry:
-- { closedEnt = <entity>, openEnt = <entity or 0> }
local laptops = {}

-- Only ONE active open laptop at a time
local activeLaptop = nil

-- Single ReplaceTexture on this client (ReplaceTexture is global per slot)
local replaceId = nil
local replaceIdx = 1

local focused = false
local focusThread = nil

local cursorX, cursorY = 0.5, 0.5
local lmbDown = false

-- Forward declarations (used by endFocus/closeActive before camera funcs are defined)
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

local function vDot(a,b)
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

local function destroyReplace()
  if replaceId then
    pcall(function()
      exports['cr-3dnui']:DestroyReplaceTexture(replaceId)
    end)
    replaceId = nil
  end
end

local function currentPair()
  local p = REPLACE_CANDIDATES[replaceIdx]
  return p[1], p[2]
end

local function printCandidate()
  local txd, txn = currentPair()
  notify(("ReplaceTexture candidate %d/%d: %s / %s"):format(replaceIdx, #REPLACE_CANDIDATES, txd, txn))
end

-- player must be on the screen side of the laptop (open model uses LAP LEFT as screen)
local function isPlayerOnScreenSide(ent)
  if not DoesEntityExist(ent) then return false end
  local pPed = PlayerPedId()
  local pPos = GetEntityCoords(pPed)
  local ePos = GetEntityCoords(ent)

  local toPlayer = vNorm(pPos - ePos)

  -- Screen faces LAP LEFT: entity LEFT = -right
  local right = select(1, GetEntityMatrix(ent))
  right = vNorm(right)
  local screenNormal = vNorm(vector3(-right.x, -right.y, -right.z)) * SCREEN_SIDE

  local d = vDot(screenNormal, toPlayer)
  return d > 0.05
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

  table.insert(laptops, { id = #laptops + 1, closedEnt = closed, openEnt = 0 })
  notify(('Placed closed laptop #%d. Walk up and press E.'):format(#laptops))
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

  -- spawn open model at same transform
  safeDelete(entry.openEnt)
  entry.openEnt = CreateObject(OPEN_MODEL, pos.x, pos.y, pos.z, true, true, false)
  SetEntityHeading(entry.openEnt, heading)
  FreezeEntityPosition(entry.openEnt, true)

  -- hide closed model (we keep the entity to "close" back later)
  SetEntityVisible(entry.closedEnt, false, false)
  SetEntityCollision(entry.closedEnt, false, false)

  return true
end

local function closeLaptop(entry)
  if not entry then return end

  safeDelete(entry.openEnt)
  entry.openEnt = 0

  if DoesEntityExist(entry.closedEnt) then
    SetEntityVisible(entry.closedEnt, true, false)
    SetEntityCollision(entry.closedEnt, true, true)
  end
end

local function ensureReplace(entry)
  -- Always recreate ReplaceTexture so UI reloads with correct lap id
  destroyReplace()

  local txd, txn = currentPair()
  local lapId = entry and entry.id or 0

  replaceId = exports['cr-3dnui']:CreateReplaceTexture({
    url = ('nui://%s/html/index.html?lap=%d'):format(GetCurrentResourceName(), lapId),
    resW = 1024,
    resH = 512,

    model = OPEN_MODEL,
    owner = GetCurrentResourceName(),

    origTxd = txd,
    origTxn = txn,
  })

  printCandidate()
  return replaceId ~= nil
end


-- =============================
-- CAMERA FOCUS
-- =============================
local focusCam = nil

startLaptopCam = function(ent)
  if focusCam then return end
  if not DoesEntityExist(ent) then return end

  -- Use the entity's TRUE screen face normal.
  -- For prop_laptop_lester, the *screen* is on entity LEFT.
  local right, _, _, pos = GetEntityMatrix(ent)
  right = vNorm(right)

  local screenNormal = vNorm(vector3(-right.x, -right.y, -right.z)) * SCREEN_SIDE -- LEFT
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
  -- Always end focus + teardown replace + swap model back to closed
  if focused then
    focused = false
  end

  if stopLaptopCam then stopLaptopCam() end
  focusThread = nil

  -- Release LMB if we had it down
  if replaceId and lmbDown then
    pcall(function() exports['cr-3dnui']:SendReplaceMouseUp(replaceId, 0) end)
  end
  lmbDown = false

  -- Restore controls/input
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(false)

  -- remove global replace mapping
  destroyReplace()

  -- close active laptop model
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

  if not ensureReplace(entry) then
    notify('Failed to create ReplaceTexture.')
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

  -- We do NOT open any NUI overlay. We just forward input into the DUI.
  SetNuiFocus(false, false)
  SetNuiFocusKeepInput(true)

  notify('Laptop focused. ESC to exit (auto-closes).')

  focusThread = CreateThread(function()
    while focused and replaceId and activeLaptop == entry do
      Wait(0)

      -- hard block pause menu + most controls
      DisableAllControlActions(0)
      DisableAllControlActions(1)
      DisableAllControlActions(2)
      DisableControlAction(0, 200, true) -- pause
      DisableControlAction(0, 199, true)
      DisableControlAction(0, 322, true)

      -- ESC exits + closes
      if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then
        closeActive()
        break
      end

      -- mouse delta -> virtual cursor
      local dx = GetDisabledControlNormal(0, 1)
      local dy = GetDisabledControlNormal(0, 2)

      if dx ~= 0.0 or dy ~= 0.0 then
        cursorX = clamp(cursorX + (dx * CURSOR_SENS), 0.0, 1.0)
        cursorY = clamp(cursorY + (dy * CURSOR_SENS), 0.0, 1.0)
        pcall(function() exports['cr-3dnui']:SendReplaceMouseMove(replaceId, cursorX, cursorY) end)
      end

      -- click
      if IsDisabledControlJustPressed(0, 24) then
        lmbDown = true
        pcall(function() exports['cr-3dnui']:SendReplaceMouseDown(replaceId, 0) end)
      elseif IsDisabledControlJustReleased(0, 24) then
        lmbDown = false
        pcall(function() exports['cr-3dnui']:SendReplaceMouseUp(replaceId, 0) end)
      end

      -- scroll (weapon wheel next/prev)
      if IsDisabledControlJustPressed(0, 15) then
        pcall(function() exports['cr-3dnui']:SendReplaceMouseWheel(replaceId, 1) end)
      elseif IsDisabledControlJustPressed(0, 14) then
        pcall(function() exports['cr-3dnui']:SendReplaceMouseWheel(replaceId, -1) end)
      end

      -- If player walks behind, exit + close
      if not isPlayerOnScreenSide(entry.openEnt) then
        notify('Moved behind the screen. Closing.')
        closeActive()
        break
      end
    end
  end)
end

-- =============================
-- CONTROLS
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

      -- If there is an active open laptop but we're not focused (shouldn't happen), close it.
      if activeLaptop and DoesEntityExist(activeLaptop.openEnt) then
        -- keep it simple: force-close
        closeActive()
      end

      -- Find nearest CLOSED laptop and allow E to open+focus
      for _, entry in ipairs(laptops) do
        if entry and DoesEntityExist(entry.closedEnt) then
          local e = GetEntityCoords(entry.closedEnt)
          if #(p - e) < 1.2 then
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to open laptop')
            EndTextCommandDisplayHelp(0, false, true, 1)

            if IsControlJustPressed(0, 38) then
              -- close any existing open laptop first (single-open enforcement)
              if activeLaptop and activeLaptop ~= entry then
                closeActive()
              end

              -- open this one
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

RegisterCommand('lapplace', function()
  placeClosed()
end)

RegisterCommand('lapnext', function()
  replaceIdx = replaceIdx + 1
  if replaceIdx > #REPLACE_CANDIDATES then replaceIdx = 1 end
  printCandidate()

  -- If currently open/focused, reapply replace (recreate mapping)
  if activeLaptop and DoesEntityExist(activeLaptop.openEnt) then
    destroyReplace()
    ensureReplace(activeLaptop)
  end
end)

RegisterCommand('lapside', function()
  SCREEN_SIDE = -SCREEN_SIDE
  notify(('SCREEN_SIDE flipped: %d'):format(SCREEN_SIDE))
end)

RegisterCommand('lapclose', function()
  closeActive()
end)

AddEventHandler('onResourceStop', function(res)
  if res ~= GetCurrentResourceName() then return end
  closeActive()

  for _, entry in ipairs(laptops) do
    if entry then
      safeDelete(entry.openEnt)
      safeDelete(entry.closedEnt)
    end
  end
  laptops = {}
end)

-- Auto place for convenience (keeps old behavior: starts with one laptop placed)
CreateThread(function()
  Wait(500)
  placeClosed()
end)
