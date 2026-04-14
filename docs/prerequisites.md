# 前提環境

Phase 6 で README 統合予定。Phase 1 時点の暫定仕様。

## 動作環境
- OS: Ubuntu 22.04 LTS（WSL2 可）
- CPU: 2 core 以上
- RAM: 8 GB 以上（WSL2 は `.wslconfig` で確保）
- Disk: 10 GB 以上空き

## 必須ソフトウェア

| ソフト | 推奨バージョン | 備考 |
|---|---|---|
| Docker | 24.x 以上 | `docker --version` |
| Docker Compose | v2.x | `docker compose version`（旧 `docker-compose` 非推奨） |
| curl | 任意 | setup で使用 |
| git | 2.30+ | fabric-samples clone |
| jq | 1.6+ | 出力整形 / テスト assert |
| bash | 5.x | スクリプト実行 |
| Node.js | 18.x LTS | chaincode ビルド / テスト |
| npm | 9+ | Node.js 18 同梱 |
| iproute2 | 5.x+ | `ss` コマンド（ポート衝突検知） |
| Go | 1.21+（任意） | Node.js chaincode 方針だが、fabric-samples 付属の Go サンプル利用時のみ |

## Fabric バージョン（固定）

| 項目 | バージョン |
|---|---|
| Fabric | 2.5.10 |
| Fabric CA | 1.5.13 |
| fabric-samples commit | `bf7e75c6c159dc1959f3bb8979ed739171673b4d` (main) |

注: fabric-samples は v2.4.9 以降 tag 運用が廃止されており、main ブランチの commit を固定する方針。

変更時は `scripts/setup.sh` 先頭の変数 3 つを更新。最新 main commit 取得:
```bash
git ls-remote https://github.com/hyperledger/fabric-samples.git refs/heads/main
```

## WSL2 注意

`.wslconfig`（Windows ユーザーホーム直下）:
```ini
[wsl2]
memory=8GB
processors=4
```
変更後 `wsl --shutdown` で再起動。

### WSL2 追加注意
- **Docker Desktop 連携必須**: Linux 側直接 daemon を起動すると Windows 側 image と共有不可
- **cgroup v2**: Ubuntu 22.04 WSL2 は v2 既定。Fabric 2.5 は対応済だが、古い Docker（<20.10）で v2 + chaincode 起動失敗事例あり
- **iptables**: WSL2 で iptables-legacy / nftables 混在時 peer コンテナ間通信が詰まる事例。`update-alternatives --config iptables` で legacy 固定推奨

## setup.sh 冪等性
- 2 回目実行は既存 fabric-samples / bin を検知して skip（数秒で完了）
- tag 不一致時は安全のため停止 → `./scripts/setup.sh --force` で再取得

## ポート使用

| ポート | 用途 |
|---|---|
| 7050 | Orderer |
| 7051 | peer0.orgA |
| 9051 | peer0.orgB |
| 11051 | peer0.orgC |
| 7054 | CA orgA |
| 8054 | CA orgB |
| 9054 | CA orgC |

他アプリで占有中の場合 `setup.sh` 冒頭で警告。
