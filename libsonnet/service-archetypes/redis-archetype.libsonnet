local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local histogramApdex = metricsCatalog.histogramApdex;
local rateMetric = metricsCatalog.rateMetric;
local kubeLabelSelectors = metricsCatalog.kubeLabelSelectors;

function(
  type,
  descriptiveName,
  featureCategory='not_owned',
  redisCluster=false,
)
  local baseSelector = { type: type };
  local formatConfig = {
    descriptiveName: descriptiveName,
  };

  {
    type: type,
    tier: 'db',
    provisioning: {
      vms: true,
      kubernetes: true,
    },
    serviceIsStageless: true,  // We don't have cny stage for Redis instances

    tags: [
      // redis tag signifies that this service has redis-exporter
      'redis',
      if redisCluster then 'redis-cluster' else 'redis-sentinel',
    ],

    monitoringThresholds: {
      apdexScore: 0.9999,
      errorRatio: 0.999,
    },


    kubeConfig: {
      labelSelectors: kubeLabelSelectors(
        ingressSelector=null,
        nodeSelector=baseSelector,
      ),
    },
    kubeResources: {
      redis: {
        kind: 'Deployment',
        containers: [
          type,
        ],
      },
    },
    serviceLevelIndicators: {
      primary_server: {
        apdexSkip: 'apdex for redis is measured clientside',
        userImpacting: true,
        featureCategory: featureCategory,
        serviceAggregation: false,
        description: |||
          Operations on the Redis primary for %(descriptiveName)s instance.
        ||| % formatConfig,

        requestRate: rateMetric(
          counter='redis_commands_processed_total',
          selector=baseSelector,
          filterExpr='and on (instance) redis_instance_info{role="master"}'
        ),

        significantLabels: ['instance'],

        toolingLinks: [],
      },

      secondary_servers: {
        apdexSkip: 'apdex for redis is measured clientside',
        userImpacting: true,  // userImpacting for data redundancy reasons
        featureCategory: featureCategory,
        description: |||
          Operations on the Redis secondaries for the %(descriptiveName)s instance.
        ||| % formatConfig,

        requestRate: rateMetric(
          counter='redis_commands_processed_total',
          selector=baseSelector,
          filterExpr='and on (instance) redis_instance_info{role="slave"}'
        ),

        significantLabels: ['instance'],
        serviceAggregation: false,
      },
    },
    skippedMaturityCriteria: {
      'Logging includes metadata for measuring scalability': "Metadata can't be injected in redis logs",
    },
  }
