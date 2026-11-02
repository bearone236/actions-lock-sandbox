# actions-lock-sandbox

GitHub Actions の workflow dependency lockfile（`.github/workflows/actions.lock`、2026-10-28 GA）を入れると、上流の action のタグが force push で付け替えられたときに何が変わるのかを、実際に Actions を動かして比べるためのリポジトリです。

上流の action 役は [bearone236/actions-lock-sandbox-upstream](https://github.com/bearone236/actions-lock-sandbox-upstream) にあります。"COMPROMISED" と表示するコードは文字列を出力するだけで、secret の読み出しや外部送信はしません。

## 構成

上流リポジトリには 2 つの composite action があります。

- `setup-tool`: ツールをインストールする action の役（内側）
- `scanner`: 内部で `setup-tool@v1.0.0` を使う action の役（外側）。2026 年 3 月に侵害された trivy-action と setup-trivy の関係を模しています

| タグ / ブランチ | コミット | 内容 |
|---|---|---|
| `v1`, `v1.0.0`（元の位置）, `release/v1.0.0` | `26d0722` | 安全な setup-tool |
| `v1.0.1` | `1fb43ac` | scanner のリリース。内部で `setup-tool@v1.0.0` を使う |
| `attack/descendant` | `693fb29` | 攻撃 A: 元の履歴の上に積んだ悪性コミット |
| `attack/orphan` | `09c3fc4` | 攻撃 B: 元の履歴と無関係な悪性コミット |

このリポジトリには、参照の書き方だけが違う 4 つのワークフローと、lockfile の検証ワークフローがあります。

| ワークフロー | 書き方 | lockfile |
|---|---|---|
| `01-tag.yml` | `setup-tool@v1` | なし |
| `02-sha.yml` | `setup-tool@<SHA>` | なし |
| `03-sha-transitive.yml` | `scanner@<SHA>`（scanner の中は `setup-tool@v1.0.0`） | なし |
| `04-locked.yml` | `scanner@v1.0.1` | あり |
| `05-verify-lockfile.yml` | `gh actions-lock --verify` を実行する | あり |

01〜03 は比較のためにわざと lockfile に入れていません。

## 結果（2026-11-02、gh-actions-lock v0.4.0、ubuntu-24.04 ランナー）

| | 攻撃前 | 攻撃 A（子孫コミットへ付け替え） | 攻撃 B（無関係なコミットへ付け替え） |
|---|---|---|---|
| 01 タグ | SAFE | COMPROMISED | COMPROMISED |
| 02 SHA | SAFE | SAFE | SAFE |
| 03 外側だけ SHA | SAFE | COMPROMISED（内側の setup-tool） | COMPROMISED（内側の setup-tool） |
| 04 actions.lock | SAFE | SAFE（ロックしたコミットを実行） | ジョブ失敗（ステップは 1 つも動かない） |
| 05 verify | success | failure（`tag-commit-mismatch`） | failure（`unreachable-pin`） |

攻撃 B での 04 のエラー:

```
##[error]Lockfile pin 26d0722ba1c61309c38eb85e999ffa02a6d51265 for `bearone236/actions-lock-sandbox-upstream` does not match ref `v1.0.0`. Ensure the pinned commit exists on the expected branch or tag
```

ほかに 2 つの挙動を PR で再現しています（どちらもマージしません）。

- [PR #1](https://github.com/bearone236/actions-lock-sandbox/pull/1): lockfile を更新せずにワークフローを変えると、verify が失敗し、`workflow_dispatch` も API に拒否される
- [PR #2](https://github.com/bearone236/actions-lock-sandbox/pull/2): `$/` で使う composite action の中を SHA で書くと、`--verify` は成功するのに実行時に `lockfile missing pin` で失敗する

`05-verify-lockfile` は schedule でも毎日実行しています。上流でタグが付け替えられても、ロックしたコミットがタグの履歴に残っていれば 04 は成功してしまい、自分のリポジトリに PR が無いと気づけないためです。

## 手元で再現する

上流役は fork せず、自分のアカウントに作り直します。scanner の中の `uses:` は `bearone236/actions-lock-sandbox-upstream/setup-tool@v1.0.0` と書かれているので、fork した上流のタグを付け替えても内側の依存には届かないためです。

必要なもの: GitHub アカウント、認証済みの [GitHub CLI](https://cli.github.com/)（2.98.0 で確認）、git 2.28 以上（`user.name` / `user.email` を設定済み）、bash（macOS 標準の 3.2 で確認）、perl、grep。

```sh
# すでに入っている場合は先に `gh extension remove actions-lock`
gh extension install github/gh-actions-lock --pin v0.4.0

# 利用者役を fork して clone する
gh repo fork bearone236/actions-lock-sandbox --clone
cd actions-lock-sandbox
OWNER=$(gh api user --jq .login)

# 上流役 $OWNER/actions-lock-sandbox-upstream を public で作る（タグと攻撃用ブランチも作る）
scripts/bootstrap-upstream.sh $OWNER
```

fork したサンドボックスの Actions タブ（`https://github.com/$OWNER/actions-lock-sandbox/actions`）を開き、ワークフローを有効にしてください（fork では既定で無効。schedule も動きません）。`gh workflow list -R $OWNER/actions-lock-sandbox` で 01〜05 が `active` なら準備完了です。

```sh
# ワークフローを自分の上流に向け直し、02 / 03 の SHA と lockfile を作り直す
scripts/retarget.sh $OWNER
git add .github/workflows
git commit -m "上流を自分のリポジトリに向ける"
git push

# 攻撃前 → 攻撃 A → 攻撃 B → 復旧
scripts/run-all.sh $OWNER/actions-lock-sandbox
scripts/move-tags.sh $OWNER/actions-lock-sandbox-upstream attack/descendant
scripts/run-all.sh $OWNER/actions-lock-sandbox
scripts/move-tags.sh $OWNER/actions-lock-sandbox-upstream attack/orphan
scripts/run-all.sh $OWNER/actions-lock-sandbox
scripts/move-tags.sh $OWNER/actions-lock-sandbox-upstream release/v1.0.0
scripts/run-all.sh $OWNER/actions-lock-sandbox   # 復旧の確認
```

`run-all.sh` は各ワークフローで実際にダウンロードされたコミットと、SAFE / COMPROMISED のどちらが出力されたかを表示します。`retarget.sh` は 04 と 05 だけを lockfile に登録します。引数なしで `gh actions-lock` を実行すると 01〜03 も登録され、02 / 03 の SHA がタグに書き換わるので注意してください。

終わったら `gh auth refresh -h github.com -s delete_repo` のあと `gh repo delete` で 2 つのリポジトリを削除できます。

確認済みの範囲: `bootstrap-upstream.sh --no-push` でこのリポジトリの上流と同じ出力をする action が生成されること、`retarget.sh` を owner を変えずに実行してワークフローと lockfile が変わらないこと、`run-all.sh` が macOS 標準の bash で動くこと。別のアカウントで 1 から通してはいません。
