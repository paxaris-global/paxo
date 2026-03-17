# Start Minikube if not running
if (-not (minikube status | Select-String "host: Running")) {
    Write-Host "Starting Minikube..."
    minikube start
}

# Apply all manifests
kubectl apply -f .

# Wait for all pods to be ready
Write-Host "Waiting for pods to be ready..."
$pods = @("api-gateway", "identity-service", "jaeger", "keycloak", "mysql", "product-management-service")
foreach ($pod in $pods) {
    while (-not (kubectl get pods | Select-String "$pod.*Running")) {
        Start-Sleep -Seconds 5
        Write-Host "Waiting for $pod..."
    }
}

# Open service URLs in browser
foreach ($svc in $pods) {
    $url = minikube service $svc --url
    if ($url) {
        Start-Process $url
        Write-Host "Opened $svc at $url"
    }
}
