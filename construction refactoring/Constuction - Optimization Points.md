## Optimization Points

- database optimization
    - resolve N+1 Problem
    - indexing if necessary
    - caching if necessary
    - Replace frappe.get_doc() with frappe.get_all() or frappe.db.get_value() when only specific attributes are needed.

- ui optimization
    - simulate real pagination not fake pagination
    - Debounce Client Scripts: On complex transactional forms (like Sales Orders or Invoices), avoid triggering network fetches or recalculations on every keystroke or table row change. Aggregate totals only on save or via a dedicated calculation button.
    - lazy loading
    - virtual scrolling

- code optimization
    - use data structures for enhance time complexity
    - limit many loops with light as possible as


---

## Performance Issues - Codex


### 1. Performance Issues - by optimizer skills

Found **8 issues** in the Fabrica Construction checkout. These are source-verified findings; production timings and query plans remain unmeasured. No files changed.

1. **High — Invoice forms repeatedly load historical invoices.**  
   Six virtual-total evaluations reload earlier invoices and all their child tables during serialization. With one contract and 100 earlier invoices, the source implies approximately **6,600 historical-document SELECTs**, before payment and contract queries.  
   **Fix option:** Fetch only required historical fields and reuse totals during serialization. Preserve existing date filters and per-contract counting.  
   Location: [construction_invoice.py:678](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/construction_invoice/construction_invoice.py).

2. **High — BOQ saves repeat the entire allocation query twice per existing row.**  
   Remaining-quantity and total-quantity calculations each call a helper that aggregates allocations for the whole BOQ. **500 existing rows produce 1,000 repeated grouped queries.**  
   **Fix option:** Calculate the allocation map once per validation and reuse it. Preserve new-row behavior and canceled-variation filters.  
   Location: [boq_child.py:125](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/boq_child/boq_child.py).

3. **High — The checked all-project summary rebuilds complete reports per project.**  
   Each project triggers full report execution, a synchronous CRM request with a 15-second timeout, and repeated database reads. The endpoint keeps only the closing-balance total.  
   **Fix option:** Add a summary calculation that batches shared reads while preserving checked-category and mapping semantics. Existing optimized endpoints calculate different results and cannot directly replace it.  
   Location: [api.py:305](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/api.py).

4. **Confirmed reliability defect — Empty CRM results break the checked report.**  
   `mappings` is assigned only when CRM returns nonempty successful data, then used unconditionally. Empty responses and handled CRM timeouts therefore cause `UnboundLocalError`.  
   **Fix options:** Explicitly stop with a clear CRM error, or calculate available accounting results without CRM budgets. The intended behavior needs your decision.  
   Location: [report_actual_project_cost_vs_budget_v2_checked.py:976](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/report/report_actual_project_cost_vs_budget_v2_checked/report_actual_project_cost_vs_budget_v2_checked.py).

5. **Medium — A global hook adds a query to unrelated document changes.**  
   Every `on_change` fetches the Construction DocType list before checking membership. This includes unrelated ERPNext documents and Version inserts.  
   **Fix option:** Check the document’s existing cached `meta.module` value instead.  
   Location: [data.py:163](frappe-bench/apps/fabrica_construction/fabrica_construction/utils/data.py).

6. **Medium — BOQ rate calculation repeatedly scans all resources.**  
   Each BOQ item filters the entire resource list: **O(items × resources)**.  
   **Fix option:** Group resource amounts once by child reference, reducing lookup work to **O(items + resources)**.  
   Location: [boq.py:317](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/boq/boq.py).

7. **Medium — Price-variance setup redraws the grid for every row.**  
   Invoice and Contract refresh handlers update each variance row through a helper that refreshes the entire table. With 100 rows, this causes 100 refresh passes.  
   **Fix option:** Apply row metadata first, then refresh once. Preserve individual formula-change refreshes.  
   Locations: [construction_invoice.js:172](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/construction_invoice/construction_invoice.js), [construction_contract.js:453](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js).

8. **Medium — Contract spreadsheet updates perform quadratic searches.**  
   Every uploaded row searches both existing item arrays using `.find`: **O(uploaded rows × existing rows)**.  
   **Fix option:** Build name lookup maps once and maintain them when rows move between tables.  
   Location: [construction_contract.js:1454](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js).

I recommend fixing **invoice serialization and BOQ allocation queries first**. All proposed changes can remain inside Fabrica Construction. Implementation requires your approval under AGENTS.md.


---

### 2. Performance Issues - by frappe_code_database_performance_auditor skill


Using **v2.1.0**, I found **6 additional issues** beyond the previous findings. These are verified from source and call paths. No files changed, site tests ran, or production measurements were taken.

**1. High — Failed background actions can commit partial changes**

- **Location:** [background_utils.py:45](frappe-bench/apps/fabrica_construction/fabrica_construction/utils/background_utils.py), also the workflow handler at line 108.
- **Category / context:** Transaction Hazard / Background Job.
- **Problem:** Both wrappers catch action exceptions without rolling back. Frappe’s worker commits when the wrapper returns normally.
- **Concrete trigger:** Background cancellation writes a BOQ’s canceled status, then encounters a submitted-contract backlink and raises an error. The wrapper reports failure, but the canceled status can persist.
- **Proposed correction:** Roll back before creating failure diagnostics in both handlers:

```python
except Exception as _e:
    frappe.db.rollback()
    is_failed = True
    _log_failure_and_add_comment(doc, __action)
```

- **Impact:** Restores transaction integrity; no performance improvement claimed.
- **Verification plan — not executed:** Simulate cancellation blocked by a submitted contract. Confirm parent and child statuses remain submitted while failure diagnostics persist.

**2. High — Each resource save recalculates the entire BOQ**

- **Location:** [provisional_sum.py:200](frappe-bench/apps/fabrica_construction/fabrica_construction/services/provisional_sum.py).
- **Category / context:** N+1 Query / Controller Hook.
- **Problem:** Contract submission reaches `refresh_boq`, which saves resources individually. Each resource’s `on_change` scans resources and updates every BOQ child. An explicit recalculation follows the loop.
- **Complexity:** This recalculation component grows approximately as **O(R × (R + N))**, where R is resources and N is BOQ children.
- **Proposed correction:** Defer this specific aggregate hook during the controlled batch, preserve resource validation, then recalculate once.
- **Estimated impact:** 500 resources and 100 children cause **50,000 intermediate child updates** through the per-resource hooks alone.
- **Verification plan — not executed:** Count recalculation calls and child updates. Compare final allocations, rates, and totals; confirm standalone resource saves still recalculate.

**3. High — Allocation logs repeatedly rewrite their source document**

- **Location:** [purchase_receipt_allocation_logs.py:64](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/purchase_receipt_allocation_logs/purchase_receipt_allocation_logs.py).
- **Category / context:** Child Table Hydration / Controller Hook.
- **Problem:** Every inserted allocation log loads and saves its complete Purchase Order or Receipt solely to increment `custom_allocated_qty`. Source child rows are rewritten on every save.
- **Complexity:** **O(M × N)** source-row processing for M logs and N source children.
- **Proposed correction:** Retain individual log lifecycle calls, accumulate the quantity change, then save the source once per batch. Preserve standalone insertion behavior.
- **Estimated impact:** 100 logs against a 100-item source cause at least **10,000 source-item updates**, excluding other child tables.
- **Verification plan — not executed:** Compare allocated quantities, source validation, and source-save counts for synchronous and queued batches. Include failure rollback.

**4. High — BOQ Report joins resources across unrelated BOQs**

- **Location:** [boq_report.py:89](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/report/boq_report/boq_report.py).
- **Category / context:** Overfetching / Script Report API.
- **Problem:** The join uses the shared master item:

```sql
ON r.master_item = c.item_code
```

Resources therefore match every child using that item, including children in other BOQs. Selecting a BOQ does not constrain resource ownership.

- **Proposed correction:** Use the recorded child relationship:

```sql
ON c.name = r.boq_child_ref
AND c.parent = r.parent
```

- **Impact:** Removes incorrect cross-BOQ rows and many-to-many result growth.
- **Verification plan — not executed:** Two BOQs sharing one master item and holding one resource each should return two rows overall and one when either BOQ is selected. Current logic produces four and two respectively.

**5. Medium — Invoice summary joins every variation before grouping**

- **Location:** [construction_contract___invoiced_items_summary.py:235](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/report/construction_contract___invoiced_items_summary/construction_contract___invoiced_items_summary.py).
- **Category / context:** Overfetching / Script Report API.
- **Problem:** Each invoice item joins every variation on its contract. `GROUP BY ci_item.name` hides the multiplied rows, while nonaggregated variation fields can come from an unrelated variation.
- **Complexity:** Up to **O(I × V)** intermediate rows for I invoice items and V contract variations.
- **Proposed options:** Join the item’s exact variation references if the report represents its currently linked variation. If historical values are required, select the intended historical variation explicitly.
- **Verification plan — not executed:** Use several variation types and repeated changes to one item. Check row cardinality and the displayed variation rate/type.

**6. Medium — Division Summary loads details only to aggregate them**

- **Location:** [division_summary_report.py:97](frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/report/division_summary_report/division_summary_report.py).
- **Category / context:** Overfetching / Script Report API.
- **Problem:** Three queries materialize individual contract, variation, and invoice rows. Python immediately sums them into dimension groups.
- **Proposed correction:** Apply SQL `SUM(amount)` grouped by the existing raw dimensions, then retain Python’s normalization and allocation fallback rules.
- **Impact:** Worker processing and returned data can decrease from **O(N)** detail rows to **O(G)** groups. The database still processes matching transactions.
- **Verification plan — not executed:** Compare report output across filters, missing dimensions, whitespace labels, and currency rounding. Measure fetched rows and peak memory.

The index review checked source definitions only. **No deployed missing index or actual full-table scan is confirmed without database inspection and `EXPLAIN`.**