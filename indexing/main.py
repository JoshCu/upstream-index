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


def get_network(hf_path: Path) -> (dict, set, dict, dict):
    network = dict()
    not_headwaters = set()
    inv_network = defaultdict(set)
    order = dict()
    with sqlite3.connect(hf_path) as con:
        # pull order so we can break merge groups where Strahler order changes
        sql = "select id, toid, \"order\" from flowpaths WHERE toid NOT LIKE 'tnx-%'"
        results = con.execute(sql).fetchall()
        for r in results:
            id = fix_sn(r[0][3:])
            toid = fix_sn(r[1][4:])
            not_headwaters.add(toid)
            network[id] = toid
            inv_network[toid].add(id)
            order[id] = r[2]
    return network, not_headwaters, inv_network, order


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


def get_upstream_indices(inv_network, depths, outlets, network) -> dict:
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


def get_merge_groups(upstream_ids, network, order) -> dict:
    """Group flowpaths into pre-mergeable runs.
    Walk segments in upstream_id order. A run continues only while the next
    segment is the SAME order AND topologically attached to the current run
    """
    # iterate in upstream_id order (the depth-first channel walk)
    ordered = sorted(upstream_ids, key=lambda i: upstream_ids[i])

    merge_group = dict()
    group_count = 0
    prev_id = None
    prev_order = None

    for id in ordered:
        connected = prev_id is not None and network.get(id) == prev_id
        same_order = prev_id is not None and order.get(id) == prev_order

        if not (connected and same_order):
            group_count += 1  # start a fresh group

        merge_group[id] = group_count
        prev_id = id
        prev_order = order.get(id)

    return merge_group


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
    (network, not_headwaters, inv_network, order) = get_network(hf)
    outlets = set(network.values()) - set(network.keys())
    depths = get_depth(network, inv_network)
    indices = get_upstream_indices(inv_network, depths, outlets, network)
    merge_groups = get_merge_groups(indices, network, order)
    num_upstreams = get_num_upstreams(network)

    csv_output = Path("upstream-idx.csv")
    with csv_output.open("w") as f:
        f.write("id,upstream_id,num_upstreams,merge_group\n")
        for id, upstream_id in indices.items():
            f.write(
                f"{int(id)}, {int(upstream_id)}, {num_upstreams[id]}, {int(merge_groups[id])}\n"
            )
