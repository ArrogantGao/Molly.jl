# Temperature and pressure coupling

export
    NoCoupling,
    apply_coupling!,
    AndersenThermostat,
    RescaleThermostat,
    FrictionThermostat,
    maxwell_boltzmann,
    random_velocities!,
    temperature

"""
    NoCoupling()

Placeholder coupler that does nothing.
"""
struct NoCoupling end

"""
    apply_coupling!(system, simulator, coupling)

Apply a coupler to modify a simulation.
Custom couplers should implement this function.
"""
function apply_coupling!(sys::System, simulator, ::NoCoupling)
    return sys
end

"""
    AndersenThermostat(temperature, coupling_const)

Rescale random velocities according to the Andersen thermostat.
"""
struct AndersenThermostat{T, C}
    temperature::T
    coupling_const::C
end

function apply_coupling!(sys::System{D}, sim, thermostat::AndersenThermostat) where D
    for i in 1:length(sys)
        if rand() < (sim.dt / thermostat.coupling_const)
            mass = sys.atoms[i].mass
            sys.velocities[i] = velocity(mass, thermostat.temperature; dims=D)
        end
    end
    return sys
end

struct RescaleThermostat{T}
    temperature::T
end

function apply_coupling!(sys::System, sim, thermostat::RescaleThermostat)
    sys.velocities *= sqrt(thermostat.temperature / temperature(sys))
    return sys
end

struct FrictionThermostat{T}
    friction_const::T
end

function apply_coupling!(sys::System, sim, thermostat::FrictionThermostat)
    sys.velocities *= thermostat.friction_const
    return sys
end

"""
    velocity(mass, temperature; dims=3)

Generate a random velocity from the Maxwell-Boltzmann distribution.
"""
function AtomsBase.velocity(mass, temp; dims::Integer=3)
    return SVector([maxwell_boltzmann(mass, temp) for i in 1:dims]...)
end

"""
    maxwell_boltzmann(mass, temperature)

Generate a random speed along one dimension from the Maxwell-Boltzmann distribution.
"""
function maxwell_boltzmann(mass, temp)
    T = typeof(convert(AbstractFloat, ustrip(temp)))
    k = unit(temp) == NoUnits ? one(T) : uconvert(u"u * nm^2 * ps^-2 * K^-1", T(Unitful.k))
    σ = sqrt(k * temp / mass)
    return rand(Normal(zero(T), T(ustrip(σ)))) * unit(σ)
end

"""
    random_velocities!(sys, temp)

Set the velocities of a `System` to random velocities generated from the
Maxwell-Boltzmann distribution.
"""
function random_velocities!(sys::System, temp)
    sys.velocities = [velocity(a.mass, temp) for a in sys.atoms]
    return sys
end

"""
    temperature(system)

Calculate the temperature of a system from the kinetic energy of the atoms.
"""
function temperature(s::System{D, S, false}) where {D, S}
    ke = sum([a.mass * dot(s.velocities[i], s.velocities[i]) for (i, a) in enumerate(s.atoms)]) / 2
    df = 3 * length(s) - 3
    T = typeof(ustrip(ke))
    k = unit(ke) == NoUnits ? one(T) : uconvert(u"K^-1" * unit(ke), T(Unitful.k))
    return 2 * ke / (df * k)
end

function temperature(s::System{D, S, true}) where {D, S}
    ke = sum(mass.(s.atoms) .* sum.(abs2, s.velocities)) / 2
    df = 3 * length(s) - 3
    T = typeof(ustrip(ke))
    k = unit(ke) == NoUnits ? one(T) : uconvert(u"K^-1" * unit(ke), T(Unitful.k))
    return 2 * ke / (df * k)
end
