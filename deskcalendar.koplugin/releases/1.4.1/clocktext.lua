-- ASCII clock only: fit the visible digit ink, not the font's line spacing.
-- Render with KOReader's glyph engine at native resolution (no bitmap stretch).
local M = {}
function M.make(value, maxw, maxh, screen, font, preferred_size)
    assert(type(value) == "string" and value:match("^[0-9:]+$"))
    local RenderText = require("ui/rendertext")
    local Blitbuffer = require("ffi/blitbuffer")
    local scale = screen:scaleBySize(100) / 100
    local target = math.ceil(math.min(preferred_size or maxh * 2, maxh * 2))
    for attempt = 1, 20 do
        local face = assert(font:getFace("cfont", target / scale))
        local bold
        face, bold = font:getAdjustedFace(face, true)
        local pen, left, right, top, bottom, previous = 0, 0, 0, 0, 0, nil
        for i = 1, #value do
            local code = value:byte(i)
            if previous then pen = pen + face.ftsize:getKerning(previous, code) end
            local glyph = assert(RenderText:getGlyph(face, code, bold))
            left = math.min(left, pen + glyph.l)
            right = math.max(right, pen + glyph.l + glyph.bb:getWidth())
            top = math.max(top, glyph.t)
            bottom = math.max(bottom, glyph.bb:getHeight() - glyph.t)
            pen, previous = pen + glyph.ax, code
        end
        local w, h = math.ceil(right - left) + 2, math.ceil(top + bottom) + 2
        if w <= maxw and h <= maxh then
            local widget = {}
            function widget:paintTo(bb, x, y)
                RenderText:renderUtf8Text(bb, x - left + 1, y + top + 1,
                    face, value, true, bold, Blitbuffer.COLOR_BLACK)
            end
            function widget:free() end -- glyph cache owns glyph bitmaps
            return {widget=widget, w=w, h=h, text=value, px=target, bold=true, tight=true}
        end
        local next_target = math.floor(target * math.min(maxw / w, maxh / h) * 0.995)
        target = math.max(6, math.min(target - 1, next_target))
    end
    error("Cannot fit clock digits")
end
return M
