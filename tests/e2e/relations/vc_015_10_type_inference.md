# Type Inference Test @SRS-INFERENCE

Exercises relation type inference: selector-based dispatch, target type
matching, and specificity scoring for competing rules.

## Section: Reference Targets @SEC-TARGETS

Provides objects and floats as resolution targets.

```fig:test-figure{caption="Test Figure"}
test.png
```

```fig:test-figure-b{caption="Second Test Figure"}
another.png
```

## Section: Float Type Inference @SEC-FLOAT-REFS

Figure reference (should resolve to float via label):
see [fig:test-figure](#).

Second figure (tests multiple XREF_FIGURE inferences):
see [fig:test-figure-b](#).

## Section: Object PID Inference @SEC-PID-REFS

Section reference by PID (should resolve to object):
see [SEC-TARGETS](@).

Cross-reference another section: [SEC-FLOAT-REFS](@).

## Section: Attribute Link Inference @SEC-ATTR-LINKS

Using attributes for traceability-style links:

> traceability: [SEC-TARGETS](@)

This tests that attribute-based links are created and resolved.
