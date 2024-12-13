# frozen_string_literal: true

module RedisTrace
  class KeyPattern
    def self.filter_key(key)
      case ENV['GITLAB_REDIS_CLUSTER']
      when 'persistent'
        # multiline (m) modifier because gitlab-kas:agent_limit can have keynames with binary in them including newlines
        key = key
          .gsub(%r{^(session:lookup:ip:gitlab2:|etag:|action_cable/|sidekiq:cancel:|database-load-balancing/write-location(/main)?/[a-z]+/|runner:build_queue:|gitlab:exclusive_lease:|issues:|gitlab-kas:agent_limit:|gitlab-kas:agent_tracker:conn_by_(project|agent)_id:|gitlab-kas:tunnel_tracker:conn_by_agent_id:|graphql-subscription:|graphql-event::issuableAssigneesUpdated:issuableId:|gitlab-sidekiq-status:|gitlab-kas:agent_info_errs:|gitlab-kas:project_info_errs:|workhorse:notifications:runner:build_queue:)(.+)}m, '\1$PATTERN')
      when 'cache'
        key = key
          .gsub(%r{^(highlighted-diff-files:merge_request_diffs/)(.+)}, '\1$PATTERN')
          .gsub(%r{^((cache:gitlab:)?(show_raw_controller:project|ancestor|can_be_resolved_in_ui\?|commit_count_refs/heads/master|commit_count_master|exists\?|last_commit_id_for_path|merge_request_template_names|merge_request_template_names_hash|root_ref|xcode_project\?|issue_template_names|issue_template_names_hash|views/shared/projects/_project|application_rate_limiter|branch_names|merged_branch_names|peek:requests|tag_names|branch_count|tag_count|commit_count|size|gitignore|rendered_readme|readme_path|license_key|contribution_guide|gitlab_ci_yml|changelog|license_blob|avatar|avatar_cache:v1|metrics_dashboard_paths|has_visible_content\?|Ci::ListConfigVariablesService|commit_stats|DiscussionsSerializer|has_ambiguous_refs\?|user_defined_metrics_dashboard_paths)):(.+)}, '\1:$PATTERN')
          .gsub(%r{^cache:gitlab:(diverging_commit_counts_|github-import/|blob_content_sha|commit_count_|flipper/v1/)(.+)}, 'cache:gitlab:\1$PATTERN')
          .gsub(%r{^cache:gitlab:projects/[0-9]+/(content|last_commits)/[0-9a-f]{40}/(.+)}, 'cache:gitlab:projects/$NUMBER/\1/$LONGHASH/$PATTERN')
          .gsub(%r{^cache:gitlab:projects/[0-9-]+/(branches/users|projects)/(.+)}, 'cache:gitlab:projects/$NUMBER/\1/$LONGHASH/$PATTERN')
          .gsub(/^container_repository:\{[0-9]+\}:tag:(.+)/, 'container_repository/{$NUMBER}:tag:$PATTERN')
      when 'ratelimiting'
        key = key
          .gsub(/^(application_rate_limiter:show_raw_controller:project):[0-9]+:(.+)/, '\1:$NUMBER:$PATTERN')
          .gsub(/^(cache:gitlab:rack::attack:allow2ban:ban):(.+)/, '\1:$PATTERN')
          .gsub(/^(cache:gitlab:rack::attack:[0-9]+:(allow2ban:count|throttle_[^:]+)):(.+)/, '\1:$PATTERN')
      when 'pubsub'
        key = key
          .gsub(%r{^(graphql-subscription:|runner:build_queue:|workhorse:notifications:runner:build_queue:|action_cable/)(.+)}, '\1$PATTERN')
          .gsub(%r{^graphql-event::(aiCompletionResponse:aiAction:chat|issuableLabelsUpdated|mergeRequestApprovalStateUpdated|mergeRequestReviewersUpdated|mergeRequestMergeStatusUpdated|workItemNoteCreated|issuableWeightUpdated|issuableEpicUpdated|issuableDatesUpdated|workItemNoteCreated|issuableAssigneesUpdated|aiCompletionResponse|workItemNoteUpdated|workItemUpdated|mergeRequestDiffGenerated|issuableDescriptionUpdated|workItemNoteDeleted|issueCrmContactsUpdated|issuableIterationUpdated|issuableMilestoneUpdated):(.+)}, '\1:$PATTERN')
          .gsub(%r{^(noteable:notes:)(.+)}, '\1:$PATTERN')
      end

      # Generic replacements
      key
        .gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{8}/, '$UUIDISH')
        .gsub(/([0-9a-f]{64})/, '$LONGHASH')
        .gsub(/([0-9a-f]{40})/, '$LONGHASH')
        .gsub(/([0-9a-f]{32})/, '$HASH')
        .gsub(/([0-9a-f]{30})/, '$HASH')
        .gsub(/([0-9]+)/, '$NUMBER')
        .encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end
end
