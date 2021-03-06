require 'spec_helper'
require 'json'
require 'dfid-transition/patch/specialist_publisher/countries'

describe DfidTransition::Patch::SpecialistPublisher::Countries do
  let(:patch_location) { nil }
  subject(:patcher) { described_class.new(patch_location) }

  it_behaves_like "holds onto the location of a schema file and warns us if it is not there"

  describe '#location' do
    context 'a location is not supplied' do
      let(:patch_location) { nil }

      it 'defaults to lib/documents/schemas/dfid_research_outputs.json relative to the current directory' do
        expect(patcher.location).to eq(
          File.expand_path(
            File.join(
              Dir.pwd, '..', 'specialist-publisher-rebuild/lib/documents/schemas/dfid_research_outputs.json')))
      end
    end
  end

  describe '#run' do
    let(:patch_location) { 'spec/fixtures/schemas/dfid_research_outputs.json' }

    context 'the target schema file exists' do
      let(:schema_src) { 'spec/fixtures/schemas/specialist_publisher/dfid_research_outputs_src.json' }
      let(:query_results_p1)  { 'spec/fixtures/service-results/country-register-p1.json' }
      let(:query_results_p2)  { 'spec/fixtures/service-results/country-register-p2.json' }
      let(:parsed_json)    { JSON.parse(File.read(patch_location)) }
      let(:country_facet)  { parsed_json['facets'].find { |f| f['key'] == 'country' } }

      before do
        FileUtils.cp(schema_src, patch_location)
      end

      after do
        File.delete(patch_location)
      end

      context 'we have a full set of countries from the countries register' do
        let(:all_countries) do
          JSON.parse(File.read('spec/fixtures/service-results/country-records.json'))
        end

        before do
          allow(Govuk::Registers::Country).to receive(:countries).
            and_return(all_countries)
        end

        it 'patches the schema with all extant countries' do
          patcher.run

          expect(country_facet['allowed_values'].length).to eql(196)
          expect(country_facet['allowed_values']).to include(
            'label' => 'Venezuela',
            'value' => 'VE'
          )
        end

        it 'sorts countries alphabetically by label' do
          patcher.run

          labels = country_facet['allowed_values'].map { |lv| lv['label'] }
          expect(labels).to eql(labels.sort), 'country labels are not sorted'
        end

        context 'the target schema file does not have a countries facet to patch' do
          let(:schema_src) { 'spec/fixtures/schemas/specialist_publisher/dfid_research_outputs_no_facets.json' }

          it 'fails with an informative KeyError' do
            expect { patcher.run }.to raise_error(KeyError, /No country facet found/)
          end
        end
      end
    end
  end
end
