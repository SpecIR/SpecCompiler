---Default theme for SpecCompiler HTML documentation app.
---Defines light and dark color schemes, typography, and layout.
---@module models.default.html.themes.default

return {
    name = "Default",

    -- ========================================================================
    -- Light Mode Colors
    -- ========================================================================
    light = {
        -- Text
        text = "#1a1a1a",
        text_muted = "#6b7280",
        text_inverse = "#ffffff",
        -- Background
        bg = "#ffffff",
        surface = "#f9fafb",
        surface_hover = "#f3f4f6",
        -- Borders
        border = "#e5e7eb",
        border_strong = "#d1d5db",
        -- Accent
        accent = "#2563eb",
        accent_hover = "#1d4ed8",
        accent_light = "#dbeafe",
        -- Semantic
        success = "#059669",
        warning = "#d97706",
        error = "#dc2626",
        info = "#0284c7",
        -- UI
        highlight = "#fef08a",
        card_bg = "#f9fafb",
        card_border = "#e5e7eb",
        code_bg = "#f8f8f8",
        sidebar_bg = "#ffffff",
        sidebar_active = "#2563eb",
        -- Syntax highlighting (Pandoc tokens)
        syntax_keyword = "#d73a49",
        syntax_string = "#032f62",
        syntax_comment = "#6a737d",
        syntax_number = "#005cc5",
        syntax_function = "#6f42c1",
        syntax_type = "#e36209",
        syntax_variable = "#24292e",
        syntax_operator = "#d73a49",
        syntax_builtin = "#005cc5",
        syntax_attribute = "#e36209",
    },

    -- ========================================================================
    -- Dark Mode Colors
    -- ========================================================================
    dark = {
        -- Text
        text = "#e5e7eb",
        text_muted = "#9ca3af",
        text_inverse = "#111827",
        -- Background
        bg = "#111827",
        surface = "#1f2937",
        surface_hover = "#374151",
        -- Borders
        border = "#374151",
        border_strong = "#4b5563",
        -- Accent
        accent = "#60a5fa",
        accent_hover = "#93bbfd",
        accent_light = "#1e3a5f",
        -- Semantic
        success = "#34d399",
        warning = "#fbbf24",
        error = "#f87171",
        info = "#38bdf8",
        -- UI
        highlight = "#854d0e",
        card_bg = "#1f2937",
        card_border = "#374151",
        code_bg = "#1e293b",
        sidebar_bg = "#111827",
        sidebar_active = "#3b82f6",
        -- Syntax highlighting (Pandoc tokens)
        syntax_keyword = "#ff7b72",
        syntax_string = "#a5d6ff",
        syntax_comment = "#8b949e",
        syntax_number = "#79c0ff",
        syntax_function = "#d2a8ff",
        syntax_type = "#ffa657",
        syntax_variable = "#e5e7eb",
        syntax_operator = "#ff7b72",
        syntax_builtin = "#79c0ff",
        syntax_attribute = "#ffa657",
    },

    -- ========================================================================
    -- Typography
    -- ========================================================================
    typography = {
        font_family = "Inter, Roboto, system-ui, -apple-system, sans-serif",
        font_mono = "JetBrains Mono, Consolas, monospace",
        font_size = "16px",
        line_height = 1.6,
    },

    -- ========================================================================
    -- Layout
    -- ========================================================================
    layout = {
        content_width = "52rem",
        sidebar_width = "280px",
        inspector_width = "340px",
        header_height = "52px",
    },
}
