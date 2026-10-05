# spec.jl — 단계(step) 하나를 선언하는 작은 타입과, 선언에서 컴파일 목록·매니페스트를 만드는 코드.
#
# 규칙: 선언에는 숫자 계산이 없다. 함수 위치(파일·줄)는 손으로 적지 않고 커널 소스를 파싱해 찾는다.
# 그래서 화면에 보이는 줄 범위는 항상 실제 정의와 일치한다.

import Base.JuliaSyntax as JS

const ROOT = dirname(@__DIR__)
const PRECISIONS = (("f64", Float64), ("f32", Float32))

# ── 선언 타입 ────────────────────────────────────────────────────────────────

"""내보내는 함수. `args`는 `"P ρ method:int v:vec sim:ref:Diffusion1D"` 꼴(기본 타입은 real)."""
struct Export
    name::String
    fn::Union{Function,Dict{DataType,Function}}   # 정밀도별로 다르면 Dict
    args::Vector{Pair{String,String}}
    returns::String                               # real | int | vec | ref:<Name> | none
    doc::String
    source::String                                # 커널 정의 이름 (위치는 파싱해서 찾는다)
    display::Union{Nothing,Pair{String,Float64}}  # 반환값을 화면에 보일 단위 (없으면 그대로)
end

# 화면 표시 단위. 계산은 SI(m/s)로 하고(P = F·v가 그대로 성립해야 한다),
# 화면만 `표시값 = 값 × scale`로 바꿔 보여준다. 자동차 속도는 km/h가 읽기 쉽다.
const KMH = "km/h" => 3.6
display_dict(::Nothing) = nothing
display_dict(d::Pair) = Dict("unit" => first(d), "scale" => last(d))

"""조작 가능한 값. `source`는 그 값이 쓰이는 커널 정의 이름."""
struct Param
    name::String
    unit::String
    default::Float64
    min::Float64
    max::Float64
    doc::String
    source::String
    presets::Vector{Pair{String,Float64}}
    display::Union{Nothing,Pair{String,Float64}}  # 화면에 보일 단위 (없으면 unit 그대로)
end

struct Option
    value::Int
    key::String
    label::String
    source::String
end

"""대안 지점. `arg`는 대안 번호를 받는 내보내기 인자 이름(예: method)."""
struct Alternative
    id::String
    title::String
    arg::String
    options::Vector{Option}
end

"""패리티 검사의 한 호출. Symbol 인자는 앞 호출의 bind 이름을 가리킨다."""
struct Op
    fn::String
    args::Vector{Any}
    bind::Union{Nothing,String}
end
op(fn, args...; bind = nothing) = Op(fn, Any[args...], bind === nothing ? nothing : String(bind))

struct Case
    name::String
    ops::Vector{Op}
end

struct StepSpec
    step::Int
    title::String
    question::String
    kernel_dir::String                 # 저장소 기준 상대 경로, 예: "src/step1"
    refs::Dict{String,Function}        # ref 타입 이름 → (T -> 구체 타입)
    exports::Vector{Export}
    parameters::Vector{Param}
    alternatives::Vector{Alternative}
    cases::Vector{Case}
    requirements::Vector{String}
    limits::Vector{String}
end

"""`"P ρ method:int"` → ["P"=>"real", "ρ"=>"real", "method"=>"int"]"""
parse_args(s::AbstractString) = [
    begin
        name, _, type = partition(String(tok), ':')
        name => (isempty(type) ? "real" : type)
    end for tok in split(s)
]
partition(s, c) = (i = findfirst(c, s)) === nothing ? (s, "", "") : (s[1:prevind(s, i)], string(c), s[nextind(s, i):end])

Export(name, fn, args::AbstractString, returns, source, doc; display = nothing) =
    Export(name, fn, parse_args(args), returns, doc, source, display)
Param(name, unit, default, min, max, source, doc; presets = Pair{String,Float64}[], display = nothing) =
    Param(name, unit, default, min, max, doc, source, presets, display)

# ── 컴파일 목록 ──────────────────────────────────────────────────────────────

fn_for(e::Export, ::Type{T}) where {T} = e.fn isa Function ? e.fn : e.fn[T]

function arg_type(spec_refs, type::String, ::Type{T}) where {T}
    type == "real" && return T
    type == "int" && return Int32
    type == "vec" && return Vector{T}
    startswith(type, "ref:") && return spec_refs[type[5:end]](T)
    error("unknown type $type")
end

"""모든 내보내기를 f64/f32로 한 번씩: `[(fn, (인자 타입...), "이름_f64"), ...]`"""
function compile_entries(exports::Vector{Export}, refs)
    return [
        (fn_for(e, T), Tuple(arg_type(refs, p.second, T) for p in e.args), "$(e.name)_$sfx")
        for e in exports for (sfx, T) in PRECISIONS
    ]
end

# ── 소스 위치: 커널 파일을 파싱해 정의의 줄 범위를 찾는다 ───────────────────────

"""정의의 이름을 꺼낸다(`f(x) where T`, `f(x)::R`, `Base.:+(a, b)`, `struct A{T} <: B` 모두)."""
function head_name(node)
    k = JS.kind(node)
    if k in (JS.K"where", JS.K"::", JS.K"<:", JS.K"curly")
        return head_name(JS.children(node)[1])
    elseif k == JS.K"call"
        return head_name(JS.children(node)[1])
    end
    return String(strip(JS.sourcetext(node)))
end

function definition(node)
    k = JS.kind(node)
    kids = JS.children(node)
    if k == JS.K"function"
        return ("function", head_name(kids[1]))
    elseif k == JS.K"struct"
        return ("struct", head_name(kids[end - 1]))
    elseif k == JS.K"=" && JS.kind(kids[1]) in (JS.K"call", JS.K"where", JS.K"::")
        return ("function", head_name(kids[1]))      # 짧은 형태 f(x) = ...
    end
    return nothing
end

"""파일의 최상위 정의 목록 `[(name, kind, [첫 줄, 끝 줄])]`. 독스트링 줄을 포함한다."""
function parse_definitions(path::AbstractString)
    src = read(path, String)
    tree = JS.parseall(JS.SyntaxNode, src)
    newlines = findall(==('\n'), src)
    line_of(byte) = count(<(byte), newlines) + 1
    out = Tuple{String,String,Vector{Int}}[]
    for node in JS.children(tree)
        inner = JS.kind(node) == JS.K"doc" ? JS.children(node)[end] : node
        d = definition(inner)
        d === nothing && continue
        first_byte = node.position
        last_byte = first_byte + JS.span(node) - 1
        push!(out, (d[2], d[1], [line_of(first_byte), line_of(last_byte)]))
    end
    return out
end

"""저장소 안의 모든 단계 커널 파일 → 정의 목록 (상대 경로 키)."""
function kernel_index()
    index = Dict{String,Vector{Tuple{String,String,Vector{Int}}}}()
    for dir in sort(filter(startswith("step"), readdir(joinpath(ROOT, "src"))))
        for f in sort(readdir(joinpath(ROOT, "src", dir)))
            endswith(f, ".jl") || continue
            rel = "src/$dir/$f"
            index[rel] = parse_definitions(joinpath(ROOT, rel))
        end
    end
    return index
end

"""정의 이름 → `(file, lines)`. 그 단계 폴더를 먼저, 없으면 앞 단계에서 찾는다."""
function find_source(index, name::String, kernel_dir::String)
    files = sort(collect(keys(index)); by = f -> (startswith(f, kernel_dir * "/") ? 0 : 1, f))
    for f in files, (n, _, lines) in index[f]
        n == name && return (file = f, lines = lines)
    end
    error("definition '$name' not found in kernel sources")
end

# ── 매니페스트 ───────────────────────────────────────────────────────────────

src_json(s) = Dict("file" => s.file, "lines" => s.lines)

# 단계 내보내기 + 브리지 도우미(bridge.jl). BRIDGE_EXPORTS는 build.jl이 bridge.jl을 먼저 불러와 정의한다.
all_exports(spec::StepSpec) = vcat(spec.exports, BRIDGE_EXPORTS)

function validate(spec::StepSpec)
    names = Set(e.name for e in spec.exports)
    length(names) == length(spec.exports) || error("duplicate export names")
    known = Set(p.name for p in spec.parameters) ∪ Set(a.arg for a in spec.alternatives)
    for e in spec.exports, (n, t) in e.args
        t in ("real", "int") && !(n in known) && error("export $(e.name): arg '$n' is not a parameter or alternative")
    end
    for p in spec.parameters
        p.min <= p.default <= p.max || error("parameter $(p.name): default outside [min, max]")
    end
end

function build_manifest(spec::StepSpec, index)
    validate(spec)
    used_files = Set{String}(f for f in keys(index) if startswith(f, spec.kernel_dir * "/"))
    function track(name)
        isempty(name) && return nothing        # 브리지 도우미는 커널 소스가 없다
        s = find_source(index, name, spec.kernel_dir)
        push!(used_files, s.file)
        return src_json(s)
    end

    functions = [Dict(
        "name" => e.name,
        "exports" => Dict(sfx => "$(e.name)_$sfx" for (sfx, _) in PRECISIONS),
        "args" => [Dict("name" => n, "type" => t) for (n, t) in e.args],
        "returns" => e.returns, "doc" => e.doc, "source" => track(e.source),
        "display" => display_dict(e.display),
    ) for e in all_exports(spec)]

    parameters = [Dict(
        "name" => p.name, "unit" => p.unit, "default" => p.default, "min" => p.min, "max" => p.max,
        "doc" => p.doc,
        "used_by" => [e.name for e in all_exports(spec) if any(first(a) == p.name for a in e.args)],
        "source" => track(p.source),
        "presets" => [Dict("label" => k, "value" => v) for (k, v) in p.presets],
        "display" => display_dict(p.display),
    ) for p in spec.parameters]

    alternatives = [Dict(
        "id" => a.id, "title" => a.title, "arg" => a.arg,
        "used_by" => [e.name for e in all_exports(spec) if any(first(x) == a.arg for x in e.args)],
        "options" => [Dict("value" => o.value, "key" => o.key, "label" => o.label,
                           "source" => track(o.source)) for o in a.options],
    ) for a in spec.alternatives]

    sources = [Dict("file" => f, "definitions" => [
        Dict("name" => n, "kind" => k, "lines" => l) for (n, k, l) in index[f]
    ]) for f in sort(collect(used_files))]

    return Dict(
        "schema" => 1, "step" => spec.step, "title" => spec.title, "question" => spec.question,
        "wasm" => "step$(spec.step).wasm",
        "precisions" => [first(p) for p in PRECISIONS],
        "functions" => functions, "parameters" => parameters, "alternatives" => alternatives,
        "sources" => sources, "requirements" => spec.requirements, "limits" => spec.limits,
    )
end
