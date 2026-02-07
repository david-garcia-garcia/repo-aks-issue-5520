# AKS Metrics Stability Reproduction

Scripts to reproduce kubelet metrics endpoint failures when AKS nodes experience high CPU load.

## Problem

When AKS nodes have CPU spikes, the kubelet metrics endpoint (`https://<node-ip>:10250/metrics/resource`) stops responding, causing:
- HPA/VPA to stop working
- Cluster autoscaler to fail adding nodes

## Prerequisites

- `kubectl` configured for your AKS cluster
- PowerShell
- Permissions to create pods in kube-system

## Scripts

**`aks-monitor-metrics.ps1`** - Monitors kubelet metrics endpoint with response times

**`aks-stress-nodes.ps1`** - Stresses a node with CPU load

## Usage

### Terminal 1: Start Monitoring

```powershell
.\aks-monitor-metrics.ps1 -Node "aks-nodepool-vmss000000"
```

Monitor output shows:
```
[2026-02-07 09:15:01] OK - 55ms
[2026-02-07 09:15:06] TIMEOUT - 10000ms
```

### Terminal 2: Deploy Stress

```powershell
# Stress node for 5 minutes with 10 pods (10 CPU threads)
.\aks-stress-nodes.ps1 -Node "aks-nodepool-vmss000000" -DurationSeconds 300 -PodCount 10

# For Windows nodes, add toleration
.\aks-stress-nodes.ps1 -Node "aks-windows-vmss000000" -DurationSeconds 300 -PodCount 10 -Tolerations @("windows:NoSchedule")
```

### Cleanup

```powershell
# Remove monitor pod
.\aks-monitor-metrics.ps1 -Node "aks-nodepool-vmss000000" -Remove

# Stress pods auto-exit after duration (status: Completed)
# Optional: kubectl delete pods -n stress-test -l app=cpu-stress
```

## Parameters

### aks-monitor-metrics.ps1
- `-Node` (required) - Node to monitor
- `-IntervalSeconds` - Check interval (default: 5)
- `-TimeoutSeconds` - Curl timeout (default: 10)
- `-Remove` - Delete monitor pod

### aks-stress-nodes.ps1
- `-Node` (required) - Node to stress
- `-DurationSeconds` (required) - Test duration in seconds
- `-PodCount` - Number of pods (default: 10, 1 CPU thread each)
- `-Namespace` - Namespace (default: "stress-test")
- `-Tolerations` - For tainted nodes (e.g., `@("windows:NoSchedule")`)

## How It Works

**Monitoring**: Pod in kube-system uses metrics-server service account to curl `https://<node-ip>:10250/metrics/resource` every 5 seconds, reporting response time and detecting timeouts.

**Stress**: Pods scheduled to target node run PowerShell CPU-intensive loops for specified duration, then exit.

## Notes

- Monitor pod streams output via `kubectl logs -f` (Ctrl+C to stop streaming)
- Stress pods use PowerShell cross-platform image (works on Linux/Windows)
- Each stress pod = 1 CPU thread
- Pods auto-exit after duration
- Response times increase before timeout occurs
