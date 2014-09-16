Task default -Depends Render

Task CreateRendersFolder -PreCondition { -Not (Test-Path "$PSScriptRoot\renders") } {
  New-Item -ItemType Container "$PSScriptRoot\renders";
}

Task DeleteRenders -Depends CreateRendersFolder { 
  Get-ChildItem -Path "$PSScriptRoot\renders" -Filter "*.png" | Remove-Item;
}

Task Render -Depends DeleteRenders {
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
    $outputName = $svgDocument.BaseName.ToLower().Replace(" ", "-").Replace("(", [String]::Empty).Replace(")", [String]::Empty);
    $outputDocument = "$PSScriptRoot\renders\$outputName.png";
    $inputParameter = "--file=$inputDocument";
    $outputParameter = "--export-png=$outputDocument";
    $additionalParameters = @("--export-area-page", "--export-background-opacity=0.0");
  
    Write-Host -ForegroundColor Magenta "Rendering $($svgDocument.BaseName)";
    & $inkscape $inputParameter $outputParameter $additionalParameters; 
  }
}
