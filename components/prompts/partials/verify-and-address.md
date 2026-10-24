## How to verify and address findings

For every finding in the review file named above:

1. **Verify** it against the actual code and the branch diff (`fidfab-diff`). Reproduce
   bugs with a failing test or a concrete trace where feasible. Do not accept a finding
   on authority; do not dismiss one without evidence.
2. **Decide** one of:
   - `fixed` — the finding is valid; you changed code and/or tests. Summarise the fix.
   - `fixed-differently` — valid, but a different remedy is better. Explain why.
   - `not-an-issue` — invalid or out of scope for this diff. Give the evidence.
   - `deferred` — valid but intentionally not addressed now (explain, and open a TODO or
     issue reference only if the repository uses them).
3. **Re-verify**: run the relevant build, tests, lints and formatters after your changes.
   New behaviour needs a test.
4. **Record** the approach for each finding in the response file named above, as a
   markdown table or list with columns: finding, severity, decision, approach/evidence,
   files touched. Keep the original finding text (abbreviated) so the record is
   self-contained.

Leave the working tree in a buildable, tested state. Do not commit; a later stage
creates the commit.
