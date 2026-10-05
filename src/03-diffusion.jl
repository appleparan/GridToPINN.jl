# 03-diffusion.jl — 확산 (3단계)
#
# 핵심 질문: 벽이 움직이면 물과 꿀 중 어느 쪽이 더 깊이 끌려오나?
#
# 풀려는 식: ∂u/∂t = α·∂²u/∂y²   (1차원 확산)
#   α = ν (동점성 계수). 물 ≈ 1e-6 m²/s (20°C),
#   꿀 ≈ 2e-3 m²/s (대표값 — 온도에 따라 수십 배까지 변한다)
#
# 방법 ("선의 방법"): 공간만 2차 중심차분으로 이산화한다.
#   격자점마다 ODE가 하나씩 생긴다:  du_i/dt = α·(u_{i-1} − 2u_i + u_{i+1}) / Δy²
#   이 ODE 묶음을 2단계에서 만든 적분기(euler_step, rk4_step)에 그대로 넘긴다.
#   시간 적분기는 새로 짜지 않는다 — 2단계 코드를 재사용한다.
#
# 정답:
#   본 문제 (움직이는 벽, Stokes 1종): 벽을 t=0에 순간적으로 속도 U로 움직임.
#       u(y,t) = U·erfc( y / (2√(ν·t)) )
#       erfc는 Base에 없으므로 직접 구현한다 (Abramowitz–Stegun 7.1.26).
#       확산 깊이 δ = 2√(ν·t): 꿀이 물보다 √(ν_꿀/ν_물)배 더 깊이 끌려온다.
#       t=0에서 벽면이 불연속 → 수렴 차수 확인에는 부적합.
#   검증 문제 (매끄러움): u(y,0) = sin(πy), u(0)=u(1)=0
#       u(y,t) = sin(πy)·e^{−α·π²·t}
#       sin(πy)는 이산 라플라시안의 고유벡터이기도 해서 오차 해석이 깔끔하다.
#       공간 오차 O(Δy²). 시간 오차는 적분기 차수를 따르지만, 확산은 stiff해서
#       RK4의 4차는 안정 한계(Δt ≤ 0.696·Δy²/α)에 가려진다 —
#       이것이 7단계 이후 음해법이 필요한 이유다.
#
# 깨뜨리기: 명시적 방법의 안정 한계 Δt ≤ Δy²/(2α) (Euler), 0.696·Δy²/α (RK4).
#   점성이 클수록(꿀) 한계 Δt가 1/α로 작아진다 — 같은 격자에서 꿀은
#   물보다 2000배 촘촘한 시간 간격이 필요하다.
#
# 재사용 (재사용 표):
#   - 2단계 euler_step / rk4_step (Vector 지원) → 시간 전진 전부
#   - 확산 연산자 diffusion_rhs_* → 4단계 Burgers 점성항,
#     5단계 Jacobi의 출발점, 7단계 점성항
#   - 움직이는 벽의 해석해 stokes_first_solution → 7단계 Cavity 초기
#     뚜껑 아래 속도 분포와 비교
#
# 주의: Float64 리터럴(0.5 등) 금지 — x/2, T(0.5) 사용 (Float32 승격 방지)

module Step3Diffusion

using ..Step2TimeIntegration

export diffusion_rhs_dirichlet, diffusion_rhs_periodic,
       erfc_approx, stokes_first_solution, diffusion_depth,
       sin_mode_initial, sin_mode_exact,
       diffuse

# ---------------------------------------------------------------------------
# 확산 연산자 (선의 방법 우변) — 4, 5, 7단계에서 재사용
# ---------------------------------------------------------------------------

"""
    diffusion_rhs_dirichlet(u::AbstractVector{T}, α::T, dx::T) where {T<:AbstractFloat}

확산 우변: du/dt = α·∂²u/∂y², 공간만 2차 중심차분.
양 끝은 고정 (Dirichlet): 끝점의 du/dt = 0 → 초기조건의 경계값이 유지된다.
"""
function diffusion_rhs_dirichlet(u::AbstractVector{T}, α::T, dx::T) where {T<:AbstractFloat}
    n = length(u)
    du = similar(u)
    inv_dx2 = one(T) / (dx * dx)
    du[1] = zero(T)
    du[n] = zero(T)
    @inbounds for i in 2:(n - 1)
        du[i] = α * (u[i - 1] - T(2) * u[i] + u[i + 1]) * inv_dx2
    end
    return du
end

"""
    diffusion_rhs_periodic(u::AbstractVector{T}, α::T, dx::T) where {T<:AbstractFloat}

주기 경계 버전 (5단계 Taylor–Green에서 재사용).
"""
function diffusion_rhs_periodic(u::AbstractVector{T}, α::T, dx::T) where {T<:AbstractFloat}
    n = length(u)
    du = similar(u)
    inv_dx2 = one(T) / (dx * dx)
    @inbounds for i in 1:n
        im = i == 1 ? n : i - 1
        ip = i == n ? 1 : i + 1
        du[i] = α * (u[im] - T(2) * u[i] + u[ip]) * inv_dx2
    end
    return du
end

# ---------------------------------------------------------------------------
# 정답: erfc 직접 구현과 움직이는 벽의 해석해
# ---------------------------------------------------------------------------

"""
    erfc_approx(x::T) where {T<:AbstractFloat}

상오차함수 erfc(x) = 1 − erf(x). Base에 없어서 직접 구현.
Abramowitz & Stegun 7.1.26 근사 — |오차| ≤ 1.5e-7 (Float64).
Float32에서는 계수 반올림 때문에 오차가 ~1e-6까지 커질 수 있다.
"""
function erfc_approx(x::T) where {T<:AbstractFloat}
    z = abs(x)
    t = one(T) / (one(T) + T(0.3275911) * z)
    p = T(1.061405429)
    p = t * p + T(-1.453152027)
    p = t * p + T(1.421413741)
    p = t * p + T(-0.284496736)
    p = t * p + T(0.254829592)
    p = t * p
    e = p * exp(-z * z)
    return x >= zero(T) ? e : T(2) - e
end

"""
    stokes_first_solution(y::T, t::T, U::T, ν::T) where {T<:AbstractFloat}

움직이는 벽(Stokes 1종 문제)의 해석해: u(y,t) = U·erfc(y/(2√(ν·t))).
t=0에 벽을 순간적으로 속도 U로 움직였을 때의 유동. (7단계 재사용)
"""
function stokes_first_solution(y::T, t::T, U::T, ν::T) where {T<:AbstractFloat}
    t > zero(T) || throw(ArgumentError("t > 0 이어야 한다 (t=0에서 해는 불연속)"))
    return U * erfc_approx(y / (T(2) * sqrt(ν * t)))
end

"""
    diffusion_depth(ν::T, t::T) where {T<:AbstractFloat}

확산 깊이 척도 δ = 2√(ν·t). 이 시간까지 점성이 끌어온 층 두께로,
그 깊이에서 벽 속도의 erfc(1) ≈ 16%가 남는다.
물과 꿀의 비교: δ_꿀/δ_물 = √(ν_꿀/ν_물).
"""
function diffusion_depth(ν::T, t::T) where {T<:AbstractFloat}
    return T(2) * sqrt(ν * t)
end

# ---------------------------------------------------------------------------
# 정답: 검증용 매끄러운 문제 (sin 모드)
# ---------------------------------------------------------------------------

"""
    sin_mode_initial(y::T) where {T<:AbstractFloat}
    sin_mode_exact(y::T, t::T, α::T) where {T<:AbstractFloat}

검증용 문제: u(y,0) = sin(πy), u(0)=u(1)=0 → u(y,t) = sin(πy)·e^{−α·π²·t}.
t=0에서 매끄러우므로 수렴 차수 확인에 적합하다 (본 문제와 대비).
"""
sin_mode_initial(y::T) where {T<:AbstractFloat} = sin(T(π) * y)
function sin_mode_exact(y::T, t::T, α::T) where {T<:AbstractFloat}
    return sin(T(π) * y) * exp(-α * T(π)^2 * t)
end

# ---------------------------------------------------------------------------
# 시간 전진 — 2단계 적분기 재사용 (새 적분기 없음)
# ---------------------------------------------------------------------------

"""
    diffuse(u0::AbstractVector{T}, Δt::T, α::T, dx::T, nsteps::Int; method) -> Vector{T}

확산 ODE 묶음을 2단계 적분기로 nsteps 전진한다.
method: :euler 또는 :rk4 (2단계의 대안 지점을 그대로 쓴다).
경계값은 우변이 0이라 고정된다 (Dirichlet).
"""
function diffuse(u0::AbstractVector{T}, Δt::T, α::T, dx::T, nsteps::Int;
                 method::Symbol = :rk4) where {T<:AbstractFloat}
    stepfun = method === :euler ? Step2TimeIntegration.euler_step :
              method === :rk4 ? Step2TimeIntegration.rk4_step :
              throw(ArgumentError("method는 :euler 또는 :rk4"))
    f = v -> diffusion_rhs_dirichlet(v, α, dx)
    u = copy(u0)
    for _ in 1:nsteps
        u = stepfun(f, u, Δt)
    end
    return u
end

end # module Step3Diffusion
