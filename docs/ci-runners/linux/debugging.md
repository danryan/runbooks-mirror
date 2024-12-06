# Hosted Runners Debugging Guide

Debugging a hosted runner involves two main steps:

1. Verifying a runner-manager's ability to spin up ephemeral VMs.
2. Ensuring the ephemeral VMs can connect to GitLab.com or the CI Gateway.

---

## Quick Overview

For a visual walkthrough, check out this video: [Hosted Runners Testing](https://youtu.be/vcTFFHOlDaA).

---

## Part 1: Testing Ephemeral VM Creation

The most challenging aspect of testing runner-managers is composing the `docker-machine` command with all the required custom options. These options vary by manager, so we've created handy scripts to automate this process.

### Using `generate-create-machine.sh`

This script is typically located in the `/tmp` folder of runner-manager VMs. It generates another script based on the configurations in the `/etc/gitlab-runner/config.toml` file of each runner-manager.

#### Steps to Run

```bash
$ sudo su
# cd /tmp
# export VM_MACHINE=test1
# ./generate-create-machine.sh
# less create-machine.sh  # Review the generated script
# ./create-machine.sh     # Run the script
```

#### Example Output of a Successful Run

```plaintext
tmp# ./create-machine.sh
Running pre-create checks...
(test1) Check that the project exists
(test1) Check if the instance already exists
Creating machine...
(test1) Generating SSH Key
(test1) Creating host...
(test1) Opening firewall ports
(test1) Creating instance
(test1) Waiting for Instance
(test1) Uploading SSH Key
Waiting for machine to be running, this may take a few minutes...
Detecting operating system of created instance...
Waiting for SSH to be available...
Detecting the provisioner...
Provisioning with cos...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!

To connect your Docker Client to the Docker Engine running on this VM, run: docker-machine env test1
```

---

## Part 2: Testing Ephemeral VM Connectivity

Once the ephemeral VM is created successfully, you can verify its connectivity.

### Steps to Test Connectivity

```bash
# docker-machine ssh test1
cos@test1 ~ $ curl -IL https://us-east1-c.ci-gateway.int.gprd.gitlab.net:8989
cos@test1 ~ $ curl -IL https://gitlab.com
```

#### Expected Outcome

- A successful call will return a `200` status code.

- If any command times out, it may indicate a network misconfiguration.

---

## Troubleshooting Tips

### Common Issue: Network Misconfiguration

One frequent issue is a missing network configuration for the CI Gateway. Ensure that the network is allowed in the [CI Gateway configuration](https://ops.gitlab.net/gitlab-com/gl-infra/config-mgmt/-/blob/7a5022fafbcd268e34b3f08b4d86aea8699db328/environments/gprd/variables.tf#L224).

If problems persist, verify the VM’s network settings and access permissions.

---
