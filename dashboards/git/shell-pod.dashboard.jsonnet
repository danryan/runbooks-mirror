local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local commonAnnotations = import 'grafana/common_annotations.libsonnet';
local k8sPodsCommon = import 'kubernetes_pods_common.libsonnet';
local platformLinks = import 'platform_links.libsonnet';
local serviceCatalog = import 'service_catalog.libsonnet';
local template = grafana.template;
local templates = import 'grafana/templates.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local basic = import 'grafana/basic.libsonnet';

basic.dashboard(
  'Pod Info',
  tags=['git', 'shell'],
)
.addTemplate(templates.gkeCluster)
.addTemplate(templates.stage)
.addTemplate(templates.namespaceGitlab)
.addTemplate(templates.Node)
.addTemplate(
  template.custom(
    name='Deployment',
    query='gitlab-(cny-)?gitlab-shell,',
    current='gitlab-(cny-)?gitlab-shell',
    hide='variable',
  )
)
.addPanel(

  row.new(title='GitLab-Shell Version'),
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
.addPanels(k8sPodsCommon.memory(startRow=2001, container='gitlab-shell'))
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
+ {
  links+: platformLinks.triage +
          serviceCatalog.getServiceLinks('git') +
          platformLinks.services,
}
