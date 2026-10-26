# US-2026-08-0293: Technical Requirements and Plan

## Purpose and scope

Synchronize BOQ quantities and Provisional Sum status with Construction Contract quantities, including changes through a Variation Order (VO).

Prevent a VO from converting invoiced quantity to Provisional Sum.

Source: `US-2026-08-0293.md`.

This document proposes implementation work. It does not authorize application changes or data migration.

## Baseline behavior before implementation

The reviewed code is in the `fabrica_construction` custom app.

- Provisional Sum uses the existing `rated_only` field. Keep this field name.
- `ConstructionContract.on_submit()` calls `back_update_boq()`.
- `back_update_boq()` updates contracted quantities and assigns the Contract row's flag to the entire linked BOQ Child.
- `VariationOrder._sync_provisional_sum_to_boq()` updates the entire linked BOQ Child and resource flag, then recalculates BOQ totals.
- That VO method does not split quantities. Mixed Contract rows can therefore overwrite the same BOQ row's flag.
- `validate_provisional_sum_changes()` already blocks normal-to-Provisional-Sum conversion when the linked Contract row has nonzero `invoiced_quantity`.
- This validation applies to `Update Current Contracted BOQ`. Its message differs from the requested message.
- VO logs already capture previous BOQ flags for cancellation. A quantity split requires more restoration data than flags alone.
- Existing VO tests cover invoice restrictions and restoration of previous flags. Extend these tests rather than duplicate them.

The main gap is quantity-aware BOQ synchronization. Invoice validation already exists and needs alignment with the agreed scope and message.

## Functional requirements

### Quantity distribution

Use the linked BOQ row identity, not only `item_code`, to identify the source quantity.

Let `Q` represent the original BOQ row quantity. Let `P` represent the quantity converted to Provisional Sum.

| Condition | Required BOQ result |
| --- | --- |
| `P = Q` | Keep one row with quantity `Q` and `rated_only = 1`. |
| `0 < P < Q` | Create a Provisional Sum portion `P` and a normal portion `Q - P`. |
| Contract has normal and Provisional Sum portions | Link each Contract portion to the matching BOQ portion. |
| No Provisional Sum conversion | Preserve the existing quantity distribution. |

For the story examples, BOQ quantity 100 produces either one Provisional Sum row of 100 or rows of 40 and 60.

The 60-unit normal portion must remain even when the Contract takes only 40 units.

For a Contract split of 40 Provisional Sum units and 60 normal units, both BOQ portions must match their Contract portions.

Required invariants:

1. Preserve total BOQ quantity across the split.
2. Assign Provisional Sum status only to the affected quantity.
3. Preserve item, UOM, and applicable source attributes when creating a portion. Resource-mode BOQ portion rates follow their resource amounts.
4. Distribute `contracted_qty` and `remaining_quantity` according to the actual allocation of each portion.
5. Recalculate existing quantity and amount totals through the app's existing calculation methods.
6. Use existing quantity precision when comparing and distributing quantities.
7. Repeated processing must not create duplicate portions or count contracted quantity twice.
8. Process related Contract rows together so row order does not determine the final BOQ status.

### References and resources

Keep each Contract row's `boq_child` linked to the BOQ portion that represents its quantity and status.

Preserve existing Invoice references to their original Contract rows. Do not transfer invoiced quantity to a new Provisional Sum row.

Review other references before reducing or splitting a BOQ row already used by another Contract or VO.

Resource-mode BOQs are included. Split resource quantities and link each resource portion to its matching BOQ Child.

Preserve existing allocations and references on the original portions. Use only available quantity for a new conversion.

### Invoice validation

Reuse `validate_provisional_sum_changes()` as the server validation entry point.

Block a normal-to-Provisional-Sum conversion when the affected linked Contract row contains invoiced quantity.

Show this message, with the affected row number as context:

> Cannot mark this item as Provisional Sum because part of its quantity has already been invoiced.

Revalidate against persisted Contract invoice quantities before submission. A draft VO may become invalid after another user submits an Invoice.

Preserve the existing ability to remove Provisional Sum status. The story restricts conversion to Provisional Sum.

Keep the existing row-level invoice restriction. A linked Contract row with invoiced quantity cannot convert to Provisional Sum.

Do not introduce separate conversion of an invoiced row's remainder in this change.

### Lifecycle and reversal

Keep BOQ writes on the existing Contract and VO lifecycle paths. Do not mutate a shared BOQ merely by editing a draft.

Draft saves must validate proposed changes. Submission must persist the matching quantity distribution and refresh calculations.

Record the source quantities, flags, affected references, and created portion identities needed to reverse a split.

Cancellation must restore the prior distribution without deleting referenced quantities or overwriting later valid transactions.

Retain existing cancellation restrictions for later Invoices and VOs.

Review permitted updates after submission. Any permitted quantity or status change must maintain the same distribution rules.

Apply related BOQ, Contract, and log changes within the same document transaction.

## Proposed implementation structure

Use one focused quantity-distribution module shared by Contract and VO processing.

Keep lifecycle orchestration in the existing controllers. Keep invoice validation in the VO controller.

Do not change Frappe or ERPNext core. Do not change other custom apps.

Paths below are relative to `frappe-bench/apps/fabrica_construction/fabrica_construction/`.

| File | Planned responsibility |
| --- | --- |
| `services/provisional_sum.py` | Calculate Contract portions, synchronize BOQ references, and refresh totals. |
| `services/provisional_sum_reversal.py` | Validate later consumers and restore Contract allocations on cancellation. |
| `services/variation_order_provisional_sum.py` | Synchronize effective VO Contract rows and store reversal snapshots in existing logs. |
| `services/boq_allocation.py` | Read submitted quantities without blocked history from canceled VOs. |
| `fabrica_construction/doctype/construction_contract/construction_contract.py` | Integrate quantity-aware synchronization with `back_update_boq()` and its reversal path. |
| `fabrica_construction/doctype/construction_contract/construction_contract.json` | Store the hidden, non-copying `provisional_sum_boq_state` snapshot. |
| `fabrica_construction/doctype/variation_order/variation_order.py` | Integrate synchronization, align validation text, and restore split state on cancellation. |
| `fabrica_construction/doctype/variation_order_items_logs/variation_order_items_logs.py` | Review existing JSON snapshots for split-state storage. Change only if required. |
| `fabrica_construction/doctype/boq/boq.py` | Reuse quantity and total calculations. Change only if the split exposes a missing calculation path. |
| BOQ Child and BOQ Items Resources controllers | Reuse the shared allocation query during later recalculation. |
| `services/test_provisional_sum.py` | Cover standard and resource quantity distribution with mocked persistence. |
| `services/test_provisional_sum_reversal.py` | Cover restoration and later-consumer restrictions with mocked persistence. |
| Existing VO test module | Cover invoice validation and the exact error message. |
| `services/test_variation_order_provisional_sum.py` | Cover grouped VO synchronization, log snapshots, and reversal ordering. |
| `services/test_boq_allocation.py` and existing BOQ counter tests | Cover shared quantity queries and their controller callers. |

Prefer existing JSON log storage. Add schema fields only if existing logs cannot represent the required reversal state.

Include a purpose docstring in new or updated implementation modules. Document only non-obvious allocation and reversal rules.

## Implementation phases

Phases 1 through 4 are implemented. Phase 5 is complete as a simulated acceptance review with static checks.

No runtime tests, migrations, or deployment actions were executed.

Runtime acceptance testing remains unexecuted. The results below do not claim a site-level test pass.

Each implementation phase includes its own focused validation. Phase 5 verifies the complete flow.

### Phase 1: Confirm scope and allocation design

**Dependency:** None.

**Work:**

1. Resolve the decisions listed at the end of this plan.
2. Trace Contract cancellation, permitted submitted updates, BOQ references, and existing split logs.
3. Confirm how existing calculations treat `rated_only` quantities and amounts.
4. Define which portion retains the original BOQ row identity and how new portions receive their references.
5. Define allocation rules for source rows shared by several Contracts.
6. Define the minimum snapshot data required for Contract and VO reversal.
7. Confirm whether existing log storage is sufficient and identify any required schema changes.

**Deliverable:** Update this document with the agreed rules, exact affected files, and snapshot structure.

**Completion criteria:** Allocation, invoice eligibility, resource scope, and reversal rules are explicit. No application code changes occur in this phase.

#### Research findings and confirmed decisions

- Target app: `fabrica_construction`. No changes are required in core or other custom apps.
- Standard BOQ row quantities use existing field precision. Contract item quantity precision is three decimal places.
- `BOQChild.validate()` recalculates contracted quantity from persisted submitted Contract item references.
- Persist matching Contract references before recalculating existing BOQ portions. New BOQ portions need recalculation after insertion.
- BOQ amount remains `qty * rate`, including Provisional Sum rows. Preserve this existing calculation.
- Reuse `_update_boq_total_qty_fields_in_db()` for BOQ quantity totals.
- Contract quantity and `rated_only` fields do not permit normal edits after submission. Do not add a new submitted-edit feature.
- Existing Contract cancellation adjusts quantities but does not restore the previous Provisional Sum flag.
- `Construction Contract Items Logs` contains accounting fields. It cannot store the required allocation snapshot.
- Snapshot storage: the hidden, read-only, non-copying JSON field `provisional_sum_boq_state` on Construction Contract.
- The snapshot must record source BOQ identity, original quantity and flag, created portion identity, and each changed Contract item reference.
- Keep the original BOQ row for the remainder with its original status. Create a row for the converted portion when required.
- For full conversion without a remainder, retain the original BOQ row and record its previous flag.
- Preserve existing allocations to other Contracts. Allocate the new Provisional Sum portion from available quantity only.
- Include resource-mode BOQs and use the existing aggregate resource-to-BOQ quantity conversion.
- Later Contract references to BOQ portions do not automatically block cancellation through standard Link checks.
- Block cancellation until later Contracts or VOs that consume a created portion are reversed.
- Also block restoration when a later Contract split changes a source quantity that the snapshot must restore.
- Keep persisted `invoiced_quantity` as the eligibility source. Preserve the existing restriction for partly invoiced Contract rows.
- No historical correction, migration execution, or deployment is included.

**Completion result:** The user confirmed resource support, preservation of existing allocations, and blocking cancellation for later consumers.

#### Resource allocation rules

For each source BOQ Child, group the Contract rows by resource identity and target status.

Calculate the converted BOQ quantity as:

`Converted BOQ Qty = Original BOQ Qty * Converted Resource Qty / Original Total Resource Qty`

Round the converted BOQ quantity to the existing field precision. Assign the residual quantity to the original BOQ portion.

Keep unchanged resource allocations on their original identities. Split a resource only when it has a nonzero remainder.

When an entire resource moves, retain its identity and update its `boq_child_ref`.

Derive each resource ratio from its portion quantity, BOQ portion quantity, and existing scrap percentage.

Derive each BOQ portion rate with `get_rate_for_boq_item()`. Preserve resource rates and total resource amounts.

#### Snapshot structure

The JSON contains `applied_on` and `groups`. The timestamp distinguishes earlier allocations from later dependent splits.

The `groups` list contains one entry per original BOQ Child used by the Contract.

| Key | Stored values |
| --- | --- |
| `boq` | Parent BOQ identity. |
| `sources` | Original child and resource identities, with changed quantity, rate, flag, ratio, and resource-parent values. |
| `created` | DocType and identity of each created portion. |
| `items` | Contract item identity and its original `boq_child` and `boq_items_resources` references. |

Normal groups without a conversion retain empty `sources` and `created` lists. Their BOQ allocations still refresh during cancellation.

### Phase 2: Align VO invoice validation

**Dependency:** Phase 1 invoice eligibility decisions.

**Files:** VO controller and existing VO test module.

**Work:**

1. Reuse the existing `validate_provisional_sum_changes()` method.
2. Use the story message with row number context.
3. Confirm that draft validation and submission check current persisted invoice quantities.
4. Change validation coverage only where the agreed scope exposes a missing path.
5. Preserve the existing behavior for removing Provisional Sum status.

**Validation:** Cover invoiced conversion, zero-invoice conversion, status removal, and an Invoice submitted after draft VO creation.

**Completion criteria:** Disallowed conversions fail with the story message and row context. Allowed changes retain existing behavior.

**Implementation result:** Updated the message and added regression coverage for invoice quantity changing after draft validation.

Submission already reruns validation and reads persisted invoice quantity. No additional submit hook was required.

**Simulated validation:** Invoiced conversion blocks, zero-invoice conversion succeeds, status removal remains allowed, and a later invoice blocks subsequent validation.

No runtime tests were executed.

This phase does not change BOQ quantity distribution.

### Phase 3: Synchronize Contract quantities with BOQ portions

**Dependency:** Phase 1 allocation and reversal design.

**Files:** Proposed shared service, Contract controller, Contract tests, and approved snapshot storage if required.

**Work:**

1. Add the focused quantity-distribution service.
2. Integrate full-quantity flag updates and partial-quantity splits into Contract submission.
3. Process related Contract rows together and link each row to its matching BOQ portion.
4. Preserve source attributes and distribute contracted and remaining quantities.
5. Reuse existing BOQ calculation methods.
6. Store the state needed for cancellation and implement Contract reversal in this phase.
7. Integrate permitted submitted updates only where the existing lifecycle supports them.
8. Include resource allocation only if Phase 1 confirms it belongs to this story.

**Validation:** Cover full quantity, partial quantity, mixed Contract rows, reversed row order, decimal quantities, repeated processing, and cancellation.

**Completion criteria:** The three story quantity examples work through the Contract lifecycle. Quantities, references, and totals remain consistent.

Contract synchronization and its reversal must be delivered together.

**Implementation result:** Added the allocation and reversal services, integrated Contract submission and cancellation, and added the snapshot field.

Existing Contracts without snapshots retain their existing cancellation path. No historical data correction was added.

**Simulated validation:** Full and partial splits, mixed row order, existing allocations, decimals, resource conversion, and cancellation match the agreed rules.

Mocked regression tests were added for these paths. They were not executed.

**Static checks:** Python syntax, Contract JSON structure, and tracked diff whitespace checks passed.

The Ruff formatting check could not run because Ruff is unavailable.

**Deployment prerequisite:** Apply the custom app schema migration before using the new snapshot field. No migration was executed.

### Phase 4: Synchronize VO changes with BOQ portions

**Dependency:** Phases 2 and 3.

**Files:** Shared service, VO controller, VO logs if required, and VO tests.

**Work:**

1. Replace whole-row flag synchronization with the shared quantity-distribution service on the agreed VO paths.
2. Keep existing Contract split behavior and update references to the matching BOQ portions.
3. Extend existing log snapshots with the approved quantity and reference state.
4. Restore quantities, flags, and references when canceling a VO.
5. Preserve existing restrictions for later Invoices and VOs.
6. Integrate permitted submitted VO updates with the same allocation rules.
7. Keep related changes within the existing document transaction.

**Validation:** Cover full and partial conversion, mixed rows, repeated processing, invoice restrictions, cancellation, and permitted submitted updates.

**Completion criteria:** VO changes produce the correct BOQ distribution and reverse correctly without transferring invoiced quantities.

VO synchronization and its reversal must be delivered together.

**Implementation result:** Synchronization runs once after the VO persists its Contract quantity and rate changes.

It resolves the effective Contract row from each log, groups rows by BOQ source, and reuses `ContractBOQAllocation`.

The first log stores `provisional_sum_boq_state` inside `variation_order_item_json`. No new VO field or DocType was added.

The snapshot contains `applied_on`, allocation `groups`, and original `vo_items` references.

Updated Contract snapshots point to the resulting portions. Original Contract snapshots remain available for cancellation.

VO-created Contract copies retain the original submitted status. This keeps them included in submitted allocation queries.

Cancellation validates consumers before reversing Contract changes. It restores BOQ portions in `on_cancel`, after the VO becomes canceled.

This order lets quantity queries exclude blocked rows retained as canceled VO history.

The shared query preserves live invoiced rows and temporary blocked rows. It excludes only blocked rows linked to canceled VOs.

Reversal ignores canceled consumers and snapshots owned by canceled VOs. Later active Contract or VO dependencies still block restoration.

Remaining active VO logs become canceled after restoration. Legacy logs without quantity snapshots retain the prior flag-restoration path.

Invoice validation covers linked rows in both `Update Current Contracted BOQ` and `Update New Scope`.

Existing submitted-edit restrictions remain in place. Quantity, rate, and Provisional Sum changes remain prohibited after submission.

Permitted accounting changes retain the snapshot and leave quantity distribution unchanged.

### Phase 5: Verify the complete story

**Dependency:** Phases 2 through 4.

**Work:**

1. Review every scenario in the acceptance and validation table below.
2. Verify the sequence from BOQ through Contract, Invoice, VO, and permitted cancellation.
3. Check quantity and amount calculations after each supported lifecycle action.
4. Check unrelated BOQ rows with the same item code.
5. Check approved resource-mode scenarios, if included.
6. Review the final diff for app-local scope and unrelated changes.

**Deliverable:** An acceptance report that maps each story criterion to its result and identifies unresolved issues.

**Completion criteria:** All acceptance criteria pass under the agreed scope, with no unresolved quantity or reference defects.

Use simulated validation by default and label its results as simulated. Run real or local tests only when explicitly requested.

Historical correction and deployment remain separate work. This plan does not authorize either action.

**Result:** Simulated acceptance review completed. Regression tests were added or updated but were not executed.

**Static checks:** Python syntax parsing and staged and unstaged whitespace checks passed.

**Precision correction:** Reject resource splits whose converted or remaining BOQ portion cannot be represented at the configured quantity precision.

This prevents rounding a partial resource conversion into a full BOQ conversion.

### Phase 5 acceptance report — simulated

The following results come from code tracing and numerical examples. They are not runtime test results.

| Story criterion | Simulated result and evidence |
| --- | --- |
| 1. Full quantity | Expected pass. BOQ 100 converted fully retains one Provisional Sum row of 100. |
| 2. Partial quantity | Expected pass. Conversion of 40 creates Provisional Sum 40 and normal 60. |
| 3. Sum of portions | Expected pass. Standard quantities use rounded conversion and a residual remainder. |
| 4. Contract split | Expected pass. Grouped Contract and VO rows map each quantity to its matching BOQ portion. |
| 5. Correct status | Expected pass. The converted portion receives the target status. Original allocations retain their portion. |
| 6. No duplication or loss | Expected pass. Snapshots stop repeated splitting. Unrepresentable resource portions reject before mutation. |
| 7. Invoice restriction | Expected pass. Both supported VO types reject conversion of a linked invoiced row. |
| 8. Validation message | Expected pass. The story message includes the affected row number. |
| 9. Calculations across lifecycle actions | Expected pass. Submission and cancellation refresh persisted allocations. Permitted accounting edits do not change portions. |

Additional simulated scenarios:

- Reversing mixed row order produces the same distribution.
- Decimal quantity 1 split by 0.333 produces portions 0.667 and 0.333.
- Resource BOQ quantity 100 with resources A100 at rate 2 and B100 at rate 3 totals 500.
- Converting A40 produces BOQ portions 80 and 20, with resource quantities 60, 100, and 40. The total amount remains 500.
- Full conversion of one resource preserves its identity when it moves to the matching BOQ portion.
- VO cancellation restores references before deleting created resources and BOQ children.
- A later active split blocks earlier reversal. Earlier snapshots and canceled history do not block later reversal.
- A normal Contract allocation that predates the split remains on its original source.
- Source identity separates unrelated BOQ rows with the same item code.
- A draft VO validates without changing the BOQ. An Invoice recorded before submission blocks a disallowed conversion.

No unresolved quantity or reference defect remains from the simulated review. Runtime behavior still requires execution on an approved test site.

## Acceptance and validation plan

The following are planned scenarios. No runtime tests were executed for this document.

| Scenario | Expected result |
| --- | --- |
| BOQ 100, Contract 100 Provisional Sum | One BOQ row of 100, flagged Provisional Sum. |
| BOQ 100, Contract 40 Provisional Sum | BOQ portions of 40 Provisional Sum and 60 normal. |
| Contract split into 40 Provisional Sum and 60 normal | BOQ portions and Contract links match that distribution. |
| Reverse the input order of mixed Contract rows | The same distribution results. |
| Save or process the same distribution again | No extra portions or quantity changes. |
| Convert an invoiced Contract row through either supported VO type | The change fails with the story message and row context. |
| Convert a Contract row with zero invoiced quantity | The conversion succeeds. |
| Invoice arrives after draft VO creation | Submission checks current invoice quantity and blocks the conversion. |
| Remove Provisional Sum status from an invoiced row | Existing permitted behavior remains available. |
| Cancel a split-producing Contract or VO | Previous quantities, flags, and links return, subject to existing cancellation restrictions. |
| Use decimal quantities | Portion quantities sum to the original quantity at configured precision. |
| Save, submit, or make permitted submitted updates | Quantity and amount calculations remain consistent. |

Also verify that unrelated BOQ rows with the same item code remain unchanged.

Resource-mode scenarios are included in the Phase 3 mocked regression tests.

## Work requiring a separate request

1. Run runtime tests on an approved test site.
2. Apply the Phase 3 schema migration before deployment.
3. Change invoice eligibility or add conversion of a partly invoiced row's remainder.
4. Correct historical data. This implementation includes no historical data migration.
