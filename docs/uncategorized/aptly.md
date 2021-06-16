# Aptly

Our Aptly server is aptly.gitlab.com and is primarily used to host custom packages that we built (e.g. [gitlab-cadvisor][cadvisor]).

When prompted for the passphrase for the GPG key, you can find it in 1Password in the DevOps vault under item "Aptly GitLab Repo GPG Passphrase".

## Add or update a file in the gitlab-utils repository

Our Aptly installation also includes a gitlab-utils repository for storing locally created packages.

### Adding or updating a file in the gitlab-utils repository

After uploading your package to the Aptly server, add or replace the existing package.

```
user@aptly:~$ sudo su - aptly
# If the package already exists in the repo, find the name and then remove it from the repo
aptly@aptly:~$ aptly repo show --with-packages gitlab-utils
Name: gitlab-utils
Comment: GitLab Server Utilities
Default Distribution:
Default Component: main
Number of packages: 1
Packages:
  package_name_2.8.3-1_amd64

aptly@aptly:~$ aptly repo remove gitlab-utils package_name_2.8.3-1_amd64
Loading packages...
[-] package_name_2.8.3-1_amd64 removed

# Now add the new or updated package
aptly@aptly:~$ aptly repo add gitlab-utils package_name_2.8.3-1_amd64.deb
Loading packages...
[+] package_name_2.8.3-1_amd64 added

```

### Now create a new snapshot for this version of the repository
Snapshots preserve the state of the repository. Include the date so that multiple snapshots can co-exist.

```
user@aptly:~$ sudo su - aptly
aptly@aptly:~$ aptly snapshot create gitlab-utils-stable-20161221 from repo gitlab-utils

Snapshot gitlab-utils-stable-20161221 successfully created.
You can run 'aptly publish snapshot gitlab-utils-stable-20161221' to publish snapshot as Debian repository.
```

### Switch the published snapshots
Now we must replace the currently published snapshot with the newly created snapshot

```
user@aptly:~$ sudo su - aptly
aptly@aptly:~$ aptly publish switch xenial gitlab-utils-stable-20161221
Loading packages...
Generating metadata files and linking package files...
Finalizing metadata files...
Signing file 'Release' with gpg, please enter your passphrase when prompted:

You need a passphrase to unlock the secret key for
user: "GitLab Infra <ops-notifications@gitlab.com>"
4096-bit RSA key, ID B7FD19AF, created 2016-12-21

gpg: gpg-agent is not available in this session
Clearsigning file 'Release' with gpg, please enter your passphrase when prompted:

You need a passphrase to unlock the secret key for
user: "GitLab Infra <ops-notifications@gitlab.com>"
4096-bit RSA key, ID B7FD19AF, created 2016-12-21

gpg: gpg-agent is not available in this session
Cleaning up prefix "." components main...

Publish for snapshot ./xenial [amd64] publishes {main: [mirror-gitlab-utils-20161221]: Merged from sources: 'mirror-snapshot-20161107', 'gitlab-utils-stable-20161221'} has been successfully switched to new snapshot.

```

## Update a mirror

Currently we don't auto update any mirror since we need to manual sign the mirror when publishing.

### Update mirror

```
user@aptly:~$ sudo su - aptly
aptly@aptly:~$ aptly mirror list
List of mirrors:
 * [ceph-jewel]: https://download.ceph.com/debian-jewel/ xenial

aptly@aptly:~$ aptly mirror update ceph-jewel
Downloading https://download.ceph.com/debian-jewel/dists/xenial/InRelease...
gpgv: Signature made Mon 17 Oct 2016 12:42:02 PM UTC using RSA key ID 460F3994
gpgv: Good signature from "Ceph.com (release key) <security@ceph.com>"
Downloading & parsing package files...
Downloading https://download.ceph.com/debian-jewel/dists/xenial/main/binary-amd64/Packages.bz2...
Building download queue...
Download queue: 0 items (0 B)

Mirror `ceph-jewel` has been successfully updated.
```

### Create new snapshot

Just use current date in name so we know from when the repository was updated.

```
user@aptly:~$ sudo su - aptly
aptly@aptly:~$ aptly snapshot create ceph-jewel-2016-11-07 from mirror ceph-jewel

Snapshot ceph-jewel-2016-11-07 successfully created.
```

### Switch published to new snapshot

```
user@aptly:~$ sudo su - aptly
aptly@aptly:~$ aptly publish switch xenial ceph-jewel-2016-11-07
Loading packages...
Generating metadata files and linking package files...
Finalizing metadata files...
Signing file 'Release' with gpg, please enter your passphrase when prompted:

You need a passphrase to unlock the secret key for
user: "GitLab Infra <ops-notifications@gitlab.com>"
2048-bit RSA key, ID E4BDBB30, created 2016-10-27

gpg: gpg-agent is not available in this session
Clearsigning file 'Release' with gpg, please enter your passphrase when prompted:

You need a passphrase to unlock the secret key for
user: "GitLab Infra <ops-notifications@gitlab.com>"
2048-bit RSA key, ID E4BDBB30, created 2016-10-27

gpg: gpg-agent is not available in this session
Cleaning up prefix "." components main...

Publish for snapshot ./xenial [amd64] publishes {main: [ceph-jewel-2016-11-07]: Snapshot from mirror [ceph-jewel]: https://download.ceph.com/debian-jewel/ xenial} has been successfully switched to new snapshot.
```


[cadvisor]: https://gitlab.com/gitlab-pkg/gitlab-cadvisor/
