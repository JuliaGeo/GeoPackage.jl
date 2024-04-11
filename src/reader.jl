#=
# The reader

This file contains the code for reading GeoPackage files.

It uses the DBInterface.jl and SQLite.jl packages to read the GeoPackage file as a SQLite database,
and then reads the tables in the GeoPackage file into DataFrames.

Finally, it converts the GeoPackage-WKB (Well-Known Binary) representations of the geometries into GeoInterface geometries.
=#

using SQLite, GeoInterface, Tables
import GeoInterface as GI, GeoFormatTypes as GFT, WellKnownGeometry as WKG
import GeometryOps as GO

using DataFrames, TimerOutputs

struct __GeoPackageFile
    source::SQLite.DB
end

"""
This dict encodes a lookup from geometry type strings as defined in 

"""
const GEOMETRY_TYPE_LOOKUP = Dict{String, Type}(
    "POINT" => GI.PointTrait,
    "LINESTRING" => GI.LineStringTrait,
    "POLYGON" => GI.PolygonTrait,
    "MULTIPOINT" => GI.MultiPointTrait,
    "MULTILINESTRING" => GI.MultiLineStringTrait,
    "MULTIPOLYGON" => GI.MultiPolygonTrait,
    "GEOMETRYCOLLECTION" => GI.GeometryCollectionTrait,
    "GEOMETRY" => GI.AbstractGeometryTrait
)

#=

## Notes on working with SQLite.jl

- Queries can only be materialized once - so read them eagerly into Julia!
=#

# Load the GeoPackage file as a SQLite database
# ```julia
# source = SQLite.DB(joinpath(dirname(@__DIR__), "test", "data", "polygon.gpkg"))
# source = SQLite.DB("/Users/anshul/git/vector-benchmark/data/points.gpkg")
# ```

# Get the various tables we'll need.

function get_crs_table(source)
    global to
    @timeit to "CRS table" begin
        @timeit to "Query" begin
            crs_table = DBInterface.execute(source, "SELECT * FROM gpkg_spatial_ref_sys;")
        end
        @timeit to "Materialization" begin
            crs_df = DataFrame(crs_table)
        end
        @timeit to "CRS parsing" begin
            crs_df[!, :gft] = _crs_row_to_gft.(eachrow(crs_df))
        end
    end
    return crs_df
end

function get_geometry_table(source, table_name, crs_table = get_crs_table(source))
    global to
    @timeit to "Table retrieval" begin
        table_query = """
        SELECT gpkg_geometry_columns.column_name, gpkg_geometry_columns.geometry_type_name, gpkg_contents.srs_id
        FROM gpkg_geometry_columns
        LEFT JOIN gpkg_contents ON gpkg_geometry_columns.table_name = gpkg_contents.table_name;
        """
        table_query_result = DBInterface.execute(source, table_query)
        @timeit to "Materialization" result = first(table_query_result)
    end
    geometry_type = GEOMETRY_TYPE_LOOKUP[result[:geometry_type_name]]
    return _get_geometry_table(geometry_type, source, table_name, result[:column_name], result[:srs_id], crs_table)
end

function _get_geometry_table(geometry_type::Type{T}, source, table_name, geometry_column, srs_id, crs_table) where T <: GI.AbstractTrait
    global to
    @timeit to "Table retrieval" begin
        table_query = "SELECT * FROM $table_name;"
        table_query_result = DBInterface.execute(source, table_query)
        @timeit to "Materialization" result = DataFrame(table_query_result)
    end

    @timeit to "WKB parsing" begin
        result[!, geometry_column] = parse_geopkg_wkb.(result[!, geometry_column]; crs_table = crs_table)
    end
    DataFrames.metadata!(result, "GeoPackage.jl SRS data", crs_table)
    DataFrames.metadata!(result, "GeoPackage.jl default SRS", srs_id)
    return result
end

function _get_geometry_table(geometry_type::Type{GI.PointTrait}, source, table_name, geometry_column, srs_id, crs_table)
    global to
    @timeit to "Table retrieval" begin
        table_query = "SELECT * FROM $table_name;"
        table_query_result = DBInterface.execute(source, table_query)
        @timeit to "Materialization" result = DataFrame(table_query_result)
    end

    @timeit to "WKB parsing" begin
        result[!, geometry_column] = parse_geopkg_wkb.(result[!, geometry_column]; crs_table = crs_table)
    end
    DataFrames.metadata!(result, "GeoPackage.jl SRS data", crs_table)
    DataFrames.metadata!(result, "GeoPackage.jl default SRS", srs_id)
    return result
end

function _get_geometry_tables(source::SQLite.DB)::Vector{DataFrame}
    global to
    @timeit to "General queries" begin
    # First, we obtain the CRS reference table.
    crs_df = get_crs_table(source)
    # # Next, we obtain the table of extensions.  This is not actually useful yet, so is commented out.
    # extensions_table = DBInterface.execute(source, "SELECT * FROM gpkg_extensions;")
    # extensions_materialized = Tables.columntable(extensions_table)
    # Next, we obtain the table of contents.
    @timeit to "Contents table" begin
    contents_table = DBInterface.execute(
        source, 
        """
            SELECT * 
            FROM gpkg_geometry_columns
            LEFT JOIN gpkg_contents ON gpkg_geometry_columns.table_name = gpkg_contents.table_name;
        """
        )
    end
    end
    # We can use this to get the names of the tables we need to read.
    function _ggt(row)
        _get_geometry_table(source, row[:table_name], row[:column_name], row[:srs_id], crs_df)
    end
    @timeit to "Get geometry tables" begin
        geometry_tables = map(_ggt, filter(row -> Tables.getcolumn(row, :data_type) == "features", Tables.rowtable(contents_table) |> collect))
    end
    return geometry_tables
end
_get_geometry_tables(file::String) = _get_geometry_tables(SQLite.DB(file))

function _crs_row_to_gft(crs_row)
    if crs_row[:organization] == "EPSG"
        GFT.EPSG(crs_row[:organization_coordsys_id])
    else
        GFT.WellKnownText(GFT.CRS(), crs_row[:definition])
    end
end


function parse_envelope(wkb::Vector{UInt8},)
    envelope = wkb[9:8+envelope_size]
    x_min = reinterpret(Float64, envelope[1:8])
    y_min = reinterpret(Float64, envelope[9:16])
    x_max = reinterpret(Float64, envelope[17:24])
    y_max = reinterpret(Float64, envelope[25:32])
    return (x_min, y_min, x_max, y_max)
end

function parse_geopkg_wkb(wkb::Vector{UInt8}; crs_table)
    # Check that the magic number is correct
    @assert wkb[1] == 0x47 && wkb[2] == 0x50 "The magic bits for a GeoPackage WKB are not present.  Expected `[0x47, 0x50]`, got `$(wkb[1:2])`."
    # Get version and flag bytes
    version = wkb[3]
    flag_byte = wkb[4]
    # Expand the flag byte into its components
    is_extended_gpkg = (flag_byte & 0b00100000) == 0b00100000 # is the GeoPackage extended?
    is_empty = (flag_byte & 0b0001000) == 0b0001000           # is the geometry empty? TODO: short-circuit here, return an empty geom.  May be a NaN geom instead.
    envelope_size_byte = flag_byte << 4 >> 5                  # what is the category of the envelope?  See note above.
    is_little_endian = (flag_byte & 0b00000001) == 0b00000001 # is the WKB little-endian?  If not we can't yet handle it in native Julia.

    # Calculate envelope size according to the definition in the GeoPackage spec
    envelope_size = if envelope_size_byte == 0
        0
    elseif envelope_size_byte == 1
        32
    elseif envelope_size_byte == 2
        48
    elseif envelope_size_byte == 3
        48
    elseif envelope_size_byte == 4
        64
    else
        error("Invalid envelope size byte: $envelope_size_byte.  Specifically, the number evaluated to $(envelope_size_byte), which is in the invalid region between 5 and 7.")
    end
    # Obtain the SRS ID
    srs_id = only(reinterpret(Int32, wkb[5:8]))
    # Look this ID up and convert it into a CRS object from `GeoFormatTypes`.
    crs_row = findfirst(==(srs_id), crs_table.srs_id)
    # We've preprocessed all available CRSs in the geopackage file into 
    # GeoFormatTypes objects, so we can just index into that table.
    crs_obj = crs_table[crs_row, :gft]
    # Calculate the number of bytes in the GeoPackage spec header.
    # This is dynamic, as it depends on the envelope size.
    header_length = 4 #= length of original flags =# + 
                    4 #= length of CRS indicator as Int32 =# + 
                    envelope_size #= size of envelope as given =#
    # We index into the WKB to get the actual geometry.
    # We need to start from the byte _after_ the header, i.e., `header_length+1`.
    final_geom = GO.tuples(GFT.WellKnownBinary(GFT.Geom(), wkb[(header_length+1):end]); crs = crs_obj)
    return final_geom
end

function _easy_get_point(wkb::Vector{UInt8})
     # Check that the magic number is correct
     @assert wkb[1] == 0x47 && wkb[2] == 0x50 "The magic bits for a GeoPackage WKB are not present.  Expected `[0x47, 0x50]`, got `$(wkb[1:2])`."
     # Get version and flag bytes
     version = wkb[3]
     flag_byte = wkb[4]
     # Expand the flag byte into its components
     is_extended_gpkg = (flag_byte & 0b00100000) == 0b00100000 # is the GeoPackage extended?
     is_empty = (flag_byte & 0b0001000) == 0b0001000           # is the geometry empty? TODO: short-circuit here, return an empty geom.  May be a NaN geom instead.
     envelope_size_byte = flag_byte << 4 >> 5                  # what is the category of the envelope?  See note above.
     is_little_endian = (flag_byte & 0b00000001) == 0b00000001 # is the WKB little-endian?  If not we can't yet handle it in native Julia.
 
     # Calculate envelope size according to the definition in the GeoPackage spec
     envelope_size = if envelope_size_byte == 0
         0
     elseif envelope_size_byte == 1
         32
     elseif envelope_size_byte == 2
         48
     elseif envelope_size_byte == 3
         48
     elseif envelope_size_byte == 4
         64
     else
         error("Invalid envelope size byte: $envelope_size_byte.  Specifically, the number evaluated to $(envelope_size_byte), which is in the invalid region between 5 and 7.")
     end
     # Obtain the SRS ID
     srs_id = only(reinterpret(Int32, wkb[5:8]))
     # Look this ID up and convert it into a CRS object from `GeoFormatTypes`.
     crs_row = findfirst(==(srs_id), crs_table.srs_id)
     # We've preprocessed all available CRSs in the geopackage file into 
     # GeoFormatTypes objects, so we can just index into that table.
     crs_obj = crs_table[crs_row, :gft]
     # Calculate the number of bytes in the GeoPackage spec header.
     # This is dynamic, as it depends on the envelope size.
     header_length = 4 #= length of original flags =# + 
                     4 #= length of CRS indicator as Int32 =# + 
                     envelope_size #= size of envelope as given =#
     # We index into the WKB to get the actual geometry.
     # We need to start from the byte _after_ the header, i.e., `header_length+1`.
     final_geom = GI.Point(reinterpret(Float64, wkb[(header_length+1+5):end]); crs = crs_obj)
     return final_geom
end

# @b _get_geometry_tables(joinpath(dirname(@__DIR__), "test", "data", "polygon.gpkg")) seconds=3 # 313 μs
# ────────────────────────────────────────────────────────────────────────────────
#                                         Time                    Allocations      
#                                ───────────────────────   ────────────────────────
#        Tot / % measured:            4.65s /  55.8%            383MiB /  94.9%    
#
#  Section               ncalls     time    %tot     avg     alloc    %tot      avg
#  ────────────────────────────────────────────────────────────────────────────────
#  General queries        7.08k    1.69s   65.1%   239μs    103MiB   28.3%  14.9KiB
#    CRS table            7.08k    1.57s   60.3%   221μs   79.2MiB   21.8%  11.4KiB
#      Query              7.08k    1.29s   49.5%   182μs   17.7MiB    4.9%  2.56KiB
#      Materialization    7.08k    256ms    9.9%  36.2μs   56.1MiB   15.4%  8.12KiB
#      CRS parsing        7.08k   20.0ms    0.8%  2.82μs   5.30MiB    1.5%     784B
#    Contents table       7.08k    124ms    4.8%  17.5μs   23.7MiB    6.5%  3.42KiB
#  Get geometry tables    7.08k    905ms   34.9%   128μs    261MiB   71.7%  37.8KiB
#    WKB parsing          7.08k    554ms   21.3%  78.2μs    216MiB   59.3%  31.2KiB
#    Table retrieval      7.08k    121ms    4.7%  17.1μs   34.5MiB    9.5%  4.99KiB
#      Materialization    7.08k   65.6ms    2.5%  9.27μs   20.9MiB    5.7%  3.02KiB
#  ────────────────────────────────────────────────────────────────────────────────
# @b GeoDataFrames.read(joinpath(dirname(@__DIR__), "test", "data", "polygon.gpkg")) seconds=3   # 781 μs

# @b _get_geometry_tables("/Users/anshul/git/vector-benchmark/data/points.gpkg") seconds=10 # 894 ms
# ────────────────────────────────────────────────────────────────────────────────
# Time                    Allocations      
# ───────────────────────   ────────────────────────
# Tot / % measured:             142s /   7.8%           3.26GiB /  99.3%    
#
# Section               ncalls     time    %tot     avg     alloc    %tot      avg
# ────────────────────────────────────────────────────────────────────────────────
# Get geometry tables       12    11.1s   99.9%   926ms   3.23GiB  100.0%   276MiB
# WKB parsing             12    6.10s   54.9%   508ms   1.82GiB   56.4%   156MiB
# Table retrieval         12    5.01s   45.1%   417ms   1.41GiB   43.6%   120MiB
# Materialization       12    5.01s   45.1%   417ms   1.41GiB   43.6%   120MiB
# General queries           12   7.39ms    0.1%   616μs    182KiB    0.0%  15.2KiB
# CRS table               12   6.94ms    0.1%   578μs    140KiB    0.0%  11.6KiB
# Query                 12   5.26ms    0.0%   439μs   30.8KiB    0.0%  2.56KiB
# Materialization       12   1.47ms    0.0%   123μs   97.4KiB    0.0%  8.12KiB
# CRS parsing           12    190μs    0.0%  15.9μs   9.19KiB    0.0%     784B
# Contents table          12    445μs    0.0%  37.1μs   41.1KiB    0.0%  3.42KiB
# ────────────────────────────────────────────────────────────────────────────────
# @b GeoDataFrames.read("/Users/anshul/git/vector-benchmark/data/points.gpkg") seconds=10 # 195 ms
# @b GO.tuples(GeoDataFrames.read("/Users/anshul/git/vector-benchmark/data/points.gpkg").geom) seconds=10 # 213 ms