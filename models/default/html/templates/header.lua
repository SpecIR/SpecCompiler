---Header bar template.
---Generates the sticky header with search, theme toggle, and mobile menu.
---@module models.default.html.templates.header
local M = {}

---Render the header bar.
---@param opts table Options: project_name
---@return string Header HTML
function M.render(opts)
    local project_name = opts.project_name or "Documentation"
	    return table.concat({
	        '<header class="header">',
	        '  <button class="sidebar-toggle" onclick="SpecCompiler.Sidebar.toggleMobile()" aria-label="Toggle sidebar">',
	        '    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2">',
	        '      <line x1="3" y1="5" x2="17" y2="5"/><line x1="3" y1="10" x2="17" y2="10"/><line x1="3" y1="15" x2="17" y2="15"/>',
	        '    </svg>',
	        '  </button>',
	        '  <div class="header-brand"><a href="#/">' .. project_name .. '</a></div>',
	        '  <nav class="breadcrumbs" id="breadcrumbs" aria-label="Breadcrumbs"></nav>',
	        '  <div class="search-box">',
	        '    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" style="flex-shrink:0;opacity:0.5">',
	        '      <circle cx="6.5" cy="6.5" r="4.5"/><line x1="10" y1="10" x2="14" y2="14"/>',
        '    </svg>',
        '    <input type="text" id="search-input" placeholder="Search specs, requirements, tests..." autocomplete="off">',
        '    <kbd>&#8984;K</kbd>',
        '  </div>',
        '  <div class="header-actions">',
        '    <button type="button" class="pane-toggle" id="btn-toggle-nav" title="Toggle navigation" aria-label="Toggle navigation" aria-pressed="false">',
        '      <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">',
        '        <rect x="3" y="4" width="14" height="12" rx="2"></rect>',
        '        <line x1="7" y1="4" x2="7" y2="16"></line>',
        '      </svg>',
        '    </button>',
        '    <button type="button" class="pane-toggle" id="btn-toggle-inspector" title="Toggle inspector" aria-label="Toggle inspector" aria-pressed="false">',
        '      <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">',
        '        <rect x="3" y="4" width="14" height="12" rx="2"></rect>',
        '        <line x1="13" y1="4" x2="13" y2="16"></line>',
        '      </svg>',
        '    </button>',
        '    <button class="theme-toggle" onclick="SpecCompiler.Theme.toggle()" title="Toggle dark mode" aria-label="Toggle dark mode">',
        '      <span class="theme-icon-light">&#9788;</span>',
        '      <span class="theme-icon-dark">&#9790;</span>',
        '    </button>',
        '  </div>',
        '</header>',
    }, '\n')
end

return M
