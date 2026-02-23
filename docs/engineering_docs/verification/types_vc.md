## Types Verification Cases

### VC: Specifications Container @VC-012

Verify specifications table stores document metadata.

> objective: Confirm root documents are correctly stored

> verification_method: Test

> approach:
> - Process document with H1 header containing type and PID
> - Query specifications table
> - Verify all fields populated correctly

> pass_criteria:
> - identifier is SHA1 of root_path
> - long_name extracted from H1 header text
> - type_ref matches header type prefix
> - pid extracted from @PID syntax

> traceability: [HLR-TYPE-001](@)


### VC: Spec Objects Container @VC-013

Verify spec_objects table stores header-based content.

> objective: Confirm H2+ headers create spec_object records

> verification_method: Test

> approach:
> - Process document with H2, H3 headers
> - Query spec_objects table
> - Verify level, title_text, ast fields

> pass_criteria:
> - Each H2+ header creates one record
> - level matches header level (2 for H2, 3 for H3)
> - file_seq preserves document order
> - ast contains body content as JSON

> traceability: [HLR-TYPE-002](@)


### VC: Spec Floats Container @VC-014

Verify spec_floats table stores numbered elements.

> objective: Confirm code blocks create spec_float records

> verification_method: Test

> approach:
> - Process document with figure, table, plantuml code blocks
> - Query spec_floats table
> - Verify label, type_ref, raw_ast fields

> pass_criteria:
> - Each code block with type prefix creates one record
> - label extracted from syntax (e.g., "fig:label")
> - number assigned during [TERM-23](@) phase
> - parent_object_ref links to containing object

> traceability: [HLR-TYPE-003](@)


### VC: Spec Relations Container @VC-015

Verify spec_relations table stores traceability links.

> objective: Confirm @PID and #label links create relation records

> verification_method: Test

> approach:
> - Process document with [text](@REQ-001) and [text](#fig-1) links
> - Process links with normalized/object-header syntax (`[@PID](@)`, `[#PID](@)`)
> - Query spec_relations table
> - Verify source_ref, target_text, type_ref fields

> pass_criteria:
> - Each link creates one relation record
> - source_ref points to containing object
> - target_text contains original link text
> - target_ref populated during [TERM-20](@) phase

> traceability: [HLR-TYPE-005](@)


### VC: Spec Views Container @VC-016

Verify spec_views table stores generated content.

> objective: Confirm view code blocks create spec_view records

> verification_method: Test

> approach:
> - Process document with ```toc and ```lof code blocks
> - Query spec_views table
> - Verify view_type_ref, resolved_ast fields

> pass_criteria:
> - Each view code block creates one record
> - view_type_ref matches view type
> - resolved_ast populated during [TERM-22](@) phase
> - resolved_data contains structured view data

> traceability: [HLR-TYPE-004](@)


### VC: Spec Attributes Container @VC-017

Verify spec_attribute_values table stores object properties.

> objective: Confirm blockquote attributes create attribute_value records

> verification_method: Test

> approach:
> - Process document with > status: draft, > priority: 1 attributes
> - Query spec_attribute_values table
> - Verify name, datatype, typed value columns

> pass_criteria:
> - Each attribute line creates one record
> - owner_ref links to parent object
> - datatype matches attribute definition
> - Value stored in correct typed column

> traceability: [HLR-TYPE-006](@)


### VC: Type Validation @VC-018

Verify proof views detect data integrity violations.

> objective: Confirm validation catches invalid data

> verification_method: Test

> approach:
> - Create document with invalid enum value (SD-102)
> - Create document with missing required attribute (SD-201)
> - Create document with dangling relation (SD-301)
> - Run VERIFY phase, check diagnostics

> pass_criteria:
> - SD-102 violation reported for invalid enum
> - SD-201 violation reported for missing required
> - SD-301 violation reported for dangling reference
> - SD-601/SD-602/SD-603 violations are reported deterministically for broken HLR-VC-TR chains (sw_docs model)
> - SD-605 violation is reported when VC TP artifact path violates TP naming convention
> - SD-606 violation is reported when an FD has no traceability link to a CSC
> - SD-607 violation is reported when an FD has no traceability link to a CSU
> - Error messages include file path and line number

> traceability: [HLR-TYPE-007](@)
