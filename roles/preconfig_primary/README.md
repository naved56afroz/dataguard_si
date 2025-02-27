# Ansible Role: preconfig_primary 
 This role performs pre configuration at primary site for dataguard setup
## Requirements
None.

## Role Variables
Variables are defined at playbooks/vars/dataguard_vars.yml  
## Dependencies
dataguard_precheck

## Example Playbook

    - hosts: aix
      include_role:
        name: preconfig_primary

## Copyright
© Copyright IBM Corporation 2020
