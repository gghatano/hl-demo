'use strict';

const { Contract } = require('fabric-contract-api');
const { ChaincodeError, ErrorCodes } = require('./errors');
const { getTxTimestampISO, getActor } = require('./util');

const MANUFACTURER_MSP = 'Org1MSP';
const STATUS_ACTIVE = 'ACTIVE';

class ProductTraceContract extends Contract {
  constructor() {
    super('ProductTraceContract');
  }

  async CreateProduct(ctx, productId, manufacturer, initialOwner) {
    if (!productId || !manufacturer || !initialOwner) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId, manufacturer, initialOwner are required'
      );
    }

    const { mspId } = getActor(ctx);
    if (mspId !== MANUFACTURER_MSP) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `CreateProduct is allowed only from ${MANUFACTURER_MSP}, caller=${mspId}`
      );
    }
    if (manufacturer !== MANUFACTURER_MSP) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `manufacturer must be ${MANUFACTURER_MSP}, got=${manufacturer}`
      );
    }
    if (initialOwner !== manufacturer) {
      throw new ChaincodeError(
        ErrorCodes.INITIAL_OWNER_MISMATCH,
        `initialOwner must equal manufacturer (${manufacturer}), got=${initialOwner}`
      );
    }

    const existing = await ctx.stub.getState(productId);
    if (existing && existing.length > 0) {
      throw new ChaincodeError(
        ErrorCodes.PRODUCT_ALREADY_EXISTS,
        `product already exists: ${productId}`
      );
    }

    const now = getTxTimestampISO(ctx);
    const actor = getActor(ctx);
    const product = {
      productId,
      manufacturer,
      currentOwner: initialOwner,
      status: STATUS_ACTIVE,
      createdAt: now,
      updatedAt: now,
      // lastActor: この version を書き込んだ主体。GetHistory で event.actor として emit する
      lastActor: { mspId: actor.mspId, id: actor.id },
    };
    await ctx.stub.putState(productId, Buffer.from(JSON.stringify(product)));
    return JSON.stringify(product);
  }

  async TransferProduct(ctx, productId, fromOwner, toOwner) {
    if (!productId || !fromOwner || !toOwner) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId, fromOwner, toOwner are required'
      );
    }
    if (fromOwner === toOwner) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `fromOwner and toOwner must differ: ${fromOwner}`
      );
    }

    const raw = await ctx.stub.getState(productId);
    if (!raw || raw.length === 0) {
      throw new ChaincodeError(
        ErrorCodes.PRODUCT_NOT_FOUND,
        `product not found: ${productId}`
      );
    }
    const product = JSON.parse(raw.toString());

    if (product.currentOwner !== fromOwner) {
      throw new ChaincodeError(
        ErrorCodes.OWNER_MISMATCH,
        `fromOwner does not match currentOwner: from=${fromOwner}, current=${product.currentOwner}`
      );
    }

    const { mspId } = getActor(ctx);
    if (mspId !== fromOwner) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `caller MSP must match fromOwner: caller=${mspId}, fromOwner=${fromOwner}`
      );
    }

    const actor = getActor(ctx);
    product.currentOwner = toOwner;
    product.updatedAt = getTxTimestampISO(ctx);
    product.lastActor = { mspId: actor.mspId, id: actor.id };
    await ctx.stub.putState(productId, Buffer.from(JSON.stringify(product)));
    return JSON.stringify(product);
  }

  async ReadProduct(ctx, productId) {
    if (!productId) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId is required'
      );
    }
    const raw = await ctx.stub.getState(productId);
    if (!raw || raw.length === 0) {
      throw new ChaincodeError(
        ErrorCodes.PRODUCT_NOT_FOUND,
        `product not found: ${productId}`
      );
    }
    return raw.toString();
  }

  // GetHistory: query only（state 書き換えなし）。
  // putState を呼ばないので endorsement 時の MVCC_READ_CONFLICT には関与しない。
  // `new Date().toISOString()` の入力は全て ledger 由来（km.timestamp）で決定的。
  async GetHistory(ctx, productId) {
    if (!productId) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId is required'
      );
    }
    const iterator = await ctx.stub.getHistoryForKey(productId);

    // GetHistoryForKey: 一般に降順（新→旧）で返るので、一旦全部集めてから reverse
    const collected = [];
    while (true) {
      const res = await iterator.next();
      if (res.value) {
        collected.push(res.value);
      }
      if (res.done) {
        await iterator.close();
        break;
      }
    }
    collected.reverse(); // 時系列昇順（旧→新）

    const events = [];
    let prevOwner = null;

    for (const km of collected) {
      if (km.isDelete) continue;
      let product;
      try {
        product = JSON.parse(km.value.toString());
      } catch (e) {
        continue;
      }

      const tsIso = km.timestamp
        ? new Date(
            Number(km.timestamp.seconds) * 1000 +
              Math.floor(km.timestamp.nanos / 1e6)
          ).toISOString()
        : null;

      // 各スナップショット時点の lastActor を採用。
      // 旧データ互換: lastActor 未記録のエントリは MSPID フォールバック。
      const actor = product.lastActor
        ? product.lastActor
        : { mspId: product.manufacturer, id: null };

      // events.length === 0 で CREATE 判定（先頭 isDelete 耐性）
      if (events.length === 0) {
        events.push({
          eventType: 'CREATE',
          productId: product.productId,
          fromOwner: null,
          toOwner: product.currentOwner,
          actor,
          txId: km.txId,
          timestamp: tsIso,
        });
        prevOwner = product.currentOwner;
      } else if (product.currentOwner !== prevOwner) {
        events.push({
          eventType: 'TRANSFER',
          productId: product.productId,
          fromOwner: prevOwner,
          toOwner: product.currentOwner,
          actor,
          txId: km.txId,
          timestamp: tsIso,
        });
        prevOwner = product.currentOwner;
      }
      // owner 変化なしの putState は履歴イベントとして扱わない
    }

    return JSON.stringify(events);
  }
}

module.exports = { ProductTraceContract, MANUFACTURER_MSP, STATUS_ACTIVE };
