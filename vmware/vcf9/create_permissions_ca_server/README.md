# Prepare Microsoft CA for VMware Cloud Foundation 9.1

Use `Configure-VcfMicrosoftCA.ps1` on an **existing domain-joined enterprise issuing CA**, with CA Web Enrollment and IIS on that same server. This is the VCF 9.1 configuration requested in the linked documentation, separate from the earlier vRA 7 troubleshooting.

## Run

Copy the script to the CA. Open **Windows PowerShell 5.1 as administrator**. Use an administrator with delegated rights to create AD certificate templates/OIDs, edit their ACLs, administer this CA, and configure IIS.

Prerequisites:

- A healthy, configured enterprise CA. The script intentionally does not create a root CA, choose a PKI hierarchy, or reconfigure CA cryptography.
- An existing, enabled, dedicated AD user in the CA's domain, with Domain Users membership. Create that account using your normal identity provisioning process; do not grant it Domain Admins or local administrator membership.
- The `ActiveDirectory`, `ServerManager`, and `ADCSAdministration` PowerShell modules. If AD tools are missing, an administrator can install `RSAT-AD-PowerShell` with `Install-WindowsFeature`.
- A valid IIS HTTPS binding with a certificate/private key on the selected site. The certificate must cover the enrollment hostname; its issuing chain must be trusted by the VCF components. The script checks certificate dates/private key, but does not prove hostname matching, chain trust, or network reachability.
- A normal CA/AD recovery plan before changing production PKI.

Preview (no configuration changes):

```powershell
.\Configure-VcfMicrosoftCA.ps1 -ServiceAccount 'CONTOSO\svc-vcf-ca'
```

Apply, installing missing Web Enrollment/Basic Authentication/IIS management features if necessary:

```powershell
.\Configure-VcfMicrosoftCA.ps1 `
  -ServiceAccount 'CONTOSO\svc-vcf-ca' `
  -DomainController 'dc01.contoso.com' `
  -TemplateName 'VMwareVCF' `
  -TemplateDisplayName 'VMware VCF' `
  -InstallMissingWebRoles `
  -Apply
```

To apply and restart **CertSvc and the selected IIS site**, append `-RestartServices` during a maintenance window. Without it, the script saves configuration and reports the pending restarts. Restarting the IIS site interrupts other applications hosted on that site.

`-Apply -WhatIf` also produces a read-only preview. Preview requires the existing CA and AD modules; it is not an enrollment test. Rerunning with the same dedicated template name updates the script-owned template and increments its minor revision. An unrelated existing template is rejected; choose a new dedicated name.

## Changes

| Area | Script behavior |
|---|---|
| AD CS roles | Validates the configured enterprise CA; optionally installs missing Web Enrollment and web features, then configures local CA Web Enrollment when CertSrv is absent |
| IIS CertSrv | Enables Basic Authentication at this application; requires SSL and sets client certificates to Ignore; disables anonymous authentication |
| Other authentication | Leaves Windows Authentication as configured |
| Template | Creates a dedicated duplicate of the built-in WebServer configuration with a unique forest enterprise OID |
| Compatibility | Sets schema version 3 and the CA/client compatibility bits for Windows Server 2008 R2 / Windows 7 |
| Application policies | Removes Server Authentication from EKU/application policy attributes, as specified in the Broadcom article; preserves other source policies |
| Basic Constraints | Sets the end-entity Basic Constraints enrollment flag (CA=false); does not create a subordinate-CA template |
| Key usage | Adds nonrepudiation to the source key usage |
| Subject | Supply in the request |
| Template security | Gives the service user Read + Enroll, without Autoenroll or Write; removes explicit Enroll/Autoenroll grants for other principals from this dedicated template, preserving administrative ACLs |
| CA security | Sets this user's direct allow ACE to Issue and Manage Certificates + Request Certificates (mask 514), preserving other principals |
| Publication | Adds this template to the CA without replacing existing published templates |
| Backups | Saves CA security, available prior/source template metadata and template DACL, publication list, manifest, and IIS configuration backup before the relevant changes |

The HTTPS-only, anonymous-disabled settings and enrollment restriction to the dedicated user are protective additions to the linked procedure. Client Certificates=Ignore also matches Broadcom KB 452531.

Permissions granted through groups are not removed or evaluated as effective access. The service account must be dedicated and free of privileged group memberships. The CA officer permission is CA-wide under the default CA configuration; it is broader than requesting certificates from this one template. Administrative template ACLs are intentionally preserved. No global SAN policy flags, CA trust settings, firewall rules, passwords, or VCF appliance configuration are changed.

## Validate

1. Complete the pending CertSvc/site restarts. If role installation requires a reboot, reboot and rerun.
2. In `certtmpl.msc`, inspect the dedicated template's compatibility, Extensions, Subject Name and Security tabs.
3. In `certsrv.msc`, confirm the template is issued and inspect the service account's CA Security permissions.
4. In IIS Manager, inspect CertSrv Authentication and SSL Settings.
5. From the relevant VCF/Fleet/SDDC Manager appliance, test authenticated HTTPS using the service account. Let curl prompt for the password; do not put it on the command line:

   ```bash
   curl --basic --user 'svc-vcf-ca@contoso.com' --cacert /path/to/ca-chain.pem https://ca.contoso.com/certsrv/
   ```

   Use the trust chain appropriate to your environment. An authenticated page response tests access, not certificate issuance.
6. Configure the CA in VCF with URL `https://ca.contoso.com/certsrv` and **template internal name `VMwareVCF`**, not display name. Use the account format required by your VCF build.
7. Generate a test certificate through VCF and inspect the resulting subject, SAN, key usage, Basic Constraints, validity, chain and component-required EKUs. Confirm the template's policy behavior with an actual issued certificate before replacing production certificates.

The script verifies saved template attributes, Basic Authentication, CA security bytes, and template publication. It cannot establish successful authenticated enrollment or validate an issued certificate without the VCF environment.

AD template/OID objects are written to the selected writable domain controller. CA publication/enrollment may use another DC; allow replication if a newly created template is not immediately visible. On a replication-related failure, rerun after replication completes.

## Recovery / partial failure

The script stops on errors and reports its backup directory. **It does not automatically roll back completed steps.** Backups are restricted to local Administrators and SYSTEM and are normally under `C:\ProgramData\VCF-CA-Preparation\<timestamp>`.

These are configuration recovery aids, not a full CA database/private-key backup.

- IIS: read `iis-backup-name.txt`, then use `%windir%\System32\inetsrv\appcmd.exe restore backup <name>` during a maintenance window. This restores server-wide IIS configuration to that point, so review any intervening changes.
- CA account permissions: restore the binary value from `ca-security.bin` to the `Security` registry value at the path recorded in `manifest.json`, then restart CertSvc. Review concurrent permission changes before restoring.
- Publication: compare with `published-templates.xml`; remove only the newly added dedicated template using `Remove-CATemplate -Name VMwareVCF -Force` if it was absent before.
- New template/OID: the manifest records their DNs. After unpublishing and checking dependencies, a PKI administrator can remove the newly created objects. Do not remove an OID used by another template or a template with active dependencies.
- Existing script-owned template: `previous-template.xml` and `template-dacl.sddl` contain the pre-change metadata/ACL for administrator-led restoration. XML is a reference export, not a directly importable AD restore.
- Newly installed Windows features are not removed automatically. Web Enrollment initial configuration is also not automatically undone by the IIS backup.

## Sources reviewed

All five supplied pages were read in the browser after the text-fetch service returned access errors.

- [Preparation overview](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/fleet-management/certificate-management-9-0/configure-a-certificate-authority_9-0/prepare-your-certificate-authority-to-enable-sddc-manger-to-manage-certificates-9-0.html)
- [Install Microsoft CA roles](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/fleet-management/certificate-management-9-0/configure-a-certificate-authority_9-0/prepare-your-certificate-authority-to-enable-sddc-manger-to-manage-certificates-9-0/install-microsoft-certificate-authority-roles-9-0.html)
- [Basic Authentication](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/fleet-management/certificate-management-9-0/configure-a-certificate-authority_9-0/prepare-your-certificate-authority-to-enable-sddc-manger-to-manage-certificates-9-0/configure-the-microsoft-certificate-authority-for-basic-authentication_1.html)
- [Create and add template](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/fleet-management/certificate-management-9-0/configure-a-certificate-authority_9-0/prepare-your-certificate-authority-to-enable-sddc-manger-to-manage-certificates-9-0/create-and-add-a-microsoft-certificate-authority-template_9-0.html)
- [Service account privileges](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/fleet-management/certificate-management-9-0/configure-a-certificate-authority_9-0/prepare-your-certificate-authority-to-enable-sddc-manger-to-manage-certificates-9-0/assign-certificate-management-privileges-to-the-sddc-manager-service-account-9-0.html)
- [Broadcom KB 452531: Microsoft CA integration in VCF 9.1](https://knowledge.broadcom.com/external/article/452531/error-failed-to-update-certificate-autho.html)
- [Microsoft: Add-CATemplate](https://learn.microsoft.com/en-us/powershell/module/adcsadministration/add-catemplate)
- [Microsoft: Install-AdcsWebEnrollment](https://learn.microsoft.com/en-us/powershell/module/adcsdeployment/install-adcswebenrollment)
- [Microsoft: Basic Constraints enrollment flag](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/ec71fd43-61c2-407b-83c9-b52272dec8a1)
- [Microsoft: CA access masks](https://learn.microsoft.com/en-us/windows/win32/api/certadm/nf-certadm-icertadmin2-getmyroles)

## Verification performed here

PowerShell parsing passed. In-memory checks passed for preserving other CA ACL entries, assigning mask 514, repeat application without duplicate ACEs, rejecting a service-account deny ACE, key usage bit manipulation, and optional/binary AD attribute handling.

No CA, IIS, AD object, or certificate was modified in this workspace. Full Windows Server/AD CS/VCF integration testing remains required.

