'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext } = require('./helpers/mock-ctx');

describe('GetLineage', () => {
  let contract;
  let store;

  beforeEach(() => {
    contract = new ProductTraceContract();
    store = new Map();
  });

  async function create(msp, productId) {
    const ctx = createMockContext({ mspId: msp, store });
    await contract.CreateProduct(ctx, productId, msp, msp);
  }
  async function transfer(productId, fromMsp, toMsp) {
    const ctx = createMockContext({ mspId: fromMsp, store });
    await contract.TransferProduct(ctx, productId, fromMsp, toMsp);
  }
  async function split(parentId, ownerMsp, children) {
    const ctx = createMockContext({ mspId: ownerMsp, store });
    await contract.SplitProduct(ctx, parentId, JSON.stringify(children));
  }
  async function merge(parentIds, childId, ownerMsp) {
    const ctx = createMockContext({ mspId: ownerMsp, store });
    await contract.MergeProducts(ctx, JSON.stringify(parentIds), JSON.stringify({ childId }));
  }
  async function lineage(productId) {
    const ctx = createMockContext({ mspId: 'Org5MSP', store });
    return JSON.parse(await contract.GetLineage(ctx, productId));
  }

  it('returns single node with no edges for a newly created product', async () => {
    await create('Org1MSP', 'S1');
    const res = await lineage('S1');
    expect(res.root).to.equal('S1');
    expect(res.nodes).to.have.length(1);
    expect(res.nodes[0].id).to.equal('S1');
    expect(res.nodes[0].manufacturer).to.equal('Org1MSP');
    expect(res.edges).to.deep.equal([]);
  });

  it('returns DAG with SPLIT edge for split-derived product', async () => {
    await create('Org1MSP', 'S1');
    await transfer('S1', 'Org1MSP', 'Org3MSP');
    await split('S1', 'Org3MSP', [
      { childId: 'S1-a', toOwner: 'Org3MSP' },
      { childId: 'S1-b', toOwner: 'Org5MSP' },
    ]);

    const res = await lineage('S1-a');
    expect(res.root).to.equal('S1-a');
    expect(res.nodes.map((n) => n.id).sort()).to.deep.equal(['S1', 'S1-a']);
    expect(res.edges).to.deep.equal([{ from: 'S1', to: 'S1-a', type: 'SPLIT' }]);
  });

  it('returns DAG with MERGE edges for merge-derived product', async () => {
    await create('Org1MSP', 'S1');
    await create('Org2MSP', 'S2');
    await transfer('S1', 'Org1MSP', 'Org3MSP');
    await transfer('S2', 'Org2MSP', 'Org3MSP');
    await merge(['S1', 'S2'], 'P1', 'Org3MSP');

    const res = await lineage('P1');
    expect(res.nodes.map((n) => n.id).sort()).to.deep.equal(['P1', 'S1', 'S2']);
    expect(res.edges).to.deep.equal([
      { from: 'S1', to: 'P1', type: 'MERGE' },
      { from: 'S2', to: 'P1', type: 'MERGE' },
    ]);
  });

  it('returns complex DAG for split-then-merge (spec-v2 N7 scenario)', async () => {
    // S1 (Org1) split to S1-a/S1-b/S1-c at Org3
    // S2 (Org2) sent to Org3
    // S1-a + S2 merged into P1 at Org3
    await create('Org1MSP', 'S1');
    await create('Org2MSP', 'S2');
    await transfer('S1', 'Org1MSP', 'Org3MSP');
    await transfer('S2', 'Org2MSP', 'Org3MSP');
    await split('S1', 'Org3MSP', [
      { childId: 'S1-a', toOwner: 'Org3MSP' },
      { childId: 'S1-b', toOwner: 'Org5MSP' },
      { childId: 'S1-c', toOwner: 'Org3MSP' },
    ]);
    await merge(['S1-a', 'S2'], 'P1', 'Org3MSP');

    const res = await lineage('P1');
    expect(res.nodes.map((n) => n.id).sort()).to.deep.equal(['P1', 'S1', 'S1-a', 'S2']);
    expect(res.edges).to.deep.equal([
      { from: 'S1', to: 'S1-a', type: 'SPLIT' },
      { from: 'S1-a', to: 'P1', type: 'MERGE' },
      { from: 'S2', to: 'P1', type: 'MERGE' },
    ]);
  });

  it('includes status/manufacturer/metadata/millSheet fields in nodes', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP', store });
    await contract.CreateProduct(
      ctx,
      'S1',
      'Org1MSP',
      'Org1MSP',
      '{"grade":"SS400","heatNo":"HT-001"}',
      'a'.repeat(64),
      'https://example.com/mill/S1.pdf'
    );

    const res = await lineage('S1');
    const n = res.nodes[0];
    expect(n.manufacturer).to.equal('Org1MSP');
    expect(n.status).to.equal('ACTIVE');
    expect(n.metadata).to.deep.equal({ grade: 'SS400', heatNo: 'HT-001' });
    expect(n.millSheetHash).to.equal('a'.repeat(64));
    expect(n.millSheetURI).to.equal('https://example.com/mill/S1.pdf');
  });

  it('returns edges sorted by (from, to) deterministically', async () => {
    await create('Org1MSP', 'zP');
    await create('Org1MSP', 'aP');
    await create('Org1MSP', 'mP');
    await transfer('zP', 'Org1MSP', 'Org3MSP');
    await transfer('aP', 'Org1MSP', 'Org3MSP');
    await transfer('mP', 'Org1MSP', 'Org3MSP');
    await merge(['zP', 'aP', 'mP'], 'FINAL', 'Org3MSP');

    const res = await lineage('FINAL');
    expect(res.edges).to.deep.equal([
      { from: 'aP', to: 'FINAL', type: 'MERGE' },
      { from: 'mP', to: 'FINAL', type: 'MERGE' },
      { from: 'zP', to: 'FINAL', type: 'MERGE' },
    ]);
  });

  it('rejects when root productId does not exist', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP', store });
    await expect(contract.GetLineage(ctx, 'GHOST'))
      .to.be.rejectedWith(/PRODUCT_NOT_FOUND/);
  });

  it('rejects missing productId', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP', store });
    await expect(contract.GetLineage(ctx, '')).to.be.rejectedWith(/required/);
  });
});
