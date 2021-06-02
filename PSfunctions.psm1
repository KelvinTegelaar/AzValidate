function New-MFARequest {
    param (
        [string]$EmailToPush
    )

    ######### Secrets #########
    $ApplicationId = $ENV:ApplicationID
    $ApplicationSecret = $ENV:ApplicationSecret
    $RefreshToken = $ENV:Refreshtoken
    $Genpass = $ENV:GeneratedPassword
    ######### Secrets #########
    write-host "Creating credentials and tokens." -ForegroundColor Green
    $credential = New-Object System.Management.Automation.PSCredential($ApplicationId, ($ApplicationSecret | Convertto-SecureString -AsPlainText -Force))
    $aadGraphToken = New-PartnerAccessToken -ApplicationId $ApplicationId -Credential $credential -RefreshToken $refreshToken -Scopes 'https://graph.windows.net/.default' -ServicePrincipal
    $graphToken = New-PartnerAccessToken -ApplicationId $ApplicationId -Credential $credential -RefreshToken $refreshToken -Scopes 'https://graph.microsoft.com/.default' -ServicePrincipal
    write-host "Connecting to MSOL" -ForegroundColor Green

    Connect-MsolService -AdGraphAccessToken $aadGraphToken.AccessToken -MsGraphAccessToken $graphToken.AccessToken
    $UserTenantName = $EmailToPush -split '@' | Select-Object -last 1
    $UserTenantGUID = (Invoke-WebRequest "https://login.windows.net/$UserTenantName/.well-known/openid-configuration" | ConvertFrom-Json).token_endpoint.Split('/')[3] 
    $MFAAppID = '981f26a1-7f43-403b-a875-f8b09b8cd720'
    write-host "Setting temporary password" -ForegroundColor Green
    New-MsolServicePrincipalCredential -TenantId $UserTenantGUID -AppPrincipalId $MFAAppID -Type password -Usage verify -Value $GenPass -Verbose
    $UPNToPush = (Get-MSOLUser -TenantId $UserTenantGUID  | Where {$_.ProxyAddresses -like "smtp:$EmailToPush"}).UserPrincipalName
    write-host "Generating XML" -ForegroundColor Green

    $XML = @"
<BeginTwoWayAuthenticationRequest>
<Version>1.0</Version>
<UserPrincipalName>$UPNToPush</UserPrincipalName>
<Lcid>en-us</Lcid><AuthenticationMethodProperties xmlns:a="http://schemas.microsoft.com/2003/10/Serialization/Arrays"><a:KeyValueOfstringstring><a:Key>OverrideVoiceOtp</a:Key><a:Value>false</a:Value></a:KeyValueOfstringstring></AuthenticationMethodProperties><ContextId>69ff05bf-eb61-47f7-a70e-e7d77b6d47d0</ContextId>
<SyncCall>true</SyncCall><RequireUserMatch>true</RequireUserMatch><CallerName>radius</CallerName><CallerIP>UNKNOWN:</CallerIP></BeginTwoWayAuthenticationRequest>
"@

    $body = @{
        'resource'      = 'https://adnotifications.windowsazure.com/StrongAuthenticationService.svc/Connector'
        'client_id'     = $MFAAppID
        'client_secret' = $Genpass
        'grant_type'    = "client_credentials"
        'scope'         = "openid"
    }

    $ClientToken = Invoke-RestMethod -Method post -Uri "https://login.microsoftonline.com/$UserTenantGUID/oauth2/token" -Body $body
    $headers = @{ "Authorization" = "Bearer $($ClientToken.access_token)" }
    write-host "Generating MFA Request" -ForegroundColor Green

    $obj = Invoke-RestMethod -uri 'https://adnotifications.windowsazure.com/StrongAuthenticationService.svc/Connector//BeginTwoWayAuthentication' -Method POST -Headers $Headers -Body $XML -ContentType 'application/xml'

    if ($obj.BeginTwoWayAuthenticationResponse.AuthenticationResult -ne $true) {
        return "Authentication failed. does the user have Push/Phone call MFA configured? Errorcode: $($obj.BeginTwoWayAuthenticationResponse.result.value | out-string)"
    }
    if ($obj.BeginTwoWayAuthenticationResponse.result) {
        return "Received a MFA confirmation: $($obj.BeginTwoWayAuthenticationResponse.result.value | Out-String)"
    }
}
