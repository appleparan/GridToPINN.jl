# bridge.jl — JS가 Vector{T}를 읽고 쓰기 위한 최소 도우미 (인덱스는 1부터, Int32는 JS 숫자).
# 값 하나씩 꺼내는 방식이며 비용은 wasm/bench.mjs로 잰다. 계산은 없다.

vec_len(v::Vector{T}) where {T} = Int32(length(v))
vec_get(v::Vector{T}, i::Int32) where {T} = v[Int(i)]
vec_set(v::Vector{T}, i::Int32, x::T) where {T} = (v[Int(i)] = x)

# 만들기는 T를 인자에서 알 수 없어 정밀도마다 한 줄씩 둔다.
vec_new_f64(n::Int32) = zeros(Float64, Int(n))
vec_new_f32(n::Int32) = zeros(Float32, Int(n))

const BRIDGE_EXPORTS = [
    Export("vec_new", Dict{DataType,Function}(Float64 => vec_new_f64, Float32 => vec_new_f32),
           "n:int", "vec", "", "길이 n인 0 벡터를 만든다. (브리지 도우미)"),
    Export("vec_len", vec_len, "v:vec", "int", "", "벡터 길이. (브리지 도우미)"),
    Export("vec_get", vec_get, "v:vec i:int", "real", "", "v[i], i는 1부터. (브리지 도우미)"),
    Export("vec_set", vec_set, "v:vec i:int x", "real", "", "v[i] = x 하고 x를 돌려준다. (브리지 도우미)"),
]

# 모든 단계가 같은 도우미를 내보내므로 패리티 사례도 하나를 같이 쓴다.
const BRIDGE_CASE = Case("vector bridge", [
    op("vec_new", 4; bind = "v"),
    op("vec_set", :v, 2, 3.5),
    op("vec_get", :v, 2), op("vec_get", :v, 3), op("vec_len", :v),
])
