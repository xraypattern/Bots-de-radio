# =========================================================================
# ESTACION FORMULA MELODICA 
# =========================================================================
$estaciones = @{
    "Formula_Melodica" = "/formula-guadalajara/"

}

$dominio = "https://emisoras.com.mx"
$raiz = "."
$bloqueadasArchivo = "$raiz/Bloqueadas.txt"

if (-not (Test-Path $bloqueadasArchivo)) {
    Set-Content -Path $bloqueadasArchivo -Value @("Thanh Yen - Pumice Pulse", "Network Music Ensemble - Bone Crusher") -Encoding UTF8
}
$bloqueadas = @(Get-Content $bloqueadasArchivo -Encoding UTF8)

# Ajustar a hora de México (UTC-6)
try { $tzMexico = [System.TimeZoneInfo]::FindSystemTimeZoneById("America/Mexico_City") } catch { $tzMexico = [System.TimeZoneInfo]::FindSystemTimeZoneById("Central Standard Time (Mexico)") }
$ahora = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tzMexico)

$diaRadio = $ahora.AddHours(-6)
$fecha = $diaRadio.ToString("yyyy-MM-dd")
$hora = $ahora.ToString("HH:mm")
$horaNum = $ahora.Hour

# Determinar el bloque horario de 6 horas
if ($horaNum -ge 6 -and $horaNum -lt 12) {
    $bloqueNombre = "1_Manana"
} elseif ($horaNum -ge 12 -and $horaNum -lt 18) {
    $bloqueNombre = "2_Tarde"
} elseif ($horaNum -ge 18 -and $horaNum -le 23) {
    $bloqueNombre = "3_Noche"
} else {
    $bloqueNombre = "4_Madrugada"
}

$numSemana = (Get-Culture).Calendar.GetWeekOfYear($diaRadio, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
$anioSemana = $diaRadio.ToString("yyyy") + "-W" + $numSemana.ToString("00")
$headers = @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" }

foreach ($nombreEstacion in $estaciones.Keys) {
    $rutaEstacion = $estaciones[$nombreEstacion]
    $trucoAntiCache = "?nocache=" + (Get-Date -Format "yyyyMMddHHmmssfff")
    $url = $dominio + $rutaEstacion + $trucoAntiCache

    $baseCarpeta = "$raiz/$nombreEstacion"
    $carpetaSpotify = "$baseCarpeta/01_Listas_Spotify"
    $carpetaBitacora = "$baseCarpeta/02_Bitacoras_Con_Hora"
    $carpetaMaestros = "$baseCarpeta/04_Estadisticas_y_Maestros"

    $archivoLimpio = "$carpetaSpotify/${nombreEstacion}_${fecha}_0_Completo.txt"

    $archivoHora = "$carpetaBitacora/Bitacora_$fecha.txt"
    $archivoMaestro = "$carpetaMaestros/Lista_Maestra_Historica.txt"
    $archivoSemanal = "$carpetaMaestros/Semana_$anioSemana.txt"
    $archivoRanking = "$carpetaMaestros/Ranking_Exitos.csv"

    foreach ($ruta in @($carpetaSpotify, $carpetaBitacora, $carpetaMaestros)) {
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -ItemType Directory -Force | Out-Null }
    }
    foreach ($arch in @($archivoLimpio, $archivoHora, $archivoMaestro, $archivoSemanal)) {
        if (-not (Test-Path $arch)) { New-Item -Path $arch -ItemType File -Force | Out-Null }
    }

    try {
        $html = (Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 15).Content
        $coincidencias = [regex]::Matches($html, 'alt="([^"]+\s-\s[^"]+)"')
    } catch {
        continue
    }

    $existentesDia = @(Get-Content $archivoLimpio -Encoding UTF8)
    $existentesMaestro = @(Get-Content $archivoMaestro -Encoding UTF8)
    $existentesSemana = @(Get-Content $archivoSemanal -Encoding UTF8)

    $ranking = @{}
    if ((Test-Path $archivoRanking) -and ((Get-Item $archivoRanking).Length -gt 0)) {
        $datosCsv = Import-Csv -Path $archivoRanking -Encoding UTF8
        foreach ($fila in $datosCsv) {
            if ($fila.Artista -and $fila.Cancion) {
                $clave = "$($fila.Artista) - $($fila.Cancion)"
                $ranking[$clave] = [PSCustomObject]@{
                    Artista        = $fila.Artista
                    Cancion        = $fila.Cancion
                    Reproducciones = [int]$fila.Reproducciones
                    Ultima_Vez     = $fila.Ultima_Vez
                }
            }
        }
    }

    $huboTraslape = $false
    $cancionesNuevasEsteTurno = @()

    for ($i = $coincidencias.Count - 1; $i -ge 0; $i--) {
        $cancionCompleta = $coincidencias[$i].Value -replace '^alt="', '' -replace '"$', ''
        $cancionCompleta = [System.Net.WebUtility]::HtmlDecode($cancionCompleta).Trim()
        
            if ($bloqueadas -contains $cancionCompleta) {
              Add-Content -Path $archivoHora -Value "[$hora] 🚫 CORTINILLA DETECTADA: $cancionCompleta" -Encoding UTF8
        } elseif ($cancionCompleta -notmatch "Digital Remaster|InstantAudio|Emisoras") {
            if ($existentesDia -contains $cancionCompleta) {
                $huboTraslape = $true
            } else {
                $cancionesNuevasEsteTurno += $cancionCompleta
            }
        }

    }

    if ($existentesDia.Count -gt 0 -and -not $huboTraslape -and $cancionesNuevasEsteTurno.Count -gt 0) {
        Add-Content -Path $archivoHora -Value "--- ⚠️ POSIBLE SALTO DE CANCIONES (0 en comun con la lectura anterior) ---" -Encoding UTF8
    }

    $minTotal = ($ahora.Hour * 60) + $ahora.Minute
    if ($minTotal -ge 375 -and $minTotal -lt 735) {       # 06:15 a 12:14
        $bloqueActual = "1_Manana"
    } elseif ($minTotal -ge 735 -and $minTotal -lt 1095) { # 12:15 a 18:14
        $bloqueActual = "2_Tarde"
    } elseif ($minTotal -ge 1095 -or $minTotal -lt 15) {   # 18:15 a 00:14
        $bloqueActual = "3_Noche"
    } else {                                               # 00:15 a 06:14
        $bloqueActual = "4_Madrugada"
    }


        foreach ($cancionCompleta in $cancionesNuevasEsteTurno) {
        if ($cancionCompleta -match "Himno Nacional") {
            if ($ahora.Hour -ge 5 -and $ahora.Hour -le 7) { $bloqueActual = "1_Manana" }
            elseif ($ahora.Hour -ge 23 -or $ahora.Hour -le 1) { $bloqueActual = "4_Madrugada" }
            Add-Content -Path $archivoHora -Value "[$hora] 🔔 CORTE: $cancionCompleta -> $bloqueActual" -Encoding UTF8
            Add-Content -Path $archivoLimpio -Value $cancionCompleta -Encoding UTF8
            $existentesDia += $cancionCompleta
            continue
        }

       $archivoBloque = "$carpetaSpotify/${nombreEstacion}_${fecha}_${bloqueActual}.txt"
        if (-not (Test-Path $archivoBloque)) { New-Item -Path $archivoBloque -ItemType File -Force | Out-Null }
        Add-Content -Path $archivoBloque -Value $cancionCompleta -Encoding UTF8

        $partes = $cancionCompleta -split '\s-\s', 2
        $artista = ($partes | Select-Object -First 1).Trim()
        $titulo = if ($partes.Count -gt 1) { ($partes | Select-Object -Last 1).Trim() } else { "" }

        Add-Content -Path $archivoLimpio -Value $cancionCompleta -Encoding UTF8
        Add-Content -Path $archivoHora -Value "[$hora] $cancionCompleta" -Encoding UTF8
        $existentesDia += $cancionCompleta

        if ($ranking.ContainsKey($cancionCompleta)) {
            $ranking[$cancionCompleta].Reproducciones += 1
            $ranking[$cancionCompleta].Ultima_Vez = "$fecha $hora"
        } else {
            $ranking[$cancionCompleta] = [PSCustomObject]@{
                Artista        = $artista
                Cancion        = $titulo
                Reproducciones = 1
                Ultima_Vez     = "$fecha $hora"
            }
        }

        if ($existentesMaestro -notcontains $cancionCompleta) {
            Add-Content -Path $archivoMaestro -Value $cancionCompleta -Encoding UTF8
            $existentesMaestro += $cancionCompleta
        }

        if ($existentesSemana -notcontains $cancionCompleta) {
            Add-Content -Path $archivoSemanal -Value $cancionCompleta -Encoding UTF8
            $existentesSemana += $cancionCompleta
        }
    }

    $ordenadas = $ranking.Values | Sort-Object -Property Reproducciones -Descending
    if ($ordenadas.Count -gt 0) {
        $ordenadas | Export-Csv -Path $archivoRanking -NoTypeInformation -Encoding UTF8
    }
}
