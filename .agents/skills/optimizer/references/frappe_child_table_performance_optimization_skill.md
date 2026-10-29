---
name: frappe-child-table-optimization
description: Guidelines and patterns for optimizing Frappe child tables handling high-volume or intensive datasets.
version: 1.0.0
tags:
  - frappe
  - erpnext
  - python
  - database-optimization
  - performance
---

# Frappe Child Table Performance Optimization

## Overview
In Frappe Framework, default child table behaviors (`doc.append()` + `doc.save()`) degrade exponentially as row counts increase. Frappe handles child tables by validating every row individually, wiping and re-inserting missing rows, triggering parent/child lifecycle hooks, and rendering heavy DOM elements in Desk forms.

Use this skill when designing, querying, or refactoring Frappe DocTypes that store high-volume, append-heavy, or calculation-heavy child records.

---

## 1. Storage & Database Indexing

### Rule 1: Ensure Composite Indexes on Link Fields
Frappe child tables store link references in `parent`, `parenttype`, and `parentfield`. When querying child records independently, ensure the composite index exists:

```sql
-- Ensure index exists on standard parent linkage
CREATE INDEX IF NOT EXISTS idx_parent_link 
ON `tabChild DocType` (parent, parentfield, parenttype);
```

### Rule 2: Keep Schema Footprints Narrow
- Minimize fields in the child DocType. Large `Text`, `Long Text`, or JSON blobs cause significant buffer pool thrashing and high row sizes during parent reads.
- Restrict `in_list_view` to 3–4 essential columns to avoid massive table payloads in Desk grids.

### Rule 3: Prune Orphaned Records
Improper script deletions can leave orphaned rows that slow queries down. Maintain database hygiene:

```python
def cleanup_orphaned_children(child_doctype: str, parent_doctype: str):
    """Prunes child rows whose parent no longer exists."""
    frappe.db.sql(f"""
        DELETE c FROM `tab{child_doctype}` c
        LEFT JOIN `tab{parent_doctype}` p ON c.parent = p.name
        WHERE p.name IS NULL
    """)
```

---

## 2. Bulk Ingestion (Bypassing ORM)

### Anti-Pattern
```python
# SLOW: Triggers Python document instantiation, validation loops, and slow SQL loops
for row in dataset:
    doc.append("items", {
        "item_code": row["item_code"],
        "qty": row["qty"],
        "rate": row["rate"]
    })
doc.save()
```

### Preferred Pattern: `frappe.db.bulk_insert`
For large batches (>100 records), bypass the ORM and write directly to the database.

```python
import frappe

def bulk_insert_child_rows(parent_name: str, parent_doctype: str, table_fieldname: str, records: list[dict]):
    """
    Inserts large amounts of child rows bypassing ORM overhead.
    """
    fields = ["name", "parent", "parenttype", "parentfield", "idx", "item_code", "qty", "rate"]
    values = []

    for idx, row in enumerate(records, start=1):
        values.append((
            frappe.generate_hash(length=10),
            parent_name,
            parent_doctype,
            table_fieldname,
            idx,
            row.get("item_code"),
            row.get("qty", 0),
            row.get("rate", 0.0),
        ))

    # Perform batch insert
    frappe.db.bulk_insert("Child DocType Name", fields=fields, values=values)
    frappe.db.commit()
```

---

## 3. Querying & Reading (Selective Fetching)

### Anti-Pattern
```python
# SLOW: Loads parent and ALL child tables into memory as Document trees
doc = frappe.get_doc("Parent DocType", parent_name)
for row in doc.items:
    process(row)
```

### Preferred Pattern: Direct SQL or `frappe.get_all`
Fetch only the fields and subsets required.

```python
# Query only the required columns directly from the child table
items = frappe.get_all(
    "Child DocType Name",
    filters={"parent": parent_name, "parentfield": "items"},
    fields=["name", "item_code", "qty", "rate"],
    order_by="idx asc",
    limit_page_length=500
)
```

---

## 4. Client-Side (Desk / UI) Optimization

1. **Avoid Heavy Client Calculations:**
   - Do not attach expensive `frm.cscript` triggers or `items_add` events that iterate over all rows inside Desk forms.
   - Debounce real-time computations or provide a manual "Recalculate Totals" action button.
2. **Limit Desk Form Rows:**
   - Desk grids struggle with >300 DOM rows.
   - For parents holding >500 child records, suppress default child grid loading in form view and use a embedded custom report, virtual data grid, or independent list view.

---

## 5. Architectural Thresholds: When to Refactor

| Scale Threshold | Recommended Architecture |
|---|---|
| **< 500 rows per parent** | Standard Child Table with ORM operations. |
| **500 – 5,000 rows** | Standard Child Table, but bypass ORM using `bulk_insert` and direct queries. |
| **> 5,000 rows per parent** | **Decouple into an Independent DocType** with a `Link` field to the parent. |
| **High-Frequency Append-Only Logs** | Virtual DocType or write directly to a dedicated append-only log table. |

### Decoupling Pattern (Independent DocType)
Instead of:
`Parent Doc` -> `Table field` -> `Child Table`

Refactor to:
`Child Doc (Submittable/Standard)` -> `parent_document (Link field to Parent Doc)`

**Advantages:**
- Native server-side pagination, search, and filtering via standard List View.
- Zero parent document locking or deadlock risk on concurrent updates.
- Aggregations can be moved to asynchronous background jobs (`frappe.enqueue`).