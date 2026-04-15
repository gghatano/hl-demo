'use strict';

// 決定性ユーティリティ
// Date.now() / Math.random() / process.env 等の非決定性 API は chaincode 内で使用禁止
// 全 endorser で同一値となる ctx.stub 由来のデータのみ使う

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

module.exports = { getTxTimestampISO, getActor };
