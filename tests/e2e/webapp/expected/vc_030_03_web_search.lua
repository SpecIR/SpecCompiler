-- Test oracle for VC-WEB-003: FTS Search Functionality
-- Verifies that FTS test spec is parsed correctly with default model

return function(actual_doc, helpers)
    local D = helpers.domain
    local I = helpers.inlines

    -- Strip data-pos tracking spans and ignore remaining data-pos attributes
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    -- Build expected AST using helpers.inlines() for consistent tokenization
    local expected = pandoc.Pandoc(
        {
            -- Spec title
            D.SpecTitle("SPEC-FTS", "FTS Search Test"),

            -- REQ-FTS-OBJ: Object Indexing
            pandoc.Header(1,
                I("Object Indexing"),
                pandoc.Attr("REQ-FTS-OBJ", {}, {})
            ),

            pandoc.Div(
                {pandoc.Para(I("The fts_objects table shall contain indexed spec objects with searchable content."))},
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

            -- REQ-FTS-ATTR: Attribute Indexing
            pandoc.Header(1,
                I("Attribute Indexing"),
                pandoc.Attr("REQ-FTS-ATTR", {}, {})
            ),

            pandoc.Div(
                {pandoc.Para(I("The fts_attributes table shall contain indexed attribute values for faceted search."))},
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

            -- REQ-FTS-QUERY: Query Results
            pandoc.Header(1,
                I("Query Results"),
                pandoc.Attr("REQ-FTS-QUERY", {}, {})
            ),

            pandoc.Div(
                {pandoc.Para(I("Search queries shall return results matching title, content, or raw_source fields."))},
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
            title = pandoc.MetaInlines({pandoc.Str("FTS Search Test")}),
            status = pandoc.MetaInlines(I("Draft"))
        })
    )

    return helpers.assert_ast_equal(actual_doc, expected, helpers.options)
end
