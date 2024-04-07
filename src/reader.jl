using SQLite, GeoInterface, Tables
import GeoInterface as GI, GeoFormatTypes as GFT, WellKnownGeometry as WKG

using DataFrames

#=

## Notes on working with SQLite.jl

- Queries can only be materialized once - so read them eagerly into Julia!
=#

source = SQLite.DB(joinpath(dirname(@__DIR__), "test", "data", "polygon.gpkg"))

crs_table = DBInterface.execute(source, "SELECT * FROM gpkg_spatial_ref_sys;")
crs_df = DataFrame(crs_table)

contents_table = DBInterface.execute(source, "SELECT * FROM gpkg_contents;")

geometry_tables = map(Tables.rows(contents_table)) do row
    table_name = row.table_name
    table_type = row.data_type
    srs_id = row.srs_id
    crs_data = crs_df[findfirst(==(srs_id), crs_df.srs_id), :]

    if table_type != "features"
        @warn """
        Trying to parse table with type other than `features` is not supported by GeoPackage.jl.
        Got table type: $table_type
        """
        return DataFrame()
    end
    table_query = "SELECT * FROM $table_name;"
    table_query_result = DBInterface.execute(source, table_query)
    DataFrame(table_query_result)
end

geometry_tables

polytable = first(geometry_tables)
poly_wkb = polytable.geom[1]

# Check that the magic number is correct
@assert poly_wkb[1] == 0x47 && poly_wkb[2] == 0x50 "The magic bits for a GeoPackage WKB are not present."
# Get version and flag bytes
version = poly_wkb[3]
flag_byte = poly_wkb[4]
# Expand the flag byte into its components
is_extended_gpkg = (flag_byte & 0b00100000) == 0b00100000
is_empty =( flag_byte & 0b0001000) == 0b0001000
envelope_size_byte = flag_byte << 4 >> 5
is_little_endian = (flag_byte & 0b00000001) == 0b00000001

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

# envelope = if envelope_size_byte == 0
#     nothing
# elseif envelope_size_byte == 1
#     nums = (reinterpret(Float))
#     reinterpret(Float32, poly_wkb[9:()])
# end


# Obtain the SRS ID
srs_id = only(reinterpret(Int32, poly_wkb[5:8]))
# Look this ID up and convert it into a CRS object from GeoFormatTypes.
crs_row = crs_df[findfirst(==(srs_id), crs_df.srs_id), :]
crs_obj = if crs.organization == "EPSG"
    GFT.EPSG(crs_row.organization_coordsys_id)
else
    GFT.WellKnownText(GFT.CRS(), crs_row.definition)
end
# 
header_length = 4 #= length of original flags =# + 8 #= length of CRS indicator as Int32 =# + envelope_size

ArchGDAL.fromWKB(poly_wkb[header_length:end]) #|> GI.trait

GFT.WellKnownBinary(GFT.Geom(), poly_wkb[(header_length):end]) |> GI.trait
