$from = 'sender'
$to = 'recipient'
$subject = "Teste $(Get-Date)"
$body = $subject
$smtpserver = '<smtp_server>'
$port = 25

Send-MailMessage -From $from -To $to -Subject $subject -Body $body -SmtpServer $smtpserver -Port $port -Credential (Get-Credential)

# The IP Address must be included in the pool of allowed IP`s.
