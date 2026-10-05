# bench.jl — bench.mjs와 같은 커널을 네이티브 Julia에서 잰다 (같은 진입 함수, 같은 입력).
#   julia +1.12 --project=wasm wasm/bench.jl
using GridToPINN
include("spec.jl")
include("bridge.jl")
include("entries/step1.jl")
include("entries/step2.jl")
include("entries/step3.jl")

# 워밍업 한 번 뒤 reps번의 중앙값 [ms]
function timeit(f, reps)
    f()
    ts = [@elapsed(f()) * 1e3 for _ in 1:reps]
    return sort(ts)[(reps + 1) ÷ 2]
end

println("Vector bridge: one vec_get / vec_set call per element (median ms; ns per element)")
println("       n   read f64   write f64   read f32   write f32     ns/elt (read f64)")
sink = Ref(0.0)
for p in 8:2:20
    n = 2^p
    row = Float64[]
    for T in (Float64, Float32)
        v = zeros(T, n)
        out = zeros(T, n)
        src = T[i * 0.5 for i in 1:n]
        reps = n >= 2^18 ? 5 : 15
        push!(row, timeit(() -> (for i in 1:n; out[i] = vec_get(v, Int32(i)); end), reps))
        push!(row, timeit(() -> (for i in 1:n; vec_set(v, Int32(i), src[i]); end), reps))
        sink[] += out[end]
    end
    f(x) = lpad(round(x; digits = 3), 10)
    println(lpad(n, 8), f(row[1]), f(row[2]), f(row[3]), f(row[4]), lpad(round(row[1] * 1e6 / n; digits = 1), 14))
end

println("\nKernels (median ms per call, f64 | f32)")
E1, E2, E3 = Step1Entries, Step2Entries, Step3Entries
function top1000(T)
    () -> (for _ in 1:1000; sink[] += E1.top_speed(T(600e3), T(1.225), T(0.9), T(1.5), T(0)); end)
end
drs(T) = () -> E2.drs_run(Int32(2), T(0.01), T(1e-6), T(600e3), T(800), T(1.225), T(1.5), T(0), T(0.9), T(0.8), T(20), T(80))
function adv(T)
    sim = E3.moving_wall(Int32(200), T(0.1), T(1), T(1e-6))
    return () -> E3.advance(sim, T(1e-3), Int32(1000), Int32(2))
end
for (label, make, reps) in [
    ("step1 top_speed (x1000 calls)", top1000, 15),
    ("step2 drs_run rk4, dt=0.01, t_end=80 (8000 steps)", drs, 15),
    ("step3 advance rk4, N=200, 1000 steps", adv, 7),
]
    println(rpad(label, 52), lpad(round(timeit(make(Float64), reps); digits = 3), 10), " | ",
            lpad(round(timeit(make(Float32), reps); digits = 3), 10))
end
