"""
"""
struct DB
    handle::SQLite.DB
    crs_dict::Dict{Int, Any}
    geometry_tables::NTuple{String}
end 

function gettable(db::DB, table_name::String = first(db.geometry_tables))
    @assert table_name in db.geometry_tables "Table $table_name is not a geometry table.  Available geometry tables are $(db.geometry_tables)."

    table_crs = "SE"
end

