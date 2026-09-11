# meshkit-architecture.tex 검증 리포트

논문(`docs/meshkit-architecture.tex`)의 기술적 주장을 실제 SDK 소스와 대조한 결과.
검증일: 2026-08-26. 방법: 주장별로 구현 파일을 직접 열어 file:line 근거로 확인.
(ooo auto 파이프라인은 시드 A등급 통과 후 실행 워커가 산출물 없이 종료되어, 본 리포트는 수동 검증으로 대체함.)

**결과 요약: 9개 범주 중 7개 전면 CONFIRMED, 2개 부분 REFUTED → 논문 수정 완료.**

## 1. 요청 서명 입력 12필드와 순서 — CONFIRMED

version, requestId, caller.appId, caller.bundleId, caller.publicKeyId,
target.targetBundleId, target.capabilityId, target.version,
payloadHash.algorithm(lowercase), payloadHash.value(lowercase), timestamp, nonce
— newline join, Ed25519.

- `meshkit-py/meshkit/request.py:45-61` (`signing_input`)
- `meshkit-android/meshkit-core/src/main/kotlin/ai/meshkit/core/MeshRequest.kt:75-88` (`signingInput`) — 동일 순서

## 2. 논스 결합 페이로드 해시 공식 — CONFIRMED

`SHA-256("meshkit-payload-hash/v1" \n "nonce="+escape(nonce) \n "payload="+canonical(payload))`

- `meshkit-py/meshkit/canonical.py:31-48` (`canonical_payload_nonce_bound`, `sha256_hex_nonce_bound`)
- `meshkit-android/.../MeshCanonical.kt:12` (`NONCE_BOUND_VERSION`)

## 3. 정규화 이스케이프 규칙 — CONFIRMED

ASCII 영숫자 외 모든 UTF-8 바이트를 대문자 hex 퍼센트 인코딩, 키 정렬 후 `key=value&...` join.

- `meshkit-py/meshkit/canonical.py:12-28` (`_ALNUM`, `escape`, `canonical_payload`)

## 4. fail-closed 파이프라인 순서 — CONFIRMED / 에러 코드명 — REFUTED→수정

단계 순서(envelope fields → observed caller → policy → payload hash → timestamp →
nonce reservation → invocation policy(consent/budget) → signature)는 구현과 정확히 일치:
`meshkit-py/meshkit/trust.py:161-220` (`validate_and_accept`).

그러나 논문 Fig 4의 코드명 4개가 실제와 달랐음:

| 논문(구판) | 실제 구현 | 근거 |
|---|---|---|
| `imposter_caller` | `observed_caller_mismatch` (+ `observed_caller_signature_mismatch`, `trusted_caller_mismatch`) | trust.py:178-191 |
| `policy_denied` | `trusted_caller_mismatch` / `caller_bundle_claim_mismatch` / `target_identity_mismatch` / `unsupported_capability` | trust.py:193-200 |
| `payload_tampered` | `payload_hash_mismatch` | trust.py:206 |
| `invalid_signature` | `signature_mismatch` (+ `signature_required`) | trust.py:141-158 |

일치했던 코드: `stale_timestamp`(trust.py:211,214), `replay_detected`(trust.py:217),
`budget_exceeded`(trust.py:116). **→ Fig 4를 실제 코드명으로 교체, 1단계 코드
`invalid_security_field`(trust.py:30-35)도 추가.**

## 5. MCP 2026-07-28 매핑 — CONFIRMED

- 확장 키 `ai.meshkit/trust`, `params._meta[...].mesh_request` / `result._meta[...].mesh_receipt`:
  `meshkit-py/meshkit/mcpv2.py:33,64-67,130`
- 헤더 미러 검증(Mcp-Method/Mcp-Name vs body): `mcpv2.py:94-101`
- 봉투 payload ≡ tool arguments 강제: `mcpv2.py:108-113`
- JSON-RPC `-32602` + `error.data.meshkit.code`: `mcpv2.py:38,149-158`
- ttlMs/cacheScope 캐시 힌트: `mcpv2.py:170-176`
- 무상태 서버(server/discover, tools/list, tools/call): `meshkit-py/examples/miniapp_server.py:107-132`

## 6. 영수증 상관 — 부분 REFUTED→수정

영수증 서명 입력(`meshkit-py/meshkit/receipt.py:36-52`)이 결박하는 것:
receiptId, **requestId, capabilityId, targetAppId, targetBundleId,
requestPayloadHash**, status, canonical(result), timestamp, nonce.
**caller identity는 포함되지 않음** — 논문 §3이 "(requestId, caller identity,
payload hash)"라고 썼던 부분을 "(requestId, capability id, target identity,
request payload hash)"로 수정. 호출자 측 상관 검증(`verify_receipt`,
receipt.py:198-209)도 requestId+capabilityId+targetBundleId+payloadHash 기준으로 일치.

## 7. 골든 벡터 파일 — CONFIRMED

`meshkit-android/vectors/wire-compat.v1.json` 존재, 키:
cases / generator / requestSigner* / receiptSigner* / version — 논문의 "seeds,
canonical forms, signing inputs, hashes를 핀하는 정답지" 역할과 일치.

## 8. 안드로이드 주장 — CONFIRMED

- 액션 `ai.meshkit.action.INVOKE_CAPABILITY`: `meshkit-android/meshkit-transport-intent/src/main/kotlin/ai/meshkit/transport/MeshIntentContract.kt:9`
- extras `mesh_request`: `MeshIntentContract.kt:12`
- `startActivityForResult` + `getCallingPackage()` + 서명 인증서 SHA-256:
  `CallerIdentityObserver.kt:11,42`
- `spend:money` AppFunctions 비노출 게이트: `meshkit-core/.../MeshAppFunctionGate.kt:9`

## 9. 봉투 인코딩 — CONFIRMED

base64(sorted-keys JSON), 서명은 봉투 바이트가 아닌 서명 입력을 커버(CryptoKit
랜덤 서명 대응으로 바이트 동일성 비교 금지):

- `meshkit-py/meshkit/envelope.py:14-16` (`sort_keys=True`)
- `MeshRequest.kt` `toJsonObject`/`MeshJson.sortedObject`, `encodedForEnvelope`

## 적용된 수정 (docs/meshkit-architecture.tex)

1. Fig 4 에러 코드 라벨 전면 교체 (표 4항 참조) + 1단계 `invalid_security_field` 추가.
2. §3 영수증 상관 필드 서술 수정 (caller identity → capability id + target identity).

코드·벡터·테스트는 일절 수정하지 않음. 수정 후 pdflatex 재컴파일 통과 확인.
