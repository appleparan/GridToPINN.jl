# build_wasm.jl — Step1 + Step2 WASM 컴파일 스크립트
#
# 용도: Julia 커널을 WasmTarget.jl로 WasmGC WASM에 컴파일,
#        산출물(.wasm)을 web/public/에 배치.
#
# 사용법 (Julia 1.12 필요):
#   julia +1.12 --project=. scripts/build_wasm.jl
#
# 출력:
#   web/public/step1.wasm        — 최적화된 WASM 모듈 (Step1 + Step2)
#   web/public/step1_manifest.json — 조작 항목·함수 목록
#
# 주의: 모든 entries 튜플은 단일 행으로 작성 (줄바꿈 포함 튜플 파싱 문제 회피)

using WasmTarget
using JSON

const ROOT = dirname(@__DIR__)
const SRC  = joinpath(ROOT, "src")
const WEB  = joinpath(ROOT, "web", "public")
const OUT_WASM = joinpath(WEB, "step1.wasm")
const OUT_MANIFEST = joinpath(WEB, "step1_manifest.json")

include(joinpath(SRC, "01-differentiation-newton.jl"))
using .Step1DiffNewton

include(joinpath(SRC, "02-time-integration.jl"))
using .Step2TimeIntegration

include(joinpath(SRC, "step1_wasm.jl"))
include(joinpath(SRC, "step2_wasm.jl"))

# ── WASM 컴파일 대상 함수 목록 ──
entries = [
    (dual_add_wasm,      (Dual{Float64}, Dual{Float64}),    "dual_add"),
    (dual_mul_wasm,      (Dual{Float64}, Dual{Float64}),    "dual_mul"),
    (vec_new_wasm,       (Int64,),                            "vec_new"),
    (vec_set_wasm,       (Vector{Float64}, Int64, Float64), "vec_set"),
    (vec_get_wasm,       (Vector{Float64}, Int64),          "vec_get"),
    (vec_len_wasm,       (Vector{Float64},),                "vec_len"),
    (vec_sum_wasm,       (Vector{Float64},),                "vec_sum"),
    (f_poly_wasm,        (Float64,),                         "f_poly"),
    (df_analytic_wasm,   (Float64,),                         "df_analytic"),
    (derivative_fd_wasm, (Float64, Float64),                "derivative_fd"),
    (derivative_dual_wasm, (Float64,),                       "derivative_dual"),
    (top_speed_wasm, (Float64, Float64, Float64, Float64, Float64, Float64, Int64), "top_speed"),
    (compare_drs_wasm, (Float64, Float64, Float64, Float64, Float64, Float64, Float64, Int64), "compare_drs"),
    (acceleration_wasm, (Float64, Float64, Float64, Float64, Float64), "acceleration"),
    (euler_step_wasm, (Float64, Float64, Float64, Float64, Float64, Float64), "euler_step"),
    (rk4_step_wasm, (Float64, Float64, Float64, Float64, Float64, Float64), "rk4_step"),
    (top_speed_target_wasm, (Float64, Float64, Float64, Float64, Float64, Int64), "top_speed_target"),
    (ode_integrate_wasm, (Float64, Float64, Float64, Float64, Float64, Float64, Float64, Float64, Int64), "ode_integrate"),
]

# ── manifest 생성 ──
function make_manifest()
    Dict{String, Any}(
        "step" => 2,
        "wasm_file" => "step1.wasm",
        "note" => "Step1 + Step2 통합 WASM. 함수명으로 export된 함수를 호출.",
        "functions" => Vector{Any}([
            Dict("name" => "dual_add", "args" => ["Dual", "Dual"], "ret" => "Dual",
                 "note" => "Dual 입력은 WASM 브릿지 필요"),
            Dict("name" => "dual_mul", "args" => ["Dual", "Dual"], "ret" => "Dual",
                 "note" => "Dual 입력은 WASM 브릿지 필요"),
            Dict("name" => "vec_new", "args" => ["Int64"], "ret" => "Vector{Float64}",
                 "note" => "JS에서 vec_set/vec_get/vec_len으로 조작"),
            Dict("name" => "vec_set", "args" => ["Vector", "Int64", "Float64"], "ret" => "Int64",
                 "note" => "1-based index (Julia 관습)"),
            Dict("name" => "vec_get", "args" => ["Vector", "Int64"], "ret" => "Float64"),
            Dict("name" => "vec_len", "args" => ["Vector"], "ret" => "Int64"),
            Dict("name" => "vec_sum", "args" => ["Vector"], "ret" => "Float64"),
            Dict("name" => "f_poly", "args" => ["Float64"], "ret" => "Float64",
                 "note" => "x^3 + 2x^2 + x"),
            Dict("name" => "df_analytic", "args" => ["Float64"], "ret" => "Float64",
                 "note" => "3x^2 + 4x + 1 (f_poly 해석적 미분)"),
            Dict("name" => "derivative_fd", "args" => ["Float64", "Float64"], "ret" => "Float64",
                 "note" => "f_poly 전진차분 (h에 따른 오차 차수 1)"),
            Dict("name" => "derivative_dual", "args" => ["Float64"], "ret" => "Float64",
                 "note" => "f_poly Dual 자동미분. 브라우저에서 정상 동작 확인됨"),
            Dict("name" => "top_speed",
                 "args" => ["Float64 P", "Float64 rho", "Float64 Cd", "Float64 A",
                            "Float64 Froll", "Float64 tol", "Int64 maxiter"],
                 "ret" => "Float64", "note" => "Newton법 (구름저항 포함)"),
            Dict("name" => "compare_drs",
                 "args" => ["Float64 P", "Float64 rho", "Float64 A", "Float64 Froll",
                            "Float64 Cd_closed", "Float64 Cd_open", "Float64 tol",
                            "Int64 maxiter"],
                 "ret" => "Float64", "note" => "dv = v_open - v_closed"),
            Dict("name" => "acceleration",
                 "args" => ["Float64 v", "Float64 P", "Float64 rho", "Float64 A",
                            "Float64 v_top"],
                 "ret" => "Float64",
                 "note" => "a(v) = (P/(rho*A))*(1-(v/v_top)^3)"),
            Dict("name" => "euler_step",
                 "args" => ["Float64 y", "Float64 dt", "Float64 P", "Float64 rho",
                            "Float64 A", "Float64 v_top"],
                 "ret" => "Float64",
                 "note" => "Euler 1스텝: y + dt*a(y)"),
            Dict("name" => "rk4_step",
                 "args" => ["Float64 y", "Float64 dt", "Float64 P", "Float64 rho",
                            "Float64 A", "Float64 v_top"],
                 "ret" => "Float64",
                 "note" => "RK4 1스텝"),
            Dict("name" => "top_speed_target",
                 "args" => ["Float64 P", "Float64 rho", "Float64 Cd", "Float64 A",
                            "Float64 tol", "Int64 maxiter"],
                 "ret" => "Float64", "note" => "v_top = (2P/(rho*Cd*A))^(1/3)"),
            Dict("name" => "ode_integrate",
                 "args" => ["Float64 y0", "Float64 t0", "Float64 t_end", "Float64 dt",
                            "Float64 P", "Float64 rho", "Float64 A", "Float64 v_top",
                            "Int64 method"],
                 "ret" => "Vector{Float64}",
                 "note" => "t0부터 t_end까지 적분. method: 1=euler, 2=rk4. 반환: [t0,y0,t1,y1,...] 평탄화, 길이 2*(스텝수+1). vec_len/vec_get으로 읽음"),
        ]),
        "manipulators" => Vector{Any}([
            Dict("name" => "P", "unit" => "W", "default" => 50.0, "range" => [1.0, 1000.0],
                 "used_by" => ["top_speed", "compare_drs", "acceleration", "top_speed_target"]),
            Dict("name" => "rho", "unit" => "kg/m^3", "default" => 1.225, "range" => [0.5, 2.0],
                 "used_by" => ["top_speed", "compare_drs", "acceleration", "top_speed_target"]),
            Dict("name" => "Cd", "unit" => "-", "default" => 0.20, "range" => [0.05, 1.5],
                 "used_by" => ["top_speed", "compare_drs", "top_speed_target"]),
            Dict("name" => "A", "unit" => "m^2", "default" => 0.55, "range" => [0.1, 2.0],
                 "used_by" => ["top_speed", "compare_drs", "acceleration", "top_speed_target"]),
            Dict("name" => "Froll", "unit" => "N", "default" => 0.0, "range" => [0.0, 500.0],
                 "used_by" => ["top_speed", "compare_drs"]),
            Dict("name" => "tol", "unit" => "-", "default" => 1e-12, "range" => [1e-15, 1e-6],
                 "used_by" => ["top_speed", "compare_drs", "top_speed_target"]),
            Dict("name" => "maxiter", "unit" => "-", "default" => 50, "range" => [10, 200],
                 "used_by" => ["top_speed", "compare_drs", "top_speed_target"]),
            Dict("name" => "h", "unit" => "-", "default" => 0.001, "range" => [1e-12, 0.1],
                 "used_by" => ["derivative_fd"]),
            Dict("name" => "dt", "unit" => "s", "default" => 0.1, "range" => [0.001, 1.0],
                 "used_by" => ["euler_step", "rk4_step", "ode_integrate"]),
            Dict("name" => "t_end", "unit" => "s", "default" => 0.5, "range" => [0.001, 10.0],
                 "used_by" => ["ode_integrate"]),
            Dict("name" => "y0", "unit" => "m/s", "default" => 0.0, "range" => [0.0, 50.0],
                 "used_by" => ["euler_step", "rk4_step", "ode_integrate"]),
            Dict("name" => "t0", "unit" => "s", "default" => 0.0, "range" => [0.0, 10.0],
                 "used_by" => ["ode_integrate"]),
            Dict("name" => "method", "unit" => "-", "default" => 2, "range" => [1, 2],
                 "used_by" => ["ode_integrate"],
                 "options" => Vector{Any}([
                     Dict("id" => 1, "name" => "Euler (1차)"),
                     Dict("id" => 2, "name" => "RK4 (4차)"),
                 ])),
        ]),
        "alternatives" => Vector{Any}([
            Dict("location" => "미분 방법 (f_poly)",
                 "options" => Vector{Any}([
                     Dict("id" => "fd", "name" => "유한차분 (전진차분, 차수 1)",
                          "fn" => "derivative_fd", "param" => "h"),
                     Dict("id" => "dual", "name" => "이중수 자동미분 (정확)",
                          "fn" => "derivative_dual", "param" => "없음"),
                 ])),
            Dict("location" => "적분기 (ODE 적분)",
                 "options" => Vector{Any}([
                     Dict("id" => "euler", "name" => "Euler (1차, 오차 큼)",
                          "fn" => "euler_step", "param" => "dt"),
                     Dict("id" => "rk4", "name" => "RK4 (4차, 정확)",
                          "fn" => "rk4_step", "param" => "dt"),
                 ])),
        ]),
        "browser_requirements" => "WasmGC 지원 브라우저: Chrome 119+, Firefox 120+, Safari 18.2+",
        "known_limits" => Vector{Any}([
            "Dual{Float64}는 WasmGC struct - JS에서 직접 생성/읽기 불가",
            "Vector 브릿지(vec_new/vec_set/vec_get)는 요소별 JS 호출 - 비용 측정 필요",
            "기본 인자(GlobalRef) 미지원: 모든 WASM 진입점은 기본 인자 없이 모든 인자 명시",
            "Step2 적분기는 acceleration에 특화 - 일반 f 함수는 JS에서 전달 불가",
            "ode_integrate 반환값 Vector{Tuple} - JS에서 vec_len/vec_get으로 요소 접근",
        ]),
    )
end

# ── 빌드 실행 ──
function build()
    mkpath(WEB)

    println("WASM 컴파일 시작 ($(length(entries)) 함수)...")
    bytes = compile_multi(entries; optimize = true)
    write(OUT_WASM, bytes)
    kb = round(length(bytes) / 1024, digits = 1)
    println("WASM 출력: $(OUT_WASM)  ($kb KB 최적화)")

    json_str = JSON.json(make_manifest(), 2)
    write(OUT_MANIFEST, json_str)
    println("Manifest 출력: $(OUT_MANIFEST)")
    println("\n빌드 완료.")
end

build()
