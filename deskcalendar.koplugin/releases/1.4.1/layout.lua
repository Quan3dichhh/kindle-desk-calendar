-- Shared native layout. Coordinates scale from the approved 1448 x 1072 design.
-- makeText returns a measured {widget,w,h,...} item that fits its bounds.
local M = {}
local function round(n) return math.floor(n + 0.5) end

function M.build(w, h, model, makeText, theme)
    local sx, sy = w / 1448, h / 1072
    local s = math.min(sx, sy)
    local stacked = theme == "stacked" and model.display_mode ~= "calendar"
    local scene = {items = {}, lines = {}, circles = {}}
    local function measure(value, size, bold, maxw, maxh, serif)
        return makeText(tostring(value), size * s, bold or false, maxw, maxh, serif)
    end
    local function put(item, x, y, align, middle)
        item.x = round(x - (align == "center" and item.w / 2 or align == "right" and item.w or 0))
        item.y = round(y - (middle and item.h / 2 or 0))
        scene.items[#scene.items + 1] = item
        return item
    end
    local function text(value, size, bold, x, y, align, maxw, maxh, middle, serif)
        return put(measure(value, size, bold, maxw or w, maxh or h, serif), x, y, align, middle)
    end
    local function line(x1, y1, x2, y2, gray, thickness)
        scene.lines[#scene.lines + 1] = {
            x = round(x1 * sx), y = round(y1 * sy),
            w = math.max(round((x2 - x1) * sx), round((thickness or 2) * s), 1),
            h = math.max(round((y2 - y1) * sy), round((thickness or 2) * s), 1), gray = gray or 0,
        }
    end
    line(790, stacked and 440 or 54, 790, 776, 0, 2)
    if stacked then line(54, 426, 1394, 426, 225, 2) end
    line(54, 805, 1394, 805, 0, 3)

    if model.display_mode ~= "calendar" then
    local period = measure(model.period, stacked and 34 or 30, false, 100 * sx, 50 * sy)
    local clock
    if stacked then
        clock = makeText(model.time, 900 * s, true, 1340 * sx - period.w - 30 * sx, 350 * sy, false, true)
    else
        clock = measure(model.time, 330, true, 706 * sx - period.w - 12 * sx, 360 * sy)
    end
    local clockX = stacked and ((54 + 1394) * sx - period.w - 30 * sx - clock.w) / 2
        or 422 * sx - (clock.w + 12 * sx + period.w) / 2
    local clockY = (stacked and 234 or 276) * sy - clock.h / 2
    if model.display_mode == "five" then
        -- Same native face, with the minute part at 2/3 of the hour font size.
        local hour = makeText(model.time:match("^(%d+):"), clock.px, true, clock.w, clock.h, false, true)
        local minute = makeText(model.time:match("(:%d+)$"), clock.px * 2/3, true, clock.w, math.floor(clock.h*2/3), false, true)
        local total = hour.w + minute.w + 12*sx
        clockX = stacked and ((54+1394)*sx-period.w-30*sx-total)/2
            or 422*sx-(total+12*sx+period.w)/2
        put(hour, clockX, clockY + clock.h - hour.h)
        put(minute, clockX+hour.w+12*sx, clockY+clock.h-minute.h)
        scene.clock_parts = {hour=hour, minute=minute}
        clock.widget:free()
        clock.w = total
    else
        put(clock, clockX, clockY)
    end
    if stacked then
        put(period, 1394 * sx, 234 * sy, "right", true)
    else
        put(period, clockX + clock.w + 12 * sx, clockY + clock.h * 0.20)
    end
    scene.clock_rect = {x = round(50 * sx), y = round((stacked and 55 or 60) * sy),
        w = round((stacked and 1348 or 734) * sx), h = round((stacked and 365 or 410) * sy)}

    end -- clock is hidden in calendar-only mode
    scene.clock_rect = scene.clock_rect or {x=round(50*sx),y=round(60*sy),w=round(734*sx),h=round(705*sy)}
    scene.status_rect = {x = round(50 * sx), y = round(12 * sy), w = round((stacked and 1348 or 734) * sx), h = round(46 * sy)}
    if model.battery then
        text(model.battery.text, 23, false, (stacked and 1394 or 750) * sx, 20 * sy, "right", 696 * sx, 33 * sy)
    end

    local calendar_only = model.display_mode == "calendar"
    local solarY = calendar_only and 360 or 585
    local day = measure(model.day, calendar_only and 260 or stacked and 152 or 128, true, 330 * sx, (calendar_only and 330 or 180) * sy, true)
    local weekday = measure(model.weekday, 40, true, 350 * sx, 60 * sy)
    local month = measure(model.month_label, 31, false, 350 * sx, 48 * sy)
    local infoW = math.max(weekday.w, month.w)
    local solarX = 422 * sx - (day.w + 34 * sx + infoW) / 2
    put(day, solarX, solarY * sy, nil, true)
    local infoY = solarY * sy - (weekday.h + 10 * sy + month.h) / 2
    put(weekday, solarX + day.w + 34 * sx, infoY)
    put(month, solarX + day.w + 34 * sx, infoY + weekday.h + 10 * sy)
    text(model.lunar_label, 30, false, 422 * sx, (calendar_only and 600 or 708) * sy, "center", 706 * sx, 45 * sy, true)
    text(model.lunar_year, 28, false, 422 * sx, (calendar_only and 654 or 754) * sy, "center", 706 * sx, 42 * sy, true)
    if model.browsing then
        text("XEM NGAY · CHẠM ĐỂ VỀ HÔM NAY", 22, false,
            (stacked and 54 or 422) * sx, (stacked and 20 or 60) * sy,
            stacked and "left" or "center", 700 * sx, 35 * sy)
    end

    text("THÁNG " .. model.month, stacked and 35 or 44, true, 836 * sx,
        (stacked and 440 or 88) * sy, nil, 390 * sx, (stacked and 45 or 65) * sy)
    text(model.year, stacked and 28 or 33, false, 1394 * sx,
        (stacked and 446 or 100) * sy, "right", 180 * sx, 50 * sy)
    local cellW = (1394 - 836) / 7
    local headerY, headerH, rowH = stacked and 486 or 173, stacked and 40 or 75, stacked and 41 or 88
    local rowsY, gridBottom = headerY + headerH, headerY + headerH + rowH * 6
    for i = 0, 7 do line(836 + cellW * i, headerY, 836 + cellW * i, gridBottom, 207, 2) end
    line(836, headerY, 1394, headerY, 207, 2)
    for row = 0, 6 do line(836, rowsY + rowH * row, 1394, rowsY + rowH * row, 207, 2) end
    for i, label in ipairs({"T2", "T3", "T4", "T5", "T6", "T7", "CN"}) do
        text(label, stacked and 22 or 26, false, (836 + cellW * (i - 0.5)) * sx,
            (headerY + headerH / 2) * sy, "center", cellW * sx - 8 * sx, (stacked and 34 or 45) * sy, true)
    end
    for _, cell in ipairs(model.cells) do
        local cx, cy = (836 + cellW * (cell.column + 0.5)) * sx, (rowsY + rowH * (cell.row + 0.5)) * sy
        if cell.day == model.day then
            scene.circles[#scene.circles + 1] = {x = round(cx), y = round(cy), r = round((stacked and 18 or 32) * s), thickness = math.max(1, round(2 * s))}
        end
        text(cell.day, stacked and 27 or 36, cell.column == 6, cx, cy, "center", cellW * sx - 8 * sx,
            (stacked and 36 or 60) * sy, true)
    end

    text(model.content_label, 25, false, 54 * sx, 842 * sy, nil, 1340 * sx, 40 * sy)
    local content = model.content
    if content.kind == "word" then
        local word, ipa, meaning
        local factor = 1
        for attempt = 1, 9 do
            word = measure(content.word, 58 * factor, true, 1340 * sx, 82 * sy)
            ipa = measure(content.ipa, 35 * factor, false, 1340 * sx, 60 * sy)
            meaning = measure(content.meaning, 36 * factor, false, 1340 * sx, 60 * sy)
            if word.w + ipa.w + meaning.w + 56 * sx <= 1340 * sx then break end
            if word.widget then word.widget:free(); ipa.widget:free(); meaning.widget:free() end
            factor = factor * 0.9
        end
        local wordX = 54 * sx
        put(word, wordX, 945 * sy, nil, true)
        put(ipa, wordX + word.w + 28 * sx, 950 * sy, nil, true)
        put(meaning, wordX + word.w + ipa.w + 56 * sx, 950 * sy, nil, true)
        text(content.example, 37, false, 54 * sx, 1018 * sy, nil, 1340 * sx, 60 * sy, true, true)
    else
        text(content.quote, 52, false, 54 * sx, 958 * sy, nil, 1340 * sx, 135 * sy, true, true)
    end
    return scene
end

return M
