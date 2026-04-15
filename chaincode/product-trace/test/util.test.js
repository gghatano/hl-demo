'use strict';

const chai = require('chai');
const { expect } = chai;

const { getTxTimestampISO, getActor } = require('../lib/util');
const { createMockContext } = require('./helpers/mock-ctx');

describe('util', () => {
  describe('getTxTimestampISO', () => {
    it('returns deterministic ISO8601 string', () => {
      const ctx = createMockContext({ txTimestampISO: '2026-04-15T10:00:00.000Z' });
      expect(getTxTimestampISO(ctx)).to.equal('2026-04-15T10:00:00.000Z');
    });

    it('does not depend on wall clock (repeat call returns same value)', () => {
      const ctx = createMockContext({ txTimestampISO: '2026-01-01T00:00:00.000Z' });
      const a = getTxTimestampISO(ctx);
      const b = getTxTimestampISO(ctx);
      expect(a).to.equal(b);
    });
  });

  describe('getActor', () => {
    it('returns mspId and id from clientIdentity', () => {
      const ctx = createMockContext({ mspId: 'Org2MSP', identityId: 'x509::CN=Alice' });
      expect(getActor(ctx)).to.deep.equal({ mspId: 'Org2MSP', id: 'x509::CN=Alice' });
    });
  });
});
