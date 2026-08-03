#!/usr/bin/env bash
set -e
REPO=ridhoajaaa/FilmKU
SHA=$(cd /home/ridhoajaaa/DataD/FreeBuff/FilmKU && git rev-parse HEAD)
echo "=== Waiting for workflow run for commit $SHA ==="
RUN_ID=""
for i in $(seq 1 25); do
  JSON=$(curl -s --max-time 20 "https://api.github.com/repos/$REPO/actions/runs?event=push&per_page=5")
  RUN_ID=$(echo "$JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); r=[x for x in d.get('workflow_runs',[]) if x['head_sha']=='$SHA' and x['name'].startswith('Build iOS')]; print(r[0]['id'] if r else '')" 2>/dev/null)
  if [ -n "$RUN_ID" ]; then echo "FOUND RUN_ID=$RUN_ID"; break; fi
  sleep 15
done
[ -z "$RUN_ID" ] && { echo 'NO_RUN_FOUND'; exit 1; }
echo "=== Polling run $RUN_ID ==="
for i in $(seq 1 45); do
  STATUS=$(curl -s --max-time 20 "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''), d.get('conclusion',''))" 2>/dev/null)
  echo "poll $i: $STATUS"
  case "$STATUS" in
    *completed*success*) echo "BUILD_SUCCESS RUN_ID=$RUN_ID"; exit 0;;
    *completed*failure*|*completed*cancelled*|*completed*timed_out*) echo "BUILD_FAILED RUN_ID=$RUN_ID"; exit 1;;
  esac
  sleep 20
done
echo "BUILD_TIMEOUT RUN_ID=$RUN_ID"
exit 2
