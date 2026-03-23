---Test fixture with invalid generate export (non-function).
---Used to exercise data_loader type validation.
---@module test_fixtures.bad_nonfunc
return {
    generate = "invalid"
}
