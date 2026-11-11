# Roadmap: research and first draft

Produce a research-backed development roadmap for:

> {{ goal }}

Write it as a set of markdown documents under `{{ inputs.plans_dir }}/$FIDFAB_PLAN_SLUG/`:

- `README.md` — the roadmap index: vision, scope and non-goals, guiding principles,
  ordered list of work items with one-line summaries, dependency graph between items
  (a Mermaid `graph` block renders on GitHub), milestones, and open questions.
- `research.md` — what you learned: the current state of the code base (use Serena to
  map it), relevant specifications and standards, prior art and comparable
  implementations, benchmarks or data sets, constraints discovered. Cite sources with
  URLs.
- `NN-<slug>.md` — one file per work item, each sized so that a single `fidfab medium`
  run can implement it. Every item has:
  1. **Motivation** — why this item exists and what it unblocks.
  2. **Research notes** — the specific findings that shape the design.
  3. **Implementation plan** — numbered phases with concrete steps, affected modules,
     interfaces to add or change, migration and compatibility considerations.
  4. **Verification** — tests to add, benchmarks, reproducibility checks.
  5. **Acceptance criteria** — observable, testable statements; these become the
     `task_plan.md` acceptance criteria when the item is implemented.
  6. **Dependencies and risks**.
  7. **Status** — `proposed` for now.

Work iteratively: research first, draft the index, then flesh out items in priority
order. Prefer understanding over volume; a smaller roadmap that is right beats a long one
that is vague.

End your reply by printing the full contents of `README.md` inside a fenced markdown
block, followed by a one-paragraph summary of each work item, so the human reviewer can
assess the draft from the run transcript.

{% include "partials/workspace.md" %}
