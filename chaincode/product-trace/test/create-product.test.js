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
    const ctx = createMockContext({ mspId: 'Org1MSP', txTimestampISO: '2026-04-15T10:00:00.000Z' });
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
    // putState invoked
    const stored = ctx.stub._store.get('X001');
    expect(stored).to.not.be.undefined;
    expect(JSON.parse(stored.toString()).productId).to.equal('X001');
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

  it('rejects when manufacturer !== Org1MSP', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X001', 'Org2MSP', 'Org2MSP')
    ).to.be.rejectedWith(/manufacturer must be Org1MSP/);
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
