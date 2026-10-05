# SRS: Float Orphan Scope Across Files @SRS-VERIFY-ORPHAN-FILES

A float before any heading is an orphan only when its own file has objects.
Here the root file has no objects; all objects live in an included file, so the
figure below must not be reported as `float_orphan`.

> version: 1.0

```fig:root-level-figure{caption="Figure in the root file, which holds no objects"}
root-figure.png
```

```include
includes/vc_018_19_objects.md
```
