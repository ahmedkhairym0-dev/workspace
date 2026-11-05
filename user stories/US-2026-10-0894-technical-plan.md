# US-2026-10-0894: Technical Plan

Date: 2026-11-03

Status: Implemented with the selected `variation_rate` field and formula after approval.

Python syntax, JavaScript syntax, JSON parsing, and diff whitespace checks passed.
Regression cases were added but not executed. Site migration remains pending.

Source: [US-2026-10-0894.md](US-2026-10-0894.md).

Target app: `fabrica_construction`.

## Required behavior

Apply the changed calculation only to `Retroactive Change Rate`.

- Sum the full quantities of included VO rows into `total_qty`.
- Set each VO row's `amount` to `qty × rate`, using the new rate.
- Calculate monetary header totals from those revised amounts.
- Preserve existing currency conversion, taxes, discounts, precision, and rounding.
- Keep active Contract row amounts equal to `qty × rate`.
- Keep `retroactivated` rows excluded from Contract totals.
- Preserve calculations for other VO types.

The VO's revised value and the Contract's rate-change contribution serve different purposes.

Store the rate difference in `variation_rate` and calculate the Contract row Variation Amount as:

```text
variation_amount = qty × variation_rate + variation_quantity × rate
```

`variation_quantity` is the existing field corresponding to `variation_qty` in the requested formula.

## Current behavior and root cause

Paths below are relative to the app root.

| File and method | Current behavior | Required change |
| --- | --- | --- |
| `fabrica_construction/fabrica_construction/doctype/variation_order/calculate_vo_taxes_and_totals.py`: `CalculateVOTaxesAndTotals.calculate_net_total()` | Sums `variation_quantity` and `variation_amount` for every VO type. | Select full quantities and revised values for Retroactive Change Rate. |
| `fabrica_construction/fabrica_construction/doctype/variation_order/variation_order.py`: `calculate_taxes_and_totals()` | Already sets row `amount = qty × rate`. | Preserve this behavior. |
| `variation_order.py`: `_create_new_construction_contract_item_for_retroactive_change_rate()` | Copies the source row and assigns its full quantity at the new rate. | Preserve revised amounts and carry the approved rate-change contribution. |
| `variation_order.py`: `_update_construction_contract_item()` | Updates uninvoiced rows in place and calculates variation from quantity alone. | Preserve the rate-change contribution for this path too. |
| `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.py`: `set_variation_amount_from_items()` | Replaces row Variation Amount with `variation_quantity × rate`. | Retain the rate-change contribution during recalculation. |
| `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js`: `recalculate_variation_amounts()` | Repeats the quantity-only formula in the form. | Match the server calculation. |

The unchanged quantity makes the VO difference fields zero. The header therefore loses the revised value.
Contract recalculation also removes rate-change effects because it uses only quantity differences.

Contract quantity, variation, and tax aggregation already exclude `retroactivated` rows.
The shared calculator also excludes `rated_only` Contract rows.
These exclusions must remain in place.

The VO client controller currently disables `calculate_taxes_and_totals()`.
Keep header calculation on the existing server path. Live client header calculation is outside this plan.

## Proposed implementation

### 1. Correct VO header inputs

Change `CalculateVOTaxesAndTotals.calculate_net_total()` for Retroactive Change Rate only.

1. Sum included row `qty` values into `total_qty`.
2. Sum row `amount` and `base_amount` into `total` and `base_total`.
3. Sum row `net_amount` and `base_net_amount` into `net_total` and `base_net_total`.
4. Keep the existing rounding step and `rated_only` exclusion.

Use values produced by the existing item calculation and currency conversion pipeline.
Do not replace discounted net amounts with raw `qty × rate` during later calculation passes.
Keep the existing difference-based branch for other VO types.

### 2. Store the Contract rate difference

Add a read-only Currency field named `variation_rate` to Construction Contract Items.
This field stores the cumulative Retroactive Change Rate difference per unit for that row.
Use the same currency and precision conventions as the existing `rate` field.

Use the selected row formula:

```text
variation_amount = qty × variation_rate + variation_quantity × rate
amount = qty × rate
```

The additional field supplies a stable rate difference to both Python and JavaScript.
Recalculation reads this field and uses the current quantity. It never changes the stored rate difference.

Do not use `actual_amount` as an assumed original-rate baseline.
The replacement helper already sets it to the revised amount, and other paths update it.

### 3. Capture and apply each rate change once

In `variation_order.py`, capture the previous rate and stored `variation_rate` before mutating the Contract row.

For a Retroactive Change Rate operation:

```text
current rate difference = new rate − previous rate
resulting variation_rate = previous variation_rate + current rate difference
```

Apply the resulting `variation_rate` to the active row.
For invoiced rows, carry it to the replacement created by the existing split flow.
For uninvoiced rows, store it on the row updated in place.

Keep the historical source excluded through its existing `retroactivated` flag.
Do not add the contribution to `amount`, `net_amount`, or the taxable Contract value.
Preserve the existing quantity, billing history, allocation, blocking, and allowance behavior.

### 4. Match Contract server and form calculations

Update `set_variation_amount_from_items()` and `recalculate_variation_amounts()` with the selected row formula.

Continue summing only rows that are neither `rated_only` nor `retroactivated`.
Follow existing field precision conventions.
Keep row Amount calculated directly from quantity and rate.

For later quantity variations, retain `variation_rate` and calculate both terms with the current row values.
Do not accumulate calculated monetary contributions in the stored rate field.

### 5. Preserve cancellation and snapshots

Extend the existing VO snapshots to retain `variation_rate` before and after the change.
Restore the previous value when the VO is canceled.
Clear `variation_rate` on a canceled replacement retained with zero quantity and amount.

Review the existing submitted-VO update path for writes that replace `variation_amount`.
Apply the selected formula where that path can affect a qualifying row.
Keep existing eligibility and cancellation restrictions.

### 6. Check dependent amount consumers

Some Contract paths calculate remaining amounts from `actual_amount + variation_amount`.
That sum would double-count the rate contribution if `actual_amount` already contains revised pricing.

Trace these consumers before implementation is complete.
For affected Retroactive Change Rate rows, use the revised row value once when calculating remaining amounts.
Keep unrelated amount calculations unchanged.

## Expected file scope

Required calculation files:

- `fabrica_construction/fabrica_construction/doctype/variation_order/calculate_vo_taxes_and_totals.py`
- `fabrica_construction/fabrica_construction/doctype/variation_order/variation_order.py`
- `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.py`
- `fabrica_construction/fabrica_construction/doctype/construction_contract/construction_contract.js`

Field metadata:

- `fabrica_construction/fabrica_construction/doctype/construction_contract_items/construction_contract_items.json`
- Generated child controller type annotations, if required by the existing metadata workflow.

Scoped remaining-amount and invoice consumers:

- `fabrica_construction/services/contract_item_billing.py`
- `fabrica_construction/fabrica_construction/doctype/construction_invoice/construction_invoice.py`

Use revised Contract Amount once for retroactively revised rows.
Recognize zero cumulative rate differences through the linked Retroactive Change Rate VO.
Mixed-type sequences that replace this link after the difference reaches zero remain outside this implementation.

Add focused regression coverage to the existing VO and Contract tests.
Include module docstrings in updated Python modules according to repository instructions.
Do not change core or another custom app.

## Verification plan

The cases below are planned simulations. No tests have been executed for this plan.

Baseline example: quantity `10`, previous rate `100`, new rate `150`, and no previous variations.

| Result | Expected |
| --- | ---: |
| VO row Amount | 1,500 |
| VO Total Quantity | 10 |
| VO Total before taxes and discounts | 1,500 |
| Active Contract row Amount | 1,500 |
| Stored `variation_rate` | 50 |
| Contract rate-change contribution | 500 |
| Historical retroactivated row contribution to Contract totals | 0 |

Mixed example: `qty = 12`, `variation_rate = 50`, `variation_quantity = 2`, and `rate = 150`.
The selected formula gives `variation_amount = 12 × 50 + 2 × 150 = 900`.
The revised row Amount remains `12 × 150 = 1,800`.

Cover these cases:

1. Increase and decrease the rate without changing quantity.
2. Apply the change to invoiced and uninvoiced Contract rows.
3. Combine multiple included rows and excluded rated-only rows.
4. Apply currency conversion, taxes, percentage discounts, fixed discounts, and rounding.
5. Repeat Contract recalculation and reload the form. Values must remain unchanged.
6. Apply successive rate changes. Count each contribution once.
7. Preserve existing quantity variations and check later quantity changes against the selected two-term formula.
8. Cancel a qualifying VO and restore the prior contribution and totals.
9. Check remaining amounts and downstream mappings for duplicate rate contributions.
10. Confirm other VO types retain their existing totals.

## Remaining scope decisions

- Decide whether existing submitted VOs need correction. This plan does not authorize a data backfill.

Migration, real site tests, data backfill, and commits were not performed.
