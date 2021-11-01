# Neighbor finders

export
    NoNeighborFinder,
    find_neighbors!,
    DistanceNeighborFinder,
    DistanceNeighborFinderVec,
    TreeNeighborFinder,
    CellListMapNeighborFinder

"""
    NoNeighborFinder()

Placeholder neighbor finder that returns no neighbors.
When using this neighbor finder, ensure that `nl_only` for the interactions is
set to `false`.
"""
struct NoNeighborFinder <: NeighborFinder end

"""
    find_neighbors!(simulation, neighbor_finder, step_n; parallel=true)

Obtain a list of close atoms in a system.
Custom neighbor finders should implement this function.
"""
function find_neighbors!(s::Simulation,
                         ::NoNeighborFinder,
                         ::Integer;
                         kwargs...)
    return
end

"""
    DistanceNeighborFinder(; nb_matrix, matrix_14, n_steps, dist_cutoff)

Find close atoms by distance.
"""
struct DistanceNeighborFinder{D} <: NeighborFinder
    nb_matrix::BitArray{2}
    matrix_14::BitArray{2}
    n_steps::Int
    dist_cutoff::D
end

function DistanceNeighborFinder(;
                                nb_matrix,
                                matrix_14=falses(size(nb_matrix)),
                                n_steps=10,
                                dist_cutoff)
    return DistanceNeighborFinder{typeof(dist_cutoff)}(nb_matrix, matrix_14, n_steps, dist_cutoff)
end

function find_neighbors!(s::Simulation,
                         nf::DistanceNeighborFinder,
                         step_n::Integer;
                         parallel::Bool=true)
    !iszero(step_n % nf.n_steps) && return

    neighbors = s.neighbors
    empty!(neighbors)

    sqdist_cutoff = nf.dist_cutoff ^ 2

    if parallel && nthreads() > 1
        nl_threads = [Tuple{Int, Int, Bool}[] for i in 1:nthreads()]

        @threads for i in 1:length(s.coords)
            nl = nl_threads[threadid()]
            ci = s.coords[i]
            nbi = @view nf.nb_matrix[:, i]
            w14i = @view nf.matrix_14[:, i]
            for j in 1:(i - 1)
                r2 = sum(abs2, vector(ci, s.coords[j], s.box_size))
                if r2 <= sqdist_cutoff && nbi[j]
                    push!(nl, (i, j, w14i[j]))
                end
            end
        end

        for nl in nl_threads
            append!(neighbors, nl)
        end
    else
        for i in 1:length(s.coords)
            ci = s.coords[i]
            nbi = @view nf.nb_matrix[:, i]
            w14i = @view nf.matrix_14[:, i]
            for j in 1:(i - 1)
                r2 = sum(abs2, vector(ci, s.coords[j], s.box_size))
                if r2 <= sqdist_cutoff && nbi[j]
                    push!(neighbors, (i, j, w14i[j]))
                end
            end
        end
    end
end

"""
    DistanceNeighborFinderVec(; nb_matrix, matrix_14, n_steps, dist_cutoff)

Find close atoms by distance.
"""
struct DistanceNeighborFinderVec{D, B, I} <: NeighborFinder
    nb_matrix::B
    matrix_14::B
    n_steps::Int
    dist_cutoff::D
    is::I
    js::I
end

function DistanceNeighborFinderVec(;
                                nb_matrix,
                                matrix_14=falses(size(nb_matrix)),
                                n_steps=10,
                                dist_cutoff)
    n_atoms = size(nb_matrix, 1)
    if isa(nb_matrix, CuArray)
        is = cu(hcat([collect(1:n_atoms) for i in 1:n_atoms]...))
        js = cu(permutedims(is, (2, 1)))
    else
        is = hcat([collect(1:n_atoms) for i in 1:n_atoms]...)
        js = permutedims(is, (2, 1))
    end
    return DistanceNeighborFinderVec{typeof(dist_cutoff), typeof(nb_matrix), typeof(is)}(
            nb_matrix, matrix_14, n_steps, dist_cutoff, is, js)
end

function findindices(nbs_ord, n_atoms)
    inds = zeros(Int, n_atoms)
    atom_i = 1
    for (nb_i, nb_ai) in enumerate(nbs_ord)
        while atom_i < nb_ai
            inds[atom_i] = nb_i
            atom_i += 1
        end
    end
    while atom_i < (n_atoms + 1)
        inds[atom_i] = length(nbs_ord) + 1
        atom_i += 1
    end
    return inds
end

function find_neighbors!(s::Simulation,
                         nf::DistanceNeighborFinderVec,
                         step_n::Integer,
                         current_nbs=nothing;
                         parallel::Bool=true)
    !iszero(step_n % nf.n_steps) && return current_nbs

    n_atoms = length(s.coords)
    sqdist_cutoff = nf.dist_cutoff ^ 2
    sqdists = sqdistance.(nf.is, nf.js, (s.coords,), (s.box_size,))

    close = sqdists .< sqdist_cutoff
    close_nb = close .* nf.nb_matrix
    eligible = tril(close_nb, -1)

    fa = Array(findall(!iszero, eligible))
    nbsi = getindex.(fa, 1)
    nbsj = getindex.(fa, 2)
    order_i = sortperm(nbsi)
    order_j = sortperm(nbsj)
    weights_14 = @view nf.matrix_14[fa]

    nbsi_ordi, nbsj_ordi = nbsi[order_i], nbsj[order_i]
    weights_14_ordi = @view weights_14[order_i]
    atom_bounds_i = findindices(nbsi_ordi, n_atoms)
    atom_bounds_j = findindices(view(nbsj, order_j), n_atoms)

    return NeighborListVec(nbsi_ordi, nbsj_ordi, atom_bounds_i, atom_bounds_j,
                            order_j, weights_14_ordi)
end

"""
    TreeNeighborFinder(; nb_matrix, matrix_14, n_steps, dist_cutoff)

Find close atoms by distance using a tree search.
"""
struct TreeNeighborFinder{D} <: NeighborFinder
    nb_matrix::BitArray{2}
    matrix_14::BitArray{2}
    n_steps::Int
    dist_cutoff::D
end

function TreeNeighborFinder(;
                            nb_matrix,
                            matrix_14=falses(size(nb_matrix)),
                            n_steps=10,
                            dist_cutoff)
    return TreeNeighborFinder{typeof(dist_cutoff)}(nb_matrix, matrix_14, n_steps, dist_cutoff)
end

function find_neighbors!(s::Simulation,
                         nf::TreeNeighborFinder,
                         step_n::Integer;
                         parallel::Bool=true)
    !iszero(step_n % nf.n_steps) && return

    neighbors = s.neighbors
    empty!(neighbors)

    dist_unit = unit(first(first(s.coords)))
    bv = ustrip.(dist_unit, s.box_size)
    btree = BallTree(ustripvec.(s.coords), PeriodicEuclidean(bv))
    dist_cutoff = ustrip(dist_unit, nf.dist_cutoff)

    if parallel && nthreads() > 1
        nl_threads = [Tuple{Int, Int, Bool}[] for i in 1:nthreads()]

        @threads for i in 1:length(s.coords)
            nl = nl_threads[threadid()]
            ci = ustrip.(s.coords[i])
            nbi = @view nf.nb_matrix[:, i]
            w14i = @view nf.matrix_14[:, i]
            idxs = inrange(btree, ci, dist_cutoff, true)
            for j in idxs
                if nbi[j] && i > j
                    push!(nl, (i, j, w14i[j]))
                end
            end
        end

        for nl in nl_threads
            append!(neighbors, nl)
        end
    else
        for i in 1:length(s.coords)
            ci = ustrip.(s.coords[i])
            nbi = @view nf.nb_matrix[:, i]
            w14i = @view nf.matrix_14[:, i]
            idxs = inrange(btree, ci, dist_cutoff, true)
            for j in idxs
                if nbi[j] && i > j
                    push!(neighbors, (i, j, w14i[j]))
                end
            end
        end
    end
end

# Find neighbor lists using CellListMap.jl
"""

    CellListMapNeighborFinder(; nb_matrix, matrix_14, n_steps, dist_cutoff, x0, unit_cell)

Find close atoms by distance, and store auxiliary arrays for in-place threading. `x0` and `unit_cell` 
are optional initial coordinates and system unit cell that improve the first approximation of the
cell list structure. The unit cell can be provided as a three-component vector of box sides on each
direction, in which case the unit cell is considered `OrthorhombicCell`, or as a unit cell matrix,
in which case the cell is considered a general `TriclinicCell` by the cell list algorithm.

### Example

```julia-repl
julia> coords
15954-element Vector{SVector{3, Quantity{Float64, 𝐋, Unitful.FreeUnits{(nm,), 𝐋, nothing}}}}:
 [2.5193063341012127 nm, 3.907448346081021 nm, 4.694954671434135 nm]
 [2.4173958848835233 nm, 3.916034913604175 nm, 4.699661024574953 nm]
 ⋮
 [1.818842280373283 nm, 5.592152965227421 nm, 4.992100424805031 nm]
 [1.7261366568663976 nm, 5.610326185704369 nm, 5.084523386833478 nm]

julia> box_size
3-element SVector{3, Quantity{Float64, 𝐋, Unitful.FreeUnits{(nm,), 𝐋, nothing}}} with indices SOneTo(3):
              5.676 nm
             5.6627 nm
             6.2963 nm

julia> neighbor_finder = CellListMapNeighborFinder(
           nb_matrix=s.neighbor_finder.nb_matrix, matrix_14=s.neighbor_finder.matrix_14, 
           n_steps=10, dist_cutoff=1.2u"nm",
           x0 = coords, unit_cell = box_size
       )
CellListMapNeighborFinder{Quantity{Float64, 𝐋, Unitful.FreeUnits{(nm,), 𝐋, nothing}}, 3, Float64}
  Size of nb_matrix = (15954, 15954)
  n_steps = 10
  dist_cutoff = 1.2 nm

```

"""
mutable struct CellListMapNeighborFinder{D, N, T} <: NeighborFinder
    nb_matrix::BitArray{2}
    matrix_14::BitArray{2}
    n_steps::Int
    dist_cutoff::D
    # auxiliary arrays for multi-threaded in-place updating of the lists
    cl::CellListMap.CellList{N, T}
    aux::CellListMap.AuxThreaded{N, T}
    neighbors_threaded::Vector{NeighborList}
end

function Base.show(io::IO, neighbor_finder::NeighborFinder)
    println(io, typeof(neighbor_finder))
    println(io,"  Size of nb_matrix = " , size(neighbor_finder.nb_matrix))
    println(io,"  n_steps = " , neighbor_finder.n_steps)
    print(io,"  dist_cutoff = ", neighbor_finder.dist_cutoff)
end

# This function sets up the box structure for CellListMap. It uses the unit cell
# if it is given, or guesses a box size from the number of particles, assuming 
# that the atomic density is similar to that of liquid water at ambient conditions.
function CellListMapNeighborFinder(;
                                   nb_matrix,
                                   matrix_14=falses(size(nb_matrix)),
                                   n_steps=10,
                                   dist_cutoff::D,
                                   x0=nothing,
                                   unit_cell=nothing) where D
    cutoff = ustrip(dist_cutoff)
    T = typeof(cutoff)
    np = size(nb_matrix, 1)
    if isnothing(unit_cell)
        side = T(ustrip(uconvert(unit(dist_cutoff ^ 3), np * 0.01u"nm^3"))) ^ (1 / 3)
        side = max(side, 2 * cutoff)
        box = CellListMap.Box(side * ones(SVector{3, T}), cutoff; T=T)
    else
        box = CellListMap.Box(unit_cell, cutoff; T=T)
    end
    if isnothing(x0)
        x = [box.unit_cell_max .* rand(SVector{3, T}) for _ in 1:np]
    else
        x = x0
    end
    # Construct the cell list for the first time, to allocate 
    cl = CellList(x, box; parallel=true)
    return CellListMapNeighborFinder{D, 3, T}(
        nb_matrix, matrix_14, n_steps, dist_cutoff,
        cl, CellListMap.AuxThreaded(cl), 
        [NeighborList(0, [(0, 0, false)]) for _ in 1:nthreads()])
end

"""
    push_pair!(neighbor::NeighborList, i, j, nb_matrix, matrix_14)

Add pair to pair list. If the buffer size is large enough, update element, otherwise
push new element to `neighbor.list`.
"""
function push_pair!(neighbors::NeighborList, i, j, nb_matrix, matrix_14)
    if nb_matrix[i, j]
        push!(neighbors, (Int(i), Int(j), matrix_14[i, j]))
    end
    return neighbors
end

# This is only called in the parallel case
function reduce_pairs(neighbors::NeighborList, neighbors_threaded::Vector{NeighborList})
    neighbors.n = 0
    for i in 1:nthreads()
        append!(neighbors, neighbors_threaded[i])
    end
    return neighbors
end

# Add method to strip_value from cell list map to pass the 
# coordinates with units without having to reallocate the vector 
CellListMap.strip_value(x::Unitful.Quantity) = Unitful.ustrip(x)

"""
    find_neighbors!(s::Simulation,
                    nf::CellListMapNeighborFinder,
                    step_n::Integer;
                    parallel::Bool=true)

Find neighbors using `CellListMap`, without in-place updating. Should be called only
the first time the cell lists are built. Modifies the mutable `nf` structure.
"""
function Molly.find_neighbors!(s::Simulation,
                               nf::CellListMapNeighborFinder,
                               step_n::Integer;
                               parallel::Bool=true)
    !iszero(step_n % nf.n_steps) && return

    aux = nf.aux
    cl = nf.cl

    neighbors = s.neighbors
    neighbors.n = 0
    neighbors_threaded = nf.neighbors_threaded
    if parallel
        for i in 1:nthreads()
            neighbors_threaded[i].n = 0
        end
    else
        neighbors_threaded[1].n = 0
    end

    dist_unit = unit(first(first(s.coords)))
    box_size_conv = ustrip.(dist_unit, s.box_size)
    dist_cutoff_conv = ustrip(dist_unit, nf.dist_cutoff)

    box = CellListMap.Box(box_size_conv, dist_cutoff_conv; T=typeof(dist_cutoff_conv), lcell=1)
    cl = UpdateCellList!(s.coords, box, cl, aux; parallel=parallel)

    map_pairwise!(
        (x, y, i, j, d2, pairs) -> push_pair!(pairs, i, j, nf.nb_matrix, nf.matrix_14),
        neighbors, box, cl;
        reduce=reduce_pairs,
        output_threaded=neighbors_threaded,
        parallel=parallel
    )

    nf.cl = cl
    return neighbors
end
