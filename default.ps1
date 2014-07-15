Task default -Depends ConvertToPng

Task ConvertToPng {
  if (Test-Path $env:ProgramFiles\Inkscape) {
    $inkscape = Join-Path $env:ProgramFiles "Inkscape\inkscape.com";
  }

  if (Test-Path ${env:ProgramFiles(x86)}\Inkscape) {
    $inkscape = Join-Path ${env:ProgramFiles(x86)} "Inkscape\inkscape.com";
  }

  if (!$inkscape) {
    throw "Inkscape could not be found in 'Program Files', aborting.";
  }

  $allSvgDocuments = Get-ChildItem -Path "$PSScriptRoot\icons" -Filter "*.svg";

  foreach ($svgDocument in $allSvgDocuments) {
    $inputDocument = $svgDocument.FullName;
    $outputDocument = "$PSScriptRoot\renders\$($svgDocument.BaseName).png";
    $inputParameter = "--file=$inputDocument";
    $outputParameter = "--export-png=$outputDocument";
    $additionalParameters = @("--export-area-page", "--export-background-opacity=0.0");

    & $inkscape $inputParameter $outputParameter $additionalParameters; 
  }
}