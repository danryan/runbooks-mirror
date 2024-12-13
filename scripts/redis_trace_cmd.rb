# frozen_string_literal: true

require 'time'
require 'json'
require_relative '../lib/redis_trace/key_pattern'

raise 'no input file provided' if ARGV.empty?

# The key mapping file can be generated with redis-cli (>= 7.0)
# redis-cli --json command | jq 'sort_by(.[0])|map({ key: .[0], value: [.[3], .[4]]})|from_entries'
# see: https://redis.io/commands/command/
command_key_mappings = JSON.parse(File.read("#{__dir__}/../lib/redis_trace/command_key_mappings.json"))

ARGV.each do |idx_filename|
  filename = idx_filename.gsub(/\.findx$/, "")

  # warn filename

  index_keys = []
  index_vals = []

  File.readlines(idx_filename).each do |line|
    offset, timestamp, _length = line.strip.split("|")

    index_keys << offset.to_i
    index_vals << timestamp.to_f
  end

  next if index_keys == [] || index_vals == []

  File.open(filename, 'r:ASCII-8BIT') do |f|
    until f.eof?
      begin
        offset = f.tell
        line = f.readline.strip

        next unless line.match(/^\*([0-9]+)$/)

        args = []

        argc = Regexp.last_match(1).to_i
        argc.times do
          line = f.readline.strip
          raise line unless line.match(/^\$([0-9]+)$/)

          # TODO: parse data types
          # https://redis.io/docs/latest/develop/reference/protocol-spec/

          len = Regexp.last_match(1).to_i
          args << f.read(len)
          f.read(2) # \r\n
        end

        i = index_keys.bsearch_index { |v| v >= offset }
        if i.nil?
          i = index_keys.size - 1
        elsif i.positive? && index_keys[i] != offset
          # bsearch rounds up, we want to round down
          i -= 1
        end

        cmd = args[0].downcase
        ts = Time.at(index_vals[i]).to_datetime.new_offset(0)
        bytes = args.reject(&:nil?).map(&:size).reduce(&:+)

        raise unless File.basename(filename).match(/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)$/)

        src_host = Regexp.last_match(1).split('.').map(&:to_i).join('.')
        # src_port = Regexp.last_match(2).to_i
        # dst_host = Regexp.last_match(3).split('.').map(&:to_i).join('.')
        # dst_port = Regexp.last_match(4).to_i

        raise "unknown command #{cmd}" if command_key_mappings[cmd].nil?

        first_key, last_key = command_key_mappings[cmd]
        keys = first_key.zero? && last_key.zero? ? [] : args[first_key..last_key]
        keys = args[1..1] if cmd == "publish"
        keys = args if cmd == "subscribe" || cmd == "unsubscribe"
        keys = keys.map { |key| key.force_encoding("ISO-8859-1").encode("UTF-8") }

        if ENV['OUTPUT_FORMAT'] == 'json'
          patterns = keys.map { |key| RedisTrace::KeyPattern.filter_key(key).gsub(' ', '_') }
          data = {
            time: ts.iso8601(9),
            cmd:,
            src_host:,
            keys:,
            patterns:,
            bytes:,
            patterns_uniq: patterns.sort.uniq
          }
          # rubocop:disable GitlabSecurity/JsonSerialization
          puts data.to_json
          # rubocop:enable GitlabSecurity/JsonSerialization
        else
          keys.each do |key|
            puts "#{ts.iso8601(9)} #{ts.to_time.to_i % 60} #{cmd} #{src_host} #{RedisTrace::KeyPattern.filter_key(key).gsub(' ', '_').inspect} #{key.gsub(' ', '_').inspect}"
          end
        end
      rescue EOFError
      end
    end
  end
end
