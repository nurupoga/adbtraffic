# ADB Traffic Monitor

Android端末のネットワークトラフィックをリアルタイムで監視するBashスクリプトです。

## 機能

- **リアルタイム監視**: ダウンロード/アップロード速度をリアルタイムで表示
- **グラフィカル表示**: ASCII文字によるグラフでトラフィックの変動を可視化
- **複数デバイス対応**: 複数のADBデバイスが接続されている場合、選択可能
- **自動インターフェース検出**: Wi-Fi、モバイルデータなど複数のネットワークインターフェースに対応

## 必要環境

- Android SDK Platform Tools (adb コマンド)
- Bash 4.0以上
- USB デバッグが有効になったAndroid端末

## インストール

1. Android SDK Platform Toolsをインストール
2. このリポジトリをクローン
3. スクリプトに実行権限を付与

```bash
git clone <repository-url>
cd adbTraffic
chmod +x adb_traffic_monitor.sh
```

## 使用方法

### 基本的な使用

```bash
./adb_traffic_monitor.sh
```

### 複数デバイスが接続されている場合

スクリプト実行時に接続されているデバイスの一覧が表示され、監視したいデバイスを選択できます：

```
Multiple devices detected:
1. ABC123DEF456 (Samsung Galaxy S21)
2. XYZ789GHI012 (Google Pixel 6)

Select device number (1-2): 1
```

## 表示内容

- **Time**: 現在時刻
- **Download**: ダウンロード速度 (B/s, KB/s, MB/s)
- **Upload**: アップロード速度 (B/s, KB/s, MB/s)
- **Download Traffic**: ダウンロード速度の時系列グラフ
- **Upload Traffic**: アップロード速度の時系列グラフ

## 対応ネットワークインターフェース

以下の優先順位でネットワークインターフェースを検出します：

1. wlan0 (Wi-Fi)
2. wlan1 (Wi-Fi)
3. rmnet1 (モバイルデータ)
4. eth0 (イーサネット)

## 終了方法

`Ctrl+C` を押してスクリプトを終了します。

## トラブルシューティング

### ADBが見つからない場合

```
[ERROR] ADB command not found. Please install Android SDK platform-tools.
```

Android SDK Platform Toolsをインストールし、PATHに追加してください。

### デバイスが見つからない場合

```
[ERROR] No ADB devices connected. Please connect your Android device.
```

1. USB デバッグが有効になっているか確認
2. デバイスが正しく接続されているか確認
3. `adb devices` コマンドでデバイスが認識されているか確認

## ライセンス

MIT License