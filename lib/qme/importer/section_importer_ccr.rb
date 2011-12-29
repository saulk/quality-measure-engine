module QME
  module Importer
    # Class that can be used to create an importer for a section of a ASTM CCR document. It usually
    # operates by selecting all CCR entries in a section and then creates entries for them.
    class SectionImporterCCR
      attr_accessor :check_for_usable
      # Creates a new SectionImporter
      # @param [String] entry_xpath An XPath expression that can be used to find the desired entries
      # @param [String] status_xpath XPath expression to find the status element as a child of the desired CDA
      #        entry. Defaults to nil. If not provided, a status will not be checked for since it is not applicable
      #        to all enrty types
      def initialize(entry_xpath,  product_xpath)
        @entry_xpath = entry_xpath
        @product_xpath = product_xpath
        @check_for_usable = true               # Pilot tools will set this to false
      end

      # normalize_coding_system attempts to simplify analysis of the XML doc by 
      # normalizing the names of the coding systems. Input is a single "Code" node
      # in the tree, and the side effect is to edit the CodingSystem subnode.
      def normalize_coding_system(code)
        lookup = {
          "lnc"       => "LOINC",
          "loinc"     => "LOINC",
          "cpt"       => "CPT",
          "cpt-4"     => "CPT",
          "snomedct"  => "SNOMED-CT",
          "snomed-ct" => "SNOMED-CT",
          "rxnorm"    => "RxNorm",
          "icd9-cm"   => "ICD-9-CM",
          "icd9"      => "ICD-9-CM",
          "icd10-cm"   => "ICD-9-CM",
          "icd10"      => "ICD-9-CM",
          "cvx"        => "CVX",
          "hcpcs"      => "HCPCS"

        }
        codingsystem = lookup[code.xpath('./ccr:CodingSystem')[0].content.downcase]
        if(codingsystem)
          code.xpath('./ccr:CodingSystem')[0].content = codingsystem
        end
      end
=begin
            # Add the codes from a <Code> block to an Entry
            def process_codes(node, entry)
              codes = node.xpath("./ccr:Description/ccr:Code")
              desctext = node.at_xpath("./ccr:Description/ccr:Text").content
              entry.description = desctext
              if codes.size > 0 
                found_code = true
                codes.each do |code|
                  normalize_coding_system(code)
                  codetext = code.at_xpath("./ccr:CodingSystem").content
                  entry.add_code(code.at_xpath("./ccr:Value").content, codetext)
                end
              end
            end

            # Add the codes from a <Product> block subsection to an Entry
            def process_product_codes(node, entry)
              codes = node.xpath("./ccr:Code")
              if codes.size > 0
                found_code = true
                codes.each do |code|
                  normalize_coding_system(code)
                  codetext = code.at_xpath("./ccr:CodingSystem").content
                  entry.add_code(code.at_xpath("./ccr:Value").content, codetext)
                end
              end
            end



            # Special handling for the medications section
            def process_medications (section_name, doc)
              #STDERR.puts "process_section #{section_name} starting at #{@sections[section_name]}"
              meds = doc.xpath(@sections[section_name])
              if(meds.size == 0)
                return
              end
              @ccr_hash[section_name] = []
              meds.each do | med | 
                entry = QME::Importer::Entry.new
                products = med.xpath("./ccr:Product")
                products.each do | product |
                  productName = product.xpath("./ccr:ProductName")
                  brandName = product.xpath("./ccr:BrandName")
                  productNameText = productName.at_xpath("./ccr:Text")
                  brandNameText = brandName.at_xpath("./ccr:Text") 
                  entry.description = productNameText.content
                  process_product_codes(productName, entry) # we throw any codes found within the productName and brandName into the same entry
                  process_product_codes(brandName, entry)
                end
                @ccr_hash[section_name] << entry
              end
            end
          end 
=end

      # Traverses that HITSP C32 document passed in using XPath and creates an Array of Entry
      # objects based on what it finds                          
      # @param [Nokogiri::XML::Document] doc It is expected that the root node of this document
      #        will have the "ccr" namespace registered to "urn:astm-org:CCR"
      #        measure definition
      # @return [Array] will be a list of Entry objects
      def create_entries(doc)
        entry_list = []
        entry_elements = doc.xpath(@entry_xpath)
        entry_elements.each do |entry_element|
          entry = Entry.new
          extract_codes(entry_element, entry)
          extract_dates(entry_element, entry)
          extract_value(entry_element, entry)
          extract_status(entry_element, entry)
        end
        if @check_for_usable
          entry_list << entry if entry.usable?
        else
          entry_list << entry
        end
        entry_list
      end

      private

      def extract_status(parent_element, entry)
        status_element = parent_element.at_xpath('ccr:Status')
        if status_element
          entry.status = parent_element.at_xpath('ccr:Status').downcase
        end
      end


      # Add the codes from a <Code> block to an Entry
      def extract_codes(parent_element, entry)
        codes = parent_element.xpath("./ccr:Description/ccr:Code")
        desctext = parent_element.at_xpath("./ccr:Description/ccr:Text").content
        entry.description = desctext
        if codes.size > 0 
          found_code = true
          codes.each do |code|
            normalize_coding_system(code)
            entry.add_code(code.at_xpath("./ccr:Value").content, code.at_xpath("./ccr:CodingSystem").content)
          end
        end
      end

      def extract_dates(parent_element, entry)
        if parent_element.at_xpath('ccr:ExactDateTime')
          entry.time = Time.iso8601(parent_element.at_xpath('ccr:ExactDateTime').content)
        end
        if parent_element.at_xpath('ccr:ApproximateDateTime')
          entry.time = Time.iso8601(parent_element.at_xpath('ccr:ApproximateDateTime').content)
        end
        if parent_element.at_xpath('ccr:DateTimeRange/ccr:BeginRange')
          entry.start_time = Time.iso8601(parent_element.at_xpath('ccr:DateTimeRange/ccr:BeginRange').content)
        end
        if parent_element.at_xpath('ccr:DateTimeRange/ccr:EndRange')
          entry.end_time = Time.iso8601(parent_element.at_xpath('ccr:DateTimeRange/ccr:EndRange').content)
        end
      end

      def extract_value(parent_element, entry)
        value_element = parent_element.at_xpath('ccr:TestResult')
        if value_element
          value = parent_element.at_xpath('ccr:TestResult/ccr:Value').content
          unit = parent_element.at_xpath('ccr:TestResult/ccr:Units').content
          if value
            entry.set_value(value, unit)
          end
        end
      end
    end
  end
end


