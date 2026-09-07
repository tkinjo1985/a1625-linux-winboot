# a1625-linux-winboot

Git・OpenSSHクライアントと、任意のC/C++開発ツールをRAM上へ追加できるようになりました。
`/run/work` と選択した設定はWindows側にDPAPI暗号化して保存・復元します。
使い方と検証範囲は [開発ツール](windows-native/development-tools/README.md) と
[RAM状態保存](windows-native/ram-state/README.md) を参照してください。

```powershell
# 保存済みスナップショットと同じ構成で復元
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development -EnableZram -RestoreRamState -EnterShell
```

`minimal` はGitとSSHクライアント、`development` はGCC/G++・make・pkg-configも含みます。
`-DevelopmentProfile` を省略した場合は従来のCodex用最小環境です。

[English README](README.md)

このワークスペースには、Apple TV HD（A1625 / Apple A8）向けの、安全性を最優先し実機で検証したネイティブ Windows のブートパスが含まれています。

診断エントリーポイントは引き続き読み取り専用です。保護されたネイティブ checkm8/Pongo ビルド、PongoOS から m1n1 へのアップローダー、A8 向け 4 KiB ページカーネル、最小 initramfs、USB NCM ネットワーク、USB ACM リカバリーシェル、Dropbear SSH は、所有する A1625 で実行済みです。どのブートコンポーネントも内部ストレージをマウントまたは書き込みしません。

## 検証済みの RAM 専用チェーン

以下のチェーンを 2026-09-02 に検証しました。

1. Apple TV の通常モード（`05ac:12a7`）を検出する。
2. DFU モード（`05ac:1227`）を検出する。
3. libusbK を使用する Windows ネイティブの checkm8 実装を実行する。
4. PongoOS をアップロードし、その USB デバイス（`05ac:4141`）を待機する。
5. PongoOS の `pongoterm` を Windows/libusb へ移植し、結合済みの `m1n1 + DTB + Image.gz + initramfs.gz` イメージをアップロードする。
6. USB NCM/SSH または USB ACM シリアルを使用して Linux initramfs に接続する。

検証済みの識別情報は CPID `0x7000` および BDID `34` です。正確な ECID は非公開とし、ローカルで追加の識別ゲートとして指定します。生成される Linux gadget では `05ac:4142`、`172.16.42.1/24`、ポート 22 の公開鍵認証のみの Dropbear を使用しました。`/` は `rootfs` で、完全なユーザー空間はブート後およそ 2.6 MiB、telnet は含まれず、ブロックデバイスまたは APFS ファイルシステムは一切マウントされていません。

最小 initramfs と結合ペイロードをビルドするには、次を実行します。

```powershell
& .\windows-native\minimal-rootfs\build-minimal-initramfs.ps1
& .\windows-native\build-hoolock-payload.ps1 `
  -BootArgs 'console=ttySAC6,115200n8 loglevel=7' `
  -InitramfsPath .\artifacts\minimal-rootfs\minimal-initramfs.cpio.gz `
  -OutputName m1n1-linux-a1625-minimal-ssh.bin
```

## 安全な使用方法

1 回だけの診断を実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-native\atv-native.ps1 diagnose
```

USB の再列挙を 30 秒間監視します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-native\atv-native.ps1 watch -TimeoutSeconds 30
```

接続中のサービスモードデバイスのポート/コンテナーのベースラインを記録します。

```powershell
& .\windows-native\atv-native.ps1 baseline
```

自己完結型テストを実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-native\tests\AtvNative.Tests.ps1
```

これらのコマンドは USB 制御転送を一切実行せず、デバイスやシステムの構成も変更しません。`baseline` コマンドが書き込むのは、無視対象のローカルファイル `windows-native/device-baseline.json` のみです。このファイルには非公開の USB 識別情報やトポロジーの詳細が含まれる可能性があるため、公開してはいけません。

## RAM 上の Codex CLI

公式の Codex `aarch64-unknown-linux-musl` リリース、code-mode ホスト、bubblewrap サンドボックス、CA バンドル、および ChatGPT のデバイスコードログインは A1625 上で検証済みです。読み取り専用の Codex ツール呼び出しでデバイス上の `uname -m` を実行し、`aarch64` が返されました。

固定されたランタイムをデプロイし、ヘッドレスログインを開始します。

```powershell
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -Login
```

起動コマンド、認証情報の扱い、および RAM 上での制限については、[windows-native/codex-runtime/README.md](windows-native/codex-runtime/README.md) を参照してください。ランタイムと認証キャッシュは再起動時に消去され、内部ストレージには変更を加えません。

認証状態を RAM ブート間で保持するには、Windows DPAPI で暗号化し、次回のデプロイ後に復元します。

```powershell
& .\windows-native\codex-state\Save-A1625CodexState.ps1
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -RestoreState
```

暗号化された状態の既定の保存先は `%LOCALAPPDATA%\AppleTvA1625\state` です。平文の認証情報がリポジトリに書き込まれることはありません。[windows-native/codex-state/README.md](windows-native/codex-state/README.md) を参照してください。

## 1 コマンドでの RAM 環境復元

再起動後、所有する A1625 を DFU モードにし、PowerShell を管理者として実行します。

```powershell
# 初回のみの非公開デバイス設定（diagnose/DFU 出力に表示される ECID を使用）:
& .\windows-native\Set-A1625DeviceConfig.ps1 -ExpectedEcid '<16-hex-digit-ECID>'

# 以降の RAM 専用復元:
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot
```

このスクリプトは、正確な A1625/T7000 成果物ハッシュ、カーネルのページサイズ構成、および ECID を検証します。その後は一時的な DFU/PongoOS/RAM ブートチェーンのみを実行し、USB NCM と Windows NAT を復元し、USB ACM 経由で新しい Dropbear 公開ホスト鍵を取得して、Codex ランタイムと DPAPI 保護済みログイン状態を復元します。Zadig を表示された正確な `05AC:1227` または `05AC:4141` インスタンスに使用する必要がある場合は一時停止します。ドライバー自体を変更することはありません。復元の成功後に Codex を起動するには `-StartCodex` を追加します。

復旧後に PTY を割り当てた対話的 SSH シェルを開くには、次を実行します。

```powershell
& .\windows-native\Enter-A1625Shell.ps1
```

または、RAM 環境の完全な復元とそのシェルへの接続を 1 コマンドで実行します。

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot -EnterShell
```

このラッパーはブートごとの最新のホスト鍵ファイルを選択し、厳格なホスト鍵検証を有効に保ったまま `ssh -tt` を使用します。このシェル内で `codex` と入力すると、対話的な Codex UI が起動します。対話的なセッションには `ssh -T` を使用しないでください。`-T` は意図的に端末割り当てを無効にします。

このコマンドには、内部ストレージ、パーティション、NVRAM、tvOS、または palera1n fakefs の操作は含まれません。Linux ペイロードおよび Codex のインストール先は RAM のままで、再起動すると消去されます。

USB を使用せずに、ネイティブ PongoOS アップローダーをビルドおよびテストします。

```powershell
cargo test --manifest-path .\windows-native\pongo-uploader\Cargo.toml
```

固定されたソースから、Windows 向けに強化された `openra1n.exe` を実行せずにビルドします。

```powershell
$pongo = '<path-to-reviewed-Pongo.bin>'
$sha256 = (Get-FileHash -LiteralPath $pongo -Algorithm SHA256).Hash
& .\windows-native\build-openra1n.ps1 `
  -PongoPath $pongo `
  -ExpectedPongoSha256 $sha256
```

ソースリポジトリは、固定されたコミット、origin、クリーンなワークツリーと一致していなければなりません。生成されるマニフェストでは、正確な Pongo イメージと対象 ECID がレビューされるまで、デバイスでの使用は引き続き未承認とされます。

このプロジェクトで使用するリビジョンの公開 upstream ソースリポジトリのみを取得します（ファームウェア、Pongo バイナリ、Apple のデータはダウンロードしません）。

```powershell
& .\windows-native\Get-PinnedSources.ps1
```

`third_party` および `artifacts` ディレクトリは意図的に無視対象です。そのため、クリーンなクローンでは、復元コマンドを使用する前に、文書化されたツールチェーンとローカルでレビュー・ビルドされた成果物が必要です。来歴とライセンスについては、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。

## 安全境界

このプロジェクトは、所有している、またはテストを明示的に許可されているハードウェアでのみ使用してください。対象は Apple TV HD A1625 / AppleTV5,3 / J42d / T7000 に限定されており、別のモデルまたは SoC に一般化するには個別のレビューが必要です。

次の操作は意図的に含めていません。

- DFU への移行自動化
- リカバリー/復元コマンド
- NVRAM、パーティション、APFS、または内部ストレージの操作

Apple ファームウェア、IPSW コンテンツ、Pongo バイナリ、コンパイル済みカーネル、Codex バイナリ、デバイス識別子、認証状態、または秘密鍵は、このリポジトリでは配布しません。Apple、palera1n、PongoOS、Hoolock Linux、Codex は各権利者の名称です。この研究プロジェクトは、各権利者と提携または推奨関係にはありません。

DFU および Pongo のドライバー変更は、それぞれの正確な VID/PID と、検証済みの単一接続インスタンスに限定されます。RAM 専用の Linux、SSH、NCM、ACM の各マイルストーンが実証済みであっても、永続ストレージ操作には引き続き別途明示的な確認が必要です。

## 調査の根拠

- palera1n は Apple TV HD をサポートしますが、リリース済み CLI は Linux/macOS 向けで、公式の Windows 手段は起動可能な Linux 環境です。
- Hoolock Linux は PongoOS 方式を推奨しており、A7/A8 では 4 KiB カーネルページ（`CONFIG_ARM64_4K_PAGES=y`）を必要とします。
- PongoOS はホストスクリプトで USB プロダクト ID `4141` を使用します。
- 非公式の Palera1nWin プロジェクトは、Windows ネイティブの `openra1n` による checkm8/Pongo のアップロード後、WSL へ引き渡す例を示しています。そのネイティブコンポーネントは調査資料として扱い、所有する A1625/T7000 でここでは別途ゲートを設けて検証しました。

## ライセンス

このリポジトリ内のオリジナルコードおよびドキュメントは [MIT License](LICENSE) の下で利用できます。サードパーティプロジェクトおよびランタイム入力には各自の条件が適用されます。 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。
