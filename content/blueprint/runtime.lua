local core = require "blueprint_demo::/blueprint/core.lua"
local runtime = {
    gameScript = "blueprint_demo::/blueprint/runtime.gs",
    eventId = "blueprint_demo.library",
    eventName = "blueprintDemoSyncLibrary",
}

function runtime.validateLibrary(candidate)
    assert(type(candidate) == "table" and candidate.version == 1, _("BLUEPRINT_LIBRARY_VERSION"))
    assert(type(candidate.templates) == "table", _("BLUEPRINT_MISSING_TEMPLATES"))
    assert(type(candidate.nextId) == "number" and candidate.nextId % 1 == 0 and candidate.nextId >= 1, _("BLUEPRINT_LIBRARY_ID"))
    local ids, count = {}, 0
    for index in pairs(candidate.templates) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0, _("BLUEPRINT_LIST_INDEX"))
        count = count + 1
    end
    assert(count == #candidate.templates, _("BLUEPRINT_LIST_GAPS"))
    for _, snapshot in ipairs(candidate.templates) do
        core.validate(snapshot)
        assert(not ids[snapshot.id] and snapshot.id < candidate.nextId, _("BLUEPRINT_DUPLICATE_ID"))
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
