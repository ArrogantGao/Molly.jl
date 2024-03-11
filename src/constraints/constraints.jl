export
    DistanceConstraint,
    disable_intra_constraint_interactions!,
    apply_position_constraints!,
    apply_velocity_constraints!    

"""
Constraint between two atoms that maintains the distance between the two atoms.
# Arguments
- `i::Int`: Index of atom participating in this constraint
- `j::Int`: Index of the other atom in this constraint
- `dist::D` : Euclidean distance between the two atoms.
"""
struct DistanceConstraint{D}
    i::Int
    j::Int
    dist::D
end


"""
Atoms in a cluster do not participate in any other constraints outside of that cluster.
"Small" clusters contain at most 4 bonds between 2,3,4 or 5 atoms around one central atom.
Small clusters include: 1 bond, 2 bonds, 1 angle, 3 bonds, 1 bond 1 angle, 4 bonds
Note that an angle constraints will be implemented as 3 distance constraints. These constraints
use special methods that improve computational performance. Any constraint not listed above
will come at a performance penatly.
"""
struct ConstraintCluster{N,C}
    constraints::SVector{N,C}
    n_unique_atoms::Integer
end


function ConstraintCluster(constraints)

    #Count # of unique atoms in cluster
    atom_ids = []
    for constraint in constraints
        push!(atom_ids, constraint.i)
        push!(atom_ids, constraint.j)
    end

    return ConstraintCluster{length(constraints), eltype(constraints)}(constraints, length(unique(atom_ids)))

end

Base.length(cc::ConstraintCluster) = length(cc.constraints)



##### Constraint Setup ######

"""
disable_intra_constraint_interactions!(neighbor_finder,
     constraint_clsuters::AbstractVector{<:ConstraintCluster})

Disables interactions between atoms in a constraint. This prevents forces
from blowing up as atoms in a bond are typically very close to eachother.
"""
function disable_intra_constraint_interactions!(neighbor_finder,
     constraint_clsuters::AbstractVector{<:ConstraintCluster})

    # Loop through constraints and modify eligible matrix
    for cluster in constraint_clsuters
        for constraint in cluster.constraints
            neighbor_finder.eligible[constraint.i, constraint.j] = false
            neighbor_finder.eligible[constraint.j, constraint.i] = false
        end
    end

    return neighbor_finder
end


"""
Parse the constraints into clusters. 
Small clusters can be solved faster whereas large
clusters fall back to slower, generic methods.
"""
function build_clusters(n_atoms, constraints)

    constraint_graph = SimpleDiGraph(n_atoms)
    idx_dist_pairs = spzeros(n_atoms, n_atoms) * unit(constraints[1].dist)

    # Store constraints as directed edges, direction is arbitrary but necessary
    for constraint in constraints
        edge_added = add_edge!(constraint_graph, constraint.i, constraint.j)
        if edge_added
            idx_dist_pairs[constraint.i,constraint.j] = constraint.dist
            idx_dist_pairs[constraint.j,constraint.i] = constraint.dist
        else
            @warn "Duplicated constraint in System. It will be ignored."
        end
    end

    # Get groups of constraints that are connected to eachother 
    cc = connected_components(constraint_graph)
    # Initialze empty vector of clusters
    clusters = Vector{ConstraintCluster}(undef, 0)

    #Loop through connected regions and convert to clusters
    for (cluster_idx, atom_idxs) in enumerate(cc)
        # Loop atoms in connected region to build cluster
        if length(atom_idxs) > 1 #connected_components gives unconnected verticies as well
            connected_constraints = Vector{DistanceConstraint}(undef, 0)
            for ai in atom_idxs
                neigh_idxs = neighbors(constraint_graph, ai)
                for neigh_idx in neigh_idxs
                    push!(connected_constraints,
                        DistanceConstraint(ai, neigh_idx, idx_dist_pairs[ai,neigh_idx]))
                end
            end
            connected_constraints = convert(SVector{length(connected_constraints)}, connected_constraints)
            push!(clusters, ConstraintCluster(connected_constraints))
        end
    end

    return [clusters...]
end


##### High Level Constraint Functions ######
"""
apply_position_constraints!(sys::System, coord_storage;
     n_threads::Integer=Threads.nthreads())
apply_position_constraints!(sys::System, coord_storage,
     vel_storage, dt; n_threads::Integer=Threads.nthreads())

Loops through the constraint algorithms inside `sys` and applies them. If `vel_storage` and `dt`
are provided velocity corrections are applied as well so that the velocities are updated using
the constraint forces.
"""
function apply_position_constraints!(sys::System, coord_storage;
     n_threads::Integer=Threads.nthreads())

   for ca in sys.constraints
       position_constraints!(sys, ca, coord_storage, n_threads = n_threads)
   end

   return sys

end

function apply_position_constraints!(sys::System, coord_storage,
     vel_storage, dt; n_threads::Integer=Threads.nthreads())

     if length(sys.constraints) > 0
        vel_storage .= -sys.coords ./ dt

        for ca in sys.constraints
            position_constraints!(sys, ca, coord_storage, n_threads = n_threads)
        end

        vel_storage .+= sys.coords ./ dt

        sys.velocities .+= vel_storage
    end

   return sys
end

"""
apply_velocity_constraints!(sys::System; n_threads::Integer=Threads.nthreads())

Loops through the constraint algorithms inside `sys` and applies them to the velocities.
"""
function apply_velocity_constraints!(sys::System; n_threads::Integer=Threads.nthreads())
    
    for ca in sys.constraints
        velocity_constraints!(sys, ca, n_threads = n_threads)
    end

    return sys
end


"""
Re-calculates the # of degrees of freedom in the system due to the constraints.
All constrained molecules with 3 or more atoms are assumed to be non-linear because
180° bond angles are not supported. The table below shows the break down of 
DoF for different types of structures in the system where D is the dimensionality.
When using constraint algorithms the vibrational DoFs are removed from a molecule.

DoF           | Monoatomic | Linear Molecule | Non-Linear Molecule |
Translational |     D      |       D         |        D            |
Rotational    |     0      |     D - 1       |        D            |
Vibrational   |     0      |  D*N - (2D - 1) |    D*N - 2D         |
Total         |     D      |      D*N        |       D*N           |

"""
#& Im not sure this is generic
function n_dof_lost(D::Int, constraint_clusters)

    # Bond constraints remove vibrational DoFs
    vibrational_dof_lost = 0
    #Assumes constraints are a non-linear chain
    for cluster in constraint_clusters
        N = cluster.n_unique_atoms
        # If N > 2 assume non-linear (e.g. breaks for CO2)
        vibrational_dof_lost += ((N == 2) ? D*N - (2*D - 1) : D*(N - 2))
    end

    return vibrational_dof_lost

end

function n_dof(D::Int, N_atoms::Int, boundary)
    return D*N_atoms - (D - (num_infinite_boundary(boundary)))
end


