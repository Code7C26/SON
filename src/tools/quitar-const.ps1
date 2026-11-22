param([string]$Proyecto)
$ErrorActionPreference = 'Continue'
Set-Location $Proyecto
for ($vuelta = 1; $vuelta -le 8; $vuelta++) {
    $salida = & flutter analyze --no-fatal-infos 2>&1 | Out-String
    $errores = [regex]::Matches($salida, 'error - .+ - ((?:lib|test)\\[^:]+):(\d+):\d+ - (invalid_constant|const_initialized_with_non_constant_value|non_constant_default_value)')
    if ($errores.Count -eq 0) {
        Write-Output "limpio en vuelta $vuelta"
        exit 0
    }
    $hechos = @{}
    $cambios = 0
    foreach ($e in $errores) {
        $rel = $e.Groups[1].Value
        $n = [int]$e.Groups[2].Value
        $clave = "$rel`:$n"
        if ($hechos.ContainsKey($clave)) { continue }
        $hechos[$clave] = $true
        $ruta = Join-Path $Proyecto ($rel -replace '\\','\')
        $lineas = [System.Collections.Generic.List[string]]::new()
        $lineas.AddRange([IO.File]::ReadAllLines($ruta))
        $idx = -1
        for ($k = $n - 1; $k -ge [Math]::Max(0, $n - 30); $k--) {
            if ($lineas[$k] -match '(^|[^A-Za-z0-9_])const ') { $idx = $k; break }
        }
        if ($idx -lt 0) { Write-Output "sin const $clave"; continue }
        $lineas[$idx] = [regex]::Replace($lineas[$idx], '(^|[^A-Za-z0-9_])const ', '$1', 1)
        [IO.File]::WriteAllLines($ruta, $lineas)
        $cambios++
    }
    Write-Output "vuelta $vuelta errores $($errores.Count) cambios $cambios"
    if ($cambios -eq 0) { exit 1 }
}
exit 1
