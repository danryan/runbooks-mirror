local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local basic = import 'grafana/basic.libsonnet';
local layout = import 'grafana/layout.libsonnet';
local graphPanel = grafana.graphPanel;
local promQuery = import 'grafana/prom_query.libsonnet';

local generalGraphPanel(
  title,
  fill=0,
  format=null,
  formatY1=null,
  formatY2=null,
  decimals=3,
  description=null,
  linewidth=2,
  sort=0,
      ) = graphPanel.new(
  title,
  linewidth=linewidth,
  fill=fill,
  format=format,
  formatY1=formatY1,
  formatY2=formatY2,
  datasource='$PROMETHEUS_DS',
  description=description,
  decimals=decimals,
  sort=sort,
  legend_show=true,
  legend_values=true,
  legend_min=false,
  legend_max=true,
  legend_current=true,
  legend_total=false,
  legend_avg=false,
  legend_alignAsTable=true,
  legend_hideEmpty=false,
  legend_rightSide=true,
);

{
  version(startRow, deploymentKind='Deployment')::
    layout.grid([
      basic.timeseries(
        title='Active Version',
        query='count(kube_pod_container_info{container_id!="", cluster="$cluster", namespace="$namespace"}) by (image)',
        legendFormat='{{ image }}',
      ),
      basic.timeseries(
        title='Active Replicaset',
        query='avg(kube_replicaset_spec_replicas{replicaset=~"^$Deployment.*", cluster="$cluster", namespace="$namespace"}) by (replicaset)',
        legendFormat='{{ replicaset }}',
        legend_rightSide=true,
      ),
    ], cols=2, rowHeight=5, startRow=startRow),

  deployment(startRow, deploymentKind='Deployment')::
    layout.grid([
      basic.singlestat(
        title='Deployment Memory Usage',
        query='sum (container_memory_working_set_bytes{env=~"$environment", pod=~"^$' + deploymentKind + '.*$", kubernetes_io_hostname=~"^$Node$", pod!="", cluster="$cluster", namespace="$namespace"}) / sum (kube_node_status_allocatable{resource="memory", unit= "byte", env=~"$environment", node=~"^$Node.*$"}) * 100',
        format='percent',
        gaugeShow=true,
        thresholds='65,90',
      ),
      basic.singlestat(
        title='Deployment CPU Usage',
        query='sum (rate (container_cpu_usage_seconds_total{env=~"$environment", pod=~"^$' + deploymentKind + '.*$", cluster="$cluster", kubernetes_io_hostname=~"^$Node$"}[2m])) / sum (machine_cpu_cores{env=~"$environment", cluster="$cluster", kubernetes_io_hostname=~"^$Node$"}) * 100',
        format='percentunit',
        gaugeMaxValue=1,
        gaugeShow=true,
        thresholds='.65,.90',
      ),
      basic.singlestat(
        title='Unavailable Replicas',
        query='((sum(kube_deployment_status_replicas{env=~"$environment", deployment=~".*$Deployment", cluster="$cluster", namespace="$namespace"}) or vector(0)) - ((sum(kube_deployment_status_replicas_available{env=~"$environment", deployment=~".*$Deployment", cluster="$cluster", namespace="$namespace"}) or vector(0)))) / (sum(kube_deployment_status_replicas{env=~"$environment", deployment=~".*$Deployment", cluster="$cluster", namespace="$namespace"}) or vector(0))',
        gaugeShow=true,
        thresholds='1,30',
      ),
    ], cols=3, rowHeight=5, startRow=startRow),

  status(startRow, deploymentKind='Deployment')::
    layout.grid([
      basic.singlestat(
        title='Memory Used',
        query='sum (container_memory_working_set_bytes{env=~"$environment", pod=~"^$' + deploymentKind + '.*$", kubernetes_io_hostname=~"^$Node$", pod!="", cluster="$cluster", namespace="$namespace"})',
        format='bytes',
      ),
      basic.singlestat(
        title='Memory Total (cluster)',
        query='sum (kube_node_status_allocatable{resource="memory", unit="byte", env=~"$environment", cluster="$cluster", node=~"^$Node.*$"})',
        format='bytes',
      ),
      basic.singlestat(
        title='CPU Used',
        query='sum (rate (container_cpu_usage_seconds_total{env=~"$environment", pod=~"^$' + deploymentKind + '.*$", kubernetes_io_hostname=~"^$Node$", cluster="$cluster", namespace="$namespace"}[1m]))',
        format='none',
        postfix='cores',
      ),
      basic.singlestat(
        title='CPU Total (cluster)',
        query='sum (machine_cpu_cores{env=~"$environment", cluster="$cluster", kubernetes_io_hostname=~"^$Node$"})',
        format='none',
        postfix='cores',
      ),
      basic.singlestat(
        title='Available (cluster)',
        query='sum(kube_deployment_status_replicas_available{env=~"$environment", deployment=~".*$Deployment", cluster="$cluster", namespace="$namespace"})',
        format='none',
        postfix='Pods',
      ),
      basic.singlestat(
        title='Total (cluster)',
        query='sum(kube_deployment_status_replicas{env=~"$environment", deployment=~".*$Deployment", cluster="$cluster", namespace="$namespace"})',
        format='none',
        postfix='Pods',
      ),
    ], cols=6, rowHeight=3, startRow=startRow + 1),

  cpu(startRow, deploymentKind='Deployment')::
    layout.grid([
      generalGraphPanel(
        'Usage',
      )
      .addTarget(
        promQuery.target(
          'sum (rate (container_cpu_usage_seconds_total{env=~"$environment", image!="", pod=~"^$' + deploymentKind + '.*$", node=~"^$Node$", cluster="$cluster", namespace="$namespace"}[1m])) by (pod,node)',
          legendFormat='real: {{ pod }}',
        )
      )
      .addTarget(
        promQuery.target(
          'sum (kube_pod_container_resource_requests{resource="cpu", unit="core", env=~"$environment", pod=~"^$' + deploymentKind + '.*$",node=~"^$Node$", cluster="$cluster", namespace="$namespace"}) by (pod,node)',
          legendFormat='rqst: {{ pod }}',
        )
      )
      .resetYaxes()
      .addYaxis(
        format='none',
        label='cores',
      )
      .addYaxis(
        format='short',
        max=1,
        min=0,
        show=false,
      ),

      grafana.tablePanel.new(
        'Quota',
        datasource='$PROMETHEUS_DS',
        styles=[
          {
            type: 'hidden',
            pattern: 'Time',
            alias: 'Time',
          },
          {
            unit: 'short',
            type: 'number',
            alias: 'Pod',
            decimals: 0,
            pattern: 'pod',
            link: true,
            linkUrl: '/d/kubernetes-resources-pod/k8s-resources-pod?var-datasource=$datasource&var-cluster=$cluster&var-namespace=$namespace&var-pod=$__cell',
            linkTooltip: 'Drill Down',

          },
          {
            unit: 'short',
            type: 'number',
            alias: 'CPU Usage',
            decimals: 3,
            pattern: 'Value #A',
          },
          {
            unit: 'short',
            type: 'number',
            alias: 'CPU Requests',
            decimals: 3,
            pattern: 'Value #B',
          },
          {
            unit: 'percentunit',
            type: 'number',
            alias: 'CPU Usage %',
            decimals: 0,
            pattern: 'Value #C',
          },
        ],
      )
      .addTarget(
        promQuery.target(
          'sum(label_replace(node_namespace_pod_container:container_cpu_usage_seconds_total:sum_rate{env=~"$environment"}, "pod", "$1", "pod", "(.*)") * on(namespace,pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod)',
          format='table',
          instant=true,
        )
      )
      .addTarget(
        promQuery.target(
          'sum(kube_pod_container_resource_requests{resource="cpu", unit="core", env=~"$environment"} * on(namespace,pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod)',
          format='table',
          instant=true,
        )
      )
      .addTarget(
        promQuery.target(
          'sum(label_replace(namespace_pod_container:container_cpu_usage_seconds_total:sum_rate{env=~"$environment"}, "pod", "$1", "pod", "(.*)") * on(pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod) / sum(kube_pod_container_resource_requests{resource="cpu", unit="core", env=~"$environment"} * on(pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod)',
          format='table',
          instant=true,
        )
      ),

    ], cols=1, rowHeight=10, startRow=startRow),

  memory(deploymentKind='Deployment', startRow, container)::
    layout.grid([
      generalGraphPanel(
        'Usage',
        format='bytes',
      )
      .addTarget(
        promQuery.target(
          'sum (container_memory_working_set_bytes{env=~"$environment", id!="/",pod=~"^$' + deploymentKind + '.*$",node=~"^$Node$", container="%(container)s", cluster="$cluster", namespace="$namespace"}) by (pod)' % { container: container },
          legendFormat='real: {{ pod }}',
        )
      ),
      grafana.tablePanel.new(
        'Quota',
        datasource='$PROMETHEUS_DS',
        styles=[
          {
            type: 'hidden',
            pattern: 'Time',
            alias: 'Time',
          },
          {
            unit: 'short',
            type: 'number',
            alias: 'Pod',
            decimals: 0,
            pattern: 'pod',
            link: true,
            linkUrl: '/d/kubernetes-resources-pod/k8s-resources-pod?var-datasource=$datasource&var-cluster=$cluster&var-namespace=$namespace&var-pod=$__cell',
            linkTooltip: 'Drill Down',

          },
          {
            unit: 'bytes',
            type: 'number',
            alias: 'Memory Usage',
            decimals: 2,
            pattern: 'Value #A',
          },
          {
            unit: 'bytes',
            type: 'number',
            alias: 'Memory Requests',
            decimals: 2,
            pattern: 'Value #B',
          },
          {
            unit: 'percentunit',
            type: 'number',
            alias: 'Memory Usage %',
            decimals: 1,
            pattern: 'Value #C',
          },
        ],
      )
      .addTarget(
        promQuery.target(
          'sum(label_replace(container_memory_usage_bytes{env=~"$environment", container!=""}, "pod", "$1", "pod", "(.*)") * on(pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod)',
          format='table',
          instant=true,
        )
      )
      .addTarget(
        promQuery.target(
          'sum(kube_pod_container_resource_requests{resource="memory", unit="byte", env=~"$environment"} * on(pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod)',
          format='table',
          instant=true,
        )
      )
      .addTarget(
        promQuery.target(
          'sum(label_replace(container_memory_usage_bytes{env=~"$environment", container!=""}, "pod", "$1", "pod", "(.*)") * on(pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod) /sum(kube_pod_container_resource_requests{resource="memory", unit="byte", env=~"$environment", } * on(pod) group_left(workload) mixin_pod_workload{env=~"$environment", workload=~"^$' + deploymentKind + '", cluster="$cluster", namespace="$namespace"}) by (pod)',
          format='table',
          instant=true,
        )
      ),
    ], cols=1, rowHeight=10, startRow=startRow),

  network(deploymentKind='Deployment', startRow)::
    layout.grid([
      generalGraphPanel(
        'All processes network I/O',
        decimals=1,
        fill=1,
        formatY1='Bps',
        formatY2='Bps',
      )
      .addTarget(
        promQuery.target(
          'sum (rate (container_network_receive_bytes_total{env=~"$environment", id!="/",pod=~"^$' + deploymentKind + '.*$",node=~"^$Node$", cluster="$cluster", namespace="$namespace"}[1m])) by (pod)',
          legendFormat='-> {{ pod }}',
        )
      )
      .addTarget(
        promQuery.target(
          '- sum( rate (container_network_transmit_bytes_total{env=~"$environment", id!="/",pod=~"^$' + deploymentKind + '.*$",node=~"^$Node$", cluster="$cluster", namespace="$namespace"}[1m])) by (pod)',
          legendFormat='<- {{ pod }}',
        )
      ),
    ], cols=1, rowHeight=10, startRow=startRow),
}
