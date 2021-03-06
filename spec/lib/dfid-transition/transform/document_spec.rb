require 'spec_helper'
require 'dfid-transition/transform/document'
require 'active_support/core_ext/string/strip'

module DfidTransition::Transform
  describe Document do
    include RDFDoubles

    subject(:doc) { Document.new(solution) }

    context 'a solution that behaves like a hash is given' do
      let(:uris) { literal('http://r4d.dfid.gov.uk/pdfs/some.pdf http://example.com/offsite.pdf') }

      AN_R4D_OUTPUT_URL = 'http://r4d.dfid.gov.uk/Output/5050/Default.aspx'.freeze

      let(:original_url)  { AN_R4D_OUTPUT_URL }
      let(:solution)      { double('RDF::Query::Solution') }
      let(:solution_hash) do
        {
          output:       uri(original_url),
          type:         uri('http://r4d.dfid.gov.uk/rdf/skos/DocumentTypes#Book%20Chapter'),
          date:         literal('2016-04-28T09:52:00'),
          title:        literal(' &amp;#8216;And Then He Switched off the Phone&amp;#8217;: Mobile Phones ... '),
          citation:     literal(' Heinlein, R.; Asimov, A. &lt;b&gt;Domestic Violence Law: The Gap Between Legislation and Practice in Cambodia and What Can Be Done About It.&lt;/b&gt; 72 pp. '),
          creators:     literal(' Heinlein, R. | Asimov, A. '),
          peerReviewed: boolean(true),
          abstract:     literal(
            '&amp;lt;p&amp;gt;This research design and methods paper can be '\
            'applied to other countries in Africa and Latin America.'\
            '&amp;lt;p&amp;gt;&amp;lt;ul&amp;gt;&amp;lt;li&amp;gt;Hello&amp;lt;/li&amp;gt;&amp;lt;/ul&amp;gt;&amp;lt;/p&amp;gt;'\
            '&amp;lt;/p&amp;gt;'),
          countryCodes: literal('AZ GB'),
          uris:         uris,
          themes:       literal(
            'http://r4d.dfid.gov.uk/rdf/skos/Themes#Infrastructure '\
            'http://r4d.dfid.gov.uk/rdf/skos/Themes#Climate%20and%20Environment'
          )
        }
      end

      before do
        allow(solution).to receive(:[]) { |key| solution_hash[key] }
      end

      it 'generates a content_id for the document' do
        uuid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
        expect(doc.content_id).to match(uuid), 'content_id wasn\'t a UUID'
      end

      it 'allows content_id to change' do
        doc.content_id = SecureRandom.uuid
      end

      describe '#original_url' do
        context 'the solution has come from the linked development endpoint' do
          it 'does not change the original URL' do
            expect(doc.original_url).to eql(AN_R4D_OUTPUT_URL)
          end
        end
        context 'the solution has come from a local endpoint' do
          let(:original_url) { 'http://linked-development.org/r4d/output/5050/' }

          it 'remaps the original URL to r4d' do
            expect(doc.original_url).to eql(AN_R4D_OUTPUT_URL)
          end
        end
      end

      it 'normalises the title by stripping, correcting ampersands and unescaping HTML' do
        expect(doc.title).to eql(
          '‘And Then He Switched off the Phone’: Mobile Phones ...')
      end

      it 'has a slug' do
        expect(doc.slug).to eql('and-then-he-switched-off-the-phone-mobile-phones')
      end

      it 'always has an empty summary' do
        expect(doc.summary).to be_empty
      end

      it 'knows the original ID for things' do
        expect(doc.original_id).to eql('5050')
      end

      it 'has a base_path that corresponds to the title' do
        expect(doc.base_path).to eql('/dfid-research-outputs/and-then-he-switched-off-the-phone-mobile-phones')
      end

      describe '#disambiguate_slug!' do
        it 'appends the original_id' do
          expect { doc.disambiguate! }.to change { doc.slug }.from(
            'and-then-he-switched-off-the-phone-mobile-phones'
          ).to \
            'and-then-he-switched-off-the-phone-mobile-phones-5050'
        end
      end

      it 'has a public_updated_at that conforms to RFC3339' do
        rfc3339 = /^([0-9]+)-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])[Tt]([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9]|60)(\.[0-9]+)?(([Zz])|([\+|\-]([01][0-9]|2[0-3]):[0-5][0-9]))$/
        expect(doc.public_updated_at).to match(rfc3339)
        expect(doc.public_updated_at).to eql('2016-04-28T09:52:00Z')
      end

      it 'has a first_published_at date that conforms to schema' do
        schema_pattern = %r(^[1-9][0-9]{3}[-/](0[1-9]|1[0-2])[-/](0[1-9]|[12][0-9]|3[0-1])$)
        expect(doc.first_published_at).to match(schema_pattern)
        expect(doc.first_published_at).to eql('2016-04-28')
      end

      describe '#peer_reviewed' do
        subject { doc.peer_reviewed }

        context 'it is peer reviewed' do
          it { is_expected.to be true }
        end

        context 'it is not peer reviewed' do
          before { solution_hash[:peerReviewed] = boolean(false) }
          it     { is_expected.to be false }
        end
      end

      it 'splits country codes' do
        expect(doc.countries).to eql(%w(AZ GB))
      end

      describe '#format_specific_metadata' do
        it 'has our countries' do
          expect(doc.format_specific_metadata[:country]).to eql(doc.countries)
        end
        it 'has our authors' do
          expect(doc.format_specific_metadata[:dfid_authors]).to eql(doc.creators)
        end
        it 'has our first_published_at date' do
          expect(doc.format_specific_metadata[:first_published_at]).to eql(doc.first_published_at)
        end
        it 'has the document review status' do
          expect(doc.format_specific_metadata[:dfid_review_status]).to eql('peer_reviewed')
        end
      end

      it 'has fixed organisations' do
        dfid_content_id = 'db994552-7644-404d-a770-a2fe659c661f'
        expect(doc.organisations).to eql([dfid_content_id])
      end

      describe '#details' do
        subject(:details) { doc.details }

        before do
          doc.attachments.each do |attachment|
            allow(attachment).to receive(:asset_response).and_return(
              double('response', file_url: 'http://asset.url'))
          end
        end

        it 'has metadata' do
          expect(details[:metadata]).to eql(doc.metadata)
        end

        it 'has a non-empty change history list' do
          expect(details[:change_history]).to be_an(Array)
          expect(details[:change_history]).not_to be_empty
        end

        it 'has onsite attachments only with URLs assigned by asset manager' do
          attachments_json = details[:attachments]
          expect(attachments_json.size).to eql(1)
          expect(attachments_json.first[:url]).to eql('http://asset.url')
        end

        describe 'the presented body' do
          subject(:presented_body) { details[:body] }

          it { is_expected.to be_an(Array) }

          it 'contains the body in the markdown section' do
            expect(presented_body.first[:content]).to eql(doc.body)
          end
        end
      end

      describe '#metadata' do
        subject(:metadata) { doc.metadata }

        it 'has the document type' do
          expect(metadata[:document_type]).to eql('dfid_research_output')
        end
        it 'has the DFID document type' do
          expect(metadata[:dfid_document_type]).to eql('book_chapter')
        end
        it 'has a list of countries' do
          expect(metadata[:country]).to eql(%w(AZ GB))
        end
        it 'has a list of theme identifiers' do
          expect(metadata[:dfid_theme]).to eql(%w(infrastructure climate_and_environment))
        end
        it 'says that this is bulk_published' do
          expect(metadata[:bulk_published]).to be true
        end
        it 'has the published date of the research output' do
          expect(metadata[:first_published_at]).to eql(doc.first_published_at)
        end
      end

      describe '#change_history' do
        subject(:change_history) { doc.change_history }

        it {
          is_expected.to eql \
            [{ public_timestamp: doc.public_updated_at, note: 'First published.' }]
        }
      end

      describe '#body' do
        subject(:body) { doc.body }

        it { is_expected.to be_a(String) }

        it 'has a header with no indents for the abstract' do
          expect(body).to match(/^## Abstract/)
        end
        it 'has a header with no indents for the links' do
          expect(body).to match(/^## Links/)
        end
        it 'has the citation' do
          expect(body).to include(doc.citation)
        end
        it 'has the abstract as markdown' do
          expect(body).to include('This research design and methods paper')
          expect(body).not_to include('<p>')
        end
        it 'corrects non-standard HTML – the list is separate' do
          expect(body).to include("\n* Hello")
        end
        it 'has the offsite link' do
          expect(body).to include('[offsite.pdf](http://example.com/offsite.pdf)')
        end
        it 'has the attachments as a list' do
          expect(body).to include(
            "* [InlineAttachment:some.pdf]\n* [offsite.pdf](http://example.com/offsite.pdf)")
        end

        context 'there is only one attachment' do
          context 'an onsite link' do
            let(:uris) { literal('http://r4d.dfid.gov.uk/filename.pdf') }

            it 'does not appear as a list and its title is that of the document' do
              expect(body).to include('[InlineAttachment:filename.pdf]')
              expect(body).not_to match(/\* \[InlineAttachment/)
            end
          end

          context 'an offsite link' do
            let(:uris) { literal('http://www.e-elgar.com/shop/handbook-of-international-development-and-education') }

            it 'does not appear as a list and its title is that of the document' do
              expect(body).to match(/\[‘And Then He Switched off the Phone’.*\]/)
              expect(body).not_to match(/\* \[‘And Then/)
            end
          end

          ##
          # 'Bumph' is defined as "the same summary and attachment hosted elsewhere, e.g.
          # dx.doi.org or gsdrc.org"
          context 'there are bumph attachments' do
            context 'for dx.doi.org' do
              let(:uris) {
                'http://dx.doi.org/10.12774/eod_hd.march2016.agarwaletal '\
              'http://r4d.dfid.gov.uk/pdfs/EoD_HDYr3_21_40_March_2016_Disability_Infrastructure.pdf'
              }

              it 'eliminates the bumph' do
                expect(body).to include('[InlineAttachment:EoD_HDYr3_21_40_March_2016_Disability_Infrastructure.pdf]')
                expect(body).not_to match(/\* \[InlineAttachment/)
              end
            end
            context 'for gsdrc.org' do
              let(:uris) {
                'http://www.gsdrc.org/docs/open/HDQ1005.pdf '\
                'http://r4d.dfid.gov.uk/pdf/outputs/GovPEAKS/hdq1005.pdf'
              }

              it 'eliminates the bumph' do
                expect(body).to include('[InlineAttachment:hdq1005.pdf]')
                expect(body).not_to match(/\* \[InlineAttachment/)
              end
            end
          end
        end

        context 'the abstract is blank' do
          context 'with a single dash' do
            before { solution_hash[:abstract] = literal('-') }
            it 'has no abstract section' do
              expect(body).not_to include('## Abstract')
            end
          end

          context 'with a single dash and leading/trailing space' do
            before { solution_hash[:abstract] = literal(' - ') }
            it 'has no abstract section' do
              expect(body).not_to include('## Abstract')
            end
          end

          context 'properly blank' do
            before { solution_hash[:abstract] = literal('') }
            it 'has no abstract section' do
              expect(body).not_to include('## Abstract')
            end
          end
        end

        context 'the abstract has Query: and Summary:' do
          before do
            solution_hash[:abstract] = literal(
              <<-TEXT
                This is a piece of abstract.

                <b>Query:</b> Something that's a query

                <strong>Summary:</strong> Something that's a summary.
              TEXT
            )
          end

          it 'expands them to h3' do
            expect(body).to match(/^### Query\n\nSomething/)
            expect(body).to match(/^### Summary\n\nSomething/m)
          end
        end

        context 'there is trouble in the abstract' do
          before do
            allow(solution_hash).to receive(:[]).with(:abstract).and_return(abstract)
          end

          context 'there are linked-development output hrefs in the abstract' do
            let(:abstract) do
              <<-BAD_HTML.strip_heredoc
                See also the document record for the meeting website
                &amp;lt;a href="http://linked-development.org/r4d/output/65132"&amp;gt;Moving
                Beyond Research to Influence Policy Workshop, University of Southampton, 23-24 January 2001.
                &amp;lt;/a&amp;gt; which provides the links to the presentations made at the meeting.
              BAD_HTML
            end

            let(:govuk_url) do
              'https://gov.uk/dfid-research-outputs/moving-beyond-research'\
              '-to-influence-policy-workshop-university-of-southampton-23-24-january-2001'
            end

            it 'replaces the LD URI with the gov.uk' do
              expect(doc.abstract).not_to include('linked-development')
              expect(doc.abstract).to include(govuk_url)
            end
          end

          context 'there are linked-development project hrefs in the abstract' do
            let(:abstract) do
              <<-BAD_HTML.strip_heredoc
                This paper reports on two action research projects conducted in Nepal, India and Kyrgyzstan
                between 2002 and 2005
                (&amp;lt;a href="http://linked-development.org/r4d/project/2980"&amp;gt;R8023: Guidelines for Good Governance&amp;lt;/a&amp;gt;,
                and &amp;lt;a href="http://linked-development.org/r4d/project/3730"&amp;gt;R8338: Equity, Irrigation and Poverty&amp;lt;/a&amp;gt;).
              BAD_HTML
            end

            it 'removes the link completely' do
              expect(doc.abstract).not_to include('linked-development')
            end

            it 'keeps the text of both' do
              expect(doc.abstract).to include('R8023: Guidelines for Good Governance')
              expect(doc.abstract).to include('R8338: Equity, Irrigation and Poverty')
            end
          end

          context 'there are bad encodings' do
            bad_abstract_solutions =
              JSON.parse(
                File.read('spec/fixtures/service-results/duff-abstracts.json')
              ).dig('results', 'bindings')

            bad_abstract_solutions.each do |binding|
              output         = binding.dig('output', 'value')
              abstract_value = binding.dig('abstract', 'value')

              context "Output #{output}" do
                let(:abstract) { abstract_value }

                it "does not throw a RangeError (or any error)" do
                  expect { doc.abstract }.not_to raise_error
                end
              end
            end
          end

          context 'there are malformed lists (without a line-break)' do
            context 'ul' do
              let :abstract do
                <<-BAD_HTML
                &amp;lt;b&amp;gt;Query:&amp;lt;/b&amp;gt; What is the evidence on:&amp;lt;br/&amp;gt; &amp;lt;ul&amp;gt;&amp;amp;#61623;&amp;lt;li&amp;gt; how best to promote effective national capacities to conduct learning assessments?&amp;lt;/li&amp;gt; &amp;amp;#61623;&amp;lt;li&amp;gt; to what extent participation in international learning assessments has built national capacities to design, implement and make use of national assessments?&amp;lt;/li&amp;gt; &amp;amp;#61623;&amp;lt;li&amp;gt; participation in international learning assessments having an impact on political decisions, policy-making and teaching practices in countries?&amp;lt;/li&amp;gt; &amp;amp;#61623;&amp;lt;li&amp;gt; the consequences of focusing assessment of learning on language (reading), numeracy/maths and science?&amp;lt;/li&amp;gt; &amp;amp;#61623;&amp;lt;li&amp;gt; the circumstances and actions required to ensure learning assessments (both national and country participation in international assessments) promote and secure improvements in learning achievement?&amp;lt;/li&amp;gt; &amp;lt;/ul&amp;gt; &amp;lt;br/&amp;gt;&amp;lt;b&amp;gt;Summary:&amp;lt;/b&amp;gt; This helpdesk report provides a rapid analysis of evidence of the role of large-scale learning assessments (LSEAs) in education systems in low- and middle-income countries. It is divided into five principal sections, each associated with one of the 5 sub-queries set out above. The information and analysis is supplemented by a number of Annexes detailing specific approaches to learning assessment design and implementation. A bibliography is included, with links for resources used. The resources included in this report were identified through a non-systematic desk-based search. A number of experts were also consulted. This report is a rapid response and, as such, it should be treated as a synthesis of the resources and evidence gathered in the assigned time.
                BAD_HTML
              end

              it 'Ensures the first items of lists occur after line breaks' do
                expect(doc.abstract).to match(/\n^\* how best to promote effective national capacities/)
              end
            end
            context 'ol' do
              let :abstract do
                <<-BAD_HTML
                The DFID Crop Protection Programme (CPP) supported a project entitled “Forecasting movements and breeding of the Red-billed Quelea bird in southern Africa and improved control strategies” The project was intended to provide four main outputs: &amp;lt;ol&amp;gt; &amp;lt;li&amp;gt;A desk-based assessment of the environmental impacts of quelea control operations.&amp;lt;/li&amp;gt; &amp;lt;li&amp;gt;A preliminary analysis of the potential for developing a statistical medium term quelea seasonal forecasting model based on sea surface temperature (SST) data and atmospheric indicators.&amp;lt;/li&amp;gt; &amp;lt;li&amp;gt;Increased knowledge of the key relationships between environmental factors and quelea migrations and breeding activities..&amp;lt;/li&amp;gt; &amp;lt;li&amp;gt;A computer-based model for forecasting the timing and geographical distribution of quelea breeding activity in southern Africa.&amp;lt;/li&amp;gt; &amp;lt;/ol&amp;gt; &amp;lt;p&amp;gt; The presentation discussed how involvement with the Information Core for Southern African Migrant Pests (ICOSAMP) project would assist in achieving these objectives, with particular reference to forecasts of breeding by the Red-billed Quelea Quelea quelea lathamii. For each objective, details of achievements to date, needs and future plans were discussed.&amp;lt;/p&amp;gt;
                BAD_HTML
              end

              it 'Ensures the first items of lists occur after line breaks' do
                expect(doc.abstract).to match(/\n^1\.  A desk-based assessment/)
              end
            end
          end
        end
      end

      describe '#creators' do
        subject(:creators) { doc.creators }

        it { is_expected.to eql(['Heinlein, R.', 'Asimov, A.']) }
      end

      describe '#citation' do
        it 'strips all formatting' do
          expect(doc.citation).to eql(
            'Heinlein, R.; Asimov, A. Domestic Violence Law: The Gap Between '\
            'Legislation and Practice in Cambodia and What Can Be Done About It. 72 pp.'
          )
        end
      end

      describe '#headers' do
        subject(:headers) { doc.headers }

        before do
          allow(doc).to receive(:body).and_return(body)
        end

        context 'there is just one header' do
          let(:body) { '## Abstract' }

          it { is_expected.to be_an(Array) }

          it 'has one item for the abstract' do
            expect(headers.first).to eql(
              text: 'Abstract', level: 2, id: 'abstract'
            )
          end
        end

        context 'there are some nested headers' do
          let(:body) do
            <<-MARKDOWN.strip_heredoc
              ## Abstract

              ### Sub-abstract

              ## Downloads
            MARKDOWN
          end

          it { is_expected.to be_an(Array) }

          it 'has 2 main headers' do
            expect(headers.size).to eql(2)
          end

          it 'nests the other headers' do
            expect(headers).to eql(
              [
                {
                  text: 'Abstract', level: 2, id: 'abstract',
                  headers: [
                    { text: 'Sub-abstract', level: 3, id: 'sub-abstract' }
                  ]
                },
                { text: 'Downloads', level: 2, id: 'downloads' }
              ]
            )
          end
        end
      end
    end
  end
end
