local M = {}
local function message(text)
    require("ui/uimanager"):show(require("ui/widget/infomessage"):new{text=text})
end
local function updater(dir) return dofile(dir .. "updater.lua") end
local function task(trapper, fn, text)
    local completed,result=trapper:dismissableRunInSubprocess(function()
        local ok,value=pcall(fn)
        return {ok=ok,value=ok and value or tostring(value)}
    end,text)
    if not completed then return nil end
    if type(result) ~= "table" or not result.ok then
        message("Cập nhật chưa hoàn tất. Bản đang dùng được giữ lại.\n\n" .. tostring(type(result)=="table" and result.value or "Không nhận được kết quả"))
        return nil
    end
    return result
end
function M.check(root,dir,current)
    require("ui/network/manager"):runWhenConnected(function()
        local Trapper=require("ui/trapper")
        Trapper:wrap(function()
            local Updater=updater(dir)
            local result=task(Trapper,function() return Updater.check(current) end,"Đang kiểm tra bản cập nhật…\nChạm để hủy.")
            if not result then return end
            local manifest=result.value
            if not manifest then message("Bạn đang dùng bản mới nhất: " .. current); return end
            if not Trapper:confirm("Cập nhật Lịch bàn " .. current .. " → " .. manifest.version .. "?\nGiữ lại bản cũ để khôi phục.","Để sau","Tải và cài") then return end
            local staged=task(Trapper,function() return Updater.stage(root,manifest) end,"Đang tải và kiểm tra bản cập nhật…\nChạm để hủy.")
            if not staged then return end
            -- Activation is deliberately done in the parent, after cancellation
            -- can no longer interrupt the two small pointer writes.
            local ok,err=pcall(Updater.activate,root,staged.value,current)
            if not ok then message("Chưa kích hoạt bản mới:\n" .. tostring(err)); return end
            message("Đã cài bản " .. staged.value .. ".\nThoát rồi mở lại KOReader để sử dụng.\nCó thể chọn “Khôi phục bản trước” nếu cần.")
        end)
    end)
end
function M.rollback(root,dir)
    local ok,version=pcall(updater(dir).rollback,root)
    if ok then message("Đã chọn lại bản " .. version .. ".\nThoát rồi mở lại KOReader để áp dụng.")
    else message(tostring(version)) end
end
return M
