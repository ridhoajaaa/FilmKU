#!/usr/bin/env bash
# retrigger_ios_when_actions_up.sh — waits out a GitHub Actions outage (the
# push was dropped because Actions was in major outage), then re-triggers the
# iOS cloud build via an empty commit push and polls it. Logs to
# /tmp/ios_retrigger.log.
set -uo pipefail

LOG=/tmp/ios_retrigger.log
REPO=ridhoajaaa/FilmKU
ROOT=/home/ridhoajaaa/DataD/FreeBuff/FilmKU

echo "[$(date -u +%H:%M)] watcher started" > "$LOG"

# 1. Wait until Actions is no longer in major outage (up to ~6h).
for i in $(seq 1 120); do
  ST=$(curl -sS --max-time 15 'https://www.githubstatus.com/api/v2/components.json' 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print([c['status'] for c in d.get('components',[]) if c['name']=='Actions'][0])" 2>/dev/null)
  echo "[$(date -u +%H:%M)] Actions status: ${ST:-unknown}" >> "$LOG"
  if [ "$ST" = "operational" ]; then
    echo "[$(date -u +%H:%M)] Actions operational — re-triggering" >> "$LOG"
    break
  fi
  sleep 180
done

# 2. Re-trigger via an empty commit push (the original push event was dropped
#    during the outage).
cd "$ROOT" || exit 1
git add -A >/dev/null 2>&1
git commit --allow-empty -m "chore: re-trigger iOS build after GitHub Actions outage" >/dev/null 2>&1 \
  && git push origin main >> "$LOG" 2>&1
NEWSHA=$(git rev-parse HEAD)
echo "[$(date -u +%H:%M)] pushed $NEWSHA" >> "$LOG"

# 3. Wait for + poll the Build iOS workflow run.
RUN_ID=""
for i in $(seq 1 40); do
  RUN_ID=$(curl -sS --max-time 20 "https://api.github.com/repos/$REPO/actions/runs?event=push&per_page=5" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); r=[x for x in d.get('workflow_runs',[]) if x['head_sha']=='$NEWSHA' and x['name'].startswith('Build iOS')]; print(r[0]['id'] if r else '')" 2>/dev/null)
  [ -n "$RUN_ID" ] && break
  sleep 20
done
if [ -z "$RUN_ID" ]; then
  echo "[$(date -u +%H:%M)] ERROR: no Build iOS run for $NEWSHA" >> "$LOG"
  exit 1
fi
echo "[$(date -u +%H:%M)] Build iOS RUN_ID=$RUN_ID" >> "$LOG"
for i in $(seq 1 60); do
  ST=$(curl -sS --max-time 20 "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''), d.get('conclusion',''))" 2>/dev/null)
  echo "[$(date -u +%H:%M)] poll: $ST" >> "$LOG"
  case "$ST" in
    *completed*success*) echo "[$(date -u +%H:%M)] BUILD_SUCCESS RUN_ID=$RUN_ID SHA=$NEWSHA" >> "$LOG"; exit 0;;
    *completed*failure*|*completed*cancelled*) echo "[$(date -u +%H:%M)] BUILD_FAILED $ST" >> "$LOG"; exit 1;;
  esac
  sleep 30
done
echo "[$(date -u +%H:%M)] BUILD_TIMEOUT" >> "$LOG"
exit 2
