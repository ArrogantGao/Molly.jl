# Chain rules to allow differentiable simulations

@non_differentiable check_force_units(args...)
@non_differentiable find_neighbors(args...)
@non_differentiable DistanceVecNeighborFinder(args...)
@non_differentiable all_neighbors(args...)
@non_differentiable run_loggers!(args...)
@non_differentiable visualize(args...)

function ChainRulesCore.rrule(T::Type{<:SVector}, vs::Number...)
    Y = T(vs...)
    function SVector_pullback(Ȳ)
        return NoTangent(), Ȳ...
    end
    return Y, SVector_pullback
end

function ChainRulesCore.rrule(T::Type{<:Atom}, vs...)
    Y = T(vs...)
    function Atom_pullback(Ȳ)
        return NoTangent(), Ȳ.index, Ȳ.charge, Ȳ.mass, Ȳ.σ, Ȳ.ϵ
    end
    return Y, Atom_pullback
end

function ChainRulesCore.rrule(T::Type{<:SpecificInteraction}, vs...)
    Y = T(vs...)
    function SpecificInteraction_pullback(Ȳ)
        return NoTangent(), Ȳ...
    end
    return Y, SpecificInteraction_pullback
end

function ChainRulesCore.rrule(T::Type{<:SpecificForce2Atoms}, vs...)
    Y = T(vs...)
    function SpecificForce2Atoms_pullback(Ȳ)
        return NoTangent(), Ȳ.f1, Ȳ.f2
    end
    return Y, SpecificForce2Atoms_pullback
end

function ChainRulesCore.rrule(T::Type{<:SpecificForce3Atoms}, vs...)
    Y = T(vs...)
    function SpecificForce3Atoms_pullback(Ȳ)
        return NoTangent(), Ȳ.f1, Ȳ.f2, Ȳ.f3
    end
    return Y, SpecificForce3Atoms_pullback
end

function ChainRulesCore.rrule(T::Type{<:SpecificForce4Atoms}, vs...)
    Y = T(vs...)
    function SpecificForce4Atoms_pullback(Ȳ)
        return NoTangent(), Ȳ.f1, Ȳ.f2, Ȳ.f3, Ȳ.f4
    end
    return Y, SpecificForce4Atoms_pullback
end

function ChainRulesCore.rrule(::typeof(sparsevec), is, vs, l)
    Y = sparsevec(is, vs, l)
    @views function sparsevec_pullback(Ȳ)
        return NoTangent(), nothing, Ȳ[is], nothing
    end
    return Y, sparsevec_pullback
end

function ChainRulesCore.rrule(::typeof(accumulateadd), x)
    Y = accumulateadd(x)
    function accumulateadd_pullback(Ȳ)
        return NoTangent(), reverse(accumulate(+, reverse(Ȳ)))
    end
    return Y, accumulateadd_pullback
end

function ChainRulesCore.rrule(::typeof(unsafe_getindex), arr, inds)
    Y = unsafe_getindex(arr, inds)
    function unsafe_getindex_pullback(Ȳ)
        dx = Zygote._zero(arr, eltype(Ȳ))
        dxv = @view dx[inds]
        dxv .= Zygote.accum.(dxv, Zygote._droplike(Ȳ, dxv))
        return NoTangent(), Zygote._project(x, dx), nothing
    end
    return Y, unsafe_getindex_pullback
end

# Only when on the GPU
function ChainRulesCore.rrule(::typeof(getindices_i), arr::CuArray, neighbors)
    Y = getindices_i(arr, neighbors)
    @views @inbounds function getindices_i_pullback(Ȳ)
        return NoTangent(), accumulate_bounds(Ȳ, neighbors.atom_bounds_i), nothing
    end
    return Y, getindices_i_pullback
end

function ChainRulesCore.rrule(::typeof(getindices_j), arr::CuArray, neighbors)
    Y = getindices_j(arr, neighbors)
    @views @inbounds function getindices_j_pullback(Ȳ)
        return NoTangent(), accumulate_bounds(Ȳ[neighbors.sortperm_j], neighbors.atom_bounds_j), nothing
    end
    return Y, getindices_j_pullback
end

# Required for SVector gradients in RescaleThermostat
function ChainRulesCore.rrule(::typeof(sqrt), x::Real)
    Y = sqrt(x)
    function sqrt_pullback(Ȳ)
        return NoTangent(), sum(Ȳ * inv(2 * Y))
    end
    return Y, sqrt_pullback
end
