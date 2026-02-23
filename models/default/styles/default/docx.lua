---Default DOCX format-specific styles for SpecCompiler.
---Defines float and object style overrides specific to DOCX output.
---Used by the DOCX filter and postprocessor alongside the main preset.
---@module models.default.styles.default.docx

return {
    name = "Default DOCX",
    description = "DOCX-specific rendering styles",

    -- ========================================================================
    -- Float-specific DOCX options (for filter/postprocessor)
    -- ========================================================================
    float_styles = {
        FIGURE = {
            caption_position = "after",
            center = true,
        },
        TABLE = {
            caption_position = "before",
        },
        LISTING = {
            caption_position = "before",
            paragraph_style = "SourceCode",
        },
        CHART = {
            caption_position = "after",
            center = true,
        },
        MATH = {
            caption_position = "after",
        },
        PLANTUML = {
            caption_position = "after",
            center = true,
        },
    },

    -- ========================================================================
    -- Object-specific DOCX options
    -- ========================================================================
    object_styles = {
        SECTION = {
            heading_style = "auto", -- uses Heading1-5 based on depth
        },
        COVER = {
            heading_style = "none", -- cover page has no heading
        },
        EXEC_SUMMARY = {
            heading_style = "auto",
        },
        REFERENCES = {
            heading_style = "auto",
        },
    },
}
