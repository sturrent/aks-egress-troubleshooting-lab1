#aks-egress-troubleshooting-lab1

Bash script to deploy lab for AKS egress troubleshooting.
This will setup an AKS cluster, PostgresQL flexiserver, and workload running on AKS that connects to the database.
To deploy run the following:

```plain-text
./aks-lab.sh -l 1 -u <USER_ALIAS>
```


General usage:

```plain-text
aks-labs usage: aks-labs -l <LAB#> -u <USER_ALIAS> [-r|--region] [-s|--sku] [-h|--help] [--version]

Here is the list of current labs available:
*************************************************************************************
*        1. Pod with intermittent issues to communicate with Postgres DB
*        2. 
*************************************************************************************

"-l|--lab" Lab scenario to deploy (3 possible options)
"-u|--user" User alias to add on the lab name
"-r|--region" region to create the resources
"-s|--sku" nodes SKU
"--version" print version of the tool
"-h|--help" help info
```
