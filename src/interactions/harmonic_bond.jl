"""
    HarmonicBond(i, j, b0, kb)

A harmonic bond between two atoms.
"""
struct HarmonicBond{T} <: SpecificInteraction
    i::Int
    j::Int
    b0::T
    kb::T
end

@inline @inbounds function force!(forces,
                                  b::HarmonicBond,
                                  s::Simulation)
    ab = vector(s.coords[b.i], s.coords[b.j], s.box_size)
    c = b.kb * (norm(ab) - b.b0)
    f = c * normalize(ab)
    forces[b.i] += f
    forces[b.j] -= f
    return nothing
end

@inline @inbounds function potential_energy(b::HarmonicBond,
                                            s::Simulation)
    dr = vector(s.coords[b.i], s.coords[b.j], s.box_size)
    r = norm(dr)
    b.kb / 2 * (r - b.b0) ^ 2
end
