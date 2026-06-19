# VHC decision rules

## Security

Critical:
- MFA is not enabled on the backup server.
- Configuration backup is not enabled, not encrypted, or the last result is not successful.
- Support is expired or expires within 30 days of the report date.
- A repository that should be immutable shows immutability disabled.
- S3 archive or cloud backup traffic is explicitly configured without TLS / encryption.

Warning:
- Traffic encryption is disabled for backup traffic.
- Non-default registry keys indicate a workaround, a compatibility issue, or a security exception.
- Malware detections exist, but describe them as detections or indicators unless the report says otherwise.
- Do not claim a confirmed breach, exfiltration, or root cause without explicit report evidence.

## Job health

Critical:
- Any job success rate is below 80%.
- Any relevant workload type is missing when the environment clearly contains that workload class.
- Protected workload counts show unprotected VMs or physical systems.
- Treat a disabled or failed tape layer as degraded recovery posture, not a fully lost air gap, unless the report explicitly says no offline copy exists.

Warning:
- Any job success rate is 80% to 95%.
- Any job is disabled or has no next run.
- Wait for resources is non-zero and clearly problematic, or average wait exceeds 30 minutes.
- If the report suggests a root cause (for example HotAdd fallback or S3 instability), phrase it as a hypothesis unless the report explicitly confirms it.

## Capacity

Critical:
- Any repository or SOBR extent has less than 10% free space.

Warning:
- Any repository or SOBR extent has 10% to 20% free space.
- A Vi proxy has failover to NBD enabled.
- Proxy resources are clearly undersized for the environment.
- A SOBR is missing a capacity tier in an environment that already uses multiple repositories or cloud targets.
- If free-space or capacity claims depend on a specific repository/extent, cite the exact row and the numeric values.

## Best practices

Warning:
- Compression is set to Extreme or None when not required.
- Block size is outside the normal LAN target or local target settings.
- A primary backup job has GFS disabled.
- Reverse Incremental is used.
- Synthetic Full and Active Full are both disabled.
- Non-default registry keys are present.
- Do not elevate tuning items into operational failures unless the report includes supporting failures, retries, or capacity pressure.

## Prioritization

1. Security and recoverability first.
2. Coverage and job failures second.
3. Capacity third.
4. Optimization and tuning last.

## Writing guidance

- Use the report's own terminology.
- Keep the exact object names.
- Group related findings when they share one root cause.
- Do not turn every warning into a separate recommendation if one fix addresses several related items.
