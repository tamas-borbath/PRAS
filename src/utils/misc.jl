CapacityDistribution{T} =
    DiscreteNonParametric{T,Float64,Vector{T},Vector{Float64}}

CapacitySampler{T} =
    DiscreteNonParametricSampler{
        T, Vector{T},
        AliasTable{SamplerRangeFast{UInt64,Int64}}}

SumVariance{T} = Series{
    Number, Tuple{Sum{T}, Variance{T, EqualWeight}}
}

MeanVariance{T} = Series{
    Number, Tuple{Mean{T, EqualWeight}, Variance{T, EqualWeight}}
}

function makemetric(f, mv::MeanVariance)
    nsamples = first(mv.stats).n
    samplemean, samplevar = value(mv)
    return f(samplemean, nsamples > 1 ? sqrt(samplevar / nsamples) : 0.)
end

function mean_stderr(mv::MeanVariance, nsamples::Int)
    samplemean, samplevar = value(mv)
    return (samplemean, sqrt(samplevar / nsamples))
end

function findfirstunique(a::AbstractVector{T}, i::T) where T
    i_idx = findfirst(isequal(i), a)
    i_idx === nothing && throw(BoundsError(a))
    return i_idx
end

"""
Generate a vector of `n` MersenneTwister random number generators, derived from
a MersenneTwister seeded with `seed`, with `step` steps between each generated
RNG.
"""
function initrngs(n::Int; seed::UInt=rand(UInt), step::Integer=big(10)^20)
    result = Vector{MersenneTwister}(undef, n)
    prev = MersenneTwister(seed)
    for i in 1:n
        prev = randjump(prev, step)
        result[i] = prev
    end
    return result
end

function transferperiodresults!(
    dest_sum::Array{V,N}, dest_var::Array{V,N},
    src::Array{MeanVariance{V},N}, idxs::Vararg{Int,N}) where {V,N}

    series = src[idxs...]

    # Do nothing if Series has no data
    if first(series.stats).n > 0
        s, v = value(series)
        dest_sum[idxs...] += s
        dest_var[idxs...] += v
        src[idxs...] = Series(Mean(), Variance())
    end

end

function assetgrouprange(starts::Vector{Int}, nassets::Int)

    ngroups = length(starts)
    ngroups == 0 && return Tuple{Int,Int}[]

    results = Vector{Tuple{Int,Int}}(undef, ngroups)

    i = 1
    while i < ngroups
        results[i] = (starts[i], starts[i+1]-1)
        i += 1
    end
    results[ngroups] = (starts[ngroups], nassets)

    return results

end

function colsum(x::Matrix{T}, col::Int) where {T}

    result = zero(T)

    for i in 1:size(x, 1)
        result += x[i, col]
    end

    return result

end
