# IMPLEMENTATION_PLAN.md — Step 1: 미분과 Newton법

## 목표

ODE를 풀기에 앞서 미분을 세 가지 방법(손 유도, 유한차분, 이중수 자동미분)으로 구하고, Newton법으로 DRS 문제의 최고속도를 찾는 커널과 테스트를 완성한다. 이후 WASM 컴파일은 별도 작업.

**핵심 질문**: DRS를 열면 최고속도가 얼마나 오르나?

---

## 재사용 설계 (미리 고려할 인터페이스)

| 만드는 것 | 시그니처 아이디어 | 재사용처 |
|---|---|---|
| Newton법 | `newton(f, f′, x0; tol, maxiter)` — 함수 기반 | 2단계 가속 곡선의 수렴값 |
| 유한차분 (전진) | `derivative_fd(f, x, h)` | 3단계 이후 우변 미분 |
| 유한차분 (중심) | `derivative_fd_central(f, x, h)` | 상동 |
| 이중수 Dual{T} | 값+미분 필드, +, *, ^ 등 오버로드 | 8단계 PDE 잔차 미분 |
| 자동미분 (이중수) | `derivative_dual(f, x)` | 8단계 |
| 항력·저항·출력 모델 | `resistance(v; ρ, Cd, A, Froll)` 등 | 2단계 동일한 수치 사용 |
| 최고속도 | `top_speed(P, ρ, Cd, A, Froll)` — Newton으로 f(v)=0 풀이 | 2단계 수렴 목표값 |

모든 커널은 `T<:AbstractFloat` 일반화로 작성. `0.5` 리터럴 금지, `x/2` 또는 `T(0.5)` 사용.

---

## 구현 항목

### 1. 패키지 뼈대
- `Project.toml`: 이름 `GridToPINN`, Julia 1.10 호환
- `src/GridToPINN.jl`: 모듈, 단계 서브모듈 포함 구조
- `src/Step1/`: Step1 전용 파일. 추후 단계가 늘어나면 `StepN/` 패턴 유지
- `test/`: 네이티브 Julia 테스트

### 2. Newton법 커널
- `newton(f, df, x0; tol=1e-12, maxiter=50)` — 수렴 시 근 반환, 실패 시 예외
- Newton 오차 제곱 감소 확인용 추적 옵션(테스트용)

### 3. 유한차분
- 전진차분: `derivative_fd(f, x, h) = (f(x+h) - f(x)) / h` — 차수 1
- 중심차분: `derivative_fd_central(f, x, h) = (f(x+h) - f(x-h)) / (2h)` — 차수 2
- h를 줄이며 오차 로그 기울기 확인 도구(테스트)

### 4. 이중수 Dual{T}
- struct Dual{T} <: Number: `val::T`, `der::T`
- Base 연산자 오버로드: `+`, `-`, `*`, `/`, `^` (정수승)
- 함수 미분을 위한 lift: `lift(f)` — Dual 입력에 대해 Dual 출력 반환
- `derivative_dual(f, x)` — `f(Dual(x, one(x))).der` 로 미분 추출

### 5. DRS 물리 모델
- 항력: `F_drag(v) = 0.5 * ρ * Cd * A * v^2`
- 출력-저항 균형 방정식: `f(v) = 0.5*ρ*Cd*A*v^3 + Froll*v - P`
- Newton 대상 함수 반환 함수 생성기 `make_f(P, ρ, Cd, A, Froll)`
- DRS 닫힘/열림: Cd만 다름 (예: Cd_closed vs Cd_open)

### 6. 해석해
- 구름저항 0일 때: `v_top = (2P / (ρ*Cd*A))^(1/3)`
- Newton 결과와의 비교 검증에 사용

### 7. 깨뜨리기 검증
- h를 계속 줄여 반올림오차 임계점 찾기
- Float32와 Float64에서 임계점이 다름을 확인
- 항력계수 속도 의존 추가 시 각 방법의 동작 차이 확인

---

## 테스트

- `Test` 패키지 사용
- Newton 수렴 확인 (해석해와 비교, 구름저항 0)
- 유한차분 오차 차수 확인 (로그-로그 기울기: 전진 1, 중심 2)
- Dual 수 미분과 손 유도 미분 일치 확인
- Newton 반복마다 오차 제곱 감소 확인
- Float32/Float64 양쪽에서 테스트
- 타입 승격 없음 확인 (Float32 입력 → Float32 출력)

---

## 산출물

- `src/Step1/` 아래 구현 파일
- `test/test_step1.jl` — 수렴 차수 수치 확인 포함
- 조작 항목 목록 파일 (Step1용): 조작 가능 값, 대안 지점, 내보낸 함수 목록
- 호출 규약 문서 초안 (이후 단계와 공유용)

---

## 보류

- WASM 컴파일 검증: Julia 1.10.12에서는 WasmTarget.jl 미지원 → Julia 1.12/1.13 업그레이드 후 별도 작업. 네이티브 테스트부터 완성.
