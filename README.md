## NetBird: Zero Trust Network Solution

NetBird stands out as the premier Zero Trust Network Solution I've encountered. Find comprehensive details at NetBird.

## Client Installs


To streamline client installations, particularly for silent/unattended setups via MDM, I've assembled a collection of automation scripts for Mac, Linux, and Windows. In each client installation, simply customize the NetBird domain to match your custom Fully Qualified Domain Name (FQDN) and the NetBird port.

Our approach to installation ensures precise control over the version deployed on users' laptops. Here's what the script accomplishes:

1) Checks Installation: Verifies if NetBird is installed; if not, initiates the installation procedure.

2) Connection Verification: Ensures that the NetBird client isn't currently connected to avoid disrupting users' workflow.

3) Version Control: Compares the installed version against the specified "$required_version" to ensure the correct version is installed.

If the NetBird client isn't installed or isn't the correct version, the installation/upgrade process will commence.


## Windows Clients:

A known issue arises where running the netbird-ui.exe program multiple times results in numerous NetBird icons, leading to connectivity and authentication complications. To address this during the installation, we replace the NetBird icon with a PowerShell script. This script, when executed, checks if netbird-ui.exe is already running. If it's inactive, the script initiates netbird-ui.exe and triggers "netbird up" to promptly display the login page. If netbird-ui.exe is already active, the script opens the browser to begin the authentication process.


## NetBird Route Management Script

This script facilitates the modification of existing routes on NetBird. It checks whether NetBird already contains the specified route and adds it if it's absent.
