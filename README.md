# Introduction

This repository contains a series of scripts that I've developed and utilised on my OPNsense installation to add to the base functionality of the system. The hope is that these scripts will eventually not be needed, and that the base functionality will be built into OPNsense or its plugins.

# Before you use them

The assumption is that this repository be cloned into `/opt/opnsense-scripts/` on your OPNsense instance.

Some scripts may have pre-requisite packages that have to be added to the base installation. They will list these requirements, and the commands to install these packages, within the comments at the top of the script file.

# Scripts
1. [Update Caddy Access List](#update-caddy-access-list)

## Update Caddy Access List
A script to be used in a CRON to regularly update an entry within a Caddy HTTP Access list. Intended to somewhat allow "Dynamic DNS" access.

To use (assumes you've followed [getting started](#getting-started)):
1. Create a HTTP Access List in Caddy and give it a name, make note of the name. This example will use the name "jellyfin-access".
2. Provide access for a "dummy" IP address. For this example we will use 8.8.8.8.
3. Create a file next to the `update-caddy-access-list.sh` called `update-caddy-access-list-old-ip`, and put the dummy IP address in it.
```bash
echo 8.8.8.8 > /opt/opnsense-scripts/update-caddy-access-list/update-caddy-access-list-old-ip
```
4. Do a trial run
```bash
root@fw:~ /usr/local/bin/bash /opt/opnsense-scripts/update-caddy-access-list/update-caddy-access-list.sh -ed some.domain.example -al some-access-list -key "some-key" -secret "some-secret" -url https://<your-opn-sense>/api
[INFO] Resolved some.domain.example to 123.123.123.123.
[INFO] Found old IP 8.8.8.8 in the access list.
[INFO] Found UUID for access list 'jellyfin-access': 4834b7...87b32.
[INFO] Successfully updated the access list: replaced 8.8.8.8 with 123.123.123.123.
```
5. Edit your crontab (with `crontab -e`) and add the following to run this every 5 minutes to keep your address up to date:
```bash
*/5 * * * * /usr/local/bin/bash /opt/opnsense-scripts/update-caddy-access-list/update-caddy-access-list.sh -ed some.domain.example -al some-access-list -key "some-key" -secret "some-secret" -url https://<your-opn-sense>/api
```


# Getting started
I suggest you install `git`
```
pkg install git
```
And that you make `vim` your default editor (exit and re-create your SSH session to take effect)
```
perl -pi -e 's/\s*setenv\s+EDITOR\s+vi\s*/setenv  EDITOR  vim\n/' ~/.cshrc
```
And then create `opt` and move there
```
mkdir /opt
cd /opt
```
And then clone these scripts
```
git clone https://github.com/JosephGarrone/opnsense-scripts
```