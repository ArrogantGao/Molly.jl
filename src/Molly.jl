module Molly

using StaticArrays
using ProgressMeter
using BioStructures

using LinearAlgebra: norm, normalize, dot, ×

include("setup.jl")
include("md.jl")
include("analysis.jl")

end
