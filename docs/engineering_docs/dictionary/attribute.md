### DIC: Attribute @SpecIR-04

An **Attribute** stores metadata for specifications and spec objects using an Entity-Attribute-Value (EAV) pattern. Attributes are defined in blockquotes following headers and support multiple datatypes including strings, integers, dates, enums, and rich XHTML content (Pandoc AST). Relations are extracted from the AST. Attribute definitions constrain which attributes each object type can have.

> description:
>
> **Formal definition:** `$: A = (tau, beta, cc R)` --- a triple of attribute type, blockquote content, and child relations.
>
> **Syntax:** `> TypeRef: value`
>
> **Datatypes:** STRING, INTEGER, REAL, BOOLEAN, DATE, ENUM, XHTML.
>
> **Full specification:** See the CommonSpec Language Specification for the complete datatype semantics, attribute constraints, and examples.
