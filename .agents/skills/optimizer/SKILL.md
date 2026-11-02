---
name: optimizer
description: Diagnose and improve Frappe and ERPNext performance, including child-table operations, database queries, and Desk forms. Use for reported slowness or requested performance optimization.
---

# Optimizer

Find the cause of slow behavior and propose the smallest change that preserves application behavior.

## Diagnose

- Identify the affected operation, custom app, files, and expected workload.
- Check existing behavior before proposing changes.
- Trace database calls, document loading, lifecycle hooks, and client events.
- Distinguish measured bottlenecks from suspected causes.
- Ask for missing evidence when it affects the proposed solution.

## Audit References

Load only the references needed for the affected operation:

- Read [the database audit reference](references/frappe_database_auditor_skill.md) for query patterns, indexes, caching, and transactions.
- Read [the code and database audit reference](references/frappe_code_database_performance_auditor.md) for broader audits covering loops, data structures, memory use, and database calls.

Treat checklist items as investigation prompts, not confirmed findings.
Check example APIs and framework behavior against the installed version before proposing changes.
Preserve query filters, permissions, row counts, ordering, and required lifecycle behavior when adapting examples.
Distinguish estimated gains from measured improvements.

## Child Tables

Read [the child-table reference](references/frappe_child_table_performance_optimization_skill.md) when child tables contribute to the performance problem.

Treat its row thresholds as investigation hints, not fixed limits.
Verify framework behavior against the installed version.
Confirm existing indexes and query patterns before proposing indexes.

Direct writes can bypass validation, permissions, hooks, and parent calculations.
Account for these requirements before recommending bulk operations.
Preserve transaction boundaries and child-row ordering.
Do not copy explicit commits or cleanup queries without task-specific justification.
Independent DocTypes can still require concurrency controls.

## Propose and Implement

Explain the root cause, affected files, options, and tradeoffs.
Follow repository approval requirements before editing.
Keep changes within the target custom app.
Preserve permissions, business rules, and user-visible results.
Avoid unrelated cleanup, schema changes, and new infrastructure.

## Verify

Compare the affected operation before and after the change.
Use relevant timing, query counts, payload size, or rendering evidence.
Check that results and required lifecycle behavior remain correct.
Label simulated outcomes clearly.
Do not claim measured improvements without measurements.
