# Summary

When GitLab.com is down it may not be possible to open incidents, make configuration changes, or deploy changes.

Below we will refer to:

- `ops` as ops.gitlab.net, which is where we mirror projects so they are available if .com is unavailable.
- `canonical` as gitlab.com, which is where we push code changes when .com is up.

## Updating or reverting Rails application code

If GitLab.com is completely down, it may be difficult to push or rollback a change. The only way we have currently to apply a codefix is to use the [post-deployment patcher](https://ops.gitlab.net/gitlab-org/release/docs/-/blob/master/general/deploy/post-deployment-patches.md).

## Making configuration changes

Application configuration changes are made by applying changes in CI pipelines on [chef-repo](https://ops.gitlab.net/gitlab-com/gl-infra/chef-repo) or [k8s-workloads/gitlab-com](https://ops.gitlab.net/gitlab-com/gl-infra/k8s-workloads/gitlab-com).

### Update your remote and create an MR on ops.gitlab.net

When the canonical source of these projects are unavailable, it will be necessary to push and create MRs directly on the mirrors.

- Ensure that MRs are enabled for the projects on `ops`:
  -  https://ops.gitlab.net/gitlab-com/gl-infra/chef-repo
  -  https://ops.gitlab.net/gitlab-com/gl-infra/k8s-workloads/gitlab-com
- Ensure that you have a remote for `ops`:
  - chef-repo: `git remote add ops git@ops.gitlab.net:gitlab-com/gl-infra/chef-repo`
  - k8s-workloads/gitlab-com: `git remote add ops git@ops.gitlab.net:gitlab-com/gl-infra/k8s-workloads/gitlab-com`
- Make a new branch and push changes to `ops`:

```
git checkout -b <name>
# Make changes
git commit -m ' ... '
git push ops
```

One the MR is merged, apply it on the `ops` CI pipeline like you would normally

### Incorporate changes into canonical when gitlab.com is available

As soon as `ops` is ahead of `canonical`, mirroring will fail to work. To incorporate your changes create a new MR:

```
git checkout -b update-canonical
git push origin master
```

Merge the MR on `canonical`, after the merge you can confirm that repository mirroring still works under repository settings.
