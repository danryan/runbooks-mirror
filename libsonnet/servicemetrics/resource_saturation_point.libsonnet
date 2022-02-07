local alerts = import 'alerts/alerts.libsonnet';
local selectors = import 'promql/selectors.libsonnet';
local stableIds = import 'stable-ids/stable-ids.libsonnet';
local strings = import 'utils/strings.libsonnet';
local validator = import 'utils/validator.libsonnet';

// The severity labels that we allow on resources
local severities = std.set(['s1', 's2', 's3', 's4']);
local environmentLabels = ['environment', 'tier', 'type', 'stage'];

local capacityPlanningStrategies = std.set(['quantile95_1w', 'quantile99_1w', 'quantile95_1h']);

local sloValidator = validator.validator(function(v) v > 0 && v <= 1, 'SLO threshold should be in the range (0,1]');

local quantileValidator = validator.validator(function(v) std.isNumber(v) && (v > 0 && v < 1) || v == 'max', 'value should be in the range (0,1) or the string "max"');

local definitionValidor = validator.new({
  title: validator.string,
  severity: validator.setMember(severities),
  horizontallyScalable: validator.boolean,
  appliesTo: validator.or(validator.array, validator.object),
  description: validator.string,
  grafana_dashboard_uid: validator.string,
  resourceLabels: validator.array,
  query: validator.string,
  quantileAggregation: quantileValidator,
  capacityPlanningStrategy: validator.setMember(capacityPlanningStrategies),
  slos: {
    soft: sloValidator,
    hard: sloValidator,
  },
});


local getAllowedServiceApplicator(allowedList) =
  local allowedSet = std.set(allowedList);
  function(type) std.setMember(type, allowedSet);

local getDisallowedServiceApplicator(disallowedList) =
  local disallowedSet = std.set(disallowedList);
  function(type) !std.setMember(type, disallowedSet);

// Returns a function that returns a boolean to indicate whether a service
// applies for the provided definition
local getServiceApplicator(appliesTo) =
  if std.isArray(appliesTo) then
    getAllowedServiceApplicator(appliesTo)
  else
    getDisallowedServiceApplicator(appliesTo.allExcept);

local defaults = {
  queryFormatConfig: {},
  alertRunbook: 'docs/{{ $labels.type }}/README.md',
  dangerouslyThanosEvaluated: false,
  quantileAggregation: 'max',
  capacityPlanningStrategy: 'quantile95_1h',
};

local validateAndApplyDefaults(definition) =
  definitionValidor.assertValid(defaults + definition) + {
    slos: {
      alertTriggerDuration: '5m',
    } + definition.slos,
  };

local resourceSaturationPoint = function(options)
  local definition = validateAndApplyDefaults(options);
  local serviceApplicator = getServiceApplicator(definition.appliesTo);

  definition {
    getQuery(selectorHash, rangeInterval, maxAggregationLabels=[])::
      local staticLabels = self.getStaticLabels();
      local environmentLabelsLocal = (if self.dangerouslyThanosEvaluated == true then ['env'] else []) + environmentLabels;
      local queryAggregationLabels = environmentLabelsLocal + self.resourceLabels;
      local allMaxAggregationLabels = environmentLabelsLocal + maxAggregationLabels;
      local queryAggregationLabelsExcludingStaticLabels = std.filter(function(label) !std.objectHas(staticLabels, label), queryAggregationLabels);
      local maxAggregationLabelsExcludingStaticLabels = std.filter(function(label) !std.objectHas(staticLabels, label), allMaxAggregationLabels);
      local queryFormatConfig = self.queryFormatConfig;

      // Remove any statically defined labels from the selectors, if they are defined
      local selectorWithoutStaticLabels = if staticLabels == {} then selectorHash else selectors.without(selectorHash, staticLabels);

      local preaggregation = self.query % queryFormatConfig {
        rangeInterval: rangeInterval,
        selector: selectors.serializeHash(selectorWithoutStaticLabels),
        aggregationLabels: std.join(', ', queryAggregationLabelsExcludingStaticLabels),
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
          maxAggregationLabels: std.join(', ', maxAggregationLabelsExcludingStaticLabels),
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
          maxAggregationLabels: std.join(', ', maxAggregationLabelsExcludingStaticLabels),
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

    getRecordingRuleDefinition(componentName)::
      local definition = self;

      local typeFilter =
        (
          if std.isArray(definition.appliesTo) then
            if std.length(definition.appliesTo) > 1 then
              { type: { re: std.join('|', definition.appliesTo) } }
            else
              { type: definition.appliesTo[0] }
          else
            if std.length(definition.appliesTo.allExcept) > 0 then
              { type: [{ ne: '' }, { nre: std.join('|', definition.appliesTo.allExcept) }] }
            else
              { type: { ne: '' } }
        );

      local query = definition.getQuery(typeFilter, definition.getBurnRatePeriod());

      {
        record: 'gitlab_component_saturation:ratio',
        labels: {
          component: componentName,
        } + definition.getStaticLabels(),
        expr: query,
      },

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

    getMetadataRecordingRuleDefinition(componentName)::
      local definition = self;

      {
        record: 'gitlab_component_saturation_info',
        labels: {
          component: componentName,
          horiz_scaling: if definition.horizontallyScalable then 'yes' else 'no',
          severity: definition.severity,
          capacity_planning_strategy: definition.capacityPlanningStrategy,
          quantile: if std.isNumber(definition.quantileAggregation) then
            '%g' % [definition.quantileAggregation]
          else
            definition.quantileAggregation,
        },
        expr: '1',
      },


    getSaturationAlerts(componentName, selectorHash)::
      local definition = self;

      local triggerDuration = definition.slos.alertTriggerDuration;

      local selectorHashWithComponent = selectorHash {
        component: componentName,
      };

      local formatConfig = {
        triggerDuration: triggerDuration,
        componentName: componentName,
        description: definition.description,
        title: definition.title,
        selector: selectors.serializeHash(selectorHashWithComponent),
      };

      local severityLabels =
        { severity: definition.severity } +
        if definition.severity == 's1' || definition.severity == 's2' then
          { pager: 'pagerduty' }
        else
          {};

      [alerts.processAlertRule({
        alert: 'component_saturation_slo_out_of_bounds',
        expr: |||
          gitlab_component_saturation:ratio{%(selector)s} > on(component) group_left
          slo:max:hard:gitlab_component_saturation:ratio{%(selector)s}
        ||| % formatConfig,
        'for': triggerDuration,
        labels: {
          rules_domain: 'general',
          alert_type: 'cause',
        } + severityLabels,
        annotations: {
          title: 'The %(title)s resource of the {{ $labels.type }} service ({{ $labels.stage }} stage), component has a saturation exceeding SLO and is close to its capacity limit.' % formatConfig,
          description: |||
            This means that this resource is running close to capacity and is at risk of exceeding its current capacity limit.

            Details of the %(title)s resource:

            %(description)s
          ||| % formatConfig,
          runbook: definition.alertRunbook,
          grafana_dashboard_id: 'alerts-' + definition.grafana_dashboard_uid,
          grafana_panel_id: stableIds.hashStableId('saturation-' + componentName),
          grafana_variables: 'environment,type,stage',
          grafana_min_zoom_hours: '6',
          promql_query: definition.getQuery({
            environment: '{{ $labels.environment }}',
            stage: '{{ $labels.stage }}',
            type: '{{ $labels.type }}',
          }, definition.getBurnRatePeriod(), definition.resourceLabels),
        },
      })],

    // Returns a boolean to indicate whether this saturation point applies to
    // a given service
    appliesToService(type)::
      serviceApplicator(type),

    // When a dashboard for this alert is opened without a type,
    // what should the default be?
    // For allowLists: always use the first item
    // For blockLists: use the default or web
    getDefaultGrafanaType()::
      if std.isArray(definition.appliesTo) then
        definition.appliesTo[0]
      else
        if std.objectHas(definition.appliesTo, 'default') then
          definition.appliesTo.default
        else
          'web',
  };

{
  resourceSaturationPoint(definition):: resourceSaturationPoint(definition),
}
