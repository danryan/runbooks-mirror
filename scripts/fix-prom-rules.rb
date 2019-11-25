#!/usr/bin/env ruby

require 'yaml'

KEY_ORDER = [
  'name',
  'interval',
  'rules',
  'alert',
  'for',
  'annotations',
  'record',
  'labels',
  'expr'
].freeze

def reorder(item)
  case
  when item.is_a?(Hash)
    reorder_hash(item)
  when item.is_a?(Array)
    reorder_array(item)
  else
    item
  end
end

def reorder_hash(item)
  item_dup = item.dup
  result = Hash.new

  KEY_ORDER.each do |key|
    if item_dup.include?(key)
      value = item_dup.delete(key)
      result[key] = reorder(value)
    end
  end

  item_dup.keys.sort.each do |key|
    result[key] = reorder(item_dup[key])
  end

  result
end

def reorder_array(item)
  item.collect { |i| reorder(i) }
end

doc = YAML.load(ARGF.read)
STDOUT.print YAML.dump(reorder(doc)).gsub("---\n", '')
