local gettext = _
local tr = require "blueprint_demo::/blueprint/i18n.lua"
local core = require "blueprint_demo::/blueprint/core.lua"
local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local persistence = require "blueprint_demo::/blueprint/persistence.lua"
local library = {}
-- 当前引擎对 userdata API 使用固定目录白名单。普通 .lua 文件不会成为
-- 原生的 *.preset.lua 模组预设；使用 Mod 专属文件名避免覆盖原生文件。
local directory, file = "mod_presets", "blueprint_library"
local loaded, state, published = false, nil, nil
local revision, retryTicks, lastSaved = 0, 0, nil
local refreshTarget
library.carrier = "blueprint_demo::/blueprint/saved_single.metacon"

function library.resourceName(id)
    -- 仅用作 GUI 卡片标识；传入建造器的始终是已加载的 carrier。
    return "blueprint_demo::/blueprint/saved_" .. tostring(id) .. ".metacon"
end

local function readLibrary(folder, filename)
    for _, name in ipairs(app.getAllUserdata(folder)) do
        if name == filename or name == filename .. ".lua" then
            -- 文件存在时，读取或校验失败必须向上传递，不能初始化空库。
            return app.loadUserdata(folder, filename), true
        end
    end
    return nil, false
end

function library.ensureLoaded()
    if loaded then return end
    local value, exists = readLibrary(directory, file)
    if not exists then
        -- 同目录下的上一版文件名可自动读取，下一次成功编辑写入新文件名。
        value, exists = readLibrary(directory, "blueprint_demo_library")
    end
    if not exists then
        -- 旧游戏版本若仍允许自定义目录，则只读加载旧库，下一次编辑写入新位置。
        local ok, legacy, legacyExists = pcall(readLibrary, "blueprint_demo", "library")
        if ok then
            if legacyExists then value, exists = legacy, true end
        else
            local message = tostring(legacy)
            local denied = message:find("The directory you trying to access is not available or invalid", 1, true)
                or message:find("The directory you're trying to access is not available or invalid", 1, true)
            if not denied then error(legacy, 0) end
        end
    end
    if not exists then value = {version = 1, nextId = 1, templates = {}} end
    state = persistence.decode(value)
    loaded = true
    debugPrint("[Blueprint] " .. tr("BLUEPRINT_LIBRARY_LOADED", {count = #state.templates}))
end

function library.pollSync()
    library.ensureLoaded()
    local shared = runtime.readState()
    if not shared or not shared.ready then return end
    if core.equal(shared.library, state) then
        if not core.equal(published, state) then
            published = core.copy(state)
            revision = revision + 1
            debugPrint("[Blueprint] " .. tr("BLUEPRINT_LIBRARY_SYNCED", {count = #state.templates}))
            local event = {
                resName = lastSaved and library.resourceName(lastSaved) or nil,
                focusResName = refreshTarget,
            }
            lastSaved = nil
            refreshTarget = nil
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

local function commit(candidate, selectedId, focusResName)
    app.saveUserdata(directory, file, persistence.encode(candidate))
    local readback = persistence.decode(app.loadUserdata(directory, file))
    assert(core.equal(readback, candidate), gettext("BLUEPRINT_WRITE_VERIFY"))
    state, lastSaved, retryTicks = readback, selectedId, 0
    refreshTarget = focusResName
end

local function nextNameNumber()
    -- 兼容旧库：非空库延续旧名称序号；空库从 1 开始，内部 ID 不回收。
    return state.nextNameNumber or (#state.templates == 0 and 1 or state.nextId)
end

function library.save(entity)
    library.ensureLoaded()
    assert(api.res.metaConstructionRep.find(library.carrier) >= 0,
        gettext("BLUEPRINT_RELOAD_CARRIER"))
    local shared = runtime.readState()
    assert(shared and shared.ready, gettext("BLUEPRINT_ENGINE_NOT_READY"))
    local nameNumber = nextNameNumber()
    local snapshot = core.capture(entity, state.nextId, api.engine, api.type.ComponentType, api.res,
        api.type.enum.TransportMode, nameNumber)
    local candidate = core.copy(state)
    candidate.templates[#candidate.templates + 1] = snapshot
    candidate.nextId = candidate.nextId + 1
    candidate.nextNameNumber = nameNumber + 1
    commit(candidate, snapshot.id, library.resourceName(snapshot.id))
    debugPrint("[Blueprint] " .. tr("BLUEPRINT_SAVED_WAIT", {name = snapshot.name}))
    return snapshot, library.resourceName(snapshot.id)
end

local function find(id, candidate)
    for index, snapshot in ipairs(candidate.templates) do
        if snapshot.id == id then return index, snapshot end
    end
    error(gettext("BLUEPRINT_NOT_FOUND"))
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

function library.exportTemplate(id)
    library.ensureLoaded()
    local _, snapshot = find(id, state)
    return persistence.encodeTemplate(snapshot), snapshot.name
end

function library.previewImport(text)
    local snapshot = persistence.decodeTemplate(text)
    return snapshot, core.missingResources(snapshot, api.res)
end

function library.importTemplate(text)
    library.ensureLoaded()
    local snapshot = library.previewImport(text)
    local candidate = core.copy(state)
    snapshot.id = candidate.nextId
    candidate.nextId = candidate.nextId + 1
    candidate.nextNameNumber = nextNameNumber()
    candidate.templates[#candidate.templates + 1] = snapshot
    commit(candidate, snapshot.id)
    return core.copy(snapshot)
end

function library.updateMetadata(id, name, description)
    library.ensureLoaded()
    assert(type(name) == "string", gettext("BLUEPRINT_ENTER_NAME"))
    name = name:match("^%s*(.-)%s*$")
    assert(#name > 0 and #name <= 384, gettext("BLUEPRINT_NAME_LENGTH"))
    assert(description == nil or type(description) == "string" and #description <= 4096, gettext("BLUEPRINT_DESCRIPTION_LENGTH"))
    local candidate = core.copy(state)
    local _, snapshot = find(id, candidate)
    snapshot.name = name
    if description ~= nil then snapshot.description = description end
    commit(candidate)
end

function library.rename(id, name)
    library.updateMetadata(id, name)
end

function library.deleteAll()
    library.ensureLoaded()
    if #state.templates == 0 then return end
    local candidate = core.copy(state)
    candidate.templates = {}
    candidate.nextNameNumber = 1
    -- Persist once and keep internal IDs monotonic, like deleting the last template.
    commit(candidate)
end

function library.delete(id)
    library.ensureLoaded()
    local candidate = core.copy(state)
    local index = find(id, candidate)
    table.remove(candidate.templates, index)
    if #candidate.templates == 0 then candidate.nextNameNumber = 1 end
    commit(candidate)
end

function library.duplicate(id)
    library.ensureLoaded()
    local candidate = core.copy(state)
    local _, original = find(id, candidate)
    local snapshot = core.copy(original)
    candidate.nextNameNumber = nextNameNumber()
    snapshot.id, snapshot.name = candidate.nextId, tr("BLUEPRINT_COPY_NAME", {name = original.name})
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

function library.decorateDefinitions(definitions)
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
            definition.blueprintTemplate = core.toTemplate(snapshot, api.res, api.engine.util.getYear())
            definition.costsYearProgression = false
            definition.name = snapshot.name
            definition.description = snapshot.description and snapshot.description ~= "" and snapshot.description
                or gettext("BLUEPRINT_SAVED_DESCRIPTION")
            local icon, preview = core.templateImages(snapshot)
            definition.icon = {icon = icon}
            definition.previewIcon = {icon = preview}
            definition.metadata = source.metadata
            definition.attributes = source.description and source.description.attributes or {}
            definition.cargoTypeSet = source.description and source.description.cargoTypeSet
            -- 原生 getActionParams 将此数组传给建造器，旧模板也可继承原建筑音效。
            local audio = source.soundConfig and source.soundConfig.builderAudioRes
            definition.builderAudioRes = {type(audio) == "string" and audio ~= "" and audio
                or "::/gui/construction/sound/buildoze_construction_large.builder_audio"}
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
    if not definition or not (definition.blueprintTemplate or definition.blueprintPayload) then return action end
    local builder = action.constructionActionParams and action.constructionActionParams.constructionBuilder
    assert(builder, gettext("BLUEPRINT_NO_BUILDER"))
    builder.constructions = {library.carrier}
    builder.constructionTemplate = -1
    if definition.blueprintTemplate then
        -- 实验：底层 params 声明为 table，直接传嵌套对象，保留原生建造参数。
        local params = shallow(builder.params)
        params.blueprintTemplate = core.copy(definition.blueprintTemplate)
        builder.params = params
    else
        -- 已存在的旧卡片仍可传入旧数字块；新生成卡片始终走对象路径。
        builder.params = core.copy(definition.blueprintPayload)
    end
    return action
end
return library
