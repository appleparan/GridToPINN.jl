# 02-time-integration.jl — 시간 전진 (2단계)
#
# 핵심 질문: DRS 개방 후 최고속도에 도달하는 데 얼마나 걸리나?
#
# 풀려는 식: dv/dt = (P/ρ·A) · (1 − (v/v_top)³)
#             (구름저항 0, DRS 열림, v → v_top 일 때 a → 0)
#
# 설계:
# - 모든 커널은 T<:AbstractFloat에 대해 일반적
# - Float64 리터럴(0.5 등) 금지 → x/2 또는 T(0.5) 사용
# - 적분기: Euler, RK4, 적응형 RK(Dormand-Prince 5(4)) 세 가지
# - 적분기는 스칼라·1차원 배열(Vector)·2차원 장(Matrix)을 모두 받음 (재사용 요구)
# - 적응형 RK: Dormand-Prince 5(4) (7개 스테이지, 임베디드 오차 추정, 스텝 자동 조절)
#
# 재사용:
# - 1단계 top_speed를 수렴 목표(정상상태)로 사용
# - Runge–Kutta 적분기는 3, 4, 7단계에서 재사용

module Step2TimeIntegration

export euler_step, rk4_step,
       ode_integrate, ode_integrate_field,
       make_adaptive_rk,
       acceleration, acceleration_field,
       top_speed_target, newton

# ---------------------------------------------------------------------------
# 물리 모델 — DRS 개방 후 가속
# ---------------------------------------------------------------------------

"""
    acceleration(v::T, P::T, ρ::T, A::T, v_top::T) where {T<:AbstractFloat}

DRS 개방 후 가속도: a(v) = (P / (ρ·A)) · (1 − (v / v_top)³)
구름저항 0, DRS 열림. v → v_top 일 때 a → 0 (정상상태).
"""
function acceleration(v::T, P::T, ρ::T, A::T, v_top::T) where {T<:AbstractFloat}
    factor = P / (ρ * A)
    r = v / v_top
    r3 = r * r * r  # r³ (T(3) 사용하지 않음)
    return factor * (one(T) - r3)
end

"""
    acceleration_field(u::Matrix{T}, P::T, ρ::T, A::T, v_top::T) where {T<:AbstractFloat}

2차원 속도장의 각 셀에 가속도를 적용 (단순 모형: 각 셀 독립).
"""
function acceleration_field(u::Matrix{T}, P::T, ρ::T, A::T, v_top::T) where {T<:AbstractFloat}
    out = similar(u)
    for i in eachindex(out)
        out[i] = acceleration(u[i], P, ρ, A, v_top)
    end
    return out
end

# ---------------------------------------------------------------------------
# Newton법 (1단계 재사용, 단순 버전)
# ---------------------------------------------------------------------------

"""
    newton(f, df, x0; tol, maxiter)

1단계 Newton법을 재사용. f(x)=0의 근을 찾는다.
"""
function newton(f, df, x0::T; tol::T = T(1) / T(1e12), maxiter::Int = 50) where {T<:AbstractFloat}
    x = x0
    for i in 1:maxiter
        fx = f(x)
        dfx = df(x)
        if dfx == zero(T)
            throw(ErrorException("Newton: f′ = 0"))
        end
        xnew = x - fx / dfx
        if abs(xnew - x) < tol * (one(T) + abs(xnew))
            return xnew
        end
        x = xnew
    end
    throw(ErrorException("Newton: $maxiter회 반복 후 수렴하지 않음"))
end

"""
    top_speed_target(P::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat}

DRS 개방 후의 최고속도(목표값). 구름저항 0, 주어진 Cd_open.
f(v) = ½ρ·Cd·A·v³ − P = 0  →  v = (2P/(ρCdA))^(1/3)
"""
function top_speed_target(P::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat}
    Froll = zero(T)
    f  = v -> (T(1) / T(2)) * ρ * Cd * A * v^3 - P
    df = v -> (T(3) / T(2)) * ρ * Cd * A * v^2
    v0 = (T(2) * P / (ρ * Cd * A))^(T(1) / T(3))
    v0 = max(v0, T(1))
    return newton(f, df, v0; tol = T(1) / T(1e12), maxiter = 50)
end

# ---------------------------------------------------------------------------
# Euler 적분기
# ---------------------------------------------------------------------------

"""
    euler_step(f, y, Δt)

Euler method: y_{n+1} = y_n + Δt · f(y_n)
스칼라, Vector, Matrix 모두 지원.
"""
function euler_step(f, y::T, Δt::T) where {T<:AbstractFloat}
    return y + Δt * f(y)
end

function euler_step(f, y::AbstractVector{T}, Δt::T) where {T<:AbstractFloat}
    return y .+ Δt .* f(y)
end

function euler_step(f, y::AbstractMatrix{T}, Δt::T) where {T<:AbstractFloat}
    return y .+ Δt .* f(y)
end

# ---------------------------------------------------------------------------
# RK4 적분기
# ---------------------------------------------------------------------------

"""
    rk4_step(f, y, Δt)

Classical 4th-order Runge–Kutta (RK4):
  k₁ = f(y)
  k₂ = f(y + (Δt/2)·k₁)
  k₃ = f(y + (Δt/2)·k₂)
  k₄ = f(y + Δt·k₃)
  y_{n+1} = y + (Δt/6)·(k₁ + 2k₂ + 2k₃ + k₄)

스칼라, Vector, Matrix 모두 지원. Δt/2 = Δt / T(2), Δt/6 = Δt / T(6).
"""
function rk4_step(f, y::T, Δt::T) where {T<:AbstractFloat}
    h2 = Δt / T(2)
    h6 = Δt / T(6)
    k1 = f(y)
    k2 = f(y + h2 * k1)
    k3 = f(y + h2 * k2)
    k4 = f(y + Δt * k3)
    return y + h6 * (k1 + T(2) * k2 + T(2) * k3 + k4)
end

function rk4_step(f, y::AbstractVector{T}, Δt::T) where {T<:AbstractFloat}
    h2 = Δt / T(2)
    h6 = Δt / T(6)
    k1 = f(y)
    k2 = f(y + h2 .* k1)
    k3 = f(y + h2 .* k2)
    k4 = f(y + Δt .* k3)
    return y .+ h6 .* (k1 .+ T(2) .* k2 .+ T(2) .* k3 .+ k4)
end

function rk4_step(f, y::AbstractMatrix{T}, Δt::T) where {T<:AbstractFloat}
    h2 = Δt / T(2)
    h6 = Δt / T(6)
    k1 = f(y)
    k2 = f(y + h2 .* k1)
    k3 = f(y + h2 .* k2)
    k4 = f(y + Δt .* k3)
    return y .+ h6 .* (k1 .+ T(2) .* k2 .+ T(2) .* k3 .+ k4)
end

const rk4_step_field = rk4_step

# ---------------------------------------------------------------------------
# Dormand-Prince 5(4) 적응형 Runge–Kutta
# ---------------------------------------------------------------------------

# Dormand-Prince 5(4) Butcher tableau 계수 (Float64 상수)
# 7개 스테이지, 6개 열 (a_ij, j<i) + 1개 열 (b_i)
const DP54_A = Float64[
     0.0        0.0         0.0         0.0         0.0         0.0;
     1.0/5.0    0.0         0.0         0.0         0.0         0.0;
     3.0/40.0   9.0/40.0    0.0         0.0         0.0         0.0;
    44.0/45.0  -56.0/15.0   32.0/9.0    0.0         0.0         0.0;
   19372.0/6561.0 -25360.0/2187.0 64448.0/6561.0 -212.0/729.0  0.0         0.0;
     9017.0/3168.0 -355.0/33.0  46732.0/5247.0  49.0/176.0  -5103.0/18656.0  0.0;
     35.0/384.0   0.0        500.0/1113.0  125.0/192.0 -275.0/512.0   512.0/1575.0
]

const DP54_B  = [35.0/384.0, 0.0, 500.0/1113.0, 125.0/192.0, -275.0/512.0, 512.0/1575.0, 0.0]     # 5차 해 계수
const DP54_B2 = [5179.0/57600.0, 0.0, 7571.0/16695.0, 393.0/640.0, -92097.0/339200.0, 187.0/2100.0, 1.0/40.0]  # 4차 해 계수
const DP54_C  = [0.0, 1.0/5.0, 3.0/10.0, 4.0/5.0, 8.0/9.0, 1.0]  # 스테이지 시간 위치 (t + c_i·Δt)

"""
    make_adaptive_rk(f, x0, Δt0; tol, maxstep, minstep)

Dormand-Prince 5(4) 적응형 적분기를 생성.
f: f(y, t) → dy/dt  (스칼라 함수)
반환: (history, final_t, final_y, naccept, nreject)
  history: [(t, y, Δt, err), ...]  (각 스텝 수용 시점의 기록)
"""
function make_adaptive_rk(
    f,
    x0::T,
    Δt0::T;
    tol::T = T(1) / T(1e12),
    maxstep::Int = 10_000,
    minstep::T = T(1) / T(1e15)
) where {T<:AbstractFloat}
    history = Vector{Tuple{T, T, T, T}}()
    sizehint!(history, maxstep)
    t = zero(T)
    y = x0
    Δt = Δt0
    naccept = 0
    nreject = 0

    for step in 1:maxstep
        # 7개 스테이지 (Dormand-Prince)
        # k1
        k1 = f(y, t)
        # k2 = f(y + Δt·a21·k1, t + Δt·c2)
        k2 = f(y + Δt * DP54_A[2, 1] * k1, t + Δt * DP54_C[2])
        # k3
        k3 = f(y + Δt * (DP54_A[3, 1] * k1 + DP54_A[3, 2] * k2), t + Δt * DP54_C[3])
        # k4
        k4 = f(y + Δt * (DP54_A[4, 1] * k1 + DP54_A[4, 2] * k2 + DP54_A[4, 3] * k3), t + Δt * DP54_C[4])
        # k5
        k5 = f(y + Δt * (DP54_A[5, 1] * k1 + DP54_A[5, 2] * k2 + DP54_A[5, 3] * k3 + DP54_A[5, 4] * k4), t + Δt * DP54_C[5])
        # k6
        k6 = f(y + Δt * (DP54_A[6, 1] * k1 + DP54_A[6, 2] * k2 + DP54_A[6, 3] * k3 + DP54_A[6, 4] * k4 + DP54_A[6, 5] * k5), t + Δt * DP54_C[6])
        # k7
        k7 = f(y + Δt * (DP54_A[7, 1] * k1 + DP54_A[7, 2] * k2 + DP54_A[7, 3] * k3 + DP54_A[7, 4] * k4 + DP54_A[7, 5] * k5 + DP54_A[7, 6] * k6), t + Δt * (T(1)))

        # 5차 추정값 (y_{n+1})
        y5 = y + Δt * (DP54_B[1] * k1 + DP54_B[2] * k2 + DP54_B[3] * k3 + DP54_B[4] * k4 + DP54_B[5] * k5 + DP54_B[6] * k6 + DP54_B[7] * k7)

        # 4차 추정값 (y*_{n+1})
        y4 = y + Δt * (DP54_B2[1] * k1 + DP54_B2[2] * k2 + DP54_B2[3] * k3 + DP54_B2[4] * k4 + DP54_B2[5] * k5 + DP54_B2[6] * k6 + DP54_B2[7] * k7)

        # 오차 = |5차 - 4차|
        err = abs(y5 - y4)

        # 오차 허용 판정: err ≤ tol · (|y5| + 1)
        if err < tol * (abs(y5) + one(T))
            # 스텝 수용
            t = t + Δt
            y = y5
            naccept += 1
            push!(history, (t, y, Δt, err))
            if step == maxstep
                break
            end
            # 다음 스텝 크기 조절 (PI 제어, 오차 기준으로)
            #Δt_new = Δt · min(5, max(0.2, 0.9 · (tol/err)^{1/5}))
            ratio = tol / max(err, T(1) / T(1e300))
            factor = T(0.9) * ratio^(T(1) / T(5))
            factor = min(T(5), max(T(1) / T(5), factor))
            Δt = Δt * factor
            Δt = max(minstep, min(Δt, T(1000)))  # 상한 제한
        else
            # 스텝 기각 → Δt 축소
            nreject += 1
            ratio = tol / max(err, T(1) / T(1e300))
            factor = T(0.9) * ratio^(T(1) / T(5))
            factor = max(T(1) / T(5), factor)
            Δt = Δt * factor
            Δt = max(minstep, Δt)
            if Δt < minstep
                throw(ErrorException("적응형 RK: 시간 간격이 너무 작아짐 (Δt = $Δt)"))
            end
        end
    end

    return (history = history, final_t = t, final_y = y, naccept = naccept, nreject = nreject)
end

"""
    ode_integrate(f, y0, t0, t_end, Δt; method)

t0 → t_end 까지 적분. method: :euler, :rk4, :adaptive
반환: [(t, y), ...] 리스트
"""
function ode_integrate(f, y0::T, t0::T, t_end::T, Δt::T;
                       method::Symbol = :rk4) where {T<:AbstractFloat}
    if method == :euler
        return _integrate_fixed(f, y0, t0, t_end, Δt, :euler)
    elseif method == :rk4
        return _integrate_fixed(f, y0, t0, t_end, Δt, :rk4)
    elseif method == :adaptive
        res = make_adaptive_rk(f, y0, Δt; tol = T(1) / T(1e12), maxstep = 10_000)
        return collect((t, y) for (t, y, _, _) in res.history)
    else
        throw(ArgumentError("Unknown method: $method"))
    end
end

function _integrate_fixed(f, y0::T, t0::T, t_end::T, Δt::T, method::Symbol) where {T<:AbstractFloat}
    nsteps = max(1, ceil(Int, (t_end - t0) / Δt))
    ts = Vector{T}(undef, nsteps + 1)
    ys = Vector{T}(undef, nsteps + 1)
    ts[1] = t0
    ys[1] = y0
    y = y0
    t = t0
    for i in 1:nsteps
        y = if method == :euler
            euler_step(f, y, Δt)
        elseif method == :rk4
            rk4_step(f, y, Δt)
        end
        t = t0 + i * Δt
        ts[i + 1] = t
        ys[i + 1] = y
    end
    return collect(zip(ts, ys))
end

"""
    ode_integrate_field(f, u0, t0, t_end, Δt; method)

2차원 장(Matrix)에 대한 고정 간격 적분.
"""
function ode_integrate_field(f, u0::Matrix{T}, t0::T, t_end::T, Δt::T;
                             method::Symbol = :rk4) where {T<:AbstractFloat}
    nsteps = max(1, ceil(Int, (t_end - t0) / Δt))
    history = Vector{Tuple{T, Matrix{T}}}(undef, nsteps + 1)
    history[1] = (t0, copy(u0))
    u = copy(u0)
    t = t0
    for i in 1:nsteps
        u = if method == :euler
            euler_step(f, u, Δt)
        elseif method == :rk4
            rk4_step(f, u, Δt)
        end
        t = t + Δt
        history[i + 1] = (t, copy(u))
    end
    return history
end

end # module Step2TimeIntegration
