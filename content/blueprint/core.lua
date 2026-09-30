local tr = require "blueprint_demo::/blueprint/i18n.lua"
-- 只保存建筑输入数据；不复制实体 ID、库存、线路或世界坐标。
local core = {}

function core.copy(value, seen, depth)
    local kind = type(value)
    if kind == "nil" or kind == "string" or kind == "boolean" then return value end
    if kind == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge, _("BLUEPRINT_INVALID_NUMBER"))
        return value
    end
    assert(kind == "table", tr("BLUEPRINT_UNSUPPORTED_VALUE", {type = kind}))
    seen, depth = seen or {}, depth or 0
    assert(depth < 32 and not seen[value], _("BLUEPRINT_PARAM_DEPTH"))
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        assert(type(key) == "string" or type(key) == "number", _("BLUEPRINT_PARAM_KEY"))
        result[core.copy(key)] = core.copy(child, seen, depth + 1)
    end
    seen[value] = nil
    return result
end

function core.equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not core.equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function resourceName(rep, value, context)
    if type(value) == "table" or type(value) == "userdata" then
        -- Construction.params_native 的模块记录使用 name；ModuleDesc 使用 fileName。
        -- 与原生建造菜单读取 modulesTable:find(slot):find("name") 的方式一致。
        value = value.fileName or value.name
    end
    local id = type(value) == "number" and value or (type(value) == "string" and rep.find(value))
    assert(type(id) == "number" and id >= 0, tr("BLUEPRINT_RESOURCE_UNKNOWN", {context = context or _("BLUEPRINT_BUILDING_OR_MODULE"), value = value}))
    local name = rep.getName(id)
    assert(type(name) == "string" and name:find("::", 1, true), tr("BLUEPRINT_RESOURCE_PATH", {name = name}))
    return name
end

function core.normalizeModules(modules, rep)
    local result = {}
    for slot, module in pairs(modules or {}) do
        local slotId = tonumber(slot)
        assert(slotId and slotId % 1 == 0 and slotId >= 0, _("BLUEPRINT_INVALID_MODULE_SLOT"))
        result[slotId] = resourceName(rep, module, tr("BLUEPRINT_MODULE_SLOT", {slot = slotId}))
    end
    return result
end

function core.validate(snapshot)
    assert(type(snapshot) == "table" and snapshot.version == 1, _("BLUEPRINT_SNAPSHOT_VERSION"))
    assert(type(snapshot.id) == "number" and snapshot.id >= 1 and snapshot.id % 1 == 0, _("BLUEPRINT_INVALID_ID"))
    assert(type(snapshot.name) == "string" and #snapshot.name > 0, _("BLUEPRINT_EMPTY_NAME"))
    assert(type(snapshot.constructionFileName) == "string" and snapshot.constructionFileName:find("::", 1, true), _("BLUEPRINT_BUILDING_PATH"))
    assert(type(snapshot.params) == "table" and type(snapshot.modules) == "table", _("BLUEPRINT_MISSING_PARAMS"))
    assert(snapshot.params.modules == nil and snapshot.params.tagToCargoType == nil, _("BLUEPRINT_UNNORMALIZED"))
    assert(type(snapshot.cargoByTag or {}) == "table", _("BLUEPRINT_CARGO_CONFIG"))
    for _, name in pairs(snapshot.cargoByTag or {}) do
        assert(type(name) == "string" and name:find("::", 1, true), _("BLUEPRINT_CARGO_PATH"))
    end
    for slot, name in pairs(snapshot.modules) do
        assert(type(slot) == "number" and slot % 1 == 0 and slot >= 0, _("BLUEPRINT_INVALID_MODULE_SLOT"))
        assert(type(name) == "string" and name:find("::", 1, true), _("BLUEPRINT_MODULE_PATH"))
    end
    assert(type(snapshot.categories) == "table" and #snapshot.categories > 0, _("BLUEPRINT_MISSING_CATEGORY"))
    for _, category in ipairs(snapshot.categories) do
        assert(type(category) == "string" and #category > 0, _("BLUEPRINT_INVALID_CATEGORY"))
    end
    assert(type(snapshot.icon) == "string" and type(snapshot.previewIcon) == "string", _("BLUEPRINT_INVALID_ICON"))
    core.copy(snapshot)
    return snapshot
end

-- 所有子建筑、车站和仓库选取都必须归一到唯一的顶层 Construction。
function core.resolveConstruction(entity, engine, types)
    if type(entity) ~= "number" or entity < 0 or not engine.entityExists(entity) then return nil end
    if engine.getComponent(entity, types.CONSTRUCTION) then return entity end
    local warehouse = engine.getComponent(entity, types.WAREHOUSE)
    if warehouse and warehouse.construction and engine.entityExists(warehouse.construction) then
        return warehouse.construction
    end
    local connector = engine.system.streetConnectorSystem
    local mappings = {
        {types.SUBCONSTRUCTION, connector.getConstructionEntityForSubconstruction},
        {types.STATION, connector.getConstructionEntityForStation},
        {types.DEPOT, connector.getConstructionEntityForDepot},
    }
    for _, mapping in ipairs(mappings) do
        if mapping[1] and engine.getComponent(entity, mapping[1]) then
            local root = mapping[2](entity)
            if root and engine.entityExists(root) and engine.getComponent(root, types.CONSTRUCTION) then return root end
        end
    end
    local group = types.STATION_GROUP and engine.getComponent(entity, types.STATION_GROUP)
    if group then
        local root
        for _, station in pairs(group.stations or {}) do
            local candidate = connector.getConstructionEntityForStation(station)
            if candidate and engine.entityExists(candidate) then
                if root and root ~= candidate then return nil, _("BLUEPRINT_MULTIPLE_BUILDINGS") end
                root = candidate
            end
        end
        return root
    end
    return nil
end

function core.menuCategories(desc, fileName, con, engine, types, transportModes)
    local categories, added = {}, {}
    local function add(category)
        if category and not added[category] then
            added[category] = true
            categories[#categories + 1] = category
        end
    end
    local function readMenu(menu)
        for _, entry in ipairs(menu and menu.categories or {}) do add(entry.category) end
    end
    readMenu(desc.menuCategory)
    if #categories > 0 then return categories end
    -- 原版模块化车站及车库的分类经常只定义在 constructionTemplates 中。
    for _, template in ipairs(desc.constructionTemplates or {}) do readMenu(template.menuCategory) end
    if #categories > 0 then return categories end
    local pathCategories = {
        rail = "rail_buildings", road = "road_buildings", street = "road_buildings",
        water = "water_buildings", air = "air_buildings",
    }
    local directory = fileName:match("/stations/([^/]+)/") or fileName:match("/depots/([^/]+)/")
    add(pathCategories[directory])
    if #categories > 0 then return categories end
    if fileName:find("/warehouses/", 1, true) then return {"warehouses"} end
    if con and engine and types then
        local modeCategories = {
            TRAIN = "rail_buildings", ELECTRIC_TRAIN = "rail_buildings",
            CAR = "road_buildings", BUS = "road_buildings", TRUCK = "road_buildings",
            TRAM = "road_buildings", ELECTRIC_TRAM = "road_buildings",
            SHIP = "water_buildings", SMALL_SHIP = "water_buildings",
            AIRCRAFT = "air_buildings", SMALL_AIRCRAFT = "air_buildings", HELICOPTER = "air_buildings",
        }
        local function readModes(modes)
            for mode, enabled in pairs(modes or {}) do
                if enabled then
                    for name, category in pairs(modeCategories) do
                        if mode == name or transportModes and transportModes[name] == mode then add(category) end
                    end
                end
            end
        end
        for _, child in ipairs(con.stations or {}) do
            local station = engine.getComponent(child, types.STATION)
            for _, terminal in ipairs(station and station.terminals or {}) do readModes(terminal.transportModes) end
        end
        for _, child in ipairs(con.depots or {}) do
            local depotType = types.VEHICLE_DEPOT or types.DEPOT
            local depot = depotType and engine.getComponent(child, depotType)
            if depot then readModes(depot.transportModes) end
        end
        for _, child in ipairs(con.subconstructions or {}) do
            if types.WAREHOUSE and engine.getComponent(child, types.WAREHOUSE) then add("warehouses") end
        end
    end
    table.sort(categories)
    return categories
end

function core.capture(entity, id, engine, types, res, transportModes)
    local root, reason = core.resolveConstruction(entity, engine, types)
    assert(root, reason or _("BLUEPRINT_SELECT_BUILDING"))
    local con = engine.getComponent(root, types.CONSTRUCTION)
    assert(con and #(con.industries or {}) == 0 and #(con.townBuildings or {}) == 0,
        _("BLUEPRINT_PLAYER_BUILDINGS_ONLY"))
    local owner = engine.getComponent(root, types.PLAYER_OWNED)
    assert(owner and owner.player == engine.util.getPlayer(), _("BLUEPRINT_OWN_BUILDINGS_ONLY"))
    local fileName = resourceName(res.constructionRep, con.fileName, _("BLUEPRINT_BUILDING"))
    local desc = res.constructionRep.get(res.constructionRep.find(fileName))
    assert(not desc.edgeObject, _("BLUEPRINT_EDGE_OBJECT"))
    local rawParams = con.params_native and con.params_native:asTable() or con.params
    local modules = core.normalizeModules(rawParams.modules, res.moduleRep)
    local params = {}
    for key, value in pairs(rawParams) do
        if key ~= "modules" then params[key] = core.copy(value) end
    end
    -- 库存货种在引擎中使用临时资源 ID；存储名称，放置时重新解析。
    local cargoByTag = {}
    for tag, cargo in pairs(params.tagToCargoType or {}) do
        cargoByTag[tag] = resourceName(res.cargoTypeRep, cargo, tr("BLUEPRINT_CARGO_SLOT", {slot = tag}))
    end
    params.tagToCargoType = nil
    local categories = core.menuCategories(desc, fileName, con, engine, types, transportModes)
    assert(#categories > 0, _("BLUEPRINT_UNKNOWN_TRANSPORT"))
    local description = desc.description or {}
    local named = engine.getComponent(root, types.NAME)
    local name = named and named.name or description.name or _("BLUEPRINT_BUILDING")
    return core.validate({
        version = 1, id = id, name = tr("BLUEPRINT_DEFAULT_NAME", {name = name, id = id}),
        constructionFileName = fileName, params = params, modules = modules,
        cargoByTag = cargoByTag, categories = categories,
        icon = description.icon or "::/warehouses/icons/wh_goods.tga",
        previewIcon = description.previewIcon or description.icon or "::/warehouses/icons/wh_goods_preview.tga",
    })
end

function core.missingResources(snapshot, res)
    local missing = {}
    if res.constructionRep.find(snapshot.constructionFileName) < 0 then missing[#missing + 1] = snapshot.constructionFileName end
    for _, name in pairs(snapshot.modules) do
        if res.moduleRep.find(name) < 0 then missing[#missing + 1] = name end
    end
    for _, name in pairs(snapshot.cargoByTag or {}) do
        if res.cargoTypeRep.find(name) < 0 then missing[#missing + 1] = name end
    end
    return missing
end

function core.toTemplate(snapshot, res)
    core.validate(snapshot)
    local missing = core.missingResources(snapshot, res)
    assert(#missing == 0, tr("BLUEPRINT_MISSING_RESOURCES", {resources = table.concat(missing, ", ")}))
    local params = core.copy(snapshot.params)
    if next(snapshot.cargoByTag or {}) then
        params.tagToCargoType = {}
        for tag, name in pairs(snapshot.cargoByTag) do params.tagToCargoType[tag] = res.cargoTypeRep.find(name) end
    end
    return {constructions = {{
        constructionFileName = snapshot.constructionFileName,
        modules = core.copy(snapshot.modules), params = params,
        -- 将世界位置与朝向归零，仍可使用原生旋转和高程控件。
        transf = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
    }}}
end

return core
