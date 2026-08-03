# Include Level Combos @SPEC-COMBO-001

Exercises include level shifting across combinations: a multi-section included
file with internal multi-level structure, several paths in one include block,
a sibling include whose context is not polluted by previously spliced content,
an include under a level-3 heading, single and double `----` pops in the main
file, and an included file that itself closes a section with `----` before
nesting a further include.

## Alpha

The three files below share one include block, so all shift by this section's
level: the multi-section file, a prose-only file (no headings), and a sibling
file that must land at the same depth even though the spliced content before
it descended deeper.

```include
includes/combos/multi_section.md
includes/combos/prose_only.md
includes/combos/sibling.md
```

### Alpha Deep

An include under a level-3 heading: the included `#` lands at level 4.

```include
includes/combos/deep_leaf.md
```

----

The `----` above closes Alpha Deep, so this include lands at level 3, a
sibling of Alpha Deep.

```include
includes/combos/after_close.md
```

----

A second `----` closes Alpha itself, so this include lands at level 2, a
sibling of Alpha.

```include
includes/combos/after_double_close.md
```

## Omega

```include
includes/combos/internal_close.md
```
