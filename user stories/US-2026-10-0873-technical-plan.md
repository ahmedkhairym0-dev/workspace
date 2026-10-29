# US-2026-10-0873: Technical Plan

Date: 2026-10-28

Status: Updated VO blocking, invoice settlement, and allowance recalculation changes implemented. VO allowance restoration on cancellation remains pending scope confirmation.

Python syntax, diff whitespace, and static review checks passed. Mocked regression cases were added but not executed.

Source: [US-2026-10-0873.md](US-2026-10-0873.md).

Requirement update: use permanent blocking only when paid and progress percentages both equal 100%. Otherwise, use temporary blocking until invoice settlement.

Reviewed app: `fabrica_construction`.

Reviewed branch: `feat/preserve-overbilling-allowance-quantity-during-vo-rate-change-splits--US-2026-10-0873`.

## Required behavior

When an invoiced item changes rate, the existing VO flow can retain the original row and create a replacement.

Set the original row's flags from `previous_paid_percent` and `previous_progress_percent`:

| Original row percentages | `block_item` | `temp_block_item` |
| --- | --- | --- |
| Both equal 100% | 1 | 0 |
| Either does not equal 100% | 0 | 1 |

Allow a temporarily blocked row to complete settlement through invoices. After an invoice update, use the same percentage rule.

Keep the existing allowance transfer for rate-change splits. Transfer the original stored `over_billing_allowance_quantity` to the replacement.

Set the original row's allowance quantity to zero. Preserve both values through `_refresh_contract_over_billing_state()`.

Transfer the full stored quantity. Do not calculate a percentage of either split quantity or transfer only the unused allowance.

Let `A` be the original stored allowance before the split. The final allowances must satisfy `old = 0`, `new = A`, and `old + new = A`.

The sum describes conservation of the original allowance. Do not add the original allowance again to an allowance already assigned to the replacement.

For multiple source rows, transfer each source allowance to its corresponding replacement.

Example: original quantity 100, invoiced quantity 40, stored allowance 10, and contract allowance 10%.

| Row after the split | Quantity | Required allowance | Current percentage calculation |
| --- | --- | --- | --- |
| Temporarily or permanently blocked original | 40 | 0 | 4 |
| Active replacement | 60 | 10 | 6 |

The same rule applies when the stored allowance differs from the current percentage calculation.

In the example, the current split allowances total `4 + 6 = 10`. The required result moves that original allowance to the replacement: `0 + 10 = 10`.

## Current behavior and root cause

All method references below belong to `variation_order.py`, unless another file is named.

1. `on_submit()` calls `back_update_construction_contract_qty()` before `back_update_construction_contract_rate()`.
2. The quantity method calls `_persist_construction_contract_for_vo_submit()`, even when changed pricing routes the item into the rate method.
3. Persistence calls `_refresh_contract_over_billing_state()`, which recalculates every row's allowance and writes the result to the database.
4. `_create_new_construction_contract_item()` then resets the replacement allowance to zero.
5. `_block_old_construction_contract_item()` selects temporary or permanent blocking. It does not transfer allowance.
6. The rate method saves the rows and logs their snapshots. It then refreshes the Contract again.
7. That final refresh calculates allowances from the split quantities, replacing the required transfer values.

The earlier branch change permanently blocked every invoiced rate-change source row. The latest requirement restores temporary blocking for incomplete settlement.

Copying the allowance inside the split helper alone cannot solve this problem. An earlier refresh can already change the original stored value.

Existing tests cover split routing and blocking percentages. The matching matrix mocks the allowance refresh, so it cannot detect this overwrite.

## Proposed changes

### 1. Preserve the allowance before the first refresh

Capture the stored allowance before `on_submit()` starts Contract mutations or allowance refreshes.

Identify actual rate changes on invoiced source rows. Exclude allocation-only changes from this story.

Identify pending rate splits independently of payment and progress percentages.

Keep the captured values by Contract row identity in transient VO state. Protect pending source values during intermediate refreshes.

Do not use the Contract allowance percentage to rebuild this baseline.

### 2. Set the original blocking state and transfer its allowance

Keep replacement creation and blocking in their existing order.

Remove the unconditional permanent-block condition for invoiced rate changes from `_block_old_construction_contract_item()`.

For an invoiced rate change, require both saved percentages to equal 100% before permanently blocking the original.

Otherwise, set `block_item = 0` and `temp_block_item = 1`.

Keep existing blocking rules for allocation-only splits and other operations outside this condition.

Keep Retroactive Change Rate blocking unchanged. The user now includes that VO type in the allowance transfer and preservation requirements.

For a qualifying rate change, assign the captured source allowance to the replacement. Assign zero to the original.

Keep the replacement active. Preserve the existing quantity, amount, and retroactive-rate calculations for each VO type.

Save both rows before the existing item log captures their final state.

Keep the existing pre-change snapshot's original allowance. The snapshot must represent the state before any allowance refresh.

Leave `over_billing_allowance_quantity_used` and the existing replacement billing resets unchanged.

### 3. Preserve transfers during later VO refreshes

Build a set of protected row identities from pending transfers and existing active VO split logs.

Record `rate_change_allowance_transfer` in the existing log's `variation_order_item_json` when a qualifying transfer occurs.

Use that marker and the log's old and replacement identities to protect the transferred allowances.

Later submitted edits can change the replacement's saved rate. The marker preserves transfer identity when that rate changes again.

Set allowance to zero for every row with `block_item` or `temp_block_item` set. This rule takes priority over pending or saved transfers.

For active replacement rows, preserve the transferred allowance from their stored values.

Share the transfer-log lookup through `services/contract_item_allowance.py`. Reuse it during VO refresh and invoice processing.

Read logs for the linked Contract in one query. Exclude cancelled logs and VOs. Do not query once per Contract row.

Do not rely on `construction_contract_item` attributes assigned to replacement documents. The child DocType does not define that stored field.

For protected active rows, preserve the stored allowance instead of applying the percentage formula. Keep blocked originals at zero.

Use membership checks to preserve zero allowances. Do not treat zero as a missing transfer.

Continue the existing calculation for unrelated active rows. Blocked and temporarily blocked rows always receive zero allowance.

Keep the existing allowance database writes and `recalculate_over_billing_allowance_remaining()` call.

The Contract remaining allowance is an amount. This story changes row allowance quantities, not that monetary calculation.

For chained qualifying splits, preserve zero on earlier source rows. Transfer the active replacement's stored allowance to its next replacement.

Do not replay old snapshot allowances onto intermediate rows. That would duplicate allowance after another split.

### 4. Complete or reverse settlement through invoices

The invoice form already permits paid and progress edits on temporarily blocked items. Keep that behavior.

After invoice submission updates Contract percentages, check the updated `previous_paid_percent` and `previous_progress_percent` values.

When both equal 100%, set `block_item = 1` and clear `temp_block_item`. Otherwise, retain temporary blocking.

The previous invoice code set `block_item` without clearing `temp_block_item`. Replace that assignment with complementary flag values.

On invoice cancellation, check the restored percentages and apply the same rule.

Identify this settlement path from the invoice item's saved temporary flag. The Contract temporary flag may already be clear after settlement.

Leave ordinary invoice items outside this path unchanged.

During invoice submission and cancellation, read transferred row identities once for all linked Contracts.

Before assigning allowance quantity, check the Contract item's blocking flags. If either flag is set, use zero.

For an active transferred replacement, retain its stored allowance. Do not recalculate it from its remaining or split quantity.

For other active items, retain the existing invoice calculation. Keep used allowance capped by the resulting allowance quantity.

### 5. Resolve VO cancellation allowance behavior before implementation

Recommended behavior: cancelling a qualifying VO restores the original allowance from its pre-change snapshot.

Clear the cancelled replacement's transferred allowance. Protect the restored source value during the cancellation refresh.

The current cancellation method restores quantities, rates, and block flags. It does not explicitly restore allowance quantity.

The story does not specify cancellation acceptance behavior. Confirm this recommendation before adding cancellation changes.

## Impacted files

Paths are relative to the `fabrica_construction` app root.

| File | Planned responsibility |
| --- | --- |
| `fabrica_construction/fabrica_construction/doctype/variation_order/variation_order.py` | Select temporary or permanent blocking from completion percentages. Keep allowance capture, transfer, and refresh preservation. |
| `fabrica_construction/fabrica_construction/doctype/variation_order/test_variation_order.py` | Cover the transfer, intermediate and repeated refreshes, persistence, and unchanged flows. |
| `fabrica_construction/fabrica_construction/doctype/variation_order_items_logs/variation_order_items_logs.py` | Store the transfer marker in the existing item JSON without changing the schema. |
| `fabrica_construction/services/test_variation_order_provisional_sum.py` | Update the submit-order expectation to include allowance capture before Contract changes. |
| `fabrica_construction/fabrica_construction/doctype/construction_invoice/construction_invoice.py` | Set complementary flags after settlement and restore the correct state on invoice cancellation. |
| `fabrica_construction/fabrica_construction/doctype/construction_invoice/test_construction_invoice.py` | Cover complete and incomplete settlement, cancellation, and both invoice accumulation modes. |
| `fabrica_construction/services/contract_item_allowance.py` | Share the active transfer-log lookup between VO and invoice recalculation. |
| `fabrica_construction/services/test_contract_item_allowance.py` | Check transfer markers, chained row identities, and active-log query filters. |

Reuse existing log fields. No schema change, migration, new hook, or core change is planned.

## Simulated verification plan

These are expected outcomes, not executed test results.

| Case | Expected result |
| --- | --- |
| Invoiced rate-change split with both percentages equal 100% | Original has `block_item = 1`, `temp_block_item = 0`, and allowance zero. Active replacement receives the original allowance. |
| Either percentage does not equal 100% | Original has `block_item = 0` and `temp_block_item = 1`. The allowance transfer remains preserved. |
| Invoice completes both percentages to 100% | Original becomes permanently blocked and its temporary flag clears. |
| Invoice leaves either percentage incomplete | Original remains temporarily blocked. |
| Cancelling the settlement invoice restores incomplete percentages | Original returns to temporary blocking. |
| Cancelling an invoice leaves both percentages at 100% | Original remains permanently blocked. |
| Either percentage exceeds 100% on an ordinary invoiced rate change | Exact equality is not satisfied. The original remains temporarily blocked. |
| Allowance conservation | Final old and replacement allowances sum to the original stored allowance, without duplication. |
| Stored allowance differs from quantity times percentage | Transfer preserves the stored value, including configured precision. |
| Quantity changes with the rate | Transfer remains independent of the resulting split quantities. |
| Intermediate quantity-stage refresh | The source allowance remains available for the later transfer. |
| Repeated refresh after Contract reload | Original stays zero. Replacement retains its allowance. Database writes match those values. |
| Stored allowance is zero | Both allowances remain zero, even with a positive Contract percentage. |
| Multiple independent source rows | Each replacement receives only its own source allowance. |
| A replacement later undergoes another qualifying split | Earlier source rows stay zero. The latest replacement receives the active source allowance. |
| Unrelated Contract row | Existing percentage calculation continues. |
| Uninvoiced update or allocation-only split | Existing behavior continues. |
| Retroactive rate change | Preserve its existing behavior. The new percentage rule does not apply to this VO type. |
| Used allowance | Existing values and rules follow their current behavior. |
| Blocked or temporarily blocked item has a stale nonzero allowance | VO refresh and invoice submission or cancellation set allowance to zero. |
| Active replacement is invoiced or its invoice is cancelled | Preserve the transferred allowance for the original total quantity. Do not transfer it twice. |
| Cancellation, if approved | Original allowance returns from its snapshot. Cancelled replacement allowance becomes zero. |

Extend the existing mocked tests. Exercise the real allowance refresh in targeted tests instead of mocking it throughout.

Check both in-memory values and database write arguments. Keep runtime tests simulated unless real execution is requested.

## Scope boundaries and open decisions

- Confirm the proposed VO cancellation allowance behavior before implementation.
- Retroactive Change Rate keeps its existing blocking behavior. Its allowance transfer and recalculation are now in scope.
- Invoice submission and cancellation follow the same allowance zeroing and transfer preservation rules as VO refresh.
- Preserve invoice consumption, used allowance, BOQ allocation, and Contract allowance percentages.
- Do not repair existing records or backfill historical splits without a separate request.
