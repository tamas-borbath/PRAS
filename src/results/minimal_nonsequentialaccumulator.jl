struct NonSequentialMinimalResultAccumulator{N,L,T,P,E} <:
    ResultAccumulator{Minimal,NonSequential}

    droppedcount_valsum::Vector{Float64}
    droppedcount_varsum::Vector{Float64}
    droppedsum_valsum::Vector{Float64}
    droppedsum_varsum::Vector{Float64}
    periodidx::Vector{Int}
    droppedcount_period::Vector{MeanVariance}
    droppedsum_period::Vector{MeanVariance}

end

function accumulator(
    ::Type{NonSequential}, resultspec::Minimal, sys::SystemModel{N,L,T,P,E}
) where {N,L,T,P,E}

    nthreads = Threads.nthreads()

    droppedcount_valsum = zeros(Float64, nthreads)
    droppedcount_varsum = zeros(Float64, nthreads)
    droppedsum_valsum = zeros(Float64, nthreads)
    droppedsum_varsum = zeros(Float64, nthreads)

    periodidx = zeros(Int, nthreads)
    periodcount = Vector{MeanVariance}(undef, nthreads)
    periodsum = Vector{MeanVariance}(undef, nthreads)

    Threads.@threads for i in 1:nthreads
        periodcount[i] = Series(Mean(), Variance())
        periodsum[i] = Series(Mean(), Variance())
    end

    return NonSequentialMinimalResultAccumulator{N,L,T,P,E}(
        droppedcount_valsum, droppedcount_varsum,
        droppedsum_valsum, droppedsum_varsum,
        periodidx, periodcount, periodsum)

end

function update!(
    acc::NonSequentialMinimalResultAccumulator,
    result::SystemOutputStateSummary, t::Int)

    thread = Threads.threadid()
    acc.droppedcount_valsum[thread] += result.lolp_system
    acc.droppedsum_valsum[thread] += sum(result.eue_regions)

    return

end

function update!(
    acc::NonSequentialMinimalResultAccumulator{N,L,T,P,E},
    sample::SystemOutputStateSample{L,T,P}, t::Int, i::Int
) where {N,L,T,P,E}

    thread = Threads.threadid()

    if t != acc.periodidx[thread]

        # Previous thread-local simulation has finished,
        # so store previous local result and reset

        transferperiodresults!(
            acc.droppedcount_valsum, acc.droppedcount_varsum,
            acc.droppedcount_period, thread)

        transferperiodresults!(
            acc.droppedsum_valsum, acc.droppedsum_varsum,
            acc.droppedsum_period, thread)

        acc.periodidx[thread] = t

    end

    isshortfall, droppedpower = droppedload(sample)
    droppedenergy = powertoenergy(E, droppedpower, P, L, T)

    fit!(acc.droppedcount_period[thread], isshortfall)
    fit!(acc.droppedsum_period[thread], droppedenergy)

    return

end

function finalize(
    cache::SimulationCache{N,L,T,P,E},
    acc::NonSequentialMinimalResultAccumulator{N,L,T,P,E}
) where {N,L,T,P,E}

    # Add the final local results
    for thread in 1:Threads.nthreads()

        transferperiodresults!(
            acc.droppedcount_valsum, acc.droppedcount_varsum,
            acc.droppedcount_period, thread)

        transferperiodresults!(
            acc.droppedsum_valsum, acc.droppedsum_varsum,
            acc.droppedsum_period, thread)

    end

    # Combine per-thread totals

    lole = sum(acc.droppedcount_valsum)
    eue = sum(acc.droppedsum_valsum)

    if ismontecarlo(cache.simulationspec)
        nsamples = cache.simulationspec.nsamples
        lole_stderr = sqrt(sum(acc.droppedcount_varsum) ./ nsamples)
        eue_stderr = sqrt(sum(acc.droppedsum_varsum) ./ nsamples)
    else
        lole_stderr = eue_stderr = 0.
    end

    return MinimalResult(
        LOLE{N,L,T}(lole, lole_stderr),
        EUE{N,L,T,E}(eue, eue_stderr),
        cache.simulationspec)

end
