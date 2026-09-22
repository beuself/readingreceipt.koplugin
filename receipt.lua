if rawget(_G, "__readingreceipt_receipt_module_loaded") then
    return
end
_G.__readingreceipt_receipt_module_loaded = true

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DocSettings = require("docsettings")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local function pluginRoot()
    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*[/\\])") or "./"
end

local ICON_DIR = pluginRoot() .. "icons/"

-- 安全加载 bit 库
local ok_bit, bit = pcall(require, "bit")
if not ok_bit then
    ok_bit, bit = pcall(require, "bit32")
    if not ok_bit then
        bit = nil
        logger.warn("read-receipt: bit library not found, using fallback")
    end
end

-- ---------------------------------------------------------------- geometry --
local BASE_W, BASE_H = 851.38, 1506.06
local current_scale = 1

local R = 35
local NOTCH_Y = 967.85
local NOTCH_DX = 3
local SCALLOPS = 8

local K_CN, K_LA = 0.792, 0.7625

local COL = {
    K  = Blitbuffer.COLOR_BLACK,
    COVER = Blitbuffer.Color8(0x91),
    TRACK = Blitbuffer.Color8(0xC7),
    FILL = Blitbuffer.Color8(0x4C),
}

local BARS = {{38.3,2.15},{47.9,5.75},{55.6,3.8},{61.35,1.9},{69,1.95},{74.8,7.65},{86.3,1.9},{90.15,7.65},{101.65,1.95},{107.4,1.95},{111.25,1.95},{120.85,3.85},{126.6,1.95},{132.15,3.85},{143.65,1.95},{147.5,1.9},{153.25,3.85},{159,3.85},{166.7,3.85},{174.4,5.75},{182.05,1.95},{189.75,3.85},{195.5,1.9},{203.2,7.65},{212.8,1.9},{216.6,3.85},{227.9,1.9},{231.75,1.9},{237.5,1.9},{243.25,3.85},{249,1.95},{258.6,3.85},{264.4,3.8},{272.05,3.85},{279.75,7.65},{289.35,5.75},{297,1.95},{300.85,1.95},{306.6,1.95},{310.45,3.6},{321.75,1.9},{331.35,1.9},{337.1,3.85},{342.85,1.95},{346.7,3.85},{354.4,1.9},{364,3.8},{369.75,3.85},{377.4,3.85},{385.1,1.9},{394.7,3.85},{400.2,1.95},{406,1.9},{411.75,7.65},{421.35,1.9},{427.1,3.85},{432.85,3.85},{440.55,3.85},{448.2,1.95},{455.9,7.7},{465.5,1.9},{469.35,3.85},{480.85,1.95},{484.7,1.9},{490.2,3.85},{496,3.8},{503.65,3.85},{511.35,1.9},{515.2,1.9},{522.85,3.85},{532.45,1.95},{538.2,7.7},{549.75,1.9},{553.6,1.9},{559.35,3.85},{565.1,1.9},{574.7,3.6},{580.2,3.85},{587.9,3.85},{595.6,3.8},{603.25,5.75},{612.85,1.95},{616.7,5.75},{624.4,1.9},{630.15,3.85},{637.8,3.85},{643.6,3.8},{651.25,3.85},{658.95,1.9},{662.8,5.5},{670.2,7.7},{679.8,3.85},{687.5,1.9},{693.25,5.75},{700.95,5.75},{710.55,1.9},{716.3,3.85},{722.05,5.75},{729.75,1.9},{733.6,7.65},{743.2,1.9},{752.8,3.8},{760.2,1.95},{764.05,1.95},{769.8,1.95},{773.65,7.7},{785.2,3.8},{794.8,5.75},{802.45,1.95},{806.3,3.85}}
local BARCODE_Y, BARCODE_H = 1307.3, 47.8

-- 星级评分配置
local STAR_COUNT = 5
local STAR_SIZE = 50
local STAR_GAP = 2
local STAR_X = 36.92
local STAR_TOP = 631.18
local RATING_TEXT_GAP = 8
local RATING_TEXT_SIZE = 30
local RATING_LABELS = { "很差", "较差", "一般", "还好", "完美" }
local RATING_DEFAULT_TEXT = "点评"
local STAR_TOUCH_EXPAND = 20
local MIN_STAR_SIZE = 8

local function normalizeRating(rating)
    local r = tonumber(rating) or 0
    if r <= 0 then return 0 end
    r = math.floor(r * 2 + 0.0001) / 2
    if r > STAR_COUNT then r = STAR_COUNT end
    return r
end

local function ratingLabelText(rating)
    if rating <= 0 then return RATING_DEFAULT_TEXT end
    local idx = math.min(#RATING_LABELS, math.max(1, math.ceil(rating - 0.001)))
    return RATING_LABELS[idx]
end

local function starIconKind(rating, index)
    if rating >= index then
        return "full"
    elseif rating >= index - 0.5 then
        return "half"
    end
    return "empty"
end

local function ratingFromTapX(tx)
    local offset_x_inner = tx - STAR_X
    if offset_x_inner < 0 then
        return 0
    end

    local slot_w = STAR_SIZE + STAR_GAP
    local slot_idx = math.floor(offset_x_inner / slot_w) + 1
    if slot_idx > STAR_COUNT then
        return STAR_COUNT
    end

    local in_slot = offset_x_inner - (slot_idx - 1) * slot_w
    if in_slot <= STAR_SIZE / 2 then
        return slot_idx - 0.5
    end
    return slot_idx
end

-- 文字排版数据
local ITEMS = {
  {x=759.55,top=132.58,f="C",size=22,ls=1.16,c="K",t="状态"},
  {x=599.56,top=173.7,f="C",size=104,ls=7.67,c="K",t="在读",key="status"},
  {x=0,top=66.64,f="L",size=25,ls=-0.1,c="K",t="NO. D20260906",key="no",no_align=true},
  {x=35.04,top=89.3,f="C",size=25,ls=-1.25,c="K",t="阅读日票"},
  {x=34.12,top=136,f="C",size=72,ls=0.03,c="K",t="READ RECEIPT"},
  {x=34.36,top=232.58,f="C",size=25,ls=-0.78,c="K",t="今日阅读轨迹"},
  {x=193,top=232.92,f="L",size=25,ls=0,c="K",t="/"},
  {x=214.52,top=232.2,f="L",size=25,ls=-0.73,c="K",t="TODAY"},
  {x=287.64,top=236.2,f="L",size=25,ls=0,c="K",t="’"},
  {x=304.32,top=232.68,f="L",size=25,ls=0,c="K",t="S"},
  {x=321.6,top=232.2,f="L",size=25,ls=-0.26,c="K",t="READING"},
  {x=434.64,top=232.2,f="L",size=25,ls=-0.42,c="K",t="TRAIL"},
  {x=70.08, top=346.35, f="C", size=20, ls=0.07, c="K", t="开始日期"},
  {x=0,    top=340,   f="L", size=32,   ls=0,    c="K", t="·", dot_center=true},
  {x=169.37,top=346.24, f="L", size=20, ls=-0.2, c="K", t="DATE"},
  {x=319.24,top=344.75,f="C",size=20,ls=-0.12,c="K",t="今日星期"},
  {x=0,top=340,f="L",size=32,ls=0,c="K",t="·",dot_center=true},
  {x=418.24,top=346.24,f="L",size=20,ls=-0.51,c="K",t="DAY"},
  {x=583,top=344.51,f="C",size=20,ls=0.47,c="K",t="当天日期"},
  {x=0,top=340,f="L",size=32,ls=0,c="K",t="·",dot_center=true},
  {x=683.41,top=346.24,f="L",size=20,ls=0.18,c="K",t="DATE"},
  {x=70.08,top=371.53,f="L",size=36,ls=-0.61,c="K",key="start_date"},
  {x=317.76,top=371.13,f="C",size=34,ls=0.92,c="K",key="weekday_cn"},
  {x=397.4,top=371.37,f="C",size=34,ls=0,c="K",t="・"},
  {x=441.16,top=371.69,f="L",size=36,ls=-0.97,c="K",key="weekday_en"},
  {x=582.24,top=371.53,f="L",size=36,ls=-0.61,c="K",key="date"},
  {x=33.6,top=489.58,f="C",size=30,ls=0.49,c="K",t="当前阅读 READING"},
  {x=33.6,top=536.78,f="L",size=38,ls=-0.07,c="K",key="title",maxw=460},
  {x=33.6,top=583.98,f="L",size=30,ls=0.67,c="K",key="author",prefix="作者：",maxw=400},
  {x=33.6,top=716.58,f="C",size=30,ls=0.71,c="K",key="chapter",maxw=460},
  {x=33.6,top=763.78,f="C",size=30,ls=0.82,c="K",key="est_time",prefix="预计阅读时间：",maxw=500},
  {x=33.6,top=858.18,f="L",size=28,ls=-0.11,c="K",key="pages"},
  {x=148.72,top=857.52,f="C",size=28,ls=0,c="K",t="页",follow=10.8},
  {x=457.2,top=858.18,f="L",size=28,ls=-0.21,c="K",t="15%",key="pct", right_align=true},
  {x=39.12,top=1001.4,f="C",size=36,ls=-0.39,c="K",t="今日摘要"},
  {x=200.64,top=1001.78,f="L",size=36,ls=-0.2,c="K",t="SUMMARY"},
  {x=192,top=1077.44,f="C",size=28,ls=2.8,c="K",t="今日"},
  {x=604.12,top=1076.96,f="C",size=28,ls=0.52,c="K",t="总计"},
  {x=35.08,top=1115.83,f="L",size=26,ls=-0.08,c="K",t="PAGES READ"},
  {x=35.08,top=1147.87,f="C",size=26,ls=2.2,c="K",t="阅读页数"},
  {x=35.08,top=1202.29,f="L",size=40,ls=-0.35,c="K",key="d_pages"},
  {x=86.2,top=1200.61,f="C",size=40,ls=0,c="K",t="页",follow=2.3},
  {x=221.08,top=1115.83,f="L",size=26,ls=-0.02,c="K",t="READING TIME"},
  {x=221.08,top=1147.87,f="C",size=26,ls=2.29,c="K",t="阅读时长"},
  {x=221.08,top=1201.65,f="L",size=40,ls=0.32,c="K",key="d_time"},
  {x=444.52,top=1116.31,f="L",size=26,ls=-0.11,c="K",t="PAGES READ"},
  {x=444.52,top=1148.35,f="C",size=26,ls=2.12,c="K",t="阅读页数"},
  {x=444.52,top=1203.01,f="L",size=40,ls=-0.35,c="K",key="total_pages"},
  {x=495.4,top=1201.33,f="C",size=40,ls=0,c="K",t="页",follow=2.1},
  {x=634.36,top=1116.31,f="L",size=26,ls=-0.04,c="K",t="READING TIME"},
  {x=634.36,top=1148.35,f="C",size=26,ls=2.29,c="K",t="阅读时长"},
  {x=634.36,top=1202.37,f="L",size=40,ls=0.32,c="K",key="total_time"},
  {x=0,top=1396.2,f="C",size=20,ls=0.03,c="K",key="id",prefix="阅读记录 · READING LOG · ",maxw=600,center=true},
}

-- ------------------------------------------------------------- primitives --
local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local function px(v) return floor(v + 0.5) end

local function rect(bb, ox, oy, x, y, w, h, c)
    local s = current_scale
    w, h = px(w * s), px(h * s)
    if w < 1 then w = 1 end
    if h < 1 then h = 1 end
    bb:paintRect(ox + px(x * s), oy + px(y * s), w, h, c)
end

local function disc(bb, ox, oy, cx, cy, r, c)
    local s = current_scale
    local scaled_r = r * s
    for dy = -ceil(scaled_r), ceil(scaled_r) do
        local hw = scaled_r * scaled_r - dy * dy
        if hw > 0 then
            hw = sqrt(hw)
            rect(bb, ox, oy, cx - hw/s, cy + dy/s, hw*2/s, 1/s, c)
        end
    end
end

local function dottedH(bb, ox, oy, x1, x2, y, dot_radius, gap, offset, c)
    local s = current_scale
    local period = (dot_radius * 2 + gap) * s
    local t = x1 * s - (offset or 0) * s
    local x1_s = x1 * s
    local x2_s = x2 * s
    local y_s = y * s
    local dot_r_s = dot_radius * s
    while t < x2_s do
        local cx = t + dot_r_s
        if cx >= x1_s and cx <= x2_s then
            disc(bb, ox, oy, cx/s, y, dot_radius, c)
        end
        t = t + period
    end
end

local function scallopCentres()
    local t = {}
    for k = 0, SCALLOPS do t[#t + 1] = k * (BASE_W / SCALLOPS) end
    return t
end

local function subtract(spans, a, b)
    local out = {}
    for _, s in ipairs(spans) do
        if b <= s[1] or a >= s[2] then
            out[#out + 1] = s
        else
            if a > s[1] then out[#out + 1] = { s[1], a } end
            if b < s[2] then out[#out + 1] = { b, s[2] } end
        end
    end
    return out
end

local CX = scallopCentres()

local function rowSpans(y)
    local spans = { { 0, BASE_W } }
    if y < R then
        local hw = sqrt(R * R - y * y)
        for _, cx in ipairs(CX) do spans = subtract(spans, cx - hw, cx + hw) end
    end
    local dyb = BASE_H - y
    if dyb < R then
        local hw = sqrt(R * R - dyb * dyb)
        for _, cx in ipairs(CX) do spans = subtract(spans, cx - hw, cx + hw) end
    end
    local dn = abs(y - NOTCH_Y)
    if dn < R then
        local hw = sqrt(R * R - dn * dn)
        spans = subtract(spans, -1e6, -NOTCH_DX + hw)
        spans = subtract(spans, BASE_W + NOTCH_DX - hw, 1e6)
    end
    return spans
end

local function colSpans(x)
    local spans = { { 0, BASE_H } }
    for _, cx in ipairs(CX) do
        local dx = abs(x - cx)
        if dx < R then
            local hh = sqrt(R * R - dx * dx)
            spans = subtract(spans, -1e6, hh)
            spans = subtract(spans, BASE_H - hh, 1e6)
        end
    end
    if x < R - NOTCH_DX then
        local hh = sqrt(R * R - (x + NOTCH_DX) * (x + NOTCH_DX))
        spans = subtract(spans, NOTCH_Y - hh, NOTCH_Y + hh)
    end
    if x > BASE_W - R + NOTCH_DX then
        local d = BASE_W + NOTCH_DX - x
        local hh = sqrt(R * R - d * d)
        spans = subtract(spans, NOTCH_Y - hh, NOTCH_Y + hh)
    end
    return spans
end

-- 缓存每行/列的扫描区间，避免重复计算
local paper_spans_cache = {}
local function getPaperSpans(scale)
    local key = string.format("%.2f", scale)
    if paper_spans_cache[key] then
        return paper_spans_cache[key]
    end

    local s = scale
    local W_s = floor(BASE_W * s + 0.5)
    local H_s = floor(BASE_H * s + 0.5)

    local rows = {}
    for y_s = 0, H_s - 1 do
        local y_base = y_s / s
        rows[y_s] = rowSpans(y_base)
    end

    local cols = {}
    for x_s = 0, W_s - 1 do
        local x_base = x_s / s
        cols[x_s] = colSpans(x_base)
    end

    local cache = { rows = rows, cols = cols, W_s = W_s, H_s = H_s }
    paper_spans_cache[key] = cache
    return cache
end

local function paintPaper(bb, ox, oy)
    local s = current_scale
    local cache = getPaperSpans(s)
    local rows, cols = cache.rows, cache.cols
    local W_s, H_s = cache.W_s, cache.H_s

    -- 绘制水平方向（白色内部 + 左右边界黑点）
    for y_s = 0, H_s - 1 do
        local spans = rows[y_s]
        for _, span in ipairs(spans) do
            local x1_base, x2_base = span[1], span[2]
            local x1_s = floor(x1_base * s + 0.5)
            local x2_s = floor(x2_base * s + 0.5)
            if x2_s > x1_s then
                bb:paintRect(ox + x1_s, oy + y_s, x2_s - x1_s, 1, Blitbuffer.COLOR_WHITE)
                bb:paintRect(ox + x1_s, oy + y_s, 1, 1, Blitbuffer.COLOR_BLACK)
                bb:paintRect(ox + x2_s - 1, oy + y_s, 1, 1, Blitbuffer.COLOR_BLACK)
            end
        end
    end

    -- 绘制垂直方向边界黑点（不重复绘制白色）
    for x_s = 0, W_s - 1 do
        local spans = cols[x_s]
        for _, span in ipairs(spans) do
            local y1_base, y2_base = span[1], span[2]
            local y1_s = floor(y1_base * s + 0.5)
            local y2_s = floor(y2_base * s + 0.5)
            if y2_s > y1_s then
                bb:paintRect(ox + x_s, oy + y1_s, 1, 1, Blitbuffer.COLOR_BLACK)
                bb:paintRect(ox + x_s, oy + y2_s - 1, 1, 1, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end

-- ------------------------------------------------------------------- text --
local face_cache = {}

local function rawFace(which, size)
    size = px(size)
    if size < 6 then size = 6 end
    local key = which .. "/" .. size
    if face_cache[key] then return face_cache[key] end

    local font_name
    if which == "C" then
        font_name = "cfont"
    elseif which == "L" then
        font_name = "ffont"
    else
        font_name = "cfont"
    end

    local ok, face = pcall(Font.getFace, Font, font_name, size)
    if not ok or not face then
        logger.warn("read-receipt: failed to get built-in font", font_name, "- falling back to cfont")
        face = Font:getFace("cfont", size)
    end

    face_cache[key] = face
    return face
end

local function textWidth(face, s)
    local ok, w = pcall(function()
        return RenderText:sizeUtf8Text(0, 1e6, face, s, true, false).x
    end)
    return ok and w or 0
end

local FONT_SCALE = nil
local function calibrate()
    local probe, target, guess = "READ RECEIPT", 479.0, 72
    for _ = 1, 6 do
        local w = textWidth(rawFace("L", guess), probe)
        if w <= 0 then break end
        if math.abs(w - target) < 0.75 then break end
        guess = guess * target / w
    end
    FONT_SCALE = guess / 72
    logger.info("read-receipt: font scale calibrated to", FONT_SCALE)
end

local function getFace(which, size)
    if not FONT_SCALE then calibrate() end
    return rawFace(which, size * FONT_SCALE * current_scale)
end

local function utf8chars(s)
    local t = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
    return t
end

local has_char_memo = {}
local function faceHasChar(face, ch)
    local memo_key = tostring(face) .. ch
    local memo = has_char_memo[memo_key]
    if memo ~= nil then return memo end
    local code
    local b1 = ch:byte(1)
    if not b1 then return true end
    if b1 < 0x80 then code = b1
    elseif b1 < 0xE0 then code = (b1 - 0xC0) * 0x40 + (ch:byte(2) or 0) - 0x80
    elseif b1 < 0xF0 then
        code = (b1 - 0xE0) * 0x10000 + ((ch:byte(2) or 0) - 0x80) * 0x40 + ((ch:byte(3) or 0) - 0x80)
    else return true end
    local has
    local ok = pcall(function() has = face.ftface:hasGlyph(code) end)
    if not ok or has == nil then has = true end
    has_char_memo[memo_key] = has
    return has
end

local function drawText(bb, x, baseline, face, alt_face, text, ls, c)
    local per_char = (ls and abs(ls) >= 0.4)
    if not per_char then
        for _, ch in ipairs(utf8chars(text)) do
            if not faceHasChar(face, ch) then
                per_char = true
                break
            end
        end
    end
    if not per_char then
        RenderText:renderUtf8Text(bb, px(x), px(baseline), face, text, true, false, c)
        return x + textWidth(face, text)
    end
    for _, ch in ipairs(utf8chars(text)) do
        local f = face
        if alt_face and not faceHasChar(face, ch) then f = alt_face end
        RenderText:renderUtf8Text(bb, px(x), px(baseline), f, ch, true, false, c)
        x = x + textWidth(f, ch) + (ls or 0) * current_scale
    end
    return x - (ls or 0) * current_scale
end

-- --------------------------------------------------------------- the data --
local function resolveReceiptContext()
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI.instance
    if ui and ui.document then
        return {
            ui = ui,
            document = ui.document,
            doc_settings = ui.doc_settings,
            lastfile = ui.document.file,
            from_lastfile = false,
        }
    end

    local lastfile = G_reader_settings:readSetting("lastfile")
    if not lastfile or lfs.attributes(lastfile, "mode") ~= "file" then
        return nil
    end

    local doc_settings
    if DocSettings:hasSidecarFile(lastfile) then
        local ok, ds = pcall(function() return DocSettings:open(lastfile) end)
        if ok then
            doc_settings = ds
        end
    end

    return {
        ui = ui,
        document = nil,
        doc_settings = doc_settings,
        lastfile = lastfile,
        from_lastfile = true,
    }
end

local function lookupBookId(doc_settings, lastfile, props)
    local md5
    if doc_settings then
        md5 = doc_settings:readSetting("partial_md5_checksum")
    end
    if not md5 and lastfile then
        local util = require("util")
        md5 = util.partialMD5(lastfile)
    end
    local title = props and (props.display_title or props.title)
    local authors = props and props.authors or "N/A"
    if not title or not md5 then
        return nil
    end

    local ok, id_book = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local DataStorage = require("datastorage")
        local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
        local sql_stmt = [[
            SELECT id
            FROM   book
            WHERE  title = ?
                AND authors = ?
                AND md5 = ?;
        ]]
        local stmt = conn:prepare(sql_stmt)
        local result = stmt:reset():bind(title, authors, md5):step()
        stmt:close()
        conn:close()
        if result and result[1] then
            return tonumber(result[1])
        end
        return nil
    end)
    if ok then
        return id_book
    end
    return nil
end

local function getTodayBookStatsFromDB(id_book)
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local start_today_time = now_stamp - (now_t.hour * 3600 + now_t.min * 60 + now_t.sec)
    local ok, pages, duration = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local DataStorage = require("datastorage")
        local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
        local sql_stmt = [[
            SELECT count(*),
                   sum(sum_duration)
            FROM   (
                        SELECT sum(duration) AS sum_duration
                        FROM   page_stat
                        WHERE  id_book = %d
                            AND start_time >= %d
                        GROUP  BY page
                   );
        ]]
        local today_pages, today_duration = conn:rowexec(string.format(sql_stmt, id_book, start_today_time))
        conn:close()
        return tonumber(today_pages) or 0, tonumber(today_duration) or 0
    end)
    if ok then
        return duration, pages
    end
    return 0, 0
end

-- First time this book was ever read.
--
-- Deliberately queries the page_stat_data *table* rather than the page_stat
-- *view*: the view exists to rescale page numbers to the book's current page
-- count, which it does by cross-joining a helper table to duplicate rows. We
-- only want the oldest timestamp, where that rescaling is irrelevant, so the
-- direct table read is the same answer for a fraction of the work - cheap
-- enough to also run on the lock-screen path. Falls back to the view for
-- databases old enough to predate the table.
local function getBookStartDate(id_book)
    if not id_book then return nil end
    local ok, stamp = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local DataStorage = require("datastorage")
        local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
        local function minStartTime(from)
            local got, v = pcall(function()
                return conn:rowexec(string.format(
                    "SELECT min(start_time) FROM %s WHERE id_book = %d", from, id_book))
            end)
            if not got or v == nil then return nil end
            return tonumber((tostring(v):gsub("[^%d]", "")))
        end
        local first = minStartTime("page_stat_data") or minStartTime("page_stat")
        conn:close()
        return first
    end)
    if ok and stamp and stamp > 0 then
        return os.date("%Y.%m.%d", stamp)
    end
    return nil
end

local cover_cache = {}
local screensaver_cache = {}

local function getSidecarMtime(lastfile)
    if not lastfile then return 0 end
    local sidecar = DocSettings:findSidecarFile(lastfile)
    if not sidecar then return 0 end
    return lfs.attributes(sidecar, "modification") or 0
end

local function getFileMtime(file)
    if not file then return 0 end
    return lfs.attributes(file, "modification") or 0
end

local function screensaverCacheValid(lastfile)
    if not lastfile or screensaver_cache.lastfile ~= lastfile then
        return false
    end
    if screensaver_cache.file_mtime ~= getFileMtime(lastfile) then
        return false
    end
    if screensaver_cache.sidecar_mtime ~= getSidecarMtime(lastfile) then
        return false
    end
    return screensaver_cache.data ~= nil
end

local function collectData(ctx, opts)
    opts = opts or {}
    local for_screensaver = opts.for_screensaver
    if ctx and ctx.document == nil and ctx.ui and ctx.ui.document and not ctx.lastfile then
        ctx = {
            ui = ctx.ui,
            document = ctx.ui.document,
            doc_settings = ctx.ui.doc_settings,
            lastfile = ctx.ui.document.file,
            from_lastfile = false,
        }
    end
    if not ctx then
        ctx = resolveReceiptContext()
    end
    if not ctx then
        return nil
    end

    local ui = ctx.ui
    local document = ctx.document
    local doc_settings = ctx.doc_settings
    local lastfile = ctx.lastfile
    local now = os.time()
    local wd_cn = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }
    local wd_en = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
    local wd = tonumber(os.date("%w", now)) + 1
    local d = {
        date = os.date("%Y.%m.%d", now),
        weekday_cn = wd_cn[wd],
        weekday_en = wd_en[wd],
        no = "NO. D" .. os.date("%Y%m%d", now),
        id = "D" .. os.date("%Y%m%d", now),
        rating = 0,
        chapter = nil,
        total_pages = "0",
        total_time = "0 m",
    }
    local props
    if document then
        props = document:getProps() or {}
        if props.title and props.title ~= "" then
            d.title = props.title
        else
            d.title = ""
        end
        if props.authors and props.authors ~= "" then
            d.author = props.authors
        end
        local cur = ui.view and ui.view.state and ui.view.state.page or 1
        local total = document:getPageCount() or 1
        d.pages = string.format("%d / %d", cur, total)
        d.progress = cur / total
        d.pct = string.format("%d%%", math.floor(d.progress * 100 + 0.5))

        local toc = ui.toc
        if toc and toc.getTocTitleByPage then
            local chapter = toc:getTocTitleByPage(cur) or ""
            if chapter ~= "" then
                d.chapter = chapter
            end
        end
    elseif lastfile then
        if doc_settings then
            props = doc_settings:readSetting("doc_props")
        end
        props = FileManagerBookInfo.extendProps(props, lastfile)
        if props then
            d.title = props.display_title or props.title or ""
            if props.authors and props.authors ~= "" then
                d.author = props.authors
            end
            local totalpages = doc_settings and doc_settings:readSetting("doc_pages") or props.pages or 0
            local percent = doc_settings and doc_settings:readSetting("percent_finished") or 0
            totalpages = tonumber(totalpages) or 0
            percent = tonumber(percent) or 0
            if totalpages > 0 then
                local currentpage = math.floor(percent * totalpages + 0.5)
                if currentpage < 1 and percent > 0 then
                    currentpage = 1
                end
                d.pages = string.format("%d / %d", currentpage, totalpages)
                d.progress = currentpage / totalpages
                d.pct = string.format("%d%%", math.floor(d.progress * 100 + 0.5))
            end
        end
    end

    d.status = "在读"
    if doc_settings then
        local ok, summary = pcall(function() return doc_settings:readSetting("summary") end)
        if ok and summary then
            if summary.status == "complete" then
                d.status = "已读"
            end
            if summary.rating then
                d.rating = normalizeRating(summary.rating)
            end
        end
    end
    if d.progress and d.progress >= 0.999 then d.status = "已读" end

    d.s_pages, d.s_time, d.d_pages, d.d_time = "--", "--", "--", "--"
    d.total_time = "0 m"
    d.start_date = "--"

    local function hm(seconds)
        seconds = math.floor(tonumber(seconds) or 0)
        local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
        if h > 0 then
            if m == 0 then
                return string.format("%dh", h)
            else
                return string.format("%dh %02dm", h, m)
            end
        else
            return string.format("%d m", m)
        end
    end

    local stats = ui and ui.statistics
    local enabled = stats and stats.settings and stats.settings.is_enabled
    local dbg = {}
    local id_book = stats and stats.id_curr_book
    if not for_screensaver and not id_book then
        id_book = lookupBookId(doc_settings, lastfile, props)
    end

    if not for_screensaver and stats and stats.insertDB then
        pcall(function() stats:insertDB() end)
    end

    if for_screensaver and ctx.from_lastfile and not id_book then
        d.debug = "screensaver-fast"
        d.est_time = "--"
        return d
    end

    if not stats and not id_book then
        d.debug = "no ui.statistics"
    elseif stats and not enabled then
        d.debug = "statistics plugin disabled"
    else
        dbg[#dbg + 1] = "id=" .. tostring(id_book)

        if stats and stats.getTodayBookStats then
            local ok, t, p = pcall(stats.getTodayBookStats, stats)
            dbg[#dbg + 1] = "today=" .. tostring(ok) .. ":" .. tostring(p) .. "/" .. tostring(t)
            if ok then
                if p then d.d_pages = tostring(p) end
                if t then d.d_time = hm(t) end
            end
        elseif id_book and not for_screensaver then
            local t, p = getTodayBookStatsFromDB(id_book)
            if p > 0 then d.d_pages = tostring(p) end
            if t > 0 then d.d_time = hm(t) end
            dbg[#dbg + 1] = "today_db=" .. tostring(p) .. "/" .. tostring(t)
        end

        if stats and stats.getPageTimeTotalStats and id_book then
            local ok, pages, secs = pcall(stats.getPageTimeTotalStats, stats, id_book)
            dbg[#dbg + 1] = "total=" .. tostring(ok) .. ":" .. tostring(pages) .. "/" .. tostring(secs)
            if ok then
                if pages then d.total_pages = tostring(pages) end
                if secs then d.total_time = hm(secs) end
            end
        elseif id_book and not for_screensaver then
            local ok_db, pages, secs = pcall(function()
                local SQ3 = require("lua-ljsqlite3/init")
                local DataStorage = require("datastorage")
                local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
                local sql_stmt = [[
                    SELECT total_read_pages, total_read_time
                    FROM   book
                    WHERE  id = %d;
                ]]
                local total_pages, total_time = conn:rowexec(string.format(sql_stmt, id_book))
                conn:close()
                return tonumber(total_pages), tonumber(total_time)
            end)
            if ok_db then
                if pages then d.total_pages = tostring(pages) end
                if secs then d.total_time = hm(secs) end
            end
        end

        if d.total_time == "0 m" and stats and stats.book_read_time then
            d.total_time = hm(stats.book_read_time)
        end

        if stats and stats.start_current_period then
            local since = tonumber((tostring(stats.start_current_period):gsub("[^%d]", ""))) or os.time()
            d.s_time = hm(os.time() - since)
        end

        -- The start date is wanted on the lock screen too, so it lives outside
        -- the in-app-only block below (it used to be inside it, which is why
        -- the screensaver receipt always showed "--" there). Its query is a
        -- single indexed min() on page_stat_data, no writes involved.
        if id_book then
            d.start_date = getBookStartDate(id_book) or d.start_date
        end

        if id_book and not for_screensaver then
            local ok_db, err = pcall(function()
                local SQ3 = require("lua-ljsqlite3/init")
                local DataStorage = require("datastorage")
                local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
                local function one(sql)
                    local ok, v = pcall(function() return conn:rowexec(sql) end)
                    if not ok or v == nil then return nil end
                    return tonumber((tostring(v):gsub("[^%-%d%.]", "")))
                end
                local since = tonumber((tostring(stats.start_current_period or ""):gsub("[^%d]", ""))) or os.time()
                local sp = one(string.format("SELECT count(DISTINCT page) FROM page_stat WHERE id_book = %d AND start_time >= %d", id_book, since))
                local st = one(string.format("SELECT sum(duration) FROM page_stat WHERE id_book = %d AND start_time >= %d", id_book, since))
                if sp then d.s_pages = tostring(sp) end
                if st then d.s_time = hm(st) end
                dbg[#dbg + 1] = "sess=" .. tostring(sp) .. "/" .. tostring(st)
                conn:close()
            end)
            if not ok_db then dbg[#dbg + 1] = "dberr:" .. tostring(err):sub(-48) end
        end

        if d.s_time == "--" and stats and stats.start_current_period then
            d.s_time = hm(os.time() - tonumber((tostring(stats.start_current_period):gsub("[^%d]", ""))))
        end
        d.debug = table.concat(dbg, " ")
    end

    local avg_time_per_page = stats and stats.avg_time
    if avg_time_per_page and avg_time_per_page > 0 and document then
        local total_pages = document:getPageCount() or 0
        local current_page = ui.view and ui.view.state and ui.view.state.page or 1
        local page_left = math.max(total_pages - current_page, 0)
        d.est_time = hm(avg_time_per_page * page_left)
    else
        d.est_time = "--"
    end

    return d
end

local function shouldShowScreensaverCover()
    if G_reader_settings:has("read_receipt_show_cover") then
        return G_reader_settings:isTrue("read_receipt_show_cover")
    end
    return true
end

-- The screensaver only ever needs the cover of the *current* lastfile, so we
-- never need cover history for previously-read books. Keeping only a single
-- entry (dropping every other one whenever we cache a new cover) matters a
-- lot on a device as memory/storage-constrained as a Kindle: each entry is a
-- decoded, uncompressed full-resolution bitmap (can be a few MB), and this
-- table lives purely in RAM for the current KOReader session (it is never
-- written to disk) - without a cap it would otherwise grow by one entry per
-- book opened for the entire session, which on a Kindle that's rarely
-- rebooted could add up to a real amount of memory over weeks of reading.
-- Embedded covers can be far larger than the screen (2000x3000 is common),
-- which at 4 bytes/pixel is ~24MB held in RAM for no benefit whatsoever: we
-- never display them bigger than the screen. Downscale once, here, so the
-- cache footprint is bounded by the screen size no matter which book is open,
-- and so we don't redo that scaling on every single suspend.
local function downscaleToScreen(cover_bb)
    if not cover_bb or not cover_bb.getWidth then return cover_bb end
    local ok, scaled = pcall(function()
        local bw, bh = cover_bb:getWidth(), cover_bb:getHeight()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        if bw <= sw and bh <= sh then
            return cover_bb
        end
        local factor = math.min(sw / bw, sh / bh)
        -- free_orig_bb = true: we own every blitbuffer that reaches this point
        -- (each loadCover strategy hands us a freshly built one).
        return RenderImage:scaleBlitBuffer(cover_bb, bw * factor, bh * factor, true)
    end)
    if ok and scaled then
        return scaled
    end
    return cover_bb
end

local function rememberCover(file, cover_bb, full_res)
    cover_bb = downscaleToScreen(cover_bb)
    if file and cover_bb then
        for existing_file in pairs(cover_cache) do
            if existing_file ~= file then
                cover_cache[existing_file] = nil
            end
        end
        cover_cache[file] = {
            bb = cover_bb,
            mtime = getFileMtime(file),
            full_res = full_res and true or false,
        }
    end
    return cover_bb
end

local function getCachedCover(file)
    local cached = cover_cache[file]
    if cached and cached.mtime == getFileMtime(file) then
        return cached.bb
    end
    return nil
end

-- A cached small thumbnail is better than nothing on the screensaver, but it
-- must not stop us from later upgrading to the real, full-resolution cover.
local function isCachedCoverFullRes(file)
    local cached = cover_cache[file]
    return cached ~= nil
        and cached.full_res
        and cached.mtime == getFileMtime(file)
end

-- cover loading
-- CoverBrowser's DB only holds covers already scaled down for the file
-- browser's cover grid, so this must stay the *last* resort: blowing one of
-- those up to a 1072x1448 screen is what made the screensaver cover blurry.
local function loadThumbnailDbCover(file, get_cover)
    for _, module_name in ipairs({
        "plugins/coverbrowser.koplugin/bookinfomanager",
        "bookinfomanager",
    }) do
        local ok, BIM = pcall(require, module_name)
        if ok and BIM then
            local got, info = pcall(function() return BIM:getBookInfo(file, get_cover) end)
            if got and info and info.cover_bb then
                return info.cover_bb
            end
        end
    end
    return nil
end

-- opts.safe_only: NEVER touch a live/already-open document instance, and never
--   open a throwaway document instance either - only read pre-existing,
--   decoupled caches (the CoverBrowser thumbnail DB, or a static custom-cover
--   file). Use this whenever a document may currently be open elsewhere (i.e.
--   the user is actively reading it) - calling into a live CreDocument's
--   getCoverPageImage() while KOReader is mid-suspend has been observed to
--   segfault the whole process (a native crash pcall cannot catch), so we must
--   avoid it entirely rather than try to guard against it in Lua.
-- opts.fast: skip anything that could open a document (suspend-time paths).
-- opts.force_refresh: ignore the cache, used to upgrade a cached thumbnail.
local function loadCover(doc_or_file, opts)
    opts = opts or {}
    local fast = opts.fast
    local safe_only = opts.safe_only
    if not doc_or_file then return nil end
    local file = type(doc_or_file) == "string" and doc_or_file or doc_or_file.file
    if not file then return nil end
    if not opts.force_refresh then
        local cached = getCachedCover(file)
        if cached then
            return cached
        end
    end
    local doc = (not safe_only) and type(doc_or_file) == "table" and doc_or_file.file and doc_or_file or nil

    -- Ordered best-quality-first. Everything above the thumbnail DB yields a
    -- full-resolution cover; the thumbnail DB is only a graceful degradation.
    local tries = {}
    if doc and doc.getCoverPageImage then
        tries[#tries + 1] = { name = "live-doc", fn = function()
            return doc:getCoverPageImage()
        end }
    end
    tries[#tries + 1] = { name = "custom-cover-file", fn = function()
        local path = DocSettings:findCustomCoverFile(file)
        if not path then return nil end
        return RenderImage:renderImageFile(path, false)
    end }
    if not fast and not safe_only then
        -- Opens a brand-new, throwaway document instance for `file` to extract
        -- its cover at full resolution. Only safe when nothing else already has
        -- this exact file open, which is why safe_only callers skip it.
        tries[#tries + 1] = { name = "full-res-throwaway-doc", fn = function()
            return FileManagerBookInfo:getCoverImage(nil, file)
        end }
    end
    tries[#tries + 1] = { name = "thumbnail-db", fn = function()
        return loadThumbnailDbCover(file, true)
    end }

    for _, try in ipairs(tries) do
        local ok, res = pcall(try.fn)
        if ok and res then
            if not fast then
                logger.info("read-receipt: cover loaded via", try.name)
            end
            return rememberCover(file, res, try.name ~= "thumbnail-db")
        end
        if not fast then
            logger.warn("read-receipt: cover strategy", try.name, "->", tostring(res))
        end
    end
    return nil
end

-- Forward declaration (defined below, but used by buildScreensaverCache).
local prewarmFullResCover

local function buildScreensaverCache(ctx)
    if not ctx or not ctx.lastfile then
        return nil
    end
    local lastfile = ctx.lastfile
    local cover
    if shouldShowScreensaverCover() then
        if ctx.document then
            -- Actively reading: absolutely no document-engine calls during
            -- the suspend window (that's what segfaulted before). Only ever
            -- read what was already prewarmed at a safe time (book-open,
            -- see prewarmFullResCover), falling back to the small CoverBrowser
            -- thumbnail cache (still a plain cache read, no engine call).
            cover = getCachedCover(lastfile) or loadCover(lastfile, { safe_only = true })
        else
            -- Not reading: no live document to conflict with, safe to do the
            -- full lookup (opening a throwaway document if needed), and to
            -- upgrade a previously cached small thumbnail to the real cover.
            prewarmFullResCover(lastfile)
            cover = getCachedCover(lastfile) or loadCover(lastfile, { fast = false })
        end
    end
    local data = collectData(ctx, { for_screensaver = true })
    screensaver_cache = {
        lastfile = lastfile,
        file_mtime = getFileMtime(lastfile),
        sidecar_mtime = getSidecarMtime(lastfile),
        data = data,
        cover = cover,
        built_at = os.time(),
    }
    return screensaver_cache
end

local function getScreensaverCache(ctx)
    if screensaverCacheValid(ctx.lastfile) then
        return screensaver_cache
    end
    return buildScreensaverCache(ctx)
end

local function isActivelyReading()
    local ok, result = pcall(function()
        local ReaderUI = require("apps/reader/readerui")
        return ReaderUI.instance and ReaderUI.instance.document ~= nil
    end)
    return ok and result or false
end

-- Full-resolution cover prewarm, meant to run at a "calm" moment only - when a
-- book is opened, or right as it's closed - and NEVER during the suspend /
-- screensaver window itself. Doing the heavier work here rather than at
-- suspend time is what gets us a sharp, full-size cover without the blur of
-- stretching CoverBrowser's small grid thumbnails up to full-screen size.
--
-- Pass `doc` whenever a live document for `file` is at hand: reading the cover
-- straight off the already-loaded document avoids opening (and parsing) the
-- book a second time, which is the expensive part. This is safe *here* because
-- we're at normal UI time - the segfault we used to hit came from doing this
-- mid-suspend, and that path (buildScreensaverCache) still refuses to touch a
-- live document at all.
function prewarmFullResCover(file, doc)
    if not file then return end
    -- Only skip when we already hold a *full-resolution* cover. If all we have
    -- is a small thumbnail-DB fallback from an earlier screensaver, force a
    -- refresh so it gets upgraded to the real cover.
    if isCachedCoverFullRes(file) then return end
    local source = (doc and doc.file == file) and doc or file
    pcall(function() loadCover(source, { fast = false, force_refresh = true }) end)
end

local function prewarmScreensaverCache()
    if G_reader_settings:readSetting("screensaver_type") ~= "read_receipt" then
        return
    end
    local ctx = resolveReceiptContext()
    if not ctx or (ctx.doc_settings and ctx.doc_settings:isTrue("exclude_screensaver")) then
        return
    end
    if isActivelyReading() then
        pcall(function() buildScreensaverCache(ctx) end)
    else
        prewarmFullResCover(ctx.lastfile)
    end
end

local function blitCoverInto(bb, img, dx, dy, dw, dh)
    if not img then return false end
    dx, dy, dw, dh = math.floor(dx), math.floor(dy), math.floor(dw), math.floor(dh)
    if dw < 1 or dh < 1 then return false end
    local ok, err = pcall(function()
        local ImageWidget = require("ui/widget/imagewidget")
        local w = ImageWidget:new{
            image = img,
            -- The blitbuffer belongs to cover_cache and gets reused; the widget
            -- must not take ownership of it (ImageWidget would otherwise free it).
            image_disposable = false,
            width = dw,
            height = dh,
            -- nil scale_factor stretches to exactly dw x dh, which is what we
            -- want here: the receipt layout has a fixed cover frame to fill.
            scale_factor = nil,
        }
        w:paintTo(bb, dx, dy)
        w:free()
    end)
    if ok then return true end
    logger.warn("read-receipt: ImageWidget cover failed:", tostring(err))
    local scaled = RenderImage:scaleBlitBuffer(img, dw, dh, false)
    if scaled then
        bb:blitFrom(scaled, dx, dy, 0, 0, dw, dh)
        return true
    end
    return false
end

-- ------------------------------------------------------------- the widget --
-- Forward declarations: Receipt:onTap needs these, but they're only defined
-- further down (they depend on the widget itself). Without declaring the
-- locals up here, the reference inside onTap compiles to a *global* lookup,
-- which is nil at runtime - that's what made tapping the barcode crash.
local resolveActiveUI
local openReadingInsightsPopup

local Receipt = InputContainer:extend{
    name = "read_receipt_view",
    covers_fullscreen = true,
    data = nil,
    document = nil,
    doc_settings = nil,
    receipt_file = nil,
    prefetched_cover = nil,
    ui = nil,
    rating = 0,
    scale = 1,
    star_icons_full = nil,
    star_icons_half = nil,
    star_icons_empty = nil,
}

function Receipt:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    if Device:hasKeys() then
        local back = Device.input and Device.input.group and Device.input.group.Back or { "Back" }
        self.key_events = { Close = { back } }
    end
    if not self.data then
        self.data = collectData({
            ui = self.ui,
            document = self.document,
            doc_settings = self.doc_settings,
            lastfile = self.receipt_file or (self.document and self.document.file),
        })
    end
    self.rating = normalizeRating(self.data and self.data.rating or 0)
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.scale = math.min(screen_w * 0.68 / BASE_W, screen_h * 0.90 / BASE_H)

    self.star_icons_full = {}
    self.star_icons_half = {}
    self.star_icons_empty = {}
    local star_size_px = math.max(MIN_STAR_SIZE, math.floor(STAR_SIZE * self.scale + 0.5))
    local star_gap_px = math.floor(STAR_GAP * self.scale + 0.5)

    for i = 1, STAR_COUNT do
        local ok_full, icon_full = pcall(IconWidget.new, IconWidget, {
            file = ICON_DIR .. "star.full.svg",
            width = star_size_px,
            height = star_size_px,
            alpha = true,
        })
        if ok_full and icon_full then
            self.star_icons_full[i] = icon_full
        else
            logger.warn("read-receipt: failed to create full star icon #", i)
        end

        local ok_half, icon_half = pcall(IconWidget.new, IconWidget, {
            file = ICON_DIR .. "star.half.svg",
            width = star_size_px,
            height = star_size_px,
            alpha = true,
        })
        if ok_half and icon_half then
            self.star_icons_half[i] = icon_half
        else
            logger.warn("read-receipt: failed to create half star icon #", i)
        end

        local ok_empty, icon_empty = pcall(IconWidget.new, IconWidget, {
            file = ICON_DIR .. "star.empty.svg",
            width = star_size_px,
            height = star_size_px,
            alpha = true,
        })
        if ok_empty and icon_empty then
            self.star_icons_empty[i] = icon_empty
        else
            logger.warn("read-receipt: failed to create empty star icon #", i)
        end
    end
end

function Receipt:onCloseWidget()
    if self.star_icons_full then
        for _, w in ipairs(self.star_icons_full) do
            if w then pcall(function() w:free() end) end
        end
    end
    if self.star_icons_half then
        for _, w in ipairs(self.star_icons_half) do
            if w then pcall(function() w:free() end) end
        end
    end
    if self.star_icons_empty then
        for _, w in ipairs(self.star_icons_empty) do
            if w then pcall(function() w:free() end) end
        end
    end
end

function Receipt:onTap(arg, ges)
    if self.is_screensaver then
        UIManager:close(self)
        return true
    end

    local pos = ges.pos
    local ox = px((Screen:getWidth() - BASE_W * self.scale) / 2)
    local oy = px((Screen:getHeight() - BASE_H * self.scale) / 2)

    local tx = (pos.x - ox) / self.scale
    local ty = (pos.y - oy) / self.scale

    if tx >= 30 and tx <= 810 and ty >= 1300 and ty <= 1360 then
        local preferred_ui = self.ui
        local receipt = self
        UIManager:scheduleIn(0.1, function()
            -- Scheduled callbacks run straight from UIManager's main loop, so
            -- anything escaping here would crash KOReader outright.
            local ok, opened, reason = pcall(openReadingInsightsPopup, preferred_ui)
            if ok and opened then
                -- Only now close the receipt. The popup went on the stack
                -- above us, so it was hidden until this point; closing marks
                -- the widgets below dirty, which paints the popup. Closing
                -- *first* (as we used to) meant that if the popup failed to
                -- open we'd silently drop the user back to the previous
                -- screen with no explanation.
                UIManager:close(receipt)
                return
            end
            if not ok then
                reason = tostring(opened)
                logger.err("read-receipt: insights popup crashed:", reason)
            end
            pcall(function()
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = "阅读洞察打开失败：" .. tostring(reason or "未知原因"),
                })
            end)
        end)
        return true
    end

    local star_total_w = STAR_COUNT * STAR_SIZE + (STAR_COUNT - 1) * STAR_GAP
    local star_x1 = STAR_X - STAR_TOUCH_EXPAND
    local star_x2 = STAR_X + star_total_w + RATING_TEXT_GAP + 100 + STAR_TOUCH_EXPAND
    local star_y1 = STAR_TOP - STAR_TOUCH_EXPAND
    local star_y2 = STAR_TOP + STAR_SIZE + STAR_TOUCH_EXPAND

    if tx >= star_x1 and tx <= star_x2 and ty >= star_y1 and ty <= star_y2 then
        local new_rating = normalizeRating(ratingFromTapX(tx))

        if new_rating == self.rating and self.rating > 0 then
            self.rating = 0
        else
            self.rating = new_rating
        end

        self:saveRating()
        UIManager:setDirty(self, "partial")
        return true
    end

    UIManager:close(self)
    return true
end

function Receipt:onClose()
    UIManager:close(self)
    return true
end

function Receipt:saveRating()
    local doc_settings = self.doc_settings or (self.ui and self.ui.doc_settings)
    if not doc_settings then return end
    local ok, err = pcall(function()
        local summary = doc_settings:readSetting("summary") or {}
        if self.rating > 0 then
            summary.rating = self.rating
        else
            summary.rating = nil
        end
        doc_settings:saveSetting("summary", summary)
        doc_settings:flush()
    end)
    if not ok then
        logger.warn("read-receipt: save rating failed:", tostring(err))
    end
end

function Receipt:getData()
    if not self.data then
        self.data = collectData({
            ui = self.ui,
            document = self.document,
            doc_settings = self.doc_settings,
            lastfile = self.receipt_file or (self.document and self.document.file),
        })
    end
    return self.data
end

function Receipt:getCover()
    if self.cover_checked then return self.cover end
    self.cover_checked = true
    if self.prefetched_cover then
        self.cover = self.prefetched_cover
    elseif self.is_screensaver then
        -- Never call into the document engine here - the live document may
        -- be open elsewhere during suspend. Only read caches (prewarmed at
        -- book-open time, or the small CoverBrowser thumbnail as fallback).
        local file = self.receipt_file or (self.document and self.document.file)
        self.cover = file and (getCachedCover(file) or loadCover(file, { safe_only = true }))
    elseif self.document then
        self.cover = loadCover(self.document)
    elseif self.receipt_file then
        self.cover = loadCover(self.receipt_file, { fast = true })
    end
    return self.cover
end

function Receipt:getSize() return self.dimen end

function Receipt:paintTo(bb, x, y)
    current_scale = self.scale

    local ox = x + px((Screen:getWidth() - BASE_W * current_scale) / 2)
    local oy = y + px((Screen:getHeight() - BASE_H * current_scale) / 2)

    paintPaper(bb, ox, oy)

    dottedH(bb, ox, oy, 33.7, 815, 327.2, 2, 7, 2, COL.K)
    dottedH(bb, ox, oy, 33.7, 815, 418.6, 2, 7, 2, COL.K)
    rect(bb, ox, oy, 586.06, 53.52, 1, 259.9, COL.K)
    rect(bb, ox, oy, 273.3, 339.9, 1, 66, COL.K)
    rect(bb, ox, oy, 540.4, 339.9, 1, 66, COL.K)

    local function paintCover()
        local cx, cy, cw, ch = px(512.9), px(489.58), px(302.9), px(399.6)
        local abs_cx = ox + math.floor(cx * current_scale)
        local abs_cy = oy + math.floor(cy * current_scale)
        local abs_cw = math.floor(cw * current_scale)
        local abs_ch = math.floor(ch * current_scale)
        if not blitCoverInto(bb, self:getCover(), abs_cx, abs_cy, abs_cw, abs_ch) then
            bb:paintRect(abs_cx, abs_cy, abs_cw, abs_ch, COL.COVER)
        end
        rect(bb, ox, oy, cx, cy, cw, 1, COL.K)
        rect(bb, ox, oy, cx, cy + ch - 1, cw, 1, COL.K)
        rect(bb, ox, oy, cx, cy, 1, ch, COL.K)
        rect(bb, ox, oy, cx + cw - 1, cy, 1, ch, COL.K)
    end
    pcall(paintCover)

    rect(bb, ox, oy, 33.6, 816.68, 423.6, 14.6, COL.TRACK)
    local progress = (self.data and self.data.progress) or 0.1705
    rect(bb, ox, oy, 33.6, 816.68, 423.6 * progress, 14.6, COL.FILL)
    dottedH(bb, ox, oy, 33.2, 814.5, 972.85, 2, 9, 2, COL.K)
    rect(bb, ox, oy, 31.9, 1058.35, 785.8, 1, COL.K)
    rect(bb, ox, oy, 45.3, 1092.1, 137, 1, COL.K)
    rect(bb, ox, oy, 253.8, 1092.1, 137.5, 1, COL.K)
    rect(bb, ox, oy, 456.8, 1092.1, 137, 1, COL.K)
    rect(bb, ox, oy, 664.8, 1092.1, 137.5, 1, COL.K)
    -- 竖线三条：恢复原始硬编码参数
    rect(bb, ox, oy, 200.9, 1122.2, 1, 126.3, COL.K)
    rect(bb, ox, oy, 422.4, 1122.2, 1, 126.3, COL.K)
    rect(bb, ox, oy, 612.4, 1122.2, 1, 126.3, COL.K)
    dottedH(bb, ox, oy, 33.2, 814.5, 1277.35, 2, 9, 2, COL.K)
    for _, b in ipairs(BARS) do
        rect(bb, ox, oy, b[1], BARCODE_Y + 5, b[2], BARCODE_H, COL.K)
    end
    disc(bb, ox, oy, 383.28, 1446.84, 3.1, COL.K)
    for i, cx in ipairs({ 406.92, 427.8, 448.44, 469.32 }) do
        disc(bb, ox, oy, cx, 1446.84, 2.4, COL.K)
    end

    local data = self.data or {}
    local widths = {}
    for _, it in ipairs(ITEMS) do
        local text = it.t
        if it.key and data[it.key] then
            if it.prefix then
                text = it.prefix .. (data[it.key] or "")
            else
                text = data[it.key]
            end
        end
        text = text or "" -- keyed items with no data and no literal `t` must not reach drawText as nil
        if text ~= "" then
            local face = getFace(it.f, it.size)
            local tw = textWidth(face, text)
            widths[it] = tw
        else
            widths[it] = 0
        end
    end

    -- 计算状态值右边缘（用于“状态”右对齐）
    local status_right_edge_base = nil
    for _, it in ipairs(ITEMS) do
        if it.key == "status" and widths[it] then
            status_right_edge_base = it.x + widths[it] / current_scale
            break
        end
    end

    -- 计算“今日摘要”的基线（用于SUMMARY对齐）
    local summary_baseline = nil
    for _, it in ipairs(ITEMS) do
        if it.t == "今日摘要" then
            summary_baseline = oy + (it.top + K_CN * it.size) * current_scale
            break
        end
    end

    local title_left_idx = 6
    local title_slash_idx = 7
    local title_right_indices = {8, 9, 10, 11, 12}
    local x_start = 34.36

    local left_item = ITEMS[title_left_idx]
    local left_face = getFace(left_item.f, left_item.size)
    local left_text = left_item.t
    local left_baseline = oy + (left_item.top + K_CN * left_item.size) * current_scale
    local end_x = drawText(bb, ox + x_start * current_scale, left_baseline, left_face, nil, left_text, left_item.ls * current_scale, COL.K)
    local x_pos = (end_x - ox) / current_scale

    local slash_item = ITEMS[title_slash_idx]
    local slash_face = getFace(slash_item.f, slash_item.size)
    local slash_text = slash_item.t
    local slash_baseline = oy + (slash_item.top + K_LA * slash_item.size) * current_scale
    local slash_x = x_pos
    end_x = drawText(bb, ox + slash_x * current_scale, slash_baseline, slash_face, nil, slash_text, slash_item.ls * current_scale, COL.K)
    x_pos = (end_x - ox) / current_scale

    for _, idx in ipairs(title_right_indices) do
        local item = ITEMS[idx]
        local face = getFace(item.f, item.size)
        local text = item.t
        local baseline = oy + (item.top + K_LA * item.size) * current_scale
        end_x = drawText(bb, ox + x_pos * current_scale, baseline, face, nil, text, item.ls * current_scale, COL.K)
        x_pos = (end_x - ox) / current_scale
    end

    local pen = 0
    for idx, it in ipairs(ITEMS) do
        if idx >= 6 and idx <= 12 then
            goto continue
        end

        local text = it.t
        if it.key and data[it.key] then
            if it.prefix then
                text = it.prefix .. (data[it.key] or "")
            else
                text = data[it.key]
            end
        end
        text = text or "" -- keyed items with no data and no literal `t` must not reach drawText as nil
        if text ~= "" then
            local face = getFace(it.f, it.size)
            local alt = getFace(it.f == "C" and "L" or "C", it.size)

            if it.maxw and textWidth(face, text) > it.maxw * current_scale then
                local chars = utf8chars(text)
                while #chars > 1 and textWidth(face, table.concat(chars) .. "…") > it.maxw * current_scale do
                    table.remove(chars)
                end
                text = table.concat(chars) .. "…"
            end

            local tw = textWidth(face, text)
            local sx

            -- 特殊处理“状态”标签右对齐
            if it.t == "状态" and status_right_edge_base then
                sx = ox + (status_right_edge_base - widths[it] / current_scale) * current_scale
            elseif it.t == "SUMMARY" then
                -- 紧跟“今日摘要”后，留一个空格宽度
                local space_w = textWidth(face, " ")
                sx = pen + space_w
            elseif it.no_align then
                local state_item = ITEMS[1]
                local status_item = ITEMS[2]
                local state_width = widths[state_item] or 0
                local status_width = widths[status_item] or 0
                local right_state = 759.55 + state_width / current_scale
                local right_status = 599.56 + status_width / current_scale
                local max_right = math.max(right_state, right_status)
                sx = ox + max_right * current_scale - tw
            elseif it.center then
                sx = ox + (BASE_W * current_scale - tw) / 2
            elseif it.right_align then
                sx = ox + it.x * current_scale - tw
            elseif it.dot_center then
                local left_item = ITEMS[idx-1]
                local right_item = ITEMS[idx+1]
                if left_item and right_item then
                    local left_x = left_item.x * current_scale
                    local left_width = widths[left_item] or 0
                    local right_x = right_item.x * current_scale
                    local mid = (left_x + left_width + right_x) / 2
                    sx = ox + mid - tw/2
                else
                    sx = ox + it.x * current_scale
                end
            else
                sx = it.follow and (pen + it.follow * current_scale) or (ox + it.x * current_scale)
            end

            local baseline
            if it.t == "SUMMARY" and summary_baseline then
                baseline = summary_baseline  -- 强制使用中文基线
            else
                local k = it.f == "C" and K_CN or K_LA
                baseline = oy + (it.top + k * it.size) * current_scale
            end

            local ok, res = pcall(drawText, bb, sx, baseline,
                                  face, alt, text, it.ls * current_scale, COL[it.c])
            if ok then
                pen = res
            else
                logger.warn("read-receipt: draw failed", text, res)
            end
        end
        ::continue::
    end

    local rating = normalizeRating(self.rating or 0)
    local star_x = ox + STAR_X * current_scale
    local star_y = oy + STAR_TOP * current_scale
    local star_size_scaled = math.max(MIN_STAR_SIZE, STAR_SIZE * current_scale)
    local star_gap_scaled = STAR_GAP * current_scale

    for i = 1, STAR_COUNT do
        local kind = starIconKind(rating, i)
        local icon
        if kind == "full" then
            icon = self.star_icons_full and self.star_icons_full[i]
        elseif kind == "half" then
            icon = self.star_icons_half and self.star_icons_half[i]
        else
            icon = self.star_icons_empty and self.star_icons_empty[i]
        end

        if icon then
            local ok_paint = pcall(function()
                icon:paintTo(bb, math.floor(star_x + 0.5), math.floor(star_y + 0.5))
            end)
            if not ok_paint then
                logger.warn("read-receipt: star paint failed for", kind, "icon", i)
            end
        else
            logger.warn("read-receipt: missing star icon for index", i)
        end

        star_x = star_x + star_size_scaled + star_gap_scaled
    end

    local rating_text = ratingLabelText(rating)
    local full_text = "（" .. rating_text .. "）"
    local text_face = getFace("C", RATING_TEXT_SIZE)
    local text_baseline = star_y + (star_size_scaled - K_CN * RATING_TEXT_SIZE * current_scale) / 2 + K_CN * RATING_TEXT_SIZE * current_scale
    pcall(drawText, bb, star_x + RATING_TEXT_GAP * current_scale, text_baseline, text_face, nil, full_text, 0, COL.K)
end

-- ------------------------------------------------------------ integration --
function resolveActiveUI()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        return ReaderUI.instance
    end
    local FileManager = require("apps/filemanager/filemanager")
    if FileManager.instance then
        return FileManager.instance
    end
    return nil
end

-- Returns true on success, or false plus a short human-readable reason so the
-- caller can actually tell the user what went wrong.
function openReadingInsightsPopup(preferred_ui)
    local ui = preferred_ui or resolveActiveUI()
    local reason
    local show = rawget(_G, "__readingreceipt_show_insights")
    if show then
        -- pcall: the popup builds a fairly large widget tree, and this runs
        -- from a scheduled callback where a raw error would reach the main
        -- loop and take KOReader down with it.
        local called_ok, shown, err = pcall(show, ui)
        if called_ok and shown then
            return true
        end
        reason = called_ok and tostring(err) or tostring(shown)
        logger.warn("read-receipt: insights popup failed:", reason)
    else
        reason = "模块未加载"
    end

    if ui and ui.onShowReadingInsightsPopup then
        local ok, err = pcall(ui.onShowReadingInsightsPopup, ui)
        if ok then
            return true
        end
        reason = tostring(err)
        logger.warn("read-receipt: insights popup fallback failed:", reason)
    elseif not ui then
        reason = reason or "没有可用界面"
    end
    return false, reason
end

local function showReceipt()
    local ctx = resolveReceiptContext()
    if not ctx then
        logger.info("read-receipt: no book context, skip showing receipt")
        return
    end
    UIManager:show(Receipt:new{
        ui = ctx.ui or resolveActiveUI(),
        document = ctx.document,
        doc_settings = ctx.doc_settings,
        receipt_file = ctx.lastfile,
        data = collectData(ctx),
    })
end

local ReceiptModule = WidgetContainer:extend{ name = "read_receipt" }

function ReceiptModule:init()
end

function ReceiptModule:onShowReadReceipt()
    showReceipt()
    return true
end

local ReaderUI = require("apps/reader/readerui")
local orig_reader_init = ReaderUI.init
function ReaderUI:init()
    orig_reader_init(self)
    self:registerModule("read_receipt", ReceiptModule:new{
        ui = self, view = self.view, document = self.document,
    })
    -- Warm the full-resolution cover cache right away, at a calm moment
    -- (book just opened, no suspend in progress) - see prewarmFullResCover.
    -- Reusing self.document means no second parse of the book file.
    local doc = self.document
    if doc and doc.file then
        UIManager:nextTick(function() pcall(prewarmFullResCover, doc.file, doc) end)
    end
end

local orig_reader_on_close = ReaderUI.onClose
function ReaderUI:onClose(full_refresh)
    -- Re-warm on close too (covers the case where init's prewarm hadn't
    -- finished yet, or the cache got evicted during a long session). Normally
    -- a no-op, since init already warmed it. The document is still live here,
    -- so again no second parse of the file.
    local doc = self.document
    if doc and doc.file then
        pcall(prewarmFullResCover, doc.file, doc)
    end
    prewarmScreensaverCache()
    return orig_reader_on_close(self, full_refresh)
end

-- ---------------------------------------------------------- sleep screen --
-- IMPORTANT: Screensaver.show/setup run during the device suspend sequence.
-- An uncaught Lua error here can crash KOReader entirely (kicking the user
-- back to the native launcher), so every code path below is defensive:
-- it must NEVER throw, and must always leave the screen with *some* fresh,
-- deliberate content (never the stale reading frame).
local ok_ss, Screensaver = pcall(require, "ui/screensaver")
if ok_ss then
    local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    local ImageWidget = require("ui/widget/imagewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local SafeWidget = require("ui/widget/widget")

    -- Absolute last-resort widget: cannot fail, guarantees the screen is
    -- repainted with something deliberate instead of the stale reading frame.
    -- A plain blank screen reads as "the device crashed" to most users, so
    -- we always draw a clear "locked" message on top - this must never rely
    -- on anything that could itself fail (custom fonts, external files...),
    -- only the same built-in text rendering primitives used elsewhere in
    -- this file, and it's wrapped in its own pcall just in case.
    local BlankScreensaverWidget = SafeWidget:extend{}
    function BlankScreensaverWidget:getSize()
        return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    end
    function BlankScreensaverWidget:paintTo(bb, x, y)
        local w, h = Screen:getWidth(), Screen:getHeight()
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
        pcall(function()
            local title = "已锁屏"
            local subtitle = "轻触唤醒"
            local title_face = Font:getFace("cfont", 42)
            local sub_face = Font:getFace("cfont", 24)
            local title_w = RenderText:sizeUtf8Text(0, 1e6, title_face, title, true, false).x
            local sub_w = RenderText:sizeUtf8Text(0, 1e6, sub_face, subtitle, true, false).x
            local cy = y + math.floor(h / 2)
            RenderText:renderUtf8Text(bb, x + math.floor((w - title_w) / 2), cy - 10, title_face, title, true, false, Blitbuffer.COLOR_BLACK)
            RenderText:renderUtf8Text(bb, x + math.floor((w - sub_w) / 2), cy + 50, sub_face, subtitle, true, false, Blitbuffer.COLOR_BLACK)
        end)
    end

    local function receiptContextAvailable()
        local ok, ctx = pcall(resolveReceiptContext)
        if not ok or not ctx then
            return nil
        end
        if ctx.doc_settings then
            local ok2, excluded = pcall(function()
                return ctx.doc_settings:isTrue("exclude_screensaver")
            end)
            if ok2 and excluded then
                return nil
            end
        end
        return ctx
    end

    local function prepareReceiptScreensaver(self)
        if self.screensaver_widget then
            pcall(UIManager.close, UIManager, self.screensaver_widget)
            self.screensaver_widget = nil
        end
        Device.screen_saver_mode = true
        local rotation_mode = Screen:getRotationMode()
        Device.orig_rotation_mode = nil
        local is_odd = false
        if bit then
            is_odd = bit.band(rotation_mode, 1) == 1
        else
            is_odd = (rotation_mode % 2) == 1
        end
        if is_odd then
            Device.orig_rotation_mode = rotation_mode
            Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
        end
    end

    local function showReceiptScreensaverWidget(self, widget_to_show)
        self.screensaver_widget = ScreenSaverWidget:new{
            widget = widget_to_show,
            background = nil,
            covers_fullscreen = true,
        }
        self.screensaver_widget.modal = true
        self.screensaver_widget.dithered = true
        UIManager:show(self.screensaver_widget, "full")
    end

    -- Single place that turns a cached cover blitbuffer into a full-screen
    -- widget, mirroring KOReader's own "cover" screensaver (ui/screensaver.lua)
    -- so covers look exactly like they do natively.
    --
    -- image_disposable = false is CRITICAL and not just a memory nicety:
    -- ImageWidget defaults it to *true*, which means it takes ownership of the
    -- blitbuffer and frees it - both when scaling during _render() and in
    -- free() on close. Since this blitbuffer lives in our own cover_cache and
    -- is reused on every later screensaver, letting the widget free it left
    -- the cache pointing at freed memory, which is what painted the garbled
    -- covers (and risked a segfault on top).
    local function buildCoverWidget(cover_bb)
        if not cover_bb then return nil end
        return ImageWidget:new{
            image = cover_bb,
            image_disposable = false,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            -- scale_factor 0 = "best fit, keep aspect ratio". ImageWidget does
            -- its own centering via offsets when width/height are given, so no
            -- extra container is needed.
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
    end

    local function buildCoverScreensaverWidget(ctx)
        return buildCoverWidget(getCachedCover(ctx.lastfile) or loadCover(ctx.lastfile, { fast = true }))
    end

    local function buildReceiptScreensaverWidget(ctx)
        local ui = ctx.ui or resolveActiveUI()
        local bundle = getScreensaverCache(ctx)
        local receipt = Receipt:new{
            ui = ui,
            document = ctx.document,
            doc_settings = ctx.doc_settings,
            receipt_file = ctx.lastfile,
            data = bundle and bundle.data or collectData(ctx, { for_screensaver = true }),
            prefetched_cover = bundle and bundle.cover,
            is_screensaver = true,
        }

        local background_widget = shouldShowScreensaverCover()
            and buildCoverWidget(bundle and bundle.cover)
            or nil
        if background_widget then
            return OverlapGroup:new{
                dimen = Screen:getSize(),
                background_widget,
                receipt,
            }
        end
        return receipt
    end

    -- Never throws. Always returns a paintable widget (receipt, plain cover,
    -- or a blank fallback), so the caller can safely display *something*.
    local function safeBuildWidget(ctx, reading)
        local ok, widget = pcall(function()
            if reading then
                return buildReceiptScreensaverWidget(ctx)
            end
            return buildCoverScreensaverWidget(ctx)
        end)
        if ok and widget then
            return widget
        end
        if not ok then
            logger.warn("read-receipt: screensaver widget build failed:", tostring(widget))
        end

        -- Secondary fallback: whatever cover we already have cached, full-screen.
        local ok2, cover_bb = pcall(getCachedCover, ctx.lastfile)
        if ok2 and cover_bb then
            local ok3, w = pcall(buildCoverWidget, cover_bb)
            if ok3 and w then
                return w
            end
        end

        -- Last resort: guaranteed-safe blank widget. Never leaves the stale frame.
        local ok4, w = pcall(function() return BlankScreensaverWidget:new{} end)
        if ok4 and w then
            return w
        end
        return nil
    end

    local orig_screensaver_show = Screensaver.show
    Screensaver.show = function(self)
        if self.screensaver_type ~= "read_receipt" then
            return orig_screensaver_show(self)
        end

        local ok, err = pcall(function()
            local ctx = receiptContextAvailable()
            if not ctx then
                error("no-context")
            end
            prepareReceiptScreensaver(self)
            local widget = safeBuildWidget(ctx, isActivelyReading())
            if not widget then
                error("no-widget")
            end
            showReceiptScreensaverWidget(self, widget)
        end)

        if not ok then
            logger.warn("read-receipt: screensaver show failed, using blank fallback:", tostring(err))
            -- Do NOT delegate to orig_screensaver_show here: native branches
            -- expect fields (self.image, self.image_file, ...) that our setup
            -- never populates, and some native types (e.g. "disable") simply
            -- return without painting anything, which would recreate the
            -- exact "stale frame" bug we're trying to avoid. Paint our own
            -- guaranteed-safe blank widget instead.
            local ok2 = pcall(function()
                prepareReceiptScreensaver(self)
                showReceiptScreensaverWidget(self, BlankScreensaverWidget:new{})
            end)
            if not ok2 then
                logger.err("read-receipt: blank fallback screensaver also failed, leaving screen as-is")
            end
        end
    end

    local orig_setup = Screensaver.setup
    Screensaver.setup = function(self, event, event_message)
        orig_setup(self, event, event_message)
        -- NOTE: We deliberately never fall back to KOReader's "random_image"
        -- type here - that wasn't requested and would pull in an unrelated
        -- picture from a folder the user never configured for this. If
        -- anything is unavailable or errors out, self.screensaver_type stays
        -- "read_receipt" and Screensaver.show's own hardened fallback chain
        -- (cover -> plain white flash) takes over - never a random image.
        pcall(function()
            if G_reader_settings:readSetting("screensaver_type") ~= "read_receipt" then
                return
            end
            self.show_message = false
            local ctx = receiptContextAvailable()
            if not ctx then
                return
            end
            -- Keep prewarming cheap: only actively-reading sessions build the
            -- full receipt bundle; otherwise we only warm the cover cache so
            -- the lock-screen delay stays short.
            if isActivelyReading() then
                pcall(buildScreensaverCache, ctx)
            else
                prewarmFullResCover(ctx.lastfile)
            end
        end)
    end
end

_G.__readingreceipt_show = showReceipt

logger.info("readingreceipt: receipt module loaded")