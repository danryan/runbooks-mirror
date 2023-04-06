local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local rateMetric = metricsCatalog.rateMetric;

metricsCatalog.serviceDefinition({
  type: 'waf',
  tier: 'lb',
  monitoringThresholds: {
    // Error SLO disabled as monitoring data is unreliable.
    // See: https://gitlab.com/gitlab-com/gl-infra/production/-/issues/5465
    //errorRatio: 0.999,
  },
  serviceDependencies: {
    frontend: true,
    nat: true,
  },
  provisioning: {
    kubernetes: false,
    vms: false,
  },
  serviceLevelIndicators: {
    gitlab_zone: {
      severity: 's3',
      team: 'reliability_foundations',
      userImpacting: false,  // Low until CF exporter metric quality increases https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/10294
      featureCategory: 'not_owned',
      description: |||
        Aggregation of all public traffic for GitLab.com passing through the WAF.

        Errors on this SLI may indicate that the WAF has detected
        malicious traffic and is blocking it. It may also indicate
        serious upstream failures on GitLab.com.
      |||,

      requestRate: rateMetric(
        counter='cloudflare_zone_requests_total',
        selector='zone=~"gitlab.com|staging.gitlab.com"'
      ),

      errorRate: rateMetric(
        counter='cloudflare_zone_requests_status',
        selector='zone=~"gitlab.com|staging.gitlab.com", status=~"5.."',
      ),

      significantLabels: [],
    },
    // The "gitlab.net" zone
    gitlab_net_zone: {
      severity: 's3',
      team: 'reliability_foundations',
      userImpacting: false,  // Low until CF exporter metric quality increases https://gitlab.com/gitlab-com/gl-infra/reliability/-/issues/10294
      featureCategory: 'not_owned',
      description: |||
        Aggregation of all GitLab.net (non-pulic) traffic passing through the WAF.

        Errors on this SLI may indicate that the WAF has detected
        malicious traffic and is blocking it.
      |||,

      requestRate: rateMetric(
        counter='cloudflare_zone_requests_total',
        selector='zone="gitlab.net"'
      ),

      errorRate: rateMetric(
        counter='cloudflare_zone_requests_status',
        selector='zone="gitlab.net", status=~"5.."',
      ),

      significantLabels: [],
    },
  },
  skippedMaturityCriteria: {
    'Developer guides exist in developer documentation': 'WAF is an infrastructure component, powered by Cloudflare',
    'Structured logs available in Kibana': 'Logs from CloudFlare are pushed to a GCS bucket by CloudFlare, and not ingested to ElasticSearch due to volume.  See https://gitlab.com/gitlab-com/runbooks/-/blob/master/docs/cloudflare/logging.md for alternatives',
  },
})
