# アプリアイコン

- `OriginalBlue.png`: 予備の青いスクリーン＋角丸スライダーの添付原画。
- `OriginalGreen.png`: 標準として採用された緑のスクリーンの添付原画。スライダーはありません。
- `IconBlue.png` / `IconGreen.png`: 原画をコードで切り抜いた1024×1024の透過素材。

4枚とも、アプリの制作・ビルドで使うソース素材としてGit管理します。テスト出力ではありません。原画の保存と、ビルド時に確実に同じアイコンを再現するため、保存期間の限られるCI artifactでの保管では足りません。

画像生成による透過では輪郭にノイズが残ったため、ユーザーの明示指定に基づき、原画の白いタイルの外周だけをコードで切り抜いています。スクリーンやスライダーの内部は描き直し・再生成していません。

再作成はリポジトリ直下で実行します。Apple Command Line Toolsのみを使用します。

```bash
mkdir -p build
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Cocoa scripts/prepare_icons.m -o build/prepare-icons
./build/prepare-icons
```

通常の `./build.sh` は透過素材から16〜1024pxのアイコンを生成し、青・緑両方の `.icns` をアプリへ収録します。生成される `.iconset` と `.icns` はGit管理外です。

標準のFinderアイコンは緑（バーなし）です。起動中のDockアイコンは「UltraScale → Dockアイコン」から青・緑を切り替えられ、次回起動時も選択を維持します。

Finder・Spotlight・ランチャー用の標準アイコンは `AppIcon.icns` として収録します。以前の青い標準アイコンのキャッシュを引き継がないよう、リソース名とバンドルの版を更新しています。
