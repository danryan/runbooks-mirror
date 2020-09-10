local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local commonAnnotations = import 'grafana/common_annotations.libsonnet';
local k8sPodsCommon = import 'kubernetes_pods_common.libsonnet';
local template = grafana.template;
local templates = import 'grafana/templates.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local basic = import 'grafana/basic.libsonnet';

basic.dashboard(
  'Pod Info',
  tags=['container registry', 'docker', 'registry'],
)
.addTemplate(templates.gkeCluster)
.addTemplate(templates.stage)
.addTemplate(templates.namespaceGitlab)
.addTemplate(templates.Node)
.addTemplate(templates.stage)
.addTemplate(
  template.custom(
    'Deployment',
    'gitlab-(cny-)?registry,',
    'gitlab-(cny-)?registry',
    hide='variable',
  )
)
.addPanel(

  row.new(title='Container Registry Version'),
  gridPos={
    x: 0,
    y: 0,
    w: 24,
    h: 1,
  }
)
.addPanels(k8sPodsCommon.version(startRow=1))
.addPanel(

  row.new(title='Deployment Info'),
  gridPos={
    x: 0,
    y: 500,
    w: 24,
    h: 1,
  }
)
.addPanels(k8sPodsCommon.deployment(startRow=501))
.addPanels(k8sPodsCommon.status(startRow=502))
.addPanel(

  row.new(title='CPU'),
  gridPos={
    x: 0,
    y: 1000,
    w: 24,
    h: 1,
  }
)
.addPanels(k8sPodsCommon.cpu(startRow=1001))
.addPanel(

  row.new(title='Memory'),
  gridPos={
    x: 0,
    y: 2000,
    w: 24,
    h: 1,
  }
)
.addPanels(k8sPodsCommon.memory(startRow=2001, container='registry'))
.addPanel(

  row.new(title='Network'),
  gridPos={
    x: 0,
    y: 3000,
    w: 24,
    h: 1,
  }
)
.addPanels(k8sPodsCommon.network(startRow=3001))
