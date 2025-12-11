local QBCore = exports['qb-core']:GetCoreObject()

local PANEL_TXD = "cr_3dnui_txd"
local PANEL_TEX = "cr_3dnui_tex"

local panelDui = nil
local panelTextureLoaded = false

local placingMode = false
local interactMode = false
local panelScale = 1.0

-- active placed panel (only one for this POC)
-- { pos = vector3, normal = vector3, scale = number }
local activePanel = nil

-------------------------------------------------------------
-- simple vector helpers
-------------------------------------------------------------
local function vecAdd(a, b)
    return vector3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vecSub(a, b)
    return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function vecMul(a, s)
    return vector3(a.x * s, a.y * s, a.z * s)
end

local function vecDot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function vecCross(a, b)
    return vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

local function vecLen(a)
    return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end

local function vecNorm(a)
    local len = vecLen(a)
    if len < 0.0001 then
        return vector3(0.0, 0.0, 0.0)
    end
    return vector3(a.x / len, a.y / len, a.z / len)
end

-------------------------------------------------------------
-- camera → direction
-------------------------------------------------------------
local function rotationToDirection(rot)
    local radX = math.rad(rot.x)
    local radY = math.rad(rot.y)
    local radZ = math.rad(rot.z)

    local cosX = math.cos(radX)
    local sinX = math.sin(radX)
    local cosZ = math.cos(radZ)
    local sinZ = math.sin(radZ)

    -- standard FiveM camera forward
    return vector3(-sinZ * cosX, cosZ * cosX, sinX)
end

-------------------------------------------------------------
-- Dui / runtime texture
-------------------------------------------------------------
local function ensurePanelTexture()
    if panelTextureLoaded then return end

    local w, h = 1024, 1024
    local resName = GetCurrentResourceName()
    local pageUrl = ("nui://%s/html/panel.html"):format(resName)

    panelDui = CreateDui(pageUrl, w, h)
    local handle = GetDuiHandle(panelDui)

    local txd = CreateRuntimeTxd(PANEL_TXD)
    CreateRuntimeTextureFromDuiHandle(txd, PANEL_TEX, handle)

    panelTextureLoaded = true
    print("^2[3d-nui] Dui created for panel.html^7")
end

-------------------------------------------------------------
-- build panel basis (center, normal, right, up, half extents)
-------------------------------------------------------------
local function makePanelBasis(pos, normal, width, height)
    local planeNormal = vecNorm(normal)

    -- flip normal so it faces the camera
    local camPos = GetGameplayCamCoord()
    local toCam = vecNorm(vecSub(camPos, pos))
    if vecDot(toCam, planeNormal) < 0.0 then
        planeNormal = vecMul(planeNormal, -1.0)
    end

    -- small offset off the wall to avoid z-fighting
    local center = vecAdd(pos, vecMul(planeNormal, 0.002))

    local worldUp = vector3(0.0, 0.0, 1.0)
    local right = vecCross(worldUp, planeNormal)

    -- fallback if we're on a horizontal surface
    if math.abs(right.x) < 0.001 and math.abs(right.y) < 0.001 and math.abs(right.z) < 0.001 then
        worldUp = vector3(0.0, 1.0, 0.0)
        right = vecCross(planeNormal, worldUp)
    end

    right = vecNorm(right)
    local upWall = vecNorm(vecCross(right, planeNormal))

    local halfW = width * 0.5
    local halfH = height * 0.5

    return {
        center = center,
        normal = planeNormal,
        right = right,
        up = upWall,
        halfW = halfW,
        halfH = halfH
    }
end

-------------------------------------------------------------
-- draw one panel quad
-------------------------------------------------------------
local function drawPanelQuad(pos, normal, width, height, alpha)
    if not panelTextureLoaded then return end
    alpha = alpha or 255

    local basis = makePanelBasis(pos, normal, width, height)
    local center = basis.center
    local right = basis.right
    local upWall = basis.up
    local halfW = basis.halfW
    local halfH = basis.halfH

    local v1 = vecAdd(center, vecAdd(vecMul(right, -halfW), vecMul(upWall,  halfH))) -- TL
    local v2 = vecAdd(center, vecAdd(vecMul(right,  halfW), vecMul(upWall,  halfH))) -- TR
    local v3 = vecAdd(center, vecAdd(vecMul(right,  halfW), vecMul(upWall, -halfH))) -- BR
    local v4 = vecAdd(center, vecAdd(vecMul(right, -halfW), vecMul(upWall, -halfH))) -- BL

    local r, g, b, a = 255, 255, 255, alpha

    -- U flipped so text is not mirrored
    DrawSpritePoly(
        v1.x, v1.y, v1.z,
        v2.x, v2.y, v2.z,
        v3.x, v3.y, v3.z,
        r, g, b, a,
        PANEL_TXD, PANEL_TEX,
        0.0, 1.0, 1.0,
        1.0, 1.0, 1.0,
        1.0, 0.0, 1.0
    )

    DrawSpritePoly(
        v1.x, v1.y, v1.z,
        v3.x, v3.y, v3.z,
        v4.x, v4.y, v4.z,
        r, g, b, a,
        PANEL_TXD, PANEL_TEX,
        0.0, 1.0, 1.0,
        1.0, 0.0, 1.0,
        0.0, 0.0, 1.0
    )
end

-------------------------------------------------------------
-- convert camera ray → hit on panel (u,v in 0..1)
-------------------------------------------------------------
local function raycastPanelUV(panel)
    if not panel then return nil end

    local width = (Config.Spray and Config.Spray.width or 1.0) * panel.scale
    local height = (Config.Spray and Config.Spray.height or 1.0) * panel.scale

    local basis = makePanelBasis(panel.pos, panel.normal, width, height)
    local center = basis.center
    local normal = basis.normal
    local right = basis.right
    local upWall = basis.up
    local halfW = basis.halfW
    local halfH = basis.halfH

    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local dir = rotationToDirection(camRot)

    local denom = vecDot(dir, normal)
    if math.abs(denom) < 0.0001 then
        return nil
    end

    local t = vecDot(vecSub(center, camPos), normal) / denom
    if t < 0.0 then
        return nil
    end

    local hitPos = vecAdd(camPos, vecMul(dir, t))
    local rel = vecSub(hitPos, center)

    local localX = vecDot(rel, right) / halfW
    local localY = vecDot(rel, upWall) / halfH

    if math.abs(localX) > 1.0 or math.abs(localY) > 1.0 then
        return nil
    end

    -- note: v is NOT flipped here anymore; we already flipped the texture verts
    local u = (localX + 1.0) * 0.5
    local v = (localY + 1.0) * 0.5

    return hitPos, u, v
end

-------------------------------------------------------------
-- send player info into the panel
-------------------------------------------------------------
local function sendPlayerInfoToPanel()
    if not panelDui or not panelTextureLoaded then return end

    local pdata = QBCore.Functions.GetPlayerData()
    if not pdata or not pdata.citizenid then return end

    local char = pdata.charinfo or {}
    local money = pdata.money or {}
    local job = pdata.job or {}
    local gang = pdata.gang or {}
    local meta = pdata.metadata or {}

    local info = {
        name      = (char.firstname or "John") .. " " .. (char.lastname or "Doe"),
        cid       = pdata.citizenid,
        job       = (job.label or job.name or "Unemployed"),
        gang      = (gang.label or gang.name or "None"),
        cash      = money.cash or money["cash"] or 0,
        bank      = money.bank or money["bank"] or 0,
        phone     = char.phone or meta.phone or meta["phone"] or "N/A",
        apartment = (meta.apartment and (meta.apartment.label or meta.apartment.name)) or "None"
    }

    local payload = json.encode({
        type = "playerInfo",
        data = info
    })

    SendDuiMessage(panelDui, payload)
end

-------------------------------------------------------------
-- placement mode
-------------------------------------------------------------
RegisterCommand("panelmode", function()
    placingMode = not placingMode
    if placingMode then
        ensurePanelTexture()
        print("^2[3d-nui] Placement mode ON (scroll = scale, E = place)^7")
    else
        print("^3[3d-nui] Placement mode OFF^7")
    end
end)

RegisterKeyMapping("panelmode", "Toggle 3D panel placement mode", "keyboard", "F7")

RegisterCommand("placepanel", function()
    if not placingMode then return end

    local camPos = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local dir = rotationToDirection(camRot)

    local from = camPos
    local to = vecAdd(camPos, vecMul(dir, 20.0))

    local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, -1, 0)
    local _, hit, hitPos, hitNormal = GetShapeTestResult(ray)

    if hit == 1 then
        activePanel = {
            pos = hitPos,
            normal = hitNormal,
            scale = panelScale
        }
        placingMode = false
        print(("^2[3d-nui] Panel placed (scale=%.2f)^7"):format(panelScale))
    else
        print("^1[3d-nui] No surface hit to place panel^7")
    end
end)

RegisterKeyMapping("placepanel", "Place 3D panel", "keyboard", "E")

-------------------------------------------------------------
-- interaction toggle (G)
-------------------------------------------------------------
RegisterCommand("paneluse", function()
    if not activePanel then
        print("^3[3d-nui] No active panel to use.^7")
        return
    end

    interactMode = not interactMode
    if interactMode then
        print("^2[3d-nui] Interaction ON (aim at screen & left-click)^7")
        sendPlayerInfoToPanel()
    else
        print("^3[3d-nui] Interaction OFF^7")
    end
end)

RegisterKeyMapping("paneluse", "Use 3D panel", "keyboard", "G")

-------------------------------------------------------------
-- NUI callback from panel.html (via DUI)
-------------------------------------------------------------
RegisterNUICallback("panelAction", function(data, cb)
    local action = data.action
    if not action then cb({}); return end

    if action == "set_waypoint" then
        if activePanel then
            SetNewWaypoint(activePanel.pos.x, activePanel.pos.y)
        end
    elseif action == "refresh_info" then
        sendPlayerInfoToPanel()
    else
        -- everything else we punt to the server
        TriggerServerEvent("cr-3dnui:server:action", action)
    end

    cb({})
end)

-------------------------------------------------------------
-- main draw & input loop
-------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)

        if placingMode then
            ensurePanelTexture()

            local camPos = GetGameplayCamCoord()
            local camRot = GetGameplayCamRot(2)
            local dir = rotationToDirection(camRot)

            local from = camPos
            local to = vecAdd(camPos, vecMul(dir, 20.0))

            local ray = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, -1, 0)
            local _, hit, hitPos, hitNormal = GetShapeTestResult(ray)

            if hit == 1 then
                local width = (Config.Spray and Config.Spray.width or 1.0) * panelScale
                local height = (Config.Spray and Config.Spray.height or 1.0) * panelScale

                drawPanelQuad(hitPos, hitNormal, width, height, 200)

                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)

                if IsDisabledControlJustPressed(0, 14) then
                    panelScale = panelScale + 0.1
                    if panelScale > 3.0 then panelScale = 3.0 end
                elseif IsDisabledControlJustPressed(0, 15) then
                    panelScale = panelScale - 0.1
                    if panelScale < 0.3 then panelScale = 0.3 end
                end
            end
        end

        if activePanel then
            ensurePanelTexture()
            local width = (Config.Spray and Config.Spray.width or 1.0) * activePanel.scale
            local height = (Config.Spray and Config.Spray.height or 1.0) * activePanel.scale

            drawPanelQuad(activePanel.pos, activePanel.normal, width, height, 255)

            local hitPos, u, v = raycastPanelUV(activePanel)
            if hitPos then
                DrawMarker(
                    28,
                    hitPos.x, hitPos.y, hitPos.z + 0.002,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    0.03, 0.03, 0.03,
                    255, 0, 0, interactMode and 200 or 80,
                    false, false, 2, nil, nil, false
                )

                if interactMode then
                    -- tiny crosshair in screen center
                    DrawRect(0.5, 0.5, 0.004, 0.004, 0, 255, 120, 200)

                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 25, true)

                    if IsDisabledControlJustPressed(0, 24) then
                        local ped = PlayerPedId()
                        local pPos = GetEntityCoords(ped)
                        if #(pPos - activePanel.pos) < 4.0 then
                            local payload = json.encode({
                                type = "click",
                                x = u,
                                y = v
                            })
                            SendDuiMessage(panelDui, payload)
                        end
                    end
                end
            end
        end
    end
end)

-------------------------------------------------------------
-- client-side helpers triggered by server actions
-------------------------------------------------------------
RegisterNetEvent("cr-3dnui:client:setTime", function(hour, minute)
    hour = hour or 12
    minute = minute or 0
    NetworkOverrideClockTime(hour, minute, 0)
end)

RegisterNetEvent("cr-3dnui:client:setWeather", function(weatherType)
    weatherType = weatherType or "CLEAR"
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetWeatherTypeOverTime(weatherType, 15.0)
    Wait(15000)
    SetWeatherTypeNowPersist(weatherType)
    SetWeatherTypeNow(weatherType)
    SetWeatherTypePersist(weatherType)
end)

RegisterNetEvent("cr-3dnui:client:revive", function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    SetEntityHealth(ped, 200)
    ClearPedTasksImmediately(ped)
end)

RegisterNetEvent("cr-3dnui:client:spawnVehicle", function(model)
    model = model or "elegy2"
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
    local heading = GetEntityHeading(ped)

    local hash = joaat(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(0)
    end

    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    SetVehicleNumberPlateText(veh, "3DNUI")
    SetPedIntoVehicle(ped, veh, -1)
    SetModelAsNoLongerNeeded(hash)
end)
