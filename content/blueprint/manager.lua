local gettext = _
local tr = require "blueprint_demo::/blueprint/i18n.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local library = require "blueprint_demo::/blueprint/library.lua"
local core = require "blueprint_demo::/blueprint/core.lua"
local gameCtx
local windowId = "blueprint.template.manager"
local function sized(width, height)
    return {styleSheet = styleutil.makeStyle {size = {width, height}}}
end
local function textButton(label, onClick, width)
    return builtin.Button {meta = width and sized(width, 32) or nil,
        content = builtin.TextView {text = label}, onClick = onClick}
end
local function spacer(width, height)
    local meta = sized(width, height)
    meta.mouseTransparent = true
    return builtin.Component {meta = meta, layout = builtin.BoxLayout {children = {}}}
end
local function close()
    api.gui.byId.setVisible(windowId, false)
end
local function descriptionText(text)
    -- 转义用户文字，防止富文本把描述中的尖括号等内容当成标记。
    return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br>"))
end
local categoryLabels = {
    rail_buildings = gettext("BLUEPRINT_RAIL_BUILDINGS"), road_buildings = gettext("BLUEPRINT_ROAD_BUILDINGS"),
    water_buildings = gettext("BLUEPRINT_WATER_BUILDINGS"), air_buildings = gettext("BLUEPRINT_AIR_BUILDINGS"), warehouses = gettext("BLUEPRINT_WAREHOUSES"),
}

local exchangeId = "blueprint.template.exchange"
local exchangeRequest = {}
local function snapshotDetails(snapshot)
    local count = 0
    for _ in pairs(snapshot.modules) do count = count + 1 end
    return tr("BLUEPRINT_DETAILS", {categories = categoryLabels[snapshot.categories[1]] or snapshot.categories[1], count = count})
end

local ExchangeWindow = react.RegisterWrapperRecipe("BlueprintTemplateExchange", builtin.Window, function()
    local request = react.useState(exchangeRequest)
    local input = react.useState("")
    local feedback = react.useState("")
    react.onEvent("blueprintExchangeRequested", function(_, payload)
        request:set(payload); input:set(""); feedback:set("")
    end)
    local sharing = request:old().kind == "share"
    local function dismiss() api.gui.byId.setVisible(exchangeId, false) end
    local function inspect(text)
        input:set(text)
        if text == "" then feedback:set(""); return end
        local ok, snapshot, missing = pcall(library.previewImport, text)
        if ok then
            feedback:set(snapshot.name .. "\n" .. snapshotDetails(snapshot)
                .. (#missing > 0 and gettext("BLUEPRINT_IMPORT_MISSING") or ""))
        else feedback:set(gettext("BLUEPRINT_IMPORT_INVALID")) end
    end
    local controls = {textButton(gettext(sharing and "BLUEPRINT_CLOSE" or "BLUEPRINT_CANCEL"), dismiss)}
    if not sharing then
        controls[#controls + 1] = textButton(gettext("BLUEPRINT_IMPORT"), function()
            local ok, result = pcall(library.importTemplate, input:old())
            if not ok then feedback:set(tr("BLUEPRINT_OP_FAILED", {error = result})); return end
            react.fireEvent(nil, "blueprintLibraryChanged", {message = gettext("BLUEPRINT_IMPORTED"), resetFilter = true})
            dismiss()
        end)
    end
    return builtin.Window {
        id = exchangeId, title = gettext(sharing and "BLUEPRINT_SHARE_TITLE" or "BLUEPRINT_IMPORT_TITLE"),
        initialVisible = true, closable = true, movable = true, onClose = dismiss,
        content = builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = {
            builtin.TextView {meta = sized(560, 30), text = sharing and request:old().name or gettext("BLUEPRINT_IMPORT_HINT")},
            builtin.TextInputField {
                meta = sized(560, 110), maxLength = 2 * 1024 * 1024,
                value = sharing and request:old().text or input:old(),
                placeholderText = gettext("BLUEPRINT_IMPORT_PLACEHOLDER"),
                focusOnStartEditing = true, deselectOnFocusLost = false,
                onTyping = sharing and function() end or inspect,
                onValueChange = sharing and function() end or inspect,
            },
            builtin.TextView {meta = sized(560, -1), text = sharing and gettext("BLUEPRINT_SHARE_COPY_HINT") or feedback:old()},
            builtin.TextView {meta = sized(560, -1), text = sharing and gettext("BLUEPRINT_SHARE_DEPS") or ""},
            builtin.Component {meta = sized(560, 36), layout = builtin.BoxLayout {
                orientation = builtin.type.Orientation.Horizontal, children = {
                    spacer(360, 36),
                    builtin.Component {meta = sized(200, 36), layout = builtin.BoxLayout {
                        orientation = builtin.type.Orientation.Horizontal, children = controls}},
                },
            }},
        }},
    }
end)

local function openExchange(kind, id)
    local request = {kind = kind}
    if kind == "share" then request.text, request.name = library.exportTemplate(id) end
    exchangeRequest = request
    local windowApi = gameCtx.windowContainer:get():getApi()
    windowApi.addSingletonWindow(ExchangeWindow, {})
    react.fireEvent(nil, "blueprintExchangeRequested", request)
    api.gui.byId.setVisible(exchangeId, true)
    windowApi.moveSingletonWindowToFront(ExchangeWindow)
end

local ManagerWindow = react.RegisterWrapperRecipe("BlueprintTemplateManager", builtin.Window, function(_params)
    local query = react.useState("")
    local editing = react.useState(nil)
    local draft = react.useState("")
    local descriptionDraft = react.useState("")
    local deleting = react.useState(nil)
    local message = react.useState("")
    local change = react.useState(0)
    local category = react.useState("")
    local function run(fn, success)
        local ok, failure = pcall(fn)
        message:set(ok and success or (tr("BLUEPRINT_OP_FAILED", {error = failure})))
        if ok then
            editing:set(nil)
            deleting:set(nil)
            change:set(change:old() + 1)
        end
    end
    react.onEvent("blueprintLibraryChanged", function(_, payload)
        if payload and payload.message then message:set(payload.message) end
        if payload and payload.resetFilter then category:set(""); query:set("") end
        change:set(change:old() + 1)
    end)
    react.onStep(function()
        local ok, event = pcall(library.pollSync)
        if ok and event then react.fireEvent(nil, "blueprintLibraryChanged", event) end
    end)
    local ok, templates = pcall(library.list, query:old())
    local status = message:old()
    if not ok then status = tr("BLUEPRINT_LIBRARY_READ_FAILED", {error = templates}); templates = {} end
    local rows = {}
    local visibleCount = 0
    for _, snapshot in ipairs(templates) do
        local id = snapshot.id
        local sourceId = api.res.constructionRep.find(snapshot.constructionFileName)
        local categories = snapshot.categories
        if sourceId >= 0 then
            local parsed = core.menuCategories(api.res.constructionRep.get(sourceId), snapshot.constructionFileName)
            if #parsed > 0 then categories = parsed end
        end
        local matches = category:old() == ""
        for _, value in ipairs(categories) do if value == category:old() then matches = true end end
        if matches then
        visibleCount = visibleCount + 1
        local labels, count = {}, 0
        for _, category in ipairs(categories) do labels[#labels + 1] = categoryLabels[category] or category end
        for _ in pairs(snapshot.modules) do count = count + 1 end
        local details = tr("BLUEPRINT_DETAILS", {categories = table.concat(labels, " / "), count = count})
        local missing = core.missingResources(snapshot, api.res)
        local _, preview = core.templateImages(snapshot)
        if #missing > 0 then details = details .. gettext("BLUEPRINT_MISSING_DEPS") end
        local controls
        local nameContent = builtin.TextView {meta = sized(400, 28), text = snapshot.name, tooltipWhenClipped = snapshot.name}
        local descriptionContent = builtin.RichTextView {
            meta = sized(400, -1), isHtml = true,
            text = descriptionText(snapshot.description and snapshot.description ~= "" and snapshot.description or gettext("BLUEPRINT_NO_DESCRIPTION")),
        }
        if editing:old() == id then
            nameContent = builtin.TextInputField {
                    meta = sized(400, 32), value = draft:old(), maxLength = 128,
                    onTyping = function(value) draft:set(value) end,
                    onValueChange = function(value) draft:set(value) end,
            }
            descriptionContent = builtin.TextInputField {
                meta = sized(400, 32), value = descriptionDraft:old(), maxLength = 1024,
                placeholderText = gettext("BLUEPRINT_DESCRIPTION_PLACEHOLDER"),
                onTyping = function(value) descriptionDraft:set(value) end,
                onValueChange = function(value) descriptionDraft:set(value) end,
            }
            controls = {
                textButton(gettext("BLUEPRINT_SAVE_METADATA"), function() run(function() library.updateMetadata(id, draft:old(), descriptionDraft:old()) end, gettext("BLUEPRINT_METADATA_SAVED")) end),
                textButton(gettext("BLUEPRINT_CANCEL"), function() editing:set(nil) end),
            }
        elseif deleting:old() == id then
            controls = {
                builtin.TextView {text = gettext("BLUEPRINT_DELETE_CONFIRM")},
                textButton(gettext("BLUEPRINT_DELETE_YES"), function() run(function() library.delete(id) end, gettext("BLUEPRINT_DELETED")) end),
                textButton(gettext("BLUEPRINT_CANCEL"), function() deleting:set(nil) end),
            }
        else
            controls = {
                textButton(gettext("BLUEPRINT_EDIT"), function() editing:set(id); draft:set(snapshot.name); descriptionDraft:set(snapshot.description or ""); deleting:set(nil) end),
                textButton(gettext("BLUEPRINT_COPY"), function() run(function() library.duplicate(id) end, gettext("BLUEPRINT_COPIED")) end),
                textButton(gettext("BLUEPRINT_DELETE"), function() deleting:set(id); editing:set(nil) end),
                textButton(gettext("BLUEPRINT_SHARE"), function()
                    local success, failure = pcall(openExchange, "share", id)
                    if not success then message:set(tr("BLUEPRINT_OP_FAILED", {error = failure})) end
                end),
            }
        end
        local rowMeta = sized(950, -1)
        rowMeta.localKey = "template-row-" .. tostring(id)
        -- 用互不重叠的固定列分配整行宽度，按钮只在最右列内对齐。
        rows[#rows + 1] = builtin.BoxLayout {
            meta = rowMeta,
            orientation = builtin.type.Orientation.Horizontal,
            children = {
                builtin.ImageView {
                    meta = sized(130, 90),
                    path = sourceId >= 0 and preview or "::/warehouses/icons/wh_goods_preview.tga",
                    scaling = builtin.type.ImageViewScaling.AutoFit,
                },
                builtin.Component {
                    meta = sized(420, -1),
                    layout = builtin.BoxLayout {
                        orientation = builtin.type.Orientation.Vertical,
                        children = {
                            nameContent,
                            descriptionContent,
                            builtin.TextView {meta = sized(400, 28), text = details, tooltipWhenClipped = details},
                        },
                    },
                },
                builtin.Component {
                    meta = sized(400, 90),
                    layout = builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = {
                        spacer(120, 90),
                        builtin.Component {meta = sized(280, 90), layout = builtin.BoxLayout {
                            orientation = builtin.type.Orientation.Horizontal, children = controls}},
                    }},
                },
            },
        }
        end
    end
    if #rows == 0 then
        rows[1] = builtin.TextView {text = #templates == 0 and query:old() == "" and gettext("BLUEPRINT_EMPTY_LIBRARY") or gettext("BLUEPRINT_NO_MATCHES")}
    end
    local filters = {}
    local selectedFilter = 1
    local filterOptions = {{"", "BLUEPRINT_FILTER_ALL"}, {"rail_buildings", "BLUEPRINT_FILTER_RAIL"},
        {"road_buildings", "BLUEPRINT_FILTER_ROAD"}, {"water_buildings", "BLUEPRINT_FILTER_WATER"},
        {"air_buildings", "BLUEPRINT_FILTER_AIR"}, {"warehouses", "BLUEPRINT_FILTER_WAREHOUSE"}}
    for index, option in ipairs(filterOptions) do
        local key, label = option[1], gettext(option[2])
        if category:old() == key then selectedFilter = index end
        filters[#filters + 1] = {
            meta = sized(85, 32),
            content = builtin.TextView {text = label},
        }
    end
    local categoryFilter = builtin.ToggleButtonGroup {
        buttons = filters, selected = selectedFilter, layout = "Horizontal",
        onValueChange = function(index)
            -- 原生 builtin.lua 使用 ipairs 的 1-based 索引；0 是无效值。
            local option = filterOptions[index]
            if option then category:set(option[1]); editing:set(nil); deleting:set(nil) end
        end,
    }
    return builtin.Window {
        id = windowId, title = gettext("BLUEPRINT_MANAGER_TITLE"),
        initialVisible = true, closable = true, movable = true,
        onClose = close,
        content = builtin.BoxLayout {
            orientation = builtin.type.Orientation.Vertical,
            children = {
                builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = {
                    builtin.Component {meta = sized(950, 34), layout = builtin.BoxLayout {
                        orientation = builtin.type.Orientation.Horizontal,
                        children = {spacer(830, 34),
                            textButton(gettext("BLUEPRINT_IMPORT_TITLE"), function() openExchange("import") end, 120)},
                    }},
                    builtin.TextInputField {
                        meta = sized(950, 34), value = query:old(), placeholderText = gettext("BLUEPRINT_SEARCH"),
                        onTyping = function(value) query:set(value) end,
                        onValueChange = function(value) query:set(value) end,
                        onCancel = function() query:set("") end,
                    },
                    builtin.Component {
                        meta = sized(950, 36),
                        layout = builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = {
                            builtin.Component {meta = sized(600, 36), layout = builtin.BoxLayout {
                                orientation = builtin.type.Orientation.Horizontal, children = {categoryFilter}}},
                            spacer(250, 36),
                            builtin.TextView {meta = sized(100, 36), text = tr("BLUEPRINT_COUNT", {count = visibleCount})},
                        }},
                    },
                }},
                builtin.ScrollArea {
                    meta = sized(950, 440),
                    horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
                    verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
                    content = builtin.Component {
                        layout = builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = rows},
                    },
                },
                builtin.TextView {text = status},
            },
        },
    }
end)

local function open(context)
        gameCtx = context or gameCtx
        assert(gameCtx and gameCtx.windowContainer, gettext("BLUEPRINT_NO_WINDOW_CONTEXT"))
        local windowApi = gameCtx.windowContainer:get():getApi()
        windowApi.addSingletonWindow(ManagerWindow, {})
        api.gui.byId.setVisible(windowId, true)
        windowApi.moveSingletonWindowToFront(ManagerWindow)
end

local installed = false
return {
    open = open,
    setContext = function(context) gameCtx = context end,
    install = function()
        if installed then return end
        installed = true
        local closeButtons, closeChildren = {}, {}
        local originalButton, originalChild, originalLayout = builtin.Button, builtin.FloatingLayoutChild, builtin.FloatingLayout
        builtin.Button = function(params, ...)
            local node = originalButton(params, ...)
            if type(params) == "table" and params.meta and params.meta.class == "fake-builtin-window-close-button" then
                closeButtons[node] = true
            end
            return node
        end
        builtin.FloatingLayoutChild = function(params, ...)
            local node = originalChild(params, ...)
            if type(params) == "table" and closeButtons[params.item] then
                closeButtons[params.item] = nil
                closeChildren[node] = true
            end
            return node
        end
        builtin.FloatingLayout = function(params, ...)
            local closeChild
            if type(params) == "table" then
                for _, child in pairs(params.children or {}) do
                    if closeChildren[child] then
                        closeChildren[child] = nil
                        closeChild = child
                    end
                end
            end
            if not closeChild then return originalLayout(params, ...) end
            local copy = {}
            for key, value in pairs(params) do copy[key] = value end
            copy.children = {}
            for _, child in ipairs(params.children) do
                if child ~= closeChild then copy.children[#copy.children + 1] = child end
            end
            local spacerMeta = sized(52, 44)
            spacerMeta.mouseTransparent = true
            copy.children[#copy.children + 1] = originalChild {
                h = 1, v = 0,
                item = builtin.BoxLayout {
                    meta = {mouseTransparent = true},
                    orientation = builtin.type.Orientation.Horizontal,
                    children = {
                        originalButton {content = builtin.TextView {text = gettext("BLUEPRINT_MANAGER")}, onClick = function() open() end},
                        builtin.Component {meta = spacerMeta, layout = builtin.BoxLayout {children = {}}},
                    },
                },
            }
            -- 原生关闭按钮最后绘制，位于入口和透明间距上方，保留它的点击区域。
            copy.children[#copy.children + 1] = closeChild
            return originalLayout(copy, ...)
        end
    end,
}
