---Preset fixture used by E2E preset-loader tests.
---Extends `test_preset_base` to exercise extends-chain merge behavior.
---@module test_preset_default
return {
    extends = {
        template = "default",
        preset = "test_preset_base"
    },
    name = "test_preset_default",
    page = {},
    paragraph_styles = {
        { id = "Normal", name = "Normal" },
    },
    captions = {
        figure = {
            separator = ":::",
        }
    }
}
