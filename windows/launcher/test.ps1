$ErrorActionPreference = 'Stop'
$source = $env:SPECCOMPILER_HOME
$pandoc = "$env:SPECCOMPILER_DIST/bin/pandoc.exe"
$suite = $null
$test = $null
$junit = $false
$coverage = $false
foreach ($arg in $args) {
    switch ($arg) {
        { $_ -in '--junit', '-j' } { $junit = $true }
        { $_ -in '--coverage', '-c' } { $coverage = $true }
        { $_ -in '--help', '-h' } { Write-Output 'Usage: specc test [suite[/test]] [--junit] [--coverage]'; exit 0 }
        default {
            if ($suite -or $arg.StartsWith('-')) { throw "Unexpected argument: $arg" }
            $parts = $arg -split '/', 2
            $suite = $parts[0]
            if ($parts.Count -eq 2) { $test = $parts[1] }
        }
    }
}
if (!(Test-Path "$source/tests/runner.lua")) { throw 'Install the test suite component to use specc test.' }
Push-Location $source
try {
    if ($junit) { Remove-Item -LiteralPath 'tests/reports/junit.partial' -ErrorAction SilentlyContinue }
    $suites = if ($suite) { @($suite) } else {
        @(Get-ChildItem tests/e2e -Directory | Sort-Object Name | ForEach-Object Name)
        @(Get-ChildItem models -Directory | Sort-Object Name | Where-Object { Test-Path "$($_.FullName)/tests/suite.yaml" } | ForEach-Object { "$($_.Name)-tests" })
    }
    $failed = 0
    $empty = [IO.Path]::GetTempFileName()  # pandoc cannot read NUL as an input file
    $reports = @()
    foreach ($name in $suites) {
        $pandocArgs = @('--from', 'markdown', '--to', 'plain', '--lua-filter', 'tests/runner.lua', '--metadata', "suite=$name", $empty, '-o', 'NUL')
        if ($test) { $pandocArgs += @('--metadata', "test=$test") }
        if ($junit) { $pandocArgs += @('--metadata', 'junit=true') }
        if ($coverage) {
            $pandocArgs += @('--metadata', 'coverage=true')
            $safeName = (($name -replace '[/\\]', '_') -replace '\s+', '_') -replace '[^a-zA-Z0-9_-]', ''
            $report = "tests/reports/coverage/$safeName.lcov"
            Remove-Item -LiteralPath $report -ErrorAction SilentlyContinue
            $reports += $report
        }
        & $pandoc @pandocArgs
        if ($LASTEXITCODE -ne 0) { $failed++ }
    }
    if ($coverage) {
        $existing = @($reports | Where-Object { Test-Path -LiteralPath $_ })
        if ($existing.Count) {
            $content = ($existing | ForEach-Object { [IO.File]::ReadAllText((Join-Path $source $_)) }) -join "`n"
            [IO.File]::WriteAllText((Join-Path $source 'tests/reports/coverage/merged.lcov'), $content)
        }
    }
    if ($failed) { exit 1 }
    exit 0
} finally { Remove-Item -LiteralPath $empty -ErrorAction SilentlyContinue; Pop-Location }
