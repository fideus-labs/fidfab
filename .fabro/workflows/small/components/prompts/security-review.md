# Security review of the branch changes

Perform a focused security review of the branch diff (`fidfab-diff`). Use Claude Code's
built-in `/security-review` command when available; in addition, examine the changed
code yourself for:

- injection (command, SQL, path, template), unsafe deserialisation and parsing of
  untrusted input (including scientific file formats: headers, chunk sizes, offsets);
- path traversal and unsafe file handling; TOCTOU; temp files;
- secret handling and logging of sensitive values;
- memory safety (`unsafe` blocks, FFI boundaries, integer overflow in size arithmetic,
  unbounded allocations driven by input);
- authentication/authorisation and network exposure of any new endpoints;
- dependency changes (new crates/packages, version bumps) and their advisories
  (`cargo audit`, `cargo deny`, `npm audit`, `pip-audit` when applicable).

Write `.fidfab/reviews/security-review.md` as a findings list with `[security]`,
`[bug]`, `[nit]` prefixes, file and line references, impact, and a suggested fix. If there
are no findings, write `No findings.` and state what you checked. Do not modify other
files.

{% include "partials/workspace.md" %}
