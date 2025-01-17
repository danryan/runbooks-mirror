local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local saturation = import 'servicemetrics/saturation-resources.libsonnet';
local manifest = import 'tamland.jsonnet';
local test = import 'test.libsonnet';

local resourceSaturationPoint = metricsCatalog.resourceSaturationPoint;

local saturationPoints = {
  michael_scott: resourceSaturationPoint({
    title: 'Michael Scott',
    severity: 's4',
    horizontallyScalable: true,
    capacityPlanning: {
      strategy: 'exclude',
    },
    appliesTo: ['thanos', 'web', 'api'],
    description: |||
      Just Mr Tamland chart
    |||,
    grafana_dashboard_uid: 'just testing',
    resourceLabels: ['name'],
    query: |||
      memory_used_bytes{area="heap", %(selector)s}
      /
      memory_max_bytes{area="heap", %(selector)s}
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
  jimbo: resourceSaturationPoint({
    title: 'Jimbo',
    severity: 's4',
    horizontallyScalable: true,
    capacityPlanning: {
      strategy: 'exclude',
    },
    appliesTo: ['thanos', 'redis'],
    description: |||
      Just Mr Jimbo
    |||,
    grafana_dashboard_uid: 'just testing',
    resourceLabels: ['name'],
    query: |||
      memory_used_bytes{area="heap", %(selector)s}
      /
      memory_max_bytes{area="heap", %(selector)s}
    |||,
    slos: {
      soft: 0.80,
      hard: 0.90,
    },
  }),
};

test.suite({
  testDefaults: {
    actual: manifest.defaults,
    expectThat: {
      local promFields = std.objectFields(self.actual.prometheus),
      result: std.objectHas(self.actual, 'prometheus')
              && promFields == ['baseURL', 'defaultSelectors', 'queryTemplates', 'serviceLabel'],
      description: 'Expect object to have default configurations',
    },
  },
  testHasSaturationPoints: {
    actual: manifest,
    expectThat: {
      result: std.objectHas(self.actual, 'saturationPoints') == true,
      description: 'Expect object to have saturationPoints field',
    },
  },
  testHasServices: {
    local servicesHaveExpectedFields = std.map(
      function(name)
        local fields = std.objectFields(self.actual.services[name]);
        local expectedFields = [
          'capacityPlanning',
          'label',
          'name',
          'overviewDashboard',
          'owner',
          'resourceDashboard',
          'shards',
        ];
        std.all(
          std.map(
            function(field)
              std.member(expectedFields, field),
            fields
          )
        ),
      std.objectFields(self.actual.services)
    ),
    actual: manifest,
    expectThat: {
      result: std.all(servicesHaveExpectedFields),
      description: 'Expect object to have serviceCatalog fields',
    },
  },
  testHasServiceCatalogTeamsField: {
    actual: manifest,
    expectThat: {
      result: std.objectHas(self.actual, 'teams') == true,
      description: 'Expect object to have serviceCatalog.teams field',
    },
  },
  testHasServiceCatalogTeamsFields: {
    actual: manifest,
    expectThat: {
      result: std.sort(std.objectFields(self.actual.teams[0])) == std.sort(['name', 'label', 'manager']),
      description: 'Expect object to have serviceCatalog.teams fields',
    },
  },
  testReportHasRunwayServices: {
    actual: manifest,
    expectThat: {
      local runwayPage = std.filter(function(page) page.path == 'runway.md', self.actual.report.pages)[0],
      local runwayServices = std.split(runwayPage.service_pattern, '|'),
      result: std.member(runwayServices, 'ai-gateway'),
      description: 'Expect object to dynamically include Runway provisioned services',
    },
  },
})
