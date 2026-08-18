# spec: Body sectPr Replacement @SPEC-OOXML-008

## section: Self-Closing Body sectPr @VC-OOXML-008

Pandoc's bundled `reference.docx` does not always carry page setup in the body
section properties. Older Pandoc releases (3.1.x, the stock Ubuntu 24.04
package) ship a reference whose body ends in a self-closing `<w:sectPr/>`,
while newer ones (3.6+) ship a populated `<w:sectPr>...</w:sectPr>`.

`replace_body_sectpr` must target the body-level element in both cases. When it
cannot see a self-closing body sectPr it falls through to the previous match,
which is the paragraph-level section break a template postprocessor injected —
silently discarding that section's page numbering and page setup.

### Requirement: Body-level targeting @REQ-OOXML-008-01

The replacement must apply to the body sectPr and must never overwrite a
paragraph-level section break stored inside `<w:pPr>`.
