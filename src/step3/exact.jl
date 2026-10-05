# step3/exact.jl — 확산의 정답
#
# 본 문제 (움직이는 벽, Stokes 1종): 벽을 t = 0에 순간적으로 속도 U로 움직인다.
#   u(y, t) = U·erfc( y / (2√(ν·t)) ),  확산 깊이 δ = 2√(ν·t)
#   꿀이 물보다 √(ν_꿀/ν_물)배 더 깊이 끌려온다. t = 0에서 벽면이 불연속이라
#   수렴 차수를 확인하기엔 부적합하다. erfc는 Base에 없어서 직접 구현한다.
# 검증 문제 (매끄러움): u(y, 0) = sin(πy), u(0) = u(1) = 0
#   u(y, t) = sin(πy)·e^{−α·π²·t}. 수렴 차수 확인용.
# 쓰임: 7단계 Cavity 초기의 뚜껑 아래 속도 분포와 비교.

"""
    erfc_approx(x)

상보오차함수 erfc(x). Abramowitz–Stegun 7.1.26 근사로 |오차| ≤ 1.5e-7(Float64).
Float32에서는 계수 반올림 때문에 ~1e-6까지 커질 수 있다.
"""
function erfc_approx(x::T) where {T<:AbstractFloat}
    z = abs(x)
    t = one(T) / (one(T) + T(0.3275911) * z)
    p = T(1.061405429)
    p = t * p + T(-1.453152027)
    p = t * p + T(1.421413741)
    p = t * p + T(-0.284496736)
    p = t * p + T(0.254829592)
    e = t * p * exp(-z * z)
    return x >= zero(T) ? e : 2 - e
end

"""
    stokes_first_solution(y, t, U, ν)

움직이는 벽의 해석해 `U·erfc(y/(2√(ν·t)))`. `t = 0`에서는 극한값(벽면 U, 그 아래 0)을 돌려준다.
"""
function stokes_first_solution(y::T, t::T, U::T, ν::T) where {T<:AbstractFloat}
    ν * t > zero(T) || return y > zero(T) ? zero(T) : U
    return U * erfc_approx(y / (2 * sqrt(ν * t)))
end

"""
    diffusion_depth(ν, t)

확산 깊이 `δ = 2√(ν·t)`. 이 깊이에서 벽 속도의 erfc(1) ≈ 16 %가 남는다.
"""
diffusion_depth(ν::T, t::T) where {T<:AbstractFloat} = 2 * sqrt(ν * t)

"""
    sin_mode_initial(y)

검증 문제의 초기조건 `sin(πy)`.
"""
sin_mode_initial(y::T) where {T<:AbstractFloat} = sin(T(π) * y)

"""
    sin_mode_exact(y, t, α)

검증 문제의 해석해 `sin(πy)·exp(−α·π²·t)`.
"""
sin_mode_exact(y::T, t::T, α::T) where {T<:AbstractFloat} = sin(T(π) * y) * exp(-α * T(π)^2 * t)
