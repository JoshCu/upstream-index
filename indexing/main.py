# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

import sqlite3
from collections import defaultdict, deque
from pathlib import Path


def fix_sn(input) -> int:
    if "e+" not in input:
        return int(input)
    sig = input.split("e+")[0]
    offset = input.split("e+")[1]
    return int(sig) * 10 ** int(offset)


def get_network(hf_path: Path) -> (dict, set, dict):
    network = dict()
    not_headwaters = set()
    inv_network = defaultdict(set)
    with sqlite3.connect(hf_path) as con:
        sql = "select id, toid from flowpaths WHERE toid NOT LIKE 'tnx-%'"
        results = con.execute(sql).fetchall()
        for r in results:
            id = fix_sn(r[0][3:])
            toid = fix_sn(r[1][4:])
            not_headwaters.add(toid)
            network[id] = toid
            inv_network[toid].add(id)
    return network, not_headwaters, inv_network


def get_depth(network, inv_network) -> dict:
    indegree = {id: len(inv_network[id]) for id in network}
    depth = defaultdict(int)
    queue = deque(id for id in network if indegree[id] == 0)
    while queue:
        id = queue.popleft()
        toid = network.get(id)
        if toid is None or toid not in indegree:
            continue
        if depth[id] + 1 > depth[toid]:
            depth[toid] = depth[id] + 1
        indegree[toid] -= 1
        if indegree[toid] == 0:
            queue.append(toid)
    return depth


def get_max(ids, depths) -> int:
    max = 0
    best_id = -1
    for id in ids:
        if depths[id] >= max:
            max = depths[id]
            best_id = id
    return best_id


def get_upstream_indices(inv_network, depths, outlets, network) -> (dict, list):
    upstream_ids = dict()
    seen = set()
    id_count = 0
    for outlet in outlets:
        id = outlet
        while True:
            if id not in seen:
                upstream_ids[id] = id_count
                id_count += 1
            seen.add(id)

            upstreams = inv_network[id]
            upstreams -= seen
            if len(upstreams) == 0:
                if id == outlet:
                    break
                id = network[id]
                continue
            id = get_max(upstreams, depths)
    return upstream_ids


def get_num_upstreams(network) -> dict:
    indeg = defaultdict(int)
    for toid in network.values():
        if toid is not None:
            indeg[toid] += 1

    num = defaultdict(int)
    queue = deque(id for id in network if indeg[id] == 0)
    while queue:
        id = queue.popleft()
        toid = network.get(id)
        if toid is None:
            continue
        num[toid] += num[id] + 1  # everything upstream of id, plus id itself
        indeg[toid] -= 1
        if indeg[toid] == 0 and toid in network:
            queue.append(toid)
    return num


if __name__ == "__main__":
    hf = Path("/raw_hf/conus_nextgen.gpkg").expanduser()
    (network, not_headwaters, inv_network) = get_network(hf)
    outlets = set(network.values()) - set(network.keys())
    depths = get_depth(network, inv_network)
    indices = get_upstream_indices(inv_network, depths, outlets, network)
    num_upstreams = get_num_upstreams(network)
    ups = Path("num_upstreams.json")
    idx = Path("upstream-indices.json")
    # idx.write_text(json.dumps(indices))
    # ups.write_text(json.dumps(num_upstreams))
    csv_output = Path("upstream-idx.csv")
    with csv_output.open("w") as f:
        f.write("id, upstream_id, num_upstreams\n")
        for id, upstream_id in indices.items():
            f.write(f"{int(id)}, {int(upstream_id)}, {num_upstreams[id]}\n")
