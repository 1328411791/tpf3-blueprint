-- Native presentation helpers. Business state and translated labels stay in manager.lua.
local builtin = ug_require "::/gui/main/builtin.lua"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local ui = {}

ui.theme = {
    cardBackground = {0.19, 0.22, 0.25, 1},
    mutedText = {0.66, 0.71, 0.76, 1},
}

function ui.sized(width, height)
    return {styleSheet = styleutil.makeStyle {size = {width, height}}}
end

-- Native size excludes padding. Copy properties so reusable style tables stay intact.
function ui.layoutMeta(width, height, key, properties, padding, class)
    local style = {}
    for name, value in pairs(properties or {}) do style[name] = value end
    style.size = {width, height}
    local sheet = styleutil.makeStyle(style)
    if padding then sheet.padding = api.type.Vec4f.new(table.unpack(padding)) end
    return {localKey = key, class = class, styleSheet = sheet}
end

function ui.text(value, meta, tooltipWhenClipped)
    return builtin.TextView {text = value, meta = meta, tooltipWhenClipped = tooltipWhenClipped}
end

function ui.escapeText(value)
    return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br>"))
end

-- Plain user text only: callers never need to build HTML for descriptions.
function ui.richText(value, meta)
    return builtin.RichTextView {text = ui.escapeText(value), meta = meta, isHtml = true}
end

function ui.textButton(label, onClick, width)
    return builtin.Button {meta = width and ui.sized(width, 32) or nil,
        content = ui.text(label), onClick = onClick}
end

-- Compact manager actions retain explicit dimensions and the game's font scaling.
function ui.managerButton(label, onClick, key, width, primary)
    return builtin.Button {
        meta = ui.layoutMeta(width or 48, 24, key, nil, {4, 8, 4, 8}, primary and "primary" or "secondary"),
        content = ui.text(label, {class = "font-scale-annotation"}), onClick = onClick,
    }
end

function ui.spacer(width, height)
    local meta = ui.sized(width, height)
    meta.mouseTransparent = true
    return builtin.Component {meta = meta, layout = builtin.BoxLayout {children = {}}}
end

function ui.spaced(children, gap, orientation, meta)
    local result = {}
    for index, child in ipairs(children) do
        if index > 1 then
            result[#result + 1] = orientation == builtin.type.Orientation.Horizontal and ui.spacer(gap, 0) or ui.spacer(0, gap)
        end
        result[#result + 1] = child
    end
    return builtin.BoxLayout {orientation = orientation, children = result, meta = meta}
end

-- row/column return layouts; component wraps a layout into a native Component.
-- These wrappers apply no implicit width, padding, color or spacing.
function ui.row(children, gap, meta)
    if gap then return ui.spaced(children, gap, builtin.type.Orientation.Horizontal, meta) end
    return builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = children, meta = meta}
end

function ui.column(children, gap, meta)
    if gap then return ui.spaced(children, gap, builtin.type.Orientation.Vertical, meta) end
    return builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = children, meta = meta}
end

function ui.component(layout, meta)
    return builtin.Component {layout = layout, meta = meta}
end

-- The template-card preset owns its background, padding and scoped class.
-- Width and height still describe content size, before the 12-unit padding.
function ui.card(layout, width, height, key)
    return ui.component(layout, ui.layoutMeta(width, height, key,
        {backgroundColor = ui.theme.cardBackground}, {12, 12, 12, 12}, "blueprint-manager-card"))
end

return ui
