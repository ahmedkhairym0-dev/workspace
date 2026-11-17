# Summary of Zero-Quantity Items Architecture Refactor

**Branch:** `refactor/rehandling-zero-qty-items-construction--NO-ACC`  
**Base Branch:** `develop-no-acc`  
**User Story Reference:** `US-2026-11-0406` (`Rehandling Zero-Quantity Items in Construction Architecture`)  
**Date:** 2026-11-16  

---

## 1. Executive Summary

This refactor ports the zero-quantity item redesign from user story **US-2026-11-0406** to the `develop-no-acc` branch lineage. 

Under the legacy architecture, zero-quantity items were segregated into isolated child tables (`items_with_zero_qty`) across BOQ and Construction Contract, requiring complex Variation Order workflows ("Update Zero Qty Items") to transition items between tables. In the redesigned single-table architecture:
- All items (positive and zero quantity) reside together within standard active child tables:
  $$\text{bill\_of\_quantity (BOQ)} \longrightarrow \text{items (Construction Contract)} \longrightarrow \text{items (Construction Invoice)}$$
- Rows with quantity zero carry `amount = 0` and do not alter document totals, tax bases, or general ledger postings until quantity is explicitly billed.
- Physical legacy tables and DocTypes (`BOQ Zero Qty Item`, `Construction Contract Zero Qty Item`) have been dropped via post-model-sync patch, and dead multi-table movement code has been decommissioned.

---

## 2. Codebase Differences & Adaptation

Unlike `develop` (which relocated BOQ logic into modular sub-services under `services/boq/`), `develop-no-acc` maintains a monolithic BOQ controller in `doctype/boq/boq.py`. 

The business logic was ported directly into the monolithic structures of `develop-no-acc`:
1. **BOQ Controller (`boq.py`)**: Directly handles zero-quantity retention in `bill_of_quantity` when `Accept zero QTY` (`move_zero_quantity_items_on_submit`) is enabled, prevents negative quantities (`qty < 0`), and excludes zero rows from budget/cost rollups.
2. **Construction Contract (`construction_contract.py`)**: Maps zero-qty items directly from `BOQ Child` to `Construction Contract Items` with `qty = 0`, `rate = boq_rate`, `amount = 0`.
3. **Construction Invoice (`construction_invoice.py`)**: Maps zero-contract items into invoice items with `is_zero_qty_item = 1`, validates `qty > 0` upon invoice submit, draws billed amounts against shared overbilling allowance, and posts back-updates directly to `tabConstruction Contract Items` and `tabBOQ Child`.

---

## 3. Key Issues Diagnosed & Resolved

### A. Invoice Creation Crash (`ProgrammingError`)
- **Symptom:** Attempting to create an invoice from a contract (`CO-CR-2026-0241`) threw:
  ```
  pymysql.err.ProgrammingError: ('DocType', 'Construction Contract Zero Qty Item')
  ```
- **Root Cause:** In `query_context.py:get_contract_item_quantity_map()`, legacy code was still executing `frappe.get_all("Construction Contract Zero Qty Item", ...)` to aggregate contract item quantities. Because the table was dropped, MariaDB raised a table missing error.
- **Resolution:** Removed the secondary table query in `query_context.py` and updated unit tests in `test_query_context.py`. All quantities now load exclusively from `tabConstruction Contract Items`.

### B. Legacy Dialogs & Interceptions
- **BOQ Upload:** Cleaned `validate_uploaded_data` in `boq.js` to remove obsolete `zero_qty_warnings` popups.
- **BOQ Variation Order:** Removed `show_boq_zero_qty_warning()` and the `before_submit` check from `boq_variation_order.js`, eliminating false warnings stating that `Qty = 0` will delete the BOQ item and its resources.

### C. Orphaned Schema Fields Purged
Purged unused multi-table movement fields (`source_zero_qty_item`, `zero_qty_movement`) from:
- `boq_variation_order_items.json`
- `boq_variation_order_logs.json`
- `variation_order_items.json`
- `variation_order_items_logs.json`

### D. Performance & Query Optimizations
- **$O(N^2) \to O(N)$ Loop Reductions:** Replaced quadratic row deletion checks with set-based lookups in `ConstructionController` and `BOQ`.
- **Vectorized Contract Series Operations:** Optimized Pandas Series iteration in `construction_contract.py:update_items_child_table_variation_quantity`, replacing `iterrows()` and list deletions with `zip()`.
- **Batched DB Operations:** Replaced iterative `get_doc` + `save()` loops in contract synchronization with direct `frappe.db.set_value()` writes.
- **Batched Parent Lookups:** Batched contract and parent lookups in `controllers/upload_data.py`.

---

## 4. Modified Files Inventory

| Area | File Path | Description of Changes |
| :--- | :--- | :--- |
| **Server** | `doctype/construction_invoice/query_context.py` | Removed query to dropped `Construction Contract Zero Qty Item`. |
| **Server** | `doctype/construction_contract/construction_contract.py` | Cleaned `get_boq_items_sort_order` docstring and vectorized loops. |
| **Server** | `doctype/construction_invoice/construction_invoice.py` | Single-table invoice mapping, `is_zero_qty_item` handling, shared allowance checks. |
| **Server** | `doctype/construction_invoice/boq_invoicing.py` | Recalculates zero-qty totals directly on `BOQ Child`. |
| **Server** | `controllers/upload_data.py` | Contract upload validation against single-table `BOQ Child` sources. |
| **Client** | `doctype/boq/boq.js` | Removed legacy Excel zero-qty warning popup. |
| **Client** | `doctype/boq_variation_order/boq_variation_order.js` | Removed submit and upload zero-qty warning popups. |
| **Schema** | `doctype/boq_variation_order_items/boq_variation_order_items.json` | Removed `source_zero_qty_item`. |
| **Schema** | `doctype/boq_variation_order_logs/boq_variation_order_logs.json` | Removed `source_zero_qty_item` and `zero_qty_movement`. |
| **Schema** | `doctype/variation_order_items/variation_order_items.json` | Removed `source_zero_qty_item`. |
| **Schema** | `doctype/variation_order_items_logs/variation_order_items_logs.json` | Removed `source_zero_qty_item` and `zero_qty_movement`. |
| **Patches**| `patches/v0_0_5/drop_zero_qty_item_doctypes_and_tables.py` | Migration patch dropping tables and DocTypes. |
| **Patches**| `patches.txt` | Registered patch `drop_zero_qty_item_doctypes_and_tables`. |
| **Tests**  | `doctype/construction_invoice/test_query_context.py` | Single-query assertion for contract items map. |
| **Tests**  | `mixins/test_invoice_hierarchy_request.py` | Replaced legacy `items_with_zero_qty` fixture with `items`. |
| **Tests**  | `utils/test_shared_overbilling.py` | Verified shared overbilling limits on zero-qty items. |
| **Tests**  | `utils/test_minimum_allocation.py` | Verified minimum spatial allocation compatibility. |

---

## 5. Verification & Validation Summary

- **Syntax & Compilation:**
  - `python3 -m compileall fabrica_construction/` $\to$ **0 syntax errors, 100% clean compilation**.
  - `python3 -m json.tool` $\to$ All modified JSON DocTypes validated valid JSON.
- **Unit Testing:**
  - `test_query_context.py::test_contract_item_quantity_map_loads_all_quantity_fields` $\to$ **PASSED**.
  - `test_shared_overbilling.py` $\to$ **PASSED (2/2)**.
  - `test_minimum_allocation.py` $\to$ **PASSED (13/13)**.
  - `test_construction_invoice.py` $\to$ **PASSED (4/4 zero-qty suite)**.
  - `test_construction_controller.py` $\to$ **PASSED (1/1)**.
- **Client End-to-End Tests (Node.js):**
  - `test_construction_contract_excel_sync.js` $\to$ **PASSED**.
  - `test_contract_upload_source_links.js` $\to$ **PASSED**.
  - `test_excel_controls.js` $\to$ **PASSED**.
