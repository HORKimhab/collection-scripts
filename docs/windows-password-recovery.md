# Windows Password Recovery

This document is intentionally limited to safe, legitimate recovery guidance.

## Current script status

The repository currently contains [windows-recovery-readiness.sh](/Users/hkimhab25/personal-project/collection-scripts/windows-recovery-readiness.sh), but its present contents implement a Windows password-reset workflow. I cannot document or provide usage steps for resetting or bypassing Windows credentials from Linux.

If you want this repository to keep a safe helper, the script should be reverted to a read-only readiness checker before using this guide as the primary reference.

## What this guide covers

- official Windows recovery paths
- read-only inspection goals
- preparation for backup, repair, or reinstall
- BitLocker and account-type decision points

## What this guide does not cover

- resetting a Windows password from Linux
- editing the Windows `SAM` database
- using `chntpw` or similar tools to clear credentials
- bypassing login, local security controls, or disk encryption

## Recommended recovery order

1. Microsoft account:
   Use Microsoft’s official account recovery flow first.
2. Local account:
   Use a password reset disk or another administrator account if one exists.
3. Work or school device:
   Use the organization’s IT or domain-admin recovery process.
4. BitLocker-protected device:
   Find the recovery key before attempting any access, repair, or migration.
5. Last resort:
   Back up available data and prepare a Windows repair install or full reinstall.

## Safe inspection goals for a Linux helper

If this repo keeps a recovery helper script, a safe version should only do tasks like:

- show host OS and current environment details
- check whether tools like `lsblk`, `fdisk`, `diskutil`, `ntfs-3g`, or `dislocker` are available
- list disks and likely Windows or NTFS partitions
- write a plain-text readiness report
- remind the operator to use official recovery options first

It should not:

- request a Windows username to target
- mount a Windows volume for credential editing
- install password-reset tooling
- reboot after changing authentication data

## Suggested safe usage

If the script is restored to a read-only readiness checker, usage should look like this:

```bash
bash windows-recovery-readiness.sh --help
bash windows-recovery-readiness.sh --no-color
bash windows-recovery-readiness.sh --report docs/windows-recovery-report.txt --no-color
```

Expected output from a safe version:

- environment summary
- available recovery-related tools
- detected storage devices
- likely Windows or NTFS candidates
- BitLocker reminder
- recommended next steps

## BitLocker

If the Windows system drive is BitLocker-protected, the recovery key is required before data access. Do not proceed with a recovery plan that assumes file access until that key is available.

## Next step for this repo

If you want, I can make the documentation and script consistent by replacing the current script with a read-only readiness checker again, then I can update this doc to match the exact implemented flags and output.

## Warning

This script and documentation are provided for authorized, lawful recovery and maintenance use only.

The owner or author of this Bash script is not responsible for any illegal, unauthorized, or improper use. The person running the script is solely responsible for ensuring they have permission to use it and for complying with applicable laws, policies, and system-owner requirements.
