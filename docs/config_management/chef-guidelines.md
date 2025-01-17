# Chef Guidelines

**Table of Contents**

[TOC]

The purpose of this page should be to document how we at GitLab use chef, write cookbooks and configure nodes. It is a work in progress, however the points made here should be agreed upon by those who work with chef on a daily basis.

## Nodes dos and donts

### **Do:** simplify node run_lists

Keep a node simple - single purpose driven role applied on a node.
For example, a front end web server should have a single role on it:

```ruby
"run_list": [
  "role[frontend-web-server]"
]
```

rather than:

```ruby
"run_list": [
  "role[base]",
  "role[do-droplet]",
  "role[frontend]",
  "role[web-server]"
]
```

Similarly, avoid (manually) setting attributes on nodes directly.
A node should be an instance of a role, making it a repetable and generic entity, rather than a patchwork of multiple different purposes. Cleaning this up would make the transition to cattle one step closer.

### **Don't:** Mix attributes

See cookbooks below.

## Cookbooks

### Supermarket Cookbooks

Do we have to build a cookbook or is there a well maintained one in the [Chef Supermarket](https://supermarket.chef.io/) we can use (e.g. via wrappers/lwrps)? The supermarket is excellent place to find cookbooks and should be the first place you look when thinking about creating a new cookbook. In many cases it is well worth spending time searching through these, rather than writing our own.

Including these cookbooks can be done in different ways by using so called wrapper cookbooks.

#### Wrapper Pattern

The Chef Cookbook Wrapper Pattern is based upon a design convention where you customize an existing "library" cookbook by using:

##### Libraries

Cookbooks can gather common tasks into libraries to ensure that the code is DRY.

Example:

[Only execute on supported platforms](https://github.com/jtimberman/enforce_supported_platform-cookbook) simplifies [this](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/commit/739040f16e901c66fa70ed6014768898f0b67f6a#16f5421f9f20b9e5d3af7fc7cdd6ff9b7de716cc_0_1) by making it [this](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/commit/ebd432345d4356818ad4a85ac436b33c9f9c8d65#2aeda62be0e44bf1b010cc93e2e1ed1348a65b4c_4_4)

##### Custom Resources (aka LWRPs)

Cookbooks can use [custom resources](https://docs.chef.io/custom_resources.html) to abstract the access to groups of tasks (e.g. installing, configuring, starting...)

Example:

[REDISIO cookbook with LWRPs](https://github.com/brianbianco/redisio#lwrp-examples)

The redisio cookbook offers all the necessary LWRPs to install and configure a redis instance, but does not actually do anything itself if the default recipe is not called.

```ruby
redisio_install "redis-installation" do
  version '2.6.9'
  download_url 'http://redis.googlecode.com/files/redis-2.6.9.tar.gz'
  safe_install false
  install_dir '/usr/local/'
end
```

By calling the LWRP we are agnostic to changes in the cookbook background, in the same way we access all chef resources. It does mean we need a wrapping recipe.

##### Attributes and includes

Cookbooks can rely on all configuration to be available via attributes on a node, allowing all configuration to be done via that route.

Example:

[REDISIO cookbook with attributes and includes](https://github.com/brianbianco/redisio#role-file-examples)

```ruby
run_list *%w[
  recipe[redisio]
  recipe[redisio::enable]
]

default_attributes({
  'redisio' => {
    'servers' => [
      {'name' => 'master', 'port' => '6379', 'unixsocket' => '/tmp/redis.sock', 'unixsocketperm' => '755'},
    ]
  }
})
```

By setting attributes on e.g. the role, we don't have to make any programmatic changes to a cookbook since the logic is still in the default redisio recipe.

It is important to note that a wrapper cookbook does not extend functionality, only configures and includes the library cookbook!

### Declarative

Each chef run should **ALWAYS** describe the node in the same way.
Avoid [if statements](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/commit/f772209475bdc4dac1a530f80666dda6c3e6ec93#16f5421f9f20b9e5d3af7fc7cdd6ff9b7de716cc_23_15) which would cause chef resources to appear and disappear. Instead, make use of [guards](https://docs.chef.io/resource_common.html#guards) to skip over resources such as [here](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/commit/c78108caffcdfd2e37cf2ba59759fbb93f77db4a#16f5421f9f20b9e5d3af7fc7cdd6ff9b7de716cc_29_22). This ensures that we **DECLARE** what our infrastructure should look the same way every time chef-client runs.

Example of a guard in practice:

```ruby
template '/etc/gitlab/gitlab.rb' do
  mode '0600'
  variables(gitlab_rb: gitlab_rb)
  helper(:single_quote) { |value| value.nil? ? nil : "'#{value}'" }
  notifies :run, 'execute[reload-gitlab]'
end

execute 'reload-gitlab' do
  command "gitlab-ctl reconfigure"
  action :nothing
  not_if '${PROD?}'
end
```

This snippet would guard against `gitlab-ctl reconfigure` being called if the environment variable `PROD` is set.

### Cookbook Attributes

Attributes are your friends:

* all attributes used by a cookbook should be:
  * nested under a common, understandable hash e.g.

    *sshd settings*

    ```ruby
    node['openssh']['sshd']['port']
    node['openssh']['sshd']['address_family']
    ```

    vs. *unreadable settings*:

    ```ruby
    node['openssh_port']
    node['address_family']
    ```

  * Kept in the respective cookbook.
     Roles are the place where you can change settings, not in unrelated cookbooks. e.g. the haproxy cookbook is not the place for [openssh settings](https://gitlab.com/gitlab-cookbooks/gitlab-haproxy/commit/f8aaa5d3ec344fba38bd15948d04854317e9e3ce#20875b27e096b4a4356a90b6ae97d03a1dbf877a_35_32).

  * Come with sane defaults. This plays into the testability of a cookbook. Never assume that attributes will be set elsewhere: either **set defaults** or **fail**.
* Try to avoid setting attributes via cookbooks e.g. `node.default['openssh']['sshd']['port'] = 23` this becomes hard to follow, when you are searching for the cause of issues.

### Documentation

The default [README.md](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/blob/37399ec3bc3a8525e7950755f09d38a79dbbf919/README.md) is **NOT** acceptable documentation.

A cookbook should not be considered **DONE** unless the following is documented:

* [Description](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/tree/%231634-Cleanup-and-simplify#gitlab-nfs-cluster-cookbook) - What does this cookbook do? (short and sweet)
* [Attributes](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/tree/%231634-Cleanup-and-simplify#attributes) - what are relevant and important attributes we expect, and what are their defaults?
* [Recipes](https://gitlab.com/gitlab-cookbooks/gitlab-nfs-cluster/tree/%231634-Cleanup-and-simplify#usage) - what does each recipe do?
* [LWRPs](https://github.com/martinisoft/chef-rvm/tree/0.9.x#-resources-and-providers):
  * name
  * Actions
  * Attributes
  * Example

### Tests

#### Chefspec

Chefspec is the fastest and easiest way to test cookbooks. Similar to [RSpec](http://rspec.info/), [ChefSpec](https://github.com/sethvargo/chefspec) is a [BDD](https://en.wikipedia.org/wiki/Behavior-driven_development) testing framework which allows you to describe the **expected** behavior of each resource during a chef run. Chefspec tests **MUST** exist for a cookbook to be complete.

#### Kitchen

[Kitchen](http://kitchen.ci/docs/getting-started/) tests are integration tests. They converge your cookbook and run it on an actual (e.g. vbox) node. This opens the door for lots of different tests, the first and foremost: does my recipe actually run.
Furthermore you can write tests in essentially any test framework, e.g. [BATS](https://github.com/sstephenson/bats) or [serverspec](http://serverspec.org/).

## Chef Tips

### `role` vs `roles`

`knife (search|ssh|..) role:my-role ...` returns only nodes for which `my-role` is specified in their run_list, not nested ones.

`knife (search|ssh|..) roles:my-role ...` returns all nodes which has `my-role`, directly and nestly specified.

### Update IP of chef node

Create or update file `/etc/ipaddress.txt` with desired IP address (or run `curl ifconfig.co | sudo tee /etc/ipaddress.txt`) and run chef-client.
