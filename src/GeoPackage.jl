module GeoPackage

using SQLite, GeoInterface, Tables
import GeoInterface as GI, GeoFormatTypes as GFT, WellKnownGeometry as WKG

using TimerOutputs
const to = TimerOutput()

include("reader.jl")
# include("writer.jl")

end
