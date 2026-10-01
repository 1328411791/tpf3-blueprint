local gettext = _
local core = require "blueprint_demo::/blueprint/core.lua"
local runtime = {
    gameScript = "blueprint_demo::/blueprint/runtime.gs",
    eventId = "blueprint_demo.library",
    eventName = "blueprintDemoSyncLibrary",
}

function runtime.validateLibrary(candidate)
    assert(type(candidate) == "table" and candidate.version == 1, gettext("BLUEPRINT_LIBRARY_VERSION"))
    assert(type(candidate.templates) == "table", gettext("BLUEPRINT_MISSING_TEMPLATES"))
    assert(type(candidate.nextId) == "number" and candidate.nextId % 1 == 0 and candidate.nextId >= 1, gettext("BLUEPRINT_LIBRARY_ID"))
    assert(candidate.nextNameNumber == nil or type(candidate.nextNameNumber) == "number"
        and candidate.nextNameNumber % 1 == 0 and candidate.nextNameNumber >= 1,
        gettext("BLUEPRINT_NAME_SEQUENCE"))
    local ids, count = {}, 0
    for index in pairs(candidate.templates) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0, gettext("BLUEPRINT_LIST_INDEX"))
        count = count + 1
    end
    -- Lua 的长度运算符不能判断稀疏数组是否连续；逐项拒绝空洞，避免 ipairs 截断迁移数据。
    for index = 1, count do
        assert(candidate.templates[index] ~= nil, gettext("BLUEPRINT_LIST_GAPS"))
    end
    for index = 1, count do
        local snapshot = candidate.templates[index]
        core.validate(snapshot)
        assert(not ids[snapshot.id] and snapshot.id < candidate.nextId, gettext("BLUEPRINT_DUPLICATE_ID"))
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
