## Output Requirements

### SF: Multi-Format Publication @SF-004

Assembles transformed content and publishes DOCX/HTML5 outputs with cache-aware emission.


> description: Single-source, multi-target publication. Groups requirements for document
> assembly, float resolution/numbering, and format-specific output generation.

> rationale: Technical documentation must be publishable in multiple formats from a
> single Markdown source.

### HLR: Document Assembly @HLR-OUT-001

The system shall assemble final documents from database content, reconstructing AST from stored fragments.

> rationale: Decouples parsing from rendering for flexibility


> belongs_to: [SF-004](@)

### HLR: Float Resolution @HLR-OUT-002

The system shall resolve [TERM-04](@) references, replacing raw AST with rendered content (SVG, images).

> rationale: Integrates external rendering results into final output


> belongs_to: [SF-004](@)

### HLR: Float Numbering @HLR-OUT-003

The system shall assign sequential numbers to [TERM-04](@)s within [TERM-28](@)s across all documents.

> rationale: Ensures consistent cross-document numbering (Figure 1, 2, 3...)


> belongs_to: [SF-004](@)

### HLR: Multi-Format Output @HLR-OUT-004

The system shall generate outputs in multiple formats (DOCX, HTML5) from a single processed document.

> rationale: Single-source publishing to multiple targets


> belongs_to: [SF-004](@)

### HLR: DOCX Generation @HLR-OUT-005

The system shall generate DOCX output via Pandoc with custom reference documents and OOXML post-processing.

> rationale: Produces Word documents with proper styling


> belongs_to: [SF-004](@)

### HLR: HTML5 Generation @HLR-OUT-006

The system shall generate HTML5 output via Pandoc with web-specific templates and assets.

> rationale: Produces web-ready documentation


> belongs_to: [SF-004](@)
