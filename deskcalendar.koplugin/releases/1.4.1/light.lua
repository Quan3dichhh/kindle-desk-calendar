-- Nonblocking hourly frontlight pulse via KOReader's public PowerD API.
-- No charger registers or charging-control files are written here.
local M = {}
M.__index = M
function M.new(device, ui)
    return setmetatable({device=device, ui=ui}, M)
end
function M:power()
    if not self.device.hasFrontlight or not self.device:hasFrontlight() then return end
    local ok, power = pcall(self.device.getPowerDevice, self.device)
    if ok and power and power.setIntensity and power.frontlightIntensity then return power end
end
function M:read()
    local power = self:power()
    if not power then return end
    local ok, level = pcall(power.frontlightIntensity, power)
    if ok and type(level) == "number" then return level, power end
end
function M:set(level)
    local power = self:power()
    if not power then return false end
    local ok = pcall(power.setIntensity, power, level, true)
    if ok then self.last = level end
    return ok
end
function M:stop(restore)
    if self.task then self.ui:unschedule(self.task) end
    local current = self:read()
    -- A manual brightness change takes ownership from the pulse.
    if restore and self.original ~= nil and current == self.last then self:set(self.original) end
    self.original, self.task = nil, nil
end
function M:nightMode(night)
    if night and not self.night then
        self:stop(true)
        self.night_original = self:read()
        self:set(0)
        self.night = true
    elseif not night and self.night then
        if self:read() == 0 and self.night_original ~= nil then self:set(self.night_original) end
        self.night, self.night_original = nil, nil
    end
end
function M:pulse(epoch, enabled, night)
    self:nightMode(night)
    local key = math.floor(epoch / 3600)
    -- Do not flash when opening at an arbitrary point in an hour or replay missed hours.
    if not enabled or night or epoch % 3600 >= 90 or self.hour == key then return false end
    self.hour = key
    self:stop(true)
    local current, power = self:read()
    if current == nil then return false end
    local peak = math.max(current, math.floor((power.fl_max or 24) * 0.65 + 0.5))
    self.original, self.start, self.peak = current, epoch, peak
    if not self:set(peak) then self.original = nil; return false end
    self.task = function()
        if self:read() ~= self.last then self:stop(false); return end
        local fraction = math.min(1, math.max(0, (os.time() - self.start) / 60))
        self:set(math.floor(self.peak + (self.original - self.peak) * fraction + 0.5))
        if fraction >= 1 then self:stop(true)
        else self.ui:scheduleIn(3, self.task) end
    end
    self.ui:scheduleIn(3, self.task)
    return true
end
function M:close()
    self:stop(true)
    self:nightMode(false)
end
return M
