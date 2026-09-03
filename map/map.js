import { updateIncomingStyle, checkPmtiles } from "./map_layers.js"
import { handleHover, handleHoverLeave } from "./tooltip.js";

let map = null;
const HIDDEN_FILTER = ["any"];

const state = {
  catId: null,
  nexId: null,
  selectedId: null,
  selectedNumUpstreams: null,
  outletId: null,
  outletNumUpstreams: null,
};

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
    map.on("mousemove", "divides", handleHover);
    map.on("mouseleave", "divides", handleHoverLeave);
    map.on("click", "divides", onDivideClick);
  });
}

export function clearUpstreamHighlight() {
  state.catId = null;
  state.nexId = null;
  state.selectedId = null;
  state.selectedNumUpstreams = null;
  state.outletId = null;
  state.outletNumUpstreams = null;

  map.setFilter("selected-divides", HIDDEN_FILTER);
  map.setFilter("upstream-divides", HIDDEN_FILTER);
  document.getElementById("input-catid").value = "";
  document.getElementById("selection-info").style.display = "none";
}

export function onDivideClick(e) {
  if (!e.features?.length) return;
  const divide = e.features[0];
  const upstreamId = divide.properties.upstream_id;
  const numUpstreams = divide.properties.num_upstreams;

  // Clicking the already-selected catchment toggles the highlight off.
  if (state.selectedId === upstreamId) {
    clearUpstreamHighlight();
    return;
  }

  state.catId = "cat-" + divide.id;
  state.selectedId = upstreamId;
  state.selectedNumUpstreams = numUpstreams;
  document.getElementById("input-catid").value = state.catId;
  const uf = queryFlowpath(divide.properties.toid);
  if (uf) {
    state.outletId = uf.properties.upstream_id;
    state.nexId = "nex-" + uf.id;
    state.outletNumUpstreams = uf.properties.num_upstreams;
  }
  else {
    state.outletId = upstreamId;
    state.nexId = null;
    state.outletNumUpstreams = numUpstreams;
  }

  updateFilters();
}

function updateFilters() {
  const includeOutlet = document.getElementById("chk-include-outlet").checked;
  const upid = includeOutlet ? state.outletId : state.selectedId;
  const upstreamCount = includeOutlet ? state.outletNumUpstreams : state.selectedNumUpstreams;
  const outlet = includeOutlet ? state.nexId : state.catId;

  map.setFilter("selected-divides", ["==", "upstream_id", state.selectedId]);
  map.setFilter("upstream-divides", [
    "all",
    [">", "upstream_id", upid],
    ["<=", "upstream_id", upid + upstreamCount],
    ["!=", "upstream_id", state.selectedId],
  ]);

  const info = document.getElementById("selection-info");
  info.style.display = "block";
  info.innerHTML = `Outlet: <span class="outlet">${outlet}</span><br>Upstream: <span class="count">${upstreamCount}</span> catchments<br>Upstream ID: <span class="range">${upid}</span><br>ID range: <span class="range">${upid}</span> - <span class="range">${upid + upstreamCount}</span>`;
}

document.getElementById("chk-include-outlet").addEventListener("change", () => {
  if (state.selectedId) updateFilters();
});

document.getElementById("btn-clear").addEventListener("click", clearUpstreamHighlight);

checkPmtiles().then(() => {
  initMap();
});
