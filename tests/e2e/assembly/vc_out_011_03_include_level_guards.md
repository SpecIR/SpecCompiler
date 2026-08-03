# Include Level Guards @SPEC-SHIFT-002

This document is itself well-formed; its oracle drives the fixtures under
`fixtures/` to assert compatibility and guard behavior: files rooted at `##`
or `###` normalize relative to the include point, malformed relative gaps stay
malformed, and computed levels beyond 6 remain distinct through SpecIR and
rendering instead of being rejected or clamped.

## Overview

A single valid section keeps this primary document clean.
