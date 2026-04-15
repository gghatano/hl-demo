'use strict';

// message 先頭に [CODE] プレフィックスを付与する。
// chaincode error は endorsement response では message 本文しか乗らないため、
// クライアント側（invoke_as.sh / test_integration.sh など）で grep しやすいよう
// コード情報を message に埋め込んでおく。
class ChaincodeError extends Error {
  constructor(code, message) {
    super(`[${code}] ${message}`);
    this.name = 'ChaincodeError';
    this.code = code;
  }
}

const ErrorCodes = {
  PRODUCT_ALREADY_EXISTS: 'PRODUCT_ALREADY_EXISTS',
  PRODUCT_NOT_FOUND: 'PRODUCT_NOT_FOUND',
  OWNER_MISMATCH: 'OWNER_MISMATCH',
  MSP_NOT_AUTHORIZED: 'MSP_NOT_AUTHORIZED',
  INITIAL_OWNER_MISMATCH: 'INITIAL_OWNER_MISMATCH',
  INVALID_ARGUMENT: 'INVALID_ARGUMENT',
};

module.exports = { ChaincodeError, ErrorCodes };
