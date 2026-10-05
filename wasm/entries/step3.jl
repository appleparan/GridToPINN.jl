# entries/step3.jl — 3단계 내보내기. 시뮬레이션 상태(Diffusion1D)는 JS에서 불투명한 참조로 오가고,
# 매 호출은 그 참조를 받아 커널을 부른다. 계산은 src/step3/*.jl(과 2단계 적분기)에 있다.
# 번호가 범위를 벗어나면 2번(RK4)으로 동작한다.

module Step3Entries
import GridToPINN as G

# 시간 적분기 번호 → step(u, t, Δt, α, dx). 1 Euler, 2 RK4(기본), 3 Crank–Nicolson.
integrator_method(method::Int32) =
    method == Int32(1) ? G.diffusion_euler_step :
    method == Int32(3) ? G.diffusion_cn_step :
    G.diffusion_rk4_step

moving_wall(N::Int32, L::T, U::T, ν::T) where {T<:AbstractFloat} = G.moving_wall(Int(N), L, U, ν)
sin_mode(N::Int32, α::T) where {T<:AbstractFloat} = G.sin_mode(Int(N), α)

advance(sim::G.Diffusion1D{T}, Δt::T, nsteps::Int32, method::Int32) where {T<:AbstractFloat} =
    G.advance!(integrator_method(method), sim, Δt, Int(nsteps))

field(sim::G.Diffusion1D{T}) where {T<:AbstractFloat} = sim.u
sim_time(sim::G.Diffusion1D{T}) where {T<:AbstractFloat} = sim.t

moving_wall_error(sim::G.Diffusion1D{T}, U::T) where {T<:AbstractFloat} = G.moving_wall_error(sim, U)
sin_mode_error(sim::G.Diffusion1D{T}) where {T<:AbstractFloat} = G.sin_mode_error(sim)
max_abs(u::Vector{T}) where {T<:AbstractFloat} = G.max_abs(u)

erfc(x::T) where {T<:AbstractFloat} = G.erfc_approx(x)
stokes_first_solution(y::T, t::T, U::T, ν::T) where {T<:AbstractFloat} = G.stokes_first_solution(y, t, U, ν)
diffusion_depth(ν::T, t::T) where {T<:AbstractFloat} = G.diffusion_depth(ν, t)
end # module

# ── 패리티 사례 ───────────────────────────────────────────────────────────────
const HONEY = 2e-3
# 움직이는 벽: N칸, L = 0.1 m, U = 1 m/s. 격자 간격 dx = L/N.
wall_ops(method, Δt, nsteps; N = 50, ν = HONEY, idx = (1, 2, 5, 10)) = [
    op("moving_wall", N, 0.1, 1.0, ν; bind = "sim"),
    op("advance", :sim, Δt, nsteps, method),
    op("time", :sim),
    op("field", :sim; bind = "u"),
    op("vec_len", :u),
    [op("vec_get", :u, i) for i in idx]...,
    op("max_abs", :u),
    op("moving_wall_error", :sim, 1.0),
]
# 검증 문제: sin(πy), α = 0.1, N칸.
sin_ops(method, Δt, nsteps; N = 20, α = 0.1, idx = (1, 5, 11)) = [
    op("sin_mode", N, α; bind = "sim"),
    op("advance", :sim, Δt, nsteps, method),
    op("time", :sim),
    op("field", :sim; bind = "u"),
    [op("vec_get", :u, i) for i in idx]...,
    op("max_abs", :u),
    op("sin_mode_error", :sim),
]

const CASES3 = [
    Case("moving wall (honey), Euler inside its stability limit", wall_ops(1, 5e-4, 200)),
    Case("moving wall (honey), RK4", wall_ops(2, 1e-3, 100)),
    Case("moving wall (honey), Crank-Nicolson", wall_ops(3, 1e-2, 10)),
    Case("moving wall (honey), out-of-range method falls back to RK4", wall_ops(99, 1e-3, 100)),
    Case("moving wall (water), Crank-Nicolson", wall_ops(3, 0.1, 20; ν = 1e-6)),
    Case("sin mode, Euler", sin_ops(1, 1e-3, 50)),
    Case("sin mode, RK4", sin_ops(2, 1e-3, 50)),
    Case("sin mode, Crank-Nicolson", sin_ops(3, 1e-2, 10)),
    Case("BREAK: Euler past its stability limit blows up", wall_ops(1, 1e-2, 400)),
    Case("BREAK: RK4 past its stability limit blows up", wall_ops(2, 1e-2, 400)),
    Case("BREAK: Crank-Nicolson with a huge step stays bounded but rings", wall_ops(3, 1.0, 5)),
    Case("exact solutions", [
        op("erfc", 0.3), op("erfc", -0.7), op("erfc", 0.0),
        op("stokes_first_solution", 0.002, 1.0, 1.0, 1e-6),
        op("stokes_first_solution", 0.01, 0.1, 1.0, HONEY),
        op("stokes_first_solution", 0.0, 0.0, 1.0, 1e-6),
        op("stokes_first_solution", 0.05, 0.0, 1.0, 1e-6),
        op("diffusion_depth", 1e-6, 10.0), op("diffusion_depth", HONEY, 10.0),
    ]),
    BRIDGE_CASE,
]

const STEP3 = let E = Step3Entries
    StepSpec(
        3, "확산", "벽이 움직이면 물과 꿀 중 어느 쪽이 더 깊이 끌려오나", "src/step3",
        Dict{String,Function}("Diffusion1D" => T -> GridToPINN.Diffusion1D{T}),
        [
            Export("moving_wall", E.moving_wall, "N:int L U ν", "ref:Diffusion1D", "moving_wall",
                   "본 문제의 시뮬레이션을 만든다: [0, L]을 N칸으로 나누고 벽(u[1])만 속도 U."),
            Export("sin_mode", E.sin_mode, "N:int α", "ref:Diffusion1D", "sin_mode",
                   "검증 문제의 시뮬레이션을 만든다: [0, 1]을 N칸으로 나누고 sin(πy)로 시작."),
            Export("advance", E.advance, "sim:ref:Diffusion1D Δt nsteps:int method:int", "real", "advance!",
                   "method로 고른 적분기로 nsteps걸음 전진하고 새 시각 [s]를 돌려준다. sim은 제자리에서 바뀐다."),
            Export("field", E.field, "sim:ref:Diffusion1D", "vec", "Diffusion1D", "현재 속도장 u (N+1점)."),
            Export("time", E.sim_time, "sim:ref:Diffusion1D", "real", "Diffusion1D", "현재 시각 [s]."),
            Export("moving_wall_error", E.moving_wall_error, "sim:ref:Diffusion1D U", "real", "moving_wall_error",
                   "Stokes 해석해와의 최대 절대오차 [m/s]."),
            Export("sin_mode_error", E.sin_mode_error, "sim:ref:Diffusion1D", "real", "sin_mode_error",
                   "sin(πy)·exp(−α·π²·t)와의 최대 절대오차."),
            Export("max_abs", E.max_abs, "u:vec", "real", "max_abs", "max |uᵢ|. 발산을 알아보는 데 쓴다."),
            Export("erfc", E.erfc, "x", "real", "erfc_approx", "상보오차함수(Abramowitz–Stegun 근사)."),
            Export("stokes_first_solution", E.stokes_first_solution, "y t U ν", "real", "stokes_first_solution",
                   "움직이는 벽의 해석해 U·erfc(y/(2√(ν·t))) [m/s]."),
            Export("diffusion_depth", E.diffusion_depth, "ν t", "real", "diffusion_depth",
                   "확산 깊이 2√(ν·t) [m]."),
        ],
        [
            Param("N", "칸", 100.0, 4.0, 5000.0, "moving_wall", "격자 칸 수."),
            Param("L", "m", 0.1, 1e-3, 10.0, "moving_wall", "영역 길이."),
            Param("U", "m/s", 1.0, 0.01, 100.0, "moving_wall", "벽 속도."),
            Param("ν", "m²/s", 1e-6, 1e-9, 1e-1, "moving_wall", "동점성 계수. 물 ≈ 1e-6, 꿀 ≈ 2e-3 (대표값).";
                  presets = ["물" => 1e-6, "꿀" => 2e-3]),
            Param("α", "m²/s", 0.1, 1e-6, 10.0, "sin_mode", "검증 문제의 확산계수."),
            Param("Δt", "s", 0.01, 1e-6, 10.0, "advance!",
                  "시간 간격. 명시적 방법은 Δt ≤ Δy²/(2α) 부근을 넘으면 발산한다."),
            Param("nsteps", "걸음", 100.0, 1.0, 100_000.0, "advance!", "한 번에 전진할 걸음 수."),
            Param("x", "-", 0.5, -5.0, 5.0, "erfc_approx", "erfc를 계산할 값."),
            Param("y", "m", 0.002, 0.0, 10.0, "stokes_first_solution", "벽에서의 거리."),
            Param("t", "s", 1.0, 0.0, 1e4, "stokes_first_solution", "시각. 0이면 극한값(벽면 U, 그 아래 0)."),
        ],
        [
            Alternative("integrator", "시간 적분기", "method", [
                Option(1, "euler", "Euler (명시적, 1차)", "diffusion_euler_step"),
                Option(2, "rk4", "RK4 (명시적, 4차)", "diffusion_rk4_step"),
                Option(3, "cn", "Crank–Nicolson (음해법, 2차)", "diffusion_cn_step"),
            ]),
        ],
        CASES3,
        ["WebAssembly GC를 지원하는 브라우저"],
        ["method가 1~3 밖이면 2(RK4)로 동작한다.",
         "명시적 방법이 안정 한계를 넘으면 예외 없이 값이 커져 Infinity/NaN이 된다.",
         "Crank–Nicolson은 발산하지 않지만 Δt가 크면 부호가 번갈아 나오는 링(진동)이 남는다.",
         "t = 0에서 불연속인 본 문제는 수렴 차수를 확인하기에 부적합하다. sin_mode로 확인한다.",
         "Diffusion1D는 JS에서 불투명한 참조다. field로 벡터를 꺼내 vec_get으로 읽는다."],
    )
end
