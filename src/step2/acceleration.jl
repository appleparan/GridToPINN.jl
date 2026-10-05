# step2/acceleration.jl — DRS 가속 모델
#
# 질문: DRS를 연 뒤 새 최고속도에 도달하는 데 얼마나 걸리나?
# 식:   m·dv/dt = P/v − R(v),  R = ½ρ·Cd·A·v² + F_구름   → a = (P/v − R)/m
#       Cd는 t_open에 닫힘 값에서 열림 값으로 바뀐다.
# 정답: v(t→∞)는 1단계 top_speed(열림 Cd). 출발점은 1단계 top_speed(닫힘 Cd)다.
# 재사용: resistance, top_speed는 1단계 것. 적분기는 integrators.jl, adaptive.jl 것.

"""
    acceleration(v, P, m, ρ, Cd, A, Froll)

가속도 `(P/v − R(v)) / m` [m/s²]. 출력 P가 일정하면 견인력은 P/v다.
"""
acceleration(v::T, P::T, m::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    (P / v - resistance(v, ρ, Cd, A, Froll)) / m

"""
    drs_acceleration(v, t, P, m, ρ, A, Froll, Cd_closed, Cd_open, t_open)

시각 `t`의 가속도. `t < t_open`이면 닫힘 Cd, 이후는 열림 Cd를 쓴다.
"""
function drs_acceleration(v::T, t::T, P::T, m::T, ρ::T, A::T, Froll::T,
                          Cd_closed::T, Cd_open::T, t_open::T) where {T<:AbstractFloat}
    Cd = t < t_open ? Cd_closed : Cd_open
    return acceleration(v, P, m, ρ, Cd, A, Froll)
end

"""
    drs_run(integrator, P, m, ρ, A, Froll, Cd_closed, Cd_open, t_open, t_end) -> Trajectory

닫힘 최고속도에서 출발해 `t_end`까지 속도 곡선을 적분한다.
`integrator(f, v0, t0, t_end)`가 적분기를 고른다. 예:
`(f, v0, t0, t1) -> integrate(rk4_step, f, v0, t0, t1, Δt)`.
"""
function drs_run(integrator, P::T, m::T, ρ::T, A::T, Froll::T,
                 Cd_closed::T, Cd_open::T, t_open::T, t_end::T) where {T<:AbstractFloat}
    f = (v, t) -> drs_acceleration(v, t, P, m, ρ, A, Froll, Cd_closed, Cd_open, t_open)
    v0 = top_speed(P, ρ, Cd_closed, A, Froll)
    return integrator(f, v0, zero(T), t_end)
end

"""
    settling_time(tr, v_final, fraction)

처음 간격 `|v₀ − v_final|`이 `(1 − fraction)`배 이하로 줄어드는 첫 시각(표본 사이는 선형 보간).
끝내 못 미치면 `Inf`.
"""
function settling_time(tr::Trajectory{T,T}, v_final::T, fraction::T) where {T<:AbstractFloat}
    limit = (one(T) - fraction) * abs(tr.y[1] - v_final)
    for i in eachindex(tr.t)
        gap = abs(tr.y[i] - v_final)
        if gap <= limit
            i == 1 && return tr.t[1]
            gap_prev = abs(tr.y[i - 1] - v_final)
            w = (gap_prev - limit) / (gap_prev - gap)
            return tr.t[i - 1] + w * (tr.t[i] - tr.t[i - 1])
        end
    end
    return T(Inf)
end
