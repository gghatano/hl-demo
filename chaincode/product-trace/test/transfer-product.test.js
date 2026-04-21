'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext } = require('./helpers/mock-ctx');

async function seedProduct(contract, ctx) {
  await contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org1MSP');
}

describe('TransferProduct', () => {
  let contract;
  beforeEach(() => {
    contract = new ProductTraceContract();
  });

  it('transfers from current owner to next owner when caller MSP matches fromOwner', async () => {
    const ctxA = createMockContext({ mspId: 'Org1MSP', txTimestampISO: '2026-04-15T10:00:00.000Z' });
    await seedProduct(contract, ctxA);

    // Org1 -> Org2
    const ctxA2 = createMockContext({ mspId: 'Org1MSP', txTimestampISO: '2026-04-15T10:05:00.000Z' });
    // share the store: copy value
    ctxA2.stub._store.set('X001', ctxA.stub._store.get('X001'));

    const result = await contract.TransferProduct(ctxA2, 'X001', 'Org1MSP', 'Org2MSP');
    const product = JSON.parse(result);
    expect(product.currentOwner).to.equal('Org2MSP');
    expect(product.updatedAt).to.equal('2026-04-15T10:05:00.000Z');
    expect(product.createdAt).to.equal('2026-04-15T10:00:00.000Z');
  });

  it('rejects when product does not exist', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.TransferProduct(ctx, 'UNKNOWN', 'Org1MSP', 'Org2MSP')
    ).to.be.rejectedWith(/not found/);
  });

  it('rejects when fromOwner does not match currentOwner', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await seedProduct(contract, ctx);
    // currentOwner is Org1MSP, but caller claims fromOwner=Org2MSP
    const ctx2 = createMockContext({ mspId: 'Org2MSP' });
    ctx2.stub._store.set('X001', ctx.stub._store.get('X001'));
    await expect(
      contract.TransferProduct(ctx2, 'X001', 'Org2MSP', 'Org3MSP')
    ).to.be.rejectedWith(/fromOwner does not match currentOwner/);
  });

  it('rejects when caller MSP does not match fromOwner', async () => {
    // Seed: Org1 creates, then transfers to Org2 so currentOwner=Org2MSP
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await seedProduct(contract, ctx);
    const ctxTransfer = createMockContext({ mspId: 'Org1MSP' });
    ctxTransfer.stub._store.set('X001', ctx.stub._store.get('X001'));
    await contract.TransferProduct(ctxTransfer, 'X001', 'Org1MSP', 'Org2MSP');

    // Now currentOwner=Org2MSP. Org3 attempts to transfer claiming fromOwner=Org2MSP.
    const ctxBad = createMockContext({ mspId: 'Org3MSP' });
    ctxBad.stub._store.set('X001', ctxTransfer.stub._store.get('X001'));
    await expect(
      contract.TransferProduct(ctxBad, 'X001', 'Org2MSP', 'Org3MSP')
    ).to.be.rejectedWith(/caller MSP must match fromOwner/);
  });

  it('rejects when fromOwner === toOwner', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await seedProduct(contract, ctx);
    const ctx2 = createMockContext({ mspId: 'Org1MSP' });
    ctx2.stub._store.set('X001', ctx.stub._store.get('X001'));
    await expect(
      contract.TransferProduct(ctx2, 'X001', 'Org1MSP', 'Org1MSP')
    ).to.be.rejectedWith(/must differ/);
  });

  // v2 追加 --------------------------------------------------------

  it('rejects transferring a CONSUMED product (Merge-consumed parent)', async () => {
    // CONSUMED になるのは Merge のみ (切り出しでは親 ACTIVE 維持)
    const store = new Map();
    const c1 = createMockContext({ mspId: 'Org1MSP', store });
    await contract.CreateProduct(c1, 'S1', 'Org1MSP', 'Org1MSP');
    const c2 = createMockContext({ mspId: 'Org2MSP', store });
    await contract.CreateProduct(c2, 'S2', 'Org2MSP', 'Org2MSP');
    const tx1 = createMockContext({ mspId: 'Org1MSP', store });
    await contract.TransferProduct(tx1, 'S1', 'Org1MSP', 'Org3MSP');
    const tx2 = createMockContext({ mspId: 'Org2MSP', store });
    await contract.TransferProduct(tx2, 'S2', 'Org2MSP', 'Org3MSP');
    const mg = createMockContext({ mspId: 'Org3MSP', store });
    await contract.MergeProducts(mg, JSON.stringify(['S1', 'S2']), JSON.stringify({ childId: 'P' }));
    // S1 is now CONSUMED
    const bad = createMockContext({ mspId: 'Org3MSP', store });
    await expect(
      contract.TransferProduct(bad, 'S1', 'Org3MSP', 'Org5MSP')
    ).to.be.rejectedWith(/PARENT_NOT_ACTIVE/);
  });

  it('rejects invalid toOwner MSP', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await seedProduct(contract, ctx);
    const ctx2 = createMockContext({ mspId: 'Org1MSP' });
    ctx2.stub._store.set('X001', ctx.stub._store.get('X001'));
    await expect(
      contract.TransferProduct(ctx2, 'X001', 'Org1MSP', 'BogusMSP')
    ).to.be.rejectedWith(/not a valid MSP/);
  });

  it('accepts transfer to new v2 orgs (Org4MSP, Org5MSP)', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await seedProduct(contract, ctx);
    const ctx2 = createMockContext({ mspId: 'Org1MSP' });
    ctx2.stub._store.set('X001', ctx.stub._store.get('X001'));
    const result = await contract.TransferProduct(ctx2, 'X001', 'Org1MSP', 'Org4MSP');
    expect(JSON.parse(result).currentOwner).to.equal('Org4MSP');

    const ctx3 = createMockContext({ mspId: 'Org4MSP' });
    ctx3.stub._store.set('X001', ctx2.stub._store.get('X001'));
    const result2 = await contract.TransferProduct(ctx3, 'X001', 'Org4MSP', 'Org5MSP');
    expect(JSON.parse(result2).currentOwner).to.equal('Org5MSP');
  });
});
