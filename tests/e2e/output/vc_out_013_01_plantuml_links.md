# PlantUML Diagram Links @SPEC-OUT-013

## Overview @SEC-OVR

Body links to the same targets: [SEC-DET](@), [SEC-OVR](@), [puml:seq](#)
and [plantuml:seq](#).

```puml:arch{caption="Architecture"}
@startuml
class Foo
class Bar
Foo -[#red]-> Bar : see [SEC-DET](@)
note right of Bar : [plantuml:seq](#) and [SEC-OVR](@)
note left of Foo : [Component] [[http://x label]] [doe2026](@cite)
@enduml
```

## Details @SEC-DET

Details section.

```puml:seq{caption="Sequence"}
@startuml
Alice -> Bob : back to [puml:arch](#)
@enduml
```
