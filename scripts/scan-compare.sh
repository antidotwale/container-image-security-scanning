#!/usr/bin/env bash
# Scans each image variant with Trivy and prints a markdown table of HIGH and CRITICAL counts.
set -euo pipefail
echo "| variant | CRITICAL | HIGH | with a fix |"
echo "|---|---|---|---|"
for v in slim slim-hardened alpine chainguard; do
  trivy image --scanners vuln --severity HIGH,CRITICAL --format json --quiet --no-progress --skip-version-check --timeout 60m "cis-$v" > "/tmp/trivy-$v.json"
  python3 - "$v" <<'PY'
import json, sys
v = sys.argv[1]
d = json.load(open(f"/tmp/trivy-{v}.json"))
crit = high = fixable = 0
for r in d.get("Results", []):
    for x in r.get("Vulnerabilities") or []:
        if x["Severity"] == "CRITICAL":
            crit += 1
        elif x["Severity"] == "HIGH":
            high += 1
        if x.get("FixedVersion"):
            fixable += 1
print(f"| {v} | {crit} | {high} | {fixable} |")
PY
done
