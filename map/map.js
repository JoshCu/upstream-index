let map = null;
let catId = null;
let nexId = null;
let selected_id = null;
let selected_num_upstreams = null;
let outlet_id = null;
let outlet_num_upstreams = null;
var divide_pmtiles = "divides.pmtiles";
var flowpath_pmtiles = "flowpaths.pmtiles";
let backup_url = "https://communityhydrofabric.s3.us-east-1.amazonaws.com/map/only_geometry/upstream_index/";
// import { handleHover } from "./tooltip.js";

function queryFlowpath(flowpathID) {
  if (!map.loaded()) return;
  const features = map.querySourceFeatures("flowpaths", {
    sourceLayer: ["flowpaths"],
    filter: ["==", ["id"], flowpathID],
  });
  return features[0];
}

async function checkPmtiles() {
  divide_pmtiles = await checkResourceExists(divide_pmtiles) ? divide_pmtiles : backup_url + divide_pmtiles;
  flowpath_pmtiles = await checkResourceExists(flowpath_pmtiles) ? flowpath_pmtiles : backup_url + flowpath_pmtiles;
}

async function checkResourceExists(url) {
  try {
    const response = await fetch(url, { method: 'HEAD' });
    return response.ok; // True if status is 200-299
  } catch (error) {
    return false; // Network error or resource does not exist
  }
}

function initMap() {
  const protocol = new pmtiles.Protocol({ metadata: true });
  maplibregl.addProtocol("pmtiles", protocol.tile);
  maplibregl.setWorkerCount(4);
  map = new maplibregl.Map({
    container: "map",
    style: "https://tiles.openfreemap.org/styles/liberty",
    center: [-96, 40],
    zoom: 4,
  });
  map.once("styledata", () => {
    if (map.getSource("flowpaths")) return;
    const layers = map.getStyle().layers;
    let firstSymbolId;
    for (let i = 0; i < layers.length; i++) {
      if (layers[i].type === "symbol") {
        firstSymbolId = layers[i].id;
        break;
      }
    }
    map.addSource("divides", {
      type: "vector",
      url: "pmtiles://" + divide_pmtiles,
    });
    map.addSource("flowpaths", {
      type: "vector",
      url: "pmtiles://" + flowpath_pmtiles,
    });
    map.addLayer(
      {
        id: "divides",
        type: "fill",
        source: "divides",
        "source-layer": "divides",
        paint: {
          "fill-color": "rgba(0, 0, 0, 0)",
          "fill-outline-color": [
            "interpolate",
            ["linear"],
            ["zoom"],
            6,
            "rgba(1, 1, 1, 0)",
            7,
            "rgba(1, 1, 1, 0.5)",
          ],
        },
      },
      firstSymbolId,
    );
    map.addLayer(
      {
        id: "selected-divides",
        type: "fill",
        source: "divides",
        "source-layer": "divides",
        paint: {
          "fill-color": "rgba(238, 51, 119, 0.316)",
          "fill-outline-color": "rgba(238, 51, 119, 0.7)",
        },
        filter: ["in", "divide_id", ""],
      },
      firstSymbolId,
    );
    map.addLayer(
      {
        id: "upstream-divides",
        type: "fill",
        source: "divides",
        "source-layer": "divides",
        paint: {
          "fill-color": "rgba(238, 119, 51, 0.278)",
          "fill-outline-color": "rgba(238, 119, 51, 0.7)",
        },
        filter: ["in", "divide_id", ""],
      },
      firstSymbolId,
    );
    map.addLayer(
      {
        id: "flowpaths",
        type: "line",
        source: "flowpaths",
        "source-layer": "flowpaths",
        layout: {
          "line-cap": "round",
        },
        paint: {
          "line-width": [
            "interpolate",
            ["exponential", 1.6],
            ["get", "order"],
            1,
            1,
            8,
            6,
          ],
          "line-color": [
            "interpolate",
            ["linear"],
            ["zoom"],
            1.3,
            "rgba(0, 119, 187, 0)",
            5,
            "rgba(0, 119, 187, 1)",
          ],
        },
      },
      firstSymbolId,
    );
    map.on("load", () => {
      // map.on("mousemove", "divides", handleHover);
      map.on("click", "divides", (e) => {
        if (!map.loaded()) return;
        if (e.features && e.features.length > 0) {
          catId = "cat-" + e.features[0].id;
          document.getElementById("input-catid").value = catId;
          const f = e.features[0];
          selected_id = f.properties.upstream_id;
          selected_num_upstreams = f.properties.num_upstreams;
          const uf = queryFlowpath(f.properties.toid);
          if (!uf) {
            window.alert("unable to find outlet");
            return;
          }
          outlet_id = uf.properties.upstream_id;
          nexId = "nex-" + uf.id;
          outlet_num_upstreams = uf.properties.num_upstreams;
          updateFilters();
        }
      });
      map.on("mouseenter", "divides", () => {
        map.getCanvas().style.cursor = "pointer";
      });
      map.on("mouseleave", "divides", () => {
        map.getCanvas().style.cursor = "";
      });
    });
  });
}

function updateFilters() {
  const includeOutlet = document.getElementById("chk-include-outlet").checked;
  let upid, upstream_count, outlet;
  if (includeOutlet) {
    outlet = nexId;
    upid = outlet_id;
    upstream_count = outlet_num_upstreams;
  } else {
    outlet = catId;
    upid = selected_id;
    upstream_count = selected_num_upstreams;
  }

  map.setFilter("selected-divides", ["==", "upstream_id", selected_id]);
  map.setFilter("upstream-divides", [
    "all",
    [">", "upstream_id", upid],
    ["<=", "upstream_id", upid + upstream_count],
    ["!=", "upstream_id", selected_id],
  ]);

  const info = document.getElementById("selection-info");
  info.style.display = "block";
  info.innerHTML = `Outlet: <span class="outlet">${outlet}</span><br>Upstream: <span class="count">${upstream_count}</span> catchments`;
}

document.getElementById("chk-include-outlet").addEventListener("change", () => {
  if (selected_id) updateFilters();
});

document.getElementById("btn-clear").addEventListener("click", () => {
  map.setFilter("selected-divides", ["in", "id", ""]);
  map.setFilter("upstream-divides", ["in", "id", ""]);
  document.getElementById("input-catid").value = "";
  document.getElementById("selection-info").style.display = "none";
});

checkPmtiles().then(() => {
  initMap();
});
