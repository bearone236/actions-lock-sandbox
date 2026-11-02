#!/usr/bin/env bash
# 上流リポジトリの v1 / v1.0.0 タグを、指定したブランチ（またはコミット）へ付け替える。
# タグ改ざん型のサプライチェーン攻撃と、その復旧を再現するためのスクリプト。
#
#   scripts/move-tags.sh <owner>/actions-lock-sandbox-upstream attack/descendant  # 攻撃 A
#   scripts/move-tags.sh <owner>/actions-lock-sandbox-upstream attack/orphan      # 攻撃 B
#   scripts/move-tags.sh <owner>/actions-lock-sandbox-upstream release/v1.0.0     # 元に戻す
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <owner/upstream-repo> <branch-or-sha>" >&2
  exit 2
fi

upstream=$1
target=$2

sha=$(gh api "repos/${upstream}/commits/${target}" --jq .sha)
for tag in v1 v1.0.0; do
  gh api -X PATCH "repos/${upstream}/git/refs/tags/${tag}" -f sha="${sha}" -F force=true \
    --jq '"\(.ref) -> \(.object.sha)"'
done
