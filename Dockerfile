FROM ubuntu AS base
RUN apt update && apt install -y nala

FROM base AS download_fabrics
WORKDIR /raw_hf
COPY --from=local_copy conus_nextgen.gpkg /raw_hf/

FROM base AS install_tools
# Install all the required tools
# protomaps, tippecanoe, gdal
RUN nala install -y build-essential libsqlite3-dev zlib1g-dev wget gdal-bin git

WORKDIR /tippecanoe
RUN git clone --single-branch --depth=1 https://github.com/felt/tippecanoe.git \
&& cd tippecanoe \
&& make -j \
&& make install

WORKDIR /pmtiles
ADD https://github.com/protomaps/go-pmtiles/releases/download/v1.30.3/go-pmtiles_1.30.3_Linux_x86_64.tar.gz /pmtiles/pmtiles.tar.gz
RUN tar -xvf pmtiles.tar.gz
RUN mv pmtiles /usr/local/bin

FROM install_tools AS hydrolocations_to_geom
RUN nala install -y python3-pip libsqlite3-mod-spatialite
RUN nala install -y sqlite3

COPY --from=download_fabrics /raw_hf /raw_hf
WORKDIR /hydrolocations_to_geom
COPY *.py .
COPY *.sql .

FROM hydrolocations_to_geom AS conus_to_geojson
# conus EPSG:5070
WORKDIR /geojson/conus
# disable spatial index to stop the UPDATEs below triggering spatial index rebuilds
RUN ogrinfo /raw_hf/conus_nextgen.gpkg -sql "SELECT DisableSpatialIndex('flowpaths','geom')"
RUN ogrinfo /raw_hf/conus_nextgen.gpkg -sql "SELECT DisableSpatialIndex('divides','geom')"

# convert the id fields to integers to speed up tiles creation and reduce tile size to allow for more geometry per tile
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "UPDATE flowpaths SET divide_id = CAST(substr(divide_id,5) AS INTEGER), id = CAST(substr(id,4) AS INTEGER), toid = CAST(substr(toid,5) AS INTEGER);"
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "UPDATE divides SET divide_id = CAST(substr(divide_id,5) AS INTEGER), id = CAST(substr(id,4) AS INTEGER), toid = CAST(substr(toid,5) AS INTEGER);"

# convert to flatgeobuf for use with tippecanoe
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 flowpaths.fgb /raw_hf/conus_nextgen.gpkg flowpaths
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 divides.fgb /raw_hf/conus_nextgen.gpkg divides
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 hydrolocations.fgb /raw_hf/conus_nextgen.gpkg hydrolocations

FROM conus_to_geojson AS conus_to_mbtiles

# create a filter to control tile zoom levels and geometry density
# the geometry must match ANY of the following conditions
# - zoom level is 1 or higher AND order is 5 or higher
# - zoom level is 4 or higher AND order is 4 or higher
# etc
#
# --drop-by-attribute-as-needed=order automatically does this
# These boundaries just speed it up so it doesn't waste time trying combinations that will fail
RUN cat > flowpaths-filter.json <<'JSON'
{
  "*": [ "any",
    [ "all", [ ">=", "$zoom", 1 ], [ ">=", "order", 5 ] ],
    [ "all", [ ">=", "$zoom", 4 ], [ ">=", "order", 4 ] ],
    [ "all", [ ">=", "$zoom", 5 ], [ ">=", "order", 3 ] ],
    [ "all", [ ">=", "$zoom", 7 ], [ ">", "order", 0 ] ],
    [ ">=", "$zoom", 8 ]
  ]
}
JSON

RUN tippecanoe -z10 -Z1 -o flowpaths.mbtiles \
    --use-attribute-for-id=divide_id \
    -l flowpaths \
    -y "id" -y "order" -y "divide_id" -y "toid" -X \
    -T "id":int -T "order":int -T "divide_id":int -T "toid":int \
    -aI  \
    -S 5 \
    -pS \
    -J flowpaths-filter.json \
    --drop-by-attribute-as-needed=order \
    --extend-zooms-if-still-dropping \
    flowpaths.fgb -P

RUN tippecanoe -z10 -Z4 -o divides.mbtiles \
    --use-attribute-for-id=divide_id \
    -l divides \
    -y "id" -y "order" -y "divide_id" -y "toid" -X \
    -T "id":int -T "order":int -T "divide_id":int -T "toid":int \
    --order-by="divide_id" \
    --coalesce-densest-as-needed \
    --accumulate-attribute="id":min \
    -aI  \
    divides.fgb -P


# RUN tippecanoe -z10 -Z2 -r1 --cluster-distance=5 -o hydrolocations.mbtiles -l conus_hydrolocations hydrolocations.fgb -P
# RUN tippecanoe -z10 -Z3 -r1 -j '{ "*": [ "any", [ "==", "hl_reference", "gages" ]] }' -o gages.mbtiles -l conus_gages hydrolocations.fgb -P
COPY upstream-idx.csv .
RUN tile-join -pk -c upstream-idx.csv -o conus.mbtiles flowpaths.mbtiles divides.mbtiles
#hydrolocations.mbtiles gages.mbtiles

FROM install_tools AS merge_mbtiles
WORKDIR /mbtiles/merged
COPY --from=conus_to_mbtiles /geojson/conus/conus.mbtiles .
RUN pmtiles convert --no-deduplication conus.mbtiles conus.pmtiles

#tippecanoe -z6 -o vpu.mbtiles --coalesce-densest-as-needed --force -P vpu.geojson
#tippecanoe -z10 -Z7 -o flowpaths.mbtiles --coalesce-densest-as-needed --extend-zooms-if-still-dropping flowpaths.geojson --force -P
