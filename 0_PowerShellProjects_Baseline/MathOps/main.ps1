param(
    [ValidateSet("Add","Sub","Mul","Div")]
    [string]$Op = "Add",
    [double]$A = 0,
    [double]$B = 0
)

switch ($Op) {
    "Add" { $r = $A + $B }
    "Sub" { $r = $A - $B }
    "Mul" { $r = $A * $B }
    "Div" {
        if ($B -eq 0) { Write-Error "Division by zero"; exit 1 }
        $r = $A / $B
    }
}

Write-Host "Result: $r"
