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

const REPO_ROOT = process.env.FABRIC_REPO_ROOT || path.resolve(__dirname, '..');
const TEST_NET_DIR = path.join(REPO_ROOT, 'fabric', 'fabric-samples', 'test-network');
const ORGS_DIR = path.join(TEST_NET_DIR, 'organizations', 'peerOrganizations');

const ORG_CONFIG = {
  org1: { mspId: 'Org1MSP', peerEndpoint: 'localhost:7051',  peerHostAlias: 'peer0.org1.example.com', label: '高炉メーカー A' },
  org2: { mspId: 'Org2MSP', peerEndpoint: 'localhost:9051',  peerHostAlias: 'peer0.org2.example.com', label: '電炉メーカー X' },
  org3: { mspId: 'Org3MSP', peerEndpoint: 'localhost:11051', peerHostAlias: 'peer0.org3.example.com', label: '加工業者 B' },
  org4: { mspId: 'Org4MSP', peerEndpoint: 'localhost:13051', peerHostAlias: 'peer0.org4.example.com', label: '加工業者 Y' },
  org5: { mspId: 'Org5MSP', peerEndpoint: 'localhost:15051', peerHostAlias: 'peer0.org5.example.com', label: '建設会社 D' },
};

const MANUFACTURER_MSPS = ['Org1MSP', 'Org2MSP'];

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

// fabric-gateway returns Uint8Array; .toString() yields comma-separated bytes
const utf8Decoder = new TextDecoder();
function decodeResult(result) {
  return utf8Decoder.decode(result);
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
    const valid = Object.keys(ORG_CONFIG).join(', ');
    return res.status(400).json({ error: `Invalid org: ${org}. Use one of: ${valid}` });
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

// POST /api/products — CreateProduct (v2: metadata + millSheet support)
app.post('/api/products', resolveOrg, async (req, res) => {
  try {
    const { productId, metadata, millSheetHash, millSheetURI } = req.body;
    if (!productId) return res.status(400).json({ error: 'productId is required' });
    const mspId = ORG_CONFIG[req.org].mspId;
    if (!MANUFACTURER_MSPS.includes(mspId)) {
      return res.status(403).json({ error: `Only manufacturer orgs (Org1MSP/Org2MSP) can CreateProduct. Caller=${mspId}` });
    }
    const contract = await getContract(req.org);
    const metadataJson = metadata === undefined ? '' : (typeof metadata === 'string' ? metadata : JSON.stringify(metadata));
    const result = await contract.submitTransaction(
      'CreateProduct',
      productId, mspId, mspId,
      metadataJson,
      millSheetHash || '',
      millSheetURI || ''
    );
    res.json(JSON.parse(decodeResult(result)));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(400).json({ error: msg });
  }
});

// POST /api/products/:id/split — SplitProduct (v2)
// body: { children: [{ childId, toOwner, metadata?, millSheetHash?, millSheetURI? }, ...] }
app.post('/api/products/:id/split', resolveOrg, async (req, res) => {
  try {
    const { id } = req.params;
    const { children } = req.body;
    if (!Array.isArray(children) || children.length < 2) {
      return res.status(400).json({ error: 'children must be an array with at least 2 elements' });
    }
    const childrenForCc = children.map((c) => ({
      childId: c.childId,
      toOwner: c.toOwner,
      metadataJson: c.metadata === undefined ? '' : (typeof c.metadata === 'string' ? c.metadata : JSON.stringify(c.metadata)),
      millSheetHash: c.millSheetHash || '',
      millSheetURI: c.millSheetURI || '',
    }));
    const contract = await getContract(req.org);
    const result = await contract.submitTransaction('SplitProduct', id, JSON.stringify(childrenForCc));
    res.json(JSON.parse(decodeResult(result)));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(400).json({ error: msg });
  }
});

// POST /api/products/merge — MergeProducts (v2)
// body: { parentIds: [...], child: { childId, metadata?, millSheetHash?, millSheetURI? } }
app.post('/api/products/merge', resolveOrg, async (req, res) => {
  try {
    const { parentIds, child } = req.body;
    if (!Array.isArray(parentIds) || parentIds.length < 2) {
      return res.status(400).json({ error: 'parentIds must be an array with at least 2 elements' });
    }
    if (!child || !child.childId) return res.status(400).json({ error: 'child.childId is required' });
    const childForCc = {
      childId: child.childId,
      metadataJson: child.metadata === undefined ? '' : (typeof child.metadata === 'string' ? child.metadata : JSON.stringify(child.metadata)),
      millSheetHash: child.millSheetHash || '',
      millSheetURI: child.millSheetURI || '',
    };
    const contract = await getContract(req.org);
    const result = await contract.submitTransaction('MergeProducts', JSON.stringify(parentIds), JSON.stringify(childForCc));
    res.json(JSON.parse(decodeResult(result)));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(400).json({ error: msg });
  }
});

// GET /api/products/:id/lineage — GetLineage (v2)
app.get('/api/products/:id/lineage', resolveOrg, async (req, res) => {
  try {
    const contract = await getContract(req.org);
    const result = await contract.evaluateTransaction('GetLineage', req.params.id);
    res.json(JSON.parse(decodeResult(result)));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(404).json({ error: msg });
  }
});

// GET /api/products?owner=Org3MSP — ListProductsByOwner
// org クエリは「どの組織として query するか」(evaluateTransaction 用)
// owner クエリは「どの MSP が保有する product を列挙するか」
// owner 未指定時は現 org の MSP をデフォルトにする。
app.get('/api/products', resolveOrg, async (req, res) => {
  try {
    const ownerMspId = req.query.owner || ORG_CONFIG[req.org].mspId;
    const contract = await getContract(req.org);
    const result = await contract.evaluateTransaction('ListProductsByOwner', ownerMspId);
    res.json(JSON.parse(decodeResult(result)));
  } catch (err) {
    const msg = extractChaincodeError(err);
    res.status(500).json({ error: msg });
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
    res.json(JSON.parse(decodeResult(result)));
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
    res.json(JSON.parse(decodeResult(result)));
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
    res.json(JSON.parse(decodeResult(result)));
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
