'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext } = require('./helpers/mock-ctx');

describe('ListProductsByOwner', () => {
  let contract;
  let store;

  beforeEach(() => {
    contract = new ProductTraceContract();
    store = new Map();
  });

  async function seed(productId, manufMsp, destOwnerMsp) {
    const ctx = createMockContext({ mspId: manufMsp, store });
    await contract.CreateProduct(ctx, productId, manufMsp, manufMsp, '', '', '');
    if (destOwnerMsp && destOwnerMsp !== manufMsp) {
      const ctx2 = createMockContext({ mspId: manufMsp, store });
      await contract.TransferProduct(ctx2, productId, manufMsp, destOwnerMsp);
    }
  }

  async function listAs(org, ownerMspArg) {
    const ctx = createMockContext({ mspId: org, store });
    return JSON.parse(await contract.ListProductsByOwner(ctx, ownerMspArg));
  }

  it('returns products currently owned by the specified MSP, sorted by productId', async () => {
    await seed('zeta', 'Org1MSP', 'Org3MSP');
    await seed('alpha', 'Org2MSP', 'Org3MSP');
    await seed('mike', 'Org1MSP', 'Org3MSP');
    await seed('other', 'Org1MSP', 'Org4MSP');

    const list = await listAs('Org3MSP', 'Org3MSP');
    expect(list.map((p) => p.productId)).to.deep.equal(['alpha', 'mike', 'zeta']);
    for (const p of list) expect(p.currentOwner).to.equal('Org3MSP');
  });

  it('excludes products no longer owned (ownership transferred away)', async () => {
    await seed('A', 'Org1MSP', 'Org3MSP');
    // Now transfer A to Org4MSP
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await contract.TransferProduct(ctx, 'A', 'Org3MSP', 'Org4MSP');

    const listOrg3 = await listAs('Org3MSP', 'Org3MSP');
    const listOrg4 = await listAs('Org3MSP', 'Org4MSP');
    expect(listOrg3.map((p) => p.productId)).to.deep.equal([]);
    expect(listOrg4.map((p) => p.productId)).to.deep.equal(['A']);
  });

  it('includes CONSUMED products (via Merge) whose currentOwner still matches', async () => {
    // CONSUMED になるのは Merge 経由のみ。2 素材を作って Merge。
    await seed('P1', 'Org1MSP', 'Org3MSP');
    await seed('P2', 'Org2MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await contract.MergeProducts(ctx, JSON.stringify(['P1', 'P2']), JSON.stringify({ childId: 'C' }));
    // P1, P2 are CONSUMED, currentOwner still Org3MSP. C は ACTIVE currentOwner Org3MSP。
    const list = await listAs('Org3MSP', 'Org3MSP');
    expect(list.map((p) => p.productId)).to.deep.equal(['C', 'P1', 'P2']);
    const p1 = list.find((x) => x.productId === 'P1');
    expect(p1.status).to.equal('CONSUMED');
    expect(p1.children).to.deep.equal(['C']);
  });

  it('keeps carved parent ACTIVE in the list', async () => {
    await seed('S', 'Org1MSP', 'Org3MSP');
    const ctx = createMockContext({ mspId: 'Org3MSP', store });
    await contract.SplitProduct(ctx, 'S', JSON.stringify([
      { childId: 'S-a', toOwner: 'Org3MSP' },
      { childId: 'S-b', toOwner: 'Org3MSP' },
    ]));
    const list = await listAs('Org3MSP', 'Org3MSP');
    expect(list.map((p) => p.productId)).to.deep.equal(['S', 'S-a', 'S-b']);
    expect(list.find((x) => x.productId === 'S').status).to.equal('ACTIVE');
  });

  it('returns empty array when no products exist', async () => {
    const list = await listAs('Org1MSP', 'Org5MSP');
    expect(list).to.deep.equal([]);
  });

  it('rejects missing ownerMspId', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP', store });
    await expect(contract.ListProductsByOwner(ctx, ''))
      .to.be.rejectedWith(/required/);
  });
});
