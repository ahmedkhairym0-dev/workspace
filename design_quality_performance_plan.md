# Implementation Plan: Design Subsystem Quality & Performance Modernization

## Goal Description
Resolve critical bugs, eliminate database write-lock contention on read operations, eliminate N+1 ORM loops, and optimize query aggregation across `Design Contract`, `Design Invoice`, and associated advance modules.

---

## User Review Required

> [!IMPORTANT]
> **P0 Runtime Fix**: [design_billing.py](file:///home/hatem/frappe-bench/apps/fabrica_construction/fabrica_construction/utils/design_billing.py#L21) contains an unbound variable `query` that crashes invoice validation and contract allowance calculations in live/staging environments.
>
> **P0 Concurrency Fix**: Viewing a Design Contract currently acquires exclusive row write locks (`SELECT ... FOR UPDATE`) across financial documents. We will remove `for_update` from read-only desk button-status endpoints.

---

## Proposed Changes

### Phase 1: Critical Bug Fix & Locking Sanitization (P0)

#### [MODIFY] [design_billing.py](file:///home/hatem/frappe-bench/apps/fabrica_construction/fabrica_construction/utils/design_billing.py)
Fix the unbound variable `query` in `get_submitted_net_billing`:
```python
def get_submitted_net_billing(contract_name, *, precision, exclude_invoice=None):
    invoice = frappe.qb.DocType("Design Invoice")
    query = (
        frappe.qb.from_(invoice)
        .select(invoice.net_total, invoice.conversion_rate)
        .where(
            (invoice.design_contract == contract_name)
            & (invoice.docstatus == 1)
            & (invoice.name != (exclude_invoice or ""))
        )
        .orderby(invoice.name)
    )
    if not frappe.flags.in_import_preview:
        query = query.for_update()
    rows = query.run(as_dict=True)
    return flt(
        sum(flt(flt(row.net_total) * (flt(row.conversion_rate) or 1), precision) for row in rows),
        precision,
    )
```

#### [MODIFY] [design_contract_advances.py](file:///home/hatem/frappe-bench/apps/fabrica_construction/fabrica_construction/utils/design_contract_advances.py)
Sanitize locking on read-only endpoints:
- In `get_remaining_original_advance(contract, exclude_request=None, for_update=False)`: Pass `for_update=False` when called from `get_advance_request_status`.
- Only acquire locks (`for_update=True`) during actual transaction mutations (`validate`, `on_submit`, `create_cash_advance_request`).

---

### Phase 2: Eliminate N+1 ORM Loops & Database Aggregation (P1 Performance)

#### [MODIFY] [design_advance_sources.py](file:///home/hatem/frappe-bench/apps/fabrica_construction/fabrica_construction/utils/design_advance_sources.py)
- **Batch Query Sources**: In `get_funded_source_rows`, include `pe.docstatus`, `pe.custom_payable_cheque_returned`, `per.design_payment_request`, and `pe.design_advance_paid_at` directly in the query.
- **Eliminate `frappe.get_doc` in Loop**: In `get_design_advance_sources`, remove `frappe.get_doc(entry.reference_type, entry.reference_name)` inside the `for entry in entries:` loop. Extract needed attributes from the batch result.
- **Batch Request Lookups**: Fetch all linked `Payment Request` records in a single `in` query rather than querying per row via `get_source_request`.

#### [MODIFY] [design_invoice.py](file:///home/hatem/frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/design_invoice/design_invoice.py)
- **SQL Aggregation for History**: In `get_previous_invoice_map`, replace in-memory nested dictionary loops with a single SQL query aggregating `MAX(accumulative_percentage)` and `SUM(amount)` grouped by `design_contract_item`.
- **Remove Redundant Account Fallback**: In `set_missing_values`, rely solely on the canonical `get_credit_to_account_for_supplier` helper rather than running a secondary `get_party_account` branch.

#### [MODIFY] [design_invoice_item.json](file:///home/hatem/frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/design_invoice_item/design_invoice_item.json)
- Add `"search_index": 1` to field `design_contract_item` to speed up historical invoice joins.

---

## Verification Plan

### Automated / Simulated Test Steps (per AGENTS.md simulation standard)
1. **Billing Validation Test**:
   - Run `get_submitted_net_billing` on a contract with submitted invoices; verify no `UnboundLocalError` occurs and net billing matches expected sums.
2. **Read-Only Concurrency Check**:
   - Call `get_advance_request_status` for a contract; verify no row-level write locks (`SELECT ... FOR UPDATE`) are held on the database connection.
3. **Advance Sources N+1 Elimination**:
   - Simulate a contract with 10 funded advance payment entries. Call `get_design_advance_sources(contract)`; verify query count remains constant ($O(1)$ batch queries) rather than scaling with the number of payments ($O(N)$).
4. **Historical Invoice Aggregation**:
   - Test `get_previous_invoice_map` against a contract with multi-invoice history; verify `previous_progress` and `previous_amount` match exactly with database aggregation.

### Manual Verification
- Open Design Contract and Design Invoice in desk view; ensure "Cash Advance", "Advance Payment", and "Create" buttons render instantly without UI lag.
- Validate, save, and submit draft Design Invoices; ensure advance recovery deductions compute seamlessly.
