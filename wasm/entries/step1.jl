# entries/step1.jl — 1단계 내보내기. 타입을 고정하고, 방법 번호를 커널 함수에 연결할 뿐이다.
# 계산은 모두 src/step1/*.jl 에 있다. 번호가 범위를 벗어나면 1번(손으로 유도한 f')으로 동작한다.

module Step1Entries
import GridToPINN as G

# 미분 방법 번호 → f'(v)를 구하는 함수 derivative(f, v).
# 1 손 유도(기본), 2 전진차분, 3 중심차분, 4 이중수.
function derivative_method(method::Int32, ρ::T, Cd::T, A::T, Froll::T, h::T) where {T<:AbstractFloat}
    return method == Int32(2) ? (f, v) -> G.derivative_forward(f, v, h) :
           method == Int32(3) ? (f, v) -> G.derivative_central(f, v, h) :
           method == Int32(4) ? (f, v) -> G.derivative_dual(f, v) :
           (f, v) -> G.power_balance_derivative(v, ρ, Cd, A, Froll)
end

function top_speed_iterates(P::T, ρ::T, Cd::T, A::T, Froll::T, v0::T, method::Int32, h::T) where {T<:AbstractFloat}
    d = derivative_method(method, ρ, Cd, A, Froll, h)
    return G.top_speed_iterates(d, P, ρ, Cd, A, Froll, v0)
end

top_speed(P::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} = G.top_speed(P, ρ, Cd, A, Froll)

top_speed_analytic(P::T, ρ::T, Cd::T, A::T) where {T<:AbstractFloat} = G.top_speed_analytic(P, ρ, Cd, A)

drs_gain(P::T, ρ::T, A::T, Froll::T, Cd_closed::T, Cd_open::T) where {T<:AbstractFloat} =
    G.drs_gain(P, ρ, A, Froll, Cd_closed, Cd_open)

power_balance(v::T, P::T, ρ::T, Cd::T, A::T, Froll::T) where {T<:AbstractFloat} =
    G.power_balance(v, P, ρ, Cd, A, Froll)

function power_balance_derivative(v::T, P::T, ρ::T, Cd::T, A::T, Froll::T, method::Int32, h::T) where {T<:AbstractFloat}
    f = x -> G.power_balance(x, P, ρ, Cd, A, Froll)
    return derivative_method(method, ρ, Cd, A, Froll, h)(f, v)
end
end # module


# ── 패리티 사례: 같은 호출을 네이티브 Julia와 WASM이 각각 실행해 비교한다 ──────────
const P1, ρ1, Cd1, A1 = 600e3, 1.225, 0.9, 1.5
iter_ops(method, v0, h; Froll = 0.0, idx = (1, 2, 4), bind = "it") = [
    op("top_speed_iterates", P1, ρ1, Cd1, A1, Froll, v0, method, h; bind = bind),
    op("vec_len", Symbol(bind)),
    [op("vec_get", Symbol(bind), i) for i in idx]...,
]

const CASES1 = [
    Case("closed-form values", [
        op("top_speed", P1, ρ1, Cd1, A1, 0.0),
        op("top_speed", P1, ρ1, Cd1, A1, 500.0),
        op("top_speed_analytic", P1, ρ1, Cd1, A1),
        op("drs_gain", P1, ρ1, A1, 0.0, 0.9, 0.8),
        op("power_balance", 50.0, P1, ρ1, Cd1, A1, 0.0),
    ]),
    Case("f'(v) by every method, plus out-of-range fallback", [
        op("power_balance_derivative", 50.0, P1, ρ1, Cd1, A1, 100.0, m, 1e-4) for m in (1, 2, 3, 4, 99)
    ]),
    Case("Newton iterates, hand f'", iter_ops(1, 50.0, 1e-4)),
    Case("Newton iterates, forward difference", iter_ops(2, 50.0, 1e-4)),
    Case("Newton iterates, central difference", iter_ops(3, 50.0, 1e-4)),
    Case("Newton iterates, dual numbers", iter_ops(4, 50.0, 1e-4; Froll = 500.0)),
    Case("BREAK: start at v0 = 0 (f' = 0)", iter_ops(1, 0.0, 1e-4; idx = (1, 2))),
    Case("BREAK: forward difference with h = 0", iter_ops(2, 50.0, 0.0; idx = (1, 2))),
    Case("BREAK: central difference with h below Float32 resolution", iter_ops(3, 50.0, 1e-8; idx = (1, 2))),
    Case("BREAK: huge h", iter_ops(2, 50.0, 100.0)),
    BRIDGE_CASE,
]

const STEP1 = let E = Step1Entries
    StepSpec(
        1, "미분과 Newton법", "DRS를 열면 최고속도가 얼마나 오르나", "src/step1",
        Dict{String,Function}(),
        [
            Export("top_speed_iterates", E.top_speed_iterates, "P ρ Cd A Froll v0 method:int h", "vec",
                   "top_speed_iterates", "Newton 반복값 전체(출발점 v0 포함) [m/s]. method로 f'을 고른다.";
                   display = KMH),
            Export("top_speed", E.top_speed, "P ρ Cd A Froll", "real", "top_speed",
                   "손으로 유도한 f'로 구한 최고속도 [m/s]."; display = KMH),
            Export("top_speed_analytic", E.top_speed_analytic, "P ρ Cd A", "real", "top_speed_analytic",
                   "구름저항 0일 때의 해석해 [m/s]."; display = KMH),
            Export("drs_gain", E.drs_gain, "P ρ A Froll Cd_closed Cd_open", "real", "drs_gain",
                   "DRS를 열었을 때 최고속도 증가량 [m/s]."; display = KMH),
            Export("power_balance", E.power_balance, "v P ρ Cd A Froll", "real", "power_balance",
                   "f(v) = ½ρ·Cd·A·v³ + F_구름·v − P [W]."),
            Export("power_balance_derivative", E.power_balance_derivative, "v P ρ Cd A Froll method:int h",
                   "real", "power_balance_derivative", "f'(v)를 method로 고른 방법으로 구한다."),
        ],
        [
            Param("P", "W", 600e3, 1e3, 2e6, "power_balance", "엔진 출력."),
            Param("ρ", "kg/m³", 1.225, 0.1, 5.0, "drag_force", "공기 밀도."),
            Param("Cd", "-", 0.9, 0.05, 3.0, "drag_force", "항력계수(DRS 닫힘 기준)."),
            Param("A", "m²", 1.5, 0.2, 5.0, "drag_force", "전면 면적."),
            Param("Froll", "N", 0.0, 0.0, 20_000.0, "resistance", "구름저항. 0이면 해석해가 정답이 된다."),
            Param("Cd_closed", "-", 0.9, 0.05, 3.0, "drs_gain", "DRS 닫힘 항력계수."),
            Param("Cd_open", "-", 0.8, 0.05, 3.0, "drs_gain", "DRS 열림 항력계수."),
            Param("v0", "m/s", 50.0, 0.0, 1000.0, "newton_iterates",
                  "Newton 출발점. 0이면 f'(0) = 0이라 NaN, 너무 멀면 수렴이 느리다."; display = KMH),
            Param("v", "m/s", 50.0, 0.0, 1000.0, "power_balance", "f와 f'을 계산할 속도."; display = KMH),
            Param("h", "m/s", 1e-4, 1e-12, 100.0, "derivative_forward",
                  "유한차분 간격. 너무 크면 절단오차, 너무 작으면 반올림오차(Float32는 더 일찍)."),
        ],
        [
            Alternative("derivative", "f'(v)를 구하는 방법", "method", [
                Option(1, "hand", "손으로 유도", "power_balance_derivative"),
                Option(2, "forward", "전진차분", "derivative_forward"),
                Option(3, "central", "중심차분", "derivative_central"),
                Option(4, "dual", "이중수 자동미분", "derivative_dual"),
            ]),
        ],
        CASES1,
        ["WebAssembly GC를 지원하는 브라우저"],
        ["method가 1~4 밖이면 1(손으로 유도한 f')로 동작한다.",
         "수렴하지 못하면 예외 없이 마지막 반복값을 돌려주고, f' = 0이면 NaN/Infinity가 나온다.",
         "Float32는 4eps(Float32) ≈ 4.8e-7 오차 한계에서 수렴 판정이 흔들릴 수 있다."],
    )
end
