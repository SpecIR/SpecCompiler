# PlantUML Diagram Links in HTML @SPEC-OUT-013-HTML

## HTML Diagram Link Contract @SEC-OUT-013-HTML

This test validates that a PlantUML diagram carrying CommonSpec links is
emitted to HTML as an inline SVG whose hyperlinks point at the resolved
targets: `#ANCHOR` within the document and `other.html#ANCHOR` across
documents. DOCX and Markdown outputs keep the PNG rendition.
