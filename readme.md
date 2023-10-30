# Coding examples.

This repository is to provide the viewer examples of the code I have written. Below is a synopsis of each script here, what it is meant to do, and any additional details for each.

# Powershell
## Server_Deployment.ps1

This script was designed to automate deployment of VMware virtual servers. It does the following.
1. Connects to the specified VCenter server, prompting the user for credentials.
2. It then prompts the user for various pieces of information about the new server. Some prompts have pre-selected options, while others the user simply types in the information. The first 7 items listed stored this information within a custom attribute in VCenter, as well as some options determining available choices later in the process.
   - PROD/DEV/QA/TEST
   - Business division.
   - VM notes field.
   - Server owner.
	   - Who requested the server and/or is in charge of the server.
   - Server function.
	   - File, Web, etc.
   - Creator.
	   - This was intended to log within VCenter who built the server.
   - Ticket number.
   - Domain to build server in.
	   - For example, a DMZ domain and an internal domain.
   - Operating system.
	   - This is what selects the specific template.
   - Server name.
   - VM network.
	   - This portion pulls all the available networks from VCenter and presents a list of those options.
   - Backup type.
	   - Backups were controlled by which folder the VM resides in. This allowed the script to drop the VM in the correct location so that backups were automatically started as soon as it was created.
   - Datastore.
	   - Like the VM network, it pulls available datastores and presents a list of those options. Additionally, PROD and DEV had different options, so if a server was destined for PROD it would only show the PROD specific datastores.
   - CPU core count.
   - CPU socket count.
	   - This was adjusted to always have half as many sockets as cores for the environment this script was built for.
   - Memory.
	   - This gave the user options in 2GB increments from 6-16 GB. Easily expandable, however servers in this environment very rarely went past 16.
   - WSUS update group.
3. The script then displays a popup for the user to double-check everything is correct, with a warning indicating any changes will need to be done manually if they continue. Cancelling would end the script and would need to start over.
4. Should the user confirm to continue, the script then begins the process of deploying the new virtual machine from the template. At the time of writing, there were 3 template options, however 2 were being phased out so did not get included. The customization specification was chosen by the doman selection above, as a seperate specification was configured for each domain.

Here is where the script ends. Fully functional as-is, however there were goals to also automate the Microsoft side of things, such as:

 - Renaming the local admin account, and setting a password.
 - Disable the guest account.
 - Create RDP and Admin AD groups.
 - Disable non-essential Windows services.
 - Place computer account in appropiate AD groups and OUs.
 - Deploy the appropiate server roles and features.
 - Automate running the IISCRYPTO tool.
