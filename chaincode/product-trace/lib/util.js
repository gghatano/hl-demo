'use strict';

// 決定性ユーティリティ
// Date.now() / Math.random() / process.env 等の非決定性 API は chaincode 内で使用禁止
// 全 endorser で同一値となる ctx.stub 由来のデータのみ使う

const { ChaincodeError, ErrorCodes } = require('./errors');

const VALID_MSPS = ['Org1MSP', 'Org2MSP', 'Org3MSP', 'Org4MSP', 'Org5MSP'];
const MANUFACTURER_MSPS = ['Org1MSP', 'Org2MSP'];
const MILL_SHEET_HASH_PATTERN = /^[0-9a-f]{64}$/;
const MILL_SHEET_URI_MAX_LEN = 1024;

function getTxTimestampISO(ctx) {
  const ts = ctx.stub.getTxTimestamp();
  const millis = Number(ts.seconds) * 1000 + Math.floor(ts.nanos / 1e6);
  return new Date(millis).toISOString();
}

function getActor(ctx) {
  const mspId = ctx.clientIdentity.getMSPID();
  const id = ctx.clientIdentity.getID();
  return { mspId, id };
}

function isValidMsp(mspId) {
  return VALID_MSPS.includes(mspId);
}

function isManufacturerMsp(mspId) {
  return MANUFACTURER_MSPS.includes(mspId);
}

// metadataJson: 空文字 or JSON string。パース後に plain object (非配列・非 null) であることを要求。
function parseMetadata(metadataJson) {
  if (metadataJson === undefined || metadataJson === null || metadataJson === '') {
    return {};
  }
  let parsed;
  try {
    parsed = JSON.parse(metadataJson);
  } catch (e) {
    throw new ChaincodeError(
      ErrorCodes.INVALID_METADATA,
      `metadata is not valid JSON: ${e.message}`
    );
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new ChaincodeError(
      ErrorCodes.INVALID_METADATA,
      'metadata must be a JSON object (not array or null)'
    );
  }
  return parsed;
}

function validateMillSheet(hash, uri) {
  if (hash !== undefined && hash !== null && hash !== '') {
    if (typeof hash !== 'string' || !MILL_SHEET_HASH_PATTERN.test(hash)) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `millSheetHash must be 64 lowercase hex chars or empty, got=${hash}`
      );
    }
  }
  if (uri !== undefined && uri !== null && uri !== '') {
    if (typeof uri !== 'string' || uri.length > MILL_SHEET_URI_MAX_LEN) {
      throw new ChaincodeError(
        ErrorCodes.INVALID_ARGUMENT,
        `millSheetURI must be a string up to ${MILL_SHEET_URI_MAX_LEN} chars`
      );
    }
  }
}

// 配列を決定的順序 (ascending string sort) に正規化して新しい配列を返す
function normalizeIds(arr) {
  return [...arr].sort();
}

module.exports = {
  VALID_MSPS,
  MANUFACTURER_MSPS,
  getTxTimestampISO,
  getActor,
  isValidMsp,
  isManufacturerMsp,
  parseMetadata,
  validateMillSheet,
  normalizeIds,
};
