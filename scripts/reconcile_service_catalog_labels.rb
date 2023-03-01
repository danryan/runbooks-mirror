#! /usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'set'
require 'net/http'
require 'logger'

# From service_catalog.yml:
#   - For labels not found in https://gitlab.com/groups/gitlab-com/gl-infra/-/labels?subscribed=&search=service%3A%3A,
#      create new labels via API
class ReconcileServiceCatalogLabels
  LABEL_COLOR = "#D1D100"
  SERVICE_LABEL_SCOPE = "Service::"
  GL_INFRA_GROUP = 'gitlab-com%2Fgl-infra'
  # https://docs.gitlab.com/ee/api/group_labels.html
  LABELS_API = "https://gitlab.com/api/v4/groups/#{GL_INFRA_GROUP}/labels".freeze
  DEFAULT_SERVICE_CATALOG_PATH = File.join(__dir__, "..", "services", "service-catalog.yml")

  def initialize(service_catalog_path = DEFAULT_SERVICE_CATALOG_PATH, logger = Logger.new($stdout))
    @service_catalog_path = service_catalog_path
    @logger = logger
  end

  def call
    if ENV["GITLAB_RECONCILE_SERVICE_LABELS_TOKEN"].to_s.empty?
      @logger.error("Missing environment variable GITLAB_RECONCILE_SERVICE_LABELS_TOKEN for labels API. Skipping script")
      return
    end

    existing_labels_set = Set.new
    list_labels(SERVICE_LABEL_SCOPE).each { |label| existing_labels_set << label["name"] }

    service_catalog = YAML.load_file(@service_catalog_path)
    service_catalog["services"].each do |service|
      full_label = SERVICE_LABEL_SCOPE + service["label"]
      create_label(full_label, service["name"]) unless existing_labels_set.include?(full_label)
    end
  end

  def list_labels(search_keyword)
    uri = URI(LABELS_API)
    page = 1
    page_size = 100
    labels = []
    loop do
      params = { search: search_keyword, page: page, per_page: page_size }
      uri.query = URI.encode_www_form(params)

      res = Net::HTTP.get_response(uri, { "PRIVATE-TOKEN": ENV["GITLAB_RECONCILE_SERVICE_LABELS_TOKEN"] })

      raise "List group labels API failed. Status: #{res.code} Message: #{res.message}" unless res.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(res.body)
      labels += parsed
      break if parsed.empty? || parsed.length < page_size

      page += 1
    end
    labels
  end

  def create_label(label_name, service_name)
    res = Net::HTTP.post(URI(LABELS_API),
      {
        name: label_name,
        color: LABEL_COLOR,
        description: "Autogenerated label for service #{service_name}"
      }.to_json,
      { "Content-Type" => "application/json", "PRIVATE-TOKEN" => ENV["GITLAB_RECONCILE_SERVICE_LABELS_TOKEN"] }
    )
    raise "Create group label API failed. Status: #{res.code} Message: #{res.message}" unless res.is_a?(Net::HTTPSuccess)

    parsed = JSON.parse(res.body)
    @logger.info "Created label #{label_name} with id #{parsed['id']}"
  end
end

ReconcileServiceCatalogLabels.new.call if $PROGRAM_NAME == __FILE__
