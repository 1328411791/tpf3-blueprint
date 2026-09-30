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
local function textButton(label, onClick)
    return builtin.Button {content = builtin.TextView {text = label}, onClick = onClick}
end
local function close()
    api.gui.byId.setVisible(windowId, false)
end
local function reveal(resName)
    close()
    api.gui.byId.setVisible("menu.construction.react", true)
    react.fireEvent(nil, "constructionMenuActive", {active = true})
    react.fireEvent(nil, "constructionMenuSelectTabForConstruction", {resName = resName})
end
local categoryLabels = {
    rail_buildings = gettext("BLUEPRINT_RAIL_BUILDINGS"), road_buildings = gettext("BLUEPRINT_ROAD_BUILDINGS"),
    water_buildings = gettext("BLUEPRINT_WATER_BUILDINGS"), air_buildings = gettext("BLUEPRINT_AIR_BUILDINGS"), warehouses = gettext("BLUEPRINT_WAREHOUSES"),
}

local ManagerWindow = react.RegisterWrapperRecipe("BlueprintTemplateManager", builtin.Window, function(_params)
    local query = react.useState("")
    local editing = react.useState(nil)
    local draft = react.useState("")
    local deleting = react.useState(nil)
    local message = react.useState("")
    local change = react.useState(0)
    local function run(fn, success)
        local ok, failure = pcall(fn)
        message:set(ok and success or (tr("BLUEPRINT_OP_FAILED", {error = failure})))
        if ok then
            editing:set(nil)
            deleting:set(nil)
            change:set(change:old() + 1)
        end
    end
    react.onEvent("blueprintLibraryChanged", function()
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
    for _, snapshot in ipairs(templates) do
        local id = snapshot.id
        local sourceId = api.res.constructionRep.find(snapshot.constructionFileName)
        local categories = snapshot.categories
        if sourceId >= 0 then
            local parsed = core.menuCategories(api.res.constructionRep.get(sourceId), snapshot.constructionFileName)
            if #parsed > 0 then categories = parsed end
        end
        local labels, count = {}, 0
        for _, category in ipairs(categories) do labels[#labels + 1] = categoryLabels[category] or category end
        for _ in pairs(snapshot.modules) do count = count + 1 end
        local details = tr("BLUEPRINT_DETAILS", {categories = table.concat(labels, " / "), count = count})
        local missing = core.missingResources(snapshot, api.res)
        if #missing > 0 then details = details .. gettext("BLUEPRINT_MISSING_DEPS") end
        local controls
        local nameContent = builtin.TextView {text = snapshot.name}
        if editing:old() == id then
            nameContent = builtin.TextInputField {
                    meta = sized(400, 32), value = draft:old(), maxLength = 128,
                    onTyping = function(value) draft:set(value) end,
                    onValueChange = function(value) draft:set(value) end,
            }
            controls = {
                textButton(gettext("BLUEPRINT_SAVE_NAME"), function() run(function() library.rename(id, draft:old()) end, gettext("BLUEPRINT_NAME_SAVED")) end),
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
                textButton(gettext("BLUEPRINT_RENAME"), function() editing:set(id); draft:set(snapshot.name); deleting:set(nil) end),
                textButton(gettext("BLUEPRINT_COPY"), function() run(function() library.duplicate(id) end, gettext("BLUEPRINT_COPIED")) end),
                textButton(gettext("BLUEPRINT_DELETE"), function() deleting:set(id); editing:set(nil) end),
                textButton(gettext("BLUEPRINT_REVEAL"), function() reveal(library.resourceName(id)) end),
            }
        end
        local rowMeta = sized(850, 90)
        rowMeta.localKey = "template-row-" .. tostring(id)
        local columns = builtin.BoxLayout {
            orientation = builtin.type.Orientation.Horizontal,
            children = {
                builtin.ImageView {
                    meta = sized(130, 90),
                    path = sourceId >= 0 and snapshot.previewIcon ~= "" and snapshot.previewIcon or "::/warehouses/icons/wh_goods_preview.tga",
                    scaling = builtin.type.ImageViewScaling.AutoFit,
                },
                builtin.Component {
                    meta = sized(420, 90),
                    layout = builtin.BoxLayout {
                        orientation = builtin.type.Orientation.Vertical,
                        children = {
                            nameContent,
                            builtin.TextView {text = details},
                        },
                    },
                },
            },
        }
        rows[#rows + 1] = builtin.Component {
            meta = rowMeta,
            layout = builtin.FloatingLayout {children = {
                builtin.FloatingLayoutChild {h = 0, v = 0.5, item = columns},
                builtin.FloatingLayoutChild {
                    h = 1, v = 0.5,
                    item = builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = controls},
                },
            }},
        }
    end
    if #rows == 0 then
        rows[1] = builtin.TextView {text = query:old() == "" and gettext("BLUEPRINT_EMPTY_LIBRARY") or gettext("BLUEPRINT_NO_MATCHES")}
    end
    return builtin.Window {
        id = windowId, title = gettext("BLUEPRINT_MANAGER_TITLE"),
        initialVisible = true, closable = true, movable = true,
        onClose = close,
        content = builtin.BoxLayout {
            orientation = builtin.type.Orientation.Vertical,
            children = {
                builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = {
                    builtin.TextInputField {
                        meta = sized(850, 34), value = query:old(), placeholderText = gettext("BLUEPRINT_SEARCH"),
                        onTyping = function(value) query:set(value) end,
                        onValueChange = function(value) query:set(value) end,
                        onCancel = function() query:set("") end,
                    },
                    builtin.Component {
                        meta = sized(850, 24),
                        layout = builtin.FloatingLayout {children = {
                            builtin.FloatingLayoutChild {
                                h = 1, v = 0.5,
                                item = builtin.TextView {text = tr("BLUEPRINT_COUNT", {count = #templates})},
                            },
                        }},
                    },
                }},
                builtin.ScrollArea {
                    meta = sized(850, 440),
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
