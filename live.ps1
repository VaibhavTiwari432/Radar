# Live Mission Console: FastAPI bridge (Python planner + MATLAB judge) + vite dev client.
#   .\live.ps1        then press RUN in the browser
# Ctrl-C here leaves the two windows running; close them to stop.
$root = $PSScriptRoot

Start-Process -WindowStyle Minimized python  -ArgumentList '-m','uvicorn','server.app:app','--port','8000' -WorkingDirectory $root
Start-Process -WindowStyle Minimized npm.cmd -ArgumentList 'run','dev' -WorkingDirectory "$root\web"

# MATLAB's engine cold-starts in 12-68 s (server/README.md); the console only
# polls /health at mount, so opening early would pin it at JUDGE OFFLINE.
Write-Host -NoNewline 'waiting for the MATLAB judge'
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep 2
    try {
        if ((Invoke-RestMethod 'http://127.0.0.1:8000/health' -TimeoutSec 5).judge_online) { break }
    } catch {}
    Write-Host -NoNewline '.'
}
Write-Host ''
Start-Process 'http://localhost:5173/console.html'
