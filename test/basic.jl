@testset "Interactions" begin
    c1 = SVector(1.0, 1.0, 1.0)u"nm"
    c2 = SVector(1.3, 1.0, 1.0)u"nm"
    c3 = SVector(1.4, 1.0, 1.0)u"nm"
    a1 = Atom(charge=1.0, σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1")
    boundary = CubicBoundary(2.0u"nm", 2.0u"nm", 2.0u"nm")
    dr12 = vector(c1, c2, boundary)
    dr13 = vector(c1, c3, boundary)

    for inter in (LennardJones(), Mie(m=6, n=12))
        @test isapprox(
            force(inter, dr12, c1, c2, a1, a1, boundary),
            SVector(16.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
            atol=1e-9u"kJ * mol^-1 * nm^-1",
        )
        @test isapprox(
            force(inter, dr13, c1, c3, a1, a1, boundary),
            SVector(-1.375509739, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
            atol=1e-9u"kJ * mol^-1 * nm^-1",
        )
        @test isapprox(
            potential_energy(inter, dr12, c1, c2, a1, a1, boundary),
            0.0u"kJ * mol^-1",
            atol=1e-9u"kJ * mol^-1",
        )
        @test isapprox(
            potential_energy(inter, dr13, c1, c3, a1, a1, boundary),
            -0.1170417309u"kJ * mol^-1",
            atol=1e-9u"kJ * mol^-1",
        )
    end

    inter = SoftSphere()
    @test isapprox(
        force(inter, dr12, c1, c2, a1, a1, boundary),
        SVector(32.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        force(inter, dr13, c1, c3, a1, a1, boundary),
        SVector(0.7602324486, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        potential_energy(inter, dr12, c1, c2, a1, a1, boundary),
        0.8u"kJ * mol^-1",
        atol=1e-9u"kJ * mol^-1",
    )
    @test isapprox(
        potential_energy(inter, dr13, c1, c3, a1, a1, boundary),
        0.0253410816u"kJ * mol^-1",
        atol=1e-9u"kJ * mol^-1",
    )

    inter = Coulomb()
    @test isapprox(
        force(inter, dr12, c1, c2, a1, a1, boundary),
        SVector(1543.727311, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-5u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        force(inter, dr13, c1, c3, a1, a1, boundary),
        SVector(868.3466125, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-5u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        potential_energy(inter, dr12, c1, c2, a1, a1, boundary),
        463.1181933u"kJ * mol^-1",
        atol=1e-5u"kJ * mol^-1",
    )
    @test isapprox(
        potential_energy(inter, dr13, c1, c3, a1, a1, boundary),
        347.338645u"kJ * mol^-1",
        atol=1e-5u"kJ * mol^-1",
    )

    c1_grav = SVector(1.0, 1.0, 1.0)u"m"
    c2_grav = SVector(6.0, 1.0, 1.0)u"m"
    a1_grav, a2_grav = Atom(mass=1e6u"kg"), Atom(mass=1e5u"kg")
    boundary_grav = CubicBoundary(20.0u"m", 20.0u"m", 20.0u"m")
    dr12_grav = vector(c1_grav, c2_grav, boundary_grav)
    inter = Gravity()
    @test isapprox(
        force(inter, dr12_grav, c1_grav, c2_grav, a1_grav, a2_grav, boundary_grav),
        SVector(-0.266972, 0.0, 0.0)u"kg * m * s^-2",
        atol=1e-9u"kg * m * s^-2",
    )
    @test isapprox(
        potential_energy(inter, dr12_grav, c1_grav, c2_grav,
                         a1_grav, a2_grav, boundary_grav),
        -1.33486u"kg * m^2 * s^-2",
        atol=1e-9u"kg * m^2 * s^-2",
    )

    b1 = HarmonicBond(b0=0.2u"nm", kb=300_000.0u"kJ * mol^-1 * nm^-2")
    b2 = HarmonicBond(b0=0.6u"nm", kb=100_000.0u"kJ * mol^-1 * nm^-2")
    fs = force(b1, c1, c2, boundary)
    @test isapprox(
        fs.f1,
        SVector(30000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        fs.f2,
        SVector(-30000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    fs = force(b2, c1, c3, boundary)
    @test isapprox(
        fs.f1,
        SVector(-20000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        fs.f2,
        SVector(20000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        potential_energy(b1, c1, c2, boundary),
        1500.0u"kJ * mol^-1",
        atol=1e-9u"kJ * mol^-1",
    )
    @test isapprox(
        potential_energy(b2, c1, c3, boundary),
        2000.0u"kJ * mol^-1",
        atol=1e-9u"kJ * mol^-1",
    )

    b1 = MorseBond(D=100.0u"kJ * mol^-1", α=10.0u"nm^-1", r0=0.2u"nm")
    b2 = MorseBond(D=200.0u"kJ * mol^-1", α=5.0u"nm^-1" , r0=0.6u"nm")
    fs = force(b1, c1, c2, boundary)
    @test isapprox(
        fs.f1,
        SVector(465.0883158697, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        fs.f2,
        SVector(-465.0883158697, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    fs = force(b2, c1, c3, boundary)
    @test isapprox(
        fs.f1,
        SVector(-9341.5485409432, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        fs.f2,
        SVector(9341.5485409432, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
        atol=1e-9u"kJ * mol^-1 * nm^-1",
    )
    @test isapprox(
        potential_energy(b1, c1, c2, boundary),
        39.9576400894u"kJ * mol^-1",
        atol=1e-9u"kJ * mol^-1",
    )
    @test isapprox(
        potential_energy(b2, c1, c3, boundary),
        590.4984884025u"kJ * mol^-1",
        atol=1e-9u"kJ * mol^-1",
    )
end

@testset "Spatial" begin
    @test vector_1D(4.0, 6.0, 10.0) ==  2.0
    @test vector_1D(1.0, 9.0, 10.0) == -2.0
    @test vector_1D(6.0, 4.0, 10.0) == -2.0
    @test vector_1D(9.0, 1.0, 10.0) ==  2.0

    @test vector_1D(4.0u"nm", 6.0u"nm", 10.0u"nm") ==  2.0u"nm"
    @test vector_1D(1.0u"m" , 9.0u"m" , 10.0u"m" ) == -2.0u"m"
    @test_throws Unitful.DimensionError vector_1D(6.0u"nm", 4.0u"nm", 10.0)

    @test vector(
        SVector(4.0, 1.0, 6.0),
        SVector(6.0, 9.0, 4.0),
        CubicBoundary(SVector(10.0, 10.0, 10.0)),
    ) == SVector(2.0, -2.0, -2.0)
    @test vector(
        SVector(4.0, 1.0, 1.0),
        SVector(6.0, 4.0, 3.0),
        CubicBoundary(SVector(10.0, 5.0, 3.5)),
    ) == SVector(2.0, -2.0, -1.5)
    @test vector(
        SVector(4.0, 1.0),
        SVector(6.0, 9.0),
        RectangularBoundary(SVector(10.0, 10.0)),
    ) == SVector(2.0, -2.0)
    @test vector(
        SVector(4.0, 1.0, 6.0)u"nm",
        SVector(6.0, 9.0, 4.0)u"nm",
        CubicBoundary(SVector(10.0, 10.0, 10.0)u"nm"),
    ) == SVector(2.0, -2.0, -2.0)u"nm"

    @test wrap_coord_1D(8.0 , 10.0) == 8.0
    @test wrap_coord_1D(12.0, 10.0) == 2.0
    @test wrap_coord_1D(-2.0, 10.0) == 8.0

    @test wrap_coord_1D(8.0u"nm" , 10.0u"nm") == 8.0u"nm"
    @test wrap_coord_1D(12.0u"m" , 10.0u"m" ) == 2.0u"m"
    @test_throws ErrorException wrap_coord_1D(-2.0u"nm", 10.0)

    vels_units   = [maxwell_boltzmann(12.0u"u", 300.0u"K") for _ in 1:1_000]
    vels_nounits = [maxwell_boltzmann(12.0    , 300.0    ) for _ in 1:1_000]
    @test 0.35u"nm * ps^-1" < std(vels_units) < 0.55u"nm * ps^-1"
    @test 0.35 < std(vels_nounits) < 0.55
end

@testset "Neighbor lists" begin
    for neighbor_finder in (DistanceNeighborFinder, TreeNeighborFinder, CellListMapNeighborFinder)
        nf = neighbor_finder(nb_matrix=trues(3, 3), n_steps=10, dist_cutoff=2.0u"nm")
        s = System(
            atoms=[Atom(), Atom(), Atom()],
            coords=[SVector(1.0, 1.0, 1.0)u"nm", SVector(2.0, 2.0, 2.0)u"nm",
                    SVector(5.0, 5.0, 5.0)u"nm"],
            boundary=CubicBoundary(10.0u"nm", 10.0u"nm", 10.0u"nm"),
            neighbor_finder=nf,
        )
        neighbors = find_neighbors(s, s.neighbor_finder; parallel=false)
        @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
        if run_parallel_tests
            neighbors = find_neighbors(s, s.neighbor_finder; parallel=true)
            @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
        end
        show(devnull, nf)
    end

    # Test passing the boundary and coordinates as keyword arguments to CellListMapNeighborFinder
    coords = [SVector(1.0, 1.0, 1.0)u"nm", SVector(2.0, 2.0, 2.0)u"nm", SVector(5.0, 5.0, 5.0)u"nm"]
    boundary = CubicBoundary(10.0u"nm", 10.0u"nm", 10.0u"nm")
    neighbor_finder=CellListMapNeighborFinder(
        nb_matrix=trues(3, 3), n_steps=10, x0=coords,
        unit_cell=boundary, dist_cutoff=2.0u"nm",
    )
    s = System(
        atoms=[Atom(), Atom(), Atom()],
        coords=coords,
        boundary=boundary,
        neighbor_finder=neighbor_finder,
    )
    neighbors = find_neighbors(s, s.neighbor_finder; parallel=false)
    @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
    if run_parallel_tests
        neighbors = find_neighbors(s, s.neighbor_finder; parallel=true)
        @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
    end
end

@testset "Analysis" begin
    pdb_path = joinpath(data_dir, "1ssu.pdb")
    struc = read(pdb_path, BioStructures.PDB)
    cm_1 = BioStructures.coordarray(struc[1], BioStructures.calphaselector)
    cm_2 = BioStructures.coordarray(struc[2], BioStructures.calphaselector)
    coords_1 = SVector{3, Float64}.(eachcol(cm_1)) / 10 * u"nm"
    coords_2 = SVector{3, Float64}.(eachcol(cm_2)) / 10 * u"nm"
    @test rmsd(coords_1, coords_2) ≈ 2.54859467758795u"Å"
    if run_gpu_tests
        @test rmsd(cu(coords_1), cu(coords_2)) ≈ 2.54859467758795u"Å"
    end

    bb_atoms = BioStructures.collectatoms(struc[1], BioStructures.backboneselector)
    coords = SVector{3, Float64}.(eachcol(BioStructures.coordarray(bb_atoms))) / 10 * u"nm"
    bb_to_mass = Dict("C" => 12.011u"u", "N" => 14.007u"u", "O" => 15.999u"u")
    atoms = [Atom(mass=bb_to_mass[BioStructures.element(bb_atoms[i])]) for i in 1:length(bb_atoms)]
    @test isapprox(radius_gyration(coords, atoms), 11.51225678195222u"Å", atol=1e-6u"nm")
end
