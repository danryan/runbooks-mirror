local metricsCatalog = import './metrics-catalog.libsonnet';
local alerts = import 'alerts/alerts.libsonnet';
local labelTaxonomy = import 'label-taxonomy/label-taxonomy.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local stableIds = import 'stable-ids/stable-ids.libsonnet';
local durationParser = import 'utils/duration-parser.libsonnet';
local strings = import 'utils/strings.libsonnet';
local validator = import 'utils/validator.libsonnet';
local capacityPlanning = (import 'capacity-planning/validator.libsonnet');
local filterLabelsFromLabelsHash = (import 'promql/labels.libsonnet').filterLabelsFromLabelsHash;
local aggregations = import 'promql/aggregations.libsonnet';

// The severity labels that we allow on resources
local severities = std.set(['s1', 's2', 's3', 's4']);

local environmentLabels = labelTaxonomy.labelTaxonomy(
  labelTaxonomy.labels.environment |
  labelTaxonomy.labels.tier |
  labelTaxonomy.labels.service |
  labelTaxonomy.labels.stage |
  labelTaxonomy.labels.shard
);

local defaultAlertingLabels =
  labelTaxonomy.labels.environment |
  labelTaxonomy.labels.service |
  labelTaxonomy.labels.stage;

local recordedQuantiles = [0.95, 0.99];

local sloValidator = validator.validator(function(v) v > 0 && v <= 1, 'SLO threshold should be in the range (0,1]');

local quantileValidator = validator.validator(function(v) std.isNumber(v) && (v > 0 && v < 1) || v == 'max', 'value should be in the range (0,1) or the string "max"');

local positiveNumber = validator.validator(function(v) v >= 0, 'Number should be >= 0');

local definitionValidor = validator.new({
  title: validator.string,
  severity: validator.setMember(severities),
  horizontallyScalable: validator.boolean,
  appliesTo: validator.array,
  description: validator.string,
  grafana_dashboard_uid: validator.string,
  resourceLabels: validator.array,
  query: validator.string,
  quantileAggregation: quantileValidator,
  linear_prediction_saturation_alert: validator.optional(validator.duration),
  alerting: {
    // TODO: we should move all of the alerting attributes in here
    // https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2562
    enabled: validator.boolean,
  },
  slos: {
    soft: sloValidator,
    hard: sloValidator,
  },
  useResourceLabelsAsMaxAggregationLabels: validator.boolean,
} + capacityPlanning);

local simpleDefaults = {
  queryFormatConfig: {},
  alertRunbook: 'docs/{{ $labels.type }}/README.md',
  dangerouslyThanosEvaluated: false,
  quantileAggregation: 'max',
  linear_prediction_saturation_alert: null,  // No linear interpolation by default
  useResourceLabelsAsMaxAggregationLabels: false,
};

local nestedDefaults = {
  capacityPlanning+: {
    strategy: 'quantile95_1h',
    forecast_days: 90,
    historical_days: 365,
    changepoints_count: 25,
  },
  alerting: {
    enabled: true,
  },
  slos: {
    alertTriggerDuration: '5m',
  },
};

local validateAndApplyDefaults(definition) =
  local merged = simpleDefaults + std.mergePatch(nestedDefaults, definition);
  definitionValidor.assertValid(merged);

local filterServicesForResource(definition, evaluation, thanosSelfMonitoring) =
  std.filter(
    function(type)
      local service = metricsCatalog.getServiceOptional(type);
      service != null && (
        if thanosSelfMonitoring then
          assert evaluation == 'thanos' : 'thanos-saturation needs to be globally evaluated in thanos, not %s' % [evaluation];
          type == 'thanos'
        else if evaluation == 'prometheus' then
          !(service.dangerouslyThanosEvaluated || service.type == 'mimir') && !definition.dangerouslyThanosEvaluated
        else if evaluation == 'thanos' then
          type != 'thanos' && (service.dangerouslyThanosEvaluated || definition.dangerouslyThanosEvaluated)
        else if evaluation == 'both' then
          true
        else
          assert false : 'unknown evaluation type %s' % [evaluation];
          false
      ),
    definition.appliesTo
  );

// TODO: replace this with oneOf and make oneOf smarter
// with single values
local oneOfType(appliesTo) =
  if std.length(appliesTo) > 1 then
    { type: { re: std.join('|', appliesTo) } }
  else
    { type: appliesTo[0] };

local generateSaturationAlerts(definition, componentName, selectorHash) =
  local triggerDuration = definition.slos.alertTriggerDuration;

  local selectorHashWithComponent = selectorHash {
    component: componentName,
  };

  local labels = labelTaxonomy.labelTaxonomy(defaultAlertingLabels);
  local labelsHash = std.foldl(
    function(memo, label)
      memo { [label]: '{{ $labels.%s }}' % [label] },
    labels,
    {}
  );
  // Don't filter with the static labels included, the static labels will overwrite
  // anything that is on the source metrics, so won't match the labels on the alert
  local labelsHashWithoutStaticLabels = selectors.without(labelsHash, definition.getStaticLabels());

  local stageLabel = labelTaxonomy.getLabelFor(labelTaxonomy.labels.stage, default='');

  local formatConfig = {
    triggerDuration: triggerDuration,
    componentName: componentName,
    description: definition.description,
    title: definition.title,
    selector: selectors.serializeHash(selectorHashWithComponent),
    titleStage: if stageLabel == '' then '' else ' ({{ $labels.%s }} stage)' % [stageLabel],
    hardSLOSelector: selectors.serializeHash(selectors.without(selectorHashWithComponent, ['type', 'env'])),
  };

  local severityLabels =
    { severity: definition.severity } +
    if definition.severity == 's1' || definition.severity == 's2' then
      { pager: 'pagerduty' }
    else
      {};

  local commonAlertDefinition = {
    'for': triggerDuration,
    labels: {
      rules_domain: 'general',
      alert_type: 'cause',
    } + severityLabels,
    annotations: {
      runbook: definition.alertRunbook,
      grafana_dashboard_id: 'alerts-' + definition.grafana_dashboard_uid,
      grafana_panel_id: stableIds.hashStableId('saturation-' + componentName),
      grafana_variables: labelTaxonomy.labelTaxonomySerialized(defaultAlertingLabels),
      grafana_min_zoom_hours: '6',
      promql_query: definition.getQuery(labelsHashWithoutStaticLabels, definition.getBurnRatePeriod(), definition.resourceLabels),
      promql_template_1: definition.getQuery(labelsHashWithoutStaticLabels, definition.getBurnRatePeriod(), definition.resourceLabels),
    },
  };

  [alerts.processAlertRule(commonAlertDefinition {
    alert: 'component_saturation_slo_out_of_bounds:%(component)s' % {
      component: componentName,
    },
    expr: |||
      gitlab_component_saturation:ratio{%(selector)s} > on(component) group_left
      slo:max:hard:gitlab_component_saturation:ratio{%(hardSLOSelector)s}
    ||| % formatConfig,
    annotations+: {
      title: 'The %(title)s resource of the {{ $labels.type }} service%(titleStage)s has a saturation exceeding SLO and is close to its capacity limit.' % formatConfig,
      description: |||
        This means that this resource is running close to capacity and is at risk of exceeding its current capacity limit.

        Details of the %(title)s resource:

        %(description)s
      ||| % formatConfig,
    },
  })] +
  (if definition.linear_prediction_saturation_alert != null then
     local formatConfig2 = formatConfig {
       linearPredictionDuration: definition.linear_prediction_saturation_alert,
       linearPredictionDurationSeconds: durationParser.toSeconds(definition.linear_prediction_saturation_alert),
     };
     [alerts.processAlertRule(commonAlertDefinition {
       alert: 'ComponentResourceRunningOut_' + componentName,
       expr: |||
         predict_linear(gitlab_component_saturation:ratio{%(selector)s}[%(linearPredictionDuration)s], %(linearPredictionDurationSeconds)d)
         > on (component) group_left
         slo:max:hard:gitlab_component_saturation:ratio{%(hardSLOSelector)s}
       ||| % formatConfig2,
       labels+: {
         linear_prediction_saturation_alert: definition.linear_prediction_saturation_alert,
       },
       annotations+: {
         title: 'The %(title)s resource of the {{ $labels.type }} service%(titleStage)s is on track to hit capacity within %(linearPredictionDuration)s' % formatConfig2,
         description: |||
           This means that this resource is growing rapidly and is predicted to exceed saturation threshold within %(linearPredictionDuration)s.

           Details of the %(title)s resource:

           %(description)s
         ||| % formatConfig2,
       },
     })]
   else
     []);


local resourceSaturationPoint = function(options)
  local definition = validateAndApplyDefaults(options);
  local serviceApplicator = function(type) std.setMember(type, std.set(definition.appliesTo));

  definition {
    getQuery(selectorHash, rangeInterval, maxAggregationLabels=[], extraStaticLabels={})::
      local staticLabels = self.getStaticLabels() + extraStaticLabels;
      local environmentLabelsLocal = (if self.dangerouslyThanosEvaluated == true then labelTaxonomy.labelTaxonomy(labelTaxonomy.labels.environmentThanos) else []) + environmentLabels;
      local queryAggregationLabels = environmentLabelsLocal + self.resourceLabels;
      local allMaxAggregationLabels = environmentLabelsLocal + maxAggregationLabels;
      local queryAggregationLabelsExcludingStaticLabels = filterLabelsFromLabelsHash(queryAggregationLabels, staticLabels);
      local maxAggregationLabelsExcludingStaticLabels = filterLabelsFromLabelsHash(allMaxAggregationLabels, staticLabels);
      local queryFormatConfig = self.queryFormatConfig;

      local preaggregation = self.query % queryFormatConfig {
        rangeInterval: rangeInterval,
        selector: selectors.serializeHash(selectorHash),
        selectorWithoutType: selectors.serializeHash(selectors.without(selectorHash, ['type'])),
        aggregationLabels: aggregations.join(queryAggregationLabelsExcludingStaticLabels),
      };

      local clampedPreaggregation = |||
        clamp_min(
          clamp_max(
            %(query)s
            ,
            1)
        ,
        0)
      ||| % {
        query: strings.indent(preaggregation, 4),
      };

      if definition.quantileAggregation == 'max' then
        |||
          max by(%(maxAggregationLabels)s) (
            %(quantileOverTimeQuery)s
          )
        ||| % {
          quantileOverTimeQuery: strings.indent(clampedPreaggregation, 2),
          maxAggregationLabels: aggregations.join(maxAggregationLabelsExcludingStaticLabels),
        }
      else
        |||
          quantile by(%(maxAggregationLabels)s) (
            %(quantileAggregation)g,
            %(quantileOverTimeQuery)s
          )
        ||| % {
          quantileAggregation: definition.quantileAggregation,
          quantileOverTimeQuery: strings.indent(clampedPreaggregation, 2),
          maxAggregationLabels: aggregations.join(maxAggregationLabelsExcludingStaticLabels),
        }
    ,

    getLegendFormat()::
      if std.length(definition.resourceLabels) > 0 then
        std.join(' ', std.map(function(f) '{{ ' + f + ' }}', definition.resourceLabels))
      else
        '{{ type }}',

    getStaticLabels()::
      ({ staticLabels: {} } + definition).staticLabels,

    // This signifies the minimum period over which this resource is
    // evaluated. Defaults to 1m, which is the legacy value
    getBurnRatePeriod()::
      ({ burnRatePeriod: '1m' } + self).burnRatePeriod,

    hasServicesForResource(evaluation, thanosSelfMonitoring)::
      std.length(filterServicesForResource(self, evaluation, thanosSelfMonitoring)) > 0,

    getRecordingRuleDefinition(componentName, evaluation, thanosSelfMonitoring, staticLabels, extraSelector)::
      local services = filterServicesForResource(self, evaluation, thanosSelfMonitoring);
      local definition = self {
        // When evaluation could be in thanos, consider the saturation point evaluated there
        // this will make sure we use the extra label taxonomy from thanos for aggregations
        dangerouslyThanosEvaluated: evaluation != 'prometheus',
      };

      if std.length(services) > 0 then
        local allStaticLabels = self.getStaticLabels() + staticLabels;
        local typeSelector = selectors.without(oneOfType(services), allStaticLabels);
        // The extraselector here should take precedence over automatic ones.
        // For example, we might want to filter for labels in the source metrics that
        // are overridden by static labels in the recording.
        local selectorHash = typeSelector + extraSelector;
        local query = definition.getQuery(
          selectorHash,
          definition.getBurnRatePeriod(),
          maxAggregationLabels=if definition.useResourceLabelsAsMaxAggregationLabels then definition.resourceLabels else [],
          extraStaticLabels=staticLabels
        );

        {
          record: 'gitlab_component_saturation:ratio',
          labels: {
                    component: componentName,
                  } +
                  definition.getStaticLabels() +
                  staticLabels,
          expr: query,
        }
      else null,

    getResourceAutoscalingRecordingRuleDefinition(componentName, evaluation, thanosSelfMonitoring, staticLabels, extraSelector)::
      local definition = self;
      local services = filterServicesForResource(definition, evaluation, thanosSelfMonitoring);

      if std.length(services) > 0 then
        local selectorHash = oneOfType(services) + extraSelector;

        local query = definition.getQuery(selectorHash, definition.getBurnRatePeriod(), definition.resourceLabels);

        {
          record: 'gitlab_component_resource_saturation:ratio',
          labels: {
                    component: componentName,
                  } +
                  definition.getStaticLabels() +
                  staticLabels,
          expr: query,
        }
      else null,

    getSLORecordingRuleDefinition(componentName)::
      local definition = self;
      local labels = {
        component: componentName,
      };

      [{
        record: 'slo:max:soft:gitlab_component_saturation:ratio',
        labels: labels,
        expr: '%g' % [definition.slos.soft],
      }, {
        record: 'slo:max:hard:gitlab_component_saturation:ratio',
        labels: labels,
        expr: '%g' % [definition.slos.hard],
      }],

    // Drop this function when migration to mimir is complete: https://gitlab.com/gitlab-com/gl-infra/scalability/-/issues/2834
    getMetadataRecordingRuleDefinition(componentName)::
      local definition = self;

      {
        record: 'gitlab_component_saturation_info',
        labels: {
          component: componentName,
          horiz_scaling: if definition.horizontallyScalable then 'yes' else 'no',
          severity: definition.severity,
          capacity_planning_strategy: definition.capacityPlanning.strategy,
          quantile: if std.isNumber(definition.quantileAggregation) then
            '%g' % [definition.quantileAggregation]
          else
            definition.quantileAggregation,
        },
        expr: '1',
      },


    getSaturationAlerts(componentName, selectorHash)::
      if self.alerting.enabled then
        generateSaturationAlerts(self, componentName, selectorHash)
      else [],

    // Returns a boolean to indicate whether this saturation point applies to
    // a given service
    appliesToService(type)::
      serviceApplicator(type),

    // When a dashboard for this alert is opened without a type,
    // what should the default be?
    // For allowLists: always use the first item
    // For blockLists: use the default or web
    getDefaultGrafanaType()::
      definition.appliesTo[0],
  };

{
  recordedQuantiles: recordedQuantiles,
  resourceSaturationPoint(definition):: resourceSaturationPoint(definition),
}
