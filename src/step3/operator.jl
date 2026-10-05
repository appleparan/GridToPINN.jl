# step3/operator.jl — 확산 연산자 (선의 방법의 우변)
#
# 질문: 벽이 움직이면 물과 꿀 중 어느 쪽이 더 깊이 끌려오나?
# 식:   ∂u/∂t = α·∂²u/∂y²   (α = ν, 동점성 계수. 물 ≈ 1e-6, 꿀 ≈ 2e-3 m²/s, 대표값)
# 방법 ("선의 방법"): 공간만 2차 중심차분 → 격자점마다 ODE가 하나씩 생긴다.
#       du_i/dt = α·(u_{i-1} − 2u_i + u_{i+1}) / Δy²
#       이 묶음을 2단계 적분기(euler_step, rk4_step)에 그대로 넘긴다. 적분기는 새로 짜지 않는다.
# 재사용: 4단계 Burgers 점성항, 5단계 Jacobi의 출발점, 7단계 점성항.

"""
    diffusion_rhs_dirichlet(u, α, dx)

확산 우변 `α·∂²u/∂y²`(2차 중심차분). 양 끝은 고정(Dirichlet)이라 끝점의 `du/dt = 0`이다.
"""
function diffusion_rhs_dirichlet(u::AbstractVector{T}, α::T, dx::T) where {T<:AbstractFloat}
    n = length(u)
    du = similar(u)
    inv_dx2 = one(T) / (dx * dx)
    du[1] = zero(T)
    du[n] = zero(T)
    for i in 2:(n - 1)
        du[i] = α * (u[i - 1] - 2 * u[i] + u[i + 1]) * inv_dx2
    end
    return du
end

"""
    diffusion_rhs_periodic(u, α, dx)

주기 경계의 확산 우변. 5단계와 7단계 Taylor–Green에서 쓴다.
"""
function diffusion_rhs_periodic(u::AbstractVector{T}, α::T, dx::T) where {T<:AbstractFloat}
    n = length(u)
    du = similar(u)
    inv_dx2 = one(T) / (dx * dx)
    for i in 1:n
        im = i == 1 ? n : i - 1
        ip = i == n ? 1 : i + 1
        du[i] = α * (u[im] - 2 * u[i] + u[ip]) * inv_dx2
    end
    return du
end
