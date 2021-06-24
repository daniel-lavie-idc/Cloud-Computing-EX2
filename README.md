# Cloud-Computing-EX2
Caching in the cloud

app.py - flask server which exposes the rest api + healthcheck endpoint for the ELB.

fixup.py - script which detect when a new node is added or an existing node is removed, and send updates to the relevant nodes.

common.py - all common functions for both scripts.

__init__.py - to allow the scripts to import each other as python modules.

setup.sh - deploy the environment in AWS.