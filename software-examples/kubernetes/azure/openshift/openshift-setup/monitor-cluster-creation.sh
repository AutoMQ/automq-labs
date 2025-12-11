#!/bin/bash

# Script to monitor Azure Red Hat OpenShift cluster creation progress
# Usage: ./monitor-cluster-creation.sh [cluster-name] [resource-group]

CLUSTER_NAME="${1:-demobe-openshift}"
RESOURCE_GROUP="${2:-AutoMQ-lab-openshift1211}"

echo "=========================================="
echo "Monitoring ARO Cluster Creation Progress"
echo "=========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "=========================================="
echo ""

# Function to get cluster provisioning state
get_cluster_state() {
    az aro show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query "{provisioningState:provisioningState,clusterProfile:clusterProfile,workerProfiles:workerProfiles[0],masterProfile:masterProfile}" \
        --output json 2>/dev/null
}

# Function to get activity log
get_activity_log() {
    echo ""
    echo "--- Recent Activity Log (last 10 events) ---"
    az monitor activity-log list \
        --resource-group "$RESOURCE_GROUP" \
        --max-events 10 \
        --query "[].{Time:eventTimestamp,Status:status.value,Operation:operationName.localizedValue,Resource:resourceId}" \
        --output table 2>/dev/null || echo "Unable to fetch activity log"
}

# Function to check resource deployment status
check_deployments() {
    echo ""
    echo "--- Resource Deployments Status ---"
    az deployment group list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, '$CLUSTER_NAME') || contains(name, 'aro')].{Name:name,State:properties.provisioningState,Time:properties.timestamp}" \
        --output table 2>/dev/null || echo "Unable to fetch deployment status"
}

# Main monitoring loop
while true; do
    clear
    echo "=========================================="
    echo "ARO Cluster Creation Monitor"
    echo "=========================================="
    echo "Cluster: $CLUSTER_NAME"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""
    
    STATE=$(get_cluster_state)
    
    if [ -z "$STATE" ] || [ "$STATE" = "null" ]; then
        echo "⚠️  Cluster resource not found or not accessible yet..."
        echo ""
        echo "This could mean:"
        echo "  1. Cluster creation is still initializing"
        echo "  2. Resource hasn't been created yet"
        echo "  3. Check your Azure credentials: az login"
    else
        echo "📊 Cluster Status:"
        echo "$STATE" | jq -r '.provisioningState // "Unknown"' | sed 's/^/   /'
        echo ""
        
        echo "🔧 Cluster Configuration:"
        echo "$STATE" | jq -r '.clusterProfile.version // "N/A"' | sed 's/^/   OpenShift Version: /'
        echo "$STATE" | jq -r '.clusterProfile.domain // "N/A"' | sed 's/^/   Domain: /'
        echo ""
        
        echo "👷 Worker Profile:"
        echo "$STATE" | jq -r '.workerProfiles.count // "N/A"' | sed 's/^/   Node Count: /'
        echo "$STATE" | jq -r '.workerProfiles.vmSize // "N/A"' | sed 's/^/   VM Size: /'
        echo ""
        
        echo "🎛️  Master Profile:"
        echo "$STATE" | jq -r '.masterProfile.vmSize // "N/A"' | sed 's/^/   VM Size: /'
        
        PROVISIONING_STATE=$(echo "$STATE" | jq -r '.provisioningState // "Unknown"')
        
        if [ "$PROVISIONING_STATE" = "Succeeded" ]; then
            echo ""
            echo "✅ Cluster creation completed successfully!"
            echo ""
            echo "Next steps:"
            echo "  1. Get API server URL:"
            echo "     az aro show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query 'apiserverProfile.url' -o tsv"
            echo ""
            echo "  2. Get credentials:"
            echo "     az aro list-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
            echo ""
            echo "  3. Connect to cluster:"
            echo "     az aro get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
            break
        elif [ "$PROVISIONING_STATE" = "Failed" ]; then
            echo ""
            echo "❌ Cluster creation failed!"
            echo ""
            echo "Check the activity log for details:"
            get_activity_log
            break
        fi
    fi
    
    get_activity_log
    check_deployments
    
    echo ""
    echo "=========================================="
    echo "Refreshing in 30 seconds... (Press Ctrl+C to stop)"
    echo "=========================================="
    sleep 30
done

