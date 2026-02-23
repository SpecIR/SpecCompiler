---Inspector template.
---Right-side contextual pane showing details for the current selection.
---@module models.default.html.templates.inspector
local M = {}

---Render the inspector pane.
---@return string Inspector HTML
function M.render()
    return table.concat({
        '<aside class="inspector" id="inspector" aria-label="Inspector">',
        '  <div class="inspector-header">',
        '    <div class="inspector-header-row">',
        '      <button type="button" class="inspector-back-btn" id="inspector-back-btn" title="Go back" aria-label="Go back" hidden>&#8249;</button>',
        '      <div class="inspector-title" id="inspector-title">Inspector</div>',
        '      <button type="button" class="inspector-follow-toggle" id="inspector-follow-toggle" title="Toggle follow while scrolling" aria-label="Toggle follow while scrolling" aria-pressed="true">Follow</button>',
        '    </div>',
        '  </div>',
        '  <div class="inspector-body" id="inspector-body">',
        '    <div class="inspector-empty">Select an item to see details.</div>',
        '  </div>',
        '</aside>',
    }, '\n')
end

return M
