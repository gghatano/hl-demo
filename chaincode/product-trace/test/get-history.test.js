'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext, makeHistoryIterator, makeHistoryEntry } = require('./helpers/mock-ctx');

describe('GetHistory', () => {
  let contract;
  beforeEach(() => {
    contract = new ProductTraceContract();
  });

  function buildProductState({ owner, createdAt, updatedAt, lastActor }) {
    return {
      productId: 'X001',
      manufacturer: 'Org1MSP',
      currentOwner: owner,
      status: 'ACTIVE',
      createdAt,
      updatedAt,
      lastActor: lastActor || { mspId: owner, id: `x509::CN=Admin@${owner}` },
    };
  }

  it('returns chronological CREATE + TRANSFER events (A->B->C)', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });

    // GetHistoryForKey は一般に降順（新→旧）で返るため、tests でも同じ順で渡す
    const entries = [
      // 新: B -> C
      makeHistoryEntry({
        txId: 'tx-c',
        timestampISO: '2026-04-15T12:00:00.000Z',
        value: buildProductState({
          owner: 'Org3MSP',
          createdAt: '2026-04-15T10:00:00.000Z',
          updatedAt: '2026-04-15T12:00:00.000Z',
        }),
      }),
      // 中: A -> B
      makeHistoryEntry({
        txId: 'tx-b',
        timestampISO: '2026-04-15T11:00:00.000Z',
        value: buildProductState({
          owner: 'Org2MSP',
          createdAt: '2026-04-15T10:00:00.000Z',
          updatedAt: '2026-04-15T11:00:00.000Z',
        }),
      }),
      // 旧: CREATE by A
      makeHistoryEntry({
        txId: 'tx-a',
        timestampISO: '2026-04-15T10:00:00.000Z',
        value: buildProductState({
          owner: 'Org1MSP',
          createdAt: '2026-04-15T10:00:00.000Z',
          updatedAt: '2026-04-15T10:00:00.000Z',
        }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));

    const result = await contract.GetHistory(ctx, 'X001');
    const events = JSON.parse(result);

    expect(events).to.have.length(3);
    expect(events[0]).to.include({
      eventType: 'CREATE',
      fromOwner: null,
      toOwner: 'Org1MSP',
      txId: 'tx-a',
      timestamp: '2026-04-15T10:00:00.000Z',
    });
    expect(events[0].actor).to.deep.equal({ mspId: 'Org1MSP', id: 'x509::CN=Admin@Org1MSP' });
    expect(events[1]).to.include({
      eventType: 'TRANSFER',
      fromOwner: 'Org1MSP',
      toOwner: 'Org2MSP',
      txId: 'tx-b',
      timestamp: '2026-04-15T11:00:00.000Z',
    });
    expect(events[1].actor).to.deep.equal({ mspId: 'Org2MSP', id: 'x509::CN=Admin@Org2MSP' });
    expect(events[2]).to.include({
      eventType: 'TRANSFER',
      fromOwner: 'Org2MSP',
      toOwner: 'Org3MSP',
      txId: 'tx-c',
      timestamp: '2026-04-15T12:00:00.000Z',
    });
    expect(events[2].actor).to.deep.equal({ mspId: 'Org3MSP', id: 'x509::CN=Admin@Org3MSP' });
  });

  it('treats first non-delete entry as CREATE even if preceded by isDelete', async () => {
    // iterator は降順（新→旧）。reverse 後、先頭が tx-del（isDelete）で次が tx-create になるよう配置
    // → 先頭 isDelete がスキップされ、events.length === 0 判定で tx-create が CREATE になる
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const entries = [
      makeHistoryEntry({
        txId: 'tx-create',
        timestampISO: '2026-04-15T11:00:00.000Z',
        value: buildProductState({
          owner: 'Org1MSP',
          createdAt: '2026-04-15T11:00:00.000Z',
          updatedAt: '2026-04-15T11:00:00.000Z',
        }),
      }),
      makeHistoryEntry({
        txId: 'tx-del',
        timestampISO: '2026-04-15T10:00:00.000Z',
        isDelete: true,
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const events = JSON.parse(await contract.GetHistory(ctx, 'X001'));
    expect(events).to.have.length(1);
    expect(events[0].eventType).to.equal('CREATE');
    expect(events[0].txId).to.equal('tx-create');
  });

  it('skips isDelete entries', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const entries = [
      makeHistoryEntry({
        txId: 'tx-del',
        timestampISO: '2026-04-15T11:00:00.000Z',
        isDelete: true,
      }),
      makeHistoryEntry({
        txId: 'tx-a',
        timestampISO: '2026-04-15T10:00:00.000Z',
        value: buildProductState({
          owner: 'Org1MSP',
          createdAt: '2026-04-15T10:00:00.000Z',
          updatedAt: '2026-04-15T10:00:00.000Z',
        }),
      }),
    ];
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator(entries));
    const result = await contract.GetHistory(ctx, 'X001');
    const events = JSON.parse(result);
    expect(events).to.have.length(1);
    expect(events[0].eventType).to.equal('CREATE');
  });

  it('returns empty array when key has no history', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    ctx.stub.getHistoryForKey.resolves(makeHistoryIterator([]));
    const result = await contract.GetHistory(ctx, 'X001');
    expect(JSON.parse(result)).to.deep.equal([]);
  });

  it('rejects missing productId', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(contract.GetHistory(ctx, '')).to.be.rejectedWith(/required/);
  });
});
