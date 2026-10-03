local gettext = _
local tr = require "blueprint_demo::/blueprint/i18n.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local ui = require "blueprint_demo::/blueprint/ui.lua"
local library = require "blueprint_demo::/blueprint/library.lua"
local core = require "blueprint_demo::/blueprint/core.lua"
local gameCtx
local windowId = "blueprint.template.manager"
local function close()
    api.gui.byId.setVisible(windowId, false)
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
    local shareInputRevision = react.useState(0)
    react.onEvent("blueprintExchangeRequested", function(_, payload)
        request:set(payload); input:set(""); feedback:set("")
        shareInputRevision:set(shareInputRevision:old() + 1)
    end)
    local sharing = request:old().kind == "share"
    local function restoreShareInput()
        shareInputRevision:set(shareInputRevision:old() + 1)
    end
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
    local controls = {ui.textButton(gettext(sharing and "BLUEPRINT_CLOSE" or "BLUEPRINT_CANCEL"), dismiss)}
    if not sharing then
        controls[#controls + 1] = ui.textButton(gettext("BLUEPRINT_IMPORT"), function()
            local ok, result = pcall(library.importTemplate, input:old())
            if not ok then feedback:set(tr("BLUEPRINT_OP_FAILED", {error = result})); return end
            react.fireEvent(nil, "blueprintLibraryChanged", {message = gettext("BLUEPRINT_IMPORTED"), resetFilter = true})
            dismiss()
        end)
    end
    local exchangeInput = builtin.TextInputField {
        meta = ui.layoutMeta(544, 24, "exchange-input", nil, {4, 8, 4, 8},
            sharing and "blueprint-manager-exchange-input, blueprint-manager-share-input, font-scale-body, no-clear-button"
                or "blueprint-manager-exchange-input, font-scale-body"),
        maxLength = 2 * 1024 * 1024,
        value = sharing and request:old().text or input:old(),
        placeholderText = sharing and "" or gettext("BLUEPRINT_IMPORT_PLACEHOLDER"),
        focusOnStartEditing = true, deselectOnFocusLost = false,
        onTyping = sharing and restoreShareInput or inspect,
        onValueChange = sharing and restoreShareInput or inspect,
        onEditingModeChange = sharing and function(editing)
            if not editing then restoreShareInput() end
        end or nil,
        onCancel = sharing and restoreShareInput or nil,
    }
    local exchangeField = exchangeInput
    if sharing then
        -- Keep the complete payload in the native copyable field. Render a bounded
        -- preview separately so long single-line payloads cannot hide all glyphs.
        local payload = request:old().text or ""
        local previewMeta = ui.layoutMeta(544, 24, "exchange-copy-preview", {color = {1, 1, 1, 1}, fontSize = 14}, {4, 8, 4, 8}, "font-scale-body")
        previewMeta.mouseTransparent = true
        exchangeField = ui.component(builtin.FloatingLayout {
            children = {
                builtin.FloatingLayoutChild {h = -1, v = -1, item = exchangeInput},
                builtin.FloatingLayoutChild {h = -1, v = -1,
                    item = ui.text(payload:sub(1, 56) .. (#payload > 56 and "…" or ""), previewMeta)},
            },
        }, ui.layoutMeta(560, 32, "exchange-copy-field-" .. tostring(shareInputRevision:old()), {margin = {0, 0, 8, 0}}))
    end
    return builtin.Window {
        id = exchangeId, title = gettext(sharing and "BLUEPRINT_SHARE_TITLE" or "BLUEPRINT_IMPORT_TITLE"),
        initialVisible = true, closable = true, movable = true, onClose = dismiss,
        content = ui.column({
            ui.text(sharing and request:old().name or gettext("BLUEPRINT_IMPORT_HINT"), ui.sized(560, 30)),
            exchangeField,
            ui.text(sharing and gettext("BLUEPRINT_SHARE_COPY_HINT") or feedback:old(), ui.sized(560, -1)),
            ui.text(sharing and gettext("BLUEPRINT_SHARE_DEPS") or "", ui.sized(560, -1)),
            ui.component(ui.row({
                    ui.spacer(360, 36),
                    ui.component(ui.row(controls), ui.sized(200, 36)),
                }), ui.sized(560, 36)),
        }),
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
    local deletingAll = react.useState(false)
    local message = react.useState("")
    local change = react.useState(0)
    local category = react.useState("")
    local function run(fn, success)
        local ok, failure = pcall(fn)
        message:set(ok and success or (tr("BLUEPRINT_OP_FAILED", {error = failure})))
        if ok then
            deletingAll:set(false)
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
    local isOther = category:old() == "developer_options"
    local rows = {}
    local visibleCount = 0
    for _, snapshot in ipairs(isOther and {} or templates) do
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
        local nameContent = ui.text(snapshot.name, ui.layoutMeta(468, 28, "template-name", nil, nil, "font-scale-body"), snapshot.name)
        local descriptionContent = ui.richText(snapshot.description and snapshot.description ~= "" and snapshot.description or gettext("BLUEPRINT_NO_DESCRIPTION"),
            ui.layoutMeta(468, -1, "template-description", nil, nil, "blueprint-manager-description"))
        if editing:old() == id then
            nameContent = builtin.TextInputField {
                    meta = ui.layoutMeta(452, 24, "template-name", nil, {4, 8, 4, 8}), value = draft:old(), maxLength = 128,
                    onTyping = function(value) draft:set(value) end,
                    onValueChange = function(value) draft:set(value) end,
            }
            descriptionContent = builtin.TextInputField {
                meta = ui.layoutMeta(452, 24, "template-description", nil, {4, 8, 4, 8}), value = descriptionDraft:old(), maxLength = 1024,
                placeholderText = gettext("BLUEPRINT_DESCRIPTION_PLACEHOLDER"),
                onTyping = function(value) descriptionDraft:set(value) end,
                onValueChange = function(value) descriptionDraft:set(value) end,
            }
            controls = {
                ui.managerButton(gettext("BLUEPRINT_SAVE_METADATA"), function() run(function() library.updateMetadata(id, draft:old(), descriptionDraft:old()) end, gettext("BLUEPRINT_METADATA_SAVED")) end, "template-save", 112, true),
                ui.managerButton(gettext("BLUEPRINT_CANCEL"), function() editing:set(nil) end, "template-cancel", 112),
            }
        elseif deleting:old() == id then
            controls = {
                ui.managerButton(gettext("BLUEPRINT_DELETE_YES"), function() run(function() library.delete(id) end, gettext("BLUEPRINT_DELETED")) end, "template-confirm-delete", 136),
                ui.managerButton(gettext("BLUEPRINT_CANCEL"), function() deleting:set(nil) end, "template-cancel", 104),
            }
        else
            controls = {
                ui.managerButton(gettext("BLUEPRINT_EDIT"), function() editing:set(id); draft:set(snapshot.name); descriptionDraft:set(snapshot.description or ""); deleting:set(nil) end, "template-edit"),
                ui.managerButton(gettext("BLUEPRINT_COPY"), function() run(function() library.duplicate(id) end, gettext("BLUEPRINT_COPIED")) end, "template-copy"),
                ui.managerButton(gettext("BLUEPRINT_DELETE"), function() deleting:set(id); editing:set(nil) end, "template-delete"),
                ui.managerButton(gettext("BLUEPRINT_SHARE"), function()
                    local success, failure = pcall(openExchange, "share", id)
                    if not success then message:set(tr("BLUEPRINT_OP_FAILED", {error = failure})) end
                end, "template-share"),
            }
        end
        local actionChildren = {}
        if deleting:old() == id then
            actionChildren[#actionChildren + 1] = ui.text(gettext("BLUEPRINT_DELETE_CONFIRM"),
                ui.layoutMeta(280, 24, "template-delete-question", nil, nil, "font-scale-body"))
            actionChildren[#actionChildren + 1] = ui.spacer(0, 8)
        else actionChildren[#actionChildren + 1] = ui.spacer(0, 29) end
        local actionRow = {ui.spacer(editing:old() == id and 16 or 0, 0)}
        actionRow[#actionRow + 1] = ui.row(controls, 8)
        actionChildren[#actionChildren + 1] = ui.row(actionRow)
        -- Native vertical scrollbar is 8 units; budget 16 including breathing room.
        -- 950 viewport - 16 scrollbar budget - 24 padding = 910 content.
        -- 130 preview + 16 gap + 468 text + 16 gap + 280 right-aligned actions.
        rows[#rows + 1] = ui.card(ui.row({
                builtin.ImageView {
                    meta = ui.sized(130, 90),
                    path = sourceId >= 0 and preview or "::/warehouses/icons/wh_goods_preview.tga",
                    scaling = builtin.type.ImageViewScaling.AutoFit,
                },
                ui.spacer(16, 0),
                ui.component(ui.column({
                            nameContent,
                            descriptionContent,
                            ui.text(details, ui.layoutMeta(468, 28, "template-details", {color = ui.theme.mutedText}, nil, "font-scale-annotation"), details),
                        }, 4), ui.sized(468, -1)),
                ui.spacer(16, 0),
                ui.component(ui.column(actionChildren), ui.layoutMeta(280, 90, "template-actions")),
            }), 910, -1, "template-row-" .. tostring(id))
        end
    end
    if isOther then
        local controls
        if deletingAll:old() then
            controls = {
                ui.managerButton(gettext("BLUEPRINT_DELETE_ALL_CONFIRM"), function()
                    run(library.deleteAll, gettext("BLUEPRINT_ALL_DELETED"))
                end, "developer-confirm-delete-all", 144),
                ui.managerButton(gettext("BLUEPRINT_CANCEL"), function() deletingAll:set(false) end,
                    "developer-cancel-delete-all", 96),
            }
        else
            controls = {ui.managerButton(gettext("BLUEPRINT_DELETE_ALL"), function()
                if #library.list() == 0 then message:set(gettext("BLUEPRINT_EMPTY_LIBRARY")); return end
                deletingAll:set(true)
            end, "developer-delete-all", 144)}
        end
        rows[1] = ui.card(ui.column({
            ui.text(gettext("BLUEPRINT_DELETE_ALL"), ui.layoutMeta(910, 28, "developer-delete-all-title", nil, nil, "font-scale-body")),
            ui.text(gettext("BLUEPRINT_DELETE_ALL_HINT"), ui.layoutMeta(910, -1, "developer-delete-all-hint", nil, nil, "font-scale-body")),
            ui.text(deletingAll:old() and tr("BLUEPRINT_DELETE_ALL_QUESTION", {count = #library.list()}) or "",
                ui.layoutMeta(910, 28, "developer-delete-all-question", nil, nil, "font-scale-body")),
            ui.row(controls, 8),
        }, 8), 910, -1, "developer-delete-all-card")
    elseif #rows == 0 then
        rows[1] = ui.text(#templates == 0 and query:old() == "" and gettext("BLUEPRINT_EMPTY_LIBRARY") or gettext("BLUEPRINT_NO_MATCHES"),
            ui.layoutMeta(910, 40, "template-empty", nil, {12, 12, 12, 12}, "font-scale-body"))
    end
    local filters = {}
    local selectedFilter = 1
    local filterOptions = {{"", "BLUEPRINT_FILTER_ALL"}, {"rail_buildings", "BLUEPRINT_FILTER_RAIL"},
        {"road_buildings", "BLUEPRINT_FILTER_ROAD"}, {"water_buildings", "BLUEPRINT_FILTER_WATER"},
        {"air_buildings", "BLUEPRINT_FILTER_AIR"}, {"warehouses", "BLUEPRINT_FILTER_WAREHOUSE"},
        {"developer_options", "BLUEPRINT_FILTER_OTHER"}}
    for index, option in ipairs(filterOptions) do
        local key, label = option[1], gettext(option[2])
        if category:old() == key then selectedFilter = index end
        filters[#filters + 1] = {
            meta = ui.layoutMeta(index == #filterOptions and 101 or 69, 24, "template-filter-" .. index, nil, {4, 8, 4, 8}),
            content = ui.text(label, {class = "font-scale-body"}),
        }
    end
    local categoryFilter = builtin.ToggleButtonGroup {
        meta = {localKey = "template-filters"},
        buttons = filters, selected = selectedFilter, layout = "Horizontal",
        onValueChange = function(index)
            -- 原生 builtin.lua 使用 ipairs 的 1-based 索引；0 是无效值。
            local option = filterOptions[index]
            if option then category:set(option[1]); editing:set(nil); deleting:set(nil); deletingAll:set(false) end
        end,
    }
    return builtin.Window {
        id = windowId, title = gettext("BLUEPRINT_MANAGER_TITLE"),
        initialVisible = true, closable = true, movable = true,
        onClose = function() deletingAll:set(false); close() end,
        content = ui.column({
                ui.column({
                    ui.component(ui.row({ui.spacer(786, 32),
                            ui.managerButton(gettext("BLUEPRINT_IMPORT_TITLE"), function() openExchange("import") end, "manager-import", 120, true),
                            ui.spacer(28, 32)}), ui.layoutMeta(950, 32, "manager-toolbar")),
                    builtin.TextInputField {
                        meta = ui.layoutMeta(934, 24, "manager-search", nil, {4, 8, 4, 8}), value = query:old(), placeholderText = gettext("BLUEPRINT_SEARCH"),
                        onTyping = function(value) query:set(value) end,
                        onValueChange = function(value) query:set(value) end,
                        onCancel = function() query:set("") end,
                    },
                    ui.component(ui.row({
                            ui.component(ui.row({categoryFilter}), ui.sized(685, 32)),
                            ui.spacer(137, 32),
                            ui.text(isOther and gettext("BLUEPRINT_DEVELOPER_OPTIONS") or tr("BLUEPRINT_COUNT", {count = visibleCount}), ui.layoutMeta(100, 32, "manager-count", nil, nil, "blueprint-manager-count, font-scale-annotation")),
                            ui.spacer(28, 32),
                        }), ui.layoutMeta(950, 32, "manager-filter-row")),
                }, 8),
                builtin.ScrollArea {
                    meta = ui.layoutMeta(950, 440, "manager-list"),
                    horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
                    verticalPolicy = builtin.type.ScrollBarPolicy.AsNeededButAlwaysReserveSpace,
                    content = ui.component(ui.column(rows, 12)),
                },
                ui.text(status, ui.layoutMeta(950, 28, "manager-status", nil, nil, "font-scale-annotation")),
            }, 12),
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
            local spacerMeta = ui.sized(52, 44)
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
