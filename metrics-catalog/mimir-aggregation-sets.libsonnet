local aggregationSet = (import 'servicemetrics/aggregation-set.libsonnet').AggregationSet;

local mimirAggregetionSetDefaults = {
  intermediateSource: false,
  selector: { monitor: 'global' },
  offset: '30s',
  recordingRuleStaticLabels: {
    // This is to ensure compatibility with the current thanos aggregations.
    // This makes sure that the dashboards would pick these up.
    // When we don't have thanos aggregations anymore, we can remove the selector
    // and static labels from these aggregation sets
    // https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2902
    monitor: 'global',
  },
};

{
  componentSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'component',
    name: 'Global SLI Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component'],
    upscaleLongerBurnRates: true,
    metricFormats: {
      apdexWeight: 'gitlab_component_apdex:weight:score_%s',
      apdexSuccessRate: 'gitlab_component_apdex:success:rate_%s',
      apdexRatio: 'gitlab_component_apdex:ratio_%s',
      opsRate: 'gitlab_component_ops:rate_%s',
      errorRate: 'gitlab_component_errors:rate_%s',
      errorRatio: 'gitlab_component_errors:ratio_%s',

      // Confidence Interval Ratios
      apdexConfidenceRatio: 'gitlab_component_apdex:confidence:ratio_%s',
      errorConfidenceRatio: 'gitlab_component_errors:confidence:ratio_%s',
    },
  }),

  serviceSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'service',
    name: 'Global Service-Aggregated Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage'],
    sourceAggregationSet: $.componentSLIs,
    metricFormats: {
      apdexSuccessRate: 'gitlab_service_apdex:success:rate_%s',
      apdexWeight: 'gitlab_service_apdex:weight:score_%s',
      apdexRatio: 'gitlab_service_apdex:ratio_%s',
      opsRate: 'gitlab_service_ops:rate_%s',
      errorRate: 'gitlab_service_errors:rate_%s',
      errorRatio: 'gitlab_service_errors:ratio_%s',
    },
    aggregationFilter: 'service',
  }),

  nodeComponentSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'component_node',
    name: 'Global Node-Aggregated SLI Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'shard', 'fqdn', 'component'],
    upscaleLongerBurnRates: true,
    slisForService(serviceDefinition): if serviceDefinition.monitoring.node.enabled then serviceDefinition.listServiceLevelIndicators() else [],
    metricFormats: {
      apdexSuccessRate: 'gitlab_component_node_apdex:success:rate_%s',
      apdexWeight: 'gitlab_component_node_apdex:weight:score_%s',
      apdexRatio: 'gitlab_component_node_apdex:ratio_%s',
      opsRate: 'gitlab_component_node_ops:rate_%s',
      errorRate: 'gitlab_component_node_errors:rate_%s',
      errorRatio: 'gitlab_component_node_errors:ratio_%s',
    },
  }),

  nodeServiceSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'service_node',
    name: 'Global Service-Node-Aggregated Metrics',
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'shard', 'fqdn'],
    sourceAggregationSet: $.nodeComponentSLIs,
    enabledForService(serviceDefinition): serviceDefinition.monitoring.node.enabled,
    metricFormats: {
      apdexRatio: 'gitlab_service_node_apdex:ratio_%s',
      opsRate: 'gitlab_service_node_ops:rate_%s',
      errorRate: 'gitlab_service_node_errors:rate_%s',
      errorRatio: 'gitlab_service_node_errors:ratio_%s',
    },
    burnRates: {
      '6h': {
        apdexRatio: 'gitlab_service_node_apdex:ratio_6h',
        opsRate: 'gitlab_service_node_ops:rate_6h',
        errorRatio: 'gitlab_service_node_errors:ratio_6h',
      },
      '3d': {
        apdexRatio: 'gitlab_service_node_apdex:ratio_3d',
        opsRate: 'gitlab_service_node_ops:rate_3d',
        errorRatio: 'gitlab_service_node_errors:ratio_3d',
      },
    },
    // Only include components (SLIs) with service_aggregation="yes"
    aggregationFilter: 'service',
  }),

  regionalComponentSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'regional_component',
    name: 'Regional SLI Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'region', 'component'],
    slisForService(serviceDefinition): std.filter(function(sli) sli.regional, serviceDefinition.listServiceLevelIndicators()),
    upscaleLongerBurnRates: true,
    metricFormats: {
      apdexSuccessRate: 'gitlab_regional_sli_apdex:success:rate_%s',
      apdexWeight: 'gitlab_regional_sli_apdex:weight:score_%s',
      apdexRatio: 'gitlab_regional_sli_apdex:ratio_%s',
      opsRate: 'gitlab_regional_sli_ops:rate_%s',
      errorRate: 'gitlab_regional_sli_errors:rate_%s',
      errorRatio: 'gitlab_regional_sli_errors:ratio_%s',
      // Confidence Interval Ratios
      apdexConfidenceRatio: 'gitlab_regional_sli_apdex:confidence:ratio_%s',
      errorConfidenceRatio: 'gitlab_regional_sli_errors:confidence:ratio_%s',
    },
  }),

  regionalServiceSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'service_regional',
    name: 'Global Service-Regional-Aggregated Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'region'],
    sourceAggregationSet: $.regionalComponentSLIs,
    enabledForService(serviceDefinition): serviceDefinition.regional,
    metricFormats: {
      apdexRatio: 'gitlab_service_regional_apdex:ratio_%s',
      opsRate: 'gitlab_service_regional_ops:rate_%s',
      errorRate: 'gitlab_service_regional_errors:rate_%s',
      errorRatio: 'gitlab_service_regional_errors:ratio_%s',
    },
    burnRates: {
      '6h': {
        apdexRatio: 'gitlab_service_regional_apdex:ratio_6h',
        opsRate: 'gitlab_service_regional_ops:rate_6h',
        errorRatio: 'gitlab_service_regional_errors:ratio_6h',
      },
      '3d': {
        apdexRatio: 'gitlab_service_regional_apdex:ratio_3d',
        opsRate: 'gitlab_service_regional_ops:rate_3d',
        errorRatio: 'gitlab_service_regional_errors:ratio_3d',
      },
    },
    aggregationFilter: ['regional', 'service'],
  }),

  shardComponentSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'component_shard',
    name: 'Global Shard-Aggregated SLI Metrics',
    selector: { monitor: 'global' },
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'shard', 'component'],
    upscaleLongerBurnRates: true,
    slisForService(serviceDefinition):
      std.filter(
        function(sli)
          sli.shardLevelMonitoring,
        serviceDefinition.listServiceLevelIndicators()
      ),
    metricFormats: {
      apdexSuccessRate: 'gitlab_component_shard_apdex:success:rate_%s',
      apdexWeight: 'gitlab_component_shard_apdex:weight:score_%s',
      apdexRatio: 'gitlab_component_shard_apdex:ratio_%s',
      opsRate: 'gitlab_component_shard_ops:rate_%s',
      errorRate: 'gitlab_component_shard_errors:rate_%s',
      errorRatio: 'gitlab_component_shard_errors:ratio_%s',
    },
  }),

  featureCategorySLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'feature_category',
    name: 'Feature Category Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component', 'feature_category'],
    slisForService(serviceDefinition): std.filter(function(indicator) indicator.hasFeatureCategory(), serviceDefinition.listServiceLevelIndicators()),
    upscaleLongerBurnRates: true,
    generateSLODashboards: false,
    metricFormats: {
      apdexSuccessRate: 'gitlab:component:feature_category:execution:apdex:success:rate_%s',
      apdexWeight: 'gitlab:component:feature_category:execution:apdex:weight:score_%s',
      opsRate: 'gitlab:component:feature_category:execution:ops:rate_%s',
      errorRate: 'gitlab:component:feature_category:execution:error:rate_%s',
    },
  }),

  serviceComponentStageGroupSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'service_component_stage_groups',
    name: 'Stage Group Service-And-Component-Aggregated Metrics',
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component', 'stage_group', 'product_stage'],
    generateSLODashboards: false,
    upscaleLongerBurnRates: false,
    sourceAggregationSet: $.featureCategorySLIs,
    joinSource: {
      metric: 'gitlab:feature_category:stage_group:mapping',
      on: ['feature_category'],
      labels: ['stage_group', 'product_stage'],
    },
    metricFormats: {
      apdexSuccessRate: 'gitlab:component:stage_group:execution:apdex:success:rate_%s',
      apdexWeight: 'gitlab:component:stage_group:execution:apdex:weight:score_%s',
      apdexRatio: 'gitlab:component:stage_group:execution:apdex:ratio_%s',
      opsRate: 'gitlab:component:stage_group:execution:ops:rate_%s',
      errorRate: 'gitlab:component:stage_group:execution:error:rate_%s',
      errorRatio: 'gitlab:component:stage_group:execution:error:ratio_%s',
    },
  }),

  stageGroupSLIs: aggregationSet(mimirAggregetionSetDefaults {
    id: 'stage_groups',
    name: 'Stage Group Metrics',
    labels: ['env', 'environment', 'stage', 'stage_group', 'product_stage'],
    generateSLODashboards: false,
    upscaleLongerBurnRates: false,
    offset: '30s',
    sourceAggregationSet: $.featureCategorySLIs,
    joinSource: {
      metric: 'gitlab:feature_category:stage_group:mapping',
      on: ['feature_category'],
      labels: ['stage_group', 'product_stage'],
    },
    metricFormats: {
      apdexSuccessRate: 'gitlab:stage_group:execution:apdex:success:rate_%s',
      apdexWeight: 'gitlab:stage_group:execution:apdex:weight:score_%s',
      apdexRatio: 'gitlab:stage_group:execution:apdex:ratio_%s',
      opsRate: 'gitlab:stage_group:execution:ops:rate_%s',
      errorRate: 'gitlab:stage_group:execution:error:rate_%s',
      errorRatio: 'gitlab:stage_group:execution:error:ratio_%s',
    },
  }),

  aggregationsFromSource::
    std.filter(
      function(aggregationSet)
        aggregationSet.sourceAggregationSet == null,
      std.objectValues(self)
    ),

  transformedAggregations::
    std.filter(
      function(aggregationSet)
        aggregationSet.sourceAggregationSet != null,
      std.objectValues(self)
    ),
}
