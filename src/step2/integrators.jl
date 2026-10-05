# step2/integrators.jl — 고정 간격 적분기 (Euler, RK4)
#
# 질문: dy/dt = f(y, t)를 어떻게 한 걸음씩 전진시키나?
# 식:   Euler  y' = y + Δt·f(y, t)
#       RK4    y' = y + Δt/6·(k₁ + 2k₂ + 2k₃ + k₄)
# 쓰임: 스칼라, Vector, Matrix를 모두 받는다(브로드캐스트 한 벌).
#       3단계 확산(선의 방법), 4단계 대류, 7단계가 그대로 가져다 쓴다.

"""
    Trajectory{T,Y}

적분 결과. `t[i]`는 시각, `y[i]`는 그 시각의 상태다.
"""
struct Trajectory{T<:AbstractFloat,Y}
    t::Vector{T}
    y::Vector{Y}
end

"""
    euler_step(f, y, t, Δt)

Euler 한 걸음: `y + Δt·f(y, t)`. 1차 정확도.
"""
euler_step(f, y, t, Δt) = y .+ Δt .* f(y, t)

"""
    rk4_step(f, y, t, Δt)

고전 4차 Runge–Kutta 한 걸음. 4차 정확도.
"""
function rk4_step(f, y, t, Δt)
    h = Δt / 2
    k1 = f(y, t)
    k2 = f(y .+ h .* k1, t + h)
    k3 = f(y .+ h .* k2, t + h)
    k4 = f(y .+ Δt .* k3, t + Δt)
    return y .+ (Δt / 6) .* (k1 .+ 2 .* k2 .+ 2 .* k3 .+ k4)
end

"""
    integrate(step, f, y0, t0, t_end, Δt) -> Trajectory

`step`(`euler_step`/`rk4_step`)으로 `t0`에서 `t_end`까지 고정 간격 Δt로 적분한다.
걸음 수는 `round((t_end - t0)/Δt)`(최소 1)이고 시각은 `t0 + i·Δt`다.
"""
function integrate(step, f, y0, t0::T, t_end::T, Δt::T) where {T<:AbstractFloat}
    nsteps = max(1, round(Int, (t_end - t0) / Δt))
    ts = T[t0]
    ys = typeof(y0)[y0]
    y = y0
    for i in 1:nsteps
        t = t0 + (i - 1) * Δt
        y = step(f, y, t, Δt)
        push!(ts, t0 + i * Δt)
        push!(ys, y)
    end
    return Trajectory(ts, ys)
end
