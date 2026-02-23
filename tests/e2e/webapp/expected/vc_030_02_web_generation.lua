-- Test oracle for VC-WEB-001: Single-File Generation
-- Verifies that webapp test spec is parsed correctly with default model

return function(actual_doc, helpers)
    local D = helpers.domain
    local I = helpers.inlines

    -- Strip data-pos tracking spans and ignore remaining data-pos attributes
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    -- Build expected AST using helpers.inlines() for consistent tokenization
    local expected = pandoc.Pandoc(
        {
            -- Spec title (rendered as Div, not Header)
            D.SpecTitle("SPEC-WEB-GEN", "Webapp Generation Test"),

            -- REQ-EMBED: Embedded Assets
            pandoc.Header(1,
                I("Embedded Assets"),
                pandoc.Attr("REQ-EMBED", {}, {})
            ),

            pandoc.Div(
                {pandoc.Para(I("The generated index.html shall contain all required embedded assets."))},
                pandoc.Attr("", {}, {})
            ),

            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("status: Draft"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- REQ-SECTIONS: Document Sections
            pandoc.Header(1,
                I("Document Sections"),
                pandoc.Attr("REQ-SECTIONS", {}, {})
            ),

            pandoc.Div(
                {pandoc.Para(I("The generated index.html shall include all document sections."))},
                pandoc.Attr("", {}, {})
            ),

            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("status: Draft"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),
        },
        pandoc.Meta({
            title = pandoc.MetaInlines({pandoc.Str("Webapp Generation Test")}),
            status = pandoc.MetaInlines(I("Draft"))
        })
    )

    return helpers.assert_ast_equal(actual_doc, expected, helpers.options)
end
