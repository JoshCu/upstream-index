# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
import sqlite3
from collections import defaultdict
from pathlib import Path


def fix_sn(input) -> int:
    if "e+" not in input:
        return int(input)
    sig = input.split("e+")[0]
    offset = input.split("e+")[1]
    return int(sig) * 10 ** int(offset)


def get_network(hf_path: Path) -> (dict, set):
    network = dict()
    not_headwaters = set()
    with sqlite3.connect(hf_path) as con:
        sql = "select id, toid from flowpaths"
        results = con.execute(sql).fetchall()
        for r in results:
            id = fix_sn(r[0][3:])
            toid = fix_sn(r[1][4:])
            not_headwaters.add(toid)
            network[id] = toid
    headwaters = set(network.keys()) - not_headwaters
    return network, headwaters


def calculate_order(network: dict, inv_network: dict, headwaters: set) -> dict:
    strahler_orders = dict()
    in_degree = {node: len(inv_network[node]) for node in inv_network}

    # Headwaters start at order 1 and are ready to process immediately
    to_visit = list(headwaters)
    for id in headwaters:
        strahler_orders[id] = 1

    while to_visit:
        id = to_visit.pop()
        toid = network.get(id)
        if toid is None:
            continue  # outlet / no downstream node

        # One upstream contribution to toid is now resolved
        in_degree[toid] -= 1
        if in_degree[toid] == 0:
            # All upstream orders are known; apply Strahler rule
            up_orders = [strahler_orders[u] for u in inv_network[toid]]
            max_order = max(up_orders)
            if up_orders.count(max_order) > 1:
                strahler_orders[toid] = max_order + 1
            else:
                strahler_orders[toid] = max_order
            to_visit.append(toid)

    return strahler_orders


if __name__ == "__main__":
    hf = Path("/raw_hf/conus_nextgen.gpkg")
    # hf = Path("~/.ngiab/hydrofabric/v2.2/conus_nextgen.gpkg").expanduser()
    network, headwaters = get_network(hf)
    inv_network = defaultdict(list)
    for id, toid in network.items():
        inv_network[toid].append(id)
    orders = calculate_order(network, inv_network, headwaters)
    print(f"Computed Strahler order for {len(orders)} flowpaths")

    with sqlite3.connect(hf) as con:
        con.executemany(
            'UPDATE flowpaths SET "order" = ? WHERE id = ?',
            [(order_value, f"wb-{id}") for id, order_value in orders.items()],
        )
        con.commit()
