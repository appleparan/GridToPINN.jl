# GridToPINN — CFD를 밑바닥부터 짜서 PINN까지 가는 튜토리얼의 계산 커널.
# 평평한 모듈 하나. 뒤 단계는 앞 단계의 함수를 그대로 부른다(2단계는 1단계 top_speed,
# 3단계는 2단계 euler_step/rk4_step). 의존 패키지는 없다.
module GridToPINN

include("step1/dual.jl")
include("step1/derivatives.jl")
include("step1/newton.jl")
include("step1/drs.jl")

include("step2/integrators.jl")
include("step2/adaptive.jl")
include("step2/acceleration.jl")

include("step3/operator.jl")
include("step3/exact.jl")
include("step3/implicit.jl")
include("step3/simulation.jl")

export Dual,
    derivative_forward, derivative_central, derivative_dual,
    newton_iterates, newton,
    drag_force, resistance, power_balance, power_balance_derivative,
    top_speed_analytic, top_speed_iterates, top_speed, drs_gain,
    Trajectory, euler_step, rk4_step, integrate,
    rk45_step, integrate_adaptive,
    acceleration, drs_acceleration, drs_run, settling_time,
    diffusion_rhs_dirichlet, diffusion_rhs_periodic,
    erfc_approx, stokes_first_solution, diffusion_depth, sin_mode_initial, sin_mode_exact,
    crank_nicolson_step,
    Diffusion1D, moving_wall, sin_mode,
    diffusion_euler_step, diffusion_rk4_step, diffusion_cn_step,
    advance!, max_abs, moving_wall_error, sin_mode_error

end # module GridToPINN
