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

> traceability: [HLR-TYPE-001](@), [LLR-055](@), [LLR-056](@)


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

> traceability: [HLR-TYPE-002](@), [LLR-057](@), [LLR-058](@), [LLR-059](@)


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
> - number assigned during [dic:emit-phase](#) phase
> - parent_object_ref links to containing object

> traceability: [HLR-TYPE-003](@), [LLR-060](@), [LLR-061](@)


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
> - target_ref populated during [dic:resolve-phase](#) phase

> traceability: [HLR-TYPE-005](@), [LLR-064](@), [LLR-065](@)


### VC: Spec Views Container @VC-016

Verify spec_views table stores view definitions and views render from live data.

> objective: Confirm view code blocks create spec_view records and render at EMIT

> verification_method: Test

> approach:
> - Process document with ```toc and ```lof code blocks
> - Query spec_views table
> - Verify view_type_ref, raw_ast fields
> - Verify the emitted output contains the rendered view content

> pass_criteria:
> - Each view code block creates one record
> - view_type_ref matches view type
> - raw_ast preserves the view definition content
> - View content is rendered live at EMIT from current database state
>   (resolved_ast is populated only by view types that pre-render during
>   [dic:transform-phase](#), e.g. abbreviations)

> traceability: [HLR-TYPE-004](@), [LLR-062](@), [LLR-063](@)


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

> traceability: [HLR-TYPE-006](@), [LLR-066](@), [LLR-067](@)


### VC: Type Validation @VC-018

Verify analyze queries detect data integrity violations.

> objective: Confirm validation catches invalid data

> verification_method: Test

> approach:
> - Create document with invalid enum value (`invalid_enum` / `invalid_cast`)
> - Create document with missing required attribute (`missing_required`)
> - Create document with dangling relation (`dangling_relation`)
> - Run ANALYZE phase, check diagnostics

> pass_criteria:
> - `invalid_enum` or `invalid_cast` violation reported for invalid enum input
> - `missing_required` violation reported for missing required data
> - `dangling_relation` violation reported for dangling references
> - `traceability_vc_to_hlr`, `traceability_tr_to_vc`, and `traceability_hlr_to_vc` are reported deterministically for broken HLR-VC-TR chains (sw_docs model)
> - `traceability_fd_to_csc` violation is reported when an FD has no traceability link to a CSC
> - `traceability_fd_to_csu` violation is reported when an FD has no traceability link to a CSU
> - Error messages include file path and line number

> traceability: [HLR-TYPE-007](@), [LLR-068](@), [LLR-069](@)


### VC: UTF-8 Label Slugification @VC-INT-016

Verify that generated object labels transliterate UTF-8 titles into stable ASCII slugs.

> objective: Confirm object label generation produces deterministic cross-reference labels for titles containing accents, punctuation, and non-ASCII characters.

> verification_method: Test

> approach:
> - Process a document with typed headings containing UTF-8 characters
> - Execute the pipeline through initialization and resolution
> - Query generated `spec_objects.label` values

> pass_criteria:
> - Accented characters are transliterated consistently
> - Punctuation and whitespace normalize to stable slug separators
> - Generated labels remain usable as `(#)` cross-reference targets

> traceability: [HLR-TYPE-002](@), [LLR-057](@), [LLR-058](@), [LLR-059](@)
