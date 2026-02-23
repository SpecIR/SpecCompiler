---Preset fixture used by E2E preset-loader tests.
---Provides a minimal valid preset plus a figure caption prefix.
---@module test_preset_base
return {
    name = "test_preset_base",
    page = {},
    paragraph_styles = {
        { id = "Normal", name = "Normal" },
    },
    captions = {
        figure = {
            prefix = "BaseFigure",
        }
    }
}
