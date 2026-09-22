local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Event = require("ui/event")
local Dispatcher = require("dispatcher")
local logger = require("logger")
local _ = require("gettext")

local ReadingReceipt = WidgetContainer:extend{
    name = "readingreceipt",
    is_doc_only = false,
}

local function pluginRoot()
    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("^(.*[/\\])") or "./"
end

local function loadCoreModules()
    if rawget(_G, "__readingreceipt_plugin_loaded") then
        return true
    end

    local root = pluginRoot()
    local ok, err = pcall(dofile, root .. "receipt.lua")
    if not ok then
        logger.err("readingreceipt: failed to load receipt module:", tostring(err))
        return false, err
    end

    ok, err = pcall(dofile, root .. "reading_insights_popup.lua")
    if not ok then
        rawset(_G, "__readingreceipt_insights_popup_loaded", nil)
        logger.warn("readingreceipt: failed to load insights popup:", tostring(err))
    elseif not rawget(_G, "__readingreceipt_show_insights") then
        rawset(_G, "__readingreceipt_insights_popup_loaded", nil)
        logger.warn("readingreceipt: insights popup loaded without entry point")
    end

    _G.__readingreceipt_plugin_loaded = true
    logger.info("readingreceipt: core loaded")
    return true
end

local function showMessage(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function dispatch(ui, event_name)
    if not ui or not ui.handleEvent then
        return false
    end
    local ok, handled = pcall(function()
        return ui:handleEvent(Event:new(event_name))
    end)
    if not ok then
        logger.warn("readingreceipt: failed to dispatch", event_name, tostring(handled))
        return false
    end
    return handled ~= false
end

local function hasReceiptBookContext()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance and ReaderUI.instance.document then
        return true
    end
    local lastfile = G_reader_settings:readSetting("lastfile")
    if not lastfile then
        return false
    end
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(lastfile, "mode") == "file"
end

local function registerScreensaverMenu()
    local ok, screensaver_menu = pcall(require, "ui/elements/screensaver_menu")
    if not ok or not screensaver_menu then
        return
    end

    for i = #screensaver_menu, 1, -1 do
        if screensaver_menu[i].added_by_readingreceipt_flag then
            table.remove(screensaver_menu, i)
        end
    end

    local insert_at = #screensaver_menu + 1
    local disable_text = _("Leave screen as-is")
    for i, item in ipairs(screensaver_menu) do
        if item.text == disable_text then
            insert_at = i
            break
        end
    end

    table.insert(screensaver_menu, insert_at, {
        text = _("Use reading receipt as screensaver"),
        enabled_func = hasReceiptBookContext,
        checked_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "read_receipt"
        end,
        callback = function()
            G_reader_settings:saveSetting("screensaver_type", "read_receipt")
        end,
        radio = true,
        added_by_readingreceipt_flag = true,
    })
    table.insert(screensaver_menu, insert_at + 1, {
        text = _("Reading receipt settings"),
        enabled_func = function()
            return G_reader_settings:readSetting("screensaver_type") == "read_receipt"
        end,
        sub_item_table = {
            {
                text = _("Show book cover behind receipt"),
                checked_func = function()
                    return not G_reader_settings:isFalse("read_receipt_show_cover")
                end,
                callback = function()
                    if G_reader_settings:isFalse("read_receipt_show_cover") then
                        G_reader_settings:delSetting("read_receipt_show_cover")
                    else
                        G_reader_settings:saveSetting("read_receipt_show_cover", false)
                    end
                end,
            },
        },
        added_by_readingreceipt_flag = true,
    })
end

local function registerActions()
    local ok, err = pcall(function()
        Dispatcher:init()
        Dispatcher:registerAction("readingreceipt_show_receipt", {
            category = "none",
            event = "ShowReadReceipt",
            title = _("Reading Receipt"),
            reader = true,
            general = true,
        })
        Dispatcher:registerAction("readingreceipt_enable_screensaver", {
            category = "none",
            event = "EnableReadingReceiptScreensaver",
            title = _("Use Reading Receipt as suspend screen"),
            reader = true,
            general = true,
        })
    end)
    if not ok then
        logger.warn("readingreceipt: failed to register dispatcher actions:", tostring(err))
    end
end

function ReadingReceipt:init()
    local ok, err = loadCoreModules()
    if not ok then
        showMessage(_("Reading Receipt failed to load: ") .. tostring(err))
        return
    end

    registerActions()
    local ok_menu, err_menu = pcall(registerScreensaverMenu)
    if not ok_menu then
        logger.warn("readingreceipt: failed to register screensaver menu:", tostring(err_menu))
    end

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function ReadingReceipt:onShowReadReceipt()
    if not hasReceiptBookContext() then
        showMessage(_("Open a document before showing Reading Receipt."))
        return true
    end
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance and ReaderUI.instance.handleEvent then
        return dispatch(ReaderUI.instance, "ShowReadReceipt")
    end
    local show = rawget(_G, "__readingreceipt_show")
    if show then
        show()
        return true
    end
    showMessage(_("Reading Receipt failed to load."))
    return true
end

function ReadingReceipt:onEnableReadingReceiptScreensaver()
    G_reader_settings:saveSetting("screensaver_type", "read_receipt")
    showMessage(_("Reading Receipt will be used as the suspend screen."))
    return true
end

function ReadingReceipt:addToMainMenu(menu_items)
    menu_items.readingreceipt = {
        text = _("Reading Receipt"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show reading receipt"),
                enabled_func = function()
                    return hasReceiptBookContext()
                end,
                callback = function()
                    self:onShowReadReceipt()
                end,
            },
            {
                text = _("Use as suspend screen"),
                checked_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "read_receipt"
                end,
                callback = function()
                    self:onEnableReadingReceiptScreensaver()
                end,
            },
            {
                text = _("Show book cover behind receipt"),
                checked_func = function()
                    return not G_reader_settings:isFalse("read_receipt_show_cover")
                end,
                callback = function()
                    if G_reader_settings:isFalse("read_receipt_show_cover") then
                        G_reader_settings:delSetting("read_receipt_show_cover")
                    else
                        G_reader_settings:saveSetting("read_receipt_show_cover", false)
                    end
                end,
            },
            {
                text = _("SimpleUI integration"),
                keep_menu_open = true,
                callback = function()
                    showMessage(_("In SimpleUI, add the Reading Receipt action to Quick Actions or the Navigation Bar."))
                end,
            },
        },
    }
end

return ReadingReceipt
