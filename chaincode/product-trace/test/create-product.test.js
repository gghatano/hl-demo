'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext } = require('./helpers/mock-ctx');

describe('CreateProduct', () => {
  let contract;
  beforeEach(() => {
    contract = new ProductTraceContract();
  });

  it('creates a new product when called by Org1MSP with matching manufacturer/initialOwner', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP', identityId: 'x509::CN=Admin@org1', txTimestampISO: '2026-04-15T10:00:00.000Z' });
    const result = await contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org1MSP');
    const product = JSON.parse(result);
    expect(product).to.include({
      productId: 'X001',
      manufacturer: 'Org1MSP',
      currentOwner: 'Org1MSP',
      status: 'ACTIVE',
      createdAt: '2026-04-15T10:00:00.000Z',
      updatedAt: '2026-04-15T10:00:00.000Z',
    });
    expect(product.lastActor).to.deep.equal({ mspId: 'Org1MSP', id: 'x509::CN=Admin@org1' });
    // putState invoked
    const stored = ctx.stub._store.get('X001');
    expect(stored).to.not.be.undefined;
    expect(JSON.parse(stored.toString()).productId).to.equal('X001');
  });

  it('accepts non-ASCII productId', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const result = await contract.CreateProduct(ctx, '製品-一号-🎁', 'Org1MSP', 'Org1MSP');
    expect(JSON.parse(result).productId).to.equal('製品-一号-🎁');
  });

  it('accepts long productId (256 chars)', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const longId = 'X'.repeat(256);
    const result = await contract.CreateProduct(ctx, longId, 'Org1MSP', 'Org1MSP');
    expect(JSON.parse(result).productId).to.equal(longId);
  });

  it('rejects when called by non-Org1MSP', async () => {
    const ctx = createMockContext({ mspId: 'Org2MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org1MSP')
    ).to.be.rejectedWith(/MSP_NOT_AUTHORIZED|only from Org1MSP/);
  });

  it('rejects when initialOwner !== manufacturer', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org2MSP')
    ).to.be.rejectedWith(/initialOwner must equal manufacturer/);
  });

  it('rejects when manufacturer does not match caller MSP (Org1MSP caller, Org2MSP claim)', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X001', 'Org2MSP', 'Org2MSP')
    ).to.be.rejectedWith(/MSP_NOT_AUTHORIZED|manufacturer must match caller/);
  });

  it('rejects duplicate productId', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org1MSP');
    await expect(
      contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org1MSP')
    ).to.be.rejectedWith(/already exists/);
  });

  it('rejects missing arguments', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, '', 'Org1MSP', 'Org1MSP')
    ).to.be.rejectedWith(/required/);
  });
});
