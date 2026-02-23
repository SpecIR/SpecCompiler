---Default HTML format-specific styles for SpecCompiler.
---Defines CSS classes, typography, colors, and layout for HTML output.
---Used by the HTML postprocessor for both rendering and web app generation.
---@module models.default.styles.default.html

return {
    name = "Default HTML",
    description = "HTML-specific rendering styles and web app configuration",

    -- ========================================================================
    -- Typography (for web app CSS generation)
    -- ========================================================================
    typography = {
        font_family = "Inter, system-ui, -apple-system, sans-serif",
        font_mono = "JetBrains Mono, Consolas, monospace",
        font_size = "16px",
        line_height = 1.6,
        heading_line_height = 1.3,
    },

    -- ========================================================================
    -- Colors (Clean minimal palette for web app)
    -- ========================================================================
    colors = {
        -- Text
        text = "#1a1a1a",
        text_muted = "#6b7280",
        text_inverse = "#ffffff",
        -- Background
        background = "#ffffff",
        surface = "#f9fafb",
        surface_hover = "#f3f4f6",
        -- Borders
        border = "#e5e7eb",
        border_strong = "#d1d5db",
        -- Accent (links, interactive)
        accent = "#2563eb",
        accent_hover = "#1d4ed8",
        accent_light = "#dbeafe",
        -- Semantic
        success = "#059669",
        warning = "#d97706",
        error = "#dc2626",
        info = "#0284c7",
    },

    -- ========================================================================
    -- Layout (for web app)
    -- ========================================================================
    layout = {
        content_width = "48rem",
        sidebar_width = "280px",
        header_height = "56px",
        spacing_unit = "1rem",
    },

    -- ========================================================================
    -- Object Cards (spec objects display in web app)
    -- ========================================================================
    object_card = {
        background = "#f9fafb",
        border = "#e5e7eb",
        border_radius = "6px",
        padding = "1rem",
        shadow = "0 1px 2px rgba(0, 0, 0, 0.05)",
    },

    -- ========================================================================
    -- Search Panel (web app)
    -- ========================================================================
    search = {
        background = "#ffffff",
        border = "#e5e7eb",
        result_hover = "#f3f4f6",
        highlight = "#fef08a",
    },

    -- ========================================================================
    -- Type Badges (object type indicators in web app)
    -- ========================================================================
    badges = {
        requirement = { background = "#dbeafe", text = "#1e40af" },
        design = { background = "#dcfce7", text = "#166534" },
        test = { background = "#fef3c7", text = "#92400e" },
        section = { background = "#f3f4f6", text = "#374151" },
    },

    -- ========================================================================
    -- Float-specific CSS classes and options (for Pandoc HTML filter)
    -- ========================================================================
    float_styles = {
        FIGURE = {
            container_class = "figure text-center",
            caption_class = "figure-caption",
            caption_position = "after",
        },
        TABLE = {
            container_class = "table-responsive",
            table_class = "table table-bordered",
            caption_class = "table-caption",
            caption_position = "before",
        },
        LISTING = {
            container_class = "code-listing",
            pre_class = "bg-light border p-3",
            code_class = "language-{lang}",
            caption_class = "listing-caption",
            caption_position = "before",
            show_line_numbers = true,
        },
        CHART = {
            container_class = "figure text-center",
            caption_class = "figure-caption",
            caption_position = "after",
        },
        MATH = {
            container_class = "equation-container d-flex justify-content-between align-items-center",
            equation_class = "equation-content flex-grow-1 text-center",
            number_class = "equation-number",
        },
        PLANTUML = {
            container_class = "figure text-center",
            caption_class = "figure-caption",
            caption_position = "after",
        },
    },

    -- Object-specific CSS classes
    object_styles = {
        SECTION = {
            header_class = "section-header",
            body_class = "",
        },
    },
}
