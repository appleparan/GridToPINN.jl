# step3_wasm.jl — Step3 WASM 진입점 래퍼
#
# 이 파일은 WASM 컴파일용 진입점(entry point)을 정의한다.
# 화면에 표시용 교재 코드가 아님 — 빌드 산출물에 포함만 됨.
#
# 설계 원칙 (step1/step2와 동일):
# - 기본 인자 없음, 모든 인자 명시
# - Function 인자 회피: 확산 우변을 내부 루프로 직접 계산
# - 브로드캐스팅 회피: 명시적 for 루프 (WasmTarget 호환)
#
# 네이티브 03-diffusion.jl의 diffusion_rhs_dirichlet + 2단계 적분기와
# 동일한 차분식·계수를 루프로 구현했다.
# 빌드 전 검증 스크립트에서 두 경로의 결과가 비트 단위 일치함을 확인한다.

using .Step3Diffusion

# ── 확산 우변 (Dirichlet 고정 경계) — in-place, 명시적 루프 ──────────────
function _diff_rhs!(du::Vector{Float64}, u::Vector{Float64}, α::Float64, dx::Float64)
    n = length(u)
    inv_dx2 = 1.0 / (dx * dx)
    du[1] = 0.0
    du[n] = 0.0
    for i in 2:(n - 1)
        du[i] = α * (u[i - 1] - 2.0 * u[i] + u[i + 1]) * inv_dx2
    end
    return du
end

# ── Euler 1스텝 (in-place) ────────────────────────────────────────────────
function _diff_euler_step!(u::Vector{Float64}, Δt::Float64, α::Float64, dx::Float64)
    du = Vector{Float64}(undef, length(u))
    _diff_rhs!(du, u, α, dx)
    n = length(u)
    for i in 1:n
        u[i] = u[i] + Δt * du[i]
    end
    return Int64(0)
end

# ── RK4 1스텝 (in-place) — 네이티브 rk4_step(Vector)와 같은 계수·연산 순서 ─
function _diff_rk4_step!(u::Vector{Float64}, Δt::Float64, α::Float64, dx::Float64)
    n = length(u)
    k1 = Vector{Float64}(undef, n)
    k2 = Vector{Float64}(undef, n)
    k3 = Vector{Float64}(undef, n)
    k4 = Vector{Float64}(undef, n)
    tmp = Vector{Float64}(undef, n)
    h2 = Δt / 2.0
    h6 = Δt / 6.0

    _diff_rhs!(k1, u, α, dx)
    for i in 1:n
        tmp[i] = u[i] + h2 * k1[i]
    end
    _diff_rhs!(k2, tmp, α, dx)
    for i in 1:n
        tmp[i] = u[i] + h2 * k2[i]
    end
    _diff_rhs!(k3, tmp, α, dx)
    for i in 1:n
        tmp[i] = u[i] + Δt * k3[i]
    end
    _diff_rhs!(k4, tmp, α, dx)
    for i in 1:n
        u[i] = u[i] + h6 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
    end
    return Int64(0)
end

# ── WASM 진입: 확산 시뮬레이션 (상태를 가진 호출 형태) ───────────────────
# u (WasmGC Vector{Float64})를 nsteps만큼 전진 (in-place). method: 1=euler, 2=rk4.
# JS 흐름: vec_new(n) → vec_set으로 초기조건 → diffuse_advance(u, …) →
#          vec_get으로 현재 장 읽기 → 필요한 만큼 반복 (중간 결과 계속 꺼내기)
function diffuse_advance_wasm(
    u::Vector{Float64}, Δt::Float64, α::Float64, dx::Float64,
    nsteps::Int64, method::Int64
)::Int64
    if method == 1
        for _ in 1:nsteps
            _diff_euler_step!(u, Δt, α, dx)
        end
    elseif method == 2
        for _ in 1:nsteps
            _diff_rk4_step!(u, Δt, α, dx)
        end
    else
        throw(ErrorException("diffuse_advance_wasm: method는 1(euler) 또는 2(rk4)"))
    end
    return Int64(0)
end

# ── WASM 진입: 정답 함수들 ────────────────────────────────────────────────
erfc_wasm(x::Float64)::Float64 = Step3Diffusion.erfc_approx(x)

stokes_first_wasm(y::Float64, t::Float64, U::Float64, ν::Float64)::Float64 =
    Step3Diffusion.stokes_first_solution(y, t, U, ν)

diffusion_depth_wasm(ν::Float64, t::Float64)::Float64 =
    Step3Diffusion.diffusion_depth(ν, t)

# ── WASM 진입: 발산 확인용 보조 ──────────────────────────────────────────
function max_abs_wasm(u::Vector{Float64})::Float64
    m = 0.0
    for x in u
        ax = abs(x)
        if ax > m
            m = ax
        end
    end
    return m
end
