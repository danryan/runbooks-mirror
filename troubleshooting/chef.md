# Chef troubleshooting

## First and foremost

*Don't Panic*

## Symptoms

1. HAProxy is missing workers:
    ```lb7.cluster.gitlab.com HAProxy_gitlab_443/worker4.cluster.gitlab.com is UNKNOWN - Check output not found in local checks```
    
2. Nodes are missing chef roles:
    ```
    jeroen@xps15:~/src/gitlab/chef-repo$ bundle exec knife node show worker1.cluster.gitlab.com
    Node Name:   worker1.cluster.gitlab.com
    Environment: _default
    FQDN:        worker1.cluster.gitlab.com
    IP:          10.1.0.X
    Run List:    
    Roles:       
    Recipes:     
    Platform:    ubuntu 16.04
    Tags:
    ```

3. Knife ssh does not work:
    ```
    bundle exec knife ssh "name:worker1.cluster.gitlab.com" "uptime"
    WARNING: Failed to connect to  -- Errno::ECONNREFUSED: Connection refused - connect(2)
    ```

## Resolution

1. Check if the workers have the chef role `gitlab-cluster-worker`. HAProxy config is generated with a chef search on this specific role.

    ```
    $ bundle exec knife node show worker1.cluster.gitlab.com
    ```
    If not restore the worker via `knife node from file`:
    ```
    $ bundle exec knife node from file worker1.cluster.gitlab.com.json
    ```
    Run chef-client on the node. When the chef-client run is finished on the nodes force a chef-client run on the load balancers to regenerate the haproxy config with the workers:
    ```
    $ bundle exec knife ssh -p2222 -a ipaddress role:gitlab-cluster-lb 'sudo chef-client'
    $ bundle exec knife ssh -p2222 -a ipaddress role:gitlab-cluster-lb-pages 'sudo chef-client'
    ```

2. See resolution steps at point 1.

3. Check if the ipnumber is correct for the node:
    ```
    $ bundle exec knife node show worker1.cluster.gitlab.com

    ```
    If ipaddress contains a wrong public ip update /etc/ipaddress.txt on the node and run chef-client
    
    If ipaddress contains a private (local) ip make sure /etc/ipaddress.txt is set and the node has at least the chef role base-X where X is the OS type like debian etc. check chef-repo/roles/base-* for all current base roles.
