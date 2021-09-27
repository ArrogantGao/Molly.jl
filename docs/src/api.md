# Molly API

The API reference can be found here.

Molly also re-exports [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl) and [Unitful.jl](https://github.com/PainterQubits/Unitful.jl), making the likes of `SVector` and `1.0u"nm"` available when you call `using Molly`.

The [`visualize`](@ref) function is only available once you have called `using Makie`.
[Requires.jl](https://github.com/JuliaPackaging/Requires.jl) is used to lazily load this code when [Makie.jl](https://github.com/JuliaPlots/Makie.jl) is available, which reduces the dependencies of the package.

```@index
Order   = [:module, :type, :constant, :function, :macro]
```

```@autodocs
Modules = [Molly]
Private = false
Order   = [:module, :type, :constant, :function, :macro]
```
