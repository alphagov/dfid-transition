require 'dfid-transition/patch/specialist_publisher/base'
require 'rest-client'
require 'govuk/registers/country'

module DfidTransition
  module Patch
    module SpecialistPublisher
      class Countries < Base
        def mutate_schema
          country_facet['allowed_values'] = transform_to_label_value(
            alphabetically_sorted_countries)
        end

      private

        def countries
          Govuk::Registers::Country.countries
        end

        def alphabetically_sorted_countries
          countries.sort_by { |_, details| details['name'] }
        end

        def transform_to_label_value(query_results)
          query_results.map do |country_code, country_details|
            {
              value: country_code,
              label: country_details['name']
            }
          end
        end

        def country_facet
          facet('country')
        end
      end
    end
  end
end
