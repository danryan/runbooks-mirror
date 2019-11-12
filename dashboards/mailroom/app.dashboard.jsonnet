local basic = import 'basic.libsonnet';
local commonAnnotations = import 'common_annotations.libsonnet';
local common = import 'container_common_graphs.libsonnet';
local grafana = import 'grafonnet/grafana.libsonnet';
local layout = import 'layout.libsonnet';
local template = grafana.template;
local templates = import 'templates.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;

dashboard.new(
  'Application Info',
  schemaVersion=16,
  tags=['mailroom'],
  timezone='utc',
  graphTooltip='shared_crosshair',
)
.addAnnotation(commonAnnotations.deploymentsForEnvironment)
.addAnnotation(commonAnnotations.deploymentsForEnvironmentCanary)
.addTemplate(templates.ds)
.addTemplate(templates.environment)
.addTemplate(templates.gkeCluster)
.addTemplate(templates.namespace)
.addTemplate(
  template.custom(
    'Deployment',
    'gitlab-mailroom,',
    'gitlab-mailroom',
  )
).addPanel(

  row.new(title='Stackdriver Metrics'),
  gridPos={
    x: 0,
    y: 0,
    w: 24,
    h: 1,
  }
)
.addPanels(common.logMessages(startRow=1))
.addPanel(

  row.new(title='Mailroom Metrics'),
  gridPos={
    x: 0,
    y: 100,
    w: 24,
    h: 1,
  }
)
.addPanels(
  layout.grid([
    basic.timeseries(
      title='Unread Emails',
      description='Number of unread messages',
      query='max(imap_nb_unread_messages_in_mailbox{environment=~"$environment"})',
      interval='1m',
      intervalFactor=2,
      yAxisLabel='',
      legend_show=true,
      linewidth=2
    ),
  ], cols=1, rowHeight=10, startRow=101)
)
