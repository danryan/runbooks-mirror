local aggregationSet = import 'servicemetrics/aggregation-set.libsonnet';

{
  /**
   * promSourceSLIs is an intermediate recording rule representing
   * the "start" of the aggregation pipeline.
   * It collects "raw" source metrics in a prometheus instance and
   * aggregates them, reducing cardinality, before
   * these values are used downstream in Thanos.
   *
   * Should not be used directly for alerting or visualization as it
   * only represents the view from a single prometheus instance,
   * not globally across all shards.
   */
  promSourceSLIs: aggregationSet.AggregationSet({
    id: 'source_sli',
    name: 'Prometheus Source SLI Metrics',
    intermediateSource: true,  // Not intended for consumption in dashboards or alerts
    selector: { monitor: { ne: 'global' } },  // Not Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage'],
    supportedBurnRates: ['1m', '5m', '30m', '1h', '6h'],  // Including 1m & 6h
    offset: '30s',
    metricFormats: {
      apdexSuccessRate: 'gitlab_component_apdex:success:rate_%s',
      apdexWeight: 'gitlab_component_apdex:weight:score_%s',
      opsRate: 'gitlab_component_ops:rate_%s',
      errorRate: 'gitlab_component_errors:rate_%s',
    },
    burnRates: {
      '1m': {
        // TODO: drop the 1m burn rate entirely
        apdexSuccessRate: 'gitlab_component_apdex:success:rate',
        apdexWeight: 'gitlab_component_apdex:weight:score',
        opsRate: 'gitlab_component_ops:rate',
        errorRate: 'gitlab_component_errors:rate',
      },
    },
  }),

  /**
   * componentSLIs consumes promSourceSLIs and is the primary
   * aggregation used for alerting, monitoring, visualizations, etc.
   */
  componentSLIs: aggregationSet.AggregationSet({
    id: 'component',
    name: 'Global SLI Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component'],
    supportedBurnRates: ['1m', '5m', '30m', '1h', '6h', '3d'],  // Including 1m
    offset: '30s',
    metricFormats: {
      apdexRatio: 'gitlab_component_apdex:ratio_%s',
      opsRate: 'gitlab_component_ops:rate_%s',
      errorRate: 'gitlab_component_errors:rate_%s',
      errorRatio: 'gitlab_component_errors:ratio_%s',
    },
    burnRates: {
      '1m': {
        // TODO: drop the 1m burn rate entirely
        apdexRatio: 'gitlab_component_apdex:ratio',
        opsRate: 'gitlab_component_ops:rate',
        errorRate: 'gitlab_component_errors:rate',
        errorRatio: 'gitlab_component_errors:ratio',
      },
    },
  }),

  /**
   * regionalComponentSLIs consumes promSourceSLIs and is the primary
   * aggregation used for alerting, monitoring, visualizations, etc.
   */
  regionalComponentSLIs: aggregationSet.AggregationSet({
    id: 'regional_component',
    name: 'Regional SLI Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'region', 'location', 'component'],
    metricFormats: {
      apdexRatio: 'gitlab_regional_sli_apdex:ratio_%s',
      opsRate: 'gitlab_regional_sli_ops:rate_%s',
      errorRate: 'gitlab_regional_sli_errors:rate_%s',
      errorRatio: 'gitlab_regional_sli_errors:ratio_%s',
    },
    burnRates: {
      '6h': {
        apdexRatio: 'gitlab_regional_sli_apdex:ratio_6h',
        opsRate: 'gitlab_regional_sli_ops:rate_6h',
        errorRatio: 'gitlab_regional_sli_errors:ratio_6h',
      },
      '3d': {
        apdexRatio: 'gitlab_regional_sli_apdex:ratio_3d',
        opsRate: 'gitlab_regional_sli_ops:rate_3d',
        errorRatio: 'gitlab_regional_sli_errors:ratio_3d',
      },
    },
    // Only include components (SLIs) with regional_aggregation="yes"
    aggregationFilter: 'regional',
  }),

  /**
   * promSourceNodeComponentSLIs is an source recording rule representing
   * the "start" of the aggregation pipeline for per-node aggregations,
   * used by Gitaly.
   *
   * It collects "raw" source metrics in a prometheus instance and
   * aggregates them, reducing cardinality, before
   * these values are used downstream in Thanos.
   *
   * Should not be used directly for alerting or visualization as it
   * only represents the view from a single prometheus instance,
   * not globally across all shards.
   */
  promSourceNodeComponentSLIs: aggregationSet.AggregationSet({
    id: 'source_node',
    name: 'Prometheus Source Node-Aggregated SLI Metrics',
    intermediateSource: true,  // Not intended for consumption in dashboards or alerts
    selector: { monitor: { ne: 'global' } },  // Not Thanos Ruler
    labels: ['environment', 'tier', 'type', 'stage', 'shard', 'fqdn', 'component'],
    supportedBurnRates: ['5m', '30m', '1h', '6h'],  // Including 6h
    metricFormats: {
      apdexSuccessRate: 'gitlab_component_node_apdex:success:rate_%s',
      apdexWeight: 'gitlab_component_node_apdex:weight:score_%s',
      opsRate: 'gitlab_component_node_ops:rate_%s',
      errorRate: 'gitlab_component_node_errors:rate_%s',
    },
  }),

  /**
   * nodeComponentSLIs consumes promSourceSLIs and is
   * used for per-node monitoring, alerting, visualzation for Gitaly.
   */
  nodeComponentSLIs: aggregationSet.AggregationSet({
    id: 'component_node',
    name: 'Global Node-Aggregated SLI Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'shard', 'fqdn', 'component'],
    metricFormats: {
      apdexRatio: 'gitlab_component_node_apdex:ratio_%s',
      opsRate: 'gitlab_component_node_ops:rate_%s',
      errorRate: 'gitlab_component_node_errors:rate_%s',
      errorRatio: 'gitlab_component_node_errors:ratio_%s',
    },
    burnRates: {
      '6h': {
        apdexRatio: 'gitlab_component_node_apdex:ratio_6h',
        opsRate: 'gitlab_component_node_ops:rate_6h',
        errorRatio: 'gitlab_component_node_errors:ratio_6h',
      },
      '3d': {
        apdexRatio: 'gitlab_component_node_apdex:ratio_3d',
        opsRate: 'gitlab_component_node_ops:rate_3d',
        errorRatio: 'gitlab_component_node_errors:ratio_3d',
      },
    },
  }),

  /**
   * promSourceShardComponentSLIs is an source recording rule representing
   * the "start" of the aggregation pipeline for per-shard aggregations,
   * used by Sidekiq execution and queueing SLIs.
   *
   * It collects "raw" source metrics in a prometheus instance and
   * aggregates them, reducing cardinality, before
   * these values are used downstream in Thanos.
   *
   * Should not be used directly for alerting or visualization as it
   * only represents the view from a single prometheus instance,
   * not globally across all shards.
   */
  promSourceShardComponentSLIs: aggregationSet.AggregationSet({
    id: 'source_shard',
    name: 'Prometheus Source Shard-Aggregated SLI Metrics',
    intermediateSource: true,  // Not intended for consumption in dashboards or alerts
    selector: { monitor: { ne: 'global' } },  // Not Thanos Ruler
    labels: ['environment', 'tier', 'type', 'stage', 'shard', 'component'],
    metricFormats: {
      apdexSuccessRate: 'gitlab_component_shard_apdex:success:rate_%s',
      apdexWeight: 'gitlab_component_shard_apdex:weight:score_%s',
      opsRate: 'gitlab_component_shard_ops:rate_%s',
      errorRate: 'gitlab_component_shard_errors:rate_%s',
    },
  }),


  /**
   * shardComponentSLIs consumes promSourceSLIs and is
   * used for per-shard monitoring, alerting, visualzation for Sidekiq.
   */
  shardComponentSLIs: aggregationSet.AggregationSet({
    id: 'component_shard',
    name: 'Global Shard-Aggregated SLI Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'shard', 'component'],
    metricFormats: {
      apdexRatio: 'gitlab_component_shard_apdex:ratio_%s',
      opsRate: 'gitlab_component_shard_ops:rate_%s',
      errorRate: 'gitlab_component_shard_errors:rate_%s',
      errorRatio: 'gitlab_component_shard_errors:ratio_%s',
    },
    burnRates: {
      '6h': {
        apdexRatio: 'gitlab_component_shard_apdex:ratio_6h',
        opsRate: 'gitlab_component_shard_ops:rate_6h',
        errorRatio: 'gitlab_component_shard_errors:ratio_6h',
      },
      '3d': {
        apdexRatio: 'gitlab_component_shard_apdex:ratio_3d',
        opsRate: 'gitlab_component_shard_ops:rate_3d',
        errorRatio: 'gitlab_component_shard_errors:ratio_3d',
      },
    },
  }),

  /**
   * serviceSLIs consumes promSourceSLIs and aggregates
   * all the SLIs in a service up to the service level.
   * This is primarily used for visualizations, to give an
   * summary overview of the service. Not used heavily for
   * alerting.
   */
  serviceSLIs: aggregationSet.AggregationSet({
    id: 'service',
    name: 'Global Service-Aggregated Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage'],
    offset: '30s',
    metricFormats: {
      apdexSuccessRate: 'gitlab_service_apdex:success:rate_%s',
      apdexWeight: 'gitlab_service_apdex:weight:score_%s',
      apdexRatio: 'gitlab_service_apdex:ratio_%s',
      opsRate: 'gitlab_service_ops:rate_%s',
      errorRate: 'gitlab_service_errors:rate_%s',
      errorRatio: 'gitlab_service_errors:ratio_%s',
    },
    burnRates: {
      '1m': {
        apdexRatio: 'gitlab_service_apdex:ratio',
        opsRate: 'gitlab_service_ops:rate',
        errorRate: 'gitlab_service_errors:rate',
        errorRatio: 'gitlab_service_errors:ratio',
      },
      '6h': {
        apdexRatio: 'gitlab_service_apdex:ratio_6h',
        opsRate: 'gitlab_service_ops:rate_6h',
        errorRatio: 'gitlab_service_errors:ratio_6h',
      },
      '3d': {
        apdexRatio: 'gitlab_service_apdex:ratio_3d',
        opsRate: 'gitlab_service_ops:rate_3d',
        errorRatio: 'gitlab_service_errors:ratio_3d',
      },
    },
    // Only include components (SLIs) with service_aggregation="yes"
    aggregationFilter: 'service',
  }),

  /**
   * nodeServiceSLIs consumes nodeComponentSLIs and aggregates
   * all the SLIs in a service up to the service level for each node.
   * This is not particularly useful and should probably be reconsidered
   * at a later stage.
   */
  nodeServiceSLIs: aggregationSet.AggregationSet({
    id: 'service_node',
    name: 'Global Service-Node-Aggregated Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'shard', 'fqdn'],
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

  /**
   * Regional SLIs, aggregated to the service level
   */
  regionalServiceSLIs: aggregationSet.AggregationSet({
    id: 'service_regional',
    name: 'Global Service-Regional-Aggregated Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'region'],
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
    // Only include components (SLIs) with regional_aggregation="yes" and service_aggregation="yes"
    aggregationFilter: ['regional', 'service'],
  }),

  featureCategorySourceSLIs: aggregationSet.AggregationSet({
    id: 'source_feature_category',
    name: 'Prometheus Source Feature Category Metrics',
    intermediateSource: true,
    selector: { monitor: { ne: 'global' } },
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component', 'feature_category'],
    offset: '30s',
    metricFormats: {
      apdexSuccessRate: 'gitlab:component:feature_category:execution:apdex:success:rate_%s',
      apdexWeight: 'gitlab:component:feature_category:execution:apdex:weight:score_%s',
      opsRate: 'gitlab:component:feature_category:execution:ops:rate_%s',
      errorRate: 'gitlab:component:feature_category:execution:error:rate_%s',
    },
  }),

  featureCategorySLIs: aggregationSet.AggregationSet({
    id: 'feature_category',
    name: 'Feature Category Metrics',
    intermediateSource: false,
    selector: { monitor: 'global' },
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component', 'feature_category'],
    upscaleLongerBurnRates: true,
    generateSLODashboards: false,
    metricFormats: {
      apdexSuccessRate: 'gitlab:component:feature_category:execution:apdex:success:rate_%s',
      apdexWeight: 'gitlab:component:feature_category:execution:apdex:weight:score_%s',
      opsRate: 'gitlab:component:feature_category:execution:ops:rate_%s',
      errorRate: 'gitlab:component:feature_category:execution:error:rate_%s',
    },
  }),

  serviceComponentStageGroupSLIs: aggregationSet.AggregationSet({
    id: 'service_component_stage_groups',
    name: 'Stage Group Service-And-Component-Aggregated Metrics',
    intermediateSource: false,
    selector: { monitor: 'global' },
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component', 'stage_group', 'product_stage'],
    generateSLODashboards: false,
    upscaleLongerBurnRates: true,
    offset: '30s',
    joinSource: {
      metric: 'gitlab:feature_category:stage_group:mapping',
      selector: { monitor: 'global' },
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

  stageGroupSLIs: aggregationSet.AggregationSet({
    id: 'stage_groups',
    name: 'Stage Group Metrics',
    intermediateSource: false,
    selector: { monitor: 'global' },
    labels: ['env', 'environment', 'stage', 'stage_group', 'product_stage'],
    generateSLODashboards: false,
    offset: '30s',
    joinSource: {
      metric: 'gitlab:feature_category:stage_group:mapping',
      selector: { monitor: 'global' },
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


  /**
   * componentSLIs consumes promSourceSLIs and is the primary
   * aggregation used for alerting, monitoring, visualizations, etc.
   */
  globallyEvaluatedSourceSLIs: aggregationSet.AggregationSet({
    id: 'globeval_source',
    name: 'Global SLI Source Metrics',
    intermediateSource: true,
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component'],
    supportedBurnRates: ['5m', '30m', '1h', '6h', '3d'],
    metricFormats: {
      apdexSuccessRate: 'gitlab_component_apdex:success:rate_%s',
      apdexWeight: 'gitlab_component_apdex:weight:score_%s',
      opsRate: 'gitlab_component_ops:rate_%s',
      errorRate: 'gitlab_component_errors:rate_%s',
    },
  }),

  /**
   * This is a special aggregation set, only used with dangerouslyThanosEvaluated services
   * for thanos self monitoring.
   */
  globallyEvaluatedSLIs: aggregationSet.AggregationSet({
    id: 'globeval_component',
    name: 'Globally evaluated SLI Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage', 'component'],
    supportedBurnRates: ['5m', '30m', '1h', '6h', '3d'],
    metricFormats: {
      apdexRatio: 'gitlab_component_apdex:ratio_%s',
      errorRatio: 'gitlab_component_errors:ratio_%s',
    },
    aggregationFilter: 'global',
    offset: '30s',
  }),

  globallyEvaluatedServiceSLIs: aggregationSet.AggregationSet({
    id: 'globeval_service',
    name: 'Global evaluated Service-Aggregated Metrics',
    intermediateSource: false,  // Used in dashboards and alerts
    selector: { monitor: 'global' },  // Thanos Ruler
    labels: ['env', 'environment', 'tier', 'type', 'stage'],
    supportedBurnRates: ['5m', '30m', '1h', '6h', '3d'],
    metricFormats: {
      apdexRatio: 'gitlab_service_apdex:ratio_%s',
      opsRate: 'gitlab_service_ops:rate_%s',
      errorRatio: 'gitlab_service_errors:ratio_%s',
    },
    // Only include components (SLIs) with service_aggregation="yes" and global_aggregation="yes"
    aggregationFilter: ['service', 'global'],
    offset: '30s',
  }),
}
