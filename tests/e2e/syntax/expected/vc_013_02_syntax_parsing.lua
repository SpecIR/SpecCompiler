-- Test oracle for VC-SYNTAX-001: Specification and Object Parsing
-- Verifies that specs, HLRs, and LLRs are parsed correctly

return function(actual_doc, helpers)
    local D = helpers.domain
    local I = helpers.inlines  -- Use Pandoc tokenization for consistent results

    -- Strip data-pos tracking spans and ignore remaining data-pos attributes
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    -- Build expected AST using helpers.inlines() for consistent tokenization
    local expected = pandoc.Pandoc(
        {
            -- Spec title (rendered as Div, not Header)
            D.SpecTitle("SRS-001", "System Requirements"),

            -- HLR-AUTH-001: Authentication Module
            pandoc.Header(1,
                I("Authentication Module"),
                pandoc.Attr("HLR-AUTH-001", {}, {})
            ),

            -- Body: User authentication requirements.
            pandoc.Div(
                {pandoc.Para(I("User authentication requirements."))},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes blockquote: priority: High
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("priority: High"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes blockquote: rationale: ...
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("rationale: Security is critical for system access."))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- LLR-AUTH-001: Login Functionality
            pandoc.Header(2,
                I("Login Functionality"),
                pandoc.Attr("LLR-AUTH-001", {}, {})
            ),

            -- Body: The system shall provide secure login.
            pandoc.Div(
                {pandoc.Para(I("The system shall provide secure login."))},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes: verification_method: Test
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("verification_method: Test"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- LLR-AUTH-002: Password Policy
            pandoc.Header(2,
                I("Password Policy"),
                pandoc.Attr("LLR-AUTH-002", {}, {})
            ),

            -- Body: Passwords must meet complexity requirements.
            pandoc.Div(
                {pandoc.Para(I("Passwords must meet complexity requirements."))},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes: verification_method: Inspection
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("verification_method: Inspection"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- HLR-AUTHZ-001: Authorization Module
            pandoc.Header(1,
                I("Authorization Module"),
                pandoc.Attr("HLR-AUTHZ-001", {}, {})
            ),

            -- Body: Role-based access control requirements.
            pandoc.Div(
                {pandoc.Para(I("Role-based access control requirements."))},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes: priority: High
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("priority: High"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- LLR-AUTHZ-001: Role Definition
            pandoc.Header(2,
                I("Role Definition"),
                pandoc.Attr("LLR-AUTHZ-001", {}, {})
            ),

            -- Body: System shall support admin, user, and guest roles.
            pandoc.Div(
                {pandoc.Para(I("System shall support admin, user, and guest roles."))},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes: verification_method: Test
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("verification_method: Test"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),

            -- LLR-AUTHZ-002: Permission Matrix
            pandoc.Header(2,
                I("Permission Matrix"),
                pandoc.Attr("LLR-AUTHZ-002", {}, {})
            ),

            -- Body: Each role has defined permissions.
            pandoc.Div(
                {pandoc.Para(I("Each role has defined permissions."))},
                pandoc.Attr("", {}, {})
            ),

            -- Attributes: verification_method: Review
            pandoc.Div(
                {pandoc.BlockQuote({
                    pandoc.Div(
                        {pandoc.Para(I("verification_method: Review"))},
                        pandoc.Attr("", {}, {})
                    )
                })},
                pandoc.Attr("", {}, {})
            ),
        },
        pandoc.Meta({
            title = pandoc.MetaInlines({pandoc.Str("System Requirements")}),
            priority = pandoc.MetaInlines({pandoc.Str("High")}),
            verification_method = pandoc.MetaInlines({pandoc.Str("Review")}),
            version = pandoc.MetaInlines(I("1.0")),
            status = pandoc.MetaInlines(I("Draft"))
        })
    )

    return helpers.assert_ast_equal(actual_doc, expected, helpers.options)
end
