import { updateIncomingStyle, checkPmtiles } from "./map_layers.js"

let map = null;
let catId = null;
let nexId = null;
let selected_id = null;
let selected_num_upstreams = null;
let outlet_id = null;
let outlet_num_upstreams = null;
let lastClickedDivide = null;
const HIDDEN_FILTER = ["any"];
// import { handleHover } from "./tooltip.js";
let start_time = performance.now();
let firstSymbolId = null;

function queryFlowpath(flowpathID) {
  if (!map.loaded()) return;
  const features = map.querySourceFeatures("flowpaths", {
    sourceLayer: ["flowpaths"],
    filter: ["==", ["id"], flowpathID],
  });
  return features[0];
}

function initMap() {
  const protocol = new pmtiles.Protocol({ metadata: true });
  maplibregl.addProtocol("pmtiles", protocol.tile);
  maplibregl.setWorkerCount(4);
  map = new maplibregl.Map({
    container: "map",
    center: [-96, 40],
    zoom: 4,
    validateStyle: false,
  });
  // alt_style = "https://communityhydrofabric.com/map/styles/light-base.json"

  map.setStyle("https://tiles.openfreemap.org/styles/liberty", {transformStyle: updateIncomingStyle});
  map.on("load", () => {
    // map.on("mousemove", "divides", handleHover);
    map.on("click", "divides", onDivideClick);
    map.on("mouseenter", "divides", () => {
      map.getCanvas().style.cursor = "pointer";
    });
    map.on("mouseleave", "divides", () => {
      map.getCanvas().style.cursor = "";
    });
  });
}

export function clearUpstreamHighlight() {
  selected_id = null;
  lastClickedDivide = null;
  map.setFilter("selected-divides", HIDDEN_FILTER);
  map.setFilter("upstream-divides", HIDDEN_FILTER);
}

export function onDivideClick(e) {
  if (!e.features?.length) return;
  const divide = e.features[0];
  const upstreamId = divide.properties.upstream_id;
  const numUpstreams = divide.properties.num_upstreams;

  catId = "cat-" + divide.id;
  document.getElementById("input-catid").value = catId;
  selected_id = divide.properties.upstream_id;
  selected_num_upstreams = divide.properties.num_upstreams;
  const uf = queryFlowpath(divide.properties.toid);
  if (uf) {
    outlet_id = uf.properties.upstream_id;
    nexId = "nex-" + uf.id;
    outlet_num_upstreams = uf.properties.num_upstreams;
  } else {
    outlet_id = null;
    nexId = null;
    outlet_num_upstreams = selected_num_upstreams;
  }

  // Clicking the already-selected catchment toggles the highlight off.
  if (
    lastClickedDivide &&
    lastClickedDivide.upstreamId === upstreamId
  ) {
    clearUpstreamHighlight();
    return;
  }

  lastClickedDivide = { upstreamId, numUpstreams, lngLat: e.lngLat };
  selected_id = upstreamId;

  updateFilters()

  if (!numUpstreams) {
    new maplibregl.Popup()
      .setLngLat(e.lngLat)
      .setHTML("No upstreams")
      .addTo(map);
  }
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
