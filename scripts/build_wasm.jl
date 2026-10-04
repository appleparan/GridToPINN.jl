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

# WASM 진입점 함수들 — src/step1_wasm.jl에 정의 (별도 Julia 파일)
include(joinpath(SRC, "step1_wasm.jl"))

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
                 "note" => "f_poly의 Dual 자동미분 (정확, 오차 0). 브라우저(WasmGC)에서 e.derivative_dual(1.0) → 8.0 정상 동작 확인. WASM 내부 Dual(x,1.0) 구성 → f_poly_wasm 적용 → .der 추출"),
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
             dual_add, dual_mul은 Dual 입력 필요 → JS에서 직접 호출 불가 (WASM 측 Dual 생성
             브릿지 함수 추가 시 호출 가능). derivative_dual은 JS에서 number 전달 시 정상 동작.",
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
