doc"""
    Categorical(p)

A *Categorical distribution* is parameterized by a probability vector `p` (of length `K`).

$P(X = k) = p[k]  \quad \text{for } k = 1, 2, \ldots, K.$

```julia
Categorical(p)   # Categorical distribution with probability vector p

params(d)        # Get the parameters, i.e. (p,)
probs(d)         # Get the probability vector, i.e. p
ncategories(d)   # Get the number of categories, i.e. K
```

Here, `p` must be a real vector, of which all components are nonnegative and sum to one.

**Note:** The input vector `p` is directly used as a field of the constructed distribution, without being copied.

External links:

* [Categorical distribution on Wikipedia](http://en.wikipedia.org/wiki/Categorical_distribution)

"""
immutable Categorical <: DiscreteUnivariateDistribution
    K::Int
    p::Vector{Float64}

    Categorical(p::Vector{Float64}, ::NoArgCheck) = new(length(p), p)

    function Categorical(p::Vector{Float64})
        @check_args(Categorical, isprobvec(p))
        new(length(p), p)
    end

    function Categorical(k::Integer)
        @check_args(Categorical, k >= 1)
        new(k, fill(1.0/k, k))
    end
end

@distr_support Categorical 1 d.K


### Parameters

ncategories(d::Categorical) = d.K
probs(d::Categorical) = d.p
params(d::Categorical) = (d.p,)


### Statistics

function categorical_mean(p::AbstractArray{Float64})
    k = length(p)
    s = 0.
    for i = 1:k
        @inbounds s += p[i] * i
    end
    s
end

mean(d::Categorical) = categorical_mean(d.p)

function median(d::Categorical)
    k = ncategories(d)
    p = probs(d)
    cp = 0.
    i = 0
    while cp < 0.5 && i <= k
        i += 1
        @inbounds cp += p[i]
    end
    i
end

function var(d::Categorical)
    k = ncategories(d)
    p = probs(d)
    m = categorical_mean(p)
    s = 0.0
    for i = 1 : k
        @inbounds s += abs2(i - m) * p[i]
    end
    s
end

function skewness(d::Categorical)
    k = ncategories(d)
    p = probs(d)
    m = categorical_mean(p)
    s = 0.0
    for i = 1 : k
        @inbounds s += (i - m)^3 * p[i]
    end
    v = var(d)
    s / (v * sqrt(v))
end

function kurtosis(d::Categorical)
    k = ncategories(d)
    p = probs(d)
    m = categorical_mean(p)
    s = 0.0
    for i = 1 : k
        @inbounds s += (i - m)^4 * p[i]
    end
    s / abs2(var(d)) - 3.0
end

entropy(d::Categorical) = entropy(d.p)

function mgf(d::Categorical, t::Real)
    k = ncategories(d)
    p = probs(d)
    s = 0.0
    for i = 1 : k
        @inbounds s += p[i] * exp(t)
    end
    s
end

function cf(d::Categorical, t::Real)
    k = ncategories(d)
    p = probs(d)
    s = 0.0 + 0.0im
    for i = 1:k
        @inbounds s += p[i] * cis(t)
    end
    s
end

mode(d::Categorical) = indmax(probs(d))

function modes(d::Categorical)
    K = ncategories(d)
    p = probs(d)
    maxp = maximum(p)
    r = Array(Int, 0)
    for k = 1:K
        @inbounds if p[k] == maxp
            push!(r, k)
        end
    end
    r
end


### Evaluation

function cdf(d::Categorical, x::Int)
    k = ncategories(d)
    p = probs(d)
    x < 1 && return 0.0
    x >= k && return 1.0
    c = p[1]
    for i = 2:x
        @inbounds c += p[i]
    end
    return c
end

pdf(d::Categorical, x::Int) = insupport(d, x) ? d.p[x] : 0.0

logpdf(d::Categorical, x::Int) = insupport(d, x) ? log(d.p[x]) : -Inf

pdf(d::Categorical) = copy(d.p)

function _pdf!(r::AbstractArray, d::Categorical, rgn::UnitRange)
    vfirst = round(Int, first(rgn))
    vlast = round(Int, last(rgn))
    vl = max(vfirst, 1)
    vr = min(vlast, d.K)
    p = probs(d)
    if vl > vfirst
        for i = 1:(vl - vfirst)
            r[i] = 0.0
        end
    end
    fm1 = vfirst - 1
    for v = vl:vr
        r[v - fm1] = p[v]
    end
    if vr < vlast
        for i = (vr-vfirst+2):length(rgn)
            r[i] = 0.0
        end
    end
    return r
end


function quantile(d::Categorical, p::Float64)
    0.0 <= p <= 1.0 || throw(DomainError())
    k = ncategories(d)
    pv = probs(d)
    i = 1
    v = pv[1]
    while v < p && i < k
        i += 1
        @inbounds v += pv[i]
    end
    i
end


# sampling

sampler(d::Categorical) = AliasTable(d.p)


### sufficient statistics

immutable CategoricalStats <: SufficientStats
    h::Vector{Float64}
end

function add_categorical_counts!{T<:Integer}(h::Vector{Float64}, x::AbstractArray{T})
    for i = 1 : length(x)
        @inbounds xi = x[i]
        h[xi] += 1.   # cannot use @inbounds, as no guarantee that x[i] is in bound
    end
    h
end

function add_categorical_counts!{T<:Integer}(h::Vector{Float64}, x::AbstractArray{T}, w::AbstractArray{Float64})
    n = length(x)
    if n != length(w)
        throw(ArgumentError("Inconsistent array lengths."))
    end
    for i = 1 : n
        @inbounds xi = x[i]
        @inbounds wi = w[i]
        h[xi] += wi   # cannot use @inbounds, as no guarantee that x[i] is in bound
    end
    h
end

function suffstats{T<:Integer}(::Type{Categorical}, k::Int, x::AbstractArray{T})
    CategoricalStats(add_categorical_counts!(zeros(k), x))
end

function suffstats{T<:Integer}(::Type{Categorical}, k::Int, x::AbstractArray{T}, w::AbstractArray{Float64})
    CategoricalStats(add_categorical_counts!(zeros(k), x, w))
end

typealias CategoricalData Tuple{Int, AbstractArray}

suffstats(::Type{Categorical}, data::CategoricalData) = suffstats(Categorical, data...)
suffstats(::Type{Categorical}, data::CategoricalData, w::AbstractArray{Float64}) = suffstats(Categorical, data..., w)

# Model fitting

function fit_mle(::Type{Categorical}, ss::CategoricalStats)
    Categorical(pnormalize!(ss.h))
end

function fit_mle{T<:Integer}(::Type{Categorical}, k::Integer, x::AbstractArray{T})
    Categorical(pnormalize!(add_categorical_counts!(zeros(k), x)), NoArgCheck())
end

function fit_mle{T<:Integer}(::Type{Categorical}, k::Integer, x::AbstractArray{T}, w::AbstractArray{Float64})
    Categorical(pnormalize!(add_categorical_counts!(zeros(k), x, w)), NoArgCheck())
end

fit_mle(::Type{Categorical}, data::CategoricalData) = fit_mle(Categorical, data...)
fit_mle(::Type{Categorical}, data::CategoricalData, w::AbstractArray{Float64}) = fit_mle(Categorical, data..., w)

fit_mle{T<:Integer}(::Type{Categorical}, x::AbstractArray{T}) = fit_mle(Categorical, maximum(x), x)
fit_mle{T<:Integer}(::Type{Categorical}, x::AbstractArray{T}, w::AbstractArray{Float64}) = fit_mle(Categorical, maximum(x), x, w)

fit(::Type{Categorical}, data::CategoricalData) = fit_mle(Categorical, data)
fit(::Type{Categorical}, data::CategoricalData, w::AbstractArray{Float64}) = fit_mle(Categorical, data, w)
