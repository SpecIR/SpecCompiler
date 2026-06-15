# spec: Host External-Float-Hook Contract @SPEC-EXT-011D

## section: host registry contract @VC-EXT-011

HOST-REGISTRY CONTRACT TEST (VC-EXT-011 family) -- this Markdown body is a
PLACEHOLDER and deliberately uses no float syntax. The oracle exercises the
host's external-float hook INDEX and the register-time mutual-exclusion rule
directly with a mock data manager; it does NOT render anything.

The mutual-exclusion rule (a float may not declare both an internal render and
external prepare_task/handle_result) is a REGISTER-TIME contract that cannot be
expressed in float syntax, so it lives here as a unit check. End-to-end
external rendering (real `puml:` / `chart:` syntax) is covered by the floats
suite (vc_024_01, vc_024_02), gated on the plantuml/echarts toolchain.
