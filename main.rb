#!/usr/bin/env ruby

require 'fileutils'
require 'slop'
require 'exifr/jpeg'

module PhotoOrganizer
  class CLI
    EXTENSIONS = %w[jpg]

    def run
      execution = []
      files.each do |path|
        media = Media.new(path)
        stack_changes_for(media)
        puts media.inspect if media.has_changes? || cli[:verbose]
        media.apply_changes unless cli[:preview]
      end
    end

    private

    def files
      @files ||= Dir.glob(File.join(cli.arguments.last, "*.{#{cli[:extensions]}}"), File::FNM_CASEFOLD)
    end

    def stack_changes_for(media)
      if cli['exif-to-file-timestamp']
        media.track_change(:created_at, media.exif_shot_at)
        media.track_change(:modified_at, media.exif_shot_at)
      end
    end

    def cli
      @cli ||= Slop.parse do |o|
        o.banner = <<~USAGE
          Photo Organizer
        USAGE

        o.separator "Options:"
        o.string '--extensions', 'Accepted file extensions', default: EXTENSIONS.join(',')
        o.bool '--exif-to-file-timestamp', 'Copy EXIF shot timestamp to file created/modified timestamp'
        o.bool '--exif-to-file-prefix', 'Copy EXIF shot timestamp to file name as a prefix. E.g. YYYY-MM-DD_HH-MM-SS_<current name>'
        o.bool '-p', '--preview', 'Simulate the execution', default: false
        o.bool '-v', '--verbose', 'Display unmodified as well', default: false
        o.on '--help', 'Shows help' do
          puts o
          exit
        end
      end
    end
  end

  class Media < Struct.new(:path)
    attr_accessor :changes

    def initialize(*args)
      super
      @changes = {}
    end

    def track_change(attribute, new)
      current = public_send(attribute)
      same = current == new
      changes[attribute] = [current, same ? nil : new]
    end

    def apply_changes
      change_created_at
      change_modified_at
    end

    def has_changes?
      changes.values.any? { |(_current, new)| !new.nil? }
    end

    def name
      File.basename(path)
    end

    def created_at
      file.birthtime
    end

    def modified_at
      file.mtime
    end

    def exif_shot_at
      exif.date_time
    end

    def inspect
      changes_string = changes.map { |attribute, (old, new)|
        "#{attribute}: #{old} → #{new || 'unmodified'}"
      }.join(' | ')
      "#{name} | #{changes_string}"
    end

    private

    def change_created_at
      return unless (new = changes[:created_at].last)
      formatted_timestamp = new.strftime('%m/%d/%Y %H:%M:%S')
      `SetFile -d '#{formatted_timestamp}' #{path}` # TODO: This is MacOS only
    end

    def change_modified_at
      return unless (new = changes[:modified_at].last)
      FileUtils.touch path, mtime: new
    end

    def file
      @file ||= File.new(path)
    end

    def exif
      @exif ||= EXIFR::JPEG.new(path)
    end
  end
end

PhotoOrganizer::CLI.new.run
