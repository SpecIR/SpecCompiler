## Pipeline Architecture

### Overview

SpecCompiler uses a layered architecture with the engine orchestrating a five-phase [TERM-15](@) that processes documents through registered [TERM-16](@).

```plantuml:comp-pipeline
@startuml
top to bottom direction
scale 1.5
skinparam componentStyle rectangle
skinparam defaultTextAlignment center
skinparam backgroundColor #FFFFFF
skinparam dpi 150
skinparam packagePadding 10

title Software Architecture — Source Layers (COMP-001)

package "src/core/" as core {
  [CSC-001\nCore Runtime] as csc001
}

package "src/pipeline/" as pipeline {
  [CSC-003\nPipeline Handlers] as csc003
  [CSC-010\nInitialize] as csc010
  [CSC-008\nAnalyze] as csc008
  [CSC-012\nTransform] as csc012
  [CSC-009\nEmit] as csc009
  [CSC-011\nShared] as csc011
}

package "src/db/" as db {
  [CSC-002\nDatabase Persistence] as csc002
  [CSC-005\nDB Queries] as csc005
  [CSC-006\nDB Schema] as csc006
  [CSC-007\nDB Views] as csc007
}

package "src/infra/" as infra {
  [CSC-004\nInfrastructure] as csc004
  [CSC-013\nFormat] as csc013
  [CSC-014\nDOCX] as csc014
  [CSC-015\nI/O] as csc015
  [CSC-016\nProcess] as csc016
}

cloud "models/" as models

' ── Core orchestrates everything ──
csc001 --> csc003 : register handlers
csc001 --> csc002 : data manager
csc001 --> models : load model

' ── Pipeline handlers → Shared ──
csc010 --> csc011
csc008 --> csc011
csc012 --> csc011
csc009 --> csc011

' ── Pipeline handlers → Database ──
csc003 --> csc002 : query / insert
csc008 --> csc005 : SQL queries
csc009 --> csc005 : SQL queries
csc010 --> csc005 : SQL queries

' ── Pipeline handlers → Infrastructure ──
csc009 --> csc004 : format output
csc012 --> csc004 : external rendering

' ── Database internals ──
csc002 --> csc006 : schema init
csc002 --> csc007 : view init

' ── Infrastructure internals ──
csc004 --> csc013 : format writers
csc013 --> csc014 : DOCX generation
csc004 --> csc015 : file I/O
csc004 --> csc016 : Pandoc CLI

@enduml
```

### Component Summary

The architecture comprises **30 CSCs** organized in four source layers and two model packages.
For the complete decomposition with all 162 CSUs, see the [Software Decomposition](software_decomposition.md) chapter.

`csc_decomposition:`
