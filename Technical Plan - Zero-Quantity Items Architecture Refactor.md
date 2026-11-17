# Technical Plan: Zero-Quantity Items Architecture Refactor (`US-2026-11-0406`)

## Executive Summary
This document defines the complete technical architecture and implementation strategy for unifying zero-quantity items into primary child tables across `BOQ`, `Construction Contract`, and `Construction Invoice`, decommissioning legacy split-table mechanisms and parallel variation order subsystems.

---

## 1. Core Principles (Ponytail Ultra)
1. **Single Table of Truth**: All items reside in primary tables (`bill_of_quantity` on BOQ, `items` on Contract, `items` on Invoice).
2. **Natural Zero Contributions**: While $\text{qty} = 0$, financial and progress metrics remain 0 without artificial exclusions:
   $$\text{amount} = 0 \times \text{rate} = 0$$
   $$\text{GL entries} = 0$$
3. **Overbilling Pool Integration**: When invoiced, zero-contract-quantity items draw against the contract's shared over-billing allowance pool.
4. **Historical Backward Compatibility**: Historical database tables (`tabBOQ Zero Qty Item`, `tabConstruction Contract Zero Qty Item`) are retained in the database schema without active UI routing, ensuring historical records and audits remain readable.

---

## 2. Technical Architecture & Component Design

```
+-------------------------------------------------------------+
|                     Construction Settings                   |
|           move_zero_quantity_items_on_submit = 1            |
|                     ("Accept zero QTY")                     |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|                             BOQ                             |
|  - Table: `tabBOQ Child` (`bill_of_quantity`)               |
|  - Items with qty == 0 accepted on validate & submit        |
|  - No row movement or deletion on submit                    |
|  - Total Amount: excludes qty == 0 rows                     |
+-------------------------------------------------------------+
                              |
                              | services/boq/mapping.py
                              v
+-------------------------------------------------------------+
|                    Construction Contract                    |
|  - Table: `tabConstruction Contract Items` (`items`)         |
|  - Mapped with qty = 0, rate = boq_rate, amount = 0         |
|  - Single-table Excel upload/download                       |
+-------------------------------------------------------------+
                              |
                              | make_invoice_async()
                              v
+-------------------------------------------------------------+
|                     Construction Invoice                    |
|  - Table: `tabConstruction Invoice Items` (`items`)         |
|  - Flagged: is_zero_qty_item = 1                            |
|  - Validation: qty > 0 strictly required to bill            |
|  - amount = qty * rate * paid% * progress%                  |
|  - Deducts from contract's shared over-billing allowance    |
|  - Generates balanced GL entries                            |
|  - Back-updates: tabConstruction Contract Items & BOQ Child |
+-------------------------------------------------------------+
```

---

## 3. Module Specifications

### Module 1: Construction Settings
- **Fieldname**: `move_zero_quantity_items_on_submit` (Check)
- **Label**: `"Accept zero QTY"`
- **Behavior**: Governs acceptance of zero-quantity lines at document creation and submission boundaries.

### Module 2: Bill of Quantities (BOQ)
- **DocType Schema**: `tabBOQ Child` (`bill_of_quantity`). Removed `items_with_zero_qty` field and `zero_qty_tab`.
- **Validation**:
  - `services/boq/validation.py`: `validate_qty_before_submit` accepts $\text{qty} = 0$ when setting is active; throws error if $\text{qty} < 0$.
  - Empty check: Passes if `bill_of_quantity` has valid rows (even if $\text{qty} = 0$).
- **Lifecycle**: `before_submit()` no longer calls `move_zero_qty_items()`.
- **Mapping**: `services/boq/mapping.py` includes zero-quantity rows in `conditions_to_map_construction_contract()`.

### Module 3: Construction Contract
- **DocType Schema**: `tabConstruction Contract Items` (`items`). Removed `items_with_zero_qty` field and `zero_qty_tab`.
- **Validation**:
  - `construction_contract.py`: `validate_positive_items_fields` accepts $\text{qty} = 0$ when `move_zero_quantity_items_on_submit` is active.
- **Excel Sync**:
  - `construction_contract.js`: Consolidated import/export routines to operate exclusively on the `items` grid.

### Module 4: Variation Orders Subsystem (Decommissioning)
- **Removed VO Types**: Removed `"Update Zero Qty Items"` from selection options in `boq.js`, `boq_variation_order.json`, and `variation_order.json`.
- **Removed Flow Classes**: Deleted `flows/update_zero_qty_items.py` and deregistered from `flows/factory.py`.
- **Removed Controller Branches**:
  - Stripped `ZeroQtyContractVariation` and `ZeroQtyContractCancellation` calls from `variation_order.py` (`validate`, `on_submit`, `before_submit`, `before_cancel`).
  - Stripped `UPDATE_ZERO_QTY_ITEMS` branches from `boq_variation_order.py` and undefined JS flags in `boq_variation_order.js`.
  - Stripped UI read-only and upload overrides from `variation_order.js`.

### Module 5: Construction Invoice & Accounting
- **Invoice Mapping**:
  - In `construction_contract.py`: `make_invoice_async()` flags zero-contract-quantity rows with `is_zero_qty_item = 1`.
- **Validation**:
  - In `construction_invoice.py`: `validate_negative_qty` enforces $\text{qty} > 0$ for all billed items.
- **Pricing & Shared Allowance**:
  - `amount = qty * rate * (paid% / 100) * (progress% / 100)`.
  - Amount is drawn from contract's shared overbilling pool (`over_billing_allowance_remaining`).
- **GL Posting**:
  - In `get_gl_entries()`: Balanced debit/credit entries are generated for all non-zero amounts.
- **Contract & BOQ Back-Updates**:
  - `update_contract_zero_qty_item_billing()` updates `tabConstruction Contract Items`.
  - `update_boq_invoiced_totals()` and `boq_invoicing.py` update `tabBOQ Child`.
  - `back_update_contract_zero_qty_item_for_cancel()` reverses updates upon invoice cancellation.

### Module 6: Utilities, DocType & Physical Table Deletion
- **Physical Table & Metadata Drop**:
  - Dropped `tabBOQ Zero Qty Item` and `tabConstruction Contract Zero Qty Item` via patch `fabrica_construction.patches.v0_0_5.drop_zero_qty_item_doctypes_and_tables`.
  - Deleted metadata from `tabDocType`, `tabDocField`, `tabCustom Field`, and `tabProperty Setter`.
- **Deleted DocType Schemas**:
  - `fabrica_construction/fabrica_construction/doctype/boq_zero_qty_item/`
  - `fabrica_construction/fabrica_construction/doctype/construction_contract_zero_qty_item/`
- **Deleted Utility Modules**:
  - `fabrica_construction/utils/zero_qty_contract_variation.py`
  - `fabrica_construction/utils/zero_qty_contract_cancellation.py`
  - `fabrica_construction/utils/zero_qty_boq_reversal.py`
  - `fabrica_construction/utils/zero_qty_boq_variation.py`
  - `fabrica_construction/tests/boq/test_zero_qty_contract_mapping.py`
- **Streamlined**:
  - `zero_qty_boq.py`: Contains only `setup_move_zero_quantity_items_on_submit()`.
  - `zero_qty_contract.py`: Contains only upload contract source validation querying directly against `tabBOQ Child`.
  - `construction_invoice.py`: Purged all fallback queries and fetches to `Construction Contract Zero Qty Item`.
  - `taxes_and_totals.py`: Purged `Construction Contract Zero Qty Item` doctype check.

---

## 4. Verification & Testing Matrix

| Scenario | Action | Expected Result |
| :--- | :--- | :--- |
| **BOQ Save & Submit** | Add Item A ($\text{Qty}=10, \text{Rate}=100$), Item B ($\text{Qty}=0, \text{Rate}=250$). Submit. | Both rows remain in `bill_of_quantity`. Total amount is 1,000. |
| **Contract Mapping** | Create Contract from submitted BOQ. | Both items map into `items`. Total amount is 1,000. Item B has $\text{Qty}=0, \text{Rate}=250, \text{Amount}=0$. |
| **Invoice Mapping** | Create Invoice from Contract. | Item B maps with `is_zero_qty_item = 1`. |
| **Invoice Validation** | Attempt submit with Item B $\text{Qty}=0$. | Blocked: "Quantity must be greater than zero". |
| **Invoice Billing** | Enter Item B $\text{Qty}=2, \text{Paid}\%=100, \text{Progress}\%=100$. | $\text{Amount} = 500$. Draws 500 from shared overbilling allowance. Balanced GL entries posted. |
| **Invoice Cancel** | Cancel submitted invoice. | GL entries cancelled. Overbilling allowance and contract billed amounts restored. |
