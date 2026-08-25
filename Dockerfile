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

FROM fix_order AS numeric_id
RUN sqlite3 /raw_hf/conus_nextgen.gpkg <<'EOF'
ALTER TABLE flowpaths ADD COLUMN widthcm REAL;
UPDATE flowpaths
SET widthcm =
    (SELECT fa.TopWdthCC * 100
     FROM "flowpath-attributes" fa WHERE fa.id = flowpaths.id)
WHERE id IN (SELECT id FROM "flowpath-attributes");
EOF

# convert the id fields to integers to speed up tiles creation and reduce tile size to allow for more geometry per tile
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "UPDATE flowpaths SET divide_id = CAST(substr(divide_id,5) AS INTEGER), id = CAST(substr(id,4) AS INTEGER), toid = CAST(substr(toid,5) AS INTEGER);"
RUN sqlite3 /raw_hf/conus_nextgen.gpkg "UPDATE divides SET divide_id = CAST(substr(divide_id,5) AS INTEGER), id = CAST(substr(id,4) AS INTEGER), toid = CAST(substr(toid,5) AS INTEGER);"

COPY --from=upstream_indexing ./indexing/upstream-idx.csv .
RUN sqlite3 /raw_hf/conus_nextgen.gpkg <<'EOF'
DROP TABLE IF EXISTS tmp;
.import --csv upstream-idx.csv tmp
CREATE INDEX idx_tmp_id ON tmp(id);
ALTER TABLE flowpaths ADD COLUMN upstream_id INTEGER;
ALTER TABLE flowpaths ADD COLUMN num_upstreams INTEGER;
ALTER TABLE flowpaths ADD COLUMN merge_group TEXT;
ALTER TABLE divides ADD COLUMN upstream_id INTEGER;
ALTER TABLE divides ADD COLUMN num_upstreams INTEGER;
ALTER TABLE divides ADD COLUMN merge_group TEXT;
UPDATE flowpaths
SET (upstream_id, num_upstreams, merge_group) =
    (SELECT CAST(t.upstream_id AS INTEGER), CAST(t.num_upstreams AS INTEGER), t.merge_group
     FROM tmp t WHERE t.id = flowpaths.id)
WHERE id IN (SELECT id FROM tmp);
UPDATE divides
SET (upstream_id, num_upstreams, merge_group) =
    (SELECT CAST(t.upstream_id AS INTEGER), CAST(t.num_upstreams AS INTEGER), t.merge_group
     FROM tmp t WHERE t.id = divides.id)
WHERE id IN (SELECT id FROM tmp);
DROP TABLE tmp;
EOF

# variables we want to keep, make sure to also add these to the sql query below
# remove as many strings as possible and convert to int where possible e.g. float meters to int cm will be much smaller
# The smaller we make these attributes, the more geometry we can keep in our tiles
ARG ATTRS='-y order -y divide_id -y upstream_id -y num_upstreams -y toid -y widthcm -y '
ARG TYPES='-T order:int -T divide_id:int -T upstream_id:int -T num_upstreams:int -T toid:int -T widthcm:int'
WORKDIR /fgb/conus

FROM numeric_id AS low_zoom
RUN ogr2ogr /raw_hf/fixed.gpkg /raw_hf/conus_nextgen.gpkg \
  -dialect sqlite -nlt MULTILINESTRING\
  -sql 'SELECT ST_LineMerge(ST_Union(geom)) AS geom, merge_group, MIN(upstream_id) AS upstream_id, MAX(num_upstreams) AS num_upstreams, toid, MAX("order") AS "order", id, MAX(widthcm) AS widthcm FROM flowpaths GROUP BY merge_group'
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 flowpaths.fgb /raw_hf/fixed.gpkg SELECT
RUN tippecanoe -z6 -Z1 -o flowpaths-low.mbtiles \
    --use-attribute-for-id=id \
    -l flowpaths -X\
    ${ATTRS} \
    ${TYPES} \
    -aI  \
    -pS \
    --drop-by-attribute-as-needed=order \
    flowpaths.fgb -P

FROM numeric_id AS conus_hydrolocations
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 hydrolocations.fgb /raw_hf/conus_nextgen.gpkg hydrolocations

FROM numeric_id AS conus_divides
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 divides.fgb /raw_hf/conus_nextgen.gpkg divides

RUN tippecanoe -z10 -Z4 -o divides.mbtiles \
    --use-attribute-for-id=divide_id \
    -l divides -X \
    ${ATTRS}   \
    ${TYPES} \
    -M 300000 \
    --order-by="divide_id" \
    --coalesce-densest-as-needed \
    -aI  \
    divides.fgb -P

FROM numeric_id AS conus_flowpaths
RUN ogr2ogr -s_srs EPSG:5070 -t_srs CRS:84 flowpaths.fgb /raw_hf/conus_nextgen.gpkg flowpaths

RUN tippecanoe -z10 -Z7 -o flowpaths-high.mbtiles \
    --use-attribute-for-id=id \
    -l flowpaths -X \
    ${ATTRS} \
    ${TYPES} \
    -aI  \
    -pS \
    --drop-by-attribute-as-needed=order \
    --extend-zooms-if-still-dropping \
    flowpaths.fgb -P

# RUN tippecanoe -z10 -Z2 -r1 --cluster-distance=5 -o hydrolocations.mbtiles -l conus_hydrolocations hydrolocations.fgb -P
# RUN tippecanoe -z10 -Z3 -r1 -j '{ "*": [ "any", [ "==", "hl_reference", "gages" ]] }' -o gages.mbtiles -l conus_gages hydrolocations.fgb -P
#hydrolocations.mbtiles gages.mbtiles

FROM base AS join_tiles
WORKDIR /mbtiles/merged
COPY --from=low_zoom /fgb/conus/flowpaths-low.mbtiles .
COPY --from=conus_flowpaths /fgb/conus/flowpaths-high.mbtiles .
COPY --from=conus_divides /fgb/conus/divides.mbtiles .

RUN tile-join -pk -o  flowpaths.mbtiles flowpaths-low.mbtiles flowpaths-high.mbtiles

RUN pmtiles convert divides.mbtiles divides.pmtiles
RUN pmtiles convert flowpaths.mbtiles flowpaths.pmtiles

FROM oven/bun:1 AS server
WORKDIR /usr/src/app
COPY map ./map
# only copying this so build.sh can copy it to a local folder outside of the container
COPY --from=upstream_indexing ./indexing/upstream-idx.csv /indexing/upstream-idx.csv
COPY --from=join_tiles /mbtiles/merged/divides.pmtiles ./tiles/divides.pmtiles
COPY --from=join_tiles /mbtiles/merged/flowpaths.pmtiles ./tiles/flowpaths.pmtiles

USER bun
EXPOSE 3000/tcp
ENTRYPOINT [ "bun", "run", "./map/server.ts" ]
