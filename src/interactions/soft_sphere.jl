"""
    SoftSphere(; cutoff, nl_only, lorentz_mixing, force_unit, energy_unit, skip_shortcut)

The soft-sphere potential.
"""
struct SoftSphere{S, C, F, E} <: GeneralInteraction
    cutoff::C
    nl_only::Bool
    lorentz_mixing::Bool
    force_unit::F
    energy_unit::E
end

function SoftSphere(;
                    cutoff=NoCutoff(),
                    nl_only=false,
                    lorentz_mixing=true,
                    force_unit=u"kJ * mol^-1 * nm^-1",
                    energy_unit=u"kJ * mol^-1",
                    skip_shortcut=false)
    return SoftSphere{skip_shortcut, typeof(cutoff), typeof(force_unit), typeof(energy_unit)}(
        cutoff, nl_only, lorentz_mixing, force_unit, energy_unit)
end

@inline @inbounds function force(inter::SoftSphere{S, C},
                                    coord_i,
                                    coord_j,
                                    atom_i,
                                    atom_j,
                                    box_size) where {S, C}
    dr = vector(coord_i, coord_j, box_size)
    r2 = sum(abs2, dr)

    if !S && iszero(atom_i.σ) || iszero(atom_j.σ)
        return ustrip.(zero(coord_i)) * inter.force_unit
    end

    # Lorentz-Berthelot mixing rules use the arithmetic average for σ
    # Otherwise use the geometric average
    σ = inter.lorentz_mixing ? (atom_i.σ + atom_j.σ) / 2 : sqrt(atom_i.σ * atom_j.σ)
    ϵ = sqrt(atom_i.ϵ * atom_j.ϵ)

    cutoff = inter.cutoff
    σ2 = σ^2
    params = (σ2, ϵ)

    if cutoff_points(C) == 0
        f = force_divr_nocutoff(inter, r2, inv(r2), params)
    elseif cutoff_points(C) == 1
        r2 > cutoff.sqdist_cutoff && return ustrip.(zero(coord_i)) * inter.force_unit

        f = force_divr_cutoff(cutoff, r2, inter, params)
    elseif cutoff_points(C) == 2
        r2 > cutoff.sqdist_cutoff && return ustrip.(zero(coord_i)) * inter.force_unit

        if r2 < cutoff.activation_dist
            f = force_divr_nocutoff(inter, r2, inv(r2), params)
        else
            f = force_divr_cutoff(cutoff, r2, inter, params)
        end
    end

    return f * dr
end

@fastmath function force_divr_nocutoff(::SoftSphere, r2, invr2, (σ2, ϵ))
    six_term = (σ2 * invr2) ^ 3

    return (24ϵ * invr2) * 2 * six_term ^ 2
end

@inbounds function potential_energy(inter::SoftSphere{S, C},
                                    s::Simulation,
                                    i::Integer,
                                    j::Integer) where {S, C}
    dr = vector(s.coords[i], s.coords[j], s.box_size)
    r2 = sum(abs2, dr)

    if !S && iszero(s.atoms[i].σ) || iszero(s.atoms[j].σ)
        return ustrip(zero(s.timestep)) * inter.energy_unit
    end

    σ = inter.lorentz_mixing ? (s.atoms[i].σ + s.atoms[j].σ) / 2 : sqrt(s.atoms[i].σ * s.atoms[j].σ)
    ϵ = sqrt(s.atoms[i].ϵ * s.atoms[j].ϵ)

    cutoff = inter.cutoff
    σ2 = σ^2
    params = (σ2, ϵ)

    if cutoff_points(C) == 0
        potential(inter, r2, inv(r2), params)
    elseif cutoff_points(C) == 1
        r2 > cutoff.sqdist_cutoff && return ustrip(zero(s.timestep)) * inter.energy_unit

        potential_cutoff(cutoff, r2, inter, params)
    elseif cutoff_points(C) == 2
        r2 > cutoff.sqdist_cutoff && return ustrip(zero(s.timestep)) * inter.energy_unit

        if r2 < cutoff.activation_dist
            potential(inter, r2, inv(r2), params)
        else
            potential_cutoff(cutoff, r2, inter, params)
        end
    end
end

@fastmath function potential(::SoftSphere, r2, invr2, (σ2, ϵ))
    six_term = (σ2 * invr2) ^ 3

    return 4ϵ * (six_term ^ 2)
end
