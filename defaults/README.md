# RHIS local defaults/env.yml variable guide

This file documents variables in defaults/env.yml for standalone project use.

- Keep defaults/env.yml encrypted with ansible-vault.
- Vault password file is expected at ~/.ansible/conf/.defaults_env.vaultpass.txt by default.

## Variables

| Variable | Synopsis | More info |
|---|---|---|
| aap_admin_password | Enter value for rhis aap admin password (RHIS) | See project checklist |
| aap_admin_user | Enter value for rhis aap admin user (RHIS) | See project checklist |
| aap_bundle_dir | Enter value for rhis aap bundle dir (RHIS) | See project checklist |
| aap_bundle_search_paths | Enter value for rhis aap bundle search paths (RHIS) | See project checklist |
| aap_controller_image | Enter value for rhis aap controller image (RHIS) | See project checklist |
| aap_controller_volumes | Enter value for rhis aap controller volumes (RHIS) | See project checklist |
| aap_extract_dir | Enter value for rhis aap extract dir (RHIS) | See project checklist |
| aap_extract_prereqs | Enter value for rhis aap extract prereqs (RHIS) | See project checklist |
| aap_gateway_host | Enter value for rhis aap gateway host (RHIS) | See project checklist |
| aap_gateway_mode | Enter value for rhis aap gateway mode (RHIS) | See project checklist |
| aap_gateway_url | Enter value for rhis aap gateway url (RHIS) | See project checklist |
| aap_http_log | Enter value for rhis aap http log (RHIS) | See project checklist |
| aap_single_host_mode | Enter value for rhis aap single host mode (RHIS) | See project checklist |
| aap_topology | Enter value for rhis aap topology (RHIS) | See project checklist |
| acm_nginx_conf_file | Enter value for rhis acm nginx conf file (RHIS) | See project checklist |
| admin_pass | Enter value for rhis admin pass (RHIS) | See project checklist |
| ansible_become | Enter value for rhis ansible become (RHIS) | See project checklist |
| ansible_become_password | - The canonical vault path is `~/.ansible/conf/env.yml` and the vault password is read from `~/.ansible/conf/.vaultpass.txt` by default. | See project checklist |
| ansible_connection | Enter value for rhis ansible connection (RHIS) | See project checklist |
| ansible_password | - The canonical vault path is `~/.ansible/conf/env.yml` and the vault password is read from `~/.ansible/conf/.vaultpass.txt` by default. | See project checklist |
| ansible_ssh_private_key_file | Enter value for rhis ansible ssh private key file (RHIS) | See project checklist |
| ansible_user | Enter value for rhis ansible user (RHIS) | See project checklist |
| auth_debug_default_debug_level | Enter value for rhis auth debug default debug level (RHIS) | See project checklist |
| auth_debug_default_normal_level | Enter value for rhis auth debug default normal level (RHIS) | See project checklist |
| auth_debug_global_persistence | Enter value for rhis auth debug global persistence (RHIS) | See project checklist |
| auth_debug_global_state | Enter value for rhis auth debug global state (RHIS) | See project checklist |
| auth_debug_sssd_modules | Enter value for rhis auth debug sssd modules (RHIS) | See project checklist |
| auto_up_disable | Enter value for rhis auto up disable (RHIS) | See project checklist |
| base_packages | Enter value for rhis base packages (RHIS) | See project checklist |
| bootstrap_services | Enter value for rhis bootstrap services (RHIS) | See project checklist |
| builder_default_user | Enter value for rhis builder default user (RHIS) | See project checklist |
| cockpit_all | Enter value for rhis cockpit all (RHIS) | See project checklist |
| cockpit_composer | Enter value for rhis cockpit composer (RHIS) | See project checklist |
| cockpit_dashboard | Enter value for rhis cockpit dashboard (RHIS) | See project checklist |
| cockpit_leapp | Enter value for rhis cockpit leapp (RHIS) | See project checklist |
| cockpit_machines | Enter value for rhis cockpit machines (RHIS) | See project checklist |
| cockpit_pcp | Enter value for rhis cockpit pcp (RHIS) | See project checklist |
| cockpit_podman | Enter value for rhis cockpit podman (RHIS) | See project checklist |
| cockpit_session_recording | Enter value for rhis cockpit session recording (RHIS) | See project checklist |
| container_user | Enter value for rhis container user (RHIS) | See project checklist |
| core_update_level | Enter value for rhis core update level (RHIS) | See project checklist |
| crun_pkg | Enter value for rhis crun pkg (RHIS) | See project checklist |
| datacenter_folder | Enter value for rhis datacenter folder (RHIS) | See project checklist |
| datacenter_name | Enter value for rhis datacenter name (RHIS) | See project checklist |
| default_osbuild_repo_dir | Enter value for rhis default osbuild repo dir (RHIS) | See project checklist |
| enable_cockpit | Enter value for rhis enable cockpit (RHIS) | See project checklist |
| ensure_httpd | Enter value for rhis ensure httpd (RHIS) | See project checklist |
| ensure_insights | Enter value for rhis ensure insights (RHIS) | See project checklist |
| epel10_rpms_repo_name | Enter value for rhis epel10 rpms repo name (RHIS) | See project checklist |
| epel10_streams_repo_name | Enter value for rhis epel10 streams repo name (RHIS) | See project checklist |
| epel8_rpms_repo_name | Enter value for rhis epel8 rpms repo name (RHIS) | See project checklist |
| epel8_streams_repo_name | Enter value for rhis epel8 streams repo name (RHIS) | See project checklist |
| epel9_rpms_repo_name | Enter value for rhis epel9 rpms repo name (RHIS) | See project checklist |
| epel9_streams_repo_name | Enter value for rhis epel9 streams repo name (RHIS) | See project checklist |
| firewalld_zone | Enter value for rhis firewalld zone (RHIS) | See project checklist |
| gitea_admin_email | Enter value for rhis gitea admin email (RHIS) | https://docs.gitea.com/ |
| gitea_admin_pass | Enter value for rhis gitea admin pass (RHIS) | https://docs.gitea.com/ |
| gitea_admin_user | - `GITTEA_ADMIN_TOKEN`: Personal access token for Gitea — generate in your Gitea instance under `Settings -> Applications` or `Settings -> Access Tokens` (e.g. https://<gittea_host>/user/settings/applications). | https://<gittea_host>/user/settings/applications |
| gitea_binary_path | Enter value for rhis gitea binary path (RHIS) | https://docs.gitea.com/ |
| gitea_binary_url | Enter value for rhis gitea binary url (RHIS) | https://docs.gitea.com/ |
| gitea_build_dir | Enter value for rhis gitea build dir (RHIS) | https://docs.gitea.com/ |
| gitea_enable_firewall | Enter value for rhis gitea enable firewall (RHIS) | https://docs.gitea.com/ |
| gitea_enable_nginx | Enter value for rhis gitea enable nginx (RHIS) | https://docs.gitea.com/ |
| gitea_group | Enter value for rhis gitea group (RHIS) | https://docs.gitea.com/ |
| gitea_home | Enter value for rhis gitea home (RHIS) | https://docs.gitea.com/ |
| gitea_install_method | Enter value for rhis gitea install method (RHIS) | https://docs.gitea.com/ |
| gitea_lets_encrypt_email | Enter value for rhis gitea lets encrypt email (RHIS) | https://docs.gitea.com/ |
| gitea_nginx_http_port | Enter value for rhis gitea nginx http port (RHIS) | https://docs.gitea.com/ |
| gitea_nginx_lets_encrypt | Enter value for rhis gitea nginx lets encrypt (RHIS) | https://docs.gitea.com/ |
| gitea_nginx_ssl_cert | Enter value for rhis gitea nginx ssl cert (RHIS) | https://docs.gitea.com/ |
| gitea_nginx_ssl_key | Enter value for rhis gitea nginx ssl key (RHIS) | https://docs.gitea.com/ |
| gitea_nginx_use_ssl | Enter value for rhis gitea nginx use ssl (RHIS) | https://docs.gitea.com/ |
| gitea_port | Enter value for rhis gitea port (RHIS) | https://docs.gitea.com/ |
| gitea_repo_url | Enter value for rhis gitea repo url (RHIS) | https://docs.gitea.com/ |
| gitea_rpm_url | Enter value for rhis gitea rpm url (RHIS) | https://docs.gitea.com/ |
| gitea_ssh_port | Enter value for rhis gitea ssh port (RHIS) | https://docs.gitea.com/ |
| gitea_user | - `GITTEA_ADMIN_TOKEN`: Personal access token for Gitea — generate in your Gitea instance under `Settings -> Applications` or `Settings -> Access Tokens` (e.g. https://<gittea_host>/user/settings/applications). | https://<gittea_host>/user/settings/applications |
| gitea_version | Enter value for rhis gitea version (RHIS) | https://docs.gitea.com/ |
| grafana_port | Enter value for rhis grafana port (RHIS) | https://grafana.com/docs/grafana/latest/ |
| guestmount_bin | Enter value for rhis guestmount bin (RHIS) | See project checklist |
| host_int_ip | Enter value for rhis host int ip (RHIS) | See project checklist |
| host_list | Enter value for rhis host list (RHIS) | See project checklist |
| host_port | Enter value for rhis host port (RHIS) | See project checklist |
| httpd_port | Enter value for rhis httpd port (RHIS) | See project checklist |
| idm_domain | Enter value for rhis idm domain (RHIS) | See project checklist |
| idm_password_policies | Enter value for rhis idm password policies (RHIS) | See project checklist |
| idm_realm | Enter value for rhis idm realm (RHIS) | See project checklist |
| idm_user_groups | Enter value for rhis idm user groups (RHIS) | See project checklist |
| idm_users | Enter value for rhis idm users (RHIS) | See project checklist |
| insights_use_rh_credentials | Enter value for rhis insights use rh credentials (RHIS) | See project checklist |
| install_grafana | Enter value for rhis install grafana (RHIS) | https://grafana.com/docs/grafana/latest/ |
| installer_pubkey | Enter value for rhis installer pubkey (RHIS) | See project checklist |
| installer_user | Enter value for rhis installer user (RHIS) | See project checklist |
| ipa_backup_cron_name | Enter value for rhis ipa backup cron name (RHIS) | See project checklist |
| ipa_backup_dir | Enter value for rhis ipa backup dir (RHIS) | See project checklist |
| ipa_backup_script_path | Enter value for rhis ipa backup script path (RHIS) | See project checklist |
| ipa_client_dns_servers | Enter value for rhis ipa client dns servers (RHIS) | See project checklist |
| ipa_healthcheck_script_path | Enter value for rhis ipa healthcheck script path (RHIS) | See project checklist |
| ipa_server_fqdn | Enter value for rhis ipa server fqdn (RHIS) | See project checklist |
| kickstart_output_dir | Enter value for rhis kickstart output dir (RHIS) | See project checklist |
| manage_firewalld | Enter value for rhis manage firewalld (RHIS) | See project checklist |
| mcp_ai_enabled | Enter value for rhis mcp ai enabled (RHIS) | See project checklist |
| mcp_ai_log_dir | Enter value for rhis mcp ai log dir (RHIS) | See project checklist |
| mcp_ai_runner_path | Enter value for rhis mcp ai runner path (RHIS) | See project checklist |
| mcp_ai_user | Enter value for rhis mcp ai user (RHIS) | See project checklist |
| mount_point | Enter value for rhis mount point (RHIS) | See project checklist |
| mrhis_installer_pubkey | Enter value for rhis mrhis installer pubkey (RHIS) | See project checklist |
| mrhis_rhsm_check_host | Enter value for rhis mrhis rhsm check host (RHIS) | https://access.redhat.com/management/api |
| mrhis_rhsm_check_port | Enter value for rhis mrhis rhsm check port (RHIS) | https://access.redhat.com/management/api |
| mrhis_rhsm_retries | Enter value for rhis mrhis rhsm retries (RHIS) | https://access.redhat.com/management/api |
| mrhis_rhsm_retry_delay | Enter value for rhis mrhis rhsm retry delay (RHIS) | https://access.redhat.com/management/api |
| mrhis_temp_enable_rc_local_exec | Enter value for rhis mrhis temp enable rc local exec (RHIS) | See project checklist |
| mysql_dbname | Enter value for rhis mysql dbname (RHIS) | See project checklist |
| mysql_dbname_vault | Enter value for rhis mysql dbname vault (RHIS) | See project checklist |
| mysql_password | Enter value for rhis mysql password (RHIS) | See project checklist |
| mysql_password_vault | - The canonical vault path is `~/.ansible/conf/env.yml` and the vault password is read from `~/.ansible/conf/.vaultpass.txt` by default. | See project checklist |
| mysql_port | Enter value for rhis mysql port (RHIS) | See project checklist |
| mysql_port_protocol | Enter value for rhis mysql port protocol (RHIS) | See project checklist |
| mysql_service | Enter value for rhis mysql service (RHIS) | See project checklist |
| mysql_sql_log_bin | Enter value for rhis mysql sql log bin (RHIS) | See project checklist |
| mysql_user_priv | Enter value for rhis mysql user priv (RHIS) | See project checklist |
| mysql_user_priv_vault | Enter value for rhis mysql user priv vault (RHIS) | See project checklist |
| mysql_username | Enter value for rhis mysql username (RHIS) | See project checklist |
| mysql_username_vault | Enter value for rhis mysql username vault (RHIS) | See project checklist |
| mysqlservice | Enter value for rhis mysqlservice (RHIS) | See project checklist |
| nginx_port | Enter value for rhis nginx port (RHIS) | See project checklist |
| nginx_port_protocol | Enter value for rhis nginx port protocol (RHIS) | See project checklist |
| node_artifacts | Enter value for rhis node artifacts (RHIS) | See project checklist |
| node_common_packages | Enter value for rhis node common packages (RHIS) | See project checklist |
| node_common_users | Enter value for rhis node common users (RHIS) | See project checklist |
| node_config_tests | Enter value for rhis node config tests (RHIS) | See project checklist |
| node_configs | Enter value for rhis node configs (RHIS) | See project checklist |
| node_install_checks | Enter value for rhis node install checks (RHIS) | See project checklist |
| node_install_commands | Enter value for rhis node install commands (RHIS) | See project checklist |
| node_integration_tests | Enter value for rhis node integration tests (RHIS) | See project checklist |
| node_packages | Enter value for rhis node packages (RHIS) | See project checklist |
| node_rpms | Enter value for rhis node rpms (RHIS) | See project checklist |
| node_wrapper_enabled | Enter value for rhis node wrapper enabled (RHIS) | See project checklist |
| open_9443 | Enter value for rhis open 9443 (RHIS) | See project checklist |
| platform_deployment_type | Enter value for rhis platform deployment type (RHIS) | See project checklist |
| platform_installer_config | Enter value for rhis platform installer config (RHIS) | See project checklist |
| podman_pkg | Enter value for rhis podman pkg (RHIS) | See project checklist |
| qemu_img | Enter value for rhis qemu img (RHIS) | See project checklist |
| recovery_backup_dir | Enter value for rhis recovery backup dir (RHIS) | See project checklist |
| rhsm_register_delay | Enter value for rhis rhsm register delay (RHIS) | https://access.redhat.com/management/api |
| rhsm_register_retries | Enter value for rhis rhsm register retries (RHIS) | https://access.redhat.com/management/api |
| sat_firewalld_interface | Enter value for rhis sat firewalld interface (RHIS) | See project checklist |
| sat_ssl_certs_dir | Enter value for rhis sat ssl certs dir (RHIS) | See project checklist |
| satellite_location | Enter value for rhis satellite location (RHIS) | See project checklist |
| satellite_organization | Enter value for rhis satellite organization (RHIS) | See project checklist |
| satellite_password | Enter value for rhis satellite password (RHIS) | See project checklist |
| satellite_pre_use_idm | Enter value for rhis satellite pre use idm (RHIS) | See project checklist |
| satellite_url | Enter value for rhis satellite url (RHIS) | See project checklist |
| satellite_username | Enter value for rhis satellite username (RHIS) | See project checklist |
| selinux_state | Enter value for rhis selinux state (RHIS) | See project checklist |
| server_hostname | Enter value for rhis server hostname (RHIS) | See project checklist |
| server_packages | Enter value for rhis server packages (RHIS) | See project checklist |
| service_name | Enter value for rhis service name (RHIS) | See project checklist |
| ssh_installer | Enter value for rhis ssh installer (RHIS) | See project checklist |
| sysmessage_allowable_types | Enter value for rhis sysmessage allowable types (RHIS) | See project checklist |
| sysmessage_default_base_message | Enter value for rhis sysmessage default base message (RHIS) | See project checklist |
| sysmessage_default_cis2_message | Enter value for rhis sysmessage default cis2 message (RHIS) | See project checklist |
| sysmessage_default_compliance_message | Enter value for rhis sysmessage default compliance message (RHIS) | See project checklist |
| sysmessage_default_custom_message | Enter value for rhis sysmessage default custom message (RHIS) | See project checklist |
| sysmessage_default_disa_stig_message | Enter value for rhis sysmessage default disa stig message (RHIS) | See project checklist |
| sysmessage_default_type | Enter value for rhis sysmessage default type (RHIS) | See project checklist |
| sysmessage_extended_cis2_message | Enter value for rhis sysmessage extended cis2 message (RHIS) | See project checklist |
| time_server_1 | Enter value for rhis time server 1 (RHIS) | See project checklist |
| time_server_1_burst | Enter value for rhis time server 1 burst (RHIS) | See project checklist |
| time_server_2 | Enter value for rhis time server 2 (RHIS) | See project checklist |
| time_server_2_burst | Enter value for rhis time server 2 burst (RHIS) | See project checklist |
| time_server_3 | Enter value for rhis time server 3 (RHIS) | See project checklist |
| time_server_3_burst | Enter value for rhis time server 3 burst (RHIS) | See project checklist |
| time_timedaemon | Enter value for rhis time timedaemon (RHIS) | See project checklist |
| time_timeservers | Enter value for rhis time timeservers (RHIS) | See project checklist |
| time_timezone | Enter value for rhis time timezone (RHIS) | See project checklist |
| use_non_idm_certs | Enter value for rhis use non idm certs (RHIS) | See project checklist |
| vault_wp_db_name | Enter value for rhis vault wp db name (RHIS) | See project checklist |
| vault_wp_db_password | - The canonical vault path is `~/.ansible/conf/env.yml` and the vault password is read from `~/.ansible/conf/.vaultpass.txt` by default. | See project checklist |
| vault_wp_db_user | Enter value for rhis vault wp db user (RHIS) | See project checklist |
| vcenter_hostname | Enter value for rhis vcenter hostname (RHIS) | See project checklist |
| vcenter_password | Enter value for rhis vcenter password (RHIS) | See project checklist |
| vcenter_username | Enter value for rhis vcenter username (RHIS) | See project checklist |
| vmware_validate_certs | Enter value for rhis vmware validate certs (RHIS) | See project checklist |
| wait_for_web | Enter value for rhis wait for web (RHIS) | See project checklist |
| web_port | Enter value for rhis web port (RHIS) | See project checklist |
| wp_admin_email | Enter value for rhis wp admin email (RHIS) | See project checklist |
| wp_admin_password | Enter value for rhis wp admin password (RHIS) | See project checklist |
| wp_allow_weak_pass | Enter value for rhis wp allow weak pass (RHIS) | See project checklist |
| wp_blog_public | Enter value for rhis wp blog public (RHIS) | See project checklist |
| wp_checksum | Enter value for rhis wp checksum (RHIS) | See project checklist |
| wp_db_name | Enter value for rhis wp db name (RHIS) | See project checklist |
| wp_db_password | Enter value for rhis wp db password (RHIS) | See project checklist |
| wp_db_user | Enter value for rhis wp db user (RHIS) | See project checklist |
| wp_url | Enter value for rhis wp url (RHIS) | See project checklist |
| wp_user_name | Enter value for rhis wp user name (RHIS) | See project checklist |
| wp_version | Enter value for rhis wp version (RHIS) | See project checklist |
| wp_weblog_title | Enter value for rhis wp weblog title (RHIS) | See project checklist |

## Sources

- Checklist: /home/sgallego/GIT/RHIS/CHECKLIST.md
