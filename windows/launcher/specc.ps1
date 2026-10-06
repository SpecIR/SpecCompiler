# Native launcher: Pandoc loads the DLL modules in its own Lua state.
$ErrorActionPreference = 'Stop'
$prefix = Split-Path $PSScriptRoot -Parent
$source = if ($env:SPECCOMPILER_HOME) { $env:SPECCOMPILER_HOME } else { $prefix }
$dist = if ($env:SPECCOMPILER_DIST) { $env:SPECCOMPILER_DIST } else { $prefix }
$source = [IO.Path]::GetFullPath($source).Replace('\', '/')
$dist = [IO.Path]::GetFullPath($dist).Replace('\', '/')
$env:SPECCOMPILER_HOME = $source
$env:SPECCOMPILER_DIST = $dist
$env:PATH = "$dist/bin;$env:PATH"
$env:LUA_PATH = "$source/src/?.lua;$source/src/?/init.lua;$source/?.lua;$source/?/init.lua;$dist/vendor/?.lua;$dist/vendor/?/init.lua;$dist/vendor/slaxml/?.lua;$source/tests/?.lua;$source/tests/?/init.lua;$env:LUA_PATH"
$env:LUA_CPATH = "$dist/vendor/?.dll;$env:LUA_CPATH"
# Version-specific Lua variables otherwise override LUA_PATH/LUA_CPATH.
$env:LUA_PATH_5_4 = $env:LUA_PATH
$env:LUA_CPATH_5_4 = $env:LUA_CPATH
$pandoc = "$dist/bin/pandoc.exe"
$command = if ($args.Count) { $args[0] } else { '--help' }
$rest = @($args | Select-Object -Skip 1)
switch ($command) {
    { $_ -in 'help', '--help', '-h' } {
        Write-Output 'Usage: specc build [project.yaml] | test [suite[/test]] [--junit] [--coverage] | pandoc <args> | --version'
        exit 0
    }
    '--version' { & $pandoc --version; exit $LASTEXITCODE }
    'pandoc' { & $pandoc @rest; exit $LASTEXITCODE }
    'test' {
        & "$prefix/bin/test.ps1" @rest
        exit $LASTEXITCODE
    }
    'build' {
        if ($rest.Count -gt 1) { throw 'Usage: specc build [project.yaml]' }
        $project = if ($rest.Count) { $rest[0] } else { 'project.yaml' }
        $project = (Resolve-Path -LiteralPath $project).Path
        Push-Location (Split-Path $project -Parent)
        try {
            $base = Split-Path $project -Leaf
            & $pandoc --from markdown --to json --lua-filter "$source/src/filter.lua" --metadata-file $base $base -o NUL
            $code = $LASTEXITCODE
        } finally { Pop-Location }
        exit $code
    }
    default { throw "Unknown command: $command" }
}
