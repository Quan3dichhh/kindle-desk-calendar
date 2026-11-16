-- Append-only, monthly CSV in persistent KOReader settings (outside releases).
-- Records actual samples only: no interpolation or backfilling during sleep.
local M = {}
M.__index = M
local HEADER = "timestamp_vietnam,epoch,battery_percent,delta_percentage_points,elapsed_minutes,power_state,display_mode,frontlight_native,version,event\n"
local function csv(value)
    if value == nil then return "" end
    return '"' .. tostring(value):gsub('"','""'):gsub('[\r\n]', ' ') .. '"'
end
function M.new(directory, version)
    return setmetatable({directory=directory, version=version}, M)
end
function M:record(epoch, battery, mode, level, event)
    local key = math.floor(epoch/3600)
    if (not event or event=="hourly") and self.hour == key and self.logged_version == self.version then return false end
    local path = self.directory .. "/deskcalendar-battery-" .. os.date("!%Y-%m",epoch+25200) .. ".csv"
    local file, err = io.open(path,"a+")
    if not file then self.error=tostring(err); return false end
    local ok, result = pcall(function()
        local size = file:seek("end")
        if size == 0 then assert(file:write(HEADER)) end
        -- Recover the preceding real sample across KOReader restarts.
        if not self.previous and size > 0 then
            file:seek("set",math.max(0,size-2048))
            local tail = file:read("*a")
            local last = tail:match('([^\n]+)\n$')
            local ts, capacity
            if last then ts, capacity = last:match('^"[^"]*","(%d+)","(%d+)"') end
            if ts and capacity then self.previous = {epoch=tonumber(ts), capacity=tonumber(capacity)} end
        end
        file:seek("end")
        local capacity = battery and battery.capacity
        local previous = self.previous
        local delta, elapsed
        if previous and previous.epoch <= epoch then
            elapsed = string.format("%.2f",(epoch-previous.epoch)/60)
            if capacity ~= nil and previous.capacity ~= nil then delta=capacity-previous.capacity end
        end
        local values = {csv(os.date("!%Y-%m-%d %H:%M:%S",epoch+25200)), csv(epoch), csv(capacity),
            csv(delta), csv(elapsed), csv(battery and battery.state or "unknown"), csv(mode),
            csv(level), csv(self.version), csv(event or "hourly")}
        assert(file:write(table.concat(values,",").."\n"))
        assert(file:flush())
        self.previous = {epoch=epoch, capacity=capacity}
        self.hour, self.logged_version = key, self.version
    end)
    file:close()
    self.last_path = path
    self.error = not ok and tostring(result) or nil
    return ok
end
return M
