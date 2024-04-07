using GeoPackage
using Documenter

DocMeta.setdocmeta!(GeoPackage, :DocTestSetup, :(using GeoPackage); recursive=true)

makedocs(;
    modules=[GeoPackage],
    authors="Anshul Singhvi <anshulsinghvi@gmail.com> and contributors",
    sitename="GeoPackage.jl",
    format=Documenter.HTML(;
        canonical="https://JuliaGeo.github.io/GeoPackage.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaGeo/GeoPackage.jl",
    devbranch="main",
)
