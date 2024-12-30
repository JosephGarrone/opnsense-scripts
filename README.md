# Introduction

This repository contains a series of scripts that I've developed and utilised on my OPNsense installation to add to the base functionality of the system. The hope is that these scripts will eventually not be needed, and that the base functionality will be built into OPNsense or its plugins.

# Before you use them

The assumption is that this repository be cloned into `/opt/opnsense-scripts/` on your OPNsense instance.

Some scripts may have pre-requisite packages that have to be added to the base installation. They will list these requirements, and the commands to install these packages, within the comments at the top of the script file.

# Scripts

| Script | Description |
| ------ | ----------- |
| update-caddy-access-list | A script to be used in a CRON to regularly update an entry within a Caddy HTTP Access list. Intended to somewhat allow "Dynamic DNS" access.