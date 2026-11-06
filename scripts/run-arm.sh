#!/bin/zsh
# usage: scripts/run-arm.sh <device-udid> <bundle-id> <arm> <reps> <run-id>
set -u
D=$1; B=$2; ARM=$3; REPS=$4; RUN=$5
mkdir -p out
xcrun devicectl device process launch --device "$D" --terminate-existing "$B" -- --arm="$ARM" --reps="$REPS" --run="$RUN" >/dev/null || exit 1
end=$((SECONDS + 150 + REPS * 110))
while (( SECONDS < end )); do
  sleep 15
  xcrun devicectl device copy from --device "$D" --domain-type appDataContainer --domain-identifier "$B" \
    --source "Documents/results-$RUN.jsonl" --destination "out/results-$RUN.jsonl" >/dev/null 2>&1
  grep -qE '"done"|"fatal"' "out/results-$RUN.jsonl" 2>/dev/null && exit 0
done
echo "timed out: $RUN"; exit 2
