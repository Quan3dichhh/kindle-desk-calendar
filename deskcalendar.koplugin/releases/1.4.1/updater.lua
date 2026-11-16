local M = {repository = "Quan3dichhh/kindle-desk-calendar", max_file = 512 * 1024, max_total = 4 * 1024 * 1024}
local REQUIRED = {"main.lua", "layout.lua", "model.lua", "lunar.lua", "words.lua", "quotes.lua", "version.lua", "schedule.lua", "battery.lua", "clocktext.lua", "light.lua", "sleep.lua", "batterylog.lua", "charge.lua", "charge-watchdog.txt", "CHARGE-LICENSE.txt", "updater.lua", "updateui.lua", "NOTICE.txt"}
local function validVersion(v)
    return type(v) == "string" and #v <= 32 and v:match("^%d+%.%d+%.%d+$") ~= nil
end
M.validVersion = validVersion
local function parts(v)
    if not validVersion(v) then error("Phiên bản không hợp lệ") end
    local a,b,c = v:match("^(%d+)%.(%d+)%.(%d+)$")
    return {tonumber(a),tonumber(b),tonumber(c)}
end
function M.newer(a,b)
    local av,bv = parts(a),parts(b)
    for i=1,3 do if av[i] ~= bv[i] then return av[i] > bv[i] end end
    return false
end
function M.validate(m)
    if type(m) ~= "table" or m.schema ~= 1 or not validVersion(m.version)
       or type(m.revision) ~= "string" or #m.revision ~= 40 or not m.revision:match("^[a-f0-9]+$")
       or type(m.files) ~= "table" or #m.files < #REQUIRED or #m.files > 64 then
        error("Thông tin bản cập nhật không hợp lệ")
    end
    local seen,total = {},0
    for _, f in ipairs(m.files) do
        if type(f) ~= "table" or type(f.name) ~= "string" or #f.name > 80
           or not f.name:match("^[a-zA-Z0-9_%-]+%.[a-zA-Z0-9]+$")
           or not (f.name:match("%.lua$") or f.name:match("%.txt$") or f.name:match("%.md$"))
           or seen[f.name] or type(f.size) ~= "number" or f.size % 1 ~= 0 or f.size <= 0 or f.size > M.max_file
           or type(f.sha256) ~= "string" or #f.sha256 ~= 64 or not f.sha256:match("^[a-f0-9]+$") then
            error("Danh sách tệp không hợp lệ")
        end
        seen[f.name],total = true,total + f.size
    end
    if total > M.max_total then error("Bản cập nhật quá lớn") end
    for _, name in ipairs(REQUIRED) do if not seen[name] then error("Thiếu tệp " .. name) end end
    return m
end

-- HTTPS is handled by KOReader's patched LuaSec, with certificate AND hostname
-- verification. Refuse old/unpatched clients rather than disabling verification.
function M.fetch(url, limit)
    local prefix = "https://raw.githubusercontent.com/" .. M.repository .. "/"
    if url:sub(1,#prefix) ~= prefix then error("Nguồn tải không được phép") end
    local ssl = require("ssl")
    if type(ssl.checkhostname) ~= "function" then error("Cần KOReader có kiểm tra chứng chỉ HTTPS") end
    local cafile
    for _, path in ipairs({"data/ca-bundle.crt", "/etc/ssl/certs/ca-certificates.crt"}) do
        local f = io.open(path,"rb")
        if f then f:close(); cafile = path; break end
    end
    if not cafile then error("Không tìm thấy chứng chỉ CA của KOReader") end
    local https = require("ssl.https")
    local socketutil = require("socketutil")
    local oldb,oldt = socketutil.block_timeout,socketutil.total_timeout
    socketutil:set_timeout(10,45)
    local chunks, bytes, start = {},0,os.time()
    local ok, result, code = pcall(https.request, {
        url=url, method="GET", redirect=false, verify="peer", cafile=cafile,
        headers={ ["user-agent"]="KindleDeskCalendar/1.1", ["accept"]="application/json, text/plain" },
        sink=function(chunk)
            if chunk then
                bytes = bytes + #chunk
                if bytes > limit or os.time()-start > 45 then return nil,"Download limit" end
                chunks[#chunks+1] = chunk
            end
            return 1
        end,
    })
    socketutil:set_timeout(oldb,oldt)
    if not ok or not result or tonumber(code) ~= 200 then
        error("Không tải được bản cập nhật (" .. tostring(code or result) .. "). Kiểm tra Wi-Fi và ngày giờ máy.")
    end
    return table.concat(chunks)
end
function M.check(current, fetch, decode)
    local data = (fetch or M.fetch)("https://raw.githubusercontent.com/" .. M.repository .. "/main/update.json", 32768)
    local m = M.validate((decode or require("json").decode)(data))
    return M.newer(m.version,current) and m or nil
end
local function read(path, limit)
    local f=io.open(path,"rb")
    if not f then return nil end
    local s=f:read(limit or M.max_file+1); f:close(); return s
end
local function write(path, data)
    local f,err=io.open(path,"wb"); if not f then error(err) end
    local ok,e=f:write(data); local closed,ce=f:close()
    if not ok or not closed then error(e or ce or "Không ghi được tệp") end
end
local function mkdir(path)
    local lfs=require("libs/libkoreader-lfs")
    local attr=lfs.attributes(path)
    if attr then if attr.mode ~= "directory" then error("Đường dẫn bị chặn") end; return end
    assert(lfs.mkdir(path))
end
local function atomicPointer(root,name,value)
    if not validVersion(value) then error("Con trỏ phiên bản không hợp lệ") end
    write(root .. name .. ".tmp",value .. "\n")
    -- rename over an existing file is atomic on the Kindle's Linux filesystem.
    assert(os.rename(root .. name .. ".tmp",root .. name))
end
local function pointer(root,name)
    local s=read(root .. name,64)
    s=s and s:match("^%s*(.-)%s*$")
    return validVersion(s) and s or nil
end
function M.stage(root,m,fetch,sha)
    M.validate(m)
    fetch,sha=fetch or M.fetch,sha or require("ffi/sha2").sha256
    mkdir(root .. "releases")
    local dir=root .. "releases/" .. m.version .. "/"
    mkdir(dir:sub(1,-2))
    local staged={}
    -- This directory is never executed until ALL files pass validation.
    if pointer(root,"active.txt") == m.version or pointer(root,"previous.txt") == m.version then
        error("Không ghi đè bản đang dùng hoặc bản dự phòng")
    end
    for _,f in ipairs(m.files) do
        local data=fetch("https://raw.githubusercontent.com/" .. M.repository .. "/" .. m.revision .. "/deskcalendar.koplugin/releases/" .. m.version .. "/" .. f.name, f.size)
        if #data ~= f.size or sha(data) ~= f.sha256 then error("Tệp tải chưa đúng: " .. f.name) end
        if f.name:match("%.lua$") then
            local compiled,err=loadstring(data,"@" .. f.name)
            if not compiled then error("Mã Lua không hợp lệ: " .. tostring(err)) end
        end
        write(dir .. f.name,data)
        staged[f.name]=data
    end
    -- version.lua is validated as plain data, not executed.
    if not staged["version.lua"]:match('^%s*return%s+"' .. m.version:gsub("%.","%%.") .. '"%s*$') then
        error("Phiên bản trong gói không khớp")
    end
    write(dir .. "verified.txt",m.version .. "\n")
    return m.version
end
function M.activate(root,version,current)
    if not validVersion(version) or not validVersion(current) then error("Phiên bản không hợp lệ") end
    if read(root .. "releases/" .. version .. "/verified.txt",64) ~= version .. "\n" then error("Bản mới chưa được kiểm tra") end
    atomicPointer(root,"previous.txt",current)
    atomicPointer(root,"active.txt",version)
end
function M.rollback(root)
    local previous=pointer(root,"previous.txt")
    if not previous then error("Chưa có bản trước để khôi phục") end
    if not read(root .. "releases/" .. previous .. "/main.lua") then error("Thiếu bản dự phòng") end
    atomicPointer(root,"active.txt",previous)
    return previous
end
return M
