# AI Development Work Cycle

Use this cycle to keep AI-assisted development scoped, testable, and reviewable. The agent classifies the user story and selects the matching workflow. Do not ask the user to select a workflow when the story provides enough information.

## Agent Workflow Router

1. Read the user story and the applicable `AGENTS.md` instructions. Inspect the repository state before making changes.
2. Classify the story by its requested outcome:
	- **Bug:** Existing behavior fails, regresses, or differs from the stated expected behavior. Route to `/fix-issue`.
	- **Feature:** The story adds or changes one bounded capability that can be delivered and verified as one coherent change. Route to `/apex`.
	- **Big multi-part feature:** The story contains multiple independently deliverable behaviors, dependencies, or end-to-end slices that need separate tickets. Route to `/grilling`, then `/to-spec` and `/to-tickets`, followed by `/implement-spec` after approval.
3. If a story mixes a bug and feature, classify by its primary requested outcome. Keep unrelated outcomes separate unless the story explicitly requires them together.
4. If the story does not provide enough information to determine behavior or scope, use `/grilling` to resolve only the decisions that could change the implementation.
5. For any Frappe task, also load `/frappe-app-dev` and the relevant references. For Frappe review, use `/frappe-code-review` when the domain or risk warrants it.
6. Follow the selected route below. Do not run `/apex` and `/implement-spec` for the same implementation.

## Feature Route: `/apex`

1. Use APEX to define the task contract, analyze the owning code path, plan, implement, validate, review by risk, and hand off.
2. Use `/grilling` only for unresolved decisions that can change behavior, scope, or risk.
3. Use `/tdd` for behavior changes. Agree on public test seams, then implement one failing test and behavior slice at a time.
4. Follow project approval rules before editing. In this repository, propose the change and wait for explicit approval when `AGENTS.md` requires it.
5. Review the complete task diff, including untracked files. Preserve unrelated user changes.

## Big Multi-Part Feature Route: `/implement-spec`

1. Read the user story and current codebase context.
2. Use `/grilling` to settle decisions that affect behavior, scope, or acceptance criteria.
3. Draft or revise the technical plan. Resolve its decision questions before implementation.
4. Agree on observable acceptance criteria and public test seams.
5. Use `/to-spec` to write the agreed spec when a published spec is needed.
6. Use `/to-tickets` to split the approved scope into end-to-end, independently verifiable tickets with correct blockers.
7. Review the ticket breakdown and wait for approval before publishing tickets or starting implementation.
8. Use `/implement-spec` to implement the approved ticket graph. It uses `/tdd` per ticket and `/code-review` at the end.
9. Inspect all changed files, including untracked files, and confirm the final diff matches the approved spec.

## Bug Route: `/fix-issue`

1. Use `/fix-issue` for a reported bug. Do not adopt the reporter's suspected cause as fact.
2. Reproduce the observable failure, or report why it cannot be reproduced.
3. Trace the behavior to its cause and make the smallest in-scope fix.
4. Add and run a regression test, then run relevant surrounding checks.
5. Review the working diff, including untracked files. Use the Frappe review skill when applicable.
6. Report the cause, fix, tests, review result, and unresolved gaps.

## Review Rules

- Use `/code-review` when you can provide a valid fixed Git base and the relevant spec. It reviews committed changes between that base and `HEAD`.
- Do not assume `/code-review` includes uncommitted or untracked files. Review those separately or make the intended changes visible in the reviewed diff.
- APEX reviews the actual task diff and selects review depth by risk. Avoid duplicating its review without a reason.
- Review findings are evidence to inspect, not instructions to apply blindly. Confirm each finding against the code and task scope.
- Do not commit, push, create a pull request, merge, deploy, or contact external systems unless the user authorized that action.

## Completion Check

Before handing off, confirm that:

- Every acceptance criterion has evidence at the required level.
- Every introduced failure is fixed or clearly reported as blocked.
- Tests and checks are reported with accurate results.
- The task diff contains only intended changes and preserves unrelated work.
- Runtime, provider, or deployment behavior is not claimed unless it was verified.
- The report lists remaining risks and checks that were not run.
