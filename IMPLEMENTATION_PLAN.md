# IMPLEMENTATION_PLAN.md — GridToPINN.jl 진행 현황

"From Grid to PINN" 계산 부분의 단계별 진행 상태와 다음 단계 계획.

## 핵심 약속

"화면에 보이는 Julia 코드가 곧 브라우저에서 도는 코드" — Julia 커널을 JS로
다시 짜서 대체하지 않는다. WASM은 WasmTarget.jl (Julia 1.12, WasmGC).

## 진행 상태

| 단계 | 상태 | 비고 |
|---|---|---|
| 1. 미분과 Newton법 | ✅ 완료 (PR #2, #3, #4) | 유한차분·이중수·Newton, WASM + e2e |
| 2. 시간 전진 | ✅ 완료 (PR #5) | Euler·RK4·적응형 DP54, WASM + e2e |
| 3. 확산 | 🔄 진행 중 (이 브랜치) | 선의 방법 + 2단계 적분기 재사용, 물/꿀 비교 |
| 4. 대류 | ⬜ 예정 | 유한체적, 기울기 제한자, SSP-RK3 |
| 5. Poisson | ⬜ 예정 | Jacobi → 다중격자 |
| 6. Staggered grid | ⬜ 예정 | MAC 격자, 투영 |
| 7. 조립 (Cavity) | ⬜ 예정 | 2~6단계 부품 조립, Ghia et al. (1982) |
| 8. PINN | ⬜ 예정 | 시작 전 WASM에서 2계 미분·학습 검증 필요 |
| 9. GPU (선택) | ⬜ 예정 | 브라우저와 무관한 로컬 실행 |

## 단계별 상태 기록

### Step 1 (완료)
- `src/01-differentiation-newton.jl` (`Step1DiffNewton`): 유한차분, 이중수 Dual{T}, Newton법, DRS 물리 모델
- WASM: `src/step1_wasm.jl` 진입점. WasmTarget 제약(기본 인자 GlobalRef, Function 인자) 회피 패턴 확립
- e2e: Playwright + Chrome 145, data URL 방식 WASM 로딩 패턴 확립
- 발견: `derivative_dual`은 브라우저에서 정상 동작 (초기 문서의 "사용 불가"는 오류)

### Step 2 (완료)
- `src/02-time-integration.jl` (`Step2TimeIntegration`): Euler·RK4·적응형 DP54, 스칼라/Vector/Matrix 겸용
- 테스트 교훈: stiff 문제(τ_char≈0.122s)에서는 Euler·RK4 모두 진동하며 수렴 —
  "RK4 > Euler" 단순 비교는 성립하지 않음. dt=1.0에서는 RK4도 오버플로→NaN
- WASM: `src/step2_wasm.jl` — acceleration에 특화된 concrete 진입점.
  `ode_integrate`는 평탄화 Vector{Float64} [t0,y0,t1,y1,…] 반환 (vec_* 브릿지로 읽음)

### Step 3 (진행 중)
- `src/03-diffusion.jl` (`Step3Diffusion`): 선의 방법(공간 2차 중심차분) +
  2단계 적분기 재사용. erfc 직접 구현 (A&S 7.1.26), Stokes 1종 해석해, 확산 깊이
- 테스트: 연산자 고유값 수렴(dx²), 공간 2차 수렴, 시간 1차(Euler)·2차(CN),
  물/꿀 확산 깊이 √2000, 안정 한계·발산, Float32
- 음해법 Crank–Nicolson 구현: 삼중대각 Thomas 알고리즘(패키지 없음, O(n)),
  무조건 안정 + 시간 2차. 깨뜨리기: 발산은 안 하지만 최대원리는 없음
  (큰 Δt에서 음수 링). 매끄러운 초기조건+보이지 않는 고주파 섭동 →
  25스텝 정상 감쇠 후 30스텝 톱니 발산 (Euler/RK4), CN은 같은 조건 정상
- WASM: `src/step3_wasm.jl` — 브로드캐스팅 없이 명시적 루프로 진입점 구현,
  `diffuse_advance`는 u를 in-place 갱신 (상태형 호출: 만들기 → n전진 → 꺼내기)
- WASM 빌드·e2e 완료: e2e 6개 (erfc, 확산 깊이, 움직이는 벽, 발산, CN 무조건 안정, 삼단 서사) 전부 통과
- 대안 지점: 적분기 3종 — Euler(1차), RK4(4차·안정 한계 가려짐), CN(음해·무조건 안정)

## 다음 단계 (Step 4) 계획 초안

- 선형 대류 + Burgers (Raissi et al. 2019 설정)
- 유한체적: 셀 경계 유속 계산, 시간은 SSP-RK3 (새 적분기 — 2단계 RK4와 계수 공유)
- 대안 지점: 유속 계산 (upwind / 중심 / minmod 기울기 제한자)
- 점성항은 3단계 확산 연산자 재사용
