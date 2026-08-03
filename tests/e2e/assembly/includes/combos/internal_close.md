# Close One

An included file that closes its own section before nesting another include.

## Close One A

Body of the child.

----

The `----` above closes Close One A inside this file, so the nested include
lands as its sibling.

```include
inner_leaf.md
```

# Close Two

Ascends back to this file's top level after the nested include.
