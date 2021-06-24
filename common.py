import boto3
import jump
import xxhash
import requests
from ec2_metadata import ec2_metadata

NUM_OF_V_NODES = 1024

def get_nodes_relevant_to_key(key):
    live_nodes = get_live_nodes_list()
    key_virtual_node_id = jump.hash(xxhash.xxh64_intdigest(key), NUM_OF_V_NODES)
    node_number = key_virtual_node_id % len(live_nodes)
    alt_node_number = (node_number + 1) % len(live_nodes)
    return live_nodes[node_number], live_nodes[alt_node_number]

def get_my_node_number():
    pass

def get_live_nodes_list():
    healthy, _ = get_targets_status()
    if len(healthy) == 0:
        raise RuntimeError("No healthy nodes are alive :(")
    healthy.sort()
    return healthy

def get_targets_status():
    elb = boto3.client('elbv2')
    target_group = elb.describe_target_groups(
        Names=["ex2-targets"],
    )
    target_group_arn = target_group["TargetGroups"][0]["TargetGroupArn"]
    health = elb.describe_target_health(TargetGroupArn=target_group_arn)
    healthy=[]
    sick={}
    for target in health["TargetHealthDescriptions"]:
        if target["TargetHealth"]["State"] == "unhealthy":
            sick[target["Target"]["Id"]] = target["TargetHealth"]["Description"]
        else:
            healthy.append(target["Target"]["Id"])
    return healthy, sick

def get_my_instance_id():
    return ec2_metadata.instance_id

def get_from_another_node(node_id, key):
    node_internal_ip = get_node_internal_ip(node_id)
    response = requests.get("http://{0}:5000/get?str_key={1}".format(node_internal_ip, key))
    if response.status_code == 200:
        return response.text
    return None

def put_in_another_node(node_instance_id, key, value, expiration_date):
    node_internal_ip = get_node_internal_ip(node_instance_id)
    response = requests.get("http://{0}:5000/put?str_key={1}&data={2}&expiration_date={3}".format(node_internal_ip, key, value, expiration_date))
    return response.status_code

def get_node_internal_ip(node_instance_id):
    instance = boto3.resource('ec2').Instance(node_instance_id)
    return instance.network_interfaces[0].private_ip_address