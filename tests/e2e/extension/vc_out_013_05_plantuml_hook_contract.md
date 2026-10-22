# PlantUML Diagram Link Hook Contract @SPEC-OUT-013-HOOKS

## Hook Contract @SEC-OUT-013-HOOKS

This test validates the host contract behind links inside diagrams: the
`format_link` and `mask_comments` float hooks, how they reach model overrides
and subtypes of PLANTUML, the `handle_result` fallback for a model that
overrides only `prepare_task`, the link scanner (escape, comments, line
offsets), and the HTML filter that inlines the SVG rendition.
