# Fabrica Construction Refactoring Plan

## Purpose

Improve response time and maintainability in the `fabrica_construction` app without changing construction, accounting, or contract behavior. The app contains about 631 Python and JavaScript source files. Its largest controllers include Construction Invoice, Construction Contract, Variation Order, and BOQ. Their size signals maintenance risk, but it does not prove a performance problem.

This plan is read-only guidance based on source review. No production timings, query plans, or before-and-after measurements were available. Treat performance estimates in earlier audit notes as hypotheses until measurements confirm them.

## Goals

- Reduce repeated database queries and repeated recalculation work.
- Reduce repeated client-side table rendering.
- Keep Frappe validation, permissions, hooks, and transaction boundaries intact.
- Make changes in small, testable steps.
- Measure each change with the same representative workload before and after.

## Priority Candidates

### 1. Reuse BOQ allocation aggregates

`BOQChild.get_contracted_qty` in `frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/boq_child/boq_child.py` calls `get_boq_contracted_quantities` from `frappe-bench/apps/fabrica_construction/fabrica_construction/services/boq_allocation.py`. The helper groups allocations for a BOQ, so repeated calls for multiple children can repeat the same query.

**Approach:** Build the allocation map once for each BOQ operation and pass or reuse it during child calculations. Preserve the filters for submitted contracts, retroactivated rows, and blocked rows from canceled variation orders. Preserve the current behavior for new child rows.

**Measure:** Query count and BOQ save/submit time across small and large BOQs. Confirm contracted and remaining quantities match before and after.

### 2. Recalculate BOQ resources once per operation

`refresh_boq` in `frappe-bench/apps/fabrica_construction/fabrica_construction/services/provisional_sum.py` saves resources in a loop and then recalculates resource quantities. Resource changes also have an `on_change` hook in `frappe-bench/apps/fabrica_construction/fabrica_construction/hooks.py`.

**Approach:** Trace the full hook call path and count recalculations. For this controlled batch only, defer aggregate recalculation until all resource values are updated, then recalculate once. Keep normal resource validation and standalone resource-save behavior.

**Measure:** Recalculation count, child-row updates, database queries, and submit/cancel time. Compare resource allocations, BOQ rates, totals, and remaining quantities.

### 3. Refresh the Contract variance table once

`set_price_variance_required_fields` in `frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js` refreshes the entire table. The Contract refresh handler calls it for each row.

**Approach:** Set each row's requirement first, then refresh the table once after the loop. Keep row-specific formula logic and refreshes triggered by individual formula changes.

**Measure:** Browser render time and number of table refreshes for forms with different row counts. Confirm the required state remains correct for formulas with and without `net_item_amount`.

### 4. Review the global version hook

`hooks.py` registers `save_custom_version_for_doctype` for every document's `on_change` event. `utils/data.py` loads the Construction DocType list before it checks whether the document belongs to this app.

**Approach:** Measure the hook's query count and time on both Construction and unrelated DocTypes. If the lookup is material, use cached DocType metadata or another app-local check. Keep Version creation rules unchanged.

**Measure:** Hook calls, query count, and elapsed time across representative document updates. Confirm that Construction changes still create the same versions and unrelated changes remain unaffected.

### 5. Confirm Construction Invoice history call paths

`construction_invoice.py` contains historical-total properties that load full Construction Contract and Construction Invoice documents. It also contains newer properties that use field projections. Source review alone does not show which properties run in the current serialization and validation paths.

**Approach:** Find all consumers of the full-document properties and profile them. If a hot path uses them, batch the required fields and reuse the result within that operation. Preserve invoice ordering, date filters, reversed-invoice exclusions, and contract counting rules.

**Measure:** Query count, document hydration count, and submit/refresh time as invoice history grows. Compare balances and totals against existing behavior.

### 6. Review report and API aggregation paths

The existing optimization notes identify a checked all-project summary that may run full reports and CRM calls per project. They also identify reports that load detail rows only to aggregate them in Python.

**Approach:** Confirm the affected endpoints and reports are still active. Batch shared reads or move aggregation into the database only when the current filters, grouping, mapping rules, and rounding behavior can be preserved. Keep CRM calls out of repeated per-project loops where possible.

**Measure:** Query and remote-call counts, response time, result row count, and peak memory across increasing project and transaction counts. Compare complete report output, not only totals.

## Delivery Stages

### Stage 1: Establish a baseline

1. Select staging data that represents small, typical, and large documents.
2. Record query count, elapsed time, rows fetched, and remote-call time for BOQ save/submit, Contract submit, Variation Order submit/cancel, Construction Invoice refresh/submit, and the checked project summary.
3. Record document row counts and relevant settings with each measurement.
4. Store the baseline output with the test or work item. Do not compare results from different data volumes or environments.

### Stage 2: Add behavior tests

1. Add focused tests for BOQ allocation and resource calculations.
2. Cover Contract and Variation Order submit, cancel, and post-submit updates.
3. Cover Construction Invoice previous balances, ordering, and reversed invoices.
4. Add report cases for shared items, variation history, missing dimensions, and rounding where those reports are changed.

### Stage 3: Make contained changes

1. Refresh the Contract price-variance table once per form refresh.
2. Reuse BOQ allocation aggregates within one operation.
3. Recalculate BOQ resources once within the controlled batch.
4. Measure after each change and stop if behavior changes or the expected performance signal does not improve.

### Stage 4: Make broader changes

1. Optimize only confirmed Construction Invoice history call paths.
2. Batch report and API reads after preserving current report semantics in tests.
3. Change the global version hook only if profiling shows a meaningful cost.
4. Keep each change isolated so results and regressions are easy to attribute.

### Stage 5: Refactor large controllers

After performance hotspots have tests and measurements, extract pure calculations and state transformations from Construction Invoice, Construction Contract, Variation Order, and BOQ. Keep controller methods responsible for Frappe lifecycle orchestration. Do not move lifecycle methods or reorder writes as part of a mechanical file split.

## Separate Correctness Work

Some findings in `Constuction - Optimization Points.md` concern correctness or transaction safety, not performance. Review them as separate changes with explicit expected behavior:

- Background actions may report failure after writes without rolling back.
- A BOQ report may join resources through a shared master item instead of the exact child reference.
- Empty CRM responses may leave report mappings undefined.
- Invoice summary joins may multiply rows across variations.

Do not combine these fixes with performance refactors unless a single test covers both the behavior change and the performance goal.

## Validation and Release Gates

- Run focused Frappe tests for each changed module before broader app tests.
- Compare calculated values, selected rows, permissions, and document status with the baseline.
- Check submit, cancel, and rollback paths for related documents.
- Compare query counts and timing with the same dataset and environment.
- Inspect query plans before adding indexes. Source inspection alone does not prove that an index is missing.
- Deploy one measured change at a time and monitor the affected operation after release.

## Constraints and Risks

Construction Invoice, Construction Contract, Variation Order, and BOQ update related documents and enforce billing and allocation rules. Their hooks run inside transactions. Preserve hook order, permission checks, rollback behavior, child-row ordering, and validation. Avoid direct database writes unless the change explicitly preserves the lifecycle behavior that those writes would bypass.

This plan does not authorize implementation. Review and approve each change before editing the app.
