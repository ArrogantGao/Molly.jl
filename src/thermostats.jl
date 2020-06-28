# Thermostats

export
    AndersenThermostat,
    apply_thermostat!,
    NoThermostat,
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
function apply_thermostat!(s::Simulation, ::NoThermostat)
    return s
end

"""
    AndersenThermostat(coupling_const)

Rescale random velocities according to the Andersen thermostat.
"""
struct AndersenThermostat{T} <: Thermostat
    coupling_const::T
end

function apply_thermostat!(s::Simulation, thermostat::AndersenThermostat)
    dims = length(first(s.velocities))
    for i in 1:length(s.velocities)
        if rand() < s.timestep / thermostat.coupling_const
            mass = s.atoms[i].mass
            s.velocities[i] = velocity(mass, s.temperature; dims=dims)
        end
    end
    return s
end

"""
    velocity(mass, temperature; dims=3)
    velocity(T, mass, temperature; dims=3)

Generate a random velocity from the Maxwell-Boltzmann distribution.
"""
function velocity(T::Type, mass::Real, temperature::Real; dims::Integer=3)
    return SVector([maxwellboltzmann(T, mass, temperature) for i in 1:dims]...)
end

function velocity(mass::Real, temperature::Real; dims::Integer=3)
    return velocity(DefaultFloat, mass, temperature, dims=dims)
end

"""
    maxwellboltzmann(mass, temperature)
    maxwellboltzmann(T, mass, temperature)

Draw from the Maxwell-Boltzmann distribution.
"""
function maxwellboltzmann(T::Type, mass::Real, temperature::Real)
    return rand(Normal(zero(T), sqrt(temperature / mass)))
end

function maxwellboltzmann(mass::Real, temperature::Real)
    return maxwellboltzmann(DefaultFloat, mass, temperature)
end

"""
    temperature(simulation)

Calculate the temperature of a system from the kinetic energy of the atoms.
"""
function temperature(s::Simulation)
    ke = sum([a.mass * dot(s.velocities[i], s.velocities[i]) for (i, a) in enumerate(s.atoms)]) / 2
    df = 3 * length(s.coords) - 3
    return 2 * ke / df
end
