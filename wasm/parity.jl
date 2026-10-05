# parity.jl — 패리티 사례를 네이티브 Julia에서 실행해 expected 값을 채운다.
# 호출하는 함수는 WASM으로 내보내는 바로 그 진입 함수다(타입만 T로 정해서 부른다).
# 비유한 값은 JSON이 못 담으므로 "NaN", "Infinity", "-Infinity" 문자열로 적는다.

encode_number(x::Integer) = x
encode_number(x::AbstractFloat) = isnan(x) ? "NaN" : isinf(x) ? (x > 0 ? "Infinity" : "-Infinity") : Float64(x)

function run_op(spec::StepSpec, op::Op, ::Type{T}, env) where {T}
    e = only(filter(x -> x.name == op.fn, all_exports(spec)))
    length(op.args) == length(e.args) || error("op $(op.fn): expected $(length(e.args)) args")
    vals = map(op.args, e.args) do a, (_, type)
        a isa Symbol ? env[String(a)] : type == "int" ? Int32(a) : T(a)
    end
    result = fn_for(e, T)(vals...)
    op.bind === nothing || (env[op.bind] = result)
    json = Dict{String,Any}(
        "fn" => op.fn,
        "args" => [a isa Symbol ? "\$" * String(a) : encode_number(a) for a in op.args],
    )
    op.bind === nothing || (json["bind"] = op.bind)
    e.returns in ("real", "int") && (json["expected"] = encode_number(result))
    return json
end

"""모든 사례를 f64, f32로 한 번씩 실행해 parity.json 내용을 만든다."""
function run_parity(spec::StepSpec)
    check_coverage(spec)
    return [
        Dict("name" => c.name, "precision" => sfx, "ops" => (env = Dict{String,Any}();
             [run_op(spec, op, T, env) for op in c.ops]))
        for c in spec.cases for (sfx, T) in PRECISIONS
    ]
end

"""모든 내보내기, 모든 대안 번호, 깨뜨리기 사례가 빠짐없이 들어 있는지 확인한다."""
function check_coverage(spec::StepSpec)
    used = Dict{String,Vector{Op}}()
    for c in spec.cases, op in c.ops
        push!(get!(used, op.fn, Op[]), op)
    end
    for e in all_exports(spec)
        haskey(used, e.name) || error("step $(spec.step): parity cases never call '$(e.name)'")
    end
    for a in spec.alternatives, o in a.options, e in all_exports(spec)
        i = findfirst(p -> first(p) == a.arg, e.args)
        i === nothing && continue
        any(op -> op.args[i] == o.value, get(used, e.name, Op[])) ||
            error("step $(spec.step): alternative '$(a.id)' option $(o.value) never tested via '$(e.name)'")
    end
    any(c -> startswith(c.name, "BREAK"), spec.cases) || error("step $(spec.step): no BREAK case")
end
