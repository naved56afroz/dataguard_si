# Ansible Role: preconfig_standby 
 This role performs pre configuration at standby site for dataguard setup
## Requirements
None.

## Role Variables
Variables are defined at playbooks/vars/dataguard_vars.yml  
## Dependencies
dataguard_precheck

## Example Playbook

    - hosts: aix
      include_role:
        name: preconfig_standby

## Copyright
© Copyright IBM Corporation 2020
