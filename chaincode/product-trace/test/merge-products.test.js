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

describe('MergeProducts', () => {
  let contract;
  let store;

  beforeEach(() => {
    contract = new ProductTraceContract();
    store = new Map();
  });

  async function seedMaterial(productId, manufMsp, destOwner) {
    const ctxCreate = createMockContext({ mspId: manufMsp, store, txTimestampISO: '2026-04-15T10:00:00.000Z' });
    await contract.CreateProduct(ctxCreate, productId, manufMsp, manufMsp);
    if (destOwner && destOwner !== manufMsp) {
      const ctxTransfer = createMockContext({ mspId: manufMsp, store, txTimestampISO: '2026-04-15T10:05:00.000Z' });
      await contract.TransferProduct(ctxTransfer, productId, manufMsp, destOwner);
    }
  }

  it('merges 2 parents into 1 child, marks parents CONSUMED, sets child.parents sorted', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    await seedMaterial('S2', 'Org2MSP', 'Org3MSP');

    const ctxMerge = createMockContext({ mspId: 'Org3MSP', store, txTimestampISO: '2026-04-15T11:00:00.000Z', identityId: 'x509::CN=Admin@org3' });
    const parentIdsJson = JSON.stringify(['S2', 'S1']); // 逆順で渡して sort 検証
    const childJson = JSON.stringify({ childId: 'P1', metadataJson: '{"type":"welded"}' });
    const result = JSON.parse(await contract.MergeProducts(ctxMerge, parentIdsJson, childJson));

    // parents all CONSUMED
    const s1 = parseStored(ctxMerge, 'S1');
    const s2 = parseStored(ctxMerge, 'S2');
    expect(s1.status).to.equal('CONSUMED');
    expect(s2.status).to.equal('CONSUMED');
    expect(s1.children).to.deep.equal(['P1']);
    expect(s2.children).to.deep.equal(['P1']);

    // child correct
    const p1 = parseStored(ctxMerge, 'P1');
    expect(p1.status).to.equal('ACTIVE');
    expect(p1.parents).to.deep.equal(['S1', 'S2']); // sorted
    expect(p1.manufacturer).to.equal('Org3MSP'); // caller
    expect(p1.currentOwner).to.equal('Org3MSP');
    expect(p1.children).to.deep.equal([]);
    expect(p1.metadata).to.deep.equal({ type: 'welded' });

    // return value
    expect(result.parents).to.have.length(2);
    expect(result.child.productId).to.equal('P1');
  });

  it('merges 3 parents into 1 child', async () => {
    await seedMaterial('A', 'Org1MSP', 'Org4MSP');
    await seedMaterial('B', 'Org2MSP', 'Org4MSP');
    await seedMaterial('C', 'Org1MSP', 'Org4MSP');
    const ctx = createMockContext({ mspId: 'Org4MSP', store });
    await contract.MergeProducts(ctx, JSON.stringify(['C', 'A', 'B']), JSON.stringify({ childId: 'Q' }));
    const q = parseStored(ctx, 'Q');
    expect(q.parents).to.deep.equal(['A', 'B', 'C']);
  });

  it('rejects parents count < 2', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1']), JSON.stringify({ childId: 'P1' })))
      .to.be.rejectedWith(/at least 2/);
  });

  it('rejects duplicate parent IDs', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'S1']), JSON.stringify({ childId: 'P1' })))
      .to.be.rejectedWith(/duplicate parentId/);
  });

  it('rejects when any parent does not exist', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'GHOST']), JSON.stringify({ childId: 'P1' })))
      .to.be.rejectedWith(/PRODUCT_NOT_FOUND/);
  });

  it('rejects when any parent is CONSUMED (previously merged)', async () => {
    // CONSUMED になるのは Merge のみ (切り出しでは親 ACTIVE)。
    // 前工程で merge して CONSUMED にした親を使って再 Merge を試みる。
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    await seedMaterial('S2', 'Org2MSP', 'Org3MSP');
    await seedMaterial('S3', 'Org1MSP', 'Org3MSP');
    // 1st merge: [S1, S2] → P1. これで S1 と S2 は CONSUMED
    const ctxFirst = createMockContext({ mspId: 'Org3MSP', store });
    await contract.MergeProducts(ctxFirst, JSON.stringify(['S1', 'S2']), JSON.stringify({ childId: 'P1' }));
    // 2nd merge: [S1(CONSUMED), S3] → 失敗すべき
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'S3']), JSON.stringify({ childId: 'P2' })))
      .to.be.rejectedWith(/PARENT_NOT_ACTIVE/);
  });

  it('rejects when parents have divergent owners (not all owned by caller)', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    await seedMaterial('S2', 'Org2MSP', 'Org4MSP'); // different owner
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'S2']), JSON.stringify({ childId: 'P1' })))
      .to.be.rejectedWith(/PARENTS_OWNER_DIVERGENT/);
  });

  it('rejects when childId already exists', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    await seedMaterial('S2', 'Org2MSP', 'Org3MSP');
    await seedMaterial('EXISTING', 'Org1MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'S2']), JSON.stringify({ childId: 'EXISTING' })))
      .to.be.rejectedWith(/CHILD_ALREADY_EXISTS/);
  });

  it('rejects when childId equals any parentId', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    await seedMaterial('S2', 'Org2MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'S2']), JSON.stringify({ childId: 'S1' })))
      .to.be.rejectedWith(/CHILD_ALREADY_EXISTS/);
  });

  it('rejects malformed parentIdsJson', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, 'not-json', JSON.stringify({ childId: 'P' })))
      .to.be.rejectedWith(/parentIdsJson is not valid JSON/);
  });

  it('rejects malformed childJson', async () => {
    await seedMaterial('S1', 'Org1MSP', 'Org3MSP');
    await seedMaterial('S2', 'Org2MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await expect(contract.MergeProducts(ctx, JSON.stringify(['S1', 'S2']), 'not-json'))
      .to.be.rejectedWith(/childJson is not valid JSON/);
  });
});
