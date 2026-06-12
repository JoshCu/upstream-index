# upstream-index

Uses the [Nested Set Model](https://en.wikipedia.org/wiki/Nested_set_model) to assign sequential integer IDs to flowpaths, enabling **O(1) upstream range queries** without any graph traversal or network connectivity data at query time.

The algorithm does a depth-first traversal of the network (preferring the deepest branch at each confluence), assigning each flowpath a unique integer that increases as you move downstream. Because upstream catchments are always assigned contiguous IDs, finding everything upstream of a given flowpath reduces to a single integer range filter.

## Use cases

- Fast highlighting of upstream flowpaths in map interfaces — no traversal, no server-side queries, just a range filter on pre-embedded tile properties.
- Guaranteeing related data splits into *at most* one more chunk than the theoretical minimum when partitioning the network.

## A note on ID stability

These IDs are **not stable**. The same data run twice may produce different assignments, and any change to the underlying network geometry requires a full rebuild. These indices are intended as an accompaniment to the canonical flowpath IDs, not a replacement. Since map tiles already need regenerating when geometry changes, reassigning IDs on rebuild is not a problem in practice.

## How the range filter works

Each flowpath gets two properties embedded in the vector tiles:

| Property | Description |
|---|---|
| `upstream_id` | Sequential integer assigned by the nested set traversal |
| `num_upstreams` | Total count of upstream flowpaths |

To highlight everything upstream of a clicked catchment:

```javascript
map.on("click", "divides", (e) => {
  const clicked = e.features[0];
  const selected_id = clicked.properties.upstream_id;
  const upstream_count = clicked.properties.num_upstreams;

  // highlight the clicked catchment
  map.setFilter("selected-divides", ["==", "upstream_id", selected_id]);

  // highlight all upstream catchments — O(1) range filter, no traversal
  map.setFilter("upstream-divides", [
    "all",
    [">",  "upstream_id", selected_id],
    ["<=", "upstream_id", selected_id + upstream_count],
    ["!=", "upstream_id", selected_id],
  ]);
});
```

## How IDs are assigned

Starting from each outlet, the algorithm walks the network upstream using a depth-first traversal. At every confluence it always follows the longest upstream branch first (measured as the longest chain of flowpaths back to a headwater). Each flowpath is assigned the next available integer as it is first visited.

Because the longest branch is always fully explored before any shorter tributary, every upstream flowpath ends up with an ID in an unbroken range immediately above the outlet's ID. That's what makes the range filter possible.

A small example — flow goes left-to-right, letters are flowpath names, numbers in parentheses are the assigned IDs:

```
headwaters                              outlet
F(3) ───── D(2) ───┐
        E(4) ──────┼── B(1) ── A(0)
        C(5) ──────┘
```

Traversal order starting at outlet `A`:
```
visit A → id 0   (upstreams: B)
visit B → id 1   (upstreams: D, E, C — pick D, longest branch since D has F upstream)
visit D → id 2   (upstreams: F)
visit F → id 3   (headwater, backtrack to D, then B)
visit E → id 4   (headwater, backtrack to B)
visit C → id 5   (headwater, backtrack to B, then A — done)
```

Now `A` has `upstream_id=0, num_upstreams=5`. The filter `upstream_id > 0 AND upstream_id <= 5` returns exactly `{B, D, F, E, C}` — no traversal required.

```python
# assign IDs with a depth-first traversal, longest branch first
id_counter = 0

def visit(node):
    global id_counter
    upstream_id[node] = id_counter
    id_counter += 1

    # sort upstream neighbors by depth descending (longest branch first)
    for upstream in sorted(neighbors[node], key=lambda n: depth[n], reverse=True):
        visit(upstream)

for outlet in outlets:
    visit(outlet)
```

## Data

The build downloads the [CONUS NextGen hydrofabric](https://communityhydrofabric.com/hydrofabrics/community/conus_nextgen.tar.gz) (~large), which contains flowpaths and drainage divides for the contiguous United States. The GeoPackage is in EPSG:5070 (Albers Equal Area) and is reprojected to WGS84 during tile generation.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) — the entire build runs inside a multi-stage Docker image

## Building

Builds the vector tiles and upstream index CSV, then copies them out of the container:

```bash
./build.sh
```

This produces:
- `tiles/conus.pmtiles` — PMTiles archive with upstream index properties embedded in each feature
- `indexing/upstream-idx.csv` — raw CSV mapping `id → upstream_id, num_upstreams`

The build has several stages:
1. Downloads the CONUS NextGen GeoPackage
2. Computes upstream indices (`indexing/main.py`)
3. Converts geometries to FlatGeobuf and builds vector tiles with [Tippecanoe](https://github.com/felt/tippecanoe), filtered by Strahler stream order per zoom level
4. Joins the index CSV into the tiles with `tile-join`
5. Converts MBTiles → PMTiles with [go-pmtiles](https://github.com/protomaps/go-pmtiles)

## Running the map

```bash
./run.sh
```

Starts a [Bun](https://bun.sh) server at `http://localhost:3000` serving a [MapLibre GL](https://maplibre.org) map. Click any catchment to highlight it (pink) and all of its upstream catchments (orange). Use the "Include outlet" checkbox to extend the selection one step downstream.
