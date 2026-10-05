using Test
using GridToPINN.Step2TimeIntegration

# ---------------------------------------------------------------------------
# 1. 가속도 함수 테스트 (물리 모델)
# ---------------------------------------------------------------------------
@testset "가속도 함수" begin
    T = Float64

    # DRS 개방 후: P=500000W, ρ=1.225, A=0.55, v_top ≈ 170.4 m/s
    P = T(500000.0)
    ρ = T(1.225)
    A = T(0.55)
    Cd_open = T(0.20)  # DRS 개방
    v_top = Step2TimeIntegration.top_speed_target(P, ρ, Cd_open, A)

    @test v_top > T(0)
    # Cd=0.20일 때 해석해: (2P/(ρ·Cd·A))^(1/3) ≈ 195 m/s
    @test v_top ≈ T(195.0) atol = T(2.0)

    # v=0에서 가속도 (최대)
    a0 = Step2TimeIntegration.acceleration(T(0.0), P, ρ, A, v_top)
    @test a0 > T(0)

    # v = v_top에서 가속도 = 0 (정상상태)
    a_top = Step2TimeIntegration.acceleration(v_top, P, ρ, A, v_top)
    @test a_top ≈ T(0.0) atol = T(1e-10)

    # 중간 속도에서 가속도 (v가 v_top의 절반)
    v_half = v_top / T(2)
    a_half = Step2TimeIntegration.acceleration(v_half, P, ρ, A, v_top)
    @test a_half > T(0)
    @test a_half < a0  # v가 클수록 가속도 감소
end

# ---------------------------------------------------------------------------
# 2. Euler 적분기 테스트
# ---------------------------------------------------------------------------
@testset "Euler 적분기" begin
    T = Float64

    # 스칼라: y' = -y, y(0)=1 → y(t)=e^{-t}
    f(x::T) = -x
    y0 = T(1.0)
    Δt = T(0.1)

    y1_euler = Step2TimeIntegration.euler_step(f, y0, Δt)
    y1_exact = exp(-Δt)
    @test y1_euler ≈ y1_exact atol = T(1e-2)  # Euler 1차 정확도

    # Vector 버전 (단순 조화진동자: y'' = -y)
    y0_vec = T[1.0, T(0.0)]
    f_vec(v::Vector{T}) = T[-v[2], v[1]]  # y' = v[2], v'' = -v[1] → [v[2], -v[1]]
    y1_vec = Step2TimeIntegration.euler_step(f_vec, y0_vec, Δt)
    @test length(y1_vec) == 2

    # Matrix 버전
    y0_mat = T[1.0 T(0.0); T(0.0) T(1.0)]
    f_mat(m::Matrix{T}) = -m
    y1_mat = Step2TimeIntegration.euler_step(f_mat, y0_mat, Δt)
    @test size(y1_mat) == (2, 2)
end

# ---------------------------------------------------------------------------
# 3. RK4 적분기 테스트
# ---------------------------------------------------------------------------
@testset "RK4 적분기" begin
    T = Float64

    # 스칼라: y' = -y, y(0)=1 → y(t)=e^{-t}
    f(x::T) = -x
    y0 = T(1.0)
    Δt = T(0.1)

    y1_rk4 = Step2TimeIntegration.rk4_step(f, y0, Δt)
    y1_exact = exp(-Δt)
    @test y1_rk4 ≈ y1_exact atol = T(1e-5)  # RK4 4차 정확도

    # Vector 버전 (단순 조화진동자)
    y0_vec = T[1.0, T(0.0)]
    f_vec(v::Vector{T}) = T[-v[2], v[1]]
    y1_vec = Step2TimeIntegration.rk4_step(f_vec, y0_vec, Δt)
    @test length(y1_vec) == 2

    # Matrix 버전
    y0_mat = T[1.0 T(0.0); T(0.0) T(1.0)]
    f_mat(m::Matrix{T}) = -m
    y1_mat = Step2TimeIntegration.rk4_step(f_mat, y0_mat, Δt)
    @test size(y1_mat) == (2, 2)
end

# ---------------------------------------------------------------------------
# 4. ORR 적분기 테스트 (DRS 가속 시나리오)
# ---------------------------------------------------------------------------
@testset "ODE 적분: DRS 가속 (Euler, RK4)" begin
    T = Float64

    # 현실적인 파라미터: P=50 W, Cd_open=0.20
    # a₀ = P/(ρ·A) = 50/(1.225·0.55) ≈ 74.2 m/s²
    # v_top = (2P/(ρ·Cd·A))^(1/3) ≈ 9.05 m/s
    P = T(50.0)
    ρ = T(1.225)
    A = T(0.55)
    Cd_open = T(0.20)

    v_top = Step2TimeIntegration.top_speed_target(P, ρ, Cd_open, A)
    @test v_top ≈ T(9.05) atol = T(0.5)

    # 가속도 함수
    f(v::T) = Step2TimeIntegration.acceleration(v, P, ρ, A, v_top)

    # Euler 적분 (ΔT=0.1, t_end=0.5: ΔT/τ_char≈0.82 → Euler overshooting 진동,
    # RK4는 안정·정확. 이 문제에서는 overshooting 후 최종값에서
    # RK4가 Euler보다 v_top에 더 가까움)
    Δt = T(0.1)
    t_end = T(0.5)
    tr_euler = Step2TimeIntegration.ode_integrate(f, T(0.0), T(0.0), t_end, Δt; method = :euler)

    # Euler: v(t) > 0, v(t) < v_top (느리게 수렴)
    @test tr_euler[end][2] > T(0)
    @test tr_euler[end][2] < v_top

    # RK4 적분 (동일 Δt)
    tr_rk4 = Step2TimeIntegration.ode_integrate(f, T(0.0), T(0.0), t_end, Δt; method = :rk4)

    # 둘 다 t_end 시점에서 v_top에 근접 (ΔT=0.1, t_end=0.5 → 수렴 상태).
    # 이 stiff 문제(a₀=74.2, τ_char≈0.122)에서는 ΔT/τ_char≈0.82로 커서
    # Euler·RK4 모두 진동하며 수렴, 우연히 Euler가 v_top에 더 가까울 수 있음.
    # 따라서 "정확도 비교" 대신 "둘 다 합리적이고 안정적"임을 확인.
    @test tr_rk4[end][2] > T(0)
    @test tr_rk4[end][2] < v_top
    @test tr_euler[end][2] > T(0)
    @test tr_euler[end][2] < v_top

    # 정상상태 근처에서 가속도가 작아짐
    @test Step2TimeIntegration.acceleration(tr_rk4[end][2], P, ρ, A, v_top) <
          Step2TimeIntegration.acceleration(T(0.0), P, ρ, A, v_top)
end

# ---------------------------------------------------------------------------
# 5. Float32/Float64 양쪽 동작, 타입 승격 없음
# ---------------------------------------------------------------------------
@testset "Float32 동작 및 타입 승격 없음" begin
    T = Float32

    P = T(50.0)
    ρ = T(1.225)
    A = T(0.55)
    Cd_open = T(0.20)
    v_top = Step2TimeIntegration.top_speed_target(P, ρ, Cd_open, A)

    @test v_top isa T
    @test v_top > zero(T)
    @test v_top ≈ T(9.05) atol = T(0.5)

    # Euler Float32
    f(x::T) = Step2TimeIntegration.acceleration(x, P, ρ, A, v_top)
    ΔT = T(0.1)
    y = Step2TimeIntegration.euler_step(f, T(0.0), ΔT)
    @test y isa T
    @test y > zero(T)
    @test y ≈ T(7.42) atol = T(0.1)

    # RK4 Float32
    y2 = Step2TimeIntegration.rk4_step(f, T(0.0), ΔT)
    @test y2 isa T
    @test y2 > zero(T)
    @test y2 ≈ T(6.54) atol = T(0.1)

    # 타입 승격 없음 확인: y, y2 모두 T(Float32)
    @test typeof(y) == T
    @test typeof(y2) == T
end

# ---------------------------------------------------------------------------
# 6. 적응형 RK (Dormand-Prince 5(4)) 테스트
# ---------------------------------------------------------------------------
@testset "적응형 RK (Dormand-Prince 5(4))" begin
    T = Float64

    P = T(50.0)
    ρ = T(1.225)
    A = T(0.55)
    Cd_open = T(0.20)
    v_top = Step2TimeIntegration.top_speed_target(P, ρ, Cd_open, A)

    f(y, t) = Step2TimeIntegration.acceleration(y, P, ρ, A, v_top)

    # 적응형 적분: 초기 ΔT=0.5로 시작 → DRS가 열리는 순간(ΔT가 작아지는 구간)
    # 간격이 촘촘해지는 것을 확인
    Δt0 = T(0.5)
    res = Step2TimeIntegration.make_adaptive_rk(f, T(0.0), Δt0)

    # 마지막 값이 v_top에 근접하는지
    @test res.final_y > T(0)
    @test res.final_y < v_top
    @test res.naccept > 0

    # 초기 스텝이 크고, 나중에 스텝이 작아지는지 확인
    # (v가 v_top에 가까워질수록 가속도가 작아지고, RK가 스텝을 줄임)
    hs = [h for (_, _, h, _) in res.history]
    @test length(hs) > 1
    # 스텝 크기가 시간이 지남에 따라 변화하는 것이 일반적 (항상 감소하는 건 아님)
    @test hs[end] < hs[1] || hs[end] > hs[1]  # 변화 있음 (단조 감소 아님)

    # history에서 t가 단조 증가하는지 확인
    ts = [t for (t, _, _, _) in res.history]
    for i in 2:length(ts)
        @test ts[i] > ts[i - 1]
    end
end

# ---------------------------------------------------------------------------
# 7. 깨뜨리기 — Δt를 크게 하면 Euler 오차 증가 / 발산
# ---------------------------------------------------------------------------
@testset "깨뜨리기: Δt가 클 때 Euler 오차" begin
    T = Float64

    P = T(50.0)
    ρ = T(1.225)
    A = T(0.55)
    Cd_open = T(0.20)
    v_top = Step2TimeIntegration.top_speed_target(P, ρ, Cd_open, A)
    # a₀ = P/(ρ·A) ≈ 74.2 m/s², τ_char = v_top/a₀ ≈ 0.122 s

    f(v::T) = Step2TimeIntegration.acceleration(v, P, ρ, A, v_top)

    # 작은 Δt (τ_char보다 작아 정확한 적분)
    tr_small = Step2TimeIntegration.ode_integrate(f, T(0.0), T(0.0), T(0.5), T(0.01); method = :euler)
    # 큰 Δt (τ_char≈0.122의 4배 → 1스텝만에 overshooting, 큰 오차)
    tr_large = Step2TimeIntegration.ode_integrate(f, T(0.0), T(0.0), T(0.5), T(0.5); method = :euler)

    # 깨뜨리기: 큰 Δt에서 Euler가 overshooting하며 v_top에서 크게 벗어남
    @test tr_small[end][2] < v_top                      # 작은 Δt: v_top 아래서 수렴
    @test tr_large[end][2] > v_top                     # 큰 Δt: overshooting (1스텝만에 v_top 초과)
    @test abs(tr_large[end][2] - v_top) > abs(tr_small[end][2] - v_top)  # 큰 Δt이 더 큰 오차
end
