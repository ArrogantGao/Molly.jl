# Molly API

The API reference can be found here.

Molly also re-exports [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl), [Unitful.jl](https://github.com/PainterQubits/Unitful.jl) and [AtomsBase.jl](https://github.com/JuliaMolSim/AtomsBase.jl), making the likes of `SVector` and `1.0u"nm"` available when you call `using Molly`.

The [`visualize`](@ref) function is in a package extension and is only available once you have called `using GLMakie`.

```@index
Order   = [:module, :type, :constant, :function, :macro]
```

```@autodocs
Modules = [Molly]
Private = false
Order   = [:module, :type, :constant, :function, :macro]
```
