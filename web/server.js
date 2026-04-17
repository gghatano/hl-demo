'use strict';

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const grpc = require('@grpc/grpc-js');
const { connect, signers } = require('@hyperledger/fabric-gateway');
const express = require('express');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
const PORT = process.env.PORT || 3000;
const CHANNEL_NAME = process.env.CHANNEL_NAME || 'supplychannel';
const CC_NAME = process.env.CC_NAME || 'product-trace';

const REPO_ROOT = path.resolve(__dirname, '..');
const TEST_NET_DIR = path.join(REPO_ROOT, 'fabric', 'fabric-samples', 'test-network');
const ORGS_DIR = path.join(TEST_NET_DIR, 'organizations', 'peerOrganizations');

const ORG_CONFIG = {
  org1: { mspId: 'Org1MSP', peerEndpoint: 'localhost:7051', peerHostAlias: 'peer0.org1.example.com', label: 'メーカー A' },
  org2: { mspId: 'Org2MSP', peerEndpoint: 'localhost:9051', peerHostAlias: 'peer0.org2.example.com', label: '卸 B' },
  org3: { mspId: 'Org3MSP', peerEndpoint: 'localhost:11051', peerHostAlias: 'peer0.org3.example.com', label: '販売店 C' },
};

// ---------------------------------------------------------------------------
// Fabric Gateway helpers
// ---------------------------------------------------------------------------

function findPrivateKey(keyDir) {
  const files = fs.readdirSync(keyDir);
  const skFile = files.find((f) => f.endsWith('_sk'));
  if (!skFile) throw new Error(`No private key (*_sk) found in ${keyDir}`);
  return path.join(keyDir, skFile);
}

function orgPaths(orgName) {
  const n = orgName.replace('org', '');
  const orgDomain = `org${n}.example.com`;
  const peerOrg = path.join(ORGS_DIR, orgDomain);
  return {
    tlsCert: path.join(peerOrg, 'peers', `peer0.${orgDomain}`, 'tls', 'ca.crt'),
    certPath: path.join(peerOrg, 'users', `Admin@${orgDomain}`, 'msp', 'signcerts', 'cert.pem'),
    keyDir: path.join(peerOrg, 'users', `Admin@${orgDomain}`, 'msp', 'keystore'),
  };
}

async function newGrpcConnection(orgName) {
  const { tlsCert } = orgPaths(orgName);
  const tlsRootCert = fs.readFileSync(tlsCert);
  const tlsCredentials = grpc.credentials.createSsl(tlsRootCert);
  const cfg = ORG_CONFIG[orgName];
  return new grpc.Client(cfg.peerEndpoint, tlsCredentials, {
    'grpc.ssl_target_name_override': cfg.peerHostAlias,
  });
}

function newIdentity(orgName) {
  const { certPath } = orgPaths(orgName);
  const credentials = fs.readFileSync(certPath);
  return { mspId: ORG_CONFIG[orgName].mspId, credentials };
}

function newSigner(orgName) {
  const { keyDir } = orgPaths(orgName);
  const keyPath = findPrivateKey(keyDir);
  const privateKeyPem = fs.readFileSync(keyPath);
  const privateKey = crypto.createPrivateKey(privateKeyPem);
  return signers.newPrivateKeySigner(privateKey);
}

// Cache gateway connections per org
const gatewayCache = {};

async function getGateway(orgName) {
  if (gatewayCache[orgName]) return gatewayCache[orgName];
  const client = await newGrpcConnection(orgName);
  const gateway = connect({
    client,
    identity: newIdentity(orgName),
    signer: newSigner(orgName),
    evaluateOptions: () => ({ deadline: Date.now() + 5000 }),
    endorseOptions: () => ({ deadline: Date.now() + 15000 }),
    submitOptions: () => ({ deadline: Date.now() + 5000 }),
    commitStatusOptions: () => ({ deadline: Date.now() + 60000 }),
  });
  gatewayCache[orgName] = { gateway, client };
  return { gateway, client };
}

async function getContract(orgName) {
  const { gateway } = await getGateway(orgName);
  const network = gateway.getNetwork(CHANNEL_NAME);
  return network.getContract(CC_NAME);
}

// ---------------------------------------------------------------------------
// Express App
// ---------------------------------------------------------------------------

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Org validation middleware
function resolveOrg(req, res, next) {
  const org = req.query.org || req.headers['x-org'] || 'org1';
  if (!ORG_CONFIG[org]) {
    return res.status(400).json({ error: `Invalid org: ${org}. Use org1, org2, or org3` });
  }
  req.org = org;
  next();
}

// GET /api/orgs — list available orgs
app.get('/api/orgs', (_req, res) => {
  const orgs = Object.entries(ORG_CONFIG).map(([key, cfg]) => ({
    key,
    mspId: cfg.mspId,
    label: cfg.label,
  }));
  res.json(orgs);
});

// POST /api/products — CreateProduct
app.post('/api/products', resolveOrg, async (req, res) => {
  try {
    const { productId } = req.body;
    if (!productId) return res.status(400).json({ error: 'productId is required' });
    const contract = await getContract(req.org);
    const mspId = ORG_CONFIG[req.org].mspId;
    const result = await contract.submitTransaction('CreateProduct', productId, mspId, mspId);
    res.json(JSON.parse(result.toString()));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(400).json({ error: msg });
  }
});

// POST /api/products/:id/transfer — TransferProduct
app.post('/api/products/:id/transfer', resolveOrg, async (req, res) => {
  try {
    const { id } = req.params;
    const { toOwner } = req.body;
    if (!toOwner) return res.status(400).json({ error: 'toOwner is required' });
    const contract = await getContract(req.org);
    const fromOwner = ORG_CONFIG[req.org].mspId;
    const result = await contract.submitTransaction('TransferProduct', id, fromOwner, toOwner);
    res.json(JSON.parse(result.toString()));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(400).json({ error: msg });
  }
});

// GET /api/products/:id — ReadProduct
app.get('/api/products/:id', resolveOrg, async (req, res) => {
  try {
    const contract = await getContract(req.org);
    const result = await contract.evaluateTransaction('ReadProduct', req.params.id);
    res.json(JSON.parse(result.toString()));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(404).json({ error: msg });
  }
});

// GET /api/products/:id/history — GetHistory
app.get('/api/products/:id/history', resolveOrg, async (req, res) => {
  try {
    const contract = await getContract(req.org);
    const result = await contract.evaluateTransaction('GetHistory', req.params.id);
    res.json(JSON.parse(result.toString()));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(404).json({ error: msg });
  }
});

// ---------------------------------------------------------------------------
// Error extraction
// ---------------------------------------------------------------------------

function extractChaincodeError(err) {
  // fabric-gateway wraps chaincode errors in details
  if (err.details && err.details.length > 0) {
    for (const detail of err.details) {
      if (detail.message) return detail.message;
    }
  }
  // Fallback: try to extract from message string
  const match = err.message && err.message.match(/message=(.+?)(?:,|$)/);
  if (match) return match[1].trim();
  return err.message || 'Unknown error';
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

app.listen(PORT, () => {
  console.log(`[web-demo] Server running at http://localhost:${PORT}`);
  console.log(`[web-demo] Fabric channel=${CHANNEL_NAME} chaincode=${CC_NAME}`);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n[web-demo] Shutting down...');
  for (const [org, cached] of Object.entries(gatewayCache)) {
    try { cached.gateway.close(); } catch (_) {}
    try { cached.client.close(); } catch (_) {}
  }
  process.exit(0);
});
