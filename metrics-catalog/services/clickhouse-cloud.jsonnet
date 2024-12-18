local metricsCatalog = import 'servicemetrics/metrics.libsonnet';
local toolingLinks = import 'toolinglinks/toolinglinks.libsonnet';

local rateMetric = metricsCatalog.rateMetric;

local clickhouseQuerySelector = {};

metricsCatalog.serviceDefinition({
    type: 'clickhouse',
    tier: 'inf',
    serviceIsStageless: true,
    skippedMaturityCriteria: {
        'Structured logs available in Kibana': 'Targeted service is a managed offering from ClickHouse Inc.',
        'Service exists in the dependency graph': 'ClickHouse Cloud instances are managed externally by ClickHouse Inc.',
    },
    serviceDependencies: {},
    monitoringThresholds: {
        errorRatio: 0.999,
    },
    provisioning: {
        kubernetes: false,
        vms: false,
    },
    serviceLevelIndicators: {
        reads: {
            severity: 's3',
            userImpacting: true,
            serviceAggregation: true,
            featureCategory: 'not_owned',
            team: 'clickhouse',
            description: |||
                Reads SLI for ClickHouse instances hosted via ClickHouse Cloud.
            |||,

            requestRate: rateMetric(
                counter='ClickHouseProfileEvents_Query',
                selector=clickhouseQuerySelector
            ),

            errorRate: rateMetric(
                counter='ClickHouseProfileEvents_FailedQuery',
                selector=clickhouseQuerySelector,
            ),

            significantLabels: [
                'clickhouse_org',
                'clickhouse_service_name',
                'hostname',
            ],
        },

        writes: {
            severity: 's3',
            userImpacting: true,
            serviceAggregation: true,
            featureCategory: 'not_owned',
            team: 'clickhouse',
            description: |||
                Writes SLI for ClickHouse instances hosted via ClickHouse Cloud.
            |||,

            requestRate: rateMetric(
                counter='ClickHouseProfileEvents_InsertQuery',
                selector=clickhouseQuerySelector
            ),

            errorRate: rateMetric(
                counter='ClickHouseProfileEvents_FailedInsertQuery',
                selector=clickhouseQuerySelector,
            ),

            significantLabels: [
                'clickhouse_org',
                'clickhouse_service_name',
                'hostname',
            ],
        },
    },
})
