# step1/dual.jl — 이중수 자동미분
#
# 질문: 도함수를 손으로 유도하지 않고 컴퓨터가 정확히 구할 수 있나?
# 방법: 값(val)과 미분(der)을 함께 들고 다니는 수. 연산마다 미분 규칙을 같이 적용한다.
# 쓰임: derivative.jl의 derivative_dual, 8단계 PINN의 PDE 잔차 미분.

"""
    Dual{T}

이중수. `val`은 함수값, `der`는 미분값이다.
`f(Dual(x, one(x))).der`가 `f'(x)`다.
"""
struct Dual{T<:AbstractFloat} <: Number
    val::T
    der::T
end

# 합과 차
Base.:+(a::Dual{T}, b::Dual{T}) where {T} = Dual(a.val + b.val, a.der + b.der)
Base.:+(a::Dual{T}, b::Real) where {T} = Dual(a.val + T(b), a.der)
Base.:+(b::Real, a::Dual{T}) where {T} = Dual(T(b) + a.val, a.der)
Base.:-(a::Dual) = Dual(-a.val, -a.der)
Base.:-(a::Dual{T}, b::Dual{T}) where {T} = Dual(a.val - b.val, a.der - b.der)
Base.:-(a::Dual{T}, b::Real) where {T} = Dual(a.val - T(b), a.der)
Base.:-(b::Real, a::Dual{T}) where {T} = Dual(T(b) - a.val, -a.der)

# 곱: (fg)' = f'g + fg'. 상수의 미분은 0
Base.:*(a::Dual{T}, b::Dual{T}) where {T} = Dual(a.val * b.val, a.der * b.val + a.val * b.der)
Base.:*(a::Dual{T}, b::Real) where {T} = Dual(a.val * T(b), a.der * T(b))
Base.:*(b::Real, a::Dual{T}) where {T} = Dual(T(b) * a.val, T(b) * a.der)

# 몫: (f/g)' = (f'g - fg') / g²
Base.:/(a::Dual{T}, b::Dual{T}) where {T} =
    Dual(a.val / b.val, (a.der * b.val - a.val * b.der) / (b.val * b.val))
Base.:/(a::Dual{T}, b::Real) where {T} = Dual(a.val / T(b), a.der / T(b))
Base.:/(b::Real, a::Dual{T}) where {T} =
    Dual(T(b) / a.val, -T(b) * a.der / (a.val * a.val))

# 정수 거듭제곱: (f^n)' = n f^(n-1) f'
function Base.:^(a::Dual{T}, n::Integer) where {T}
    return Dual(a.val^n, T(n) * a.val^(n - 1) * a.der)
end
