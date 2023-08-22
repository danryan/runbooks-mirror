local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';

// Default SLIs/SLOs for Runway services
function(
  type,
  team,
  runwayServiceID,
  apdexScore=0.999,
  errorRatio=0.999,
  apdexSatisfiedThreshold=1024,
  featureCategory='not_owned',
  userImpacting=true,
  trafficCessationAlertConfig=true,
  severity='s4',
)
  local baseSelector = { service_name: runwayServiceID };
  {
    type: type,
    tier: 'sv',

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

    runwayConfig: {
      id: runwayServiceID,
    },

    serviceLevelIndicators: {
      runway_ingress: {
        description: |||
          Application load balancer serving ingress HTTP requests for the Runway service.
        |||,

        apdex: histogramApdex(
          histogram='stackdriver_cloud_run_revision_run_googleapis_com_request_latencies_bucket',
          selector=baseSelector,
          satisfiedThreshold=apdexSatisfiedThreshold
        ),

        requestRate: rateMetric(
          counter='stackdriver_cloud_run_revision_run_googleapis_com_request_count',
          selector=baseSelector,
        ),

        errorRate: rateMetric(
          counter='stackdriver_cloud_run_revision_run_googleapis_com_request_count',
          selector=baseSelector { response_code_class: '5xx' },
        ),

        significantLabels: ['revision_name', 'response_code', 'route'],

        userImpacting: userImpacting,

        trafficCessationAlertConfig: trafficCessationAlertConfig,

        team: team,

        featureCategory: featureCategory,

        severity: severity,

        toolingLinks: [
          toolingLinks.googleCloudRun(
            serviceName=runwayServiceID,
            project='gitlab-runway-production',
            gcpRegion='us-east1'
          ),
        ],
      },
    },

    skippedMaturityCriteria: {
      'Structured logs available in Kibana': 'Runway structured logs are temporarily available in Stackdriver',
      'Service exists in the dependency graph': 'Runway services are deployed outside of the monolith',
    },
  }