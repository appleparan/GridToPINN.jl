# Step1.jl — 미분과 Newton법
#
# 핵심 질문: DRS를 열면 최고속도가 얼마나 오르나?
#
# 풀려는 식: f(v) = ½ρ·C_d·A·v³ + F_구름·v − P = 0
# 해석해 (구름저항 0): v_top = (2P / (ρ·C_d·A))^(1/3)
#
# 설계:
# - 모든 커널은 T<:AbstractFloat에 대해 일반적
# - Float64 리터럴(0.5 등) 금지 → x/2 또는 T(0.5) 사용
# - Newton법, 유한차분(전진/중심), 이중수 자동미분 세 가지 미분 방법 제공
# - 이중수 Dual{T}는 값과 미분을 함께 들고 다니는 구조체

module Step1

# ---------------------------------------------------------------------------
# Dual 수 — 값과 미분을 함께 들고 다니는 작은 구조체
# ---------------------------------------------------------------------------

"""
    Dual{T} <: Number

자동미분을 위한 이중수. `val`은 함수값, `der`는 도함수값(미분계수).
스칼라 함수 f(x)의 x에서의 미분을 구하려면 f(Dual(x, one(x)))의 `.der`를 읽는다.
"""
struct Dual{T<:AbstractFloat} <: Number
    val::T
    der::T
end

# 생성자 편의
Dual(x::T, d::T) where {T<:AbstractFloat} = Dual{T}(x, d)
Dual(x::Real, d::Real) = Dual(promote(x, d)...)
Dual(x::Real) = Dual(promote(x, one(x))...)

# Dual{T}의 기저 타입 추출
dualtype(::Dual{T}) where {T} = T

# ---------------------------------------------------------------------------
# Base 연산자 오버로드 — Dual 수의 사칙연산 및 거듭제곱
# ---------------------------------------------------------------------------

# 덧셈
function Base.:+(a::Dual, b::Dual)
    T = promote_type(dualtype(a), dualtype(b))
    Dual(T(a.val + b.val), T(a.der + b.der))
end
Base.:+(a::Dual, b::Real) = a + Dual(b)
Base.:+(b::Real, a::Dual) = a + b

# 뺄셈
function Base.:-(a::Dual, b::Dual)
    T = promote_type(dualtype(a), dualtype(b))
    Dual(T(a.val - b.val), T(a.der - b.der))
end
Base.:-(a::Dual, b::Real) = a - Dual(b)
Base.:-(b::Real, a::Dual) = Dual(b) - a
Base.:-(a::Dual) = Dual(-a.val, -a.der)

# 곱셈 (곱의 미분법: (fg)' = f'g + fg')
function Base.:*(a::Dual, b::Dual)
    T = promote_type(dualtype(a), dualtype(b))
    Dual(T(a.val * b.val), T(a.der * b.val + a.val * b.der))
end
Base.:*(a::Dual, b::Real) = a * Dual(b)
Base.:*(b::Real, a::Dual) = a * b

# 나눗셈 (몫의 미분법: (f/g)' = (f'g - fg')/g²)
function Base.:/(a::Dual, b::Dual)
    T = promote_type(dualtype(a), dualtype(b))
    val = a.val / b.val
    der = (a.der * b.val - a.val * b.der) / (b.val * b.val)
    Dual(T(val), T(der))
end
Base.:/(a::Dual, b::Real) = a / Dual(b)
Base.:/(b::Real, a::Dual) = Dual(b) / a

# 거듭제곱 (정수 승만 — 연쇄법칙 + 거듭제곱 미분법)
function Base.:^(a::Dual, n::Integer)
    T = dualtype(a)
    val = a.val^n
    # (x^n)' = n·x^(n-1)·x'
    der = T(n) * a.val^(n - 1) * a.der
    Dual(T(val), T(der))
end

# ---------------------------------------------------------------------------
# Base 함수 — Dual 지원 (필요한 것만)
# ---------------------------------------------------------------------------

# abs는 x=0에서 미분 불가능하나 실용적으로 부호 함수 사용
function Base.abs(d::Dual)
    s = sign(d.val)
    Dual(abs(d.val), s * d.der)
end

# ---------------------------------------------------------------------------
# 유한차분 — 전진차분(차수 1)과 중심차분(차수 2)
# ---------------------------------------------------------------------------

"""
    derivative_fd(f, x, h)

전진차분 1차 근사: f'(x) ≈ (f(x+h) − f(x)) / h
h → 0 일 때 오차 O(h), 로그 기울기 1.
"""
derivative_fd(f, x::T, h::T) where {T<:AbstractFloat} = (f(x + h) - f(x)) / h

"""
    derivative_fd_central(f, x, h)

중심차분 2차 근사: f'(x) ≈ (f(x+h) − f(x−h)) / (2h)
h → 0 일 때 오차 O(h²), 로그 기울기 2.
"""
derivative_fd_central(f, x::T, h::T) where {T<:AbstractFloat} = (f(x + h) - f(x - h)) / (T(2) * h)

# ---------------------------------------------------------------------------
# 자동미분 — 이중수를 이용한 함수 미분
# ---------------------------------------------------------------------------

"""
    derivative_dual(f, x)

이중수를 이용한 f의 x에서의 미분.
f가 Dual 입력을 받아 Dual 출력을 낼 수 있도록 연산자 오버로드에 의존한다.
"""
function derivative_dual(f, x::T) where {T<:AbstractFloat}
    d = Dual(x, one(T))
    r = f(d)
    # r이 Dual이 아니면 변환 시도 (단순 스칼라 반환 함수 대비)
    r isa Dual ? r.der : convert(T, r)
end

# ---------------------------------------------------------------------------
# Newton법
# ---------------------------------------------------------------------------

"""
    newton(f, df, x0; tol=톨러런스, maxiter=최대반복)

Newton-Raphson 방법으로 f(x) = 0의 근을 찾는다.
df는 f의 도함수(해석적 또는 수치적). 수렴 시 근, 실패 시 ErrorException.
"""
function newton(f, df, x0::T; tol::T = T(1e-12), maxiter::Int = 50) where {T<:AbstractFloat}
    x = x0
    for i in 1:maxiter
        fx = f(x)
        dfx = df(x)
        if dfx == zero(T)
            throw(ErrorException("Newton: x = $x 에서f′ = 0, 중단"))
        end
        xnew = x - fx / dfx
        if abs(xnew - x) < tol * (one(T) + abs(xnew))
            return xnew
        end
        x = xnew
    end
    throw(ErrorException("Newton: $maxiter회 반복 후 수렴하지 않음, 마지막 x = $x, f(x) = $(f(x))"))
end

"""
    newton_with_trace(f, df, x0; tol=..., maxiter=...)

Newton 반복마다 (|x_new - x_old|, |f(x)|)를 기록한 벡터를 함께 반환.
수렴 차수(제곱 감소) 확인용.
"""
function newton_with_trace(f, df, x0::T; tol::T = T(1e-12), maxiter::Int = 50) where {T<:AbstractFloat}
    x = x0
    history = Vector{T}()
    sizehint!(history, maxiter)
    for i in 1:maxiter
        fx = f(x)
        dfx = df(x)
        if dfx == zero(T)
            throw(ErrorException("Newton: x = $x 에서 f′ = 0"))
        end
        xnew = x - fx / dfx
        push!(history, (abs(xnew - x), abs(fx)))
        if abs(xnew - x) < tol * (one(T) + abs(xnew))
            return xnew, history
        end
        x = xnew
    end
    throw(ErrorException("Newton: $maxiter회 반복 후 수렴하지 않음"))
end

# ---------------------------------------------------------------------------
# DRS 물리 모델
# ---------------------------------------------------------------------------

"""
    drag_force(v, ρ, Cd, A)

속도에 따른 항력: F_drag = ½ρ·C_d·A·v²
"""
drag_force(v::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat} = (T(1) / T(2)) * ρ * Cd * A * v^2

"""
    power_to_overcome_drag(v, ρ, Cd, A)

항력을 이겨내는 데 드는 출력: P = F_drag · v = ½ρ·C_d·A·v³
"""
power_to_overcome_drag(v::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat} = drag_force(v, ρ, Cd, A) * v

"""
    resistance(v, ρ, Cd, A, Froll)

총 저항력: 항력 + 구름저항
"""
resistance(v::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} = drag_force(v, ρ, Cd, A) + Froll

"""
    power_balance(v, P, ρ, Cd, A, Froll)

출력 = 저항 × 속도 → P − (항력+구름저항)·v
f(v) = ½ρ·C_d·A·v³ + F_구름·v − P
f(v) = 0이 최고속도.
"""
power_balance(v::T, P::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    power_to_overcome_drag(v, ρ, Cd, A) + Froll * v - P

"""
    top_speed(P, ρ, Cd, A, Froll; tol=..., maxiter=...)

Newton법으로 P = 저항·v 의 해를 구해 최고속도를 반환.
f′(v) = (3/2)ρ·C_d·A·v² + F_구름 (손 유도).
"""
function top_speed(P::T, ρ::T, Cd::T, A::T, Froll::T;
                   tol::T = T(1e-12), maxiter::Int = 50) where {T<:AbstractFloat}
    f  = v -> power_balance(v, P, ρ, Cd, A, Froll)
    df = v -> (T(3) / T(2)) * ρ * Cd * A * v^2 + Froll  # 손 유도 f′
    # 초기 추측: 구름저항 0 해석해로 시작
    v0 = T(2) * P / (ρ * Cd * A)  # (2P/(ρCDa))^(1/3) 아님 — v³ 항의 계수를 감안한 초기값 시도
    # 더 나은 초기값: 구름저항 무시 근사 (P ≈ ½ρ·C_d·A·v³ → v ≈ (2P/(ρCDa))^(1/3))
    v0 = (T(2) * P / (ρ * Cd * A))^(T(1) / T(3))
    v0 = max(v0, T(1))  # 너무 작아지지 않게
    newton(f, df, v0; tol = tol, maxiter = maxiter)
end

"""
    top_speed_analytic_zero_rolling(P, ρ, Cd, A)

구름저항이 0일 때의 해석해: (2P / (ρ·C_d·A))^(1/3)
Newton법 검증 기준.
"""
top_speed_analytic_zero_rolling(P::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat} =
    (T(2) * P / (ρ * Cd * A))^(T(1) / T(3))

# ---------------------------------------------------------------------------
# DRS 비교용 편의: Cd만 바꿔서 top_speed 쌍 반환
# ---------------------------------------------------------------------------

"""
    compare_drs(P, ρ, A, Froll, Cd_closed, Cd_open; ...)

DRS 닫힘/열림(Cd 차이)에 따른 최고속도 쌍과 차이(dv = v_open − v_closed) 반환.
"""
function compare_drs(P::T, ρ::T, A::T, Froll::T, Cd_closed::T, Cd_open::T;
                     tol::T = T(1e-12), maxiter::Int = 50) where {T<:AbstractFloat}
    v_closed = top_speed(P, ρ, Cd_closed, A, Froll; tol = tol, maxiter = maxiter)
    v_open   = top_speed(P, ρ, Cd_open,   A, Froll; tol = tol, maxiter = maxiter)
    (closed = v_closed, open = v_open, dv = v_open - v_closed)
end

end # module
