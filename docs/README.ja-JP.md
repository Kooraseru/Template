<div align="center">
  <img src="../content/assets/branding/Billboard.svg" alt="Template" width="860">
  <h3>ソース、オートメーション、ドキュメント、公開のための再利用可能な基盤。</h3>

  <p>
    <a href="https://github.com/Kooraseru/Template"><img alt="Stars + Issues + License" src="https://shieldcn.dev/group/github/stars/Kooraseru/Template+github/Kooraseru/Template/issues+github/license/Kooraseru/Template.svg?variant=outline"></a>
  </p>

  <img src="https://counter.seku.su/cmoe?name=Kooraseru&theme=mb" alt="Visitor counter">

  <table>
    <tr>
      <td align="center"><a href="#features">機能</a></td>
      <td align="center"><a href="#quick-start">クイックスタート</a></td>
      <td align="center"><a href="#documentation">ドキュメント</a></td>
      <td align="center"><a href="#project">プロジェクト</a></td>
    </tr>
  </table>

  <table>
  <tr>
    <td align="center"><a href="README.md">English</a></td>
    <td align="center"><a href="README.ja-JP.md">日本語</a></td>
  </tr>
</table>
</div>

<h2 id="features">機能</h2>

- 作成されたソース、非公開のワークスペース状態、生成された出力の境界を明確に分離します。
- GitHub Issue の受付、依存関係管理、検証、公開のための再利用可能なオートメーションを提供します。
- MkDocs で構築したプロジェクトドキュメントを `.generated/site/` 内に限定します。
- 共有可能な VS Code の起動設定、タスク、拡張機能、スニペット、ポータブル MCP テンプレートを提供します。
- 不変の `source` コミットから、オートメーション管理の `canary`、`beta`、`stable` ブランチを生成します。

<h2 id="quick-start">クイックスタート</h2>

1. メンテナーが承認したテンプレート複製ワークフローを使用して、このテンプレートからリポジトリを作成します。
2. Template の名前、説明、ワードマーク、リンク、プロジェクト固有のガイダンスを置き換えます。
3. [公開ドキュメント](https://kooraseru.github.io/Template/)と[コントリビューションガイド](../CONTRIBUTING.md)を確認します。
4. プロジェクトが使用するソース領域、テスト、依存関係、公開コンテンツのみを追加します。
5. プロジェクトで必要な場合にのみ、公開、GitHub Pages、環境、署名、CodeQL を設定します。
6. `source` 向けのプルリクエストを開く前に、リポジトリ検証タスクを実行します。

公開処理では `../.github/publication/config.yml` の明示的な公開ファイル許可リストを使用します。公開範囲の変更に合わせて、この許可リストを調整してください。

<h2 id="documentation">ドキュメント</h2>

<table>
  <tr><td><a href="../CONTRIBUTING.md"><code>CONTRIBUTING.md</code></a></td><td>コントリビューターのワークフローを定義します。</td></tr>
  <tr><td><a href="../SECURITY.md"><code>SECURITY.md</code></a></td><td>脆弱性を非公開で報告する方法を定義します。</td></tr>
  <tr><td><a href="https://kooraseru.github.io/Template/">公開ドキュメント</a></td><td>生成されたドキュメントサイトを提供します。</td></tr>
</table>

<h2 id="project">プロジェクト</h2>

Template は再利用可能なリポジトリ基盤として管理されています。このテンプレートから作成したプロジェクトでは、テンプレートの識別情報を置き換え、担当メンテナーと実際の利用者が存在する機能のみを残してください。

### ブランチ

<table>
  <tr><td><code>source</code></td><td>正規の作成ブランチ</td></tr>
  <tr><td><code>canary</code></td><td>生成された早期利用チャンネル</td></tr>
  <tr><td><code>beta</code></td><td>生成されたテストチャンネル</td></tr>
  <tr><td><code>stable</code></td><td>生成された本番チャンネル</td></tr>
</table>

コントリビューターは `source` で変更を作成し、プルリクエストの対象も `source` にします。生成ブランチはオートメーションが管理します。

### ライセンス

[Observer License 0.1](https://github.com/Kooraseru/Observer-License) を採用しています。

### コントリビューター

<a href="https://github.com/Kooraseru/Template/graphs/contributors" target="_blank">
  <img src="https://contrib.rocks/image?repo=Kooraseru/Template" alt="Template contributors">
</a>
