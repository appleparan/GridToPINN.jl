module GridToPINN

# 단계별 계산은 각 0N-*.jl 파일에 담고, 여기서는 재수출만 한다.
include("01-differentiation-newton.jl")
include("02-time-integration.jl")
include("03-diffusion.jl")

end # module GridToPINN
