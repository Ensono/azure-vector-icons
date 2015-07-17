Task default -Depends "Inspect Metadata", Render
Task full -Depends "Inspect Metadata", OptimizeVectors, DeleteRenders, Render, OptimizeRenders, UpdateReadme

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
      $metadata = $icon.SVGDocument.SelectSingleNode('//svg/metadata/rdf:RDF/cc:work', $namespaceManager).RDF.cc;

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
  $inkscape = Join-Path $env:ProgramFiles "Inkscape\inkscape.com";

  if (!$inkscape) {
    throw "Inkscape could not be found in 'Program Files', aborting.";
  }

  foreach ($icon in Get-Icons) {
    $inputDocument = $icon.FullName;
    $outputName = $icon.Identifier;
    $outputDocument = "$PSScriptRoot\renders\$outputName.png";

    if (Test-Path $outputDocument) {
      Write-Host -ForegroundColor Yellow "  Not Re-rendering $($icon.Title), it already exists.";
      continue;
    }

    $inputParameter = "--file=$inputDocument";
    $outputParameter = "--export-png=$outputDocument";
    $additionalParameters = @("--export-area-page", "--export-background-opacity=0.0");
  
    Write-Host -ForegroundColor Magenta "  Rendering $($icon.Title)";
    & $inkscape $inputParameter $outputParameter $additionalParameters | Write-Verbose; 
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
  $svgoParams = @("$PSScriptRoot\tools\node_modules\svgo\bin\svgo", "--disable=removeMetadata", "--disable=convertPathData", "--pretty");

  foreach ($icon in Get-Icons) {
    Write-Host -ForegroundColor Magenta "  Optimizing $($icon.Title)";
    $outputName = "$PSScriptRoot\icons\$($icon.Title)-opt.svg";
    & node $svgoParams --input $($icon.FullName) --output $outputName | Write-Verbose;

    if (Test-Path $outputName) {
      $optimizedSvg = Get-ChildItem $outputName;
      $saving = 100 - ([Math]::Round(($optimizedSvg.Length / $icon.Length) * 100, 2) );
      Write-Host -ForegroundColor Yellow "    SVG Optimization Saved $($saving)%";
      Remove-Item $icon.FullName;
      Move-Item $outputName $icon.FullName;
    }
  }
}

Task UpdateReadme -Depends "Inspect Metadata" {
  $categories = Get-Icons | Group-Object -Property "Category" | Sort-Object -Property Name;

  $readmeFile = "$PSScriptRoot\README.md";
  Copy-Item "$PSScriptRoot\README.template.md" $readmeFile;

  foreach ($category in $categories) {
    Add-Content $readmeFile $category.Name.Trim();
    Add-Content $readmeFile (New-Object System.String -ArgumentList "-", $category.Name.Length);
    Add-Content $readmeFile "";
    Add-Content $readmeFile "| Icon | Title |";
    Add-Content $readmeFile "|:---- |:----- |";
    foreach ($icon in $category.Group) {
      Add-Content $readmeFile "| ![$($icon.Title)](renders/$($icon.Identifier).png) | $($icon.Title) |";
    }
    Add-Content $readmeFile "";
  }
}

function Get-Icons {
  Get-ChildItem "$PSScriptRoot\icons" `
    | Select-Object FullName, BaseName, Name, Length, @{ Name="Content"; Expression={[xml](Get-Content $_.FullName);} } `
    | Select-Object FullName, BaseName, Name, Length, Content, @{ Name="Metadata"; Expression={ $_.Content.svg.metadata.rdf.Work } } `
    | Select-Object FullName, BaseName, Name, Length, `
        @{ Name="Category"; Expression={ $_.Metadata.subject.Trim() } }, `
        @{ Name="Title"; Expression={ $_.Metadata.title.Trim() } }, `
        @{ Name="Identifier"; Expression={ $_.Metadata.identifier.Trim() } };
}