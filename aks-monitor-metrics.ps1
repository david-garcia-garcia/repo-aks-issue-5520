param(
    [Parameter(Mandatory=$true)]
    [string]$Node,
    [int]$IntervalSeconds = 5,
    [int]$TimeoutSeconds = 10,
    [switch]$Remove
)

$podName = "test-metrics-monitor-$($Node.ToLower())"

if ($Remove) {
    kubectl delete pod $podName -n kube-system
    exit 0
}

$ip = (kubectl get node $Node -o json | ConvertFrom-Json).status.addresses | Where-Object { $_.type -eq "InternalIP" } | Select-Object -ExpandProperty address
Write-Host "$Node -> $ip"

$yaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: $podName
  namespace: kube-system
spec:
  serviceAccountName: metrics-server
  containers:
  - name: monitor
    image: curlimages/curl:latest
    command: [sh, -c]
    args:
    - |
      apk add --no-cache bc > /dev/null 2>&1
      echo "Monitor started for node: $Node (${ip}) - Timeout: ${TimeoutSeconds}s - Interval: ${IntervalSeconds}s"
      while true; do
        TOKEN=`$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
        TIME_OUTPUT=`$(curl -w "%{time_total}" -o /tmp/response.txt -sS --max-time $TimeoutSeconds -k --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer `$TOKEN" https://${ip}:10250/metrics/resource 2>&1)
        CURL_EXIT=`$?
        MS=`$(echo "`$TIME_OUTPUT * 1000" | bc | cut -d. -f1)
        if [ `$CURL_EXIT -eq 0 ] && grep -q "node_cpu_usage" /tmp/response.txt 2>/dev/null; then
          echo "[`$(date '+%Y-%m-%d %H:%M:%S')] OK - `${MS}ms"
        elif [ `$CURL_EXIT -eq 28 ]; then
          echo "[`$(date '+%Y-%m-%d %H:%M:%S')] TIMEOUT - `${MS}ms"
        else
          ERROR=`$(echo "`$TIME_OUTPUT" | head -c 60)
          echo "[`$(date '+%Y-%m-%d %H:%M:%S')] FAIL - `${MS}ms - `$ERROR"
        fi
        sleep $IntervalSeconds
      done
  restartPolicy: Always
"@

$tmp = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tmp, $yaml, [System.Text.Encoding]::UTF8)
kubectl apply -f $tmp
Remove-Item $tmp

Write-Host "`nWaiting for pod..."
$attempts = 0
while ($attempts -lt 30) {
    $status = kubectl get pod $podName -n kube-system -o jsonpath='{.status.phase}' 2>&1
    if ($status -eq "Running") { break }
    Start-Sleep 1
    $attempts++
}

Write-Host "Streaming logs (Ctrl+C to stop):`n"
kubectl logs -f $podName -n kube-system
