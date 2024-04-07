"""
    parse_geopkg_wkb(wkb::Vector{UInt8})

Parse a GeoPackage WKB (Well-Known Binary) representation into a GeoInterface Geometry.


# Extended help
## Structure
```c
GeoPackageBinaryHeader {
  byte[2] magic = 0x4750; 
  byte version;           
  byte flags;             
  int32 srs_id;           
  double[] envelope;      
}

StandardGeoPackageBinary {
  GeoPackageBinaryHeader header;
  WKBGeometry geometry;          
}
```
so 
"""
function parse_geopkg_wkb(wkb::Vector{UInt8})
    @assert reinterpret(UInt16, (wkb[1], wkb[2])) == 0x4750
end