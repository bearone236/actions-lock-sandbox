#!/usr/bin/env bash
# サンドボックスのワークフローを <owner>/actions-lock-sandbox-upstream に向け直し、
# 02 / 03 の SHA をその上流の v1.0.0 / v1.0.1 のコミットに書き換えて actions.lock を作り直す。
#
#   scripts/retarget.sh <your-github-owner>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <your-github-owner>" >&2
  exit 2
fi

upstream="$1/actions-lock-sandbox-upstream"
v100=$(gh api "repos/${upstream}/commits/v1.0.0" --jq .sha)
v101=$(gh api "repos/${upstream}/commits/v1.0.1" --jq .sha)

perl -pi -e "s|[\\w.-]+/actions-lock-sandbox-upstream|${upstream}|g" .github/workflows/0*.yml
perl -pi -e "s|setup-tool\\@[0-9a-f]{40}|setup-tool\\@${v100}|" .github/workflows/02-sha.yml
perl -pi -e "s|scanner\\@[0-9a-f]{40}|scanner\\@${v101}|" .github/workflows/03-sha-transitive.yml

# 01〜03 は比較のためにわざと lockfile に入れない。引数なしの `gh actions-lock` は
# 全ワークフローを登録し、02 / 03 の SHA もタグに書き換えてしまうので、対象を絞る。
rm -f .github/workflows/actions.lock
gh actions-lock .github/workflows/04-locked.yml .github/workflows/05-verify-lockfile.yml
