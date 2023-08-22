# Runway Observability

[Runway](https://about.gitlab.com/handbook/engineering/infrastructure/platforms/tools/runway/) is GitLab’s internal Platform as a Service (PaaS), which enables teams to deploy, scale, and operate services outside of the Rails monolith.

Runway fully integrates with monitoring stack to provide observability out of the box for managed services. Features include default [SLIs and SLOs](../../metrics-catalog/README.md), [saturation resources](../../libsonnet/saturation-monitoring/README.md), and [service overview dashboards](../../dashboards/README.md).

### Default SLIs

By default, every Runway service includes SLI called `runway_ingress` for application load balancer serving HTTP requests. Component includes request rate, error rate, and apdex latency.

### Default SLOs

By default, every Runway service includes alerting for the following SLOs:

* Apdex SLO violation
* Error SLO violation
* Traffic absent SLO violation

For more information on alert routing, refer to [documentation](../uncategorized/alert-routing.md).

### Default Saturation Resources

By default, every Runway services includes saturation monitoring for the following resources:

* Container CPU Utilization
* Container Memory Utilization
* Container Instance Utilization
* Container Max Concurrent Requests Utilization

For more information on scaling resources, refer to [documentation](../../libsonnet/saturation-monitoring/runway_utilization.libsonnet).

## Prerequisites

Before proceeding, you must have access to the following:

1. Provisioned Runway [service](https://gitlab.com/gitlab-com/gl-infra/platform/runway/docs/-/blob/master/onboarding-new-service.md?ref_type=heads)
1. Runway [service ID](https://gitlab.com/gitlab-com/gl-infra/platform/runway/deployments)

## Usage

To mature your provisioned Runway service, follow these steps:

1. Create new entry in [service catalog](../../services/service-catalog.yml): e.g. `my_service`.
2. Create new entry in [metrics catalog](../../metrics-catalog/services/all.jsonnet): e.g.

```jsonnet
// metrics-catalog/services/my-service.jsonnet
local runwayArchetype = import 'service-archetypes/runway-archetype.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';

metricsCatalog.serviceDefinition(
  runwayArchetype(
    type='my_service',
    team='my_team',
    runwayServiceID='my_runway_service_id',
  )
)
```

3. Run `make generate` and commit autogenerated content

And that's it! After approval and merging, you can view your newly generated [service overview dashboard](https://dashboards.gitlab.net/dashboards?query=my_service).

The default dashboard will include everything you need to identify the performance and reliability of your Runway service, including ingress SLI details, saturation details, and Runway Overview details. Automatic [annotations for service deploys](https://gitlab.com/gitlab-com/gl-infra/platform/runway/team/-/issues/77) are also planned for near future.

## Configuration

Runway's observability was built with sane defaults in mind. Every service's workload is different though, so customization is an advanced option for Runway service owners.

### Default SLIs

Right now, the following defaults can be optionally configured:

| Option    | Description | Default |
| -------- | ------- |------- |
| `apdexSatisfiedThreshold` | Alter expected request latency of Runway service | `1024` ms |
| `apdexScore` | Alter apdex threshold for the Runway service | `0.999` |
| `errorScore` | Alter how many errors are tolerated for the Runway service | `0.999` |

### Custom SLIs

In addition to default SLIs, you can optionally configure custom SLIs:

```jsonnet
local runwayArchetype = import 'service-archetypes/runway-archetype.libsonnet';
local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local rateMetric = metricsCatalog.rateMetric;

metricsCatalog.serviceDefinition(
  // Default SLIs
  runwayArchetype(
    type='my_service',
    team='my_team',
    runwayServiceID='my_service_runway_id',
  ),
  // Custom SLIs
  {
    serviceLevelIndicators+: {
      my_component: {
        requestRate: rateMetric(
          counter='my_service_custom_metric_total',
          selector='type="my_service"'
        ),
      },
    },
  }
)
```

For more information on full configuration, refer to [documentation](../../metrics-catalog/README.md).