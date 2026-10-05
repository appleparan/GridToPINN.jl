# build.jl — 모든 단계를 WASM으로 컴파일하고 web/static/wasm/ 에 쓴다.
#   julia +1.12 --project=wasm wasm/build.jl
# 새 단계는 wasm/entries/stepN.jl 을 만들고 아래 STEPS 목록에 한 줄을 더하면 된다.

using WasmTarget, JSON, Pkg
using GridToPINN

include("spec.jl")
include("bridge.jl")
include("parity.jl")

# ── 등록: (진입 파일, 스펙 상수 이름) ──
const STEPS = [
    ("entries/step1.jl", :STEP1),
    ("entries/step2.jl", :STEP2),
    ("entries/step3.jl", :STEP3),


]
for (file, _) in STEPS
    include(joinpath(@__DIR__, file))
end

const OUT = joinpath(ROOT, "web", "static", "wasm")

write_json(path, obj) = open(io -> JSON.print(io, obj, 2), path, "w")

function main()
    mkpath(OUT)
    index = kernel_index()
    steps = Any[]
    for (_, sym) in STEPS
        spec = getfield(Main, sym)
        name = "step$(spec.step)"
        bytes = compile_multi(compile_entries(all_exports(spec), spec.refs); optimize = true)
        write(joinpath(OUT, "$name.wasm"), bytes)
        write_json(joinpath(OUT, "$name.json"), build_manifest(spec, index))
        parity = run_parity(spec)
        write_json(joinpath(OUT, "$name.parity.json"), parity)
        println(rpad(name, 6), lpad(length(bytes), 9), " bytes   ", length(parity), " parity cases")
        push!(steps, Dict("step" => spec.step, "title" => spec.title, "manifest" => "$name.json",
                          "wasm" => "$name.wasm", "parity" => "$name.parity.json", "bytes" => length(bytes)))
    end
    wt = Pkg.dependencies()[Base.PkgId(WasmTarget).uuid].version
    write_json(joinpath(OUT, "index.json"), Dict(
        "schema" => 1,
        "generated_with" => Dict("julia" => string(VERSION), "wasmtarget" => string(wt)),
        "steps" => steps))
    println("wrote ", OUT)
end

main()
