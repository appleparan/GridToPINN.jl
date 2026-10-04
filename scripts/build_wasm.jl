# build_wasm.jl — Step1 WASM 컴파일 스크립트
#
# 용도: Julia 커널을 WasmTarget.jl로 WasmGC WASM에 컴파일,
#        산출물(.wasm)을 web/public/에 배치.
#
# 사용법 (Julia 1.12 필요):
#   julia +1.12 --project=. scripts/build_wasm.jl
#
# 출력:
#   web/public/step1.wasm        — 최적화된 WASM 모듈
#   web/public/step1_manifest.json — 조작 항목·함수 목록 (스키마 문서 참조)
#
# 전제:
#   - WasmTarget.jl = Project.toml에 등록됨 (Pkg.add("WasmTarget"); Julia 1.12)
#   - wasm-opt (Binaryen_jll)는 WasmTarget 설치 시 자동 포함
#   - 출력 경로는 프로젝트 루트의 web/public/ (사이트 기준 경로)

using WasmTarget
using JSON

# 프로젝트 루트: scripts/의 부모 디렉터리
const ROOT = dirname(@__DIR__)
const SRC  = joinpath(ROOT, "src")
const WEB  = joinpath(ROOT, "web", "public")
const OUT_WASM = joinpath(WEB, "step1.wasm")
const OUT_MANIFEST = joinpath(WEB, "step1_manifest.json")

# WASM 진입점 함수들 (기본 인자 없음, 모든 인자 명시, concrete 타입)
# → 원본 Step1DiffNewton 함수의 "WASM용 래퍼"

include(joinpath(SRC, "01-differentiation-newton.jl"))
using .Step1DiffNewton

# ---------------------------------------------------------------------------
# Dual 연산 (WASM 노출용 래퍼 — Dual{T}는 WasmGC struct, JS에서 직접 생성 불가)
# Dual 입출력은 WASM 측 브릿지 함수가 별도로 필요 (현재 여기서는 연산만 컴파일)
# ---------------------------------------------------------------------------
dual_add_wasm(d1::Dual{Float64}, d2::Dual{Float64}) = d1 + d2
dual_mul_wasm(d1::Dual{Float64}, d2::Dual{Float64}) = d1 * d2

# ---------------------------------------------------------------------------
# Vector 브릿지 (WasmTarget 공식 권장 패턴)
# JS에서 Vector{Float64} 직접 생성 불가 → WASM 측 생성 + 요소 조작 함수
# ---------------------------------------------------------------------------
vec_new_wasm(n::Int64)::Vector{Float64}       = Vector{Float64}(undef, n)
vec_set_wasm(v::Vector{Float64}, i::Int64, val::Float64)::Int64 = (v[i] = val; Int64(0))
vec_get_wasm(v::Vector{Float64}, i::Int64)::Float64          = v[i]
vec_len_wasm(v::Vector{Float64})::Int64                       = Int64(length(v))
vec_sum_wasm(v::Vector{Float64})::Float64                     = sum(v)

# ---------------------------------------------------------------------------
# 스칼라 함수 (구체적, WASM에 함께 컴파일)
# ---------------------------------------------------------------------------
f_poly_wasm(x::Float64)::Float64 = x^3 + 2.0 * x^2 + x
df_analytic_wasm(x::Float64)::Float64 = 3.0 * x^2 + 4.0 * x + 1.0

# ---------------------------------------------------------------------------
# derivative_fd (구체적 함수 f_poly_wasm에 대한 전진차분)
# ---------------------------------------------------------------------------
derivative_fd_wasm(x::Float64, h::Float64)::Float64 =
    (f_poly_wasm(x + h) - f_poly_wasm(x)) / h

# ---------------------------------------------------------------------------
# derivative_dual (구체적 함수 f_poly_wasm에 대한 Dual 자동미분)
# 주의: Dual{Float64}가 WasmGC struct로 JS에서 직접 생성 불가 →
#       JS 호출 시 Dual 입력을 받을 수 없음. WASM 측 Dual 생성 브릿지 필요.
# ---------------------------------------------------------------------------
derivative_dual_wasm(x::Float64)::Float64 =
    Step1DiffNewton.derivative_dual(f_poly_wasm, x)

# ---------------------------------------------------------------------------
# top_speed_wasm — Newton 반복을 내부에서 직접 구현
# (원본 top_speed의 기본 인자 maxiter::Int=50이 GlobalRef로 IR에 남아
#  WasmTarget이 처리 못 함. 모든 인자 명시, Newton 로직 직접 작성.)
# ---------------------------------------------------------------------------
function top_speed_wasm(P::Float64, ρ::Float64, Cd::Float64,
                         A::Float64, Froll::Float64,
                         tol::Float64, maxiter::Int64)::Float64
    # f(v) = ½ρ·Cd·A·v³ + Froll·v − P
    # f′(v) = (3/2)ρ·Cd·A·v² + Froll
    f  = v -> 0.5 * ρ * Cd * A * v * v * v + Froll * v - P
    df = v -> 1.5 * ρ * Cd * A * v * v + Froll
    # 초기 추측: 구름저항 0 해석해  v₀ = (2P/(ρCDa))^(1/3)
    x  = (2.0 * P / (ρ * Cd * A))^(1.0 / 3.0)
    x  = max(x, 1.0)
    for i in 1:maxiter
        fx  = f(x)
        dfx = df(x)
        if dfx == 0.0
            throw(ErrorException("Newton: f′(v) = 0"))
        end
        xnew = x - fx / dfx
        if abs(xnew - x) < tol * (1.0 + abs(xnew))
            return xnew
        end
        x = xnew
    end
    throw(ErrorException("Newton: $(maxiter)회 반복 후 수렴하지 않음"))
end

# ---------------------------------------------------------------------------
# compare_drs_wasm — DRS 개폐(Cd 차이)에 따른 속력 차이
# ---------------------------------------------------------------------------
function compare_drs_wasm(P::Float64, ρ::Float64, A::Float64, Froll::Float64,
                          Cd_closed::Float64, Cd_open::Float64,
                          tol::Float64, maxiter::Int64)::Float64
    # Newton 반복 헬퍼 (클로저)
    function newton_one(f, df, x0::Float64, tol::Float64, maxiter::Int64)::Float64
        x = x0
        for i in 1:maxiter
            fx  = f(x)
            dfx = df(x)
            if dfx == 0.0
                throw(ErrorException("Newton: f′ = 0"))
            end
            xnew = x - fx / dfx
            if abs(xnew - x) < tol * (1.0 + abs(xnew))
                return xnew
            end
            x = xnew
        end
        throw(ErrorException("Newton: 수렴하지 않음"))
    end

    # 닫힌 상태
    f_c  = v -> 0.5 * ρ * Cd_closed * A * v * v * v + Froll * v - P
    df_c = v -> 1.5 * ρ * Cd_closed * A * v * v + Froll
    v_c  = newton_one(f_c, df_c,
                      max((2.0 * P / (ρ * Cd_closed * A))^(1.0 / 3.0), 1.0),
                      tol, maxiter)
    # 열린 상태
    f_o  = v -> 0.5 * ρ * Cd_open * A * v * v * v + Froll * v - P
    df_o = v -> 1.5 * ρ * Cd_open * A * v * v + Froll
    v_o  = newton_one(f_o, df_o,
                      max((2.0 * P / (ρ * Cd_open * A))^(1.0 / 3.0), 1.0),
                      tol, maxiter)
    return v_o - v_c
end

# ---------------------------------------------------------------------------
# 컴파일
# ---------------------------------------------------------------------------
function build()
    mkpath(WEB)

    entries = [
        # Dual 연산
        (dual_add_wasm,     (Dual{Float64}, Dual{Float64}),    "dual_add"),
        (dual_mul_wasm,     (Dual{Float64}, Dual{Float64}),    "dual_mul"),
        # Vector 브릿지
        (vec_new_wasm,      (Int64,),                            "vec_new"),
        (vec_set_wasm,      (Vector{Float64}, Int64, Float64), "vec_set"),
        (vec_get_wasm,      (Vector{Float64}, Int64),          "vec_get"),
        (vec_len_wasm,      (Vector{Float64},),                "vec_len"),
        (vec_sum_wasm,      (Vector{Float64},),                "vec_sum"),
        # 스칼라 함수
        (f_poly_wasm,       (Float64,),                         "f_poly"),
        (df_analytic_wasm,  (Float64,),                         "df_analytic"),
        # 미분
        (derivative_fd_wasm,  (Float64, Float64),              "derivative_fd"),
        (derivative_dual_wasm,(Float64,),                       "derivative_dual"),
        # 최고속도 / DRS
        (top_speed_wasm,    (Float64, Float64, Float64, Float64, Float64, Float64, Int64),
                                            "top_speed"),
        (compare_drs_wasm,  (Float64, Float64, Float64, Float64, Float64, Float64,
                                         Float64, Int64),         "compare_drs"),
    ]

    println("WASM 컴파일 시작 ($(length(entries)) 함수)...")
    bytes = compile_multi(entries; optimize=true)
    write(OUT_WASM, bytes)
    kb = round(length(bytes) / 1024, digits=1)
    println("WASM 출력: $(OUT_WASM)  ($kb KB 최적화)")

    # 조작 항목 manifest (JSON) — 스키마는 호출 규약 문서 참조
    manifest = Dict(
        "step" => 1,
        "wasm_file" => "step1.wasm",
        "functions" => [
            Dict("name" => "dual_add",        "args" => ["Dual{Float64}", "Dual{Float64}"],
                 "ret" => "Dual{Float64}", "note" => "Dual 입력은 WASM 브릿지 필요"),
            Dict("name" => "dual_mul",        "args" => ["Dual{Float64}", "Dual{Float64}"],
                 "ret" => "Dual{Float64}", "note" => "Dual 입력은 WASM 브릿지 필요"),
            Dict("name" => "vec_new",         "args" => ["Int64"],  "ret" => "Vector{Float64}",
                 "note" => "JS에서 vec_set/vec_get/vec_len으로 조작"),
            Dict("name" => "vec_set",         "args" => ["Vector{Float64}", "Int64", "Float64"],
                 "ret" => "Int64", "note" => "1-based index (Julia 관습)"),
            Dict("name" => "vec_get",         "args" => ["Vector{Float64}", "Int64"],
                 "ret" => "Float64"),
            Dict("name" => "vec_len",         "args" => ["Vector{Float64}"],
                 "ret" => "Int64"),
            Dict("name" => "vec_sum",         "args" => ["Vector{Float64}"],
                 "ret" => "Float64"),
            Dict("name" => "f_poly",         "args" => ["Float64"], "ret" => "Float64",
                 "note" => "x³ + 2x² + x"),
            Dict("name" => "df_analytic",    "args" => ["Float64"], "ret" => "Float64",
                 "note" => "3x² + 4x + 1 (f_poly 해석적 미분)"),
            Dict("name" => "derivative_fd",  "args" => ["Float64", "Float64"], "ret" => "Float64",
                 "note" => "f_poly의 전진차분 (h 인자에 따른 오차 차수 1)"),
            Dict("name" => "derivative_dual","args" => ["Float64"], "ret" => "Float64",
                 "note" => "f_poly의 Dual 자동미분 (정확). JS 호출 시 Dual 입력 브릿지 필요"),
            Dict("name" => "top_speed",      "args" => ["Float64(P)", "Float64(ρ)", "Float64(Cd)",
                                                           "Float64(A)", "Float64(Froll)",
                                                           "Float64(tol)", "Int64(maxiter)"],
                 "ret" => "Float64",
                 "note" => "Newton법, 기본 인자 없음 (모든 인자 명시)"),
            Dict("name" => "compare_drs",    "args" => ["Float64(P)", "Float64(ρ)", "Float64(A)",
                                                           "Float64(Froll)", "Float64(Cd_closed)",
                                                           "Float64(Cd_open)",
                                                           "Float64(tol)", "Int64(maxiter)"],
                 "ret" => "Float64",
                 "note" => "DRS 개방 시 속력 증가량 dv = v_open − v_closed"),
        ],
        "manipulators" => [
            Dict("name" => "P",      "unit" => "W",      "default" => 500000.0,
                 "range" => [100000.0, 1000000.0], "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "ρ",      "unit" => "kg/m³", "default" => 1.225,
                 "range" => [1.0, 1.5],            "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "Cd",     "unit" => "—",     "default" => 0.30,
                 "range" => [0.10, 0.50],          "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "A",      "unit" => "m²",    "default" => 0.55,
                 "range" => [0.30, 1.0],           "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "Froll",  "unit" => "N",     "default" => 0.0,
                 "range" => [0.0, 500.0],          "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "tol",    "unit" => "—",     "default" => 1e-12,
                 "range" => [1e-15, 1e-8],         "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "maxiter","unit" => "—",     "default" => 50,
                 "range" => [10, 200],             "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "h",      "unit" => "—",     "default" => 1e-6,
                 "range" => [1e-15, 1e-3],         "used_by" => ["derivative_fd"]),
        ],
        "alternatives" => [
            Dict("location" => "derivative_fd vs derivative_dual",
                 "options" => [
                     Dict("id" => "fd",      "name" => "유한차분 (전진차분, 차수 1)",
                          "fn" => "derivative_fd", "param" => "h"),
                     Dict("id" => "dual",    "name" => "이중수 자동미분 (정확)",
                          "fn" => "derivative_dual", "param" => "없음"),
                 ]),
        ],
        "browser_requirements" => "WasmGC 지원 브라우저: Chrome 119+, Firefox 120+, Safari 18.2+",
        "known_limits" => [
            "Dual{Float64}는 WasmGC struct — JS에서 직접 생성·읽기 불가.
             Dual 입출력 함수(dual_add, dual_mul, derivative_dual)는 WASM 측 Dual 생성
             브릿지 함수 추가 시에만 JS에서 완전 호출 가능.",
            "derivative_dual은 WASM에서 컴파일되나, 현재 JS에서 Dual 입력 없이 호출 시
             WebAssembly.Exception 발생. JS 측에서는 derivative_fd 사용 권장.",
            "Vector 브릿지(vec_new/vec_set/vec_get)는 요소별 JS 호출 → 격자 크기별 비용 측정 필요.",
            "기본 인자(GlobalRef) 미지원: 모든 WASM 진입점은 기본 인자 없이 모든 인자 명시.",
        ]
    )

    # JSON 출력
    json_str = JSON.json(manifest, 2)  # 2-space indent
    write(OUT_MANIFEST, json_str)
    println("Manifest 출력: $(OUT_MANIFEST)")

    println("\n빌드 완료.")
end

build()
