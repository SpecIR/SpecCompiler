# Unresolved Diagram Links @SVC-VERIFY-DIAGRAM-LINKS

A CommonSpec link inside a PlantUML diagram is diagnosed like a body link:
an unresolved target raises `unresolved_relation` at the exact source line.

> version: 1.0

## Section: Diagram With Links @SEC-DIAG-LINKS

```puml:diag-links{caption="Diagram Links"}
@startuml
Foo --> Bar : ok [SEC-DIAG-TARGET](@)
note right of Bar
  broken [NOPE-999](@)
end note
@enduml
```

## Section: Diagram Link Target @SEC-DIAG-TARGET

Control body link (resolves): [SEC-DIAG-LINKS](@).
