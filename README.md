# GeoPackage

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaGeo.github.io/GeoPackage.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaGeo.github.io/GeoPackage.jl/dev/)
[![Build Status](https://github.com/JuliaGeo/GeoPackage.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaGeo/GeoPackage.jl/actions/workflows/CI.yml?query=branch%3Amain)

> [!WARNING]
> This package does not work yet!

GeoPackage.jl is designed to be a fast and mostly native Julia reader of GeoPackage (`.gpkg`) files.  

It currently only supports geometry tables, and not tilesets or other raster variants.  If you want to read such a table, use ArchGDAL.jl which can perform this reading.

## How it works
The package has 2 main components:
1. An SQL query mechanism to obtain the various geometry tables from the `.gpkg` file
2. A method to parse binary representations of geometry into a Julia-native form.