Task default -Depends "Inspect Metadata", Render

Task CreateRendersFolder -PreCondition { -Not (Test-Path "$PSScriptRoot\renders") } {
  New-Item -ItemType Container "$PSScriptRoot\renders";
}

Task "Inspect Metadata" {
  $icons = Get-ChildItem "$PSScriptRoot\icons";
  $iconXml = $icons | Select-Object BaseName, Name, @{ Name="SVGDocument"; Expression={[xml](Get-Content $_.FullName);} };
  [bool]$hasFailed = $false;

  foreach ($icon in $iconXml) {
    try {
      $namespaceManager = New-Object System.Xml.XmlNamespaceManager -ArgumentList $icon.SVGDocument.NameTable;
      $icon.SVGDocument.SelectNodes('//namespace::*[not(. = ../../namespace::*)]') `
        | Where-Object { $_.LocalName -ne 'xmlns' } `
        | ForEach-Object { $namespaceManager.AddNamespace($_.LocalName, $_.Value) }
      $metadata = $icon.SVGDocument.SelectSingleNode('//svg:svg/svg:metadata/rdf:RDF/cc:work', $namespaceManager).RDF.cc;

      Write-Host -NoNewLine -ForegroundColor Green "  [SUCCESS] "
      Write-Host -ForegroundColor Yellow "$($icon.BaseName)";
  } catch {
      Write-Host -NoNewLine -ForegroundColor Red "  [FAILED ] "
      Write-Host -ForegroundColor Yellow "$($icon.BaseName)";
      Write-Host -ForegroundColor Red "    " + $_.ToString();
      $hasFailed = $true;
    }
  }

  if ($hasFailed) {
    throw "One or more files faile metadata validation, please review the logs and correct validation as required.";
  }
}

Task DeleteRenders -Depends CreateRendersFolder { 
  Get-ChildItem -Path "$PSScriptRoot\renders" -Filter "*.png" | Remove-Item;
}

Task Render -Depends "Inspect Metadata", DeleteRenders {
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
  
    Write-Host -ForegroundColor Magenta "  Rendering $($svgDocument.BaseName)";
    & $inkscape $inputParameter $outputParameter $additionalParameters; 
  }
}
