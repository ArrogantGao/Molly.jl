# Thermostats

export
    NoThermostat,
    apply_thermostat!,
    AndersenThermostat,
    velocity,
    maxwellboltzmann,
    temperature

"""
    NoThermostat()

Placeholder thermostat that does nothing.
"""
struct NoThermostat <: Thermostat end

"""
    apply_thermostat!(simulation, thermostat)

Apply a thermostat to modify a simulation.
Custom thermostats should implement this function.
"""
function apply_thermostat!(velocities, s::Simulation, ::NoThermostat)
    return velocities
end

"""
    AndersenThermostat(coupling_const)

Rescale random velocities according to the Andersen thermostat.
"""
struct AndersenThermostat{T} <: Thermostat
    coupling_const::T
end

function apply_thermostat!(velocities, s::Simulation, thermostat::AndersenThermostat)
    dims = length(first(velocities))
    for i in 1:length(velocities)
        if rand() < s.timestep / thermostat.coupling_const
            mass = s.atoms[i].mass
            velocities[i] = velocity(mass, s.temperature; dims=dims)
        end
    end
    return velocities
end

"""
    velocity(mass, temperature; dims=3)
    velocity(T, mass, temperature; dims=3)

Generate a random velocity from the Maxwell-Boltzmann distribution.
"""
function velocity(T::Type, mass, temp; dims::Integer=3)
    return SVector([maxwellboltzmann(T, mass, temp) for i in 1:dims]...)
end

function velocity(mass, temp; dims::Integer=3)
    return velocity(DefaultFloat, mass, temp; dims=dims)
end

"""
    maxwellboltzmann(mass, temperature)
    maxwellboltzmann(T, mass, temperature)

Draw from the Maxwell-Boltzmann distribution.
"""
function maxwellboltzmann(T::Type, mass, temp)
    return rand(Normal(zero(T), sqrt(temp / mass)))
end

function maxwellboltzmann(mass, temp)
    return maxwellboltzmann(DefaultFloat, mass, temp)
end

"""
    temperature(simulation)

Calculate the temperature of a system from the kinetic energy of the atoms.
"""
function temperature(s::Simulation{false})
    ke = sum([a.mass * dot(s.velocities[i], s.velocities[i]) for (i, a) in enumerate(s.atoms)]) / 2
    df = 3 * length(s.coords) - 3
    return 2 * ke / df
end

function temperature(s::Simulation{true})
    masses = mass.(s.atoms)
    ke = sum(masses .* sum.(abs2, s.velocities)) / 2
    df = 3 * length(s.coords) - 3
    return 2 * ke / df
end
