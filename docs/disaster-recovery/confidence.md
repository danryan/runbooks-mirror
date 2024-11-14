# GitLab.com Disaster Recovery Confidence Measurements

These are tables that help express our current confidence levels in the processes used for recoverying from a Zonal or Regional degredation/outage.
These are specific to GitLab.com GPRD and GSTG right now, but could be expanded in the future to account for other instances or environments.

## GitLab.com Zonal Recovery Confidence

| Category | Component | Phase | Time to Restore (Hours) | Number of SREs | Confidence | Tested in Staging? | Issue Links | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Services | Gitaly | Phase 1 | 2 | 1 | Medium Confidence | Yes | | |
| Services | Patroni | Phase 1 | 1 | 0.5 | Medium Confidence | Yes | | This has been test in staging in a RO capacity. I'm suggesting we add a patroni leader failover to the game day before increasing the confidence level to Medium. |
| Services | PG Bouncer | Phase 1 | 0.5 | 1 | Medium Confidence | Yes | | Staging testing was concluded on 8/8/23. The next steps would be to plan a restore attempt in GPRD. |
| Services | HAProxy | Phase 1 | 1 | 1 | Medium Confidence | Yes | | |
| Services | CI Runners | Phase 1 | 3 | 1 | Medium Confidence | Yes | | |
| Services | Redis | Phase 2 | 0 | 0.5 | Low Confidence | No | <https://gitlab.com/gitlab-com/gl-infra/production-engineering/-/issues/25642> | |
| Services | Redis Cluster | Phase 2 | 0 | 0.5 | Low Confidence | No | <https://gitlab.com/gitlab-com/gl-infra/production-engineering/-/issues/25642> | |
| Services | Regional Clusters | Phase 2 | 1 | 1 | Medium Confidence | Yes | | |
| Services | CustomersDot | Phase 2 | 3 | 1 | Low Confidence | No | | CustomersDot has a Cloud Redis that is single zone. |
| Services | Zonal Clusters | Phase 2 | 1 | 1 | Low Confidence | No | | |
| Post-Recovery | Patroni Backups | Phase 3 | 1 | 1 | Low Confidence | No | | |
| Post-Recovery | Runway Production Services | Phase 3 | 0 | 0 | Low Confidence | No | | |

### Zonal Phases and Phase Definitions

Phases are prioritized groups of components to help guide a response to an outage/degradation.
Each phase should have it's components restored in parallel to minimize the time in a degraded state.
Moving onto the next phase assumes the previous phase's components have been restored.

- Phase 1 - Once these are completed we believe we will be available for customers
- Phase 2 - This phase is to check components that may be in a degraded state
- Phase 3 - This phase ensures operational tooling and processes work

### Zonal Confidence Definitions

Confidence levels help define and communicate how mature the components process is.

| Confidence Level | Parameters |
| --- | --- |
| No Confidence | 1. We have not tested recovery |
| | 2. We do not have a good understanding of the impact of the component going down |
| | 3. We do not have an emergency plan for when the component goes down |
| Low Confidence | 1. We have not tested recovery |
| | 2. We have a good understanding of the impact of the component going down |
| | 3. We may or may not have an emergency plan when the component goes down, but it has not been validated |
| Medium Confidence | 1. We have tested recovery in a production like environment but not tested in production |
| | 2. We have a good understanding of the impact of the component going down |
| | 3. We have an emergency plan for when the component goes down, and it has been validated in some environment |
| High Confidence | 1. We have tested recovery in production |
| | 2. We have a good understanding of the impact of the component going down |
| | 3. We have an emergency plan when the component goes down, and it has been validated |

## GitLab.com Regional Recovery Confidence

### Regional Phases and Phase Definitions

### Regional Confidence Definitions
