# US-2026-210-0894: Retroactive Change Rate totals

## Status and scope

Status: initial technical plan, based on local source inspection on November 1, 2026.

Source: [US-2026-210-0894](US-2026-210-0894.md).

All proposed application changes belong to `frappe-bench/apps/fabrica_construction`.
This document does not authorize implementation, migration, or site execution.
No application files were changed for this plan.

## Required behavior

- For Retroactive Change Rate, VO Total Quantity sums full included row quantities.
- Each row Amount equals Quantity × New Rate. Monetary header totals use those revised amounts.
- Existing currency conversion, taxes, discounts, and rounding still apply.
- Contract Variation Amount includes each submitted rate contribution once: Quantity × (New Rate − Old Rate).
- Later rate changes and recalculation preserve earlier valid variation contributions.
- Permitted cancellation removes only the cancelled VO contribution.
- Contract row Amount remains Quantity × New Rate. Variation Amount does not increase that Amount again.
- Rated Only exclusions, Retroactivated exclusions, eligibility, and unchanged-quantity validation remain in place.
- Other VO types retain their calculation rules.

## Confirmed source behavior

Paths below are relative to the application root.

| File or method | Current behavior | Planning implication |
| --- | --- | --- |
| `fabrica_construction/fabrica_construction/doctype/variation_order/calculate_vo_taxes_and_totals.py`, `calculate_net_total()` | Sums `variation_amount` and `variation_quantity` for all VO types, excluding Rated Only rows. | Add a type-specific basis for Retroactive Change Rate. |
| `doctype/variation_order/variation_order.py`, `calculate_variation_order_construction_contract_item_variation_quantity()` | Sets variation quantity from `qty - actual_quantity`, then multiplies by rate. | Keep quantity validation separate from the revised monetary basis. |
| `variation_order.py`, `_update_construction_contract_item()` | Applies the new rate and recalculates variation amount from variation quantity. | The uninvoiced path needs persistent rate contribution accounting. |
| `variation_order.py`, `_create_new_construction_contract_item_for_retroactive_change_rate()` | Copies an invoiced row and prices its full quantity at the new rate. | Preserve contribution history when replacing the active row. |
| `variation_order.py`, `_block_old_construction_contract_item()` | Marks the old retroactive row as history and clears its variation quantity and amount. | Transfer valid contributions before excluding the historical row. |
| `doctype/construction_contract/construction_contract.py`, `set_variation_amount_from_items()` | Overwrites each row Variation Amount with `variation_quantity × rate`. Excludes Rated Only and Retroactivated rows from the header. | Recalculation must reconstruct the complete contribution instead of erasing rate effects. |
| `doctype/construction_contract/construction_contract.js`, `recalculate_variation_amounts()` | Repeats the server formula and exclusions. | Match the server formula without requiring asynchronous totals during form calculation. |
| `doctype/variation_order_items_logs/variation_order_items_logs.py` and `.json` | Store before, after, replacement, and VO row snapshots. Logs have cancellation state and VO links. | Reuse these lifecycle records where possible. |

The shared calculator already derives row amounts from quantity and rate.
Changing only the VO header does not resolve Contract contribution loss.
Changing only submission does not resolve later server or browser recalculation.

## Calculation model

Keep revised pricing separate from variation accounting:

```text
VO row Amount = full quantity × new rate
rate contribution for one VO row = submitted quantity × (new rate − source rate before submit)
Contract row Amount = current quantity × current rate
Contract Variation Amount = sum of valid quantity and rate contributions
```

Capture the source rate from the actual Contract state used for submission.
Do not derive an old rate from the Contract after mutation.
Do not increment a parent total during recalculation. Rebuild totals from persisted contribution state.

Existing quantity contributions require special care when a rate changes.
Repricing `variation_quantity` at the new rate and adding the full rate difference can count part of that difference twice.
For rate-affected rows, preserve the prior valid variation amount and add only the new rate contribution.
Later quantity changes must add or remove their own contribution under their existing VO rules.

## Proposed design and alternatives

Recommended direction: use persistent contribution state on the active Contract row, with VO logs recording each transition.
Server and browser calculations can then use the same row data.
Do not finalize field names or add schema until the transition audit below is complete.

Two implementation options need comparison:

1. Persist the complete variation contribution for rate-affected rows, with an explicit state marker.
   Preserve it during recalculation. Update it through existing quantity and rate mutation paths.
2. Persist a monetary adjustment to the existing `variation_quantity × rate` formula.
   Recalculate that adjustment on each rate transition to preserve previous contributions without double counting.

Choose the smallest option that preserves contributions through row replacement, later quantity changes, and cancellation.
A log-derived ledger is an alternative if row state cannot represent those transitions reliably.
It requires exact row lineage and a browser data strategy, so do not introduce it without evidence.

## Phase 1: Complete transition audit

1. Trace VO validation, item calculation, tax calculation, submit, log creation, and Contract persistence order.
2. Trace both invoiced replacement and uninvoiced update paths.
3. Find every Contract row writer that changes rate, quantity, variation amount, or row identity.
4. Trace cancellation guards, snapshot restoration, replacement-row treatment, and log cancellation order.
5. Check whether existing snapshots contain enough data to restore the chosen contribution state.
6. Trace browser calculation triggers and the shared calculator's discount and tax inputs.
7. Check invoice and remaining-amount consumers before changing row Variation Amount semantics.
8. Confirm how existing submitted rate changes can be reconstructed from their logs.

Exit condition: select one persistence model and list its exact schema and method changes before implementation approval.

## Phase 2: Correct VO totals

1. Branch only for `Retroactive Change Rate` in `CalculateVOTaxesAndTotals`.
2. Sum full quantities for included rows and use revised row amounts for monetary totals.
3. Preserve the existing Rated Only filter and conversion behavior.
4. Keep tax, discount, and rounding processing in the existing calculator pipeline.
5. Verify that item net amounts and base amounts use the same revised pricing basis.
6. Preserve current behavior for every other VO type.

Do not use the rate difference as the VO header total.
The story requires revised pricing there and a rate difference in Contract variation accounting.

## Phase 3: Preserve Contract contributions

1. Capture each changed row's source quantity, source rate, and existing valid variation contribution before mutation.
2. Apply its rate contribution once during submit.
3. Carry valid contribution state to the replacement row when the source has invoices.
4. Keep the historical Retroactivated row excluded from Contract totals.
5. Update server and browser recalculation to use the selected contribution model.
6. Preserve contributions when another rate change or a supported quantity variation follows.
7. Store the contribution transition in the existing VO log lifecycle.
8. Preserve existing transaction boundaries without intermediate commits.

Put shared contribution logic in one focused module if several lifecycle methods need it.
Avoid unrelated changes to the existing large controllers.

## Phase 4: Reverse permitted cancellations

1. Retain the existing later-VO and invoice cancellation guards.
2. Restore the prior contribution state through the existing snapshot reversal path.
3. Remove only this VO's contribution from active accounting.
4. Prevent cancelled replacement rows from retaining a counted contribution.
5. Recalculate the Contract using the same server method used after submission.
6. Keep log cancellation and Contract changes in the same transaction.

Do not broaden cancellation eligibility under this story.

## Expected impact

The four story files require review and likely changes.
The selected persistence model may also require Contract item metadata and VO log serialization changes.
Any schema additions, historical data patch, or helper module must be listed explicitly after phase 1.
Do not edit Frappe, ERPNext, or another custom app.

## Planned verification

These are proposed scenarios with expected results. No tests or simulated passes have been executed for this plan.
Examples exclude taxes and discounts unless stated.

| Scenario | Expected result |
| --- | --- |
| Quantity 10, rate 100 → 120 | VO quantity 10 and Amount 1,200. Contract Amount 1,200 and rate contribution +200. |
| Quantity 10, rate 100 → 80 | VO Amount 800. Contract rate contribution −200. |
| Second change 120 → 130 on quantity 10 | Add +100 once. Cumulative rate contribution becomes +300. |
| Prior quantity contribution +200, quantity 10, rate 100 → 120 | Preserve +200 and add +200. Contract Variation Amount becomes 400. |
| Repeat save, refresh, and recalculation | Variation Amount remains unchanged. |
| Invoiced source row | Replacement keeps full revised pricing and contribution history. Historical row remains excluded. |
| Permitted cancellation of second rate change | Restore the first change's valid contribution and pricing. |
| Cancellation blocked by existing guards | No Contract or contribution mutation persists. |
| Mixed changed and unchanged rows | Unchanged-rate rows add no rate contribution. Header quantities follow included-row rules. |
| Rated Only and Retroactivated rows | Existing exclusions remain effective in their respective totals. |
| Conversion, inclusive/exclusive tax, discounts, and rounding | Existing pipeline processes revised VO amounts without a second rate-difference charge. |
| Other VO types and later quantity changes | Existing type rules remain valid and earlier valid contributions survive. |
| Browser and server recalculation | Matching row and header Variation Amounts at configured precision. |

After implementation approval, use static artifact checks and clearly labeled simulated lifecycle traces by default.
Actual site execution requires an explicit request.

## Open implementation decisions

- Select the persistence model after tracing all affected row writers.
- Decide whether historical submitted VOs need a data patch after checking snapshot completeness.
- Confirm the treatment of later quantity variations on rate-affected rows against each existing VO type's rules.

These decisions block a final implementation patch, but do not change the story's required arithmetic.
