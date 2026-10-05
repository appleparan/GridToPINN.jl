# step2/adaptive.jl — 간격을 스스로 조절하는 Runge–Kutta (Dormand–Prince 5(4))
#
# 질문: 변화가 빠른 곳에서만 촘촘하게 걷게 할 수 없나?
# 방법: 5차 해와 4차 해의 차이를 오차로 보고, 허용오차에 맞춰 Δt를 늘리고 줄인다.
# 쓰임: DRS가 열리는 순간 오차가 커져 Δt가 줄고, 정상상태가 되면 다시 커진다.
#       계수는 모두 T로 만든다(Float64 상수를 쓰면 Float32가 승격된다).

# 스칼라와 배열 모두의 최대 절대값
maxabs(x::Number) = abs(x)
maxabs(x::AbstractArray) = maximum(abs, x)

"""
    rk45_step(f, y, t, Δt) -> (y5, err)

Dormand–Prince 한 걸음. `y5`는 5차 해, `err`는 `maximum(abs, y5 - y4)`(4차 해와의 차이)다.
"""
function rk45_step(f, y, t, Δt)
    k1 = f(y, t)
    k2 = f(@.(y + Δt * (k1 / 5)), t + Δt / 5)
    k3 = f(@.(y + Δt * (3 * k1 / 40 + 9 * k2 / 40)), t + 3 * Δt / 10)
    k4 = f(@.(y + Δt * (44 * k1 / 45 - 56 * k2 / 15 + 32 * k3 / 9)), t + 4 * Δt / 5)
    k5 = f(@.(y + Δt * (19372 * k1 / 6561 - 25360 * k2 / 2187 + 64448 * k3 / 6561 -
                       212 * k4 / 729)), t + 8 * Δt / 9)
    k6 = f(@.(y + Δt * (9017 * k1 / 3168 - 355 * k2 / 33 + 46732 * k3 / 5247 +
                       49 * k4 / 176 - 5103 * k5 / 18656)), t + Δt)
    y5 = @. y + Δt * (35 * k1 / 384 + 500 * k3 / 1113 + 125 * k4 / 192 -
                     2187 * k5 / 6784 + 11 * k6 / 84)
    k7 = f(y5, t + Δt)   # FSAL: 5차 해에서의 기울기
    dy = @. Δt * (71 * k1 / 57600 - 71 * k3 / 16695 + 71 * k4 / 1920 -
                 17253 * k5 / 339200 + 22 * k6 / 525 - k7 / 40)   # y5 − y4
    return y5, maxabs(dy)
end

"""
    integrate_adaptive(f, y0, t0, t_end, Δt0; rtol, maxsteps) -> Trajectory

간격을 조절하며 `t0`에서 `t_end`까지 적분한다. 받아들인 걸음만 기록한다
(걸음 크기는 `diff(tr.t)`). `err <= rtol·(1 + max|y5|)`이면 받아들이고,
`Δt`에 `0.9·(허용/err)^(1/5)`를 곱한다(0.2~5배로 제한). 마지막 걸음은 `t_end`에 맞춰 자른다.
`maxsteps`번 시도 안에 끝나지 않으면 거기까지의 기록을 돌려준다.
"""
function integrate_adaptive(f, y0, t0::T, t_end::T, Δt0::T;
                            rtol::T = T(1) / 1_000_000, maxsteps::Int = 100_000) where {T<:AbstractFloat}
    ts = T[t0]
    ys = typeof(y0)[y0]
    t = t0
    y = y0
    Δt = Δt0
    for _ in 1:maxsteps
        t >= t_end && break
        is_last = Δt >= t_end - t
        h = is_last ? t_end - t : Δt
        y5, err = rk45_step(f, y, t, h)
        tol = rtol * (one(T) + maxabs(y5))
        if err <= tol
            t = is_last ? t_end : t + h
            y = y5
            push!(ts, t)
            push!(ys, y)
        end
        ratio = tol / err          # err = 0이면 Inf, NaN이면 NaN
        factor = isnan(ratio) ? T(1) / 5 : clamp(T(9) / 10 * ratio^(T(1) / 5), T(1) / 5, T(5))
        Δt = h * factor
    end
    return Trajectory(ts, ys)
end
