#!/usr/bin/env bash
# 01〜05 のワークフローを workflow_dispatch で実行し、終わったら
# 「どの action のどのコミットが動き、SAFE / COMPROMISED のどちらが出たか」を表示する。
#
#   scripts/run-all.sh <owner>/actions-lock-sandbox
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <owner/sandbox-repo>" >&2
  exit 2
fi

repo=$1
workflows=(01-tag 02-sha 03-sha-transitive 04-locked 05-verify-lockfile)

for wf in "${workflows[@]}"; do
  gh workflow run "${wf}.yml" -R "${repo}"
done

# dispatch 直後は run 一覧に出てこないことがあるので少し待つ
sleep 10

for wf in "${workflows[@]}"; do
  id=$(gh run list -R "${repo}" --workflow "${wf}.yml" --event workflow_dispatch --limit 1 \
    --json databaseId --jq '.[0].databaseId')
  gh run watch "${id}" -R "${repo}" --exit-status >/dev/null 2>&1 || true
  conclusion=$(gh run view "${id}" -R "${repo}" --json conclusion --jq .conclusion)
  echo "=== ${wf}: ${conclusion} (https://github.com/${repo}/actions/runs/${id})"
  gh run view "${id}" -R "${repo}" --log 2>/dev/null \
    | sed -E 's/^[^\t]*\t[^\t]*\t[0-9TZ:.-]+ //' \
    | grep -E "Using locked|Download action repository|: SAFE \(|: COMPROMISED \(|^##\[error\]|^✗|^  (tag|locked commit|used in)" \
    | grep -v 'echo ' || true
done
