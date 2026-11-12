# BOQ Refactoring Lessons & Architecture Patterns

This document captures the architectural decisions, refactoring patterns, and performance optimizations implemented during the refactoring of the `BOQ` (Bill of Quantities) DocType (Commit `0c88dcf85` / PR `refactor/v1`). 

These patterns serve as the **authoritative architectural template** to guide the refactoring of `boq_variation_order` and other large construction DocTypes.

---

## 1. Executive Summary of the BOQ Transformation

| Dimension | Before Refactoring | After Refactoring |
| :--- | :--- | :--- |
| **Controller Size** | Monolithic `boq.py` (~4,000 lines) | Slim orchestration layer (~740 lines) |
| **Logic Placement** | Mixed validation, SQL, math, mapping, and UI hooks | Specialized service package in `services/boq/` |
| **Query Complexity** | $O(N)$ N+1 queries during row validation and saves | $O(1)$ amortized queries via `BOQReferenceContext` |
| **Downstream Safety** | High risk of breaking `aljar_system` overrides | 100% backward compatibility via module delegation |
| **Test Strategy** | Scattered high-level integration tests | Modular unit tests per service in `tests/boq/` |

---

## 2. The Core Architecture: Dedicated Service Layer

Instead of keeping business logic inside the Frappe `Document` controller class, `BOQ` delegated domain responsibilities to a dedicated package: [`fabrica_construction/services/boq/`](file:///home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/services/boq/).

```
services/boq/
├── __init__.py               # Re-exports all public API functions
├── reference_context.py      # Batch-loader & in-memory cache for N+1 elimination
├── calculations.py           # Pure financial totals, rates, and quantity math
├── validation.py             # BOQValidationService (rules, hierarchy, duplicates)
├── resources.py              # BOQResourceService (item resource sync & rate derivation)
├── item_population.py        # BOQItemPopulationService (grid filling & hierarchy sorting)
├── mapping.py                # Document mappers (Contracts, Quotations, Tenders)
├── variation_order.py        # Variation order generation, queueing, & delete tracking
└── queries.py                # Reusable QB/SQL queries and projections
```

### Key Principles Applied:
1. **Orchestrator Controller**: `boq.py` acts solely as the lifecycle orchestrator (handling `validate`, `on_submit`, `on_cancel`, `before_insert`). It delegates all heavy domain logic to services in a single line (e.g., `BOQValidationService(self).validate_boq_data()`).
2. **Single Responsibility Principle (SRP)**: Financial math does not live next to database queries; row insertion does not live next to hierarchy validation.
3. **Pure Functions & Testability**: Calculations (in `calculations.py`) take raw values or lightweight objects and return numbers/dicts without mutating database state, making them trivially unit-testable in milliseconds.

---

## 3. Pattern 1: Batch-Loading Context (`BOQReferenceContext`)

### The Problem
During row-by-row iteration in validation or resource generation:
- Checking if a `uom` exists runs `frappe.db.exists("UOM", uom)` per row.
- Checking item categories runs `frappe.db.get_value("Construction Item", code, "category")` per row.
- Checking parent categories runs `frappe.db.get_value("Construction Category", ...)` per row.
- For a 1,000-row BOQ, saving the document caused **3,000+ database roundtrips**.

### The Solution: `BOQReferenceContext`
Location: [`fabrica_construction/services/boq/reference_context.py`](file:///home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/services/boq/reference_context.py#L22-L170)

```python
class BOQReferenceContext:
    """Operation-scoped context to load related data once per BOQ run."""
    def __init__(self, boq_doc, data_provider=None):
        self.boq_doc = boq_doc
        self.data_provider = data_provider or frappe.db
        self._category_map = {}
        self._existing_uoms = set()
        self._item_map = {}
        self._loaded = False

    def load_for_validation(self):
        if self._loaded:
            return self

        rows = self.boq_doc.get("bill_of_quantity", default=[])
        # 1. Single pass: collect distinct keys across all child rows
        uoms = {r.get("uom") for r in rows if r.get("uom")}
        item_codes = {r.get("item_code") for r in rows if r.get("item_code")}

        # 2. Batch query in a single DB roundtrip using IN
        if uoms:
            self._existing_uoms = set(
                self.data_provider.get_all("UOM", filters={"name": ["in", list(uoms)]}, pluck="name")
            )
        if item_codes:
            records = self.data_provider.get_all(
                "Construction Item",
                filters={"name": ["in", list(item_codes)]},
                fields=["name", "category", "is_a_boq_item"]
            )
            for r in records:
                self._item_map[r.name] = r

        self._loaded = True
        return self
```

### Takeaway for `boq_variation_order`:
`boq_variation_order` currently repeats database lookups per row in:
- `validate_uploaded_data_update_current`
- `_get_boq_children()` in `update_current_boq.py`
- Resource rate queries in `_get_new_scope_resource_rates`
Applying a `BOQVariationOrderReferenceContext` will immediately collapse these redundant queries into single-pass batch lookups.

---

## 4. Pattern 2: Strict Backward Compatibility & Downstream Safety

### The Problem
`Aljar System` directly subclasses `BOQ` (`AljarBOQ`) and overrides or calls methods on `BOQ` controller. Refactoring must never break:
1. Method signatures on the `BOQ` class.
2. Module-level functions imported by other apps or monkey-patched in `hooks.py`.
3. `@frappe.whitelist()` endpoints callable from Desk JavaScript or mobile clients.

### The Solution: Facade Controller & Compatibility Export
In [`fabrica_construction/doctype/boq/boq.py`](file:///home/ahmed-khairy/Documents/Projects/Fabrica_Project/frarica_construction/fabrica_construction/doctype/boq/boq.py#L27-L45):
```python
# 1. Class methods delegate directly to specialized service instances
class BOQ(Document):
    def validate_boq_data(self) -> None:
        BOQValidationService(self).validate_boq_data()

    def calculate_total_amount(self) -> None:
        _calc.calculate_total_amount(self)

    def set_rate_for_items(self) -> None:
        _calc.set_rate_for_items(self)

    @frappe.whitelist()
    def fill_boq_child_table(self, adding_type: str = "NEW") -> dict[str, Any]:
        return _item_pop.fill_boq_child_table(self, adding_type)

# 2. Module-level functions re-export from services to preserve imports:
calculate_total_amount = _calc.calculate_total_amount
set_rate_for_items = _calc.set_rate_for_items
create_boq_variation_order = _vo.create_boq_variation_order

# 3. Explicit __all__ list exports all legacy symbols
__all__ = [
    "BOQ",
    "calculate_total_amount",
    "set_rate_for_items",
    ...
]
```

### Takeaway for `boq_variation_order`:
`AljarBOQVariationOrder` subclasses `BOQVariationOrder` and overrides:
- `boq_vaidate_system_structure_hierarchy`
- `before_validate`
- `before_submit`
- `_validate_non_negative`
When decomposing `boq_variation_order.py`, all class methods and module functions must be preserved as delegating shims so `AljarBOQVariationOrder` continues functioning seamlessly without edits to `aljar_system`.

---

## 5. Pattern 3: Decoupling Calculations from Database Persistence

### The Problem
In legacy controllers, calculations often called `.save()`, `.db_set()`, or `frappe.db.commit()` in the middle of loops, triggering cascaded hooks and lock contention.

### The Solution: Pure In-Memory Projections with Explicit DB Sync
In [`services/boq/calculations.py`](file:///home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/services/boq/calculations.py):
1. **In-Memory Calculations**: Methods like `_get_boq_child_item_resource_totals` calculate numbers on in-memory objects without touching SQL:
   ```python
   def _get_boq_item_resource_qty(boq_child_qty: float, ratio: float, scrap_percent: float) -> float:
       return flt(boq_child_qty) * flt(flt(ratio) / 100) * flt(1 + (flt(scrap_percent) / 100))
   ```
2. **Explicit Batched DB Updaters**: Dedicated helper functions update the database when explicitly requested (e.g. `update_boq_child_item_resource_qty_fields_in_db`), clearly separating read/calculate phases from write phases.

### Takeaway for `boq_variation_order`:
In `boq_variation_order.py`, `_update_boq_child_item` and `_insert_new_boq_child_item` currently call `.save()` or `.db_set()` per child row inside a submit loop. Decoupling the calculation from persistence and performing a single batch update will dramatically reduce execution time.

---

## 6. Pattern 4: Background Execution with Threshold Gate

### The Problem
Large documents with 500+ rows freeze the Desk UI or cause HTTP gateway timeouts (504) during submit or document creation.

### The Solution: Threshold-Gated Queueing
In [`services/boq/variation_order.py`](file:///home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/services/boq/variation_order.py#L98-L128):
```python
def should_enqueue_boq_variation_order(source_name: str, variation_order_flow_type: str) -> bool:
    if variation_order_flow_type != "Update Current BOQ":
        return False

    enqueue_enabled = cint(frappe.db.get_single_value("Construction Settings", "enque_construction_documents_in_background"))
    row_threshold = cint(frappe.db.get_single_value("Construction Settings", "number_of_row"))
    if not enqueue_enabled or row_threshold <= 0:
        return False

    mapped_row_count = frappe.db.count("BOQ Child", filters={"parent": source_name, "parenttype": "BOQ"})
    return mapped_row_count > row_threshold
```
- Small operations run synchronously for immediate feedback.
- Large operations run in the background queue (`save_construction_docs`) with a file lock (`filelock`) and notify the user via `frappe.publish_realtime`.

---

## 7. Pattern 5: Isolated Test Factories & Unit Test Architecture

### The Problem
Integration tests that create real database records (`frappe.get_doc({...}).insert()`) take 2-5 seconds each, causing slow test suites and flakey runs due to uncommitted test state.

### The Solution: Fast Mock Document Factories
In [`tests/boq/factories.py`](file:///home/ahmed-khairy/Documents/Projects/Fabrica_Project/frappe-bench/apps/fabrica_construction/fabrica_construction/tests/boq/factories.py):
- Created `FakeDocument`, `FakeBOQ`, `FakeVariationOrder` extending `frappe._dict`.
- Tested business logic in memory with `unittest.mock.patch` where necessary.
- Result: 50+ unit tests across `tests/boq/` execute in **under 2 seconds**.

---

## 8. Concrete Mapping to `boq_variation_order` Refactoring

| BOQ Pattern | Corresponding Application for `BOQ Variation Order` |
| :--- | :--- |
| **`services/boq/` package** | Create `fabrica_construction/services/boq_variation_order/` to house flows, calculations, validation, and logs. |
| **`BOQReferenceContext`** | Implement `BOQVOReferenceContext` to batch load BOQ Child rows, Construction Items, Categories, and Settings during validation. |
| **Eliminate per-row `.save()`** | Batch-update or bulk-insert new `BOQ Child` rows during `back_update_boq_for_submit` instead of calling `new_boq_child.save()` per row. |
| **Eliminate per-row Log submission** | Bulk-insert `BOQ Variation Order Logs` in a single query rather than instantiating and submitting individual submittable docs. |
| **Prevent Hook Storms** | Pass context flags (e.g. `flags.ignore_item_resource_recalculation = True`) to avoid re-triggering `on_change` per row. |
| **Controller Preservation** | Maintain all public methods on `BOQVariationOrder` to ensure `AljarBOQVariationOrder` remains 100% stable. |
| **Dedicated Unit Test Suite** | Create `tests/boq_variation_order/` with mock factories mirroring `tests/boq/`. |
