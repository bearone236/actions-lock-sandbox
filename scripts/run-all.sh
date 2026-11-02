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

latest_run_id() {
  gh run list -R "${repo}" --workflow "$1.yml" --event workflow_dispatch --limit 1 \
    --json databaseId --jq '.[0].databaseId // 0'
}

before=()
for wf in "${workflows[@]}"; do
  before+=("$(latest_run_id "${wf}")")
  gh workflow run "${wf}.yml" -R "${repo}"
done

for i in "${!workflows[@]}"; do
  wf=${workflows[$i]}
  # dispatch 直後は run 一覧に出てこないことがある。前回の run を拾わないよう、新しい id が出るまで待つ
  id=${before[$i]}
  for _ in $(seq 1 30); do
    id=$(latest_run_id "${wf}")
    [ "${id}" != "${before[$i]}" ] && break
    sleep 2
  done
  if [ "${id}" = "${before[$i]}" ]; then
    echo "=== ${wf}: dispatch した run が見つからない" >&2
    exit 1
  fi
  gh run watch "${id}" -R "${repo}" --exit-status >/dev/null 2>&1 || true
  conclusion=$(gh run view "${id}" -R "${repo}" --json conclusion --jq .conclusion)
  echo "=== ${wf}: ${conclusion} (https://github.com/${repo}/actions/runs/${id})"
  # ログの各行は「job<TAB>step<TAB>timestamp 本文」。BSD sed は [^\t] を解釈しないので perl で外す
  gh run view "${id}" -R "${repo}" --log 2>/dev/null \
    | perl -pe 's/^[^\t]*\t[^\t]*\t\S+ //' \
    | grep -E "Using locked|Download action repository|: SAFE \(|: COMPROMISED \(|^##\[error\]|^✗|^  (tag|locked commit|used in)" \
    | grep -v 'echo ' || true
done
