'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext } = require('./helpers/mock-ctx');

function parseStored(ctx, id) {
  return JSON.parse(ctx.stub._store.get(id).toString());
}

describe('SplitProduct', () => {
  let contract;
  let store;

  beforeEach(() => {
    contract = new ProductTraceContract();
    store = new Map();
  });

  async function seedActiveParent(parentId = 'S1', ownerMsp = 'Org3MSP') {
    // CreateProduct via Org1MSP, then TransferProduct to ownerMsp
    const ctxCreate = createMockContext({ mspId: 'Org1MSP', store, txTimestampISO: '2026-04-15T10:00:00.000Z' });
    await contract.CreateProduct(ctxCreate, parentId, 'Org1MSP', 'Org1MSP', '{"grade":"SS400"}');
    if (ownerMsp !== 'Org1MSP') {
      const ctxTransfer = createMockContext({ mspId: 'Org1MSP', store, txTimestampISO: '2026-04-15T10:05:00.000Z' });
      await contract.TransferProduct(ctxTransfer, parentId, 'Org1MSP', ownerMsp);
    }
  }

  it('carves children out of parent; parent stays ACTIVE and records children', async () => {
    await seedActiveParent('S1', 'Org3MSP');

    const ctxSplit = createMockContext({ mspId: 'Org3MSP', store, txTimestampISO: '2026-04-15T11:00:00.000Z', identityId: 'x509::CN=Admin@org3' });
    const childrenJson = JSON.stringify([
      { childId: 'S1-a', toOwner: 'Org3MSP', metadataJson: '{"weightKg":3000}' },
      { childId: 'S1-b', toOwner: 'Org5MSP', metadataJson: '{"weightKg":3000}' },
      { childId: 'S1-c', toOwner: 'Org3MSP', metadataJson: '{"weightKg":4000}' },
    ]);
    const result = JSON.parse(await contract.SplitProduct(ctxSplit, 'S1', childrenJson));

    // parent: ACTIVE のまま、children が記録される
    const parentStored = parseStored(ctxSplit, 'S1');
    expect(parentStored.status).to.equal('ACTIVE');
    expect(parentStored.children).to.deep.equal(['S1-a', 'S1-b', 'S1-c']);
    expect(parentStored.currentOwner).to.equal('Org3MSP');
    expect(parentStored.lastActor.mspId).to.equal('Org3MSP');
    expect(parentStored.updatedAt).to.equal('2026-04-15T11:00:00.000Z');

    // children verification
    for (const childId of ['S1-a', 'S1-b', 'S1-c']) {
      const child = parseStored(ctxSplit, childId);
      expect(child.status).to.equal('ACTIVE');
      expect(child.parents).to.deep.equal(['S1']);
      expect(child.manufacturer).to.equal('Org1MSP'); // 継承
      expect(child.children).to.deep.equal([]);
      expect(child.createdAt).to.equal('2026-04-15T11:00:00.000Z');
      expect(child.lastActor.mspId).to.equal('Org3MSP');
    }
    expect(parseStored(ctxSplit, 'S1-a').currentOwner).to.equal('Org3MSP');
    expect(parseStored(ctxSplit, 'S1-b').currentOwner).to.equal('Org5MSP');
    expect(parseStored(ctxSplit, 'S1-c').currentOwner).to.equal('Org3MSP');

    // return value sanity
    expect(result.parent.status).to.equal('ACTIVE');
    expect(result.children).to.have.length(3);
  });

  it('allows carving a single child (N=1)', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    const result = JSON.parse(await contract.SplitProduct(ctx, 'S1',
      JSON.stringify([{ childId: 'S1-a', toOwner: 'Org3MSP' }])
    ));
    expect(result.children).to.have.length(1);
    expect(parseStored(ctx, 'S1').status).to.equal('ACTIVE');
    expect(parseStored(ctx, 'S1').children).to.deep.equal(['S1-a']);
  });

  it('allows multiple rounds of carving from the same parent', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx1 = createMockContext({ mspId: 'Org3MSP', store });
    await contract.SplitProduct(ctx1, 'S1', JSON.stringify([
      { childId: 'S1-a', toOwner: 'Org3MSP' },
      { childId: 'S1-b', toOwner: 'Org3MSP' },
    ]));
    // 2 回目の切り出し (S1 はまだ ACTIVE)
    const ctx2 = createMockContext({ mspId: 'Org3MSP', store });
    await contract.SplitProduct(ctx2, 'S1', JSON.stringify([
      { childId: 'S1-c', toOwner: 'Org5MSP' },
    ]));
    const parent = parseStored(ctx2, 'S1');
    expect(parent.status).to.equal('ACTIVE');
    expect(parent.children).to.deep.equal(['S1-a', 'S1-b', 'S1-c']); // cumulative, sorted
  });

  it('sorts parent.children lexicographically (deterministic)', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctxSplit = createMockContext({ mspId: 'Org3MSP', store });
    const childrenJson = JSON.stringify([
      { childId: 'zeta', toOwner: 'Org3MSP' },
      { childId: 'alpha', toOwner: 'Org3MSP' },
      { childId: 'mike', toOwner: 'Org3MSP' },
    ]);
    await contract.SplitProduct(ctxSplit, 'S1', childrenJson);
    const parent = parseStored(ctxSplit, 'S1');
    expect(parent.children).to.deep.equal(['alpha', 'mike', 'zeta']);
  });

  it('rejects when parent does not exist', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    const childrenJson = JSON.stringify([
      { childId: 'A', toOwner: 'Org3MSP' },
      { childId: 'B', toOwner: 'Org3MSP' },
    ]);
    await expect(contract.SplitProduct(ctx, 'GHOST', childrenJson))
      .to.be.rejectedWith(/PRODUCT_NOT_FOUND/);
  });

  it('rejects when parent is CONSUMED (from a Merge)', async () => {
    // CONSUMED に遷移するのは Merge のみ。切り出しを何回やっても ACTIVE。
    // 2 素材を作り、Merge で親を CONSUMED にしてから Split を試みる。
    const ctxCreate1 = createMockContext({ mspId: 'Org1MSP', store });
    await contract.CreateProduct(ctxCreate1, 'P1', 'Org1MSP', 'Org1MSP', '', '', '');
    const ctxCreate2 = createMockContext({ mspId: 'Org2MSP', store });
    await contract.CreateProduct(ctxCreate2, 'P2', 'Org2MSP', 'Org2MSP', '', '', '');
    const ctxXfer1 = createMockContext({ mspId: 'Org1MSP', store });
    await contract.TransferProduct(ctxXfer1, 'P1', 'Org1MSP', 'Org3MSP');
    const ctxXfer2 = createMockContext({ mspId: 'Org2MSP', store });
    await contract.TransferProduct(ctxXfer2, 'P2', 'Org2MSP', 'Org3MSP');
    const ctxMerge = createMockContext({ mspId: 'Org3MSP', store });
    await contract.MergeProducts(ctxMerge, JSON.stringify(['P1', 'P2']), JSON.stringify({ childId: 'CHILD' }));
    // P1 は CONSUMED (Merge 由来)
    const ctxBad = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctxBad, 'P1', JSON.stringify([
      { childId: 'X', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/PARENT_NOT_ACTIVE/);
  });

  it('rejects when caller is not parent.currentOwner', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org4MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([
      { childId: 'S1-a', toOwner: 'Org3MSP' },
      { childId: 'S1-b', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/MSP_NOT_AUTHORIZED/);
  });

  it('rejects empty children array', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([])))
      .to.be.rejectedWith(/at least 1/);
  });

  it('rejects duplicate childId in request', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([
      { childId: 'S1-a', toOwner: 'Org3MSP' },
      { childId: 'S1-a', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/CHILD_ALREADY_EXISTS/);
  });

  it('rejects childId that equals parentId', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([
      { childId: 'S1', toOwner: 'Org3MSP' },
      { childId: 'S1-b', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/CHILD_ALREADY_EXISTS/);
  });

  it('rejects childId that already exists in state', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    // seed another product
    const ctxSeed = createMockContext({ mspId: 'Org1MSP', store, txTimestampISO: '2026-04-15T09:00:00.000Z' });
    await contract.CreateProduct(ctxSeed, 'X999', 'Org1MSP', 'Org1MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([
      { childId: 'X999', toOwner: 'Org3MSP' },
      { childId: 'Y', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/CHILD_ALREADY_EXISTS/);
  });

  it('rejects invalid toOwner MSP', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([
      { childId: 'a', toOwner: 'BogusMSP' },
      { childId: 'b', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/toOwner is not a valid MSP/);
  });

  it('rejects invalid metadata JSON', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', JSON.stringify([
      { childId: 'a', toOwner: 'Org3MSP', metadataJson: '{not-json' },
      { childId: 'b', toOwner: 'Org3MSP' },
    ]))).to.be.rejectedWith(/INVALID_METADATA/);
  });

  it('rejects malformed childrenJson', async () => {
    await seedActiveParent('S1', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.SplitProduct(ctx, 'S1', 'not-json'))
      .to.be.rejectedWith(/not valid JSON/);
  });
});
