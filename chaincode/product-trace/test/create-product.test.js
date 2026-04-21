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

  // v2 新機能 -------------------------------------------------------------

  it('accepts Org2MSP (electric furnace) as manufacturer', async () => {
    const ctx = createMockContext({ mspId: 'Org2MSP' });
    const result = await contract.CreateProduct(ctx, 'S2', 'Org2MSP', 'Org2MSP');
    const product = JSON.parse(result);
    expect(product.manufacturer).to.equal('Org2MSP');
    expect(product.currentOwner).to.equal('Org2MSP');
    expect(product.status).to.equal('ACTIVE');
    expect(product.parents).to.deep.equal([]);
    expect(product.children).to.deep.equal([]);
  });

  it('rejects CreateProduct from non-manufacturer MSP (Org3MSP)', async () => {
    const ctx = createMockContext({ mspId: 'Org3MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X', 'Org3MSP', 'Org3MSP')
    ).to.be.rejectedWith(/MSP_NOT_AUTHORIZED/);
  });

  it('accepts valid metadata JSON and persists parsed object', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const result = await contract.CreateProduct(
      ctx,
      'X',
      'Org1MSP',
      'Org1MSP',
      '{"grade":"SS400","weightKg":10000}'
    );
    const product = JSON.parse(result);
    expect(product.metadata).to.deep.equal({ grade: 'SS400', weightKg: 10000 });
  });

  it('rejects invalid metadata JSON', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X', 'Org1MSP', 'Org1MSP', '{not-json')
    ).to.be.rejectedWith(/INVALID_METADATA/);
  });

  it('rejects metadata that parses to array', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X', 'Org1MSP', 'Org1MSP', '[1,2,3]')
    ).to.be.rejectedWith(/INVALID_METADATA/);
  });

  it('accepts millSheetHash (64 hex) and millSheetURI', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const result = await contract.CreateProduct(
      ctx,
      'X',
      'Org1MSP',
      'Org1MSP',
      '',
      'a'.repeat(64),
      'https://example.com/mill/X.pdf'
    );
    const product = JSON.parse(result);
    expect(product.millSheetHash).to.equal('a'.repeat(64));
    expect(product.millSheetURI).to.equal('https://example.com/mill/X.pdf');
  });

  it('rejects malformed millSheetHash (wrong length)', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    await expect(
      contract.CreateProduct(ctx, 'X', 'Org1MSP', 'Org1MSP', '', 'abc')
    ).to.be.rejectedWith(/millSheetHash/);
  });

  it('accepts empty metadata / millSheet fields', async () => {
    const ctx = createMockContext({ mspId: 'Org1MSP' });
    const result = await contract.CreateProduct(ctx, 'X', 'Org1MSP', 'Org1MSP', '', '', '');
    const product = JSON.parse(result);
    expect(product.metadata).to.deep.equal({});
    expect(product.millSheetHash).to.equal('');
    expect(product.millSheetURI).to.equal('');
  });
});
