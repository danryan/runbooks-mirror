local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local gaugeMetric = metricsCatalog.gaugeMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';
local runwayHelper = import 'service-archetypes/helpers/runway.libsonnet';
local googleLoadBalancerComponents = import 'services/lib/google_load_balancer_components.libsonnet';

// Default Runway SLIs
function(
  type,
  team,
  apdexScore=0.999,
  errorRatio=0.999,
  // When using stackdriver_cloud_run_revision_run_googleapis_com_request_latencies_bucket as source metrics request latencies are put into specific
  // buckets this number is chosen to align with the closest desirable bucket see buckets here https://dashboards.gitlab.net/goto/vnxXtRZHg?orgId=1
  apdexSatisfiedThreshold='1067.1895716335973',
  featureCategory='not_owned',
  userImpacting=true,
  trafficCessationAlertConfig=true,
  severity='s4',
  customToolingLinks=[],
  regional=false,
  externalLoadBalancer=true,
  tags=[],
)
  local baseSelector = { type: type };
  {
    type: type,
    tier: 'sv',

    tenants: ['runway'],

    tags: tags,

    monitoringThresholds: {
      apdexScore: apdexScore,
      errorRatio: errorRatio,
    },

    provisioning: {
      vms: false,
      kubernetes: false,
      runway: true,
    },

    // Runway splits traffic between multiple revisions for canary deployments
    serviceIsStageless: true,

    dangerouslyThanosEvaluated: true,

    // Set true for multi-region deployments
    // https://gitlab-com.gitlab.io/gl-infra/platform/runway/runwayctl/manifest.schema.html#spec_regions
    regional: regional,

    serviceLevelIndicators: {
      runway_ingress: {
        description: |||
          Application load balancer serving ingress HTTP requests for the Runway service.
        |||,

        apdex: histogramApdex(
          histogram='stackdriver_cloud_run_revision_run_googleapis_com_request_latencies_bucket',
          rangeVectorFunction='avg_over_time',
          selector=baseSelector { response_code_class: { noneOf: ['4xx', '5xx'] } },
          satisfiedThreshold=apdexSatisfiedThreshold,
          unit='ms',
        ),

        requestRate: gaugeMetric(
          gauge='stackdriver_cloud_run_revision_run_googleapis_com_request_count',
          selector=baseSelector,
          samplingInterval=60,  //seconds. See https://cloud.google.com/monitoring/api/metrics_gcp#run/request_count
        ),

        errorRate: gaugeMetric(
          gauge='stackdriver_cloud_run_revision_run_googleapis_com_request_count',
          selector=baseSelector { response_code_class: '5xx' },
          samplingInterval=60,
        ),

        significantLabels:
          ['revision_name', 'response_code']
          + runwayHelper.labels(self)
          // In thanos the regional label on source metrics coming from stackdriver-exporter
          // is not respected. To work around this we use the `location` label.
          // We can remove this once we switch to mimir.
          // https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/3398
          + if regional then ['location'] else [],


        userImpacting: userImpacting,

        trafficCessationAlertConfig: trafficCessationAlertConfig,

        team: team,

        featureCategory: featureCategory,

        severity: severity,

        toolingLinks: [
          toolingLinks.googleCloudRun(
            serviceName=type,
            project='gitlab-runway-production',
            gcpRegion='us-east1'
          ),
        ] + customToolingLinks,
      },

      [if externalLoadBalancer then 'runway_lb']: googleLoadBalancerComponents.googleLoadBalancer(
        userImpacting=userImpacting,
        trafficCessationAlertConfig=trafficCessationAlertConfig,
        team=team,
        featureCategory=featureCategory,
        loadBalancerName='%(type)s-url-map' % type,
        projectId='gitlab-runway-production',
        baseSelector={ job: 'runway-exporter', url_map_name: '%(type)s-url-map' % type },
        serviceAggregation=false,
        extra={
          severity: severity,
          description: |||
            External load balancer serving global HTTP requests for the Runway service.
          |||,
        },
      ),
    },

    skippedMaturityCriteria: {
      'Structured logs available in Kibana': 'Runway structured logs are temporarily available in Stackdriver',
      'Service exists in the dependency graph': 'Runway services are deployed outside of the monolith',
    },
  }
