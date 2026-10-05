# step3/implicit.jl — 음해법 Crank–Nicolson
#
# 질문: 명시적 방법의 안정 한계(Δt ≤ Δy²/2α)를 넘어 큰 Δt를 쓸 수 없나?
# 식:   (I − Δt/2·L) uⁿ⁺¹ = (I + Δt/2·L) uⁿ.  삼중대각 시스템을 Thomas 알고리즘(O(n))으로 푼다.
# 성질: 무조건 안정, 시간 2차. 단 최대원리는 보장하지 않아, |λ|Δt ≫ 1이면 부호가 번갈아 나오는
#       링(진동)이 남는다. 발산하지 않을 뿐 해가 틀어질 수 있다.

"""
    crank_nicolson_step(u, Δt, α, dx)

Crank–Nicolson 한 걸음. 양 끝은 고정(Dirichlet)이다.
"""
function crank_nicolson_step(u::AbstractVector{T}, Δt::T, α::T, dx::T) where {T<:AbstractFloat}
    n = length(u)
    u_new = copy(u)
    m = n - 2                      # 내부 미지수 u₂ … u_{n−1}
    m <= 0 && return u_new

    r = α * Δt / (2 * dx * dx)
    b = Vector{T}(undef, m)        # 주대각 (부대각·초대각은 모두 −r)
    c = Vector{T}(undef, m)        # 초대각 (소거 중에는 c′)
    d = Vector{T}(undef, m)        # 우변 (소거 중에는 d′)
    for k in 1:m
        i = k + 1
        b[k] = 1 + 2r
        c[k] = -r
        d[k] = r * u[i - 1] + (1 - 2r) * u[i] + r * u[i + 1]
    end
    d[1] += r * u[1]               # 고정된 경계값(알려진 항)을 우변으로
    d[m] += r * u[n]

    c[1] = c[1] / b[1]             # Thomas 전진 소거
    d[1] = d[1] / b[1]
    for k in 2:m
        denom = b[k] + r * c[k - 1]
        c[k] = c[k] / denom
        d[k] = (d[k] + r * d[k - 1]) / denom
    end
    u_new[m + 1] = d[m]            # 후진 대입
    for k in (m - 1):-1:1
        u_new[k + 1] = d[k] - c[k] * u_new[k + 2]
    end
    return u_new
end
