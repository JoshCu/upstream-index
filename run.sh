#!/bin/bash
# if linux
if [ "$(uname)" == "Linux" ]; then
    xdg-open http://localhost:3000
fi
# if macos
if [ "$(uname)" == "Darwin" ]; then
    open http://localhost:3000
fi
# if windows (good luck)
if [ "$(uname)" == "MINGW64_NT-10.0" ]; then
    start http://localhost:3000
fi
docker rm upstream_map;
docker run -p 3000:3000 --name upstream_map -v $(pwd)/map:/usr/src/app/map map_server;
# ctrl-c doesn't always stop the container so we use docker kill
docker kill upstream_map;
docker rm upstream_map;
