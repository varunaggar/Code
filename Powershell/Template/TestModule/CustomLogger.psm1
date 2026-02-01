function Test-CustomFunction {
    Write-Host "I am loaded from a path!" -ForegroundColor Magenta
}
Export-ModuleMember -Function Test-CustomFunction