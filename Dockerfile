FROM ubuntu AS base
RUN apt update && apt install -y nala
RUN nala install -y build-essential libsqlite3-dev zlib1g-dev wget gdal-bin git python3-pip libsqlite3-mod-spatialite sqlite3

WORKDIR /tippecanoe
RUN git clone --single-branch --depth=1 https://github.com/felt/tippecanoe.git \
&& cd tippecanoe \
&& make -j \
&& make install

WORKDIR /pmtiles
ADD https://github.com/protomaps/go-pmtiles/releases/download/v1.30.3/go-pmtiles_1.30.3_Linux_x86_64.tar.gz /pmtiles/pmtiles.tar.gz
RUN tar -xvf pmtiles.tar.gz
RUN mv pmtiles /usr/local/bin

FROM base AS hf_download
ADD --unpack https://communityhydrofabric.com/hydrofabrics/community/conus_nextgen.tar.gz /raw_hf/
# disable spatial index to stop the UPDATEs below triggering spatial index rebuilds
RUN ogrinfo /raw_hf/conus_nextgen.gpkg -sql "SELECT DisableSpatialIndex('divides','geom')"
RUN ogrinfo /raw_hf/conus_nextgen.gpkg -sql "SELECT DisableSpatialIndex('flowpaths','geom')"
RUN ogrinfo /raw_hf/conus_nextgen.gpkg -sql "SELECT DisableSpatialIndex('nexus','geom')"


FROM hf_download AS fix_10l
# this fix has huge implications that require recalculating any metrics like upstream area
# not done here as we're not using any of them in this simple example
# I just want the map to show flowpaths properly
# nexuses tnx-1000005433 and tnx-1000005436 shouldn't exist and instead there should be a nex-1580119
# they're in the right place so we can reuse one to avoid dealing with geometry
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "\
  DELETE FROM nexus WHERE id = 'tnx-1000005436'; \
  DELETE FROM network WHERE id = 'tnx-1000005436'; \
  UPDATE nexus SET id = 'nex-1580119', toid = 'wb-1580119', type = 'nexus' WHERE id IN ('tnx-1000005433','tnx-1000005436'); \
  UPDATE network SET id = 'nex-1580119', toid = 'wb-1580119', type = 'nexus' WHERE id IN ('tnx-1000005433','tnx-1000005436'); \
  UPDATE flowpaths SET toid = 'nex-1580119' WHERE toid IN ('tnx-1000005433','tnx-1000005436'); \
  UPDATE divides SET toid = 'nex-1580119' WHERE toid IN ('tnx-1000005433','tnx-1000005436'); \
  UPDATE network SET toid = 'nex-1580119' WHERE toid IN ('tnx-1000005433','tnx-1000005436'); \
"

FROM fix_10l AS fix_order
COPY tiles/fix_order.py .
RUN python3 fix_order.py

FROM fix_order AS upstream_indexing
WORKDIR /indexing
COPY indexing/main.py .
RUN python3 main.py


FROM fix_order AS conus_to_mbtiles
# conus EPSG:5070
WORKDIR /fgb/conus

# convert the id fields to integers to speed up tiles creation and reduce tile size to allow for more geometry per tile
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "UPDATE flowpaths SET divide_id = CAST(substr(divide_id,5) AS INTEGER), id = CAST(substr(id,4) AS INTEGER), toid = CAST(substr(toid,5) AS INTEGER);"
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "UPDATE divides SET divide_id = CAST(substr(divide_id,5) AS INTEGER), id = CAST(substr(id,4) AS INTEGER), toid = CAST(substr(toid,5) AS INTEGER);"

# convert to flatgeobuf for use with tippecanoe
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 flowpaths.fgb /raw_hf/conus_nextgen.gpkg flowpaths
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 divides.fgb /raw_hf/conus_nextgen.gpkg divides
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 hydrolocations.fgb /raw_hf/conus_nextgen.gpkg hydrolocations

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
# remove attributes at low zoom except Order, coalese

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
COPY --from=upstream_indexing ./indexing/upstream-idx.csv .
RUN tile-join -pk -c upstream-idx.csv -o conus.mbtiles flowpaths.mbtiles divides.mbtiles
#hydrolocations.mbtiles gages.mbtiles

FROM base AS join_tiles

WORKDIR /mbtiles/merged
COPY --from=conus_to_mbtiles /fgb/conus/conus.mbtiles .
RUN pmtiles convert --no-deduplication conus.mbtiles conus.pmtiles

FROM oven/bun:1 AS server
WORKDIR /usr/src/app
COPY map ./map
# only copying this so build.sh can copy it to a local folder outside of the container
COPY --from=upstream_indexing ./indexing/upstream-idx.csv /indexing/upstream-idx.csv
COPY --from=join_tiles /mbtiles/merged/conus.pmtiles ./tiles/conus.pmtiles
USER bun
EXPOSE 3000/tcp
ENTRYPOINT [ "bun", "run", "./map/server.ts" ]
