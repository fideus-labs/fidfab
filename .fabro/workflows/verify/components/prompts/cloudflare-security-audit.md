# Security audit (personal data involved)

The decision stage determined that these changes handle potentially personal data. Run
the **security-audit** skill (Cloudflare's six-phase verified security audit) over the
branch changes and the code paths they touch. Follow the skill's phases: reconnaissance,
threat modelling, vulnerability analysis, verification of each candidate finding against
the real code, severity assessment, and reporting.

Pay particular attention to data minimisation, de-identification of metadata, retention,
logging and exposure of personal or medical data.

Write the audit report to `.fidfab/reviews/security-audit.md` with verified findings
only, each with severity, file and line references, evidence and a remediation. Do not
modify other files.

{% include "partials/workspace.md" %}
