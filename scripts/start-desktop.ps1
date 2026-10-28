Get-Content "$PSScriptRoot\..\.env" | Where-Object { $_ -match '^\s*[^#\s][^=]*=' } | ForEach-Object {
  $k, $v = $_ -split '=', 2; [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process') }
Set-Location "$PSScriptRoot\..\desktop"; mvn javafx:run
