#!/usr/bin/env bash
# Starts each variant with a read only filesystem, no capabilities and no new privileges, then checks health and user id.
set -u
for v in slim slim-hardened alpine chainguard; do
  echo "== $v"
  docker run -d --rm --name "t-$v" -p 8000:8000 --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges "cis-$v" >/dev/null
  curl -fsS --retry 15 --retry-delay 1 --retry-all-errors http://127.0.0.1:8000/health 2>/dev/null || docker logs "t-$v"
  echo
  docker exec "t-$v" python -c "import os; print('uid', os.getuid())"
  docker stop "t-$v" >/dev/null
done
