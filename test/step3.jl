# 3단계 테스트: 확산 연산자, 정답(erfc, Stokes, sin 모드), 시간 적분 세 가지(Euler, RK4, CN),
# 그리고 "깨뜨리기"(안정 한계, 삼단 서사, CN 링).

# 같은 격자의 sin 모드를 step으로 nsteps 전진한 뒤의 장
function run_sin(step, N, α::T, Δt::T, nsteps) where {T}
    sim = sin_mode(N, α)
    advance!(step, sim, Δt, nsteps)
    return sim
end

@testset "step3 operators" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            α = T(0.01)
            N = 10
            dx = T(1) / N
            u = [sin(T(π) * (i - 1) * dx) for i in 1:(N + 1)]

            du = @inferred diffusion_rhs_dirichlet(u, α, dx)
            @test du isa Vector{T}
            # sin(πy)는 이산 라플라시안의 고유벡터: du = λ_h·u, λ_h = −(4α/dx²)·sin²(π·dx/2)
            λ_h = -(4α / dx^2) * sin(T(π) * dx / 2)^2
            @test du[2:N] ≈ λ_h .* u[2:N] rtol = 100eps(T)
            @test du[1] == 0           # Dirichlet: 끝점은 고정
            @test du[N + 1] == 0

            n = 10
            dxp = T(0.1)
            up = [sin(2 * T(π) * i / n) for i in 1:n]
            dup = @inferred diffusion_rhs_periodic(up, α, dxp)
            @test dup isa Vector{T}
            λ_p = -(4α / dxp^2) * sin(T(π) / n)^2
            @test dup ≈ λ_p .* up rtol = 1000eps(T) atol = 100eps(T)
        end
    end

    # 연산자의 수렴 차수: |λ_h − λ| = α·π⁴·dx²/12 → 격자 2배 → 오차 1/4 (Float64)
    α = 0.01
    λ = -α * π^2
    λerr(N) = abs(-(4α * N^2) * sin(π / (2N))^2 - λ)
    @test log2(λerr(10) / λerr(20)) ≈ 2 atol = 0.05
    @test log2(λerr(20) / λerr(40)) ≈ 2 atol = 0.05
end

@testset "step3 exact solutions" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            tol = T == Float32 ? T(2e-6) : T(2e-7)       # A&S 7.1.26의 오차 한계
            ref = Dict(0.0 => 1.0, 0.5 => 0.4795001221869535, 1.0 => 0.15729920705028513,
                       2.0 => 0.004677734981047265)
            for (x, e) in ref
                @test @inferred(erfc_approx(T(x))) isa T
                @test erfc_approx(T(x)) ≈ T(e) atol = tol
                @test erfc_approx(-T(x)) ≈ 2 - T(e) atol = tol
            end

            # 확산 깊이: 꿀이 물보다 √(ν_꿀/ν_물) = √2000 ≈ 44.7배 깊다
            ν_w, ν_h, t = T(1e-6), T(2e-3), T(1)
            δ_w = @inferred diffusion_depth(ν_w, t)
            δ_h = diffusion_depth(ν_h, t)
            @test δ_w isa T
            @test δ_w ≈ T(2e-3) rtol = 10eps(T)
            @test δ_h ≈ T(0.0894427191) rtol = max(10eps(T), T(1e-8))   # 참고값은 10자리
            @test δ_h / δ_w ≈ sqrt(T(2000)) rtol = 100eps(T)

            # Stokes 1종: 깊이 δ에서 벽 속도의 erfc(1) ≈ 16 %
            U = T(2)
            @test @inferred(stokes_first_solution(δ_w, t, U, ν_w)) isa T
            @test stokes_first_solution(δ_w, t, U, ν_w) ≈ U * T(0.15729920705028513) atol = 2tol
            @test stokes_first_solution(zero(T), t, U, ν_w) ≈ U atol = tol
            # t = 0: 예외 없이 극한값 (벽면 U, 그 아래 0)
            @test stokes_first_solution(zero(T), zero(T), U, ν_w) == U
            @test stokes_first_solution(T(0.01), zero(T), U, ν_w) == 0

            # sin 모드
            @test @inferred(sin_mode_initial(T(0.5))) isa T
            @test sin_mode_initial(T(0.5)) ≈ 1 atol = 4eps(T)
            @test @inferred(sin_mode_exact(T(0.5), T(1), T(0.01))) isa T
            @test sin_mode_exact(T(0.5), T(1), T(0.01)) ≈ exp(-T(0.01) * T(π)^2) rtol = 100eps(T)
            @test sin_mode_exact(T(0.3), zero(T), T(0.01)) ≈ sin_mode_initial(T(0.3))
        end
    end
end

@testset "step3 convergence orders" begin
    α, t_end = 0.01, 1.0

    # 공간 2차 (RK4, Δt = 1e-3: 시간 오차는 무시할 만큼 작다)
    errs = [sin_mode_error(run_sin(diffusion_rk4_step, N, α, 1e-3, 1000)) for N in (25, 50, 100)]
    p_space = [log2(errs[k] / errs[k + 1]) for k in 1:2]
    @test all(isapprox.(p_space, 2; atol = 0.15))

    # 시간 오차만 따로 보려고 같은 격자(N=20)의 매우 작은 Δt RK4를 기준해로 삼는다
    ref = run_sin(diffusion_rk4_step, 20, α, 2e-3, 500).u
    time_err(step, Δt) = max_abs(run_sin(step, 20, α, Δt, round(Int, t_end / Δt)).u .- ref)

    # 시간 1차 (Euler)
    e_euler = [time_err(diffusion_euler_step, Δt) for Δt in (0.1, 0.05, 0.025)]
    @test all(isapprox.([log2(e_euler[k] / e_euler[k + 1]) for k in 1:2], 1; atol = 0.2))

    # 시간 2차 (Crank–Nicolson)
    e_cn = [time_err(diffusion_cn_step, Δt) for Δt in (0.2, 0.1, 0.05)]
    @test all(isapprox.([log2(e_cn[k] / e_cn[k + 1]) for k in 1:2], 2; atol = 0.1))

    # 같은 Δt에서 RK4는 Euler보다 훨씬 정확하다. 4차는 안정 한계(Δt ≤ 0.696·dx²/α)에 가려
    # 직접 보기 어렵다 — 그래서 음해법이 필요하다.
    @test time_err(diffusion_rk4_step, 0.1) < e_euler[1] / 10
end

@testset "step3 simulation state" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            sim = @inferred sin_mode(20, T(0.01))
            @test sim isa Diffusion1D{T}
            @test length(sim.u) == 21
            @test sim.dx == T(1) / 20
            @test sim.t == 0
            @test sim.u[1] == 0
            @test sim.u[11] ≈ 1 atol = 4eps(T)
            @test sin_mode_error(sim) < 4eps(T)
            for step in (diffusion_euler_step, diffusion_rk4_step, diffusion_cn_step)
                s = sin_mode(20, T(0.01))
                t = @inferred advance!(step, s, T(0.05), 10)
                @test t isa T
                @test t ≈ T(0.5) atol = 10eps(T)
                @test s.t == t
                @test s.u isa Vector{T}
                @test s.u[1] == 0           # 경계 고정
                @test s.u[end] == sin_mode_initial(one(T))   # 끝점도 초기값 그대로
                @test @inferred(max_abs(s.u)) isa T
                @test @inferred(sin_mode_error(s)) isa T
                @test sin_mode_error(s) < T(2e-3)             # 합리적 정확도 (N=20)
            end

            w = @inferred moving_wall(100, T(0.02), T(2), T(1e-6))
            @test w isa Diffusion1D{T}
            @test length(w.u) == 101
            @test w.u[1] == 2
            @test all(w.u[2:end] .== 0)
            @test w.dx ≈ T(0.02) / 100
            @test w.α == T(1e-6)
            @test @inferred(moving_wall_error(w, T(2))) isa T
            @test moving_wall_error(w, T(2)) == 0            # t = 0의 극한 정답과 일치
        end
    end
    # 한 대안이 같은 서명을 가진다: step(u, t, Δt, α, dx) -> u_new
    u = sin_mode(20, 0.01).u
    for step in (diffusion_euler_step, diffusion_rk4_step, diffusion_cn_step)
        @test step(u, 0.0, 0.01, 0.01, 0.05) isa Vector{Float64}
    end
end

@testset "step3 moving wall: water vs honey" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            U, t = T(1), T(1)
            ν_water, ν_honey = T(1e-6), T(2e-3)
            δ_water = diffusion_depth(ν_water, t)
            δ_honey = diffusion_depth(ν_honey, t)
            # 질문의 답: 꿀이 √2000 ≈ 44.7배 깊이 끌려온다
            @test δ_honey / δ_water ≈ sqrt(T(2000)) rtol = 100eps(T)

            # 물: y ∈ [0, 0.02] m, δ = 2 mm를 20칸으로. RK4 한계 Δt ≤ 6.96e-3 s
            w = moving_wall(200, T(0.02), U, ν_water)
            advance!(diffusion_rk4_step, w, T(1e-3), 1000)
            @test w.t ≈ t atol = 1000eps(T)
            @test w.u[1] == U
            @test all(diff(w.u) .<= 100eps(T))                  # 단조 감소 (최대원리)
            idx = round(Int, δ_water / w.dx) + 1
            @test w.u[idx] ≈ U * T(0.15729920705028513) atol = T(0.02)
            @test moving_wall_error(w, U) < T(0.05)

            # 꿀: y ∈ [0, 0.5] m, δ = 8.9 cm를 36칸으로. RK4 한계 Δt ≤ 2.17e-3 s
            h = moving_wall(200, T(0.5), U, ν_honey)
            advance!(diffusion_rk4_step, h, T(5e-4), 2000)
            @test h.u[1] == U
            idx = round(Int, δ_honey / h.dx) + 1
            @test h.u[idx] ≈ U * T(0.15729920705028513) atol = T(0.02)
            @test moving_wall_error(h, U) < T(0.05)
        end
    end
end

@testset "step3 breaking: stability limits" begin
    α = 0.01
    N = 20
    dx = 1 / N
    limit = dx^2 / (2α)                          # 명시적 Euler 안정 한계
    @test limit ≈ 0.125 rtol = 1e-12

    # 한계 이하: 안정. 최대값이 초기 최대를 넘지 않는다 (최대원리)
    s = run_sin(diffusion_euler_step, N, α, 0.9 * limit, 40)
    @test max_abs(s.u) <= 1 + 1e-9

    # 한계의 4배: Euler 발산
    @test max_abs(run_sin(diffusion_euler_step, N, α, 4 * limit, 30).u) > 1e6
    # RK4도 발산 (한계 0.696·dx²/α는 Euler의 1.39배일 뿐)
    @test max_abs(run_sin(diffusion_rk4_step, N, α, 4 * limit, 30).u) > 1e6
    # RK4는 한계의 1.2배까지는 안정, Euler는 이미 발산
    @test max_abs(run_sin(diffusion_rk4_step, N, α, 1.2 * limit, 40).u) <= 1 + 1e-9
    @test max_abs(run_sin(diffusion_euler_step, N, α, 1.2 * limit, 200).u) > 1e6

    # 발산은 예외가 아니라 큰 숫자다 (Float32도 마찬가지)
    s32 = sin_mode(N, Float32(α))
    advance!(diffusion_euler_step, s32, Float32(4 * limit), 400)
    @test !(max_abs(s32.u) < 1)

    # 점성이 크면 한계 Δt ∝ 1/α: 같은 격자에서 꿀은 물보다 2000배 촘촘해야 한다
    lim_water = dx^2 / (2 * 1e-6)
    lim_honey = dx^2 / (2 * 2e-3)
    @test lim_water / lim_honey ≈ 2000 rtol = 1e-12
end

@testset "step3 breaking: smooth → latent → blow-up" begin
    # 매끄러운 sin(πy)에 눈에 안 보이는 고주파 섭동 1e-3·sin(9πy)를 얹고 Δt = 0.3 (한계의 2.4배)
    #   스텝 1–25: 매끄러운 해가 정상 감쇠 (0.97 → 0.47)
    #   스텝 26–27: 고주파 잔재가 이기기 시작 (0.47 → 0.51)
    #   스텝 28–30: 톱니(sawtooth) 발산 (0.80 → 2.08 → 6.65)
    α, N = 0.01, 20
    dx = 1 / N
    perturbed() = begin
        s = sin_mode(N, α)
        s.u .+= 1e-3 .* sin.(9π .* (0:N) .* dx)
        s
    end
    Δt = 0.3
    limit = dx^2 / (2α)
    @test Δt / limit ≈ 2.4 rtol = 1e-3

    s = perturbed()
    hist = [max_abs(s.u)]
    for _ in 1:30
        advance!(diffusion_euler_step, s, Δt, 1)
        push!(hist, max_abs(s.u))
    end
    @test 0.4 < hist[26] < 0.5                      # 1) 25스텝 후까지 매끄럽게 감쇠
    @test argmin(hist) == 26                         # 2) 전환점, 이후 반등
    @test hist[end] > 6                              # 3) 발산
    @test hist[end] ≈ 6.645961359408092 rtol = 1e-6
    @test sign(s.u[2]) != sign(s.u[3])               # 프로파일이 톱니: 인접 값 부호 반대
    @test sign(s.u[10]) != sign(s.u[11])

    # 같은 조건에서 CN은 정상: 발산하지 않고 해석해와 일치
    c = perturbed()
    advance!(diffusion_cn_step, c, Δt, 30)
    @test max_abs(c.u) < 0.5
    exact = [sin_mode_exact(i * dx, c.t, α) for i in 0:N]
    @test max_abs(c.u .- exact) < 1e-3

    # RK4도 같은 조건에서 발산
    r = perturbed()
    advance!(diffusion_rk4_step, r, Δt, 30)
    @test max_abs(r.u) > 1e6
end

@testset "step3 implicit: Crank–Nicolson" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            α, N = T(0.01), 20
            dx = T(1) / N
            u0 = sin_mode(N, α).u
            u1 = @inferred crank_nicolson_step(u0, T(0.1), α, dx)
            @test u1 isa Vector{T}
            @test length(u1) == length(u0)
            @test u1[1] == u0[1]
            @test u1[end] == u0[end]
            # 경계가 아닌 점의 크기 감소: 한 걸음에 sin 모드가 약 e^{−απ²Δt}
            @test u1[11] ≈ u0[11] * exp(-α * T(π)^2 * T(0.1)) rtol = T(1e-3)

            # 무조건 안정: 명시적 Euler 한계(0.125)의 8배(Δt = 1)에서도 발산하지 않는다
            s = sin_mode(N, α)
            advance!(diffusion_cn_step, s, T(1), 20)
            @test max_abs(s.u) <= 1 + 100eps(T)
            # 큰 Δt에서도 합리적 정확도 (시간 오차 O(Δt²))
            s = sin_mode(N, α)
            advance!(diffusion_cn_step, s, T(0.5), 2)
            @test sin_mode_error(s) < T(1e-3)

            # 점이 3개 이하일 때도 예외 없이 그대로 돌려준다
            @test crank_nicolson_step(T[1, 2], T(0.1), α, dx) == T[1, 2]
        end
    end
end

@testset "step3 breaking: CN rings" begin
    # 발산하지는 않지만 최대원리가 깨진다: 부호가 번갈아 나오는 링(음수 값)
    α, N = 0.01, 20
    dx = 1 / N
    limit = dx^2 / (2α)
    spike() = (s = sin_mode(N, α); s.u .= 0; s.u[2] = 1; s)

    # Euler와 RK4는 한계의 8배(Δt = 1)에서 10스텝 만에 발산
    e = spike(); advance!(diffusion_euler_step, e, 8 * limit, 10)
    @test max_abs(e.u) > 1e6
    r = spike(); advance!(diffusion_rk4_step, r, 8 * limit, 10)
    @test max_abs(r.u) > 1e6

    # CN은 같은 Δt에서 발산하지 않는다 (모든 모드 증폭률 |g| ≤ 1)
    c = spike(); advance!(diffusion_cn_step, c, 8 * limit, 11)
    @test max_abs(c.u) <= 1 + 1e-6
    # 하지만 음의 링이 생긴다: "발산하지 않을 뿐" 해가 틀어질 수 있다
    @test minimum(c.u) < 0
end
