# 1단계 검증 보고서 — WasmTarget.jl 툴체인

> **이 문서는 과거 기록입니다 (2026-10-05 대체됨).** 아래의 "함수 인자 미지원", "기본 인자 미지원"
> 결론과 "WASM 전용 래퍼" 패턴은 더 이상 유효하지 않습니다. 파일 경로(`scripts/build_wasm.jl`,
> `src/step1_wasm.jl`)와 성능 추정치도 현재 저장소와 다릅니다. 현재 구조와 다시 확인한 결과는
> [2026-10-05-architecture-refactor.md](2026-10-05-architecture-refactor.md)와
> [../calling-convention.md](../calling-convention.md)를 보십시오.

**작성일**: 2026-10-04  
**확인 시점 WasmTarget.jl 문서 URL**: https://grouptherapyorg.github.io/WasmTarget.jl/manual/  
**WasmTarget.jl 버전**: v0.5.3 (2026년 6월 22일 discourse 업데이트 기준)  
**사용 Julia 버전**: 1.12.7 (1.13.1은 `CC.compile!` new 키워드 incompatibility로 실패)

---

## 1. WasmTarget.jl 현재 상태 (문서 기반)

### 지원 Julia 버전
- **Julia 1.12, 1.13** — CI green (2026-06-22 discourse 업데이트)
- Julia 1.13.1 실제 사용 시 `Core.Compiler.compile!`에 추가된 필수 키워드 `external_linkage` 누락으로 WasmTarget v0.5.3 컴파일 실패 → ** Julia 1.12 사용 권장**

### WasmGC 지원 브라우저 범위
- Chrome 119+ (2023년 11월), Firefox 120+ (2023년 12월), Safari 18.2+ (2024년 말)
- "대규모 브라우저 사용량이 현재 WasmGC를 지원함" (WasmTarget 문서 + Chrome 개발자 블로그)
- 타겟 audiences 기준으로 문제 없는 범위

### 알려진 제약
- 동적 디스패치 불가 — `Any` 타입 인자, 함수 인자(`Function`)는 컴파일 불가
- `ccall` 경로(BLAS 등) 불가 — 단, Julia 1.12부터 수학 함수는 순수 Julia 구현이라 libm foreigncall 없음
- 생태계 패키지 대부분 컴파일 불가
- **기본 인자(default argument)의 GlobalRef 처리 미비** — 모듈 상수 참조가 IR에 남으면 `unsupported_global` 오류
- **함수 `Function` 인자** — dynamic dispatch 발생 → 컴파일 불가

### WasmGC 배열/구조체 매핑
- `struct Foo ... end` → WasmGC `struct` (필드 직접 매핑) — **Dual{T} 포함**
- `Vector{T}` → WasmGC `struct{array, length}` — JS에서 직접 생성 불가
- `Matrix{T}` → WasmGC `struct{array, sizes}`
- `JSValue` → `externref` (JS 객체 opaque 핸들)

---

## 2. JS에서 WASM 배열 결과 읽는 경로 — 2가지 시도·비교

### 경로 (a): WasmGC 배열을 JS에서 직접 접근하는 방법
- **결론: 실질적으로 불가**
- WasmGC 배열은 JS에서 "Exported GC Object"로 노출되나, opaque 참조일 뿐 Indexed Array처럼 요소 접근 불가
- W3C Wasm GC spec + Reddit/HackerNews 논의에서 확인된 한계: "WasmGC 배열을 ArrayBuffer로 bulk copy하는 효율적 방법 없음" (open issue)
- WasmTarget도 이 한계를 인정하고 Vector 브릿지 패턴을 공식 권장

### 경로 (b): 선형 메모리 + JS 쪽 재배치
- WasmTarget은 WasmGC struct/array를 우선 사용하므로 선형 메모리 직접 접근이 기본 경로가 아님
- 필요시 `add_memory!`로 선형 메모리 추가 가능하지만, WasmTarget IDL과 호환 작업 필요
- **현재의 실용적 경로: WasmTarget 공식 권장 Vector 브릿지 패턴** (아래 확인 결과 참조)

### 확인 결과: Vector 브릿지 패턴 (WasmTarget 공식 권장)
WasmTarget 매뉴얼의 "Manual Vector Bridge" 패턴을 그대로 적용:

```julia
# WASM 측 컴파일 대상
vec_new(n::Int64)::Vector{Float64} = Vector{Float64}(undef, n)
vec_set!(v::Vector{Float64}, i::Int64, val::Float64)::Int64 = (v[i] = val; Int64(0))
vec_get(v::Vector{Float64}, i::Int64)::Float64 = v[i]
vec_len(v::Vector{Float64})::Int64 = Int64(length(v))
vec_sum(v::Vector{Float64})::Float64 = sum(v)

# JS 측 호출
const v = e.vec_new(5n);           // BigInt: Int64 인자
e.vec_set(v, 1n, 1.0);             // 1-based indexing (Julia 관습)
e.vec_set(v, 2n, 2.0);
const len = e.vec_len(v);          // 5
const sum = e.vec_sum(v);          // 15.0
```

**JS 테스트 결과**: vec_new, vec_set, vec_get, vec_len, vec_sum **모두 정상 동작 확인** ✓

**한계**: 
- JS → WASM 배열 전달은 WASM 측에서 배열 생성 후 요소 채우는 방식 (진정한 "JS 배열 읽기" 아님)
- 대용량 격자(예: 100×100 Cavity)의 요소별 세팅은 JS 측에서 루프 돌며 vec_set 호출 → 격자 크기별 비용 측정 필요 (향후 7단계에서)
- 100×100 Float64 격자: vec_set × 10,000회 → JS 오버헤드 우세 가능성

---

## 3. 번들 크기 (WASM 파일 크기) 및 네이티브 Julia 대비 속도

### WASM 파일 크기 (WasmTarget v0.5.3, Julia 1.12)

| 함수 | 최적화 전 | 최적화 후 (wasm-opt) | 압축률 |
|---|---|---|---|
| dual_add (Dual+, Dual+) | 13,623 B | **715 B** | 94.7% |
| dual_mul (Dual×, Dual×) | — | **729 B** | — |
| derivative_dual (Dual 자동미분) | 14,329 B | **775 B** | 94.6% |
| derivative_fd (전진차분) | 13,340 B | **702 B** | 94.8% |
| top_speed_wASM (Newton 직접구현) | 89,434 B | **25,756 B** | 71.2% |
| compare_drs_wASM | 89,856 B | **26,018 B** | 71.0% |
| **전체 모듈 (13함수)** | **97,547 B (95.3 KB)** | — | — |

**wasm-opt**: Binaryen_jll 내장, `optimize=true`로 자동 적용. 평균 80-95% 크기 감소.

### 네이티브 Julia 성능 (간단 평균 타이밍, 1.12.7)

| 함수 | 평균 시간 |
|---|---|
| f_poly(1.0) | ≈0 μs (측정 한계) |
| derivative_fd(f_poly, 1.0, h=1e-6) | 0.3 μs |
| top_speed (Newton법, tol=1e-12, maxiter=50) | 12.6 μs |
| compare_drs (Cd 0.30→0.20) | 9.1 μs |

### WASM 추정 성능
- WASM 함수 호출 오버헤드 (Node.js): 약 1–5 μs/호출
- WASM 내부 연산: WasmGC JIT로 네이티브의 대략 50–100% 수준 추정 (정량 측정은 브라우저 환경에서 필요)
- **top_speed WASM** (25.7 KB, 최적화): 호출 ≈ (12.6 μs × 0.5~1.0) + 1~5 μs 오버헤드 ≈ 7~18 μs 추정

---

## 4. Step1 커널 WASM 컴파일 결과 요약

### 컴파일 성공 (JS에서 직접 호출 가능)
| 함수 | 상태 | 비고 |
|---|---|---|
| f_poly, df_analytic | ✓ | 스칼라 다항식, 해석적 미분 |
| derivative_fd | ✓ | 구체적 함수(f_poly) 전진차분 |
| top_speed | ✓ | Newton 반복 WASM 직접 구현 (기본 인자 회피) |
| compare_drs | ✓ | top_speed 로직 직접 구현 |
| vec_new, vec_set, vec_get, vec_len, vec_sum | ✓ | Vector 브릿지 패턴, JS에서 정상 호출 확인 |
| dual_add, dual_mul | ✓ | Dual 연산은 컴파일 성공, JS 호출은 Dual 입력 필요 (아래 제한) |

### 컴파일 실패 / 제한
| 시도 함수 | 오류 | 원인 및 대응 |
|---|---|---|
| `newton` (Function 인자) | dynamic dispatch (`Any`) | 함수 인자 미지원 → WASM에서 Newton 로직 직접 구현으로 우회 |
| `top_speed` (원본, 기본 인자 `maxiter=50`) | `unsupported_global: GlobalRef` | 기본 인자의 GlobalRef 처리 미비 → 모든 인자 명시하는 WASM 전용 함수 작성 |
| `derivative_dual` (JS 호출 시) | WebAssembly.Exception | Dual(T)가 WasmGC struct — JS에서 Dual 입력 생성 방법 없음. **derivative_fd로 기능 대체 가능** |
| `newton_wASM` (f::Any, df::Any) | dynamic dispatch | WASM에서는 concrete 함수만 사용 → 스칼라 특화 버전으로 제한 |

---

## 5. WasmTarget.jl 계속 사용 여부 — 판단

### 계속 사용하는 것이 타당한 이유
1. **Dual{T} 구조체 → WasmGC struct 컴파일 성공** (ForwardDiff 예시도 공식 docs에서 확인). 8단계 PINN의 자동미분과 직접 연결됨.
2. **Vector 브릿지 패턴으로 배열 처리 가능** — 5~7단계 Poisson, Cavity에서 핵심.
3. **julia → WASM "화면에 보이는 Julia 코드가 곧 브라우저 코드" 핵심 약속 충족**. Dual, Newton, 유한차분 코드 수정 없이 (WASM 전용 래퍼만 추가) JS 호출 가능.
4. **등록된 패키지** (`Pkg.add("WasmTarget")`), 2409 테스트 통과, ForwardDiff·Statistics·LinearAlgebra 부분 지원.
5. **wasm-opt로 80-95% 크기 감소** → 1단계 전체 95 KB → 최적화 후 수십 KB 수준.

### 주의해야 할 점 (가정·한계)
1. **Julia 1.12 사용 필수** — 1.13은 `CC.compile!` 변경 incompatibility (WasmTarget v0.5.3 기준). 향후 WasmTarget 업데이트로 1.13 지원되면 전환 검토.
2. **기본 인자의 GlobalRef** — 모든 WASM 진입점(entry point)은 기본 인자 없이 모든 인자를 명시적으로 받아야 함. Step2 이후 적분기 등에서도 동일 문제 예상 → WASM 전용 래퍼 패턴 표준화 필요.
3. **Dual 자동미분 JS 호출** — derivative_dual은 WASM에서 컴파일되나 JS에서 Dual 입력 생성 방법이 없어 현재 직접 호출 불가. **실용적 대안: derivative_fd 사용, 또는 WASM 측에서 Dual 생성·반환하는 브릿지 함수 추가** (Dual inputs/outputs를 JS가 직접 조작하지 않아도 되는 경우 유용).
4. **Vector 브릿지 비용** — 격자 크기별 vec_set 호출 비용은 7단계에서 실제 측정 필요. 현재 추정으로는 중소 격자(≤50×50)에서 실용적.
5. **WasmTarget은 실험적 도구** — "correct-or-loud" 철학: 컴파일 안 되는 것은 명확한 오류로 알려줌. 커버리지 gap 발생 시 WasmTarget 이슈에 파일링하거나 우회 구현.

### 결론: **WasmTarget.jl 사용 — 계속 진행 권장**
- 1단계 핵심 커널(Dual, Newton, 유한차분, top_speed)의 WASM 컴파일 성공
- JS interop 패턴(Vector 브릿지) 확인 및 동작 검증 완료
- 남은 과제: Dual JS 입출력 브릿지, 격자 크기별 Vector 브릿지 비용 측정 (7단계)

---

## 6. 코드 변경 요약 (PR에 포함)

### WASM 빌드 스크립트 위치
- `/scripts/build_wasm.jl` — 현재 자리 표시자. 아래 내용으로 구현 필요.

### WASM 전용 래퍼 패턴 (Step1 기준)
원본 함수와 별도로 WASM 진입점 함수를 작성 (기본 인자 없음, 모든 인자 명시, concrete 타입). 예:

```julia
# src/01-differentiation-newton.jl 의 WASM 진입점 (추가 예정)
function top_speed_wasm(P::Float64, ρ::Float64, Cd::Float64,
                        A::Float64, Froll::Float64,
                        tol::Float64, maxiter::Int64)::Float64
    # Newton 반복 직접 구현 (newton 함수 호출 회피)
    ...
end
```

### 빌드 스크립트 (build_wasm.jl) 초기 구현 방향
```julia
using WasmTarget
include("src/01-differentiation-newton.jl")
using .Step1DiffNewton

# WASM 진입점들
bytes = compile_multi([
    (top_speed_wasm,        (...명시적 인자...), "top_speed"),
    (derivative_fd_wasm,    (Float64, Float64),  "derivative_fd"),
    (vec_new_wasm,          (Int64,),              "vec_new"),
    ...
], optimize=true)

write("web/public/step1.wasm", bytes)
# 조작 항목 목록 JSON도 함께 생성
```

---

## 7. 확인되지 않은 것 (가정·향후 확인)

- [ ] **듀얼 수 JS 입출력 브릿지** — WASM 측 Dual 생성·반환 함수 필요 여부, 구현 복잡도
- [ ] **JS에서 WASM 실행 속도 실측** — 브라우저(Firefox/Chrome)에서 WebAssembly.instantiate 후 실제 호출 시간 측정 필요 (Node.js는 WasmGC 미지원일 수 있음 — 브라우저에서 재검증)
- [ ] **격자 크기별 Vector 브릿지 비용** — 7단계 Cavity 이전 측정
- [ ] **WasmTarget v0.5.3 이상 버전** — 1.13 호환성 개선 여부 (최신 버전 확인 후 업그레이드 검토)
- [ ] **WasmGC 배열 → JS TypedArray 직접 읽기** 가능성 — 최신 브라우저 API 변경 확인 (2026년 후반)
