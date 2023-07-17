local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;

{
  nat_gateway_port_allocation: resourceSaturationPoint({
    title: 'Cloud NAT Gateway Port Allocation',
    severity: 's2',

    // Technically, this is horizontally scalable, but requires us to send out
    // adequate notice to our customers before scaling it up, eg
    // https://gitlab.com/gitlab-org/gitlab/-/merge_requests/37444 and
    // https://gitlab.com/gitlab-com/gl-infra/production/-/issues/3991 for examples
    horizontallyScalable: false,

    staticLabels: {
      type: 'nat',
      tier: 'inf',
      stage: 'main',
    },
    appliesTo: ['nat'],
    description: |||
      Each NAT IP address on a Cloud NAT gateway offers 64,512 TCP source ports and 64,512 UDP source ports.

      When these are exhausted, processes may experience connection problems to external destinations. In the application these
      may manifest as SMTP connection drops or webhook delivery failures. In Kubernetes, nodes may fail while
      attempting to download images from external repositories.

      More details in the Cloud NAT documentation: https://cloud.google.com/nat/docs/ports-and-addresses
    |||,
    grafana_dashboard_uid: 'sat_nat_gw_port_allocation',
    resourceLabels: ['gateway_name', 'project_id'],
    burnRatePeriod: '1h',  // This needs to be high, since the StackDriver export only updates infrequently
    queryFormatConfig: {
      // From https://cloud.google.com/nat/docs/ports-and-addresses#ports
      // Each NAT IP address on a Cloud NAT gateway offers 64,512 TCP source ports
      max_ports_per_nat_ip: 64512,
    },
    query: |||
      sum without(nat_ip) (
        stackdriver_nat_gateway_router_googleapis_com_nat_allocated_ports{
          job="stackdriver",
          %(selector)s
        }
      )
      /
      on(router_id) group_left() (
        %(max_ports_per_nat_ip)d * (count by (router_id) (stackdriver_nat_gateway_router_googleapis_com_nat_allocated_ports{
          job="stackdriver",
          %(selector)s
        })
      ))
    |||,
    slos: {
      soft: 0.85,
      hard: 0.90,
    },
  }),
}
