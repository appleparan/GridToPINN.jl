# step1/derivatives.jl — 미분 세 가지
#
# 질문: Newton법에 필요한 f'(x)를 어떻게 구하나?
# 방법: 전진차분(1차), 중심차분(2차), 이중수 자동미분(반올림 외 오차 없음).
# 쓰임: newton.jl과 drs.jl에서 고르는 대안 지점. 유한차분은 3단계 이후 공간 미분의 바탕이다.

"""
    derivative_forward(f, x, h)

전진차분 `(f(x+h) - f(x)) / h`. 오차는 O(h)다.
"""
derivative_forward(f, x::T, h::T) where {T<:AbstractFloat} = (f(x + h) - f(x)) / h

"""
    derivative_central(f, x, h)

중심차분 `(f(x+h) - f(x-h)) / 2h`. 오차는 O(h²)다.
"""
derivative_central(f, x::T, h::T) where {T<:AbstractFloat} = (f(x + h) - f(x - h)) / (2h)

"""
    derivative_dual(f, x)

이중수로 구한 `f'(x)`. `f`는 `Dual`을 받아 `Dual`을 돌려줘야 한다.
"""
derivative_dual(f, x::T) where {T<:AbstractFloat} = f(Dual(x, one(T))).der
