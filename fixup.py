import time
import redis
from common import get_live_nodes_list, get_my_instance_id, get_nodes_relevant_to_key, put_in_another_node

MY_INSTANCE_ID = get_my_instance_id()
ITERATION_SLEEP_TIME_SECONDS = 10

LIVE_NODES = []

r = redis.StrictRedis(host='localhost', port=6379, db=0)

def main():
    while True:
        print("Fixup script started")
        time.sleep(ITERATION_SLEEP_TIME_SECONDS)
        do_work()

def do_work():
    global LIVE_NODES
    print("Doing the work")
    # Note: Assuming a single node is either added or removed per update
    live_nodes = get_live_nodes_list()
    if len(live_nodes) == 0:
        # Nothing to do
        return
    if len(LIVE_NODES) == len(live_nodes):
        # Nothing to do
        return

    forward_data_to_new_node()
    LIVE_NODES = live_nodes

def forward_data_to_new_node():
    for key in r.scan_iter():
        value = r.get(key)
        node_id, alt_node_id = get_nodes_relevant_to_key(key)
        if MY_INSTANCE_ID != node_id:
            print("Forwarding {}:{} to node {}".format(key, value, node_id))
            put_in_another_node(node_id, key, value, 0)
        if MY_INSTANCE_ID != alt_node_id:
            print("Forwarding {}:{} to node {}".format(key, value, alt_node_id))
            put_in_another_node(alt_node_id, key, value, 0)

if __name__ == "__main__":
    main()