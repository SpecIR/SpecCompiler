# PlantUML Diagram Link Edge Cases @SPEC-OUT-013-EDGE

## Edge Case Contract @SEC-OUT-013-EDGE

This test validates diagram links in situations a real project hits: a
cross-document target in a specification whose file name has a space, links
inside PlantUML comments, `~`-escaped link-like text, a diagram placed before
the first section, a percent width, and a build directory left by a
PNG-only version.
