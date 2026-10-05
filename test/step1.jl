# 1단계 테스트: 이중수, 미분 세 가지, Newton법, DRS 최고속도.
# 모든 커널을 Float32와 Float64에서 시험하고, 결과 타입이 T로 유지되는지 확인한다.

# 대표값 (src/step1/drs.jl 머리말의 가정과 같다)
drs_params(T) = (P = T(600_000), ρ = T(1.225), A = T(1.5), Cd_closed = T(0.9), Cd_open = T(0.8))

# 반으로 줄여 가는 h에서 오차의 로그 기울기 log2(e_k / e_{k+1})
slopes(errs) = [log2(errs[k] / errs[k + 1]) for k in 1:(length(errs) - 1)]

@testset "step1 Dual" begin
    for T in (Float32, Float64)
        a = Dual(T(3), T(1))
        b = Dual(T(2), T(0.5))
        @testset "$T" begin
            @test (a + b) == Dual(T(5), T(1.5))
            @test (a - b) == Dual(T(1), T(0.5))
            @test (a * b) == Dual(T(6), T(3) * T(0.5) + T(2) * T(1))      # 곱의 미분
            @test (a / b).val == T(3) / T(2)
            @test (a / b).der ≈ (T(1) * T(2) - T(3) * T(0.5)) / T(4)      # 몫의 미분
            @test (-a) == Dual(T(-3), T(-1))
            @test a^2 == Dual(T(9), T(6))
            @test a^3 == Dual(T(27), T(27))
            # 상수와의 연산: 상수의 미분은 0
            @test (a + 1) == Dual(T(4), T(1))
            @test (1 + a) == Dual(T(4), T(1))
            @test (a - 1) == Dual(T(2), T(1))
            @test (1 - a) == Dual(T(-2), T(-1))
            @test (2 * a) == Dual(T(6), T(2))
            @test (a * 2) == Dual(T(6), T(2))
            @test (a / 2) == Dual(T(1.5), T(0.5))
            @test (6 / a).val == T(2)
            @test (6 / a).der == T(-6) / T(9)
            # 타입이 T로 유지된다
            @test @inferred(a + b) isa Dual{T}
            @test @inferred(a * b) isa Dual{T}
            @test @inferred(a / b) isa Dual{T}
            @test @inferred(a^2) isa Dual{T}
            @test @inferred(T(2) * a + 1) isa Dual{T}
            @test @inferred(1 / a) isa Dual{T}
        end
    end
end

@testset "step1 derivatives" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            f(x) = x^3 + 2 * x^2 + x
            df(x) = 3 * x^2 + 4 * x + 1
            for x in (T(0.5), T(1), T(2), T(-1))
                @test @inferred(derivative_dual(f, x)) isa T
                @test derivative_dual(f, x) ≈ df(x) rtol = 4eps(T)   # 이중수는 반올림 수준으로 정확
                @test @inferred(derivative_forward(f, x, T(0.01))) isa T
                @test @inferred(derivative_central(f, x, T(0.01))) isa T
            end
            # 몫 규칙도 이중수가 따라간다
            g(x) = 1 / (1 + x * x)
            @test derivative_dual(g, T(1)) ≈ T(-0.5) rtol = 4eps(T)
        end
    end

    # 수렴 차수 (Float64, f = exp, x = 1): h를 절반씩 줄일 때 오차의 로그 기울기
    hs = [Float64(2)^(-k) for k in 3:8]
    errs_f = [abs(derivative_forward(exp, 1.0, h) - exp(1.0)) for h in hs]
    errs_c = [abs(derivative_central(exp, 1.0, h) - exp(1.0)) for h in hs]
    @test all(isapprox.(slopes(errs_f), 1; atol = 0.1))   # 전진차분 1차
    @test all(isapprox.(slopes(errs_c), 2; atol = 0.1))   # 중심차분 2차
    @test all(errs_c .< errs_f)

    # 깨뜨리기: h를 너무 줄이면 반올림오차가 이긴다. 오차가 최소인 h는 Float32가 훨씬 크다.
    hs = [Float64(10)^(-k / 2) for k in 2:30]
    best_h(T) = hs[argmin([abs(derivative_central(exp, T(1), T(h)) - exp(T(1))) for h in hs])]
    errs64 = [abs(derivative_central(exp, 1.0, h) - exp(1.0)) for h in hs]
    @test argmin(errs64) < length(hs)               # 끝(가장 작은 h)이 최선이 아니다
    @test errs64[end] > 100 * minimum(errs64)       # 너무 작은 h에서 오차가 다시 커진다
    @test best_h(Float32) > 10 * best_h(Float64)
end

@testset "step1 newton" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            f(x) = x^2 - 2
            df(x) = 2 * x
            xs = @inferred newton_iterates(f, df, T(1))
            @test xs isa Vector{T}
            @test xs[1] == T(1)                      # x0가 첫 원소
            @test last(xs) ≈ sqrt(T(2)) rtol = 4eps(T)
            @test @inferred(newton(f, df, T(1))) == last(xs)
            @test newton(f, df, T(1)) isa T
            # 조금 가다 멈추는 maxiter
            @test length(newton_iterates(f, df, T(1); maxiter = 2)) == 3
        end
    end

    # 제곱 수렴 (Float64): e_{n+1} / e_n² → f''/(2f') = 1/(2√2)
    xs = newton_iterates(x -> x^2 - 2, x -> 2x, 1.0)
    errs = abs.(xs .- sqrt(2.0))
    for n in 2:3
        @test errs[n + 1] / errs[n]^2 ≈ 1 / (2 * sqrt(2.0)) rtol = 0.15
    end
    # 자릿수가 매 반복마다 대략 두 배가 된다
    @test log10(errs[3]) / log10(errs[2]) > 1.7

    # 깨뜨리기: f'(x0) = 0이면 예외 없이 비유한 수가 나온다
    xs = newton_iterates(x -> x^2 - 2, x -> 2x, 0.0)
    @test !isfinite(last(xs))
    # 수렴하지 못하는 경우: maxiter까지 돌고 마지막 값을 돌려준다 (예외 없음)
    xs = newton_iterates(x -> x^2 + 1, x -> 2x, 0.5; maxiter = 10)
    @test length(xs) == 11
end

@testset "step1 DRS" begin
    for T in (Float32, Float64)
        @testset "$T" begin
            p = drs_params(T)
            tol = 1000eps(T)

            # 정답: 구름저항 0이면 해석해 (2P/(ρ Cd A))^(1/3)
            v_an = @inferred top_speed_analytic(p.P, p.ρ, p.Cd_closed, p.A)
            v_nt = @inferred top_speed(p.P, p.ρ, p.Cd_closed, p.A, zero(T))
            @test v_an isa T && v_nt isa T
            @test v_nt ≈ v_an rtol = tol
            @test v_nt ≈ T(89.86) atol = T(0.01)          # 닫힘 최고속도 ≈ 89.86 m/s
            @test abs(power_balance(v_nt, p.P, p.ρ, p.Cd_closed, p.A, zero(T))) < tol * p.P

            # DRS: 열림 최고속도가 더 높다
            v_open = top_speed(p.P, p.ρ, p.Cd_open, p.A, zero(T))
            gain = @inferred drs_gain(p.P, p.ρ, p.A, zero(T), p.Cd_closed, p.Cd_open)
            @test gain isa T
            @test v_open ≈ T(93.46) atol = T(0.01)
            @test gain ≈ v_open - v_nt rtol = tol
            @test gain > 3

            # 구름저항이 있으면 최고속도가 낮아지고 (해석해 없음) 잔차는 0
            Froll = T(300)
            v_roll = top_speed(p.P, p.ρ, p.Cd_closed, p.A, Froll)
            @test v_roll < v_nt
            @test abs(power_balance(v_roll, p.P, p.ρ, p.Cd_closed, p.A, Froll)) < tol * p.P

            # 손 유도 f'는 이중수 자동미분과 같다
            f = v -> power_balance(v, p.P, p.ρ, p.Cd_closed, p.A, Froll)
            @test power_balance_derivative(v_roll, p.ρ, p.Cd_closed, p.A, Froll) ≈
                  derivative_dual(f, v_roll) rtol = 4eps(T)
            @test @inferred(drag_force(v_roll, p.ρ, p.Cd_closed, p.A)) isa T
            @test @inferred(resistance(v_roll, p.ρ, p.Cd_closed, p.A, Froll)) isa T

            # 대안 지점: 미분 방법을 바꿔도 같은 최고속도에 도달한다
            h = sqrt(eps(T)) * 10
            v0 = v_an
            for deriv in (derivative_dual,
                          (f, v) -> derivative_central(f, v, h * 100),
                          (f, v) -> derivative_forward(f, v, h * 10))
                xs = @inferred top_speed_iterates(deriv, p.P, p.ρ, p.Cd_closed, p.A, Froll, v0)
                @test xs isa Vector{T}
                @test last(xs) ≈ v_roll rtol = 1000eps(T)
            end
        end
    end

    # 깨뜨리기: 나쁜 미분(h = 500 m/s 전진차분)은 예외 없이 틀린 답이나 비유한 수를 낸다
    p = drs_params(Float64)
    v_good = top_speed(p.P, p.ρ, p.Cd_closed, p.A, 0.0)
    xs = top_speed_iterates((f, v) -> derivative_forward(f, v, 500.0),
                            p.P, p.ρ, p.Cd_closed, p.A, 0.0, 10.0)
    @test length(xs) == 51                 # 50번을 다 돌고도 멈추지 못한다 (예외는 없다)
    @test abs(last(xs) - v_good) > 1       # 마지막 값도 틀렸다 (≈ 82.95 vs 89.86)
    # f'(0) = 0 이 되는 출발점: 예외 없이 비유한 수
    xs = top_speed_iterates(derivative_dual, p.P, p.ρ, p.Cd_closed, p.A, 0.0, 0.0)
    @test !isfinite(last(xs))
end
