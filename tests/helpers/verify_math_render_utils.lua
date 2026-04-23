-- Run: pandoc lua tests/helpers/verify_math_render_utils.lua
-- Exercises math_render_utils.mathml_to_pandoc_math against known MathML samples.

package.path = "src/?.lua;src/?/init.lua;" .. package.path
local math_utils = require("pipeline.shared.math_render_utils")

local function assert_eq(got, want, msg)
    if got ~= want then
        error(string.format("%s: expected %q, got %q", msg, tostring(want), tostring(got)), 2)
    end
end

local function test_inline()
    local mathml = '<math xmlns="http://www.w3.org/1998/Math/MathML" display="inline">'
        .. '<mrow><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></mrow></math>'
    local elt = math_utils.mathml_to_pandoc_math(mathml, "inline")
    assert(elt, "expected non-nil element")
    assert_eq(elt.t, "Math", "element type")
    assert_eq(elt.mathtype, "InlineMath", "mathtype")
    assert(elt.text:find("E") and elt.text:find("m") and elt.text:find("c"),
        "TeX should contain E, m, c; got: " .. tostring(elt.text))
end

local function test_block()
    local mathml = '<math xmlns="http://www.w3.org/1998/Math/MathML" display="block">'
        .. '<mrow><mi>x</mi><mo>=</mo><mn>1</mn></mrow></math>'
    local elt = math_utils.mathml_to_pandoc_math(mathml, "block")
    assert(elt, "expected non-nil element")
    assert_eq(elt.mathtype, "DisplayMath", "mathtype should be DisplayMath for block")
end

local function test_empty()
    assert(math_utils.mathml_to_pandoc_math("", "inline") == nil, "empty → nil")
    assert(math_utils.mathml_to_pandoc_math(nil, "inline") == nil, "nil → nil")
end

test_inline()
test_block()
test_empty()
print("OK")
