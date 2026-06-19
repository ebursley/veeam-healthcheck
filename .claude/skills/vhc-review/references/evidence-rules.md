# Evidence and confidence rules

Use this file to keep findings grounded in what the report explicitly shows.

## Evidence tiers

- **Fact**: Directly visible in a table row, header, checkbox, count, date, or value.
- **Inference**: A conclusion that follows from the facts but is not stated outright by the report.
- **Assumption**: A guess about cause, intent, or operational impact that is not supported by the report.

## Writing rules

- Label each finding with the strongest evidence tier you can justify.
- Use exact report values whenever possible.
- Do not state a causal root cause unless the report explicitly shows it.
- If a conclusion is inferred, use cautious language such as `suggests`, `indicates`, `likely`, or `appears`.
- If the report does not justify a strong claim, downgrade the wording rather than stretching the evidence.

## Date handling

- Treat the report header/footer date as the reference date for all time-based thresholds.
- Compare license expiry, recent detections, and freshness windows against the report date, not the conversation date.
- If the report date is missing, say so and avoid threshold claims that depend on it.

## Recommended finding shape

For each finding, include:
1. Exact object / job / repository / server name.
2. Exact source section and row/value.
3. What the report proves.
4. Why it matters.
5. Confidence: `high`, `medium`, or `low`.

## Strong wording allowed only when the report is explicit

- `disabled`, `not implemented`, `failed`, `expired`, `missing`, `unchecked`, `0% free`, `without TLS`

## Weaker wording for inferred conclusions

- `suggests`, `appears`, `likely`, `may indicate`, `should be validated`
