# spec: Manifest-Only Config @SPEC-CFG-001

## section: Config Source Of Truth @VC-CFG-001

This document verifies that build configuration (output format, build
directory, log level) is sourced from project.yaml only. The bogus env
vars set by the oracle must not influence the resolved configuration.
