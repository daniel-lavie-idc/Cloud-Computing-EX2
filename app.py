import redis
from flask import Flask, request
from .common import get_from_another_node, get_nodes_relevant_to_key, get_my_instance_id, put_in_another_node


app = Flask(__name__)

r = redis.Redis(host='localhost', port=6379, db=0)

MY_INSTANCE_ID = get_my_instance_id()

@app.route('/put')
def put():
    key = request.args.get("str_key")
    value = request.args.get("data")
    expiration_date = request.args.get("expiration_date")
    print("Got key:{}, value:{}, expiration_date:{}".format(key, value, expiration_date))
    node_id, alt_node_id = get_nodes_relevant_to_key(key)
    print("relevant node_id: {}, alt_node_id: {}".format(node_id, alt_node_id))
    if MY_INSTANCE_ID in (node_id, alt_node_id):
        status = r.set(key, value)
        if status:
            return "Value was set", 200
        return "Something went wrong while trying to put the value", 404
    status_code = put_in_another_node(node_id, key, value, expiration_date)
    status_code_alt = put_in_another_node(alt_node_id, key, value, expiration_date)
    if 200 not in (status_code, status_code_alt):
        return "Something went wrong while trying to put the value", 404
    return "Value was set", 200

@app.route('/get')
def get():
    key = request.args.get("str_key")
    node_id, alt_node_id = get_nodes_relevant_to_key(key)
    print("relevant node_id: {}, alt_node_id: {}".format(node_id, alt_node_id))
    if MY_INSTANCE_ID in (node_id, alt_node_id):
        value = r.get(key)
        if value is not None:
            return r.get(key), 200
        else:
            return "Key does not exist in the system, you have to put a value to it first", 404
    value = get_from_another_node(node_id, key)
    if value != None:
        return value, 200
    value = get_from_another_node(alt_node_id, key)
    if value != None:
        return value, 200
    return "Key does not exist in the system, you have to put a value to it first", 404

@app.route('/healthcheck')
def healthcheck():
    return "", 200
