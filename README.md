# UltraScale

3440 × 1440の外部モニタで、文字・UIの大きさを100〜200%の範囲で1%刻みに選ぶmacOSアプリです。縦横比を維持し、選んだ見かけの解像度の2倍で描画する仮想HiDPI画面を外部モニタへミラー表示します。整数ピクセルへの丸めにより各辺に最大0.5ピクセルの差があります。

## 使い方

1. 下記の手順でビルドし、`build/UltraScale.app` を開きます。必要ならFinderで「アプリケーション」へコピーできます。
2. 3440 × 1440の外部モニタを接続し、対象を選びます。
3. スライダーで倍率を選び、「HiDPIを適用」を押します。
4. 表示を確認して15秒以内に「この設定を使う」を押します。確認しなければHiDPIを解除して通常表示に戻ります。倍率を変更し直した際も、未確認の場合はHiDPIを解除します。
5. 解除するには「元の表示に戻す」を押すか、アプリを終了します。

ウインドウを閉じてもHiDPI表示は継続します。メニューバーのディスプレイアイコンから再表示・解除・終了できます。スリープ時は解除します。スリープ復帰後や再接続後は手動で適用してください。既存のミラーリングがある場合は先にシステム設定で解除してください。

未接続時にも倍率と見かけの解像度を確認できますが、適用は無効になります。内蔵画面へ適用する機能はありません。

## アイコン

標準は青いスクリーン＋角丸スライダーです。予備として緑のスクリーン版もアプリに収録しています。「UltraScale → Dockアイコン → 青／緑」から起動中のDockアイコンを切り替えられ、選択は次回起動時にも引き継ぎます。Finderに表示するアプリファイルのアイコンは青のままです。

原画と透過素材は `Assets/Icons/` に保存しています。輪郭の切り抜きと各サイズへの変換はコードで再現できます。手順は [アイコン素材の説明](Assets/Icons/README.md) を参照してください。

| 倍率 | 見かけの解像度 | 内部の描画解像度 |
| --- | --- | --- |
| 100% | 3440 × 1440 | 6880 × 2880 |
| 125% | 2752 × 1152 | 5504 × 2304 |
| 150% | 2293 × 960 | 4586 × 1920 |
| 200% | 1720 × 720 | 3440 × 1440 |

## 対応範囲と制限

- 同梱バイナリはApple Silicon向けです。今回の動作検証環境はMacBook Air M4 / macOS 15.8.1です。
- 仮想画面は60 Hz・SDRです。HDR、可変リフレッシュレート、高リフレッシュレートは対象に含めません。
- 倍率の変更はモード切り替えです。ドラッグ中にデスクトップが連続アニメーションするものではなく、「適用」で切り替わります。画面の瞬断やウインドウの移動が起こる可能性があります。
- HiDPIは高解像度で描画してから縮小する方式です。モニタ自体の物理画素数は増えません。画質・負荷はモニタや接続構成によって異なります。
- 非公開の `CGVirtualDisplay` APIを使います。macOS更新後の互換性は保証されません。利用できない場合はエラーを表示します。
- 設定変更はアプリの動作中だけのCore Graphics設定です。システムファイル、ディスプレイのオーバーライド、SIP、ログイン項目は変更しません。画面録画は行いません。
- ローカルビルド用のアドホック署名です。Developer IDによる署名・公証は行っていません。

## 検証

検証内容と未検証事項は `VALIDATION.md` に記録しています。実際の3440 × 1440モニタは今回未接続のため、実モニタでの画質・映像出力・抜き差し・スリープ復帰は未検証です。仮想画面での検証は実モニタでの検証を代替しません。

## ビルドとテスト

外部ライブラリやXcodeプロジェクトは不要です。AppleのCommand Line Toolsが必要です。

```bash
git clone https://github.com/tndd/ultrascale.git
cd ultrascale
./build.sh
open build/UltraScale.app
./test.sh
```

ビルド結果は標準で、リポジトリ内の `build/UltraScale.app` に出力されます。`./build.sh /任意の出力先/UltraScale.app` で変更できます。

実際のWindowServer APIで仮想画面・ミラー・復元を検証する場合は次を実行します。一時的な仮想画面を作成するため、テスト中はデスクトップ配置が変わる場合があります。

```bash
./test.sh --virtual
```

テスト用バイナリとUI画像はGit管理外の `build/` に出力します。UIテストはAppKitの実コントロールへアクションを送信し、ウインドウ内容を描画・検査します。ユーザーの実クリックや実モニタの目視検証とは区別しています。Web UIではないためPlaywright・組み込みブラウザは使用していません。

## API調査の参照先

- [Apple: CGConfigureDisplayMirrorOfDisplay](https://developer.apple.com/documentation/coregraphics/cgconfiguredisplaymirrorofdisplay(_:_:_:))
- [Apple: CGCompleteDisplayConfiguration](https://developer.apple.com/documentation/coregraphics/cgcompletedisplayconfiguration(_:_:))
- [Chromium: macOS仮想ディスプレイの実装](https://github.com/chromium/chromium/blob/main/ui/display/mac/test/virtual_display_util_mac.mm)

仮想画面のモード引数はこのMac上で実測しました。HiDPIモードには論理解像度を、ディスプレイの最大サイズにはその2倍のピクセル数を渡しています。

公開リポジトリ: [tndd/ultrascale](https://github.com/tndd/ultrascale)。アプリのビルド成果物とテスト画像はGit管理に含めません。
