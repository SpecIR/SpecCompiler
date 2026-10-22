# PlantUML Diagram Link Cache @SPEC-OUT-013-CACHE

## Diagram Link Cache Invalidation Contract @SEC-OUT-013-CACHE

This test validates that the content-addressed PlantUML render cache is keyed
on the diagram source after its links are lowered to resolved display text:
renaming a linked section or renumbering a linked figure must produce a new
lowered source hash and an SVG showing the new text.
