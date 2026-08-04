### mrhis-provisioner-container (MRHIS provisioner)

This folder contains the container build information for the mrhis-provisioner-container. It builds the provisioner container from the base container by adding the individual mrhis projects into the container image and setting it up to consume the inventory. The base container changes infrequently when there are updates to the underlying ubi9 container, binaries, collections and python modules. By separating the base container from the provisioner container we reduce container build times for development and allow ourselves to move faster as the collection deployment is very time consuming. We only will rebuild this container when we have committed changes in the upstream mrhis repos.

The goal is to eventually get on a schedule for releases for this container to ensure stability and repeatable infrastructure builds.

See the [README.md](../mrhis-base-local/README.md) in the mrhis-base-container folder for details.

If you have suggestions, requests or have found a bug, please open an issue against this project. This will allow us to centrally manage the issues for the underlying projects for visibility and allow us to involve the proper team for the underlying project. We will pull together an issue template soon to help with ensure we have the required debugging information.

Just like the original container build, we will have an AAP 2.4 and an AAP 2.5+ build of the mrhis-provisioner-container due to collection requirement differences for AAP 2.4 and AAP 2.5 and greater.

As always, your contributions to the project are essential, PRs are welcome.

Thanks!

The MRHIS Team.

---

**Rules & Policies**

 - Container builds and the `mrhis-provisioner` container are part of this repo for convenience. Follow the project RULES: do not run containerized workflows unless you explicitly request them using a container flag (for example `--container`). See `docs/RULES.md` and `docs/assistant-adherence-rules.md` for details.


## Headless Test & Vault

See the top-level README 'Headless Noninteractive Test (developer)' for the noninteractive test command and vault guidance.
