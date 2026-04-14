# Phase 3: Chaincode 実装（Node.js / fabric-contract-api）

## T3-0 共通ユーティリティ
- `getTxTimestampISO(ctx)`: `ctx.stub.getTxTimestamp()` → ISO8601
  - 決定性確保、`Date.now()` 禁止
- `getActor(ctx)`: `ctx.clientIdentity.getMSPID()` / `getID()`
- エラー型統一

## T3-1 スキャフォールド
- `chaincode/product-trace/`
- package.json / index.js / Contract クラス

## T3-2 `CreateProduct`
- 重複チェック（`GetState` 空判定）
- `initialOwner === manufacturer` 検証
- `clientIdentity.MSPID === 'Org1MSP'` 検証（メーカー A のみ登録可能）
- `createdAt` / `updatedAt` は T3-0 経由

## T3-3 `TransferProduct`
- `fromOwner === currentOwner` 一致
- 呼び出し元 MSP と `fromOwner` 対応検証
- `currentOwner` / `updatedAt` 更新

## T3-4 `ReadProduct`
- 未登録時エラー

## T3-5 `GetHistory`
- `GetHistoryForKey` 使用
- state に `history` 配列を持たせない（二重管理排除）
- 時系列昇順整形
- `IsDelete` スキップ
- `txId` / `timestamp` は `keyModification` 由来

## T3-6 ユニットテスト（L1 主戦場）
- fabric-shim mock（`sinon-chai` / `chai-as-promised`）
- 配置: `chaincode/product-trace/test/`
- 実行: `npm test`
- 詳細: [test-strategy.md#L1](../test-strategy.md)
