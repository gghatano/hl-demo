#!/usr/bin/env bash
# 10_normal_flow.sh — N1〜N4 正常系
# test_integration.sh から source される前提。
# 共通 env: INVOKE (invoke_as.sh パス) / PRODUCT_N_ID

# shellcheck shell=bash

tc_begin "N1 CreateProduct (as Org1 / メーカー A)"
if out=$("${INVOKE}" org1 invoke CreateProduct "${PRODUCT_N_ID}" Org1MSP Org1MSP 2>&1); then
  tc_pass "create committed"
else
  tc_fail "invoke failed: ${out}"
fi

tc_begin "N2 TransferProduct Org1→Org2 (A→B)"
if out=$("${INVOKE}" org1 invoke TransferProduct "${PRODUCT_N_ID}" Org1MSP Org2MSP 2>&1); then
  tc_pass "transfer A→B committed"
else
  tc_fail "invoke failed: ${out}"
fi

tc_begin "N3 TransferProduct Org2→Org3 (B→C)"
if out=$("${INVOKE}" org2 invoke TransferProduct "${PRODUCT_N_ID}" Org2MSP Org3MSP 2>&1); then
  tc_pass "transfer B→C committed"
else
  tc_fail "invoke failed: ${out}"
fi

tc_begin "N4 ReadProduct as Org3 (C 視点で現在状態確認)"
if read_json=$("${INVOKE}" org3 query ReadProduct "${PRODUCT_N_ID}" 2>/dev/null); then
  current_owner=$(printf '%s' "${read_json}" | jq -r '.currentOwner')
  manuf=$(printf '%s' "${read_json}" | jq -r '.manufacturer')
  assert_eq "${current_owner}" "Org3MSP" "currentOwner should be Org3MSP" && \
  assert_eq "${manuf}"         "Org1MSP" "manufacturer should be Org1MSP" && \
    tc_pass "product state visible from Org3"
else
  tc_fail "query failed"
fi

tc_begin "N4 GetHistory as Org3 (起点 A を確認)"
if hist_json=$("${INVOKE}" org3 query GetHistory "${PRODUCT_N_ID}" 2>/dev/null); then
  len=$(printf '%s' "${hist_json}" | jq 'length')
  first_type=$(printf '%s' "${hist_json}" | jq -r '.[0].eventType')
  first_to=$(printf '%s' "${hist_json}" | jq -r '.[0].toOwner')
  first_actor=$(printf '%s' "${hist_json}" | jq -r '.[0].actor.mspId')
  last_to=$(printf '%s' "${hist_json}" | jq -r '.[-1].toOwner')
  assert_eq "${len}"         "3"         "history length" && \
  assert_eq "${first_type}"  "CREATE"    "first event type" && \
  assert_eq "${first_to}"    "Org1MSP"   "first toOwner (起点=A)" && \
  assert_eq "${first_actor}" "Org1MSP"   "first actor MSP" && \
  assert_eq "${last_to}"     "Org3MSP"   "final owner C" && \
    tc_pass "history traced A→B→C"
else
  tc_fail "query failed"
fi
