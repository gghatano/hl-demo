'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext, makeHistoryIterator, makeHistoryEntry } = require('./helpers/mock-ctx');

// v2 GetHistory が SPLIT/MERGE/SPLIT_FROM/MERGE_FROM イベントを emit することを検証する。
// これらは state の snapshots (降順 iterator) から差分を判定する必要があるため、
// 直接 snapshot を構成して iterator に流し込むパターンで tests を組む。

describe('GetHistory v2 events', () => {
  let contract;
  beforeEach(() => {
    contract = new ProductTraceContract();
  });

  function snap(over = {}) {
    return {
      productId: 'X',
      manufacturer: 'Org1MSP',
      currentOwner: 'Org1MSP',
      status: 'ACTIVE',
      parents: [],
      children: [],
      metadata: {},
      millSheetHash: '',
      millSheetURI: '',
      lastActor: { mspId: 'Org1MSP', id: 'x509::CN=Admin@org1' },
      ...over,
    };
  }

  it('emits SPLIT (carve) event when parent stays ACTIVE and children are added', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });
    const entries = [
      // 新: 切り出し後 (ACTIVE のまま、children=[a,b,c])
      makeHistoryEntry({
        txId: 'tx-split',
        timestampISO: '2026-04-15T12:00:00.000Z',
        value: snap({
          productId: 'S1',
          currentOwner: 'Org3MSP',
          status: 'ACTIVE',
          children: ['a', 'b', 'c'],
          lastActor: { mspId: 'Org3MSP', id: 'x509::CN=Admin@org3' },
        }),
      }),
      // 中: Transfer to Org3 (children 未追加)
      makeHistoryEntry({
        txId: 'tx-transfer',
        timestampISO: '2026-04-15T11:00:00.000Z',
        value: snap({
          productId: 'S1',
          currentOwner: 'Org3MSP',
          lastActor: { mspId: 'Org1MSP', id: 'x509::CN=Admin@org1' },
        }),
      }),
      // 旧: CREATE
      makeHistoryEntry({
        txId: 'tx-create',
        timestampISO: '2026-04-15T10:00:00.000Z',
        value: snap({ productId: 'S1' }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'S1'));
    expect(events.map((e) => e.eventType)).to.deep.equal(['CREATE', 'TRANSFER', 'SPLIT']);
    const splitEv = events[2];
    expect(splitEv.children).to.deep.equal(['a', 'b', 'c']);
    expect(splitEv.fromOwner).to.equal('Org3MSP');
    expect(splitEv.toOwner).to.equal('Org3MSP');
  });

  it('emits SPLIT for each carve round (cumulative children, only new ones reported)', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });
    const entries = [
      // 2 回目の切り出し後: children=[a,b,c]
      makeHistoryEntry({
        txId: 'tx-split-2',
        timestampISO: '2026-04-15T13:00:00.000Z',
        value: snap({ productId: 'S1', currentOwner: 'Org3MSP', children: ['a', 'b', 'c'] }),
      }),
      // 1 回目の切り出し後: children=[a,b]
      makeHistoryEntry({
        txId: 'tx-split-1',
        timestampISO: '2026-04-15T12:00:00.000Z',
        value: snap({ productId: 'S1', currentOwner: 'Org3MSP', children: ['a', 'b'] }),
      }),
      // CREATE
      makeHistoryEntry({
        txId: 'tx-create',
        timestampISO: '2026-04-15T10:00:00.000Z',
        value: snap({ productId: 'S1', currentOwner: 'Org3MSP' }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'S1'));
    expect(events.map((e) => e.eventType)).to.deep.equal(['CREATE', 'SPLIT', 'SPLIT']);
    expect(events[1].children).to.deep.equal(['a', 'b']);   // 1 回目は a,b 追加
    expect(events[2].children).to.deep.equal(['c']);         // 2 回目は c のみ追加
  });

  it('emits MERGE event when parent transitions ACTIVE -> CONSUMED with exactly 1 child', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });
    const entries = [
      makeHistoryEntry({
        txId: 'tx-merge',
        timestampISO: '2026-04-15T12:00:00.000Z',
        value: snap({
          productId: 'S1',
          currentOwner: 'Org3MSP',
          status: 'CONSUMED',
          children: ['P1'],
        }),
      }),
      makeHistoryEntry({
        txId: 'tx-create',
        timestampISO: '2026-04-15T10:00:00.000Z',
        value: snap({ productId: 'S1', currentOwner: 'Org3MSP' }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'S1'));
    expect(events.map((e) => e.eventType)).to.deep.equal(['CREATE', 'MERGE']);
    expect(events[1].children).to.deep.equal(['P1']);
  });

  it('emits SPLIT_FROM as first event for a split-derived child', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });
    const entries = [
      makeHistoryEntry({
        txId: 'tx-split-create',
        timestampISO: '2026-04-15T11:00:00.000Z',
        value: snap({
          productId: 'S1-a',
          currentOwner: 'Org3MSP',
          parents: ['S1'],
          lastActor: { mspId: 'Org3MSP', id: 'x509::CN=Admin@org3' },
        }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'S1-a'));
    expect(events).to.have.length(1);
    expect(events[0].eventType).to.equal('SPLIT_FROM');
    expect(events[0].parents).to.deep.equal(['S1']);
    expect(events[0].toOwner).to.equal('Org3MSP');
  });

  it('emits MERGE_FROM as first event for a merge-derived child', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });
    const entries = [
      makeHistoryEntry({
        txId: 'tx-merge-create',
        timestampISO: '2026-04-15T11:00:00.000Z',
        value: snap({
          productId: 'P1',
          manufacturer: 'Org3MSP',
          currentOwner: 'Org3MSP',
          parents: ['S1', 'S2'],
          lastActor: { mspId: 'Org3MSP', id: 'x509::CN=Admin@org3' },
        }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'P1'));
    expect(events).to.have.length(1);
    expect(events[0].eventType).to.equal('MERGE_FROM');
    expect(events[0].parents).to.deep.equal(['S1', 'S2']);
  });

  it('emits TRANSFER after SPLIT_FROM when child is transferred', async () => {
    const ctx = createMockContext({ mspId: 'Org5MSP' });
    const entries = [
      // 新: transfer to Org5
      makeHistoryEntry({
        txId: 'tx-xfer',
        timestampISO: '2026-04-15T12:00:00.000Z',
        value: snap({
          productId: 'S1-a',
          currentOwner: 'Org5MSP',
          parents: ['S1'],
          lastActor: { mspId: 'Org3MSP', id: 'x509::CN=Admin@org3' },
        }),
      }),
      // 旧: SPLIT_FROM
      makeHistoryEntry({
        txId: 'tx-split-create',
        timestampISO: '2026-04-15T11:00:00.000Z',
        value: snap({
          productId: 'S1-a',
          currentOwner: 'Org3MSP',
          parents: ['S1'],
        }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'S1-a'));
    expect(events.map((e) => e.eventType)).to.deep.equal(['SPLIT_FROM', 'TRANSFER']);
    expect(events[1].fromOwner).to.equal('Org3MSP');
    expect(events[1].toOwner).to.equal('Org5MSP');
  });
});
