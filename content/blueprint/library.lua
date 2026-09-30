local core = require "blueprint_demo::/blueprint/core.lua"
local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local transport = require "blueprint_demo::/blueprint/transport.lua"
local persistence = require "blueprint_demo::/blueprint/persistence.lua"
local library = {}
local directory, file = "blueprint_demo", "library"
local loaded, state, published = false, nil, nil
local revision, retryTicks, lastSaved = 0, 0, nil
library.carrier = "blueprint_demo::/blueprint/saved_single.metacon"

function library.resourceName(id)
    -- 仅用作 GUI 卡片标识；传入建造器的始终是已加载的 carrier。
    return "blueprint_demo::/blueprint/saved_" .. tostring(id) .. ".metacon"
end

function library.ensureLoaded()
    if loaded then return end
    local exists = false
    for _, name in ipairs(app.getAllUserdata(directory)) do
        if name == file or name == file .. ".lua" then exists = true end
    end
    state = persistence.decode(exists and app.loadUserdata(directory, file)
        or {version = 1, nextId = 1, templates = {}})
    loaded = true
    debugPrint("[Blueprint] 已读取 " .. tostring(#state.templates) .. " 个模板；等待引擎同步")
end

function library.pollSync()
    library.ensureLoaded()
    local shared = runtime.readState()
    if not shared or not shared.ready then return end
    if core.equal(shared.library, state) then
        if not core.equal(published, state) then
            published = core.copy(state)
            revision = revision + 1
            debugPrint("[Blueprint] 引擎同步完成，菜单可用模板 " .. tostring(#state.templates))
            local event = {
                resName = lastSaved and library.resourceName(lastSaved) or nil,
            }
            lastSaved = nil
            return event
        end
        retryTicks = 0
        return
    end
    -- 订阅就绪后发送；尚未回读到引擎状态时每 60 个 GUI step 重试。
    if retryTicks == 0 then
        api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", runtime.eventId,
            runtime.eventName, {library = core.copy(state)}))
    end
    retryTicks = (retryTicks + 1) % 60
end

local function commit(candidate, selectedId)
    app.saveUserdata(directory, file, persistence.encode(candidate))
    local readback = persistence.decode(app.loadUserdata(directory, file))
    assert(core.equal(readback, candidate), "模板库写入后校验失败")
    state, lastSaved, retryTicks = readback, selectedId, 0
end

function library.save(entity)
    library.ensureLoaded()
    assert(api.res.metaConstructionRep.find(library.carrier) >= 0,
        "请重新载入地图，以加载新版模板载体")
    local shared = runtime.readState()
    assert(shared and shared.ready, "模板引擎尚未就绪，请等待地图加载完成后重试")
    local snapshot = core.capture(entity, state.nextId, api.engine, api.type.ComponentType, api.res,
        api.type.enum.TransportMode)
    local candidate = core.copy(state)
    candidate.templates[#candidate.templates + 1] = snapshot
    candidate.nextId = candidate.nextId + 1
    commit(candidate, snapshot.id)
    debugPrint("[Blueprint] 已写入 " .. snapshot.name .. "；等待引擎确认")
    return snapshot, library.resourceName(snapshot.id)
end

local function find(id, candidate)
    for index, snapshot in ipairs(candidate.templates) do
        if snapshot.id == id then return index, snapshot end
    end
    error("该模板不存在或已删除")
end

function library.list(query)
    library.ensureLoaded()
    local result = {}
    query = (query or ""):lower()
    for _, snapshot in ipairs(state.templates) do
        if query == "" or snapshot.name:lower():find(query, 1, true) then
            result[#result + 1] = core.copy(snapshot)
        end
    end
    return result
end

function library.rename(id, name)
    library.ensureLoaded()
    assert(type(name) == "string", "请输入模板名称")
    name = name:match("^%s*(.-)%s*$")
    assert(#name > 0 and #name <= 384, "模板名称不能为空或过长")
    local candidate = core.copy(state)
    local _, snapshot = find(id, candidate)
    snapshot.name = name
    commit(candidate)
end

function library.delete(id)
    library.ensureLoaded()
    local candidate = core.copy(state)
    local index = find(id, candidate)
    table.remove(candidate.templates, index)
    commit(candidate)
end

function library.duplicate(id)
    library.ensureLoaded()
    local candidate = core.copy(state)
    local _, original = find(id, candidate)
    local snapshot = core.copy(original)
    snapshot.id, snapshot.name = candidate.nextId, original.name .. "（副本）"
    candidate.nextId = candidate.nextId + 1
    candidate.templates[#candidate.templates + 1] = snapshot
    commit(candidate, snapshot.id)
    return core.copy(snapshot)
end

local function shallow(value)
    local result = {}
    for key, child in pairs(value or {}) do result[key] = child end
    return result
end

function library.decorateDefinitions(definitions, getAttributes)
    local result, carrier = {}, nil
    for _, definition in ipairs(definitions) do
        if definition.resName == library.carrier then carrier = definition
        else result[#result + 1] = definition end
    end
    if not carrier or not published then return result end
    for _, snapshot in ipairs(published.templates) do
        if #core.missingResources(snapshot, api.res) == 0 then
            local definition = shallow(carrier)
            local source = api.res.constructionRep.get(api.res.constructionRep.find(snapshot.constructionFileName))
            definition.resName = library.resourceName(snapshot.id)
            -- 信息面板使用已计算的属性；建造器由 getActionParams 包装器设置载体。
            -- 避免原生信息面板再次用不含配置数据的默认参数调用载体。
            definition.constructions = {}
            definition.blueprintPayload = transport.encode(core.toTemplate(snapshot, api.res))
            definition.costsYearProgression = false
            definition.name = snapshot.name
            definition.description = "已保存的单座建筑模板，保留建筑参数及模块。"
            definition.icon = {icon = snapshot.icon ~= "" and snapshot.icon or "::/warehouses/icons/wh_goods.tga"}
            definition.previewIcon = {icon = snapshot.previewIcon ~= "" and snapshot.previewIcon or "::/warehouses/icons/wh_goods_preview.tga"}
            definition.metadata = source.metadata
            definition.attributes = source.description and source.description.attributes or {}
            if getAttributes then
                local result = api.engine.util.construction.getConstructionResult(library.carrier, -1, definition.blueprintPayload)
                if result then definition.attributes = getAttributes(result) or definition.attributes end
            end
            definition.cargoTypeSet = source.description and source.description.cargoTypeSet
            definition.params = shallow(carrier.params)
            local categories = {}
            -- 展示时重新解析分类，旧版误存为四种交通目录的模板也立即纠正。
            local actualCategories = core.menuCategories(source, snapshot.constructionFileName)
            if #actualCategories == 0 then actualCategories = snapshot.categories end
            for _, category in ipairs(actualCategories) do
                categories[#categories + 1] = {category = category, order = 9500, filterCategories = {"building"}}
            end
            definition.menuCategory = {categories = categories}
            result[#result + 1] = definition
        end
    end
    return result
end

function library.getRevision() return revision end
function library.applyBuilderPayload(definition, action)
    if not definition or not definition.blueprintPayload then return action end
    local builder = action.constructionActionParams and action.constructionActionParams.constructionBuilder
    assert(builder, "模板未生成原生建造器")
    builder.constructions = {library.carrier}
    builder.constructionTemplate = -1
    builder.params = core.copy(definition.blueprintPayload)
    return action
end
return library
