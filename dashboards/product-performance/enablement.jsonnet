local layout = import 'grafana/layout.libsonnet';
local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local template = grafana.template;
local annotation = grafana.annotation;
local productCommon = import 'product_common.libsonnet';

dashboard.new(
  title = "Performance - Enablement",
  time_from = "now-7d",
  tags = ["product performance"],
).addLink(
  productCommon.productDashboardLink(),
).addLink(
  productCommon.pageDetailLink(),
).addTemplate(
    template.interval("function", "min, mean, median, p90, max", "median"),
).addPanel(
  grafana.text.new(
    title = "Overview",
    mode = "markdown",
    content = "### Synthetic tests of GitLab.com pages for the Enablement group.\n\nFor more information, please see: https://gitlab.com/gitlab-org/gitlab/-/issues/221018\n\n\n\n",
  ), gridPos = { "h": 3, "w": 24, "x": 0, "y": 0, }
).addPanel(
  row.new(title='Global Search'), gridPos = {x: 0, y: 1000, w: 24, h: 1, }
).addPanels(
  layout.grid(
    [
      productCommon.pageDetail("Basic Global Search - Projects", "Basic_Search_Projects", "https://gitlab.com/search?utf8=%E2%9C%93&snippets=&scope=&repository_ref=&search=gitlab"),
      productCommon.pageDetail("Advanced Global Search - Projects", "Advanced_Search_Projects", "https://gitlab.com/search?utf8=%E2%9C%93&snippets=&scope=&repository_ref=&search=gitlab&group_id=6543"),
      productCommon.pageDetail("Advanced Global Search - Code", "Advanced_Search_Code", "https://gitlab.com/search?group_id=6543&repository_ref=&scope=blobs&search=gitlab&snippets="),
    ],
    startRow = 1001,
  ),
)