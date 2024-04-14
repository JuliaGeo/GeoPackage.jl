import GeoFormatTypes as GFT, WellKnownGeometry as WKG, GeoInterface as GI

db = SQLite.DB("/Users/anshul/git/vector-benchmark/data/points.gpkg")
db = SQLite.DB("/Users/anshul/git/vector-benchmark/data/polygon.gpkg")

crs_table = get_crs_table(db)

table_query = """
SELECT gpkg_geometry_columns.table_name, gpkg_geometry_columns.column_name, gpkg_geometry_columns.geometry_type_name, gpkg_contents.srs_id
FROM gpkg_geometry_columns
LEFT JOIN gpkg_contents ON gpkg_geometry_columns.table_name = gpkg_contents.table_name;
"""
table_query_result = DBInterface.execute(db, table_query)
contents_df = DataFrame(table_query_result)

geoms_table = Tables.columntable(DBInterface.execute(db, "SELECT $(contents_df[1, :column_name]) FROM $(contents_df[1, :table_name])"))

geoms = geoms_table.geom

tups = tuple.(rand(300_000), rand(300_000))
tups = tuple.(rand(3000), rand(3000))

geoms = GFT.val.(WKG.getwkb.(GI.Point.(tups)))

# Parsing approach 1 - using WellKnownGeometry directly

GFT.WellKnownBinary(GFT.Geom(), view(geoms[1], (8+1):length(geoms[1]))) |> GI.trait
# This is a bit unfair because a lot of the parsing work would have happened earlier in approach 2, 
# but even that is at most 1ms.  Plus, this is allocating vectors where the next method is not.
@benchmark begin
    GI.coordinates.(GFT.WellKnownBinary.((GFT.Geom(),), getindex.($geoms, ((8+1):length($(geoms[1])),))))
end

# BenchmarkTools.Trial: 43 samples with 1 evaluation.
#  Range (min … max):  107.476 ms … 163.324 ms  ┊ GC (min … max): 0.00% … 7.01%
#  Time  (median):     116.491 ms               ┊ GC (median):    5.98%
#  Time  (mean ± σ):   118.121 ms ±   9.870 ms  ┊ GC (mean ± σ):  5.11% ± 2.83%

#         ▄  █                                                     
#   ██▁▁▄▄██▆█▄████▁▁▁▁▁▁▁▁▄▁▁▄▁▁▁▁▁▄▁▁▄▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▄ ▁
#   107 ms           Histogram: frequency by time          163 ms <

#  Memory estimate: 57.22 MiB, allocs estimate: 1200009.

# Parsing approach 2 - reinterpret the bytes as a tuple

@benchmark begin
    map($(geoms)) do geom
        only(reinterpret(Tuple{Float64, Float64}, view(geom, (8+1+5):length(geom))))
    end
end

# BenchmarkTools.Trial: 1520 samples with 1 evaluation.
#  Range (min … max):  2.622 ms …  13.164 ms  ┊ GC (min … max): 0.00% … 26.14%
#  Time  (median):     3.054 ms               ┊ GC (median):    0.00%
#  Time  (mean ± σ):   3.283 ms ± 782.676 μs  ┊ GC (mean ± σ):  5.00% ± 10.67%

#     ▂▇▇██▆▅▅▄▄▃▂▁                                             ▁
#   ▆▅█████████████▇▆▆▆▁▄▅▅▁▆▄▁▅▁▄▁▁▄▅▁▅▅▆▇▆▇▅▇█▆▅▅▇▆▅▁▆▄▄▁▄▄▇▄ █
#   2.62 ms      Histogram: log(frequency) by time      6.64 ms <

#  Memory estimate: 4.58 MiB, allocs estimate: 2.

ls = GI.LineString(map((geoms)) do geom
    only(reinterpret(GI.Point{false, false, Makie.Point{2, Float64}, Nothing}, view(geom, (1+5):length(geom)))) # this should be 5+1 if we are parsing from WKB
end)

ls_as_wkb = GFT.val(WKG.getwkb(ls))

# Parsing approach 1 - reduce to GO.tuples
@benchmark GI.coordinates(GFT.WellKnownBinary(GFT.Geom(), $ls_as_wkb))

# Parsing approach 2 - reduce to reinterpret
@benchmark reinterpret(GI.Point{false, false, Makie.Point{2, Float64}, Nothing}, view($ls_as_wkb, (1+4+4+1):length($ls_as_wkb)))
# This is 2 ns without collect, 200 ns with collect.

# BenchmarkTools.Trial: 10000 samples with 334 evaluations.
#  Range (min … max):  258.111 ns …  3.375 μs  ┊ GC (min … max): 0.00% … 89.28%
#  Time  (median):     274.826 ns              ┊ GC (median):    0.00%
#  Time  (mean ± σ):   280.685 ns ± 97.172 ns  ┊ GC (mean ± σ):  1.11% ±  2.94%

#            ▁▄█▇▅▂  ▁ ▂▁
#   ▁▁▂▃▃▃▄▃▅███████▇████▆▆▄▄▄▄▃▃▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▃
#   258 ns          Histogram: frequency by time          326 ns <

#  Memory estimate: 160 bytes, allocs estimate: 4.


# Parsing approach 3 - ArchGDAL
@benchmark ArchGDAL.fromWKB(ls_as_wkb)

# BenchmarkTools.Trial: 3790 samples with 1 evaluation.
#  Range (min … max):  399.750 μs …   1.036 s  ┊ GC (min … max): 0.00% … 0.00%
#  Time  (median):     492.834 μs              ┊ GC (median):    0.00%
#  Time  (mean ± σ):     1.317 ms ± 17.177 ms  ┊ GC (mean ± σ):  0.00% ± 0.00%

#   █▆▂▁▁▁        ▁ ▁ ▁                                          ▁
#   ██████▇██▇███████████▆▄▆▄▆▄▄▄▅▄▅▄▅▅▄▄▁▄▄▄▃▁▅▄▄▄▁▄▄▁▃▃▁▃▃▁▃▁▄ █
#   400 μs        Histogram: log(frequency) by time      7.67 ms <

#  Memory estimate: 48 bytes, allocs estimate: 3.

@b _get_geometry_tables(joinpath(dirname(@__DIR__), "test", "data", "polygon.gpkg")) seconds=3

# Quick & easy linestring - ignore endianness for now
function _easy(::Type{GT}, wkb::AbstractVector{UInt8}, ::Val{Z}, ::Val{M}) where {GT <: Union{GI.LineString, GI.LinearRing}, Z, M}
    header = (1#=endianness=#+4#=geomtype=#+4#=srid.sth=#)
    points = reinterpret(GI.Point{Z, M, Point{2+Z+M, Float64}, Nothing}, @view wkb[header+1:end])
    return GT{Z, M, typeof(points), Nothing, Nothing}(
        points,
        nothing, 
        nothing
    )
end

_easy(GI.LineString, ls_as_wkb, (Val(false)), (Val(false)))

@benchmark _easy(GI.LineString, $ls_as_wkb, $(Val(false)), $(Val(false)))

function _easy_polygon(wkb::AbstractVector{UInt8}, ::Val{Z}, ::Val{M})