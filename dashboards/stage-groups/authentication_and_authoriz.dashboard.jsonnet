// This file is autogenerated using scripts/update_stage_groups_dashboards.rb
// Please feel free to customize this file.
local stageGroupDashboards = import './stage-group-dashboards.libsonnet';
local signIn = import 'stage-groups/manage-authentication-and-authorization/sign_in.libsonnet';

stageGroupDashboards.dashboard('authentication_and_authorization', components=stageGroupDashboards.supportedComponents)
.addSidekiqJobDurationByUrgency()
.addPanels(signIn.panels())
.stageGroupDashboardTrailer()
