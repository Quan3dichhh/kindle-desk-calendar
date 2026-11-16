-- Kindle suspend + RTC refresh. Only installed while the calendar is open.
-- Uses KOReader's wakeup_mgr; never writes the RTC directly.
local M = {}
M.__index = M
function M.new(view, device, ui, schedule)
    local power = device.getPowerDevice and device:getPowerDevice()
    local mgr = device.wakeup_mgr
    if not (device:isKindle() and device.supportsScreensaver and device:supportsScreensaver()
        and mgr and mgr.addTask and mgr.removeTasks and power and power.toggleSuspend
        and device.screen.bb and device.screen.refreshFull) then return end
    local ok, saver = pcall(require, "ui/screensaver")
    if not ok or not saver.setup or not saver.show or not saver.close then return end
    local self = setmetatable({view=view, device=device, ui=ui, schedule=schedule,
        power=power, mgr=mgr, saver=saver, originals={}}, M)
    self.alarm_task = function()
        -- WakeupMgr removes its current task *after* invoking us. Re-arm later.
        local due = self.due or os.time()
        self.ui:unschedule(self.rtc_task)
        self.ui:scheduleIn(math.max(0.2, due - os.time() + 0.15), self.rtc_task)
    end
    self.rtc_task = function() self:rtc() end
    self.idle_task = function() self:idle() end
    self.originals.setup, self.originals.show, self.originals.close = saver.setup, saver.show, saver.close
    self.setup_hook = function(...)
        if self.closed then return self.originals.setup(...) end
        self.view.boost_until = nil
        self:arm()
    end
    self.show_hook = function(...)
        if self.closed then return self.originals.show(...) end
        self.device.screen_saver_mode = true
        self:paint()
    end
    self.close_hook = function(...)
        if self.closed then return self.originals.close(...) end
        self.device.screen_saver_mode, self.device.screen_saver_lock = false, false
        return true
    end
    saver.setup, saver.show, saver.close = self.setup_hook, self.show_hook, self.close_hook
    return self
end
function M:arm()
    self.mgr:removeTasks(nil, self.alarm_task)
    if self.closed or self.view.closed then return end
    self.display_due = self.schedule.nextEpoch(os.time(), self.view.owner.weekend_fast, nil, self.view.owner.hourly_log)
    self.due = self.display_due
    local charger = self.view.owner.charger
    if charger and charger:needsWake() then self.due=math.min(self.due,os.time()+60) end
    self.mgr:addTask(math.max(1, self.due - os.time()), self.alarm_task)
end
function M:cancelAlarm()
    self.mgr:removeTasks(nil, self.alarm_task)
    self.ui:unschedule(self.rtc_task)
end
function M:paint()
    if self.closed or self.view.closed then return end
    local ok, err = pcall(function()
        self.view:rebuild(os.time())
        self.view.light:nightMode(self.schedule.isNight(os.time()))
        self.view:paintTo(self.device.screen.bb, 0, 0)
        self.device.screen:refreshFull(0, 0, self.view.dimen.w, self.view.dimen.h)
    end)
    if not ok then
        require("logger").err("DeskCalendar sleep refresh failed", err)
        self.failed = true
    end
    return ok
end
function M:wake()
    self.view.programmatic_resume = true
    self.power:toggleSuspend()
end
function M:rtc()
    if self.closed or self.view.closed or not self.view.suspended then return end
    local now = os.time()
    if not self.display_due or now>=self.display_due then self:paint()
    elseif self.view.owner.charger then self.view:checkCharge() end
    self:arm()
    local view = self.view
    local plugged = view.model.battery and view.model.battery.plugged
    local pulse = view.owner.hourly_light and not self.schedule.isNight(now) and now % 3600 < 90
    if self.failed or self.schedule.mode(now, view.owner.weekend_fast) == "minute"
        or pulse or (view.owner.continuous_power and plugged) then self:wake() end
end
function M:shouldSleep()
    local view = self.view
    local plugged = view.model and view.model.battery and view.model.battery.plugged
    return not (self.failed or view.closed or view.suspended
        or view.old_keepalive or view.old_pause
        or (view.owner.continuous_power and plugged))
        and self.schedule.mode(os.time(), view.owner.weekend_fast, view.boost_until) ~= "minute"
end
function M:plan()
    self.ui:unschedule(self.idle_task)
    if self:shouldSleep() then self.ui:scheduleIn(self.view.light.task and 62 or 3, self.idle_task) end
end
function M:idle()
    if not self:shouldSleep() then return end
    -- Arm first. Clearing preventScreenSaver is required before toggleSuspend.
    self:arm()
    self.view.light:stop(true)
    self.view:releaseWakeLock()
    local ok, err = pcall(self.power.toggleSuspend, self.power)
    if not ok then
        self.failed = true
        require("logger").err("DeskCalendar suspend request failed", err)
        self.view:acquireWakeLock()
        self:cancelAlarm()
    end
end
function M:suspend()
    self.ui:unschedule(self.idle_task)
    self.view.light:stop(true)
    self.view:releaseWakeLock()
    self:arm()
end
function M:resume()
    self:cancelAlarm()
end
function M:close()
    if self.closed then return end
    self.closed = true
    self.ui:unschedule(self.idle_task)
    self:cancelAlarm()
    -- Restore only our own hooks so other plugins' later hooks keep ownership.
    for _, pair in ipairs({{"setup",self.setup_hook},{"show",self.show_hook},{"close",self.close_hook}}) do
        if self.saver[pair[1]] == pair[2] then self.saver[pair[1]] = self.originals[pair[1]] end
    end
end
return M
