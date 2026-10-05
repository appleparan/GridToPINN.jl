# 2단계 테스트: Euler, RK4, 적응형 DP5(4), DRS 가속 모델.
# 수렴 차수는 간격을 절반으로 줄이며 오차의 로그 기울기를 재서 확인한다.

# 비자율 시험 문제: y' = −2y + t, y(0) = 1
#   정답 y(t) = t/2 − 1/4 + (5/4)·e^{−2t}
ode_f(y, t) = -2 * y .+ t
ode_exact(t::T) where {T} = t / 2 - T(1) / 4 + T(5) / 4 * exp(-2t)

# 조화진동자 y'' = −y 를 [y, y']으로
osc(v, t) = [v[2], -v[1]]

drs_args(T) = (P = T(600_000), m = T(800), ρ = T(1.225), A = T(1.5), Froll = zero(T),
               Cd_closed = T(0.9), Cd_open = T(0.8))

# (f, v0, t0, t1) -> Trajectory 형태의 적분기 대안 세 가지
euler_integrator(Δt) = (f, y0, t0, t1) -> integrate(euler_step, f, y0, t0, t1, Δt)
rk4_integrator(Δt) = (f, y0, t0, t1) -> integrate(rk4_step, f, y0, t0, t1, Δt)
adaptive_integrator(Δt0, rtol) = (f, y0, t0, t1) -> integrate_adaptive(f, y0, t0, t1, Δt0; rtol = rtol)

run_drs(integrator, a, t_open, t_end) =
    drs_run(integrator, a.P, a.m, a.ρ, a.A, a.Froll, a.Cd_closed, a.Cd_open, t_open, t_end)

@testset "step2 fixed-step integrators" begin
    for T in (Float32, Float64)
        @testset "$T 스칼라/Vector/Matrix, 타입 유지" begin
            Δt = T(0.1)
            t0 = zero(T)
            for step in (euler_step, rk4_step)
                # 스칼라
                y1 = @inferred step(ode_f, T(1), t0, Δt)
                @test y1 isa T
                # Vector: 조화진동자 y'' = −y
                v1 = @inferred step(osc, T[1, 0], t0, Δt)
                @test v1 isa Vector{T}
                # Matrix
                M1 = @inferred step((m, t) -> -m, T[1 0; 0 2], t0, Δt)
                @test M1 isa Matrix{T}
                @test size(M1) == (2, 2)
            end
            # y' = −y 한 걸음의 정확도
            @test euler_step((y, t) -> -y, T(1), t0, Δt) == T(0.9)
            @test rk4_step((y, t) -> -y, T(1), t0, Δt) ≈ exp(-Δt) atol = T(2e-6)   # 국소 절단오차 ≈ 8e-8
            # Matrix의 각 성분이 독립적으로 전진한다
            M = rk4_step((m, t) -> -m, T[1 0; 0 2], t0, Δt)
            @test M ≈ T[1 0; 0 2] .* exp(-Δt) atol = T(2e-6)

            tr = @inferred integrate(rk4_step, ode_f, T(1), t0, T(1), Δt)
            @test tr isa Trajectory{T,T}
            @test length(tr.t) == length(tr.y) == 11
            @test tr.t[1] == t0
            @test tr.t[end] ≈ T(1) atol = 10eps(T)
            @test tr.y[end] ≈ ode_exact(tr.t[end]) atol = T(1e-4)   # 전역 절단오차 ≈ 5e-6
            trm = integrate(rk4_step, (m, t) -> -m, T[1 0; 0 2], t0, T(1), Δt)
            @test trm isa Trajectory{T,Matrix{T}}
            @test trm.y[end] isa Matrix{T}
        end
    end

    # 수렴 차수 (Float64): Δt = 0.1 → 0.05 → 0.025 → 0.0125, t = 1에서의 오차
    Δts = [0.1 / 2^k for k in 0:3]
    err(step, Δt) = abs(integrate(step, ode_f, 1.0, 0.0, 1.0, Δt).y[end] - ode_exact(1.0))
    p_euler = [log2(err(euler_step, Δts[k]) / err(euler_step, Δts[k + 1])) for k in 1:3]
    p_rk4 = [log2(err(rk4_step, Δts[k]) / err(rk4_step, Δts[k + 1])) for k in 1:3]
    @test all(isapprox.(p_euler, 1; atol = 0.1))   # Euler 1차
    @test all(isapprox.(p_rk4, 4; atol = 0.2))     # RK4 4차

    # Vector에서도 같은 차수: 조화진동자, 정답 (cos t, −sin t)
    errv(step, Δt) = maximum(abs, integrate(step, osc, [1.0, 0.0], 0.0, 1.0, Δt).y[end] .-
                                  [cos(1.0), -sin(1.0)])
    @test log2(errv(rk4_step, 0.1) / errv(rk4_step, 0.05)) ≈ 4 atol = 0.2
    @test log2(errv(euler_step, 0.01) / errv(euler_step, 0.005)) ≈ 1 atol = 0.1
end

@testset "step2 adaptive Dormand–Prince" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            y, e = @inferred rk45_step(ode_f, T(1), zero(T), T(0.1))
            @test y isa T
            @test e isa T
            @test y ≈ ode_exact(T(0.1)) atol = T(1e-6)   # 국소 절단오차 ≈ 2e-8
            yv, ev = @inferred rk45_step(osc, T[1, 0], zero(T), T(0.1))
            @test yv isa Vector{T}
            @test ev isa T
            ym, em = @inferred rk45_step((m, t) -> -m, T[1 0; 0 2], zero(T), T(0.1))
            @test ym isa Matrix{T}
            @test em isa T

            tr = @inferred integrate_adaptive(ode_f, T(1), zero(T), T(2), T(0.5))
            @test tr isa Trajectory{T,T}
            @test tr.t[end] == T(2)                    # 마지막 걸음은 t_end에 정확히 맞춘다
            @test all(diff(tr.t) .> 0)
            @test tr.y[end] ≈ ode_exact(T(2)) atol = T(1e-4)
            trv = @inferred integrate_adaptive(osc, T[1, 0], zero(T), T(3), T(0.5))
            @test trv isa Trajectory{T,Vector{T}}
            @test trv.y[end] ≈ T[cos(T(3)), -sin(T(3))] atol = T(1e-4)
            trm = integrate_adaptive((m, t) -> -m, T[1 0; 0 2], zero(T), T(1), T(0.5))
            @test trm.y[end] isa Matrix{T}
            @test trm.y[end] ≈ T[1 0; 0 2] .* exp(-T(1)) atol = T(1e-4)
        end
    end

    # 한 걸음의 국소 오차는 O(Δt⁶): Δt를 절반으로 줄이면 오차 1/64 (Float64, y' = −y)
    local_err(Δt) = abs(rk45_step((y, t) -> -y, 1.0, 0.0, Δt)[1] - exp(-Δt))
    p_local = [log2(local_err(0.4 / 2^k) / local_err(0.4 / 2^(k + 1))) for k in 0:2]
    @test all(isapprox.(p_local, 6; atol = 0.3))

    # 추정 오차는 실제 4차-5차 차이다: 실제 국소 오차보다 크다 (보수적)
    y5, est = rk45_step((y, t) -> -y, 1.0, 0.0, 0.4)
    @test est > abs(y5 - exp(-0.4))

    # 허용오차를 줄이면 전체 오차가 따라 줄어든다 (전역 오차 ∝ rtol^p, p ≈ 1)
    rtols = [1e-4, 1e-6, 1e-8, 1e-10]
    errs = [abs(integrate_adaptive(ode_f, 1.0, 0.0, 5.0, 0.1; rtol = r).y[end] - ode_exact(5.0))
            for r in rtols]
    @test issorted(errs; rev = true)
    @test all(errs .< 100 .* rtols)                 # 허용오차의 100배 안
    slope = log10(errs[1] / errs[end]) / log10(rtols[1] / rtols[end])
    @test 0.6 < slope < 1.4
    # 허용오차가 작을수록 걸음 수는 늘어난다 (DP5: 걸음 수 ∝ rtol^(−1/5))
    nsteps(r) = length(integrate_adaptive(ode_f, 1.0, 0.0, 5.0, 0.1; rtol = r).t) - 1
    @test nsteps(1e-10) > nsteps(1e-4)

    # 깨뜨리기: maxsteps가 모자라면 예외 없이 거기까지의 기록을 돌려준다
    short = integrate_adaptive(ode_f, 1.0, 0.0, 5.0, 0.1; rtol = 1e-10, maxsteps = 3)
    @test short.t[end] < 5.0
end

@testset "step2 DRS physics" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            a = drs_args(T)
            v_closed = top_speed(a.P, a.ρ, a.Cd_closed, a.A, a.Froll)
            v_open = top_speed(a.P, a.ρ, a.Cd_open, a.A, a.Froll)

            # 가속도: 최고속도에서 0, 느리면 +, 빠르면 −, 단위는 m/s²
            acc(v, Cd) = acceleration(v, a.P, a.m, a.ρ, Cd, a.A, a.Froll)
            @test @inferred(acc(v_closed, a.Cd_closed)) isa T
            @test abs(acc(v_closed, a.Cd_closed)) < T(1e-3)
            @test acc(v_closed / 2, a.Cd_closed) > 0
            @test acc(v_closed * T(1.1), a.Cd_closed) < 0
            # 닫힘 최고속도에서 Cd를 열림으로 바꾸면 가속이 생긴다 (≈ 0.93 m/s²)
            @test acc(v_closed, a.Cd_open) ≈ T(0.93) atol = T(0.02)
            @test @inferred(drs_acceleration(v_closed, T(1), a.P, a.m, a.ρ, a.A, a.Froll,
                                             a.Cd_closed, a.Cd_open, T(5))) == acc(v_closed, a.Cd_closed)
            @test drs_acceleration(v_closed, T(6), a.P, a.m, a.ρ, a.A, a.Froll,
                                   a.Cd_closed, a.Cd_open, T(5)) == acc(v_closed, a.Cd_open)

            t_open, t_end = T(10), T(60)
            for integrator in (rk4_integrator(T(0.1)), adaptive_integrator(T(1), T(1) / 1_000_000))
                tr = @inferred run_drs(integrator, a, t_open, t_end)
                @test tr isa Trajectory{T,T}
                @test tr.y[1] == v_closed                  # 닫힘 최고속도에서 출발 (1단계 답)
                # t_open 전에는 그 속도를 유지한다
                before = tr.y[tr.t .< t_open - T(0.2)]
                @test length(before) > 2
                @test all(abs.(before .- v_closed) .< 1000eps(T) * v_closed)
                # 이후 1단계의 열림 최고속도로 수렴한다
                @test tr.y[end] ≈ v_open atol = T(0.01)
                @test issorted(tr.y[tr.t .>= t_open + T(0.5)])  # 열린 뒤 단조 증가
            end
        end
    end

    # 적응형 간격: DRS가 열리기 전 크고, 열린 직후 줄고, 정상상태에 다가가며 다시 커진다 (Float64)
    a = drs_args(Float64)
    t_open, t_end = 20.0, 80.0
    tr = run_drs(adaptive_integrator(0.1, 1e-6), a, t_open, t_end)
    h = diff(tr.t)
    tm = tr.t[2:end]                                    # 각 걸음이 끝나는 시각
    h_before = maximum(h[tm .< t_open - 1])             # 정상상태 구간에서 간격이 자라 있다
    h_just_after = minimum(h[(tm .>= t_open) .& (tm .< t_open + 2)])
    h_late = maximum(h[tm .> t_open + 30])
    @test h_before > 5                                  # 정상상태: 가속도가 0이라 간격이 크다
    @test h_just_after < h_before / 10                  # 열린 직후 10배 넘게 줄어든다
    @test h_late > 5 * h_just_after                     # 다시 커진다
    # 정상상태에서 간격이 커졌다가 열리는 순간 줄었다가 돌아오는 순서
    i_min = argmin(h[tm .>= t_open]) + count(tm .< t_open)
    @test h[i_min] == h_just_after
    @test maximum(h[1:(i_min - 1)]) > h[i_min]
    @test maximum(h[(i_min + 1):end]) > h[i_min]

    # 깨뜨리기: Δt가 너무 크면 Euler는 진동하며 발산한다 (안정 한계 Δt < 2/λ ≈ 7.6 s)
    v_open = top_speed(a.P, a.ρ, a.Cd_open, a.A, a.Froll)
    bad = run_drs(euler_integrator(10.0), a, 5.0, 100.0)
    gaps = bad.y[3:8] .- v_open                         # 열린 뒤 첫 걸음들
    @test all(sign.(gaps[1:(end - 1)]) .!= sign.(gaps[2:end]))       # 부호가 번갈아 바뀐다
    @test all(abs.(gaps[2:end]) .> abs.(gaps[1:(end - 1)]))           # 진폭이 커진다
    @test !(abs(bad.y[end] - v_open) < 1)                              # 끝내 수렴하지 못한다
    # 간격을 충분히 줄이면 Euler도 수렴한다
    ok = run_drs(euler_integrator(0.1), a, 5.0, 100.0)
    @test ok.y[end] ≈ v_open atol = 0.01
    # RK4도 같은 큰 Δt에서는 정확도를 잃지만 Euler처럼 진동하지는 않는다
    @test abs(run_drs(rk4_integrator(2.0), a, 5.0, 100.0).y[end] - v_open) < 0.01
end

@testset "step2 settling_time" begin
    for T in (Float32, Float64)
        a = drs_args(T)
        v_open = top_speed(a.P, a.ρ, a.Cd_open, a.A, a.Froll)
        t_open, t_end = T(10), T(80)
        rk = run_drs(rk4_integrator(T(0.05)), a, t_open, t_end)
        ad = run_drs(adaptive_integrator(T(1), T(1) / 1_000_000), a, t_open, t_end)
        for fraction in (T(0.5), T(0.9), T(0.99))
            s_rk = @inferred settling_time(rk, v_open, fraction)
            s_ad = settling_time(ad, v_open, fraction)
            @test s_rk isa T
            @test s_rk > t_open                              # 열린 뒤에야 도달
            @test s_ad ≈ s_rk rtol = T(0.04)                 # 두 적분기의 값이 일치
        end
        # 더 높은 비율에는 더 오래 걸린다
        @test settling_time(rk, v_open, T(0.5)) < settling_time(rk, v_open, T(0.9)) <
              settling_time(rk, v_open, T(0.99))
        # 한 번도 닿지 못하면 Inf
        short = run_drs(rk4_integrator(T(0.05)), a, t_open, t_open + 1)
        @test settling_time(short, v_open, T(0.99)) == T(Inf)
    end
end
