export SHAKE

"""
    SHAKE(dists, is, js)

Constrains a set of bonds to defined distances.
"""
struct SHAKE{D, B, E, U} <: PositionConstraintAlgorithm
    tolerance::E
    unconstrained_position::U #Used as storage to avoid re-allocating arrays
end

function SHAKE(unconstrained_position; tolerance=1e-10u"nm")
    return SHAKE{typeof(tolerance), typeof(unconstrained_position)}(
        unconstrained_position; tolerance = tolerance)
end

function apply_position_constraints!(sys, constraint::SHAKE, 
    constraint_cluster::ConstraintCluster)

    SHAKE_algo(sys, constraint_cluster, constraint_cluster.unconstrained_coords)

end


#TODO: SHould these just be nothing, or do you arbitrarblty zero out the bond velocities???
function apply_velocity_constraints!(sys, constraint::SHAKE, 
    constraint_cluster::ConstraintCluster, unconstrained_velocities)

end


#TODO: I do not think we actually need to iterate here its analytical solution
function SHAKE_algo(sys, cluster::ConstraintCluster{1}, unconstrained_coords)
 #IDENTIFY TYPE OF CLUSTER AND APPLY CORRECT VERSION OF SHAKE

    # converged = false

    # while !converged
    #     for r in eachindex(constraint.is)
    #         # Atoms that are part of the bond
    #         i0 = constraint.is[r]
    #         i1 = constraint.js[r]

    #         # Distance vector between the atoms before unconstrained update
    #         r01 = vector(unconstrained_coords[i1], unconstrained_coords[i0], sys.boundary)

    #         # Distance vector after unconstrained update
    #         s01 = vector(sys.coords[i1], sys.coords[i0], sys.boundary)

    #         if abs(norm(s01) - constraint.dists[r]) > constraint.tolerance
    #             m0 = mass(sys.atoms[i0])
    #             m1 = mass(sys.atoms[i1])
    #             a = (1/m0 + 1/m1)^2 * norm(r01)^2
    #             b = 2 * (1/m0 + 1/m1) * dot(r01, s01)
    #             c = norm(s01)^2 - ((constraint.dists[r])^2)
    #             D = (b^2 - 4*a*c)
                
    #             if ustrip(D) < 0.0
    #                 @warn "SHAKE determinant negative, setting to 0.0"
    #                 D = zero(D)
    #             end

    #             # Quadratic solution for g
    #             α1 = (-b + sqrt(D)) / (2*a)
    #             α2 = (-b - sqrt(D)) / (2*a)

    #             g = abs(α1) <= abs(α2) ? α1 : α2

    #             # g needs to be divided by dt^2???

    #             # Update positions
    #             δri0 = r01 .* ( g/m0)
    #             δri1 = r01 .* (-g/m1)

    #             sys.coords[i0] += δri0
    #             sys.coords[i1] += δri1
    #         end

    #     end

    #     lengths = [abs(norm(vector(sys.coords[constraint.is[r]], sys.coords[constraint.js[r]], sys.boundary)) - constraint.dists[r]) for r in eachindex(constraint.is)]

    #     if maximum(lengths) < constraint.tolerance
    #         converged = true
    #     end
    # end
end

# TODO
SHAKE_algo(sys, cluster::ConstraintCluster{2}) = nothing
SHAKE_algo(sys, cluster::ConstraintCluster{3}) = nothing
SHAKE_algo(sys, cluster::ConstraintCluster{4}) = nothing

#Implement later, see:
# https://onlinelibrary.wiley.com/doi/abs/10.1002/1096-987X(20010415)22:5%3C501::AID-JCC1021%3E3.0.CO;2-V
# https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3285512/
# SHAKE_algo(sys, cluster::ConstraintClusterP{D}) where {D >= 5} = nothing
