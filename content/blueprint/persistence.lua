local gettext = _
local transport = require "blueprint_demo::/blueprint/transport.lua"
local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local base64 = require "blueprint_demo::/blueprint/base64.lua"
local core = require "blueprint_demo::/blueprint/core.lua"
local persistence = {}

function persistence.encodeTemplate(snapshot)
    return base64.encode(transport.serialize(core.validate(snapshot)))
end

function persistence.decodeTemplate(text)
    assert(type(text) == "string" and #text <= 2 * 1024 * 1024, gettext("BLUEPRINT_TRANSFER_SIZE"))
    return core.validate(transport.deserialize(base64.decode(text:gsub("%s", ""))))
end

local function groupFor(snapshot)
    -- 已知资源目录可修正早期误存分类；自定义资源沿用保存的首个分类。
    local categories = core.menuCategories({}, snapshot.constructionFileName)
    return categories[1] or snapshot.categories[1]
end

local function arrayLength(value)
    assert(type(value) == "table", gettext("BLUEPRINT_LIBRARY_GROUP"))
    local count = 0
    for key in pairs(value) do
        assert(type(key) == "number" and key % 1 == 0 and key >= 1, gettext("BLUEPRINT_LIST_INDEX"))
        count = count + 1
    end
    for index = 1, count do assert(value[index] ~= nil, gettext("BLUEPRINT_LIST_GAPS")) end
    return count
end

function persistence.encode(value)
    local library = runtime.validateLibrary(value)
    local result = {version = 4, encoding = "base64", nextId = library.nextId,
        nextNameNumber = library.nextNameNumber, templateOrder = {}, data = {
            rail_buildings = {}, road_buildings = {}, water_buildings = {},
            air_buildings = {}, warehouses = {},
        }}
    for _, snapshot in ipairs(library.templates) do
        local group = groupFor(snapshot)
        result.data[group] = result.data[group] or {}
        local entries = result.data[group]
        entries[#entries + 1] = persistence.encodeTemplate(snapshot)
        result.templateOrder[#result.templateOrder + 1] = snapshot.id
    end
    return result
end

function persistence.decode(value)
    if type(value) == "table" and value.version == 4 then
        assert(value.encoding == "base64" and type(value.data) == "table", gettext("BLUEPRINT_MISSING_ENCODING"))
        local library = runtime.validateLibrary({version = 1, nextId = value.nextId,
            nextNameNumber = value.nextNameNumber, templates = {}})
        local byId, count = {}, 0
        for group, entries in pairs(value.data) do
            assert(type(group) == "string" and #group > 0, gettext("BLUEPRINT_LIBRARY_GROUP"))
            for index = 1, arrayLength(entries) do
                assert(type(entries[index]) == "string", gettext("BLUEPRINT_MISSING_ENCODING"))
                local snapshot = core.validate(transport.deserialize(base64.decode(entries[index])))
                assert(groupFor(snapshot) == group, gettext("BLUEPRINT_LIBRARY_GROUP"))
                assert(not byId[snapshot.id], gettext("BLUEPRINT_DUPLICATE_ID"))
                byId[snapshot.id], count = snapshot, count + 1
            end
        end
        -- 分类不改变管理窗口中原有的跨类型排列顺序。
        assert(arrayLength(value.templateOrder) == count, gettext("BLUEPRINT_LIST_GAPS"))
        for _, id in ipairs(value.templateOrder) do
            assert(type(id) == "number" and byId[id], gettext("BLUEPRINT_DUPLICATE_ID"))
            library.templates[#library.templates + 1] = byId[id]
            byId[id] = nil
        end
        return runtime.validateLibrary(library)
    end
    if type(value) == "table" and value.version == 3 then
        assert(value.encoding == "base64" and type(value.data) == "string", gettext("BLUEPRINT_MISSING_ENCODING"))
        return runtime.validateLibrary(transport.deserialize(base64.decode(value.data)))
    end
    if type(value) == "table" and value.version == 2 then
        assert(type(value.data) == "table", gettext("BLUEPRINT_MISSING_ENCODING"))
        return runtime.validateLibrary(transport.decode(value.data))
    end
    -- 读取旧版模板；下次成功保存时自动升级文件格式。
    return runtime.validateLibrary(value)
end
return persistence
