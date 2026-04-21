'use strict';

const { Contract } = require('fabric-contract-api');
const { ChaincodeError, ErrorCodes } = require('./errors');
const {
  getTxTimestampISO,
  getActor,
  isValidMsp,
  isManufacturerMsp,
  parseMetadata,
  validateMillSheet,
  normalizeIds,
  VALID_MSPS,
  MANUFACTURER_MSPS,
} = require('./util');

const STATUS_ACTIVE = 'ACTIVE';
const STATUS_CONSUMED = 'CONSUMED';

const LINEAGE_MAX_DEPTH = 20;

// state → product オブジェクトへの decode。v1 (parents/children/status/metadata 未保持)
// 時代のデータを読む可能性に備え、未定義フィールドは安全なデフォルトで補完する。
function decodeProduct(raw) {
  const obj = JSON.parse(raw.toString());
  if (!Array.isArray(obj.parents)) obj.parents = [];
  if (!Array.isArray(obj.children)) obj.children = [];
  if (obj.status !== STATUS_CONSUMED) obj.status = STATUS_ACTIVE;
  if (obj.metadata == null || typeof obj.metadata !== 'object' || Array.isArray(obj.metadata)) {
    obj.metadata = {};
  }
  if (typeof obj.millSheetHash !== 'string') obj.millSheetHash = '';
  if (typeof obj.millSheetURI !== 'string') obj.millSheetURI = '';
  return obj;
}

function encodeProduct(product) {
  return Buffer.from(JSON.stringify(product));
}

async function loadProductOrThrow(ctx, productId) {
  const raw = await ctx.stub.getState(productId);
  if (!raw || raw.length === 0) {
    throw new ChaincodeError(
      ErrorCodes.PRODUCT_NOT_FOUND,
      `product not found: ${productId}`
    );
  }
  return decodeProduct(raw);
}

async function assertNotExists(ctx, productId) {
  const existing = await ctx.stub.getState(productId);
  if (existing && existing.length > 0) {
    throw new ChaincodeError(
      ErrorCodes.CHILD_ALREADY_EXISTS,
      `product already exists: ${productId}`
    );
  }
}

class ProductTraceContract extends Contract {
  constructor() {
    super('ProductTraceContract');
  }

  // fabric-contract-api は関数の Function.length を使って期待引数数を決めるため、
  // デフォルト引数を付けると期待値が減って client は全引数を送る必要があるのに不一致となる。
  // → 全引数を必須にし、クライアント側で空文字を明示的に送る規約にする。
  async CreateProduct(
    ctx,
    productId,
    manufacturer,
    initialOwner,
    metadataJson,
    millSheetHash,
    millSheetURI
  ) {
    if (!productId || !manufacturer || !initialOwner) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId, manufacturer, initialOwner are required'
      );
    }

    const { mspId, id: callerId } = getActor(ctx);
    if (!isManufacturerMsp(mspId)) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `CreateProduct is allowed only from manufacturer MSPs [${MANUFACTURER_MSPS.join(',')}], caller=${mspId}`
      );
    }
    if (!isManufacturerMsp(manufacturer)) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `manufacturer must be one of [${MANUFACTURER_MSPS.join(',')}], got=${manufacturer}`
      );
    }
    if (manufacturer !== mspId) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `manufacturer must match caller MSP: caller=${mspId}, manufacturer=${manufacturer}`
      );
    }
    if (initialOwner !== manufacturer) {
      throw new ChaincodeError(
        ErrorCodes.INITIAL_OWNER_MISMATCH,
        `initialOwner must equal manufacturer (${manufacturer}), got=${initialOwner}`
      );
    }

    const metadata = parseMetadata(metadataJson);
    validateMillSheet(millSheetHash, millSheetURI);

    const existing = await ctx.stub.getState(productId);
    if (existing && existing.length > 0) {
      throw new ChaincodeError(
        ErrorCodes.PRODUCT_ALREADY_EXISTS,
        `product already exists: ${productId}`
      );
    }

    const now = getTxTimestampISO(ctx);
    const product = {
      productId,
      manufacturer,
      currentOwner: initialOwner,
      status: STATUS_ACTIVE,
      parents: [],
      children: [],
      metadata,
      millSheetHash: millSheetHash || '',
      millSheetURI: millSheetURI || '',
      createdAt: now,
      updatedAt: now,
      lastActor: { mspId, id: callerId },
    };
    await ctx.stub.putState(productId, encodeProduct(product));
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
    if (!isValidMsp(toOwner)) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `toOwner is not a valid MSP: ${toOwner}`
      );
    }

    const product = await loadProductOrThrow(ctx, productId);

    if (product.status !== STATUS_ACTIVE) {
      throw new ChaincodeError(
        ErrorCodes.PARENT_NOT_ACTIVE,
        `product is not ACTIVE (status=${product.status}): ${productId}`
      );
    }
    if (product.currentOwner !== fromOwner) {
      throw new ChaincodeError(
        ErrorCodes.OWNER_MISMATCH,
        `fromOwner does not match currentOwner: from=${fromOwner}, current=${product.currentOwner}`
      );
    }

    const { mspId, id: callerId } = getActor(ctx);
    if (mspId !== fromOwner) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `caller MSP must match fromOwner: caller=${mspId}, fromOwner=${fromOwner}`
      );
    }

    product.currentOwner = toOwner;
    product.updatedAt = getTxTimestampISO(ctx);
    product.lastActor = { mspId, id: callerId };
    await ctx.stub.putState(productId, encodeProduct(product));
    return JSON.stringify(product);
  }

  // SplitProduct: 親1→子N (N>=2)。
  // childrenJson は [{childId, toOwner, metadataJson, millSheetHash, millSheetURI}, ...] の JSON 文字列。
  async SplitProduct(ctx, parentId, childrenJson) {
    if (!parentId || childrenJson === undefined || childrenJson === null) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'parentId and childrenJson are required'
      );
    }

    let childSpecs;
    try {
      childSpecs = JSON.parse(childrenJson);
    } catch (e) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `childrenJson is not valid JSON: ${e.message}`
      );
    }
    if (!Array.isArray(childSpecs) || childSpecs.length < 2) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'childrenJson must be an array with at least 2 elements'
      );
    }

    // 各 child spec の基本検証
    const childIds = [];
    for (const spec of childSpecs) {
      if (!spec || typeof spec !== 'object') {
        throw new ChaincodeError(
          ErrorCodes.INVALID_ARGUMENT,
          'each child spec must be an object'
        );
      }
      if (!spec.childId || typeof spec.childId !== 'string') {
        throw new ChaincodeError(
          ErrorCodes.INVALID_ARGUMENT,
          'child.childId is required'
        );
      }
      if (!isValidMsp(spec.toOwner)) {
        throw new ChaincodeError(
          ErrorCodes.INVALID_ARGUMENT,
          `child.toOwner is not a valid MSP: ${spec.toOwner}`
        );
      }
      childIds.push(spec.childId);
    }

    // child 同士の重複
    const uniqueChildIds = new Set(childIds);
    if (uniqueChildIds.size !== childIds.length) {
      throw new ChaincodeError(
        ErrorCodes.CHILD_ALREADY_EXISTS,
        `duplicate childId in request: ${childIds.join(',')}`
      );
    }
    if (uniqueChildIds.has(parentId)) {
      throw new ChaincodeError(
        ErrorCodes.CHILD_ALREADY_EXISTS,
        `childId must not equal parentId: ${parentId}`
      );
    }

    const parent = await loadProductOrThrow(ctx, parentId);
    if (parent.status !== STATUS_ACTIVE) {
      throw new ChaincodeError(
        ErrorCodes.PARENT_NOT_ACTIVE,
        `parent is not ACTIVE (status=${parent.status}): ${parentId}`
      );
    }

    const { mspId, id: callerId } = getActor(ctx);
    if (mspId !== parent.currentOwner) {
      throw new ChaincodeError(
        ErrorCodes.MSP_NOT_AUTHORIZED,
        `caller MSP must match parent.currentOwner: caller=${mspId}, owner=${parent.currentOwner}`
      );
    }

    // state 上で既存の childId がないか全数チェック
    for (const childId of childIds) {
      // eslint-disable-next-line no-await-in-loop
      await assertNotExists(ctx, childId);
    }

    // 各 child の metadata/millSheet 検証 (副作用前にまとめて)
    const childPayloads = [];
    const now = getTxTimestampISO(ctx);
    for (const spec of childSpecs) {
      const metadata = parseMetadata(spec.metadataJson);
      validateMillSheet(spec.millSheetHash, spec.millSheetURI);
      childPayloads.push({
        productId: spec.childId,
        manufacturer: parent.manufacturer,
        currentOwner: spec.toOwner,
        status: STATUS_ACTIVE,
        parents: [parentId],
        children: [],
        metadata,
        millSheetHash: spec.millSheetHash || '',
        millSheetURI: spec.millSheetURI || '',
        createdAt: now,
        updatedAt: now,
        lastActor: { mspId, id: callerId },
      });
    }

    // 親更新 (CONSUMED + children 記録)
    parent.status = STATUS_CONSUMED;
    parent.children = normalizeIds(childIds);
    parent.updatedAt = now;
    parent.lastActor = { mspId, id: callerId };
    await ctx.stub.putState(parentId, encodeProduct(parent));

    // 子 putState
    for (const child of childPayloads) {
      // eslint-disable-next-line no-await-in-loop
      await ctx.stub.putState(child.productId, encodeProduct(child));
    }

    return JSON.stringify({ parent, children: childPayloads });
  }

  // MergeProducts: 親N→子1 (N>=2)。
  // parentIdsJson は ["p1","p2",...] の JSON 文字列。
  // childJson は { childId, metadataJson, millSheetHash, millSheetURI } の JSON 文字列。
  async MergeProducts(ctx, parentIdsJson, childJson) {
    if (parentIdsJson === undefined || parentIdsJson === null || !childJson) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'parentIdsJson and childJson are required'
      );
    }

    let parentIds;
    try {
      parentIds = JSON.parse(parentIdsJson);
    } catch (e) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `parentIdsJson is not valid JSON: ${e.message}`
      );
    }
    if (!Array.isArray(parentIds) || parentIds.length < 2) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'parentIdsJson must be an array with at least 2 elements'
      );
    }
    for (const pid of parentIds) {
      if (!pid || typeof pid !== 'string') {
        throw new ChaincodeError(
          ErrorCodes.INVALID_ARGUMENT,
          'each parentId must be a non-empty string'
        );
      }
    }
    const uniqueParents = new Set(parentIds);
    if (uniqueParents.size !== parentIds.length) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `duplicate parentId: ${parentIds.join(',')}`
      );
    }

    let childSpec;
    try {
      childSpec = JSON.parse(childJson);
    } catch (e) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `childJson is not valid JSON: ${e.message}`
      );
    }
    if (!childSpec || typeof childSpec !== 'object' || Array.isArray(childSpec)) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'childJson must be an object'
      );
    }
    if (!childSpec.childId || typeof childSpec.childId !== 'string') {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'childJson.childId is required'
      );
    }
    if (uniqueParents.has(childSpec.childId)) {
      throw new ChaincodeError(
        ErrorCodes.CHILD_ALREADY_EXISTS,
        `childId must not equal any parentId: ${childSpec.childId}`
      );
    }

    const { mspId, id: callerId } = getActor(ctx);

    // 子 ID 新規性
    await assertNotExists(ctx, childSpec.childId);

    // 全親 load + 検証
    const parents = [];
    for (const pid of parentIds) {
      // eslint-disable-next-line no-await-in-loop
      const parent = await loadProductOrThrow(ctx, pid);
      if (parent.status !== STATUS_ACTIVE) {
        throw new ChaincodeError(
          ErrorCodes.PARENT_NOT_ACTIVE,
          `parent is not ACTIVE (status=${parent.status}): ${pid}`
        );
      }
      if (parent.currentOwner !== mspId) {
        throw new ChaincodeError(
          ErrorCodes.PARENTS_OWNER_DIVERGENT,
          `parent currentOwner must equal caller: pid=${pid}, owner=${parent.currentOwner}, caller=${mspId}`
        );
      }
      parents.push(parent);
    }

    const metadata = parseMetadata(childSpec.metadataJson);
    validateMillSheet(childSpec.millSheetHash, childSpec.millSheetURI);

    const now = getTxTimestampISO(ctx);
    const childPayload = {
      productId: childSpec.childId,
      // 接合部材の「メーカー」は接合実施者。起点 (高炉/電炉) は parents 経由で辿れる。
      manufacturer: mspId,
      currentOwner: mspId,
      status: STATUS_ACTIVE,
      parents: normalizeIds(parentIds),
      children: [],
      metadata,
      millSheetHash: childSpec.millSheetHash || '',
      millSheetURI: childSpec.millSheetURI || '',
      createdAt: now,
      updatedAt: now,
      lastActor: { mspId, id: callerId },
    };

    // 各親更新
    for (const parent of parents) {
      parent.status = STATUS_CONSUMED;
      parent.children = normalizeIds([...parent.children, childSpec.childId]);
      parent.updatedAt = now;
      parent.lastActor = { mspId, id: callerId };
      // eslint-disable-next-line no-await-in-loop
      await ctx.stub.putState(parent.productId, encodeProduct(parent));
    }

    await ctx.stub.putState(childSpec.childId, encodeProduct(childPayload));
    return JSON.stringify({ parents, child: childPayload });
  }

  async ReadProduct(ctx, productId) {
    if (!productId) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId is required'
      );
    }
    const product = await loadProductOrThrow(ctx, productId);
    return JSON.stringify(product);
  }

  // GetHistory: query only (state 書き換えなし)。
  // v2: CREATE / TRANSFER に加え SPLIT / MERGE / SPLIT_FROM / MERGE_FROM を emit
  async GetHistory(ctx, productId) {
    if (!productId) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId is required'
      );
    }
    const iterator = await ctx.stub.getHistoryForKey(productId);

    const collected = [];
    while (true) {
      // eslint-disable-next-line no-await-in-loop
      const res = await iterator.next();
      if (res.value) {
        collected.push(res.value);
      }
      if (res.done) {
        await iterator.close();
        break;
      }
    }
    collected.reverse(); // 時系列昇順 (旧→新)

    const events = [];
    let prev = null; // 直前のスナップショット product state

    for (const km of collected) {
      if (km.isDelete) continue;
      let product;
      try {
        product = decodeProduct(km.value);
      } catch (e) {
        continue;
      }

      const tsIso = km.timestamp
        ? new Date(
            Number(km.timestamp.seconds) * 1000
              + Math.floor(km.timestamp.nanos / 1e6)
          ).toISOString()
        : null;

      const actor = product.lastActor
        ? product.lastActor
        : { mspId: product.manufacturer, id: null };

      if (prev === null) {
        // 最初の非削除スナップショット
        const parents = product.parents || [];
        let eventType;
        if (parents.length === 0) eventType = 'CREATE';
        else if (parents.length === 1) eventType = 'SPLIT_FROM';
        else eventType = 'MERGE_FROM';

        const evt = {
          eventType,
          productId: product.productId,
          fromOwner: null,
          toOwner: product.currentOwner,
          actor,
          txId: km.txId,
          timestamp: tsIso,
        };
        if (parents.length > 0) evt.parents = parents;
        events.push(evt);
      } else {
        const ownerChanged = product.currentOwner !== prev.currentOwner;
        const statusTransitionConsumed = prev.status === STATUS_ACTIVE
          && product.status === STATUS_CONSUMED;

        if (statusTransitionConsumed) {
          const children = product.children || [];
          // Split の子は常に N>=2、Merge の子は 1 のため children 数で判定
          const eventType = children.length >= 2 ? 'SPLIT' : 'MERGE';
          events.push({
            eventType,
            productId: product.productId,
            fromOwner: product.currentOwner,
            toOwner: null,
            children,
            actor,
            txId: km.txId,
            timestamp: tsIso,
          });
        } else if (ownerChanged) {
          events.push({
            eventType: 'TRANSFER',
            productId: product.productId,
            fromOwner: prev.currentOwner,
            toOwner: product.currentOwner,
            actor,
            txId: km.txId,
            timestamp: tsIso,
          });
        }
        // owner / status いずれも無変化 → イベント emit 無し
      }

      prev = product;
    }

    return JSON.stringify(events);
  }

  // GetLineage: 祖先方向 DAG を BFS で収集
  async GetLineage(ctx, productId) {
    if (!productId) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        'productId is required'
      );
    }

    // root 存在確認
    const rootRaw = await ctx.stub.getState(productId);
    if (!rootRaw || rootRaw.length === 0) {
      throw new ChaincodeError(
        ErrorCodes.PRODUCT_NOT_FOUND,
        `product not found: ${productId}`
      );
    }

    const visited = new Set();
    const nodes = [];
    const edges = [];

    let currentLevel = [productId];
    let depth = 0;

    while (currentLevel.length > 0) {
      if (depth > LINEAGE_MAX_DEPTH) {
        throw new ChaincodeError(
          ErrorCodes.LINEAGE_DEPTH_EXCEEDED,
          `lineage depth exceeded ${LINEAGE_MAX_DEPTH} for root=${productId}`
        );
      }
      const nextLevel = [];
      // 決定性: level 内の id を昇順で処理
      const sortedLevel = [...currentLevel].sort();
      for (const id of sortedLevel) {
        if (visited.has(id)) continue;
        visited.add(id);

        // eslint-disable-next-line no-await-in-loop
        const raw = await ctx.stub.getState(id);
        if (!raw || raw.length === 0) {
          // 参照先が存在しない (データ不整合時のみ発生しうる) → skip
          continue;
        }
        const product = decodeProduct(raw);

        nodes.push({
          id: product.productId,
          manufacturer: product.manufacturer,
          currentOwner: product.currentOwner,
          status: product.status,
          metadata: product.metadata,
          millSheetHash: product.millSheetHash,
          millSheetURI: product.millSheetURI,
        });

        const parents = product.parents || [];
        const edgeType = parents.length >= 2 ? 'MERGE'
          : parents.length === 1 ? 'SPLIT'
            : null;

        for (const parentId of parents) {
          if (edgeType) {
            edges.push({ from: parentId, to: product.productId, type: edgeType });
          }
          if (!visited.has(parentId)) {
            nextLevel.push(parentId);
          }
        }
      }
      currentLevel = nextLevel;
      depth += 1;
    }

    // edges を (from,to) 辞書順ソート (決定性)
    edges.sort((a, b) => {
      if (a.from !== b.from) return a.from < b.from ? -1 : 1;
      if (a.to !== b.to) return a.to < b.to ? -1 : 1;
      return 0;
    });

    return JSON.stringify({ root: productId, nodes, edges });
  }
}

module.exports = {
  ProductTraceContract,
  MANUFACTURER_MSPS,
  VALID_MSPS,
  STATUS_ACTIVE,
  STATUS_CONSUMED,
};
