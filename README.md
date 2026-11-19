# container-image-security-scanning

Personal lab on my own AWS and GitHub accounts. The company and scenario below are fictional. Nothing here is client or employer work.

## Scenario

A small payments API team (fictional) asks: which base image should we standardise on for our Python services? They want fewer vulnerabilities, a non root runtime, and an image that still runs in a locked down container.

I built the same Flask app four ways and scanned each with Trivy on 19 November 2026.

## Variants

| Variant | Base image | Runs as | Built size | CRITICAL | HIGH | HIGH with a fix |
|---|---|---|---|---|---|---|
| slim | python:3.15-slim (Debian 13.7) | root (uid 0) | 237 MB | 0 | 53 | 6 |
| slim-hardened | same base, multi stage, pip removed | uid 10001 | 219 MB | 0 | 48 | 1 |
| alpine | python:3.15-alpine (Alpine 3.24.4) | uid 10001 | 96 MB | 0 | 0 | 0 |
| chainguard | cgr.dev/chainguard/python (Wolfi) | uid 65532 | 118 MB | 0 | 0 | 0 |

All four run Python 3.15.2 and the same app. Every base image is pinned by digest. Dockerfiles are in `docker/`.

Each variant was started with `--read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges` and served `/health` (evidence 06).

## What the numbers mean

**slim to slim-hardened (53 to 48 HIGH, 6 to 1 fixable).** The difference is five HIGH findings. In my GitHub Actions pipeline lab the same base image had five HIGH findings in packages vendored inside pip (msgpack, urllib3, setuptools), and removing pip cleared them. The matching count here is consistent with that, but evidence 01 holds counts only, so I am not claiming the exact package names for this lab. The app does not need pip at runtime, which is why a multi stage build that copies only the installed dependencies is safe.

**The one fixable finding left in slim-hardened** is zlib1g, CVE-2026-85091, with a fixed Debian version available (evidence 04). I left the patch out on purpose so the table shows what hardening alone does. In a real pipeline this is the finding that fails the gate until the base image or an apt upgrade catches up.

**Of the 48 HIGH findings in slim-hardened, 47 have no fixed version available** (evidence 04 against evidence 05). That is accepted risk to be reviewed, not a clean bill of health.

**The zeros for alpine and chainguard are real scans, not failed scans.** Trivy detected the operating system and counted the packages: 33 OS packages for Alpine, 30 for Wolfi, against 88 for Debian slim (evidence 02 and 03 for the first two). Fewer packages means fewer places for a CVE to land. It does not mean the image is secure.

## Trade offs

**Alpine**
- Uses musl instead of glibc. Python packages with compiled extensions can need musl specific wheels or a compiler at build time. My app has no such dependencies, so I did not hit this.
- Has a shell and a package manager, which helps debugging and also helps an attacker.

**Chainguard**
- The runtime image has no shell (evidence 07), so you cannot get a shell inside it with docker exec. The healthcheck and the entrypoint must use exec form. A separate latest-dev image (969 MB) is needed for the build stage.
- The free tier offers only the latest and latest-dev tags, so the digest pin is the only thing holding the version still. Without an update process, a digest pin goes stale. I did not test Dependabot against this registry in this lab.

**Debian slim**
- Best compatibility and the most familiar tooling. Also the largest scan surface and the noisiest report.

## Recommendation

For this app, Chainguard, on two conditions: the team accepts no shell in the runtime image, and someone owns the process for bumping the digest. If the team needs a shell for debugging, use Alpine. If the team needs glibc, use slim-hardened and gate on fixable findings only, with the unfixed list reviewed on a schedule.

## CI

`.github/workflows/images.yml` runs on every push and pull request to main. One matrix job per variant: build, start with the locked down flags, check health and the uid, scan with Trivy, write a count table to the run summary and keep the JSON report as an artifact.

- alpine and chainguard are gated. Gate 1 fails on any CRITICAL. Gate 2 fails on HIGH that has a fix.
- slim and slim-hardened are report only. They exist for the comparison, and gating them would keep main red (6 and 1 fixable HIGH).
- Trivy is installed as a binary with a checksum check, every Action is pinned to a commit SHA, and the token is read only.

**Proof the gate can fail.** On a throwaway pull request I turned the gate on for slim-hardened. Gate 2 failed on zlib1g CVE-2026-85091, the one fixable HIGH, while the other jobs stayed green (evidence 08). The pull request was closed without merging. Gate 1 was not shown failing, because none of these images has a CRITICAL finding to trigger it.

## Limits of this lab

- One small app, one scanner (Trivy), one day. Results change daily as vulnerability data and base images change. Treat the table as a snapshot.
- Trivy reports known CVEs. It does not judge exploitability, and zero findings does not mean zero risk.
- I did not measure startup time, memory or build time.
- The sample app has only Flask and its dependencies. A real service with native extensions may behave differently on Alpine.

## Reproduce

    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt -r requirements-dev.txt && pytest -q
    for v in slim slim-hardened alpine chainguard; do docker build -q -f docker/Dockerfile.$v -t cis-$v .; done
    bash scripts/scan-compare.sh
    bash scripts/run-locked-down.sh

## Evidence

| File | What it shows |
|---|---|
| evidence/01-variant-comparison.md | Counts for all four variants |
| evidence/02-trivy-alpine.txt | Alpine scan, OS detected, zero findings |
| evidence/03-trivy-chainguard.txt | Chainguard scan, OS detected, zero findings |
| evidence/04-trivy-slim-hardened-fixable.txt | The one fixable HIGH (zlib1g) |
| evidence/05-trivy-slim-hardened-all-high.txt | All 48 HIGH on slim-hardened |
| evidence/06-locked-down-run.txt | Each variant healthy under a locked down container, with its uid |
| evidence/07-shell-check.txt | Chainguard runtime has no shell, slim does |
| evidence/08-gate-proof-red-run.txt | CI log of Gate 2 failing on zlib1g when slim-hardened was gated on a throwaway pull request |
