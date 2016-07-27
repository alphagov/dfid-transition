require 'cgi'
require 'kramdown'
require 'nokogiri'

module DfidTransition
  module Transform
    module Html
      def self.unescape_three_times(string_input)
        CGI.unescape_html(
          CGI.unescape_html(
            CGI.unescape_html(string_input)
          )
        )
      end

      def self.to_markdown(html)
        corrected_html = expand_h3s(html)

        kramdown_tree, _warnings = Kramdown::Parser::Html.parse(corrected_html)
        Kramdown::Converter::Kramdown.convert(kramdown_tree).first
      end

      KNOWN_HEADERS = ['Query', 'Summary', 'Key Findings', 'Overview'].map { |h| Regexp.new(h) }

      def self.expand_h3s(frag)
        frag = Nokogiri::HTML.fragment(frag) unless frag.is_a?(Nokogiri::HTML::DocumentFragment)

        header_nodes = frag.css('b,strong').select do |f|
          KNOWN_HEADERS.any? { |known_header| f.text =~ known_header }
        end

        header_nodes.each do |node|
          node.name = 'h3'
          node.content = node.content.sub(':', '')
          node.add_previous_sibling('<br/><br/>')
          node.next_sibling.content = node.next_sibling.content.sub(/^\s*/, '')
        end
        frag.to_s
      end
    end
  end
end
