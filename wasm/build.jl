# build.jl — 모든 단계를 WASM으로 컴파일하고 web/static/wasm/ 에 쓴다.
#   julia +1.12 --project=wasm wasm/build.jl           산출물을 다시 만든다
#   julia +1.12 --project=wasm wasm/build.jl --check   아무것도 쓰지 않고, 커밋된 목록 파일과 일치 검사 기대값이
#                                                       지금 소스에서 만든 것과 같은지 확인한다 (다르면 실패)
# 산출물은 git에 넣는다. 그래서 커널이나 선언을 고친 뒤 다시 빌드하지 않으면 --check가 CI에서 막는다.
# .wasm 바이트는 빌드마다 조금 달라질 수 있어 바이트로 비교하지 않는다. 대신 커밋된 .wasm이 새 기대값과
# 같은 수를 내는지는 `node wasm/check_parity.mjs`가 확인한다.
# 새 단계는 wasm/entries/stepN.jl 을 만들고 아래 STEPS 목록에 한 줄을 더하면 된다.

using JSON, Pkg
using GridToPINN
# WasmTarget은 컴파일할 때만 불러온다. --check는 컴파일하지 않으므로 필요 없고,
# 불러오지 않으면 CI에서 사전 컴파일 5분이 빠진다.
const CHECK_ONLY = "--check" in ARGS
CHECK_ONLY || @eval using WasmTarget

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

# 커밋된 JSON 산출물이 지금 소스에서 만든 것과 같은가. 다른 파일 이름을 돌려준다.
function stale_files()
    index = kernel_index()
    stale = String[]
    same(path, obj) = isfile(path) && JSON.parse(read(path, String)) == JSON.parse(JSON.json(obj))
    for (_, sym) in STEPS
        spec = getfield(Main, sym)
        name = "step$(spec.step)"
        same(joinpath(OUT, "$name.json"), build_manifest(spec, index)) || push!(stale, "$name.json")
        same(joinpath(OUT, "$name.parity.json"), run_parity(spec)) || push!(stale, "$name.parity.json")
        isfile(joinpath(OUT, "$name.wasm")) || push!(stale, "$name.wasm")
    end
    return stale
end

function check()
    stale = stale_files()
    if isempty(stale)
        println("web/static/wasm is up to date with src/ and wasm/entries/")
    else
        println("STALE: ", join(stale, ", "))
        println("Rebuild and commit: julia +1.12 --project=wasm wasm/build.jl")
        exit(1)
    end
end

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

CHECK_ONLY ? check() : main()
