# step2_wasm.jl — Step2 WASM 진입점 래퍼
#
# 이 파일은 WASM 컴파일용 진입점(entry point)을 정의한다.
# 화면에 표시용 교재 코드가 아님 — 빌드 산출물에 포함만 됨.
#
# 설계 원칙 (Step1과 동일):
# - 기본 인자(GlobalRef) 회피: 모든 인자 명시적
# - Function 인자 회피: concrete 타입만 사용
# - 원본 Step2TimeIntegration 함수를 호출하거나, 로직을 직접 구현
#
# Step2의 재사용 요구: 적분기(euler_step, rk4_step)는 f에 대해 일반적이어야 함.
# 하지만 WASM에서는 Function 인자를 받을 수 없으므로, acceleration에 특화된
# concrete 버전(euler_step_acc_wasm, rk4_step_acc_wasm)을 노출한다.
# → JS에서 "f"를 전달할 필요 없이 P, ρ, A, v_top만 넘기면 됨.

using .Step2TimeIntegration

# ---------------------------------------------------------------------------
# acceleration_wasm — DRS 가속도 (WASM 노출용 concrete 함수)
#
# 원본 acceleration(v, P, ρ, A, v_top)는 T<:AbstractFloat에 대해 일반적.
# WASM에서는 Float64로 고정하여 노출.
# ---------------------------------------------------------------------------
function acceleration_wasm(
    v::Float64, P::Float64, ρ::Float64, A::Float64, v_top::Float64
)::Float64
    return Step2TimeIntegration.acceleration(v, P, ρ, A, v_top)
end

# ---------------------------------------------------------------------------
# Euler 적분기 (acceleration에 특화, WASM 노출용)
#
# 원본 euler_step(f, y, Δt)는 f를 Function으로 받음 → WASM 불가.
# → acceleration_wasm을 내부에 하드코딩한 concrete 버전.
# ---------------------------------------------------------------------------
function euler_step_wasm(
    y::Float64, Δt::Float64,
    P::Float64, ρ::Float64, A::Float64, v_top::Float64
)::Float64
    a = acceleration_wasm(y, P, ρ, A, v_top)
    return y + Δt * a
end

# ---------------------------------------------------------------------------
# RK4 적분기 (acceleration에 특화, WASM 노출용)
#
# 원본 rk4_step(f, y, Δt)는 f를 Function으로 받음 → WASM 불가.
# → acceleration_wasm을 내부에 하드코딩한 concrete 버전.
# ---------------------------------------------------------------------------
function rk4_step_wasm(
    y::Float64, Δt::Float64,
    P::Float64, ρ::Float64, A::Float64, v_top::Float64
)::Float64
    h2 = Δt / 2.0
    h6 = Δt / 6.0
    k1 = acceleration_wasm(y, P, ρ, A, v_top)
    k2 = acceleration_wasm(y + h2 * k1, P, ρ, A, v_top)
    k3 = acceleration_wasm(y + h2 * k2, P, ρ, A, v_top)
    k4 = acceleration_wasm(y + Δt * k3, P, ρ, A, v_top)
    return y + h6 * (k1 + 2.0 * k2 + 2.0 * k3 + k4)
end

# ---------------------------------------------------------------------------
# top_speed_target_wasm — DRS 최고속도 (WASM 노출용)
#
# 원본 top_speed_target은 newton() 호출 시 기본 인자(tol, maxiter)가
# GlobalRef로 남아 WASM 컴파일 실패.
# → Newton 반복을 직접 구현한 concrete 버전.
#
# 구름저항 0, DRS 열림. v_top = (2P/(ρ·Cd·A))^(1/3)
# ---------------------------------------------------------------------------
function top_speed_target_wasm(
    P::Float64, ρ::Float64, Cd::Float64, A::Float64,
    tol::Float64, maxiter::Int64
)::Float64
    # f(v) = (1/2)·ρ·Cd·A·v³ − P = 0
    # f′(v) = (3/2)·ρ·Cd·A·v²
    #           (수동 유도. T(1)/T(2) 대신 0.5, 1.5 사용 — WASM용 concrete)
    half_ρCdA = 0.5 * ρ * Cd * A
    three_half_ρCdA = 1.5 * ρ * Cd * A

    f  = v -> half_ρCdA * v * v * v - P
    df = v -> three_half_ρCdA * v * v

    # 초기 추측: v₀ = (2P/(ρ·Cd·A))^(1/3)
    x = (2.0 * P / (ρ * Cd * A))^(1.0 / 3.0)
    x = max(x, 1.0)

    for i in 1:maxiter
        fx  = f(x)
        dfx = df(x)
        if dfx == 0.0
            throw(ErrorException("top_speed_target_wasm: f′(v) = 0"))
        end
        xnew = x - fx / dfx
        if abs(xnew - x) < tol * (1.0 + abs(xnew))
            return xnew
        end
        x = xnew
    end

    throw(ErrorException("top_speed_target_wasm: 최대 반복 후 수렴하지 않음"))
end

# ---------------------------------------------------------------------------
# ode_integrate_wasm — DRS 가속도 ODE 적분 (WASM 노출용)
#
# 원본 ode_integrate(f, y0, t0, t_end, Δt; method)는 method 선택에 따라
# euler_step 또는 rk4_step을 호출. f가 Function 인자 → WASM 불가.
# → acceleration_wasm을 사용하는 concrete 버전.
#
# 반환: Vector{Float64} (평탄화) — [t0, y0, t1, y1, ..., tn, yn]
#   Vector{Tuple}은 JS에서 읽을 브릿지가 없으므로, vec_get/vec_len으로
#   읽을 수 있는 Vector{Float64}로 평탄화해 반환.
#   길이 = 2·(스텝 수 + 1). 짝수 인덱스(1-based)가 t, 홀수 인덱스가 y.
# ---------------------------------------------------------------------------
function ode_integrate_wasm(
    y0::Float64, t0::Float64, t_end::Float64, Δt::Float64,
    P::Float64, ρ::Float64, A::Float64, v_top::Float64,
    method::Int64  # 1=euler, 2=rk4
)::Vector{Float64}
    (method == 1 || method == 2) ||
        throw(ErrorException("ode_integrate_wasm: method는 1(euler) 또는 2(rk4)"))

    nsteps = clamp(Int64(floor((t_end - t0) / Δt + 0.5)), 1, 1_000_000)
    result = Vector{Float64}(undef, 2 * (nsteps + 1))

    t = t0
    y = y0
    result[1] = t
    result[2] = y

    for i in 1:nsteps
        if method == 1  # Euler
            y = euler_step_wasm(y, Δt, P, ρ, A, v_top)
        else  # RK4
            y = rk4_step_wasm(y, Δt, P, ρ, A, v_top)
        end
        t = t + Δt
        result[2i + 1] = t
        result[2i + 2] = y
    end

    return result
end

# ---------------------------------------------------------------------------
# Vector 브릿지 — WASM 노출용 (step1과 동일한 함수명 사용.
# step2_wasm.jl이 step1_wasm.jl 이후에 include되므로 동일 이름으로 재정의됨.
# → build_wasm.jl에서는 step1의 vec_*_wasm만 entries에 등록하면 됨)
# ---------------------------------------------------------------------------
# (step1_wasm.jl의 vec_new_wasm, vec_set_wasm, vec_get_wasm, vec_len_wasm,
#  vec_sum_wasm이 이미 정의되어 있음. 여기서는 재정의하지 않음)
