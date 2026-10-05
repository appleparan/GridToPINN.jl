# step3/simulation.jl — 상태를 가진 확산 시뮬레이션
#
# 화면은 "만들기 → n걸음 전진 → 현재 장 꺼내기 → 오차 꺼내기"로 쓴다.
# 시간 적분기는 한 줄짜리 대안 셋이다. 모두 같은 서명 step(u, t, Δt, α, dx) -> u_new를 가지며,
# 앞의 둘은 2단계 적분기를 그대로 부르고 셋째는 implicit.jl의 음해법이다.

"""
    Diffusion1D{T}

1차원 확산 상태. `u` 장, `α` 확산계수, `dx` 격자 간격, `t` 현재 시각.
"""
mutable struct Diffusion1D{T<:AbstractFloat}
    u::Vector{T}
    α::T
    dx::T
    t::T
end

"""
    moving_wall(N, L, U, ν)

본 문제. [0, L]을 N칸(N+1점)으로 나누고 벽(`u[1]`)만 속도 `U`, 나머지는 0이다. `α = ν`.
"""
function moving_wall(N::Int, L::T, U::T, ν::T) where {T<:AbstractFloat}
    u = zeros(T, N + 1)
    u[1] = U
    return Diffusion1D(u, ν, L / N, zero(T))
end

"""
    sin_mode(N, α)

검증 문제. [0, 1]을 N칸으로 나누고 `sin(πy)`로 시작한다.
"""
function sin_mode(N::Int, α::T) where {T<:AbstractFloat}
    dx = one(T) / N
    u = [sin_mode_initial((i - 1) * dx) for i in 1:(N + 1)]
    return Diffusion1D(u, α, dx, zero(T))
end

"""
    diffusion_euler_step(u, t, Δt, α, dx)

대안 1: 2단계 `euler_step`을 확산 우변에 적용.
"""
diffusion_euler_step(u, t, Δt, α, dx) =
    euler_step((v, s) -> diffusion_rhs_dirichlet(v, α, dx), u, t, Δt)

"""
    diffusion_rk4_step(u, t, Δt, α, dx)

대안 2: 2단계 `rk4_step`을 확산 우변에 적용.
"""
diffusion_rk4_step(u, t, Δt, α, dx) =
    rk4_step((v, s) -> diffusion_rhs_dirichlet(v, α, dx), u, t, Δt)

"""
    diffusion_cn_step(u, t, Δt, α, dx)

대안 3: Crank–Nicolson (음해법).
"""
diffusion_cn_step(u, t, Δt, α, dx) = crank_nicolson_step(u, Δt, α, dx)

"""
    advance!(step, sim, Δt, nsteps)

`step`으로 `nsteps`걸음 전진하고 새 시각 `sim.t`를 돌려준다.
"""
function advance!(step, sim::Diffusion1D{T}, Δt::T, nsteps::Int) where {T<:AbstractFloat}
    for _ in 1:nsteps
        sim.u = step(sim.u, sim.t, Δt, sim.α, sim.dx)
        sim.t = sim.t + Δt
    end
    return sim.t
end

"""
    max_abs(u)

`max |uᵢ|`.
"""
max_abs(u::AbstractVector) = maximum(abs, u)

"""
    moving_wall_error(sim, U)

현재 시각에서 Stokes 해석해와의 최대 절대오차.
"""
function moving_wall_error(sim::Diffusion1D{T}, U::T) where {T<:AbstractFloat}
    err = zero(T)
    for i in eachindex(sim.u)
        exact = stokes_first_solution((i - 1) * sim.dx, sim.t, U, sim.α)
        err = max(err, abs(sim.u[i] - exact))
    end
    return err
end

"""
    sin_mode_error(sim)

현재 시각에서 `sin(πy)·exp(−α·π²·t)`와의 최대 절대오차.
"""
function sin_mode_error(sim::Diffusion1D{T}) where {T<:AbstractFloat}
    err = zero(T)
    for i in eachindex(sim.u)
        exact = sin_mode_exact((i - 1) * sim.dx, sim.t, sim.α)
        err = max(err, abs(sim.u[i] - exact))
    end
    return err
end
