# Extend Zygote to work with static vectors and custom types on the GPU
# Here be dragons

using ForwardDiff: Chunk, Dual, dualize, partials, value
using Zygote: unbroadcast

Zygote.accum(x::AbstractArray{<:SizedVector}, ys::AbstractArray{<:SVector}...) = Zygote.accum.(convert(typeof(ys[1]), x), ys...)
Zygote.accum(x::AbstractArray{<:SVector}, ys::AbstractArray{<:SizedVector}...) = Zygote.accum.(x, convert.(typeof(x), ys)...)

Base.:+(x::Real, y::SizedVector) = x .+ y
Base.:+(x::SizedVector, y::Real) = x .+ y

Base.:+(x::Real, y::Zygote.OneElement) = x .+ y
Base.:+(x::Zygote.OneElement, y::Real) = x .+ y

function Base.:+(x::Atom{T, T, T, T}, y::Atom{T, T, T, T}) where T
    Atom{T, T, T, T}(0, x.charge + y.charge, x.mass + y.mass, x.σ + y.σ, x.ϵ + y.ϵ)
end

function Base.:-(x::Atom{T, T, T, T}, y::Atom{T, T, T, T}) where T
    Atom{T, T, T, T}(0, x.charge - y.charge, x.mass - y.mass, x.σ - y.σ, x.ϵ - y.ϵ)
end

function Zygote.accum(x::LennardJones{S, C, W, F, E}, y::LennardJones{S, C, W, F, E}) where {S, C, W, F, E}
    LennardJones{S, C, W, F, E}(x.cutoff, x.nl_only, x.lorentz_mixing, x.weight_14 + y.weight_14, x.force_units, x.energy_units)
end

function Zygote.accum(x::CoulombReactionField{D, S, W, T, F, E}, y::CoulombReactionField{D, S, W, T, F, E}) where {D, S, W, T, F, E}
    CoulombReactionField{D, S, W, T, F, E}(x.dist_cutoff + y.dist_cutoff, x.solvent_dielectric + y.solvent_dielectric, x.nl_only,
                x.weight_14 + y.weight_14, x.coulomb_const + y.coulomb_const, x.force_units, x.energy_units)
end

function Zygote.accum_sum(xs::AbstractArray{Tuple{LennardJones{S, C, W, F, E}, CoulombReactionField{D, SO, W, T, F, E}}}; dims=:) where {S, C, W, F, E, D, SO, T}
    reduce(Zygote.accum, xs, dims=dims; init=(
        LennardJones{S, C, W, F, E}(nothing, false, false, zero(W), NoUnits, NoUnits),
        CoulombReactionField{D, SO, W, T, F, E}(zero(D), zero(S), false, zero(W), zero(T), NoUnits, NoUnits),
    ))
end

function Zygote.accum(x::Tuple{NTuple{N, Int}, NTuple{N, T}, NTuple{N, E}},
                        y::Tuple{NTuple{N, Int}, NTuple{N, T}, NTuple{N, E}}) where {N, T, E}
    ntuple(n -> 0, N), x[2] .+ y[2], x[3] .+ y[3]
end

Base.zero(::Type{Atom{T, T, T, T}}) where {T} = Atom(0, zero(T), zero(T), zero(T), zero(T))
atom_or_empty(at::Atom, T) = at
atom_or_empty(at::Nothing, T) = zero(Atom{T, T, T, T})

Zygote.z2d(dx::AbstractArray{Union{Nothing, Atom{T, T, T, T}}}, primal::AbstractArray{Atom{T, T, T, T}}) where {T} = atom_or_empty.(dx, T)
Zygote.z2d(dx::SVector{3, T}, primal::T) where {T} = sum(dx)

Zygote.unbroadcast(x::Tuple{Any}, x̄::Nothing) = nothing

function Zygote.unbroadcast(x::AbstractArray{<:Real}, x̄::AbstractArray{<:StaticVector})
    if length(x) == length(x̄)
        Zygote._project(x, sum.(x̄))
    else
        dims = ntuple(d -> size(x, d) == 1 ? d : ndims(x̄) + 1, ndims(x̄))
        Zygote._project(x, accum_sum(x̄; dims=dims))
    end
end

Zygote._zero(xs::AbstractArray{<:StaticVector}, T) = fill!(similar(xs, T), zero(T))

function Zygote._zero(xs::AbstractArray{Atom{T, T, T, T}}, ::Type{Atom{T, T, T, T}}) where {T}
    fill!(similar(xs), Atom{T, T, T, T}(0, zero(T), zero(T), zero(T), zero(T)))
end

function Base.zero(::Type{Union{Nothing, SizedVector{D, T, Vector{T}}}}) where {D, T}
    zero(SizedVector{D, T, Vector{T}})
end

# Slower version than in Zygote but doesn't give wrong gradients on the GPU for repeated indices
# Here we just move it to the CPU then move it back
# See https://github.com/FluxML/Zygote.jl/pull/1131
Zygote.∇getindex(x::CuArray, inds::Tuple{AbstractArray{<:Integer}}) = dy -> begin
    inds1_cpu = Array(inds[1])
    dx = Zygote._zero(Array(x), eltype(dy))
    dxv = view(dx, inds1_cpu)
    dxv .= Zygote.accum.(dxv, Zygote._droplike(Array(dy), dxv))
    return Zygote._project(x, cu(dx)), nothing
end

# Extend to add extra empty partials before (B) and after (A) the SVector partials
@generated function ForwardDiff.dualize(::Type{T}, x::StaticArray, ::Val{B}, ::Val{A}) where {T, B, A}
    N = length(x)
    dx = Expr(:tuple, [:(Dual{T}(x[$i], chunk, Val{$i + $B}())) for i in 1:N]...)
    V = StaticArrays.similar_type(x, Dual{T, eltype(x), N + B + A})
    return quote
        chunk = Chunk{$N + $B + $A}()
        $(Expr(:meta, :inline))
        return $V($(dx))
    end
end

# Dualize a value with extra partials
macro dualize(x, n_partials::Integer, active_partial::Integer)
    ps = [i == active_partial for i in 1:n_partials]
    return :(ForwardDiff.Dual($(esc(x)), $(ps...)))
end

# Space for 4 duals given to interactions though only one used in this case
# No gradient for cutoff type
function dualize_fb(inter::LennardJones{S, C, W, F, E}) where {S, C, W, F, E}
    w14 = inter.weight_14
    dual_weight_14 = @dualize(w14, 21, 1)
    return LennardJones{S, C, typeof(dual_weight_14), F, E}(inter.cutoff, inter.nl_only,
                inter.lorentz_mixing, dual_weight_14, inter.force_units, inter.energy_units)
end

function dualize_fb(inter::CoulombReactionField{D, S, W, T, F, E}) where {D, S, W, T, F, E}
    dc, sd, w14, cc = inter.dist_cutoff, inter.solvent_dielectric, inter.weight_14, inter.coulomb_const
    dual_dist_cutoff        = @dualize(dc , 21, 1)
    dual_solvent_dielectric = @dualize(sd , 21, 2)
    dual_weight_14          = @dualize(w14, 21, 3)
    dual_coulomb_const      = @dualize(cc , 21, 4)
    return CoulombReactionField{typeof(dual_dist_cutoff), typeof(dual_solvent_dielectric), typeof(dual_weight_14), typeof(dual_coulomb_const), F, E}(
                                dual_dist_cutoff, dual_solvent_dielectric, inter.nl_only, dual_weight_14,
                                dual_coulomb_const, inter.force_units, inter.energy_units)
end

function dualize_fb(inter::HarmonicBond{D, K}) where {D, K}
    b0, kb = inter.b0, inter.kb
    dual_b0 = @dualize(b0, 11, 1)
    dual_kb = @dualize(kb, 11, 2)
    return HarmonicBond{typeof(dual_b0), typeof(dual_kb)}(dual_b0, dual_kb)
end

function dualize_fb(inter::HarmonicAngle{D, K}) where {D, K}
    th0, cth = inter.th0, inter.cth
    dual_th0 = @dualize(th0, 14, 1)
    dual_cth = @dualize(cth, 14, 2)
    return HarmonicAngle{typeof(dual_th0), typeof(dual_cth)}(dual_th0, dual_cth)
end

function dualize_fb(inter::PeriodicTorsion{6, T, E}) where {T, E}
    p1, p2, p3, p4, p5, p6 = inter.phases
    k1, k2, k3, k4, k5, k6 = inter.ks
    dual_phases = (
        @dualize(p1, 27,  1), @dualize(p2, 27,  2), @dualize(p3, 27,  3),
        @dualize(p4, 27,  4), @dualize(p5, 27,  5), @dualize(p6, 27,  6),
    )
    dual_ks = (
        @dualize(k1, 27,  7), @dualize(k2, 27,  8), @dualize(k3, 27,  9),
        @dualize(k4, 27, 10), @dualize(k5, 27, 11), @dualize(k6, 27, 12),
    )
    return PeriodicTorsion{6, eltype(dual_phases), eltype(dual_ks)}(inter.periodicities,
                            dual_phases, dual_ks)
end

function dualize_atom_fb1(at::Atom)
    charge, mass, σ, ϵ = at.charge, at.mass, at.σ, at.ϵ
    dual_charge = @dualize(charge, 21, 11)
    dual_mass = @dualize(mass, 21, 12)
    dual_σ = @dualize(σ, 21, 13)
    dual_ϵ = @dualize(ϵ, 21, 14)
    return Atom{typeof(dual_charge), typeof(dual_mass), typeof(dual_σ), typeof(dual_ϵ)}(
                at.index, dual_charge, dual_mass, dual_σ, dual_ϵ)
end

function dualize_atom_fb2(at::Atom)
    charge, mass, σ, ϵ = at.charge, at.mass, at.σ, at.ϵ
    dual_charge = @dualize(charge, 21, 15)
    dual_mass = @dualize(mass, 21, 16)
    dual_σ = @dualize(σ, 21, 17)
    dual_ϵ = @dualize(ϵ, 21, 18)
    return Atom{typeof(dual_charge), typeof(dual_mass), typeof(dual_σ), typeof(dual_ϵ)}(
                at.index, dual_charge, dual_mass, dual_σ, dual_ϵ)
end

function dual_function_svec(f::F) where F
    function (arg1)
        ds1 = dualize(Nothing, arg1, Val(0), Val(0))
        return f(ds1)
    end
end

function dual_function_svec_real(f::F) where F
    function (arg1::SVector{D, T}, arg2) where {D, T}
        ds1 = dualize(Nothing, arg1, Val(0), Val(1))
        # Leaving the integer type in here results in Float32 -> Float64 conversion
        ds2 = Zygote.dual(isa(arg2, Int) ? T(arg2) : arg2, (false, false, false, true))
        return f(ds1, ds2)
    end
end

function dual_function_svec_svec(f::F) where F
    function (arg1, arg2)
        ds1 = dualize(Nothing, arg1, Val(0), Val(3))
        ds2 = dualize(Nothing, arg2, Val(3), Val(0))
        return f(ds1, ds2)
    end
end

function dual_function_atom(f::F) where F
    function (arg1)
        charge, mass, σ, ϵ = arg1.charge, arg1.mass, arg1.σ, arg1.ϵ
        ds1 = Atom(arg1.index, @dualize(charge, 4, 1), @dualize(mass, 4, 2),
                    @dualize(σ, 4, 3), @dualize(ϵ, 4, 4))
        return f(ds1)
    end
end

function dual_function_force_broadcast(f::F) where F
    function (arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
        ds1 = (dualize_fb(arg1[1]), dualize_fb(arg1[2])) # Only works for this case
        ds2 = dualize(Nothing, arg2, Val(4), Val(14))
        ds3 = dualize(Nothing, arg3, Val(7), Val(11))
        ds4 = dualize_atom_fb1(arg4)
        ds5 = dualize_atom_fb2(arg5)
        ds6 = dualize(Nothing, arg6, Val(18), Val(0))
        ds7 = arg7
        ds8 = arg8
        return f(ds1, ds2, ds3, ds4, ds5, ds6, ds7, ds8)
    end
end

function dual_function_specific_2_atoms(f::F) where F
    function (arg1, arg2, arg3, arg4)
        ds1 = dualize_fb(arg1)
        ds2 = dualize(Nothing, arg2, Val(2), Val(6))
        ds3 = dualize(Nothing, arg3, Val(5), Val(3))
        ds4 = dualize(Nothing, arg4, Val(8), Val(0))
        return f(ds1, ds2, ds3, ds4)
    end
end

function dual_function_specific_3_atoms(f::F) where F
    function (arg1, arg2, arg3, arg4, arg5)
        ds1 = dualize_fb(arg1)
        ds2 = dualize(Nothing, arg2, Val( 2), Val(9))
        ds3 = dualize(Nothing, arg3, Val( 5), Val(6))
        ds4 = dualize(Nothing, arg4, Val( 8), Val(3))
        ds5 = dualize(Nothing, arg5, Val(11), Val(0))
        return f(ds1, ds2, ds3, ds4, ds5)
    end
end

function dual_function_specific_4_atoms(f::F) where F
    function (arg1, arg2, arg3, arg4, arg5, arg6)
        ds1 = dualize_fb(arg1)
        ds2 = dualize(Nothing, arg2, Val(12), Val(12))
        ds3 = dualize(Nothing, arg3, Val(15), Val( 9))
        ds4 = dualize(Nothing, arg4, Val(18), Val( 6))
        ds5 = dualize(Nothing, arg5, Val(21), Val( 3))
        ds6 = dualize(Nothing, arg6, Val(24), Val( 0))
        return f(ds1, ds2, ds3, ds4, ds5, ds6)
    end
end

@inline function sum_partials(sv::SVector{3, Dual{Nothing, T, P}}, y1, i::Integer) where {T, P}
    partials(sv[1], i) * y1[1] + partials(sv[2], i) * y1[2] + partials(sv[3], i) * y1[3]
end

@inline function Zygote.broadcast_forward(f, arg1::AbstractArray{SVector{D, T}}) where {D, T}
    out = dual_function_svec(f).(arg1)
    y = map(x -> value.(x), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        barg1 = broadcast(ȳ, out) do y1, o1
            if length(y1) == 1
                y1 .* SVector{D, T}(partials(o1))
            else
                SVector{D, T}(sum_partials(o1, y1, 1), sum_partials(o1, y1, 2), sum_partials(o1, y1, 3))
            end
        end
        darg1 = unbroadcast(arg1, barg1)
        (nothing, nothing, darg1)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f, arg1::AbstractArray{SVector{D, T}}, arg2) where {D, T}
    out = dual_function_svec_real(f).(arg1, arg2)
    y = map(x -> value.(x), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        barg1 = broadcast(ȳ, out) do y1, o1
            if length(y1) == 1
                y1 .* SVector{D, T}(partials.((o1,), (1, 2, 3)))
            else
                SVector{D, T}(sum_partials(o1, y1, 1), sum_partials(o1, y1, 2), sum_partials(o1, y1, 3))
            end
        end
        darg1 = unbroadcast(arg1, barg1)
        darg2 = unbroadcast(arg2, broadcast((y1, o1) -> y1 .* partials.(o1, 4), ȳ, out))
        (nothing, nothing, darg1, darg2)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f, arg1::AbstractArray{SVector{D, T}}, arg2::AbstractArray{SVector{D, T}}) where {D, T}
    out = dual_function_svec_svec(f).(arg1, arg2)
    y = map(x -> value.(x), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        barg1 = broadcast(ȳ, out) do y1, o1
            if length(y1) == 1
                y1 .* SVector{D, T}(partials.((o1,), (1, 2, 3)))
            else
                SVector{D, T}(sum_partials(o1, y1, 1), sum_partials(o1, y1, 2), sum_partials(o1, y1, 3))
            end
        end
        darg1 = unbroadcast(arg1, barg1)
        barg2 = broadcast(ȳ, out) do y1, o1
            if length(y1) == 1
                y1 .* SVector{D, T}(partials.((o1,), (4, 5, 6)))
            else
                SVector{D, T}(sum_partials(o1, y1, 4), sum_partials(o1, y1, 5), sum_partials(o1, y1, 6))
            end
        end
        darg2 = unbroadcast(arg2, barg2)
        (nothing, nothing, darg1, darg2)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f, arg1::AbstractArray{<:Atom})
    out = dual_function_atom(f).(arg1)
    y = map(x -> value.(x), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        barg1 = broadcast(ȳ, out) do y1, o1
            ps = partials(o1)
            Atom(0, y1 * ps[1], y1 * ps[2], y1 * ps[3], y1 * ps[4])
        end
        darg1 = unbroadcast(arg1, barg1)
        (nothing, nothing, darg1)
    end
    return y, bc_fwd_back
end

function combine_dual_GeneralInteraction(y1::SVector{3, T}, o1::SVector{3, Dual{Nothing, T, P}}, i::Integer) where {T, P}
    (
        LennardJones{false, Nothing, T, typeof(NoUnits), typeof(NoUnits)}(
            nothing, false, false,
            y1[1] * partials(o1[1], i) + y1[2] * partials(o1[2], i) + y1[3] * partials(o1[3], i),
            NoUnits, NoUnits,
        ),
        CoulombReactionField{T, T, T, T, typeof(NoUnits), typeof(NoUnits)}(
            y1[1] * partials(o1[1], i    ) + y1[2] * partials(o1[2], i    ) + y1[3] * partials(o1[3], i    ),
            y1[1] * partials(o1[1], i + 1) + y1[2] * partials(o1[2], i + 1) + y1[3] * partials(o1[3], i + 1),
            false,
            y1[1] * partials(o1[1], i + 2) + y1[2] * partials(o1[2], i + 2) + y1[3] * partials(o1[3], i + 2),
            y1[1] * partials(o1[1], i + 3) + y1[2] * partials(o1[2], i + 3) + y1[3] * partials(o1[3], i + 3),
            NoUnits, NoUnits,
        ),
    )
end

function combine_dual_SpecificInteraction(inter::HarmonicBond, y1, o1, i::Integer)
    (y1.f1[1] * partials(o1.f1[1], i    ) + y1.f1[2] * partials(o1.f1[2], i    ) + y1.f1[3] * partials(o1.f1[3], i    ) + y1.f2[1] * partials(o1.f2[1], i    ) + y1.f2[2] * partials(o1.f2[2], i    ) + y1.f2[3] * partials(o1.f2[3], i    ),
     y1.f1[1] * partials(o1.f1[1], i + 1) + y1.f1[2] * partials(o1.f1[2], i + 1) + y1.f1[3] * partials(o1.f1[3], i + 1) + y1.f2[1] * partials(o1.f2[1], i + 1) + y1.f2[2] * partials(o1.f2[2], i + 1) + y1.f2[3] * partials(o1.f2[3], i + 1))
end

function combine_dual_SpecificInteraction(inter::HarmonicAngle, y1, o1, i::Integer)
    (y1.f1[1] * partials(o1.f1[1], i    ) + y1.f1[2] * partials(o1.f1[2], i    ) + y1.f1[3] * partials(o1.f1[3], i    ) + y1.f2[1] * partials(o1.f2[1], i    ) + y1.f2[2] * partials(o1.f2[2], i    ) + y1.f2[3] * partials(o1.f2[3], i    ) + y1.f3[1] * partials(o1.f3[1], i    ) + y1.f3[2] * partials(o1.f3[2], i    ) + y1.f3[3] * partials(o1.f3[3], i    ),
     y1.f1[1] * partials(o1.f1[1], i + 1) + y1.f1[2] * partials(o1.f1[2], i + 1) + y1.f1[3] * partials(o1.f1[3], i + 1) + y1.f2[1] * partials(o1.f2[1], i + 1) + y1.f2[2] * partials(o1.f2[2], i + 1) + y1.f2[3] * partials(o1.f2[3], i + 1) + y1.f3[1] * partials(o1.f3[1], i + 1) + y1.f3[2] * partials(o1.f3[2], i + 1) + y1.f3[3] * partials(o1.f3[3], i + 1))
end

function combine_dual_SpecificInteraction(inter::PeriodicTorsion{6}, y1, o1, i::Integer)
    (
        (0, 0, 0, 0, 0, 0),
        (
            y1.f1[1] * partials(o1.f1[1], i     ) + y1.f1[2] * partials(o1.f1[2], i     ) + y1.f1[3] * partials(o1.f1[3], i     ) + y1.f2[1] * partials(o1.f2[1], i     ) + y1.f2[2] * partials(o1.f2[2], i     ) + y1.f2[3] * partials(o1.f2[3], i     ) + y1.f3[1] * partials(o1.f3[1], i     ) + y1.f3[2] * partials(o1.f3[2], i     ) + y1.f3[3] * partials(o1.f3[3], i     ) + y1.f4[1] * partials(o1.f4[1], i     ) + y1.f4[2] * partials(o1.f4[2], i     ) + y1.f4[3] * partials(o1.f4[3], i     ),
            y1.f1[1] * partials(o1.f1[1], i +  1) + y1.f1[2] * partials(o1.f1[2], i +  1) + y1.f1[3] * partials(o1.f1[3], i +  1) + y1.f2[1] * partials(o1.f2[1], i +  1) + y1.f2[2] * partials(o1.f2[2], i +  1) + y1.f2[3] * partials(o1.f2[3], i +  1) + y1.f3[1] * partials(o1.f3[1], i +  1) + y1.f3[2] * partials(o1.f3[2], i +  1) + y1.f3[3] * partials(o1.f3[3], i +  1) + y1.f4[1] * partials(o1.f4[1], i +  1) + y1.f4[2] * partials(o1.f4[2], i +  1) + y1.f4[3] * partials(o1.f4[3], i +  1),
            y1.f1[1] * partials(o1.f1[1], i +  2) + y1.f1[2] * partials(o1.f1[2], i +  2) + y1.f1[3] * partials(o1.f1[3], i +  2) + y1.f2[1] * partials(o1.f2[1], i +  2) + y1.f2[2] * partials(o1.f2[2], i +  2) + y1.f2[3] * partials(o1.f2[3], i +  2) + y1.f3[1] * partials(o1.f3[1], i +  2) + y1.f3[2] * partials(o1.f3[2], i +  2) + y1.f3[3] * partials(o1.f3[3], i +  2) + y1.f4[1] * partials(o1.f4[1], i +  2) + y1.f4[2] * partials(o1.f4[2], i +  2) + y1.f4[3] * partials(o1.f4[3], i +  2),
            y1.f1[1] * partials(o1.f1[1], i +  3) + y1.f1[2] * partials(o1.f1[2], i +  3) + y1.f1[3] * partials(o1.f1[3], i +  3) + y1.f2[1] * partials(o1.f2[1], i +  3) + y1.f2[2] * partials(o1.f2[2], i +  3) + y1.f2[3] * partials(o1.f2[3], i +  3) + y1.f3[1] * partials(o1.f3[1], i +  3) + y1.f3[2] * partials(o1.f3[2], i +  3) + y1.f3[3] * partials(o1.f3[3], i +  3) + y1.f4[1] * partials(o1.f4[1], i +  3) + y1.f4[2] * partials(o1.f4[2], i +  3) + y1.f4[3] * partials(o1.f4[3], i +  3),
            y1.f1[1] * partials(o1.f1[1], i +  4) + y1.f1[2] * partials(o1.f1[2], i +  4) + y1.f1[3] * partials(o1.f1[3], i +  4) + y1.f2[1] * partials(o1.f2[1], i +  4) + y1.f2[2] * partials(o1.f2[2], i +  4) + y1.f2[3] * partials(o1.f2[3], i +  4) + y1.f3[1] * partials(o1.f3[1], i +  4) + y1.f3[2] * partials(o1.f3[2], i +  4) + y1.f3[3] * partials(o1.f3[3], i +  4) + y1.f4[1] * partials(o1.f4[1], i +  4) + y1.f4[2] * partials(o1.f4[2], i +  4) + y1.f4[3] * partials(o1.f4[3], i +  4),
            y1.f1[1] * partials(o1.f1[1], i +  5) + y1.f1[2] * partials(o1.f1[2], i +  5) + y1.f1[3] * partials(o1.f1[3], i +  5) + y1.f2[1] * partials(o1.f2[1], i +  5) + y1.f2[2] * partials(o1.f2[2], i +  5) + y1.f2[3] * partials(o1.f2[3], i +  5) + y1.f3[1] * partials(o1.f3[1], i +  5) + y1.f3[2] * partials(o1.f3[2], i +  5) + y1.f3[3] * partials(o1.f3[3], i +  5) + y1.f4[1] * partials(o1.f4[1], i +  5) + y1.f4[2] * partials(o1.f4[2], i +  5) + y1.f4[3] * partials(o1.f4[3], i +  5),
        ),
        (
            y1.f1[1] * partials(o1.f1[1], i +  6) + y1.f1[2] * partials(o1.f1[2], i +  6) + y1.f1[3] * partials(o1.f1[3], i +  6) + y1.f2[1] * partials(o1.f2[1], i +  6) + y1.f2[2] * partials(o1.f2[2], i +  6) + y1.f2[3] * partials(o1.f2[3], i +  6) + y1.f3[1] * partials(o1.f3[1], i +  6) + y1.f3[2] * partials(o1.f3[2], i +  6) + y1.f3[3] * partials(o1.f3[3], i +  6) + y1.f4[1] * partials(o1.f4[1], i +  6) + y1.f4[2] * partials(o1.f4[2], i +  6) + y1.f4[3] * partials(o1.f4[3], i +  6),
            y1.f1[1] * partials(o1.f1[1], i +  7) + y1.f1[2] * partials(o1.f1[2], i +  7) + y1.f1[3] * partials(o1.f1[3], i +  7) + y1.f2[1] * partials(o1.f2[1], i +  7) + y1.f2[2] * partials(o1.f2[2], i +  7) + y1.f2[3] * partials(o1.f2[3], i +  7) + y1.f3[1] * partials(o1.f3[1], i +  7) + y1.f3[2] * partials(o1.f3[2], i +  7) + y1.f3[3] * partials(o1.f3[3], i +  7) + y1.f4[1] * partials(o1.f4[1], i +  7) + y1.f4[2] * partials(o1.f4[2], i +  7) + y1.f4[3] * partials(o1.f4[3], i +  7),
            y1.f1[1] * partials(o1.f1[1], i +  8) + y1.f1[2] * partials(o1.f1[2], i +  8) + y1.f1[3] * partials(o1.f1[3], i +  8) + y1.f2[1] * partials(o1.f2[1], i +  8) + y1.f2[2] * partials(o1.f2[2], i +  8) + y1.f2[3] * partials(o1.f2[3], i +  8) + y1.f3[1] * partials(o1.f3[1], i +  8) + y1.f3[2] * partials(o1.f3[2], i +  8) + y1.f3[3] * partials(o1.f3[3], i +  8) + y1.f4[1] * partials(o1.f4[1], i +  8) + y1.f4[2] * partials(o1.f4[2], i +  8) + y1.f4[3] * partials(o1.f4[3], i +  8),
            y1.f1[1] * partials(o1.f1[1], i +  9) + y1.f1[2] * partials(o1.f1[2], i +  9) + y1.f1[3] * partials(o1.f1[3], i +  9) + y1.f2[1] * partials(o1.f2[1], i +  9) + y1.f2[2] * partials(o1.f2[2], i +  9) + y1.f2[3] * partials(o1.f2[3], i +  9) + y1.f3[1] * partials(o1.f3[1], i +  9) + y1.f3[2] * partials(o1.f3[2], i +  9) + y1.f3[3] * partials(o1.f3[3], i +  9) + y1.f4[1] * partials(o1.f4[1], i +  9) + y1.f4[2] * partials(o1.f4[2], i +  9) + y1.f4[3] * partials(o1.f4[3], i +  9),
            y1.f1[1] * partials(o1.f1[1], i + 10) + y1.f1[2] * partials(o1.f1[2], i + 10) + y1.f1[3] * partials(o1.f1[3], i + 10) + y1.f2[1] * partials(o1.f2[1], i + 10) + y1.f2[2] * partials(o1.f2[2], i + 10) + y1.f2[3] * partials(o1.f2[3], i + 10) + y1.f3[1] * partials(o1.f3[1], i + 10) + y1.f3[2] * partials(o1.f3[2], i + 10) + y1.f3[3] * partials(o1.f3[3], i + 10) + y1.f4[1] * partials(o1.f4[1], i + 10) + y1.f4[2] * partials(o1.f4[2], i + 10) + y1.f4[3] * partials(o1.f4[3], i + 10),
            y1.f1[1] * partials(o1.f1[1], i + 11) + y1.f1[2] * partials(o1.f1[2], i + 11) + y1.f1[3] * partials(o1.f1[3], i + 11) + y1.f2[1] * partials(o1.f2[1], i + 11) + y1.f2[2] * partials(o1.f2[2], i + 11) + y1.f2[3] * partials(o1.f2[3], i + 11) + y1.f3[1] * partials(o1.f3[1], i + 11) + y1.f3[2] * partials(o1.f3[2], i + 11) + y1.f3[3] * partials(o1.f3[3], i + 11) + y1.f4[1] * partials(o1.f4[1], i + 11) + y1.f4[2] * partials(o1.f4[2], i + 11) + y1.f4[3] * partials(o1.f4[3], i + 11),
        ),
    )
end

function combine_dual_Atom(y1::SVector{3, T}, o1::SVector{3, Dual{Nothing, T, P}}, i::Integer, j::Integer, k::Integer, l::Integer) where {T, P}
    ps1, ps2, ps3 = partials(o1[1]), partials(o1[2]), partials(o1[3])
    Atom(
        0,
        y1[1] * ps1[i] + y1[2] * ps2[i] + y1[3] * ps3[i],
        y1[1] * ps1[j] + y1[2] * ps2[j] + y1[3] * ps3[j],
        y1[1] * ps1[k] + y1[2] * ps2[k] + y1[3] * ps3[k],
        y1[1] * ps1[l] + y1[2] * ps2[l] + y1[3] * ps3[l],
    )
end

@inline function Zygote.broadcast_forward(f,
                                            arg1,
                                            arg2::AbstractArray{SVector{D, T}},
                                            arg3::AbstractArray{SVector{D, T}},
                                            arg4::AbstractArray{<:Atom},
                                            arg5::AbstractArray{<:Atom},
                                            arg6::Tuple{SVector{D, T}},
                                            arg7::Base.RefValue{<:Unitful.FreeUnits},
                                            arg8) where {D, T}
    out = dual_function_force_broadcast(f).(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    y = map(x -> value.(x), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg2 isa CuArray ? cu(ȳ_in) : ȳ_in
        darg1 = unbroadcast(arg1, broadcast(combine_dual_GeneralInteraction, ȳ, out, 1))
        darg2 = unbroadcast(arg2, broadcast((y1, o1) -> SVector{D, T}(sum_partials(o1, y1,  5),
                                sum_partials(o1, y1,  6), sum_partials(o1, y1,  7)), ȳ, out))
        darg3 = unbroadcast(arg3, broadcast((y1, o1) -> SVector{D, T}(sum_partials(o1, y1,  8),
                                sum_partials(o1, y1,  9), sum_partials(o1, y1, 10)), ȳ, out))
        darg4 = unbroadcast(arg4, broadcast(combine_dual_Atom, ȳ, out, 11, 12, 13, 14))
        darg5 = unbroadcast(arg5, broadcast(combine_dual_Atom, ȳ, out, 15, 16, 17, 18))
        darg6 = unbroadcast(arg6, broadcast((y1, o1) -> SVector{D, T}(sum_partials(o1, y1, 19),
                                sum_partials(o1, y1, 20), sum_partials(o1, y1, 21)), ȳ, out))
        darg7 = nothing
        darg8 = nothing
        return (nothing, nothing, darg1, darg2, darg3, darg4, darg5, darg6, darg7, darg8)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f,
                                            arg1::AbstractArray{<:SpecificInteraction},
                                            arg2::AbstractArray{SVector{D, T}},
                                            arg3::AbstractArray{SVector{D, T}},
                                            arg4::Tuple{SVector{D, T}}) where {D, T}
    out = dual_function_specific_2_atoms(f).(arg1, arg2, arg3, arg4)
    y = broadcast(o1 -> SpecificForce2Atoms{D, T}(value.(o1.f1), value.(o1.f2)), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        darg1 = unbroadcast(arg1, broadcast(combine_dual_SpecificInteraction, arg1, ȳ, out, 1))
        darg2 = unbroadcast(arg2, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 3) + sum_partials(o1.f2, y1.f2, 3),
                    sum_partials(o1.f1, y1.f1, 4) + sum_partials(o1.f2, y1.f2, 4),
                    sum_partials(o1.f1, y1.f1, 5) + sum_partials(o1.f2, y1.f2, 5)),
                    ȳ, out))
        darg3 = unbroadcast(arg3, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 6) + sum_partials(o1.f2, y1.f2, 6),
                    sum_partials(o1.f1, y1.f1, 7) + sum_partials(o1.f2, y1.f2, 7),
                    sum_partials(o1.f1, y1.f1, 8) + sum_partials(o1.f2, y1.f2, 8)),
                    ȳ, out))
        darg4 = unbroadcast(arg4, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1,  9) + sum_partials(o1.f2, y1.f2,  9),
                    sum_partials(o1.f1, y1.f1, 10) + sum_partials(o1.f2, y1.f2, 10),
                    sum_partials(o1.f1, y1.f1, 11) + sum_partials(o1.f2, y1.f2, 11)),
                    ȳ, out))
        return (nothing, nothing, darg1, darg2, darg3, darg4)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f,
                                            arg1::AbstractArray{<:SpecificInteraction},
                                            arg2::AbstractArray{SVector{D, T}},
                                            arg3::AbstractArray{SVector{D, T}},
                                            arg4::AbstractArray{SVector{D, T}},
                                            arg5::Tuple{SVector{D, T}}) where {D, T}
    out = dual_function_specific_3_atoms(f).(arg1, arg2, arg3, arg4, arg5)
    y = broadcast(o1 -> SpecificForce3Atoms{D, T}(value.(o1.f1), value.(o1.f2), value.(o1.f3)), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        darg1 = unbroadcast(arg1, broadcast(combine_dual_SpecificInteraction, arg1, ȳ, out, 1))
        darg2 = unbroadcast(arg2, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 3) + sum_partials(o1.f2, y1.f2, 3) + sum_partials(o1.f3, y1.f3, 3),
                    sum_partials(o1.f1, y1.f1, 4) + sum_partials(o1.f2, y1.f2, 4) + sum_partials(o1.f3, y1.f3, 4),
                    sum_partials(o1.f1, y1.f1, 5) + sum_partials(o1.f2, y1.f2, 5) + sum_partials(o1.f3, y1.f3, 5)),
                    ȳ, out))
        darg3 = unbroadcast(arg3, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 6) + sum_partials(o1.f2, y1.f2, 6) + sum_partials(o1.f3, y1.f3, 6),
                    sum_partials(o1.f1, y1.f1, 7) + sum_partials(o1.f2, y1.f2, 7) + sum_partials(o1.f3, y1.f3, 7),
                    sum_partials(o1.f1, y1.f1, 8) + sum_partials(o1.f2, y1.f2, 8) + sum_partials(o1.f3, y1.f3, 8)),
                    ȳ, out))
        darg4 = unbroadcast(arg4, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1,  9) + sum_partials(o1.f2, y1.f2,  9) + sum_partials(o1.f3, y1.f3,  9),
                    sum_partials(o1.f1, y1.f1, 10) + sum_partials(o1.f2, y1.f2, 10) + sum_partials(o1.f3, y1.f3, 10),
                    sum_partials(o1.f1, y1.f1, 11) + sum_partials(o1.f2, y1.f2, 11) + sum_partials(o1.f3, y1.f3, 11)),
                    ȳ, out))
        darg5 = unbroadcast(arg5, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 12) + sum_partials(o1.f2, y1.f2, 12) + sum_partials(o1.f3, y1.f3, 12),
                    sum_partials(o1.f1, y1.f1, 13) + sum_partials(o1.f2, y1.f2, 13) + sum_partials(o1.f3, y1.f3, 13),
                    sum_partials(o1.f1, y1.f1, 14) + sum_partials(o1.f2, y1.f2, 14) + sum_partials(o1.f3, y1.f3, 14)),
                    ȳ, out))
        return (nothing, nothing, darg1, darg2, darg3, darg4, darg5)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f,
                                            arg1::AbstractArray{<:SpecificInteraction},
                                            arg2::AbstractArray{SVector{D, T}},
                                            arg3::AbstractArray{SVector{D, T}},
                                            arg4::AbstractArray{SVector{D, T}},
                                            arg5::AbstractArray{SVector{D, T}},
                                            arg6::Tuple{SVector{D, T}}) where {D, T}
    out = dual_function_specific_4_atoms(f).(arg1, arg2, arg3, arg4, arg5, arg6)
    y = broadcast(o1 -> SpecificForce4Atoms{D, T}(value.(o1.f1), value.(o1.f2), value.(o1.f3), value.(o1.f4)), out)
    function bc_fwd_back(ȳ_in)
        ȳ = arg1 isa CuArray ? cu(ȳ_in) : ȳ_in
        darg1 = unbroadcast(arg1, broadcast(combine_dual_SpecificInteraction, arg1, ȳ, out, 1))
        darg2 = unbroadcast(arg2, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 13) + sum_partials(o1.f2, y1.f2, 13) + sum_partials(o1.f3, y1.f3, 13) + sum_partials(o1.f4, y1.f4, 13),
                    sum_partials(o1.f1, y1.f1, 14) + sum_partials(o1.f2, y1.f2, 14) + sum_partials(o1.f3, y1.f3, 14) + sum_partials(o1.f4, y1.f4, 14),
                    sum_partials(o1.f1, y1.f1, 15) + sum_partials(o1.f2, y1.f2, 15) + sum_partials(o1.f3, y1.f3, 15) + sum_partials(o1.f4, y1.f4, 15)),
                    ȳ, out))
        darg3 = unbroadcast(arg3, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 16) + sum_partials(o1.f2, y1.f2, 16) + sum_partials(o1.f3, y1.f3, 16) + sum_partials(o1.f4, y1.f4, 16),
                    sum_partials(o1.f1, y1.f1, 17) + sum_partials(o1.f2, y1.f2, 17) + sum_partials(o1.f3, y1.f3, 17) + sum_partials(o1.f4, y1.f4, 17),
                    sum_partials(o1.f1, y1.f1, 18) + sum_partials(o1.f2, y1.f2, 18) + sum_partials(o1.f3, y1.f3, 18) + sum_partials(o1.f4, y1.f4, 18)),
                    ȳ, out))
        darg4 = unbroadcast(arg4, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 19) + sum_partials(o1.f2, y1.f2, 19) + sum_partials(o1.f3, y1.f3, 19) + sum_partials(o1.f4, y1.f4, 19),
                    sum_partials(o1.f1, y1.f1, 20) + sum_partials(o1.f2, y1.f2, 20) + sum_partials(o1.f3, y1.f3, 20) + sum_partials(o1.f4, y1.f4, 20),
                    sum_partials(o1.f1, y1.f1, 21) + sum_partials(o1.f2, y1.f2, 21) + sum_partials(o1.f3, y1.f3, 21) + sum_partials(o1.f4, y1.f4, 21)),
                    ȳ, out))
        darg5 = unbroadcast(arg5, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 22) + sum_partials(o1.f2, y1.f2, 22) + sum_partials(o1.f3, y1.f3, 22) + sum_partials(o1.f4, y1.f4, 22),
                    sum_partials(o1.f1, y1.f1, 23) + sum_partials(o1.f2, y1.f2, 23) + sum_partials(o1.f3, y1.f3, 23) + sum_partials(o1.f4, y1.f4, 23),
                    sum_partials(o1.f1, y1.f1, 24) + sum_partials(o1.f2, y1.f2, 24) + sum_partials(o1.f3, y1.f3, 24) + sum_partials(o1.f4, y1.f4, 24)),
                    ȳ, out))
        darg6 = unbroadcast(arg6, broadcast((y1, o1) -> SVector{D, T}(
                    sum_partials(o1.f1, y1.f1, 25) + sum_partials(o1.f2, y1.f2, 25) + sum_partials(o1.f3, y1.f3, 25) + sum_partials(o1.f4, y1.f4, 25),
                    sum_partials(o1.f1, y1.f1, 26) + sum_partials(o1.f2, y1.f2, 26) + sum_partials(o1.f3, y1.f3, 26) + sum_partials(o1.f4, y1.f4, 26),
                    sum_partials(o1.f1, y1.f1, 27) + sum_partials(o1.f2, y1.f2, 27) + sum_partials(o1.f3, y1.f3, 27) + sum_partials(o1.f4, y1.f4, 27)),
                    ȳ, out))
        return (nothing, nothing, darg1, darg2, darg3, darg4, darg5, darg6)
    end
    return y, bc_fwd_back
end

@inline function Zygote.broadcast_forward(f::typeof(getf1),
                                            arg1::AbstractArray{<:SpecificForce2Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=y1, f2=zero(y1)), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf1),
                                            arg1::AbstractArray{<:SpecificForce3Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=y1, f2=zero(y1), f3=zero(y1)), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf1),
                                            arg1::AbstractArray{<:SpecificForce4Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=y1, f2=zero(y1), f3=zero(y1), f4=zero(y1)), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf2),
                                            arg1::AbstractArray{<:SpecificForce2Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=zero(y1), f2=y1), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf2),
                                            arg1::AbstractArray{<:SpecificForce3Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=zero(y1), f2=y1, f3=zero(y1)), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf2),
                                            arg1::AbstractArray{<:SpecificForce4Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=zero(y1), f2=y1, f3=zero(y1), f4=zero(y1)), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf3),
                                            arg1::AbstractArray{<:SpecificForce3Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=zero(y1), f2=zero(y1), f3=y1), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf3),
                                            arg1::AbstractArray{<:SpecificForce4Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=zero(y1), f2=zero(y1), f3=y1, f4=zero(y1)), ȳ)))
end

@inline function Zygote.broadcast_forward(f::typeof(getf4),
                                            arg1::AbstractArray{<:SpecificForce4Atoms}) where {D, T}
    return f.(arg1), ȳ -> (nothing, nothing, unbroadcast(arg1, broadcast(y1 -> (f1=zero(y1), f2=zero(y1), f3=zero(y1), f4=y1), ȳ)))
end

# Use fast broadcast path on CPU
for op in (:+, :-, :*, :/, :force, :force_nounit, :mass, :remove_molar, :ustrip,
            :ustrip_vec, :wrap_coords_vec, :getf1, :getf2, :getf3, :getf4)
    @eval Zygote.@adjoint Broadcast.broadcasted(::Broadcast.AbstractArrayStyle, f::typeof($op), args...) = Zygote.broadcast_forward(f, args...)
    # Avoid ambiguous dispatch
    @eval Zygote.@adjoint Broadcast.broadcasted(::CUDA.AbstractGPUArrayStyle  , f::typeof($op), args...) = Zygote.broadcast_forward(f, args...)
end
