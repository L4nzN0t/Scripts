$from = 'sender'
$to = 'recipient'
$subject = "Teste $(Get-Date)"
$body = $subject
$smtpserver = '<smtp_server>'
$port = 587

Send-MailMessage -From $from -To $to -Subject $subject -Body $body -Credential (Get-Credential) -SmtpServer $smtpserver365 -Port $port -UseSsl

# To sent a authenticated mail, the mailbox must be delegated to send on behalf of themselves or other mailboxes.