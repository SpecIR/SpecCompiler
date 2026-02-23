# Assembly Order Test @SPEC-ASSEMBLY-001

Test that document assembly preserves file_seq order, not alphabetical from_file order.

## Introduction

This section should appear FIRST (section 1) in the output.

The following include has a filename "_aaa_included.md" that sorts alphabetically
BEFORE "Introduction". If the assembler incorrectly sorts by from_file, the
included content would appear before this Introduction section.

```include
includes/_aaa_included.md
```

## Conclusion

This section should appear LAST in the output.
