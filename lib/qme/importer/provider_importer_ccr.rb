require "date"
require "date/delta"

module QME
  module Importer
    class ProviderImporterCCR
      include Singleton
      
      # Extract Healthcare Providers from CCR
      #
      # @param [Nokogiri::XML::Document] doc It is expected that the root node of this document
      #        will have the "ccr" namespace registered to "urn:astm-org:CCR"
      # @return [Array] an array of providers found in the document
      def extract_providers(doc)
        # This is stubbed out for now
         providers = {}
      end
      
      private
    end
   end
end