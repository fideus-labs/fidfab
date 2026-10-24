# Decision: do these changes touch potentially personal data?

Inspect the branch diff (`fidfab-diff`) and the code it touches. Decide whether the
changes handle, store, transmit, log or infer **potentially personal data** — for
example: names, e-mail addresses, identifiers, account or session data, IP addresses,
device identifiers, free-text user content, images of people, or **health and medical
data** (patient identifiers, DICOM headers and other medical image metadata, clinical
measurements, dates of birth, study and accession numbers, protected health information
in any form).

Be conservative: when the code processes scientific or medical imaging data formats that
can carry identifying metadata, answer **yes**.

Write a short justification to `.fidfab/reviews/personal-data-decision.md` (what data,
where in the diff, why it is or is not personal). Then end your reply with exactly one
routing directive JSON object on its own line:

- `{"preferred_next_label": "personal-data", "context_updates": {"personal_data": true}}`
  when potentially personal data is involved, or
- `{"preferred_next_label": "no-personal-data", "context_updates": {"personal_data": false}}`
  otherwise.

Do not modify any other file.
