
function velocity_constraints!(sys::System, constraint_algo::SHAKE_RATTLE;
     n_threads::Integer=Threads.nthreads())

    RATTLE_updates!(sys, constraint_algo)
 
    return sys
end

function RATTLE_updates!(sys, ca::SHAKE_RATTLE)

    converged = false

    while !converged
        for cluster in ca.clusters #& illegal to parallelize this
            for constraint in cluster.constraints

                # Index of atoms in bond k
                k1, k2 = constraint.atom_idxs

                # Inverse of masses of atoms in bond k
                inv_m1 = 1/mass(sys.atoms[k1])
                inv_m2 = 1/mass(sys.atoms[k2])

                # Distance vector between the atoms after SHAKE constraint
                r_k1k2 = vector(sys.coords[k2], sys.coords[k1], sys.boundary)

                # Difference between unconstrainted velocities
                v_k1k2 = sys.velocities[k2] .- sys.velocities[k1]

                err = abs(dot(r_k1k2, v_k1k2))
                if err > ca.vel_tolerance
                    # Re-arrange constraint equation to solve for Lagrange multiplier
                    # Technically this has a factor of dt which cancels out in the velocity update
                    λₖ = -dot(r_k1k2,v_k1k2)/(dot(r_k1k2,r_k1k2)*(inv_m1 + inv_m2))

                    # Correct velocities
                    sys.velocities[k1] -= (inv_m1 .* λₖ .* r_k1k2)
                    sys.velocities[k2] += (inv_m2 .* λₖ .* r_k1k2)
                end

            end
        end

        converged = check_velocity_constraints(sys, ca)
    end

end

