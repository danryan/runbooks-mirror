require 'fileutils'
require_relative 'periodic_queries/prometheus_api'
require_relative 'periodic_queries/topic'
require_relative 'periodic_queries/storage'

module PeriodicQueries
  def self.perform_queries(sets, api, out = STDOUT)
    sets.each do |set|
      out.puts "Fetching results for #{set.name}"
      set.queries.each do |query|
        out.puts "-- ⬇ Performing query for #{query.name}"
        response = api.perform_query(query)
        query.response = response
      end
    end
  end

  def self.write_results(sets, target_directory, time, out = STDOUT)
    timestamp = time.utc.strftime("%Y%m%d%H%M%S")
    directory = File.join(target_directory, timestamp)

    out.puts "Storing results for #{sets.size} topics in #{directory}"

    FileUtils.mkdir_p(directory)

    sets.each do |set|
      filename = File.join(directory, "#{set.name}.json")
      out.puts "-- 💾 #{set.name}: #{filename}"
      File.write(filename, set.to_result.to_json)
    end
  end

  def self.upload_results(directory, storage, out = STDOUT)
    directory = File.expand_path(directory)
    out.puts "Uploading results in #{directory}"
    Dir.glob(File.join(directory, '*/*.json')).each do |f|
      upload = storage.create_file(f)
      out.puts "-- ⬆ Uploading #{f}: #{upload.public_url}"
    end
  end
end
