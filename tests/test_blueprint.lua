-- 使用内存中的 API 替身验证快照、持久化与刷新协议；不触碰真实存档。
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end
local function rejects(fn, fragment)
    local ok, err = pcall(fn)
    assert(not ok and tostring(err):find(fragment, 1, true), tostring(err))
end
local modules = {}
local realRequire = require
local function copy(v)
    if type(v) ~= "table" then return v end
    local result = {}
    for k, child in pairs(v) do result[k] = copy(child) end
    return result
end
function require(name)
    if modules[name] then return modules[name] end
    local path = name:match("^blueprint_demo::/(.+)$")
    if path then
        local result = assert(loadfile(ROOT .. "/content/" .. path))()
        modules[name] = result
        return result
    end
    return realRequire(name)
end
function debugPrint() end
local function script(path)
    local env = setmetatable({}, {__index = _G})
    assert(loadfile(ROOT .. "/content/" .. path, "t", env))()
    return env.data()
end
local function repository(names)
    local data, index = {}, {}
    for id, name in pairs(names) do data[id] = {}; index[name] = id end
    local rep = {adds = 0}
    rep.find = function(name) return index[name] or -1 end
    rep.getName = function(id) for name, i in pairs(index) do if i == id then return name end end end
    rep.get = function(id) return data[id] end
    rep.getAsTable = function(id) return copy(data[id]) end
    rep.setAsTable = function(id, value) assert(data[id]); data[id] = copy(value); return true end
    rep.addAsTable = function(name, value)
        assert(not index[name]); local id = rep.adds + 100
        rep.adds = rep.adds + 1; index[name] = id; data[id] = copy(value); return id
    end
    rep.setVisible = function(id, value) data[id].visible = value end
    return rep
end
api = {res = {
    constructionRep = repository({[0] = "::/warehouses/warehouse.con", [1] = "other_mod::/station.con"}),
    moduleRep = repository({[0] = "::/warehouses/wh_goods.module", [1] = "other_mod::/platform.module"}),
    cargoTypeRep = repository({[0] = "::/cargos/goods.cargo", [7] = "::/cargos/coal.cargo"}),
    metaConstructionRep = repository({}),
}, type = {ComponentType = {}, enum = {ScriptParamType = {ComboBox = "ComboBox"}}}}
local types = api.type.ComponentType
for _, name in ipairs({"CONSTRUCTION", "WAREHOUSE", "SUBCONSTRUCTION", "STATION", "STATION_GROUP", "DEPOT", "NAME", "PLAYER_OWNED"}) do types[name] = name end
api.res.constructionRep.setAsTable(0, {
    description = {name = "仓库", icon = "::/icon.tga", previewIcon = "::/preview.tga"},
    menuCategory = {categories = {{category = "warehouses"}}}, metadata = {company = {permitKey = "warehouse"}},
})
api.res.constructionRep.setAsTable(1, {
    description = {name = "车站", icon = "other_mod::/icon.tga", previewIcon = "other_mod::/preview.tga"},
    menuCategory = {categories = {{category = "rail_buildings"}}},
})
local entities = {
    [10] = {CONSTRUCTION = {fileName = "::/warehouses/warehouse.con", params = {
        year = 1940, seed = 34, label = "测试仓库", choice = {1, 3, enabled = true},
        modules = {[632502500] = "::/warehouses/wh_goods.module"}, tagToCargoType = {[632502500] = 7},
    }, stations = {}, depots = {}, industries = {}, townBuildings = {}},
    NAME = {name = "货物仓库"}, PLAYER_OWNED = {player = 9}},
    [11] = {WAREHOUSE = {construction = 10}},
    [20] = {CONSTRUCTION = {fileName = "other_mod::/station.con", params = {
        year = 1920, seed = 123, platforms = 3, modules = {[5] = {fileName = "other_mod::/platform.module"}},
    }, stations = {21}, industries = {}, townBuildings = {}}, PLAYER_OWNED = {player = 9}},
    [21] = {STATION = {}}, [22] = {STATION_GROUP = {stations = {21}}},
    [23] = {STATION_GROUP = {stations = {21, 24}}}, [24] = {STATION = {}},
    [30] = {SUBCONSTRUCTION = {}},
}
api.engine = {
    getComponent = function(id, kind) return entities[id] and entities[id][kind] end,
    entityExists = function(id) return entities[id] ~= nil end,
    util = {getPlayer = function() return 9 end, getYear = function() return 1950 end},
    system = {streetConnectorSystem = {
        getConstructionEntityForSubconstruction = function() return 10 end,
        getConstructionEntityForStation = function(id) return id == 24 and 10 or 20 end,
        getConstructionEntityForDepot = function() return 20 end,
    }},
}
local disk, writes, failWrite, corruptRead = nil, 0, false, false
app = {
    getAllUserdata = function() return disk and {"library"} or {} end,
    loadUserdata = function()
        local result = copy(disk)
        if corruptRead then result.templates[#result.templates].params.seed = 999 end
        if result and result.version == 1 then
            return require("blueprint_demo::/blueprint/persistence.lua").encode(result)
        end
        return result
    end,
    saveUserdata = function(directory, file, value)
        assert(directory == "blueprint_demo" and file == "library")
        if failWrite then error("disk failure") end
        assert(value.version == 4 and value.encoding == "base64" and type(value.data) == "table")
        -- 模拟只保留字符串键及连续数组的游戏文件输出。
        local function fileCopy(input)
            if type(input) ~= "table" then return input end
            local result = {}
            for key, child in pairs(input) do
                if type(key) == "string" then result[key] = fileCopy(child) end
            end
            for key, child in ipairs(input) do result[key] = fileCopy(child) end
            return result
        end
        writes = writes + 1
        disk = require("blueprint_demo::/blueprint/persistence.lua").decode(fileCopy(value))
    end,
}
local core = require "blueprint_demo::/blueprint/core.lua"
local library = require "blueprint_demo::/blueprint/library.lua"
local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local transport = require "blueprint_demo::/blueprint/transport.lua"
local shared, commands, outgoing = {}, {}, {}
types.GAME_SCRIPT = "GAME_SCRIPT"
entities[99] = {GAME_SCRIPT = {state = shared}}
api.engine.system.gameScriptSystem = {getEntityForGameScript = function(name)
    assert(name == runtime.gameScript); return 99
end}
api.cmd = {
    makeScriptingSendEventCmd = function(src, id, name, param)
        return {src = src, id = id, name = name, param = copy(param)}
    end,
    sendCommand = function(cmd) commands[#commands + 1] = cmd end,
}
api.gui = {fireReactEvent = function(name, value) outgoing[#outgoing + 1] = {name = name, value = value} end}
local gameScript = script("blueprint/runtime.script.lua")
local engineState = {
    get = function() return shared end,
    set = function(_, value) shared = copy(value); entities[99].GAME_SCRIPT.state = shared end,
    subscribeToEvent = function(_, name) assert(name == runtime.eventName) end,
}
gameScript.update({}, engineState, 0)
local carrier = {
    resName = library.carrier, constructions = {library.carrier}, constructionTemplate = -1,
    action = "ACTION_CONSTRUCTION_BUILDER", params = {{key = "rotation", numbers = {0}, defaultIndex = 1}},
    availability = {yearFrom = 0, yearTo = 0}, hudIcons = {},
}
api.res.metaConstructionRep = {find = function(name) return name == library.carrier and 0 or -1 end}
local function acknowledge()
    local event = library.pollSync()
    if event then outgoing[#outgoing + 1] = {name = "blueprintLibraryChanged", value = event} end
    local cmd = commands[#commands]
    assert(cmd)
    gameScript.handleEvent({}, engineState, cmd.src, cmd.id, cmd.name, cmd.param)
    event = library.pollSync()
    if event then outgoing[#outgoing + 1] = {name = "blueprintLibraryChanged", value = event} end
end
local snapshot

test("warehouse snapshot and cargo IDs survive recreation", function()
    snapshot = core.capture(11, 1, api.engine, types, api.res)
    assert(snapshot.constructionFileName == "::/warehouses/warehouse.con")
    assert(snapshot.params.modules == nil and snapshot.params.tagToCargoType == nil)
    assert(snapshot.cargoByTag[632502500] == "::/cargos/coal.cargo")
    local result = core.toTemplate(snapshot, api.res).constructions[1]
    assert(result.modules[632502500] == "::/warehouses/wh_goods.module")
    assert(result.params.seed == 34 and result.params.year == 1940 and result.params.choice.enabled)
    assert(result.params.tagToCargoType[632502500] == 7)
    assert(result.transf[13] == 0 and result.transf[16] == 1)
    result.params.choice[1] = 99
    assert(snapshot.params.choice[1] == 1 and entities[10].CONSTRUCTION.params.choice[1] == 1)
end)
test("native params table takes precedence", function()
    local con = entities[10].CONSTRUCTION
    con.params_native = {asTable = function() return copy(con.params) end}
    assert(core.capture(10, 1, api.engine, types, api.res).params.seed == 34)
    con.params_native = nil
end)
test("native module name records preserve every slot", function()
    local con = entities[10].CONSTRUCTION
    con.params_native = {asTable = function()
        local params = copy(con.params)
        params.modules = {
            [632502500] = {name = "::/warehouses/wh_goods.module", metadata = {type = "goods"}},
            [632502510] = {name = "other_mod::/platform.module", metadata = {}},
        }
        return params
    end}
    local saved = core.capture(11, 1, api.engine, types, api.res)
    local result = core.toTemplate(saved, api.res).constructions[1]
    assert(result.modules[632502500] == "::/warehouses/wh_goods.module")
    assert(result.modules[632502510] == "other_mod::/platform.module")
    assert(result.params.seed == 34)
    con.params_native = nil
    assert(core.normalizeModules({[5] = {fileName = "other_mod::/platform.module"}}, api.res.moduleRep)[5]
        == "other_mod::/platform.module")
    rejects(function() core.normalizeModules({[99] = {metadata = {}}}, api.res.moduleRep) end, "模块槽位 99")
end)
test("station/subconstruction selection maps to exactly one building", function()
    assert(core.resolveConstruction(21, api.engine, types) == 20)
    assert(core.resolveConstruction(22, api.engine, types) == 20)
    assert(core.resolveConstruction(30, api.engine, types) == 10)
    rejects(function() core.capture(23, 2, api.engine, types, api.res) end, "多个建筑")
    local station = core.capture(21, 2, api.engine, types, api.res)
    assert(station.modules[5] == "other_mod::/platform.module")
    assert(station.params.platforms == 3 and station.categories[1] == "rail_buildings")
end)
test("station and depot categories follow resource menus and transport directories", function()
    local cases = {
        {"::/stations/rail/modular_station/modular_station.con", "rail_buildings"},
        {"::/depots/rail/rail_depot.con", "rail_buildings"},
        {"::/stations/road/bus_station.con", "road_buildings"},
        {"::/stations/street/modular_street_station/station.con", "road_buildings"},
        {"::/depots/road/depot.con", "road_buildings"},
        {"::/stations/water/port.con", "water_buildings"},
        {"::/depots/water/shipyard.con", "water_buildings"},
        {"::/stations/air/airport.con", "air_buildings"},
    }
    for _, item in ipairs(cases) do
        local categories = core.menuCategories({}, item[1])
        assert(#categories == 1 and categories[1] == item[2])
    end
    local desc = {constructionTemplates = {
        {menuCategory = {categories = {{category = "rail_buildings"}}}},
        {menuCategory = {categories = {{category = "rail_buildings"}}}},
    }}
    local categories = core.menuCategories(desc, "mod::/custom.con")
    assert(#categories == 1 and categories[1] == "rail_buildings")
end)
test("custom buildings use terminal modes and unknown types are not broadcast", function()
    local engine = {getComponent = function(id, component)
        if component == "STATION" then return {terminals = {{transportModes = {[8] = true, [9] = false}}}} end
        if component == "VEHICLE_DEPOT" then return {transportModes = {[9] = true}} end
    end}
    local enums = {TRAIN = 8, SHIP = 9}
    local types = {STATION = "STATION", VEHICLE_DEPOT = "VEHICLE_DEPOT"}
    local rail = core.menuCategories({}, "mod::/custom.con", {stations = {1}}, engine, types, enums)
    assert(#rail == 1 and rail[1] == "rail_buildings")
    local ship = core.menuCategories({}, "mod::/custom.con", {depots = {2}}, engine, types, enums)
    assert(#ship == 1 and ship[1] == "water_buildings")
    assert(#core.menuCategories({}, "mod::/unknown.con") == 0)
end)
test("foreign ownership and unsupported objects cannot be saved", function()
    entities[10].PLAYER_OWNED.player = 1
    rejects(function() library.save(10) end, "当前玩家")
    entities[10].PLAYER_OWNED.player = 9
    rejects(function() library.save(999) end, "请点击")
    entities[10].CONSTRUCTION.industries = {1}
    rejects(function() library.save(10) end, "不支持工业")
    entities[10].CONSTRUCTION.industries = {}
    assert(writes == 0)
end)
test("unknown modules and nonserializable parameters fail explicitly", function()
    rejects(function() core.normalizeModules({[1] = "missing.module"}, api.res.moduleRep) end, "无法识别")
    rejects(function() core.copy({f = function() end}) end, "不能保存")
    local cyclic = {}; cyclic.child = cyclic
    rejects(function() core.copy(cyclic) end, "循环引用")
end)
test("save uses read-only repositories and waits for engine acknowledgement", function()
    local saved = library.save(11)
    assert(disk.nextId == 2 and #disk.templates == 1 and writes == 1)
    assert(core.equal(saved, disk.templates[1]))
    assert(library.getRevision() == 0 and #outgoing == 0)
    assert(#library.decorateDefinitions({carrier}) == 0)
    acknowledge()
    local cards = library.decorateDefinitions({carrier})
    assert(#cards == 1 and #cards[1].constructions == 0)
    assert(cards[1].costsYearProgression == false and type(cards[1].attributes) == "table")
    local action = {constructionActionParams = {constructionBuilder = {height = 5, rotation = 0.5,
        params = {nativeChoice = 42}}}}
    assert(library.applyBuilderPayload(cards[1], action) == action)
    assert(action.constructionActionParams.constructionBuilder.constructions[1] == library.carrier)
    assert(action.constructionActionParams.constructionBuilder.height == 5)
    local builderParams = action.constructionActionParams.constructionBuilder.params
    assert(builderParams.nativeChoice == 42 and builderParams.blueprintBytes == nil)
    assert(core.equal(builderParams.blueprintTemplate, core.toTemplate(saved, api.res)))
    assert(cards[1].resName == library.resourceName(saved.id) and cards[1].constructionTemplate == -1)
    assert(#cards[1].params == #carrier.params)
    assert(cards[1].metadata.company.permitKey == "warehouse")
    assert(#carrier.params == 1 and carrier.resName == library.carrier)
    assert(library.getRevision() == 1 and #outgoing == 1)
end)
test("resource callback returns supplied nested template without api or app", function()
    local exports = script("blueprint/saved_single.script.lua")
    local params = {blueprintTemplate = core.toTemplate(disk.templates[1], api.res)}
    local previousApp, previousApi = app, api
    app, api = nil, nil
    local built = exports.createTemplateFn({}, params).constructions[1]
    app, api = previousApp, previousApi
    assert(built.params.seed == 34 and built.params.year == 1940)
    assert(built.modules[632502500] == "::/warehouses/wh_goods.module")
    rejects(function() exports.createTemplateFn({}, {}) end, "缺少单座")
    assert(built ~= params.blueprintTemplate.constructions[1])
    built.params.seed = -1
    assert(params.blueprintTemplate.constructions[1].params.seed == 34)
    for _, payload in ipairs({{constructions = {}}, {constructions = {{}, {}}},
        {constructions = {{constructionFileName = "x", params = {}, modules = false}}}}) do
        rejects(function() exports.createTemplateFn({}, {blueprintTemplate = payload}) end, "缺少单座")
    end
end)
test("existing depot templates with four saved categories are corrected in the menu", function()
    local previousDisk, previousShared = disk, copy(shared)
    local saved = copy(snapshot)
    saved.constructionFileName = "::/depots/rail/rail_depot.con"
    saved.modules, saved.cargoByTag = {}, {}
    saved.categories = {"rail_buildings", "road_buildings", "water_buildings", "air_buildings"}
    api.res.constructionRep.addAsTable(saved.constructionFileName, {description = {}, menuCategory = {categories = {}}})
    disk = {version = 1, nextId = 2, templates = {saved}}
    modules["blueprint_demo::/blueprint/library.lua"] = nil
    local reloaded = require "blueprint_demo::/blueprint/library.lua"
    reloaded.pollSync()
    local cmd = commands[#commands]
    gameScript.handleEvent({}, engineState, cmd.src, cmd.id, cmd.name, cmd.param)
    reloaded.pollSync()
    local cards = reloaded.decorateDefinitions({carrier})
    assert(#cards == 1 and #cards[1].menuCategory.categories == 1)
    assert(cards[1].menuCategory.categories[1].category == "rail_buildings")
    assert(#disk.templates[1].categories == 4) -- 展示修正无需改写用户文件。
    disk = previousDisk
    engineState:set(previousShared)
    modules["blueprint_demo::/blueprint/library.lua"] = library
end)
test("numeric payload preserves Unicode, sparse slots, booleans and number precision", function()
    local original = {constructions = {{
        constructionFileName = "other_mod::/中文建筑.con", modules = {[632502500] = "槽位"},
        params = {name = "车站：甲\n乙", flags = {true, false}, fraction = 1 / 7,
            largeInteger = 9007199254740993, seed = -1234},
    }}}
    local packet = transport.encode(original)
    for _, value in pairs(packet) do assert(type(value) == "number" and value <= 16777215 and value % 1 == 0) end
    assert(core.equal(transport.decode(packet), original))
    local other = core.copy(original)
    other.constructions[1].params.seed = 99
    assert(transport.decode(transport.encode(other)).constructions[1].params.seed == 99)
    assert(transport.decode(packet).constructions[1].params.seed == -1234)
end)
test("incomplete or invalid numeric payload fails explicitly", function()
    local packet = transport.encode({constructions = {}})
    local missing = copy(packet); missing.blueprintWord1 = nil
    rejects(function() transport.decode(missing) end, "不完整")
    local broken = copy(packet); broken.blueprintWord1 = math.huge
    rejects(function() transport.decode(broken) end, "不完整")
    rejects(function() transport.decode({blueprintBytes = 10000000}) end, "缺少有效")
end)
test("versioned persistence preserves sparse maps and reads legacy libraries", function()
    local persistence = require "blueprint_demo::/blueprint/persistence.lua"
    local legacy = {version = 1, nextId = 2, templates = {snapshot}}
    assert(core.equal(persistence.decode(copy(legacy)), legacy))
    local encoded = persistence.encode(legacy)
    assert(encoded.version == 4 and encoded.encoding == "base64" and type(encoded.data) == "table")
    assert(encoded.data.warehouses[1]:match("^[A-Za-z0-9+/=]+$") and encoded.blueprintWord1 == nil)
    local restored = persistence.decode(encoded)
    assert(restored.templates[1].modules[632502500] == "::/warehouses/wh_goods.module")
    assert(restored.templates[1].cargoByTag[632502500] == "::/cargos/coal.cargo")
    assert(core.equal(restored, legacy))
    assert(core.equal(persistence.decode({version = 2, data = transport.encode(legacy)}), legacy))
    local base64 = require "blueprint_demo::/blueprint/base64.lua"
    assert(core.equal(persistence.decode({version = 3, encoding = "base64",
        data = base64.encode(transport.serialize(legacy))}), legacy))
    rejects(function() persistence.decode({version = 2, data = {}}) end, "缺少有效")
    rejects(function() persistence.decode({version = 3, encoding = "unknown", data = "AAAA"}) end, "缺少编码")
    rejects(function() persistence.decode({version = 3, encoding = "base64", data = "!!!!"}) end, "Base64")
end)
test("reload restores local library without runtime resource mutation", function()
    library.save(21)
    assert(disk.nextId == 3)
    modules["blueprint_demo::/blueprint/library.lua"] = nil
    library = require "blueprint_demo::/blueprint/library.lua"
    library.ensureLoaded()
    acknowledge()
    assert(#library.decorateDefinitions({carrier}) == 2)
    local exports = script("blueprint/saved_single.script.lua")
    assert(exports.createTemplateFn({}, {blueprintTemplate = core.toTemplate(disk.templates[2], api.res)}).constructions[1].params.platforms == 3)
end)
test("write failure never publishes or consumes an ID", function()
    local oldRevision = library.getRevision()
    failWrite = true
    rejects(function() library.save(10) end, "disk failure")
    failWrite = false
    assert(disk.nextId == 3 and library.getRevision() == oldRevision)
    assert(library.save(10).id == 3)
    assert(#library.decorateDefinitions({carrier}) == 2)
    acknowledge()
    assert(#library.decorateDefinitions({carrier}) == 3)
end)
test("partial readback is detected before synchronization", function()
    local count, oldRevision = #commands, library.getRevision()
    corruptRead = true
    rejects(function() library.save(10) end, "校验失败")
    corruptRead = false
    library.pollSync()
    assert(#commands == count and library.getRevision() == oldRevision)
end)
test("invalid and unrelated events cannot replace engine snapshots", function()
    local previous = copy(shared)
    gameScript.handleEvent({}, engineState, "", "other_mod", runtime.eventName, {library = disk})
    gameScript.handleEvent({}, engineState, "", runtime.eventId, runtime.eventName, {library = {version = 99}})
    assert(core.equal(shared, previous))
end)
test("missing dependencies hide cards and preserve persisted snapshots", function()
    local find = api.res.moduleRep.find
    api.res.moduleRep.find = function(name)
        if name == "other_mod::/platform.module" then return -1 end
        return find(name)
    end
    assert(#library.decorateDefinitions({carrier}) == 2 and #disk.templates == 4)
    rejects(function() core.toTemplate(disk.templates[2], api.res) end, "缺少资源")
    api.res.moduleRep.find = find
    assert(#library.decorateDefinitions({carrier}) == 3)
end)
test("invalid libraries are never silently overwritten", function()
    local previous = disk
    disk = {version = 99, nextId = 1, templates = {}}
    modules["blueprint_demo::/blueprint/library.lua"] = nil
    local broken = require "blueprint_demo::/blueprint/library.lua"
    local oldWrites = writes
    rejects(function() broken.save(10) end, "不受支持")
    assert(writes == oldWrites and disk.version == 99)
    disk = previous
    modules["blueprint_demo::/blueprint/library.lua"] = library
end)
test("missing static carrier stops saving before file writes", function()
    local find, oldWrites = api.res.metaConstructionRep.find, writes
    api.res.metaConstructionRep.find = function() return -1 end
    rejects(function() library.save(10) end, "重新载入地图")
    api.res.metaConstructionRep.find = find
    assert(writes == oldWrites)
end)
test("engine readiness prevents sends and writes before subscription", function()
    local previous, oldWrites, count = shared, writes, #commands
    entities[99].GAME_SCRIPT.state = {}
    library.pollSync()
    rejects(function() library.save(10) end, "尚未就绪")
    assert(writes == oldWrites and #commands == count)
    entities[99].GAME_SCRIPT.state = previous
end)
test("sync retries without publishing until the engine responds", function()
    library.save(10)
    local count, oldRevision = #commands, library.getRevision()
    for _ = 1, 60 do library.pollSync() end
    assert(#commands == count + 1 and library.getRevision() == oldRevision)
    library.pollSync()
    assert(#commands == count + 2)
    acknowledge()
    assert(library.getRevision() == oldRevision + 1)
    local events = #outgoing
    library.pollSync()
    assert(#outgoing == events)
end)
test("empty icons use native fallbacks and ordinary cards are preserved", function()
    local source = api.res.constructionRep.getAsTable(0)
    local changed = copy(source)
    changed.description.icon, changed.description.previewIcon = "", ""
    api.res.constructionRep.setAsTable(0, changed)
    local saved = library.save(10)
    acknowledge()
    local ordinary = {resName = "ordinary"}
    local definitions = library.decorateDefinitions({ordinary, carrier})
    assert(definitions[1] == ordinary)
    local card = definitions[#definitions]
    assert(card.resName == library.resourceName(saved.id))
    assert(card.icon.icon ~= "" and card.previewIcon.icon ~= "")
    api.res.constructionRep.setAsTable(0, source)
end)
test("menu replacement wraps native definitions and remounts after acknowledgement", function()
    modules["blueprint_demo::/blueprint/manager.lua"] = {install = function() end, setContext = function() end}
    local events, steps, stateValue, calledParams, sent = {}, {}, nil, nil, {}
    local listNode
    local builtin = {List = function(params) return params end}
    local original = function() end
    local parameterWindow = function() end
    local ordinaryWindow = function() end
    local parameterKey, parameterRef, mainKey, mainRef
    local windowApi = {addSingletonWindow = function(recipe, params)
        if recipe == parameterWindow then
            local key = params.meta and params.meta.localKey
            if not parameterRef or key ~= parameterKey then
                parameterKey, parameterRef = key, {owner = params.constructionListRef}
                params.initRef(parameterRef)
            end
        else
            assert(recipe == ordinaryWindow and params.meta.localKey == "ordinary-window")
        end
    end}
    local react = {
        RegisterWrapperRecipe = function(_name, wrapped, fn) assert(wrapped == original); return fn end,
        useState = function(value)
            stateValue = stateValue or value
            return {old = function() return stateValue end, set = function(_, v) stateValue = v end}
        end,
        useRef = function(value) return {get = function() return value end, set = function(_, v) value = v end} end,
        onEvent = function(name, fn) events[name] = fn end,
        fireEvent = function(_, name, param)
            sent[name] = param
            if events[name] then events[name](name, param) end
        end,
        onStep = function(fn) steps[#steps + 1] = fn end,
        useSelfRef = function() return {get = function() return listNode end} end,
        GetRecipeName = function(recipe) return recipe == parameterWindow and "ConstructionParamsWindow" or "OtherWindow" end,
        CallOriginalRecipe = function(window, params)
            assert(window == original); calledParams = params
            if params.payload.toolParam and params.payload.toolParam.gameCtx and mainKey ~= params.meta.localKey then
                if mainRef then mainRef.alive = false end
                mainKey, mainRef = params.meta.localKey, {alive = true}
                local owner = mainRef
                windowApi.addSingletonWindow(parameterWindow, {
                    constructionListRef = owner,
                    initRef = function(ref) owner.parameters = ref end,
                })
            end
            return 42
        end,
    }
    local ui = {
        getConstructionDefinitions = function() return {carrier} end,
        getActionParams = function(definition)
            return {constructionActionParams = {constructionBuilder = {height = 3,
                builderAudioRes = definition.builderAudioRes}}}
        end,
    }
    api.engine.util.construction = {getConstructionResult = function(name, index, params)
        error("Menu refresh must not evaluate building scripts")
    end}
    function ug_require(name)
        if name:find("react.lua", 1, true) then return react end
        if name:find("builtin.lua", 1, true) then return builtin end
        if name:find("construction_react_util", 1, true) then return ui end
        if name:find("construction_desc_react_util", 1, true) then
            return {getAttributesFromConstructionResult = function(result) return result.attributes end}
        end
        return original
    end
    api.gui = {byId = {setVisible = function(id, value) assert(id == "menu.construction.react" and value) end},
        fireReactEvent = function(name, param)
            sent[name] = param
            if events[name] then events[name](name, param) end
        end}
    local installed
    script("blueprint/menu_refresh.script.lua").install({ReplaceRecipe = function(window, replacement)
        assert(window == original); installed = replacement
    end})
    -- 地图初始化及工具栈未就绪时，原生窗口的 setActionFn 可以缺省。
    assert(installed({payload = {toolParam = {}}}) == 42)
    events.blueprintLibraryChanged(nil, {})
    assert(sent.constructionMenuQuit == nil)
    steps = {}
    local cleared = false
    local param = {payload = {
        setActionFn = function(action) assert(action == nil); cleared = true end,
        toolParam = {gameCtx = {windowContainer = {get = function()
            return {getApi = function() return windowApi end}
        end}}},
    }}
    assert(installed(param) == 42 and calledParams.payload == param.payload)
    assert(mainRef.parameters and mainRef.parameters.owner == mainRef and mainRef.alive)
    local oldMainRef = mainRef
    windowApi.addSingletonWindow(ordinaryWindow, {meta = {localKey = "ordinary-window"}})
    assert(#ui.getConstructionDefinitions() == #disk.templates)
    local card = ui.getConstructionDefinitions()[1]
    assert(type(card.attributes) == "table" and not card.costsYearProgression)
    local action = ui.getActionParams(card)
    assert(action.constructionActionParams.constructionBuilder.constructions[1] == library.carrier)
    assert(core.equal(action.constructionActionParams.constructionBuilder.builderAudioRes, card.builderAudioRes))
    assert(#card.builderAudioRes == 1)
    assert(action.constructionActionParams.constructionBuilder.params.blueprintTemplate.constructions[1])
    local keyBefore = calledParams.meta.localKey
    local saved, resource = library.save(10)
    assert(not cleared)
    steps[1]()
    local cmd = commands[#commands]
    gameScript.handleEvent({}, engineState, cmd.src, cmd.id, cmd.name, cmd.param)
    for _ = 1, 4 do steps[1]() end
    assert(cleared and sent.constructionMenuSelectTabForConstruction.resName == resource)
    assert(installed(param) == 42 and calledParams.meta.localKey ~= keyBefore)
    assert(not oldMainRef.alive and mainRef.parameters and mainRef.parameters.owner == mainRef)
    assert(parameterRef.owner.alive and parameterKey == "blueprint-params-" .. tostring(library.getRevision()))
    local selected, definitions = nil, {{resName = "ordinary-road-stop"}, {resName = resource}}
    listNode = {getApi = function() return {getDefinition = function(index) return definitions[index] end} end}
    builtin.List {meta = {tag = "construction-menu.construction-definitions-list"}, children = {1, 2},
        onSelect = function(index) selected = index end}
    steps[#steps]()
    assert(selected == 2, "Refresh must select the saved blueprint rather than the first native road stop")
    selected = nil
    steps[#steps]()
    assert(selected == nil, "Selection must run once without overriding later user clicks")
end)
test("save tooltip satisfies the game's layout-only contract", function()
    local recipes, selector = {}, nil
    local react = {RegisterRecipe = function(name, fn) recipes[name] = fn; return fn end}
    local builtin = {
        type = {Orientation = {Vertical = "Vertical"}},
        TextView = function(param) return {kind = "text", text = param.text} end,
        BoxLayout = function(param) return {kind = "layout", children = param.children} end,
    }
    local ui = {RegisterCustomSelectorBasedActionRecipe = function(_name, callbacks)
        selector = callbacks; return function() end
    end}
    function ug_require(name)
        if name:find("react.lua", 1, true) then return react end
        if name:find("builtin.lua", 1, true) then return builtin end
        return ui
    end
    local exports = script("blueprint/save_tool.script.lua")
    local result = recipes.BlueprintSaveFeedback({text = "保存模板"})
    assert(result.kind == "layout" and result.children[1].text == "保存模板")
    assert(selector.onHover({}, 11).param.recipe)
    assert(exports.getDefinition("test.res").customAction.recipe)
end)
test("template management searches and renames only the selected template", function()
    local originals = library.list()
    local id = originals[1].id
    local count = #originals
    library.rename(id, "  铁路模板 [测试]  ")
    local matches = library.list("[测试]")
    assert(#matches == 1 and matches[1].id == id and matches[1].name == "铁路模板 [测试]")
    matches[1].params.seed = -100
    assert(library.list("[测试]")[1].params.seed ~= -100)
    assert(#library.list() == count)
    for index = 2, #originals do assert(core.equal(library.list()[index], originals[index])) end
    acknowledge()
end)
test("descriptions persist, reload, copy and clear without changing other templates", function()
    local previous = library.list()
    local id = previous[1].id
    local description = "货运站 <测试> & 模块\n第二行 " .. string.rep("长描述", 100)
    library.updateMetadata(id, previous[1].name, description)
    assert(disk.templates[1].description == description)
    acknowledge()
    local function menuDescription()
        for _, card in ipairs(library.decorateDefinitions({carrier})) do
            if card.resName == library.resourceName(id) then return card.description end
        end
        error("Saved template missing from construction menu")
    end
    assert(menuDescription() == description)
    local restored = require("blueprint_demo::/blueprint/persistence.lua").decode(
        require("blueprint_demo::/blueprint/persistence.lua").encode(disk))
    assert(restored.templates[1].description == description)
    for index = 2, #previous do assert(core.equal(library.list()[index], previous[index])) end
    local duplicate = library.duplicate(id)
    assert(duplicate.description == description)
    library.delete(duplicate.id)
    local beforeFailure = library.list()
    failWrite = true
    rejects(function() library.updateMetadata(id, "不会保存", "错误更新") end, "disk failure")
    failWrite = false
    assert(core.equal(beforeFailure, library.list()))
    rejects(function() library.updateMetadata(id, previous[1].name, {}) end, "描述")
    rejects(function() library.updateMetadata(id, previous[1].name, string.rep("x", 4097)) end, "描述")
    library.updateMetadata(id, previous[1].name, "")
    assert(library.list()[1].description == "")
    acknowledge()
    assert(menuDescription() == _("BLUEPRINT_SAVED_DESCRIPTION"))
end)
test("copy and deletion preserve monotonic IDs and other template contents", function()
    local originals = library.list()
    local nextId = disk.nextId
    local duplicate = library.duplicate(originals[1].id)
    assert(duplicate.id == nextId and disk.nextId == nextId + 1)
    assert(core.equal(duplicate.modules, originals[1].modules) and core.equal(duplicate.params, originals[1].params))
    assert(#library.list() == #originals + 1)
    library.delete(duplicate.id)
    assert(#library.list() == #originals and disk.nextId == nextId + 1)
    assert(core.equal(library.list(), originals))
    acknowledge()
end)
test("management rejects invalid targets and retains state when persistence fails", function()
    local previous, oldWrites = library.list(), writes
    rejects(function() library.rename(previous[1].id, "   ") end, "不能为空")
    rejects(function() library.delete(999999) end, "不存在")
    assert(writes == oldWrites)
    failWrite = true
    rejects(function() library.rename(previous[1].id, "不会保存") end, "disk failure")
    rejects(function() library.delete(previous[1].id) end, "disk failure")
    failWrite = false
    assert(core.equal(library.list(), previous))
end)
test("manager opens independently without replacing native UI and renders searchable preview rows", function()
    local recipes, states, cursor = {}, {}, 0
    local handlers = {}
    local function node(kind)
        return function(params) return {kind = kind, params = params} end
    end
    local builtin = {type = {
        Orientation = {Vertical = "vertical", Horizontal = "horizontal"},
        ImageViewScaling = {AutoFit = "fit"}, ScrollBarPolicy = {AlwaysOff = "off", AsNeeded = "auto"},
    }}
    for _, name in ipairs({"Window", "Component", "Button", "ToggleButtonGroup", "TextView", "RichTextView", "ImageView", "TextInputField", "BoxLayout", "ScrollArea", "FloatingLayout", "FloatingLayoutChild"}) do
        builtin[name] = node(name)
    end
    builtin.Component = function(params)
        local layouts = {BoxLayout = true, FloatingLayout = true, TableLayout = true, FlowLayout = true}
        assert(params.layout and layouts[params.layout.kind], "Item of Component must be a layout")
        return {kind = "Component", params = params}
    end
    rejects(function() builtin.Component {layout = builtin.ToggleButtonGroup {buttons = {}}} end,
        "Item of Component must be a layout")
    builtin.ScrollArea = function(params)
        assert(params.content.kind == "Component", "ScrollArea does not accept a Layout as content")
        return {kind = "ScrollArea", params = params}
    end
    local react = {
        RegisterWrapperRecipe = function(name, _, fn) recipes[name] = fn; return fn end,
        useState = function(initial)
            cursor = cursor + 1
            local index = cursor
            if states[index] == nil then states[index] = {value = initial} end
            local state = states[index]
            return {old = function() return state.value end, set = function(_, value) state.value = value end}
        end,
        onEvent = function(name, fn) handlers[name] = fn end, onStep = function() end,
        fireEvent = function(_, name, payload) if handlers[name] then handlers[name](name, payload) end end,
    }
    function ug_require(name)
        if name:find("react.lua", 1, true) then return react end
        if name:find("builtin.lua", 1, true) then return builtin end
        return {makeStyle = function(value) return value end}
    end
    modules["blueprint_demo::/blueprint/manager.lua"] = nil
    local manager = require "blueprint_demo::/blueprint/manager.lua"
    local shown, windowRecipe = {}, nil
    local windowApi = {
        addSingletonWindow = function(recipe) windowRecipe = recipe end,
        moveSingletonWindowToFront = function(recipe) assert(recipe == windowRecipe) end,
    }
    local context = {windowContainer = {get = function() return {getApi = function() return windowApi end} end}}
    api.gui = {byId = {setVisible = function(id, visible) shown[id] = visible end}}
    local nativeWindow, nativeButton, nativeLayout = builtin.Window, builtin.Button, builtin.FloatingLayout
    manager.open(context)
    assert(builtin.Window == nativeWindow and builtin.Button == nativeButton and builtin.FloatingLayout == nativeLayout)
    assert(shown["blueprint.template.manager"] and windowRecipe)
    manager.install()
    assert(builtin.Window == nativeWindow)
    local closeClicks = 0
    local closeButton = builtin.Button {meta = {class = "fake-builtin-window-close-button"}, onClick = function() closeClicks = closeClicks + 1 end}
    local closeChild = builtin.FloatingLayoutChild {item = closeButton}
    local originalContent = {kind = "native-menu"}
    local originalParams = {children = {originalContent, closeChild}}
    local panel = builtin.FloatingLayout(originalParams).params
    assert(#originalParams.children == 2 and #panel.children == 3)
    assert(panel.children[1] == originalContent and panel.children[3] == closeChild)
    local entry = panel.children[2].params.item.params
    assert(entry.meta.mouseTransparent and entry.children[2].params.meta.mouseTransparent)
    assert(entry.children[1].params.content.params.text == "模板管理")
    entry.children[1].params.onClick()
    panel.children[3].params.item.params.onClick()
    assert(closeClicks == 1)
    cursor = 0
    local window = windowRecipe({})
    assert(window.kind == "Window" and window.params.id == "blueprint.template.manager")
    local children = window.params.content.params.children
    assert(children[2].kind == "ScrollArea")
    assert(children[2].params.content.kind == "Component")
    local rows = children[2].params.content.params.layout.params.children
    local function rowColumns(row)
        return row.params.children
    end
    assert(#rows == #library.list() and rowColumns(rows[1])[1].kind == "ImageView")
    assert(rowColumns(rows[1])[2].params.layout.params.children[1].kind == "TextView")
    local filterRow = children[1].params.children[3].params.layout.params.children
    assert(filterRow[1].params.meta.styleSheet.size[1] == 600)
    assert(filterRow[2].params.meta.styleSheet.size[1] == 250 and filterRow[2].params.meta.mouseTransparent)
    assert(filterRow[3].kind == "TextView" and filterRow[3].params.meta.styleSheet.size[1] == 100)
    assert(rows[1].params.children[3].params.layout.params.children[1].params.meta.mouseTransparent)
    children[1].params.children[2].params.onTyping("没有这个模板")
    cursor = 0
    local empty = windowRecipe({}).params.content.params.children[2].params.content.params.layout.params.children
    assert(#empty == 1 and empty[1].params.text == "没有匹配的模板")
    children[1].params.children[2].params.onCancel()
    local function renderRows()
        cursor = 0
        return windowRecipe({}).params.content.params.children[2].params.content.params.layout.params.children
    end
    local function rowControls(row)
        return row.params.children[3].params.layout.params.children[2].params.layout.params.children
    end
    local firstId = library.list()[1].id
    assert(#rowControls(renderRows()[1]) == 4)
    assert(rowColumns(renderRows()[1])[2].params.layout.params.children[2].kind == "RichTextView")
    rowControls(renderRows()[1])[1].params.onClick()
    local editControls = rowControls(renderRows()[1])
    rowColumns(renderRows()[1])[2].params.layout.params.children[1].params.onTyping("管理窗口修改")
    rowColumns(renderRows()[1])[2].params.layout.params.children[2].params.onTyping("货运 <站> & 换行\n描述")
    editControls[1].params.onClick()
    assert(library.list("管理窗口修改")[1].id == firstId)
    assert(library.list("管理窗口修改")[1].description == "货运 <站> & 换行\n描述")
    assert(rowColumns(renderRows()[1])[2].params.layout.params.children[2].params.text == "货运 &lt;站&gt; &amp; 换行<br>描述")
    local countBefore = #library.list()
    rowControls(renderRows()[1])[2].params.onClick()
    assert(#library.list() == countBefore + 1)
    local copiedId = library.list()[countBefore + 1].id
    rowControls(renderRows()[countBefore + 1])[3].params.onClick()
    assert(#library.list() == countBefore + 1)
    local confirmation = rowControls(renderRows()[countBefore + 1])
    assert(confirmation[1].params.text == "删除此模板？")
    confirmation[3].params.onClick()
    assert(#library.list() == countBefore + 1)
    rowControls(renderRows()[countBefore + 1])[3].params.onClick()
    rowControls(renderRows()[countBefore + 1])[2].params.onClick()
    assert(#library.list() == countBefore)
    for _, saved in ipairs(library.list()) do assert(saved.id ~= copiedId) end
    -- 分类筛选与文本搜索组合；使用原生 ToggleButtonGroup 显示选中状态。
    cursor = 0
    local filter = windowRecipe({}).params.content.params.children[1].params.children[3].params.layout.params.children[1].params.layout.params.children[1]
    assert(filter.kind == "ToggleButtonGroup" and #filter.params.buttons == 6 and filter.params.selected == 1)
    filter.params.onValueChange(4)
    local noWater = renderRows()
    assert(#noWater == 1 and noWater[1].params.text == "没有匹配的模板")
    filter.params.onValueChange(1)
    assert(#renderRows() == #library.list())
    -- 六个原生按钮的索引分别是 1..6，尤其检查最后的仓库按钮。
    local categoryKeys = {"", "rail_buildings", "road_buildings", "water_buildings", "air_buildings", "warehouses"}
    for index, key in ipairs(categoryKeys) do
        filter.params.onValueChange(index)
        cursor = 0
        local filteredWindow = windowRecipe({})
        local filterLine = filteredWindow.params.content.params.children[1].params.children[3].params.layout.params.children
        assert(filterLine[1].params.layout.kind == "BoxLayout")
        assert(filterLine[1].params.layout.params.children[1].params.selected == index)
        local expected = 0
        for _, saved in ipairs(library.list()) do
            local sourceId = api.res.constructionRep.find(saved.constructionFileName)
            local categories = sourceId >= 0 and core.menuCategories(api.res.constructionRep.get(sourceId), saved.constructionFileName)
                or saved.categories
            local matches = key == ""
            for _, value in ipairs(categories) do if value == key then matches = true end end
            if matches then expected = expected + 1 end
        end
        assert(filterLine[3].params.text == tostring(expected) .. " 个模板")
        local actualRows = filteredWindow.params.content.params.children[2].params.content.params.layout.params.children
        assert(expected == 0 and actualRows[1].kind == "TextView" or #actualRows == expected)
    end
    filter.params.onValueChange(1)
    -- 分享弹窗不修改模板库；导入弹窗读取分享文本并新增一个独立 ID。
    local managerRecipe, managerStates = windowRecipe, states
    local shareText = library.exportTemplate(firstId)
    rowControls(renderRows()[1])[4].params.onClick()
    assert(shown["blueprint.template.exchange"])
    states, cursor = {}, 0
    local shareWindow = windowRecipe({})
    local exchangeStates = states
    assert(shareWindow.params.title == "分享蓝图")
    assert(shareWindow.params.content.params.children[2].params.value == shareText)
    shareWindow.params.onClose()
    assert(not shown["blueprint.template.exchange"])
    states, cursor, windowRecipe = managerStates, 0, managerRecipe
    local header = windowRecipe({}).params.content.params.children[1].params.children
    assert(header[1].params.layout.params.children[1].params.meta.styleSheet.size[1] == 830)
    header[1].params.layout.params.children[2].params.onClick()
    states, cursor = exchangeStates, 0
    local importRecipe = windowRecipe
    local importWindow = importRecipe({})
    assert(importWindow.params.title == "导入蓝图")
    importWindow.params.content.params.children[2].params.onTyping(shareText)
    cursor = 0
    importWindow = importRecipe({})
    assert(importWindow.params.content.params.children[3].params.text:find("管理窗口修改", 1, true))
    local beforeImport = #library.list()
    importWindow.params.content.params.children[5].params.layout.params.children[2].params.layout.params.children[2].params.onClick()
    assert(#library.list() == beforeImport + 1 and not shown["blueprint.template.exchange"])
    states, cursor, windowRecipe = managerStates, 0, managerRecipe
    -- 切换语言并重新加载管理器，验证真实界面调用点和已保存名称。
    testLanguage = "en"
    modules["blueprint_demo::/blueprint/manager.lua"] = nil
    states, cursor = {}, 0
    local englishManager = require "blueprint_demo::/blueprint/manager.lua"
    englishManager.open(context)
    local englishWindow = windowRecipe({})
    assert(englishWindow.params.title == "Template Manager · Blueprint")
    local englishChildren = englishWindow.params.content.params.children
    assert(englishChildren[1].params.children[2].params.placeholderText == "Search template names…")
    local englishRows = englishChildren[2].params.content.params.layout.params.children
    assert(rowColumns(englishRows[1])[2].params.layout.params.children[1].params.text == library.list()[1].name)
    assert(rowControls(englishRows[1])[1].params.content.params.text == "Edit")
    assert(rowColumns(englishRows[1])[2].params.layout.params.children[3].params.text:find("modules", 1, true))
    testLanguage = "zh_CN"
end)
test("legacy street station images are repaired without changing saved data or other mods", function()
    local saved = {constructionFileName = "::/stations/street/modular_street_station/modular_terminal.con",
        params = {year = 1950}, modules = {[3] = "::/stations/street/modular_street_station/passenger_platform.module"},
        icon = "::/stations/street/modular_street_station/cargo_era_c.tga",
        previewIcon = "::/stations/street/modular_street_station/menuConstructionStreetStation@2x.tga"}
    local original = copy(saved)
    local icon, preview = core.templateImages(saved)
    assert(icon == "::/stations/street/modular_street_station/passenger_era_b.tga")
    assert(preview == "::/stations/street/modular_street_station/passenger_era_b_preview.tga")
    assert(core.equal(saved, original))
    saved.modules[3] = "::/stations/street/modular_street_station/cargo_platform.module"
    saved.params.year = 2000
    icon, preview = core.templateImages(saved)
    assert(preview == "::/stations/street/modular_street_station/icons/cargo_era_c_universal_preview.tga")
    saved.constructionFileName = "other_mod::/station.con"
    assert(core.templateImages(saved) == saved.icon)
end)
test("missing station year is supplied for new snapshots and legacy builder payloads", function()
    local original = entities[20].CONSTRUCTION.params.year
    entities[20].CONSTRUCTION.params.year = nil
    local saved = core.capture(20, 100, api.engine, api.type.ComponentType, api.res)
    assert(saved.params.year == 1950)
    entities[20].CONSTRUCTION.params.year = original
    saved.params.year = nil
    local template = core.toTemplate(saved, api.res, 1970)
    assert(template.constructions[1].params.year == 1970 and saved.params.year == nil)
    saved.params.year = 1920
    assert(core.toTemplate(saved, api.res, 1970).constructions[1].params.year == 1920)
end)
test("translations reorder named values, preserve user text and fall back to English", function()
    local tr = require "blueprint_demo::/blueprint/i18n.lua"
    testLanguage = "en"
    assert(tr("BLUEPRINT_DEFAULT_NAME", {name = "车站 100% {name}", id = 7}) == "车站 100% {name} · Template 7")
    rejects(function() core.validate({}) end, "Unsupported template format")
    testLanguage = "fr"
    assert(tr("BLUEPRINT_COUNT", {count = 3}) == "3 templates")
    testLanguage = "test"
    TRANSLATIONS.test = {BLUEPRINT_DEFAULT_NAME = "{id}: {name}"}
    assert(tr("BLUEPRINT_DEFAULT_NAME", {name = "玩家命名", id = 7}) == "7: 玩家命名")
    assert(_("UNKNOWN_TRANSLATION") == "UNKNOWN_TRANSLATION")
    TRANSLATIONS.test = nil
    testLanguage = "zh_CN"
    assert(tr("BLUEPRINT_COUNT", {count = 3}) == "3 个模板")
end)
test("saved cards inherit building sounds and provide a native fallback", function()
    acknowledge()
    local source = api.res.constructionRep.get(0)
    local previous = source.soundConfig
    source.soundConfig = {builderAudioRes = "other_mod::/warehouse.builder_audio"}
    local ordinary = {resName = "ordinary", builderAudioRes = {"ordinary_sound"}}
    local cards = library.decorateDefinitions({ordinary, carrier})
    assert(cards[1] == ordinary and ordinary.builderAudioRes[1] == "ordinary_sound")
    local found = false
    for _, card in ipairs(cards) do
        if card.blueprintTemplate then
            local payload = card.blueprintTemplate
            if payload.constructions[1].constructionFileName == "::/warehouses/warehouse.con" then
                assert(card.builderAudioRes[1] == source.soundConfig.builderAudioRes)
                found = true
            end
        end
    end
    assert(found)
    for _, soundConfig in ipairs({{}, {builderAudioRes = ""}}) do
        source.soundConfig = soundConfig
        for _, card in ipairs(library.decorateDefinitions({carrier})) do
            local payload = card.blueprintTemplate
            if payload.constructions[1].constructionFileName == "::/warehouses/warehouse.con" then
                assert(card.builderAudioRes[1] == "::/gui/construction/sound/buildoze_construction_large.builder_audio")
            end
        end
    end
    source.soundConfig = previous
    assert(carrier.builderAudioRes == nil)
end)
test("default names reset only when empty and remain separate from internal IDs", function()
    local nextId = disk.nextId
    for _, saved in ipairs(library.list()) do library.delete(saved.id) end
    assert(disk.nextId == nextId and disk.nextNameNumber == 1)
    local first = library.save(10)
    assert(first.id == nextId and first.name == "货物仓库 · 模板 1")
    local duplicate = library.duplicate(first.id)
    assert(duplicate.id == nextId + 1 and disk.nextNameNumber == 2)
    local second = library.save(10)
    assert(second.id == nextId + 2 and second.name == "货物仓库 · 模板 2")
    library.delete(first.id)
    assert(disk.nextNameNumber == 3)
    modules["blueprint_demo::/blueprint/library.lua"] = nil
    library = require "blueprint_demo::/blueprint/library.lua"
    failWrite = true
    rejects(function() library.save(10) end, "disk failure")
    failWrite = false
    assert(disk.nextNameNumber == 3 and disk.nextId == nextId + 3)
    local third = library.save(10)
    assert(third.name == "货物仓库 · 模板 3" and third.id == nextId + 3)
    acknowledge()
    assert(shared.library.nextNameNumber == 4)
end)
test("legacy libraries accept an optional name counter and reject invalid counters", function()
    disk = {version = 1, nextId = 17, templates = {}}
    modules["blueprint_demo::/blueprint/library.lua"] = nil
    library = require "blueprint_demo::/blueprint/library.lua"
    local saved = library.save(10)
    assert(saved.id == 17 and saved.name == "货物仓库 · 模板 1" and disk.nextNameNumber == 2)
    disk = {version = 1, nextId = 18, templates = {saved}}
    modules["blueprint_demo::/blueprint/library.lua"] = nil
    library = require "blueprint_demo::/blueprint/library.lua"
    library.duplicate(saved.id)
    assert(disk.nextNameNumber == 18)
    assert(library.save(10).name == "货物仓库 · 模板 18")
    for _, value in ipairs({0, -1, 1.5, "1", math.huge}) do
        local invalid = copy(disk)
        invalid.nextNameNumber = value
        rejects(function() runtime.validateLibrary(invalid) end, "模板名称序号无效")
    end
end)
test("Base64 follows standard vectors and preserves all byte values", function()
    local base64 = require "blueprint_demo::/blueprint/base64.lua"
    local vectors = {{"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"},
        {"foob", "Zm9vYg=="}, {"fooba", "Zm9vYmE="}, {"foobar", "Zm9vYmFy"}}
    for _, vector in ipairs(vectors) do
        assert(base64.encode(vector[1]) == vector[2])
        assert(base64.decode(vector[2]) == vector[1])
    end
    local bytes = {}
    for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
    local binary = table.concat(bytes) .. "中文\0\n"
    assert(base64.decode(base64.encode(binary)) == binary)
    for _, invalid in ipairs({"A", "!!!!", "=AAA", "A===", "AA=A", "AA==AAAA", "AB==", "AAB="}) do
        rejects(function() base64.decode(invalid) end, "Base64")
    end
end)
test("Base64 library preserves sparse keys and integer precision without evaluating Lua", function()
    local persistence = require "blueprint_demo::/blueprint/persistence.lua"
    local value = {version = 1, nextId = 2, templates = {copy(snapshot)}}
    value.templates[1].params.preciseInteger = 9007199254740993
    value.templates[1].params.preciseFloat = 0.12345678901234567
    value.templates[1].params.enabled = true
    value.templates[1].params.label = "中文 % {name} \0\n return os.execute('invalid')"
    local encoded = persistence.encode(value)
    assert(core.equal(persistence.decode(encoded), value))
    assert(encoded.data.warehouses[1]:find("blueprintWord", 1, true) == nil)
    rejects(function() transport.deserialize("return os.execute('invalid')") end, "类型无效")
end)
test("placement passes nested objects without any numeric codec", function()
    acknowledge()
    local encode, decode = transport.encode, transport.decode
    transport.encode = function() error("Numeric encode must not run during placement") end
    transport.decode = function() error("Numeric decode must not run during placement") end
    local card = library.decorateDefinitions({carrier})[1]
    assert(card and card.blueprintTemplate and card.blueprintPayload == nil)
    local action = {constructionActionParams = {constructionBuilder = {
        height = 3, rotation = 1.2, params = {paramX = 1, year = 2000}}}}
    library.applyBuilderPayload(card, action)
    local builder = action.constructionActionParams.constructionBuilder
    local exports = script("blueprint/saved_single.script.lua")
    local template = exports.createTemplateFn({}, builder.params)
    assert(core.equal(template, card.blueprintTemplate))
    assert(builder.height == 3 and builder.rotation == 1.2 and builder.params.paramX == 1)
    local slot, module = next(card.blueprintTemplate.constructions[1].modules)
    assert(template.constructions[1].modules[slot] == module)
    builder.params.blueprintTemplate.constructions[1].params.seed = -999
    assert(card.blueprintTemplate.constructions[1].params.seed ~= -999)
    transport.encode, transport.decode = encode, decode
end)
test("legacy numeric construction parameters still work without api or app", function()
    local template = core.toTemplate(snapshot, api.res)
    local packet = transport.encode(template)
    local action = {constructionActionParams = {constructionBuilder = {height = 5, rotation = 0.5}}}
    library.applyBuilderPayload({blueprintPayload = packet}, action)
    local builder = action.constructionActionParams.constructionBuilder
    assert(core.equal(builder.params, packet) and builder.params ~= packet)
    assert(builder.height == 5 and builder.rotation == 0.5)
    local exports = script("blueprint/saved_single.script.lua")
    local previousApp, previousApi = app, api
    app, api = nil, nil
    local restored = exports.createTemplateFn({}, builder.params)
    app, api = previousApp, previousApi
    assert(core.equal(restored, template))
    assert(restored.constructions[1].modules[632502500] == "::/warehouses/wh_goods.module")
    local broken = copy(packet)
    broken.blueprintWord1 = nil
    rejects(function() exports.createTemplateFn({}, broken) end, "不完整")
    local mixed = copy(packet)
    mixed.blueprintTemplate = {constructions = {}}
    rejects(function() exports.createTemplateFn({}, mixed) end, "缺少单座")
    mixed.blueprintTemplate = template
    assert(core.equal(exports.createTemplateFn({}, mixed), template))
end)
test("version 1, 2 and 3 files load unchanged and migrate only on a successful edit", function()
    local persistence = require "blueprint_demo::/blueprint/persistence.lua"
    local previousDisk, loadUserdata, saveUserdata = disk, app.loadUserdata, app.saveUserdata
    local original = {version = 1, nextId = 2, templates = {copy(snapshot)}}
    original.templates[1].params.preciseInteger = 9007199254740993
    for _, version in ipairs({1, 2, 3}) do
        local stored = version == 1 and copy(original) or {version = 2, data = transport.encode(original)}
        if version == 3 then
            local base64 = require "blueprint_demo::/blueprint/base64.lua"
            stored = {version = 3, encoding = "base64", data = base64.encode(transport.serialize(original))}
        end
        disk = copy(original)
        app.loadUserdata = function() return copy(stored) end
        app.saveUserdata = function(directory, file, value)
            saveUserdata(directory, file, value)
            stored = copy(value)
        end
        modules["blueprint_demo::/blueprint/library.lua"] = nil
        local reloaded = require "blueprint_demo::/blueprint/library.lua"
        local oldWrites = writes
        assert(core.equal(reloaded.list(), original.templates))
        assert(writes == oldWrites and stored.version == version)
        failWrite = true
        rejects(function() reloaded.rename(snapshot.id, "迁移模板") end, "disk failure")
        failWrite = false
        assert(stored.version == version and core.equal(reloaded.list(), original.templates))
        reloaded.rename(snapshot.id, "迁移模板")
        assert(stored.version == 4 and stored.encoding == "base64" and type(stored.data) == "table")
        local restored = persistence.decode(stored)
        assert(restored.templates[1].name == "迁移模板")
        restored.templates[1].name = original.templates[1].name
        assert(core.equal(restored, original))
    end
    disk, app.loadUserdata, app.saveUserdata = previousDisk, loadUserdata, saveUserdata
    modules["blueprint_demo::/blueprint/library.lua"] = library
end)
test("version 4 groups independently decoded templates and preserves cross-category order", function()
    local persistence = require "blueprint_demo::/blueprint/persistence.lua"
    local base64 = require "blueprint_demo::/blueprint/base64.lua"
    local warehouse = copy(snapshot)
    local rail = copy(snapshot)
    rail.id, rail.constructionFileName, rail.categories = 2, "other_mod::/station.con", {"rail_buildings"}
    local road = copy(snapshot)
    road.id, road.constructionFileName = 3, "::/stations/street/modular_street_station/modular_terminal.con"
    road.categories = {"rail_buildings", "road_buildings", "water_buildings", "air_buildings"}
    local custom = copy(snapshot)
    custom.id, custom.constructionFileName, custom.categories = 4, "other_mod::/custom.con", {"custom_buildings"}
    local original = {version = 1, nextId = 7, nextNameNumber = 3,
        templates = {rail, warehouse, custom, road}}
    local encoded = persistence.encode(original)
    assert(encoded.version == 4 and encoded.nextId == 7 and encoded.nextNameNumber == 3)
    assert(#encoded.data.rail_buildings == 1 and #encoded.data.warehouses == 1)
    assert(#encoded.data.road_buildings == 1 and #encoded.data.custom_buildings == 1)
    assert(#encoded.data.air_buildings == 0 and #encoded.data.water_buildings == 0)
    assert(core.equal(encoded.templateOrder, {2, 1, 4, 3}))
    assert(core.equal(transport.deserialize(base64.decode(encoded.data.road_buildings[1])), road))
    assert(core.equal(persistence.decode(encoded), original))
    local before = encoded.data.rail_buildings[1]
    warehouse.name = "独立修改仓库"
    assert(persistence.encode(original).data.rail_buildings[1] == before)
    local empty = {version = 1, nextId = 100, templates = {}}
    assert(core.equal(persistence.decode(persistence.encode(empty)), empty))
end)
test("version 4 rejects holes, invalid groups, duplicate IDs and missing order entries", function()
    local persistence = require "blueprint_demo::/blueprint/persistence.lua"
    local valid = persistence.encode({version = 1, nextId = 2, templates = {snapshot}})
    local broken = copy(valid)
    broken.data.warehouses[3], broken.data.warehouses[1] = broken.data.warehouses[1], nil
    rejects(function() persistence.decode(broken) end, "不连续")
    broken = copy(valid); broken.data.warehouses.extra = "x"
    rejects(function() persistence.decode(broken) end, "索引无效")
    broken = copy(valid); broken.data.warehouses[2] = broken.data.warehouses[1]
    rejects(function() persistence.decode(broken) end, "重复")
    broken = copy(valid); broken.data.road_buildings = broken.data.warehouses; broken.data.warehouses = {}
    rejects(function() persistence.decode(broken) end, "分类数组无效")
    broken = copy(valid); broken.templateOrder = {}
    rejects(function() persistence.decode(broken) end, "不连续")
    broken = copy(valid); broken.templateOrder[1] = 999
    rejects(function() persistence.decode(broken) end, "重复或无效")
    broken = copy(valid); broken.data.warehouses[1] = "!!!!"
    rejects(function() persistence.decode(broken) end, "Base64")
end)
test("sharing exports one v4 element and import assigns a fresh ID with exact configuration", function()
    local persistence = require "blueprint_demo::/blueprint/persistence.lua"
    local original = library.list()[1]
    local text, name = library.exportTemplate(original.id)
    assert(name == original.name and core.equal(persistence.decodeTemplate(text), original))
    local preview = library.previewImport("\n " .. text .. "\r\n")
    assert(core.equal(preview, original))
    local beforeId, beforeName = disk.nextId, disk.nextNameNumber
    local imported = library.importTemplate(text)
    assert(imported.id == beforeId and disk.nextId == beforeId + 1 and disk.nextNameNumber == beforeName)
    imported.id = original.id
    assert(core.equal(imported, original))
    local nextId, oldWrites = disk.nextId, writes
    rejects(function() library.importTemplate("!!!!") end, "Base64")
    failWrite = true
    rejects(function() library.importTemplate(text) end, "disk failure")
    failWrite = false
    assert(disk.nextId == nextId and writes == oldWrites)
    local missing = copy(original)
    missing.constructionFileName = "missing_mod::/station.con"
    local missingText = persistence.encodeTemplate(missing)
    local _, dependencies = library.previewImport(missingText)
    assert(#dependencies > 0)
    assert(library.importTemplate(missingText).constructionFileName == missing.constructionFileName)
end)
print(tostring(passed) .. " Lua contract tests passed")
