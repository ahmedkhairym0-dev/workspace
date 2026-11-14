I’m reviewing the user story and the repo’s planning context first so I can reframe it around performance and code quality without carrying over weak implementation details.

Read [](file:///home/hatem/workspace/user%20stories/US-2026-11-0413.md)

Read skill [thermo-nuclear-code-quality-review](file:///home/hatem/.agents/skills/thermo-nuclear-code-quality-review/SKILL.md?vscodeLinkType%3Dskill)

## Replanned user story: Excel child-table sync for Design documents

Based on US-2026-11-0413.md, I am ignoring the file-by-file implementation context because it is a solution detail, not a requirement. The product requirement is the real contract: reliable spreadsheet round-tripping for child tables, with strong validation and clean performance.

### Objective

Enable users to download and upload child-table data for Design Contract and Design Invoice using Excel templates, while preserving correct row identity, respecting business rules, and keeping the form state stable until save.

### Scope

In scope:
- Separate download and upload controls for each child table on both parent DocTypes
- Template-based export/import for:
  - Design Contract: Items, Purchase Taxes and Charges, Payment Terms
  - Design Invoice: Items, Advances, Purchase Taxes and Charges
- Row matching by stable document identity, not row number or display text
- Validation of:
  - template structure
  - duplicate/foreign identifiers
  - prohibited changes
  - field-level value constraints
  - permissions and protected-field rules
- Deferred application until save, with no mutation on failed upload

Out of scope:
- Rewriting the broader document calculation model
- Changing the business meaning of parent document rules
- Any non-template spreadsheet workflow

---

## Replan with performance and code-quality emphasis

### 1) Product intent

This feature is not really “Excel import/export”; it is a controlled, row-aware synchronization layer between a document and a spreadsheet. The core principle is:

- parse once
- validate once
- match by stable row identity
- apply in one atomic logical update
- recalculate once

This keeps behavior predictable and limits DB churn.

### 2) Architecture

Use one shared spreadsheet sync engine for all child tables, with a table-specific metadata layer.

Core design:
- Shared parser/validator for xlsx files
- Shared row-identity resolver
- Shared permission and field-policy checks
- Parent-specific table metadata that defines:
  - child table name
  - allowed fields
  - identity columns
  - editable columns
  - create/update rules
  - recalculation triggers

This avoids duplicate logic across the two DocTypes and keeps branching contained to metadata rather than scattered conditionals.

### 3) Data and identity model

The upload logic must operate on stable keys, not spreadsheet position.

Required identity rules:
- Preserve unique row identifiers from the existing document rows
- Include matching identifiers automatically in exported templates
- On upload, match rows by:
  - current document
  - target child table
  - stable row identity
- Never match by:
  - row position
  - item description
  - order in the sheet
- Foreign or duplicate identifiers must be rejected clearly

For advances specifically:
- Keep source identity intact across recalculation
- Do not depend on display order or regenerated row order
- Treat advance rows as a special case where source linkage is part of the row identity, not just a value

### 4) Validation and safety model

Validation should be strict and fail-fast before any mutation.

Required behavior:
- Reject invalid template structure before touching document state
- Reject duplicate or foreign row ids early
- Reject forbidden edits and unsupported columns before row application
- Enforce existing permissions, document locking rules, protected fields, child-table creation constraints, and contract-link rules
- Keep form unchanged on rejected upload

This should be implemented as a staged validation pass:
1. parse workbook
2. normalize rows
3. validate table schema and identifiers
4. validate business rules
5. build an in-memory update set
6. apply only if fully valid

### 5) Performance plan

Performance concerns are important because this feature touches child tables and recalculation-heavy documents.

Minimum standards:
- Parse workbook once and avoid repeated row scans
- Build dictionary lookups by row identity rather than repeated nested loops
- Validate row sets in batches, not row-by-row against the DB
- Avoid per-row save or per-row recalculation
- Calculate dependent amounts once after all updates are assembled
- Reuse existing document-level recalculation routines instead of re-implementing them in the spreadsheet layer

Performance rule:
- Do not put row-level DB work inside the import loop.
- Resolve all matches first, then apply final updates in one coherent pass.

### 6) Code-quality requirements

The implementation should be deliberately boring and easy to reason about:

- One generic import engine
- One metadata contract per child table
- One row-identity resolver
- One validation pipeline
- One final apply phase

Avoid:
- ad hoc conditionals spread across document handlers
- duplicate import logic per DocType
- special-case branching hidden in unrelated form code
- "smart" generic code that hides a simple data contract

The clean structure is:
- spreadsheet layer
- validation layer
- business rules layer
- apply/recalculate layer

This is much easier to test and maintain than a custom import flow embedded into each JS form file.

### 7) Acceptance criteria

- Users can download a table-specific Excel file for each supported child table
- Export includes the identifiers required to match existing rows
- Blank template export works
- Upload updates existing rows without recreating them
- New rows are added only when creation is allowed by table rules
- Omitted rows remain unchanged
- Matching is done by current document + child table + stable identity, not by spreadsheet order
- Failed uploads leave the form unchanged
- Recalculation happens through existing document logic and not duplicate business rules
- Permissions and protected-field rules are enforced
- Invalid templates and invalid row payloads are rejected with actionable guidance

---

## Recommended implementation posture

This should be treated as a controlled sync feature, not a broad spreadsheet rewrite.

Priority order:
1. Shared table metadata and row-matching contract
2. Validation pipeline and rejected-upload safety
3. Apply/recalculate flow
4. Template export UX
5. Specific DocType wiring

This keeps the architecture simple and minimizes performance risk.

Skipped: deep review of the existing JS/Python implementation files and their current structure; this is intentionally a product-level replan, not a code-preservation exercise.
Risk: if the actual row identity model in the production DocTypes differs from the assumed stable identifiers, the matcher must be validated against real data before release.