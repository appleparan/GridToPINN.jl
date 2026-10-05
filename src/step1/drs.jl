# step1/drs.jl — DRS 모델과 최고속도
#
# 질문: DRS를 열면 최고속도가 얼마나 오르나?
# 식:   f(v) = ½ρ·Cd·A·v³ + F_구름·v − P = 0   (출력 = 저항 × 속도)
# 정답: 구름저항 0이면 v = (2P / (ρ·Cd·A))^(1/3)
# 쓰임: 2단계가 이 함수들로 가속 모델을 만들고, 최고속도를 수렴 목표로 쓴다.
#
# `v`는 타입을 고정하지 않는다: 이중수(Dual)가 들어와야 자동미분이 된다.
#
# 대표값(가정, 실제 차량 값이 아님): P = 600 kW, ρ = 1.225 kg/m³, A = 1.5 m²,
# Cd 닫힘 0.9 / 열림 0.8, F_구름 = 0, 질량 m = 800 kg.
# 닫힘 최고속도 ≈ 89.9 m/s (323.5 km/h), 열림 ≈ 93.5 m/s (336.5 km/h): DRS로 약 13 km/h 오른다.
#
# 단위: 계산은 모두 SI(m/s)다. 출력 = 힘 × 속도가 그대로 성립해야 하기 때문이다.
# 화면은 속도만 km/h(= m/s × 3.6)로 바꿔 보여준다.

"""
    drag_force(v, ρ, Cd, A)

항력 `½ρ·Cd·A·v²`.
"""
drag_force(v, ρ::T, Cd::T, A::T) where {T<:AbstractFloat} = ρ * Cd * A * v * v / 2

"""
    resistance(v, ρ, Cd, A, Froll)

총 저항력: 항력 + 구름저항.
"""
resistance(v, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    drag_force(v, ρ, Cd, A) + Froll

"""
    power_balance(v, P, ρ, Cd, A, Froll)

출력 균형 `f(v) = ½ρ·Cd·A·v³ + F_구름·v − P`. 근이 최고속도다.
"""
power_balance(v, P::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    resistance(v, ρ, Cd, A, Froll) * v - P

"""
    power_balance_derivative(v, ρ, Cd, A, Froll)

손으로 유도한 `f'(v) = (3/2)ρ·Cd·A·v² + F_구름`.
"""
power_balance_derivative(v, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    3 * ρ * Cd * A * v * v / 2 + Froll

"""
    top_speed_analytic(P, ρ, Cd, A)

구름저항 0일 때의 해석해 `(2P / (ρ·Cd·A))^(1/3)`. Newton법의 정답이자 출발점이다.
"""
top_speed_analytic(P::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat} = cbrt(2P / (ρ * Cd * A))

"""
    top_speed_iterates(derivative, P, ρ, Cd, A, Froll, v0; tol, maxiter)

Newton 반복값 전체. 미분 방법은 `derivative(f, v)`(= f'(v))로 고른다.
예: `(f, v) -> derivative_central(f, v, h)`, `derivative_dual`.
"""
function top_speed_iterates(derivative, P::T, ρ::T, Cd::T, A::T, Froll::T, v0::T;
                            tol::T = 4eps(T), maxiter::Int = 50) where {T<:AbstractFloat}
    f = v -> power_balance(v, P, ρ, Cd, A, Froll)
    df = v -> derivative(f, v)
    return newton_iterates(f, df, v0; tol = tol, maxiter = maxiter)
end

"""
    top_speed(P, ρ, Cd, A, Froll)

손으로 유도한 f'로 Newton법을 돌려 구한 최고속도. 출발점은 구름저항 0의 해석해다.
"""
function top_speed(P::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat}
    f = v -> power_balance(v, P, ρ, Cd, A, Froll)
    df = v -> power_balance_derivative(v, ρ, Cd, A, Froll)
    return newton(f, df, top_speed_analytic(P, ρ, Cd, A))
end

"""
    drs_gain(P, ρ, A, Froll, Cd_closed, Cd_open)

DRS를 열었을 때 최고속도 증가량 `v_open − v_closed`.
"""
function drs_gain(P::T, ρ::T, A::T, Froll::T, Cd_closed::T, Cd_open::T) where {T<:AbstractFloat}
    return top_speed(P, ρ, Cd_open, A, Froll) - top_speed(P, ρ, Cd_closed, A, Froll)
end
