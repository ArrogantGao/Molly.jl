# Molecular dynamics
# See https://www.saylor.org/site/wp-content/uploads/2011/06/MA221-6.1.pdf for
#   integration algorithm - used shorter second version
# See https://udel.edu/~arthij/MD.pdf for information on forces

export
    simulate!

mutable struct Acceleration
    x::Float64
    y::Float64
    z::Float64
end

function update_coordinates!(coords::Vector{Coordinates},
                    velocities::Vector{Velocity},
                    accels::Vector{Acceleration},
                    timestep::Real)
    for (i, c) in enumerate(coords)
        c.x += velocities[i].x*timestep + 0.5*accels[i].x*timestep^2
        c.y += velocities[i].y*timestep + 0.5*accels[i].y*timestep^2
        c.z += velocities[i].z*timestep + 0.5*accels[i].z*timestep^2
    end
    return coords
end

function update_velocities!(velocities::Vector{Velocity},
                    accels_t::Vector{Acceleration},
                    accels_t_dt::Vector{Acceleration},
                    timestep::Real)
    for (i, v) in enumerate(velocities)
        v.x += 0.5*(accels_t[i].x+accels_t_dt[i].x)*timestep
        v.y += 0.5*(accels_t[i].y+accels_t_dt[i].y)*timestep
        v.z += 0.5*(accels_t[i].z+accels_t_dt[i].z)*timestep
    end
    return velocities
end

function forcebond(coords_one::Coordinates, coords_two::Coordinates, bondtype::Bondtype)
    dx = coords_two.x-coords_one.x
    dy = coords_two.y-coords_one.y
    dz = coords_two.z-coords_one.z
    r = sqrt(dx^2 + dy^2 + dz^2)
    f = bondtype.kb * (r - bondtype.b0)
    return f*dx, f*dy, f*dz, -f*dx, -f*dy, -f*dz
end

function update_accelerations!(accels::Vector{Acceleration}, universe::Universe, forcefield::Forcefield)
    # Clear accelerations
    for i in 1:length(accels)
        accels[i].x = 0.0
        accels[i].y = 0.0
        accels[i].z = 0.0
    end

    # Bond forces
    for b in universe.molecule.bonds
        if haskey(forcefield.bondtypes, "$(universe.molecule.atoms[b.atom_i].attype)/$(universe.molecule.atoms[b.atom_j].attype)")
            bondtype = forcefield.bondtypes["$(universe.molecule.atoms[b.atom_i].attype)/$(universe.molecule.atoms[b.atom_j].attype)"]
        else
            bondtype = forcefield.bondtypes["$(universe.molecule.atoms[b.atom_j].attype)/$(universe.molecule.atoms[b.atom_i].attype)"]
        end
        d1x, d1y, d1z, d2x, d2y, d2z = forcebond(universe.coords[b.atom_i], universe.coords[b.atom_j], bondtype)
        accels[b.atom_i].x += d1x
        accels[b.atom_i].y += d1y
        accels[b.atom_i].z += d1z
        accels[b.atom_j].x += d2x
        accels[b.atom_j].y += d2y
        accels[b.atom_j].z += d2z
    end

    # Angles forces
    for a in universe.molecule.angles

    end

    # Dihedral forces
    for d in universe.molecule.dihedrals

    end

    # Electrostatic forces
    # Check non-bonded/angles

    # Van der Waal's forces
    # Check non-bonded/angles
    for (i, a1) in enumerate(universe.molecule.atoms)
        for (j, a2) in enumerate(universe.molecule.atoms)
            if i != j

            end
        end
    end

    return accels
end

empty_accelerations(n_atoms::Int) = [Acceleration(0.0, 0.0, 0.0) for i in 1:n_atoms]

function simulate!(s::Simulation, n_steps::Int)
    n_atoms = length(s.universe.coords)
    a_t = update_accelerations!(empty_accelerations(n_atoms), s.universe, s.forcefield)
    a_t_dt = empty_accelerations(n_atoms)
    @showprogress for i in 1:n_steps
        update_coordinates!(s.universe.coords, s.universe.velocities, a_t, s.timestep)
        update_accelerations!(a_t_dt, s.universe, s.forcefield)
        update_velocities!(s.universe.velocities, a_t, a_t_dt, s.timestep)
        if i % 100 == 0#=
            pe = potential_energy(s.universe)
            ke = kinetic_energy(s.universe.velocities)
            push!(s.pes, pe)
            push!(s.kes, ke)
            push!(s.energies, pe+ke)
            push!(s.temps, temperature(ke, n_atoms))=#
        end
        a_t = a_t_dt
        s.steps_made += 1
        #i%10000==0 && println(s.universe.coords[1], s.universe.velocities[1], a_t[1])
    end
    return s
end

simulate!(s::Simulation) = simulate!(s, s.n_steps-s.steps_made)
