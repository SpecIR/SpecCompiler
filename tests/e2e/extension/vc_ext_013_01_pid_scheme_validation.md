# spec: PID Scheme Validation @SPEC-EXT-013

## section: pid_scheme registration contract @VC-EXT-013

Object types declare `pid_scheme = "sequential" | "hierarchical"`. The
hierarchical scheme maps onto the legacy `is_composite` storage flag, which
remains accepted as a deprecated alias. Invalid scheme values and declarations
that conflict with the legacy flag are loud register-time errors.
