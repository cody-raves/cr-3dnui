local QBCore = exports['qb-core']:GetCoreObject()

-- Detect qb-weathersync if it's running
local hasWeatherSync = false
if GetResourceState ~= nil then
    local state = GetResourceState('qb-weathersync')
    if state == 'started' or state == 'starting' then
        hasWeatherSync = true
        print("^2[3d-nui] Detected qb-weathersync, using its API for time/weather.^7")
    end
end

RegisterNetEvent("cr-3dnui:server:action", function(action)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if action == "cash_plus" then
        Player.Functions.AddMoney("cash", 5, "3dnui-panel")

    elseif action == "cash_minus" then
        Player.Functions.RemoveMoney("cash", 5, "3dnui-panel")

    elseif action == "give_water" then
        Player.Functions.AddItem("water_bottle", 1)
        local item = QBCore.Shared.Items["water_bottle"]
        if item then
            TriggerClientEvent("inventory:client:ItemBox", src, item, "add")
        end

    ----------------------------------------------------------------------
    -- TIME
    ----------------------------------------------------------------------
    elseif action == "time_day" then
        if hasWeatherSync then
            -- qb-weathersync controls time, so ask it
            TriggerEvent('qb-weathersync:server:setTime', 12, 0)
        else
            -- fallback: direct client override
            TriggerClientEvent("cr-3dnui:client:setTime", -1, 12, 0)
        end

    elseif action == "time_night" then
        if hasWeatherSync then
            TriggerEvent('qb-weathersync:server:setTime', 23, 0)
        else
            TriggerClientEvent("cr-3dnui:client:setTime", -1, 23, 0)
        end

    ----------------------------------------------------------------------
    -- WEATHER
    ----------------------------------------------------------------------
    elseif action == "weather_clear" then
        if hasWeatherSync then
            TriggerEvent('qb-weathersync:server:setWeather', "CLEAR")
        else
            TriggerClientEvent("cr-3dnui:client:setWeather", -1, "CLEAR")
        end

    elseif action == "weather_rain" then
        if hasWeatherSync then
            TriggerEvent('qb-weathersync:server:setWeather', "RAIN")
        else
            TriggerClientEvent("cr-3dnui:client:setWeather", -1, "RAIN")
        end

    ----------------------------------------------------------------------
    -- REVIVE / VEHICLE
    ----------------------------------------------------------------------
    elseif action == "revive" then
        TriggerClientEvent("cr-3dnui:client:revive", src)

    elseif action == "spawn_elegy" then
        TriggerClientEvent("cr-3dnui:client:spawnVehicle", src, "elegy2")

    ----------------------------------------------------------------------
    -- JOB / GANG (adjust names to your setup)
    ----------------------------------------------------------------------
    elseif action == "add_job" then
        -- Example: police grade 0 – change to what you actually use
        Player.Functions.SetJob("police", 0)

    elseif action == "remove_job" then
        Player.Functions.SetJob("unemployed", 0)

    elseif action == "add_gang" then
        if Player.Functions.SetGang then
            Player.Functions.SetGang("ballas", 0) -- make sure "ballas" exists in gangs config
        end

    elseif action == "remove_gang" then
        if Player.Functions.SetGang then
            Player.Functions.SetGang("none", 0) -- or whatever you use for "no gang"
        end
    end
end)
