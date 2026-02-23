# spec: EAV Pivot View Test @SPEC-PIVOT

## HLR: Fully Attributed Requirement @HLR-001

This requirement has all HLR attributes populated.

> status: Approved

> priority: High

> rationale:
> This requirement is **critical** for system safety and must be
> implemented in the first release.

## HLR: Sparse Requirement @HLR-002

This requirement has only the status attribute.

> status: Draft

## HLR: Bare Requirement @HLR-003

This requirement has no attributes at all.

## NFR: Performance Constraint @NFR-001

Response time must be under 100 milliseconds.

> status: Approved

> category: Performance

> priority: Mid

> metric: < 100ms p99 latency

> rationale: User experience degrades above 100ms response time.

## NFR: Security Constraint @NFR-002

All API endpoints must require authentication.

> status: Draft

> category: Security

## VC: Pivot View Smoke Test @VC-PIVOT-SMOKE

Verify pivot views are queryable.

> objective: Confirm pivot views expose typed columns for BI queries

> verification_method: Test

> status: Approved

> pass_criteria: All pivot view queries return expected data

## TR: Pivot Smoke Execution @TR-001

Result of executing VC-PIVOT-SMOKE.

> result: Pass

> execution_date: 2025-06-15

> executed_by: ci-runner

> test_file: tests/e2e/pivot/vc_033_01_eav_views.md

> traceability: [VC-PIVOT-SMOKE](@)

## section: Additional Context

This section exercises the default SECTION type (which also gets a pivot view)
to verify multiple types produce separate views.
