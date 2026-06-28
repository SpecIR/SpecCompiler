# Cross-Format Heading Levels @SPEC-XFMT-001

Guards against LaTeX and DOCX diverging on heading depth for the same source.
Both formats consume the same assembled IR, so a `###` section must map to the
same depth in each (`\section` <-> Heading2), never one nesting deeper in one
format than the other.

## Chapter One

Body.

### Section 1.1

Body.

#### Subsection 1.1.1

Body.

## Chapter Two

### Section 2.1
