# Verify View Syntax @SVC-VERIFY-VIEWS

This test validates that legacy/unsupported inline view syntax does not crash
the pipeline and does not emit unexpected SD-5xx diagnostics.

> version: 1.0

## Section: Unsupported View Syntax @SEC-VIEW-SYNTAX

### Unsupported Prefix Is Ignored

The following inline code uses an unregistered view prefix.

`invalid_view_type:`

No SD-5xx error is expected.

### Unregistered Fenced Block Class Is Ignored

The following fenced block uses an unregistered class and should be ignored.

```select:invalid-query{caption="View with SQL syntax error"}
SELEKT * FORM nonexistent_table WHERE invalid syntax
```

No SD-5xx error is expected.

## Section: Valid View Controls @SEC-VALID-VIEWS

### Valid Table of Contents

`toc:`

### Valid List of Figures

`lof:`

### Valid List of Tables

`lot:`

### Valid Abbreviation List

`sigla_list:`

## HLR: Requirement for Views @HLR-FOR-VIEWS

This requirement exists to provide content for the valid views above.

> status: Approved

> priority: High

## HLR: Another Requirement @HLR-ANOTHER

Another requirement to populate the table of contents.

> status: Draft

> priority: Mid
