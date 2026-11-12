# US-2026-11-0327 Technical Plan

## Status and scope

The user approved the decisions in this plan after the grilling rounds.

Phases 1–5 are implemented and reviewed locally. Static syntax, JSON, and whitespace checks passed, and independent reviews are complete.

Atomic consultation uploads are enabled for editable drafts. The [acceptance review](US-2026-11-0327-acceptance-review.md) records simulated outcomes for every planned scenario.

Runtime tests, asset builds, migrations, and staging checks were not executed.

## Approved quantity acceptance revision

Invoice Number means `consultants_qty`. Allow positive actual quantities equal to or greater than contracted Number.

Do not apply a separate percentage quantity cap or `check_overbilling_allowance_on_every_item`.
Calculate the regular amount from headcount, rate, and billable days. Consume the item’s remaining balance first, then the shared monetary allowance.
Reject the invoice if its additional monetary draw exceeds the remaining allowance. Submitted invoices consume monetary allowance across billing periods.

## Approved monetary-allowance revision

Add three fields to Consultation Contract: `over_billing_allowance_`, `used_over_billing_allowance_amount`, and `remaining_over_billing_allowance_amount`.

Default the percentage from Construction Settings for a new contract. Preserve draft edits and an explicit zero. Calculate the two read-only Currency fields from submitted regular invoices.

```text
Total monetary allowance = sum(items.total_amount) × percentage / 100
Used = sum(max(submitted amount by item − item.total_amount, 0))
Remaining = max(total monetary allowance − used, 0)
```

Each row consumes its own remaining base first. Additional excess must fit the remaining shared allowance. Other items' unused base cannot offset excess.

Keep depleted rows available for creation, mapping, and reload. Apply allowance validation during calculation, Excel preview, save, and submission. Exclude the current invoice from submitted totals before validating its candidate amount.

Lock the contract and read current submitted totals again before submission persists. Submission and cancellation update row balances and both contract amount fields in the same transaction.

Quantity limits reset each billing period. Monetary usage accumulates across submitted invoices. Overtime and taxes do not consume monetary allowance.

This approved revision replaces the earlier unrestricted-amount behavior. Historical excess remains visible, but cannot fund additional excess draws.

Source: [US-2026-11-0327.md](US-2026-11-0327.md).

All implementation belongs in `frappe-bench/apps/fabrica_construction`. Do not change Frappe core or other apps.

## Current behavior and diagnosis

Paths below are relative to `frappe-bench/apps/fabrica_construction/fabrica_construction/`. The DocType directory is `fabrica_construction/doctype/`.

| Area | Existing behavior | Required delta |
| --- | --- | --- |
| Contract Number | `consultation_contract/rate_schedule.py:get_source_state` already permits zero Number and requires positive Rate. | Preserve this behavior. |
| Invoice creation | Contract JS and `make_consultation_invoice` require positive remaining amounts. The mapper filters depleted rows. | Remove monetary eligibility checks. |
| Billing regeneration | `consultation_invoice/billing_period.py:rebuild_billing_rows` skips previously absent rows with no remaining amount. | Select rows by dates and rate periods, preserving explicit exclusions. |
| Actual headcount | `validate_invoice_contract_rows` caps invoice Number at contract Number. | Remove this comparison. |
| Contract balances | `calculate_invoiced_amounts` rejects negative remaining amounts during submission. | Allow negative balances and retain balance updates. |
| Overtime | Server and browser validation cap combined consultant counts by regular invoice headcount. | Remove aggregate caps and preserve separate rows. |
| Template configuration | Consultation parents and their tables are missing from template selection. | Register the four requested table pairs. |
| Excel infrastructure | `public/js/sheet_utils.js` already supports defaults, labeled headers, workbook parsing, and merge options. | Reuse these facilities and add consultation integration. |
| Form integration | Consultation forms do not use sheet utilities. Their target Table fields lack `allow_bulk_edit`. | Enable the existing table transfer controls and wire consultation policies. |
| Blank downloads | Empty tables export headers, but populated tables lack an explicit blank-download choice. | Add a consultation export choice for populated or blank sheets. |

Default uniqueness and default preselection already exist. Negative balance formulas also exist. These do not need replacement implementations.

## Approved import and export decisions

1. Validate the complete upload before changing the form. Any invalid row leaves the document unchanged.
2. Report the worksheet row number, field, and reason for each detected import error.
3. A blank cell in a supplied editable column clears its value. An omitted column preserves its value.
4. Use child-row `name` for updates. Reject unknown IDs and duplicate supplied IDs.
5. Blank IDs create rows only in Contract Details, Rate Increases, and Overtime Details.
6. Regular Invoice Details permits updates to existing rows only.
7. Always export identity and required relationship columns, alongside selected template columns.
8. Export editable contract source rows only. Maintain generated rate periods and exclusions through the existing form workflow.
9. Ignore uploaded calculated values and recalculate them. Reject changes to protected identity and reference fields.
10. Preserve omitted rows. Uploads do not delete rows or replace entire tables.

An editable overtime source-period selector remains a business input. Validate its membership instead of treating it as an immutable regular-invoice reference.

## Table policies

| Parent and table | Child DocType | Editable business inputs | Preserved relationships |
| --- | --- | --- | --- |
| Consultation Contract: `items` | Consultation Contract Detail | Source job title, title name, `qty`, Rate/Initial Rate, dates, and existing editable accounting fields | `name`, source keys, generated-period metadata, calculated amounts and balances |
| Consultation Contract: Rate Increases | Consultation Contract Rate Increase | `month_start`, `month_end`, `rate_increase`, `increasing_method` | `name`, `schedule_key`, exclusions and generated relationships |
| Consultation Invoice: `invoice_details` | Consultation Invoice Detail | `consultants_qty` | `name`, `reference`, job title, billing source, period dates, rates and calculated values |
| Consultation Invoice: `overtime_details` | Overtime Details | `job_title`, `consultation_contract_detail`, `consultants_qty`, `number_of_overtime_hours`, `contracts`, `allocated_to_developer_company` | Row identity and calculated rates, amounts and accounting values |

Use explicit field allowlists based on existing form behavior. Do not expose hidden implementation fields as editable spreadsheet inputs.

For Rate and Initial Rate, reuse `get_source_state` precedence and recalculation. Do not introduce a second rate-schedule interpretation.

Required reference columns must contain values that match the identified existing row. An update cannot clear these protected values.

## Excel implementation design

### Template and form integration

- Extend Construction Export Template JSON parent options and its JS table-selection logic.
- Retain existing column selection, default uniqueness validation, and default preselection.
- Enable bulk editing on the four parent Table fields.
- Wire both consultation forms to the shared download and upload controls.
- Export `.xlsx` with `Label(fieldname)` headers. Include mandatory identity and relationship columns once.
- Offer populated and blank exports from populated tables. Blank exports contain headers without data rows.
- Accept `.xlsx`, `.xlsm`, and `.xlsb`. Read the first worksheet only.

### Shared utilities and focused modules

Reuse `sheet_utils.js` merge handling with `clear_table=false`, row identity, editable fields, and table-specific addition rules.

Avoid its `option_wrapper` upload branch because that branch appends rows without applying merge parameters.

Add consultation-specific policy and form coordination in a focused client module. Keep server import validation in a focused consultation module.

Limit shared utility changes to required export options, header identification, and physical worksheet row tracking. Preserve existing callers' behavior.

Parse field identifiers from the terminal header suffix. Labels containing parentheses must still resolve to the correct field identifier.

### Import sequence

1. Read headers and cells while retaining physical Excel row numbers, including gaps from blank rows.
2. Check supported fields, required identity columns, duplicate IDs, and row membership before merging.
3. Build a candidate from the current form document, including unsaved changes.
4. Merge editable values by row ID. Append permitted new rows without replacing existing rows.
5. Preserve protected values, generated contract rows, schedule keys, and exclusion state.
6. Validate the candidate server-side with existing contract or invoice calculation logic.
7. Return errors with spreadsheet row and field context before applying any changes.
8. Apply the calculated candidate only when all validation succeeds. Mark the form dirty without saving or submitting it.

Validate permissions and document editability through existing Frappe conventions. Do not write documents during import preview or call submission/cancellation handlers.

Reject arbitrary regular invoice rows, mismatched contract references, unrelated job titles, invalid periods, and invalid allocation destinations.

Use the existing invoice row synchronization behavior when applying calculated results. Import must not invoke Reload Contract Rows or reset exclusions.

## Billing changes

### Creation, mapping, and regeneration

- Remove the remaining-amount gate in `consultation_contract.js:add_create_buttons`.
- Remove the server creation gate and mapper `has_remaining_amount` condition in `consultation_contract.py:make_consultation_invoice`.
- Remove local helpers or queries made unused by those removals.
- Remove only the monetary exclusion in `billing_period.py:rebuild_billing_rows`.
- Keep source membership, unique references, applicable rate periods, contract boundaries, and explicit billing exclusions.

The shared regeneration path must cover creation, Reload Contract Rows, recalculation, save, and submission.

Zero-headcount contract rows initially inherit zero invoice Number. Users must enter positive actual Number before those rows become valid billable rows.

### Headcount and balances

- Remove the fixed contract-quantity ceiling. Validate the calculated amount against available monetary balances.
- Replace the absolute negative-remaining rejection with shared monetary allowance validation before submission.
- Retain finite positive billable inputs, positive rates, transaction locking, and submitted-invoice balance calculations.
- Retain the existing formula: remaining amount equals contract total minus submitted regular invoice amounts.
- Keep overtime and taxes outside the existing regular contract-row balance calculation.

The monetary revision adds the three contract fields described above. Cancellation must reverse the canceled invoice's contribution through the existing flow.

### Overtime allocations

- Remove aggregate consultant validation from server `calculate_line_amounts`.
- Remove client `validate_consultants_qty_in_overtime` and its calls. Keep recalculation handlers.
- Keep each allocation as a separate child row, even when job title and consultants repeat.
- Preserve row-specific hours, rates, amounts, construction contracts, and developer-company allocation.
- Retain positive inputs, exact source rate-period resolution, and construction-contract eligibility checks.
- Preserve allocation-log creation and cancellation. Developer-company allocations retain their existing handling.

## Planned file changes

All DocType paths below start at `fabrica_construction/doctype/`.

| File or module | Responsibility |
| --- | --- |
| `construction_export_template/construction_export_template.json` and `.js` | Register consultation parents and target tables. |
| `consultation_contract/consultation_contract.json` | Enable transfer controls on Details and Rate Increases. |
| `consultation_invoice/consultation_invoice.json` | Enable transfer controls on regular and overtime tables. |
| `consultation_contract/consultation_contract.js` | Wire Excel controls and remove monetary creation eligibility. |
| `consultation_contract/consultation_contract.py` | Remove creation and mapping monetary filters. |
| `consultation_invoice/consultation_invoice.js` | Wire Excel controls and remove aggregate overtime validation. |
| `consultation_invoice/consultation_invoice.py` | Remove headcount and amount ceilings while retaining calculations and lifecycle effects. |
| `consultation_invoice/billing_period.py` | Remove amount-based billing-row exclusion. |
| `services/consultation_amount_allowance.py` | Calculate used/remaining monetary allowance and validate excess regular invoice draws. |
| `public/js/sheet_utils.js` | Add the narrow shared transfer capabilities described above. |
| New focused consultation client/server modules | Own table policies, atomic candidate validation, and error mapping. |
| Existing consultation tests and focused Excel tests | Replace obsolete rejection expectations and cover approved behavior. |

Reuse existing template controller validation. Modify it only if implementation reveals a gap required by this story.

New or updated implementation modules need purpose docstrings. New whitelisted methods belong at the bottom of their file or class.

## Implementation phases

Execute the phases in order. The design sections above define the detailed behavior for each phase.

Before application edits, load applicable local Frappe skills and code-style guidance. Keep every phase within the custom app.

### Phase 1: Actual headcount and unrestricted contract billing

Scope:

- Remove remaining-amount gates from invoice creation, mapping, and billing-row regeneration.
- Remove the fixed invoice headcount ceiling and validate calculated monetary draws. Remove the negative-remaining submission rejection.
- Preserve dates, source membership, exclusions, positive billable inputs, and existing balance calculations.
- Update existing creation, billing-period, invoice restriction, and balance test expectations.

Files: contract JS/Python, invoice Python, `billing_period.py`, and their relevant tests.

Completion criteria: A and B bill actual headcount through creation, reload, recalculation, save, and submission. Negative balances remain accurate after submission and cancellation.

### Phase 2: Independent overtime allocations

Scope:

- Remove aggregate consultant caps from invoice Python and JS.
- Remove the obsolete client validation method and its calls. Retain recalculation handlers.
- Preserve separate allocation rows, destination eligibility, row calculations, and allocation-log lifecycle effects.
- Update invoice and overtime allocation-log test expectations.

Files: invoice JS/Python and their relevant tests.

Completion criteria: repeated consultants can appear against different destinations. Each row retains its own amount and allocation effects without a combined headcount ceiling.

### Phase 3: Excel templates and downloads

Scope:

- Register both consultation parents and all four tables in Construction Export Template.
- Enable table transfer controls and wire consultation downloads.
- Reuse default uniqueness and preselection behavior.
- Add populated and blank `.xlsx` downloads with selected columns and mandatory identity/reference columns.
- Export editable contract source rows only. Preserve generated rows in the document.
- Add the focused client policy module and required shared export/header changes.

Files: template JSON/JS, parent DocType JSON, consultation form JS, the new client module, `sheet_utils.js`, and focused tests.

Completion criteria: all four tables support configured defaults and both download modes. Headers preserve field identifiers, including labels containing parentheses.

Phase 4 enables consultation upload controls after adding their validation path.

### Phase 4: Atomic Excel imports

Scope:

- Add the focused server validation module and connect consultation upload controls.
- Accept the three approved workbook formats and read the first worksheet.
- Preserve physical worksheet row numbers for error reporting.
- Implement the approved table allowlists, row-ID merge rules, blank-cell behavior, and new-row restrictions.
- Validate a candidate containing current unsaved form changes before applying any upload values.
- Recalculate through existing contract and invoice logic. Preserve generated relationships and exclusions.
- Add focused tests for atomicity, identity, relationships, error mapping, and unsaved document behavior.

Files: new consultation client/server modules, consultation form JS, `sheet_utils.js`, and focused tests.

Completion criteria: valid uploads update only intended inputs. Invalid uploads report row/field errors without partial changes, document saves, or lifecycle side effects.

### Phase 5: Integrated acceptance and regression review

Scope:

- Review every scenario in the simulated acceptance matrix below.
- Trace Excel changes through recalculation, save, submission, cancellation, and Reload Contract Rows.
- Check scheduled increases, explicit exclusions, taxes, balances, and overtime allocation logs.
- Check existing non-consultation Excel callers for shared-utility regressions.

Completion criteria: record the expected outcome for each scenario and identify any unresolved gaps. Clearly label simulated results.

Real local or staging execution requires an explicit request. Apply DocType metadata through the normal staging migration process when implementation is deployed.

## Simulated acceptance matrix

These are expected outcomes from code analysis. They are not executed test results.

Use fresh illustrative staging contracts for independent scenarios. Follow the source story's company, project, currency, dates, and construction-contract setup.

The A/B numeric checks use 400% monetary allowance. Combined Number 5 is accepted when its calculated amount fits available monetary capacity.

The same contract percentage creates monetary allowance 19200. The first invoice uses 7200 and leaves 12000. A second identical invoice exhausts the pool.

| Scenario | Expected outcome |
| --- | --- |
| Save A with Number 1 and B with Number 0, both at Rate 2400 for two months | Contract totals are A 4800 and B 0. |
| First full-month invoice with A Number 3 and B Number 2 | Regular amounts are A 7200 and B 4800. Total is 12000 without taxes or overtime. |
| Submit that invoice | Remaining balances are A −2400 and B −4800. |
| Reuse that contract for the second valid billing month | Both rows remain eligible despite negative remaining balances. |
| Recalculate, save, submit, and reload depleted rows | Monetary ceilings do not return through another lifecycle path. Explicit exclusions retain their existing reload behavior. |
| Two overtime allocations, each Number 3 and Hours 2 at monthly Rate 2400 | Hourly rate is 10. Each row totals 60 despite combined Number 6. |
| Split overtime across two construction contracts and a developer allocation | Rows retain destinations and amounts. Existing allocation-log behavior remains correct. |
| Cancel an overbilled invoice | Contract balances and allocation logs follow the existing cancellation flow. |
| Invalid dates, unrelated source rows, nonpositive billable inputs, or ineligible destinations | Existing validation still rejects the document. |
| Set a default for each of the four parent/child pairs | The correct default preselects. A second default for the same pair is rejected. |
| Export populated and blank sheets for all four tables | Headers contain labels and identifiers, including mandatory identity/reference columns. |
| Import each supported format with multiple worksheets | Only the first worksheet supplies data. |
| Import known IDs and omit unrelated rows | Identified rows update once. Omitted rows remain unchanged. |
| Add blank-ID rows in the three editable tables | New rows append without merging separate overtime allocations. |
| Import unknown or duplicate IDs, or a new regular invoice row | Upload fails without changing the form. |
| Clear an editable cell and omit another column | The blank clears its field. The omitted column preserves its field. Required-field errors reject the upload. |
| Change calculated values and protected references | Calculated values are ignored. Protected reference changes reject the upload. |
| Import source edits with scheduled increases and exclusions | Existing schedule logic rebuilds generated periods and preserves exclusions. |
| Invalid spreadsheet row after blank worksheet rows | Error reports the physical worksheet row, field, and reason. No partial changes occur. |
| Import a workbook into a form with unsaved edits | Candidate validation preserves unrelated unsaved edits and does not save the document. |
| Use existing non-consultation Excel workflows | Existing template, export, and upload behavior remains unchanged. |
| Invoice Number exceeds contracted Number and the former percentage cap | Accept when the calculated amount fits the item balance plus remaining monetary allowance. |
| Toggle Check Overbilling Allowance on Every Item | Quantity acceptance remains based on monetary capacity. |
| Base total 1000, prior submitted 900, allowance 20% | A new amount of 300 is allowed. Amount 300.01 is rejected. |
| Cancel an invoice that consumed allowance | Used and remaining monetary allowance recalculate from submitted invoices. |
| Change a draft contract percentage or attempt read-only balance edits | Balances recalculate. Explicit zero is retained and derived balances are not trusted. |

Update existing contract creation, invoice restrictions, billing-period, balance, and overtime allocation-log tests during implementation. Add focused Excel tests for merge semantics and atomicity.

Real staging or local test execution requires an explicit request under the workspace instructions.
