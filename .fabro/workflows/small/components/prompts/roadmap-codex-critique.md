# Roadmap critique (independent second opinion)

Read the roadmap documents under `{{ inputs.plans_dir }}/$FIDFAB_PLAN_SLUG/`
(`FIDFAB_PLAN_SLUG` is set in your shell and recorded in `.fidfab/run.env`) and the
relevant parts of the code base (use `ccc` for semantic search). Critique the roadmap as a
senior research software engineer would:

- Are the work items correctly sequenced and are the dependencies real?
- Are implementation plans concrete enough to execute without re-deriving the design?
- Are acceptance criteria observable and testable? Are reproducibility and
  verification covered?
- What is missing, over-scoped, or technically risky? Which assumptions in
  `research.md` deserve a citation or an experiment?

Write your critique as a markdown findings list to `.fidfab/reviews/roadmap-critique.md`
with `[gap]`, `[risk]`, `[sequence]`, `[criteria]`, `[nit]` prefixes and references to the
specific documents and sections. Do not modify the roadmap files.
