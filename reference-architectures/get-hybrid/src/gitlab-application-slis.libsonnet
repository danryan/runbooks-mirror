local sliDefinition = import 'gitlab-slis/sli-definition.libsonnet';

local list = [
  sliDefinition.new({
    name: 'rails_request',
    significantLabels: ['endpoint_id', 'feature_category', 'request_urgency'],
    kinds: [sliDefinition.apdexKind, sliDefinition.errorRateKind],
    description: |||
      The number of requests meeting their duration target based on the urgency
      of the endpoint. By default, a request should take no more than 1s. But
      this can be adjusted by endpoint.

      Read more about this in the [documentation](https://docs.gitlab.com/ee/development/application_slis/rails_request_apdex.html).
    |||,
  }),
];

local definitionsByName = std.foldl(
  function(memo, definition)
    assert !std.objectHas(memo, definition.name) : '%s already defined' % [definition.name];
    memo { [definition.name]: definition },
  list,
  {}
);

{
  get(name):: std.get(definitionsByName, name, error 'No SLI with name %s has been defined' % [name]),
  all:: list,
  names:: std.map(function(sli) sli.name, list),
}
