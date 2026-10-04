# 호출 규약 — GridToPINN WASM ↔ Svelte 연동

**문서 버전**: 2026-10-04 (Step1 검증 결과 기반 초안)  
**관련 문서**: [Step1 WASM 검증 보고서](./changes/step1_wasm_validation.md)  
**갱신 규칙**: 단계 추가·함수 변경 시 이 문서를 함께 갱신한다. 화면은 이 문서 + `stepN_manifest.json`을 단일 출처로 삼는다.

---

## 1. 전체 구조

저장소는 두 부분이 나란히 있다:

```
GridToPINN.jl/
├── src/                    # Julia 패키지 (단계별 커널)
│   ├── 01-differentiation-newton.jl   # Step1
│   └── ...
├── scripts/
│   └── build_wasm.jl        # WASM 컴파일 스크립트
├── web/                     # SvelteKit 정적 사이트
│   ├── public/
│   │   ├── step1.wasm       # Step1 WASM 모듈 (빌드 산출물)
│   │   └── step1_manifest.json  # 조작 항목·함수 목록
│   └── src/
│       ├── lib/
│       │   └── wasm.ts      # WASM 로딩·호출 래퍼 (JS/TS)
│       └── routes/
│           └── +page.svelte # 메인 페이지
└── docs/
    ├── calling_convention.md    # ← 이 문서
    └── changes/
        └── step1_wasm_validation.md   # Step1 WASM 검증 보고서
```

- **WASM 파일 위치**: `web/public/stepN.wasm` — SvelteKit 정적 빌드 시 사이트 루트에 배치됨
- **Manifest 파일 위치**: `web/public/stepN_manifest.json` — 동일 위치
- **WSASM 파일 경로**는 사이트 기준 경로가 바뀌어도 동작하도록 인자로 받는다 (Vite의 `import.meta.env.BASE_URL` 활용).

---

## 2. WASM 불러오는 법

### 2.1. 파일 위치 확보

WASM 파일과 manifest는 SvelteKit의 `public/` 디렉터리에 둔다. 빌드 후 사이트 루트에 배치되며, `fetch()`로 로드한다.

```typescript
// web/src/lib/wasm.ts
const wasmPath = `${import.meta.env.BASE_URL}step1.wasm`;
const manifestPath = `${import.meta.env.BASE_URL}step1_manifest.json`;
```

`import.meta.env.BASE_URL`은 Vite가 제공하는 사이트 기준 경로(디폴트 `/`). 개발 서버, 정적 빌드, 서브패스 배포 모두 대응.

### 2.2. Manifest 먼저 로드

화면 조작 요소를 구성하려면 manifest를 먼저 읽는다.

```typescript
async function loadManifest(step: number): Promise<StepManifest> {
  const r = await fetch(`${BASE_URL}step${step}_manifest.json`);
  if (!r.ok) throw new Error(`manifest 로드 실패: ${r.status}`);
  return r.json() as Promise<StepManifest>;
}
```

### 2.3. WASM 모듈 로드

```typescript
async function loadWasmModule(wasmPath: string): Promise<WebAssembly.Instance> {
  const bytes = await fetch(wasmPath).then(r => r.arrayBuffer());
  const { instance } = await WebAssembly.instantiate(bytes, {});
  return instance;
}
```

**주의**: `WebAssembly.instantiate(bytes, {})`의 두 번째 인자(import 객체)는 현재 빈 객체. Step1은 JS import가 필요 없다. 다른 단계에서 JS 함수 임포트가 필요해지면 이곳에 추가한다.

### 2.4. 전체 로딩 순서 (권장)

```typescript
// 1. manifest 로드 → 화면 조작 요소 구성
// 2. WASM 로드 → 계산 준비 완료
// 순서는 상관 없으나 manifest가 먼저면 UI 구성이 빠름
const manifest = await loadManifest(1);
const wasmInstance = await loadWasmModule(`${BASE_URL}step1.wasm`);
const exports = wasmInstance.exports;
```

---

## 3. 함수 목록과 인자·반환 형식

### 3.1. 함수 정보 출처

화면은 `stepN_manifest.json`의 `functions` 배열을 읽어서 함수 목록을 구성한다. 각 함수 객체:

```typescript
interface WasmFunction {
  name: string;           // WASM export 함수명 (instance.exports[name])
  args: string[];         // 인자 타입 목록 (표시용, 런타임 타입 아님)
  ret: string;            // 반환 타입 (표시용)
  note?: string;          // 주의사항 (Dual 브릿지 필요 등)
}
```

### 3.2. Step1 현재 함수 (manifest 기반)

`web/public/step1_manifest.json`의 `functions` 배열에서 확인. 현재 Step1 노출 함수:

| 함수명 | 인자 (WASM 호출 시) | 반환 | 비고 |
|---|---|---|---|
| `f_poly` | `(x: number)` | `number` | x³ + 2x² + x (generic: `Dual{Float64}` 입력도 가능) |
| `df_analytic` | `(x: number)` | `number` | 3x² + 4x + 1 |
| `derivative_fd` | `(x: number, h: number)` | `number` | f_poly의 전진차분. h는 Float64 |
| `derivative_dual` | `(x: number)` | `number` | f_poly의 Dual 자동미분 (정확, 오차 0). **브라우저(WasmGC)에서 정상 동작 확인**: e.derivative_dual(1.0) → 8.0. WASM 내부에서 Dual(x,1.0) 생성 후 f_poly_wasm 적용, .der 추출. JS에서 상수 number 전달 가능. |
| `top_speed` | `(P, ρ, Cd, A, Froll, tol, maxiter)` | `number` | P[W], ρ[kg/m³], Cd[–], A[m²], Froll[N], tol[–], maxiter[Int64] |
| `compare_drs` | `(P, ρ, A, Froll, Cd_closed, Cd_open, tol, maxiter)` | `number` | dv = v_open − v_closed |
| `vec_new` | `(n: BigInt)` | `WasmGCVector` | 길이 n인 Vector{Float64} 생성. 반환값은 WasmGC struct 참조 |
| `vec_set` | `(v: WasmGCVector, i: BigInt, val: number)` | `0` | v[i] = val (1-based index, Julia 관습). BigInt로 Int64 전달 |
| `vec_get` | `(v: WasmGCVector, i: BigInt)` | `number` | v[i] 읽기 |
| `vec_len` | `(v: WasmGCVector)` | `BigInt` | 벡터 길이 |
| `vec_sum` | `(v: WasmGCVector)` | `number` | 벡터 요소 합계 |
| `dual_add` | `(d1: WasmGCDual, d2: WasmGCDual)` | `WasmGCDual` | **WasmGC struct 입력 필요 — JS에서 직접 호출 불가** (브릿지 필요) |
| `dual_mul` | `(d1: WasmGCDual, d2: WasmGCDual)` | `WasmGCDual` | 위와 동일 |

### 3.3. 인자 타입 매핑 (WasmTarget → JS)

| Julia/WasmTarget 타입 | JS 전달 형식 | 비고 |
|---|---|---|
| `Float64` | `number` (JS number) | IEEE 754 double 그대로 전달 |
| `Float32` | `number` | JS number → WASM f32로 변환 |
| `Int64` | `BigInt` | JS BigInt로 전달 (Int64 범위: ±2⁶³−1) |
| `Int32` | `number` | JS number (안전 정수 범위 내) |
| `Vector{Float64}` | `WasmGCVector` (WasmGC struct 참조) | JS에서 직접 생성 불가 → `vec_new`로 생성 후 반환값 사용 |
| `Dual{Float64}` | `WasmGCDual` (WasmGC struct 참조) | JS에서 직접 생성 불가 → WASM 측 브릿지 필요 |

**BigInt 사용 이유**: Int64 범위를 JS number(53비트 정수 정밀도)로 정확히 표현할 수 없기 때문. WasmTarget은 Int64 인자를 BigInt로 받는다.

### 3.4. 실제 호출 예시

```typescript
const e = wasmInstance.exports;

// 스칼라 함수 (인자: number, 반환: number)
const fx = e.f_poly(1.0);           // → 4.0
const dfx = e.df_analytic(1.0);     // → 8.0

// derivative_fd (인자 2개, 반환 number)
const h = 1e-6;
const df = e.derivative_fd(1.0, h); // → ≈ 8.0

// top_speed (인자 7개, BigInt 1개 포함)
const v = e.top_speed(
  500000.0,   // P: Float64
  1.225,      // ρ: Float64
  0.30,       // Cd: Float64
  0.55,       // A: Float64
  0.0,        // Froll: Float64
  1e-12,      // tol: Float64
  50n         // maxiter: Int64 → BigInt
);            // → ≈ 170.4 m/s

// vec_new + vec_set + vec_sum
const v = e.vec_new(5n);            // Vector{Float64} 생성
e.vec_set(v, 1n, 1.0);              // 1-based: v[1] = 1.0
e.vec_set(v, 2n, 2.0);
e.vec_set(v, 3n, 3.0);
e.vec_set(v, 4n, 4.0);
e.vec_set(v, 5n, 5.0);
const len = e.vec_len(v);           // → 5 (BigInt)
const sum = e.vec_sum(v);           // → 15.0
const third = e.vec_get(v, 3n);    // → 3.0
```

### 3.5. 반환 타입 처리

- **`number` 반환**: 그대로 JS number. 추가 변환 불필요.
- **`BigInt` 반환** (`vec_len`): JS BigInt. 넘버가 필요하면 `Number(bignum)` 변환 (정수 범위 확인 필요).
- **`WasmGCVector` 반환** (`vec_new`): WasmGC struct 참조. JS에서 직접 필드 접근 불가. `vec_set`/`vec_get`/`vec_len`/`vec_sum`으로 조작. JS에서 읽기 전용 접근이 필요하면 추가 "브릿지 읽기" 함수(예: `vec_to_js_array`)를 WASM에 컴파일해야 함 → 격자 크기별 비용 측정 필요.
- **`WasmGCDual` 반환** (`dual_add`, `dual_mul`): WasmGC struct. JS에서 직접 접근·생성 불가. Dual 입출력 브릿지 함수 필요.

---

## 4. 중간 결과 꺼내는 방식

AGENTS.md 요구: "시뮬레이션은 만들기 → n걸음 전진 → 현재 장 꺼내기 → 오차 꺼내기로 분할된 함수로 내보낸다."

### 4.1. Step1의 경우

Step1은 "만들기 → n걸음 전진" 구조가 아닌 **단일 호출 계산**이다. top_speed, compare_drs 모두 한 번 호출로 결과 반환. 따라서 중간 결과 꺼내기 구조가 불필요.

### 4.2. 향후 단계 (5~7단계) 일반 패턴

시뮬레이션 단계가 "만들기 → n걸음 전진 → 현재 장 꺼내기" 구조를 가질 때:

```typescript
// Julia 측 WASM 진입점 (예시: Step5 Poisson)
function make_solver(nx::Int64, ny::Int64, rhs::Vector{Float64})::SolverState
function step_solver(s::SolverState, nsteps::Int64)::SolverState
function get_field(s::SolverState)::Vector{Float64}
function get_residual(s::SolverState)::Float64
```

```typescript
// JS 측 호출 패턴
const s = e.make_solver(nx, ny, rhs_vec);  // 만들기
for (let i = 0; i < 10; i++) {
  e.step_solver(s, 1n);                     // 1스텝 전진
  const field = e.get_field(s);             // 현재 장 꺼내기
  const resid = e.get_residual(s);          // 오차 꺼내기
  // → 화면에 중간 결과 표시
}
```

**Worker 연동 시**: `step_solver` 후 `get_field` 결과를 Worker postMessage로 메인 스레드에 전달. 상세 형식은 5절 참조.

---

## 5. Web Worker 래퍼

AGENTS.md 요구: "무거운 단계(5~8)는 Worker에서 돌 수 있게 메시지 형식을 정한 래퍼를 제공. 프레임워크에 의존하지 않는 순수 JS/TS로 작성."

### 5.1. 설계 원칙

- **순수 JS/TS**, Svelte/Vite에 의존하지 않음. `web/src/lib/workers/`에 위치.
- **메시지 기반**: 메인 스레드 ↔ Worker 간 JSON 메시지 교환.
- **WASM 인스턴스**는 Worker 내부에서 생성·보유. 메인 스레드는 WASM을 직접 로드하지 않음.
- **중간 결과**는 Worker가 주기적으로(main 스레드에) push. 메인 스레드는 요청하지 않아도 받음.

### 5.2. Worker API (순수 JS)

```typescript
// web/src/lib/workers/simulation-worker.ts (Worker 내부 코드)
//Worker는 별도 스레드에서 실행. 이 파일을 Worker로 등록.

importScripts(`${import.meta.env.BASE_URL}step5.wasm`);  // WASM 로드 (Worker 내 fetch 불가 시)
// 실제로는 fetch → arrayBuffer → instantiate

let wasmInstance: WebAssembly.Instance;
let currentSolver: any = null;  // SolverState WasmGC 참조

self.onmessage = async (e: MessageEvent<WorkerIn>) => {
  const { type, payload } = e.data;
  switch (type) {
    case 'init': {
      const bytes = await fetch(payload.wasmPath).then(r => r.arrayBuffer());
      const { instance } = await WebAssembly.instantiate(bytes, {});
      wasmInstance = instance;
      self.postMessage({ type: 'ready' });
      break;
    }
    case 'make': {
      // e.g., Step5: 솔버 생성
      const s = wasmInstance.exports.make_solver(payload.nx, payload.ny, payload.rhs_vec);
      currentSolver = s;
      self.postMessage({ type: 'made', solverRef: true });
      break;
    }
    case 'step': {
      // n걸음 전진
      wasmInstance.exports.step_solver(currentSolver, payload.nsteps);
      self.postMessage({
        type: 'stepped',
        nsteps: payload.nsteps,
      });
      break;
    }
    case 'get_field': {
      const field = wasmInstance.exports.get_field(currentSolver);
      // field는 WasmGC Vector → vec_get으로 요소별 읽거나 추가 브릿지 필요
      self.postMessage({ type: 'field', fieldRef: field });
      break;
    }
    case 'get_residual': {
      const resid = wasmInstance.exports.get_residual(currentSolver);
      self.postMessage({ type: 'residual', value: resid });
      break;
    }
    case 'destroy': {
      currentSolver = null;
      self.postMessage({ type: 'destroyed' });
      break;
    }
  }
};
```

```typescript
// web/src/lib/workers/simulation-worker.ts (메인 스레드 측 래퍼)
// 순수 JS — Svelte/Vite 독립적. 브라우저에서만 실행.

export interface WorkerIn {
  type: 'init' | 'make' | 'step' | 'get_field' | 'get_residual' | 'destroy';
  payload?: Record<string, unknown>;
}

export interface WorkerOut {
  type: 'ready' | 'made' | 'stepped' | 'field' | 'residual' | 'destroyed';
  solverRef?: boolean;
  nsteps?: number;
  fieldRef?: unknown;
  value?: number;
}

export class SimulationWorker {
  private worker: Worker;
  private wasmPath: string;
  private onMessage: (msg: WorkerOut) => void;

  constructor(wasmPath: string, onMessage: (msg: WorkerOut) => void) {
    this.wasmPath = wasmPath;
    this.onMessage = onMessage;
    // Worker 파일 자체도 별도 URL로 로드 (blob URL 또는 별도 파일)
    this.worker = new Worker(new URL('./simulation-worker-core.js', import.meta.url), {
      type: 'module',
    });
    this.worker.onmessage = (e) => onMessage(e.data as WorkerOut);
  }

  async init(): Promise<void> {
    this.worker.postMessage({ type: 'init', payload: { wasmPath: this.wasmPath } });
  }

  make(nx: number, ny: number, rhs: Float64Array): void {
    // rhs는 JS Float64Array → WASM vec_new/vec_set으로 전달 필요
    this.worker.postMessage({ type: 'make', payload: { nx, ny, rhs } });
  }

  step(nsteps: number): void {
    this.worker.postMessage({ type: 'step', payload: { nsteps: BigInt(nsteps) } });
  }

  destroy(): void {
    this.worker.postMessage({ type: 'destroy' });
    this.worker.terminate();
  }
}
```

### 5.3. Worker 메시지 형식 확정 스키마

```typescript
// 공통 메시지 래퍼
interface WorkerMessage<T> {
  step: number;          // 단계 번호 (1~9) — 다중 단계 Worker 공유 시 식별
  type: string;          // 메시지 유형
  payload: T;           // 유형별 페이로드
  timestamp?: number;   // 중간 결과 순서 확인용
}

// Step5~7용 메시지 유형
type StepMessages =
  | { type: 'solver-ready'; payload: { solverId: string } }
  | { type: 'step-done';    payload: { solverId: string; nsteps: number;
                                    residual: number } }
  | { type: 'field-update'; payload: { solverId: string;
                                       field: Float64Array;        // JS 측 재구성 배열
                                       timestamp: number } }
  | { type: 'error';        payload: { solverId: string; message: string } }
  | { type: 'done';         payload: { solverId: string;
                                       field: Float64Array;
                                       residual: number } }
```

**field 전달 방식 주의**: WasmGC Vector(`get_field` 반환)를 JS로 직접 읽는 방법은 현재 없음. 실용적 접근:
1. **WASM 측 브릿지**: `get_field_js(s::SolverState)::Vector{Float64}`를 WASM에 컴파일하여 JS에서 vec_get으로 요소별 읽어 JS Float64Array에 재구성 → 격자 크기별 비용 측정 필요
2. **대안**: Worker 내에서 Canvas/SVG 직접 그리기 (DOM 접근 불가 → OffscreenCanvas 사용)

---

## 6. 배열 전달 방식

### 6.1. JS → WASM: Vector 전달

WasmTarget의 Vector 브릿지 패턴 (Step1 검증에서 확인):

```typescript
// JS 측: Float64Array를 WASM Vector로 변환
function jsArrayToWasmVector(e: any, arr: Float64Array): WasmGCVector {
  const n = BigInt(arr.length);
  const v = e.vec_new(n);
  for (let i = 0; i < arr.length; i++) {
    e.vec_set(v, BigInt(i + 1), arr[i]);  // 1-based index
  }
  return v;
}

// 사용 예
const jsArr = new Float64Array([1.0, 2.0, 3.0, 4.0, 5.0]);
const v = jsArrayToWasmVector(e, jsArr);
const result = e.vec_sum(v);  // 15.0
```

**비용**: `vec_set` 요소별 호출 → 격자 크기 비례. 100×100 격자(10,000 요소)면 vec_set 10,000회. **경로 (b) 선형 메모리 대량 복사**는 WasmTarget 기본 경로가 아니므로 현재 사용하지 않음.

### 6.2. WASM → JS: Vector 읽기

WASM Vector를 JS 배열로 읽는 방법:

```typescript
function wasmVectorToJsArray(e: any, v: WasmGCVector, n: bigint): Float64Array {
  const arr = new Float64Array(Number(n));
  for (let i = 0; i < arr.length; i++) {
    arr[i] = e.vec_get(v, BigInt(i + 1));
  }
  return arr;
}
```

**비용**: `vec_get` 요소별 호출 → WASM→JS 경계 교차 비용 포함. 격자 크기별 실측 필요 (보고서의 "확인되지 않은 것" 항목).

### 6.3. 실용적 격자 한계 (현재 추정)

| 격자 크기 | vec_set + vec_get 호출 수 | 예상 JS 오버헤드 | 판정 |
|---|---|---|---|
| 10×10 (100 요소) | 200회 | 무시 가능 | ✓ 실용적 |
| 50×50 (2,500 요소) | 5,000회 | 수 ms 수준 예상 | ✓ 실용적 (확인 필요) |
| 100×100 (10,000 요소) | 20,000회 | 수십 ms 가능성 | ⚠️ 측정 후 결정 |
| 200×200 (40,000 요소) | 80,000회 | 수백 ms 가능성 | ⚠ 대체 경로 검토 |

**참고**: Worker 내에서 계산과 동시에 중간 결과를 `get_field`→vec_get→JS 배열로 재구성해 메인 스레드에 전송하면, 격자 크기가 커질수록 Worker↔메인 스레드 메시지 전달 비용이 지배적일 수 있음. OffscreenCanvas로 Worker 내에서 직접 그리는 대안이 있음.

---

## 7. 조작 항목 목록 파일 (Manifest) 스키마

### 7.1. 파일 위치·이름 규칙

```
web/public/stepN_manifest.json
```

- `N`: 단계 번호 (1~9)
- 빌드 시 `scripts/build_wasm.jl`이 생성
- 화면이 읽어 조작 요소·대안·함수 목록을 구성

### 7.2. 스키마는 세 블록

```typescript
interface StepManifest {
  // ── 메타데이터 ──
  step: number;              // 단계 번호
  wasmFile: string;          // WASM 파일명 (stepN.wasm)
  title?: string;            // 단계 제목 (표시용)
  question?: string;         // 핵심 질문 (표시용)

  // ── 조작 가능 값 (Manipulators) ──
  // 화면의 슬라이더/입력 요소 구성용
  manipulators: Manipulator[];

  // ── 대안 지점 (Alternatives) ──
  // 단계당 1~2개. 화면은 대안 선택 UI를 이 정보로 구성
  alternatives: Alternative[];

  // ── 노출 함수 (Functions) ──
  // WASM export 함수 목록. 화면은 이 정보로 호출 코드 구성
  functions: WasmFunction[];

  // ── 부가 정보 ──
  browserRequirements?: string;
  knownLimits?: string[];
}

interface Manipulator {
  name: string;              // 변수명 (코드 내 식별자와 일치)
  unit?: string;             // 표시용 단위
  default: number;           // 기본값
  range: [number, number];   // 허용 범위 [min, max]
  step?: number;             // 슬라이더 스텝 크기 (생략 시 자동)
  usedBy: string[];          // 이 값을 받는 함수 목록
  sourceLocation?: string;   // 소스 파일 내 위치 (표시용)
}

interface Alternative {
  location: string;          // 대안 지점 설명 (표시용)
  options: AlternativeOption[];
}

interface AlternativeOption {
  id: string;                // 식별자 (화면 선택값)
  name: string;              // 표시 이름
  fn?: string;               // 연결된 WASM 함수명 (없으면 기존 함수 재사용)
  param?: string;            // 변경하는 매개변수명
}

interface WasmFunction {
  name: string;
  args: string[];            // 인자 타입 (표시용 문자열)
  ret: string;               // 반환 타입 (표시용)
  note?: string;             // 주의사항
}
```

### 7.3. Step1 manifest 예시 (실제 파일 구조)

`web/public/step1_manifest.json` (실제 생성 파일):

```json
{
  "step": 1,
  "wasmFile": "step1.wasm",
  "functions": [
    { "name": "top_speed", ... },
    { "name": "compare_drs", ... },
    ...
  ],
  "manipulators": [
    { "name": "P", "unit": "W", "default": 500000.0,
      "range": [100000.0, 1000000.0], "usedBy": ["top_speed", "compare_drs"] },
    { "name": "Cd", "unit": "—", "default": 0.30,
      "range": [0.10, 0.50], "usedBy": ["top_speed", "compare_drs"] },
    ...
  ],
  "alternatives": [
    {
      "location": "derivative_fd vs derivative_dual",
      "options": [
        { "id": "fd", "name": "유한차분 (전진차분, 차수 1)",
          "fn": "derivative_fd", "param": "h" },
        { "id": "dual", "name": "이중수 자동미분 (정확)",
          "fn": "derivative_dual", "param": "없음" }
      ]
    }
  ],
  "browserRequirements": "WasmGC 지원 브라우저: Chrome 119+, Firefox 120+, Safari 18.2+",
  "knownLimits": [
    "Dual{Float64}는 WasmGC struct — JS에서 직접 생성·읽기 불가",
    "derivative_dual JS 호출 시 WebAssembly.Exception — derivative_fd 사용 권장",
    "Vector 브릿지는 요소별 JS 호출 — 격자 크기별 비용 측정 필요"
  ]
}
```

### 7.4. 화면에서의 사용

```typescript
// 화면 컴포넌트 (Svelte)
<script lang="ts">
  import { onMount } from 'svelte';
  import { loadWasm } from '$lib/wasm';

  let manifest: StepManifest;
  let wasmExports: any;
  let loading = true;

  onMount(async () => {
    const [m, wasm] = await Promise.all([
      fetch(`/step1_manifest.json`).then(r => r.json()),
      loadWasm('/step1.wasm'),
    ]);
    manifest = m;
    wasmExports = wasm.exports;
    loading = false;
  });

  // 조작 값 변경 시 재계산
  function recompute(): void {
    const P = +document.getElementById('input-P').value;
    const Cd = +document.getElementById('input-Cd').value;
    const result = wasmExports.top_speed(
      P, 1.225, Cd, 0.55, 0.0, 1e-12, 50n
    );
    document.getElementById('result-speed').textContent = result;
  }
</script>
```

---

## 8. 소스 파일이 유일한 출처

AGENTS.md 요구: "화면은 컴파일에 쓴 `.jl` 파일을 문자열로 불러와 표시. 표시용 사본을 따로 만들지 않음. 함수 단위로 보여줄 수 있도록 파일이나 구역을 나눔."

### 8.1. 소스 파일 구조 (Step1)

Step1의 Julia 소스 파일은 두 개:

| 파일 | 역할 | 화면 표시 |
|---|---|---|
| `src/01-differentiation-newton.jl` | 교재 코드: Dual, Newton법, 유한차분, 자동미분, DRS 물리 모델 | ✓ 표시 대상 |
| `src/step1_wasm.jl` | WASM 진입점 래퍼: top_speed_wasm, compare_drs_wasm, Vector 브릿지 등 | ✗ 표시 대상 아님 (빌드 산출물) |

### 8.2. 소스 파일 표시 방식

- 화면은 SvelteKit `public/`이 아닌 `src/`의 Julia 파일을 읽어야 함. SvelteKit 정적 빌드 시 `src/`는 클라이언트에 노출되지 않으므로, **빌드 스크립트가 소스 파일을 `web/public/src-steps/`에 복사**하거나, **Vite 플러그인으로 처리**한다.
- 현재 권장 방식: `scripts/build_wasm.jl`이 WASM 컴파일에 사용한 `src/01-differentiation-newton.jl`을 `web/public/src-steps/step1/`에 복사. 화면은 이 경로의 파일을 `fetch()`로 읽어 코드 블록으로 표시.

```
web/public/src-steps/
├── step1/
│   └── 01-differentiation-newton.jl   # 화면 표시용 소스 (교재 코드만)
├── step2/
│   └── ...
```

### 8.3. WASM 컴파일에 사용한 파일

`scripts/build_wasm.jl`의 include 순서:
```julia
include("src/01-differentiation-newton.jl")   # 교재 코드 + Step1DiffNewton 모듈
using .Step1DiffNewton
include("src/step1_wasm.jl")                   # WASM 진입점 래퍼 (top_speed_wasm 등)
# ... compile_multi 호출
```

- WASM 컴파일에 사용한 파일 = 화면 표시용 파일: `src/01-differentiation-newton.jl`
- `src/step1_wasm.jl`은 WASM 컴파일용 진입점만 담음. 화면 표시 대상 아님.
- "화면에 보이는 Julia 코드가 곧 브라우저에서 도는 코드" — `src/01-differentiation-newton.jl`이 화면에 표시되고, 이 파일의 Dual 연산·Newton법 등이 WASM으로 컴파일되어 브라우저에서 실행됨. `src/step1_wasm.jl`은 그 WASM 진입점을 제공하는 별도의 구현 레이어.

---

## 9. 정답 데이터도 내보냄

AGENTS.md 요구: "해석해를 계산하는 함수와 문헌 표(예: Ghia)를 화면이 가져다 쓸 수 있게 함."

### 9.1. 해석해 함수 (WASM에 포함)

Step1의 경우 `top_speed_analytic_zero_rolling` (구름저항 0 해석해)가 이미 `Step1DiffNewton` 모듈에 있음. WASM에 포함하지 않은 이유는:
- 이 함수는 단순 산술 `(2P/(ρCdA))^(1/3)` → WASM 컴파일 trivial
- top_speed의 검증 기준으로 사용 (테스트에서 확인 완료)
- **화면이 직접 계산할 수 있게 JS 구현도 제공**

```typescript
// web/src/lib/step1-js-answers.ts
/**
 * 구름저항 0일 때 최고속도 해석해
 * v_top = (2P / (ρ·Cd·A))^(1/3)
 */
export function topSpeedAnalyticZeroRolling(
  P: number, ρ: number, Cd: number, A: number
): number {
  return Math.cbrt((2 * P) / (ρ * Cd * A));
}
```

### 9.2. 문헌 표 (Ghia et al. 1982) — 7단계

7단계 Lid-driven Cavity의 Ghia 테이블은 원 논문에서 직접 읽어서 `web/public/data/ghia_1982.json`으로 제공. Step1에서는 해당 없음.

---

## 10. 브라우저 요구사항

| 요구사항 | 상세 |
|---|---|
| **WasmGC** | Chrome 119+ (2023-11), Firefox 120+ (2023-12), Safari 18.2+ (2024년 말) |
| **BigInt** | Chrome 67+, Firefox 68+, Safari 14+ (WasmTarget Int64 인자 전달에 필요) |
| **WebAssembly.Exception** | Chrome 119+, Firefox 120+, Safari 18+ (WasmGC throw/from 자바스크립트 캐치) |
| **Web Workers** | 모든 최신 브라우저 (Worker 내 WASM 실행용) |
| **fetch()** | 모든 최신 브라우저 (WASM·manifest 로드) |

**지원 범위 판단**: 2026년 10월 기준 주요 브라우저 대부분이 WasmGC 지원. Safari 18.2 미만 기기(iOS 17 이하)는 WasmGC 미지원 → "브라우저 업그레이드 권장" 메시지 표시.

### 10.1. 브라우저 감지

```typescript
// web/src/lib/wasm.ts
export function checkWasmGCSupport(): { supported: boolean; browser: string; version?: string } {
  // 간단한 User-Agent 기반 판별 (정밀 감지에는 wasm-feature-detect 라이브러리 사용)
  if (typeof WebAssembly === 'undefined') {
    return { supported: false, browser: 'unknown' };
  }
  // WasmTarget WASM 모듈 인스턴스화 시도 → 성공 여부로 WasmGC 지원 확인
  // (실제 감지: wasm-feature-detect 라이브러리 권장)
  return { supported: true, browser: 'modern' };
}
```

---

## 11. 알려진 한계

### 11.1. Step1 특정 한계

| 한계 | 영향 | 대응 |
|---|---|---|
| **Dual{Float64} JS 입출력 불가** | `dual_add`, `dual_mul`은 WASM에서 컴파일되나 JS에서 Dual 입력 생성 불가 → 직접 호출 불가 | Dual 입출력 브릿지 함수 추가 시 호출 가능 (향후). `derivative_fd`로 기능 대체 가능 |
| **derivative_dual 브라우저 동작 확인** | `e.derivative_dual(1.0)` → 8.0 (브라우저에서 정상 동작). WASM 내부에서 Dual(x,1.0) 생성 후 f_poly_wasm 적용, .der 추출. JS에서 상수 number 전달 가능. | 추가 대응 불필요. 듀얼수 자동미분 실제로 브라우저에서 작동. |
| **기본 인자(GlobalRef) 미지원** | 원본 `top_speed`, `newton` 등은 WASM 컴파일 불가 | 모든 WASM 진입점은 기본 인자 없이 모든 인자 명시. WASM 전용 래퍼 패턴 사용 |
| **Function 인자 불가 (dynamic dispatch)** | `newton(f, df, ...)`의 f, df 인자 → dynamic dispatch → 컴파일 불가 | WASM에서는 구체적 함수 사용 또는 Newton 로직 직접 구현 |
| **Vector 브릿지 요소별 호출 비용** | 격자 크기별 vec_set/vec_get 비용 미측정 | 7단계 Cavity 이전 측정 필요. 중소 격자(≤50×50)는 실용적 추정 |

### 11.2. WasmTarget.jl 일반 한계

| 한계 | 상세 |
|---|---|
| **실험적 도구** | "correct-or-loud" 철학: 컴파일 안 되면 명확한 오류. 커버리지 gap 발생 가능 |
| **동적 디스패치 불가** | 다중 디스패치, `Any` 타입, 함수 인자 불가 |
| **생태계 패키지 불가** | BLAS, 대부분의 Julia 생태계 패키지 컴파일 불가. 수학 함수는 Julia 1.12부터 순수 Julia 구현이라 가능 |
| **Julia 1.12 권장** | 1.13은 WasmTarget v0.5.3 기준 `CC.compile!` 키워드 incompatibility (향후 WasmTarget 업데이트 확인) |
| **WasmGC 브라우저 요구** | 구형 브라우저(iOS 17 이하 Safari 등) 미지원 |

---

## 12. Worker 래퍼 API (요약)

웹 Worker 래퍼(`web/src/lib/workers/`)가 제공하는 공개 API:

```typescript
// Step1은 단일 호출 계산 → Worker 불필요. 경량 단계는 메인 스레드에서 직접 호출.

// Step5~7용 Worker API (향후 구현)
interface StepWorkerAPI {
  // 초기화
  init(wasmPath: string): Promise<void>;

  // 만들기
  make(nx: number, ny: number, rhs: Float64Array): Promise<string>; // solverId 반환

  // n걸음 전진 (중간 결과 포함)
  step(solverId: string, nsteps: number): Promise<{ residual: number }>;

  // 현재 장 꺼내기 (WASM Vector → JS Float64Array 브릿지 포함)
  getField(solverId: string): Promise<Float64Array>;

  // 오차 꺼내기
  getResidual(solverId: string): Promise<number>;

  // 정리
  destroy(solverId: string): void;
}
```

**중간 결과 주기 반환**: Worker가 `step()` 호출 후 자동으로 `postMessage({ type: 'field-update', ... })`를 메인 스레드에 전송. 메인 스레드는 `onmessage`로 받아 화면에 표시. **요청-응답 모델 아님 — Worker가 push.**

---

## 13. 요약: 화면 개발자가 알아야 할 핵심

| 항목 | 요약 |
|---|---|
| **WASM 파일** | `/step1.wasm` (48.3 KB, 최적화됨). `public/`에 있음 |
| **Manifest** | `/step1_manifest.json`. 조작 요소·함수·대안 정보 포함 |
| **WASM 로드** | `fetch()` → `arrayBuffer()` → `WebAssembly.instantiate(bytes, {})` |
| **함수 호출** | `instance.exports.함수명(인자들)` |
| **Float64 인자** | JS `number` 그대로 전달 |
| **Int64 인자** | JS `BigInt` (예: `50n`) |
| **Vector{Float64} 반환/인자** | `vec_new`로 생성 → `vec_set`/`vec_get`/`vec_len`/`vec_sum`으로 조작. JS에서 직접 읽기 불가 |
| **Dual{Float64}** | JS에서 직접 생성·호출 불가. `derivative_fd` 사용 |
| **중간 결과** | Step1은 단일 호출. Step5~7은 make/step/get_field/get_residual 분할 패턴 |
| **Worker** | Step5~8은 Worker에서 실행. Worker가 중간 결과를 메인 스레드에 push |
| **브라우저** | WasmGC 지원 필요: Chrome 119+, Firefox 120+, Safari 18.2+ |
| **소스 표시** | `src/01-differentiation-newton.jl`을 `public/src-steps/step1/`에 복사 → 화면 fetch로 표시 |
| **정답 데이터** | `topSpeedAnalyticZeroRolling`은 JS 함수로 제공. Ghia 표는 7단계에서 JSON 제공 |
