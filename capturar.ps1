powershell
# =========================================================================
# LISTA DE ESTACIONES (Agrega o quita el símbolo # para activar más radios)
# =========================================================================
$estaciones = @{
    "Formula_Melodica" = "/formula-guadalajara/"
    # "Radio_Amor"       = "/amor-cdmx/"
    # "Radio_Felicidad"  = "/felicidad/"
    # "El_Fonografo"     = "/centro-690/"
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

$fecha = $ahora.ToString("yyyy-MM-dd")
$hora = $ahora.ToString("HH:mm")
$numSemana = (Get-Culture).Calendar.GetWeekOfYear($ahora, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
$anioSemana = $ahora.ToString("yyyy") + "-W" + $numSemana.ToString("00")
$headers = @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" }

foreach ($nombreEstacion in $estaciones.Keys) {
    $rutaEstacion = $estaciones[$nombreEstacion]
    $trucoAntiCache = "?nocache=" + (Get-Date -Format "yyyyMMddHHmmssfff")
    $url = $dominio + $rutaEstacion + $trucoAntiCache

    $baseCarpeta = "$raiz/$nombreEstacion"
    $carpetaSpotify = "$baseCarpeta/01_Listas_Spotify"
    $carpetaBitacora = "$baseCarpeta/02_Bitacoras_Con_Hora"
    $carpetaMaestros = "$baseCarpeta/04_Estadisticas_y_Maestros"

    $archivoLimpio = "$carpetaSpotify/${nombreEstacion}_$fecha.txt"
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

    foreach ($m in $coincidencias) {
        $cancionCompleta = $m.Value -replace '^alt="', '' -replace '"$', ''
        $cancionCompleta = [System.Net.WebUtility]::HtmlDecode($cancionCompleta).Trim()
        
        if ($cancionCompleta -notmatch "Digital Remaster|InstantAudio|Emisoras" -and $bloqueadas -notcontains $cancionCompleta) {
            
            $partes = $cancionCompleta -split '\s-\s', 2
            $artista = ($partes | Select-Object -First 1).Trim()
            $titulo = if ($partes.Count -gt 1) { ($partes | Select-Object -Last 1).Trim() } else { "" }

            if ($existentesDia -notcontains $cancionCompleta) {
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
    }

    $ordenadas = $ranking.Values | Sort-Object -Property Reproducciones -Descending
    if ($ordenadas.Count -gt 0) {
        $ordenadas | Export-Csv -Path $archivoRanking -NoTypeInformation -Encoding UTF8
    }
}
