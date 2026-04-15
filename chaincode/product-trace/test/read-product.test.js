'use strict';

const chai = require('chai');
const chaiAsPromised = require('chai-as-promised');
chai.use(chaiAsPromised);
const { expect } = chai;

const { ProductTraceContract } = require('../lib/product-trace-contract');
const { createMockContext } = require('./helpers/mock-ctx');

describe('ReadProduct', () => {
  let contract;
  beforeEach(() => {
    contract = new ProductTraceContract();
  });

  it('returns the stored product JSON', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await contract.CreateProduct(ctx, 'X001', 'Org1MSP', 'Org1MSP');
    const result = await contract.ReadProduct(ctx, 'X001');
    const product = JSON.parse(result);
    expect(product.productId).to.equal('X001');
    expect(product.currentOwner).to.equal('Org1MSP');
  });

  it('rejects when product does not exist', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(contract.ReadProduct(ctx, 'MISSING')).to.be.rejectedWith(/not found/);
  });

  it('rejects missing productId', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(contract.ReadProduct(ctx, '')).to.be.rejectedWith(/required/);
  });
});
