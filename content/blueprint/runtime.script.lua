local runtime = require "blueprint_demo::/blueprint/runtime.lua"
local subscribed = false
function data()
    return {
        update = function(_params, state, _dt)
            if not subscribed then
                state:subscribeToEvent(runtime.eventName)
                subscribed = true
            end
            local value = state:get() or {}
            if not value.ready then
                value.ready = true
                state:set(value)
            end
        end,
        handleEvent = function(_params, state, _src, id, name, param)
            if id ~= runtime.eventId or name ~= runtime.eventName then return end
            local ok, value = pcall(runtime.validateLibrary, type(param) == "table" and param.library)
            if not ok then debugPrint("[Blueprint] 拒绝无效的引擎同步: " .. tostring(value)); return end
            state:set({ready = true, library = value})
        end,
    }
end
