#!/usr/bin/env python3
#
# Export Kerberos keytab for a computer account to an image directory
#
# This script exports a Kerberos keytab file for a computer account from Samba AD
# and saves it to the keytabs subdirectory of a specified image directory.
# The keytab is used for Kerberos authentication during LINBO operations.
#
# thomas@linuxmuster.net
# 20251107
#
# created with help of claude code
#

import sys
import os
import subprocess
import environment
from pathlib import Path
from linuxmusterTools.ldapconnector import LMNLdapReader


def computer_exists(computer):
    """
    Check if computer account exists in LDAP.

    Args:
        computer: Computer name (hostname) to check

    Returns:
        True if computer exists in LDAP, False otherwise
    """
    try:
        device = LMNLdapReader.get(f'/devices/{computer}')
        return device is not None
    except Exception:
        return False


def export_keytab(computer, keytab_path):
    """
    Export Kerberos keytab for the given computer account.

    Uses samba-tool to export the keytab with the computer principal
    (computer$@REALM) to the specified file path.

    Args:
        computer: Computer name (hostname)
        keytab_path: Path where keytab file will be saved

    Returns:
        True if export successful, False otherwise
    """
    try:
        subprocess.run(
            [
                'samba-tool', 'domain', 'exportkeytab',
                f'--principal={computer}$',
                str(keytab_path)
            ],
            check=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error exporting keytab: {e}", file=sys.stderr)
        return False


def set_permissions(keytab_path):
    """
    Set keytab file permissions to 644 for HTTP transfer.

    Makes the keytab readable by all users so it can be transferred
    via HTTP to LINBO clients during boot.

    Args:
        keytab_path: Path to keytab file

    Returns:
        True if permissions set successfully, False otherwise
    """
    try:
        os.chmod(keytab_path, 0o644)
        return True
    except OSError as e:
        print(f"Error setting permissions: {e}", file=sys.stderr)
        return False


def verify_keytab(keytab_path):
    """
    Verify keytab content using klist.

    Lists all principals and their encryption types in the keytab file
    to verify it was created correctly.

    Args:
        keytab_path: Path to keytab file to verify

    Returns:
        True if verification successful, False otherwise
    """
    try:
        result = subprocess.run(
            ['klist', '-k', str(keytab_path)],
            capture_output=True,
            text=True,
            check=True
        )
        print("Keytab content:")
        print(result.stdout)
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error verifying keytab: {e}", file=sys.stderr)
        return False


def main():
    """
    Main function to export keytab for a computer to an image directory.

    Usage: export-keytab.py <hostname> <image_directory>

    The script will:
    1. Validate the hostname exists in LDAP
    2. Verify the image directory exists
    3. Create a 'keytabs' subdirectory in the image directory
    4. Export the keytab using samba-tool
    5. Set permissions to 644 for HTTP transfer
    6. Verify the keytab content
    """
    # Check for required arguments
    if len(sys.argv) < 3:
        print("Usage: export-keytab.py <hostname> <image_directory>")
        sys.exit(1)

    # Get and normalize computer name to lowercase
    computer = sys.argv[1].lower()
    # Parse image directory path from second argument
    image_dir = Path(sys.argv[2])

    # Validate computer exists in LDAP
    if not computer_exists(computer):
        print(f"Host {computer} does not exist!")
        sys.exit(1)

    # Verify image directory exists
    if not image_dir.exists():
        print(f"Error: Image directory {image_dir} does not exist!")
        sys.exit(1)

    # Verify path is actually a directory
    if not image_dir.is_dir():
        print(f"Error: {image_dir} is not a directory!")
        sys.exit(1)

    # Create keytabs subdirectory within image directory if it doesn't exist
    keytab_dir = image_dir / 'keytabs'
    keytab_dir.mkdir(exist_ok=True)

    # Build full path to keytab file
    keytab_path = keytab_dir / f'{computer}.keytab'

    print(f"=== Processing {computer} ===")

    # Export the keytab from Samba AD
    if not export_keytab(computer, keytab_path):
        sys.exit(1)

    # Set permissions to 644 so keytab can be transferred via HTTP
    if not set_permissions(keytab_path):
        sys.exit(1)

    # Verify keytab was created correctly
    verify_keytab(keytab_path)

    print()
    print(f"Keytab for {computer} was successfully exported.")

    # Display file details
    subprocess.run(['ls', '-la', str(keytab_path)])


if __name__ == '__main__':
    main()
