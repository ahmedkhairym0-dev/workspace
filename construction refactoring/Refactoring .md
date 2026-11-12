# Role
You are a senior Frappe/ERPNext architect and performance engineer. Your task is to perform a deep, evidence-based review of the custom doctype `boq_variation_order` (a Bill of Quantities Variation Order) and everything that touches it, then produce a prioritized plan to make it faster, cleaner, and easier to maintain.

# Mode: READ-ONLY ANALYSIS
- Do NOT modify any files, run patches, or change data. Produce findings and proposed diffs only.
- Do not guess. Every claim must cite a file path and line range or a concrete measurement. If you cannot verify something, label it "Unverified" and say how to verify it.
- Ask me before running anything against a production site. Prefer a dev/staging site.

# Phase 1: Discovery (map the full footprint)
Locate and read everything related to `boq_variation_order`:
1. Doctype JSON: fields, field types, `search_index`/`unique`/`in_list_view`/`in_standard_filter`, child tables, link fields, `is_submittable`, `track_changes`, `autoname`, `fetch_from` fields, permissions, and workflow.
2. Python controller: all lifecycle methods (`autoname`, `validate`, `before_save`, `on_update`, `before_submit`, `on_submit`, `on_cancel`, `on_trash`, `after_insert`, etc.), whitelisted methods, and helper modules.
3. Child doctypes (BOQ items, variation items, etc.) and their controllers.
4. Client scripts (`.js` in the doctype folder, `doctype_js` in hooks, and any Client Script records exported as fixtures).
5. `hooks.py` entries: `doc_events`, `scheduler_events`, `override_doctype_class`, `override_whitelisted_methods`, `fixtures`, permission query conditions, and `has_permission`.
6. Reports, Script Reports, Dashboards, Number Cards, Print Formats, and Workspaces referencing it.
7. Patches (`patches.txt`) and migrations touching this doctype or its data.
8. Other doctypes that read or write to it (Project, Contract, BOQ, Sales/Purchase documents, etc.), found via grep for the doctype name and its fields.
9. Tests and fixtures.

Output a dependency map: what triggers what, in what order, on which events.

# Phase 2: Architecture & Design Review
Evaluate:
- **Data model**: normalization, redundant or denormalized fields, whether totals and cumulative values are stored or recomputed, missing links, JSON/Text fields used where child tables fit (and vice versa), and the number of fields and child rows per document.
- **Business logic placement**: logic in the controller vs. client script vs. hooks vs. SQL; duplicated logic across layers; fat controllers; missing service/utility modules.
- **Lifecycle correctness**: validations in the wrong event, side effects in `validate`, logic that runs on every save but only needs to run on submit, and re-entrancy or recursion risk (e.g. `on_update` calling `save()` on itself or related docs).
- **Submit/cancel/amend flow**: correct handling of docstatus, rollback of cumulative values on cancel, and consistency of totals against the original BOQ.
- **Concurrency & integrity**: race conditions when multiple variation orders affect the same BOQ, missing row locks (`for_update`), non-atomic multi-document updates, and misuse of `frappe.db.commit()`.
- **Permissions & security**: SQL injection in raw queries, unchecked `ignore_permissions=True`, whitelisted methods missing permission checks.
- **Code quality**: dead code, magic strings and numbers, inconsistent naming, missing type hints and docstrings, broad `except`, `frappe.throw` messages not wrapped in `_()`, and repeated code that should be extracted.
- **Frappe conventions**: version compatibility, deprecated APIs, and use of the framework's built-in features instead of reinventing them (e.g. `frappe.qb`, `get_cached_doc`, `frappe.utils` helpers, `flags`).

# Phase 3: Performance Analysis
Hunt for these specific problems, with evidence:
**Database**
- N+1 patterns: `frappe.get_doc`, `frappe.db.get_value`, or `frappe.db.exists` inside loops; replace with a single `frappe.get_all`/`frappe.qb` query using `IN`, joins, or `group_by`.
- `frappe.get_doc(...)` where `frappe.db.get_value`, `get_cached_value`, or `get_all(fields=[...])` is enough.
- Loading entire documents (and all child tables) just to read one field.
- Row-by-row `doc.save()`, `insert()`, or `db_set` in loops; consider `frappe.db.bulk_insert`, `frappe.db.set_value` with batching, or `update_modified=False` where appropriate.
- Aggregations done in Python that should be SQL (`SUM`, `COUNT`, `GROUP BY`).
- Missing indexes on fields used in `WHERE`, `JOIN`, `ORDER BY`, and filters (list view, reports, link filters). Recommend `search_index` or composite indexes via patch, and check existing indexes with `SHOW INDEX`.
- Queries that are not sargable (functions on indexed columns, leading-wildcard `LIKE`).
- `SELECT *` and unbounded queries with no `limit`.
- Per-row `fetch_from` fields and Link-field title fetches that add load to list views.

**Application**
- Heavy work inside `validate`/`on_update` that should run once, be deferred, or be enqueued with `frappe.enqueue` (long jobs, notifications, recalculation of rollups).
- Repeated recomputation of the same totals; opportunities for caching (`frappe.cache`, `@site_cache`, `get_cached_doc`) with correct invalidation.
- Large child tables processed with nested loops (O(n²)); propose dict/set lookups.
- Unnecessary `reload()`, `get_doc().save()` on parent documents, and cascading saves that trigger further hooks (hook storms).
- Logic that runs on every form load or `onload` and could be lazy.

**Client side**
- `frappe.call`/`frm.call` fired per row or per keystroke (needs batching or debouncing), repeated `frappe.db.get_value` from JS in grid events, expensive `refresh` handlers, and redundant `frm.refresh_field` calls.

**Reports & list views**
- Slow Script Reports, missing pagination, and heavy `get_list` calls with many columns and filters.

# Phase 4: Measure, Don't Assume
Propose and, where I approve, run a measurement plan on a dev site:
- Use `frappe.recorder` (or the Recorder UI) to capture queries for: create, save, submit, cancel, and open form/list view with realistic data volume.
- Use `bench --site <site> mariadb` with `EXPLAIN`/`ANALYZE` on the top slow queries and enable the slow query log.
- Use `pyinstrument` or `cProfile` around the controller methods through `bench console`.
- Generate or describe a realistic test dataset (e.g. 50, 500, 2000 child rows) and report query count and wall time before and after each recommendation.
Report baseline numbers, or clearly state that they could not be collected.

# Phase 5: Deliverable
Produce a single report with these sections:

1. **Executive summary**: top 5 issues by impact, in plain language.
2. **Architecture map**: diagram or list of components and event flow.
3. **Findings table**. For each finding give:
   - ID, title, category (Performance / Architecture / Correctness / Security / Maintainability)
   - Severity (Critical / High / Medium / Low)
   - Evidence (file:line, query, or measurement)
   - Why it matters, with expected impact (e.g. "N+1: ~2 queries × row count")
   - Recommended fix, with a before/after code snippet
   - Risk of change, effort (S/M/L), and whether it needs a data patch or migration
4. **Quick wins**: changes that are low risk and under about an hour each.
5. **Refactoring roadmap**: phased plan (Phase A: safe optimizations, Phase B: structural refactors, Phase C: data model changes), with dependencies and ordering.
6. **Index and schema recommendations**: exact DDL or doctype JSON changes, plus patch skeletons.
7. **Test plan**: unit tests to add or extend (`FrappeTestCase`), regression scenarios for submit/cancel/amend, cumulative total checks, and concurrency checks.
8. **Open questions & assumptions**: anything that needs my input (business rules, data volumes, Frappe/ERPNext version).

# Quality bar
- Be specific to this codebase. No generic Frappe advice unless tied to a concrete location.
- Distinguish confirmed problems from suspected ones.
- Preserve business behavior: for every proposed optimization, state how to prove the behavior is unchanged.
- Prefer the smallest change that delivers the gain; flag over-engineering.
- Rank by impact ÷ effort.

Start with Phase 1 and show me the dependency map before moving on.