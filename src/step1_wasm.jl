# step1_wasm.jl — Step1 WASM 진입점 래퍼
#
# 이 파일은 WASM 컴파일용 진입점(entry point)을 정의한다.
# 화면에 표시용 교재 코드가 아님 — 빌드 산출물에 포함만 됨.
#
# 설계 원칙:
# - 기본 인자(GlobalRef) 회피: 모든 인자 명시적
# - Function 인자 회피: concrete 타입만 사용
# - 원본 Step1DiffNewton 함수를 호출하거나, Newton 로직을 직접 구현

using .Step1DiffNewton

# ---------------------------------------------------------------------------
# Dual 연산 — WASM 노출용 얇은 래퍼
# (원본 연산자 오버로드를 그대로 노출. Dual{Float64} WasmGC struct 컴파일 확인됨)
# ---------------------------------------------------------------------------
dual_add_wasm(d1::Dual{Float64}, d2::Dual{Float64}) = d1 + d2
dual_mul_wasm(d1::Dual{Float64}, d2::Dual{Float64}) = d1 * d2

# ---------------------------------------------------------------------------
# Vector 브릿지 — WasmTarget 공식 권장 패턴
# JS에서 Vector{Float64} 직접 생성 불가 → WASM 측 생성 + 요소 조작 함수
# ---------------------------------------------------------------------------
vec_new_wasm(n::Int64)::Vector{Float64}       = Vector{Float64}(undef, n)
vec_set_wasm(v::Vector{Float64}, i::Int64, val::Float64)::Int64 = (v[i] = val; Int64(0))
vec_get_wasm(v::Vector{Float64}, i::Int64)::Float64          = v[i]
vec_len_wasm(v::Vector{Float64})::Int64                       = Int64(length(v))
vec_sum_wasm(v::Vector{Float64})::Float64                     = sum(v)

# ---------------------------------------------------------------------------
# 스칼라 함수 (WASM에 함께 컴파일할 구체적 함수)
# f_poly_wasm: Dual{Float64}도 받아야 derivative_dual에서 사용 가능.
#   Dual 연산자 오버로드(Base.:+, :*, :^ 등)가 Dual에 대해 정의되어 있으므로
#   동일한 표현이 Dual에서도 동작한다.
#   where 절을 함수 서명과 분리해서 작성 (Julia 1.12 호환성)
# ---------------------------------------------------------------------------
function f_poly_wasm(x::T) where {T<:Number}
    return x^3 + 2 * x^2 + x
end
df_analytic_wasm(x::Float64)::Float64 = 3.0 * x^2 + 4.0 * x + 1.0

# ---------------------------------------------------------------------------
# derivative_fd (전진차분) — 구체적 함수 f_poly_wasm에 대해
# 원본 derivative_fd를 f_poly_wasm에 특화하여 호출
# ---------------------------------------------------------------------------
derivative_fd_wasm(x::Float64, h::Float64)::Float64 =
    Step1DiffNewton.derivative_fd(f_poly_wasm, x, h)

# ---------------------------------------------------------------------------
# derivative_dual (Dual 자동미분) — 구체적 함수 f_poly_wasm에 대해
# 주의: Dual{Float64}는 WasmGC struct. JS에서 Dual 입력 생성 불가 →
#       derivative_dual_wasm 자체는 WASM에서 컴파일되나 JS에서 직접 호출 불가.
#       JS에서는 derivative_fd_wasm 사용.
# ---------------------------------------------------------------------------
derivative_dual_wasm(x::Float64)::Float64 =
    Step1DiffNewton.derivative_dual(f_poly_wasm, x)

# ---------------------------------------------------------------------------
# top_speed_wasm — Newton-Raphson 기반 최고속도
#
# 원본 top_speed는 기본 인자 maxiter::Int=50이 IR에서 GlobalRef로 남아
# WasmTarget이 "unsupported_global" 오류로 컴파일 실패.
# → 모든 인자 명시적, Newton 반복을 내부에서 직접 구현.
#
# 물리 모델:
#   f(v) = ½ρ·Cd·A·v³ + Froll·v − P  = 0  을 만족하는 v를 찾는다
#   f′(v) = (3/2)ρ·Cd·A·v² + Froll     (손 유도)
# ---------------------------------------------------------------------------
function top_speed_wasm(
    P::Float64, ρ::Float64, Cd::Float64,
    A::Float64, Froll::Float64,
    tol::Float64, maxiter::Int64
)::Float64
    # f(v)와 f′(v)를 클로저로 정의
    f  = v -> 0.5 * ρ * Cd * A * v * v * v + Froll * v - P
    df = v -> 1.5 * ρ * Cd * A * v * v + Froll

    # 초기 추측: 구름저항 0일 때 해석해
    #   v₀ = (2·P / (ρ·Cd·A))^(1/3)
    x  = (2.0 * P / (ρ * Cd * A))^(1.0 / 3.0)
    x  = max(x, 1.0)  # 너무 작아지지 않게 하한 clamp

    # Newton-Raphson 반복
    for i in 1:maxiter
        fx  = f(x)
        dfx = df(x)
        if dfx == 0.0
            throw(ErrorException("Newton: f′(v) = 0 에서 중단"))
        end
        xnew = x - fx / dfx
        # 상대오차 기반 수렴 판정: |xnew−x| < tol·(1 + |xnew|)
        if abs(xnew - x) < tol * (1.0 + abs(xnew))
            return xnew
        end
        x = xnew
    end

    throw(ErrorException("Newton: 최대 반복 후 수렴하지 않음"))
end

# ---------------------------------------------------------------------------
# compare_drs_wasm — DRS 개폐(Cd 차이)에 따른 최고속도 차이
#
# 원본 compare_drs는 내부 top_speed 호출 시 기본 인자 GlobalRef 문제.
# → Newton 반복을 직접 구현한 내부 함수로 대체.
# ---------------------------------------------------------------------------
function compare_drs_wasm(
    P::Float64, ρ::Float64, A::Float64, Froll::Float64,
    Cd_closed::Float64, Cd_open::Float64,
    tol::Float64, maxiter::Int64
)::Float64

    # Newton 반복 헬퍼 (클로저 내부에서 사용)
    function newton_one(
        f, df,
        x0::Float64, tol::Float64, maxiter::Int64
    )::Float64
        x = x0
        for i in 1:maxiter
            fx  = f(x)
            dfx = df(x)
            if dfx == 0.0
                throw(ErrorException("Newton: f′ = 0"))
            end
            xnew = x - fx / dfx
            if abs(xnew - x) < tol * (1.0 + abs(xnew))
                return xnew
            end
            x = xnew
        end
        throw(ErrorException("Newton: 수렴하지 않음"))
    end

    # 닫힌 상태 (Cd = Cd_closed)
    f_c  = v -> 0.5 * ρ * Cd_closed * A * v * v * v + Froll * v - P
    df_c = v -> 1.5 * ρ * Cd_closed * A * v * v + Froll
    v_c  = newton_one(
        f_c, df_c,
        max((2.0 * P / (ρ * Cd_closed * A))^(1.0 / 3.0), 1.0),
        tol, maxiter
    )

    # 열린 상태 (Cd = Cd_open)
    f_o  = v -> 0.5 * ρ * Cd_open * A * v * v * v + Froll * v - P
    df_o = v -> 1.5 * ρ * Cd_open * A * v * v + Froll
    v_o  = newton_one(
        f_o, df_o,
        max((2.0 * P / (ρ * Cd_open * A))^(1.0 / 3.0), 1.0),
        tol, maxiter
    )

    return v_o - v_c
end
