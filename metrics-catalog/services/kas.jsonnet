local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local baseSelector = {
    type: 'kas',
};

metricsCatalog.serviceDefinition({
  type: 'kas',
  tier: 'sv',
  tenants: ['gitlab-gprd', 'gitlab-gstg', 'gitlab-pre'],

  tags: ['golang'],

  monitoringThresholds: {
    apdexScore: 0.95,
    errorRatio: 0.9995,
  },
  otherThresholds: {
    // Deployment thresholds are optional, and when they are specified, they are
    // measured against the same multi-burn-rates as the monitoring indicators.
    // When a service is in violation, deployments may be blocked or may be rolled
    // back.
    deployment: {
      apdexScore: 0.95,
      errorRatio: 0.9995,
    },
  },
  serviceDependencies: {
    api: true,
    gitaly: true,
    kas: true,
    redis: true,
  },
  provisioning: {
    kubernetes: true,
    vms: false,
  },
  kubeResources: {
    kas: {
      kind: 'Deployment',
      containers: [
        'kas',
      ],
    },
  },
  serviceLevelIndicators: {
    grpc_requests: {
      userImpacting: true,
      featureCategory: 'deployment_management',

      apdex: histogramApdex(
        histogram='tunnel_routing_duration_seconds_bucket',
        selector=baseSelector {
          // The `success` status contains durations up to 20s and
          // the `timeout` would contain everything above that.
          // However, if no agent is connected at the time of the proxy request,
          // (because it simply isn't or is reconnecting) this is NOT an actual
          // issue with KAS itself, but with the customers infrastructure.
          // Therefore, we only select for `success` statuses for now and will
          // look into how we can improve the Apdex score long-term.
          // status: { oneOf: ['success', 'timeout'] },
          status: { oneOf: ['success'] },
        },
        satisfiedThreshold=4.096,
      ),

      requestRate: rateMetric(
        counter='grpc_server_handled_total',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='grpc_server_handled_total',
        selector=baseSelector {
          grpc_code: { nre: '^(OK|NotFound|PaymentRequired|FailedPrecondition|Unauthenticated|PermissionDenied|Canceled|DeadlineExceeded|ResourceExhausted)$' },
          grpc_service: { ne: 'gitlab.agent.kubernetes_api.rpc.KubernetesApi' },
        },
      ),

      significantLabels: ['grpc_method'],

      toolingLinks: [
        toolingLinks.sentry(projectId=11, variables=['environment']),
        toolingLinks.kibana(title='Kubernetes Agent Server', index='kas', type='kas'),
      ],
    },
    connections: {
      userImpacting: true,
      featureCategory: 'deployment_management',

      requestRate: rateMetric(
        counter='accepted_connections_total',
        selector=baseSelector
      ),

      errorRate: rateMetric(
        counter='redis_expiring_hash_api_gc_deleted_keys_count_total',
        selector=baseSelector {
          expiring_hash_name: { re: '^listener_conns_' },
        },
      ),

      significantLabels: ['expiring_hash_name'],
    },
  },
} + {
  capacityPlanning+: {
    components: [
      {
        name: 'kube_container_memory',
        parameters: {
          ignore_outliers: [
            {
              // https://gitlab.com/gitlab-com/gl-infra/production/-/issues/17753
              start: '2024-03-08',
              end: '2024-03-25',
            },
          ],
        },
      },
      {
        name: 'kube_go_memory',
        parameters: {
          ignore_outliers: [
            {
              // https://gitlab.com/gitlab-com/gl-infra/production/-/issues/17753
              start: '2024-03-08',
              end: '2024-03-25',
            },
          ],
        },
      },
    ],
  },
})
