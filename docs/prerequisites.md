# 前提環境

## 動作環境

- OS: Ubuntu 22.04 LTS（WSL2 可）/ macOS (Apple Silicon, Colima 経由)
- CPU: 2 core 以上（4 core 推奨）
- RAM: 8 GB 以上（WSL2 は `.wslconfig` / Colima は `--memory 6` 以上）
- Disk: 10 GB 以上空き（Colima は `--disk 30` 推奨）

一次サポートは Linux。macOS は Colima 利用を前提に動作確認済み（詳細後述）。

## 必須ソフトウェア

| ツール | バージョン | 備考 |
|---|---|---|
| Docker | **29+** | `docker compose v2` 必須 |
| Node.js | 18 LTS | chaincode ビルド / L1 テスト |
| jq | 1.6+ | スクリプト全般で JSON 整形に使用 |
| git | 任意 | fabric-samples 取得に使用 |
| bash | 3.2+ | scripts は macOS bash 3.2 互換で書いてある |
| curl | 任意 | setup.sh で使用 |

## Fabric バージョン（固定）

| 項目 | バージョン |
|---|---|
| Fabric | **2.5.15** |
| Fabric CA | **1.5.18** |
| fabric-samples commit | pin 済（`scripts/setup.sh` 先頭で定義） |

> Docker 29+ との互換性のため Fabric 2.5.15 以上が必須。詳細は [`fabric-pitfalls.md`](fabric-pitfalls.md) 参照。

## クリーン Ubuntu 22.04 からの導入コマンド例

```bash
# 基本ツール
sudo apt-get update
sudo apt-get install -y curl git jq ca-certificates gnupg lsb-release

# Docker CE + compose v2（公式 apt repo）
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"   # ← 再ログイン or `newgrp docker`

# Node.js 18 LTS（NodeSource）
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# バージョン確認
docker --version && docker compose version && node --version && jq --version
```

Docker 操作は **sudo 不要** にしておくこと:

```bash
sudo usermod -aG docker "$USER"   # → 再ログイン
# または未反映シェルで一時的に:
sg docker -c './scripts/network_up.sh'
```

## macOS (Apple Silicon) 手順

**Docker Desktop は避け、Colima を使う**。Docker Desktop は container の `/var/run/docker.sock` bind-mount を socket proxy に差し替える仕組みが Fabric の chaincode ビルドと非互換で、`No such image: hyperledger/fabric-nodeenv:2.5` で install が落ちる（詳細 [`fabric-pitfalls.md`](fabric-pitfalls.md)）。

```bash
# Homebrew（未導入なら https://brew.sh 参照）
brew install colima docker docker-compose jq node

# Docker CLI プラグイン（docker compose）が ~/.docker/cli-plugins に無ければ brew 導入分で揃う
brew install docker-compose

# Colima VM 起動（初回のみ 1-2 分）
colima start --cpu 4 --memory 6 --disk 30

# context 確認（colima * がアクティブであること）
docker context ls
docker context use colima

# 動作確認
docker --version && docker compose version && node --version && jq --version

# 以降は Linux 手順と同じ
./scripts/setup.sh
./scripts/network_up.sh
./scripts/deploy_chaincode.sh
```

運用:

| 操作 | コマンド |
|---|---|
| 停止 | `colima stop` |
| 起動（前回設定 resume） | `colima start` |
| リソース変更 | `colima stop && colima start --cpu 6 --memory 8` |
| 完全削除（VM ごと）| `colima delete` |

Docker Desktop と Colima は **同時起動しない**。context が混乱するので使う方だけ起動する。

## WSL2 注意

`.wslconfig`（Windows ユーザーホーム直下 `%USERPROFILE%\.wslconfig`）:

```ini
[wsl2]
memory=8GB
processors=4
```

変更後 `wsl --shutdown` で再起動。

### docker グループ加入（推奨）

```sh
sudo usermod -aG docker $USER
# 反映のため一度ログアウト → ログインし直す
```

- 未加入だと `./scripts/reset.sh` / `./scripts/network_up.sh` を **sudo で実行せざるを得ない**
- sudo 実行すると `fabric-samples/test-network/organizations/` が **root 所有** で生成され、次回 git 操作が "Permission denied" で詰まる（[`fabric-pitfalls.md`](fabric-pitfalls.md) 参照）

### WSL2 追加注意

- **Docker Desktop 連携必須**: Linux 側直接 daemon を起動すると Windows 側 image と共有不可
- **cgroup v2**: Ubuntu 22.04 WSL2 は v2 既定。Fabric 2.5 は対応済だが、古い Docker（<20.10）で v2 + chaincode 起動失敗事例あり
- **iptables**: WSL2 で iptables-legacy / nftables 混在時 peer コンテナ間通信が詰まる事例。`update-alternatives --config iptables` で legacy 固定推奨

## ポート使用

| ポート | 用途 |
|---|---|
| 7050 | Orderer |
| 7051 | peer0.org1 (メーカー A) |
| 9051 | peer0.org2 (卸 B) |
| 11051 | peer0.org3 (販売店 C) |
| 7054 | CA org1 |
| 8054 | CA org2 |
| 9054 | CA org3 |

他アプリで占有中の場合 `setup.sh` 冒頭で警告。

## setup.sh 冪等性

- 2 回目実行は既存 fabric-samples / bin を検知して skip（数秒で完了）
- tag 不一致時は安全のため停止 → `./scripts/setup.sh --force` で再取得
