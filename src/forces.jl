# See https://udel.edu/~arthij/MD.pdf for information on forces
# See https://arxiv.org/pdf/1401.1181.pdf for applying forces to atoms
# See Gromacs manual for other aspects of forces

export
    LennardJones,
    Coulomb,
    HarmonicBond,
    HarmonicAngle,
    Dihedral,
    force!

"Square of the non-bonded interaction distance cutoff in nm^2."
const sqdist_cutoff_nb = 1.0 ^ 2

"The constant for Coulomb interaction, 1/(4*π*ϵ0*ϵr)."
const coulomb_const = 138.935458 / 70.0 # Treat ϵr as 70 for now

"The Lennard-Jones 6-12 interaction."
struct LennardJones <: GeneralInteraction
    nl_only::Bool
end

LennardJones() = LennardJones(false)

"The Coulomb electrostatic interaction."
struct Coulomb <: GeneralInteraction
    nl_only::Bool
end

"A harmonic bond between two atoms."
struct HarmonicBond{T} <: SpecificInteraction
    i::Int
    j::Int
    b0::T
    kb::T
end

"A bond angle between three atoms."
struct HarmonicAngle{T} <: SpecificInteraction
    i::Int
    j::Int
    k::Int
    th0::T
    cth::T
end

"A dihedral torsion angle between four atoms."
struct Dihedral{T} <: SpecificInteraction
    i::Int
    j::Int
    k::Int
    l::Int
    f1::T
    f2::T
    f3::T
    f4::T
end

"Update the force for an atom pair in response to a given interation type."
function force! end

@fastmath @inbounds function force!(forces,
                                    inter::LennardJones,
                                    s::Simulation,
                                    i::Integer,
                                    j::Integer)
    if iszero(s.atoms[i].σ) || iszero(s.atoms[j].σ)
        return
    end
    σ = sqrt(s.atoms[i].σ * s.atoms[j].σ)
    ϵ = sqrt(s.atoms[i].ϵ * s.atoms[j].ϵ)
    dr = vector(s.coords[i], s.coords[j], s.box_size)
    r2 = sum(abs2, dr)
    if r2 > sqdist_cutoff_nb
        return
    end
    invr2 = inv(r2)
    six_term = (σ ^ 2 * invr2) ^ 3
    # Limit this to 100 as a fudge to stop it exploding
    f = min((24ϵ * invr2) * (2 * six_term ^ 2 - six_term), 100)
    fdr = f * dr
    forces[i] -= fdr
    forces[j] += fdr
end

@fastmath @inbounds function force!(forces,
                                    inter::Coulomb,
                                    s::Simulation,
                                    i::Integer,
                                    j::Integer)
    dr = vector(s.coords[i], s.coords[j], s.box_size)
    r2 = sum(abs2, dr)
    if r2 > sqdist_cutoff_nb
        return
    end
    T = typeof(r2)
    f = (T(coulomb_const) * s.atoms[i].charge * s.atoms[j].charge) / sqrt(r2 ^ 3)
    fdr = f * dr
    forces[i] -= fdr
    forces[j] += fdr
end

function force!(forces,
                b::HarmonicBond,
                s::Simulation)
    ab = vector(s.coords[b.i], s.coords[b.j], s.box_size)
    c = b.kb * (norm(ab) - b.b0)
    f = c * normalize(ab)
    forces[b.i] += f
    forces[b.j] -= f
end

# Sometimes domain error occurs for acos if the value is > 1.0 or < -1.0
acosbound(x::Real) = acos(clamp(x, -1, 1))

function force!(forces,
                a::HarmonicAngle,
                s::Simulation)
    ba = vector(s.coords[a.j], s.coords[a.i], s.box_size)
    bc = vector(s.coords[a.j], s.coords[a.k], s.box_size)
    pa = normalize(ba × (ba × bc))
    pc = normalize(-bc × (ba × bc))
    angle_term = -a.cth * (acosbound(dot(ba, bc) / (norm(ba) * norm(bc))) - a.th0)
    fa = (angle_term / norm(ba)) * pa
    fc = (angle_term / norm(bc)) * pc
    fb = -fa - fc
    forces[a.i] += fa
    forces[a.j] += fb
    forces[a.k] += fc
end

function force!(forces,
                d::Dihedral,
                s::Simulation)
    ba = vector(s.coords[d.j], s.coords[d.i], s.box_size)
    bc = vector(s.coords[d.j], s.coords[d.k], s.box_size)
    dc = vector(s.coords[d.l], s.coords[d.k], s.box_size)
    p1 = normalize(ba × bc)
    p2 = normalize(-dc × -bc)
    θ = atan(dot((-ba × bc) × (bc × -dc), normalize(bc)), dot(-ba × bc, bc × -dc))
    angle_term = (d.f1*sin(θ) - 2*d.f2*sin(2*θ) + 3*d.f3*sin(3*θ)) / 2
    fa = (angle_term / (norm(ba) * sin(acosbound(dot(ba, bc) / (norm(ba) * norm(bc)))))) * p1
    # fd clashes with a function name
    f_d = (angle_term / (norm(dc) * sin(acosbound(dot(bc, dc) / (norm(bc) * norm(dc)))))) * p2
    oc = bc / 2
    tc = -(oc × f_d + (-dc × f_d) / 2 + (ba × fa) / 2)
    fc = (1 / dot(oc, oc)) * (tc × oc)
    fb = -fa - fc - f_d
    forces[d.i] += fa
    forces[d.j] += fb
    forces[d.k] += fc
    forces[d.l] += f_d
end
