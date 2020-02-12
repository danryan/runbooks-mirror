# rubocop:disable Style/TrailingCommaInHashLiteral
# rubocop:disable Style/TrailingCommaInArguments
# rubocop:disable Style/TrailingCommaInArrayLiteral
# rubocop:disable Style/NumericPredicate
# rubocop:disable Style/ZeroLengthPredicate
# rubocop:disable Style/BlockDelimiters
# rubocop:disable Style/MultilineBlockChain
# rubocop:disable Layout/SpaceAroundOperators
# rubocop:disable Layout/EmptyLineAfterGuardClause
# rubocop:disable Layout/IndentFirstHashElement
# rubocop:disable Layout/AlignHash
# rubocop:disable Layout/SpaceAfterColon
# rubocop:disable Layout/SpaceInsideHashLiteralBraces
# rubocop:disable Layout/SpaceAfterComma
# rubocop:disable Layout/SpaceInsideBlockBraces
# rubocop:disable Layout/SpaceInsideArrayLiteralBrackets

require 'http'
require 'uri'
require 'json'
require 'HDRHistogram'

clusters = {
  es5: ENV['ELASTICSEARCH_URL_ES5'],
  es7: ENV['ELASTICSEARCH_URL_ES7'],
}

correlation_queries = {
  # 'pubsub-workhorse-inf-gprd*' => '{"version":true,"query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}},"size":500,"sort":[{"@timestamp":{"order":"desc","unmapped_type":"boolean"}}],"_source":{"excludes":[]},"stored_fields":["*"],"script_fields":{},"docvalue_fields":["@timestamp","json.time","publish_time"],"highlight":{"pre_tags":["@kibana-highlighted-field@"],"post_tags":["@/kibana-highlighted-field@"],"fields":{"*":{"highlight_query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}}}},"fragment_size":2147483647}}',
  'pubsub-rails-inf-gprd-*' => '{"version":true,"query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}},"size":500,"sort":[{"@timestamp":{"order":"desc","unmapped_type":"boolean"}}],"_source":{"excludes":[]},"stored_fields":["*"],"script_fields":{},"docvalue_fields":["@timestamp","json.expiry_from","json.expiry_to","json.extra.commits.timestamp","json.extra.context.project.created_at","json.extra.context.project.last_activity_at","json.extra.context.project.last_repository_updated_at","json.extra.context.project.updated_at","json.extra.created_after","json.extra.created_at","json.extra.created_before","json.extra.head_commit.timestamp","json.extra.raw_response.created_on","json.extra.raw_response.updated_on","json.extra.repository.updated_at","json.extra.request_forgery_protection.commits.timestamp","json.extra.request_forgery_protection.head_commit.timestamp","json.extra.request_forgery_protection.repository.updated_at","json.extra.since","json.extra.updated_after","json.time","publish_time"],"highlight":{"pre_tags":["@kibana-highlighted-field@"],"post_tags":["@/kibana-highlighted-field@"],"fields":{"*":{"highlight_query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}}}},"fragment_size":2147483647}}',
  # 'pubsub-sidekiq-inf-gprd*' => '{"version":true,"query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}},"size":500,"sort":[{"@timestamp":{"order":"desc","unmapped_type":"boolean"}}],"_source":{"excludes":[]},"stored_fields":["*"],"script_fields":{},"docvalue_fields":["@timestamp","json.completed_at","json.created_at","json.enqueued_at","json.failed_at","json.retried_at","json.time","publish_time"],"highlight":{"pre_tags":["@kibana-highlighted-field@"],"post_tags":["@/kibana-highlighted-field@"],"fields":{"*":{"highlight_query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}}}},"fragment_size":2147483647}}',
  # 'pubsub-gitaly-inf-gprd-*' => '{"version":true,"query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}},"size":500,"sort":[{"@timestamp":{"order":"desc","unmapped_type":"boolean"}}],"_source":{"excludes":[]},"stored_fields":["*"],"script_fields":{},"docvalue_fields":["@timestamp","json.grpc.request.deadline","json.grpc.start_time","json.time","publish_time"],"highlight":{"pre_tags":["@kibana-highlighted-field@"],"post_tags":["@/kibana-highlighted-field@"],"fields":{"*":{"highlight_query":{"bool":{"must":[{"match_all":{}},{"match_phrase":{"json.correlation_id":{"query":"PUT_CORRELATION_ID_HERE"}}},{"match_all":{}},{"range":{"json.time":{"gte":TIMESTAMP_FROM,"lte":TIMESTAMP_UNTIL,"format":"epoch_millis"}}}],"must_not":[]}}}},"fragment_size":2147483647}}',
}

profile = true
window_days = 3
num_correlation_ids = 1

now = Time.now

timestamp_until = now.to_time.to_i*1000
timestamp_from = (now - (window_days*86400)).to_time.to_i*1000
timestamp_yesterday = (now - (1*86400)).to_time.to_i*1000

stats = {}

def self.new_histogram
  HDRHistogram.new(0.001, 1000*300, 3, multiplier: 0.001, unit: :ms)
end

def self.measure
  start = Time.now
  yield
  (Time.now - start)*1000
end

# get correlation_id ahead of time
# we want to use the same one against both clusters

url = clusters[:es5]
uri = URI.parse(url)
client = HTTP
  .persistent(url)
  .basic_auth(
    user: URI.decode_www_form_component(uri.user),
    pass: URI.decode_www_form_component(uri.password),
  )

resp = client.get('/')
raise "expected status 200, got #{resp.status.code}, response #{resp}" unless resp.status.success?
body = JSON.parse(resp.body)

req = JSON.generate({
  "_source": ["json.correlation_id"],
  "query": {
    "bool":{"must":[
      {"exists": {"field": "json.correlation_id"}},
      {"range":{"json.time":{"gte":timestamp_yesterday,"lte":timestamp_until,"format":"epoch_millis"}}},
    ]}
  },
  "size": num_correlation_ids,
})
resp = client.post(
  '/pubsub-rails-inf-gprd-*/_search',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: req,
)
raise "expected status 200, got #{resp.status.code}, response #{resp}" unless resp.status.success?
body = JSON.parse(resp.body)

raise "expected a hit on correlation_id, found none" unless body['hits']['hits'].size > 0
correlation_ids = body['hits']['hits'].map {|hit| hit['_source']['json']['correlation_id']}

puts "correlation_id"
puts correlation_ids
puts

# start benchmark

clusters.each do |cluster, url|
  stats[cluster] = {}

  puts cluster
  puts

  uri = URI.parse(url)
  client = HTTP
    .persistent(url)
    .basic_auth(
      user: URI.decode_www_form_component(uri.user),
      pass: URI.decode_www_form_component(uri.password),
    )

  resp = client.get('/')
  raise "expected status 200, got #{resp.status.code}, response #{resp}" unless resp.status.success?
  body = JSON.parse(resp.body)

  correlation_queries.each do |index, query_json|
    stats[cluster]["correlation_server_#{index}"] = new_histogram

    puts "index: #{index}"

    correlation_ids.each do |correlation_id|
      puts "correlation_id: #{correlation_id}"

      query_json = query_json
        .gsub('PUT_CORRELATION_ID_HERE', correlation_id)
        .gsub('TIMESTAMP_FROM', timestamp_from.to_s)
        .gsub('TIMESTAMP_UNTIL', timestamp_until.to_s)

      if profile
        query = JSON.parse(query_json)
        query['profile'] = true
        query_json = JSON.generate(query)
      end

      resp = client.post(
        "/#{index}/_search",
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: query_json,
      )
      raise "expected status 200, got #{resp.status.code}, response #{resp}" unless resp.status.success?
      body = JSON.parse(resp.body)

      stats[cluster]["correlation_server_#{index}"].record(body['took'])

      if profile
        # [nodeID][indexName][shardID]
        profile_shards = body['profile']['shards'].map { |s| s['id'].scan(/\[(.+?)\]/).flatten }
        unique_nodes = profile_shards.map { |s| s[0] }.uniq.size
        unique_indices = profile_shards.map { |s| [s[0], s[1]] }.uniq.size
        unique_shards = profile_shards.map { |s| [s[0], s[1], s[2]] }.uniq.size
        puts "unique nodes / indices / shards: #{unique_nodes} #{unique_indices} #{unique_shards}"
        puts

        time_per_node = body['profile']['shards']
          .group_by { |s| s['id'].scan(/\[(.+?)\]/).flatten[0] }
          .map { |node, shards|
            sum = shards.map { |s|
              s['searches'].map { |search|
                search['query'].map { |q| q['time_in_nanos'].to_i / 1_000_000 }
              }
            }.flatten.sum
            [node, sum]
          }
          .sort_by { |k, v| -v }
          .to_h

        # cumulative -- these are supposedly concurrent
        puts "cumulative profiled time: #{time_per_node.map { |_, n| n }.sum}"
        puts

        puts "cumulative time per node: #{time_per_node.inspect}"
        puts

        shards_per_node = body['profile']['shards']
          .group_by { |s| s['id'].scan(/\[(.+?)\]/).flatten[0] }
          .map { |node, shards| [node, shards.size] }
          .sort_by { |k, v| -v }
          .to_h

        puts "shards per node: #{shards_per_node.inspect}"
        puts
      end

      body.delete('hits')
      body.delete('profile')
      puts body
      puts
    end
  end

  puts
end

puts stats.map { |c,v| [c,v.map { |k,h| [k,h.stats([ 50.0, 75.0, 90.0, 99.0, 100.0 ])] }] }

# rubocop:enable Style/TrailingCommaInHashLiteral
# rubocop:enable Style/TrailingCommaInArguments
# rubocop:enable Style/TrailingCommaInArrayLiteral
# rubocop:enable Style/NumericPredicate
# rubocop:enable Style/ZeroLengthPredicate
# rubocop:enable Style/BlockDelimiters
# rubocop:enable Style/MultilineBlockChain
# rubocop:enable Layout/SpaceAroundOperators
# rubocop:enable Layout/EmptyLineAfterGuardClause
# rubocop:enable Layout/IndentFirstHashElement
# rubocop:enable Layout/AlignHash
# rubocop:enable Layout/SpaceAfterColon
# rubocop:enable Layout/SpaceInsideHashLiteralBraces
# rubocop:enable Layout/SpaceAfterComma
# rubocop:enable Layout/SpaceInsideBlockBraces
# rubocop:enable Layout/SpaceInsideArrayLiteralBrackets
