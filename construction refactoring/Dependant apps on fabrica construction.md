# Dependant apps on fabrica construction App

Across the workspace, **four apps explicitly declare `fabrica_construction` as a required app**:

| App | Dependency |
|---|---|
| **aljar_system** | Construction overrides, APIs, forms, and linked construction/property DocTypes |
| **alqamzi_system** | Construction overrides, billing/payment logic, and Unit/Building links |
| **crm_integration** | Unit and Payment Entry overrides, property links, and construction invoice cost integration |
| **handover** | Property handover workflows linked to Construction’s Unit DocType |

I also found **three apps with code or metadata dependencies that are not declared in `required_apps`**:

| App | Coupling to Construction |
|---|---|
| **child_table_pagination** | Imports `ErrorsWarningsPublisher` and calls Construction’s spreadsheet utilities in specific execution paths |
| **fabrica_accounting** | Links to Unit, hooks Construction Invoice cancellation, and optionally integrates construction workspace links and spreadsheet utilities |
| **erp_fabrica** | Its Category Cost Mapping DocType links to Construction’s Category Cost |

One important detail: **Construction itself requires `fabrica_accounting` and `erp_fabrica`**, so those two also contain reverse references back to Construction.

This is a source-level inventory; staging/live installation was not checked.

---
---


## aljar_system App Dependancies on Fabrica Construction

Aljar has **7 construction class overrides, 5 API overrides, form scripts, and exported field customizations**.

| Area | Aljar behavior |
|---|---|
| **BOQ** | For `custom_old_data`, skips system-error checks, mandatory validation, link validation, and submitted-update restrictions. For submitted BOQs, exempts child `scope` from mandatory checks. |
| **BOQ Child** | Allows missing `scope` when its parent BOQ is submitted. |
| **BOQ Variation Order** | Adds legacy BOQ hierarchy handling. Allows Floor without Building under the legacy rules. Checks negative contracted quantities, with an exemption for “Update Current BOQ” against old BOQs. |
| **Construction Contract** | Adds contract locking; bypasses validation when locked. Disables the BOQ/BOQ Child existence check. Adds tax-resource validation and legacy hierarchy rules per item row. |
| **Construction Invoice** | Adds tax-resource validation and hierarchy checks per row. Allows duplicate-row validation to be non-blocking through a checkbox. Excludes advances marked as returned payable cheques. |
| **Variation Order** | Prevents changing accounts, cost center, and allocation fields on already-invoiced contract items for “Update Current Contracted BOQ.” Adds tax-resource validation and legacy allocation rules. |
| **Resources Price List** | Requires Engineering Branch on both server and form. |

The class registrations are in [hooks.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/aljar_system/aljar_system/hooks.py:169).

**Account mapping has a date split:** contracts and invoices dated before **June 1, 2026** use Aljar’s older rules, which can accept one valid mapped account when the other is absent. Contracts and variation orders also fill missing accounts and cost center from Work Type, then Scope. Newer documents delegate to Construction’s standard mapping behavior.

**Contract locking and payment creation**

- Locked contracts block creating invoices, variation orders, price variances, and payment requests. The form also disables interactions while retaining the unlock control.
- Contract payment requests calculate an amount from remaining advance or uninvoiced net value, assign a Projects/Engineering department, and synchronize Accounting’s payment details.
- Invoice payment requests use the invoice’s outstanding amount and synchronize payment details.
- The BOQ-to-contract API override currently just delegates to Construction without adding behavior.

See [construction_contract.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/aljar_system/aljar_system/override/construction_contract.py) and [payment_request.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/aljar_system/aljar_system/override/payment_request.py).

**Form and field customizations**

- Old BOQ rows receive the Floor-without-Building exemption across contracts, invoices, and variation orders.
- Tax item/resource selectors are restricted to relevant document items; server validation checks resource membership.
- Construction Item and Resources Item Price get an **Update BOQ** button to update selected BOQs and recalculate resources.
- Exported metadata adds department, finishing type, workflow state, contract lock, old-data and duplicate-validation fields.
- It changes naming series, required/read-only fields, labels, filters, and defaults—including **25% contract overbilling allowance** and cumulative contracts enabled.

These exports are under [custom](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/aljar_system/aljar_system/aljar_system/custom).

**Additional construction changes**

Aljar includes construction reports/workspaces and many migration patches for quantities, billing, outstanding amounts, BOQ references, resources, and historical data repair. Those are separate from recurring runtime overrides.

Two registration issues appeared during inspection:

- The invoice submit hook targets `ConstructionInvoice` instead of `Construction Invoice`, so its payment-count update would not run for the standard DocType.
- `public/js/boq_child.js` is registered but missing from this checkout.

This describes the checked-out source; live customizations and patch execution status were not verified.


---
---


## alqamzi_system App Dependancies on Fabrica Construction

Alqamzi has **4 construction class overrides, 2 Construction API overrides, form scripts, and exported field customizations**. Its main changes concern pagination, invoice accounting, taxes, and payments.

| Area | Alqamzi behavior |
|---|---|
| **BOQ** | Adds batched child-link validation. Overrides naming with project-based naming logic, although the current condition prevents that naming path for normal non-negative BOQ counts. |
| **Construction Contract** | Adds pagination for `items` and batched link validation. Its invoice-creation API wrapper currently delegates to Construction without adding business logic. |
| **Construction Invoice** | Adds pagination, batched link validation, tax checks, custom GL grouping/posting, advance-reconciliation adjustments, and spreadsheet quantity/progress updates. |
| **Variation Order** | Adds pagination for `items` and batched link validation. No additional business-rule methods are defined in this controller. |

Registrations: [hooks.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/alqamzi_system/alqamzi_system/hooks.py:202).

**Pagination and contract form**

- Replaces the contract items grid with a paginated table.
- Disables the client controller’s automatic tax/total calculation.
- Adds spreadsheet upload/download and table clearing.
- Blocks upload and clearing for submitted contracts; permits downloading.
- Upload warns about zero quantities and offers to remove zero-rate rows.
- Switches editable rate columns according to “Rate Include VAT.”

Server pagination and batched link validation each have a site configuration switch, enabled by default. See [construction_contract.js](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/alqamzi_system/alqamzi_system/public/js/construction_contract.js).

**Invoice accounting and taxes**

- Groups item and tax GL rows using account, cost center, project, Unit, Department, Time Deposit, and **Cost Type**.
- Keeps reverse items separate and posts their amounts as credits.
- Excludes withholding deductions from ordinary deduction-tax GL posting.
- Reduces available advances by amounts already reconciled or settled.
- Rejects tax rows that combine withholding with VAT inclusion, include deducted tax in item amounts, or use withholding with a charge type other than **On Net Total**.
- Spreadsheet updates match rows by `item_key`, update quantity/payment/progress percentages, recalculate totals, and report ignored field changes.

See [construction_invoice.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/alqamzi_system/alqamzi_system/override/construction_invoice.py) and [tax_validation.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/alqamzi_system/alqamzi_system/tax_validation.py).

**Construction payments**

- Contract payment requests calculate the remaining advance after paid advances and existing requests, and copy accounting dimensions.
- Invoice payment requests require a submitted, non-reversed invoice and calculate available cash after existing requests, with separate withholding handling.
- Payment Entry creation adds withholding, cheque bank-account selection, and rounding adjustments, with checks to avoid repeated withholding.
- Cancelling a Construction Invoice first cancels its supplier-advance reconciliations.

See [payment_request.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/alqamzi_system/alqamzi_system/override/payment_request.py:3840).

**Fields and defaults**

Exported customizations include:

- Accrued Loan, workflow state, allocation type, and invoice Feasibility Study/Department/Time Deposit/Unit fields.
- **25% contract overbilling allowance** and cumulative contracts enabled by default.
- Required contract Project/Posting Date and invoice-item Cost Center.
- Invoice-item progress defaults to **100%**.
- Construction naming series, item filters, visibility, labels, and tax flags.
- Unit reservation and floor-number fields.

One distinction: the older BOQ, Construction Invoice, and Variation Order form-script registrations are **commented out**. The active invoice script handles payment routing and tax flags; the full older invoice script is not registered through those hooks.

Alqamzi also ships construction-related migration patches. This describes the workspace source; live configuration and applied customizations were not checked.


## Differences among develop and develop-no-acc (alqamzi) branches

The branches differ in **accounting integration, billing calculations, advances, invoice status, and performance**. `develop-no-acc` still creates accounting entries; its name means it removes the direct dependency on `fabrica_accounting`.

I compared the latest **locally available remote-tracking snapshots**:

- `develop`: `2711a0c3`
- `develop-no-acc`: `585042b2`
- **179 files differ**, including tests, metadata, reports, and migrations. I did not fetch from the server. Your local `develop-no-acc` branch is older than this snapshot.

| Area | `develop` | `develop-no-acc` |
|---|---|---|
| **Required apps** | Requires `erp_fabrica` and `fabrica_accounting` | Requires only `erp_fabrica` |
| **Tax calculation base** | Extends Accounting’s `PurchaseInvoiceTaxesAndTotals` | Extends ERPNext’s standard tax calculator |
| **Payment Request controller** | Registers `FabricaConstructionPaymentRequest`, extending Accounting’s controller | Does not register that controller; retains permission filtering |
| **Purchase Invoice controller** | Registers a Construction-specific class override | Uses document-event hooks instead |
| **Contract outstanding** | Calculates `grand_total − total_paid_amount` | Calculates `grand_total − advance_paid` |
| **Contract remaining balances** | Clamps remaining quantity and amount to zero | Allows negative remaining quantity and amount |
| **Billing history** | Uses dedicated submitted-item billing history, including retroactive rate-change handling | Lacks that billing-history service and uses different calculations in affected paths |
| **Cost Plus** | Generates Purchase Invoices through contract/invoice submission hooks | Does not contain those Cost Plus hooks or service |
| **Stock Entry integration** | Registers construction validation, processing, and cancellation handlers | Does not register those handlers |
| **Contractor deductions** | Registers an Internal Memo contractor-deduction handler | Does not contain that handler |
| **Invoice status** | Has dedicated status handling and a daily overdue-status refresh | Lacks that service and scheduler entry |
| **Design payments** | Registers Design Contract/Invoice in advance-payment and invoice hooks | Registers only Construction Contract/Invoice |

The central integration differences are visible in [hooks.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/hooks.py).

**Advances and withholding differ substantially**

`develop` integrates Accounting’s advance handling and payment-request detail synchronization.

`develop-no-acc` instead:

- Adds `separate_advance_settlement` and a dedicated advance GL-entry method.
- Calculates advances on draft invoices through a different path.
- Excludes withholding tax from Construction Invoice tax-total contributions.
- Tracks cash-advance requests against individual Payment Entry or Journal Entry source rows, including grouped funding vouchers.
- Contains a cash-advance creation endpoint that directly calls **`alqamzi_system`**.

That last point matters: **removing the Accounting dependency does not make this branch independent of customer apps**. Its cash-advance creation path explicitly depends on Alqamzi.

**`develop-no-acc` also contains performance changes**

It adds an invoice query-context module, bulk lookups for linked documents and account validation, and cached invoice-history/payment properties. It also introduces `ignore_upload_validate` handling in BOQ, contract, variation-order, and shared controller paths.

**Reports and metadata differ too**

`develop-no-acc` adds reports such as Actual Project Cost vs Budget V2, Project Cost Custom, Payable Cheque, and Supplier Balances by Project Based on Mapping. Conversely, `develop` contains additional invoice-status fields, previous-invoice balance handling, Cost Plus configuration, and Design payment links.

These are **changes inside Construction itself**, separate from the Aljar and Alqamzi overrides discussed earlier. The table covers the main behavior differences found in the source; it is not a line-by-line inventory of all 179 files. No files were changed or runtime tests executed.


## crm_integration App Dependancies on Fabrica Construction

CRM Integration mainly changes **Units, property synchronization, Payment Entries, and construction cost allocation**.

| Area | CRM Integration behavior |
|---|---|
| **Unit controller** | Replaces Construction’s `Unit` class with `CRMUnit`. Creates a linked ERP Item after Unit insertion and includes linked-Item deletion handling. |
| **Unit synchronization** | Provides APIs to create/update Construction Units from CRM payloads, matching existing Units by `crm_id`. |
| **Reservations** | Updates Unit status during reservation flows—for example, marks a reserved Unit as Reserved and a transferred-from Unit as Re-pricing. |
| **Payment Entry** | Extends Construction’s `PaymentEntryConstruction` with CRM-specific party, account, reference, and payment validation behavior. |
| **Construction Invoice costs** | Registers a contribution provider that reconstructs invoice-item costs from posted GL rows for Unit Cost Capitalization. |
| **GL Entries** | Populates Zone from the linked Unit. CRM-created entries receive a CRM source marker and future-posting-date validation. |
| **Change tracking** | Records document changes made during CRM API calls and adds CRM updater references to Unit changes. |

**Unit and linked Item**

The [CRMUnit override](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/crm_integration/crm_integration/overrides/crm_unit.py) creates an Item with:

- Item code equal to the Unit document name.
- Item name/description from `unit_id`.
- UOM `Unit`, with stock and purchase flags disabled.
- Item Group from CRM Integration Settings.
- Company defaults copied from the matching Item Group defaults row.

It requires a Unit company and matching company defaults. Exported metadata adds the Unit’s **Item** link and makes `crm_id` read-only.

The [Unit APIs](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/crm_integration/crm_integration/api/v1/unit.py) synchronize project, type, status, serial, areas, room count, phase, and other Unit details. They also create missing Unit Types.

**Payment Entry changes**

The [Payment Entry override](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/crm_integration/crm_integration/overrides/payment_entry.py):

- Keeps CRM-selected accounts outside standard separate advance-liability handling.
- Validates primary/secondary parties and attaches them to receivable/payable GL rows.
- Clears Unit for EOI payments.
- Checks duplicate CRM payment codes on Receive entries.
- Replaces reference-document validation and supports partial reversal of grouped payments.

One significant detail: its `validate_allocated_amount_with_latest_data()` currently **does not call the parent implementation**, so that inherited validation is skipped.

**Construction Invoice cost allocation**

The [contribution provider](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/crm_integration/crm_integration/unit_cost_capitalization/services/construction_invoice.py) identifies which invoice items contributed to a GL line, including allocation hierarchy, reverse items, and included VAT. It rejects ambiguous matches or amounts that do not reconcile exactly. This supports capitalization; it does not override the Construction Invoice controller.

There are **no direct BOQ, Construction Contract, Construction Invoice, or Variation Order class overrides**, and no Construction API replacements registered in CRM Integration’s hooks.

This describes the workspace source; live behavior was not tested.


## handover App Dependancies on Fabrica Construction

Handover **depends on Construction’s property data but has no direct Construction class or API overrides**.

| Area | Handover behavior |
|---|---|
| **Unit details** | Reads Construction Units to populate project, company, hierarchy, type, status, areas, and reservation details in Handover documents. |
| **Release Unit** | Links to a Unit, finds its active reservation, and prevents multiple non-cancelled Release Unit records for the same Unit. |
| **Project validation** | Requires the selected Unit to belong to the selected Project when the configured customization adapter requires this. |
| **Area comparison** | Compares actual measured areas against the Unit’s gross, sellable, land, and garden areas. Stores differences on Release Unit. |
| **Quality checks** | Uses the Unit Type to select a matching Quality Goal and create a Quality Review. |
| **Handover Appointment** | Links appointments to Construction Units for the handover process. |

The main integration code is in [unit_service.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/handover/handover/services/unit_service.py) and [release_unit_service.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/handover/handover/services/release_unit_service.py).

Handover’s [hooks.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/handover/handover/hooks.py) registers Quality Review events and Handover workflow/permission behavior. It does **not** register:

- Construction controller, API, dashboard, or form-script overrides.
- Document-event handlers on Construction DocTypes.
- Exported custom fields or property setters for Construction DocTypes.

I found no direct writes to Construction Unit records in the inspected integration paths. Handover reads Unit data and maintains its own release, inspection, and appointment records.

This describes the workspace source; live customizations were not checked.


## child_table_pagination App Dependencies points


The relationship is **runtime coupling in both directions**, mainly connected through **Alqamzi’s overrides**. Neither app declares the other in `required_apps`.

| Dependency point | Direction | What uses it |
|---|---|---|
| **Paginated document controller** | Alqamzi → Pagination | Alqamzi’s Construction Contract, Construction Invoice, and Variation Order controllers inherit `PaginatedDocument` and paginate `items`. |
| **Paginated form UI** | Alqamzi → Pagination | The active contract script uses `PaginatedChildTable`, row-fetching, bulk-save, clearing, and progress utilities. |
| **Spreadsheet export** | Pagination → Construction | XLSX download calls Construction’s `sheet_utils.export_template_dialog()` or `download_sheet_from_json_array()`. |
| **Warning presentation** | Pagination → Construction | Row saves import Construction’s `ErrorsWarningsPublisher` when upload validation returns warnings. |
| **Invoice-specific saving** | Pagination → Construction behavior | `save_documents()` explicitly routes `Construction Invoice` to a separate bulk-save implementation. |
| **Validation and recalculation** | Pagination → document controllers | Save paths call methods supplied by Construction controllers, such as upload validation, tax calculation, allocation updates, and overbilling recalculation. |

**How pagination changes Construction documents**

[PaginatedDocument](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/child_table_pagination/child_table_pagination/model/paginated_document.py:57):

- Removes configured child tables from serialized document responses.
- Loads their rows separately for server processing.
- Provides a custom save path.
- Supports bulk child-row inserts, updates, and deletes.

Its save operations call controller methods including:

- `validate_uploaded_data()` and `warning_uploaded_data()`
- `system_updates()` and `calculate_taxes_and_totals()`
- `auto_fetch_project_for_children()` and `set_type_of_allocation()`
- `recalculate_over_billing_allowance_remaining()`

These calls make Pagination dependent on the consuming controller’s method behavior. Bulk saving also temporarily sets validation-bypass flags such as `ignore_upload_validate`, `ignore_links`, and `ignore_mandatory`.

**Where the integration is enabled**

Alqamzi’s [pagination bridge](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/alqamzi_system/alqamzi_system/compat/pagination.py) enables server pagination by default through `alqamzi_enable_pagination`.

Construction itself has **no active direct Pagination imports or calls** in the inspected `develop` checkout; the only reference found is commented out. The inspected `develop-no-acc` snapshot likewise has only that commented reference.

Therefore:

- **Construction alone:** no direct Pagination requirement found.
- **Alqamzi with pagination enabled:** requires Pagination’s controller and UI functionality.
- **Pagination’s XLSX export and warning paths:** require Construction utilities, despite the missing declared dependency.

Pagination does not register Construction class overrides or document-event hooks itself; Alqamzi supplies those overrides. This is based on workspace source, without runtime testing.



## fabrica_accounting App Dependencies points

The relationship is **a declared dependency from Construction to Accounting, plus reverse integration points from Accounting back to Construction**.

In the checked-out `develop` source:

- **Construction requires Accounting** in `required_apps`.
- **Accounting does not declare Construction**; its only declared requirement is `lending`.
- Some Accounting features still reference Construction DocTypes, so those execution paths depend on Construction being available.

**Construction → Accounting dependencies**

| Point | What Construction uses |
|---|---|
| **Controller inheritance** | Accounting’s Payment Entry, Payment Request, Purchase Order, and Purchase Invoice controllers |
| **Taxes and advances** | Accounting’s `PurchaseInvoiceTaxesAndTotals` calculator |
| **Payment requests** | Helpers to synchronize payment details, determine direct-payment status, set dimensions, and handle withholding |
| **Advance reconciliation** | Accounting’s settlement ledger, source lookup, and supplier-advance reconciliation services |
| **Cost Plus** | Accounting services that generate and manage related Purchase Invoices |
| **Contractor deductions** | Accounting’s Internal Memo handler infrastructure |
| **Purchase Receipt** | Accounting’s dashboard extension helper |
| **Accounting dimensions** | Cost Type setup and Project account fields used by Construction settings |

These are direct Python imports, so Accounting is a functional requirement for this Construction branch—not just an installation declaration.

**Accounting → Construction integration points**

| Point | Behavior |
|---|---|
| **Construction Invoice cancellation** | Cancels supplier-advance reconciliations before the invoice is cancelled |
| **Supplier approval** | Global validation requires approved suppliers on Construction Contracts and Invoices, including supplier links in child rows |
| **Tax validation** | Enforces compatible withholding/item-cost flags. The “On Net Total” withholding restriction additionally requires `imarrae_system` |
| **Payment Request details** | Reads Construction Contract/Invoice payable accounts and outstanding amounts to populate payment details |
| **Payments and withholding** | Recognizes Construction Invoices in Payment Entry, Payment Request, and Payable Cheque withholding flows |
| **Internal Memo** | Supports Construction Contracts/Invoices in cross-deductions, advance reconciliation, and shareholder-account reconciliation |
| **Transaction controls** | Includes Construction references in payment/reversal-related processing |
| **Reports** | Includes Construction Invoices in supplier-withholding and VAT-included invoice reports |
| **Unit references** | Uses Construction’s Unit in Internal Memo, wallet, cheque, commission, and cheque-reclassification features |
| **Workspace and export** | Adds Construction workspace links when installed; optionally uses Construction’s spreadsheet download helper |

Relevant registrations are in [Accounting hooks.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_accounting/fabrica_accounting/hooks.py:304). The inherited controllers are registered in [Construction hooks.py](/home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/hooks.py:142).

**This is not a symmetric installation dependency.** Construction `develop` directly requires Accounting. Accounting integrates with Construction through document names, metadata, hooks, and selected feature paths; some integrations explicitly check whether Construction is installed, while others assume its DocTypes exist.

This describes workspace source. The previously inspected `develop-no-acc` branch removes much of Construction’s direct Accounting dependency. No runtime tests were executed.