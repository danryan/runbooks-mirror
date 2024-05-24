# frozen_string_literal: true

require 'spec_helper'

require_relative '../scripts/uploads_cleanup'

describe ::Uploads::Cleaner do
  subject { described_class.new(options) }

  let(:host) { options[:hostname] }
  let(:disk_path) { 'test/path' }
  let(:file) { 'test' }
  let(:operation) { :delete }
  let(:args) { { disk_path:, operation: } }
  let(:defaults) { ::Uploads::CleanupScript::Config::DEFAULTS.dup.merge(args) }
  let(:options) { defaults }

  describe '#safely_invoke_find_with_operation' do
    let(:path) { File.join(options[:uploads_dir_path], disk_path) }
    let(:found) { File.join(path, 'tmp/test') }
    let(:find_command) do
      command = format(options[:find], path:, minutes: options[:interval_minutes])
      format(
        options[:remote_command],
        hostname: options[:hostname],
        command:
      )
    end

    let(:find_with_delete_command) do
      command = format(options[:find], path:, minutes: options[:interval_minutes])
      command <<= " -#{operation}"
      format(
        options[:remote_command],
        hostname: options[:hostname],
        command:
      )
    end

    context 'when the dry-run option is true' do
      it 'logs a dry-run informational message' do
        allow(subject).to receive(:get_non_empty_with_only_tmp_dir_files).with(host, path).and_return([found])
        expect(subject).to receive(:options).at_least(:once).and_return(options)
        expect(subject.log).to receive(:info)
          .with("[Dry-run] Would have invoked command: #{find_with_delete_command}")
        expect(subject.clean).to be_nil
      end
    end

    context 'when the dry-run option is false' do
      let(:options) { defaults.merge(dry_run: false) }

      it 'logs the operation and executes it' do
        allow(subject).to receive(:get_non_empty_with_only_tmp_dir_files).with(host, path).and_return([found])
        expect(subject).to receive(:options).at_least(:once).and_return(options)
        expect(subject.log).to receive(:info)
          .with("Invoking command: #{find_with_delete_command}")
        expect(subject).to receive(:invoke).with(find_with_delete_command).and_return('')
        expect(subject.clean).to be_nil
      end
    end
  end
end

describe ::Uploads::CleanupScript do
  subject { Object.new.extend(described_class) }

  let(:args) { { operation: :delete } }
  let(:defaults) { ::Uploads::CleanupScript::Config::DEFAULTS.dup.merge(args) }
  let(:options) { defaults }
  let(:cleanup) { instance_double('::Uploads::Cleaner') }

  before do
    allow(subject).to receive(:parse).and_return(options)
  end

  describe '#main' do
    context 'when the dry-run option is true' do
      it 'logs the given operation' do
        expect(::Uploads::Cleaner).to receive(:new).and_return(cleanup)
        expect(cleanup).to receive(:clean)
        expect(subject.log).to receive(:info).with("[Dry-run] This is only a dry-run -- write " \
          "operations will be logged but not executed")
        expect(subject.main).to be_nil
      end
    end

    context 'when the dry-run option is false' do
      let(:options) { defaults.merge(dry_run: false) }

      it 'safely invokes the given operation' do
        expect(::Uploads::Cleaner).to receive(:new).and_return(cleanup)
        expect(cleanup).to receive(:clean)
        expect(subject.main).to be_nil
      end
    end
  end
end
