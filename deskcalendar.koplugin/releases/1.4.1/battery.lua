-- Read-only status: never changes any charging or power-control setting.
local M = {}
local function call(obj, name)
    if obj and type(obj[name]) == "function" then
        local ok, value = pcall(obj[name], obj)
        if ok then return value end
    end
end
local function statusFile(path)
    local file = path and io.open(path, "rb")
    if not file then return nil end
    local status = file:read(64)
    file:close()
    return status and status:match("^%s*(.-)%s*$")
end
function M.read(device, readStatus)
    local power = call(device, "getPowerDevice")
    if not power then return {text = "Pin: --% · Không rõ", state = "unknown"} end
    local capacity = tonumber(call(power, "getCapacity"))
    if capacity and (capacity ~= capacity or capacity < 0 or capacity > 100) then capacity = nil end
    local percent = capacity and (tostring(math.floor(capacity + 0.5)) .. "%") or "--%"
    local status = (readStatus or statusFile)(power.batt_status_file)
    if not status and call(device, "isKindle") then
        status = (readStatus or statusFile)("/sys/class/power_supply/max77696-battery/status")
    end
    local state, label
    if status == "Full" or call(power, "isCharged") == true then
        state, label = "full", "Đã đầy"
    elseif status == "Charging" then
        state, label = "charging", "Đang sạc"
    elseif status == "Not charging" then
        state, label = "paused", "Chưa sạc"
    elseif status == "Discharging" then
        state, label = "battery", "Dùng pin"
    else
        -- On Kindle, KOReader's isCharging can mean plugged in, even at full.
        local plugged = call(power, "isCharging")
        if plugged == true then state, label = "plugged", "Cắm sạc"
        elseif plugged == false then state, label = "battery", "Dùng pin"
        else state, label = "unknown", "Không rõ" end
    end
    return {capacity = capacity, state = state, plugged = state == "charging" or state == "full" or state == "plugged", text = "Pin " .. percent .. " · " .. label}
end
return M
