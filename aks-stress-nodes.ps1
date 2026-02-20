param(
    [Parameter(Mandatory=$true)]
    [string]$Node,
    
    [Parameter(Mandatory=$true)]
    [int]$DurationSeconds,
    
    [string]$Namespace = "stress-test",
    
    [int]$PodCount = 10,
    
    [string[]]$Tolerations = @()
)

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "AKS Node Stress Tool" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "Node: $Node"
Write-Host "Namespace: $Namespace"
Write-Host "Pods: $PodCount (1 CPU thread per pod)"
Write-Host "Duration: $DurationSeconds seconds"
Write-Host "========================================`n" -ForegroundColor Magenta

$tolerationsYaml = ""
if ($Tolerations -and $Tolerations.Count -gt 0) {
    $tolerationsYaml = "`n  tolerations:"
    foreach ($tol in $Tolerations) {
        $parts = $tol -split ':'
        $keyVal = $parts[0] -split '='
        $tolerationsYaml += "`n  - key: `"$($keyVal[0])`"`n    operator: Exists"
        if ($parts.Count -eq 2) {
            $tolerationsYaml += "`n    effect: $($parts[1])"
        }
    }
}

Write-Host "Deploying $PodCount pods..." -ForegroundColor Yellow

$timestamp = Get-Date -Format "yyyyMMddHHmmss"

for ($i = 1; $i -le $PodCount; $i++) {
    $podYaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: cpu-stress-$timestamp-$i
  namespace: $Namespace
spec:
  nodeName: $Node$tolerationsYaml
  restartPolicy: Never
  containers:
  - name: stress
    image: mcr.microsoft.com/powershell:latest
    command: ["pwsh", "-c"]
    args:
    - |
      `$duration = $DurationSeconds
      Write-Host "Starting CPU stress for `$duration seconds"
      `$endTime = (Get-Date).AddSeconds(`$duration)
      while ((Get-Date) -lt `$endTime) {
        `$x = 0
        for (`$i = 0; `$i -lt 100000; `$i++) {
          `$x = [math]::Sqrt(`$i) + [math]::Sin(`$i)
        }
      }
      Write-Host "Completed"
    resources:
      requests:
        cpu: "50m"
        memory: "256Mi"
"@
    
    $podYaml | kubectl apply -f -
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "Deployed $PodCount stress pods to node $Node" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "Pods will run for $DurationSeconds seconds and exit" -ForegroundColor Yellow
Write-Host "Monitor: kubectl get pods -n $Namespace -w" -ForegroundColor Gray
Write-Host ""
