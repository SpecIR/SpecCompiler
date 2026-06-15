# spec: Inherited Card Render @SPEC-EXT-011B

## section: card render via extends @VC-EXT-011

The standard object-card render lives once on the base type TRACEABLE; leaf
requirement types (HLR, ...) are pure schema and inherit it via the host's
extends-chain dispatch (get_hook_inherited). A type with a custom render (COVER)
declares its own hooks.render and is dispatched directly.
