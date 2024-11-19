local g = import 'grafonnet-dashboarding/grafana/g.libsonnet';

{
  forPanel(p):: {
    local standardOptions = p.standardOptions,
    local override = standardOptions.override,
    local custom = p.fieldConfig.defaults.custom,

    fromOptions(options)::
      override.byRegexp.new(options.alias)
      + override.byRegexp.withPropertiesFromOptions(
        {}
        + (
          if std.objectHas(options, 'color') then
            standardOptions.color.withFixedColor(options.color)
            + standardOptions.color.withMode('shades')
          else
            {}
        )
        + (
          if options.dashes then
            custom.lineStyle.withFill('dash')
            + custom.lineStyle.withDash([options.dashLength, options.spaceLength])
          else
            {}
        )
        + (
          if std.objectHas(options, 'linewidth') then
            custom.withLineWidth(options.linewidth)
          else
            {}
        )
        + (
          if !options.legend then
            custom.hideFrom.withLegend(true)
          else
            {}
        )
      ),
  },

}
