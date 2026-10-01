local tr = require "blueprint_demo::/blueprint/i18n.lua"
local react = ug_require "::/gui/main/react.lua"
local originalWindow = ug_require "::/gui/construction/construction.tl"
local library = require "blueprint_demo::/blueprint/library.lua"
local constructionUi = ug_require "::/gui/construction/construction_react_util.tl"
local builtin = ug_require "::/gui/main/builtin.lua"
local selectionTarget
local lastSyncError
local manager = require "blueprint_demo::/blueprint/manager.lua"
local hookedContainers = setmetatable({}, {__mode = "k"})

local function installParameterWindowRefresh(param)
    local toolParam = param.payload and param.payload.toolParam
    local gameCtx = toolParam and toolParam.gameCtx
    if not gameCtx or not gameCtx.windowContainer then return end
    local container = gameCtx.windowContainer:get()
    if not container then return end
    local windowApi = container:getApi()
    if not windowApi or hookedContainers[windowApi] then return end
    local addSingletonWindow = windowApi.addSingletonWindow
    windowApi.addSingletonWindow = function(recipe, windowParams)
        if react.GetRecipeName(recipe) == "ConstructionParamsWindow" then
            -- 原生参数窗口只在 onMount 回传 initRef。
            -- 建筑列表重建后必须同时重建它，否则会沿用已经失效的列表引用。
            local copy, meta = {}, {}
            for key, value in pairs(windowParams) do copy[key] = value end
            for key, value in pairs(windowParams.meta or {}) do meta[key] = value end
            meta.localKey = "blueprint-params-" .. tostring(library.getRevision())
            copy.meta = meta
            return addSingletonWindow(recipe, copy)
        end
        return addSingletonWindow(recipe, windowParams)
    end
    hookedContainers[windowApi] = true
end

-- 官方 recipe replacement 机制保留原生菜单行为，仅在模板变化时重建窗口。
-- 新 localKey 会清除原菜单的 useStateLazy 缓存；普通帧不重建。
local RefreshableWindow = react.RegisterWrapperRecipe("BlueprintConstructionWindow", originalWindow, function(param)
    if param.payload and param.payload.toolParam then manager.setContext(param.payload.toolParam.gameCtx) end
    installParameterWindowRefresh(param)
    local revision = react.useState(library.getRevision())
    local pending = react.useRef(nil)
    local ticks = react.useRef(0)
    local ok, err = pcall(library.ensureLoaded)
    if not ok then debugPrint("[Blueprint] " .. tr("BLUEPRINT_LIBRARY_LOAD_FAILED", {error = err})) end

    react.onEvent("blueprintLibraryChanged", function(_name, event)
        if event.focusResName then
            pending:set(event.focusResName)
            selectionTarget = nil
        end
        ticks:set(0)
        revision:set(library.getRevision())
        -- 与原生 propagateActionFn 一样，动作回调在工具栈未就绪时可以缺省。
        -- 有回调时解除旧预览的引用；缺省时仍允许重建菜单。
        if param.payload and param.payload.setActionFn then
            param.payload.setActionFn(nil, "BlueprintMenuRefresh")
        end
    end)
    react.onStep(function()
        if selectionTarget then
            selectionTarget.ticks = selectionTarget.ticks + 1
            if selectionTarget.ticks > 120 then selectionTarget = nil end
        end
        local success, failure = pcall(library.pollSync)
        if not success then
            local message = tostring(failure)
            if message ~= lastSyncError then
                debugPrint("[Blueprint] " .. tr("BLUEPRINT_SYNC_FAILED", {error = message}))
                lastSyncError = message
            end
        else
            lastSyncError = nil
            if failure then react.fireEvent(nil, "blueprintLibraryChanged", failure) end
        end
        if not pending:get() then return end
        ticks:set(ticks:get() + 1)
        if ticks:get() < 3 then return end
        local resName = pending:get()
        pending:set(nil)
        selectionTarget = {resName = resName, ticks = 0}
        api.gui.byId.setVisible("menu.construction.react", true)
        react.fireEvent(nil, "constructionMenuActive", {active = true})
        react.fireEvent(nil, "constructionMenuSelectTabForConstruction", {resName = resName})
    end)

    local params = {}
    for key, value in pairs(param) do params[key] = value end
    params.meta = {localKey = "blueprint-menu-" .. tostring(revision:old())}
    return react.CallOriginalRecipe(originalWindow, params)
end)

function data()
    return {install = function(replacementApi)
        manager.install()
        local originalList = builtin.List
        builtin.List = function(params, ...)
            if params.meta and params.meta.tag == "construction-menu.construction-definitions-list" then
                -- 此调用仍在原生 ConstructionDefinitionsList 的 recipe 上下文中。
                -- 使用它的公开 getDefinition API 和原生 onSelect 回调，保持卡片、参数和动作同步。
                local listRef = react.useSelfRef()
                react.onStep(function()
                    if not selectionTarget then return end
                    local node = listRef:get()
                    local listApi = node and node:getApi()
                    if not listApi then return end
                    for index = 1, #(params.children or {}) do
                        local definition = listApi.getDefinition(index)
                        if definition and definition.resName == selectionTarget.resName then
                            selectionTarget = nil
                            params.onSelect(index)
                            return
                        end
                    end
                end)
            end
            return originalList(params, ...)
        end
        local originalDefinitions = constructionUi.getConstructionDefinitions
        constructionUi.getConstructionDefinitions = function(...)
            return library.decorateDefinitions(originalDefinitions(...))
        end
        local originalActionParams = constructionUi.getActionParams
        constructionUi.getActionParams = function(definition, ...)
            return library.applyBuilderPayload(definition, originalActionParams(definition, ...))
        end
        replacementApi.ReplaceRecipe(originalWindow, RefreshableWindow)
    end}
end
