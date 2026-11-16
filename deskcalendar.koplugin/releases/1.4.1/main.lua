local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local PluginShare = require("pluginshare")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local Screen = Device.screen
local DIR = debug.getinfo(1, "S").source:match("^@(.*/)") or "plugins/deskcalendar.koplugin/"
local Model = dofile(DIR .. "model.lua")
local Layout = dofile(DIR .. "layout.lua")
local Schedule = dofile(DIR .. "schedule.lua")
local Battery = dofile(DIR .. "battery.lua")
local ROOT = DIR:match("^(.*[/])releases/[^/]+/$") or DIR
local VERSION = dofile(DIR .. "version.lua")
local ClockText = dofile(DIR .. "clocktext.lua")
local Light = dofile(DIR .. "light.lua")
local Sleep = dofile(DIR .. "sleep.lua")
local BatteryLog = dofile(DIR .. "batterylog.lua")
local Charge = dofile(DIR .. "charge.lua")

local CalendarView = InputContainer:extend{covers_fullscreen = true, modal = true, stop_events_propagation = true}

function CalendarView:init()
    self.dimen = Geom:new{x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight()}
    self.offset, self.content_step = 0, 0
    self.ges_events = {
        Hold = {GestureRange:new{ges = "hold", range = self.dimen}},
        Tap = {GestureRange:new{ges = "tap", range = self.dimen}},
        Swipe = {GestureRange:new{ges = "swipe", range = self.dimen}},
    }
    self.key_events = self.key_events or {}
    self.key_events.Exit = {{"Back"}, {"Esc"}}
    self.key_events.Home = {{"Home"}}
    self.tick_task = function() self:tick() end
    self.light = Light.new(Device, UIManager)
    self.battery_log = BatteryLog.new(DataStorage:getSettingsDir(), VERSION)
    self.last_clean = os.time()
    self:rebuild(os.time())
end

function CalendarView:makeText(value, px, bold, maxw, maxh, serif, tight)
    if tight then return ClockText.make(value, maxw, maxh, Screen, Font, px) end
    local scale = Screen:scaleBySize(100) / 100
    local target = math.max(6, px)
    for attempt = 1, 12 do
        local name = serif and "NotoSerif-Regular.ttf" or "cfont"
        local face = Font:getFace(name, target / scale) or Font:getFace("cfont", target / scale)
        local widget = TextWidget:new{text = value, face = face, bold = bold, padding = 0}
        local size = widget:getSize()
        if (size.w <= maxw and size.h <= maxh) or target <= 6 then
            return {widget = widget, w = size.w, h = size.h, text = value, px = target, bold = bold, serif = serif}
        end
        local ratio = math.min(maxw / math.max(size.w, 1), maxh / math.max(size.h, 1), 0.95)
        widget:free()
        target = math.max(6, math.floor(target * ratio * 0.98))
    end
    error("Cannot fit calendar text")
end

function CalendarView:freeScene()
    if not self.scene then return end
    for _, item in ipairs(self.scene.items) do item.widget:free() end
    self.scene = nil
end

function CalendarView:rebuild(epoch)
    local model = Model.get(epoch, self.offset, self.owner.mode, self.content_step)
    if self.model and model.today_jd ~= self.model.today_jd then
        self.offset = 0
        model = Model.get(epoch, self.offset, self.owner.mode, self.content_step)
    end
    if self.model and model.hour_key ~= self.model.hour_key then
        self.content_step = 0
        model = Model.get(epoch, self.offset, self.owner.mode, self.content_step)
    end
    model.night = Schedule.isNight(epoch)
    model.display_mode = Schedule.mode(epoch, self.owner.weekend_fast, self.boost_until)
    model.battery = Battery.read(Device)
    local charge_event
    if self.owner.charger then
        charge_event = self.owner.charger:tick(model.battery, epoch)
        self.owner.charger:decorate(model.battery)
    end
    local scene = Layout.build(self.dimen.w, self.dimen.h, model, function(...) return self:makeText(...) end, self.owner.layout)
    self:freeScene()
    self.model, self.scene = model, scene
    self.light:nightMode(Schedule.isNight(epoch))
    if self.owner.hourly_log or charge_event then
        self.battery_log:record(epoch, model.battery, model.display_mode, self.light:read(), charge_event or "hourly")
    end
end

-- Charger checks do not advance the displayed clock between its scheduled ticks.
function CalendarView:checkCharge()
    if self.closed then return end
    local epoch = os.time()
    local battery = Battery.read(Device)
    local event = self.owner.charger:tick(battery, epoch)
    self.owner.charger:decorate(battery)
    if self.owner.hourly_log or event then
        self.battery_log:record(epoch, battery, Schedule.mode(epoch, self.owner.weekend_fast, self.boost_until),
            self.light:read(), event or "hourly")
    end
    if self.model then
        local changed = self.model.battery.text ~= battery.text
        self.model.battery = battery
        if changed and not self.suspended then
            local scene = Layout.build(self.dimen.w, self.dimen.h, self.model,
                function(...) return self:makeText(...) end, self.owner.layout)
            self:freeScene()
            self.scene = scene
            UIManager:setDirty(self, "ui", Geom:new(scene.status_rect))
        end
    end
end

function CalendarView:paintTo(bb, x, y)
    x, y = x or 0, y or 0
    self.dimen.x, self.dimen.y = x, y
    -- Paint white before drawing. The whole old clock rectangle is refreshed,
    -- so narrower digits cannot leave fragments from the preceding minute.
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if not self.scene then return end
    for _, line in ipairs(self.scene.lines) do
        bb:paintRect(x + line.x, y + line.y, line.w, line.h, Blitbuffer.Color8(line.gray))
    end
    for _, circle in ipairs(self.scene.circles) do
        bb:paintCircle(x + circle.x, y + circle.y, circle.r, Blitbuffer.COLOR_BLACK, circle.thickness)
    end
    for _, item in ipairs(self.scene.items) do item.widget:paintTo(bb, x + item.x, y + item.y) end
end

function CalendarView:acquireWakeLock()
    if self.wake_lock then return end
    self.old_pause, self.old_keepalive = PluginShare.pause_auto_suspend, PluginShare.keepalive
    PluginShare.pause_auto_suspend, PluginShare.keepalive = true, true
    if Device:isKindle() then os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 1") end
    self.wake_lock = true
end

function CalendarView:releaseWakeLock()
    if not self.wake_lock then return end
    PluginShare.pause_auto_suspend, PluginShare.keepalive = self.old_pause, self.old_keepalive
    if Device:isKindle() and not self.old_keepalive then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver 0")
    end
    self.wake_lock = false
end

function CalendarView:scheduleTick()
    UIManager:unschedule(self.tick_task)
    if not self.closed and not self.suspended then
        local delay = Schedule.delay(os.time(), self.owner.weekend_fast, self.boost_until, self.owner.hourly_log)
        UIManager:scheduleIn(delay, self.tick_task)
        if self.sleep then self.sleep:plan() end
    end
end

function CalendarView:refresh(full)
    if self.closed then return end
    local ok, err = pcall(function()
        local epoch = os.time()
        local nextModel = Model.get(epoch, self.offset, self.owner.mode, self.content_step)
        if self.model and nextModel.today_jd ~= self.model.today_jd then self.offset = 0; full = true end
        if self.model and nextModel.hour_key ~= self.model.hour_key then self.content_step = 0; full = true end
        if epoch - self.last_clean >= 15 * 60 then full = true end
        local old_mode = self.model and self.model.display_mode
        self:rebuild(epoch)
        self.light:pulse(epoch, self.owner.hourly_light, Schedule.isNight(epoch))
        if old_mode ~= self.model.display_mode then full = true end
        if full then
            self.last_clean = epoch
            UIManager:setDirty(self, "full", self.dimen)
        else
            UIManager:setDirty(self, "ui", Geom:new(self.scene.clock_rect))
            UIManager:setDirty(self, "ui", Geom:new(self.scene.status_rect))
        end
    end)
    if not ok then
        logger.err("DeskCalendar rendering failed:", err)
        self:closeCalendar()
        UIManager:show(InfoMessage:new{text = "Lịch bàn gặp lỗi. Đã trở về KOReader."})
    end
end

function CalendarView:tick()
    if self.closed or self.suspended then return end
    self:refresh(false)
    self:scheduleTick()
end

function CalendarView:onTap(_, ges)
    self.boost_until = os.time() + 300
    if self.offset ~= 0 then
        self.offset = 0
    elseif ges and ges.pos and ges.pos.y >= self.dimen.h * 805 / 1072 then
        self.content_step = self.content_step + 1
    end
    self:refresh(true)
    self:scheduleTick()
    return true
end

function CalendarView:onSwipe(_, ges)
    self.boost_until = os.time() + 300
    local direction = ges and ges.direction
    if direction == "west" then self.offset = math.min(366, self.offset + 1)
    elseif direction == "east" then self.offset = math.max(-366, self.offset - 1)
    else return true end
    self:refresh(true)
    self:scheduleTick()
    return true
end

function CalendarView:cleanup()
    if self.closed then return end
    self.closed = true
    if self.sleep then self.sleep:close() end
    self.owner:stopCharge(self)
    self.light:close()
    UIManager:unschedule(self.tick_task)
    self:releaseWakeLock()
    self:freeScene()
    if self.old_rotation ~= nil and Screen:getRotationMode() ~= self.old_rotation then
        Screen:setRotationMode(self.old_rotation)
    end
    if self.owner and self.owner.view == self then self.owner.view = nil end
end

function CalendarView:closeCalendar()
    if self.closed then return true end
    self:cleanup()
    UIManager:close(self)
    UIManager:setDirty("all", "full")
    return true
end

CalendarView.onHold = CalendarView.closeCalendar
CalendarView.onExit = CalendarView.closeCalendar
CalendarView.onHome = CalendarView.closeCalendar
CalendarView.onCloseWidget = CalendarView.cleanup

function CalendarView:onSuspend()
    if self.closed or self.suspended then return end
    self.suspended = true
    UIManager:unschedule(self.owner.charge_task)
    self.boost_until = nil
    self.light:stop(true)
    if self.sleep then self.sleep:suspend() end
    UIManager:unschedule(self.tick_task)
end

function CalendarView:onResume()
    if self.closed or not self.suspended then return end
    self.suspended = false
    if self.sleep then self.sleep:resume() end
    if not self.programmatic_resume then self.boost_until = os.time() + 300 end
    self.programmatic_resume = nil
    self:acquireWakeLock()
    self:refresh(true)
    self:scheduleTick()
    self.owner:scheduleCharge()
end

local DeskCalendar = WidgetContainer:extend{name = "deskcalendar", is_doc_only = false}

function DeskCalendar:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/deskcalendar.lua")
    self.mode = self.settings:readSetting("mode") or "mixed"
    if self.mode ~= "mixed" and self.mode ~= "words" and self.mode ~= "quotes" then self.mode = "mixed" end
    self.layout = self.settings:readSetting("layout")
    if self.layout ~= "stacked" then self.layout = "split" end
    self.weekend_fast = self.settings:readSetting("weekend_fast") == true
    self.continuous_power = self.settings:readSetting("continuous_power") ~= false
    self.hourly_light = self.settings:readSetting("hourly_light") ~= false
    self.hourly_log = self.settings:readSetting("hourly_log") ~= false
    self.sleep_enabled = self.settings:readSetting("sleep_enabled") ~= false
    self.charge_enabled = self.settings:readSetting("charge_enabled") ~= false
    self.charger = Charge.new{directory=DataStorage:getSettingsDir(), version=VERSION,
        script=DIR.."charge-watchdog.txt", kindle=Device:isKindle(),
        phase=self.settings:readSetting("charge_phase"),
        save_phase=function(value) self.settings:saveSetting("charge_phase",value); self.settings:flush() end}
    self.charge_task = function()
        if self.view and not self.view.closed and not self.view.suspended then
            self.view:checkCharge()
            self:scheduleCharge()
        end
    end
    self.ui.menu:registerToMainMenu(self)
    Dispatcher:registerAction("desk_calendar", {category = "none", event = "ShowDeskCalendar", title = "Lịch bàn", general = true})
    for _, name in ipairs({"ui/elements/filemanager_menu_order", "ui/elements/reader_menu_order"}) do
        local ok, order = pcall(require, name)
        if ok and order.tools then
            local found = false
            for _, entry in ipairs(order.tools) do if entry == "deskcalendar" then found = true end end
            if not found then table.insert(order.tools, 1, "deskcalendar") end
        end
    end
end

function DeskCalendar:scheduleCharge()
    UIManager:unschedule(self.charge_task)
    if self.charge_enabled and self.view and not self.view.closed and not self.view.suspended
        and (self.charger.running or self.charger.pending) then
        UIManager:scheduleIn(self.charger.pending and 1 or 30, self.charge_task)
    end
end

function DeskCalendar:stopCharge(view)
    UIManager:unschedule(self.charge_task)
    local had_control = self.charger.owned
    local ok = self.charger:stop()
    if had_control and view and view.battery_log then
        view.battery_log:record(os.time(), Battery.read(Device), view.model.display_mode,
            view.light:read(), ok and "charge_restore" or "charge_restore_error")
    end
end

function DeskCalendar:openCalendar()
    if self.view and not self.view.closed then self.view:refresh(true); return end
    local oldRotation = Screen:getRotationMode()
    local ok, result = pcall(function()
        if Screen:getWidth() < Screen:getHeight() then
            Screen:setRotationMode((oldRotation + 1) % 4)
        end
        return CalendarView:new{owner = self, old_rotation = oldRotation}
    end)
    if not ok then
        Screen:setRotationMode(oldRotation)
        logger.err("DeskCalendar could not open:", result)
        UIManager:show(InfoMessage:new{text = "Không mở được lịch bàn. Vui lòng mở lại KOReader."})
        return
    end
    self.view = result
    self.view:acquireWakeLock()
    UIManager:show(self.view, "full")
    if self.sleep_enabled then self.view.sleep = Sleep.new(self.view, Device, UIManager, Schedule) end
    if self.charge_enabled then self.charger:begin(os.time()) end
    self.view:refresh(true)
    self.view:scheduleTick()
    self:scheduleCharge()
end

function DeskCalendar:setLayout(value)
    if value ~= "split" and value ~= "stacked" then return false end
    self.layout = value
    self.settings:saveSetting("layout", value)
    self.settings:flush()
    if self.view then self.view:refresh(true) end
    return true
end

function DeskCalendar:setOption(key, value)
    if not ({weekend_fast=true, continuous_power=true, hourly_light=true, hourly_log=true, sleep_enabled=true, charge_enabled=true})[key]
        or type(value) ~= "boolean" then return false end
    self[key] = value
    self.settings:saveSetting(key, value)
    self.settings:flush()
    if key == "charge_enabled" then
        if value and self.view then
            local ok = self.charger:begin(os.time())
            if not ok then UIManager:show(InfoMessage:new{text=self.charger.error}) end
        elseif not value then self:stopCharge(self.view) end
        self:scheduleCharge()
    end
    if self.view then
        if key == "sleep_enabled" then
            if self.view.sleep then self.view.sleep:close(); self.view.sleep = nil end
            if value then self.view.sleep = Sleep.new(self.view, Device, UIManager, Schedule) end
        end
        if key == "hourly_light" and not value then self.view.light:stop(true) end
        self.view:refresh(true)
        self.view:scheduleTick()
    end
    return true
end

function DeskCalendar:addToMainMenu(menu)
    local UpdateUI = dofile(DIR .. "updateui.lua")
    local layouts = {}
    for _, choice in ipairs({{"split", "Hai cột (hiện tại)"}, {"stacked", "Đồng hồ phía trên"}}) do
        local value, label = choice[1], choice[2]
        layouts[#layouts + 1] = {text = label, radio = true,
            checked_func = function() return self.layout == value end,
            callback = function() self:setLayout(value) end,
        }
    end
    local power_choices = {}
    for _, item in ipairs({
        {"charge_enabled", "Giới hạn sạc 20–80% (khi mở lịch)"},
        {"continuous_power", "Dùng khi cắm sạc thường xuyên"},
        {"weekend_fast", "Cuối tuần: cập nhật mỗi phút ban ngày"},
        {"hourly_light", "Đèn sáng rồi mờ dần vào đầu giờ"},
        {"hourly_log", "Ghi log pin mỗi giờ (kèm phiên bản)"},
        {"sleep_enabled", "Ngủ giữa các lần cập nhật (cần thử trên máy)"},
    }) do
        local key, label = item[1], item[2]
        power_choices[#power_choices + 1] = {text=label,
            checked_func=function() return self[key] end,
            callback=function() self:setOption(key, not self[key]) end}
    end
    power_choices[#power_choices+1] = {text="Trạng thái giới hạn sạc", callback=function()
        local supported, reason = self.charger:probe()
        UIManager:show(InfoMessage:new{text="Ngừng sạc từ 80%, bật lại khi dưới 20%.\n" ..
            "20–79% giữ trạng thái trước. Chỉ hoạt động khi lịch đang mở.\n" ..
            "Thoát lịch/tắt giới hạn sẽ yêu cầu cho phép sạc bình thường.\n" ..
            "Bộ điều khiển: " .. (supported and "MAX77696" or tostring(reason)) ..
            "\nTrạng thái: " .. self.charger.state ..
            (self.charger.error and ("\n"..self.charger.error) or "") ..
            "\nLog có version và sự kiện charge_hold / charge_resume."})
    end}
    power_choices[#power_choices+1] = {text="Xem thông tin log pin", callback=function()
        local log = self.view and self.view.battery_log
        UIManager:show(InfoMessage:new{text="CSV theo tháng, trong thư mục settings của KOReader.\nCột version ghi phiên bản ở từng lần đo.\n" ..
            (log and log.last_path or "deskcalendar-battery-YYYY-MM.csv") ..
            ((log and log.error) and ("\nLỗi ghi: " .. log.error) or "")})
    end}
    local choices = {}
    for _, choice in ipairs({{"mixed", "Luân phiên từ vựng / châm ngôn"}, {"words", "Chỉ từ tiếng Anh"}, {"quotes", "Chỉ châm ngôn"}}) do
        local value, label = choice[1], choice[2]
        choices[#choices + 1] = {text = label,
            checked_func = function() return self.mode == value end,
            callback = function()
                self.mode = value
                self.settings:saveSetting("mode", value)
                self.settings:flush()
                if self.view then self.view.content_step = 0; self.view:refresh(true) end
            end,
        }
    end
    menu.deskcalendar = {text = "Lịch bàn", sorting_hint = "tools", sub_item_table = {
        {text = "Mở lịch bàn", callback = function() self:openCalendar() end},
        {text = "Chọn giao diện", sub_item_table = layouts},
        {text = "Pin, đèn và lịch hoạt động", sub_item_table = power_choices},
        {text = "Nội dung mỗi giờ", sub_item_table = choices},
        {text = "Cập nhật qua Wi-Fi", callback = function() UpdateUI.check(ROOT, DIR, VERSION) end},
        {text = "Khôi phục bản trước", callback = function() UpdateUI.rollback(ROOT, DIR) end},
        {text = "Phiên bản " .. VERSION, enabled = false},
        {text = "Cách dùng", callback = function()
            UIManager:show(InfoMessage:new{text = "Nhấn giữ để thoát. Chạm để xem giờ chính xác trong 5 phút.\n06:00–19:00: 5 phút/lần, phần phút nhỏ bằng 2/3 giờ.\n19:00–23:00: mỗi phút. 23:00–06:00: chỉ lịch.\nCắm sạc thường xuyên: giữ ứng dụng hoạt động, vẫn dùng lịch trên. Giới hạn sạc 20–80% tự nhận MAX77696; xem trạng thái trong menu.\nLog CSV mỗi giờ kèm phiên bản; khi ngủ, máy thức ngắn để đo pin.\nCơ chế ngủ/RTC và đèn cần kiểm tra trên Kindle thực tế."})
        end},
    }}
end

DeskCalendar.onShowDeskCalendar = DeskCalendar.openCalendar
function DeskCalendar:onCharging()
    local view = self.view
    if not view then return end
    if view.suspended then
        if (self.continuous_power or self.charge_enabled) and view.sleep then view.sleep:wake() end
    else view:checkCharge(); view:scheduleTick(); self:scheduleCharge() end
end
function DeskCalendar:onNotCharging()
    if self.view and not self.view.suspended then self.view:checkCharge(); self.view:scheduleTick(); self:scheduleCharge() end
end
function DeskCalendar:onSuspend() if self.view then self.view:onSuspend() end end
function DeskCalendar:onResume() if self.view then self.view:onResume() end end
function DeskCalendar:onCloseWidget() if self.view then self.view:closeCalendar() end end
function DeskCalendar:onFlushSettings() self.settings:saveSetting("mode", self.mode); self.settings:saveSetting("layout", self.layout); self.settings:flush() end

return DeskCalendar
