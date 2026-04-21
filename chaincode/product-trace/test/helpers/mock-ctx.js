'use strict';

const sinon = require('sinon');

// fabric-contract-api の Context を差し替える軽量モック。
// tests は stub/clientIdentity を直接操作して入出力をシミュレートする。

function makeTimestamp(isoString) {
  const ms = new Date(isoString).getTime();
  return {
    seconds: { toNumber: () => Math.floor(ms / 1000), low: Math.floor(ms / 1000), high: 0 },
    nanos: (ms % 1000) * 1e6,
  };
}

// getTxTimestampISO は Number(ts.seconds) を使うので、seconds は数値 or toNumber 持ち object どちらでも OK にする
function makeTimestampNumeric(isoString) {
  const ms = new Date(isoString).getTime();
  return {
    seconds: Math.floor(ms / 1000),
    nanos: (ms % 1000) * 1e6,
  };
}

function createMockContext({ mspId = 'Org1MSP', identityId = 'x509::CN=Admin@org1', txId = 'tx-1', txTimestampISO = '2026-04-15T10:00:00.000Z', store } = {}) {
  // store は任意。未指定なら新規 Map。複数 ctx 間で state を共有したい場合は同じ Map を渡す。
  const sharedStore = store || new Map();

  const stub = {
    getState: sinon.stub().callsFake(async (key) => {
      if (!sharedStore.has(key)) return Buffer.from('');
      return sharedStore.get(key);
    }),
    putState: sinon.stub().callsFake(async (key, value) => {
      sharedStore.set(key, value);
    }),
    getTxID: sinon.stub().returns(txId),
    getTxTimestamp: sinon.stub().returns(makeTimestampNumeric(txTimestampISO)),
    getHistoryForKey: sinon.stub(),
    _store: sharedStore,
  };

  const clientIdentity = {
    getMSPID: sinon.stub().returns(mspId),
    getID: sinon.stub().returns(identityId),
  };

  return { stub, clientIdentity };
}

// 履歴イテレータのモック。降順（新→旧）順で entries を渡す想定（実 Fabric と同じ）
function makeHistoryIterator(entries) {
  let i = 0;
  return {
    next: sinon.stub().callsFake(async () => {
      if (i >= entries.length) {
        return { value: null, done: true };
      }
      const v = entries[i];
      i += 1;
      return { value: v, done: i >= entries.length };
    }),
    close: sinon.stub().resolves(),
  };
}

function makeHistoryEntry({ txId, timestampISO, isDelete = false, value }) {
  const ms = new Date(timestampISO).getTime();
  return {
    txId,
    timestamp: {
      seconds: Math.floor(ms / 1000),
      nanos: (ms % 1000) * 1e6,
    },
    isDelete,
    value: value == null ? Buffer.from('') : Buffer.from(JSON.stringify(value)),
  };
}

module.exports = {
  createMockContext,
  makeHistoryIterator,
  makeHistoryEntry,
};
