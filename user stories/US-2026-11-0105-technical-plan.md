# US-2026-11-0105: Technical Plan

Date: 2026-11-04

Status: Planned. No implementation or tests have been run.

Source: [US-2026-11-0105.md](US-2026-11-0105.md).

Target app: `fabrica_construction`.

## Required behavior

For an existing uninvoiced Contract row updated by a Variation Order, preserve `actual_quantity` and `actual_amount`. Keep the existing quantity and amount formulas:

```text
qty = actual_quantity + variation_quantity
amount = qty × new_rate
variation_amount = amount − actual_amount
remaining_amount = amount - invoiced_amount
```

This balance must hold after a quantity change, a rate change, or both. A quantity-only increase/decrease must retain a prior rate-change contribution. If the rate never changed, the balance equals `variation_amount = (Q1 × R1) − (Q0 × R0)`. 


For an invoiced rate-change split, keep the historical row and create the active row through the existing split flow. On the new active row, move the amount from `actual_amount` to `variation_amount`: set `actual_amount` to zero and set `variation_amount` to `amount`. This preserves `actual_amount + variation_amount = amount`, which the invoice calculation already consumes.

Keep the submitted Variation Order Quantity and Rate restrictions. Keep existing handling of invoiced quantities. Keep Construction Invoice remaining-amount calculations unchanged.

## Current behavior and root cause

Paths below are relative to the app root.

| File and method | Current behavior | Planned action |
| --- | --- | --- |
| `fabrica_construction/fabrica_construction/doctype/variation_order/variation_order.py`: `back_update_construction_contract_qty()` | Updates `qty`, `amount`, and `variation_amount = amount − actual_amount` for eligible existing rows. | Keep the formulas and confirm a quantity-only VO retains an existing rate difference. |
| `variation_order.py`: `_update_construction_contract_item()` | Updates an uninvoiced row in place, preserves its actual values, and balances `variation_amount` against `actual_amount`. | Keep this behavior and cover rate-only, quantity-only, and combined changes. |
| `variation_order.py`: `_create_new_construction_contract_item()` | Creates the active row for an invoiced rate change with `actual_amount = amount` and `variation_amount = 0`. | Move the active row amount to `variation_amount` and set `actual_amount = 0`. Keep the historical row and split quantities unchanged. |
| `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.py`: `set_variation_amount_from_items()` | Recalculates each row as `amount − actual_amount`. | Keep this balancing rule. Confirm refresh and recalculation retain corrected values. |
| `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js`: `recalculate_variation_amounts()` | Replaces the row value with `variation_quantity × rate`. This drops prior rate differences and any moved split value. | Use `amount − actual_amount`, matching the server calculation. |
| `fabrica_construction/fabrica_construction/doctype/construction_invoice/construction_invoice.py` | Calculates the row total from `actual_amount + variation_amount`. | Do not change this formula. Verify the row representation keeps its result equal to `amount`. |

The agreed example must remain `actual_quantity = 1000`, `actual_amount = 1000`, `qty = 1200`, `rate = 10`, `amount = 12000`, and `variation_amount = 11000`.

## Proposed implementation

### 1. Keep the uninvoiced row balance

In `variation_order.py`, preserve the existing `qty` and `amount` calculations for an in-place row update. Keep the original `actual_quantity` and `actual_amount` unchanged.

Set `variation_amount` to `amount − actual_amount` after the VO updates the row. Do not derive the value only from the current VO quantity delta or rate delta.

Keep the existing rules that prevent submitted Variation Orders from changing Quantity or Rate. Do not change eligibility or invoiced-quantity handling.

### 2. Move the amount on an invoiced rate split

In `_create_new_construction_contract_item()`, keep the existing split quantities, new rate, and `amount = qty × rate` calculation.

Set `actual_amount = 0` and `variation_amount = amount` on the new active row. Keep the historical row's invoiced quantity and amount under the current blocking and split behavior.

Do not change the separate Retroactive Change Rate helper unless an acceptance criterion explicitly routes through that helper. Preserve its quantity restrictions and existing split behavior.

### 3. Align Contract recalculation

Change `recalculate_variation_amounts()` in the Contract form script to calculate each row as `amount − actual_amount`. Keep the existing total exclusions for `rated_only` and `retroactivated` rows.

Keep `set_variation_amount_from_items()` on the same formula. Check whether Contract refresh or recalculation resets `actual_amount` on persisted rows. If it does, keep the stored baseline for existing rows and the explicit zero on the active invoiced split row.

Make sure a later VO that leaves a corrected row unchanged does not clear or replace its variation amount during Contract refresh.

### 4. Leave invoice calculations unchanged

Do not edit `construction_invoice.py`. Its row total uses `actual_amount + variation_amount`, so the new split representation must keep this sum equal to the Contract row `amount`.

Keep remaining amount as the existing Contract row total less invoiced amount. Add a regression check to catch any duplicate or missing amount without changing invoice logic.

## Expected file scope

Paths are relative to the `fabrica_construction` app root.

- `fabrica_construction/fabrica_construction/doctype/variation_order/variation_order.py`
- `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.py`
- `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js`
- `fabrica_construction/fabrica_construction/doctype/variation_order/test_variation_order.py`
- Existing Construction Contract or Construction Invoice tests, only where needed for the refresh and unchanged invoice-formula checks.

No DocType field, schema migration, data backfill, core change, or invoice formula change is planned.

## Verification plan

These are planned checks, not executed results. Keep staging data changes separate from automated tests.

1. Confirm the reproduction Contract starts with the specified B44-P18 and B45-P18 values and no submitted invoices. Confirm each linked BOQ resource has at least 200 units available for its increase.
2. Create a fresh Variation Order for each of criteria 1, 2, 4, and 5. Leave unrelated Contract rows unchanged.
3. For an uninvoiced row, test quantity-only, rate-only, and combined changes. Confirm actual values stay unchanged and `actual_amount + variation_amount = amount` after submit and refresh.
4. For a quantity-only increase after an earlier rate change, confirm the prior rate contribution remains in `variation_amount`.
5. For an invoiced rate change, confirm the historical row keeps the existing invoiced quantity and the new active row has `actual_amount = 0`, `variation_amount = amount`, and the existing split quantity.
6. Reload and recalculate the Contract, then submit a later Variation Order that leaves the corrected row unchanged. Confirm its variation amount remains unchanged.
7. Create a fresh Construction Invoice draft for criterion 3. Confirm its remaining amount uses the unchanged invoice formula and does not double-count the split row.
8. Confirm submitted Variation Orders still reject prohibited Quantity and Rate changes. Confirm existing handling of invoiced quantities remains unchanged.
9. Run the focused Variation Order, Contract, and invoice regression tests available in the app.

For the agreed example, confirm `1000 + 11000 = 12000` after submit, Contract refresh, and invoice draft calculation.