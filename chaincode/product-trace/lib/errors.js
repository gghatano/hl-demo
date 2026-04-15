'use strict';

class ChaincodeError extends Error {
  constructor(code, message) {
    super(message);
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
