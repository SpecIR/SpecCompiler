# Heading Hierarchy @SPEC-HIER-001

Validates that header levels survive a deep chain of nested includes and that
the assembler maps them to the correct Word Heading styles: sibling chapters
share a style, children nest one level deeper, and ascending back to a
shallower level (the "go back up" case) returns to the shallower style.

The include chain is five files deep (main -> a -> a1 -> b -> b1); includes
never shift levels, so structure is governed purely by the markdown #-count.

## Chapter A

```include
includes/hier/a.md
```

## Chapter C
