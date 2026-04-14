# test-network-wrapper

`fabric-samples/test-network` を 3Org 構成へ拡張するラッパー。

## 構成

```
fabric/
  fabric-samples/       # scripts/setup.sh で clone（.gitignore 対象）
  test-network-wrapper/
    README.md           # 本ファイル
    patches/            # 3Org 化の差分（Phase 2 で追加）
```

## 方針
- `fabric-samples` は tag 固定 clone（`docs/prerequisites.md`）
- オリジナルに手を入れない
- 3Org 化の差分は `patches/` 配下に版管理
- Phase 2 の `scripts/network_up.sh` が patch 適用 → ネットワーク起動

## Phase 1 時点
patches/ は空。Phase 2 で埋める。
