# a1625-linux-winboot

Apple TV HD（A1625 / AppleTV5,3 / J42d / Apple A8 / T7000）を、Windows から **内蔵ストレージへインストールせず、一時的な RAM-only Linux として起動する**ためのツール群です。

このプロジェクトでは、DFU → checkm8 → PongoOS → m1n1 → Linux initramfs という一時ブート経路を使用します。Linux の root filesystem、開発ツール、Codex、Wi-Fi セッション、作業ディレクトリは RAM 上に置かれ、Apple TV の内蔵ストレージ、APFS、NVRAM、tvOS をマウントまたは書き換える処理は含みません。

> **対象機種は A1625 のみです。**
>
> 所有している、または明示的に許可を受けた Apple TV HD A1625 以外には使用しないでください。他モデル・他 SoC への流用は想定していません。

[English README](README.md)

---

## 現在の検証状況

2026-09-09 時点で、所有する A1625 について次を実機確認しています。

- Windows ネイティブの checkm8 / PongoOS ブート経路
- PongoOS から m1n1 + Linux + initramfs の RAM ブート
- AArch64 / 4 KiB page kernel
- RAM rootfs
- USB NCM ネットワーク
- USB ACM リカバリーシェル
- 公開鍵認証のみの Dropbear SSH
- Codex CLI の RAM 上での実行
- Git / OpenSSH client / GCC / G++ / make / pkg-config 等の RAM 開発環境
- RAM-only zram swap
- `/run/work` と選択された Codex / Git / SSH 状態の Windows DPAPI 暗号化保存・復元
- 内蔵 BCM4350 Wi-Fi
- WPA2-PSK / AES（CCMP）
- DHCP / DNS
- CA 検証付き HTTPS
- Wi-Fi IP 宛て SSH
- USB データ接続を物理的に外した後の Wi-Fi SSH

Wi-Fi は現在も「RAM 上の研究セッション」であり、永続インストールや自動起動サービスではありません。

詳細な検証記録:

- [RAM / 開発ツール検証](windows-native/VALIDATION-ISSUES-3-4.md)
- [Wi-Fi 検証記録](windows-native/wifi/acceptance-2026-09-09.md)
- [Wi-Fi セッション手順](windows-native/wifi/session-workflow.md)

---

## まず理解しておくこと

このプロジェクトでは、似た名前の 2 種類の「Profile」があります。

### BootProfile

`-BootProfile` は **どの Linux kernel / RAM payload を起動するか**を選びます。

例:

```powershell
-BootProfile baseline
```

または:

```powershell
-BootProfile wifi-t7000-leaf
```

### DevelopmentProfile

`-DevelopmentProfile` は、起動した Linux の RAM 上へ **どのユーザーランド開発ツールを追加するか**を選びます。

例:

```powershell
-DevelopmentProfile development
```

つまり、

```text
BootProfile
    ↓
Linux kernel / payload を決める

DevelopmentProfile
    ↓
その Linux 上へ追加する Git / SSH / GCC 等を決める
```

という関係です。

---

# 必要環境

## ハードウェア

- Apple TV HD A1625
- USB 接続可能な Windows PC
- DFU モードへはいれること
- Wi-Fi を使う場合は対応する WPA2-PSK / AES（CCMP）アクセスポイント

## Windows

本 README の主要コマンドは **PowerShell 7 (`pwsh`)** を前提とします。

必要なホストツール:

- PowerShell 7
- OpenSSH client
  - `ssh.exe`
  - `ssh-keygen.exe`
  - `ssh-keyscan.exe`
- Python
  - `python.exe`
- Git
- 必要なローカルビルド済み成果物

開発・再ビルドを行う場合は、用途に応じて MSYS2、Rust、C/C++ toolchain 等も必要になります。

---

# クリーンクローンについて

このリポジトリは、すべての実行バイナリやファームウェアを配布するものではありません。

特に以下は `artifacts` / `third_party` 等のローカル領域に置かれ、Git では配布されないものがあります。

- PongoOS binary
- ビルド済み kernel / payload
- `openra1n.exe`
- libusb 関連成果物
- SSH private key
- Codex binary
- Broadcom Wi-Fi firmware
- 個体固有データ
- Apple 由来データ
- 認証情報
- Wi-Fi SSID / PSK

そのため、クリーンクローン直後に必ずしも RAM boot を実行できるわけではありません。

公開 upstream source の取得には:

```powershell
& .\windows-native\Get-PinnedSources.ps1
```

を使用できます。

---

# 初回セットアップ

## 1. デバイス ECID を登録する

初回のみ、対象 A1625 の ECID を Windows のユーザー別設定へ保存します。

```powershell
& .\windows-native\Set-A1625DeviceConfig.ps1 `
  -ExpectedEcid '<16桁の16進ECID>'
```

ECID は `diagnose` や DFU 検出結果から確認します。

この値は対象個体を誤って操作しないための追加 identity gate として使われます。

---

## 2. DFU モードにする

Apple TV を DFU モードにして Windows に接続します。

復元スクリプトは、接続された DFU / PongoOS デバイスについて A1625 / T7000 と ECID の一致を確認してから処理を進めます。

---

## 3. 必要な場合だけ Zadig で libusbK を設定する

DFU または PongoOS の特定 USB instance に libusbK が必要な場合、復元スクリプトが停止して対象 instance を表示します。

対象 USB ID:

- DFU: `05AC:1227`
- PongoOS: `05AC:4141`

**通常の tvOS、Linux USB NCM、Linux USB ACM、他の Apple USB デバイスのドライバーを変更しないでください。**

変更前に元のドライバー provider / version / service / INF を記録してください。

戻し方:

[windows-native/DRIVER-ROLLBACK.md](windows-native/DRIVER-ROLLBACK.md)

---

# BootProfile

`Restore-A1625RamEnvironment.ps1` の `-BootProfile` では次を選択できます。

| BootProfile | 用途 | 通常利用 |
| --- | --- | --- |
| `baseline` | 標準の RAM-only Linux payload。USB NCM / SSH / Codex / 開発ツール用途の基本構成 | **推奨 / デフォルト** |
| `wifi-experimental` | Wi-Fi 開発初期段階の研究用 payload | 通常利用しない |
| `wifi-fw-lifetime` | Wi-Fi firmware lifecycle 検証段階の研究用 payload | 通常利用しない |
| `wifi-fw-response` | Wi-Fi firmware response 検証段階の研究用 payload | 通常利用しない |
| `wifi-t7000-table` | T7000 Wi-Fi 統合途中の検証用 payload | 通常利用しない |
| `wifi-t7000-leaf` | 現在の A1625 内蔵 Wi-Fi 実機検証に使用した payload | **Wi-Fi 利用時に使用** |

省略時:

```text
BootProfile = baseline
```

です。

したがって、

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot
```

は `baseline` で起動します。

Wi-Fi を使う場合は明示的に:

```powershell
-BootProfile wifi-t7000-leaf
```

を指定してください。

> `baseline` 以外の BootProfile は experimental boot として扱われます。既に Linux が起動している状態をその場で別 profile に置き換えるのではなく、fresh DFU / Pongo stage から起動してください。

---

# DevelopmentProfile

`-DevelopmentProfile` は RAM 上に追加するツール層を選択します。

| DevelopmentProfile | 内容 |
| --- | --- |
| `none` | 追加の開発ツール層なし |
| `minimal` | Git、OpenSSH client、CA bundle 等 |
| `development` | `minimal` に加え GCC / G++ / linker / make / file / patch / pkg-config 等 |

省略時:

```text
DevelopmentProfile = none
```

です。

通常の開発用途では:

```powershell
-DevelopmentProfile development
```

を推奨します。

開発ツールの詳細:

[windows-native/development-tools/README.md](windows-native/development-tools/README.md)

---

# Restore-A1625RamEnvironment.ps1 の引数

主要な起動・復元処理は:

```powershell
.\windows-native\Restore-A1625RamEnvironment.ps1
```

で行います。

| 引数 | 意味 |
| --- | --- |
| `-ConfirmRamBoot` | 一時的な RAM-only boot を実行することを明示的に確認します。実ブート時は必須です |
| `-BootProfile <name>` | 起動する kernel / payload を選択します。デフォルト `baseline` |
| `-ExpectedEcid <16hex>` | 対象 A1625 の ECID を明示指定します。省略時は保存済み device config を使用 |
| `-StageTimeoutSeconds <30-300>` | 各 boot stage の timeout。デフォルト 120 秒 |
| `-DevelopmentProfile none|minimal|development` | RAM 開発ツール層を選択 |
| `-EnableZram` | RAM-only zram swap を有効化 |
| `-RestoreRamState` | Windows に保存済みの RAM state snapshot を復元 |
| `-RamStateDirectory <path>` | RAM snapshot 保存先。デフォルト `%LOCALAPPDATA%\AppleTvA1625\ram-state` |
| `-StartCodex` | 復元完了後に Codex UI を起動 |
| `-EnterShell` | 復元完了後に対話 SSH shell を開く |
| `-ValidateOnly` | ローカル成果物と snapshot compatibility の事前検証だけを行い、USB transfer / network change を行わない |

`-StartCodex` と `-EnterShell` は同時指定できません。

また:

```text
-EnableZram
-RestoreRamState
```

は `DevelopmentProfile` が `minimal` または `development` の場合だけ使用できます。

---

# よく使う起動コマンド

## 最小の baseline 起動

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot
```

---

## baseline + 対話 shell

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -EnterShell
```

---

## 開発環境 + zram + shell

初回、まだ RAM snapshot がない場合:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -EnterShell
```

---

## 保存済み開発環境を復元

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState `
  -EnterShell
```

---

## Wi-Fi kernel + 開発環境

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram `
  -EnterShell
```

既に `wifi-t7000-leaf` と同じ payload / tool layer で作成した compatible snapshot がある場合のみ:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState `
  -EnterShell
```

---

# 起動時に何が行われるか

`Restore-A1625RamEnvironment.ps1` は概ね次の順序で処理します。

```text
ローカル成果物 SHA-256 検証
        ↓
ECID / A1625 identity gate
        ↓
DFU
        ↓
checkm8
        ↓
YOLO DFU
        ↓
PongoOS
        ↓
m1n1 + Linux + initramfs を RAM へ upload
        ↓
Linux USB composite device
        ├─ USB NCM
        └─ USB ACM
        ↓
Windows 側 USB NCM / NAT
        ↓
USB ACM から Dropbear host key を取得
        ↓
strict known_hosts を boot ごとに作成
        ↓
SSH health check
        ↓
Codex runtime
        ↓
DevelopmentProfile
        ↓
zram（指定時）
        ↓
RAM snapshot（指定時）
        ↓
Codex または shell
```

Linux health check では少なくとも:

- `aarch64`
- 4 KiB pages
- `/` が RAM rootfs
- zram 以外の internal block device が見えていないこと

を確認します。

---

# USB SSH

標準 USB NCM 側の Linux address:

```text
172.16.42.1
```

SSH user:

```text
root
```

port:

```text
22
```

認証は公開鍵のみです。

既定の Windows 側 private key:

```text
artifacts\ssh\a1625_ram_ed25519
```

Dropbear server host key は RAM boot ごとに生成されるため、`StrictHostKeyChecking=no` は使用しません。

復元スクリプトは USB ACM から host public key を取得・検証し、boot ごとの known_hosts を:

```text
%LOCALAPPDATA%\AppleTvA1625\state\known_hosts_ram_*
```

へ保存します。

---

# 対話 shell

復元後に直接 shell へ入る:

```powershell
& .\windows-native\Enter-A1625Shell.ps1
```

または起動と同時に:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -EnterShell
```

shell は PTY を割り当て、基本的に:

```text
root@172.16.42.1
```

へ接続します。

作業ディレクトリ:

```text
/run/work
```

Codex home:

```text
/run/codex-home
```

shell 内で:

```sh
codex-ram
```

を実行すると Codex UI を開始できます。

---

# zram

`-EnableZram` を指定すると、RAM 内に zram swap を作成します。

検証済み構成では:

- `/dev/zram0`
- 768 MiB logical swap
- priority 100
- zstd
- compressed allocation limit 256 MiB
- backing device なし

です。

swap も RAM 内のみで、内蔵ストレージへの writeback は設定しません。

使用例:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram
```

A1625 は約 2 GiB RAM のため、C/C++ build、Codex、大きな repository を扱う場合でもメモリ不足になる可能性があります。

---

# RAM state snapshot

電源を切ると RAM 上の内容は消えます。

作業を保持したい場合、電源断前に Windows へ snapshot を保存します。

デフォルト保存先:

```text
%LOCALAPPDATA%\AppleTvA1625\ram-state
```

保存内容は Windows CurrentUser DPAPI で暗号化されます。

---

## 保存対象

主な保存対象:

```text
/run/work
/run/codex-home/auth.json
/run/codex-home/config.toml
/run/codex-home/.gitconfig
/run/codex-home/.ssh/config
/run/codex-home/.ssh/known_hosts
/run/codex-home/.ssh/id_ed25519
/run/codex-home/.ssh/id_ed25519.pub
```

`/run/work` 内の `.git` や未 commit の regular files も対象です。

---

## 保存しないもの

例えば以下は snapshot に入りません。

- `/dev`
- `/proc`
- `/sys`
- `/etc`
- block device
- Dropbear server key
- `authorized_keys`
- internal storage
- APFS
- NVRAM

---

## baseline 開発環境を保存

作業を止めてから:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1
```

を実行します。

保存中は `/run/work` の編集や Codex command を停止してください。

---

# snapshot compatibility は重要

RAM snapshot は単なる `/run/work` のコピーではありません。

snapshot は少なくとも:

- boot payload
- development tool bundle
- installer/runtime
- schema
- 各 hash

との compatibility を検証します。

したがって:

```text
baseline
```

で作った snapshot を:

```text
wifi-t7000-leaf
```

へそのまま復元することはできません。

また:

```text
DevelopmentProfile minimal
```

と:

```text
DevelopmentProfile development
```

も別構成として扱ってください。

**BootProfile または DevelopmentProfile を変更したら、その構成用の新しい snapshot を作成してください。**

---

# Wi-Fi BootProfile で RAM state を保存する場合

`Save-A1625RamEnvironment.ps1` のデフォルト `PayloadPath` は baseline の:

```text
artifacts\hoolock\payload\m1n1-linux-a1625-minimal-ssh.bin
```

です。

`wifi-t7000-leaf` で起動した状態を保存する場合は、payload を明示します。

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1 `
  -DevelopmentProfile development `
  -PayloadPath .\artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-leaf.bin
```

次回は同じ構成で:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState
```

を使用します。

---

# Codex CLI

Codex CLI は A1625 の RAM rootfs 上で動作確認済みです。

通常の restore では Codex runtime が RAM 上へ復元されます。

直接 Codex を開始する場合:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -StartCodex
```

shell から開始する場合:

```sh
codex-ram
```

初回ログイン:

```powershell
& .\windows-native\codex-runtime\Install-CodexRamRuntime.ps1 -Login
```

認証情報を Codex 専用 state として Windows DPAPI へ保存:

```powershell
& .\windows-native\codex-state\Save-A1625CodexState.ps1
```

Codex の credential と RAM snapshot は別の保存機構です。

詳細:

[windows-native/codex-runtime/README.md](windows-native/codex-runtime/README.md)

[windows-native/codex-state/README.md](windows-native/codex-state/README.md)

---

# 内蔵 Wi-Fi

## 現在の対応状況

実機確認済み:

- Apple TV HD A1625 / J42d / T7000
- Broadcom BCM4350
- PCIe
- `wifi-t7000-leaf`
- Japan regulatory configuration
- WPA2-PSK
- AES / CCMP
- DHCP
- DNS
- HTTPS + CA verification
- Wi-Fi IP 宛て Dropbear SSH
- USB データ接続を抜いた後の SSH

未保証 / 非対応:

- WPA3
- 他国 regulatory configuration の検証
- 永続インストール
- boot 時の自動 Wi-Fi 起動
- 長時間連続運用の保証
- supervisor failure 後の完全自動復旧
- full RF calibration / regulatory certification

---

# Wi-Fi firmware

検証した firmware candidate:

```text
brcm/brcmfmac4350-pcie.bin
```

version:

```text
7.35.180.119
```

SHA-256:

```text
5691d1e0ceb70baf18efb7a0ec6cb84feb9edd2d0700c525b42930c4e7e4b845
```

この firmware binary はリポジトリには含めません。

個体固有 MAC、raw calibration、Apple 由来 firmware / NVRAM 等も commit しないでください。

別機種の NVRAM を流用したり、calibration conversion を推測して使用しないでください。

詳細:

[windows-native/wifi/README.md](windows-native/wifi/README.md)

---

# Wi-Fi userland の準備

Windows で:

```powershell
python .\windows-native\wifi\build_userland.py
```

offline cache を使う場合:

```powershell
python .\windows-native\wifi\build_userland.py --offline
```

生成先:

```text
artifacts\wifi-userland\reproduced\
```

WPA / curl / iw runtime bundle は pinned package hash により検証されます。

---

# Wi-Fi credential の保存

初回のみ:

```powershell
& .\windows-native\wifi\Set-A1625WifiProfile.ps1
```

SSID と WPA2 passphrase は hidden input です。

保存先:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi
```

Windows CurrentUser DPAPI で暗号化します。

現在の profile は:

```text
country=JP
WPA2-PSK
RSN
pairwise=CCMP
group=CCMP
```

を前提とします。

SSID / passphrase / PSK を command line、ログ、Git repository に残さないでください。

---

# Wi-Fi を使うための起動

まず Wi-Fi 対応 payload で fresh RAM boot します。

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram
```

`wifi-t7000-leaf` を指定するだけでは、Wi-Fi radio が自動的に常時起動するわけではありません。

現在の Wi-Fi は、PCI / DART / MSI / firmware lifetime を RAM 上の明示的な session として管理します。

そのため cold boot 後の最初の Wi-Fi session では:

[windows-native/wifi/session-workflow.md](windows-native/wifi/session-workflow.md)

に従って、必要な firmware / regulatory DB / module / runner / userland を RAM へ staging し、hardware hold を開始します。

hardware hold が開始済みであることの代表的な状態:

```text
/run/a1625-wifi/runner.pid
/sys/class/net/wlan0
```

---

# Connect-A1625Wifi.ps1

Wi-Fi hardware session が起動済みなら:

```powershell
& .\windows-native\wifi\Connect-A1625Wifi.ps1
```

で WPA / DHCP / WLAN Dropbear の状態を確認・開始します。

成功時は Wi-Fi IPv4 address を:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

へ保存します。

例:

```text
192.168.1.123
```

---

## Connect-A1625Wifi.ps1 と USB

この helper は最初に保存済み Wi-Fi IP を試します。

```text
last-address.txt
        ↓
Wi-Fi SSH が正常
        ↓
USB なしで完了
```

Wi-Fi が到達不能の場合は USB NCM:

```text
172.16.42.1
```

へ fallback します。

ただし重要な制約があります。

**Wi-Fi radio / hardware session 自体が停止している cold state から、USB も他の管理経路もない状態で Wi-Fi を新規起動することはできません。**

現在の構成では、cold boot 後の hardware initialization と firmware session の開始には既存の管理経路が必要です。

また `Connect-A1625Wifi.ps1` は PCI / DART / firmware hardware hold を勝手に再実行しません。

想定運用:

```text
fresh DFU boot
    ↓
USB NCM / ACM
    ↓
Wi-Fi hardware session を開始
    ↓
Connect-A1625Wifi.ps1
    ↓
WPA / DHCP / WLAN SSH
    ↓
Wi-Fi IP 保存
    ↓
USB データ接続を外す
    ↓
以後 Wi-Fi SSH
```

---

# Wi-Fi SSH

Wi-Fi 接続後は DHCP address の port 22 に別の Dropbear listener が起動します。

user:

```text
root
```

認証鍵は USB SSH と同じ RAM session の鍵を使用します。

host key verification では USB 側で既に検証した host key を:

```text
HostKeyAlias=172.16.42.1
```

として再利用します。

host key verification を無効化しないでください。

---

# Enter-A1625WifiShell.ps1

`Connect-A1625Wifi.ps1` が Wi-Fi IP を保存済みなら:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1
```

だけで Wi-Fi shell を開けます。

通常は `-Address` の手動指定は不要です。

必要な場合だけ上書き:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1 `
  -Address 192.168.1.123
```

保存 IP:

```text
%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt
```

shell は `/run/work` から開始します。

---

# USB を外して Wi-Fi を検証する

まず Wi-Fi 接続が正常であることを確認します。

USB データ接続を物理的に外した後:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 `
  -Address '192.168.1.123' `
  -KnownHostsPath '<current-boot-known-hosts-path>' `
  -RequireUsbDisconnected
```

この test は少なくとも:

- runner
- network supervisor
- DHCP client
- `wpa_state=COMPLETED`
- WPA2 / CCMP
- power save off
- DNS
- `wlan0` に bind した HTTPS
- TLS certificate verification
- strict host-key WLAN SSH
- Windows 側で対象 USB device が存在しないこと

を確認します。

---

# Wi-Fi session の停止

networking のみ停止:

```sh
kill -TERM "$(cat /run/a1625-wifi/network.pid)"
```

Wi-Fi hardware session も停止:

```sh
kill -TERM "$(cat /run/a1625-wifi/runner.pid)"
```

終了時は Wi-Fi route / DNS / process / PCI / DART / MSI / power resource が cleanup される設計です。

詳細な確認項目は:

[windows-native/wifi/session-workflow.md](windows-native/wifi/session-workflow.md)

を参照してください。

---

# Windows 側の保存場所

このプロジェクトでは用途ごとに state を分離しています。

| 内容 | デフォルト保存先 |
| --- | --- |
| device config / boot known_hosts / Codex state | `%LOCALAPPDATA%\AppleTvA1625\state` |
| RAM state snapshot | `%LOCALAPPDATA%\AppleTvA1625\ram-state` |
| Wi-Fi DPAPI profile | `%LOCALAPPDATA%\AppleTvA1625\wifi\japan.wifi.dpapi` |
| 最後に成功した Wi-Fi IP | `%LOCALAPPDATA%\AppleTvA1625\wifi\last-address.txt` |
| host-side logs | `%LOCALAPPDATA%\AppleTvA1625\logs` |

Wi-Fi IP 自体は credential ではありませんが、SSID、PSK、認証 token、private key、個体識別情報は公開しないでください。

---

# 事前検証だけ行う

USB transfer や network change を行わず、ローカル成果物・hash・snapshot compatibility を確認する場合:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -DevelopmentProfile development `
  -ValidateOnly
```

Wi-Fi payload:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 `
  -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -ValidateOnly
```

`-ValidateOnly` は実機 boot を開始しません。

---

# 診断

読み取り中心の診断:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\windows-native\atv-native.ps1 diagnose
```

USB 再列挙を 30 秒監視:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\windows-native\atv-native.ps1 watch `
  -TimeoutSeconds 30
```

現在の service-mode USB topology baseline:

```powershell
& .\windows-native\atv-native.ps1 baseline
```

self-contained tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\windows-native\tests\AtvNative.Tests.ps1
```

`baseline` command が作成する:

```text
windows-native/device-baseline.json
```

には private USB identity / topology が含まれる可能性があるため commit しないでください。

---

# よくあるトラブル

## `Enter-A1625WifiShell.ps1` が見つからない

ファイル名を確認します。

正しい名前:

```text
Enter-A1625WifiShell.ps1
```

確認:

```powershell
Get-ChildItem .\windows-native\wifi\Enter-A1625*
```

---

## `Connect-A1625Wifi.ps1` が USB なしで失敗する

USB なしで動作できるのは、既に WLAN session が生きており、保存済み Wi-Fi IP の Dropbear に到達できる場合です。

確認:

```powershell
Get-Content "$env:LOCALAPPDATA\AppleTvA1625\wifi\last-address.txt"
```

Wi-Fi session 自体が停止している場合、cold state からの起動には USB 等の管理経路が必要です。

---

## `RestoreRamState` で compatibility error

BootProfile または DevelopmentProfile が snapshot 作成時と異なる可能性があります。

特に:

```text
baseline
```

と:

```text
wifi-t7000-leaf
```

は別 payload です。

対応する構成で新しい snapshot を作成してください。

---

## `EnableZram` がエラーになる

`-EnableZram` には:

```powershell
-DevelopmentProfile minimal
```

または:

```powershell
-DevelopmentProfile development
```

が必要です。

例:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram
```

---

## `StartCodex` と `EnterShell` を両方指定した

どちらか一方だけ指定してください。

```powershell
-StartCodex
```

または:

```powershell
-EnterShell
```

---

## experimental BootProfile へ切り替えられない

`baseline` 以外の experimental profile は fresh DFU / Pongo stage を要求します。

既に Linux が起動している状態をその場で置き換えないでください。

---

## SSH host key mismatch

RAM boot ごとに Dropbear host key は新しくなります。

古い generic `known_hosts` を流用したり:

```text
StrictHostKeyChecking=no
```

に逃げないでください。

その boot で USB ACM から検証された:

```text
%LOCALAPPDATA%\AppleTvA1625\state\known_hosts_ram_*
```

を使用してください。

---

# セキュリティ境界

このプロジェクトでは次を重要な境界として扱います。

## Apple TV 内部ストレージ

RAM boot workflow は:

- internal block device をマウントしない
- APFS をマウントしない
- NVRAM を変更しない
- tvOS を restore / update しない
- fakefs を作成しない

ことを前提とします。

## SSH

- password login を使わない
- public-key authentication
- boot ごとの host key を ACM で検証
- strict host-key checking
- private key を repository に commit しない

## Wi-Fi credential

- Windows CurrentUser DPAPI
- plaintext temp file を作らない
- command-line argument に PSK を載せない
- SSH stdin 経由で RAM へ渡す
- `/run` 上の private file のみ
- Git repository へ保存しない

## RAM snapshot

- Windows CurrentUser DPAPI
- plaintext archive を Windows disk へ保存しない
- archive path / type / size を検証
- payload / runtime hash と compatibility を確認

---

# 電源断について

この Linux 環境は RAM-only です。

Apple TV の電源を切ると、RAM 上の:

- `/run/work`
- development tools
- zram
- Codex runtime
- Wi-Fi process
- Wi-Fi configuration file
- DHCP lease state
- Dropbear host key

等は消えます。

必要な作業状態は電源断前に:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1
```

で保存してください。

Wi-Fi BootProfile の場合は前述の通り `-PayloadPath` を合わせてください。

---

# 検証済み USB identity

対象:

```text
Apple TV HD
A1625
AppleTV5,3
J42d
T7000
```

確認済み:

```text
CPID = 0x7000
BDID = 34
```

USB:

```text
Normal mode  05AC:12A7
DFU          05AC:1227
PongoOS      05AC:4141
Linux gadget 05AC:4142
```

Linux USB NCM address:

```text
172.16.42.1/24
```

SSH:

```text
root@172.16.42.1:22
```

---

# リポジトリ内の主なドキュメント

| ドキュメント | 内容 |
| --- | --- |
| `README.ja.md` | 利用者向け総合ガイド |
| `windows-native/development-tools/README.md` | Git / GCC 等の RAM development layer |
| `windows-native/ram-state/README.md` | `/run/work` 等の保存・復元 |
| `windows-native/codex-runtime/README.md` | Codex runtime |
| `windows-native/codex-state/README.md` | Codex credential state |
| `windows-native/wifi/README.md` | BCM4350 / firmware / Wi-Fi 技術詳細 |
| `windows-native/wifi/session-workflow.md` | Wi-Fi session startup / cleanup |
| `windows-native/wifi/acceptance-2026-09-09.md` | Wi-Fi 実機 acceptance |
| `windows-native/DRIVER-ROLLBACK.md` | Zadig / libusbK の戻し方 |
| `windows-native/VALIDATION-ISSUES-3-4.md` | development / zram / RAM state 実機記録 |
| `THIRD_PARTY_NOTICES.md` | third-party provenance / notices |
| `SECURITY.md` | security policy |

---

# 推奨運用例

## USB 開発機として使う

初回:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -EnterShell
```

作業:

```sh
cd /run/work
```

終了前:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1
```

次回:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -DevelopmentProfile development `
  -EnableZram `
  -RestoreRamState `
  -EnterShell
```

---

## Wi-Fi 開発機として使う

Wi-Fi profile を一度作成:

```powershell
& .\windows-native\wifi\Set-A1625WifiProfile.ps1
```

fresh DFU boot:

```powershell
& .\windows-native\Restore-A1625RamEnvironment.ps1 -ConfirmRamBoot `
  -BootProfile wifi-t7000-leaf `
  -DevelopmentProfile development `
  -EnableZram
```

Wi-Fi hardware session を:

```text
windows-native/wifi/session-workflow.md
```

に従って開始します。

network 接続:

```powershell
& .\windows-native\wifi\Connect-A1625Wifi.ps1
```

Wi-Fi shell:

```powershell
& .\windows-native\wifi\Enter-A1625WifiShell.ps1
```

USB independence test:

```powershell
& .\windows-native\wifi\Test-A1625Wifi.ps1 `
  -Address (Get-Content "$env:LOCALAPPDATA\AppleTvA1625\wifi\last-address.txt").Trim() `
  -KnownHostsPath '<current-boot-known-hosts-path>' `
  -RequireUsbDisconnected
```

Wi-Fi payload 用 snapshot 保存:

```powershell
& .\windows-native\Save-A1625RamEnvironment.ps1 `
  -DevelopmentProfile development `
  -PayloadPath .\artifacts\hoolock\payload\m1n1-linux-a1625-wifi-t7000-leaf.bin
```

---

# Safety boundary

このプロジェクトは、所有または明示的に許可された A1625 に限定してください。

以下の操作は、この RAM-only workflow の範囲外です。

- tvOS restore
- erase
- update
- internal partition operation
- APFS write
- NVRAM write
- palera1n fakefs
- 他モデルへの一般化
- DFU entry の自動化

異常時に「直すため」として内部ストレージ操作へ切り替えないでください。

USB driver を変更した場合は、同じ instance の元のドライバーへ戻します。

---

# License / third-party software

このリポジトリのライセンスは [LICENSE](LICENSE) を参照してください。

third-party software、upstream source、firmware の provenance と license については:

[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

および各サブディレクトリの README を確認してください。

Apple、PongoOS、palera1n、Hoolock Linux、OpenAI Codex その他の名称は、それぞれの権利者に帰属します。この研究プロジェクトは、それらの各プロジェクトまたは企業による公式製品・公式サポートを意味するものではありません。
