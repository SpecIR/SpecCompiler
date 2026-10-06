@echo off
where java >NUL 2>&1
if errorlevel 1 (
  echo plantuml: no Java runtime on PATH. Install one, e.g.: winget install EclipseAdoptium.Temurin.21.JRE 1>&2
  exit /b 1
)
java -Djava.awt.headless=true -jar "%~dp0..\vendor\plantuml\plantuml.jar" %*
exit /b %errorlevel%
