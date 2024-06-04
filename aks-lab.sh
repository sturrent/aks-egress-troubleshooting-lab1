#!/bin/bash

# script name: aks-lab.sh
# Version v0.0.1 20240503
# Set of tools to deploy AKS troubleshooting labs

# "-l|--lab" Lab scenario to deploy
# "-r|--region" region to deploy the resources
# "-s|--sku" nodes SKU
# "-u|--user" User alias to add on the lab name
# "-v|--validate" validate resolution
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=$(getopt -o g:n:l:r:s:u:h --long resource-group:,name:,lab:,region:,sku:,user:,help,version -n 'aks-flp-networking.sh' -- "$@")
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
USER_ALIAS=""
LOCATION="eastus2"
SKU="Standard_D2s_v5"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;
        -s|--sku) case "$2" in
            "") shift 2;;
            *) SKU="$2"; shift 2;;
            esac;;
        -u|--user) case "$2" in
            "") shift 2;;
            *) USER_ALIAS="$2"; shift 2;;
            esac;;    
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo "$0" | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.0.1 20240603"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\n--> Warning: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login --use-device-code -o table
    fi
    if $(az group list 2>&1 | grep -q 'token has expired')
    then
        echo -e "\n--> Warning: Your token has expired. Trying to login to refresh token\n"
        az login --use-device-code -o table
    fi
}

# validate SKU availability
function check_sku_availability () {
    SKU="$1"
    
    echo -e "\n--> Checking if SKU \"$SKU\" is available in your subscription at region \"$LOCATION\" ...\n"
    while true; do for s in / - \\ \|; do printf "\r$s"; sleep 1; done; done &  # running spiner
    SKU_LIST="$(az vm list-skus -l "$LOCATION" -o table | grep -v -E '(disk|hostGroups/hosts|snapshots|availabilitySets|NotAvailableForSubscription|Name|^--)')"
    kill $!; trap 'kill $!' SIGTERM # kill spiner
    
    if $(echo "$SKU_LIST" | grep -q -w "$SKU")
    then
        echo -e "\n--> SKU \"${SKU}\" is available in your subscription at region \"${LOCATION}\"\n"
    else
        echo -e "\n--> ERROR: The SKU \"${SKU}\" is not available in your subscription at region \"${LOCATION}\".\n"
        echo -e "The SKUs currently available in your subscription for region \"${LOCATION}\" are:\n"
        echo "$SKU_LIST" | awk '{print $3}' | pr -7 -s" | " -T
        echo -e "\n\n--> Please try with one of the above SKUs (if any) or try with a different region.\n"
        exit 4
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    RG_EXIST="$(az group show -g "$RESOURCE_GROUP" &>/dev/null; echo $?)"
    if [ "$RG_EXIST" -ne 0 ]
    then
        echo -e "\n--> Creating resource group ${RESOURCE_GROUP}...\n"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o table &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" &>/dev/null; echo $?)
    if [ "$CLUSTER_EXIST" -eq 0 ]
    then
        echo -e "\n--> Cluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 5
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    CLUSTER_EXIST=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" &>/dev/null; echo $?)
    if [ "$CLUSTER_EXIST" -ne 0 ]
    then
        echo -e "\n--> ERROR: Failed to create cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP ...\n"
        exit 5
    fi
}

# Usage text
function print_usage_text () {
    NAME_EXEC="aks-labs"
    echo -e "$NAME_EXEC usage: $NAME_EXEC -l <LAB#> -u <USER_ALIAS> [-r|--region] [-s|--sku] [-h|--help] [--version]"
    echo -e "\nHere is the list of current labs available:
*************************************************************************************
*\t 1. Pod with intermittent issues to communicate with Postgres DB
*\t 2. 
*************************************************************************************\n"
echo -e '"-l|--lab" Lab scenario to deploy (3 possible options)
"-u|--user" User alias to add on the lab name
"-r|--region" region to create the resources
"-s|--sku" nodes SKU
"--version" print version of the tool
"-h|--help" help info\n'
}

# Lab scenario 1
function lab_scenario_1 () {
    RMD_SEED="$(cat /dev/urandom | tr -dc '0-9' | fold -w 2 | head -n 1)"
    PG_NAME="postgresdb${RMD_SEED}-${USER_ALIAS}.private.postgres.database.azure.com"
    DB_CLUSTER_NAME=postgresdb1-workbench
    RESOURCE_GROUP_DB=workgroup-db-rg
    VNET_NAME_DB=vnet-workgroup-db
    SUBNET_NAME_DB=subnet-workgroup-db

    echo -e "\n--> Deploying resources for lab${LAB_SCENARIO}...\n"

    check_sku_availability "$SKU"

    # DB RG
    az group create -n "$RESOURCE_GROUP_DB" --location "$LOCATION" -o table

    # create db vnet
    az network vnet create -g $RESOURCE_GROUP_DB --name $VNET_NAME_DB --location "$LOCATION" --address-prefixes 10.0.0.0/24 -o table
    DB_VNETID="$(az network vnet list -g $RESOURCE_GROUP_DB --query '[].id' -o tsv)"

    # create db subnet
    az network vnet subnet create --resource-group $RESOURCE_GROUP_DB --vnet-name $VNET_NAME_DB --address-prefixes 10.0.0.0/24 --name $SUBNET_NAME_DB -o table
    DB_SUBNET_ID=$(az network vnet subnet list \
        --resource-group $RESOURCE_GROUP_DB \
        --vnet-name $VNET_NAME_DB \
        --query "[].id" --output tsv)

    # create private dns zone
    az network private-dns zone create -g $RESOURCE_GROUP_DB -n "$PG_NAME" -o table
    PRIVATE_DNS_ZONE_ID=$(az network private-dns zone list -g $RESOURCE_GROUP_DB --query "[].id" -o tsv)

    # Create psql server
    az postgres flexible-server create --resource-group $RESOURCE_GROUP_DB --name $DB_CLUSTER_NAME --location "$LOCATION" \
    --admin-user admindb --admin-password "T3mp0r4l" \
    --sku-name Standard_B1ms --tier Burstable \
    --subnet "$DB_SUBNET_ID" --private-dns-zone "$PRIVATE_DNS_ZONE_ID" -o table

    # Create AKS cluster
    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"
    check_resourcegroup_cluster "$RESOURCE_GROUP" "$CLUSTER_NAME"

    CLUSTER_NAME=aks-work1
    RESOURCE_GROUP=aks-work1-rg
    VNET_NAME=aks-work1-vnet
    SUBNET_NAME=aks-work1-subnet

    az group create --name $RESOURCE_GROUP --location "$LOCATION" -o table

    az network vnet create \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME \
        --address-prefixes 172.16.0.0/16 \
        --subnet-name $SUBNET_NAME \
        --subnet-prefix 172.16.0.0/24 \
        -o table

    AKS_VNETID="$(az network vnet list -g $RESOURCE_GROUP --query '[].id' -o tsv)"
        
    SUBNET_ID=$(az network vnet subnet list \
        --resource-group $RESOURCE_GROUP \
        --vnet-name $VNET_NAME \
        --query "[].id" --output tsv)

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location "$LOCATION" \
    --node-vm-size "$SKU" \
    --network-plugin kubenet \
    --network-policy calico \
    --vnet-subnet-id "$SUBNET_ID" \
    --node-count 2 \
    -y \
    -o table
    
    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    # VNET peering
    az network vnet peering create -g "$RESOURCE_GROUP_DB" -n db-to-aks-peering --vnet-name "$VNET_NAME_DB" --remote-vnet "$AKS_VNETID" --allow-vnet-access true --allow-forwarded-traffic true -o table
    az network vnet peering create -g "$RESOURCE_GROUP" -n aks-to-db-peering --vnet-name "$VNET_NAME" --remote-vnet "$DB_VNETID" --allow-vnet-access true --allow-forwarded-traffic true -o table

    # private DNS zone virtual network link
    az network private-dns link vnet create -g "$RESOURCE_GROUP_DB" -n vlink2 -z "$PG_NAME" -v "$AKS_VNETID" -e False -o table

    az aks get-credentials -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --overwrite-existing &>/dev/null

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-monitor-config
  namespace: default
data:
  pghost: "${DB_CLUSTER_NAME}.postgres.database.azure.com"
  pguser: "admindb"
  pgpass: "T3mp0r4l"
  dbname: "postgres"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-check
  labels:
    app: db-check
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db-check
  template:
    metadata:
      labels:
        app: db-check
    spec:
      containers:
      - name: db-check
        image: sturrent/psql-monitor:latest
        env:
        - name: PGHOST
          valueFrom:
            configMapKeyRef:
              name: db-monitor-config
              key: pghost
        - name: PGUSER
          valueFrom:
            configMapKeyRef:
              name: db-monitor-config
              key: pguser
        - name: PGPASS
          valueFrom:
            configMapKeyRef:
              name: db-monitor-config
              key: pgpass
        - name: DBNAME
          valueFrom:
            configMapKeyRef:
              name: db-monitor-config
              key: dbname
EOF

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: workbench1
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: runner1
  namespace: workbench1
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: runner1-admin
subjects:
- kind: ServiceAccount
  name: runner1
  namespace: workbench1
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: runner1
  namespace: workbench1
  labels:
    app: runner1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: runner1
  template:
    metadata:
      labels:
        app: runner1
    spec:
      containers:
      - name: runner1
        image: sturrent/runner1:latest
      serviceAccountName: runner1
EOF


    CLUSTER_URI="$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query id -o tsv)"
    echo -e "\n************************************************************************\n"
    echo -e "\n--> Issue description: \n Pod db-check intermittenlty fails to talk to Postgres DB server $PG_NAME\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_1_validation () {
    echo -e "\n--> Validating resolution for lab${LAB_SCENARIO}...\n"
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	print_usage_text
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z "$LAB_SCENARIO" ]; then
	echo -e "\n--> Error: Lab scenario value must be provided. \n"
	print_usage_text
	exit 9
fi

if [ -z "$USER_ALIAS" ]; then
	echo -e "Error: User alias value must be provided. \n"
	print_usage_text
	exit 10
fi

# lab scenario has a valid option
if [[ ! "$LAB_SCENARIO" =~ ^[1-2]+$ ]];
then
    echo -e "\n--> Error: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 3\n"
    exit 11
fi

# main
echo -e "\n--> AKS Troubleshooting sessions
********************************************

This tool will use your default subscription to deploy the lab environments.

--> Checking prerequisites...
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ "$LAB_SCENARIO" -eq 1 ] && [ "$VALIDATE" -eq 0 ]
then
    lab_scenario_1
else
    echo -e "\n--> Error: no valid option provided\n"
    exit 12
fi

exit 0