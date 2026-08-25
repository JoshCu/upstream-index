let divide_pmtiles = "divides.pmtiles";
let flowpath_pmtiles = "flowpaths.pmtiles";
const backup_url = "https://communityhydrofabric.com/map/only_geometry/upstream_index/";

async function checkResourceExists(url) {
  try {
    const response = await fetch(url, { method: 'HEAD' });
    return response.ok; // True if status is 200-299
  } catch (error) {
    return false; // Network error or resource does not exist
  }
}

export async function checkPmtiles() {
  const [divideOk, flowpathOk] = await Promise.all([
    checkResourceExists(divide_pmtiles),
    checkResourceExists(flowpath_pmtiles),
  ]);
  if (!divideOk) divide_pmtiles = backup_url + divide_pmtiles;
  if (!flowpathOk) flowpath_pmtiles = backup_url + flowpath_pmtiles;
}

// Built lazily (not at module load) so it picks up the resolved URLs from checkPmtiles().
function hydrofabricSources() {
  return {
    "flowpaths": {
      type: "vector",
      url: "pmtiles://" + flowpath_pmtiles,
    },
    "divides": {
      type: "vector",
      url: "pmtiles://" + divide_pmtiles,
    },
  };
}

const hydrofabric_layers = [
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
    }
];
const boostTextHalo = (layer) => ({ ...layer, paint: { ...layer.paint, "text-halo-width": 3, "text-halo-blur": 3 },});

export function updateIncomingStyle(previousStyle, nextStyle) {
  return {
    sources: {
      ...nextStyle.sources,
      ...hydrofabricSources(),
    },
    layers: [
      // base layers, then our layers, then symbol layers (icons stripped, halos boosted)
      ...nextStyle.layers.filter((layer) => layer.type !== "symbol"),
      ...hydrofabric_layers,
      ...nextStyle.layers
        .filter((layer) => layer.type === "symbol" && !layer.paint?.["text-halo-width"] && !layer.layout?.["icon-image"]),
      ...nextStyle.layers
        .filter((layer) => layer.type === "symbol" && layer.paint?.["text-halo-width"])
        .map(boostTextHalo),
    ],
  };
}
