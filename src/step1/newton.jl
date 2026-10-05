# step1/newton.jl — Newton법
#
# 질문: f(x) = 0의 근을 어떻게 빠르게 찾나?
# 식:   x_{n+1} = x_n - f(x_n) / f'(x_n)
# 쓰임: drs.jl의 최고속도. 2단계의 정상상태 목표값. 나쁜 선택(f' = 0, 먼 출발점)은
#       예외 대신 NaN/Inf나 마지막 반복값으로 나타난다.

"""
    newton_iterates(f, df, x0; tol, maxiter) -> Vector{T}

Newton 반복의 값을 모두 모아 돌려준다. 첫 원소는 `x0`다.
`|x_new - x| <= tol * (1 + |x_new|)`이면 멈춘다. 값이 유한하지 않아도 멈춘다.
수렴하지 못해도 예외 없이 마지막 반복값까지만 돌려준다.
"""
function newton_iterates(f, df, x0::T; tol::T = 4eps(T), maxiter::Int = 50) where {T<:AbstractFloat}
    xs = T[x0]
    x = x0
    for _ in 1:maxiter
        xnew = x - f(x) / df(x)
        push!(xs, xnew)
        if !isfinite(xnew) || abs(xnew - x) <= tol * (one(T) + abs(xnew))
            break
        end
        x = xnew
    end
    return xs
end

"""
    newton(f, df, x0; tol, maxiter)

`newton_iterates`의 마지막 값, 곧 근의 추정값.
"""
function newton(f, df, x0::T; tol::T = 4eps(T), maxiter::Int = 50) where {T<:AbstractFloat}
    return last(newton_iterates(f, df, x0; tol = tol, maxiter = maxiter))
end
