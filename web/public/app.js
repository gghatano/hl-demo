'use strict';

// ---------------------------------------------------------------------------
// MSP label map
// ---------------------------------------------------------------------------
const MSP_LABELS = {
  Org1MSP: 'メーカー A',
  Org2MSP: '卸 B',
  Org3MSP: '販売店 C',
};

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

// ---------------------------------------------------------------------------
// Org switch
// ---------------------------------------------------------------------------
orgSelect.addEventListener('change', () => {
  currentOrg = orgSelect.value;
  document.body.className = currentOrg;
  orgBadge.className = `badge ${currentOrg}`;
  const orgMap = { org1: 'Org1MSP', org2: 'Org2MSP', org3: 'Org3MSP' };
  orgBadge.textContent = orgMap[currentOrg];
});
// Init
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
  d.textContent = s;
  return d.innerHTML;
}

// ---------------------------------------------------------------------------
// CreateProduct
// ---------------------------------------------------------------------------
document.getElementById('btnCreate').addEventListener('click', async () => {
  const productId = document.getElementById('createProductId').value.trim();
  if (!productId) return showError('製品 ID を入力してください');
  showLoading();
  try {
    const data = await apiCall('POST', '/api/products', { productId });
    showSuccess('製品を登録しました', data);
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
  if (!productId) return showError('製品 ID を入力してください');
  showLoading();
  try {
    const data = await apiCall('POST', `/api/products/${encodeURIComponent(productId)}/transfer`, { toOwner });
    showSuccess('移転が完了しました', data);
  } catch (e) {
    showError(e.message);
  }
});

// ---------------------------------------------------------------------------
// ReadProduct
// ---------------------------------------------------------------------------
document.getElementById('btnRead').addEventListener('click', async () => {
  const productId = document.getElementById('readProductId').value.trim();
  if (!productId) return showError('製品 ID を入力してください');
  showLoading();
  try {
    const data = await apiCall('GET', `/api/products/${encodeURIComponent(productId)}`);
    showSuccess(`製品情報: ${productId}`, data);
  } catch (e) {
    showError(e.message);
  }
});

// ---------------------------------------------------------------------------
// GetHistory — with timeline + flow visualization
// ---------------------------------------------------------------------------
document.getElementById('btnHistory').addEventListener('click', async () => {
  const productId = document.getElementById('historyProductId').value.trim();
  if (!productId) return showError('製品 ID を入力してください');
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

  // Build flow chain: extract unique owners in order
  const owners = [];
  for (const ev of events) {
    if (ev.eventType === 'CREATE' && ev.toOwner && !owners.includes(ev.toOwner)) {
      owners.push(ev.toOwner);
    }
    if (ev.eventType === 'TRANSFER') {
      if (ev.fromOwner && !owners.includes(ev.fromOwner)) owners.push(ev.fromOwner);
      if (ev.toOwner && !owners.includes(ev.toOwner)) owners.push(ev.toOwner);
    }
  }

  // Flow chain HTML
  let flowHtml = '<div class="flow-chain">';
  owners.forEach((o, i) => {
    if (i > 0) flowHtml += '<span class="flow-arrow">&rarr;</span>';
    flowHtml += `<span class="flow-node ${escapeHtml(o)}">${escapeHtml(mspLabel(o))}</span>`;
  });
  flowHtml += '</div>';

  // Verify origin
  const origin = events[0];
  const isOriginA = origin.eventType === 'CREATE' && origin.toOwner === 'Org1MSP';
  const verifyClass = isOriginA ? 'verify-ok' : 'verify-ng';
  const verifyMsg = isOriginA
    ? `起点検証 OK: 製品 ${escapeHtml(productId)} はメーカー A (Org1MSP) が登録`
    : `起点検証 NG: 製品 ${escapeHtml(productId)} の登録者は ${escapeHtml(mspLabel(origin.toOwner || '不明'))}`;
  const verifyHtml = `<div class="verify-result ${verifyClass}">${verifyMsg}</div>`;

  // Timeline
  let timelineHtml = '<ul class="timeline">';
  for (const ev of events) {
    const cls = `event-${ev.eventType}`;
    let detail = '';
    if (ev.eventType === 'CREATE') {
      detail = `登録者: ${escapeHtml(mspLabel(ev.toOwner))}`;
    } else {
      detail = `${escapeHtml(mspLabel(ev.fromOwner))} → ${escapeHtml(mspLabel(ev.toOwner))}`;
    }
    const ts = ev.timestamp ? new Date(ev.timestamp).toLocaleString('ja-JP') : '';
    const txShort = ev.txId ? ev.txId.substring(0, 12) + '...' : '';
    timelineHtml += `
      <li class="${cls}">
        <div class="event-type">${escapeHtml(ev.eventType)}</div>
        <div class="event-detail">${detail}</div>
        <div class="event-detail">${escapeHtml(ts)}${txShort ? ' | tx: ' + escapeHtml(txShort) : ''}</div>
      </li>`;
  }
  timelineHtml += '</ul>';

  resultArea.innerHTML =
    `<div class="result-success"><strong>来歴: ${escapeHtml(productId)}</strong></div>` +
    flowHtml + verifyHtml + timelineHtml;
}
