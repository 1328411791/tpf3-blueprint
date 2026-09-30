local core = require "blueprint_demo::/blueprint/core.lua"
local runtime = {
    gameScript = "blueprint_demo::/blueprint/runtime.gs",
    eventId = "blueprint_demo.library",
    eventName = "blueprintDemoSyncLibrary",
}

function runtime.validateLibrary(candidate)
    assert(type(candidate) == "table" and candidate.version == 1, "模板库格式不受支持；原文件未改动")
    assert(type(candidate.templates) == "table", "模板库缺少 templates")
    assert(type(candidate.nextId) == "number" and candidate.nextId % 1 == 0 and candidate.nextId >= 1, "模板库序号无效")
    local ids, count = {}, 0
    for index in pairs(candidate.templates) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0, "模板库列表索引无效")
        count = count + 1
    end
    assert(count == #candidate.templates, "模板库列表不连续")
    for _, snapshot in ipairs(candidate.templates) do
        core.validate(snapshot)
        assert(not ids[snapshot.id] and snapshot.id < candidate.nextId, "模板库存在重复或无效序号")
        ids[snapshot.id] = true
    end
    return core.copy(candidate)
end

function runtime.readState()
    local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(runtime.gameScript)
    if not entity then return nil end
    local component = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
    return component and component.state or nil
end

return runtime
