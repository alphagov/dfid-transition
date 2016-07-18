require 'uri'
require 'concurrent/future'
require 'securerandom'
require 'rest-client'
require 'mime-types'
require 'ostruct'

module DfidTransition
  module Transform
    class Attachment
      attr_reader :original_url

      def initialize(original_url)
        @original_url = URI(original_url)
        raise ArgumentError, "expected a URL, got #{original_url}" unless @original_url.is_a?(URI::HTTP)
      end

      def content_id
        @content_id ||= SecureRandom.uuid
      end

      def file_future
        @file_future ||= case
                         when external_link?
                           raise RuntimeError, 'external links cannot be downloaded'
                         when hosted_at_r4d?
                           Concurrent::Future.new do
                             download_to = "/tmp/#{filename}"
                             File.open(download_to, 'w+') do |file|
                               RestClient.get original_url.to_s do |str|
                                 file.write(str)
                               end
                             end
                             File.open(download_to, 'r')
                           end
                         end.tap(&:execute)
      end

      def file
        file_future.value
      end

      def external_link?
        !hosted_at_r4d?
      end

      def hosted_at_r4d?
        original_url.host == 'r4d.dfid.gov.uk'
      end

      def filename
        File.basename(original_url.path).sub('/', '')
      end

      def snippet
        case
        when hosted_at_r4d? then "[InlineAttachment:#{filename}]"
        when external_link? then "[#{filename}](#{original_url})"
        end
      end

      def link_to_asset
        "[#{filename}](#{asset_response.file_url})"
      end

      def save_to(asset_manager)
        @asset_response = asset_manager.create_asset(file: file)
      end

      def details_from_index(details)
        @asset_response = OpenStruct.new(details)
      end

      def to_json
        raise RuntimeError, '#to_json is not valid for an external link' if external_link?

        {
          url:          asset_response.file_url,
          title:        filename,
          content_type: content_type,
          updated_at:   Time.now.to_datetime.rfc3339,
          created_at:   Time.now.to_datetime.rfc3339,
          content_id:   content_id
        }
      end

    private

      def content_type
        mime = MIME::Types.type_for(filename).first
        mime.content_type if mime
      end

      def asset_response
        @asset_response ||
          (raise RuntimeError.new('#save_to(asset_manager) has not been called yet'))
      end
    end
  end
end
