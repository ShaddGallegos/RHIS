minirhis-env role
=================

Purpose
-------

Load the per-user vaulted runtime configuration file located at
`$HOME/.ansible/conf/env.yml` into the play scope. This role is intentionally
minimal and safe to include at the start of playbooks that require runtime
secrets, hostnames, and network variables that must not be committed to the
repository.

Usage
-----

Add this role at the top of your play's `roles:` list or ensure the play has a
pre_task that includes the same `include_vars` call. The role uses
`include_vars` and will silently continue if the vaulted file is missing (use
`--reconfigure` to create it interactively).

Security
--------

Do not commit `~/.ansible/conf/env.yml` or any vault password files to git.
