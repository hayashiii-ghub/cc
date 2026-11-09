# cc:

資料や成果物をエージェントと受け渡す、macOSの小さな棚。
ファイル・画像・リンク・テキストを集めて「棚の資料を読んで」「cc:に置いて」と頼めます。

macOS 26以降・Apple Silicon / Intel対応。無料・オープンソース。
[サイト](https://cc.shigoto.dev) · [ダウンロード](https://github.com/hayashiii-ghub/cc/releases/latest)

## 使い方

1. DMGまたはZIPの`cc.app`をApplicationsへ入れて起動します。
2. **Settings → AI Tools → Set Up**でCodex・Claude Code・Antigravity向けのCLIとスキルを設定します。更新は同じ画面の**Update**から。
3. メニューバーの`cc:`から棚を開き、ドラッグや**Paste**で資料を追加します。

初期ショートカットは、Finderの選択項目を追加する**Option + Tab**と、棚を開閉する**Option + Shift + Tab**。
開くアプリは**Settings → Open with**で選べます。AIにも棚の項目を開く・削除するよう頼めます。

資料はMac内にコピーして保存し、棚から削除しても元ファイルは残ります。
アカウント登録・クラウド同期・利用状況の収集はありません。
アプリの更新は**Settings → Updates…**から。v0.4.0より前の版は手動導入とデータ・設定の移行が必要です。

Appleの公証は未対応です。初回起動がブロックされた場合は、信頼できる配布版か確かめて、macOSの**プライバシーとセキュリティ → このまま開く**を使います。
セットアップ・開発・公開手順は[AGENTS.md](AGENTS.md)へ。

ノッチの操作とサイトの表現は[CodexIsland](https://github.com/ericjypark/codex-island)を参考にしています。独立したプロジェクトです。
[MIT](LICENSE) · [第三者ライセンス](THIRD_PARTY_NOTICES.md)

## サイトのCloudflare公開

`site/`の静的ビルドを使い、既定の`cc-site-preview`と`production` modeの`cc-site`を分けています。本番設定だけに`cc.shigoto.dev`を登録し、プレビューには独自ドメインを接続しません。設定・buildの成功と、実際のDNS・HTTPS切替完了は分けて確認します。アプリ・更新フィードは変更しません。

Node.js 24.22.1 / Bun 1.4.2、image `dev-environment:0.1.1`を使います。cf `1.0.0-beta.28`とWrangler `4.158.0`は`site/package.json`と`bun.lock`で固定しています。cfの実行はNodeです。

初回は`/Users/hayashi/work/projects/dev-environment/README.md`に従い、`cc-cf-preview-home`と`cc-cf-preview-node-modules`を作り、UID/GID `501:20`で初期化します。リポジトリのルートから起動します。

```sh
container run -d --name cc-cf-preview-dev -w /workspace/site -e HOME=/home/dev \
  -v "$PWD:/workspace" -v cc-cf-preview-home:/home/dev \
  -v cc-cf-preview-node-modules:/workspace/site/node_modules \
  -p 127.0.0.1:8795:8795 dev-environment:0.1.1 sleep infinity
container exec -w /workspace/site cc-cf-preview-dev bunx --package bun@1.4.2 bun install --frozen-lockfile
container exec -w /workspace/site cc-cf-preview-dev bunx --package bun@1.4.2 bun run check
container exec -w /workspace/site cc-cf-preview-dev bunx --package bun@1.4.2 bun run test
container exec -w /workspace/site cc-cf-preview-dev bunx --package bun@1.4.2 bun run cf:check
container exec -it -w /workspace/site cc-cf-preview-dev bunx --package bun@1.4.2 bun run cf:dev
```

確認先は`http://localhost:8795`。build出力は`site/dist/`、CFの公開用出力は`site/.cloudflare/output/v0/`、依存とcacheは上のvolumeに保存します。終了は開発サーバーをCtrl+Cで止めて`container stop cc-cf-preview-dev`、再開は`container start cc-cf-preview-dev`です。

認証と公開はMac側で行います。Macの既存Node.js 24.22.1環境へcf `1.0.0-beta.28`をglobal installしており、既定のNode.jsは変更していません。ログインは`fnm exec --using=24.22.1 cf auth login`、プレビュー公開は`site/`から`fnm exec --using=24.22.1 cf deploy --prebuilt --worker cc-site-preview`で行います。資格情報をcontainerへコピーしません。

本番は`container exec -w /workspace/site cc-cf-preview-dev bunx --package bun@1.4.2 bun run cf:check:production`でbuild・dry-runします。本番への適用前に、既存DNSの引継ぎ、zoneの有効化、HTTPSの準備完了を確認します。`cf deploy`も設定済みの独自ドメインを適用するため、この確認前には実行しません。

準備とレビューが済んだら、Macの`site/`から`fnm exec --using=24.22.1 cf deploy --prebuilt --mode production --worker cc-site --no-provision`でコードとドメイン設定を更新します。`--no-provision`は不足するbindingリソースの作成を止めるだけで、ドメイン適用は止めません。アップロード済みWorkerのドメイン設定だけを更新する場合は、同じ前提を確認してから`fnm exec --using=24.22.1 cf workers triggers deploy --prebuilt --mode production --worker cc-site`を代わりに使います。適用後に[workers.devの確認先](https://cc-site.hayashigoto.workers.dev/)と`https://cc.shigoto.dev`を両方確認します。

Cloudflare Buildsの本番自動公開は、上の準備確認後に`main`だけを対象として有効にします。root directoryは`site/`、Node.jsは24.22.1、Bunは1.4.2、buildは`bun run check && bun run test && bun run cf:build:production`、deployは`node node_modules/cf/bin/cf deploy --prebuilt --mode production --worker cc-site`です。有効化後はmainへのpushで検査・公開し、他branchからは本番公開しません。上のMacからの手動コマンドも引き続き使えます。

Build Outputはmodeごとに保存されず、最後のbuildで置き換わります。cf beta.28は`--mode`省略時にその出力のmodeを使うため、省略してもプレビューには戻りません。実行前に`.cloudflare/output/v0/config.json`の`buildContext.mode`と`.cloudflare/output/v0/workers/default/worker.config.json`の`name`・`domains`を確認し、本番出力には`--mode production --worker cc-site`を付けます。プレビューへ戻る場合は`cf:check`で作り直します。

旧Vercelのproject・デプロイ・独自ドメイン登録は復旧用に保持します。戻す場合はCFのCustom Domainを解除してから、保存した元のVercel用DNSレコードを同じCloudflare zoneへ復元し、HTTPSと公開ページを確認します。サイトだけを戻すためにzone全体やメール設定を切り替えません。Vercelの停止・削除は移行確認後の別工程です。
