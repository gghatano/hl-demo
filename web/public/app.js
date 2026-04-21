'use strict';

// ---------------------------------------------------------------------------
// MSP label map (Phase 8: 5Org)
// ---------------------------------------------------------------------------
const MSP_LABELS = {
  Org1MSP: '高炉メーカー A',
  Org2MSP: '電炉メーカー X',
  Org3MSP: '加工業者 B',
  Org4MSP: '加工業者 Y',
  Org5MSP: '建設会社 D',
};

const ORG_KEYS = ['org1', 'org2', 'org3', 'org4', 'org5'];
const ORG_MSP_MAP = {
  org1: 'Org1MSP', org2: 'Org2MSP', org3: 'Org3MSP', org4: 'Org4MSP', org5: 'Org5MSP',
};
const ALL_MSPS = Object.values(ORG_MSP_MAP);

function mspLabel(mspId) {
  return MSP_LABELS[mspId] || mspId;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
let currentOrg = 'org1';

const orgSelect = document.getElementById('orgSelect');
const orgBadge = document.getElementById('orgBadge');
const resultArea = document.getElementById('resultArea');

// Mermaid init
mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });

// ---------------------------------------------------------------------------
// Org switch
// ---------------------------------------------------------------------------
orgSelect.addEventListener('change', () => {
  currentOrg = orgSelect.value;
  document.body.className = currentOrg;
  orgBadge.className = `badge ${currentOrg}`;
  orgBadge.textContent = ORG_MSP_MAP[currentOrg];
});
document.body.className = currentOrg;

// ---------------------------------------------------------------------------
// API helper
// ---------------------------------------------------------------------------
async function apiCall(method, path, body) {
  const sep = path.includes('?') ? '&' : '?';
  const url = `${path}${sep}org=${currentOrg}`;
  const opts = { method, headers: {} };
  if (body) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(url, opts);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function showLoading() {
  resultArea.innerHTML = '<div class="loading">処理中...</div>';
}
function showError(msg) {
  resultArea.innerHTML = `<div class="result-error">${escapeHtml(msg)}</div>`;
}
function showSuccess(label, data) {
  resultArea.innerHTML =
    `<div class="result-success"><strong>${escapeHtml(label)}</strong></div>` +
    `<pre>${escapeHtml(JSON.stringify(data, null, 2))}</pre>`;
}
function escapeHtml(s) {
  const d = document.createElement('div');
  d.textContent = String(s);
  return d.innerHTML;
}

// ---------------------------------------------------------------------------
// SHA-256 helper (ブラウザ側で PDF ハッシュ計算)
// ---------------------------------------------------------------------------
async function sha256Hex(fileOrBuffer) {
  const buf = fileOrBuffer instanceof ArrayBuffer ? fileOrBuffer : await fileOrBuffer.arrayBuffer();
  const hashBuf = await crypto.subtle.digest('SHA-256', buf);
  return Array.from(new Uint8Array(hashBuf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

// ---------------------------------------------------------------------------
// CreateProduct
// ---------------------------------------------------------------------------
const createMillSheetFile = document.getElementById('createMillSheetFile');
const createMillSheetHashLabel = document.getElementById('createMillSheetHashLabel');
createMillSheetFile.addEventListener('change', async () => {
  createMillSheetHashLabel.textContent = '';
  const file = createMillSheetFile.files[0];
  if (!file) return;
  try {
    const hash = await sha256Hex(file);
    createMillSheetHashLabel.textContent = `SHA-256: ${hash.substring(0, 16)}...`;
    createMillSheetHashLabel.dataset.hash = hash;
  } catch (e) {
    createMillSheetHashLabel.textContent = `ハッシュ計算失敗: ${e.message}`;
  }
});

document.getElementById('btnCreate').addEventListener('click', async () => {
  const productId = document.getElementById('createProductId').value.trim();
  if (!productId) return showError('素材 ID を入力してください');
  const metadataRaw = document.getElementById('createMetadata').value.trim();
  const millSheetURI = document.getElementById('createMillSheetURI').value.trim();
  const millSheetHash = createMillSheetHashLabel.dataset.hash || '';
  let metadata;
  if (metadataRaw) {
    try { metadata = JSON.parse(metadataRaw); }
    catch (e) { return showError(`metadata JSON が不正: ${e.message}`); }
  }
  showLoading();
  try {
    const data = await apiCall('POST', '/api/products', {
      productId, metadata, millSheetHash, millSheetURI,
    });
    showSuccess(`素材を登録しました: ${productId}`, data);
  } catch (e) {
    showError(e.message);
  }
});

// ---------------------------------------------------------------------------
// TransferProduct
// ---------------------------------------------------------------------------
document.getElementById('btnTransfer').addEventListener('click', async () => {
  const productId = document.getElementById('transferProductId').value.trim();
  const toOwner = document.getElementById('transferTo').value;
  if (!productId) return showError('素材 ID を入力してください');
  showLoading();
  try {
    const data = await apiCall('POST', `/api/products/${encodeURIComponent(productId)}/transfer`, { toOwner });
    showSuccess('譲渡が完了しました', data);
  } catch (e) {
    showError(e.message);
  }
});

// ---------------------------------------------------------------------------
// Split UI - dynamic child rows
// ---------------------------------------------------------------------------
const splitChildrenDiv = document.getElementById('splitChildren');
let splitChildCount = 0;

function addSplitChildRow() {
  splitChildCount += 1;
  const idx = splitChildCount;
  const row = document.createElement('div');
  row.className = 'child-row';
  row.dataset.idx = String(idx);
  row.innerHTML = `
    <span class="child-label">子 #${idx}</span>
    <input type="text" placeholder="childId (例: S1-a)" class="child-id">
    <select class="child-owner">
      ${ALL_MSPS.map((m) => `<option value="${m}">${m} - ${escapeHtml(mspLabel(m))}</option>`).join('')}
    </select>
    <input type="text" placeholder='metadata JSON (省略可: {"weightKg":3000})' class="child-meta">
    <button type="button" class="btn-remove">削除</button>
  `;
  row.querySelector('.btn-remove').addEventListener('click', () => row.remove());
  splitChildrenDiv.appendChild(row);
}
// 初期表示で 2 行
addSplitChildRow();
addSplitChildRow();

document.getElementById('btnAddSplitChild').addEventListener('click', addSplitChildRow);

document.getElementById('btnSplit').addEventListener('click', async () => {
  const parentId = document.getElementById('splitParentId').value.trim();
  if (!parentId) return showError('親 ID を入力してください');
  const rows = splitChildrenDiv.querySelectorAll('.child-row');
  const children = [];
  for (const row of rows) {
    const childId = row.querySelector('.child-id').value.trim();
    const toOwner = row.querySelector('.child-owner').value;
    const metaRaw = row.querySelector('.child-meta').value.trim();
    if (!childId) continue;
    let metadata;
    if (metaRaw) {
      try { metadata = JSON.parse(metaRaw); }
      catch (e) { return showError(`子 ${childId} の metadata JSON 不正: ${e.message}`); }
    }
    children.push({ childId, toOwner, metadata });
  }
  if (children.length < 2) return showError('子は 2 個以上必要です');
  showLoading();
  try {
    const data = await apiCall('POST', `/api/products/${encodeURIComponent(parentId)}/split`, { children });
    showSuccess(`分割が完了しました: ${parentId} → ${children.map((c) => c.childId).join(', ')}`, data);
  } catch (e) {
    showError(e.message);
  }
});

// ---------------------------------------------------------------------------
// Merge UI - dynamic parent rows
// ---------------------------------------------------------------------------
const mergeParentsDiv = document.getElementById('mergeParents');
let mergeParentCount = 0;

function addMergeParentRow() {
  mergeParentCount += 1;
  const row = document.createElement('div');
  row.className = 'parent-row';
  row.innerHTML = `
    <input type="text" placeholder="親 productId (例: S1-a)" class="parent-id">
    <button type="button" class="btn-remove">削除</button>
  `;
  row.querySelector('.btn-remove').addEventListener('click', () => row.remove());
  mergeParentsDiv.appendChild(row);
}
addMergeParentRow();
addMergeParentRow();
document.getElementById('btnAddMergeParent').addEventListener('click', addMergeParentRow);

document.getElementById('btnMerge').addEventListener('click', async () => {
  const rows = mergeParentsDiv.querySelectorAll('.parent-row');
  const parentIds = [];
  for (const row of rows) {
    const pid = row.querySelector('.parent-id').value.trim();
    if (pid) parentIds.push(pid);
  }
  if (parentIds.length < 2) return showError('親は 2 個以上必要です');
  const childId = document.getElementById('mergeChildId').value.trim();
  if (!childId) return showError('子 ID を入力してください');
  const metaRaw = document.getElementById('mergeMetadata').value.trim();
  let metadata;
  if (metaRaw) {
    try { metadata = JSON.parse(metaRaw); }
    catch (e) { return showError(`metadata JSON 不正: ${e.message}`); }
  }
  showLoading();
  try {
    const data = await apiCall('POST', '/api/products/merge', {
      parentIds,
      child: { childId, metadata },
    });
    showSuccess(`接合が完了しました: [${parentIds.join(',')}] → ${childId}`, data);
  } catch (e) {
    showError(e.message);
  }
});

// ---------------------------------------------------------------------------
// ReadProduct
// ---------------------------------------------------------------------------
document.getElementById('btnRead').addEventListener('click', async () => {
  const productId = document.getElementById('readProductId').value.trim();
  if (!productId) return showError('素材 ID を入力してください');
  showLoading();
  try {
    const data = await apiCall('GET', `/api/products/${encodeURIComponent(productId)}`);
    const label = `素材 ${productId} の状態`;
    resultArea.innerHTML =
      `<div class="result-success"><strong>${escapeHtml(label)}</strong></div>` +
      productCard(data) +
      `<pre>${escapeHtml(JSON.stringify(data, null, 2))}</pre>`;
  } catch (e) {
    showError(e.message);
  }
});

function productCard(p) {
  return `
    <div class="product-card">
      <div><b>productId</b>: ${escapeHtml(p.productId)}</div>
      <div><b>製造元</b>: ${escapeHtml(mspLabel(p.manufacturer))} (${escapeHtml(p.manufacturer)})</div>
      <div><b>現所有者</b>: ${escapeHtml(mspLabel(p.currentOwner))} (${escapeHtml(p.currentOwner)})</div>
      <div><b>status</b>: <span class="status-${escapeHtml(p.status)}">${escapeHtml(p.status)}</span></div>
      <div><b>parents</b>: ${(p.parents || []).map(escapeHtml).join(', ') || '(none)'}</div>
      <div><b>children</b>: ${(p.children || []).map(escapeHtml).join(', ') || '(none)'}</div>
      <div><b>metadata</b>: <code>${escapeHtml(JSON.stringify(p.metadata || {}))}</code></div>
      <div><b>millSheetURI</b>: ${p.millSheetURI ? `<a href="${escapeHtml(p.millSheetURI)}" target="_blank">${escapeHtml(p.millSheetURI)}</a>` : '(none)'}</div>
      <div><b>millSheetHash</b>: <code>${escapeHtml((p.millSheetHash || '').substring(0, 16))}${p.millSheetHash ? '…' : ''}</code></div>
    </div>
  `;
}

// ---------------------------------------------------------------------------
// GetHistory
// ---------------------------------------------------------------------------
document.getElementById('btnHistory').addEventListener('click', async () => {
  const productId = document.getElementById('historyProductId').value.trim();
  if (!productId) return showError('素材 ID を入力してください');
  showLoading();
  try {
    const events = await apiCall('GET', `/api/products/${encodeURIComponent(productId)}/history`);
    renderHistory(productId, events);
  } catch (e) {
    showError(e.message);
  }
});

function renderHistory(productId, events) {
  if (!events || events.length === 0) {
    resultArea.innerHTML = '<div class="result-error">履歴が見つかりません</div>';
    return;
  }
  let timelineHtml = '<ul class="timeline">';
  for (const ev of events) {
    const cls = `event-${ev.eventType}`;
    let detail;
    switch (ev.eventType) {
      case 'CREATE':
        detail = `登録者: ${escapeHtml(mspLabel(ev.toOwner))}`;
        break;
      case 'TRANSFER':
        detail = `${escapeHtml(mspLabel(ev.fromOwner))} → ${escapeHtml(mspLabel(ev.toOwner))}`;
        break;
      case 'SPLIT':
        detail = `分割 → 子: [${(ev.children || []).map(escapeHtml).join(', ')}]`;
        break;
      case 'MERGE':
        detail = `接合 → 子: ${escapeHtml((ev.children || [])[0] || '?')}`;
        break;
      case 'SPLIT_FROM':
        detail = `分割由来。親: [${(ev.parents || []).map(escapeHtml).join(', ')}]`;
        break;
      case 'MERGE_FROM':
        detail = `接合由来。親: [${(ev.parents || []).map(escapeHtml).join(', ')}]`;
        break;
      default:
        detail = JSON.stringify(ev);
    }
    const actor = ev.actor && ev.actor.mspId ? escapeHtml(mspLabel(ev.actor.mspId)) : '-';
    const ts = ev.timestamp ? new Date(ev.timestamp).toLocaleString('ja-JP') : '';
    const txShort = ev.txId ? ev.txId.substring(0, 12) + '…' : '';
    timelineHtml += `
      <li class="${cls}">
        <div class="event-type">${escapeHtml(ev.eventType)}</div>
        <div class="event-detail">${detail}</div>
        <div class="event-detail">actor: ${actor} | ${escapeHtml(ts)}${txShort ? ' | tx: ' + escapeHtml(txShort) : ''}</div>
      </li>`;
  }
  timelineHtml += '</ul>';
  resultArea.innerHTML =
    `<div class="result-success"><strong>履歴: ${escapeHtml(productId)}</strong></div>` +
    timelineHtml;
}

// ---------------------------------------------------------------------------
// GetLineage — Mermaid DAG
// ---------------------------------------------------------------------------
document.getElementById('btnLineage').addEventListener('click', async () => {
  const productId = document.getElementById('lineageProductId').value.trim();
  if (!productId) return showError('素材 ID を入力してください');
  showLoading();
  try {
    const lineage = await apiCall('GET', `/api/products/${encodeURIComponent(productId)}/lineage`);
    await renderLineage(productId, lineage);
  } catch (e) {
    showError(e.message);
  }
});

async function renderLineage(productId, lineage) {
  const { nodes, edges } = lineage;
  // Mermaid graph: flowchart TD
  // root にアスタリスク
  const nodeLines = nodes.map((n) => {
    const isRoot = n.id === productId;
    const label = `${n.id}${isRoot ? ' ⭐' : ''}<br/>${mspLabel(n.manufacturer)}<br/><small>${n.status}</small>`;
    // Mermaid の node id にハイフン等が含まれると壊れるため quote
    const safe = n.id.replace(/[^A-Za-z0-9_]/g, '_');
    return `  ${safe}["${label}"]`;
  }).join('\n');

  const edgeLines = edges.map((e) => {
    const from = e.from.replace(/[^A-Za-z0-9_]/g, '_');
    const to = e.to.replace(/[^A-Za-z0-9_]/g, '_');
    const arrow = e.type === 'SPLIT' ? '-->' : '==>';
    const label = e.type;
    return `  ${from} ${arrow}|${label}| ${to}`;
  }).join('\n');

  // CONSUMED ノードに class 付与
  const classLines = nodes
    .filter((n) => n.status === 'CONSUMED')
    .map((n) => `  class ${n.id.replace(/[^A-Za-z0-9_]/g, '_')} consumed;`)
    .join('\n');

  const mermaidSrc = `flowchart TD
${nodeLines}
${edgeLines}
${classLines}
  classDef consumed fill:#eee,stroke:#888,stroke-dasharray: 5 5,color:#555;
`;

  // Render
  const containerId = `mermaidContainer_${Date.now()}`;
  resultArea.innerHTML = `
    <div class="result-success"><strong>系譜 DAG: ${escapeHtml(productId)}</strong></div>
    <div class="lineage-meta">nodes=${nodes.length}, edges=${edges.length}</div>
    <div id="${containerId}" class="mermaid-container"></div>
    <details>
      <summary>ノード詳細</summary>
      <pre>${escapeHtml(JSON.stringify(nodes, null, 2))}</pre>
    </details>
    <details>
      <summary>Mermaid source</summary>
      <pre>${escapeHtml(mermaidSrc)}</pre>
    </details>
  `;
  try {
    const { svg } = await mermaid.render(`svg_${containerId}`, mermaidSrc);
    document.getElementById(containerId).innerHTML = svg;
  } catch (e) {
    document.getElementById(containerId).innerHTML = `<div class="result-error">Mermaid レンダ失敗: ${escapeHtml(e.message)}</div>`;
  }
}
