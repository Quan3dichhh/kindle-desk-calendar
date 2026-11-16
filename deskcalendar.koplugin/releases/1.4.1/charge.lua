-- MAX77696 only. Driver controls follow André Cheng's chargectl (MIT),
-- https://github.com/chengandre/ereader-charge-limit/blob/main/src/chargectl.c
-- MODE 4 stops charging; MODE 5 permits charging. Never writes raw I2C.
local M = {}
M.__index = M
local BASE = "/sys/devices/system/wario_charger/wario_charger0/"
local function read(path)
    local file = io.open(path,"rb")
    if not file then return end
    local text = file:read(4096); file:close()
    return text and text:match("^%s*(.-)%s*$")
end
local function write(path, value)
    local file, err = io.open(path,"wb")
    if not file then return false, err end
    local ok, message = file:write(value)
    local closed, close_err = file:close()
    return ok ~= nil and closed ~= nil, message or close_err
end
local function quote(value) return "'"..tostring(value):gsub("'", "'\\''").."'" end
local function process(requested_pid)
    if requested_pid and not tostring(requested_pid):match("^%d+$") then return end
    local stat = read("/proc/"..(requested_pid or "self").."/stat")
    if not stat then return end
    local pid = stat:match("^(%d+) ")
    local fields = {}
    for item in (stat:match("^%d+ %b() (.*)$") or ""):gmatch("%S+") do fields[#fields+1]=item end
    if pid and fields[20] and fields[20]:match("^%d+$") then return pid, fields[20] end
end
function M.new(options)
    local self = setmetatable(options or {},M)
    self.read = self.read or read
    self.write = self.write or write
    self.remove = self.remove or os.remove
    self.process = self.process or process
    self.spawn = self.spawn or function(command) return os.execute(command) end
    self.marker = self.directory.."/deskcalendar-charge.guard"
    self.ready = self.directory.."/deskcalendar-charge.ready"
    self.report = self.directory.."/deskcalendar-charge-recovery.log"
    self.phase = self.phase == "hold" and "hold" or "charge"
    self.state = "idle"
    return self
end
function M:probe()
    if not self.kindle then return false, "Không phải Kindle" end
    local mode = self.read(BASE.."mode")
    local connected = self.read(BASE.."connected")
    if (mode ~= "4" and mode ~= "5") or (connected ~= "0" and connected ~= "1")
        or self.read(BASE.."allow_charging") == nil then
        return false, "Chưa xác định được bộ điều khiển MAX77696 tương thích"
    end
    -- Avoid two programs fighting over the same charger.
    if self.read("/tmp/chargelimitd.lock/pid") then return false, "Charge Limit khác đang chạy" end
    return true, mode, connected == "1"
end
function M:begin(epoch)
    if self.running or self.pending then return true end
    local ok, reason = self:probe()
    if not ok then self.state,self.error="unsupported",reason; return false end
    local pid, start = self.process()
    if not pid then self.state,self.error="error","Không xác định được tiến trình KOReader"; return false end
    self.error=nil
    self.token = tostring(pid).."-"..tostring(start).."-"..tostring(epoch)
    local written = self.write(self.marker,self.token)
    if not written then self.state,self.error="error","Không tạo được dấu kiểm soát sạc"; return false end
    self.remove(self.ready)
    self.spawn("nohup sh "..quote(self.script).." "..quote(self.marker).." "..quote(self.token).." "..
        quote(pid).." "..quote(start).." "..quote(self.ready).." "..quote(self.report).." "..
        quote(self.version).." >/dev/null 2>&1 &")
    self.pending,self.deadline,self.state=true,epoch+8,"starting"
    return true
end
function M:guardReady()
    if not self.token or self.read(self.marker)~=self.token then return false end
    local ready=self.read(self.ready)
    if not ready then return false end
    local token,pid,start=ready:match("^([^\n]+)\n(%d+)\n(%d+)$")
    if token~=self.token then return false end
    local actual_pid,actual_start=self.process(pid)
    return actual_pid==pid and actual_start==start
end
function M:setPhase(value)
    if self.phase ~= value then
        self.phase=value
        if self.save_phase then self.save_phase(value) end
    end
end
function M.decide(capacity, phase)
    if type(capacity)~="number" or capacity~=capacity or capacity<0 or capacity>100 then return nil end
    if capacity>=80 then return "hold" end
    if capacity<20 then return "charge" end
    return phase=="hold" and "hold" or "charge"
end
function M:apply(enable)
    if not enable then
        if not self:guardReady() or self.read(BASE.."connected")~="1" then return false end
    end
    local path,value = BASE..(enable and "allow_charging" or "mode"),enable and "1" or "4"
    local ok = self.write(path,value)
    if not enable then self.owned=true end -- even a short/failed write needs restoration
    return ok and self.read(BASE.."mode")== (enable and "5" or "4")
end
function M:restore()
    if not self.owned then return true end
    local ok=self:apply(true)
    if ok then self.owned=false end
    return ok
end
function M:fail(message)
    local restored=self:restore()
    self.running,self.pending=false,false
    self.error=message..(restored and "" or "; chưa xác nhận khôi phục sạc")
    self.state="error"
    -- Keep the supervisor alive if immediate restoration failed.
    if self.read(self.marker)==self.token then self.remove(self.marker) end
    return "charge_error"
end
function M:tick(battery, epoch)
    if self.pending then
        if self:guardReady() then self.pending,self.running=false,true
        elseif epoch>=self.deadline then return self:fail("Không khởi động được giám sát khôi phục sạc")
        else return end
    end
    if not self.running then return end
    if not self:guardReady() then return self:fail("Mất giám sát khôi phục sạc") end
    local ok,mode,plugged=self:probe()
    if not ok then return self:fail(mode) end
    self.connected=plugged
    if not plugged then
        if not self:restore() then return self:fail("Không khôi phục được sạc khi rút nguồn") end
        self.state="unplugged"
        return
    end
    local phase=M.decide(battery and battery.capacity,self.phase)
    if not phase then return self:fail("Không đọc được phần trăm pin hợp lệ") end
    self:setPhase(phase)
    if phase=="hold" and mode=="4" then self.owned=true end
    local want=phase=="hold" and "4" or "5"
    if mode~=want then
        if not self:apply(phase=="charge") then return self:fail("Lệnh bật/tắt sạc chưa được xác nhận") end
        self.state=phase
        return phase=="hold" and "charge_hold" or "charge_resume"
    end
    self.state=phase
end
function M:decorate(battery)
    if not self.running then return battery end
    if self.connected~=nil then battery.plugged=self.connected end
    if self.connected and self.state=="hold" then
        battery.state="charge_limited"
        battery.text="Pin "..tostring(battery.capacity or "--").."% · Ngừng sạc (20–80%)"
    elseif self.connected then
        battery.text=(battery.text or "").." · Giới hạn 20–80%"
    end
    return battery
end
function M:needsWake()
    return self.running and self.connected==true
end
function M:stop()
    local ok=self:restore()
    self.running,self.pending=false,false
    if self.read(self.marker)==self.token then self.remove(self.marker) end
    if ok then
        self.state="idle"
    else self.state,self.error="error","Chưa xác nhận khôi phục sạc; giám sát sẽ thử lại" end
    return ok
end
return M
