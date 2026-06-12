#!/bin/bash
docker build -t pmtiles --build-context local_copy=~/.ngiab/hydrofabric/v2.2/ .  && \
docker run -d --name pmtiles_container pmtiles sleep infinity && \
docker cp pmtiles_container:/mbtiles/merged/conus.pmtiles . && \
docker kill pmtiles_container && \
docker rm pmtiles_container # && \
