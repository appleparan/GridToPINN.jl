# entries/step2.jl — 2단계 내보내기. 타입을 고정하고 적분기 번호를 커널 적분기에 연결할 뿐이다.
# 계산은 src/step2/*.jl(과 1단계 top_speed)에 있다. 번호가 범위를 벗어나면 2번(RK4)으로 동작한다.

module Step2Entries
import GridToPINN as G

# 적분기 번호 → integrator(f, v0, t0, t_end). 1 Euler, 2 RK4(기본), 3 적응형 Dormand–Prince.
function integrator_method(method::Int32, Δt::T, rtol::T) where {T<:AbstractFloat}
    return method == Int32(1) ? (f, y, t0, t1) -> G.integrate(G.euler_step, f, y, t0, t1, Δt) :
           method == Int32(3) ? (f, y, t0, t1) -> G.integrate_adaptive(f, y, t0, t1, Δt; rtol = rtol) :
           (f, y, t0, t1) -> G.integrate(G.rk4_step, f, y, t0, t1, Δt)
end

function drs_run(method::Int32, Δt::T, rtol::T, P::T, m::T, ρ::T, A::T, Froll::T,
                 Cd_closed::T, Cd_open::T, t_open::T, t_end::T) where {T<:AbstractFloat}
    return G.drs_run(integrator_method(method, Δt, rtol), P, m, ρ, A, Froll, Cd_closed, Cd_open, t_open, t_end)
end

trajectory_t(tr::G.Trajectory{T,T}) where {T<:AbstractFloat} = tr.t
trajectory_y(tr::G.Trajectory{T,T}) where {T<:AbstractFloat} = tr.y

settling_time(tr::G.Trajectory{T,T}, v_final::T, fraction::T) where {T<:AbstractFloat} =
    G.settling_time(tr, v_final, fraction)

acceleration(v::T, P::T, m::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    G.acceleration(v, P, m, ρ, Cd, A, Froll)

top_speed(P::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} = G.top_speed(P, ρ, Cd, A, Froll)
end # module

# ── 패리티 사례 ───────────────────────────────────────────────────────────────
# drs_run(method, Δt, rtol, P, m, ρ, A, Froll, Cd_closed, Cd_open, t_open, t_end)
const VF2 = 93.5     # 열림 Cd의 최고속도 근처(settling_time 목표)
run_ops(method, Δt; rtol = 1e-6, t_open = 20.0, t_end = 80.0, idx = (1, 2, 5)) = [
    op("drs_run", method, Δt, rtol, 600e3, 800.0, 1.225, 1.5, 0.0, 0.9, 0.8, t_open, t_end; bind = "tr"),
    op("trajectory_t", :tr; bind = "ts"),
    op("trajectory_y", :tr; bind = "ys"),
    op("vec_len", :ts), op("vec_len", :ys),
    [op("vec_get", :ts, i) for i in idx]...,
    [op("vec_get", :ys, i) for i in idx]...,
    op("settling_time", :tr, VF2, 0.9),
]

const CASES2 = [
    Case("acceleration and top speed", [
        op("acceleration", 80.0, 600e3, 800.0, 1.225, 0.8, 1.5, 0.0),
        op("acceleration", 93.5, 600e3, 800.0, 1.225, 0.8, 1.5, 0.0),
        op("top_speed", 600e3, 1.225, 0.8, 1.5, 0.0),
    ]),
    Case("DRS run, Euler", run_ops(1, 0.5; idx = (1, 2, 5, 161))),
    Case("DRS run, RK4", run_ops(2, 0.5; idx = (1, 2, 5, 161))),
    Case("DRS run, adaptive Dormand-Prince", run_ops(3, 0.5; idx = (1, 2, 5, 10, 20, 26))),
    Case("DRS run, out-of-range method falls back to RK4", run_ops(99, 0.5; idx = (1, 2, 5, 161))),
    Case("BREAK: Euler with a step far past the stability limit", run_ops(1, 30.0; t_open = 0.0, t_end = 300.0, idx = (1, 2, 5, 11))),
    Case("BREAK: RK4 with a step far past the stability limit", run_ops(2, 30.0; t_open = 0.0, t_end = 300.0, idx = (1, 2, 5, 11))),
    BRIDGE_CASE,
]

const STEP2 = let E = Step2Entries
    StepSpec(
        2, "시간 전진", "그 속도에 도달하는 데 얼마나 걸리나", "src/step2",
        Dict{String,Function}("Trajectory" => T -> GridToPINN.Trajectory{T,T}),
        [
            Export("drs_run", E.drs_run, "method:int Δt rtol P m ρ A Froll Cd_closed Cd_open t_open t_end",
                   "ref:Trajectory", "drs_run",
                   "닫힘 최고속도에서 출발해 t_end까지 속도 곡선을 적분한다. method로 적분기를 고른다."),
            Export("trajectory_t", E.trajectory_t, "tr:ref:Trajectory", "vec", "Trajectory",
                   "받아들인 걸음의 시각들 [s]."),
            Export("trajectory_y", E.trajectory_y, "tr:ref:Trajectory", "vec", "Trajectory",
                   "각 시각의 속도 [m/s]."),
            Export("settling_time", E.settling_time, "tr:ref:Trajectory v_final fraction", "real", "settling_time",
                   "처음 간격이 (1 − fraction)배로 줄어드는 첫 시각 [s]. 못 미치면 Infinity."),
            Export("acceleration", E.acceleration, "v P m ρ Cd A Froll", "real", "acceleration",
                   "가속도 (P/v − R(v)) / m [m/s²]."),
            Export("top_speed", E.top_speed, "P ρ Cd A Froll", "real", "top_speed",
                   "1단계 top_speed. v(t→∞)가 수렴해야 할 목표 [m/s]."),
        ],
        [
            Param("P", "W", 600e3, 1e3, 2e6, "acceleration", "엔진 출력."),
            Param("m", "kg", 800.0, 50.0, 5000.0, "acceleration", "차량 질량."),
            Param("ρ", "kg/m³", 1.225, 0.1, 5.0, "drag_force", "공기 밀도."),
            Param("A", "m²", 1.5, 0.2, 5.0, "drag_force", "전면 면적."),
            Param("Froll", "N", 0.0, 0.0, 20_000.0, "resistance", "구름저항."),
            Param("Cd", "-", 0.8, 0.05, 3.0, "acceleration", "항력계수(acceleration, top_speed용)."),
            Param("Cd_closed", "-", 0.9, 0.05, 3.0, "drs_acceleration", "DRS 닫힘 항력계수."),
            Param("Cd_open", "-", 0.8, 0.05, 3.0, "drs_acceleration", "DRS 열림 항력계수."),
            Param("t_open", "s", 20.0, 0.0, 300.0, "drs_acceleration", "DRS가 열리는 시각."),
            Param("t_end", "s", 80.0, 1.0, 1000.0, "drs_run", "적분 끝 시각."),
            Param("Δt", "s", 0.5, 1e-3, 60.0, "integrate",
                  "Euler/RK4의 고정 간격, 적응형의 첫 간격. 크면 Euler가 발산한다(이 모델의 Euler 안정 한계는 약 7 s)."),
            Param("rtol", "-", 1e-6, 0.0, 1e-1, "integrate_adaptive",
                  "적응형의 상대 허용오차. 0이면 어떤 걸음도 받아들이지 못한다."),
            Param("v", "m/s", 80.0, 1.0, 500.0, "acceleration", "가속도를 계산할 속도."),
            Param("v_final", "m/s", VF2, 1.0, 500.0, "settling_time", "목표 속도. 열림 Cd의 최고속도(1단계 top_speed)."),
            Param("fraction", "-", 0.9, 0.0, 1.0, "settling_time", "처음 간격 중 줄어들어야 할 비율."),
        ],
        [
            Alternative("integrator", "시간 적분기", "method", [
                Option(1, "euler", "Euler (1차)", "euler_step"),
                Option(2, "rk4", "RK4 (4차)", "rk4_step"),
                Option(3, "adaptive", "적응형 Dormand–Prince 5(4)", "integrate_adaptive"),
            ]),
        ],
        CASES2,
        ["WebAssembly GC를 지원하는 브라우저"],
        ["method가 1~3 밖이면 2(RK4)로 동작한다.",
         "Δt가 안정 한계를 넘으면 예외 없이 값이 진동하거나 NaN/Infinity가 된다.",
         "적응형은 maxsteps = 100000번 시도 안에 끝나지 않으면 그때까지의 기록을 돌려준다.",
         "Trajectory는 JS에서 불투명한 참조다. trajectory_t/trajectory_y로 벡터를 꺼내 vec_get으로 읽는다."],
    )
end
