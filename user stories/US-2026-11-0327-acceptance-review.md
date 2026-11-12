# US-2026-11-0327 Acceptance Review

## Evidence boundary

This review covers phases 1–5 of the [technical plan](US-2026-11-0327-technical-plan.md).

All behavioral outcomes below are simulated from code inspection. Authored regression tests were inspected but not executed.

Static Python syntax, JavaScript syntax, JSON parsing, and diff whitespace checks passed. Independent server and client reviews are complete.

No browser flows, test suites, asset builds, migrations, or staging operations were executed. Runtime behavior remains unproven.

## Acceptance matrix

Paths below are relative to `frappe-bench/apps/fabrica_construction/fabrica_construction/`.

The A/B numeric scenarios use 400% monetary allowance. Regular headcount has no separate quantity cap.

The contract percentage also funds a shared monetary pool of 19200. The first A/B invoice uses 7200 and leaves 12000. The second exhausts the pool.

| Scenario | Simulated outcome | Code or authored regression evidence |
| --- | --- | --- |
| A Number 1 and B Number 0, Rate 2400, two months | Estimated totals are A 4800 and B 0. | `rate_schedule.get_source_state`; existing zero-Number contract coverage. |
| First full-month invoice: A Number 3, B Number 2 | Combined Number 5 meets the configured allowance. Regular amounts are 7200 and 4800. Total is 12000 without taxes or overtime. | `ConsultationInvoice.calculate_line_amounts`; quantity-allowance validation. |
| Submit the first invoice | Remaining balances become A −2400 and B −4800. | `calculate_invoiced_amounts`; negative-balance regression cases. |
| Bill the second valid month on the same contract | Both source rows remain eligible despite negative balances. | Creation and mapper monetary gates removed; `rebuild_billing_rows` retains depleted rows. |
| Recalculate, save, submit, and reload depleted rows | Rows remain available. Recalculation, save, and submit enforce the monetary pool. Explicit exclusions retain existing reload behavior. | Shared calculation paths and `Reload Contract Rows` source-key reset inspected. |
| Two overtime rows: Number 3, Hours 2, monthly Rate 2400 | Each row uses hourly Rate 10 and Amount 60. Combined Number 6 is permitted. | Server/client aggregate caps removed; independent-allocation tests. |
| Split overtime across two construction contracts and a developer allocation | Rows retain separate destinations and amounts. Developer allocation follows its existing log handling. | `validate_overtime_contracts`, allocation-log creation, and separate-destination tests. |
| Cancel an overbilled invoice | Submitted regular balances recalculate and allocation logs cancel. | Existing `on_cancel`; cancellation balance and allocation-log tests. |
| Invalid dates, source membership, positive inputs, or destinations | Validation still rejects invalid documents. | Existing invoice validation and rate-period logic remain active. |
| Configure one default per parent/child pair | The matching default preselects. Duplicate defaults remain invalid. | Existing template controller validation and `get_default_template_name`; four-pair client tests. |
| Export populated and blank sheets for all four tables | Selected columns and mandatory identity/reference columns export with label/identifier headers. | `consultation_sheets.setup`, optional export options, and four-table export tests. |
| Import `.xlsx`, `.xlsm`, and `.xlsb` workbooks | The reader uses only the first worksheet. | Existing FileUploader format restrictions; first-sheet processor and three-format tests. |
| Update known IDs and omit unrelated rows | Known rows update once. Omitted rows and columns remain unchanged. | Private candidate merge; successful invoice merge regression. |
| Add blank-ID rows in the three editable tables | Source details, rate increases, and overtime rows append. Regular invoice rows cannot append. | Table policies, `merge_rows`, source creation and overtime append tests. |
| Upload unknown or duplicate IDs, or a new regular row | The upload reports errors and returns no candidate document. | Header/identity checks and row-diagnostic tests. |
| Supply blank editable cells and omit other columns | Blanks clear supplied fields. Omitted fields retain their values. Required or positive-value errors reject the upload. | Header-aware reader, `cell_value`, and candidate merge logic. |
| Change calculated values or protected references | Calculated values are ignored and recomputed. Protected changes reject the upload. | Metadata read-only handling, explicit protected fields, and reference regression tests. |
| Edit sources with scheduled increases and exclusions | Canonical schedule logic rebuilds periods and preserves source keys, schedule keys, and exclusions. | `validate_contract_periods`, existing contract validation, and source/exclusion regression. |
| Invalid data follows blank worksheet rows | Diagnostics report the physical worksheet row, field, and reason. The form remains unchanged. | `read_upload_sheet`, row-location mapping, and invalid-late-row tests. |
| Import into a form with unsaved changes | The preview includes those changes. Application preserves the parent and marks it dirty without saving. | Snapshot request, private deepcopy, controller `apply_import`, and parent-identity tests. |
| Use existing non-consultation Excel workflows | Existing parsing and mutation paths remain active unless callers opt into the new processor. | Optional `upload_options`; existing export compatibility test and unchanged legacy uploader paths. |

## Additional import boundaries

| Case | Simulated outcome | Evidence |
| --- | --- | --- |
| Template labels contain parentheses | The reader uses the terminal identifier suffix. | Header parser and parentheses regression. |
| A supplied column has no header, or headers repeat | Server validation rejects the workbook before merging. | Column union in the reader and duplicate/unsupported-header checks. |
| Excel contains a date cell | The reader sends its calendar date for server date validation. | Opt-in `cellDates`, Date normalization, and `cell_value`. |
| The form changes during preview | The response cannot replace newer form edits. | Snapshot comparison and stale-preview regression. |
| Two previews overlap | Only the latest request can apply. | Per-form import request generation. |
| An invalid upload arrives while a calculation is pending | The existing calculation remains scheduled or in flight. | Cancellation deferred until successful application; invalid-preview regression. |
| A new source supplies positive Rate and blank Initial Rate | Canonical source-state logic accepts the Rate. | Rate-precedence regression. |
| Both Rate and Initial Rate change | Existing source-state precedence decides the effective rate. | Simultaneous-rate-edit regression. |
| A document is submitted, canceled, or not writable | Upload controls are hidden and the server checks draft status and permissions. | Grid editability, persisted draft check, and create/write permission checks. |
| Import succeeds or fails | Preview does not save, submit, cancel, or create allocation logs. | Private candidate validation only; lifecycle methods are not invoked. |
| Headcount exceeds contracted Number or the former percentage cap | Accept if the calculated amount fits available base and monetary allowance. | Monetary import boundary cases, simulated only. |
| Toggle the per-item overbilling setting | Quantity acceptance is unchanged. | Monetary import cases for both settings, simulated only. |
| Allowance validation regenerates reordered invoice rows | Errors still identify the imported row's physical Excel location by child-row identity. | Reordered billing-row import regression. |
| New contract percentage is missing, zero, or explicitly entered | Missing values copy Settings. Explicit zero and entered percentages remain unchanged. | Contract-default integration cases. |
| Base total 1000, prior regular billing 900, contract percentage 20% | A new amount of 300 is allowed. Amount 300.01 is rejected. | Shared monetary service boundary cases. |
| Another item still has unused base balance | Its unused base does not hide excess on the billed item. | Positive-excess-by-source pool tests. |
| Submitted or canceled regular invoice changes the totals | Used and remaining contract amounts update from submitted regular rows only. | Contract balance lifecycle cases. |
| Another submission consumed the last allowance after preview | The fresh locked pre-submission check rejects an additional draw. | Before-submit fresh-balance regression, statically inspected only. |
| Quantity import produces an amount above available allowance | The preview rejects it at the physical row and amount field without modifying the form. | Atomic monetary import regression. |

Document-level problems use a document or table context when no uploaded cell owns the error. Cell diagnostics retain physical worksheet rows.

## Review resolutions

- Removed independent positivity checks on Rate and Initial Rate. Canonical source-state logic now validates the effective rate.
- Deferred calculation cancellation until a valid preview applies. Failed uploads preserve pending calculations.
- Independent re-reviews found no remaining confirmed defects.
- Monetary allowance checks use the shared calculation path. Reordered invoice-row errors retain their spreadsheet location.

Real execution and deployment validation remain outside this simulated review.
