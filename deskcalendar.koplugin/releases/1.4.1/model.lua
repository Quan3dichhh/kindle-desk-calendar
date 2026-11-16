local dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "plugins/deskcalendar.koplugin/"
local Lunar = dofile(dir .. "lunar.lua")
local Words = dofile(dir .. "words.lua")
local Quotes = dofile(dir .. "quotes.lua")
local M = {lunar = Lunar, words = Words, quotes = Quotes}
local weekdays = {"CHỦ NHẬT", "THỨ HAI", "THỨ BA", "THỨ TƯ", "THỨ NĂM", "THỨ SÁU", "THỨ BẢY"}
local stems = {"Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"}
local branches = {"Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi"}
local months = {"Giêng", "Hai", "Ba", "Tư", "Năm", "Sáu", "Bảy", "Tám", "Chín", "Mười", "Mười Một", "Chạp"}

function M.daysInMonth(month, year)
    local ny, nm = year, month + 1
    if nm == 13 then ny, nm = ny + 1, 1 end
    return Lunar.jdn(1, nm, ny) - Lunar.jdn(1, month, year)
end

function M.monthCells(month, year)
    local cells = {}
    local first = Lunar.jdn(1, month, year) % 7 -- Monday=0
    for day = 1, M.daysInMonth(month, year) do
        local slot = first + day - 1
        cells[#cells + 1] = {day = day, row = math.floor(slot / 7), column = slot % 7}
    end
    return cells
end

function M.get(epoch, offset, mode, contentStep)
    local now = os.date("!*t", epoch + 7 * 3600)
    local today = Lunar.jdn(now.day, now.month, now.year)
    local day, month, year = Lunar.fromJdn(today + (offset or 0))
    local moon = Lunar.convert(day, month, year, 7)
    local lunarDay = moon.day <= 10 and ("mùng " .. moon.day) or tostring(moon.day)
    local hourKey = math.floor((epoch + 7 * 3600) / 3600)
    local step = contentStep or 0
    local contentHour = hourKey + step
    local isQuote = mode == "quotes" or (mode ~= "words" and contentHour % 2 == 1)
    local item
    if isQuote then
        local index = (mode == "quotes" and contentHour or math.floor(contentHour / 2)) % #Quotes + 1
        item = {kind = "quote", quote = Quotes[index]}
    else
        local index = (mode == "words" and contentHour or math.floor(contentHour / 2)) % #Words + 1
        local w = Words[index]
        item = {kind = "word", word = w[1], ipa = w[2], meaning = w[3], example = w[4]}
    end
    local hour12 = now.hour % 12
    if hour12 == 0 then hour12 = 12 end
    return {
        time = string.format("%d:%02d", hour12, now.min), period = now.hour < 12 and "AM" or "PM",
        hour = now.hour, minute = now.min, hour_key = hourKey, today_jd = today, selected_jd = today + (offset or 0),
        day = day, month = month, year = year, weekday = weekdays[((today + (offset or 0) + 1) % 7) + 1],
        month_label = string.format("THÁNG %d · %d", month, year),
        lunar_label = "Âm lịch: " .. lunarDay .. " tháng " .. months[moon.month] .. (moon.leap and " nhuận" or ""),
        lunar_year = "Năm " .. stems[(moon.year + 6) % 10 + 1] .. " " .. branches[(moon.year + 8) % 12 + 1],
        cells = M.monthCells(month, year), lunar = moon, content = item,
        content_label = (isQuote and "CHÂM NGÔN" or "TỪ VỰNG") .. string.format(" · %02d:00–%02d:00", now.hour, (now.hour + 1) % 24),
        browsing = offset and offset ~= 0,
    }
end

return M
