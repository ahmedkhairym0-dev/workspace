# Aljar System Overrides of Fabrica Construction

## Scope

This note compares the construction-related hooks in Aljar System with the corresponding code in Fabrica Construction. It covers controller overrides, whitelisted-method overrides, and related client scripts and document events. It does not cover Aljar customizations for other apps.

Aljar depends on Fabrica Construction and customizes selected DocTypes and workflows. It does not replace the construction app as a whole. The hook declarations are in [Aljar hooks.py](../frappe-bench/apps/aljar_system/aljar_system/hooks.py#L168) and [the whitelisted-method section](../frappe-bench/apps/aljar_system/aljar_system/hooks.py#L293).

## Controller Overrides

These hooks replace the registered controller class for each DocType. Most Aljar controllers extend the construction controller, call its standard behavior, and add Aljar-specific rules.

| DocType | Aljar controller | Difference from the construction controller |
|---|---|---|
| BOQ | [AljarBOQ](../frappe-bench/apps/aljar_system/aljar_system/override/boq.py#L16) | Handles legacy `custom_old_data` BOQs with validation bypasses for some link and mandatory checks. |
| BOQ Child | [AljarBOQChild](../frappe-bench/apps/aljar_system/aljar_system/override/boq_child.py#L7) | Allows a missing `scope` on child rows of submitted BOQs. |
| BOQ Variation Order | [AljarBOQVariationOrder](../frappe-bench/apps/aljar_system/aljar_system/override/boq_variation_order.py#L14) | Adds legacy BOQ hierarchy handling and rejects negative contracted quantities. |
| Construction Contract | [AljarConstructionContract](../frappe-bench/apps/aljar_system/aljar_system/override/construction_contract.py#L23) | Adds BOQ hierarchy and allocation checks, tax-resource validation, contract-lock handling, and date-based account mapping. It replaces `validate_boq_and_boq_child_exists` without calling the base validation. |
| Construction Invoice | [AljarConstructionInvoice](../frappe-bench/apps/aljar_system/aljar_system/override/construction_invoice.py#L15) | Adds hierarchy and tax checks, supports skipping duplicate-row validation with a custom flag, and filters advances linked to returned cheques. It calls base behavior for several lifecycle and validation methods. |
| Variation Order | [AljarVariationOrder](../frappe-bench/apps/aljar_system/aljar_system/override/variation_order.py#L39) | Adds tax and allocation validation. It also blocks changes to selected allocation and account fields after related contract items have been invoiced. |
| Resources Price List | [AljarResourcesPriceList](../frappe-bench/apps/aljar_system/aljar_system/override/resources_price_list.py#L7) | Requires `engineering_branch`. This validation replaces the base implementation and does not call `super()`. |

## Whitelisted-Method Overrides

These hooks replace individual callable methods. Three wrappers add a contract-lock check before calling the base method. One wrapper only delegates, and one method reimplements the calculation.

| Base method | Aljar implementation | Difference from the base method |
|---|---|---|
| `boq.create_construction_contract` | [Aljar wrapper](../frappe-bench/apps/aljar_system/aljar_system/override/boq.py#L109) | Calls the base function with the same arguments. It adds no behavior. |
| `construction_contract.make_invoice` | [Aljar wrapper](../frappe-bench/apps/aljar_system/aljar_system/override/construction_contract.py#L190) | Rejects the request when the contract is locked, then calls the base method. |
| `construction_contract.create_variation_order` | [Aljar wrapper](../frappe-bench/apps/aljar_system/aljar_system/override/construction_contract.py#L208) | Rejects the request when the contract is locked, then calls the base method. |
| `construction_contract.make_price_variance` | [Aljar wrapper](../frappe-bench/apps/aljar_system/aljar_system/override/construction_contract.py#L213) | Rejects the request when the contract is locked, then calls the base method. |
| `construction_contract.create_payment_request_from_construction_contract` | [Aljar implementation](../frappe-bench/apps/aljar_system/aljar_system/override/payment_request.py#L23) | Reimplements mapping and amount calculation. Its requested-total query includes all matching draft and submitted requests. The base query excludes requests marked `custom_is_construction_cash_advance`. This can change the calculated remaining advance. Aljar also gets the department through `get_department_by_company`. |

## Other Construction Customizations

Aljar adds client scripts for construction forms. These scripts add behaviors such as tax filters, contract-lock UI, BOQ mapping, and row-status updates. For example, see [Construction Contract JS](../frappe-bench/apps/aljar_system/aljar_system/public/js/construction_contract.js#L60), [Construction Invoice JS](../frappe-bench/apps/aljar_system/aljar_system/public/js/construction_invoice.js#L6), and [Variation Order JS](../frappe-bench/apps/aljar_system/aljar_system/public/js/variation_order.js#L2).

Aljar also registers an `on_submit` event for `ConstructionInvoice` in [hooks.py](../frappe-bench/apps/aljar_system/aljar_system/hooks.py). The construction metadata names the DocType `Construction Invoice` in [construction_invoice.json](../frappe-bench/apps/fabrica_construction/fabrica_construction/fabrica_construction/doctype/construction_invoice/construction_invoice.json#L1403). The different names may prevent the event handler from running. Verify the event key against the installed DocType name before relying on this hook. The handler sets `custom_payment_number` based on linked Payment Entries in [the Aljar event module](../frappe-bench/apps/aljar_system/aljar_system/doc_events/construction_invoice.py#L8).

## Main Differences

Aljar's main changes add legacy BOQ support, contract locking, Aljar-specific validation and account rules, and custom payment-request calculations. Most controller overrides preserve base behavior through inheritance. The payment-request method and Resources Price List validation replace base behavior instead. The construction-contract validation override also skips a base BOQ existence check, so its effect merits review when changing related validation.
