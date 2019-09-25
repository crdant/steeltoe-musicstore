# add params for location, subscription id
# create short random id to use for all things that need unique routes
$uid = "123"
$version = "v1"
$location = "eastus2"
$rg = "musicstore$uid"
$registryId = "musicregistry$uid"
$configId = "musicconfig$uid"
$saPassword = "SteeltoeR0cks!"

Write-Host "Building environment with unique suffix $uid"

## login is not extremely straightforward. Sign in before running this script
## ref: https://docs.microsoft.com/en-us/cli/azure/authenticate-azure-cli?view=azure-cli-latest
## TODO: bail out if not logged in

## select subscription
# az account set --subscription <subscription-id>

## create resource group, setting default location
Write-Host "Creating resource group $rg"
az group create -l $location --name $rg

## create azure container registry
Write-Host "Creating container registry $registryId"
# az acr create --name $registryId --resource-group $rg --sku basic --admin-enabled true
Write-Host "Fetching registry credentials"
$registryPassword = az acr credential show -n $registryId | jq ".passwords[0].value" -r
Write-Host "Logging in to container registry"
az acr login --name $registryId
$acrLoginServer = az acr show --name $registryId --query loginServer --output tsv

# TODO: Use Azure SQL with Managed Identity access instead
# deploy the sql server well in advance so it can spin up fully
Write-Host "Deploying SQL Server"
az container create --image mcr.microsoft.com/mssql/server -g musicstore123 -n sqlserver --cpu 3 --memory 3.5  --no-wait `
     --dns-name-label="musicsql$uid" --ports 1433 `
     --environment-variables ACCEPT_EULA=Y SA_PASSWORD=$saPassword

## this is a bit brute force...
az appconfig create -g $rg -n $configId -l $location
az appconfig kv set -n $configId --key DisableServiceDiscovery --value true -y
az appconfig kv set -n $configId --key sqlserver:credentials:password --value $saPassword -y
az appconfig kv set -n $configId --key sqlserver:credentials:username --value sa -y
az appconfig kv set -n $configId --key discovery:services:0:serviceId --value musicservice -y
az appconfig kv set -n $configId --key discovery:services:0:host --value "musicservice$uid.$location.azurecontainer.io" -y
az appconfig kv set -n $configId --key discovery:services:0:port --value 80 -y
az appconfig kv set -n $configId --key discovery:services:0:isSecure --value false -y
az appconfig kv set -n $configId --key discovery:services:1:serviceId --value orderservice -y
az appconfig kv set -n $configId --key discovery:services:1:host --value "orderservice$uid.$location.azurecontainer.io" -y
az appconfig kv set -n $configId --key discovery:services:1:port --value 80 -y
az appconfig kv set -n $configId --key discovery:services:1:isSecure --value false -y
az appconfig kv set -n $configId --key discovery:services:2:serviceId --value shoppingcartservice -y
az appconfig kv set -n $configId --key discovery:services:2:host --value "shoppingcartservice$uid.$location.azurecontainer.io" -y
az appconfig kv set -n $configId --key discovery:services:2:port --value 80 -y
az appconfig kv set -n $configId --key discovery:services:2:isSecure --value false -y

## tag and push containers 
$images = "musicservice", "orderservice", "shoppingcartservice", "musicstore"
foreach ($image in $images)
{
    $tag = $image + ":" + $version
    docker-compose build $image
    Write-Debug "Tagging $image with $acrLoginServer/$tag"
    docker tag $image $acrLoginServer/$tag
    Write-Host "Pushing $tag to $acrLoginServer"
    docker push $acrLoginServer/$tag
    Write-Host("Creating container $image from $acrLoginServer/$tag in $rg")
    az container create -g $rg --name $image --image $acrLoginServer/$tag --registry-login-server $acrLoginServer --registry-username $registryId --registry-password $registryPassword --no-wait `
        --dns-name-label=$image$uid --ports 80 --assign-identity `
        --environment-variables ASPNETCORE_ENVIRONMENT=AzureContainerInstances sqlserver__credentials__server="musicsql$uid.$location.azurecontainer.io" AppConfig__Endpoint="https://$rg.azconfig.io"

    # TODO: Give container instance the Contributor permission on the AppConfig resource
}
