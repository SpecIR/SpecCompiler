---Corporate Technical Report Style Preset for SpecCompiler.
---A neutral, globally appropriate document style inspired by modern
---corporate whitepapers and technical documentation.
---12pt Calibri, clean heading hierarchy, A4, structured footer.
---@module preset

return {
    name = "Default",
    description = "Corporate technical report style",

    -- ========================================================================
    -- Page Configuration (A4, ISO 216 international standard)
    -- ========================================================================
    page = {
        size = "A4",
        orientation = "portrait",
        margins = {
            top = "1in",
            bottom = "1in",
            left = "1in",
            right = "1in",
        },
    },

    -- ========================================================================
    -- Paragraph Styles
    -- ========================================================================
    paragraph_styles = {
        {
            id = "Normal",
            name = "Normal",
            font = { name = "Calibri", size = 12 },
            spacing = { line = 1.15, after = 8 },
            indent = { first_line = "0.5in" },
            alignment = "left",
        },
        {
            id = "Heading1",
            name = "Heading 1",
            based_on = "Normal",
            next = "FirstParagraph",
            font = { name = "Calibri Light", size = 18, bold = true, color = "000000" },
            spacing = { before = 12, after = 0, line = 1.15 },
            indent = { first_line = "0in" },
            keep_next = true,
            page_break_before = true,
            outline_level = 0,
        },
        {
            id = "Heading2",
            name = "Heading 2",
            based_on = "Normal",
            next = "FirstParagraph",
            font = { name = "Calibri Light", size = 14, bold = true, color = "000000" },
            spacing = { before = 2, after = 0, line = 1.15 },
            indent = { first_line = "0in" },
            keep_next = true,
            outline_level = 1,
        },
        {
            id = "Heading3",
            name = "Heading 3",
            based_on = "Normal",
            next = "FirstParagraph",
            font = { name = "Calibri", size = 12, bold = true, color = "000000" },
            spacing = { before = 2, after = 0, line = 1.15 },
            indent = { first_line = "0in" },
            keep_next = true,
            outline_level = 2,
        },
        {
            id = "Heading4",
            name = "Heading 4",
            based_on = "Normal",
            next = "FirstParagraph",
            font = { name = "Calibri", size = 12, italic = true, color = "000000" },
            spacing = { before = 2, after = 0, line = 1.15 },
            indent = { first_line = "0in" },
            keep_next = true,
            outline_level = 3,
        },
        {
            id = "Heading5",
            name = "Heading 5",
            based_on = "Normal",
            next = "FirstParagraph",
            font = { name = "Calibri", size = 12, color = "000000" },
            spacing = { before = 2, after = 0, line = 1.15 },
            indent = { first_line = "0in" },
            keep_next = true,
            outline_level = 4,
        },
        {
            id = "Title",
            name = "Title",
            based_on = "Normal",
            next = "FirstParagraph",
            font = { name = "Calibri Light", size = 28, color = "000000" },
            spacing = { after = 4, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "left",
        },
        {
            id = "Caption",
            name = "Caption",
            based_on = "Normal",
            font = { name = "Calibri", size = 9, italic = true },
            spacing = { before = 0, after = 10, line = 1.15 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
        {
            id = "Quote",
            name = "Quote",
            based_on = "Normal",
            font = { name = "Calibri", size = 12, italic = true, color = "404040" },
            spacing = { line = 1.15, before = 10, after = 8 },
            indent = { left = "0.5in", right = "0.5in", first_line = "0in" },
        },
        {
            id = "FirstParagraph",
            name = "First Paragraph",
            based_on = "Normal",
            next = "Normal",
            font = { name = "Calibri", size = 12 },
            spacing = { line = 1.15, after = 8 },
            indent = { first_line = "0in" },
            alignment = "left",
        },
        {
            id = "BodyText",
            name = "Body Text",
            based_on = "Normal",
            font = { name = "Calibri", size = 12 },
            spacing = { line = 1.15, after = 8 },
            indent = { first_line = "0.5in" },
            alignment = "left",
        },
        {
            id = "Header",
            name = "Header",
            based_on = "Normal",
            font = { name = "Calibri", size = 10 },
            spacing = { line = 1.0, after = 0 },
            indent = { first_line = "0in" },
        },
        {
            id = "Footer",
            name = "Footer",
            based_on = "Normal",
            font = { name = "Calibri", size = 10 },
            spacing = { line = 1.0, after = 0 },
            indent = { first_line = "0in" },
        },
        {
            id = "Source",
            name = "Source",
            based_on = "Normal",
            font = { name = "Calibri", size = 9 },
            spacing = { before = 0, after = 4, line = 1.0 },
            indent = { first_line = "0in" },
        },
        {
            id = "Reference",
            name = "Reference",
            based_on = "Normal",
            font = { name = "Calibri", size = 12 },
            spacing = { before = 0, after = 6, line = 1.15 },
            indent = { hanging = "0.5in", left = "0.5in" },
        },
        {
            id = "SourceCode",
            name = "Source Code",
            based_on = "Normal",
            font = { name = "Courier New", size = 10 },
            spacing = { before = 0, after = 0, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "left",
            borders = {
                top    = { style = "single", width = 0.5, color = "CCCCCC" },
                bottom = { style = "single", width = 0.5, color = "CCCCCC" },
                left   = { style = "single", width = 0.5, color = "CCCCCC" },
                right  = { style = "single", width = 0.5, color = "CCCCCC" },
            },
            shading = { pattern = "clear", fill = "F5F5F5" },
        },
        {
            id = "FigureCenter",
            name = "Figure Center",
            based_on = "Normal",
            alignment = "center",
            spacing = { before = 6, after = 6, line = 1.0 },
            indent = { first_line = "0in" },
        },
        -- Table of Contents styles
        {
            id = "TOCHeading",
            name = "TOC Heading",
            based_on = "Normal",
            next = "Normal",
            font = { name = "Calibri Light", size = 18, bold = true, color = "000000" },
            spacing = { before = 0, after = 6, line = 1.15 },
            indent = { first_line = "0in" },
            alignment = "left",
        },
        {
            id = "TOC1",
            name = "TOC 1",
            based_on = "Normal",
            font = { name = "Calibri", size = 12, bold = true, color = "000000" },
            spacing = { before = 6, after = 0, line = 1.15 },
            indent = { first_line = "0in" },
        },
        {
            id = "TOC2",
            name = "TOC 2",
            based_on = "Normal",
            font = { name = "Calibri", size = 12, color = "000000" },
            spacing = { before = 0, after = 0, line = 1.15 },
            indent = { left = "0.25in", first_line = "0in" },
        },
        {
            id = "TOC3",
            name = "TOC 3",
            based_on = "Normal",
            font = { name = "Calibri", size = 12, color = "000000" },
            spacing = { before = 0, after = 0, line = 1.15 },
            indent = { left = "0.5in", first_line = "0in" },
        },
        -- Cover page styles
        {
            id = "CoverTitle",
            name = "Cover Title",
            based_on = "Normal",
            font = { name = "Calibri", size = 28, bold = true, color = "000000" },
            spacing = { before = 0, after = 12, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
        {
            id = "CoverSubtitle",
            name = "Cover Subtitle",
            based_on = "Normal",
            font = { name = "Calibri", size = 16, color = "444444" },
            spacing = { before = 0, after = 8, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
        {
            id = "CoverAuthor",
            name = "Cover Author",
            based_on = "Normal",
            font = { name = "Calibri", size = 12, color = "000000" },
            spacing = { before = 0, after = 4, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
        {
            id = "CoverDate",
            name = "Cover Date",
            based_on = "Normal",
            font = { name = "Calibri", size = 12, italic = true, color = "666666" },
            spacing = { before = 0, after = 4, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
        {
            id = "CoverDocId",
            name = "Cover Document ID",
            based_on = "Normal",
            font = { name = "Calibri", size = 10, color = "888888" },
            spacing = { before = 0, after = 4, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
        {
            id = "CoverVersion",
            name = "Cover Version",
            based_on = "Normal",
            font = { name = "Calibri", size = 10, color = "888888" },
            spacing = { before = 0, after = 4, line = 1.0 },
            indent = { first_line = "0in" },
            alignment = "center",
        },
    },

    -- ========================================================================
    -- Character Styles
    -- ========================================================================
    character_styles = {
        {
            id = "VerbatimChar",
            name = "Verbatim Char",
            font = { name = "Courier New", size = 10 },
        },
        {
            id = "Hyperlink",
            name = "Hyperlink",
            font = { name = "Calibri", color = "000000" },
        },
    },

    -- ========================================================================
    -- Table Styles
    -- ========================================================================
    table_styles = {
        {
            id = "TableGrid",
            name = "Table Grid",
            borders = {
                top = { style = "single", width = 0.5, color = "000000" },
                bottom = { style = "single", width = 0.5, color = "000000" },
                left = { style = "single", width = 0.5, color = "000000" },
                right = { style = "single", width = 0.5, color = "000000" },
                inside_h = { style = "single", width = 0.5, color = "000000" },
                inside_v = { style = "single", width = 0.5, color = "000000" },
            },
            cell_margins = {
                top = "0.05in",
                bottom = "0.05in",
                left = "0.08in",
                right = "0.08in",
            },
            autofit = true,
        },
    },

    -- ========================================================================
    -- Float Source Attribution
    -- ========================================================================
    floats = {
        source_self_text = "Author",     -- Text shown when source="self"
        source_style = "Source",          -- Custom-style for source attribution
        source_template = "Source: %s",   -- Format template for source text
    },

    -- ========================================================================
    -- Caption Formats
    -- ========================================================================
    captions = {
        figure = {
            template = "{prefix} {number}: {title}",
            prefix = "Figure",
            separator = ": ",
            style = "Caption",
            position = "below",
            source_style = "Source",
        },
        table = {
            template = "{prefix} {number}: {title}",
            prefix = "Table",
            separator = ": ",
            style = "Caption",
            position = "above",
            source_style = "Source",
        },
        listing = {
            template = "{prefix} {number}: {title}",
            prefix = "Listing",
            separator = ": ",
            style = "Caption",
            position = "above",
            source_style = "Source",
        },
    },

    -- ========================================================================
    -- Settings
    -- ========================================================================
    settings = {
        default_tab_stop = 720, -- 0.5 inch = 720 twips
        language = "en-US",
    },
}
