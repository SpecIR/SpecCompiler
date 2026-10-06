# Run with Windows PowerShell 5.1; exercise quoting, working directory and exits
# without requiring a full Haskell build.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sandbox = Join-Path $repo ('dist/launcher test ' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $sandbox 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
Copy-Item "$repo/windows/launcher/*" $bin
$mock = @'
using System;
using System.IO;
public static class MockPandoc {
    public static int Main(string[] args) {
        File.WriteAllLines(Environment.GetEnvironmentVariable("SPECC_TEST_LOG"),
            new[] { Directory.GetCurrentDirectory(), Environment.GetEnvironmentVariable("LUA_CPATH") });
        File.AppendAllLines(Environment.GetEnvironmentVariable("SPECC_TEST_LOG"), args);
        return int.Parse(Environment.GetEnvironmentVariable("SPECC_TEST_EXIT") ?? "0");
    }
}
'@
Add-Type -TypeDefinition $mock -OutputAssembly "$bin/pandoc.exe" -OutputType ConsoleApplication
$env:SPECC_TEST_LOG = "$sandbox/args.txt"
$env:SPECCOMPILER_HOME = $sandbox
$env:SPECCOMPILER_DIST = $sandbox
$projectDir = Join-Path $sandbox 'project with spaces'
New-Item -ItemType Directory -Force $projectDir | Out-Null
Set-Content "$projectDir/project.yaml" 'title: Test'
$env:SPECC_TEST_EXIT = '37'
& "$bin/specc.cmd" build "$projectDir/project.yaml"
if ($LASTEXITCODE -ne 37) { throw 'Build exit code was lost' }
$lines = Get-Content $env:SPECC_TEST_LOG
if ($lines[0] -ne $projectDir) { throw 'Project working directory was lost' }
if ($lines[1] -notlike '*vendor/?.dll*') { throw 'Native module path missing' }
if ($lines -notcontains 'project.yaml') { throw 'Project argument was lost' }
& "$bin/specc.cmd" pandoc '--metadata' 'title=hello world'
if ($LASTEXITCODE -ne 37) { throw 'Pandoc exit code was lost' }
if ((Get-Content $env:SPECC_TEST_LOG) -notcontains 'title=hello world') { throw 'Argument quoting failed' }
New-Item -ItemType Directory -Force "$sandbox/tests" | Out-Null
Set-Content "$sandbox/tests/runner.lua" '-- placeholder'
& "$bin/specc.cmd" test 'pipeline/example' --junit
if ($LASTEXITCODE -ne 1) { throw 'Test failure was lost' }
$lines = Get-Content $env:SPECC_TEST_LOG
foreach ($expected in @('suite=pipeline', 'test=example', 'junit=true', 'NUL')) {
    if ($lines -notcontains $expected) { throw "Missing test argument: $expected" }
}
$env:SPECC_TEST_EXIT = '0'
& "$bin/specc.cmd" test pipeline
if ($LASTEXITCODE -ne 0) { throw 'Successful test returned failure' }
Remove-Item -LiteralPath $sandbox -Recurse -Force
Write-Output 'Launcher checks passed (spaces, arguments, project directory, exit codes).'
