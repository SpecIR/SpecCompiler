# SRS: Duplicate PID Detection @SRS-DUPE-TEST

> version: 1.0

## HLR: First Requirement @HLR-DUPE

This is the first requirement with a duplicated PID.

Expected error: **object_duplicate_pid** (view_object_duplicate_pid)

> priority: High

## HLR: Second Requirement @HLR-DUPE

This is the second requirement sharing the same PID.

Expected error: **object_duplicate_pid** (view_object_duplicate_pid)

> priority: Mid

## HLR: Control Unique PID @HLR-UNIQUE

This requirement has a unique PID and should not trigger the proof.

> priority: Low
