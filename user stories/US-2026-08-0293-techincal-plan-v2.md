# US-2026-08-0293: Technical Plan, Version 2

Date: 2026-10-20

Status: Phases 1–5 implemented. Verification is simulated. Runtime acceptance remains unexecuted.

Python syntax and diff whitespace checks passed. Mocked regression tests were added but were not executed.

The BOQ reconciliation service is connected to the Current BOQ VO lifecycle. No site records were changed.

Source requirements: [US-2026-08-0293.md](US-2026-08-0293.md).

Previous plan: [Version 1](US-2026-08-0293-techincal-plan.md).

## Scope and agreed behavior

Propagate changes in this order: **Variation Order → Construction Contract → BOQ**.

For `Update Current Contracted BOQ`, update the existing linked Contract row from the VO quantity and Provisional Sum status.

Update the Contract quantity only when the VO changes it. Do not split, copy, or create Contract rows for this flow.

Apply the three story cases to the BOQ using the resulting Contract quantities. Create or adjust portions only in the BOQ.

Existing separate Contract rows remain separate. Their quantities and statuses determine the corresponding BOQ portions.

Keep changes inside `fabrica_construction`. Preserve unrelated VO behavior, financial calculations, and existing Contract submission behavior.

## Baseline behavior before phases 4–5

The VO controller already propagates quantity changes to linked Contract rows and updates BOQ contracted and remaining quantities.

`ContractBOQAllocation` converts BOQ portions when the Contract and BOQ Provisional Sum flags differ.

When the flags already match, its conversion filter skips the row. A later quantity change can leave the previous provisional portion unchanged.

`sync_variation_order_boq()` stores a snapshot and skips processing when that snapshot already exists. It does not reconcile later quantity edits.

The submitted VO update path changes Contract quantities and allocation counters. It does not apply the three BOQ distribution cases again.

The existing VO flow also contains Contract row creation and split paths. The scoped flow must update the existing row instead.

## Required quantity rules

Use BOQ source identities and saved portion relationships. Do not group unrelated rows by item code.

Let `Q` be the original combined quantity of the affected BOQ source and its portions.

Let `P` be the resulting provisional quantity allocated through the affected Contract rows.

Preserve other Contract allocations when calculating the affected distribution.

| Story case | Required BOQ result |
| --- | --- |
| Full quantity: `P = Q` | Keep one BOQ row of `Q`, marked Provisional Sum. Create no extra row. |
| Partial quantity: `0 < P < Q` | Maintain a provisional portion of `P` and a normal portion of `Q - P`. |
| Existing Contract rows have different statuses | Maintain matching BOQ portions and link each existing Contract row to its matching portion. |
| Provisional quantity becomes zero | Return the affected quantity to the normal distribution, preserving existing allocations and references. |

A later quantity change must recalculate the distribution even when the Provisional Sum flags already match.

Example: original BOQ quantity 700, provisional Contract quantity changed through the VO from 700 to 500.

Expected result: the existing Contract row has quantity 500. The BOQ has provisional quantity 500 and normal quantity 200.

The Contract retains one row. The combined BOQ quantity remains 700.

Required invariants:

- Preserve the combined BOQ quantity at the configured precision.
- Count each allocation once.
- Preserve quantities assigned to other Contract rows.
- Preserve the existing Contract row identity and Invoice references.
- Reuse existing BOQ portions where their identities and references permit adjustment.
- Do not create duplicate portions on repeated saves.
- Keep Provisional Sum quantities excluded from Contract `total_qty` under the current calculation rule.

## Processing sequence

### Phase 1: Validate and capture the previous state

**Dependency:** None.

**Work:**

Read the persisted VO, linked Contract row, BOQ portions, and existing allocation snapshots.

Identify quantity and Provisional Sum changes against the persisted state.

Reuse the existing invoice restriction before converting normal quantity to Provisional Sum.

Keep the existing restrictions on submitted quantity edits and later document dependencies.

Capture the affected quantities, statuses, references, and portion identities before mutation.

**Completion criteria:** Relevant changes and restrictions are identified. The previous state is available for allocation and reversal.

**Implementation result:** Submission captures prior Contract rows, the Contract allocation snapshot, and affected BOQ documents in transient flags.

Submission rechecks invoice conversion restrictions, active Contract row links, invoiced quantity limits, and rate restrictions.

Submitted VO quantity and rate edits are currently blocked before the update handler. This restriction remains unchanged.

### Phase 2: Update the existing Contract row

**Dependency:** Phase 1.

**Work:**

Resolve the existing linked Contract row from the VO and its active item log.

Apply the VO Provisional Sum status on the permitted draft-to-submit path.

Apply the quantity difference through the existing actual and variation quantity calculations.

Preserve the Contract row identity. Do not enter Contract row creation or splitting paths for this scoped operation.

Recalculate affected Contract item amounts and remaining quantities through the existing methods.

Persist the Contract row before calculating BOQ allocations, because those calculations read persisted Contract references.

**Completion criteria:** The existing Contract row reflects the VO changes. Contract row identities and count remain unchanged.

**Implementation result:** Current-BOQ submission uses the existing quantity-update path even when rate or allocation fields change.

The existing row receives quantity, rate, status, and amount updates. It bypasses the Contract row-copy path and preserves paid and progress values.

### Phase 3: Reconcile BOQ portions

**Dependency:** Phase 2.

**Work:**

Resolve the original BOQ source and all portions recorded for the affected allocation.

Calculate the target distribution from the updated Contract rows and the preserved allocations of other Contracts.

Apply the full, partial, or existing-multiple-row case.

When quantity decreases, return the released provisional quantity to the normal portion.

When quantity increases, take the additional quantity from the available normal portion.

When the entire quantity becomes provisional, avoid creating a new portion solely for the conversion.

Reuse or resize existing portions before creating another row.

Preserve source attributes, configured precision, resource rates, and existing BOQ amount calculations.

For resource-mode BOQs, reuse the existing resource-to-BOQ quantity conversion and ratio calculations.

Preserve the combined source quantity and resource quantities during redistribution.

Do not delete a portion with active references. Apply the existing dependency restrictions when a requested redistribution conflicts with those references.

**Completion criteria:** BOQ portions match the resulting Contract quantities and statuses. Combined quantities and other Contract allocations remain preserved.

**Implementation result:** `services/provisional_sum_reconciliation.py` provides `BOQPortionReconciliation` for standard and resource BOQs.

The service accepts updated persisted Contract rows, previous Contract rows, and the relevant prior allocation group.

It returns captured allocation state and proposed Contract references. Phase 4 persists references and logs and refreshes totals.

New portion snapshots include their source identity. Existing resource splits without that relationship require separate lineage resolution before reconciliation.

The service rejects those legacy resource splits instead of grouping resources by item code.

**Simulated verification:** Full conversion, partial conversion, quantity decreases, quantity increases, repeated allocation, and other Contract allocations follow the planned arithmetic.

These results come from code review. They do not claim runtime acceptance.

### Phase 4: Update references, logs, and totals

**Dependency:** Phase 3.

**Work:**

Link the existing Contract row to its resulting BOQ Child and resource portion.

Update the VO item references to the same portion.

Refresh BOQ contracted quantities, remaining quantities, amounts, and totals through existing calculation methods.

Recalculate Contract totals after the Contract changes.

Update the active VO log with the effective Contract row and current VO values.

Keep all changes inside the existing document transaction.

**Completion criteria:** Contract and VO references identify the correct BOQ portions. Logs and totals reflect the same allocation.

**Implementation result:** `services/vo_boq_reconciliation.py` coordinates Current BOQ VO allocation after the existing Contract update.

It resolves related portions from the Contract snapshot and active VO snapshots. Existing Contract snapshots remain unchanged.

It groups rows by source lineage, applies redistribution, and persists Contract references before refreshing BOQ allocations and totals.

It then updates VO references, effective Contract log snapshots, and Contract totals in the existing document transaction.

Availability validation counts related BOQ portions together. Quantity releases offset increases within the same source pool.

The permitted submitted-update handler uses the same coordinator. Existing validation still blocks submitted quantity and rate edits.

Service review corrected reference preservation for multiple same-status portions and reference output for zero-resource pools.

### Phase 5: Preserve reversal state

**Dependency:** Phases 1 through 4.

**Work:**

Keep the original pre-VO snapshot for cancellation. Do not replace it with the state from the latest edit.

Record the current portion identities and ownership needed to reverse later edits of the same VO.

Adjust snapshot handling so an existing snapshot prevents duplicate allocation but does not suppress a valid quantity change.

Cancellation must restore the pre-VO quantities, statuses, and references.

Preserve existing restrictions when later Contracts, VOs, or Invoices depend on affected portions.

**Completion criteria:** Cancellation restores the original state when dependencies permit. Repeated edits preserve both the original snapshot and current portion identities.

**Implementation result:** Snapshot merging preserves the first source values, original item references, and original application timestamp.

Newly created VO portions accumulate in the VO snapshot. Portions created before this VO remain source rows and are never deleted as VO-owned rows.

Existing cancellation restores Contract values first, then VO references, Contract references, and BOQ source values.

Created resources are deleted before created BOQ children. BOQ calculations refresh after restoration.

Source quantity validation prevents restoration below retained allocations. Resource-mode validation compares resource units instead of raw Contract quantities against BOQ Child units.

Existing invoice and later-document restrictions remain in place.

**Simulated acceptance review:**

| Scenario | Review result |
| --- | --- |
| Full conversion | Existing source identity is reused. |
| Partial conversion and quantity changes | Portions preserve their combined quantity and matching Contract references. |
| Existing same-status portions | Active row references and allocated quantities remain on their existing portions. |
| Resource distribution | Child and resource quantities use their respective units and existing conversion rules. |
| References, logs, and totals | Contract references persist before BOQ refresh. VO references and logs follow. |
| Repeated reconciliation | The original cancellation baseline remains unchanged. New VO-created portions accumulate once. |
| Cancellation ownership | Preexisting portions are restored. Only VO-created portions are deleted. |
| Other allocations | Restoration blocks when the original source quantity cannot hold retained allocations. |
| Submitted edits | Existing quantity, rate, and Provisional Sum restrictions remain unchanged. |

Mocked regression coverage was added or extended for these paths. No runtime tests, migrations, or deployment actions were executed.

These phases describe implementation responsibilities. They are not separate commits to the database.

Complete allocation and reversal together before releasing the change. Verify the phases with the scenarios in Planned verification.

## Lifecycle behavior

| Action | Required behavior |
| --- | --- |
| Edit or save a draft VO | Validate proposed changes. Do not change the submitted Contract or shared BOQ. |
| Submit the VO | Update the existing Contract row, then reconcile BOQ portions. |
| Change a permitted quantity on a submitted VO | Apply the quantity difference to the existing Contract row, then reconcile BOQ portions again. |
| Change Provisional Sum on a submitted VO | Keep the checkbox locked under the current UI rule. |
| Save without a relevant change | Keep quantities, references, and portion count unchanged. |
| Cancel the VO | Restore the pre-VO state, subject to existing dependency restrictions. |

Provisional Sum remains editable only for draft `Update Current Contracted BOQ` VOs.

This plan does not extend Provisional Sum editing to other VO types or submitted VOs.

## Planned file responsibilities

Paths are relative to `frappe-bench/apps/fabrica_construction/fabrica_construction/`.

| File | Planned change |
| --- | --- |
| `fabrica_construction/doctype/variation_order/variation_order.py` | Update the existing Contract row and invoke BOQ reconciliation after submission and permitted submitted quantity edits. |
| `services/variation_order_provisional_sum.py` | Coordinate VO allocation reconciliation, references, and original versus current snapshot state. |
| `services/vo_boq_reconciliation.py` | Group source portions, persist references and logs, refresh totals, and preserve the cancellation baseline. |
| `services/provisional_sum.py` | Reuse allocation calculations and add the missing quantity redistribution for existing portions. Preserve existing Contract submission behavior. |
| `services/provisional_sum_reversal.py` | Extend restoration only where updated portion state requires it. Preserve dependency checks. |
| `services/test_variation_order_provisional_sum.py` | Cover the VO-to-Contract-to-BOQ sequence and repeated edits. |
| `services/test_vo_boq_reconciliation.py` | Cover reference ordering, availability across portions, source lineage, and snapshot ownership. |
| `services/test_provisional_sum.py` | Cover full, partial, and existing mixed allocations, including resource mode. |
| `services/test_provisional_sum_reversal.py` | Cover cancellation after repeated quantity changes. |
| Existing VO controller tests | Cover unchanged Contract row count, invoice restrictions, and submitted quantity updates. |

Use existing JSON snapshot storage where sufficient. Do not add schema fields unless implementation research proves they are required.

Keep lifecycle coordination in the controller and allocation logic in the existing services.

New or updated implementation modules must describe their purpose. Explain only non-obvious allocation and reversal logic.

## Implementation steps

1. Trace the scoped VO submission and submitted-edit paths, including existing Contract split decisions and snapshot ownership.
2. Confirm the source-to-portion relationship needed to reconcile quantities after an earlier conversion.
3. Update the scoped Contract path to preserve the existing row identity and count.
4. Add BOQ reconciliation for both status conversions and quantity-only changes.
5. Integrate reconciliation after Contract updates on submission and permitted submitted quantity edits.
6. Update references and snapshots without overwriting the original cancellation state.
7. Extend reversal handling and focused regression coverage.
8. Review the diff for app-local scope and unrelated changes.

## Planned verification

The following scenarios are planned. They are not executed test results.

Use simulated verification by default. Run real or local tests only when explicitly requested.

| Scenario | Expected result |
| --- | --- |
| BOQ 100, resulting Contract 100 provisional | One BOQ row of 100 provisional. Contract row count stays unchanged. |
| BOQ 100, resulting Contract 40 provisional | BOQ 40 provisional and 60 normal. Existing Contract row becomes 40. |
| Existing Contract rows of 40 provisional and 60 normal | BOQ matches both portions. No Contract rows are added. |
| Provisional quantity decreases from 700 to 500 | BOQ 500 provisional and 200 normal. Existing Contract row becomes 500. |
| Provisional quantity increases from 40 to 70 | BOQ 70 provisional and 30 normal, when that quantity is available. |
| Provisional flag remains set while quantity changes | BOQ distribution still updates. |
| Provisional quantity becomes zero | Released quantity returns to the normal BOQ distribution. |
| Full conversion becomes partial, then full again | Combined BOQ quantity stays constant. No duplicate portions remain. |
| Save the same VO repeatedly | No allocation drift or extra portions. |
| Another Contract consumes part of the source | Its quantity and references remain valid. |
| Convert an invoiced Contract row to provisional | Existing invoice validation blocks conversion. |
| Cancel after repeated submitted quantity edits | Pre-VO quantities, statuses, and references return when dependencies permit. |
| Use decimal quantities | Portions sum to the original quantity at configured precision. |
| Use resource-mode BOQ | Child and resource distributions agree. Combined quantities remain preserved. |
| Process unrelated BOQ rows with the same item code | Those rows remain unchanged. |

For every applicable scenario, compare Contract row identities and count before and after processing.

## Excluded work

- Historical correction of existing Contracts, VOs, or BOQ portions.
- New Contract row splitting for the scoped VO operation.
- Changes to other VO types or core applications.
- New permission to edit Provisional Sum after VO submission.
- Migration, build, deployment, or runtime test execution.
