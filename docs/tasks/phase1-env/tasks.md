# Phase 1: 環境準備

## T1-1 前提ソフト バージョン固定
- Fabric 2.5.x / Node.js 18 / Docker 24+ / Compose v2 / Go
- README §前提 記載

## T1-2 fabric-samples 取得
- tag/commit 固定
- `fabric/test-network-wrapper/` 配置
- `install-fabric.sh` 直叩き回避 → 固定tag をscriptsから呼ぶ

## T1-3 `scripts/setup.sh`
- `set -euo pipefail`
- 既存 bin/ / network 検出 skip、`--force` 再導入
- 冪等性（2回目実行OK）
