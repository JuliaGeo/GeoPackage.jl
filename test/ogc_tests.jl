using Downloads, GeoPackage

# Get the GeoPackage files

sample1_2 = download("http://www.geopackage.org/data/sample1_2.gpkg")

sample1_2F10 = download("http://www.geopackage.org/data/sample1_2F10.gpkg")

source = SQLite.DB(sample1_2)
source = SQLite.DB(sample1_2F10)

crs_table = get_crs_table(source)

# Get the geometry table

_get_geometry_tables(source)




