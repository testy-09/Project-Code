# Path to your CSV file
$csvPath = "C:\Path\To\Your\File.csv"

# Import the CSV
$rows = Import-Csv -Path $csvPath

# Loop through each row and print the Name column
foreach ($row in $rows) {
    Write-Host $row.Name
}
