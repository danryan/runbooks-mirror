#! /usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'stringio'
require_relative 'compile_jsonnet'

THANOS_URL = ENV['THANOS_URL'] || 'http://localhost:10902'
THANOS_QUERY_API = "#{THANOS_URL}/api/v1/query"

source = StringIO.new
CompileJsonnet.new(source).run(['scripts/generate-service-dependencies.jsonnet'])

$service_dependencies_from_slis = {}
$service_slis_with_emitted_by = {}
def fetch_type_dependencies(service, sli, query)
  uri = URI(THANOS_QUERY_API)
  params = {
    dedup: true,
    partial_response: true,
    query: query
  }
  uri.query = URI.encode_www_form(params)

  res = Net::HTTP.get_response(uri)

  raise "Thanos query API failed. Status: #{res.code} Message: #{res.message}" unless res.is_a?(Net::HTTPSuccess)

  parsed = JSON.parse(res.body)
  parsed['data']['result'].each do |r|
    emitting_service = r['metric']['type']
    # next if emitting_service == service

    $service_dependencies_from_slis[emitting_service] ||= {}
    if !emitting_service
      puts "Empty emitting_service for #{service} #{sli} #{query}"
    end
    $service_dependencies_from_slis[emitting_service][sli] ||= Set.new
    $service_dependencies_from_slis[emitting_service][sli] << service

    $service_slis_with_emitted_by[service] ||= {}
    $service_slis_with_emitted_by[service]['slis'] ||= {}
    $service_slis_with_emitted_by[service]['slis'][sli] ||= {}
    $service_slis_with_emitted_by[service]['slis'][sli]['emitted_by'] ||= Set.new
    $service_slis_with_emitted_by[service]['slis'][sli]['emitted_by'] << emitting_service
    $service_slis_with_emitted_by[service]['slis'][sli]['requestRate'] ||= $data[service]['slis'][sli]['requestRate']
  end
end

$data = JSON.parse(source.string)

$data.each do |service, value|
  value['slis'].each do |sli, sli_obj|
    sli_obj['requestRate'].each do |rate|
      raw_query = rate['raw']
      aggregate_by_type = "count by (type) (#{raw_query})"
      puts "Querying Service: #{service} SLI: #{sli} Query: #{aggregate_by_type}"

      fetch_type_dependencies(service, sli, aggregate_by_type)
    end
  end
end

$service_dependencies_from_slis.each do |service, slis|
  slis.each do |sli, dependencies|
    $service_dependencies_from_slis[service][sli] = dependencies.to_a
  end
end

$service_slis_with_emitted_by.each do |service, _|
  $service_slis_with_emitted_by[service]['slis'].each do |sli, obj|
    $service_slis_with_emitted_by[service]['slis'][sli]['emitted_by'] = obj['emitted_by'].to_a
  end
end

# puts '======== Service dependencies from SLIs ============'
# puts $service_dependencies_from_slis.to_json
# File.write("services/service_dependencies_from_slis.json", $service_dependencies_from_slis.to_json)
# puts '====================================='
puts '======== Service SLIs with emitted_by ============'
puts $service_slis_with_emitted_by.to_json
File.write("services/service_slis_with_emitted_by.json", JSON.pretty_generate($service_slis_with_emitted_by))
puts '====================================='
puts 'Done'
