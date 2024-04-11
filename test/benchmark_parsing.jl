import GeoFormatTypes as GFT, WellKnownGeometry as WKG, GeoInterface as GI

# db = SQLite.DB("/Users/anshul/git/vector-benchmark/data/points.gpkg")

# crs_table = get_crs_table(db)

# table_query = """
# SELECT gpkg_geometry_columns.table_name, gpkg_geometry_columns.column_name, gpkg_geometry_columns.geometry_type_name, gpkg_contents.srs_id
# FROM gpkg_geometry_columns
# LEFT JOIN gpkg_contents ON gpkg_geometry_columns.table_name = gpkg_contents.table_name;
# """
# table_query_result = DBInterface.execute(db, table_query)
# contents_df = DataFrame(table_query_result)

# geoms_table = Tables.columntable(DBInterface.execute(db, "SELECT $(contents_df[1, :column_name]) FROM $(contents_df[1, :table_name])"))

# geoms = geoms_table.geom

tups = tuple.(rand(300_000), rand(300_000))

geoms = GFT.val.(WKG.getwkb.(GI.Point.(tups)))

# Parsing approach 1 - using WellKnownGeometry directly

GFT.WellKnownBinary(GFT.Geom(), view(geoms[1], (8+1):length(geoms[1])))
# This is a bit unfair because a lot of the parsing work would have happened earlier in approach 2, 
# but even that is at most 1ms.
@benchmark begin
    GO.tuples(GFT.WellKnownBinary.((GFT.Geom(),), getindex.($geoms, ((8+1):length($(geoms[1])),))))
end

# BenchmarkTools.Trial: 19 samples with 1 evaluation.
#  Range (min … max):  254.759 ms … 283.244 ms  ┊ GC (min … max):  6.17% … 15.63%
#  Time  (median):     270.962 ms               ┊ GC (median):    10.07%
#  Time  (mean ± σ):   269.855 ms ±   8.431 ms  ┊ GC (mean ± σ):  10.96% ±  3.00%

#   ▁       █   ▁ ▁       ▁ ▁  ▁   ▁  ▁ █   ▁     ▁ ▁ ▁   ▁ ▁   ▁  
#   █▁▁▁▁▁▁▁█▁▁▁█▁█▁▁▁▁▁▁▁█▁█▁▁█▁▁▁█▁▁█▁█▁▁▁█▁▁▁▁▁█▁█▁█▁▁▁█▁█▁▁▁█ ▁
#   255 ms           Histogram: frequency by time          283 ms <

# Parsing approach 2 - reinterpret the bytes as a tuple

@benchmark begin
    map($(geoms)) do geom
        only(reinterpret(Tuple{Float64, Float64}, view(geom, (8+1+5):length(geom))))
    end
end

ls = GI.LineString(map((geoms)) do geom
    only(reinterpret(Tuple{Float64, Float64}, view(geom, (8+1+5):length(geom)))) # this should be 5+1 if we are parsing from WKB
end)

ls_as_wkb = GFT.val(WKG.getwkb(ls))

# Parsing approach 1 - reduce to GO.tuples
@benchmark collect(GI.getpoint(GFT.WellKnownBinary(GFT.Geom(), $ls_as_wkb)))

# Parsing approach 2 - reduce to reinterpret
@benchmark collect(reinterpret(Tuple{Float64, Float64}, view($ls_as_wkb, (1+4+4+1):length($ls_as_wkb))))


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
