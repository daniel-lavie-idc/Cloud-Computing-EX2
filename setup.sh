#!/bin/bash

set -e

RUN_ID=$(date +'%N')
REGION=$(aws ec2 describe-availability-zones | jq -r .AvailabilityZones[0].RegionName)
LOAD_BALANCER_NAME="cloud-computing-ex2"
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true | jq -r '.Vpcs[0].VpcId')
SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=availabilityZone,Values="$REGION"a,"$REGION"b Name=vpc-id,Values=$DEFAULT_VPC_ID)
SUBNET_ID_1=$(echo $SUBNET_IDS | jq -r '.Subnets[0].SubnetId')
SUBNET_ID_2=$(echo $SUBNET_IDS | jq -r '.Subnets[1].SubnetId')

echo "Region name: $REGION"
echo "Default vpc id is: $DEFAULT_VPC_ID"
echo "The subnets id that we'll work with: $SUBNET_ID_1, $SUBNET_ID_2"

ELB_SEC_GRP="my-sg-elb-`date +'%N'`"

echo "setup security group (firewall) $ELB_SEC_GRP"
ELB_SECURITY_GROUP_ID=$(aws ec2 create-security-group   \
    --group-name $ELB_SEC_GRP       \
    --description "ELB exercise" | jq -r ".GroupId")
echo "ELB security group ID is: $ELB_SECURITY_GROUP_ID"

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"
aws ec2 authorize-security-group-ingress --group-id $ELB_SECURITY_GROUP_ID --protocol tcp --port 80 --cidr $MY_IP/32

echo "Creating an application ELB"
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer --name $LOAD_BALANCER_NAME --subnets $SUBNET_ID_1 $SUBNET_ID_2 --security-groups $ELB_SECURITY_GROUP_ID | \
                     jq -r '.LoadBalancers[0].LoadBalancerArn')
echo "Load balancer arn is: $LOAD_BALANCER_ARN"

echo "Creating a target group for the ELB"
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name ex2-targets \
    --protocol HTTP \
    --port 5000 \
    --target-type instance \
    --health-check-protocol HTTP \
    --health-check-port 5000 \
    --health-check-path /healthcheck \
    --health-check-interval-seconds 5 \
    --health-check-timeout-seconds 2 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 2 \
    --vpc-id $DEFAULT_VPC_ID | jq -r .TargetGroups[0].TargetGroupArn)

echo "Creating a listener in the ELB"
CREATE_LISTENER_STATUS=$(aws elbv2 create-listener \
    --load-balancer-arn $LOAD_BALANCER_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN)

KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"
SSH_PATH="$HOME/.ssh"
KEY_PATH="$SSH_PATH/$KEY_PEM" # WSL Hack


echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PATH

# secure the key pair
chmod 400 $KEY_PATH

echo "setup security group for the instance (with ssh)"
INSTANCE_SEC_GRP="my-sg-instance-`date +'%N'`"
INSTANCE_SECURITY_GROUP_ID=$(aws ec2 create-security-group   \
    --group-name $INSTANCE_SEC_GRP       \
    --description "ELB exercise" | jq -r ".GroupId")
echo "Instance security group ID is: $INSTANCE_SECURITY_GROUP_ID"

aws ec2 authorize-security-group-ingress --group-id $INSTANCE_SECURITY_GROUP_ID --protocol tcp --port 22 --cidr $MY_IP/32
# Allow inner conneciton between ELB and instance, and between the instances
aws ec2 authorize-security-group-ingress --group-id $INSTANCE_SECURITY_GROUP_ID --protocol tcp --port 5000 --source-group $ELB_SECURITY_GROUP_ID
aws ec2 authorize-security-group-ingress --group-id $INSTANCE_SECURITY_GROUP_ID --protocol tcp --port 5000 --source-group $INSTANCE_SECURITY_GROUP_ID

AWS_ROLE="ec2-role-$RUN_ID"

echo "Creating role $AWS_ROLE..."
aws iam create-role --role-name $AWS_ROLE --assume-role-policy-document file://trust-policy.json

echo "Allowing all access for simplicity..."
aws iam attach-role-policy --role-name $AWS_ROLE  \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

INSTANCE_PROFILE_NAME="$AWS_ROLE-Instance-Profile"
echo "Instance profile name is: $INSTANCE_PROFILE_NAME"
aws iam create-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME
aws iam add-role-to-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --role-name $AWS_ROLE

aws iam wait role-exists --role-name $AWS_ROLE
echo "Workaround consistency rules in AWS roles after creation... (sleep 10)"
sleep 10

UBUNTU_20_04_AMI="ami-042e8287309f5df03"
NUM_OF_INSTANCES=3

echo "Creating $NUM_OF_INSTANCES Ubuntu 20.04 instances..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --iam-instance-profile Name=$INSTANCE_PROFILE_NAME \
    --instance-type t3.micro            \
    --key-name $KEY_NAME                \
    --subnet-id $SUBNET_ID_1                       \
    --security-group-ids $INSTANCE_SECURITY_GROUP_ID \
    --count $NUM_OF_INSTANCES)


for i in $(seq 0 $(expr $NUM_OF_INSTANCES - 1))
do
    INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r .Instances[$i].InstanceId)

    echo "Waiting for instance creation..."
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID

    PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress')

    echo "Registering target instance in the ELB target group"
    aws elbv2 register-targets \
        --target-group-arn $TARGET_GROUP_ARN \
        --targets Id=$INSTANCE_ID

    echo "deploying code to production"
    sudo scp -i $KEY_PATH -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" app.py __init__.py fixup.py common.py ubuntu@$PUBLIC_IP:/home/ubuntu/

    echo "setup production environment"
    # Sorry for the AWS_DEFAULT_REGION, could not found a more elegant solution
    sudo ssh -i $KEY_PATH -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP <<EOF
        sudo apt-get update
        sudo apt-get install python3-pip -y
        sudo apt-get install python3-flask -y
        sudo apt-get install redis-server -y
        sudo service redis-server start
        pip3 install redis
        pip3 install boto3
        pip3 install jump-consistent-hash
        pip3 install ec2_metadata
        pip3 install xxhash
        echo "200" > healthcheck
        export AWS_DEFAULT_REGION=us-east-1
        # run app
        nohup flask run --host 0.0.0.0 &>/dev/null &
        python3 fixup.py &>/dev/null &
        exit
EOF
    
done