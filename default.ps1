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

Task Render -Depends "Inspect Metadata" {
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

    if (Test-Path $outputDocument) {
      Write-Host -ForegroundColor Yellow "  Not Re-rendering $($svgDocument.BaseName), it already exists.";
      continue;
    }

    $inputParameter = "--file=$inputDocument";
    $outputParameter = "--export-png=$outputDocument";
    $additionalParameters = @("--export-area-page", "--export-background-opacity=0.0");
  
    Write-Host -ForegroundColor Magenta "  Rendering $($svgDocument.BaseName)";
    & $inkscape $inputParameter $outputParameter $additionalParameters; 
  }
}

Task OptimizeRenders {
  $pngquant = Resolve-Path "$PSScriptRoot\tools\pngquant.exe";
  $deflopt = Resolve-Path "$PSScriptRoot\tools\DeflOpt.exe";
  $optipng = Resolve-Path "$PSScriptRoot\tools\optipng.exe";
  $pngout = Resolve-Path "$PSScriptRoot\tools\pngout.exe";

  $pngquantParms = @("256", "--force");
  $optipngParams = @("-o7", "-quiet");
  $pngoutParams = @("/y", "/d0", "/s0", "/mincodes0", "/q");
  $defloptParams = @("/s");

  $allRenders = Get-ChildItem -Path "$PSScriptRoot\renders" -Filter "*.png";
  foreach ($render in $allRenders | Where-Object { -Not $_.FullName.EndsWith("-fs8.png") }) {
    Write-Host -ForegroundColor Magenta "  Optimizing $($render.BaseName)";
    $outputName = "$PSScriptRoot\renders\$($render.BaseName)-fs8.png";

    & $pngquant $pngquantParms $render.FullName;

    if (Test-Path $outputName) {
      $quantImage = Get-ChildItem $outputName;
      $saving = 100 - ([Math]::Round(($quantImage.Length / $render.Length) * 100, 2) );
      Write-Host -ForegroundColor Yellow "    PNG Quantizeation Saved $($saving)%";

      & $optipng $optipngParams $outputName;
      $optipngImage = Get-ChildItem $outputName;
      $saving = 100 - ([Math]::Round(($optipngImage.Length / $render.Length) * 100, 2) );
      Write-Host -ForegroundColor Yellow "    PNG Optimization Saved $($saving)%";

      & $pngout $pngoutParams $outputName;
      $pngoutImage = Get-ChildItem $outputName;
      $saving = 100 - ([Math]::Round(($pngoutImage.Length / $render.Length) * 100, 2) );
      Write-Host -ForegroundColor Yellow "    PNG Out Saved $($saving)%";

      & $deflopt $defloptParams $outputName | Out-Null;
      $defloptImage = Get-ChildItem $outputName;
      $saving = 100 - ([Math]::Round(($defloptImage.Length / $render.Length) * 100, 2) );
      Write-Host -ForegroundColor Yellow "    Deflate Optimization Saved $($saving)%";

      if ($saving -gt 0) {
        Remove-Item $render.FullName;

        Move-Item $outputName $render.FullName;
      } else {
        Remove-Item $outputName;
      }
    }
  } 
}

Task InstallSVGO -PreCondition { (Get-Command npm -ErrorAction Ignore) -And -Not (Test-Path .\tools\node_modules\svgo) } {
  Push-Location "$PSScriptRoot\tools";
  & npm install svgo;
  Pop-Loction;
}

Task OptimizeVectors -Depends InstallSVGO -PreCondition { (Get-Command npm -ErrorAction Ignore) -And (Test-Path .\tools\node_modules\svgo) } {
  $allSvgDocuments = Get-ChildItem -Path "$PSScriptRoot\icons" -Filter "*.svg";

  foreach ($svgDocument in $allSvgDocuments) {
    & node "$PSScriptRoot\tools\node_modules\svgo\bin\svgo" --disable=Metadata -i $svgDocument.FullName;
  }
}