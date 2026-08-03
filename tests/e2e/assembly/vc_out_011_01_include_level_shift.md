# Include Level Shift @SPEC-SHIFT-001

Validates that include expansion shifts the included file's heading levels by
the heading level in effect at the include point (LLR-071). An included file is
authored as a standalone document starting at `#`; its top-level heading nests
one level below the section that contains the include directive. Nested
includes accumulate the shift, and a `----` section close pops the include
context back to the parent level.

## Child Section

Body before the include. The include below sits under a level-2 heading, so
the included `#` becomes `###` and its `##` becomes `####`.

```include
includes/shift/grand_child.md
```

## Sibling After

This heading is authored in the main file and stays at level 2.

----

The `----` above closes "Sibling After", so the next include belongs to the
spec root and its `#` lands at level 2, a sibling chapter.

```include
includes/shift/appendix.md
```
