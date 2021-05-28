using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

if (-not [string]::IsNullOrEmpty($ENV:Logo)) {
  $Logo = "<img src=`"$($ENV:Logo)`" alt=`"Logo`">"
}
else {
  $Logo = ""
}

$Username = $Request.Query.username
if (!$Username){
$Username = ([System.Web.HttpUtility]::ParseQueryString($Request.Body))['username']
}

if ($Username) {
  import-module .\PSfunctions.psm1
  import-module MSOnline -UseWindowsPowerShell
  $MFARequest = New-MFARequest -EmailToPush $Username
  $RequestText = @"
$MFARequest
"@
}
else {
  $RequestText = @"
  <form action="create" method="POST">
    <label for="Username">Username</label><br>
    <input type="text" name="username" id="username" value="user@user.com"><br>
    Use the Create button below to generate a MFA push towards the user.<br>
    <input class="button" name="Submit" type="submit" value="Create">
  </form>
"@
}

# Interact with query parameters or the body of the request.
$Body = @"
<!DOCTYPE html>
<html>
<style>
input, select {
  width: 70%;
  padding: 12px 20px;
  margin: 8px 0;
  display: inline-block;
  border: 1px solid #ccc;
  border-radius: 4px;
  box-sizing: border-box;
}

.button {
  width: 25%;
  background-color: #4CAF50;
  color: white;
  padding: 14px 20px;
  margin: 8px 0;
  border: none;
  border-radius: 20px;
  cursor: pointer;
}

.button:hover {
  background-color: #45a049;
  width: 25%
}
.divider{
  width:5px;
  height:auto;
}
div {
  border-radius: 5px;
  background-color: #f2f2f2;
  padding: 20px;
  width: 40%
}
</style>
<body>
<center>
$($Logo)
<title>Identity Confirmation Portal</Title>
<h3>Confirm an identity by sending a MFA request.</h3>

<div>
$RequestText
</div>
  </center>
</body>
</html>
"@

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode  = [HttpStatusCode]::OK
    Body        = $Body
    ContentType = 'text/html'
  })
