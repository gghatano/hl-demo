'use strict';

// =============================================================================
// 定数
// =============================================================================
const MSP_LABELS = {
  Org1MSP: '高炉メーカー A',
  Org2MSP: '電炉メーカー X',
  Org3MSP: '加工業者 B',
  Org4MSP: '加工業者 Y',
  Org5MSP: '建設会社 D',
};
const ORG_MSP_MAP = {
  org1: 'Org1MSP', org2: 'Org2MSP', org3: 'Org3MSP', org4: 'Org4MSP', org5: 'Org5MSP',
};
const ALL_MSPS = Object.values(ORG_MSP_MAP);
const STATUS_LABEL = { ACTIVE: '使用可', CONSUMED: '消費済' };
const mspLabel = (id) => MSP_LABELS[id] || id;

// =============================================================================
// State
// =============================================================================
let currentOrg = 'org1';
const orgSelect = document.getElementById('orgSelect');

mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });

// =============================================================================
// Utility
// =============================================================================
function esc(s) {
  const d = document.createElement('div');
  d.textContent = String(s == null ? '' : s);
  return d.innerHTML;
}

async function api(method, path, body) {
  const sep = path.includes('?') ? '&' : '?';
  const url = `${path}${sep}org=${currentOrg}`;
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(url, opts);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

async function sha256Hex(file) {
  const buf = await file.arrayBuffer();
  const hashBuf = await crypto.subtle.digest('SHA-256', buf);
  return Array.from(new Uint8Array(hashBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function setResult(container, label, data, extraHtml = '') {
  container.innerHTML =
    `<div class="result-success"><strong>${esc(label)}</strong></div>` +
    extraHtml +
    `<details><summary>JSON 詳細</summary><pre>${esc(JSON.stringify(data, null, 2))}</pre></details>`;
}

function setError(container, msg) {
  container.innerHTML = `<div class="result-error">${esc(msg)}</div>`;
}

function setLoading(container) {
  container.innerHTML = '<div class="loading">処理中…</div>';
}

function productCard(p, opts = {}) {
  const statusCls = `status-${p.status}`;
  const { showLineageButton = false } = opts;
  const lineageBtn = showLineageButton
    ? `<button class="btn-lineage" data-product-id="${esc(p.productId)}">🔎 由来をたどる</button>`
    : '';
  return `
    <div class="product-card">
      <div class="pc-header">
        <span class="pc-id">${esc(p.productId)}</span>
        <span class="pc-status ${statusCls}">${esc(STATUS_LABEL[p.status] || p.status)}</span>
      </div>
      <div class="pc-row"><b>製造元</b>: ${esc(mspLabel(p.manufacturer))} <span class="msp-dim">(${esc(p.manufacturer)})</span></div>
      <div class="pc-row"><b>現所有者</b>: ${esc(mspLabel(p.currentOwner))} <span class="msp-dim">(${esc(p.currentOwner)})</span></div>
      <div class="pc-row"><b>親</b>: ${(p.parents || []).map(esc).join(', ') || '<span class="pc-none">なし (起点素材)</span>'}</div>
      <div class="pc-row"><b>子</b>: ${(p.children || []).map(esc).join(', ') || '<span class="pc-none">なし</span>'}</div>
      <div class="pc-row"><b>metadata</b>: <code>${esc(JSON.stringify(p.metadata || {}))}</code></div>
      ${p.millSheetURI ? `<div class="pc-row"><b>ミルシート</b>: <a href="${esc(p.millSheetURI)}" target="_blank">${esc(p.millSheetURI)}</a></div>` : ''}
      <div class="pc-row pc-dim">created: ${esc(p.createdAt)} / updated: ${esc(p.updatedAt)}</div>
      ${lineageBtn}
    </div>
  `;
}

// 画面遷移: 手持ち一覧のカードから「由来をたどる」 → 素材を調べる view に遷移 + 自動検索
function wireLineageButtons(container) {
  container.querySelectorAll('.btn-lineage').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const pid = btn.dataset.productId;
      searchProductId.value = pid;
      showView('viewSearch');
      runSearch();
    });
  });
}

// =============================================================================
// View 切替
// =============================================================================
const views = document.querySelectorAll('.view');
function showView(viewId) {
  for (const v of views) v.classList.remove('active');
  const target = document.getElementById(viewId);
  if (target) target.classList.add('active');
  window.scrollTo({ top: 0, behavior: 'smooth' });
  // ビュー固有の初期処理
  if (viewId === 'viewInventory') refreshInventory();
  if (viewId === 'viewTransfer') refreshTransferSelect();
  if (viewId === 'viewSplit') refreshSplitSelect();
  if (viewId === 'viewMerge') { /* 親行は常駐 */ }
}

document.querySelectorAll('[data-view]').forEach((btn) => {
  btn.addEventListener('click', (e) => {
    e.preventDefault();
    showView(btn.dataset.view);
  });
});
document.getElementById('btnHome').addEventListener('click', (e) => {
  e.preventDefault();
  showView('viewHome');
});

// =============================================================================
// Org 切替
// =============================================================================
function applyOrg() {
  document.body.className = currentOrg;
  // invOrgLabel update
  const lbl = document.getElementById('invOrgLabel');
  if (lbl) lbl.textContent = `${mspLabel(ORG_MSP_MAP[currentOrg])} (${ORG_MSP_MAP[currentOrg]})`;
  // 現在表示中の view が依存データあれば再読込
  const active = document.querySelector('.view.active');
  if (active) {
    if (active.id === 'viewInventory') refreshInventory();
    if (active.id === 'viewTransfer') refreshTransferSelect();
    if (active.id === 'viewSplit') refreshSplitSelect();
  }
}
orgSelect.addEventListener('change', () => {
  currentOrg = orgSelect.value;
  applyOrg();
});
applyOrg();

// =============================================================================
// 手持ち素材一覧
// =============================================================================
const inventoryList = document.getElementById('inventoryList');
const invShowConsumed = document.getElementById('invShowConsumed');
const btnInvRefresh = document.getElementById('btnInvRefresh');

async function refreshInventory() {
  setLoading(inventoryList);
  try {
    const products = await api('GET', '/api/products');
    const filtered = invShowConsumed.checked ? products : products.filter((p) => p.status === 'ACTIVE');
    if (filtered.length === 0) {
      inventoryList.innerHTML = '<div class="empty-note">該当する素材がありません。組織セレクタで切替、または「CONSUMED も表示」を ON にしてください。</div>';
      return;
    }
    const active = filtered.filter((p) => p.status === 'ACTIVE');
    const consumed = filtered.filter((p) => p.status === 'CONSUMED');
    let html = '';
    const cardOpts = { showLineageButton: true };
    if (active.length > 0) {
      html += `<h3 class="group-title">使用可 (ACTIVE) ${active.length} 件</h3>`;
      html += '<div class="product-grid">' + active.map((p) => productCard(p, cardOpts)).join('') + '</div>';
    }
    if (consumed.length > 0) {
      html += `<h3 class="group-title group-consumed">消費済 (CONSUMED) ${consumed.length} 件</h3>`;
      html += '<div class="product-grid">' + consumed.map((p) => productCard(p, cardOpts)).join('') + '</div>';
    }
    inventoryList.innerHTML = html;
    wireLineageButtons(inventoryList);
  } catch (e) {
    setError(inventoryList, `取得失敗: ${e.message}`);
  }
}
btnInvRefresh.addEventListener('click', refreshInventory);
invShowConsumed.addEventListener('change', refreshInventory);

// =============================================================================
// 素材を調べる (Read + History + Lineage)
// =============================================================================
const searchProductId = document.getElementById('searchProductId');
const searchResult = document.getElementById('searchResult');
document.getElementById('btnSearch').addEventListener('click', runSearch);
searchProductId.addEventListener('keydown', (e) => { if (e.key === 'Enter') runSearch(); });

async function runSearch() {
  const pid = searchProductId.value.trim();
  if (!pid) return setError(searchResult, '素材 ID を入力してください');
  setLoading(searchResult);
  try {
    const [product, history, lineage] = await Promise.all([
      api('GET', `/api/products/${encodeURIComponent(pid)}`),
      api('GET', `/api/products/${encodeURIComponent(pid)}/history`).catch(() => []),
      api('GET', `/api/products/${encodeURIComponent(pid)}/lineage`).catch(() => null),
    ]);
    const html = `
      <h3>現在の状態</h3>
      ${productCard(product)}
      <h3>履歴 (${history.length} 件)</h3>
      ${renderHistoryList(history)}
      <h3>祖先 DAG</h3>
      ${lineage ? `<div id="lineageContainer"></div>` : '<div class="empty-note">系譜情報なし</div>'}
    `;
    searchResult.innerHTML = html;
    if (lineage) {
      await renderLineageSvg(lineage, pid, 'lineageContainer');
    }
  } catch (e) {
    setError(searchResult, e.message);
  }
}

function renderHistoryList(events) {
  if (!events || events.length === 0) return '<div class="empty-note">履歴なし</div>';
  const items = events.map((ev) => {
    const type = ev.eventType;
    let detail = '';
    switch (type) {
      case 'CREATE':     detail = `${esc(mspLabel(ev.toOwner))} が新規登録`; break;
      case 'TRANSFER':   detail = `${esc(mspLabel(ev.fromOwner))} → ${esc(mspLabel(ev.toOwner))}`; break;
      case 'SPLIT':      detail = `${esc(mspLabel(ev.fromOwner))} が分割 (子: ${(ev.children || []).map(esc).join(', ')})`; break;
      case 'MERGE':      detail = `${esc(mspLabel(ev.fromOwner))} が接合素材として消費 (子: ${(ev.children || []).map(esc).join(', ')})`; break;
      case 'SPLIT_FROM': detail = `分割由来。親: ${(ev.parents || []).map(esc).join(', ')}`; break;
      case 'MERGE_FROM': detail = `接合由来。親: ${(ev.parents || []).map(esc).join(', ')}`; break;
      default:           detail = esc(JSON.stringify(ev));
    }
    const actor = ev.actor && ev.actor.mspId ? esc(mspLabel(ev.actor.mspId)) : '-';
    const ts = ev.timestamp ? new Date(ev.timestamp).toLocaleString('ja-JP') : '';
    return `
      <li class="event-${type}">
        <div class="event-type">${esc(type)}</div>
        <div class="event-detail">${detail}</div>
        <div class="event-detail event-dim">実行者: ${actor}  /  ${esc(ts)}</div>
      </li>`;
  });
  return `<ul class="timeline">${items.join('')}</ul>`;
}

async function renderLineageSvg(lineage, rootId, containerId) {
  const { nodes, edges } = lineage;
  const safeId = (s) => s.replace(/[^A-Za-z0-9_]/g, '_');
  const nodeLines = nodes.map((n) => {
    const isRoot = n.id === rootId;
    const statusMark = n.status === 'CONSUMED' ? '⚠' : '';
    const label = `${n.id}${isRoot ? ' ⭐' : ''}<br/>${mspLabel(n.manufacturer)}<br/><small>${STATUS_LABEL[n.status] || n.status} ${statusMark}</small>`;
    return `  ${safeId(n.id)}["${label}"]`;
  }).join('\n');
  const edgeLines = edges.map((e) => {
    const arrow = e.type === 'SPLIT' ? '-->' : '==>';
    return `  ${safeId(e.from)} ${arrow}|${e.type}| ${safeId(e.to)}`;
  }).join('\n');
  const classLines = nodes
    .filter((n) => n.status === 'CONSUMED')
    .map((n) => `  class ${safeId(n.id)} consumed;`)
    .join('\n');
  const mermaidSrc = `flowchart TD
${nodeLines}
${edgeLines}
${classLines}
  classDef consumed fill:#f3f4f6,stroke:#9ca3af,stroke-dasharray: 5 5,color:#6b7280;
`;
  const container = document.getElementById(containerId);
  container.className = 'mermaid-container';
  try {
    const { svg } = await mermaid.render(`svg_${containerId}_${Date.now()}`, mermaidSrc);
    container.innerHTML = svg + `<details><summary>Mermaid source</summary><pre>${esc(mermaidSrc)}</pre></details>`;
  } catch (err) {
    container.innerHTML = `<div class="result-error">Mermaid レンダ失敗: ${esc(err.message)}</div>`;
  }
}

// =============================================================================
// 新規登録
// =============================================================================
const createResult = document.getElementById('createResult');
const createMillSheetFile = document.getElementById('createMillSheetFile');
const createMillSheetHashLabel = document.getElementById('createMillSheetHashLabel');

createMillSheetFile.addEventListener('change', async () => {
  createMillSheetHashLabel.textContent = '';
  const f = createMillSheetFile.files[0];
  if (!f) return;
  try {
    const hash = await sha256Hex(f);
    createMillSheetHashLabel.textContent = `SHA-256: ${hash.substring(0, 16)}… (64 文字)`;
    createMillSheetHashLabel.dataset.hash = hash;
  } catch (e) {
    createMillSheetHashLabel.textContent = `ハッシュ計算失敗: ${e.message}`;
  }
});

document.getElementById('btnCreate').addEventListener('click', async () => {
  const productId = document.getElementById('createProductId').value.trim();
  if (!productId) return setError(createResult, '素材 ID を入力してください');
  const metaRaw = document.getElementById('createMetadata').value.trim();
  const uri = document.getElementById('createMillSheetURI').value.trim();
  const hash = createMillSheetHashLabel.dataset.hash || '';
  let metadata;
  if (metaRaw) {
    try { metadata = JSON.parse(metaRaw); }
    catch (e) { return setError(createResult, `metadata JSON が不正: ${e.message}`); }
  }
  setLoading(createResult);
  try {
    const data = await api('POST', '/api/products', {
      productId, metadata, millSheetHash: hash, millSheetURI: uri,
    });
    setResult(createResult, `登録しました: ${productId}`, data, productCard(data));
  } catch (e) {
    setError(createResult, e.message);
  }
});

// =============================================================================
// 譲渡
// =============================================================================
const transferSelect = document.getElementById('transferSelect');
const transferProductId = document.getElementById('transferProductId');
const transferResult = document.getElementById('transferResult');

async function refreshTransferSelect() {
  transferSelect.innerHTML = '<option value="">— 手持ち素材から選択 —</option>';
  try {
    const products = await api('GET', '/api/products');
    const active = products.filter((p) => p.status === 'ACTIVE');
    for (const p of active) {
      const opt = document.createElement('option');
      opt.value = p.productId;
      const meta = p.metadata && (p.metadata.grade || p.metadata.purpose) ? ` (${p.metadata.grade || p.metadata.purpose})` : '';
      opt.textContent = `${p.productId}${meta}`;
      transferSelect.appendChild(opt);
    }
  } catch (_) { /* ignore */ }
}
transferSelect.addEventListener('change', () => {
  if (transferSelect.value) transferProductId.value = transferSelect.value;
});

document.getElementById('btnTransfer').addEventListener('click', async () => {
  const pid = transferProductId.value.trim();
  const to = document.getElementById('transferTo').value;
  if (!pid) return setError(transferResult, '素材 ID を入力してください');
  setLoading(transferResult);
  try {
    const data = await api('POST', `/api/products/${encodeURIComponent(pid)}/transfer`, { toOwner: to });
    setResult(transferResult, `${pid} を ${mspLabel(to)} (${to}) に譲渡しました`, data, productCard(data));
  } catch (e) {
    setError(transferResult, e.message);
  }
});

// =============================================================================
// 分割
// =============================================================================
const splitSelect = document.getElementById('splitSelect');
const splitParentId = document.getElementById('splitParentId');
const splitChildrenDiv = document.getElementById('splitChildren');
const splitResult = document.getElementById('splitResult');

splitSelect.addEventListener('change', () => {
  if (splitSelect.value) splitParentId.value = splitSelect.value;
});

async function refreshSplitSelect() {
  splitSelect.innerHTML = '<option value="">— 手持ち ACTIVE 素材から選択 —</option>';
  try {
    const products = await api('GET', '/api/products');
    const active = products.filter((p) => p.status === 'ACTIVE');
    for (const p of active) {
      const opt = document.createElement('option');
      opt.value = p.productId;
      opt.textContent = `${p.productId}`;
      splitSelect.appendChild(opt);
    }
  } catch (_) { /* ignore */ }
}

function addSplitChildRow() {
  const row = document.createElement('div');
  row.className = 'dynamic-row';
  row.innerHTML = `
    <div class="drow-grid">
      <input type="text" class="child-id" placeholder="子の ID (例: C-001)">
      <select class="child-owner">
        ${ALL_MSPS.map((m) => `<option value="${m}">${esc(mspLabel(m))} (${m})</option>`).join('')}
      </select>
      <input type="text" class="child-meta" placeholder='metadata JSON (任意): {"weightKg":3000}'>
      <button type="button" class="btn-remove">削除</button>
    </div>
  `;
  row.querySelector('.btn-remove').addEventListener('click', () => row.remove());
  splitChildrenDiv.appendChild(row);
}
// 初期 2 行
addSplitChildRow(); addSplitChildRow();
document.getElementById('btnAddSplitChild').addEventListener('click', addSplitChildRow);

document.getElementById('btnSplit').addEventListener('click', async () => {
  const pid = splitParentId.value.trim();
  if (!pid) return setError(splitResult, '親 ID を入力してください');
  const rows = splitChildrenDiv.querySelectorAll('.dynamic-row');
  const children = [];
  for (const r of rows) {
    const cid = r.querySelector('.child-id').value.trim();
    const to = r.querySelector('.child-owner').value;
    const meta = r.querySelector('.child-meta').value.trim();
    if (!cid) continue;
    let metadata;
    if (meta) {
      try { metadata = JSON.parse(meta); }
      catch (e) { return setError(splitResult, `子 ${cid} の metadata JSON 不正: ${e.message}`); }
    }
    children.push({ childId: cid, toOwner: to, metadata });
  }
  if (children.length < 2) return setError(splitResult, '子を 2 つ以上入力してください');
  setLoading(splitResult);
  try {
    const data = await api('POST', `/api/products/${encodeURIComponent(pid)}/split`, { children });
    const kids = children.map((c) => `<li>${esc(c.childId)} → ${esc(mspLabel(c.toOwner))}</li>`).join('');
    const extra = `<div class="info-box">親 ${esc(pid)} を ${children.length} 個に分割しました。<ul>${kids}</ul></div>`;
    setResult(splitResult, '分割完了', data, extra);
  } catch (e) {
    setError(splitResult, e.message);
  }
});

// =============================================================================
// 接合
// =============================================================================
const mergeParentsDiv = document.getElementById('mergeParents');
const mergeResult = document.getElementById('mergeResult');

function addMergeParentRow() {
  const row = document.createElement('div');
  row.className = 'dynamic-row';
  row.innerHTML = `
    <div class="drow-grid-merge">
      <input type="text" class="parent-id" placeholder="親 productId (例: S-A-001-a)">
      <button type="button" class="btn-remove">削除</button>
    </div>
  `;
  row.querySelector('.btn-remove').addEventListener('click', () => row.remove());
  mergeParentsDiv.appendChild(row);
}
addMergeParentRow(); addMergeParentRow();
document.getElementById('btnAddMergeParent').addEventListener('click', addMergeParentRow);

document.getElementById('btnMerge').addEventListener('click', async () => {
  const rows = mergeParentsDiv.querySelectorAll('.dynamic-row');
  const parentIds = [];
  for (const r of rows) {
    const v = r.querySelector('.parent-id').value.trim();
    if (v) parentIds.push(v);
  }
  if (parentIds.length < 2) return setError(mergeResult, '親を 2 つ以上入力してください');
  const childId = document.getElementById('mergeChildId').value.trim();
  if (!childId) return setError(mergeResult, '子 ID を入力してください');
  const metaRaw = document.getElementById('mergeMetadata').value.trim();
  let metadata;
  if (metaRaw) {
    try { metadata = JSON.parse(metaRaw); }
    catch (e) { return setError(mergeResult, `metadata JSON 不正: ${e.message}`); }
  }
  setLoading(mergeResult);
  try {
    const data = await api('POST', '/api/products/merge', {
      parentIds, child: { childId, metadata },
    });
    const plist = parentIds.map((p) => `<li>${esc(p)}</li>`).join('');
    const extra = `<div class="info-box">親 ${parentIds.length} 個を消費し、${esc(childId)} を生成しました。<ul>${plist}</ul></div>`;
    setResult(mergeResult, '接合完了', data, extra);
  } catch (e) {
    setError(mergeResult, e.message);
  }
});

// =============================================================================
// 初期表示
// =============================================================================
showView('viewHome');
