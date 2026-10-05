using Test
using GridToPINN

@testset verbose = true "GridToPINN" begin
    include("step1.jl")
    include("step2.jl")
    include("step3.jl")
end
