## CIrepoM Runbooks

* **Bot**: https://ops.gitlab.net/gitlab-com/gl-infra/infra-bots/cirepom-bot
* **Service Review**: https://gitlab.com/gitlab-com/gl-infra/readiness/-/blob/master/cirepom/index.md



### Initializing `cirepom-bot`

It is recommended you maintain separate local clones of `cirepom-bot` per target instance. The following shows the initialization for GitLab.com. Adjust paths to your needs and preferences.

I keep the clones in `~/Work/Infra/Bots/cirepom-bot/` and use FQDNs toclone the repositories into:

```shell
gerir@beirut:~/Work/Infra/Bots/cirepom-bot:git clone git@ops.gitlab.net:gitlab-com/gl-infra/infra-bots/cirepom-bot.git gitlab.com
Cloning into 'gitlab.com'...
remote: Enumerating objects: 66, done.
remote: Counting objects: 100% (66/66), done.
remote: Compressing objects: 100% (50/50), done.
remote: Total 198 (delta 20), reused 33 (delta 5), pack-reused 132
Receiving objects: 100% (198/198), 81.24 KiB | 366.00 KiB/s, done.
Resolving deltas: 100% (55/55), done.

gerir@beirut:~/Work/Infra/Bots/cirepom-bot:ls -la gitlab.com/
total 32
drwxr-xr-x   8 gerir  staff   256 May 21 11:28 .
drwxr-xr-x   6 gerir  staff   192 May 21 11:03 ..
-rw-r--r--   1 gerir  staff  1141 May 16 02:19 .envrc
drwxr-xr-x  12 gerir  staff   384 May 21 11:03 .git
-rw-r--r--   1 gerir  staff    18 May 16 01:53 .gitignore
-rw-r--r--   1 gerir  staff  2198 May 21 11:03 .gitlab-ci.yml
-rw-r--r--   1 gerir  staff    84 May 21 11:03 .gitmodules
drwxr-xr-x   5 gerir  staff   160 May 21 11:03 runtime
```

### Configuring `cirepom-bot`

Locally, you need [two environment variables](https://gitlab.com/gitlab-com/gl-infra/readiness/-/blob/gerir/cirepom/cirepom/index.md#terminal) per target instance:

* `CIREPOM_CRI_GITLAB_PRIVATE_TOKEN`contains your access token to the instance where change requests are opened, namely GitLab.com. 
* `CIREPOM_BOT_GITLAB_PRIVATE_TOKEN` contains a user's acess token to the executor instance, which hosts the `cirepom-bot` project, namely `ops.gitlab.com`

#### Using 1Password+direnv

You may want to configure these environment variables through [1Password+direnv](https://gitlab.com/gitlab-com/runbooks/-/blob/master/utilities/1password+direnv.md), which entails the use of the `envrc` file:

```sh
#
GITLAB_BOT_FQDN_1PUUID="5r4j2rlgdbbsrbxifm5gcebai4"     # The executor's UUID in 1Password
GITLAB_REPOSET_FQDN="gitlab.com"                        # The target's FQDN
#

# Validate there's a valid 1Password session
if [ -z "${OP_SESSION_gitlab}" ]  # Validate there's a 1Password session
then
   echo "error: missing 1Password session token"
   return 1
else
  if op list users --vault Private > /dev/null 2>&1  # Validate the 1Password session token has not expired
  then
    cirepom_bot_gpt=$(op get item ${GITLAB_BOT_FQDN_1PUUID} | jq -r '.details.sections[] | select(.title == "ENV_VAR::CIREPOM://GITLAB.COM") | .fields[] | select(.t == "CIREPOM_BOT_GITLAB_PRIVATE_TOKEN") | @text "\(.v)"')
    cirepom_cri_gpt=$(op get item ${GITLAB_BOT_FQDN_1PUUID} | jq -r '.details.sections[] | select(.title == "ENV_VAR::CIREPOM://GITLAB.COM") | .fields[] | select(.t == "CIREPOM_CRI_GITLAB_PRIVATE_TOKEN") | @text "\(.v)"')
    export CIREPOM_BOT_GITLAB_PRIVATE_TOKEN=${cirepom_bot_gpt}
    export CIREPOM_CRI_GITLAB_PRIVATE_TOKEN=${cirepom_cri_gpt}
  else
    echo "error: expired 1Password session token"
    return 1
  fi
fi
```

Then:

```shell
gerir@beirut:~/Work/Infra/Bots/cirepom-bot:cd gitlab.com
direnv: loading ~/Work/Infra/Bots/cirepom-bot/gitlab.com/.envrc
direnv: export +CIREPOM_BOT_GITLAB_PRIVATE_TOKEN +CIREPOM_CRI_GITLAB_PRIVATE_TOKEN
```

### Ready

You are now ready to use CIrepoM on GitLab.com. Follow the same procedure for `staging.gitlab.com`.

