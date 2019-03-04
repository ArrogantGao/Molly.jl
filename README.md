# Molly.jl

[![Travis build status](https://travis-ci.org/jgreener64/Molly.jl.svg?branch=master)](https://travis-ci.org/jgreener64/Molly.jl)
[![AppVeyor build status](https://ci.appveyor.com/api/projects/status/8dl6lqavnhqigq4p?svg=true)](https://ci.appveyor.com/project/jgreener64/molly-jl)
[![Coverage Status](https://coveralls.io/repos/github/jgreener64/Molly.jl/badge.svg?branch=master)](https://coveralls.io/github/jgreener64/Molly.jl?branch=master)

Much of science can be explained by the movement and interaction of molecules. Molecular dynamics (MD) is a computational technique used to explore these phenomena, particularly for biological macromolecules. Molly.jl is a pure Julia implementation of MD.

At the minute the package is a proof of concept for MD of proteins in Julia v1.0. It can read in pre-computed Gromacs topology and coordinate files with the OPLS-AA forcefield and run MD with given parameters. In theory it can do this for any regular protein. Implemented features include:
- Bonded interactions - covalent bonds, bond angles, dihedral angles.
- Non-bonded interactions - Lennard-Jones Van der Waals/repulsion force, electrostatic Coulomb potential.
- Andersen thermostat.
- Velocity Verlet integration.
- Explicit solvent.
- Periodic boundary conditions in a cubic box.
- Neighbour list to speed up calculation of non-bonded forces.
- Interface to allow arbitrary definition of new forces, thermostats etc.

Features not yet implemented include:
- Speed. Seriously, it's not fast yet - ~20x slower than GROMACS by some rough calculations. For reference most of the computational time in MD is spent in the force calculation, and most of that in calculation of non-bonded forces.
- Force fields other than OPLS-AA.
- Energy minimisation.
- Other temperature or pressure coupling methods.
- Protein preparation - solvent box, add hydrogens etc.
- Trajectory/topology file format readers/writers.
- Trajectory analysis.
- Parallelisation.
- GPU compatibility.
- Unit tests.

## Usage

```julia
using Molly

timestep = 0.0002 # ps
temperature = 298 # K
n_steps = 5000

forcefield, molecule, coords, box_size = readinputs(
            joinpath(dirname(pathof(Molly)), "..", "data", "5XER", "gmx_top_ff.top"),
            joinpath(dirname(pathof(Molly)), "..", "data", "5XER", "gmx_coords.gro"))

s = Simulation(forcefield, molecule, coords, box_size, temperature,
            timestep, n_steps)

simulate!(s)
```

## Video

The above 1 ps simulation looks something like this when you output more PDB files and view it in VMD:
![MD simulation](data/5XER/sim_1ps.gif)

## Plans

I plan to work on this in my spare time, but progress will be slow. MD could provide a nice use case for Julia - I think a reasonably featured and performant MD program could be written in fewer than 1,000 lines of code for example. Julia is also a well-suited language for trajectory analysis.

Contributions are very welcome - see the [roadmap issue](https://github.com/jgreener64/Molly.jl/issues/2) for more.
