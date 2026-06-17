#!/bin/bash
docker build -t map_server .  && \
docker run -d --name pmtiles_container map_server && \
docker cp pmtiles_container:/usr/src/app/tiles/divides.pmtiles ./tiles/divides.pmtiles && \
docker cp pmtiles_container:/usr/src/app/tiles/flowpaths.pmtiles ./tiles/flowpaths.pmtiles && \
docker cp pmtiles_container:/indexing/upstream-idx.csv ./indexing/upstream-idx.csv && \
docker kill pmtiles_container && \
docker rm pmtiles_container
