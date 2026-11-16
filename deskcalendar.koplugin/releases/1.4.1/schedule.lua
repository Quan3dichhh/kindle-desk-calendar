-- Vietnam local wall clock, independent of the Kindle's system timezone.
local M = {}
function M.localTime(epoch)
    return os.date("!*t", epoch + 7 * 3600)
end
function M.isNight(epoch)
    local t = M.localTime(epoch)
    return t.hour >= 23 or t.hour < 6
end
function M.mode(epoch, weekend_fast, boost_until)
    if boost_until and epoch < boost_until then return "minute" end
    local t = M.localTime(epoch)
    if t.hour >= 23 or t.hour < 6 then return "calendar" end
    if t.hour >= 19 then return "minute" end
    if weekend_fast and (t.wday == 1 or t.wday == 7) then return "minute" end
    return "five"
end
function M.nextEpoch(epoch, weekend_fast, boost_until, hourly_log)
    local mode = M.mode(epoch, weekend_fast, boost_until)
    local due
    if mode == "calendar" then
        local local_epoch = epoch + 7 * 3600
        local day_start = local_epoch - local_epoch % 86400 - 7 * 3600
        local hour = M.localTime(epoch).hour
        -- Midnight changes the date; 06:00 restores the clock.
        due = hour >= 23 and day_start + 86400 or day_start + 6 * 3600
    else
        local interval = mode == "five" and 300 or 60
        due = math.floor(epoch / interval) * interval + interval
    end
    if hourly_log then due = math.min(due, math.floor(epoch/3600)*3600+3600) end
    if boost_until and boost_until > epoch then due = math.min(due, boost_until) end
    return due
end
function M.delay(epoch, weekend_fast, boost_until, hourly_log)
    return math.max(0.15, M.nextEpoch(epoch, weekend_fast, boost_until, hourly_log) - epoch + 0.15)
end
return M
