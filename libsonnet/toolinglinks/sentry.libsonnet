local strings = import 'utils/strings.libsonnet';

local toolingLinkDefinition = (import './tooling_link_definition.libsonnet').toolingLinkDefinition({ tool:: 'sentry' });

local joinObject(object, keyValueSeparator, elementSeparator) =
  std.join(
    elementSeparator,
    std.map(
      function(key) '%(key)s%(separator)s%(value)s' % {
        key: key,
        value: object[key],
        separator: keyValueSeparator,
      },
      std.objectFields(object)
    )
  );

local linkContent(config) =
  if std.objectHas(config, 'featureCategory') && config.type != null then
    '🐞 Sentry %(type)s issues: %(featureCategory)s' % config
  else if std.objectHas(config, 'featureCategory') then
    '🐞 Sentry issues: %(featureCategory)s' % config
  else if config.type != null then
    '🐞 Sentry %(type)s issues' % config
  else
    '🐞 Sentry issues' % config;

local formatUrl(path, config, variables) =
  local url = 'https://new-sentry.gitlab.net/organizations/gitlab/%(path)s/?project=%(projectId)d' % {
    projectId: config.projectId,
    path: path,
  };
  local query = {
    [if std.objectHas(config, 'type') && config.type != null then 'type']: config.type,
    [if std.objectHas(config, 'featureCategory') then 'feature_category']: config.featureCategory,
    [if std.member(variables, 'stage') then 'stage']: '${stage}',
  };
  local queryString = strings.urlEncode(joinObject(query, ':', ' '));
  local params = std.prune({
    [if std.member(variables, 'environment') then 'environment']: '${environment}',
    [if std.length(queryString) > 0 then 'query']: queryString,
  });

  if std.length(params) == 0 then
    url
  else
    '%(url)s&%(paramsString)s' % {
      url: url,
      paramsString: joinObject(params, '=', '&'),
    };

local issuesLinks(projectId, featureCategories, type, variables) =
  if std.length(featureCategories) != 0 then
    [
      (
        local config = {
          projectId: projectId,
          type: type,
          featureCategory: featureCategory,
        };
        toolingLinkDefinition({
          title: linkContent(config),
          url: formatUrl('issues', config, variables),
        })
      )
      for featureCategory in featureCategories
    ]
  else
    local config = {
      projectId: projectId,
      type: type,
    };
    [
      toolingLinkDefinition({
        title: linkContent(config),
        url: formatUrl('issues', config, variables),
      }),
    ];


{
  sentry(projectId, featureCategories=[], type=null, variables=['environment'])::
    function(options)
      local config = {
        projectId: projectId,
      };
      [
        toolingLinkDefinition({
          title: '🐞 Sentry Releases' % config,
          url: formatUrl('releases', config, ['environment']),
        }),
      ] +
      issuesLinks(projectId, featureCategories, type, variables),
}
