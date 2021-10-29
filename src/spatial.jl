# Spatial calculations

export
    vector1D,
    vector,
    wrapcoords,
    wrapcoordsvec

"""
    vector1D(c1, c2, side_length)

Displacement between two 1D coordinate values from c1 to c2, accounting for
the bounding box.
The minimum image convention is used, so the displacement is to the closest
version of the coordinate accounting for the periodic boundaries.
"""
function vector1D(c1, c2, side_length)
    if c1 < c2
        return (c2 - c1) < (c1 - c2 + side_length) ? (c2 - c1) : (c2 - c1 - side_length)
    else
        return (c1 - c2) < (c2 - c1 + side_length) ? (c2 - c1) : (c2 - c1 + side_length)
    end
end

"""
    vector(c1, c2, box_size)

Displacement between two coordinate values, accounting for the bounding box.
The minimum image convention is used, so the displacement is to the closest
version of the coordinates accounting for the periodic boundaries.
"""
vector(c1, c2, box_size) = vector1D.(c1, c2, box_size)

@generated function vector(c1::SVector{N}, c2::SVector{N}, box_size) where N
    quote
        Base.Cartesian.@ncall $N SVector{$N} i->vector1D(c1[i], c2[i], box_size[i])
    end
end

sqdistance(i, j, coords, box_size) = sum(abs2, vector(coords[i], coords[j], box_size))

"""
    wrapcoords(c, side_length)

Ensure a 1D coordinate is within the simulation box and return the coordinate.
"""
wrapcoords(c, side_length) = c - floor(c / side_length) * side_length

"""
    wrapcoordsvec(c, box_size)

Ensure a coordinate is within the simulation box and return the coordinate.
"""
wrapcoordsvec(v, box_size) = wrapcoords.(v, box_size)
