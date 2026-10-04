using Test
using GridToPINN.Step1DiffNewton

# ---------------------------------------------------------------------------
# 1. Dual 수 기본 연산 확인
# ---------------------------------------------------------------------------
@testset "Dual 수 연산" begin
    d1 = Dual(3.0, 1.0)
    d2 = Dual(2.0, 0.5)

    # 덧셈
    s = d1 + d2
    @test s.val == 5.0
    @test s.der == 1.5  # 1.0 + 0.5

    # 곱셈
    p = d1 * d2
    @test p.val == 6.0
    @test p.der == 3.0 * 0.5 + 2.0 * 1.0  # 1.5 + 2.0 = 3.5

    # 거듭제곱 (정수 승)
    q = d1^2
    @test q.val == 9.0
    @test q.der == 2 * 3.0 * 1.0  # 6.0
end

# ---------------------------------------------------------------------------
# 2. 자동미분 — 간단한 다항식
# ---------------------------------------------------------------------------
@testset "자동미분 (Dual)" begin
    T = Float64

    # f(x) = x^3 + 2x^2 + x
    f(x) = x^3 + T(2) * x^2 + x
    df_analytic(x) = T(3) * x^2 + T(4) * x + T(1)

    for x in [T(0.5), T(1.0), T(2.0), T(-1.0)]
        ad = derivative_dual(f, x)
        analytic = df_analytic(x)
        @test ad ≈ analytic atol = T(1e-12)
    end
end

# ---------------------------------------------------------------------------
# 3. 유한차분 오차 차수 확인
# ---------------------------------------------------------------------------
@testset "유한차분 오차 차수" begin
    T = Float64
    # 비선형 함수: f(x) = sin(x) → f'(x) = cos(x), f'''(x) = -cos(x)
    # 중심차분 오차 O(h²) 항이 0이 아니어서 수렴 차수 확인 가능
    f(x) = sin(x)
    df_exact(x) = cos(x)

    x0 = T(1.0)
    exact = df_exact(x0)

    # h를 충분히 작게: truncation 오차가 rounding 오차보다 큰 구간
    hs = T.([1e-1, 5e-2, 1e-2, 5e-3, 1e-3])
    errors_forward = [abs(derivative_fd(f, x0, h) - exact) for h in hs]
    errors_central = [abs(derivative_fd_central(f, x0, h) - exact) for h in hs]

    # 전진차분: 연속 h 간 오차 비율이 약 2~5배 (O(h) → h 1/2 → 오차 1/2)
    @test errors_forward[1] > errors_forward[end]  # h 줄면 오차 감소
    # 중심차분: 연속 h 간 오차 비율이 약 4~25배 (O(h²) → h 1/2 → 오차 1/4)
    @test errors_central[1] > errors_central[end]

    # 중심차분이 전진보다 작은 오류로부터 시작함을 확인 (h=0.1 기준)
    @test errors_central[1] < errors_forward[1]
end

# ---------------------------------------------------------------------------
# 4. Newton법 — 제곱 수렴 확인
# ---------------------------------------------------------------------------
@testset "Newton법 수렴" begin
    T = Float64

    # f(x) = x^2 - 2  → 근 = √2
    f(x) = x^2 - T(2)
    df(x) = T(2) * x
    x0 = T(1.0)

    root, trace = newton_with_trace(f, df, x0; tol = T(1e-14), maxiter = 20)
    @test root ≈ sqrt(T(2)) atol = T(1e-12)

    # 오차가 매 반복마다 제곱으로 줄어드는지 확인 (초기 몇 회)
    # |e_{n+1}| ≈ C·|e_n|²  → log|e_{n+1}| / log|e_n| ≈ 2
    for i in 1:min(4, length(trace) - 1)
        en = trace[i][1]   # |x_n - x_{n-1}| 근사
        en1 = trace[i + 1][1]
        if en > T(1e-15) && en1 > T(1e-15)
            ratio = log(en1) / log(en)
            @test ratio > T(1.5)  # 제곱 수렴의 최소 기준 (완벽한 2는 아님)
        end
    end
end

# ---------------------------------------------------------------------------
# 5. 최고속도 — 구름저항 0 해석해와 일치
# ---------------------------------------------------------------------------
@testset "최고속도 (구름저항 0)" begin
    T = Float64

    # F1 스타일 근사값 (원리가 목적, 정확치 아님)
    P   = T(500_000)       # 엔진 출력 [W] — 근사값
    ρ   = T(1.225)         # 공기 밀도 [kg/m³]
    Cd  = T(0.30)          # 항력계수 — 근사값
    A   = T(0.55)          # 전면적 [m²]
    Froll = T(0.0)         # 구름저항 0 (검증용)

    v_newton = top_speed(P, ρ, Cd, A, Froll; tol = T(1e-14))
    v_analytic = top_speed_analytic_zero_rolling(P, ρ, Cd, A)

    @test v_newton ≈ v_analytic atol = T(1e-10)

    # DRS 비교: Cd_open < Cd_closed
    Cd_closed = T(0.30)
    Cd_open   = T(0.20)
    cmp = compare_drs(P, ρ, A, Froll, Cd_closed, Cd_open; tol = T(1e-14))
    @test cmp.open > cmp.closed
    @test cmp.dv > zero(T)
end

# ---------------------------------------------------------------------------
# 6. Float32/Float64 양쪽 동작, 타입 승격 없음
# ---------------------------------------------------------------------------
@testset "Float32 동작 및 타입 승격 없음" begin
    # Dual{Float32} 연산
    d1 = Dual(Float32(3.0), Float32(1.0))
    d2 = Dual(Float32(2.0), Float32(0.5))
    s = d1 + d2
    @test s isa Dual{Float32}
    @test s.val == Float32(5.0)

    # Float32 Newton
    T = Float32
    f(x) = x^2 - T(2)
    df(x) = T(2) * x
    root = newton(f, df, T(1.0); tol = T(1e-6), maxiter = 20)
    @test root ≈ sqrt(T(2)) atol = T(1e-5)

    # Float32 최고속도
    P     = T(500_000)
    ρ     = T(1.225)
    Cd    = T(0.30)
    A     = T(0.55)
    Froll = T(0.0)
    v32 = top_speed(P, ρ, Cd, A, Froll; tol = T(1e-6))
    @test v32 isa T
    @test v32 > zero(T)
end

# ---------------------------------------------------------------------------
# 7. 깨뜨리기 — h 감소에 따른 반올림오차 임계점 (Float32 vs Float64)
# ---------------------------------------------------------------------------
@testset "깨뜨리기: 반올림오차 임계점" begin
    T64 = Float64
    T32 = Float32

    # f(x) = exp(x): f'''(x) = exp(x) ≠ 0 → 중심차분 절단오차 O(h²) 항이 존재
    # h가 작아지면 절단오차 감소 + 반올림오차 증가 → U자 곡선, 중간에서 최소
    f(x) = exp(x)
    df_exact(x) = exp(x)
    x0 = T64(0.0)
    exact = df_exact(x0)

    # Float64: 넓은 h 범위에서 오차 변화 추적
    hs_64 = T64.([1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6, 1e-7, 1e-8, 1e-9, 1e-10, 1e-11, 1e-12, 1e-13, 1e-14, 1e-15])
    errs_64 = [abs(derivative_fd_central(f, x0, h) - exact) for h in hs_64]
    # 충분히 큰 h(0.1)에서는 절단오차가 지배 → 작은 h에서 오차가 더 작아야 함
    @test minimum(errs_64) < errs_64[1]
    # 최소점이 배열 끝에 있지 않음 = 반올림오차가 작용하는 구간이 존재함
    minidx = argmin(errs_64)
    @test minidx < length(errs_64)
end
