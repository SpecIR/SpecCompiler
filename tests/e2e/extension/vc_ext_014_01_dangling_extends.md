# spec: Dangling Extends Validation @SPEC-EXT-014

## section: extends target must exist @VC-EXT-014

A type whose `extends` names a type that is not registered by the time the
host finalizes is a silent no-op today: attribute inheritance matches nothing
and the hook chain stops. `host:finalize()` must fail loudly, naming the kind,
the child type, and the missing parent.
