# spec: Adjacent Attribute Lines @SPEC-INT-027

## section: Adjacent Lines @VC-INT-027

One blockquote declares ONE attribute (CommonSpec disambiguation rule).
Adjacent `> ` lines -- even ones that look like `key: value` -- continue the
FIRST attribute's value.

> description: tempo
> term: stays inside the description value

Body paragraph after the attribute.

## section: Paragraph Continuation

Distinct attributes require separate, blank-line separated blockquotes; a
`>`-separated paragraph inside one blockquote continues the same attribute.

> description: para one
>
> para two continues the same attribute.
