export ustrip_vec

"""
    ustrip_vec(x)
    ustrip_vec(u, x)

Broadcasted form of `ustrip` from Unitful.jl, allowing e.g. `ustrip_vec.(coords)`.
"""
ustrip_vec(x...) = ustrip.(x...)

"""
Parses the length, mass, velocity, energy and force units and verifies they are correct and consistent
with other parameters passed to the `System`.
"""
function check_units(atoms, coords, velocities, energy_units, force_units,
                p_inters, s_inters, g_inters, boundary, constraints)
    masses = mass.(atoms)
    sys_units = check_system_units(masses, coords, velocities, energy_units, force_units)

    check_interaction_units(p_inters, s_inters, g_inters, sys_units)
    check_other_units(atoms, boundary, constraints, sys_units)

    return sys_units
end

function check_system_units(masses, coords, velocities, energy_units, force_units)
    
    length_dim, length_units = validate_coords(coords)
    vel_dim, vel_units = validate_velocities(velocities)
    force_dim = dimension(force_units)
    energy_dim = dimension(energy_units)
    mass_dim, mass_units = validate_masses(masses)
    validate_energy_units(energy_units)

    forceIsMolar = (force_dim == u"𝐋 * 𝐌 * 𝐍^-1 * 𝐓^-2")
    energyIsMolar = (energy_dim == u"𝐋^2 * 𝐌 * 𝐍^-1 * 𝐓^-2")
    massIsMolar = (mass_dim == u"𝐌* 𝐍^-1")
    
    if !allequal([energyIsMolar, massIsMolar, forceIsMolar])
        throw(ArgumentError("""System was constructed with inconsistent energy, force & mass units.\
         All must be molar, non-molar or unitless. For example, kcal & kg are allowed but kcal/mol\
         and kg is not allowed. Units were: $([energy_units, mass_units, force_units])"""))
    end

    no_dim_arr = [dim == NoDims for dim in [length_dim, vel_dim, energy_dim, force_dim, mass_dim]]

    # If something has NoDims, all other data must have NoDims
    if any(no_dim_arr) && !all(no_dim_arr)
        throw(ArgumentError("""Either coords, velocities, masses or energy_units has NoDims/NoUnits but\
         the others do have units. Molly does not permit mixing dimensionless and dimensioned data."""))
    end

    #Check derived units
    if force_units != (energy_units / length_units)
        throw(ArgumentError("Force unit was specified as $(force_units), but that unit could not be re-derived
            from the length units in coords and the energy_units passed to `System`"))
    end

    #TODO: How do I check velocity units are length_units / time and not something stupid???
    #TODO: time unit can be whatever, I just want to avoid velo being sqrt(J/kg)
    # if vel_units != (length_units / ??)

    # end

    return NamedTuple{(:length, :velocity, :mass, :energy, :force)}((length_units,
        vel_units, mass_units, energy_units, force_units))

end

#TODO: THIS HAS ISSUES BECAUISE SOME OF THE INTERS DONT DEFINE THESE? Best we can do for now?
function check_interaction_units(p_inters, s_inters, g_inters, sys_units::NamedTuple)

    for inter in [p_inters; s_inters; g_inters]
        if hasproperty(inter, :energy_units)
            if inter.energy_units != sys_units[:energy]
                throw(ArgumentError("Energy units passed to system do not match those passed to interactions"))
            end
        end

        if hasproperty(inter, :force_units)
            if inter.force_units != sys_units[:force]
                throw(ArgumentError("Force units passed to system do not match those passed to interactions"))
            end
        end
    end

end

function check_other_units(atoms, boundary, constraints, sys_units::NamedTuple)
    box_units = unit(boundary)

    if !all(sys_units[:length] .== box_units)
        throw(ArgumentError("Simulation box constructed with $(box_units) but length unit on coords was $(sys_units[:length])"))
    end

    σ_units = unit.(getproperty.(atoms, :σ))
    ϵ_units = unit.(getproperty.(atoms, :ϵ))

    if !all(sys_units[:length] .== σ_units)
        throw(ArgumentError("Atom σ has $(σ_units[1]) units but length unit on coords was $(sys_units[:length])"))
    end

    if !all(sys_units[:energy] .== ϵ_units)
        throw(ArgumentError("Atom ϵ has $(ϵ_units[1]) units but system energy unit was $(sys_units[:energy])"))
    end

    #TODO: check constraint dists here once that is pulled

end


function validate_energy_units(energy_units)
    valid_energy_dimensions = [u"𝐋^2 * 𝐌 * 𝐍^-1 * 𝐓^-2", u"𝐋^2 * 𝐌 * 𝐓^-2", NoDims]
    if dimension(energy_units) ∉ valid_energy_dimensions
        throw(ArgumentError("$(energy_units) are not energy units. Energy units must be energy,
            energy/amount, or NoUnits. For example, kcal & kcal/mol"))
    end
end

function validate_masses(masses)
    mass_units = unit.(masses)

    if !allequal(mass_units)
        throw(ArgumentError("Atoms array constructed with mixed mass units"))
    end

    valid_mass_dimensions = [u"𝐌", u"𝐌* 𝐍^-1", NoDims]
    mass_dimension = dimension(masses[1])

    if mass_dimension ∉ valid_mass_dimensions
        throw(ArgumentError("$(mass_dimension) are not mass units. Mass units must be mass or 
            mass/amount or NoUnits. For example, 1.0u\"kg\", 1.0u\"kg/mol\", & 1.0 are valid masses."))
    end

    return mass_dimension, mass_units[1]
end

function validate_coords(coords)
    coord_units = map(coords) do coord
        [unit(c) for c in coord]
    end 

    if !allequal(coord_units)
        throw(ArgumentError("Atoms array constructed with mixed length units"))
    end

    valid_length_dimensions = [u"𝐋", NoDims]
    coord_dimension = dimension(coords[1][1])

    if coord_dimension ∉ valid_length_dimensions
        throw(ArgumentError("$(coord_dimension) are not length units. Length units must be length or 
            or NoUnits. For example, 1.0u\"m\" & 1.0 are valid positions."))
    end

    return coord_dimension, coord_units[1][1]
end

function validate_velocities(velocities)
    velocity_units = map(velocities) do vel
        [unit(v) for v in vel]
    end 

    if !allequal(velocity_units)
        throw(ArgumentError("Velocities have mixed units"))
    end

    valid_velocity_dimensions = [u"𝐋 * 𝐓^-1", NoDims]
    velocity_dimension = dimension(velocities[1][1])

    if velocity_dimension ∉ valid_velocity_dimensions
        throw(ArgumentError("$(velocity_dimension) are not velocity units. Velocity units must be velocity or 
            or NoUnits. For example, 1.0u\"m/s\" & 1.0 are valid velocities."))
    end

    return velocity_dimension, velocity_units[1][1]
end

# Convert the Boltzmann constant k to suitable units and float type
# Assumes temperature untis are Kelvin
function convert_k_units(T, k, energy_units)
    if energy_units == NoUnits
        if unit(k) == NoUnits
            k_converted = T(k)
        else
            throw(ArgumentError("energy_units was passed as NoUnits but units were provided on k: $(unit(k))"))
        end
    elseif dimension(energy_units) == u"𝐋^2 * 𝐌 * 𝐍^-1 * 𝐓^-2" # Energy / Amount
        k_converted = T(uconvert(energy_units * u"K^-1", k * Unitful.Na))
    else
        k_converted = T(uconvert(energy_units * u"K^-1", k))
    end
    return k_converted
end


function check_energy_units(E, energy_units)
    if unit(E) != energy_units
        error("system energy units are ", energy_units, " but encountered energy units ",
                unit(E))
    end
end

function check_force_units(fdr::AbstractArray, sys_force_units)
    return check_force_units(unit(first(fdr)), sys_force_units)
end

function check_force_units(force_units, sys_force_units)
    if force_units != sys_force_units
        error("system force units are ", sys_force_units, " but encountered force units ",
              force_units)
    end
end


#TODO NONE OF THESE SHOULD NOT BE NECESSARY ANYMORE CAUSE MASS WILL BE MOLAR
function energy_remove_mol(x)
    if dimension(x) == u"𝐋^2 * 𝐌 * 𝐍^-1 * 𝐓^-2"
        T = typeof(ustrip(x))
        return x / T(Unitful.Na)
    else
        return x
    end
end

function energy_add_mol(x, energy_units)
    if dimension(energy_units) == u"𝐋^2 * 𝐌 * 𝐍^-1 * 𝐓^-2"
        T = typeof(ustrip(x))
        return x * T(Unitful.Na)
    else
        return x
    end
end

# Forces are often expressed per mol but this dimension needs removing for use in the integrator
function accel_remove_mol(x)
    fx = first(x)
    if dimension(fx) == u"𝐋 * 𝐍^-1 * 𝐓^-2"
        T = typeof(ustrip(fx))
        return x / T(Unitful.Na)
    else
        return x
    end
end