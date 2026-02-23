## Storage Verification Cases

### VC: SQLite Persistence @VC-007

Verify data persists correctly in [TERM-SQLITE](@) database.

> objective: Confirm all content tables store and retrieve data accurately

> verification_method: Test

> approach:
> - Insert test data into specifications, spec_objects, spec_floats tables
> - Query data back and compare with original
> - Verify foreign key relationships are maintained

> pass_criteria:
> - Inserted data matches queried data exactly
> - Foreign keys resolve to valid parent records
> - Database survives process restart

> traceability: [HLR-STOR-001](@), [LLR-DB-007-01](@), [LLR-DB-007-02](@)


### VC: EAV Attribute Model @VC-008

Verify attributes store in correct typed columns.

> objective: Confirm [TERM-EAV](@) pattern correctly routes values to typed columns

> verification_method: Test

> approach:
> - Run markdown-driven attribute probe through `test_cov` template
> - Cast attributes across STRING, INTEGER, REAL, BOOLEAN, DATE, ENUM, XHTML
> - Exercise `cast_all()` on pending rows with mixed valid/invalid values
> - Verify only the appropriate typed columns are populated

> pass_criteria:
> - STRING values populate string_value column only
> - INTEGER values populate int_value column only
> - ENUM values populate enum_ref column only
> - Exactly one typed column is non-NULL per row
> - Invalid values leave typed columns NULL for proof-view diagnostics

> traceability: [HLR-STOR-002](@), [LLR-DB-008-01](@)


### VC: Build Cache @VC-009

Verify [TERM-30](@) tracks document changes.

> objective: Confirm changed documents are rebuilt, unchanged are skipped

> verification_method: Test

> approach:
> - Build project with 2 documents
> - Modify one document
> - Rebuild and verify only modified document is reprocessed

> pass_criteria:
> - is_document_dirty() returns true for changed documents
> - is_document_dirty() returns false for unchanged documents
> - Include file changes propagate to root documents

> traceability: [HLR-STOR-003](@)


### VC: Output Cache @VC-010

Verify [TERM-31](@) prevents redundant generation.

> objective: Confirm unchanged outputs are not regenerated

> verification_method: Test

> approach:
> - Build project generating DOCX output
> - Rebuild without changes
> - Verify pandoc is not invoked for unchanged outputs

> pass_criteria:
> - is_output_current() returns true when input hash matches
> - Pandoc invocation count is zero for unchanged outputs
> - Cache updates after successful generation

> traceability: [HLR-STOR-004](@)


### VC: Incremental Rebuild @VC-011

Verify incremental rebuild reduces processing time.

> objective: Confirm partial rebuilds are faster than full rebuilds

> verification_method: Demonstration

> approach:
> - Build project with 10 documents (measure time T1)
> - Modify 1 document
> - Rebuild (measure time T2)
> - Compare T2 << T1

> pass_criteria:
> - Incremental build processes only changed documents
> - Build time scales with changes, not project size
> - Include graph correctly identifies dependencies

> traceability: [HLR-STOR-005](@)


### VC: EAV Pivot Views @VC-033

Verify per-object-type SQL views pivot [TERM-EAV](@) attributes into typed columns.

> objective: Confirm eav_pivot module generates correct views for all
> datatypes used by model types, enabling external BI queries against
> flat relational views.

> verification_method: Test

> approach:
> - Process a rich markdown fixture through the sw_docs pipeline
> - Open the pipeline database after processing
> - Query pivot views (view_hlr_objects, view_nfr_objects, etc.)
> - Validate column mapping, NULL handling, enum resolution, WHERE filtering

> pass_criteria:
> - ENUM values resolve to human-readable keys via enum_values join
> - STRING values accessible via pivoted string column
> - XHTML values accessible via pivoted string column
> - Sparse attributes produce NULL for missing values
> - Objects with no attributes show NULL for all attribute columns
> - WHERE filtering works on ENUM, STRING columns
> - Different object types produce separate views with type-specific columns
> - View naming follows view_{type_lower}_objects convention

> traceability: [HLR-STOR-006](@)
