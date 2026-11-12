Objective: implement approved phases 1-3 only. Exclude imports, commits, deployment and real tests.
Baseline: root master 1bd666c650dac9e703a389dcc8dca5ad27bc5cf9; target app clean; unrelated untracked documentation preserved.
Risk: high, billing semantics. Independent review required. Runtime proof intentionally not run per user simulated-test policy.
Evidence: repository inspection, syntax and whitespace checks, simulated acceptance matrix.
Capabilities: shell, patch, Git and bounded agents. No external services required.
