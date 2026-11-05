# Fabrica Construction Architecture Analysis

## Scope

This report reviews the checked-out `fabrica_construction` app and the documented links to dependent apps. It uses the code and the app's refactoring review as evidence. It does not inspect a live site or measure production performance.

## Current Architecture

The app follows the standard Frappe structure. DocType controllers own document lifecycle behavior. `hooks.py` connects controllers, document events, overrides, scheduled tasks, and browser assets. Focused business modules live in `services/`, with shared logic in `controllers/`, `utils/`, and `doc_events/`.

This is a modular app, not a single monolithic module. Some services already provide useful depth: callers can use focused billing and reconciliation behavior without repeating all of its implementation. The app also has a substantial test suite. These are good foundations to keep.

The main interface for Construction documents is still their Frappe lifecycle methods. However, downstream apps also subclass Construction classes and import helpers. Those apps therefore rely on implementation details as well as the intended document behavior.

## Downsides and Proportionate Solutions

### Large DocType Controllers

The app's [refactoring review](../frappe-bench/apps/fabrica_construction/doc/README_REFACTORING.md) reports very large controllers for Construction Invoice, Construction Contract, Variation Order, and BOQ. These files combine lifecycle behavior with validation, calculations, posting, and updates to related documents.

This reduces locality. A change to one rule can require a developer to understand and test a large implementation. Splitting files only to reduce line counts would not solve that problem.

**Suggested solution:** keep lifecycle methods as the stable interface. When changing a business capability, move that cohesive operation into an existing focused service or a nearby module. Keep small wrappers for existing callers. Do not create a new layer unless it hides real complexity.

### Downstream Apps Depend on Implementation Details

Aljar and Alqamzi override or subclass Construction classes and import Construction helpers. The dependency inventory is in [Dependant apps on fabrica construction.md](Dependant%20apps%20on%20fabrica%20construction.md). This gives those apps leverage, but it makes internal changes harder to contain. A change to a helper or controller method can require coordinated edits and tests across apps.

**Suggested solution:** search downstream callers before moving or renaming methods. Record the methods they rely on and treat those as supported extension points. Keep compatibility wrappers when extracting code. Add a general extension framework only if multiple real adapters need it.

### Global Hooks and Runtime Patching Hide Effects

The wildcard `on_change` hook in [hooks.py](../frappe-bench/apps/fabrica_construction/fabrica_construction/hooks.py) calls custom versioning for every DocType. The handler in [data.py](../frappe-bench/apps/fabrica_construction/fabrica_construction/utils/data.py) filters for Construction documents after it runs and silently catches all exceptions. The package initializer also runs monkey-patch setup during import. The validation utility temporarily replaces the process-wide `frappe.throw` function.

These choices widen the effects of local changes and make failures harder to diagnose. The need for custom versioning and validation bypasses may still be valid for specific workflows.

**Suggested solution:** confirm which DocTypes need custom versioning and which workflows need each bypass. Narrow hooks to those cases, and make failures visible. Replace process-wide behavior in small steps with explicit checks or supported Frappe hooks. Keep required legacy behavior and test it before removing a bypass.

### Some Validation May Do Work Per Row

The app's refactoring review identifies invoice validation paths with linked-record lookups inside item loops. If those paths run for large invoices, query work may grow with the number of rows. Static code alone does not establish the production cost.

**Suggested solution:** measure query counts and timings on representative documents. If repeated reads are confirmed, fetch unique references once per operation and reuse them during validation. Do not redesign child tables or add pagination based only on row count.

### App Integrations Raise Upgrade Risk

Construction requires `erp_fabrica` and `fabrica_accounting`, and its hooks replace classes or methods from Frappe and ERPNext. This makes the installed app versions and hook order part of Construction's effective interface.

**Suggested solution:** record the supported app revisions and test the combined stack during upgrades. Add a small compatibility adapter only for upstream behavior that has multiple callers or changes across supported versions. Avoid a generic integration layer without a concrete need.

## Recommended Order

1. Inventory downstream imports, class overrides, and method replacements before changing shared code.
2. Confirm the requirements for wildcard versioning and each validation bypass.
3. Measure the slow invoice paths and batch only the reads shown to be repeated.
4. Extract one cohesive operation from a large controller when that behavior is next changed.
5. Test the affected Construction flow together with the downstream apps that extend it.

This order improves locality and makes each change easier to verify. It does not require a new framework, a broad rewrite, or a new app structure.

## Evidence Limits

This is a static source review. No site database, production query trace, benchmark, installed-app order, or application test run was used. Confirm runtime costs and customer-specific behavior before making broad changes. The app's existing refactoring review gives detailed code-path references and test guidance.