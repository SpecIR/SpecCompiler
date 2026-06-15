# Vendored: luacov 0.15.0

Vendored copy of [luacov](https://github.com/lunarmodules/luacov) (MIT license),
used only by the test suite for coverage (`tests/helpers/coverage.lua`).

**Why it lives here:** the lean distribution image (stock pandoc + the four C
extensions) deliberately does not carry test tooling, and `dist/` / `vendor/` are
git-ignored. The test runner already puts `$SPECCOMPILER_HOME/tests/?.lua` on
`package.path` ([tests/runner.lua](../runner.lua)), so placing luacov here makes
`require("luacov.runner")` resolve in CI (workspace mounted) and natively, without
adding luacov to the shipped image.

Do not edit these files — replace them wholesale to upgrade luacov.
