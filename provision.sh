#!/bin/bash

## receive default VPC ID
VPC_ID=`aws ec2 describe-vpcs --query Vpcs[0].VpcId --output text`

## receive default SubNet ID
SUBNET_1_ID=`aws ec2 describe-subnets --query 'Subnets[0].SubnetId' --output text`
SUBNET_2_ID=`aws ec2 describe-subnets --query 'Subnets[1].SubnetId' --output text`

## create security group for LoadBalancer
GROUP_LB_ID=`aws ec2 create-security-group --group-name SecGroupForLB --description "Security group for LB" --vpc-id $VPC_ID --query GroupId --output text`

## configure the security group for loadbalancer
aws ec2 authorize-security-group-ingress --group-id $GROUP_LB_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 

## create loadbalancer
LB_ARN=`aws elbv2 create-load-balancer --name lb-broda --subnets $SUBNET_1_ID $SUBNET_2_ID --security-groups $GROUP_LB_ID \
    --query LoadBalancers[*].LoadBalancerArn --output text`


## receive ip address of vpc
VPC_NET=`aws ec2 describe-vpcs --query Vpcs[0].CidrBlock --output text`

## security group for Instances
GROUP_INC_ID=`aws ec2 create-security-group --group-name SecGroupForINC --description "Security group for Instances" --vpc-id $VPC_ID --query GroupId --output text`

## configure security group to allow receiving trafic from loadbalancer
aws ec2 authorize-security-group-ingress --group-id $GROUP_INC_ID --protocol tcp --port 80 --cidr $VPC_NET
aws ec2 authorize-security-group-ingress --group-id $GROUP_INC_ID --protocol tcp --port 22 --cidr 0.0.0.0/0


## create a key pair and sent output to .pem file
aws ec2 create-key-pair --key-name KeyBroda --query 'KeyMaterial' --output text > ./KeyBroda.pem

## update permissions
chmod 400 KeyBroda.pem

sleep 30

## create tow similar instances
INSTANCE_1_ID=`aws ec2 run-instances --image-id ami-0b5eea76982371e91 --subnet-id $SUBNET_1_ID --count 1 --instance-type t2.micro --key-name KeyBroda \
    --security-group-ids $GROUP_INC_ID --user-data file://user_script.sh --query Instances[0].InstanceId --output text`

INSTANCE_2_ID=`aws ec2 run-instances --image-id ami-0b5eea76982371e91 --subnet-id $SUBNET_2_ID --count 1 \--instance-type t2.micro --key-name KeyBroda \
    --security-group-ids $GROUP_INC_ID --user-data file://user_script.sh --query Instances[0].InstanceId --output text`

## create a target-group
TG_ARN=`aws elbv2 create-target-group --name TargetGroup --protocol HTTP --port 80 --vpc-id $VPC_ID --query 'TargetGroups[*].TargetGroupArn' --output text`

## 30 sec pause
sleep 30

## register targets
aws elbv2 register-targets --target-group-arn $TG_ARN --targets Id=$INSTANCE_1_ID Id=$INSTANCE_2_ID

## create listener acording to some tips
aws elbv2 create-listener --load-balancer-arn $LB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN 

## create asg
aws autoscaling create-auto-scaling-group --auto-scaling-group-name AutoScalingGroup --instance-id $INSTANCE_1_ID --min-size 2 --max-size 2 --target-group-arns $TG_ARN 

## update asg health settings
aws autoscaling update-auto-scaling-group --auto-scaling-group-name AutoScalingGroup --health-check-type ELB --health-check-grace-period 15 

## receive loadbalancer's dns address
LB_DNS=`aws elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName' --output text`

## check autoscalinggroup
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-name AutoScalingGroup

## print loadbalancer dns address
echo $LB_DNS

sleep 15
