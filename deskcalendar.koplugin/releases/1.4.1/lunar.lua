-- Vietnamese lunar conversion, timezone UTC+7.
-- Lua adaptation of Ho Ngoc Duc's astronomical calendar algorithm (2006),
-- based on Jean Meeus, Astronomical Algorithms (1998). See NOTICE.txt.
local M = {}
local floor, sin, pi = math.floor, math.sin, math.pi
local rad = pi / 180

function M.jdn(day, month, year)
    local a = floor((14 - month) / 12)
    local y, m = year + 4800 - a, month + 12 * a - 3
    return day + floor((153 * m + 2) / 5) + 365 * y + floor(y / 4)
        - floor(y / 100) + floor(y / 400) - 32045
end

function M.fromJdn(jd)
    local a = jd + 32044
    local b = floor((4 * a + 3) / 146097)
    local c = a - floor(146097 * b / 4)
    local d = floor((4 * c + 3) / 1461)
    local e = c - floor(1461 * d / 4)
    local m = floor((5 * e + 2) / 153)
    return e - floor((153 * m + 2) / 5) + 1,
        m + 3 - 12 * floor(m / 10), b * 100 + d - 4800 + floor(m / 10)
end

local function moonDay(k, tz)
    local t = k / 1236.85
    local t2, t3 = t * t, t * t * t
    local jd = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3
    jd = jd + 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * rad)
    local sun = (359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3) * rad
    local moon = (306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3) * rad
    local f = (21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3) * rad
    local correction = (0.1734 - 0.000393 * t) * sin(sun) + 0.0021 * sin(2 * sun)
        - 0.4068 * sin(moon) + 0.0161 * sin(2 * moon) - 0.0004 * sin(3 * moon)
        + 0.0104 * sin(2 * f) - 0.0051 * sin(sun + moon) - 0.0074 * sin(sun - moon)
        + 0.0004 * sin(2 * f + sun) - 0.0004 * sin(2 * f - sun)
        - 0.0006 * sin(2 * f + moon) + 0.0010 * sin(2 * f - moon)
        + 0.0005 * sin(2 * moon + sun)
    local delta
    if t < -11 then
        delta = 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
    else
        delta = -0.000278 + 0.000265 * t + 0.000262 * t2
    end
    return floor(jd + correction - delta + 0.5 + tz / 24)
end

local function sunSector(jd, tz)
    local t = (jd - 2451545.5 - tz / 24) / 36525
    local t2 = t * t
    local anomaly = (357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2) * rad
    local mean = 280.46645 + 36000.76983 * t + 0.0003032 * t2
    local delta = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(anomaly)
        + (0.019993 - 0.000101 * t) * sin(2 * anomaly) + 0.000290 * sin(3 * anomaly)
    local longitude = ((mean + delta) * rad) % (2 * pi)
    return floor(longitude / pi * 6)
end

local month11_cache = {}
local function month11(year, tz)
    local key = year .. ":" .. tz
    if month11_cache[key] then return month11_cache[key] end
    local k = floor((M.jdn(31, 12, year) - 2415021) / 29.530588853)
    local nm = moonDay(k, tz)
    if sunSector(nm, tz) >= 9 then nm = moonDay(k - 1, tz) end
    month11_cache[key] = nm
    return nm
end

local function leapOffset(a11, tz)
    local k = floor((a11 - 2415021.076998695) / 29.530588853 + 0.5)
    local i, last = 1, -1
    local sector = sunSector(moonDay(k + i, tz), tz)
    repeat
        last, i = sector, i + 1
        sector = sunSector(moonDay(k + i, tz), tz)
    until sector == last or i >= 14
    return i - 1
end

function M.convert(day, month, year, tz)
    tz = tz or 7
    local jd = M.jdn(day, month, year)
    local k = floor((jd - 2415021.076998695) / 29.530588853)
    local start = moonDay(k + 1, tz)
    if start > jd then start = moonDay(k, tz) end
    local a11, b11 = month11(year, tz), month11(year, tz)
    local lunarYear
    if a11 >= start then
        lunarYear, a11 = year, month11(year - 1, tz)
    else
        lunarYear, b11 = year + 1, month11(year + 1, tz)
    end
    local diff = floor((start - a11) / 29)
    local lunarMonth, leap = diff + 11, false
    if b11 - a11 > 365 then
        local leapDiff = leapOffset(a11, tz)
        if diff >= leapDiff then lunarMonth = diff + 10; leap = diff == leapDiff end
    end
    if lunarMonth > 12 then lunarMonth = lunarMonth - 12 end
    if lunarMonth >= 11 and diff < 4 then lunarYear = lunarYear - 1 end
    return {day = jd - start + 1, month = lunarMonth, year = lunarYear, leap = leap}
end

return M
