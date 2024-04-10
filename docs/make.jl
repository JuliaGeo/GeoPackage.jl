using GeoPackage
using Documenter, DocumenterVitepress
using Literate
using Makie, CairoMakie
CairoMakie.activate!(px_per_unit = 2, type = "svg", inline = true) # TODO: make this svg

DocMeta.setdocmeta!(GeoPackage, :DocTestSetup, :(using GeoPackage); recursive=true)

using GeoInterfaceMakie

# include(joinpath(dirname(@__DIR__), "benchmarks", "benchmark_plots.jl"))

# First, remove any codecov files that may have been generated by the CI run
for (root, dirs, files) in walkdir(dirname(@__DIR__)) # walk through `GeoPackage/*`
    # Iterate through all files in the current directory
    for file in files
        # If the file is a codecov file, remove it
        if splitext(file)[2] == ".cov"
            rm(joinpath(root, file))
        end
    end
end

# Now, we convert the source code to markdown files using Literate.jl
source_path = joinpath(dirname(@__DIR__), "src")
output_path = joinpath(@__DIR__, "src", "source")
mkpath(output_path)

literate_pages = Any[]

# We don't want Literate to convert the code into Documenter blocks, so we use a custom postprocessor
# to add the `@meta` block to the markdown file, which will be used by Documenter to add an edit link.
function _add_meta_edit_link_generator(path)
    return function (input)
        return """
        ```@meta
        EditURL = "$(path).jl"
        ```

        """ * input # we add `.jl` because `relpath` eats the file extension, apparently :shrug:
    end
end

# First letter of `str` is made uppercase and returned
ucfirst(str::String) = string(uppercase(str[1]), str[2:end])

function process_literate_recursive!(pages::Vector{Any}, path::String)
    global source_path
    global output_path
    if isdir(path)
        contents = []
        process_literate_recursive!.((contents,), normpath.(readdir(path; join = true)))
        push!(pages, ucfirst(splitdir(path)[2]) => contents)
    elseif isfile(path)
        if endswith(path, ".jl")
            relative_path = relpath(path, source_path)
            output_dir = joinpath(output_path, splitdir(relative_path)[1])
            Literate.markdown(
                path, output_dir; 
                flavor = Literate.CommonMarkFlavor(), 
                postprocess = _add_meta_edit_link_generator(joinpath(relpath(source_path, output_dir), relative_path))
            )
            push!(pages, joinpath("source", splitext(relative_path)[1] * ".md"))
        end
    end
end

withenv("JULIA_DEBUG" => "Literate") do # allow Literate debug output to escape to the terminal!
    global literate_pages
    vec = []
    process_literate_recursive!(vec, source_path)
    literate_pages = vec[1][2] # this is a hack to get the pages in the correct order, without an initial "src" folder.  
    # TODO: We should probably fix the above in `process_literate_recursive!`.
end

# Finally, make the docs!
makedocs(;
    modules=[GeoPackage],
    authors="Anshul Singhvi <anshulsinghvi@gmail.com> and contributors",
    repo="https://github.com/JuliaGeo/GeoPackage.jl/blob/{commit}{path}#{line}",
    sitename="GeoPackage.jl",
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/JuliaGeo/GeoPackage.jl",
    ),
    pages=[
        "Introduction" => "index.md",
        "Source code" => literate_pages,
    ],
    warnonly = true,
)

deploydocs(;
    repo="github.com/JuliaGeo/GeoPackage.jl",
    devbranch="main",
    push_preview = true,
)