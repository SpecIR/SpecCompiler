# Broken Hierarchy Detection @SPEC-HIER-002

This document is itself well-formed; its oracle drives the fixtures under
`fixtures/` to assert that the `object_broken_hierarchy` verification view
rejects skipped levels and orphaned roots while leaving valid hierarchies
(including deep include chains and ascending levels) untouched.

## Overview

A single valid section keeps this primary document clean.
