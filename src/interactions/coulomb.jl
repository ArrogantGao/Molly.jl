"""
    Coulomb(; coulomb_const, cutoff, nl_only, force_unit, energy_unit)

The Coulomb electrostatic interaction.
"""
struct Coulomb{C, T, F, E} <: GeneralInteraction
    coulomb_const::T
    cutoff::C
    nl_only::Bool
    force_unit::F
    energy_unit::E
end

function Coulomb(;
                    coulomb_const=138.935458u"kJ * mol^-1 * nm * q^-2", # 1 / 4πϵ0
                    cutoff=NoCutoff(),
                    nl_only=false,
                    force_unit=u"kJ * mol^-1 * nm^-1",
                    energy_unit=u"kJ * mol^-1")
    return Coulomb{typeof(cutoff), typeof(coulomb_const), typeof(force_unit), typeof(energy_unit)}(
        coulomb_const, cutoff, nl_only, force_unit, energy_unit)
end

@inline @inbounds function force(inter::Coulomb{C},
                                    coord_i,
                                    coord_j,
                                    atom_i,
                                    atom_j,
                                    box_size) where C
    dr = vector(coord_i, coord_j, box_size)
    r2 = sum(abs2, dr)

    cutoff = inter.cutoff
    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge

    params = (coulomb_const, qi, qj)

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

@fastmath function force_divr_nocutoff(::Coulomb, r2, invr2, (coulomb_const, qi, qj))
    (coulomb_const * qi * qj) / √(r2 ^ 3)
end

@inline @inbounds function potential_energy(inter::Coulomb{C},
                                    s::Simulation,
                                    i::Integer,
                                    j::Integer) where C
    dr = vector(s.coords[i], s.coords[j], s.box_size)
    r2 = sum(abs2, dr)

    cutoff = inter.cutoff
    coulomb_const = inter.coulomb_const
    qi = s.atoms[i].charge
    qj = s.atoms[j].charge
    params = (coulomb_const, qi, qj)

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

@fastmath function potential(::Coulomb, r2, invr2, (coulomb_const, qi, qj))
    (coulomb_const * qi * qj) * √invr2
end
